/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtPositioning
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: root

    Component.onCompleted: {
        if (!cfg_locationName || cfg_locationName.trim().length === 0)
            cfg_autoDetectLocation = true;
        _rebuildSavedLocModel();
    }

    // Called when user clicks KCM Apply button.
    // Writes activeLocation so main.qml's onActiveLocationChanged can update
    // display fields (_activeLocName, etc.).  WeatherService reads individual
    // Plasmoid.configuration.* entries (synced by KCM via cfg_*), NOT this JSON.
    function save() {
        if (!root.cfg_autoDetectLocation) {
            Plasmoid.configuration.activeLocation = JSON.stringify({
                name:        root.cfg_locationName  || "",
                lat:         root.cfg_latitude       || 0,
                lon:         root.cfg_longitude      || 0,
                altitude:    root.cfg_altitude       || 0,
                timezone:    root.cfg_timezone       || "",
                countryCode: root.cfg_countryCode    || ""
            });
        }
        Qt.callLater(function() {
            root._commitPending();
        });
    }

    property bool cfg_autoDetectLocation: true
    property string cfg_locationName: ""
    property real cfg_latitude: 0.0
    property real cfg_longitude: 0.0
    property int cfg_altitude: 0
    property string cfg_timezone: ""
    property string cfg_countryCode: ""
    property string cfg_altitudeUnit: "m"
    property string cfg_weatherProvider: "adaptive"
    property string cfg_savedLocations: "[]"

    property string duplicateWarning: ""
    property bool autoDetectBusy: false
    property string autoDetectStatus: ""

    property string detectedLocationName: ""
    property real detectedLatitude: 0.0
    property real detectedLongitude: 0.0
    property int detectedAltitude: 0
    property string detectedTimezone: ""
    property string detectedCountryCode: ""
    property bool showDetectedLocationDialog: false
    // Set to true once the user clicks "Apply" in the confirm dialog.
    // Allows late-arriving metadata (timezone, elevation) from Open-Meteo
    // to be written directly to Plasmoid.configuration.
    property bool _detectedLocationApplied: false

    // Silently add an entry to saved locations if it isn't already there.
    function _autoSaveIfNew(entry) {
        if (!entry)
            return;
        var locs;
        try {
            locs = JSON.parse(root.cfg_savedLocations || "[]");
            if (!Array.isArray(locs))
                locs = [];
        } catch (e) {
            locs = [];
        }
        for (var i = 0; i < locs.length; i++) {
            if (Math.abs(locs[i].lat - entry.lat) < 0.01 && Math.abs(locs[i].lon - entry.lon) < 0.01)
                return; // already saved
        }
        // First location ever added — make it the default automatically
        if (locs.length === 0)
            entry.starred = true;
        locs.push(entry);
        root.cfg_savedLocations = JSON.stringify(locs);
        Plasmoid.configuration.savedLocations = root.cfg_savedLocations;
    }

    // Returns true if any saved location already has starred: true
    function _hasStarredLocation() {
        var locs;
        try {
            locs = JSON.parse(cfg_savedLocations || "[]");
            if (!Array.isArray(locs)) locs = [];
        } catch (e) { locs = []; }
        for (var i = 0; i < locs.length; i++) {
            if (locs[i].starred) return true;
        }
        return false;
    }

    // Set by subpages when a brand-new location is selected and staged to cfg_*.
    // Returns to main view. Back button calls this; it does NOT save the location —
    // saving happens when the user clicks Apply (detected via Plasmoid.configuration change).
    function _goBack() {
        stack.currentIndex = 0;
        searchPageLoader.active = false;
        mapPageLoader.active = false;
        manualPageLoader.active = false;
    }

    // Called directly (e.g. _pendingEntry set after navigating back) or via the
    // Connections block below when Apply causes Plasmoid.configuration.latitude to change.
    function _commitPending() {
        if (!root._pendingEntry)
            return;
        var entry = root._pendingEntry;
        var locs;
        try {
            locs = JSON.parse(Plasmoid.configuration.savedLocations || "[]");
            if (!Array.isArray(locs)) locs = [];
        } catch (e) { locs = []; }
        var isDup = locs.some(function(l) {
            return Math.abs(l.lat - entry.lat) < 0.01 && Math.abs(l.lon - entry.lon) < 0.01;
        });
        if (isDup) {
            root._pendingEntry = null;
            root.duplicateWarning = i18n("This location is already in your saved list.");
            return;
        }
        if (locs.length === 0) {
            // First location ever — auto-star, save immediately
            entry.starred = true;
            locs.push(entry);
            Plasmoid.configuration.savedLocations = JSON.stringify(locs);
            root.cfg_savedLocations = Plasmoid.configuration.savedLocations;
            root._pendingEntry = null;
        } else {
            // Ask the user whether to set it as default (dialog stays visible after Apply)
            setDefaultDialog.open();
        }
    }

    // Detect when location changes via Apply: either through save() or via
    // Plasmoid.configuration.latitude update. Both trigger _commitPending()
    // to show the setDefaultDialog for new locations.
    Connections {
        target: Plasmoid.configuration
        function onLatitudeChanged() { root._commitPending(); }
        function onAutoDetectLocationChanged() {
            // Auto-detect toggled: clear any stale pending entry
            if (Plasmoid.configuration.autoDetectLocation)
                root._pendingEntry = null;
        }
    }

    // Staged by sub-pages when the user selects a new location.
    // NOT written to cfg_savedLocations until Apply fires the Connections above.
    property var _pendingEntry: null

    // Always show the confirmation dialog when auto-detecting via the
    // config UI so the user can review the detected place before it is saved.
    property bool _forceConfirmAutoDetect: false

    function _moveLocation(fromIdx, toIdx) {
        var locs;
        try {
            locs = JSON.parse(root.cfg_savedLocations || "[]");
            if (!Array.isArray(locs))
                locs = [];
        } catch (e) {
            locs = [];
        }
        if (fromIdx < 0 || fromIdx >= locs.length || toIdx < 0 || toIdx >= locs.length)
            return;
        var item = locs.splice(fromIdx, 1)[0];
        locs.splice(toIdx, 0, item);
        root.cfg_savedLocations = JSON.stringify(locs);
    }

    // ── Saved-locations ListModel (drives the drag-and-drop ListView) ───
    // `cfg_savedLocations` (JSON string) remains the source of truth.
    // We mirror it into `savedLocWorkingModel` so `Kirigami.ListItemDragHandle`
    // can use `.move()` on a ListModel for live visual reordering.
    ListModel { id: savedLocWorkingModel }
    property bool _savedLocApplying: false

    function _rebuildSavedLocModel() {
        if (_savedLocApplying) return;
        savedLocWorkingModel.clear();
        var locs;
        try {
            locs = JSON.parse(cfg_savedLocations || "[]");
            if (!Array.isArray(locs)) locs = [];
        } catch (e) { locs = []; }
        for (var i = 0; i < locs.length; ++i) {
            var it = locs[i] || {};
            savedLocWorkingModel.append({
                name:        it.name || "",
                lat:         Number(it.lat) || 0,
                lon:         Number(it.lon) || 0,
                altitude:    Number(it.altitude) || 0,
                timezone:    it.timezone || "",
                countryCode: it.countryCode || "",
                starred:     !!it.starred
            });
        }
    }
    function _applySavedLocModel() {
        var locs = [];
        for (var i = 0; i < savedLocWorkingModel.count; ++i) {
            var it = savedLocWorkingModel.get(i);
            var entry = { name: it.name, lat: it.lat, lon: it.lon };
            if (it.altitude)    entry.altitude    = it.altitude;
            if (it.timezone)    entry.timezone    = it.timezone;
            if (it.countryCode) entry.countryCode = it.countryCode;
            if (it.starred)     entry.starred     = true;
            locs.push(entry);
        }
        _savedLocApplying = true;
        cfg_savedLocations = JSON.stringify(locs);
        _savedLocApplying = false;
    }
    onCfg_savedLocationsChanged: _rebuildSavedLocModel()
    // Note: the initial rebuild happens from the single Component.onCompleted
    // at the top of the file (declaring it a second time here would raise
    // "Property value set multiple times").

    // ── Open the manual-entry sub-page in "edit" mode for a saved entry ──
    function openManualPageForEdit(entry, index) {
        manualPageLoader.active = true;
        stack.currentIndex = 3;
        // Populate the manual form via the Loader's item once it's ready.
        // The Loader is already active (or will finish synchronously here),
        // so setting properties on `item` is safe.
        var page = manualPageLoader.item;
        if (page) {
            page.editingIndex = index;
            page.mName     = entry.name || "";
            page.mLat      = String(entry.lat || 0);
            page.mLon      = String(entry.lon || 0);
            page.mAlt      = entry.altitude !== undefined ? String(entry.altitude) : "";
            page.mTimezone = entry.timezone || "";
        }
    }

    function shouldConfirmAutoDetectedLocation() {
        return _forceConfirmAutoDetect || (!cfg_locationName || cfg_locationName.length === 0);
    }
    function stageDetectedLocation(lat, lon, altitude, timezone, name) {
        _detectedLocationApplied = false;
        detectedLatitude = lat;
        detectedLongitude = lon;
        if (!isNaN(altitude))
            detectedAltitude = Math.round(altitude);
        if (timezone && timezone.length > 0)
            detectedTimezone = timezone;
        if (name && name.length > 0)
            detectedLocationName = name;
    }
    function applyDetectedLocation() {
        // Apply even if name isn't available yet — coordinates are enough for weather
        showDetectedLocationDialog = false;
        _forceConfirmAutoDetect = false;
        _detectedLocationApplied = true;

        // Always star the auto-detected location — it becomes the new default,
        // clearing any previously starred entry.
        var locs;
        try {
            locs = JSON.parse(cfg_savedLocations || "[]");
            if (!Array.isArray(locs)) locs = [];
        } catch (e) { locs = []; }
        for (var i = 0; i < locs.length; i++) delete locs[i].starred;
        var detected = {
            name: detectedLocationName || "",
            lat: detectedLatitude,
            lon: detectedLongitude,
            altitude: detectedAltitude || 0,
            timezone: detectedTimezone || "",
            countryCode: detectedCountryCode || "",
            starred: true
        };
        var found = false;
        for (var j = 0; j < locs.length; j++) {
            if (Math.abs(locs[j].lat - detectedLatitude) < 0.01 && Math.abs(locs[j].lon - detectedLongitude) < 0.01) {
                locs[j].starred = true;
                if (detectedLocationName && detectedLocationName.length > 0)
                    locs[j].name = detectedLocationName;
                var existing = locs.splice(j, 1)[0];
                locs.unshift(existing);
                found = true;
                break;
            }
        }
        if (found) {
            root.duplicateWarning = i18n("The auto-detected location is already in your saved list.");
            duplicateDialog.open();
        } else {
            root.duplicateWarning = "";
            locs.unshift(detected);
        }
        cfg_savedLocations = JSON.stringify(locs);
        Plasmoid.configuration.savedLocations = cfg_savedLocations;

        // Always apply as the active location — write once to activeLocation,
        // then keep individual entries in sync (suppressed from triggering refreshDebounce).
        Plasmoid.configuration.activeLocation = JSON.stringify({
            name:        detectedLocationName  || "",
            lat:         detectedLatitude       || 0,
            lon:         detectedLongitude      || 0,
            altitude:    (!isNaN(detectedAltitude) && detectedAltitude !== 0) ? detectedAltitude : 0,
            timezone:    detectedTimezone       || "",
            countryCode: detectedCountryCode    || ""
        });
        Plasmoid.configuration.autoDetectLocation = true;
        Plasmoid.configuration.latitude = detectedLatitude;
        Plasmoid.configuration.longitude = detectedLongitude;
        if (detectedTimezone && detectedTimezone.length > 0)
            Plasmoid.configuration.timezone = detectedTimezone;
        if (!isNaN(detectedAltitude) && detectedAltitude !== 0)
            Plasmoid.configuration.altitude = detectedAltitude;
        if (detectedLocationName && detectedLocationName.length > 0)
            Plasmoid.configuration.locationName = detectedLocationName;
        if (detectedCountryCode && detectedCountryCode.length > 0)
            Plasmoid.configuration.countryCode = detectedCountryCode;
        cfg_autoDetectLocation = Plasmoid.configuration.autoDetectLocation;
        cfg_latitude = Plasmoid.configuration.latitude;
        cfg_longitude = Plasmoid.configuration.longitude;
        cfg_timezone = Plasmoid.configuration.timezone;
        cfg_altitude = Plasmoid.configuration.altitude;
        cfg_locationName = Plasmoid.configuration.locationName;
        cfg_countryCode = Plasmoid.configuration.countryCode;

        verifyProviderLocation(detectedLatitude, detectedLongitude);
    }
    function chooseManualLocation() {
        _forceConfirmAutoDetect = false;
        cfg_autoDetectLocation = false;
        showDetectedLocationDialog = false;
        openSearchPage();
    }

    // Apply current cfg_ values to Plasmoid.configuration immediately
    // (bypasses KCM Apply button) and open the save dialog if a pending
    // entry is waiting.
    //
    // Uses a short Timer to defer the Plasmoid.configuration writes to the
    // next event-loop iteration.  This avoids timing conflicts with the KCM
    // framework's own dirty-detection which can intercept synchronous writes.
    Timer {
        id: _applyTimer
        interval: 50
        repeat: false
        onTriggered: {
            Plasmoid.configuration.activeLocation = JSON.stringify({
                name:        root.cfg_locationName  || "",
                lat:         root.cfg_latitude       || 0,
                lon:         root.cfg_longitude      || 0,
                altitude:    root.cfg_altitude       || 0,
                timezone:    root.cfg_timezone       || "",
                countryCode: root.cfg_countryCode    || ""
            });
            Plasmoid.configuration.autoDetectLocation = root.cfg_autoDetectLocation;
            Plasmoid.configuration.latitude = root.cfg_latitude;
            Plasmoid.configuration.longitude = root.cfg_longitude;
            Plasmoid.configuration.locationName = root.cfg_locationName;
            Plasmoid.configuration.timezone = root.cfg_timezone;
            Plasmoid.configuration.altitude = root.cfg_altitude;
            Plasmoid.configuration.countryCode = root.cfg_countryCode;
            Plasmoid.configuration.savedLocations = root.cfg_savedLocations;
            if (typeof Plasmoid.configuration.writeConfig === "function")
                Plasmoid.configuration.writeConfig();
        }
    }

    function _immediateApplyAndOffer() {
        _applyTimer.restart();
    }

    // Like _immediateApplyAndOffer but WITHOUT the immediate Plasmoid.configuration
    // write — used by the map sub-page so changes are only committed when the
    // user clicks the KCM Apply button.
    function _offerSave() {
        // No-op: locations are now saved automatically without a dialog.
    }

    property string preferredLanguage: Qt.locale().name.split("_")[0]
    readonly property string bundledOpenWeatherApiKey: "8003225e8825db83758c237068447229"
    readonly property string bundledWeatherApiKey: "601ba4ac57404ec29ff120510261802"
    function displayAltitudeUnit() {
        return cfg_altitudeUnit === "ft" ? "feet" : "meters";
    }

    // ── Provider location check state ───────────────────────────────────
    // 0 = idle, 1 = checking, 2 = ok, 3 = error
    property int locationCheckState: 0
    property string locationCheckMessage: ""

    function verifyProviderLocation(lat, lon) {
        var provider = cfg_weatherProvider;
        if (provider === "adaptive" || provider === "openMeteo") {
            locationCheckState = 0;
            return;  // Open-Meteo always works
        }
        locationCheckState = 1;
        locationCheckMessage = i18n("Checking location availability…");

        var req = new XMLHttpRequest();
        var url;
        if (provider === "openWeather") {
            var owKey = (Plasmoid.configuration.owApiKey || "").trim();
            if (!owKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.openweathermap.org/data/2.5/weather?lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon) + "&units=metric&appid=" + encodeURIComponent(owKey);
        } else if (provider === "weatherApi") {
            var waKey = (Plasmoid.configuration.waApiKey || "").trim();
            if (!waKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.weatherapi.com/v1/current.json?key=" + encodeURIComponent(waKey) + "&q=" + encodeURIComponent(lat + "," + lon);
        } else if (provider === "pirateWeather") {
            var pwKey = (Plasmoid.configuration.pwApiKey || "").trim();
            if (!pwKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.pirateweather.net/forecast/" + encodeURIComponent(pwKey) + "/" + lat + "," + lon + "?units=ca&exclude=minutely,hourly,daily,alerts";
        } else if (provider === "metno") {
            url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon);
        } else if (provider === "qWeather") {
            var qwKey = (Plasmoid.configuration.qwApiKey || "").trim();
            if (!qwKey) {
                locationCheckState = 0;
                return;
            }
            var qwHost = (Plasmoid.configuration.qwApiHost || "").trim();
            if (!qwHost) qwHost = "https://devapi.qweather.com";
            qwHost = qwHost.replace(/\/+$/, "");
            var qwLoc = encodeURIComponent(parseFloat(lon).toFixed(2) + "," + parseFloat(lat).toFixed(2));
            url = qwHost + "/v7/weather/now?location=" + qwLoc + "&unit=m";
        } else {
            locationCheckState = 0;
            return;
        }
        req.open("GET", url);
        if (provider === "qWeather") {
            var _qwKey = (Plasmoid.configuration.qwApiKey || "").trim();
            req.setRequestHeader("X-QW-Api-Key", _qwKey);
        } else if (provider === "metno")
            req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            var pLabel = providerDisplayNameFor(provider);
            if (req.status === 200) {
                locationCheckState = 2;
                locationCheckMessage = i18n("Location is available on %1.", pLabel);
            } else {
                locationCheckState = 3;
                locationCheckMessage = i18n("Location is not available on %1 (HTTP %2). Try a different provider or location.", pLabel, req.status);
            }
        };
        req.send();
    }

    function providerDisplayNameFor(p) {
        if (p === "openWeather")
            return "OpenWeatherMap";
        if (p === "weatherApi")
            return "WeatherAPI.com";
        if (p === "metno")
            return "met.no";
        if (p === "pirateWeather")
            return "Pirate Weather";
        if (p === "qWeather")
            return "QWeather";
        return "Open-Meteo";
    }

    // Returns "(GMT +2)" / "(GMT -5:30)" for any IANA timezone identifier.
    // We compute the UTC offset by formatting the same Date in the target timezone
    // and in UTC using basic hour+minute parts — this works in Qt 6's V4+ICU
    // without needing timeZoneName:"shortOffset" (ES2021, not guaranteed available).
    function gmtOffsetLabel(tzId) {
        if (!tzId || tzId.length === 0)
            return "";
        try {
            var now = new Date();
            // Helper: get total minutes-since-midnight for a given timezone
            function totalMins(tz) {
                var parts = new Intl.DateTimeFormat("en-US", {
                    timeZone: tz,
                    hour: "numeric",
                    minute: "numeric",
                    hour12: false
                }).formatToParts(now);
                var h = 0, m = 0;
                for (var i = 0; i < parts.length; ++i) {
                    if (parts[i].type === "hour")
                        h = parseInt(parts[i].value, 10);
                    if (parts[i].type === "minute")
                        m = parseInt(parts[i].value, 10);
                }
                return h * 60 + m;
            }
            var diff = totalMins(tzId) - totalMins("UTC");
            // Clamp across midnight boundaries (diff can be ±1439)
            if (diff > 720)
                diff -= 1440;
            if (diff < -720)
                diff += 1440;
            var sign = diff >= 0 ? "+" : "-";
            var abs = Math.abs(diff);
            var h = Math.floor(abs / 60);
            var m = abs % 60;
            var label = m === 0 ? "GMT " + sign + h : "GMT " + sign + h + ":" + (m < 10 ? "0" + m : String(m));
            return "(" + label + ")";
        } catch (e) {
            return "";
        }
    }

    function formatResultTitle(item) {
        if (!item)
            return "";
        if (item.localizedDisplayName && item.localizedDisplayName.length > 0)
            return item.localizedDisplayName;
        var admin = item.admin1 ? ", " + item.admin1 : "";
        var country = item.country ? ", " + item.country : "";
        var first = item.name ? item.name : "";
        return first.length > 0 ? first + admin + country : (item.display_name ? item.display_name : "");
    }
    function formatResultListItem(item) {
        return formatResultTitle(item);
    }
    function selectedProviderDisplayName() {
        if (cfg_weatherProvider === "adaptive")
            return "Adaptive";
        if (cfg_weatherProvider === "openWeather")
            return "OpenWeather";
        if (cfg_weatherProvider === "weatherApi")
            return "WeatherAPI.com";
        if (cfg_weatherProvider === "pirateWeather")
            return "Pirate Weather";
        if (cfg_weatherProvider === "metno")
            return "met.no";
        return "Open-Meteo";
    }
    function currentLocationDisplayName() {
        return cfg_locationName && cfg_locationName.length > 0 ? cfg_locationName : i18n("None Selected");
    }
    function openSearchPage() {
        searchPageLoader.active = true; stack.currentIndex = 1;
    }
    function openMapPage() {
        mapPageLoader.active = true; stack.currentIndex = 2;
    }
    function openManualPage() {
        manualPageLoader.active = true; stack.currentIndex = 3;
        // Fresh "Add new location" flow — clear any leftover edit-mode state
        // from a previous visit to this sub-page.
        var page = manualPageLoader.item;
        if (page) {
            page.editingIndex = -1;
            page.mName = "";
            page.mLat = "";
            page.mLon = "";
            page.mAlt = "";
            page.mTimezone = "";
        }
    }

    function reverseGeocode(lat, lon) {
        stageDetectedLocation(lat, lon, NaN, "", "");
        var metaReq = new XMLHttpRequest();
        metaReq.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon) + "&current=temperature_2m&timezone=auto");
        metaReq.onreadystatechange = function () {
            if (metaReq.readyState !== XMLHttpRequest.DONE)
                return;
            if (metaReq.status === 200) {
                var meta = JSON.parse(metaReq.responseText);
                if (root._detectedLocationApplied) {
                    // The user already clicked "Apply" before this response
                    // arrived — write directly to config so it’s not lost.
                    if (meta.timezone && meta.timezone.length > 0) {
                        cfg_timezone = meta.timezone;
                        Plasmoid.configuration.timezone = meta.timezone;
                    }
                    if (meta.elevation !== undefined && !isNaN(meta.elevation)) {
                        cfg_altitude = Math.round(meta.elevation);
                        Plasmoid.configuration.altitude = Math.round(meta.elevation);
                    }
                } else if (shouldConfirmAutoDetectedLocation()) {
                    if (meta.timezone)
                        root.detectedTimezone = meta.timezone;
                    if (meta.elevation !== undefined && !isNaN(meta.elevation))
                        root.detectedAltitude = Math.round(meta.elevation);
                } else {
                    // Persist directly so the widget sees the new values even
                    // if the config dialog is closed before this callback fires.
                    if (meta.timezone) {
                        cfg_timezone = meta.timezone;
                        Plasmoid.configuration.timezone = meta.timezone;
                    }
                    if (meta.elevation !== undefined && !isNaN(meta.elevation)) {
                        cfg_altitude = Math.round(meta.elevation);
                        Plasmoid.configuration.altitude = Math.round(meta.elevation);
                    }
                }
            }
        };
        metaReq.send();
        var req = new XMLHttpRequest();
        // accept-language must NOT be percent-encoded (commas are syntactically significant)
        var revLang = preferredLanguage.length > 0 ? preferredLanguage + ",en;q=0.8" : "en";
        req.open("GET", "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&addressdetails=1" + "&accept-language=" + revLang + "&lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon));
        req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status === 200) {
                var data = JSON.parse(req.responseText);
                if (data && data.address) {
                    var a = data.address;
                    // Extended fallback chain — matches forward-search logic
                    var city = a.city || a.town || a.village || a.hamlet || a.suburb || a.municipality || a.county || "";
                    var country = a.country || "";
                    var name;
                    if (city.length > 0 && country.length > 0)
                        name = city + ", " + country;
                    else if (city.length > 0)
                        name = city;
                    else if (country.length > 0)
                        name = country;
                    else
                        name = data.display_name || "";   // last-resort fallback

                    if (name.length > 0) {
                        if (shouldConfirmAutoDetectedLocation()) {
                            root.detectedLocationName = name;
                            root.showDetectedLocationDialog = true;
                        } else {
                            cfg_locationName = name;
                            Plasmoid.configuration.locationName = name;
                        }
                    }
                    // Capture country code for MeteoAlarm alerts
                    var cc = (a.country_code || "").toUpperCase();
                    if (cc.length > 0) {
                        if (shouldConfirmAutoDetectedLocation()) {
                            root.detectedCountryCode = cc;
                        } else {
                            cfg_countryCode = cc;
                            Plasmoid.configuration.countryCode = cc;
                        }
                    }
                }
                autoDetectStatus = i18n("Location auto-detected.");
            } else {
                autoDetectStatus = i18n("Auto-detection updated coordinates.");
            }
            autoDetectBusy = false;
        };
        req.send();
    }

    // ── 3-tier auto-detection ───────────────────────────────────────────
    // Tier 1: GeoClue2 explicitly
    // Tier 2: Any available Qt Positioning plugin
    // Tier 3: IP geolocation (geo.kamero.ai → reallyfreegeoip.org)
    // Which tier is active: 0 = idle, 1 = geoclue2, 2 = generic, 3 = IP
    property int _cfgLocationTier: 0

    function _cfgHandlePosition(lat, lon, alt, tierLabel) {
        // Deactivate sources after successful fix to avoid duplicate callbacks
        cfgGeoclue2Source.active = false;
        cfgGenericSource.active = false;
        if (root.shouldConfirmAutoDetectedLocation()) {
            root.stageDetectedLocation(lat, lon, alt, "", "");
        } else {
            root.cfg_latitude = lat;
            root.cfg_longitude = lon;
            Plasmoid.configuration.activeLocation = JSON.stringify({
                name:        root.cfg_locationName || "",
                lat:         lat  || 0,
                lon:         lon  || 0,
                altitude:    (!isNaN(alt) && alt > 0) ? Math.round(alt) : (root.cfg_altitude || 0),
                timezone:    root.cfg_timezone     || "",
                countryCode: root.cfg_countryCode  || ""
            });
            Plasmoid.configuration.latitude = lat;
            Plasmoid.configuration.longitude = lon;
            if (!isNaN(alt) && alt > 0) {
                root.cfg_altitude = Math.round(alt);
                Plasmoid.configuration.altitude = Math.round(alt);
            }
        }
        autoDetectStatus = i18n("Requesting location… (%1)", tierLabel);
        root.reverseGeocode(lat, lon);
    }

    function refreshAutoDetectedLocation() {
        if (!cfg_autoDetectLocation) {
            autoDetectBusy = false;
            return;
        }
        autoDetectBusy = true;
        _cfgLocationTier = 1;
        autoDetectStatus = i18n("Requesting location via GeoClue2…");
        cfgGeoclue2Source.active = true;
        cfgGeoclue2Source.update();
        _cfgGeoclue2Timer.restart();
    }

    function _cfgEscalateToGeneric() {
        cfgGeoclue2Source.active = false;
        _cfgLocationTier = 2;
        autoDetectStatus = i18n("GeoClue2 unavailable, trying system location…");
        cfgGenericSource.active = true;
        cfgGenericSource.update();
        _cfgGenericTimer.restart();
    }

    function _cfgEscalateToIpGeo() {
        cfgGenericSource.active = false;
        _cfgLocationTier = 3;
        autoDetectStatus = i18n("System location unavailable, trying IP geolocation…");
        _cfgIpGeolocate();
    }

    Timer {
        id: _cfgGeoclue2Timer
        interval: 8000
        repeat: false
        onTriggered: {
            if (_cfgLocationTier === 1) {
                console.log("[Location/config] GeoClue2 timed out, trying generic…");
                _cfgEscalateToGeneric();
            }
        }
    }
    Timer {
        id: _cfgGenericTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (_cfgLocationTier === 2) {
                console.log("[Location/config] Generic source timed out, trying IP…");
                _cfgEscalateToIpGeo();
            }
        }
    }

    Timer {
        id: _cfgIpGeoTimer
        interval: 10000
        repeat: false
        property var _activeReq: null
        onTriggered: {
            if (_cfgLocationTier === 3 && _activeReq) {
                console.warn("[Location/config] Tier 3 IP geolocation timed out");
                _activeReq.abort();
                _activeReq = null;
                _cfgLocationTier = 0;
                autoDetectBusy = false;
                autoDetectStatus = i18n("Unable to detect location. All methods failed.");
            }
        }
    }

    // Tier 1 — GeoClue2 explicitly
    PositionSource {
        id: cfgGeoclue2Source
        name: "geoclue2"
        active: false
        updateInterval: 300000
        onPositionChanged: {
            if (!root.cfg_autoDetectLocation)
                return;
            var c = position.coordinate;
            if (!c || !c.isValid)
                return;
            _cfgGeoclue2Timer.stop();
            _cfgLocationTier = 0;
            console.log("[Location/config] Tier 1 (GeoClue2): position acquired");
            _cfgHandlePosition(c.latitude, c.longitude, c.altitude, "GeoClue2");
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && _cfgLocationTier === 1) {
                console.log("[Location/config] Tier 1 (GeoClue2) error:", sourceError);
                _cfgGeoclue2Timer.stop();
                _cfgEscalateToGeneric();
            }
        }
    }

    // Tier 2 — any available Qt Positioning plugin
    PositionSource {
        id: cfgGenericSource
        active: false
        updateInterval: 300000
        onPositionChanged: {
            if (!root.cfg_autoDetectLocation)
                return;
            var c = position.coordinate;
            if (!c || !c.isValid)
                return;
            _cfgGenericTimer.stop();
            _cfgLocationTier = 0;
            console.log("[Location/config] Tier 2 (generic): position acquired");
            _cfgHandlePosition(c.latitude, c.longitude, c.altitude, i18n("system location"));
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && _cfgLocationTier === 2) {
                console.log("[Location/config] Tier 2 (generic) error:", sourceError);
                _cfgGenericTimer.stop();
                _cfgEscalateToIpGeo();
            }
        }
    }

    // Tier 3 — IP-based geolocation
    function _cfgIpGeolocate() {
        console.log("[Location/config] Tier 3: trying geo.kamero.ai…");
        var req = new XMLHttpRequest();
        _cfgIpGeoTimer._activeReq = req;
        _cfgIpGeoTimer.restart();
        req.open("GET", "https://geo.kamero.ai/api/geo");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status === 200) {
                try {
                    var data = JSON.parse(req.responseText);
                    var lat = parseFloat(data.latitude);
                    var lon = parseFloat(data.longitude);
                    if (!isNaN(lat) && !isNaN(lon)) {
                        _cfgIpGeoTimer.stop();
                        _cfgIpGeoTimer._activeReq = null;
                        _cfgLocationTier = 0;
                        console.log("[Location/config] Tier 3 (geo.kamero.ai): position acquired");
                        _cfgHandlePosition(lat, lon, NaN, i18n("IP geolocation"));
                        return;
                    }
                } catch (e) {
                    console.warn("[Location/config] geo.kamero.ai parse error:", e);
                }
            }
            _cfgIpGeolocateFallback();
        };
        req.send();
    }

    function _cfgIpGeolocateFallback() {
        console.log("[Location/config] Tier 3 fallback: trying reallyfreegeoip.org…");
        var req = new XMLHttpRequest();
        _cfgIpGeoTimer._activeReq = req;
        _cfgIpGeoTimer.restart();
        req.open("GET", "https://reallyfreegeoip.org/json/");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            _cfgIpGeoTimer.stop();
            _cfgIpGeoTimer._activeReq = null;
            if (req.status === 200) {
                try {
                    var data = JSON.parse(req.responseText);
                    var lat = parseFloat(data.latitude);
                    var lon = parseFloat(data.longitude);
                    if (!isNaN(lat) && !isNaN(lon)) {
                        _cfgLocationTier = 0;
                        console.log("[Location/config] Tier 3 (reallyfreegeoip): position acquired");
                        _cfgHandlePosition(lat, lon, NaN, i18n("IP geolocation"));
                        return;
                    }
                } catch (e) {
                    console.warn("[Location/config] reallyfreegeoip parse error:", e);
                }
            }
            _cfgLocationTier = 0;
            autoDetectBusy = false;
            autoDetectStatus = i18n("Unable to detect location. All methods failed.");
            console.warn("[Location/config] All 3 tiers failed");
        };
        req.send();
    }

    function applySearchResult(item) {
        if (!item)
            return;
        var newName;
        if (item.providerKey === "nominatim" && item.localizedDisplayName && item.localizedDisplayName.length > 0) {
            newName = item.localizedDisplayName;
        } else {
            var nameParts = [];
            if (item.name && item.name.length > 0)
                nameParts.push(item.name);
            if (item.district && item.district.length > 0 && item.district.toLowerCase() !== (item.name || "").toLowerCase())
                nameParts.push(item.district);
            if (item.admin1 && item.admin1.length > 0 && item.admin1.toLowerCase() !== (item.name || "").toLowerCase())
                nameParts.push(item.admin1);
            if (item.country && item.country.length > 0)
                nameParts.push(item.country);
            newName = nameParts.length > 0 ? nameParts.join(", ") : (item.localizedDisplayName || "");
        }

        var lat = parseFloat(item.latitude);
        var lon = parseFloat(item.longitude);
        var newTimezone = item.timezone || cfg_timezone;
        var newCountryCode = (item.countryCode && item.countryCode.length > 0)
            ? item.countryCode.toUpperCase() : cfg_countryCode;

        // Stage active location — committed to Plasmoid.configuration only on KCM Apply
        cfg_autoDetectLocation = false;
        cfg_locationName = newName;
        cfg_latitude = lat;
        cfg_longitude = lon;
        cfg_timezone = newTimezone;
        cfg_countryCode = newCountryCode;

        // Fetch accurate elevation — updates cfg_altitude only, no Plasmoid.configuration write
        var elevReq = new XMLHttpRequest();
        elevReq.open("GET", "https://api.open-meteo.com/v1/elevation?latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon));
        elevReq.onreadystatechange = function () {
            if (elevReq.readyState !== XMLHttpRequest.DONE)
                return;
            if (elevReq.status === 200) {
                var data = JSON.parse(elevReq.responseText);
                if (data.elevation && data.elevation.length > 0 && !isNaN(data.elevation[0]))
                    cfg_altitude = Math.round(data.elevation[0]);
            }
        };
        elevReq.send();

        // Fetch timezone — updates cfg_timezone only, no Plasmoid.configuration write
        var tzReq = new XMLHttpRequest();
        tzReq.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon) + "&current=temperature_2m&timezone=auto");
        tzReq.onreadystatechange = function () {
            if (tzReq.readyState !== XMLHttpRequest.DONE)
                return;
            if (tzReq.status === 200) {
                var meta = JSON.parse(tzReq.responseText);
                if (meta.timezone && meta.timezone.length > 0)
                    cfg_timezone = meta.timezone;
            }
        };
        tzReq.send();

        verifyProviderLocation(lat, lon);
    }

    onCfg_autoDetectLocationChanged: {
        if (cfg_autoDetectLocation)
            refreshAutoDetectedLocation();
        else {
            autoDetectBusy = false;
            autoDetectStatus = "";
            cfgGeoclue2Source.active = false;
            cfgGenericSource.active = false;
            _cfgLocationTier = 0;
        }
    }

    Kirigami.Dialog {
        id: detectedLocationDialog
        title: i18n("Confirm your location")
        standardButtons: Kirigami.Dialog.NoButton
        leftPadding: Kirigami.Units.gridUnit * 2
        rightPadding: Kirigami.Units.gridUnit * 2
        topPadding: Kirigami.Units.gridUnit
        bottomPadding: Kirigami.Units.gridUnit
        onClosed: {
            root.showDetectedLocationDialog = false;
            root._forceConfirmAutoDetect = false;
        }
        contentItem: Item {
            implicitWidth: 540
            implicitHeight: contentCol.implicitHeight
            ColumnLayout {
                id: contentCol
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    source: "mark-location"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.RichText
                    text: root.detectedLocationName && root.detectedLocationName.length > 0 ? i18n("We detected your location as: <b>%1</b>.", root.detectedLocationName) : i18n("We detected your coordinates: <b>%1°, %2°</b>.", root.detectedLatitude.toFixed(4), root.detectedLongitude.toFixed(4))
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.75
                    text: i18n("If this looks correct, apply it. Otherwise, choose your location manually.")
                }
                Item {
                    Layout.preferredHeight: Kirigami.Units.largeSpacing
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Kirigami.Units.mediumSpacing
                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        text: i18n("Apply detected location")
                        icon.name: "dialog-ok-apply"
                        enabled: root.detectedLatitude !== 0.0 || root.detectedLongitude !== 0.0
                        onClicked: root.applyDetectedLocation()
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Kirigami.Units.mediumSpacing
                        Button {
                            text: i18n("Search location")
                            icon.name: "edit-find"
                            onClicked: root.chooseManualLocation()
                        }
                        Button {
                            text: i18n("Enter manually")
                            icon.name: "document-edit"
                            onClicked: {
                                root.showDetectedLocationDialog = false;
                                root._forceConfirmAutoDetect = false;
                                root.cfg_autoDetectLocation = false;
                                root.openManualPage();
                            }
                        }
                        Button {
                            text: i18n("Choose on map")
                            icon.name: "map-flat"
                            onClicked: {
                                root.showDetectedLocationDialog = false;
                                root._forceConfirmAutoDetect = false;
                                root.cfg_autoDetectLocation = false;
                                root.openMapPage();
                            }
                        }
                    }
                }
                Item {
                    Layout.preferredHeight: Kirigami.Units.smallSpacing
                }
            }
        }
    }

    onShowDetectedLocationDialogChanged: {
        if (showDetectedLocationDialog)
            detectedLocationDialog.open();
        else
            detectedLocationDialog.close();
    }



    // ── Set as default dialog (shown on KCM Apply for new locations) ──────
    Kirigami.Dialog {
        id: setDefaultDialog
        // Buttons write directly to Plasmoid.configuration so the save is
        // immediate and does not require a second Apply click.
        title: i18n("Set as default?")
        standardButtons: Kirigami.Dialog.NoButton
        leftPadding: Kirigami.Units.gridUnit * 2
        rightPadding: Kirigami.Units.gridUnit * 2
        topPadding: Kirigami.Units.gridUnit
        bottomPadding: Kirigami.Units.gridUnit
        onClosed: root._pendingEntry = null

        contentItem: Item {
            implicitWidth: 360
            implicitHeight: setDefaultDlgCol.implicitHeight
            ColumnLayout {
                id: setDefaultDlgCol
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    source: "starred-symbolic"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.RichText
                    text: root._pendingEntry
                        ? i18n("Set <b>%1</b> as your default location?", root._pendingEntry.name)
                        : ""
                }
                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Kirigami.Units.mediumSpacing
                    Button {
                        text: i18n("Yes")
                        icon.name: "dialog-ok-apply"
                        onClicked: {
                            var entry = root._pendingEntry;
                            if (!entry) { setDefaultDialog.close(); return; }
                            // Clear _pendingEntry FIRST so any signal triggered below
                            // cannot re-enter _commitPending with a non-null entry.
                            root._pendingEntry = null;
                            var locs;
                            try {
                                locs = JSON.parse(Plasmoid.configuration.savedLocations || "[]");
                                if (!Array.isArray(locs)) locs = [];
                            } catch (e) { locs = []; }
                            for (var i = 0; i < locs.length; i++)
                                delete locs[i].starred;
                            locs.unshift({
                                name: entry.name, lat: entry.lat, lon: entry.lon,
                                altitude: entry.altitude || 0,
                                timezone: entry.timezone || "",
                                countryCode: entry.countryCode || "",
                                starred: true
                            });
                            var newJson = JSON.stringify(locs);
                            // Write Plasmoid.configuration first, then cfg_ to the same
                            // value. When KCM evaluates dirty (cfg_ vs Plasmoid.configuration),
                            // they are already equal → Apply button stays inactive.
                            // Writing cfg_ also refreshes savedLocWorkingModel immediately.
                            Plasmoid.configuration.savedLocations = newJson;
                            root.cfg_savedLocations = newJson;
                            // Do NOT re-write latitude, longitude, locationName, etc. here.
                            // KCM Apply already synced all those from cfg_* to
                            // Plasmoid.configuration.*. Re-writing them triggers
                            // onLatitudeChanged and Plasma widget reload a second time,
                            // which is what causes the perceived hang.
                            setDefaultDialog.close();
                        }
                    }
                    Button {
                        text: i18n("No")
                        icon.name: "dialog-cancel"
                        onClicked: {
                            var entry = root._pendingEntry;
                            if (!entry) { setDefaultDialog.close(); return; }
                            // Clear _pendingEntry FIRST — same re-entrancy guard as Yes.
                            root._pendingEntry = null;
                            var locs;
                            try {
                                locs = JSON.parse(Plasmoid.configuration.savedLocations || "[]");
                                if (!Array.isArray(locs)) locs = [];
                            } catch (e) { locs = []; }
                            locs.push({
                                name: entry.name, lat: entry.lat, lon: entry.lon,
                                altitude: entry.altitude || 0,
                                timezone: entry.timezone || "",
                                countryCode: entry.countryCode || ""
                            });
                            var newJson = JSON.stringify(locs);
                            // Same pattern as Yes: Plasmoid.configuration first, then cfg_
                            // to the same value so KCM sees them equal (not dirty) and
                            // savedLocWorkingModel updates immediately.
                            Plasmoid.configuration.savedLocations = newJson;
                            root.cfg_savedLocations = newJson;
                            setDefaultDialog.close();
                        }
                    }
                }
                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
            }
        }
    }

    // ── Delete last location confirmation dialog ───────────────────────────
    property int _deleteLocIndex: -1

    Kirigami.Dialog {
        id: deleteLastLocDialog
        title: i18n("Remove last location?")
        standardButtons: Kirigami.Dialog.NoButton
        leftPadding: Kirigami.Units.gridUnit * 2
        rightPadding: Kirigami.Units.gridUnit * 2
        topPadding: Kirigami.Units.gridUnit
        bottomPadding: Kirigami.Units.gridUnit

        contentItem: Item {
            implicitWidth: 380
            implicitHeight: deleteLastDlgCol.implicitHeight
            ColumnLayout {
                id: deleteLastDlgCol
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    source: "edit-delete"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: i18n("Are you sure? This is your last saved location. If you remove it, the widget will no longer show weather information.")
                }
                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Kirigami.Units.mediumSpacing
                    Button {
                        text: i18n("Yes, remove it")
                        icon.name: "edit-delete"
                        onClicked: {
                            root.cfg_savedLocations = "[]";
                            root.cfg_locationName = "";
                            root.cfg_latitude = 0.0;
                            root.cfg_longitude = 0.0;
                            root.cfg_altitude = 0;
                            root.cfg_timezone = "";
                            root.cfg_countryCode = "";
                            root.cfg_autoDetectLocation = false;
                            // Clear activeLocation so hasSelectedTown becomes false and weather stops showing
                            Plasmoid.configuration.activeLocation = "{}";
                            root._deleteLocIndex = -1;
                            deleteLastLocDialog.close();
                        }
                    }
                    Button {
                        text: i18n("Cancel")
                        icon.name: "dialog-cancel"
                        onClicked: {
                            root._deleteLocIndex = -1;
                            deleteLastLocDialog.close();
                        }
                    }
                }
                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // StackLayout replaces StackView to avoid Kirigami page-routing interference
    // inside KCM.SimpleKCM. Navigation is done by setting currentIndex.
    StackLayout {
        id: stack
        anchors.fill: parent
        currentIndex: 0

        // page 0 — main
        Loader { id: mainPageLoader; sourceComponent: mainPage; active: true }
        // page 1 — search
        Loader { id: searchPageLoader; sourceComponent: searchSubPage; active: false }
        // page 2 — map
        Loader { id: mapPageLoader;    sourceComponent: mapSubPage;    active: false }
        // page 3 — manual entry
        Loader { id: manualPageLoader; sourceComponent: manualSubPage; active: false }
    }

    Component {
        id: mainPage
        Item {
            ScrollView {
                id: mainScrollView
                anchors.fill: parent
                contentWidth: availableWidth

                ColumnLayout {
                    width: mainScrollView.availableWidth
                    spacing: 10

                    ButtonGroup {
                        id: locationModeGroup
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.duplicateWarning !== ""
                        type: Kirigami.MessageType.Warning
                        text: root.duplicateWarning
                        showCloseButton: true
                        onVisibleChanged: if (!visible) root.duplicateWarning = ""
                    }

                    // ── Auto-detect radio ──────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RadioButton {
                            text: i18n("Automatically detect location")
                            checked: root.cfg_autoDetectLocation
                            ButtonGroup.group: locationModeGroup
                            onClicked: {
                                root._forceConfirmAutoDetect = true;
                                root.cfg_autoDetectLocation = true;
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            spacing: 8
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                opacity: 0.78
                                text: root.autoDetectBusy ? i18n("Detecting…") : (root.autoDetectStatus.length > 0 ? root.autoDetectStatus : i18n("Location detection is depending on system configuration and permissions."))
                            }
                            Button {
                                text: i18n("Refresh")
                                visible: root.cfg_autoDetectLocation
                                enabled: root.cfg_autoDetectLocation && !root.autoDetectBusy
                                onClicked: {
                                    root._forceConfirmAutoDetect = true;
                                    root.refreshAutoDetectedLocation();
                                }
                            }
                        }

                        // ── Manual radio with inline Change Location button ─
                        Item {
                            Layout.preferredHeight: 4
                        }
                        RadioButton {
                            text: i18n("Use manual location")
                            checked: !root.cfg_autoDetectLocation
                            ButtonGroup.group: locationModeGroup
                            onClicked: root.cfg_autoDetectLocation = false
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            spacing: 8
                            visible: !root.cfg_autoDetectLocation
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                opacity: 0.78
                                text: i18n("Search for a location or choose it on the map.")
                            }
                            Button {
                                text: i18n("Search Location")
                                icon.name: "edit-find"
                                enabled: !root.cfg_autoDetectLocation
                                onClicked: root.openSearchPage()
                            }
                            Button {
                                text: i18n("Choose on Map")
                                icon.name: "map-flat"
                                enabled: !root.cfg_autoDetectLocation
                                onClicked: root.openMapPage()
                            }
                            Button {
                                text: i18n("Enter Manually")
                                icon.name: "document-edit"
                                enabled: !root.cfg_autoDetectLocation
                                onClicked: root.openManualPage()
                            }
                        }
                    }

                    // ── Saved Locations section header ──────────────────────
                    Item {
                        Layout.preferredHeight: 4
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Kirigami.Heading {
                            text: i18n("Saved locations")
                            level: 4
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                            opacity: 0.6
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        visible: savedLocWorkingModel.count === 0
                        text: i18n("No saved locations. Save the current location to quickly switch between places.")
                    }

                    // Drag-and-drop list of saved locations — matches the reorder
                    // pattern used in ConfigDetailsSubPage / ConfigPanelSubPage /
                    // ConfigTooltipSubPage via Kirigami.ListItemDragHandle.
                    ListView {
                        id: savedLocList
                        Layout.fillWidth: true
                        Layout.preferredHeight: contentHeight
                        interactive: false
                        reuseItems: false
                        spacing: 2
                        clip: false
                        model: savedLocWorkingModel

                        moveDisplaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: 120
                                easing.type: Easing.OutQuad
                            }
                        }
                        displaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: 120
                                easing.type: Easing.OutQuad
                            }
                        }

                        delegate: Item {
                            id: savedLocDelegateRoot
                            required property int index
                            required property string name
                            required property real lat
                            required property real lon
                            required property real altitude
                            required property string timezone
                            required property string countryCode
                            required property bool starred

                            width: savedLocList.width
                            implicitHeight: savedLocDelegate.implicitHeight

                            property bool _renaming: false
                            readonly property bool _isActive:
                                Math.abs(root.cfg_latitude  - lat) < 0.01 &&
                                Math.abs(root.cfg_longitude - lon) < 0.01

                            function _commitRename() {
                                var newName = renameField.text.trim();
                                if (newName.length === 0) {
                                    _renaming = false;
                                    return;
                                }
                                var locs;
                                try {
                                    locs = JSON.parse(root.cfg_savedLocations || "[]");
                                    if (!Array.isArray(locs)) locs = [];
                                } catch (e) { locs = []; }
                                if (index >= 0 && index < locs.length) {
                                    locs[index].name = newName;
                                    root.cfg_savedLocations = JSON.stringify(locs);
                                }
                                _renaming = false;
                            }

                            ItemDelegate {
                                id: savedLocDelegate
                                width: parent.width
                                implicitHeight: savedLocContent.implicitHeight + 12
                                hoverEnabled: true
                                down: false

                                background: Rectangle {
                                    radius: 4
                                    color: savedLocDelegateRoot._isActive
                                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.20)
                                        : (savedLocDelegate.hovered && !savedLocDelegateRoot._renaming
                                            ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.10)
                                            : "transparent")
                                    border.color: savedLocDelegateRoot._isActive ? Kirigami.Theme.highlightColor : "transparent"
                                    border.width: savedLocDelegateRoot._isActive ? 1 : 0
                                }

                                // Row click activates this location (unless renaming
                                // or the user clicks a child button which consumes
                                // the event first).
                                onClicked: {
                                    if (savedLocDelegateRoot._renaming) return;
                                    root.cfg_autoDetectLocation = false;
                                    root.cfg_locationName = savedLocDelegateRoot.name;
                                    root.cfg_latitude     = savedLocDelegateRoot.lat;
                                    root.cfg_longitude    = savedLocDelegateRoot.lon;
                                    if (savedLocDelegateRoot.altitude !== 0)
                                        root.cfg_altitude = savedLocDelegateRoot.altitude;
                                    if (savedLocDelegateRoot.timezone && savedLocDelegateRoot.timezone.length > 0)
                                        root.cfg_timezone = savedLocDelegateRoot.timezone;
                                    if (savedLocDelegateRoot.countryCode && savedLocDelegateRoot.countryCode.length > 0)
                                        root.cfg_countryCode = savedLocDelegateRoot.countryCode;
                                }

                                contentItem: RowLayout {
                                    id: savedLocContent
                                    spacing: Kirigami.Units.smallSpacing

                                    // ── Drag handle ─────
                                    Kirigami.ListItemDragHandle {
                                        id: dragHandle
                                        listItem: savedLocDelegate
                                        listView: savedLocList
                                        enabled: !savedLocDelegateRoot._renaming
                                        opacity: enabled ? 1.0 : 0.0
                                        onMoveRequested: function (oldIndex, newIndex) {
                                            if (oldIndex !== newIndex)
                                                savedLocWorkingModel.move(oldIndex, newIndex, 1);
                                        }
                                        onDropped: root._applySavedLocModel()
                                    }

                                    Kirigami.Icon {
                                        source: "mark-location"
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Label {
                                            Layout.fillWidth: true
                                            visible: !savedLocDelegateRoot._renaming
                                            text: savedLocDelegateRoot.name.length > 0 ? savedLocDelegateRoot.name : i18n("Unknown")
                                            elide: Text.ElideRight
                                            font.bold: savedLocDelegateRoot._isActive
                                            color: savedLocDelegateRoot._isActive ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                                        }
                                        TextField {
                                            id: renameField
                                            Layout.fillWidth: true
                                            visible: savedLocDelegateRoot._renaming
                                            onVisibleChanged: {
                                                if (visible) {
                                                    text = savedLocDelegateRoot.name;
                                                    selectAll();
                                                    forceActiveFocus();
                                                }
                                            }
                                            Keys.onReturnPressed: savedLocDelegateRoot._commitRename()
                                            Keys.onEscapePressed: savedLocDelegateRoot._renaming = false
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: {
                                                var parts = [savedLocDelegateRoot.lat.toFixed(4) + "°, " + savedLocDelegateRoot.lon.toFixed(4) + "°"];
                                                if (savedLocDelegateRoot.altitude !== 0)
                                                    parts.push(i18n("Alt: %1 m", savedLocDelegateRoot.altitude));
                                                if (savedLocDelegateRoot.timezone && savedLocDelegateRoot.timezone.length > 0)
                                                    parts.push(savedLocDelegateRoot.timezone);
                                                return parts.join("  ·  ");
                                            }
                                            opacity: 0.6
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // ── Star button (marks default; does NOT reorder) ──
                                    ToolButton {
                                        id: starButton
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                        display: AbstractButton.IconOnly
                                        visible: !savedLocDelegateRoot._renaming
                                        flat: true

                                        contentItem: Kirigami.Icon {
                                            source: savedLocDelegateRoot.starred ? "starred-symbolic" : "non-starred-symbolic"
                                            implicitWidth: Kirigami.Units.iconSizes.small
                                            implicitHeight: Kirigami.Units.iconSizes.small
                                            isMask: true
                                            color: savedLocDelegateRoot.starred ? "#f5c518" : Kirigami.Theme.textColor
                                        }
                                        background: Rectangle {
                                            radius: 3
                                            color: starButton.pressed
                                                ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3)
                                                : (starButton.hovered
                                                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                                                    : "transparent")
                                        }
                                        ToolTip.visible: hovered
                                        ToolTip.text: savedLocDelegateRoot.starred
                                            ? i18n("Default location (click to unset)")
                                            : i18n("Set as default location")
                                        onClicked: {
                                            var locs;
                                            try {
                                                locs = JSON.parse(root.cfg_savedLocations || "[]");
                                                if (!Array.isArray(locs)) locs = [];
                                            } catch (e) { locs = []; }
                                            var wasStarred = !!(locs[savedLocDelegateRoot.index] && locs[savedLocDelegateRoot.index].starred);
                                            for (var i = 0; i < locs.length; i++)
                                                delete locs[i].starred;
                                            if (!wasStarred && savedLocDelegateRoot.index >= 0 && savedLocDelegateRoot.index < locs.length)
                                                locs[savedLocDelegateRoot.index].starred = true;
                                            root.cfg_savedLocations = JSON.stringify(locs);
                                        }
                                    }

                                    // Rename buttons
                                    ToolButton {
                                        icon.name: "dialog-ok-apply"
                                        display: AbstractButton.IconOnly
                                        visible: savedLocDelegateRoot._renaming
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Confirm rename")
                                        onClicked: savedLocDelegateRoot._commitRename()
                                    }
                                    ToolButton {
                                        icon.name: "dialog-cancel"
                                        display: AbstractButton.IconOnly
                                        visible: savedLocDelegateRoot._renaming
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Cancel rename")
                                        onClicked: savedLocDelegateRoot._renaming = false
                                    }

                                    ToolButton {
                                        icon.name: "edit-rename"
                                        display: AbstractButton.IconOnly
                                        visible: !savedLocDelegateRoot._renaming
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Rename location")
                                        onClicked: savedLocDelegateRoot._renaming = true
                                    }

                                    // ── Settings: opens the Manual-entry sub-page
                                    // pre-populated with this entry's values. The
                                    // user edits name / lat / lon / altitude /
                                    // timezone and commits via KCM Apply.
                                    ToolButton {
                                        icon.name: "configure"
                                        display: AbstractButton.IconOnly
                                        visible: !savedLocDelegateRoot._renaming
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Edit location details")
                                        onClicked: {
                                            root.openManualPageForEdit({
                                                name:        savedLocDelegateRoot.name,
                                                lat:         savedLocDelegateRoot.lat,
                                                lon:         savedLocDelegateRoot.lon,
                                                altitude:    savedLocDelegateRoot.altitude,
                                                timezone:    savedLocDelegateRoot.timezone,
                                                countryCode: savedLocDelegateRoot.countryCode
                                            }, savedLocDelegateRoot.index);
                                        }
                                    }

                                    ToolButton {
                                        icon.name: "edit-delete"
                                        display: AbstractButton.IconOnly
                                        visible: !savedLocDelegateRoot._renaming
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Remove saved location")
                                        onClicked: {
                                            var locs;
                                            try {
                                                locs = JSON.parse(root.cfg_savedLocations || "[]");
                                                if (!Array.isArray(locs)) locs = [];
                                            } catch (e) { locs = []; }
                                            if (locs.length === 1) {
                                                root._deleteLocIndex = savedLocDelegateRoot.index;
                                                deleteLastLocDialog.open();
                                            } else {
                                                locs.splice(savedLocDelegateRoot.index, 1);
                                                root.cfg_savedLocations = JSON.stringify(locs);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.locationCheckState === 2
                        type: Kirigami.MessageType.Positive
                        text: root.locationCheckMessage
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.locationCheckState === 3
                        type: Kirigami.MessageType.Error
                        text: root.locationCheckMessage
                    }

                    Item {
                        Layout.preferredHeight: Kirigami.Units.largeSpacing
                    }
                } // ColumnLayout
            } // ScrollView
        }
    }

    Component {
        id: searchSubPage
        ConfigLocationSubPage {
            configRoot: root
        }
    }

    Component {
        id: mapSubPage
        ConfigMapSubPage {
            configRoot: root
        }
    }

    Component {
        id: manualSubPage
        ConfigLocationManualSubPage {
            configRoot: root
        }
    }
}
