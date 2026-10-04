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
 * ConfigLocationSubPage - Location search, extracted from configLocation.qml
 * Requires: required property var configRoot
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: searchSubPageRoot
    required property var configRoot
    spacing: 0

    property var searchResults: []
    property bool searchBusy: false
    property int searchRequestId: 0
    property var selectedResult: null
    property int selectedIndex: -1
    property var _pendingItemData: null  // tracks whether a new location was staged

    // ── Current-location metadata (fetched from Open-Meteo) ────────────
    property real currentTemperature: NaN
    property int  currentWeatherCode: -1
    property string currentTemperatureUnit: "°C"
    property bool currentInfoBusy: false
    property int  _currentInfoGen: 0

    function _weatherCodeDescription(code) {
        // WMO weather interpretation codes (Open-Meteo)
        if (code === 0)  return i18n("Clear sky");
        if (code === 1)  return i18n("Mainly clear");
        if (code === 2)  return i18n("Partly cloudy");
        if (code === 3)  return i18n("Overcast");
        if (code === 45 || code === 48) return i18n("Fog");
        if (code === 51 || code === 53 || code === 55) return i18n("Drizzle");
        if (code === 56 || code === 57) return i18n("Freezing drizzle");
        if (code === 61 || code === 63 || code === 65) return i18n("Rain");
        if (code === 66 || code === 67) return i18n("Freezing rain");
        if (code === 71 || code === 73 || code === 75) return i18n("Snow");
        if (code === 77) return i18n("Snow grains");
        if (code === 80 || code === 81 || code === 82) return i18n("Rain showers");
        if (code === 85 || code === 86) return i18n("Snow showers");
        if (code === 95) return i18n("Thunderstorm");
        if (code === 96 || code === 99) return i18n("Thunderstorm with hail");
        return "";
    }

    function _fetchCurrentInfo() {
        try {
            var lat = configRoot.cfg_latitude;
            var lon = configRoot.cfg_longitude;
            if (!configRoot.cfg_locationName || configRoot.cfg_locationName.length === 0
                || (lat === 0 && lon === 0)) {
                currentTemperature = NaN;
                currentWeatherCode = -1;
                currentInfoBusy = false;
                return;
            }
            currentInfoBusy = true;
            var myGen = ++_currentInfoGen;
            var req = new XMLHttpRequest();
            req.open("GET", "https://api.open-meteo.com/v1/forecast?latitude="
                + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon)
                + "&current=temperature_2m,weather_code&timezone=auto");
            req.onreadystatechange = function() {
                if (req.readyState !== XMLHttpRequest.DONE) return;
                if (myGen !== _currentInfoGen) return;
                currentInfoBusy = false;
                if (req.status === 200) {
                    try {
                        var data = JSON.parse(req.responseText);
                        if (data.current) {
                            if (data.current.temperature_2m !== undefined)
                                currentTemperature = data.current.temperature_2m;
                            if (data.current.weather_code !== undefined)
                                currentWeatherCode = data.current.weather_code;
                        }
                        if (data.current_units && data.current_units.temperature_2m)
                            currentTemperatureUnit = data.current_units.temperature_2m;
                    } catch (e) { /* ignore */ }

                    // Update config with missing metadata if needed. This handles cases where
                    // the search provider (Photon) doesn't supply timezone or altitude.
                    if (data.timezone && (!configRoot.cfg_timezone || configRoot.cfg_timezone.length === 0)) {
                        configRoot.cfg_timezone = data.timezone;
                    }
                    if (data.elevation !== undefined && (!configRoot.cfg_altitude || configRoot.cfg_altitude === 0)) {
                        var alt = data.elevation;
                        if (configRoot.cfg_altitudeUnit === "ft") {
                            alt = Math.round(alt * 3.28084);
                        } else {
                            alt = Math.round(alt);
                        }
                        configRoot.cfg_altitude = alt;
                    }
                    // Ensure the pending entry (staged for savedLocations) is also updated.
                    if (configRoot._pendingEntry) {
                        if (data.timezone && (!configRoot._pendingEntry.timezone || configRoot._pendingEntry.timezone.length === 0)) {
                            configRoot._pendingEntry.timezone = data.timezone;
                        }
                        if (data.elevation !== undefined && (!configRoot._pendingEntry.altitude || configRoot._pendingEntry.altitude === 0)) {
                            var alt2 = data.elevation;
                            if (configRoot.cfg_altitudeUnit === "ft") {
                                alt2 = Math.round(alt2 * 3.28084);
                            } else {
                                alt2 = Math.round(alt2);
                            }
                            configRoot._pendingEntry.altitude = alt2;
                        }
                    }
                }
            };
            req.send();
        } catch (e) {
            currentInfoBusy = false;
        }
    }

    // Re-run the Open-Meteo lookup whenever the active location changes.
    // Using a derived property + its own change handler avoids Connections
    // on configRoot (which caused initialisation issues in some Qt 6 builds).
    readonly property string activeLocKey:
        "" + configRoot.cfg_latitude + "|" + configRoot.cfg_longitude + "|" + (configRoot.cfg_locationName || "")
    onActiveLocKeyChanged: Qt.callLater(_fetchCurrentInfo)

    Component.onCompleted: Qt.callLater(_fetchCurrentInfo)

    // Location search uses Photon only (photon.komoot.io, OpenStreetMap data).
    function performSearch(query) {
        if (!query || query.trim().length < 2) {
            searchResults = [];
            selectedResult = null;
            selectedIndex = -1;
            resultsList.currentIndex = -1;
            searchBusy = false;
            return;
        }
        var q = query.trim();
        var requestId = ++searchRequestId;
        searchBusy = true;
        searchResults = [];
        selectedResult = null;
        selectedIndex = -1;
        resultsList.currentIndex = -1;

        // lang=default: every place is named in its own local language (София, not Sofia).
        // Without it Photon uses the Accept-Language header of the request, which here
        // follows the system locale and gives English names.
        var url = "https://photon.komoot.io/api?q=" + encodeURIComponent(q) + "&limit=15&lang=default";
        console.warn("[LocationSearch] #" + requestId + " Photon GET " + url);
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (requestId !== searchRequestId) {
                console.warn("[LocationSearch] #" + requestId + " Photon reply ignored (stale), HTTP " + req.status);
                return;
            }
            console.warn("[LocationSearch] #" + requestId + " Photon HTTP " + req.status + " " + req.statusText);
            var collected = [];
            if (req.status === 200) {
                try {
                    var feats = JSON.parse(req.responseText).features || [];
                    // Prefer settlements / administrative areas over streets, shops, etc.
                    var places = feats.filter(function (f) {
                        var k = f.properties && f.properties.osm_key;
                        return k === "place" || k === "boundary";
                    });
                    if (places.length === 0)
                        places = feats;
                    console.warn("[LocationSearch] #" + requestId + " Photon returned " + feats.length + " item(s), kept " + places.length);
                    places.forEach(function (f) {
                        var pr = f.properties || {};
                        var c = f.geometry && f.geometry.coordinates;   // GeoJSON order: [lon, lat]
                        if (!c || c.length < 2 || !pr.name)
                            return;
                        var fix = configRoot._fixMixedScript;
                        var pName = fix(pr.name);
                        var pCounty = fix(pr.county);
                        var pState = fix(pr.state);
                        var pCountry = fix(pr.country);
                        // Result title: "name, county, state, country" (a part equal to an earlier one is skipped)
                        var parts = [];
                        [pName, pCounty, pState, pCountry].forEach(function (part) {
                            if (part.length > 0 && parts.every(function (x) {
                                return x.toLowerCase() !== part.toLowerCase();
                            }))
                                parts.push(part);
                        });
                        var title = parts.join(", ");
                        console.warn("[LocationSearch] #" + requestId + " Photon item: " + title);
                        collected.push({
                            name: pName,
                            admin1: pState,
                            district: pCounty,
                            country: pCountry,
                            countryCode: (pr.countrycode || "").toUpperCase(),
                            latitude: parseFloat(c[1]),
                            longitude: parseFloat(c[0]),
                            timezone: "",
                            elevation: undefined,
                            provider: "Photon",
                            providerKey: "photon",
                            localizedDisplayName: title
                        });
                    });
                } catch (e) {
                    console.warn("[LocationSearch] #" + requestId + " Photon parse error: " + e);
                }
            } else {
                console.warn("[LocationSearch] #" + requestId + " Photon body: " + String(req.responseText).substring(0, 400));
            }
            var dedup = {}, finalList = [];
            for (var i = 0; i < collected.length; ++i) {
                var item = collected[i];
                var key = Number(item.latitude).toFixed(3) + "|" + Number(item.longitude).toFixed(3);
                if (!dedup[key]) {
                    dedup[key] = true;
                    finalList.push(item);
                }
            }
            searchResults = finalList;
            searchBusy = false;
            selectedResult = null;
            selectedIndex = -1;
            resultsList.currentIndex = -1;
        };
        req.send();
    }

    Timer {
        id: searchDebounce
        interval: 500
        repeat: false
        onTriggered: searchSubPageRoot.performSearch(searchField.text)
    }

    // ── Set as default dialog lives in configLocation.qml, shown on KCM Apply ──

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
            text: i18n("Search Location")
            font.bold: true
        }
    }

    // ── Search content ──────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 8

        // ── Current location info panel ─────────────────────────────────
        // Only shown when a location is actually configured.
        Rectangle {
            id: currentInfoCard
            Layout.fillWidth: true
            Layout.topMargin: 2
            radius: 4
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            border.width: 1
            implicitHeight: currentInfoCol.implicitHeight + 12

            readonly property bool hasLocation:
                configRoot.cfg_locationName && configRoot.cfg_locationName.length > 0

            visible: hasLocation

            ColumnLayout {
                id: currentInfoCol
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 8
                    rightMargin: 8
                }
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Kirigami.Icon {
                        source: "mark-location"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.bold: true
                        text: i18n("Location:") + " " + (currentInfoCard.hasLocation
                            ? configRoot.cfg_locationName
                            : i18n("None"))
                    }
                    BusyIndicator {
                        visible: searchSubPageRoot.currentInfoBusy
                        running: visible
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                }

                // Details row - only shown if a location is configured
                Label {
                    Layout.fillWidth: true
                    visible: currentInfoCard.hasLocation
                    wrapMode: Text.WordWrap
                    opacity: 0.8
                    font: Kirigami.Theme.smallFont
                    text: {
                        var parts = [];
                        parts.push(i18n("Lat: %1°", Number(configRoot.cfg_latitude).toFixed(4)));
                        parts.push(i18n("Lon: %1°", Number(configRoot.cfg_longitude).toFixed(4)));
                        var altVal = configRoot.cfg_altitude || 0;
                        var altUnit = configRoot.cfg_altitudeUnit === "ft" ? i18n("ft") : i18n("m");
                        parts.push(i18n("Alt: %1 %2", altVal, altUnit));
                        if (configRoot.cfg_timezone && configRoot.cfg_timezone.length > 0)
                            parts.push(configRoot.cfg_timezone);
                        return parts.join("  ·  ");
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: currentInfoCard.hasLocation
                    wrapMode: Text.WordWrap
                    opacity: 0.8
                    font: Kirigami.Theme.smallFont
                    text: {
                        var parts = [];
                        // When "adaptive" is selected, show which concrete
                        // provider is actually used first in the chain -
                        // Open-Meteo. We use it here for the current-weather
                        // preview too, so the label accurately reflects the
                        // data source.
                        var providerName = configRoot.selectedProviderDisplayName();
                        if (configRoot.cfg_weatherProvider === "adaptive")
                            providerName = i18n("Adaptive (Open-Meteo)");
                        parts.push(i18n("Provider: %1", providerName));
                        if (!isNaN(searchSubPageRoot.currentTemperature)) {
                            var desc = searchSubPageRoot._weatherCodeDescription(searchSubPageRoot.currentWeatherCode);
                            var tStr = Math.round(searchSubPageRoot.currentTemperature) + searchSubPageRoot.currentTemperatureUnit;
                            parts.push(i18n("Now: %1%2", tStr, desc.length > 0 ? " · " + desc : ""));
                        }
                        return parts.join("  ·  ");
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18n("Enter Location")
                selectByMouse: true
                onTextChanged: {
                    searchSubPageRoot.selectedResult = null;
                    searchSubPageRoot.selectedIndex = -1;
                    resultsList.currentIndex = -1;
                    configRoot.locationCheckState = 0;
                    if (text.trim().length < 2) {
                        searchSubPageRoot.searchResults = [];
                        searchSubPageRoot.searchBusy = false;
                        return;
                    }
                    // Search starts after the debounce; show "Loading…" meanwhile instead of
                    // flashing "No weather stations found".
                    searchSubPageRoot.searchBusy = true;
                    searchDebounce.restart();
                }
                onAccepted: {
                    searchDebounce.stop();
                    searchSubPageRoot.performSearch(text);
                }
            }
            ToolButton {
                text: "✕"
                visible: searchField.text.length > 0
                onClicked: {
                    searchField.clear();
                    searchSubPageRoot.searchResults = [];
                    searchSubPageRoot.searchBusy = false;
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ListView {
                id: resultsList
                anchors.fill: parent
                clip: true
                model: searchSubPageRoot.searchResults
                currentIndex: searchSubPageRoot.selectedIndex
                visible: searchSubPageRoot.searchResults.length > 0
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: resultsList.moving || hovered
                }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 36
                    color: index === searchSubPageRoot.selectedIndex ? Kirigami.Theme.highlightColor : "transparent"
                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: configRoot.formatResultListItem(modelData)
                        color: index === searchSubPageRoot.selectedIndex ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            searchSubPageRoot.selectedIndex = index;
                            searchSubPageRoot.selectedResult = modelData;
                            resultsList.currentIndex = index;

                            var entryLat = parseFloat(modelData.latitude);
                            var entryLon = parseFloat(modelData.longitude);
                            var entryName = configRoot.formatResultTitle(modelData);
                            var locs;
                            try {
                                locs = JSON.parse(configRoot.cfg_savedLocations || "[]");
                                if (!Array.isArray(locs)) locs = [];
                            } catch (e) { locs = []; }
                            var isDup = locs.some(function(l) {
                                return Math.abs(l.lat - entryLat) < 0.01 && Math.abs(l.lon - entryLon) < 0.01;
                            });

                            // Always stage to cfg_* so KCM Apply becomes active
                            configRoot.applySearchResult(modelData);

                            if (!isDup) {
                                configRoot.duplicateWarning = "";
                                // Store pending - saved on KCM Apply via save() in configLocation.qml
                                var startAlt = modelData.elevation || 0;
                                if (startAlt !== 0 && configRoot.cfg_altitudeUnit === "ft") {
                                    startAlt = Math.round(startAlt * 3.28084);
                                } else {
                                    startAlt = Math.round(startAlt);
                                }

                                configRoot._pendingEntry = {
                                    name: entryName,
                                    lat: entryLat,
                                    lon: entryLon,
                                    altitude: startAlt,
                                    timezone: modelData.timezone || "",
                                    countryCode: (modelData.countryCode || "").toUpperCase()
                                };
                                searchSubPageRoot._pendingItemData = modelData;
                            } else {
                                // Already saved - clear pending
                                configRoot._pendingEntry = null;
                                searchSubPageRoot._pendingItemData = null;
                                configRoot.duplicateWarning = i18n("Location '%1' is already in your saved list. You can apply the selected location, but it will not be saved again.", entryName);
                                configRoot.duplicateDialog.open();
                            }
                        }
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 10
                visible: searchSubPageRoot.searchBusy || searchSubPageRoot.searchResults.length === 0
                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: searchSubPageRoot.searchBusy
                    visible: searchSubPageRoot.searchBusy
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.9
                    font.pixelSize: searchSubPageRoot.searchBusy ? 18 : 30
                    font.bold: true
                    text: searchSubPageRoot.searchBusy ? i18n("Loading locations…") : (searchField.text.trim().length < 2 ? i18n("Search a weather station to set your location") : i18n("No weather stations found for '%1'", searchField.text.trim()))
                }
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

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: configRoot.locationCheckState === 2
            type: Kirigami.MessageType.Positive
            text: configRoot.locationCheckMessage
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: configRoot.locationCheckState === 3
            type: Kirigami.MessageType.Error
            text: configRoot.locationCheckMessage
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            type: Kirigami.MessageType.Information
            text: i18n("Location search by %1 · Map data © %2",
                       "<a href=\"https://photon.komoot.io\">Photon</a>",
                       "<a href=\"https://www.openstreetmap.org/copyright\">OpenStreetMap contributors</a>")
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
}
