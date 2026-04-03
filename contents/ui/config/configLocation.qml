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
            cfg_autoDetectLocation = true
    }

    property bool   cfg_autoDetectLocation: true
    property string cfg_locationName: ""
    property real   cfg_latitude: 0.0
    property real   cfg_longitude: 0.0
    property int    cfg_altitude: 0
    property string cfg_timezone: ""
    property string cfg_countryCode: ""
    property string cfg_altitudeUnit: "m"
    property string cfg_weatherProvider: "adaptive"

    property bool   autoDetectBusy: false
    property string autoDetectStatus: ""

    property string detectedLocationName: ""
    property real   detectedLatitude: 0.0
    property real   detectedLongitude: 0.0
    property int    detectedAltitude: 0
    property string detectedTimezone: ""
    property string detectedCountryCode: ""
    property bool   showDetectedLocationDialog: false
    // Set to true once the user clicks "Apply" in the confirm dialog.
    // Allows late-arriving metadata (timezone, elevation) from Open-Meteo
    // to be written directly to Plasmoid.configuration.
    property bool   _detectedLocationApplied: false

    // Always show the confirmation dialog when auto-detecting via the
    // config UI so the user can review the detected place before it is saved.
    property bool _forceConfirmAutoDetect: false

    function shouldConfirmAutoDetectedLocation() {
        return _forceConfirmAutoDetect
               || (!cfg_locationName || cfg_locationName.length === 0)
    }
    function stageDetectedLocation(lat, lon, altitude, timezone, name) {
        _detectedLocationApplied = false
        detectedLatitude = lat; detectedLongitude = lon
        if (!isNaN(altitude)) detectedAltitude = Math.round(altitude)
        if (timezone && timezone.length > 0) detectedTimezone = timezone
        if (name && name.length > 0) detectedLocationName = name
    }
    function applyDetectedLocation() {
        // Apply even if name isn't available yet — coordinates are enough for weather
        showDetectedLocationDialog = false
        _forceConfirmAutoDetect = false
        _detectedLocationApplied = true
        Plasmoid.configuration.autoDetectLocation = true
        Plasmoid.configuration.latitude   = detectedLatitude
        Plasmoid.configuration.longitude  = detectedLongitude
        if (detectedTimezone && detectedTimezone.length > 0)
            Plasmoid.configuration.timezone = detectedTimezone
        if (!isNaN(detectedAltitude) && detectedAltitude !== 0)
            Plasmoid.configuration.altitude = detectedAltitude
        if (detectedLocationName && detectedLocationName.length > 0)
            Plasmoid.configuration.locationName = detectedLocationName
        if (detectedCountryCode && detectedCountryCode.length > 0)
            Plasmoid.configuration.countryCode = detectedCountryCode
        // Sync cfg_ back so the config dialog display stays consistent
        cfg_autoDetectLocation = Plasmoid.configuration.autoDetectLocation
        cfg_latitude           = Plasmoid.configuration.latitude
        cfg_longitude          = Plasmoid.configuration.longitude
        cfg_timezone           = Plasmoid.configuration.timezone
        cfg_altitude           = Plasmoid.configuration.altitude
        cfg_locationName       = Plasmoid.configuration.locationName
        cfg_countryCode        = Plasmoid.configuration.countryCode

        // Verify the detected location is available on the current provider
        verifyProviderLocation(detectedLatitude, detectedLongitude)
    }
    function chooseManualLocation() {
        _forceConfirmAutoDetect = false
        cfg_autoDetectLocation = false; showDetectedLocationDialog = false; openSearchPage()
    }

    property string preferredLanguage: Qt.locale().name.split("_")[0]
    readonly property string bundledOpenWeatherApiKey: "8003225e8825db83758c237068447229"
    readonly property string bundledWeatherApiKey: "601ba4ac57404ec29ff120510261802"
    function displayAltitudeUnit() { return cfg_altitudeUnit === "ft" ? "feet" : "meters" }

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
            if (!owKey) { locationCheckState = 0; return; }
            url = "https://api.openweathermap.org/data/2.5/weather?lat="
                + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon)
                + "&units=metric&appid=" + encodeURIComponent(owKey);
        } else if (provider === "weatherApi") {
            var waKey = (Plasmoid.configuration.waApiKey || "").trim();
            if (!waKey) { locationCheckState = 0; return; }
            url = "https://api.weatherapi.com/v1/current.json?key="
                + encodeURIComponent(waKey)
                + "&q=" + encodeURIComponent(lat + "," + lon);
        } else if (provider === "metno") {
            url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat="
                + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon);
        } else {
            locationCheckState = 0;
            return;
        }
        req.open("GET", url);
        if (provider === "metno")
            req.setRequestHeader("User-Agent",
                "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
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
        if (p === "openWeather") return "OpenWeatherMap";
        if (p === "weatherApi") return "WeatherAPI.com";
        if (p === "metno") return "met.no";
        return "Open-Meteo";
    }

    // Returns "(GMT +2)" / "(GMT -5:30)" for any IANA timezone identifier.
    // We compute the UTC offset by formatting the same Date in the target timezone
    // and in UTC using basic hour+minute parts — this works in Qt 6's V4+ICU
    // without needing timeZoneName:"shortOffset" (ES2021, not guaranteed available).
    function gmtOffsetLabel(tzId) {
        if (!tzId || tzId.length === 0) return ""
        try {
            var now  = new Date()
            // Helper: get total minutes-since-midnight for a given timezone
            function totalMins(tz) {
                var parts = new Intl.DateTimeFormat("en-US", {
                    timeZone:  tz,
                    hour:      "numeric",
                    minute:    "numeric",
                    hour12:    false
                }).formatToParts(now)
                var h = 0, m = 0
                for (var i = 0; i < parts.length; ++i) {
                    if (parts[i].type === "hour")   h = parseInt(parts[i].value, 10)
                    if (parts[i].type === "minute") m = parseInt(parts[i].value, 10)
                }
                return h * 60 + m
            }
            var diff = totalMins(tzId) - totalMins("UTC")
            // Clamp across midnight boundaries (diff can be ±1439)
            if (diff >  720) diff -= 1440
            if (diff < -720) diff += 1440
            var sign  = diff >= 0 ? "+" : "-"
            var abs   = Math.abs(diff)
            var h     = Math.floor(abs / 60)
            var m     = abs % 60
            var label = m === 0
                        ? "GMT " + sign + h
                        : "GMT " + sign + h + ":" + (m < 10 ? "0" + m : String(m))
            return "(" + label + ")"
        } catch(e) { return "" }
    }

    function formatResultTitle(item) {
        if (!item) return ""
        if (item.localizedDisplayName && item.localizedDisplayName.length > 0) return item.localizedDisplayName
        var admin   = item.admin1  ? ", " + item.admin1  : ""
        var country = item.country ? ", " + item.country : ""
        var first   = item.name   ? item.name            : ""
        return first.length > 0 ? first + admin + country : (item.display_name ? item.display_name : "")
    }
    function formatResultListItem(item) {
        return formatResultTitle(item)
    }
    function selectedProviderDisplayName() {
        if (cfg_weatherProvider === "adaptive")    return "Adaptive"
        if (cfg_weatherProvider === "openWeather") return "OpenWeather"
        if (cfg_weatherProvider === "weatherApi")  return "WeatherAPI.com"
        if (cfg_weatherProvider === "metno")       return "met.no"
        return "Open-Meteo"
    }
    function currentLocationDisplayName() {
        return cfg_locationName && cfg_locationName.length > 0 ? cfg_locationName : i18n("None Selected")
    }
    function openSearchPage() {
        stack.push(searchSubPage)
    }

    function reverseGeocode(lat, lon) {
        stageDetectedLocation(lat, lon, NaN, "", "")
        var metaReq = new XMLHttpRequest()
        metaReq.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(lat)
            + "&longitude=" + encodeURIComponent(lon) + "&current=temperature_2m&timezone=auto")
        metaReq.onreadystatechange = function() {
            if (metaReq.readyState !== XMLHttpRequest.DONE) return
            if (metaReq.status === 200) {
                var meta = JSON.parse(metaReq.responseText)
                if (root._detectedLocationApplied) {
                    // The user already clicked "Apply" before this response
                    // arrived — write directly to config so it’s not lost.
                    if (meta.timezone && meta.timezone.length > 0) {
                        cfg_timezone = meta.timezone
                        Plasmoid.configuration.timezone = meta.timezone
                    }
                    if (meta.elevation !== undefined && !isNaN(meta.elevation)) {
                        cfg_altitude = Math.round(meta.elevation)
                        Plasmoid.configuration.altitude = Math.round(meta.elevation)
                    }
                } else if (shouldConfirmAutoDetectedLocation()) {
                    if (meta.timezone) root.detectedTimezone = meta.timezone
                    if (meta.elevation !== undefined && !isNaN(meta.elevation)) root.detectedAltitude = Math.round(meta.elevation)
                } else {
                    // Persist directly so the widget sees the new values even
                    // if the config dialog is closed before this callback fires.
                    if (meta.timezone) {
                        cfg_timezone = meta.timezone
                        Plasmoid.configuration.timezone = meta.timezone
                    }
                    if (meta.elevation !== undefined && !isNaN(meta.elevation)) {
                        cfg_altitude = Math.round(meta.elevation)
                        Plasmoid.configuration.altitude = Math.round(meta.elevation)
                    }
                }
            }
        }
        metaReq.send()
        var req = new XMLHttpRequest()
        // accept-language must NOT be percent-encoded (commas are syntactically significant)
        var revLang = preferredLanguage.length > 0 ? preferredLanguage + ",en;q=0.8" : "en"
        req.open("GET", "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&addressdetails=1"
            + "&accept-language=" + revLang
            + "&lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon))
        req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)")
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (req.status === 200) {
                var data = JSON.parse(req.responseText)
                if (data && data.address) {
                    var a = data.address
                    // Extended fallback chain — matches forward-search logic
                    var city = a.city || a.town || a.village || a.hamlet
                             || a.suburb || a.municipality || a.county || ""
                    var country = a.country || ""
                    var name
                    if (city.length > 0 && country.length > 0)
                        name = city + ", " + country
                    else if (city.length > 0)
                        name = city
                    else if (country.length > 0)
                        name = country
                    else
                        name = data.display_name || ""   // last-resort fallback

                    if (name.length > 0) {
                        if (shouldConfirmAutoDetectedLocation()) {
                            root.detectedLocationName = name
                            root.showDetectedLocationDialog = true
                        } else {
                            cfg_locationName = name
                            Plasmoid.configuration.locationName = name
                        }
                    }
                    // Capture country code for MeteoAlarm alerts
                    var cc = (a.country_code || "").toUpperCase()
                    if (cc.length > 0) {
                        if (shouldConfirmAutoDetectedLocation()) {
                            root.detectedCountryCode = cc
                        } else {
                            cfg_countryCode = cc
                            Plasmoid.configuration.countryCode = cc
                        }
                    }
                }
                autoDetectStatus = i18n("Location auto-detected.")
            } else { autoDetectStatus = i18n("Auto-detection updated coordinates.") }
            autoDetectBusy = false
        }
        req.send()
    }

    // ── 3-tier auto-detection ───────────────────────────────────────────
    // Tier 1: GeoClue2 explicitly
    // Tier 2: Any available Qt Positioning plugin
    // Tier 3: IP geolocation (geo.kamero.ai → reallyfreegeoip.org)
    // Which tier is active: 0 = idle, 1 = geoclue2, 2 = generic, 3 = IP
    property int _cfgLocationTier: 0

    function _cfgHandlePosition(lat, lon, alt, tierLabel) {
        // Deactivate sources after successful fix to avoid duplicate callbacks
        cfgGeoclue2Source.active = false
        cfgGenericSource.active = false
        if (root.shouldConfirmAutoDetectedLocation()) {
            root.stageDetectedLocation(lat, lon, alt, "", "")
        } else {
            root.cfg_latitude   = lat
            root.cfg_longitude  = lon
            Plasmoid.configuration.latitude  = lat
            Plasmoid.configuration.longitude = lon
            if (!isNaN(alt) && alt > 0) {
                root.cfg_altitude = Math.round(alt)
                Plasmoid.configuration.altitude = Math.round(alt)
            }
        }
        autoDetectStatus = i18n("Requesting location… (%1)", tierLabel)
        root.reverseGeocode(lat, lon)
    }

    function refreshAutoDetectedLocation() {
        if (!cfg_autoDetectLocation) { autoDetectBusy = false; return }
        autoDetectBusy = true
        _cfgLocationTier = 1
        autoDetectStatus = i18n("Requesting location via GeoClue2…")
        cfgGeoclue2Source.active = true
        cfgGeoclue2Source.update()
        _cfgGeoclue2Timer.restart()
    }

    function _cfgEscalateToGeneric() {
        cfgGeoclue2Source.active = false
        _cfgLocationTier = 2
        autoDetectStatus = i18n("GeoClue2 unavailable, trying system location…")
        cfgGenericSource.active = true
        cfgGenericSource.update()
        _cfgGenericTimer.restart()
    }

    function _cfgEscalateToIpGeo() {
        cfgGenericSource.active = false
        _cfgLocationTier = 3
        autoDetectStatus = i18n("System location unavailable, trying IP geolocation…")
        _cfgIpGeolocate()
    }

    Timer {
        id: _cfgGeoclue2Timer; interval: 8000; repeat: false
        onTriggered: {
            if (_cfgLocationTier === 1) {
                console.log("[Location/config] GeoClue2 timed out, trying generic…")
                _cfgEscalateToGeneric()
            }
        }
    }
    Timer {
        id: _cfgGenericTimer; interval: 8000; repeat: false
        onTriggered: {
            if (_cfgLocationTier === 2) {
                console.log("[Location/config] Generic source timed out, trying IP…")
                _cfgEscalateToIpGeo()
            }
        }
    }

    Timer {
        id: _cfgIpGeoTimer; interval: 10000; repeat: false
        property var _activeReq: null
        onTriggered: {
            if (_cfgLocationTier === 3 && _activeReq) {
                console.warn("[Location/config] Tier 3 IP geolocation timed out")
                _activeReq.abort()
                _activeReq = null
                _cfgLocationTier = 0
                autoDetectBusy = false
                autoDetectStatus = i18n("Unable to detect location. All methods failed.")
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
            if (!root.cfg_autoDetectLocation) return
            var c = position.coordinate
            if (!c || !c.isValid) return
            _cfgGeoclue2Timer.stop()
            _cfgLocationTier = 0
            console.log("[Location/config] Tier 1 (GeoClue2): position acquired")
            _cfgHandlePosition(c.latitude, c.longitude, c.altitude, "GeoClue2")
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && _cfgLocationTier === 1) {
                console.log("[Location/config] Tier 1 (GeoClue2) error:", sourceError)
                _cfgGeoclue2Timer.stop()
                _cfgEscalateToGeneric()
            }
        }
    }

    // Tier 2 — any available Qt Positioning plugin
    PositionSource {
        id: cfgGenericSource
        active: false
        updateInterval: 300000
        onPositionChanged: {
            if (!root.cfg_autoDetectLocation) return
            var c = position.coordinate
            if (!c || !c.isValid) return
            _cfgGenericTimer.stop()
            _cfgLocationTier = 0
            console.log("[Location/config] Tier 2 (generic): position acquired")
            _cfgHandlePosition(c.latitude, c.longitude, c.altitude, i18n("system location"))
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && _cfgLocationTier === 2) {
                console.log("[Location/config] Tier 2 (generic) error:", sourceError)
                _cfgGenericTimer.stop()
                _cfgEscalateToIpGeo()
            }
        }
    }

    // Tier 3 — IP-based geolocation
    function _cfgIpGeolocate() {
        console.log("[Location/config] Tier 3: trying geo.kamero.ai…")
        var req = new XMLHttpRequest()
        _cfgIpGeoTimer._activeReq = req
        _cfgIpGeoTimer.restart()
        req.open("GET", "https://geo.kamero.ai/api/geo")
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (req.status === 200) {
                try {
                    var data = JSON.parse(req.responseText)
                    var lat = parseFloat(data.latitude)
                    var lon = parseFloat(data.longitude)
                    if (!isNaN(lat) && !isNaN(lon)) {
                        _cfgIpGeoTimer.stop()
                        _cfgIpGeoTimer._activeReq = null
                        _cfgLocationTier = 0
                        console.log("[Location/config] Tier 3 (geo.kamero.ai): position acquired")
                        _cfgHandlePosition(lat, lon, NaN, i18n("IP geolocation"))
                        return
                    }
                } catch (e) { console.warn("[Location/config] geo.kamero.ai parse error:", e) }
            }
            _cfgIpGeolocateFallback()
        }
        req.send()
    }

    function _cfgIpGeolocateFallback() {
        console.log("[Location/config] Tier 3 fallback: trying reallyfreegeoip.org…")
        var req = new XMLHttpRequest()
        _cfgIpGeoTimer._activeReq = req
        _cfgIpGeoTimer.restart()
        req.open("GET", "https://reallyfreegeoip.org/json/")
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return
            _cfgIpGeoTimer.stop()
            _cfgIpGeoTimer._activeReq = null
            if (req.status === 200) {
                try {
                    var data = JSON.parse(req.responseText)
                    var lat = parseFloat(data.latitude)
                    var lon = parseFloat(data.longitude)
                    if (!isNaN(lat) && !isNaN(lon)) {
                        _cfgLocationTier = 0
                        console.log("[Location/config] Tier 3 (reallyfreegeoip): position acquired")
                        _cfgHandlePosition(lat, lon, NaN, i18n("IP geolocation"))
                        return
                    }
                } catch (e) { console.warn("[Location/config] reallyfreegeoip parse error:", e) }
            }
            _cfgLocationTier = 0
            autoDetectBusy = false
            autoDetectStatus = i18n("Unable to detect location. All methods failed.")
            console.warn("[Location/config] All 3 tiers failed")
        }
        req.send()
    }

    function applySearchResult(item) {
        if (!item) return
        // For Nominatim (OSM) results: use localizedDisplayName directly.
        // It is the raw display_name from OSM — already fully localised and
        // containing every address level (city → district → state → country).
        // Example: "Царевци, Омуртаг, Търговище, България"
        //
        // For Open-Meteo results: build from the individual fields because
        // Open-Meteo's geocoder only returns name/admin1/country.
        if (item.providerKey === "nominatim" && item.localizedDisplayName && item.localizedDisplayName.length > 0) {
            cfg_locationName = item.localizedDisplayName
        } else {
            var nameParts = []
            if (item.name    && item.name.length    > 0) nameParts.push(item.name)
            if (item.district && item.district.length > 0
                    && item.district.toLowerCase() !== (item.name || "").toLowerCase())
                nameParts.push(item.district)
            if (item.admin1  && item.admin1.length  > 0
                    && item.admin1.toLowerCase() !== (item.name || "").toLowerCase())
                nameParts.push(item.admin1)
            if (item.country && item.country.length > 0) nameParts.push(item.country)
            cfg_locationName = nameParts.length > 0 ? nameParts.join(", ") : (item.localizedDisplayName || "")
        }
        // Full-precision coordinates
        cfg_latitude  = parseFloat(item.latitude)
        cfg_longitude = parseFloat(item.longitude)
        cfg_timezone  = item.timezone ? item.timezone : cfg_timezone

        // Country code for MeteoAlarm alerts
        if (item.countryCode && item.countryCode.length > 0)
            cfg_countryCode = item.countryCode.toUpperCase()

        // Always fetch accurate elevation from Open-Meteo elevation API.
        // Nominatim does not return elevation at all; Open-Meteo geocoder
        // returns elevation only for its own results.  The dedicated
        // elevation endpoint is accurate for all coordinate pairs.
        var lat = parseFloat(item.latitude)
        var lon = parseFloat(item.longitude)
        var elevReq = new XMLHttpRequest()
        elevReq.open("GET", "https://api.open-meteo.com/v1/elevation?latitude="
                     + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon))
        elevReq.onreadystatechange = function() {
            if (elevReq.readyState !== XMLHttpRequest.DONE) return
            if (elevReq.status === 200) {
                var data = JSON.parse(elevReq.responseText)
                // Response: { "elevation": [123.4] }
                if (data.elevation && data.elevation.length > 0 && !isNaN(data.elevation[0])) {
                    cfg_altitude = Math.round(data.elevation[0])
                }
            }
        }
        elevReq.send()

        // Always fetch timezone from Open-Meteo when a new location is selected.
        // Do NOT guard with "if (!cfg_timezone)" — the old location's timezone
        // would satisfy that check and the stale value would never be updated.
        var tzReq = new XMLHttpRequest()
        tzReq.open("GET", "https://api.open-meteo.com/v1/forecast?latitude="
                   + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon)
                   + "&current=temperature_2m&timezone=auto")
        tzReq.onreadystatechange = function() {
            if (tzReq.readyState !== XMLHttpRequest.DONE) return
            if (tzReq.status === 200) {
                var meta = JSON.parse(tzReq.responseText)
                if (meta.timezone && meta.timezone.length > 0)
                    cfg_timezone = meta.timezone
            }
        }
        tzReq.send()

        // Verify the new location is available on the current provider
        verifyProviderLocation(lat, lon)
    }

    onCfg_autoDetectLocationChanged: {
        if (cfg_autoDetectLocation) refreshAutoDetectedLocation()
        else {
            autoDetectBusy = false; autoDetectStatus = ""
            cfgGeoclue2Source.active = false
            cfgGenericSource.active = false
            _cfgLocationTier = 0
        }
    }

    Kirigami.Dialog {
        id: detectedLocationDialog
        title: i18n("Confirm your location")
        standardButtons: Kirigami.Dialog.NoButton
        leftPadding: Kirigami.Units.gridUnit * 2; rightPadding: Kirigami.Units.gridUnit * 2
        topPadding: Kirigami.Units.gridUnit;      bottomPadding: Kirigami.Units.gridUnit
        onClosed: { root.showDetectedLocationDialog = false; root._forceConfirmAutoDetect = false }
        contentItem: Item {
            implicitWidth: 420; implicitHeight: contentCol.implicitHeight 
            ColumnLayout {
                id: contentCol
                anchors.left: parent.left; anchors.right: parent.right
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter; source: "mark-location"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; textFormat: Text.RichText
                    text: root.detectedLocationName && root.detectedLocationName.length > 0
                          ? (i18n("We detected your location as: <b>%1</b>.").arg(root.detectedLocationName))
                          : i18n("We detected your coordinates: <b>%1°, %2°</b>.").arg(
                                root.detectedLatitude.toFixed(4)).arg(root.detectedLongitude.toFixed(4))
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; opacity: 0.75
                    text: i18n("If this looks correct, apply it. Otherwise, choose your location manually.")
                }
                Item { Layout.preferredHeight: Kirigami.Units.largeSpacing }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Kirigami.Units.mediumSpacing
                    Button { text: i18n("Set manually"); icon.name: "edit-find"; onClicked: root.chooseManualLocation() }
                    Button {
                        text: i18n("Apply detected location"); icon.name: "dialog-ok-apply"
                        enabled: root.detectedLatitude !== 0.0 || root.detectedLongitude !== 0.0
                        onClicked: root.applyDetectedLocation()
                    }
                }
                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
            }
        }
    }

    onShowDetectedLocationDialogChanged: {
        if (showDetectedLocationDialog) detectedLocationDialog.open()
        else detectedLocationDialog.close()
    }

    // ══════════════════════════════════════════════════════════════════════
    StackView {
        id: stack
        anchors.fill: parent
        initialItem: mainPage
    }

    Component {
        id: mainPage
        Item {
            ColumnLayout {
                anchors.fill: parent; spacing: 10

                ButtonGroup { id: locationModeGroup }

                // ── Auto-detect radio ──────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4

                    RadioButton {
                        text: i18n("Automatically detect location")
                        checked: root.cfg_autoDetectLocation
                        ButtonGroup.group: locationModeGroup
                        onClicked: { root._forceConfirmAutoDetect = true; root.cfg_autoDetectLocation = true }
                    }
                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 24; spacing: 8
                        Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.78
                            text: root.autoDetectBusy ? i18n("Detecting…")
                                  : (root.autoDetectStatus.length > 0 ? root.autoDetectStatus
                                  : i18n("Location detection is depending on system configuration and permissions."))
                        }
                        Button {
                            text: i18n("Refresh"); visible: root.cfg_autoDetectLocation
                            enabled: root.cfg_autoDetectLocation && !root.autoDetectBusy
                            onClicked: { root._forceConfirmAutoDetect = true; root.refreshAutoDetectedLocation() }
                        }
                    }

                    // ── Manual radio with inline Change Location button ─
                    Item { Layout.preferredHeight: 4 }
                    RadioButton {
                        text: i18n("Use manual location")
                        checked: !root.cfg_autoDetectLocation
                        ButtonGroup.group: locationModeGroup
                        onClicked: root.cfg_autoDetectLocation = false
                    }
                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 24; spacing: 8
                        visible: !root.cfg_autoDetectLocation
                        Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.78
                            text: i18n("Click \'Change Location\' to search and set your location manually.")
                        }
                        Button {
                            text: i18n("Change Location")
                            enabled: !root.cfg_autoDetectLocation
                            onClicked: root.openSearchPage()
                        }
                    }
                }

                // ── Location information section header ─────────────────
                Item { Layout.preferredHeight: 4 }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Kirigami.Heading {
                        text: i18n("Location information")
                        level: 4
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 1
                        color: Kirigami.Theme.separatorColor
                        opacity: 0.6
                    }
                }

                // ── Location fields (read-only display) ─────────────────
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2; columnSpacing: 10; rowSpacing: 8

                    Label { text: i18n("Location name:") }
                    TextField {
                        Layout.fillWidth: true
                        id: locationNameField
                        text: root.cfg_locationName
                        readOnly: true
                        background: Rectangle {
                            color: Qt.rgba(0.5, 0.5, 0.5, 0.15)
                            border.color: Qt.rgba(0.5, 0.5, 0.5, 0.35)
                            border.width: 1; radius: 4
                        }
                    }

                    Label { text: i18n("Latitude:") }
                    TextField {
                        Layout.fillWidth: true
                        id: latField
                        text: {
                            var v = root.cfg_latitude
                            if (v === 0.0) return "0°"
                            return v.toFixed(7).replace(/\.?0+$/, "") + "°"
                        }
                        readOnly: true
                        background: Rectangle {
                            color: Qt.rgba(0.5, 0.5, 0.5, 0.15)
                            border.color: Qt.rgba(0.5, 0.5, 0.5, 0.35)
                            border.width: 1; radius: 4
                        }
                    }

                    Label { text: i18n("Longitude:") }
                    TextField {
                        Layout.fillWidth: true
                        id: lonField
                        text: {
                            var v = root.cfg_longitude
                            if (v === 0.0) return "0°"
                            return v.toFixed(7).replace(/\.?0+$/, "") + "°"
                        }
                        readOnly: true
                        background: Rectangle {
                            color: Qt.rgba(0.5, 0.5, 0.5, 0.15)
                            border.color: Qt.rgba(0.5, 0.5, 0.5, 0.35)
                            border.width: 1; radius: 4
                        }
                    }

                    Label { text: i18n("Altitude:") }
                    TextField {
                        Layout.fillWidth: true
                        id: altField
                        text: root.cfg_altitude + " m"
                        readOnly: true
                        background: Rectangle {
                            color: Qt.rgba(0.5, 0.5, 0.5, 0.15)
                            border.color: Qt.rgba(0.5, 0.5, 0.5, 0.35)
                            border.width: 1; radius: 4
                        }
                    }

                    Label { text: i18n("Timezone:") }
                    TextField {
                        Layout.fillWidth: true
                        id: timezoneField
                        text: {
                            var tz = root.cfg_timezone
                            if (!tz || tz.length === 0) return ""
                            var offset = root.gmtOffsetLabel(tz)
                            return offset.length > 0 ? tz + " " + offset : tz
                        }
                        readOnly: true
                        background: Rectangle {
                            color: Qt.rgba(0.5, 0.5, 0.5, 0.15)
                            border.color: Qt.rgba(0.5, 0.5, 0.5, 0.35)
                            border.width: 1; radius: 4
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

                Item { Layout.fillHeight: true }
            }
        }
    }

    Component {
        id: searchSubPage
        ConfigLocationSubPage {
            configRoot: root
        }
    }
}
