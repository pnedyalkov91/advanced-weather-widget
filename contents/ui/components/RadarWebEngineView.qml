/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * RadarWebEngineView.qml - Interactive weather radar map using WebEngineView + Leaflet
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
import "../providers/mapProviders.js" as MapProvidersJS

Item {
    id: radarRoot

    property var weatherRoot

    readonly property double lat:    weatherRoot ? (Plasmoid.configuration.latitude  || 0) : 0
    readonly property double lon:    weatherRoot ? (Plasmoid.configuration.longitude || 0) : 0
    readonly property string owmKey: Plasmoid.configuration.owApiKey || ""
    // Plasmoid.configuration.radarLayer should only ever be "rainviewer" or one
    // of the layers[] ids below. It has been observed holding "librewxr" -
    // a value that belongs in the separate radarProvider key instead - which
    // silently took the "OWM overlay, no key" branch everywhere downstream
    // (no RainViewer API call, createLayer() returns null, nothing renders).
    // Guard against any value we don't recognize rather than trusting it.
    readonly property string activeLayer: {
        var v = Plasmoid.configuration.radarLayer || "rainviewer";
        for (var i = 0; i < layers.length; i++) {
            if (layers[i].id === v) return v;
        }
        console.warn("[Advanced Weather Widget Radar/WebEngine] radarLayer config has unrecognized value:", v, "- falling back to rainviewer");
        return "rainviewer";
    }
    readonly property int    initialZoom: Plasmoid.configuration.radarZoom || 9
    readonly property string mapBackground: Plasmoid.configuration.mapBackground || "auto"
    /** Set while the in-map layer button is what changed the background. */
    property bool _backgroundFromMap: false

    // The RainViewer weather-maps.json fetch used to be done with an XHR
    // *inside* the WebEngineView page. Pages created via loadHtml() can end
    // up with an opaque/unique security origin in QtWebEngine even when a
    // baseUrl is given, which makes that in-page XHR fail as a silent CORS
    // error (no onerror before this fix) - the base map (image tiles, which
    // aren't subject to CORS) still renders fine, so nothing *looked* broken
    // except the missing radar overlay. We now also fetch this JSON from the
    // QML/JS engine, which isn't a browser security context and isn't
    // affected by that restriction, and push the result into the page.
    property string rainviewerApiJson: ""
    property bool webViewPageReady: false

    onRainviewerApiJsonChanged: _pushApiToPage()
    onWebViewPageReadyChanged: _pushApiToPage()

    function _pushApiToPage() {
        if (!webViewPageReady || !rainviewerApiJson) return;
        webView.runJavaScript("window.applyRainviewerApi && window.applyRainviewerApi(" + JSON.stringify(rainviewerApiJson) + "," + JSON.stringify(_frameLabels(rainviewerApiJson)) + ");");
    }

    // The time shown for each radar frame follows Settings → Misc → Date and
    // Time. Qt formats it here (the page cannot read Qt date patterns); the
    // page looks the text up by frame timestamp and falls back to its own
    // formatting for a timestamp it was not given.
    function _frameLabels(jsonText) {
        var out = {};
        if (!weatherRoot || !jsonText)
            return out;
        try {
            var radar = JSON.parse(jsonText).radar || {};
            var frames = (radar.past || []).concat(radar.nowcast || []);
            for (var i = 0; i < frames.length; i++) {
                var d = new Date(frames[i].time * 1000);
                out[frames[i].time] = weatherRoot.formatDateObj(d, false) + ", " + weatherRoot.formatTimeObj(d);
            }
        } catch (e) {}
        return out;
    }

    // Changing the format re-labels the frames without rebuilding the map.
    readonly property string _formatKey: weatherRoot ? (weatherRoot.dateFormatSetting + "|" + weatherRoot.timeFormatSetting) : ""
    on_FormatKeyChanged: {
        if (webViewPageReady && rainviewerApiJson)
            webView.runJavaScript("window.setTimeLabels && window.setTimeLabels(" + JSON.stringify(_frameLabels(rainviewerApiJson)) + ");");
    }

    function _fetchRainviewerApi() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.rainviewer.com/public/weather-maps.json", true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                console.log("[Advanced Weather Widget Radar/WebEngine] host-side RainViewer API fetch OK; length=", xhr.responseText.length);
                radarRoot.rainviewerApiJson = xhr.responseText;
            } else {
                console.warn("[Advanced Weather Widget Radar/WebEngine] host-side RainViewer API fetch failed; status=", xhr.status);
            }
        };
        xhr.onerror = function() {
            console.warn("[Advanced Weather Widget Radar/WebEngine] host-side RainViewer API fetch network error");
        };
        xhr.send();
    }

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

    Component.onCompleted: {
        console.log("[Advanced Weather Widget Radar/WebEngine] component completed; lat=", lat,
                    "lon=", lon, "layer=", activeLayer,
                    "zoom=", initialZoom, "owmKeyPresent=", owmKey.length > 0,
                    "qt=", Qt.version, "platform=", Qt.platform.os);
        _fetchRainviewerApi();
    }

    // ── Wi-font icon loader ───────────────────────────────────────────────
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../../fonts/weathericons-regular-webfont.ttf")
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

    // ── Base map choices offered by the in-map layer button ──────────────
    // RainViewer has no light/dark theme of its own, so themeHint stays empty
    // and "auto" resolves to the standard OSM tiles this map always used.
    readonly property MapBackgroundChoices backgroundChoices: MapBackgroundChoices {}

    // ── Build the Leaflet HTML page ──────────────────────────────────────
    function _buildHtml(lat, lon, owmKey, layer, initZoom, mapBackground) {
        var owmKeyJs   = JSON.stringify(owmKey || "");
        var layerJs    = JSON.stringify(layer  || "rainviewer");
        var baseMap    = MapProvidersJS.resolveMapBackground(mapBackground);
        // A vector background has no raster template; the page starts on plain
        // OSM tiles and swaps itself over once MapLibre has loaded.
        var baseUrlJs  = JSON.stringify(baseMap.tileUrlTemplate
                                        || MapProvidersJS.MAP_BACKGROUNDS[MapProvidersJS.DEFAULT_MAP_BACKGROUND].tileUrlTemplate);
        var baseAttrJs = JSON.stringify(baseMap.attribution);
        var bgListJs   = radarRoot.backgroundChoices.toJson();
        var bgCurrJs   = JSON.stringify(mapBackground || "auto");
        var titleBg    = JSON.stringify(i18n("Map background"));
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
        var svgLayers = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill="white" d="M8 1.5L1.5 5 8 8.5 14.5 5 8 1.5z"/><path fill="none" stroke="white" stroke-width="1.3" d="M1.8 8.2L8 11.5l6.2-3.3M1.8 11.2L8 14.5l6.2-3.3"/><\/svg>';
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
  /* Dark OSM: the same standard raster, recoloured here. Scoped to the base\
     layer container, never to the tile pane, which this map shares with the\
     radar and OWM overlays: filtering the pane would invert them too. */\
  .base-inverted img { filter: invert(1) hue-rotate(180deg) brightness(0.9) contrast(0.9) saturate(0.8); }\
  .base-inverted.base-dimmed img { filter: invert(1) hue-rotate(180deg) brightness(0.78) contrast(0.9) saturate(0.65); }\
  #timeLabel { font-size:10px; font-weight:bold; color:#fff; white-space:nowrap; \
    font-family:' + fontFamily + '; background:rgba(0,0,0,0.55); border-radius:6px; padding:2px 6px; }\
  /* Sits inside #controls, under the player row, so the layers button is in\
     the same corner as the one on the LibreWXR map. */\
  #bgControl {\
    display:flex; flex-direction:column; align-items:flex-end; gap:4px;\
    font-family:' + fontFamily + ';\
  }\
  #btnBg {\
    background:rgba(0,0,0,0.55); border:none; border-radius:6px;\
    width:28px; height:28px; padding:0; cursor:pointer;\
    display:flex; align-items:center; justify-content:center;\
  }\
  #btnBg:hover { background:rgba(0,0,0,0.75); }\
  #btnBg img { width:16px; height:16px; display:block; }\
  #bgMenu {\
    display:none; background:rgba(0,0,0,0.75); border-radius:6px; padding:4px;\
  }\
  #bgMenu div {\
    color:#fff; font-size:11px; padding:4px 8px; border-radius:4px;\
    cursor:pointer; white-space:nowrap;\
  }\
  #bgMenu div:hover { background:rgba(255,255,255,0.2); }\
  #bgMenu div.active { font-weight:bold; }\
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
  <div id="bgControl">\
    <button id="btnBg" title=' + titleBg + '><img src="data:image/svg+xml,' + encodeURIComponent(svgLayers) + '"/><\/button>\
    <div id="bgMenu"><\/div>\
  <\/div>\
<\/div>\
<script>\
var LAT = ' + lat + ';\
var LON = ' + lon + ';\
var INIT_ZOOM = ' + initZoom + ';\
var OWM_KEY = ' + owmKeyJs + ';\
var ACTIVE_LAYER = ' + layerJs + ';\
var SYS_LOCALE = ' + localeJs + ';\
var LOC_INFO = ' + locInfoJs + ';\
var HOUR12 = ' + hour12Js + ';\
var BASE_TILE_URL = ' + baseUrlJs + ';\
var BASE_ATTRIBUTION = ' + baseAttrJs + ';\
var BASE_MAX_ZOOM = ' + baseMap.maxZoom + ';\
var BG_LIST = ' + bgListJs + ';\
var BG_CURRENT = ' + bgCurrJs + ';\
/* Backgrounds stop at different zoom levels (OpenTopoMap at 17, OSM at 19),\
   and radarZoom goes up to 18. Past its own maxZoom a Leaflet layer renders\
   nothing at all, which would leave the base map blank under the radar, so\
   cap every background at the same MAP_MAX_ZOOM and let Leaflet upscale the\
   deepest tiles it does have through maxNativeZoom. */\
var MAP_MAX_ZOOM = 19;\
var TILE_SIZE = 512;\
var RADAR_OPACITY = 0.6;\
var OWM_OPACITY  = 1.00;\
var ANIM_DELAY = 500;\
var API_URL = "https://api.rainviewer.com/public/weather-maps.json";\
var TIME_LABELS = {};\
\
var map = L.map("map", { zoomControl: true, attributionControl: true })\
           .setView([LAT, LON], INIT_ZOOM);\
\
map.on("zoomend", function() { document.title = "zoom:" + map.getZoom(); });\
\
/* Leaflet splits this on whitespace, so both classes can ride along. */\
var _baseClass = ((ACTIVE_LAYER !== "rainviewer") ? "base-dimmed " : "")\
    + (bgEntry(BG_CURRENT).invert ? "base-inverted" : "");\
var baseLayer = L.tileLayer(BASE_TILE_URL, {\
    attribution: BASE_ATTRIBUTION,\
    maxNativeZoom: BASE_MAX_ZOOM,\
    maxZoom: MAP_MAX_ZOOM,\
    className: _baseClass,\
    zIndex: 1\
}).addTo(map);\
\
L.marker([LAT, LON]).addTo(map);\
\
/* baseLayer above is always raster. If the saved background is a vector style,\
   fetch MapLibre and swap it in; applyBackground is hoisted, BG_LIST is set. */\
(function() {\
    var e0 = bgEntry(BG_CURRENT);\
    if (e0 && e0.vector && e0.styleUrl) loadMapLibre(function() { applyBackground(BG_CURRENT); });\
})();\
\
var apiData = {};\
var mapFrames = [];\
var animPos = 0;\
var isPlaying = false;\
var animTimer = null;\
var currentLayer = null;\
var layerCache = {};\
var isLoading = false;\
var cachedApiJson = null;\
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
    if (TIME_LABELS[ts]) return TIME_LABELS[ts];\
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
    if (cachedApiJson) {\
        try {\
            initFrames(JSON.parse(cachedApiJson));\
            return;\
        } catch(e) { /* fall through to network fetch */ }\
    }\
    var xhr = new XMLHttpRequest();\
    xhr.open("GET", API_URL, true);\
    xhr.timeout = 8000;\
    xhr.onload = function() {\
        if (xhr.status !== 200) {\
            console.error("[radar] RainViewer API HTTP " + xhr.status + " " + xhr.statusText);\
            return;\
        }\
        try {\
            apiData = JSON.parse(xhr.responseText);\
            cachedApiJson = xhr.responseText;\
            initFrames(apiData);\
        } catch(e) {\
            console.error("[radar] RainViewer API JSON parse failed: " + e);\
        }\
    };\
    xhr.onerror = function() {\
        console.error("[radar] RainViewer API request failed (network/CORS) - waiting for host-side fetch");\
    };\
    xhr.ontimeout = function() {\
        console.error("[radar] RainViewer API request timed out - waiting for host-side fetch");\
    };\
    xhr.send();\
}\
\
/* Fallback / primary data path: QML runs outside the page\'s browser security\
 * context, so it is not subject to the CORS restrictions that can silently\
 * kill the in-page XHR above (e.g. the opaque origin QtWebEngine sometimes\
 * assigns to pages created via loadHtml()). radarRoot fetches\
 * weather-maps.json itself and calls this once it has the data. */\
window.applyRainviewerApi = function(jsonText, labels) {\
    if (labels) TIME_LABELS = labels;\
    cachedApiJson = jsonText;\
    if (ACTIVE_LAYER !== "rainviewer") return;\
    try {\
        apiData = JSON.parse(jsonText);\
        initFrames(apiData);\
    } catch(e) {\
        console.error("[radar] applyRainviewerApi parse failed: " + e);\
    }\
};\
\
window.setTimeLabels = function(labels) {\
    TIME_LABELS = labels || {};\
    if (mapFrames.length > 0) updateUI();\
};\
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
document.getElementById("btnLoc").onclick   = function() { map.setView([LAT, LON], map.getZoom()); };\
\
map.on("movestart", clearCache);\
\
function bgEntry(id) {\
    for (var i = 0; i < BG_LIST.length; i++) if (BG_LIST[i].id === id) return BG_LIST[i];\
    return BG_LIST[0];\
}\
\
/* Keep the base map dimmed while an OWM overlay is on top, so precipitation\
   stays readable. Applied to the live container, since the class has to follow\
   layer switches and not just the initial page load.\
   Block comment on purpose: this script is emitted as a single line. */\
function updateBaseDim() {\
    if (!baseLayer) return;\
    var c = baseLayer.getContainer();\
    if (!c) return;\
    if (ACTIVE_LAYER !== "rainviewer") c.classList.add("base-dimmed");\
    else c.classList.remove("base-dimmed");\
    if (bgEntry(BG_CURRENT).invert) c.classList.add("base-inverted");\
    else c.classList.remove("base-inverted");\
}\
\
/* MapLibre is only fetched when a vector background is actually picked: it is\
   an 800 kB script and every raster background works without it. Until it\
   lands, the vector entry shows plain OSM tiles. */\
var MAPLIBRE_STATE = "idle";\
/* MapLibre needs a WebGL context. Where there is none - blacklisted GPU, a VM,\
   software rendering off - creating the layer throws and the map is left with\
   no background at all, so check first and stay on raster tiles instead. */\
var WEBGL_OK = null;\
function hasWebGL() {\
    if (WEBGL_OK !== null) return WEBGL_OK;\
    try {\
        var c = document.createElement("canvas");\
        WEBGL_OK = !!(c.getContext("webgl2") || c.getContext("webgl"));\
    } catch (e) { WEBGL_OK = false; }\
    return WEBGL_OK;\
}\
function loadMapLibre(onReady) {\
    if (MAPLIBRE_STATE === "ready") { onReady(); return; }\
    if (MAPLIBRE_STATE !== "idle") return;\
    MAPLIBRE_STATE = "loading";\
    var css = document.createElement("link");\
    css.rel = "stylesheet";\
    css.href = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css";\
    document.head.appendChild(css);\
    var gl = document.createElement("script");\
    gl.src = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js";\
    gl.onerror = function() { MAPLIBRE_STATE = "failed"; };\
    gl.onload = function() {\
        var br = document.createElement("script");\
        br.src = "https://unpkg.com/@maplibre/maplibre-gl-leaflet@0.0.22/leaflet-maplibre-gl.js";\
        br.onerror = function() { MAPLIBRE_STATE = "failed"; };\
        br.onload = function() { MAPLIBRE_STATE = "ready"; onReady(); };\
        document.head.appendChild(br);\
    };\
    document.head.appendChild(gl);\
}\
\
function applyBackground(id) {\
    var e = bgEntry(id);\
    BG_CURRENT = e.id;\
    var wantsVector = !!(e.vector && e.styleUrl && hasWebGL());\
    if (wantsVector && MAPLIBRE_STATE !== "ready") {\
        loadMapLibre(function() { applyBackground(BG_CURRENT); });\
    }\
    var next = null;\
    if (wantsVector && MAPLIBRE_STATE === "ready") {\
        try {\
            next = L.maplibreGL({ style: e.styleUrl, attribution: e.attribution }).addTo(map);\
        } catch (err) { WEBGL_OK = false; }\
    }\
    if (!next) {\
        next = L.tileLayer(e.url || BASE_TILE_URL, {\
            attribution: e.attribution,\
            maxNativeZoom: e.maxZoom,\
            maxZoom: MAP_MAX_ZOOM,\
            zIndex: 1\
        }).addTo(map);\
    }\
    if (baseLayer) map.removeLayer(baseLayer);\
    baseLayer = next;\
    updateBaseDim();\
    renderBgMenu();\
}\
\
function renderBgMenu() {\
    var menu = document.getElementById("bgMenu");\
    menu.innerHTML = "";\
    for (var i = 0; i < BG_LIST.length; i++) {\
        (function(entry) {\
            var row = document.createElement("div");\
            row.textContent = entry.label;\
            if (entry.id === BG_CURRENT) row.className = "active";\
            row.onclick = function(ev) {\
                ev.stopPropagation();\
                menu.style.display = "none";\
                if (entry.id === BG_CURRENT) return;\
                applyBackground(entry.id);\
                document.title = "bg:" + entry.id;\
            };\
            menu.appendChild(row);\
        })(BG_LIST[i]);\
    }\
}\
\
document.getElementById("btnBg").onclick = function(ev) {\
    ev.stopPropagation();\
    var menu = document.getElementById("bgMenu");\
    menu.style.display = (menu.style.display === "block") ? "none" : "block";\
};\
document.addEventListener("click", function() {\
    document.getElementById("bgMenu").style.display = "none";\
});\
renderBgMenu();\
\
window.setBackground = function(id) {\
    if (id !== BG_CURRENT) applyBackground(id);\
};\
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

            // Disable the native Chromium context menu (Back/Forward/Reload/Save page/View source).
            // Radar reload is handled by the header Refresh button instead, for a consistent UI.
            onContextMenuRequested: function(request) { request.accepted = true; }

            Component.onCompleted: {
                var html = radarRoot._buildHtml(radarRoot.lat, radarRoot.lon, radarRoot.owmKey, radarRoot.activeLayer, radarRoot.initialZoom, radarRoot.mapBackground);
                console.log("[Advanced Weather Widget Radar/WebEngine] WebEngineView completed; calling loadHtml, htmlLength=", html.length);
                radarRoot.webViewPageReady = false;
                webView.loadHtml(html, "https://rainviewer.com/");
            }

            // Surface console.log/warn/error from inside the page (RainViewer
            // XHR failures, Leaflet errors, etc.) in Plasma's own log output -
            // otherwise failures inside the sandboxed page are invisible.
            onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                console.log("[Advanced Weather Widget Radar/WebEngine][page console]", message, "(line", lineNumber + ")");
            }

            onLoadingChanged: function(loadRequest) {
                console.log("[Advanced Weather Widget Radar/WebEngine] loading changed:",
                            "status=", loadRequest.status,
                            "url=", loadRequest.url,
                            "errorCode=", loadRequest.errorCode,
                            "error=", loadRequest.errorString);
                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    radarRoot.webViewPageReady = true;
                }
            }

            onRenderProcessTerminated: function(terminationStatus, exitCode) {
                console.warn("[Advanced Weather Widget Radar/WebEngine] render process terminated:",
                             "status=", terminationStatus, "exitCode=", exitCode);
            }

            onTitleChanged: {
                if (title.indexOf("zoom:") === 0) {
                    var z = parseInt(title.substring(5));
                    if (!isNaN(z) && z !== Plasmoid.configuration.radarZoom) {
                        Plasmoid.configuration.radarZoom = z;
                    }
                } else if (title.indexOf("bg:") === 0) {
                    // Picked from the in-map layer button: the page already swapped
                    // its tiles, so persist the choice without reloading the page.
                    var bg = title.substring(3);
                    if (bg.length > 0 && bg !== Plasmoid.configuration.mapBackground) {
                        radarRoot._backgroundFromMap = true;
                        Plasmoid.configuration.mapBackground = bg;
                    }
                }
            }

            // Reload when lat/lon change (location change)
            Connections {
                target: radarRoot
                function onLatChanged() {
                    var html = radarRoot._buildHtml(radarRoot.lat, radarRoot.lon, radarRoot.owmKey, radarRoot.activeLayer, radarRoot.initialZoom, radarRoot.mapBackground);
                    console.log("[Advanced Weather Widget Radar/WebEngine] latitude changed; reloading html, lat=", radarRoot.lat, "lon=", radarRoot.lon);
                    radarRoot.webViewPageReady = false;
                    radarRoot._fetchRainviewerApi();
                    webView.loadHtml(html, "https://rainviewer.com/");
                }
                function onLonChanged() {
                    var html = radarRoot._buildHtml(radarRoot.lat, radarRoot.lon, radarRoot.owmKey, radarRoot.activeLayer, radarRoot.initialZoom, radarRoot.mapBackground);
                    console.log("[Advanced Weather Widget Radar/WebEngine] longitude changed; reloading html, lat=", radarRoot.lat, "lon=", radarRoot.lon);
                    radarRoot.webViewPageReady = false;
                    radarRoot._fetchRainviewerApi();
                    webView.loadHtml(html, "https://rainviewer.com/");
                }
                function onMapBackgroundChanged() {
                    if (radarRoot._backgroundFromMap) {
                        // The map itself made the change; swapping tiles again
                        // would throw away the current pan and zoom.
                        radarRoot._backgroundFromMap = false;
                        return;
                    }
                    console.log("[Advanced Weather Widget Radar/WebEngine] map background changed; background=", radarRoot.mapBackground);
                    webView.runJavaScript("window.setBackground(" + JSON.stringify(radarRoot.mapBackground) + ");");
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
                console.log("[Advanced Weather Widget Radar/WebEngine] generating labels for layer:", layer);
                if (layer === "rainviewer")        return [i18n("None"), i18n("Light"), i18n("Mod"), i18n("Heavy"), i18n("Storm")];
                if (layer === "precipitation_new") return imp ? ["0","0.04","0.4","5.5 " + i18n("in/h")] : ["0","1","25","100 " + i18n("mm/h")];
                if (layer === "clouds_new")        return ["0%","40%","60%","80%","100%"];
                if (layer === "temp_new")          return imp ? ["-40°","-4°","32°","50°","68°","86°F"] : ["-40°","-20°","0°","10°","20°","30°C"];
                if (layer === "wind_new") {
                    if (wu === "mph")  return ["0","11","34","56","112","224 " + i18n("mph")];
                    if (wu === "kmh")  return ["0","18","54","90","180","360 " + i18n("km/h")];
                    if (wu === "kn")   return ["0","10","29","49","97","194 " + i18n("kn")];
                    return ["0","5","15","25","50","100 " + i18n("m/s")];
                }
                if (layer === "pressure_new") {
                    if (pu2 === "inHg") return ["27.8","28.4","29.0","29.5","29.8","30.1","30.7","31.3","31.9 " + i18n("inHg")];
                    if (pu2 === "mmHg") return ["705","720","735","750","758","765","780","795","810 " + i18n("mmHg")];
                    return ["940","960","980","1000","1010","1020","1040","1060","1080 " + i18n("hPa")];
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
        var html = radarRoot._buildHtml(radarRoot.lat, radarRoot.lon, radarRoot.owmKey, radarRoot.activeLayer, radarRoot.initialZoom, radarRoot.mapBackground);
        console.log("[Advanced Weather Widget Radar/WebEngine] reload; htmlLength=", html.length,
                    "lat=", radarRoot.lat, "lon=", radarRoot.lon,
                    "layer=", radarRoot.activeLayer);
        radarRoot.webViewPageReady = false;
        radarRoot._fetchRainviewerApi();
        webView.loadHtml(html, "https://rainviewer.com/");
    }
}
