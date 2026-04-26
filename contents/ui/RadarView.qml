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
 * RadarView.qml — Interactive weather radar map tab
 *
 * Base map: QtLocation Map with OSM plugin (same as ConfigMapSubPage).
 * Weather overlay: MapQuickItem tiles fetched at the correct z/x/y for
 * the visible viewport — avoids all Qt OSM plugin tile-URL limitations.
 *
 * Free layers (no API key):   Radar (RainViewer)
 * OWM key layers:             Rain, Clouds, Temperature, Wind, Pressure
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtLocation
import QtPositioning
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: radarRoot

    property var weatherRoot

    readonly property double lat:    weatherRoot ? (Plasmoid.configuration.latitude  || 0) : 0
    readonly property double lon:    weatherRoot ? (Plasmoid.configuration.longitude || 0) : 0
    readonly property string owmKey: Plasmoid.configuration.owApiKey || ""
    readonly property string activeLayer: Plasmoid.configuration.radarLayer || "rainviewer"

    implicitHeight: 340

    // ── Layer definitions ────────────────────────────────────────────────
    readonly property var layers: [
        { id: "rainviewer",        label: i18n("Radar"),       freeKey: true  },
        { id: "precipitation_new", label: i18n("Rain"),        freeKey: false },
        { id: "clouds_new",        label: i18n("Clouds"),      freeKey: false },
        { id: "temp_new",          label: i18n("Temperature"), freeKey: false },
        { id: "wind_new",          label: i18n("Wind"),        freeKey: false },
        { id: "pressure_new",      label: i18n("Pressure"),    freeKey: false }
    ]

    // ── RainViewer latest radar frame path ───────────────────────────────
    property string _rvPath: ""

    function _fetchRainviewer() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.rainviewer.com/public/weather-maps.json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) return;
            try {
                var d = JSON.parse(xhr.responseText);
                var f = d.radar && d.radar.past;
                if (f && f.length > 0) {
                    radarRoot._rvPath = d.host + f[f.length - 1].path;
                    overlayCanvas.requestPaint();
                }
            } catch(e) {}
        };
        xhr.send();
    }

    // ── Build tile URL for a given z/x/y ────────────────────────────────
    function _tileUrl(z, x, y) {
        var layer = radarRoot.activeLayer;
        if (layer === "rainviewer") {
            if (!radarRoot._rvPath) return "";
            return radarRoot._rvPath + "/256/" + z + "/" + x + "/" + y + "/2/1_1.png";
        }
        if (radarRoot.owmKey) {
            return "https://tile.openweathermap.org/map/" + layer + "/" + z + "/" + x + "/" + y + ".png?appid=" + radarRoot.owmKey;
        }
        return "";
    }

    // ── Tile math helpers (Web Mercator) ─────────────────────────────────
    function _lon2tile(lon, z) { return Math.floor((lon + 180) / 360 * Math.pow(2, z)); }
    function _lat2tile(lat, z) {
        var r = lat * Math.PI / 180;
        return Math.floor((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * Math.pow(2, z));
    }
    function _tile2lon(x, z) { return x / Math.pow(2, z) * 360 - 180; }
    function _tile2lat(y, z) {
        var n = Math.PI - 2 * Math.PI * y / Math.pow(2, z);
        return 180 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
    }

    Component.onCompleted: _fetchRainviewer()

    onActiveLayerChanged: {
        if (activeLayer === "rainviewer" && !_rvPath) _fetchRainviewer();
        overlayRepaintTimer.restart();
    }
    on_RvPathChanged: overlayRepaintTimer.restart()

    onLatChanged: baseMap.center = QtPositioning.coordinate(radarRoot.lat || 42.70, radarRoot.lon || 23.32)
    onLonChanged: baseMap.center = QtPositioning.coordinate(radarRoot.lat || 42.70, radarRoot.lon || 23.32)

    // ── Layout ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // ── Layer selector buttons ────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: radarRoot.layers
                delegate: Button {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.label
                    highlighted: radarRoot.activeLayer === modelData.id
                    enabled: modelData.freeKey || radarRoot.owmKey !== ""
                    opacity: enabled ? 1.0 : 0.38
                    padding: 4
                    font.pixelSize: 10
                    ToolTip.visible: hovered && !enabled
                    ToolTip.text: i18n("OpenWeatherMap API key required")
                    onClicked: Plasmoid.configuration.radarLayer = modelData.id
                }
            }
        }

        // ── Map container ─────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // ── Base OSM map ──────────────────────────────────────────
            Map {
                id: baseMap
                anchors.fill: parent
                center: QtPositioning.coordinate(
                    radarRoot.lat || 42.70,
                    radarRoot.lon || 23.32)
                zoomLevel: 9

                plugin: Plugin {
                    name: "osm"
                    PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: "true" }
                    PluginParameter { name: "osm.mapping.custom.host";      value: "https://tile.openstreetmap.org/" }
                    PluginParameter { name: "osm.mapping.custom.mapcopyright"; value: "© OpenStreetMap contributors" }
                }

                Behavior on zoomLevel {
                    enabled: !pinch.active
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                onZoomLevelChanged: overlayRepaintTimer.restart()
                onCenterChanged:    overlayRepaintTimer.restart()

                PinchHandler {
                    id: pinch
                    target: null
                    onActiveChanged: if (active) baseMap.startCentroid = baseMap.toCoordinate(pinch.centroid.position, false)
                    onScaleChanged: delta => {
                        baseMap.zoomLevel += Math.log2(delta);
                        baseMap.alignCoordinateToPoint(baseMap.startCentroid, pinch.centroid.position);
                    }
                    grabPermissions: PointerHandler.TakeOverForbidden
                }
                WheelHandler {
                    acceptedDevices: Qt.platform.pluginName === "cocoa" || Qt.platform.pluginName === "wayland"
                        ? PointerDevice.Mouse | PointerDevice.TouchPad : PointerDevice.Mouse
                    rotationScale: 1 / 30
                    target: null
                    property real _prev: 0
                    onRotationChanged: {
                        var d = rotation - _prev; _prev = rotation;
                        var coord = baseMap.toCoordinate(point.position, false);
                        baseMap.zoomLevel += d;
                        baseMap.alignCoordinateToPoint(coord, point.position);
                    }
                }
                DragHandler {
                    target: null
                    onTranslationChanged: delta => baseMap.pan(-delta.x, -delta.y)
                }
                property geoCoordinate startCentroid

                MapQuickItem {
                    coordinate: QtPositioning.coordinate(radarRoot.lat || 42.70, radarRoot.lon || 23.32)
                    anchorPoint.x: markerIcon.width / 2
                    anchorPoint.y: markerIcon.height
                    sourceItem: Kirigami.Icon {
                        id: markerIcon
                        source: "mark-location"
                        width: 28; height: 28
                        color: Kirigami.Theme.negativeTextColor
                    }
                }
            }

            // Debounce repaint — wait for map to settle after zoom/pan
            Timer {
                id: overlayRepaintTimer
                interval: 120
                onTriggered: overlayCanvas.requestPaint()
            }

            // ── Weather overlay: Canvas using loadImage() API ─────────
            Canvas {
                id: overlayCanvas
                anchors.fill: parent
                opacity: 0.65
                enabled: false  // don't steal pointer events

                // Set of URLs we have already requested via loadImage()
                property var _requested: ({})

                onImageLoaded: requestPaint()

                function _clearCache() {
                    _requested = {};
                    requestPaint();
                }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    var z = Math.round(baseMap.zoomLevel);
                    var isRV = (radarRoot.activeLayer === "rainviewer");
                    if (z < 1) z = 1;
                    if (z > (isRV ? 7 : 18)) z = isRV ? 7 : 18;

                    var topLeft     = baseMap.toCoordinate(Qt.point(0, 0), false);
                    var bottomRight = baseMap.toCoordinate(Qt.point(width, height), false);
                    if (!topLeft || !bottomRight) return;
                    if (!topLeft.isValid || !bottomRight.isValid) return;

                    var txMin = radarRoot._lon2tile(topLeft.longitude, z) - 1;
                    var txMax = radarRoot._lon2tile(bottomRight.longitude, z) + 1;
                    var tyMin = radarRoot._lat2tile(topLeft.latitude, z) - 1;
                    var tyMax = radarRoot._lat2tile(bottomRight.latitude, z) + 1;
                    var maxTile = Math.pow(2, z) - 1;
                    txMin = Math.max(0, txMin); txMax = Math.min(maxTile, txMax);
                    tyMin = Math.max(0, tyMin); tyMax = Math.min(maxTile, tyMax);

                    for (var tx = txMin; tx <= txMax; tx++) {
                        for (var ty = tyMin; ty <= tyMax; ty++) {
                            var url = radarRoot._tileUrl(z, tx, ty);
                            if (!url) continue;

                            // Pixel bounds of this tile on the map
                            var px  = baseMap.fromCoordinate(
                                QtPositioning.coordinate(radarRoot._tile2lat(ty,   z), radarRoot._tile2lon(tx,   z)), false);
                            var px2 = baseMap.fromCoordinate(
                                QtPositioning.coordinate(radarRoot._tile2lat(ty+1, z), radarRoot._tile2lon(tx+1, z)), false);
                            if (!px || !px2) continue;
                            var tw = Math.ceil(px2.x - px.x);
                            var th = Math.ceil(px2.y - px.y);
                            if (tw <= 0 || th <= 0) continue;

                            if (isImageLoaded(url)) {
                                ctx.drawImage(url, px.x, px.y, tw, th);
                            } else if (!_requested[url]) {
                                _requested[url] = true;
                                loadImage(url);
                            }
                        }
                    }
                }

                Connections {
                    target: radarRoot
                    function onActiveLayerChanged() { overlayCanvas._clearCache(); }
                }
            }

            // ── Zoom buttons ──────────────────────────────────────────
            Column {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 4
                z: 2

                RoundButton {
                    width: 36; height: 36
                    text: "+"
                    font.pixelSize: 18
                    onClicked: baseMap.zoomLevel = Math.min(baseMap.zoomLevel + 1, 18)
                    ToolTip.visible: hovered
                    ToolTip.text: i18n("Zoom in")
                }
                RoundButton {
                    width: 36; height: 36
                    text: "−"
                    font.pixelSize: 18
                    onClicked: baseMap.zoomLevel = Math.max(baseMap.zoomLevel - 1, 2)
                    ToolTip.visible: hovered
                    ToolTip.text: i18n("Zoom out")
                }
            }

            // ── Attribution ───────────────────────────────────────────
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
                    text: radarRoot.activeLayer === "rainviewer"
                        ? "© <a href='https://www.openstreetmap.org/copyright'>OSM</a> · © <a href='https://www.rainviewer.com'>RainViewer</a>"
                        : "© <a href='https://www.openstreetmap.org/copyright'>OSM</a> · © <a href='https://openweathermap.org'>OWM</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 9
                    color: "#333"
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
        }

        // ── OWM key hint ──────────────────────────────────────────────
        Label {
            Layout.fillWidth: true
            visible: radarRoot.owmKey === ""
            text: i18n("Radar layer (RainViewer) is always free. Add an OpenWeatherMap API key in Settings → General to unlock Rain, Clouds, Temperature, Wind and Pressure layers.")
            color: Kirigami.Theme.textColor
            opacity: 0.55
            font.pixelSize: 9
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    function reload() {
        _fetchRainviewer();
        overlayCanvas.requestPaint();
    }
}
