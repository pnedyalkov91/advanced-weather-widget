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

/**
 * ConfigMapSubPage - Pick a location on an interactive OSM map.
 * Requires: required property var configRoot
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: mapSubPageRoot
    required property var configRoot
    spacing: 0

    // ── Selected location state ─────────────────────────────────────────
    property string selectedName: ""
    property real selectedLat: NaN
    property real selectedLon: NaN
    property int selectedAltitude: 0
    property string selectedTimezone: ""
    property string selectedCountryCode: ""
    property bool lookupBusy: false
    property int _reqId: 0
    property real selectedTemperature: NaN
    property int selectedWeatherCode: -1
    property string selectedTemperatureUnit: "°C"

    // ── Map search state ────────────────────────────────────────────────
    property var _mapSearchResults: []
    property bool _mapSearchBusy: false
    property int _mapSearchReqId: 0
    property int _searchMode: 0   // 0 = Location name, 1 = Coordinates
    property string _mapError: ""

    function _applyToConfig() {
        if (isNaN(selectedLat) || isNaN(selectedLon))
            return;

        var locs;
        try {
            locs = JSON.parse(configRoot.cfg_savedLocations || "[]");
            if (!Array.isArray(locs)) locs = [];
        } catch (e) { locs = []; }
        var isDup = locs.some(function(l) {
            return Math.abs(l.lat - selectedLat) < 0.01 && Math.abs(l.lon - selectedLon) < 0.01;
        });

        // Always stage to cfg_* so KCM Apply becomes active
        configRoot.cfg_autoDetectLocation = false;
        configRoot.cfg_latitude = selectedLat;
        configRoot.cfg_longitude = selectedLon;
        if (selectedName.length > 0) configRoot.cfg_locationName = selectedName;
        if (selectedAltitude !== 0) configRoot.cfg_altitude = selectedAltitude;
        if (selectedTimezone.length > 0) configRoot.cfg_timezone = selectedTimezone;
        if (selectedCountryCode.length > 0) configRoot.cfg_countryCode = selectedCountryCode;
        configRoot.verifyProviderLocation(selectedLat, selectedLon);

        if (!isDup) {
            configRoot.duplicateWarning = "";
            // Store pending - saved on KCM Apply via save() in configLocation.qml
            var entryName = selectedName.length > 0
                ? selectedName : (selectedLat.toFixed(4) + "°, " + selectedLon.toFixed(4) + "°");
            configRoot._pendingEntry = {
                name: entryName,
                lat: selectedLat,
                lon: selectedLon,
                altitude: selectedAltitude || 0,
                timezone: selectedTimezone || "",
                countryCode: selectedCountryCode || ""
            };
        } else {
            configRoot._pendingEntry = null;
            configRoot.duplicateWarning = i18n("Location '%1' is already in your saved list. You can apply the selected location, but it will not be saved again.", selectedName);
            if (configRoot.duplicateDialog)
                configRoot.duplicateDialog.open();
        }
    }

    // Open the map at a spot: move the pin and zoom in to at least minZoom (0 = keep the view).
    // Does nothing while the map page is not there (QtWebEngine missing, still loading, offline).
    function _mapShow(lat, lon, minZoom) {
        if (mapLoader.item)
            mapLoader.item.setMarker(lat, lon, minZoom);
    }

    // Name of the place under a map click, "name, county, state, country" like the location
    // search and the auto-detect (a part equal to an earlier one is skipped). A "place" result
    // (city, town, village...) is the settlement itself. For a street, a shop, a metro entrance
    // and so on Photon's "name" belongs to that object, not to the location, so it is left out
    // and the settlement comes from "city" when Photon provides it.
    function _photonReverseName(pr) {
        var fix = configRoot._fixMixedScript;
        var isPlace = pr.osm_key === "place" || pr.osm_key === "boundary";
        var parts = [];
        [pr.city || (isPlace ? pr.name : ""), pr.county, pr.state, pr.country].forEach(function (part) {
            part = fix(part);
            if (part.length > 0 && parts.every(function (x) {
                return x.toLowerCase() !== part.toLowerCase();
            }))
                parts.push(part);
        });
        return parts.length > 0 ? parts.join(", ") : fix(pr.locality || pr.district || pr.name || "");
    }

    // Title of a search result: "name, city, county, state, country" (city helps tell streets and
    // landmarks apart; a part equal to an earlier one is skipped).
    function _photonTitle(pr) {
        var fix = configRoot._fixMixedScript;
        var parts = [];
        [pr.name, pr.city, pr.county, pr.state, pr.country].forEach(function (part) {
            part = fix(part);
            if (part.length > 0 && parts.every(function (x) {
                return x.toLowerCase() !== part.toLowerCase();
            }))
                parts.push(part);
        });
        return parts.join(", ");
    }

    function _lookupLocation(lat, lon, preset) {
        selectedLat = lat;
        selectedLon = lon;
        selectedName = "";
        selectedAltitude = 0;
        selectedTimezone = "";
        selectedCountryCode = "";
        selectedTemperature = NaN;
        selectedWeatherCode = -1;
        lookupBusy = true;
        var reqId = ++_reqId;

        // Move marker
        _mapShow(lat, lon, 0);

        // 1) Name and country code. A picked search result already carries both (preset),
        //    otherwise reverse geocode the point via Photon (OpenStreetMap data).
        //    lang=default: local-language names, the same as the location search.
        if (preset) {
            selectedName = preset.name || "";
            if (preset.countryCode && preset.countryCode.length > 0)
                selectedCountryCode = preset.countryCode;
        } else {
            var revReq = new XMLHttpRequest();
            var revUrl = "https://photon.komoot.io/reverse?lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon) + "&radius=20&limit=1&lang=default";
            console.warn("[LocationSearch] Map Photon reverse GET " + revUrl);
            revReq.open("GET", revUrl);
            revReq.onreadystatechange = function () {
                if (revReq.readyState !== XMLHttpRequest.DONE)
                    return;
                if (reqId !== _reqId)
                    return;
                console.warn("[LocationSearch] Map Photon reverse HTTP " + revReq.status + " " + revReq.statusText);
                if (revReq.status === 200) {
                    try {
                        var feats = JSON.parse(revReq.responseText).features || [];
                        if (feats.length > 0) {
                            var pr = feats[0].properties || {};
                            selectedName = mapSubPageRoot._photonReverseName(pr);
                            var cc = (pr.countrycode || "").toUpperCase();
                            if (cc.length > 0)
                                selectedCountryCode = cc;
                            console.warn("[LocationSearch] Map Photon reverse name: " + selectedName);
                        }
                    } catch (e) {
                        console.warn("[MapSubPage] Photon reverse parse error:", e);
                    }
                } else {
                    console.warn("[LocationSearch] Map Photon reverse body: " + String(revReq.responseText).substring(0, 300));
                }
                _checkDone();
            };
            revReq.send();
        }

        // 2) Elevation + timezone via Open-Meteo
        var metaReq = new XMLHttpRequest();
        metaReq.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon) + "&current=temperature_2m,weather_code&timezone=auto");
        metaReq.onreadystatechange = function () {
            if (metaReq.readyState !== XMLHttpRequest.DONE)
                return;
            if (reqId !== _reqId)
                return;
            if (metaReq.status === 200) {
                try {
                    var meta = JSON.parse(metaReq.responseText);
                    if (meta.timezone && meta.timezone.length > 0)
                        selectedTimezone = meta.timezone;
                    if (meta.elevation !== undefined && !isNaN(meta.elevation))
                        selectedAltitude = Math.round(meta.elevation);
                    if (meta.current) {
                        if (meta.current.temperature_2m !== undefined)
                            selectedTemperature = meta.current.temperature_2m;
                        if (meta.current.weather_code !== undefined)
                            selectedWeatherCode = meta.current.weather_code;
                    }
                    if (meta.current_units && meta.current_units.temperature_2m)
                        selectedTemperatureUnit = meta.current_units.temperature_2m;
                } catch (e) { /* ignore */ }
            }
            _checkDone();
        };
        metaReq.send();

        var _pending = preset ? 1 : 2;   // Open-Meteo, plus the reverse lookup unless a name was given
        function _checkDone() {
            if (--_pending <= 0) {
                // Fallback: if still no name, show coordinates
                if (selectedName.length === 0)
                    selectedName = lat.toFixed(4) + "°, " + lon.toFixed(4) + "°";
                lookupBusy = false;
                mapSubPageRoot._applyToConfig();
            }
        }
    }

    function _performMapSearch(query) {
        var q = query.trim();
        if (q.length < 2) {
            _mapSearchResults = [];
            _mapSearchBusy = false;
            return;
        }

        // Text search via Photon (photon.komoot.io, OpenStreetMap data).
        // lang=default: every place is named in its own local language.
        _mapSearchBusy = true;
        _mapSearchResults = [];
        var reqId = ++_mapSearchReqId;
        var url = "https://photon.komoot.io/api?q=" + encodeURIComponent(q) + "&limit=8&lang=default";
        console.warn("[LocationSearch] Map Photon GET " + url);
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (reqId !== _mapSearchReqId)
                return;
            _mapSearchBusy = false;
            console.warn("[LocationSearch] Map Photon HTTP " + req.status + " " + req.statusText);
            if (req.status !== 200) {
                console.warn("[LocationSearch] Map Photon body: " + String(req.responseText).substring(0, 300));
                return;
            }
            try {
                var feats = JSON.parse(req.responseText).features || [];
                var items = [], seen = {};
                feats.forEach(function (f) {
                    var pr = f.properties || {};
                    var c = f.geometry && f.geometry.coordinates;   // GeoJSON order: [lon, lat]
                    if (!c || c.length < 2 || !pr.name)
                        return;
                    var key = Number(c[1]).toFixed(3) + "|" + Number(c[0]).toFixed(3);
                    if (seen[key])
                        return;
                    seen[key] = true;
                    items.push({
                        name: mapSubPageRoot._photonTitle(pr),
                        lat: parseFloat(c[1]),
                        lon: parseFloat(c[0]),
                        countryCode: (pr.countrycode || "").toUpperCase()
                    });
                });
                console.warn("[LocationSearch] Map Photon returned " + feats.length + " item(s), listed " + items.length);
                _mapSearchResults = items;
            } catch (e) {
                console.warn("[MapSubPage] Photon search parse error:", e);
                _mapSearchResults = [];
            }
        };
        req.send();
    }

    function _navigateToCoordinates() {
        // Normalize "," → "." so locales using "," as decimal separator still parse correctly.
        var lat = parseFloat(String(latField.text).replace(",", "."));
        var lon = parseFloat(String(lonField.text).replace(",", "."));
        if (isNaN(lat) || isNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180)
            return;
        _mapShow(lat, lon, 10);
        _lookupLocation(lat, lon);
    }

    // ── Header ──────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.leftMargin: 4
        Layout.rightMargin: 8
        Layout.bottomMargin: 4
        spacing: 4

        Button {
            icon.name: "go-previous"
            text: i18n("Back")
            flat: true
            onClicked: configRoot._goBack()
        }
        Label {
            Layout.fillWidth: true
            text: i18n("Choose on Map")
            font.bold: true
        }
    }

    // ── Search bar ──────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 4

        ComboBox {
            id: searchModeCombo
            model: [i18n("Location name"), i18n("Coordinates")]
            currentIndex: _searchMode
            onCurrentIndexChanged: {
                _searchMode = currentIndex;
                _mapSearchResults = [];
            }
            implicitWidth: 160
        }

        // ── Location name mode ──────────────────────────────────────
        TextField {
            id: mapSearchField
            Layout.fillWidth: true
            visible: _searchMode === 0
            placeholderText: i18n("Search location…")
            onAccepted: mapSubPageRoot._performMapSearch(text)
        }

        // ── Coordinates mode ────────────────────────────────────────
        TextField {
            id: latField
            Layout.preferredWidth: 120
            visible: _searchMode === 1
            placeholderText: i18n("Latitude")
            // Locale-independent: accept both "." and "," as decimal separator.
            // _navigateToCoordinates() normalizes "," → "." before parsing.
            validator: RegularExpressionValidator {
                regularExpression: /^-?(\d{1,2}([.,]\d{0,7})?)?$/
            }
            onAccepted: mapSubPageRoot._navigateToCoordinates()
        }
        TextField {
            id: lonField
            Layout.preferredWidth: 120
            visible: _searchMode === 1
            placeholderText: i18n("Longitude")
            validator: RegularExpressionValidator {
                regularExpression: /^-?(\d{1,3}([.,]\d{0,7})?)?$/
            }
            onAccepted: mapSubPageRoot._navigateToCoordinates()
        }

        Button {
            icon.name: "search"
            text: i18n("Find")
            onClicked: {
                if (_searchMode === 0)
                    mapSubPageRoot._performMapSearch(mapSearchField.text);
                else
                    mapSubPageRoot._navigateToCoordinates();
            }
        }

        BusyIndicator {
            visible: _mapSearchBusy
            running: _mapSearchBusy
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: configRoot.duplicateWarning !== ""
        type: Kirigami.MessageType.Warning
        text: configRoot.duplicateWarning
        showCloseButton: true
        onVisibleChanged: if (!visible) configRoot.duplicateWarning = ""
    }

    // ── Search results list ──────────────────────────────────────────
    ListView {
        id: searchResultsListView
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.preferredHeight: visible ? Math.min(contentHeight, 200) : 0
        visible: _mapSearchResults.length > 0 && _searchMode === 0
        clip: true
        model: _mapSearchResults

        delegate: ItemDelegate {
            width: searchResultsListView.width
            text: modelData.name
            icon.name: "mark-location"
            onClicked: {
                mapSubPageRoot._mapShow(modelData.lat, modelData.lon, 12);
                mapSubPageRoot._lookupLocation(modelData.lat, modelData.lon, {
                    "name": modelData.name,
                    "countryCode": modelData.countryCode
                });
                _mapSearchResults = [];
                mapSearchField.text = "";
            }
        }
    }

    // ── Map ─────────────────────────────────────────────────────────────
    // Leaflet inside a WebEngineView (LocationMapPickerView.qml + location-map-picker.html), the same approach as the
    // radar tab. A Loader keeps a missing QtWebEngine from taking the whole page down.
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Loader {
            id: mapLoader
            anchors.fill: parent
            source: Qt.resolvedUrl("../../components/LocationMapPickerView.qml")
            onLoaded: {
                var lat = configRoot.cfg_latitude;
                var lon = configRoot.cfg_longitude;
                item.start(isNaN(lat) || lat === 0 ? 48.0 : lat, isNaN(lon) || lon === 0 ? 14.0 : lon, 5);
            }
        }

        Connections {
            target: mapLoader.item
            ignoreUnknownSignals: true
            function onMapClicked(lat, lon) {
                mapSubPageRoot._lookupLocation(lat, lon);
            }
            function onLoadFailed() {
                mapSubPageRoot._mapError = i18n("The map could not be loaded. Check your internet connection.");
            }
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - 2 * Kirigami.Units.gridUnit
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: mapLoader.status === Loader.Error ? i18n("The map needs QtWebEngine, which is not installed. You can still search for a location above.") : mapSubPageRoot._mapError
            visible: text.length > 0
        }
    }

    // ── Location info panel ─────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: infoPanelLayout.implicitHeight + 16
        color: Kirigami.Theme.backgroundColor !== undefined
            ? Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.95)
            : Qt.rgba(0, 0, 0, 0.95)
        border.color: Qt.rgba(0.5, 0.5, 0.5, 0.4)
        border.width: 1
        visible: !isNaN(mapSubPageRoot.selectedLat)

        ColumnLayout {
            id: infoPanelLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 8
            }
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Kirigami.Icon {
                    source: "mark-location"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                Label {
                    Layout.fillWidth: true
                    text: mapSubPageRoot.lookupBusy ? i18n("Looking up location…") : (mapSubPageRoot.selectedName.length > 0 ? mapSubPageRoot.selectedName : i18n("Unknown location"))
                    font.bold: true
                    elide: Text.ElideRight
                }

                // ── Inline weather info ─────────────────────────────
                Kirigami.Icon {
                    source: mapSubPageRoot._wmoIconName(mapSubPageRoot.selectedWeatherCode)
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    visible: !isNaN(mapSubPageRoot.selectedTemperature) && !mapSubPageRoot.lookupBusy
                }
                Label {
                    text: !isNaN(mapSubPageRoot.selectedTemperature) ? Math.round(mapSubPageRoot.selectedTemperature) + mapSubPageRoot.selectedTemperatureUnit + "  ·  " + mapSubPageRoot._wmoDescription(mapSubPageRoot.selectedWeatherCode) : ""
                    font.italic: true
                    opacity: 0.85
                    visible: !isNaN(mapSubPageRoot.selectedTemperature) && !mapSubPageRoot.lookupBusy
                }

                BusyIndicator {
                    visible: mapSubPageRoot.lookupBusy
                    running: mapSubPageRoot.lookupBusy
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 12
                rowSpacing: 4

                Label {
                    text: i18n("Lat:")
                    opacity: 0.7
                }
                Label {
                    text: isNaN(mapSubPageRoot.selectedLat) ? "-" : mapSubPageRoot.selectedLat.toFixed(5) + "°"
                }
                Label {
                    text: i18n("Lon:")
                    opacity: 0.7
                }
                Label {
                    text: isNaN(mapSubPageRoot.selectedLon) ? "-" : mapSubPageRoot.selectedLon.toFixed(5) + "°"
                }

                Label {
                    text: i18n("Altitude:")
                    opacity: 0.7
                }
                Label {
                    text: mapSubPageRoot.selectedAltitude !== 0 ? mapSubPageRoot.selectedAltitude + " m" : "-"
                }
                Label {
                    text: i18n("Timezone:")
                    opacity: 0.7
                }
                Label {
                    text: mapSubPageRoot.selectedTimezone.length > 0 ? mapSubPageRoot.selectedTimezone : "-"
                }
            }
        }
    }

    // Hint when no location is selected
    Label {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        horizontalAlignment: Text.AlignHCenter
        visible: isNaN(mapSubPageRoot.selectedLat)
        opacity: 0.6
        text: i18n("Click on the map to select a location")
    }

    // ── Set as default dialog lives in configLocation.qml, shown on KCM Apply ──

    // ── WMO weather code helpers ────────────────────────────────────────
    function _wmoIconName(code) {
        if (code < 0)
            return "weather-none-available";
        if (code === 0)
            return "weather-clear";
        if (code <= 3)
            return "weather-few-clouds";
        if (code <= 48)
            return "weather-fog";
        if (code <= 55)
            return "weather-showers-scattered";
        if (code <= 57)
            return "weather-freezing-rain";
        if (code <= 65)
            return "weather-showers";
        if (code <= 67)
            return "weather-freezing-rain";
        if (code <= 77)
            return "weather-snow";
        if (code <= 82)
            return "weather-showers";
        if (code <= 86)
            return "weather-snow";
        if (code >= 95)
            return "weather-storm";
        return "weather-none-available";
    }
    function _wmoDescription(code) {
        if (code === 0)
            return i18n("Clear sky");
        if (code === 1)
            return i18n("Mainly clear");
        if (code === 2)
            return i18n("Partly cloudy");
        if (code === 3)
            return i18n("Overcast");
        if (code === 45 || code === 48)
            return i18n("Fog");
        if (code === 51)
            return i18n("Light drizzle");
        if (code === 53)
            return i18n("Moderate drizzle");
        if (code === 55)
            return i18n("Dense drizzle");
        if (code === 56 || code === 57)
            return i18n("Freezing drizzle");
        if (code === 61)
            return i18n("Slight rain");
        if (code === 63)
            return i18n("Moderate rain");
        if (code === 65)
            return i18n("Heavy rain");
        if (code === 66 || code === 67)
            return i18n("Freezing rain");
        if (code === 71)
            return i18n("Slight snowfall");
        if (code === 73)
            return i18n("Moderate snowfall");
        if (code === 75)
            return i18n("Heavy snowfall");
        if (code === 77)
            return i18n("Snow grains");
        if (code === 80)
            return i18n("Slight rain showers");
        if (code === 81)
            return i18n("Moderate rain showers");
        if (code === 82)
            return i18n("Violent rain showers");
        if (code === 85)
            return i18n("Slight snow showers");
        if (code === 86)
            return i18n("Heavy snow showers");
        if (code === 95)
            return i18n("Thunderstorm");
        if (code === 96 || code === 99)
            return i18n("Thunderstorm with hail");
        return i18n("Unknown");
    }
}
