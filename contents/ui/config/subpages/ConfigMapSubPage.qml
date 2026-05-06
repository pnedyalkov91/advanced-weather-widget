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
 * ConfigMapSubPage — Pick a location on an interactive OSM map.
 * Requires: required property var configRoot
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
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
    property string _preferredLanguage: Qt.locale().name.split("_")[0]

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
            // Store pending — saved on KCM Apply via save() in configLocation.qml
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
            configRoot.duplicateDialog.open();
        }
    }

    function _lookupLocation(lat, lon) {
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
        markerItem.coordinate = QtPositioning.coordinate(lat, lon);
        markerItem.visible = true;

        // 1) Reverse geocode via Nominatim — use preferred language so that
        //    region and country names come back in the user's locale
        var revLang = _preferredLanguage.length > 0 ? _preferredLanguage + ",en;q=0.8" : "en";
        var revReq = new XMLHttpRequest();
        revReq.open("GET", "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&addressdetails=1&accept-language=" + revLang + "&lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon));
        revReq.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
        revReq.onreadystatechange = function () {
            if (revReq.readyState !== XMLHttpRequest.DONE)
                return;
            if (reqId !== _reqId)
                return;
            if (revReq.status === 200) {
                try {
                    var data = JSON.parse(revReq.responseText);
                    if (data && data.address) {
                        var a = data.address;
                        // Use display_name which is fully localized by accept-language
                        selectedName = data.display_name || "";
                        var cc = (a.country_code || "").toUpperCase();
                        if (cc.length > 0)
                            selectedCountryCode = cc;
                    } else if (data && data.display_name) {
                        selectedName = data.display_name;
                    }
                } catch (e) {
                    console.warn("[MapSubPage] Nominatim parse error:", e);
                }
            }
            _checkDone();
        };
        revReq.send();

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

        var _done = 0;
        function _checkDone() {
            if (++_done >= 2) {
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

        // Text search via Nominatim
        _mapSearchBusy = true;
        _mapSearchResults = [];
        var reqId = ++_mapSearchReqId;
        var req = new XMLHttpRequest();
        var searchLang = _preferredLanguage.length > 0 ? _preferredLanguage + ",en;q=0.8" : "en";
        req.open("GET", "https://nominatim.openstreetmap.org/search?format=json&limit=8&addressdetails=1&accept-language=" + searchLang + "&q=" + encodeURIComponent(q));
        req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (reqId !== _mapSearchReqId)
                return;
            _mapSearchBusy = false;
            if (req.status === 200) {
                try {
                    var results = JSON.parse(req.responseText);
                    var items = [];
                    for (var i = 0; i < results.length && i < 8; i++) {
                        items.push({
                            name: results[i].display_name || "",
                            lat: parseFloat(results[i].lat),
                            lon: parseFloat(results[i].lon)
                        });
                    }
                    _mapSearchResults = items;
                } catch (e) {
                    _mapSearchResults = [];
                }
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
        osmMap.center = QtPositioning.coordinate(lat, lon);
        osmMap.zoomLevel = Math.max(osmMap.zoomLevel, 10);
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
                osmMap.center = QtPositioning.coordinate(modelData.lat, modelData.lon);
                osmMap.zoomLevel = Math.max(osmMap.zoomLevel, 12);
                mapSubPageRoot._lookupLocation(modelData.lat, modelData.lon);
                _mapSearchResults = [];
                mapSearchField.text = "";
            }
        }
    }

    // ── Map ─────────────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Map {
            id: osmMap
            anchors.fill: parent
            plugin: Plugin {
                name: "osm"
                PluginParameter {
                    name: "osm.mapping.providersrepository.disabled"
                    value: "true"
                }
                PluginParameter {
                    name: "osm.mapping.custom.host"
                    value: "https://tile.openstreetmap.org/"
                }
                PluginParameter {
                    name: "osm.mapping.custom.mapcopyright"
                    value: "© OpenStreetMap contributors"
                }
            }
            center: QtPositioning.coordinate(isNaN(configRoot.cfg_latitude) || configRoot.cfg_latitude === 0 ? 48.0 : configRoot.cfg_latitude, isNaN(configRoot.cfg_longitude) || configRoot.cfg_longitude === 0 ? 14.0 : configRoot.cfg_longitude)
            zoomLevel: 5

            // Explicitly clamp the map's zoom range to match the active map type.
            // Using 17 as a conservative maximum ensures consistent coverage globally 
            // and avoids the "Zoom level not supported" overlay for regions with sparse tiles.
            maximumZoomLevel: (activeMapType && activeMapType.maximumZoomLevel > 0) ? Math.min(17, activeMapType.maximumZoomLevel) : 17
            minimumZoomLevel: 3

            Behavior on zoomLevel {
                enabled: !pinch.active
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            activeMapType: {
                for (var i = 0; i < supportedMapTypes.length; i++) {
                    // Prefer our custom OpenStreetMap provider
                    if (supportedMapTypes[i].name.indexOf("Custom") !== -1)
                        return supportedMapTypes[i];
                }
                return supportedMapTypes.length > 0 ? supportedMapTypes[0] : null;
            }

            // ── Zoom controls ───────────────────────────────────────
            PinchHandler {
                id: pinch
                target: null
                onActiveChanged: if (active)
                    osmMap.startCentroid = osmMap.toCoordinate(pinch.centroid.position, false)
                onScaleChanged: delta => {
                    osmMap.zoomLevel = Math.max(osmMap.minimumZoomLevel, Math.min(osmMap.maximumZoomLevel, osmMap.zoomLevel + Math.log2(delta)));
                    osmMap.alignCoordinateToPoint(osmMap.startCentroid, pinch.centroid.position);
                }
                onRotationChanged: delta => {
                    osmMap.bearing -= delta;
                    osmMap.alignCoordinateToPoint(osmMap.startCentroid, pinch.centroid.position);
                }
                grabPermissions: PointerHandler.TakeOverForbidden
            }
            WheelHandler {
                id: wheel
                acceptedDevices: Qt.platform.pluginName === "cocoa" || Qt.platform.pluginName === "wayland" ? PointerDevice.Mouse | PointerDevice.TouchPad : PointerDevice.Mouse
                rotationScale: 1 / 30
                target: null
                property real _prevRotation: 0
                onRotationChanged: {
                    var delta = rotation - _prevRotation;
                    _prevRotation = rotation;
                    var coord = osmMap.toCoordinate(point.position, false);
                    osmMap.zoomLevel = Math.max(osmMap.minimumZoomLevel, Math.min(osmMap.maximumZoomLevel, osmMap.zoomLevel + delta));
                    osmMap.alignCoordinateToPoint(coord, point.position);
                }
            }
            DragHandler {
                id: drag
                target: null
                onTranslationChanged: delta => osmMap.pan(-delta.x, -delta.y)
            }
            // Start centroid helper for pinch-zoom
            property geoCoordinate startCentroid

            // ── Click to select location ────────────────────────────
            TapHandler {
                onTapped: function (eventPoint) {
                    var coord = osmMap.toCoordinate(eventPoint.position, false);
                    mapSubPageRoot._lookupLocation(coord.latitude, coord.longitude);
                }
            }

            // ── Marker ──────────────────────────────────────────────
            MapQuickItem {
                id: markerItem
                visible: false
                anchorPoint.x: markerIcon.width / 2
                anchorPoint.y: markerIcon.height
                sourceItem: Kirigami.Icon {
                    id: markerIcon
                    source: "mark-location"
                    width: 32
                    height: 32
                    color: Kirigami.Theme.negativeTextColor
                }
            }
        }

        // ── Zoom buttons (top-right) ────────────────────────────────
        Column {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 4
            z: 2

            RoundButton {
                width: 36
                height: 36
                text: "+"
                font.pixelSize: 18
                onClicked: osmMap.zoomLevel = Math.min(osmMap.zoomLevel + 1, osmMap.maximumZoomLevel)
                ToolTip.visible: hovered
                ToolTip.text: i18n("Zoom in")
            }
            RoundButton {
                width: 36
                height: 36
                text: "−"
                font.pixelSize: 18
                onClicked: osmMap.zoomLevel = Math.max(osmMap.zoomLevel - 1, osmMap.minimumZoomLevel)
                ToolTip.visible: hovered
                ToolTip.text: i18n("Zoom out")
            }
        }

        // ── Attribution (bottom-right) ──────────────────────────────
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4
            color: Qt.rgba(1, 1, 1, 0.75)
            radius: 3
            width: attribLabel.implicitWidth + 8
            height: attribLabel.implicitHeight + 4
            z: 2

            Label {
                id: attribLabel
                anchors.centerIn: parent
                text: "© <a href=\"https://www.openstreetmap.org/copyright\">OpenStreetMap</a> contributors"
                textFormat: Text.RichText
                font.pixelSize: 10
                color: "#333"
                onLinkActivated: function (link) {
                    Qt.openUrlExternally(link);
                }
            }
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
                    text: isNaN(mapSubPageRoot.selectedLat) ? "—" : mapSubPageRoot.selectedLat.toFixed(5) + "°"
                }
                Label {
                    text: i18n("Lon:")
                    opacity: 0.7
                }
                Label {
                    text: isNaN(mapSubPageRoot.selectedLon) ? "—" : mapSubPageRoot.selectedLon.toFixed(5) + "°"
                }

                Label {
                    text: i18n("Altitude:")
                    opacity: 0.7
                }
                Label {
                    text: mapSubPageRoot.selectedAltitude !== 0 ? mapSubPageRoot.selectedAltitude + " m" : "—"
                }
                Label {
                    text: i18n("Timezone:")
                    opacity: 0.7
                }
                Label {
                    text: mapSubPageRoot.selectedTimezone.length > 0 ? mapSubPageRoot.selectedTimezone : "—"
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
