/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * RadarView.qml — Interactive weather radar map using WebEngineView + Leaflet
 *
 * GPU-accelerated tile compositing identical to rainviewer.com.
 * Leaflet runs inside an embedded Chromium (QtWebEngine) instance.
 * KDE layer buttons communicate with Leaflet via runJavaScript().
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtWebEngine
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: radarRoot

    property var weatherRoot

    readonly property double lat:    weatherRoot ? (Plasmoid.configuration.latitude  || 0) : 0
    readonly property double lon:    weatherRoot ? (Plasmoid.configuration.longitude || 0) : 0
    readonly property string owmKey: Plasmoid.configuration.owApiKey || ""
    readonly property string activeLayer: Plasmoid.configuration.radarLayer || "rainviewer"

    readonly property var localeInfo: {
        var d = new Date(2025, 0, 31); // January 31
        var s = d.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
        var dayFirst = s.indexOf("31") < s.search(/1|01/);
        var yearFirst = s.indexOf("2025") === 0;
        var sepMatch = s.match(/[0-9]([^0-9])[0-9]/);
        return {
            "dayFirst": dayFirst,
            "yearFirst": yearFirst,
            "sep": sepMatch ? sepMatch[1] : "."
        };
    }
    readonly property string systemLocale: Qt.locale().name
    readonly property bool is24h: {
        var f = Qt.locale().timeFormat(Locale.ShortFormat);
        return f.indexOf('H') !== -1 || f.indexOf('k') !== -1;
    }

    implicitHeight: 380

    // ── Wi-font icon loader ───────────────────────────────────────────────
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }
    readonly property bool wiFontReady: wiFont.status === FontLoader.Ready
    readonly property string wiFontFamily: wiFontReady ? wiFont.font.family : ""

    // ── Layer definitions ────────────────────────────────────────────────
    readonly property var layers: [
        { id: "rainviewer",        label: i18n("Radar"),       glyph: "\uF01D", freeKey: true  },
        { id: "precipitation_new", label: i18n("Rain"),        glyph: "\uF019", freeKey: false },
        { id: "clouds_new",        label: i18n("Clouds"),      glyph: "\uF041", freeKey: false },
        { id: "temp_new",          label: i18n("Temperature"), glyph: "\uF055", freeKey: false },
        { id: "wind_new",          label: i18n("Wind"),        glyph: "\uF050", freeKey: false },
        { id: "pressure_new",      label: i18n("Pressure"),    glyph: "\uF079", freeKey: false }
    ]

    // ── Build the Leaflet HTML page ──────────────────────────────────────
    function _buildHtml(lat, lon, owmKey, layer) {
        var owmKeyJs   = JSON.stringify(owmKey || "");
        var layerJs    = JSON.stringify(layer  || "rainviewer");
        var fontFamily = JSON.stringify(Kirigami.Theme.defaultFont.family || "sans-serif");
        var titlePrev  = JSON.stringify(i18n("Recent"));
        var titlePlay  = JSON.stringify(i18n("Play"));
        var titlePause = JSON.stringify(i18n("Pause"));
        var titleNext  = JSON.stringify(i18n("Real-time"));
        var titleLoc   = JSON.stringify(i18n("Show my location"));
        var lblNone    = JSON.stringify(i18n("None"));
        var lblLight   = JSON.stringify(i18n("Light"));
        var lblMod     = JSON.stringify(i18n("Moderate"));
        var lblHeavy   = JSON.stringify(i18n("Heavy"));
        var lblStorm   = JSON.stringify(i18n("Storm"));
        var localeJs   = JSON.stringify(Qt.locale().uiLanguages);
        var locInfoJs  = JSON.stringify(radarRoot.localeInfo);
        var hour12Js   = !radarRoot.is24h;
        // KDE Breeze-style SVG icon paths (white, 16×16 viewBox)
        var svgPrev  = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill="white" d="M4 3h1.5v10H4zm7.5 0L5.5 8l6 5z"/><\/svg>';
        var svgPlay  = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill="white" d="M4 3l9 5-9 5z"/><\/svg>';
        var svgPause = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill="white" d="M4 3h3v10H4zm5 0h3v10H9z"/><\/svg>';
        var svgNext  = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill="white" d="M10.5 3H12v10h-1.5zM4.5 3l6 5-6 5z"/><\/svg>';
        var svgLoc   = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><circle cx="8" cy="8" r="3" fill="white"/><path fill="white" d="M8 1v2M8 13v2M1 8h2M13 8h2" stroke="white" stroke-width="1.5"/><circle cx="8" cy="8" r="6" fill="none" stroke="white" stroke-width="1.2"/><\/svg>';
        return '<!DOCTYPE html>\
<html>\
<head>\
<meta charset="utf-8"/>\
<meta name="viewport" content="width=device-width,initial-scale=1"/>\
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>\
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"><\/script>\
<style>\
  * { margin:0; padding:0; box-sizing:border-box; }\
  html, body, #map { width:100%; height:100%; overflow:hidden; }\
  .leaflet-control-attribution { font-size:9px !important; }\
  #controls {\
    position:absolute; top:8px; right:8px; z-index:1000;\
    display:flex; flex-direction:column; align-items:flex-end; gap:4px;\
    pointer-events:auto;\
  }\
  #ctrlRow {\
    display:flex; align-items:center; gap:4px;\
    background:rgba(0,0,0,0.55); border-radius:6px; padding:3px 6px;\
  }\
  #ctrlRow button {\
    background:none; border:none;\
    width:24px; height:24px; padding:0;\
    cursor:pointer; display:flex; align-items:center; justify-content:center;\
    border-radius:4px;\
  }\
  #ctrlRow button:hover { background:rgba(255,255,255,0.2); }\
  #ctrlRow button img { width:16px; height:16px; display:block; }\
  #slider { width:120px; height:4px; cursor:pointer; accent-color:#4fc3f7; }\
  .base-dimmed img { filter: saturate(0.8) brightness(0.85); }\
  #timeLabel { font-size:10px; font-weight:bold; color:#fff; white-space:nowrap; \
    font-family:' + fontFamily + '; background:rgba(0,0,0,0.55); border-radius:6px; padding:2px 6px; }\
<\/style>\
<\/head>\
<body>\
<div id="map"><\/div>\
<div id="controls">\
  <div id="ctrlRow">\
    <button id="btnBack"  title=' + titlePrev  + '><img src="data:image/svg+xml,' + encodeURIComponent(svgPrev)  + '"/><\/button>\
    <button id="btnPlay"  title=' + titlePlay  + '><img id="playIcon" src="data:image/svg+xml,' + encodeURIComponent(svgPlay) + '"/><\/button>\
    <button id="btnFwd"   title=' + titleNext  + '><img src="data:image/svg+xml,' + encodeURIComponent(svgNext)  + '"/><\/button>\
    <input id="slider" type="range" min="0" max="0" value="0"\/>\
    <button id="btnLoc" title=' + titleLoc   + '><img src="data:image/svg+xml,' + encodeURIComponent(svgLoc) + '"/><\/button>\
  <\/div>\
  <span id="timeLabel">Loading...<\/span>\
<\/div>\
<script>\
var LAT = ' + lat + ';\
var LON = ' + lon + ';\
var OWM_KEY = ' + owmKeyJs + ';\
var ACTIVE_LAYER = ' + layerJs + ';\
var SYS_LOCALE = ' + localeJs + ';\
var LOC_INFO = ' + locInfoJs + ';\
var HOUR12 = ' + hour12Js + ';\
var TILE_SIZE = 512;\
var RADAR_OPACITY = 0.6;\
var OWM_OPACITY  = 1.00;\
var ANIM_DELAY = 500;\
var API_URL = "https://api.rainviewer.com/public/weather-maps.json";\
\
var map = L.map("map", { zoomControl: true, attributionControl: true })\
           .setView([LAT, LON], 7);\
\
var _baseClass = (ACTIVE_LAYER !== "rainviewer") ? "base-dimmed" : "";\
L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {\
    attribution: "\u00a9 <a href=\'https://www.openstreetmap.org/copyright\'>OpenStreetMap</a> contributors",\
    maxZoom: 19,\
    className: _baseClass\
}).addTo(map);\
\
L.marker([LAT, LON]).addTo(map);\
\
var apiData = {};\
var mapFrames = [];\
var animPos = 0;\
var isPlaying = false;\
var animTimer = null;\
var currentLayer = null;\
var layerCache = {};\
var isLoading = false;\
\
function wrapPos(p, wrap) {\
    if (wrap) {\
        while (p >= mapFrames.length) p -= mapFrames.length;\
        while (p < 0) p += mapFrames.length;\
    } else {\
        if (p >= mapFrames.length) p = mapFrames.length - 1;\
        if (p < 0) p = 0;\
    }\
    return p;\
}\
\
function fmtTime(ts) {\
    var d = new Date(ts * 1000);\
    var dd = d.getDate();\
    var mm = d.getMonth() + 1;\
    var yy = d.getFullYear();\
    var ms = (mm < 10 ? "0" + mm : mm);\
    var dStr = "";\
    if (LOC_INFO.yearFirst) {\
        dStr = yy + LOC_INFO.sep + ms + LOC_INFO.sep + dd;\
    } else if (LOC_INFO.dayFirst) {\
        dStr = dd + LOC_INFO.sep + ms + LOC_INFO.sep + yy;\
    } else {\
        dStr = ms + LOC_INFO.sep + dd + LOC_INFO.sep + yy;\
    }\
    var tStr = d.toLocaleTimeString(SYS_LOCALE, { hour: "2-digit", minute: "2-digit", hour12: HOUR12 });\
    return dStr + ", " + tStr;\
}\
\
function updateUI() {\
    var slider = document.getElementById("slider");\
    var label  = document.getElementById("timeLabel");\
    slider.max   = mapFrames.length - 1;\
    slider.value = animPos;\
    if (mapFrames.length > 0) label.textContent = fmtTime(mapFrames[animPos].time);\
    document.getElementById("playIcon").src = isPlaying ? "data:image/svg+xml,' + encodeURIComponent(svgPause) + '" : "data:image/svg+xml,' + encodeURIComponent(svgPlay) + '";\
}\
\
function layerOpacity() { return ACTIVE_LAYER === "rainviewer" ? RADAR_OPACITY : OWM_OPACITY; }\
\
function createLayer(frame) {\
    if (ACTIVE_LAYER === "rainviewer") {\
        return L.tileLayer(\
            apiData.host + frame.path + "/" + TILE_SIZE + "/{z}/{x}/{y}/2/1_1.png",\
            { tileSize: 256, opacity: 0.001, maxNativeZoom: 7, maxZoom: 18, zIndex: 10 }\
        );\
    } else if (OWM_KEY) {\
        return L.tileLayer(\
            "https://tile.openweathermap.org/map/" + ACTIVE_LAYER + "/{z}/{x}/{y}.png?appid=" + OWM_KEY,\
            { opacity: 0.001, maxZoom: 18, zIndex: 10 }\
        );\
    }\
    return null;\
}\
\
function stopAnim() {\
    if (isPlaying) {\
        isPlaying = false;\
        if (animTimer) { clearTimeout(animTimer); animTimer = null; }\
        isLoading = false;\
        updateUI();\
        return true;\
    }\
    return false;\
}\
\
function scheduleNext() {\
    if (!isPlaying) return;\
    if (animPos >= mapFrames.length - 1) { stopAnim(); return; }\
    animTimer = setTimeout(function() { showFrame(animPos + 1); }, ANIM_DELAY);\
}\
\
function showFrame(pos) {\
    if (isLoading) return;\
    pos = wrapPos(pos, !isPlaying);\
    var frame = mapFrames[pos];\
    var oldLayer = currentLayer;\
    if (layerCache[pos]) {\
        layerCache[pos].setOpacity(layerOpacity());\
        if (oldLayer && oldLayer !== layerCache[pos]) oldLayer.setOpacity(0);\
        currentLayer = layerCache[pos];\
        animPos = pos;\
        updateUI();\
        scheduleNext();\
        return;\
    }\
    isLoading = true;\
    var newLayer = createLayer(frame);\
    if (!newLayer) { isLoading = false; return; }\
    newLayer.on("load", function() {\
        newLayer.setOpacity(layerOpacity());\
        if (oldLayer && oldLayer !== newLayer) oldLayer.setOpacity(0);\
        layerCache[pos] = newLayer;\
        currentLayer = newLayer;\
        animPos = pos;\
        isLoading = false;\
        updateUI();\
        scheduleNext();\
    });\
    newLayer.addTo(map);\
}\
\
function clearCache() {\
    stopAnim();\
    for (var k in layerCache) {\
        if (parseInt(k) !== animPos) { map.removeLayer(layerCache[k]); delete layerCache[k]; }\
    }\
}\
\
function initFrames(api) {\
    clearCache();\
    currentLayer = null;\
    mapFrames = [];\
    animPos = 0;\
    if (!api || !api.radar || !api.radar.past) return;\
    mapFrames = api.radar.past.concat(api.radar.nowcast || []);\
    animPos = api.radar.past.length - 1;\
    var slider = document.getElementById("slider");\
    slider.max = mapFrames.length - 1;\
    slider.value = animPos;\
    showFrame(animPos);\
}\
\
function loadApi() {\
    if (ACTIVE_LAYER !== "rainviewer") {\
        document.getElementById("ctrlRow").style.display = "none";\
        document.getElementById("timeLabel").style.display = "none";\
        mapFrames = [{ time: Date.now() / 1000, path: "" }];\
        animPos = 0;\
        showFrame(0);\
        updateUI();\
        return;\
    }\
    document.getElementById("ctrlRow").style.display = "flex";\
    document.getElementById("timeLabel").style.display = "";\
    var xhr = new XMLHttpRequest();\
    xhr.open("GET", API_URL, true);\
    xhr.onload = function() {\
        try {\
            apiData = JSON.parse(xhr.responseText);\
            initFrames(apiData);\
        } catch(e) {}\
    };\
    xhr.send();\
}\
\
var TITLE_PLAY  = ' + titlePlay  + ';\
var TITLE_PAUSE = ' + titlePause + ';\
\
function updatePlayTitle() {\
    document.getElementById("btnPlay").title = isPlaying ? TITLE_PAUSE : TITLE_PLAY;\
}\
\
document.getElementById("btnPlay").onclick  = function() {\
    if (!stopAnim()) {\
        isPlaying = true;\
        updatePlayTitle();\
        if (animPos >= mapFrames.length - 1) {\
            animPos = 0;\
            showFrame(0);\
        } else {\
            showFrame(animPos + 1);\
        }\
    } else {\
        updatePlayTitle();\
    }\
};\
document.getElementById("btnBack").onclick  = function() { stopAnim(); showFrame(0); };\
document.getElementById("btnFwd").onclick   = function() { stopAnim(); showFrame(mapFrames.length - 1); };\
document.getElementById("slider").oninput   = function() { stopAnim(); showFrame(parseInt(this.value)); };\
document.getElementById("btnLoc").onclick   = function() { map.setView([LAT, LON], 7); };\
\
map.on("movestart", clearCache);\
\
window.setLayer = function(layer, owmKey) {\
    ACTIVE_LAYER = layer;\
    OWM_KEY = owmKey || "";\
    clearCache();\
    if (currentLayer) { map.removeLayer(currentLayer); currentLayer = null; }\
    layerCache = {};\
    loadApi();\
};\
\
loadApi();\
<\/script>\
<\/body>\
<\/html>';
    }

    // ── Main layout ──────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // ── Layer selector (pill-tab style matching Details/Forecast/Radar tabs) ─
        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 17
            visible: radarRoot.owmKey !== ""
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)

            RowLayout {
                anchors { fill: parent; margins: 3 }
                spacing: 0

                Repeater {
                    model: radarRoot.layers
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isOwmLayer: !modelData.freeKey
                        readonly property bool hasOwmKey: radarRoot.owmKey !== ""
                        readonly property bool isActive: radarRoot.activeLayer === modelData.id
                        visible: !isOwmLayer || hasOwmKey
                        Layout.fillWidth: visible
                        Layout.preferredWidth: visible ? -1 : 0
                        Layout.fillHeight: true
                        radius: 14
                        color: isActive
                            ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.17)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                visible: radarRoot.wiFontReady
                                text: modelData.glyph
                                font.family: radarRoot.wiFontFamily
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                                color: Kirigami.Theme.textColor
                                opacity: parent.parent.isActive ? 1.0 : 0.42
                                verticalAlignment: Text.AlignVCenter
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }
                            Label {
                                text: modelData.label
                                color: Kirigami.Theme.textColor
                                opacity: parent.parent.isActive ? 1.0 : 0.42
                                font: weatherRoot ? weatherRoot.wf(11, parent.parent.isActive) : Qt.font({ bold: parent.parent.isActive })
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Plasmoid.configuration.radarLayer = modelData.id;
                                webView.runJavaScript(
                                    "window.setLayer(" + JSON.stringify(modelData.id) + "," + JSON.stringify(radarRoot.owmKey) + ");"
                                );
                            }
                        }
                    }
                }
            }
        }

        // ── WebEngine map ─────────────────────────────────────────────
        WebEngineView {
            id: webView
            Layout.fillWidth: true
            Layout.fillHeight: true

            settings.javascriptEnabled: true
            settings.localContentCanAccessRemoteUrls: true
            settings.localContentCanAccessFileUrls: true

            // Prevent popups / navigation away from our page
            onNewWindowRequested: function(req) { Qt.openUrlExternally(req.requestedUrl); }

            Component.onCompleted: {
                var html = radarRoot._buildHtml(radarRoot.lat, radarRoot.lon, radarRoot.owmKey, radarRoot.activeLayer);
                webView.loadHtml(html, "https://rainviewer.com/");
            }

            // Reload when lat/lon change (location change)
            Connections {
                target: radarRoot
                function onLatChanged() {
                    var html = radarRoot._buildHtml(radarRoot.lat, radarRoot.lon, radarRoot.owmKey, radarRoot.activeLayer);
                    webView.loadHtml(html, "https://rainviewer.com/");
                }
                function onLonChanged() {
                    var html = radarRoot._buildHtml(radarRoot.lat, radarRoot.lon, radarRoot.owmKey, radarRoot.activeLayer);
                    webView.loadHtml(html, "https://rainviewer.com/");
                }
            }
        }

        // ── Legend bar ────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            height: 18

            readonly property bool isImperial: {
                var mode = Plasmoid.configuration.unitsMode || "metric";
                if (mode === "kde") return Qt.locale().measurementSystem === 1;
                return (Plasmoid.configuration.temperatureUnit || "C") === "F";
            }
            readonly property string precipUnit: (Plasmoid.configuration.precipitationUnit || "mm") === "in" ? "in/h" : "mm/h"
            readonly property string windUnit:   Plasmoid.configuration.windSpeedUnit || "kmh"
            readonly property string pressUnit:  Plasmoid.configuration.pressureUnit  || "hPa"
            readonly property string tempUnit:   (Plasmoid.configuration.temperatureUnit || "C") === "F" ? "°F" : "°C"

            readonly property var legendData: ({
                "rainviewer":        { stops: ["rgba(0,0,0,0)","#aaddff","#00ccee","#0088cc","#ffff00","#ffaa00","#ff4400","#ff00cc","#ff88ff","#ffffff"] },
                "precipitation_new": { stops: ["rgba(225,200,100,0)","rgba(110,110,205,0.3)","rgba(80,80,225,0.7)","rgba(20,20,255,0.9)"] },
                "clouds_new":        { stops: ["rgba(255,255,255,0)","rgba(249,248,255,0.4)","rgba(246,245,255,0.75)","rgba(244,244,255,1)","rgba(240,240,255,1)"], labels: ["0%","40%","60%","80%","100%"] },
                "temp_new":          { stops: ["rgba(130,22,146,1)","rgba(130,87,219,1)","rgba(32,140,236,1)","rgba(32,196,232,1)","rgba(35,221,221,1)","rgba(194,255,40,1)","rgba(255,240,40,1)","rgba(255,194,40,1)","rgba(252,128,20,1)"] },
                "wind_new":          { stops: ["rgba(255,255,255,0)","rgba(238,206,206,0.4)","rgba(179,100,188,0.7)","rgba(63,33,59,0.8)","rgba(116,76,172,0.9)","rgba(70,0,175,1)","rgba(13,17,38,1)"] },
                "pressure_new":      { stops: ["rgba(0,115,255,1)","rgba(0,170,255,1)","rgba(75,208,214,1)","rgba(141,231,199,1)","rgba(176,247,32,1)","rgba(240,184,0,1)","rgba(251,85,21,1)","rgba(243,54,59,1)","rgba(198,0,0,1)"] }
            })

            function labelsFor(layer) {
                var pu = precipUnit, wu = windUnit, pu2 = pressUnit, tu = tempUnit;
                var imp = isImperial;
                if (layer === "rainviewer")        return [i18n("None"), i18n("Light"), i18n("Mod"), i18n("Heavy"), i18n("Storm")];
                if (layer === "precipitation_new") return imp ? ["0","0.04","0.4","5.5 in/h"] : ["0","1","25","100 mm/h"];
                if (layer === "clouds_new")        return ["0%","40%","60%","80%","100%"];
                if (layer === "temp_new")          return imp ? ["-40°","-4°","32°","50°","68°","86°F"] : ["-40°","-20°","0°","10°","20°","30°C"];
                if (layer === "wind_new") {
                    if (wu === "mph")  return ["0","11","34","56","112","224 mph"];
                    if (wu === "kmh")  return ["0","18","54","90","180","360 km/h"];
                    if (wu === "kn")   return ["0","10","29","49","97","194 kn"];
                    return ["0","5","15","25","50","100 m/s"];
                }
                if (layer === "pressure_new") {
                    if (pu2 === "inHg") return ["27.8","28.4","29.0","29.5","29.8","30.1","30.7","31.3","31.9 inHg"];
                    if (pu2 === "mmHg") return ["705","720","735","750","758","765","780","795","810 mmHg"];
                    return ["940","960","980","1000","1010","1020","1040","1060","1080 hPa"];
                }
                return [];
            }

            property var ld: legendData[radarRoot.activeLayer] || legendData["rainviewer"]

            Canvas {
                id: legendCanvas
                anchors.fill: parent
                property var ld: parent.ld
                onLdChanged: requestPaint()
                Connections {
                    target: radarRoot
                    function onActiveLayerChanged() { legendCanvas.requestPaint(); }
                }
                Connections {
                    target: legendCanvas.parent
                    function onIsImperialChanged() { legendCanvas.requestPaint(); }
                    function onWindUnitChanged()   { legendCanvas.requestPaint(); }
                    function onPressUnitChanged()  { legendCanvas.requestPaint(); }
                }
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    var s = ld.stops;
                    var l = parent.labelsFor(radarRoot.activeLayer);
                    var grad = ctx.createLinearGradient(0, 0, width, 0);
                    for (var i = 0; i < s.length; i++) grad.addColorStop(i / (s.length - 1), s[i]);
                    ctx.fillStyle = grad;
                    ctx.fillRect(0, 0, width, height);
                    ctx.strokeStyle = Qt.rgba(0.5,0.5,0.5,0.4);
                    ctx.strokeRect(0, 0, width, height);
                    var pad = 4;
                    ctx.font = "bold 10px sans-serif";
                    ctx.textBaseline = "middle";
                    for (var j = 0; j < l.length; j++) {
                        var x;
                        if (j === 0) { ctx.textAlign = "left";   x = pad; }
                        else if (j === l.length - 1) { ctx.textAlign = "right";  x = width - pad; }
                        else { ctx.textAlign = "center"; x = j / (l.length - 1) * width; }
                        ctx.shadowColor = "black";
                        ctx.shadowBlur = 3;
                        ctx.fillStyle = "white";
                        ctx.fillText(l[j], x, height / 2);
                        ctx.shadowBlur = 0;
                    }
                }
            }
        }

    }

    function reload() {
        var html = radarRoot._buildHtml(radarRoot.lat, radarRoot.lon, radarRoot.owmKey, radarRoot.activeLayer);
        webView.loadHtml(html, "https://rainviewer.com/");
    }
}
