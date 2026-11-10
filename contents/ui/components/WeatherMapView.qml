/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * WeatherMapView.qml - the Weather Map tab: the LibreWXR map page
 * (components/librewxr-map.html, MapLibre) playing the weather from days
 * before to days ahead, with its layers in a column at the right
 * (weathermap/LayerPanel.qml) and the time bar under it
 * (weathermap/TimeBar.qml).
 *
 * The page draws the pictures (window.anim*, glue-controls.js); this file
 * reads window.animState() ten times a second for the bar, and keeps the
 * user's choices in Plasmoid.configuration (weatherMap* and librewxr* keys).
 * Radar and satellite are layers of the animation, shown while the time is
 * in their range; a double click on one of their icons shows that source
 * alone, on its own range (the "solo" views below).
 *
 * The page also reports through document.title: "ready:" (awaitReady),
 * "zoom:", "proj:", "night:" and "bg:" (changes made on the map itself),
 * and through its console: "[keys] escape", "[readout] ctrl:<0|1>", and
 * "[ui] <name>" (opens a menu, for captures: see testUi()).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtWebEngine
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "../js/configUtils.js" as ConfigUtils
import "weathermap"

Item {
    id: radarRoot

    property var weatherRoot

    readonly property double lat: weatherRoot ? (Plasmoid.configuration.latitude || 0) : 0
    readonly property double lon: weatherRoot ? (Plasmoid.configuration.longitude || 0) : 0
    readonly property int initialZoom: Math.min(12, Plasmoid.configuration.radarZoom || 7)
    readonly property int colorScheme: Plasmoid.configuration.librewxrColorScheme !== undefined ? Plasmoid.configuration.librewxrColorScheme : 10
    readonly property bool arrowsOn: Plasmoid.configuration.librewxrArrows === true
    // Frame-rate budget of the wind from the settings: [base fps, ceiling fps].
    readonly property var windRate: {
        var q = Plasmoid.configuration.librewxrWindQuality || "balanced";
        if (q === "economy")
            return [8, 10];
        if (q === "smooth")
            return [20, 30];
        return [10, 20];
    }
    // Particle width from the settings, in CSS px (the page clamps it to 0.5-2).
    readonly property real windLineWidth: Plasmoid.configuration.librewxrWindLineWidth > 0 ? Plasmoid.configuration.librewxrWindLineWidth : 1
    // Particle density factor from the settings (the page keeps it within 0.5-2 by clamping the count).
    readonly property real windDensity: Plasmoid.configuration.librewxrWindDensity > 0 ? Plasmoid.configuration.librewxrWindDensity : 1
    // Flat map or globe, switched from the globe button on the map.
    readonly property string projection: Plasmoid.configuration.librewxrProjection === "globe" ? "globe" : "flat"
    // Day and night on the map, switched from the button under the globe one.
    readonly property bool dayNight: Plasmoid.configuration.librewxrDayNight !== false
    // Glow of the globe's atmosphere, in percent of full strength (Radar settings).
    readonly property int glow: Plasmoid.configuration.librewxrGlow
    // Darkness of the deep night, in percent of black (Radar settings).
    readonly property int nightDepth: Plasmoid.configuration.librewxrNightDepth
    // "Prepare the radar in advance" (Radar settings): kept loaded, the
    // hidden page prepares the latest image.
    readonly property string prepareMode: Plasmoid.configuration.radarKeepLoaded === true ? "all" : "none"
    // The wind palette in use, in the page's form: 8 "max:rrggbb" (max in
    // m/s, "inf" for the last level). Empty for the default palette, and for
    // an entry that does not read: the page then uses the default one.
    readonly property string windPalette: {
        var name = Plasmoid.configuration.librewxrWindPalette || "";
        if (!name)
            return "";
        var list = [];
        try {
            list = JSON.parse(Plasmoid.configuration.librewxrWindPalettes || "[]");
        } catch (e) {
            return "";
        }
        for (var i = 0; i < list.length; i++) {
            var levels = list[i].levels;
            if (list[i].name !== name || !levels || levels.length !== 8)
                continue;
            return levels.map(function (l, k) {
                return (k === 7 ? "inf" : String(Math.round(Number(l.max) * 1000) / 1000)) + ":" + String(l.color).replace("#", "");
            }).join(",");
        }
        return "";
    }
    // The temperature palette in use, in the page's form: "t:rrggbb" points,
    // t in °C; the vivid palette for an entry that does not read.
    readonly property string tempPalette: ConfigUtils.formatTempPalette(ConfigUtils.tempPaletteStops(Plasmoid.configuration.librewxrTempPalette || "", Plasmoid.configuration.librewxrTempPalettes || "[]"))
    // Coasts and borders drawn over the color layers (the settings of the column).
    readonly property bool mapLinesOn: Plasmoid.configuration.librewxrMapLines !== false
    readonly property int tempOpacity: Plasmoid.configuration.librewxrTempOpacity >= 0 ? Plasmoid.configuration.librewxrTempOpacity : 45
    readonly property real tempStep: Plasmoid.configuration.librewxrTempStep
    // The widget's temperature unit, which the bands and the legend follow.
    readonly property string tempUnit: ConfigUtils.effectiveTempUnit(Plasmoid.configuration.unitsMode, Plasmoid.configuration.temperatureUnit, Qt.locale().measurementSystem)
    // The widget's wind unit and its label, for the readout under the pointer (Ctrl).
    readonly property string windUnit: Plasmoid.configuration.windSpeedUnit || "kmh"
    readonly property string windUnitLabel: ({
            "kmh": i18n("km/h"),
            "ms": i18n("m/s"),
            "kn": i18n("kn"),
            "mph": i18n("mph")
        })[windUnit] || i18n("km/h")
    readonly property string activeCells: Plasmoid.configuration.librewxrCells || ""
    readonly property bool alertsOn: Plasmoid.configuration.librewxrAlerts === true
    readonly property bool smoothOn: Plasmoid.configuration.librewxrSmooth !== false
    readonly property bool snowOn: Plasmoid.configuration.librewxrSnow !== false
    readonly property string tileFormat: Plasmoid.configuration.librewxrFormat || "webp"
    readonly property string tileSizeChoice: Plasmoid.configuration.librewxrTileSize || "auto"
    readonly property string serverUrl: {
        var u = (Plasmoid.configuration.librewxrUrl || "https://api.librewxr.net").trim();
        while (u.length > 1 && u.charAt(u.length - 1) === "/")
            u = u.substring(0, u.length - 1);
        return u || "https://api.librewxr.net";
    }

    // Follow the Plasma theme: perceptual luminance of the theme background
    readonly property bool isDark: {
        var c = Kirigami.Theme.backgroundColor;
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) < 0.5;
    }
    readonly property string mapTheme: {
        var t = Plasmoid.configuration.librewxrTheme || "auto";
        if (t === "light" || t === "dark")
            return t;
        return isDark ? "dark" : "light";
    }

    // ── Base map background ──────────────────────────────────────────────
    // "auto" keeps the theme-driven pair this map uses (OSM in light,
    // OpenFreeMap Dark in dark); any other id pins one background
    // regardless of the theme. The page re-resolves "auto" itself on theme
    // switches, so themeHint only seeds the initial load.
    readonly property string mapBackground: Plasmoid.configuration.mapBackground || "auto"
    /** Set while the in-map picker is what changed the background. */
    property bool _backgroundFromMap: false

    readonly property MapBackgroundChoices backgroundChoices: MapBackgroundChoices {
        themeHint: radarRoot.mapTheme
        attributionSuffix: " | <a href=\"https://librewxr.net/\">LibreWXR</a>"
    }

    // Any explicitly chosen base map has a fixed light/dark style of its own,
    // so the map page ignores the theme for tile selection while one is
    // active. The Dark map switch is locked while one is selected, since
    // toggling it would have no visible effect on the map.
    readonly property bool darkMapLocked: radarRoot.mapBackground !== "auto"

    // A manual "Dark map" toggle only sticks until the Plasma theme itself
    // actually changes - at that point the override is cleared so the map
    // (and the switch) snap back to following Plasma automatically.
    property bool _themeGuardArmed: false

    Timer {
        id: themeGuardTimer
        interval: 400
        repeat: false
        onTriggered: radarRoot._themeGuardArmed = true
    }

    onIsDarkChanged: {
        if (!radarRoot._themeGuardArmed) {
            console.log("[Advanced Weather Widget Weather Map] ignoring theme read during startup settle");
            return;
        }
        if ((Plasmoid.configuration.librewxrTheme || "auto") !== "auto") {
            console.log("[Advanced Weather Widget Weather Map] Plasma theme changed; clearing manual dark-map override");
            Plasmoid.configuration.librewxrTheme = "auto";
        }
    }

    function setDarkMap(on) {
        // A manual choice overrides following the Plasma theme until the
        // Plasma theme itself changes (see onIsDarkChanged).
        Plasmoid.configuration.librewxrTheme = on ? "dark" : "light";
        call("setTheme", on ? "dark" : "light");
    }

    // 12/24-hour clock follows Settings → Misc → Date and Time.
    readonly property bool is24h: {
        if (weatherRoot)
            return weatherRoot.timeIs24h;
        var f = Qt.locale().timeFormat(Locale.ShortFormat);
        return f.indexOf('H') !== -1 || f.indexOf('k') !== -1;
    }
    /** The time of a Date as the widget writes its times. */
    function formatTime(d) {
        return weatherRoot ? weatherRoot.formatTimeObj(d) : d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    implicitHeight: 380

    // ── Blank-view workaround ────────────────────────────────────────────
    // When the plasmoid popup is closed and reopened, the Chromium surface
    // behind WebEngineView is not always recomposited, leaving a blank map
    // until the user resizes the widget. Nudging the view's size by 1 px
    // (and back) forces Chromium to produce a fresh frame - the same thing
    // a manual resize does.
    property int _repaintNudge: 0

    Timer {
        id: repaintNudgeTimer
        interval: 150
        repeat: false
        onTriggered: {
            console.log("[Advanced Weather Widget Weather Map] repaint nudge");
            radarRoot._repaintNudge = 1;
            repaintRestoreTimer.restart();
        }
    }
    Timer {
        id: repaintRestoreTimer
        interval: 60
        repeat: false
        onTriggered: radarRoot._repaintNudge = 0
    }

    onVisibleChanged: {
        if (visible)
            repaintNudgeTimer.restart();
        else
            radarRoot._pause();
    }

    // Whether the map can be seen: a closed popup does not hide its items.
    readonly property bool shown: visible && (!weatherRoot || weatherRoot.expanded !== false)
    // The help panel does not outlive the tab: it closes with the popup or on
    // another tab, so the next opening starts on the map.
    onShownChanged: if (!shown) helpPanel.close()

    Connections {
        target: radarRoot.weatherRoot ? radarRoot.weatherRoot : null
        ignoreUnknownSignals: true
        // Settings → Misc → Date and Time changed: relabel the map in place.
        function onDateTimeSpecChanged() {
            radarRoot.call("setDateTimeFormat", radarRoot.weatherRoot.dateTimeSpec);
        }
        function onExpandedChanged() {
            // The page cannot always tell a collapsed popup from a visible one,
            // so pause and resume the wind particles from here; the
            // animation stops with the popup.
            radarRoot.call("setWindActive", !!radarRoot.weatherRoot.expanded);
            if (!radarRoot.weatherRoot.expanded)
                radarRoot._pause();
            if (radarRoot.weatherRoot.expanded && radarRoot.visible)
                repaintNudgeTimer.restart();
        }
    }

    // awaitReady(): the page answers through its title once the map shown
    // again has its tiles (window.signalWhenLoaded), for RadarView's fade.
    property int _readyToken: 0
    property var _readyCallback: null
    function awaitReady(callback) {
        _readyToken++;
        _readyCallback = callback;
        webView.runJavaScript("if (window.signalWhenLoaded) window.signalWhenLoaded(" + _readyToken + "); else document.title = 'ready:" + _readyToken + "';");
    }

    Component.onCompleted: {
        console.log("[Advanced Weather Widget Weather Map] component completed; lat=", lat, "lon=", lon, "zoom=", initialZoom, "theme=", mapTheme, "server=", serverUrl, "qt=", Qt.version, "platform=", Qt.platform.os);
        _applyMapProfile();
        themeGuardTimer.restart();
    }

    // The map's own storage, see MapWebProfile.qml; no item where it cannot load.
    Loader {
        id: mapProfileLoader
        source: "MapWebProfile.qml"
        onLoaded: radarRoot._applyMapProfile()
    }

    // Hands the map's profile to the view once, before the first page load.
    // instance() is null until the prototype's component is complete, and
    // QtWebEngine dereferences a null profile in setProfile: plasmashell
    // crashed on it (2026-10-23), so a null one is never written.
    property bool _mapProfileSet: false
    function _applyMapProfile() {
        if (_mapProfileSet || radarRoot._lastPageUrl !== "" || !mapProfileLoader.item)
            return;
        var p = mapProfileLoader.item.instance();
        if (!p)
            return;
        webView.profile = p;
        _mapProfileSet = true;
        console.log("[Advanced Weather Widget Weather Map] map profile:", p.storageName);
    }

    // ══════════════════════════════════════════════════════════════════════
    // The animation: what the page shows, and the user's choices
    // ══════════════════════════════════════════════════════════════════════

    function js(code) {
        webView.runJavaScript(code);
    }
    /** Calls window[fn](args...) in the page when it has it, the arguments
        as JSON. */
    function call(fn) {
        var args = [];
        for (var i = 1; i < arguments.length; i++)
            args.push(JSON.stringify(arguments[i]));
        js("if (window." + fn + ") window." + fn + "(" + args.join(", ") + ")");
    }

    property var animState: null      // window.animState()
    property bool started: false      // window.animStart() took
    property bool startFailed: false  // the page cannot animate here (no WebGL)
    property bool ctrlDown: false     // Ctrl held: readout under the pointer, cross cursor
    onCtrlDownChanged: if (ctrlDown && !mapHover.hovered) call("setReadout", false)
    readonly property int count: animState ? animState.times.length : 0
    readonly property int readyCount: animState ? animState.ready.filter(function (r) { return r; }).length : 0

    // The time shown, between two frames while playing, and now. The last
    // ones shown are kept while the range reloads (no picture shown then).
    property var shownTime: null
    property var shownNow: null
    // The times of the frames: changes with the range only.
    property var frameTimes: []
    // The days of the range, for the list under the date: [index of the
    // day's first picture, its name].
    readonly property var days: {
        var out = [], seen = {};
        for (var i = 0; i < frameTimes.length; i++) {
            var d = new Date(frameTimes[i]), key = d.toDateString();
            if (seen[key])
                continue;
            seen[key] = true;
            out.push([i, d.toLocaleString(Qt.locale(), "dddd d MMMM")]);
        }
        return out;
    }

    // The page switches and says where it stands: the last reading may be a
    // tenth of a second old.
    function toggle() {
        webView.runJavaScript("window.animToggle()", function (playing) {
            if (radarRoot.animState)
                radarRoot.animState = Object.assign({}, radarRoot.animState, { playing: playing });
        });
    }
    function showIndex(i) {
        call("animPlay", false);
        call("animShow", i);
    }
    function _pause() {
        if (started)
            call("animPlay", false);
    }

    // Pictures per second at most, resolution while playing.
    readonly property int maxFps: [4, 8, 15].indexOf(Plasmoid.configuration.weatherMapFps) >= 0 ? Plasmoid.configuration.weatherMapFps : 8
    readonly property int resolution: [1, 2, 4].indexOf(Plasmoid.configuration.weatherMapResolution) >= 0 ? Plasmoid.configuration.weatherMapResolution : 1
    function setMaxFps(v) {
        Plasmoid.configuration.weatherMapFps = v;
        call("animSetMaxFps", v);
    }
    function setResolution(v) {
        Plasmoid.configuration.weatherMapResolution = v;
        call("animSetResolution", v);
    }
    function setMapLines(on) {
        Plasmoid.configuration.librewxrMapLines = on;
        call("setMapLines", on);
    }

    // The palettes of the wind and the temperature, those of the Radar
    // settings: [id, name], the id being what the setting holds ("" for the
    // default one). The page follows a change (onWindPaletteChanged,
    // onTempPaletteChanged).
    function _paletteNames(json) {
        try {
            return JSON.parse(json || "[]").map(function (p) { return p.name; }).filter(function (n) { return !!n; });
        } catch (e) {
            return [];
        }
    }
    readonly property var windPaletteChoices: [["", i18n("Default")]].concat(_paletteNames(Plasmoid.configuration.librewxrWindPalettes).map(function (n) { return [n, n]; }))
    readonly property string windPaletteId: Plasmoid.configuration.librewxrWindPalette || ""
    function setWindPaletteId(id) { Plasmoid.configuration.librewxrWindPalette = id; }
    readonly property var tempPaletteChoices: [["", i18n("Vivid")], ["builtin:muted", i18n("Muted")], ["builtin:bluered", i18n("Blue-red")]]
        .concat(_paletteNames(Plasmoid.configuration.librewxrTempPalettes).map(function (n) { return [n, n]; }))
    readonly property string tempPaletteId: Plasmoid.configuration.librewxrTempPalette || ""
    function setTempPaletteId(id) { Plasmoid.configuration.librewxrTempPalette = id; }

    // The temperature's bands, shared with the Radar settings.
    readonly property var tempStepChoices: [[0, i18n("Smooth")], [2, "2 °"], [2.5, Number(2.5).toLocaleString(Qt.locale(), "f", 1) + " °"], [5, "5 °"], [10, "10 °"]]
    function setTempStep(v) {
        Plasmoid.configuration.librewxrTempStep = v;   // the page follows (onTempStepChanged)
    }

    // The wind's height.
    readonly property var windLevelChoices: [["10m", i18n("10 m")], ["700hPa", i18n("700 hPa")]]
    readonly property string windLevel: Plasmoid.configuration.librewxrWindLevel === "700hPa" ? "700hPa" : "10m"
    function setWindLevel(v) {
        Plasmoid.configuration.librewxrWindLevel = v;
        call("animSetWindLevel", v);
    }

    // The layers switched on, kept in weatherMapLayers.
    readonly property var layerIds: ["radar", "satellite"].concat(animLayerIds)
    readonly property var animLayerIds: ["wind", "temperature", "precipitation", "clouds", "pressure", "isobars", "humidity", "dewpoint", "airquality"]
    readonly property var layersSaved: {
        var o = {};
        try {
            o = JSON.parse(Plasmoid.configuration.weatherMapLayers || "{}") || {};
        } catch (e) {}
        return o;
    }
    // The layers taken out of the column (the radar always stays).
    readonly property var disabledLayers: {
        try {
            return JSON.parse(Plasmoid.configuration.weatherMapDisabledLayers || "[]") || [];
        } catch (e) {
            return [];
        }
    }
    function layerEnabled(id) {
        return id === "radar" || disabledLayers.indexOf(id) < 0;
    }
    // Takes a layer out of the column or puts it back (the settings of the
    // column and the Weather Maps settings share the key).
    function setLayerEnabled(id, on) {
        var d = [];
        try {
            d = JSON.parse(Plasmoid.configuration.weatherMapDisabledLayers || "[]") || [];
        } catch (e) {}
        d = d.filter(function (x) { return x !== id; });
        if (!on)
            d.push(id);
        Plasmoid.configuration.weatherMapDisabledLayers = JSON.stringify(d);
    }
    // The stack of the layers, top first, chosen in the settings: the map
    // draws them so (the wind, a canvas over the map, over all wherever it
    // is) and the column lists them so.
    readonly property var layerOrder: ConfigUtils.weatherStackOrder(Plasmoid.configuration.weatherMapLayerOrder)
    function setLayerOrder(json) { Plasmoid.configuration.weatherMapLayerOrder = json; }
    onLayerOrderChanged: if (started) call("setLayerOrder", layerOrder)
    // A layer taken out while on goes off.
    onDisabledLayersChanged: {
        if (!started)
            return;
        disabledLayers.forEach(function (id) {
            if (layerOn(id))
                setLayer(id, false);
        });
    }
    function layerOn(id) {
        if (id === "radar" || id === "satellite")
            return animState && animState[id] ? !!animState[id].on : !!layersSaved[id];
        return animState && animState.layers ? !!animState.layers[id] : !!layersSaved[id];
    }
    function _saveLayers(id, on) {
        var o = {};
        for (var i = 0; i < layerIds.length; i++)
            o[layerIds[i]] = layerIds[i] === id ? on : layerOn(layerIds[i]);
        var j = JSON.stringify(o);
        if (j !== Plasmoid.configuration.weatherMapLayers)
            Plasmoid.configuration.weatherMapLayers = j;
    }
    function setLayer(id, on) {
        // A layer changed by hand: the solo is over, as it stands (the page
        // goes back to the files' step for a layer).
        var fine = false;
        if (!_soloing) {
            // The solo is over; its range stays.
            _endSolo();
            _saveLayers(id, on);
            var forecast = animLayerIds.indexOf(id) >= 0;
            // A forecast layer on a source's range: the files' steps over it.
            if (on && forecast && rangeKind && stepH < 3) {
                stepH = 3;
                var shown = _aligned(_soloSpan(rangeKind)), now = Date.now();
                pastH = Math.max(0, (now - shown[0]) / 3600e3);
                futureH = Math.max(0, (shown[1] - now) / 3600e3);
                timeBar.timeLine.glideTo(shown[0], shown[1]);
            }
            // The last one off: the source's own steps again (once the page
            // has taken the layer off).
            fine = !on && forecast && rangeKind !== "" && stepH >= 3
                && !animLayerIds.some(function (x) { return x !== id && layerOn(x); });
        }
        if (id === "radar")
            call("animSetRadar", on);
        else if (id === "satellite")
            call("animSetSatellite", on);
        else
            call("animSetLayer", id, on);
        if (fine)
            _rangeTo(rangeKind, false);
    }
    // A solo ends as it stands: its range stays. Radar and satellite
    // together cover the satellite's range (it starts first), the one the
    // clocks know.
    function _endSolo() {
        if (!solo)
            return;
        solo = "";
        soloSaved = null;
        if (rangeKind === "both")
            rangeKind = "satellite";
    }
    // A click on the radar or the satellite: in a solo, it changes the solo.
    function clickSource(id, on) {
        if (solo)
            _soloClick(id, on);
        else
            setLayer(id, on);
    }

    // Solo (a double click on the radar or satellite icon): that source
    // alone, the time line on its range; "both" with Ctrl. The same double
    // click again gives back the layers and the range from before. Not
    // kept: the tab opens on the layers chosen.
    property string solo: ""          // "", "radar", "satellite", "both"
    property var soloSaved: null
    property bool _soloing: false
    function _applyLayers(on) {
        _soloing = true;
        for (var i = 0; i < layerIds.length; i++)
            if (layerOn(layerIds[i]) !== !!on[layerIds[i]])
                setLayer(layerIds[i], !!on[layerIds[i]]);
        _soloing = false;
    }
    // One picture every 10 minutes for the radar alone, an hour for the
    // satellite or both, the files' three hours otherwise.
    property real stepH: 3
    // The range of kind, [start, end] in ms: the radar's, the satellite's,
    // or both together. Each ends on the radar's last image, where both
    // show (the satellite's last one stays on until the radar ends).
    function _soloSpan(kind) {
        var H = 3600e3, now = Date.now();
        var r = animState && animState.radar && animState.radar.start !== null ? animState.radar : { start: now - 2 * H, last: now + 50 * 60e3 };
        var sat = animState && animState.satellite && animState.satellite.start !== null ? animState.satellite : { start: now - 12 * H, last: now - H };
        var end = r.last !== null && r.last !== undefined ? r.last : sat.last;
        if (kind === "radar")
            return [r.start, end];
        if (kind === "satellite")
            return [sat.start, end];
        return [Math.min(r.start, sat.start), end];
    }
    function _soloTo(kind) {
        solo = kind;
        _rangeTo(kind, false);
    }
    // The range of a source ("radar", "satellite", "both"; "" for hours):
    // the time line on that source's range, kept when a forecast layer is
    // switched on. Its pictures then come on the files' 3 h steps that
    // cover it; without one, every 10 minutes (radar) or hour.
    property string rangeKind: ""
    property bool _kindPending: false    // a source's range kept, set once its images are known
    readonly property string savedRangeKind: Plasmoid.configuration.weatherMapRangeKind || ""
    readonly property bool forecastOn: animLayerIds.some(function (id) { return layerOn(id); })
    function _aligned(span) {
        var S = 3 * 3600e3;
        return [Math.floor(span[0] / S) * S, Math.ceil(span[1] / S) * S];
    }
    function _rangeTo(kind, forecast) {
        rangeKind = kind;
        var span = _soloSpan(kind), now = Date.now();
        stepH = forecast ? 3 : kind === "radar" ? 1 / 6 : 1;
        var shown = forecast ? _aligned(span) : span;
        pastH = Math.max(0, (now - shown[0]) / 3600e3);
        futureH = Math.max(0, (shown[1] - now) / 3600e3);
        timeBar.timeLine.glideTo(shown[0], shown[1]);
        call("animSetSpan", span[0], span[1], stepH);
    }
    onAnimStateChanged: {
        if (!_kindPending || !animState || !animState.radar || animState.radar.start === null)
            return;
        if (savedRangeKind === "satellite" && (!animState.satellite || animState.satellite.start === null))
            return;
        _kindPending = false;
        if (!solo)
            _rangeTo(savedRangeKind, forecastOn);
    }
    function soloSource(kind) {
        if (kind !== "radar" && !layerEnabled("satellite"))
            kind = "radar";
        if (solo === kind) {
            var back = soloSaved;
            solo = "";
            soloSaved = null;
            if (back) {
                _applyLayers(back.on);
                if (back.kind) {
                    _rangeTo(back.kind, animLayerIds.some(function (id) { return !!back.on[id]; }));
                } else {
                    rangeKind = "";
                    stepH = 3;
                    _goRange(back.pastH, back.futureH);
                }
            }
            return;
        }
        if (!solo) {
            var was = {};
            layerIds.forEach(function (id) { was[id] = layerOn(id); });
            soloSaved = { on: was, pastH: pastH, futureH: futureH, kind: rangeKind };
        }
        _applyLayers({ radar: kind !== "satellite", satellite: kind !== "radar" });
        _soloTo(kind);
    }
    // In a solo, a click on the other source adds it (both, their joint
    // range), on one of both leaves the other alone; with none left, the
    // solo is over as it stands.
    function _soloClick(id, on) {
        var r = id === "radar" ? on : layerOn("radar"), sat = id === "satellite" ? on : layerOn("satellite");
        var kind = r && sat ? "both" : r ? "radar" : sat ? "satellite" : "";
        _soloing = true;
        setLayer(id, on);
        _soloing = false;
        if (kind) {
            _soloTo(kind);
        } else {
            _endSolo();
            _saveLayers(id, on);
        }
    }
    // 2.83 hours as "2 h 50", 3 as "3 h", 0.5 as "30 min".
    function hoursText(h) {
        var m = Math.round(h * 6) * 10, hh = Math.floor(m / 60), mm = m % 60;
        return hh === 0 ? i18n("%1 min", mm) : mm === 0 ? i18n("%1 h", hh) : i18n("%1 h %2", hh, (mm < 10 ? "0" : "") + mm);
    }
    // The steps of the -/+ buttons: 10 minutes through the radar alone, an
    // hour through the satellite, 3 hours over the forecast.
    readonly property real stepHours: stepH < 1 ? 1 / 6 : stepH < 3 ? 1 : 3
    readonly property string stepText: stepLabel(stepHours)
    // The step buttons follow the time shown (window.animStepButton): the
    // radar's 10 min or the satellite's hour in their ranges, while on.
    readonly property real stepBackH: animState && animState.stepBack ? animState.stepBack : stepHours
    readonly property real stepAheadH: animState && animState.stepAhead ? animState.stepAhead : stepHours
    function stepLabel(h) {
        return h < 1 ? i18n("%1 min", Math.round(h * 60)) : i18n("%1 h", h);
    }

    // The kinds of precipitation and the cloud levels shown, the pollutant.
    readonly property var precipChoices: [["rain", i18n("Rain")], ["snow", i18n("Snow")], ["wet_snow", i18n("Wet snow")], ["mix", i18n("Rain and snow")], ["freezing_rain", i18n("Freezing rain")], ["freezing_drizzle", i18n("Freezing drizzle")], ["ice_pellets", i18n("Ice pellets")]]
    readonly property var cloudChoices: [["high", i18nc("@item cloud level", "High")], ["mid", i18nc("@item cloud level", "Mid")], ["low", i18nc("@item cloud level", "Low")]]
    readonly property var aqChoices: [["pm2_5", "PM2.5"], ["pm10", "PM10"], ["ozone", "O₃"], ["nitrogen_dioxide", "NO₂"], ["sulphur_dioxide", "SO₂"], ["dust", i18n("Dust")], ["aerosol_optical_depth", i18n("AOD")], ["uv_index", i18n("UV")]]
    function _list(json, choices) {
        var all = choices.map(function (c) { return c[0]; });
        try {
            var v = JSON.parse(json || "null");
            if (Array.isArray(v))
                return all.filter(function (x) { return v.indexOf(x) >= 0; });
        } catch (e) {}
        return all;
    }
    readonly property var precipKinds: _list(Plasmoid.configuration.weatherMapPrecipKinds, precipChoices)
    readonly property var cloudLevels: _list(Plasmoid.configuration.weatherMapCloudLevels, cloudChoices)
    readonly property string pollutant: aqChoices.some(function (c) { return c[0] === Plasmoid.configuration.weatherMapPollutant; }) ? Plasmoid.configuration.weatherMapPollutant : "pm2_5"
    function setPrecipKinds(values) {
        Plasmoid.configuration.weatherMapPrecipKinds = JSON.stringify(values);
        call("precipSetKinds", values);
    }
    function setCloudLevels(values) {
        Plasmoid.configuration.weatherMapCloudLevels = JSON.stringify(values);
        call("cloudSetLevels", values);
    }
    // The isobars' settings: the width of the lines (times the usual one),
    // the hPa between two lines, the values on them, the highs and lows.
    readonly property var isoWidthChoices: [[0.6, i18nc("isobar lines", "Thin")], [1, i18nc("isobar lines", "Normal")], [2, i18nc("isobar lines", "Thick")]]
    readonly property var isoStepChoices: [[2, "2"], [4, "4"], [8, "8"]]
    readonly property var isoTextChoices: [[11, i18nc("text size", "Small")], [13, i18nc("text size", "Medium")], [16, i18nc("text size", "Large")]]
    // "" follows the theme (white on dark, near black on light).
    readonly property var isoColorChoices: [["", i18nc("color", "Theme")], ["#ffffff", i18nc("color", "White")], ["#000000", i18nc("color", "Black")], ["#4aa3ff", i18nc("color", "Blue")], ["#ffd23f", i18nc("color", "Yellow")], ["#ff6b6b", i18nc("color", "Red")], ["#7ee07e", i18nc("color", "Green")]]
    readonly property var isobars: {
        var o = {};
        try {
            o = JSON.parse(Plasmoid.configuration.weatherMapIsobars || "{}") || {};
        } catch (e) {}
        if (o.color === "#1a1a24")      // the black of before
            o.color = "#000000";
        return {
            width: isoWidthChoices.some(function (c) { return c[0] === o.width; }) ? o.width : 1,
            step: isoStepChoices.some(function (c) { return c[0] === o.step; }) ? o.step : 4,
            labels: o.labels !== false,
            marks: o.marks !== false,
            textSize: isoTextChoices.some(function (c) { return c[0] === o.textSize; }) ? o.textSize : 11,
            color: isoColorChoices.some(function (c) { return c[0] === o.color; }) ? o.color : ""
        };
    }
    function setIsobars(key, value) {
        var o = Object.assign({}, isobars);
        o[key] = value;
        Plasmoid.configuration.weatherMapIsobars = JSON.stringify(o);
        var one = {};
        one[key] = value;
        call("isoSetOptions", one);
    }
    function setPollutant(v) {
        Plasmoid.configuration.weatherMapPollutant = v;
        call("aqSetPollutant", v);
    }
    // What the layers show, told to the page before it starts: the
    // pictures of the right pollutant are the first read.
    function _layerChoices() {
        return "if (window.precipSetKinds) window.precipSetKinds(" + JSON.stringify(precipKinds) + ");"
            + "if (window.cloudSetLevels) window.cloudSetLevels(" + JSON.stringify(cloudLevels) + ");"
            + "if (window.aqSetPollutant) window.aqSetPollutant(" + JSON.stringify(pollutant) + ");"
            + "if (window.isoSetOptions) window.isoSetOptions(" + JSON.stringify(isobars) + ");";
    }

    // The opacity of each layer, in percent: the temperature's is the
    // Radar settings' one, the others are kept in weatherMapOpacities.
    readonly property var opacityDefaults: ({ radar: 80, satellite: 60, wind: 100, precipitation: 80, clouds: 70, pressure: 60, isobars: 80, humidity: 60, dewpoint: 60, airquality: 60 })
    readonly property var opacities: {
        var kept = {};
        try {
            kept = JSON.parse(Plasmoid.configuration.weatherMapOpacities || "{}") || {};
        } catch (e) {}
        return Object.assign({}, opacityDefaults, kept, { temperature: tempOpacity });
    }
    function setOpacity(id, pct) {
        if (id === "temperature") {
            Plasmoid.configuration.librewxrTempOpacity = pct;   // the page follows (onTempOpacityChanged)
            return;
        }
        var o = {};
        try {
            o = JSON.parse(Plasmoid.configuration.weatherMapOpacities || "{}") || {};
        } catch (e) {}
        o[id] = pct;
        Plasmoid.configuration.weatherMapOpacities = JSON.stringify(o);
        call("animSetOpacity", id, pct);
    }

    // The layer column folded to the width of an icon, or open. Open, the
    // column lies over the map's right (the map does not move): the page's
    // buttons there slide out of its way.
    readonly property bool panelFolded: Plasmoid.configuration.weatherMapPanelFolded === true
    readonly property real panelOver: layerPanel.openWidth - layerPanel.foldedWidth
    function setFolded(on) {
        Plasmoid.configuration.weatherMapPanelFolded = on;
        call("animSetRightInset", on ? 0 : panelOver);
    }

    // The color legends hidden, by layer id.
    readonly property var legendsHidden: {
        try {
            return JSON.parse(Plasmoid.configuration.weatherMapLegendsHidden || "{}") || {};
        } catch (e) {
            return {};
        }
    }
    function setLegend(id, on) {
        var h = Object.assign({}, legendsHidden);
        if (on)
            delete h[id];
        else
            h[id] = true;
        Plasmoid.configuration.weatherMapLegendsHidden = JSON.stringify(h);
        call("animSetLegend", id, on);
    }

    // The radar's options and color schemes, read from the page when its menu opens.
    property var radarOptions: ({})
    property var radarSchemes: []
    function readRadar() {
        webView.runJavaScript("JSON.stringify({ o: window.animRadarOptions(), s: window.animRadarSchemes() })", function (s) {
            if (!s)
                return;
            var r = JSON.parse(s);
            r.o.tileSize = String(r.o.tileSize);
            radarRoot.radarOptions = r.o;
            radarRoot.radarSchemes = r.s;
        });
    }
    // An option of the radar, kept in the librewxr keys it shares with the
    // radar's settings. Storm cells take the theme opposite the map's, so
    // they stand out.
    function setRadarOption(key, value) {
        if (key === "cells")
            value = value ? (mapTheme === "dark" ? "light" : "dark") : "";
        var keys = { color: "librewxrColorScheme", smooth: "librewxrSmooth", snow: "librewxrSnow", arrows: "librewxrArrows",
            alerts: "librewxrAlerts", format: "librewxrFormat", tileSize: "librewxrTileSize", cells: "librewxrCells", lightning: "weatherMapLightning" };
        if (keys[key])
            Plasmoid.configuration[keys[key]] = value;
        var o = Object.assign({}, radarOptions);
        o[key] = value;
        radarOptions = o;
        call("animSetRadarOption", key, value);
    }

    // Hours before and after now. The range picked is kept; a solo's range is not.
    // The radar's and the satellite's ranges, before the hours.
    readonly property var sourceChoices: [["radar", i18n("Radar")]].concat(layerEnabled("satellite") ? [["satellite", i18n("Satellite")]] : [])
    readonly property var pastChoices: sourceChoices.concat([[0, i18n("0 h")], [12, i18n("12 h")], [24, i18n("1 d")], [48, i18n("2 d")], [72, i18n("3 d")], [120, i18n("5 d")], [192, i18n("8 d")]])
    readonly property var futureChoices: sourceChoices.concat([[12, i18n("12 h")], [24, i18n("1 d")], [48, i18n("2 d")], [72, i18n("3 d")], [96, i18n("4 d")], [144, i18n("6 d")]])
    readonly property real savedPastH: Plasmoid.configuration.weatherMapPastHours >= 0 ? Plasmoid.configuration.weatherMapPastHours : 24
    readonly property real savedFutureH: Plasmoid.configuration.weatherMapFutureHours > 0 ? Plasmoid.configuration.weatherMapFutureHours : 48
    property real pastH: savedPastH
    property real futureH: savedFutureH
    function _goRange(p, f) {
        _soloing = true;
        pastH = p;
        futureH = f;
        // Around the step nearest the clock, as the page counts it.
        var S = stepH * 3600e3, now = Math.round(Date.now() / S) * S;
        timeBar.timeLine.glideTo(now - pastH * 3600e3, now + futureH * 3600e3);
        call("animSetRange", pastH, futureH, stepH);
        _soloing = false;
    }
    // The range sent again around the clock once now has left its frame
    // (the map left open for hours): at most every 5 minutes, a source
    // ending before now (the satellite alone) would ask for it all along.
    property real _rolledMs: 0
    function _rollRange() {
        _rolledMs = Date.now();
        console.log("[Advanced Weather Widget Weather Map] time line moved on to now");
        if (rangeKind)
            _rangeTo(rangeKind, solo ? false : forecastOn);
        else
            _goRange(pastH, futureH);
    }
    // A range picked by hand ends the solo, as it stands.
    function pickRange(p, f) {
        if (solo) {
            _endSolo();
            _saveLayers("", false);
        }
        // "radar" or "satellite" from either clock: that source's range.
        var kind = typeof p === "string" ? p : typeof f === "string" ? f : "";
        Plasmoid.configuration.weatherMapRangeKind = kind;
        if (kind) {
            _rangeTo(kind, forecastOn);
            return;
        }
        rangeKind = "";
        stepH = 3;
        Plasmoid.configuration.weatherMapPastHours = p;
        Plasmoid.configuration.weatherMapFutureHours = f;
        _goRange(p, f);
    }

    // x1, x2, x3: 3 hours of weather in 1.5 s, 0.75 s, 0.5 s.
    readonly property int speed: Math.max(1, Math.min(3, Plasmoid.configuration.weatherMapSpeed || 1))
    function setSpeed(s) {
        Plasmoid.configuration.weatherMapSpeed = s;
        call("animSetStep", Math.round(1500 / s));
    }
    readonly property bool loop: Plasmoid.configuration.weatherMapLoop !== false
    function setLoop(on) {
        Plasmoid.configuration.weatherMapLoop = on;
        call("animSetLoop", on);
    }

    // The help panel.
    readonly property bool helpOpen: helpPanel.opened
    function toggleHelp() {
        helpPanel.opened ? helpPanel.close() : helpPanel.open();
    }

    // "[ui] <name>" from the page's console (node cdp.mjs eval
    // "console.log('[ui] radar')"): opens or closes a menu, so captures can
    // be taken without the mouse.
    function testUi(what) {
        var popups = { radar: layerPanel.radarMenu, days: dateBox.daysMenu, settings: layerPanel.settingsMenu, order: layerPanel.orderMenu,
            "opts-wind": layerPanel.windRow.optionsPopup, "opts-temp": layerPanel.tempRow.optionsPopup,
            "opts-precip": layerPanel.precipRow.optionsPopup, "opts-clouds": layerPanel.cloudRow.optionsPopup,
            "opts-pressure": layerPanel.presRow.optionsPopup, "opts-aq": layerPanel.aqRow.optionsPopup,
            past: layerPanel.pastPick.menu, future: layerPanel.futurePick.menu };
        if (what === "fold" || what === "unfold") {
            setFolded(what === "fold");
            return;
        }
        // "right-temp", "right-radar": what a right click on that icon does.
        if (what.indexOf("right-") === 0) {
            var rr = { radar: layerPanel.radarRow, wind: layerPanel.windRow, temp: layerPanel.tempRow, pressure: layerPanel.presRow, isobars: layerPanel.isoRow }[what.substring(6)];
            if (rr) {
                layerPanel.showRow(rr);
                rr.openOptions();
            }
            return;
        }
        if (what.indexOf("solo-") === 0) {
            soloSource(what.slice(5));
            return;
        }
        // "range-radar", "range-satellite", "range-24": a range picked; "layer-wind-on": a layer switched.
        if (what.indexOf("range-") === 0) {
            var v = what.slice(6);
            pickRange(isNaN(+v) ? v : +v, savedFutureH);
            return;
        }
        // "pick-past-satellite", "pick-future-12": that entry of a clock's
        // menu, as clicked; "clocks": what both clocks show, in the log.
        if (what.indexOf("pick-") === 0) {
            var pp = what.split("-"), pick = pp[1] === "past" ? layerPanel.pastPick : layerPanel.futurePick;
            var at = pick.choices.map(function (c) { return String(c[0]); }).indexOf(pp[2]);
            if (at >= 0)
                pick.menu.itemAt(at).triggered();
            return;
        }
        if (what === "rows") {
            console.log("[ui] rows: " + layerPanel.rowTitles().join(" | "));
            return;
        }
        if (what === "clocks") {
            console.log("[ui] clocks: " + layerPanel.pastPick.label + " | " + layerPanel.futurePick.label
                + " | kind=" + rangeKind + " step=" + stepH);
            return;
        }
        // "order:temperature,radar": the stack of the layers, as set in the settings ("order:" the default).
        if (what.indexOf("order:") === 0) {
            var ord = what.slice(6);
            Plasmoid.configuration.weatherMapLayerOrder = JSON.stringify(ord ? ord.split(",") : []);
            return;
        }
        // "palette-temp:builtin:bluered", "palette-wind:": a palette picked in the options.
        if (what.indexOf("palette-") === 0) {
            var pid = what.slice(what.indexOf(":") + 1);
            if (what.indexOf("palette-temp:") === 0)
                setTempPaletteId(pid);
            else
                setWindPaletteId(pid);
            return;
        }
        // "place-45.9,6.87": the widget's place changed, as from its settings.
        if (what.indexOf("place-") === 0) {
            var ll = what.slice(6).split(",");
            Plasmoid.configuration.latitude = +ll[0];
            Plasmoid.configuration.longitude = +ll[1];
            return;
        }
        if (what.indexOf("layer-") === 0) {
            var parts = what.split("-");
            setLayer(parts[1], parts[2] === "on");
            return;
        }
        if (what === "click-radar") {
            clickSource("radar", !layerOn("radar"));
            return;
        }
        if (what === "click-satellite") {
            clickSource("satellite", !layerOn("satellite"));
            return;
        }
        if (what === "close") {
            for (var k in popups)
                popups[k].close();
            helpPanel.close();
            return;
        }
        if (what === "radar")
            readRadar();
        if (popups[what])
            popups[what].open();
        if (what === "help")
            helpPanel.open();
    }

    // The legends at the top left go under the date when the map is too
    // narrow for both side by side (zoom buttons, legends 320 px, the date).
    readonly property real legendTop: mapArea.width - layerPanel.width - dateBox.width < 52 + 320 + 12 ? dateBox.height + 8 : 0
    onLegendTopChanged: if (started) call("animSetLegendTop", legendTop)

    // Everything the page needs once the animation has started.
    function _afterStart() {
        var code = "window.animSetStep(" + Math.round(1500 / speed) + ");"
            + "window.animSetMaxFps(" + maxFps + ");"
            + "window.animSetResolution(" + resolution + ");"
            + "if (window.animSetLoop) window.animSetLoop(" + loop + ");"
            + "if (window.animSetWindLevel) window.animSetWindLevel('" + windLevel + "');"
            + "if (window.setLayerOrder) window.setLayerOrder(" + JSON.stringify(layerOrder) + ");";
        for (var id in opacities)
            code += "window.animSetOpacity('" + id + "', " + opacities[id] + ");";
        for (var l in legendsHidden)
            code += "if (window.animSetLegend) window.animSetLegend('" + l + "', false);";
        code += "if (window.animSetRightInset) window.animSetRightInset(" + (panelFolded ? 0 : panelOver) + ");";
        code += "if (window.animSetLegendTop) window.animSetLegendTop(" + legendTop + ");";
        if (Plasmoid.configuration.weatherMapLightning === true)
            code += "window.animSetRadarOption('lightning', true);";
        code += "window.animSetRadar(" + !!layersSaved.radar + "); window.animSetSatellite(" + (!!layersSaved.satellite && layerEnabled("satellite")) + ");";
        js(code);
    }

    // ── Page URL ─────────────────────────────────────────────────────────
    function _pageUrl() {
        var strings = {
            "forecast": i18n("Forecast"),
            "loading": i18n("Loading…"),
            "loadingFrame": i18n("Loading frame…"),
            "loadingFrames": i18n("Loading frames"),
            "noData": i18n("No data"),
            "noRadarData": i18n("No radar data"),
            "noSatData": i18n("No satellite data"),
            "apiError": i18n("API error"),
            "connFailed": i18n("Connection failed"),
            "globe": i18n("Globe"),
            "dayNight": i18n("Day and night"),
            "isobars": i18n("Isobars"),
            "zoomIn": i18n("Zoom in"),
            "zoomOut": i18n("Zoom out"),
            "windUnitLabel": radarRoot.windUnitLabel,
            "dirN": i18n("N"),
            "dirNE": i18n("NE"),
            "dirE": i18n("E"),
            "dirSE": i18n("SE"),
            "dirS": i18n("S"),
            "dirSW": i18n("SW"),
            "dirW": i18n("W"),
            "dirNW": i18n("NW"),
            "precip_rain": i18n("Rain"),
            "precip_snow": i18n("Snow"),
            "precip_wet_snow": i18n("Wet snow"),
            "precip_mix": i18n("Rain and snow"),
            "precip_freezing_rain": i18n("Freezing rain"),
            "precip_freezing_drizzle": i18n("Freezing drizzle"),
            "precip_ice_pellets": i18n("Ice pellets"),
            "precipDry": i18nc("@label no precipitation at that place", "Dry"),
            "cloud_total": i18nc("@label total cloud cover", "Total"),
            "cloud_high": i18nc("@item cloud level", "High"),
            "cloud_mid": i18nc("@item cloud level", "Mid"),
            "cloud_low": i18nc("@item cloud level", "Low"),
            "humidity": i18n("Humidity"),
            "dewpoint": i18n("Dew point"),
            "aqDust": i18n("Dust")
        };
        // The live wind and temperature stay off (wind=0, temp=0): the
        // animation draws its own.
        return Qt.resolvedUrl("librewxr-map.html") + "?lat=" + radarRoot.lat + "&lon=" + radarRoot.lon + "&zoom=" + radarRoot.initialZoom + "&layer=radar" + "&color=" + radarRoot.colorScheme + "&arrows=" + (radarRoot.arrowsOn ? "1" : "0") + "&wind=0" + "&windlevel=" + radarRoot.windLevel + "&windfps=" + radarRoot.windRate[0] + "&windmaxfps=" + radarRoot.windRate[1] + "&windwidth=" + radarRoot.windLineWidth + "&proj=" + radarRoot.projection + "&night=" + (radarRoot.dayNight ? "1" : "0") + "&glow=" + radarRoot.glow + "&nightdepth=" + radarRoot.nightDepth + "&prepare=" + radarRoot.prepareMode + "&windpalette=" + encodeURIComponent(radarRoot.windPalette) + "&winddensity=" + radarRoot.windDensity + "&temp=0" + "&temppalette=" + encodeURIComponent(radarRoot.tempPalette) + "&tempopacity=" + radarRoot.tempOpacity + "&tempstep=" + radarRoot.tempStep + "&tempunit=" + radarRoot.tempUnit + "&lines=" + (radarRoot.mapLinesOn ? "1" : "0") + "&windunit=" + radarRoot.windUnit + "&cells=" + encodeURIComponent(radarRoot.activeCells) + "&alerts=" + (radarRoot.alertsOn ? "1" : "0") + "&smooth=" + (radarRoot.smoothOn ? "1" : "0") + "&snow=" + (radarRoot.snowOn ? "1" : "0") + "&format=" + encodeURIComponent(radarRoot.tileFormat) + "&tilesize=" + encodeURIComponent(radarRoot.tileSizeChoice) + "&theme=" + radarRoot.mapTheme + "&server=" + encodeURIComponent(radarRoot.serverUrl) + "&hour12=" + (radarRoot.is24h ? "0" : "1") + "&dtfmt=" + encodeURIComponent(weatherRoot ? weatherRoot.dateTimeSpec : "") + "&locale=" + encodeURIComponent(Qt.locale().name.replace("_", "-")) + "&strings=" + encodeURIComponent(JSON.stringify(strings)) + "&bg=" + encodeURIComponent(radarRoot.mapBackground) + "&bglist=" + encodeURIComponent(radarRoot.backgroundChoices.toJson()) + "&font=" + encodeURIComponent(Kirigami.Theme.defaultFont.family || "");
    }

    // Last url handed to the view; compared as built here, since webView.url
    // comes back normalised by QUrl.
    property string _lastPageUrl: ""

    function _loadPage(reason) {
        var url = _pageUrl();
        // The coalesced timer only follows changes of the page parameters.
        // Opening the tab also asks for a load (FullView -> reload()) within
        // the timer's window: when the page already holds this exact url,
        // loading it a second time only made the map show up twice in a row.
        if (reason === "coalesced" && url === radarRoot._lastPageUrl) {
            console.log("[Advanced Weather Widget Weather Map] coalesced load skipped: page already at this url");
            return;
        }
        radarRoot._lastPageUrl = url;
        console.log("[Advanced Weather Widget Weather Map] loading page (" + reason + "); lat=", radarRoot.lat, "lon=", radarRoot.lon, "theme=", radarRoot.mapTheme);
        // Assigning an unchanged url is not guaranteed to navigate - force a
        // real reload in that case (e.g. the header Refresh button).
        if (webView.url.toString() === url)
            webView.reload();
        else
            webView.url = url;
    }

    // A new place while the map plays: the page moves there, nothing is
    // reloaded (a reload showed the viewer's own radar a moment and the
    // time line started over). Before that, a load as for any parameter.
    function _placeChanged() {
        if (started)
            homeTimer.restart();
        else
            pageLoadTimer.restart();
    }
    Timer {
        id: homeTimer
        interval: 150
        onTriggered: {
            radarRoot.call("setHome", radarRoot.lat, radarRoot.lon);
            // The page holds this place now: a later load request with
            // the same parameters is not needed.
            radarRoot._lastPageUrl = radarRoot._pageUrl();
        }
    }

    // Coalesce page loads: at creation lat and lon arrive one after the
    // other (0 → lat → lat+lon), which used to trigger three page loads in a
    // row - each one a fresh window for compositing glitches.
    Timer {
        id: pageLoadTimer
        interval: 150
        repeat: false
        onTriggered: radarRoot._loadPage("coalesced")
    }

    // The map comes a little after the page: ask until the animation takes,
    // for 15 s at most (a page without WebGL cannot animate).
    Timer {
        id: startTimer
        property int tries: 0
        interval: 500
        repeat: true
        onTriggered: {
            if (++tries > 30) {
                stop();
                radarRoot.startFailed = true;
                console.warn("[Advanced Weather Widget Weather Map] the animation did not start");
                return;
            }
            var layers = {};
            radarRoot.animLayerIds.forEach(function (id) { layers[id] = !!radarRoot.layersSaved[id] && radarRoot.layerEnabled(id); });
            webView.runJavaScript(radarRoot._layerChoices() + "window.animStart ? window.animStart(" + radarRoot.pastH + ", " + radarRoot.futureH + ", " + JSON.stringify(layers) + ") : false", function (ok) {
                if (!ok || radarRoot.started)
                    return;
                radarRoot.started = true;
                startTimer.stop();
                radarRoot._afterStart();
            });
        }
    }

    // What the page shows, ten times a second while it can be seen.
    Timer {
        interval: 100
        repeat: true
        running: radarRoot.started && radarRoot.shown
        onTriggered: webView.runJavaScript("JSON.stringify(window.animState())", function (s) {
            if (!s)
                return;
            var st = JSON.parse(s);
            if (!st)
                return;
            radarRoot.animState = st;
            if (!st.playing && Date.now() - radarRoot._rolledMs > 300000 && ConfigUtils.timeLineStale(st.times, st.now, Date.now()))
                radarRoot._rollRange();
            if (st.time !== null) {
                radarRoot.shownTime = st.time;
                radarRoot.shownNow = st.times[st.now];
            }
            var t = st.times;
            if (t.length !== radarRoot.frameTimes.length || t[0] !== radarRoot.frameTimes[0])
                radarRoot.frameTimes = t;
            // A colored layer switched on switches the others off in the
            // page: the layers kept follow, outside a solo.
            if (!radarRoot.solo)
                radarRoot._saveLayers("", false);
        })
    }

    // Space plays or pauses, the arrows step as the -/+ buttons, Page Up and Page Down
    // (or Ctrl and an arrow) go to the previous or next picture from the
    // forecast file. Only while the map can be seen: the shortcuts belong
    // to the whole popup.
    readonly property bool keysOn: started && shown
    // The same keys from the page (window.animKeyFor): "play", "step:1",
    // "file:-1", "layer:wind", "loop", "now", "speed:1", "zoom:-1".
    function pageKey(k) {
        if (!keysOn)
            return;
        if (k === "play")
            toggle();
        else if (k.indexOf("step:") === 0)
            call("animStepButton", +k.slice(5));
        else if (k.indexOf("file:") === 0)
            call("animStepFile", +k.slice(5));
        else if (k.indexOf("end:") === 0)
            call("animToEnd", +k.slice(4));
        else if (k.indexOf("layer:") === 0)
            keyLayer(k.slice(6));
        else if (k === "loop")
            setLoop(!loop);
        else if (k === "now")
            keyNow();
        else if (k.indexOf("speed:") === 0)
            stepSpeed(+k.slice(6));
        else if (k.indexOf("zoom:") === 0)
            zoomBy(+k.slice(5));
    }
    // One letter per layer, the same in every language: it switches the
    // layer on or off as a click on its icon does. Shown in the icons' tips.
    readonly property var layerKeys: ({ radar: "R", satellite: "S", wind: "V", temperature: "T", precipitation: "P",
        clouds: "N", pressure: "B", isobars: "I", humidity: "H", dewpoint: "D", airquality: "A" })
    function keyLayer(id) {
        if (!layerEnabled(id))
            return;
        if (id === "radar" || id === "satellite")
            clickSource(id, !layerOn(id));
        else
            setLayer(id, !layerOn(id));
    }
    // + and -: the next or previous speed, round x1, x2, x3 like the click.
    function stepSpeed(d) {
        setSpeed((speed - 1 + d + 3) % 3 + 1);
    }
    // Ctrl and + or -: the map's zoom, as its buttons.
    function zoomBy(d) {
        call("animZoom", d);
    }
    function keyNow() {
        if (count > 0 && animState)
            showIndex(animState.now);
    }
    Shortcut { sequence: "Space"; enabled: radarRoot.keysOn; onActivated: radarRoot.toggle() }
    Shortcut { sequence: "Left"; enabled: radarRoot.keysOn; onActivated: radarRoot.call("animStepButton", -1) }
    Shortcut { sequence: "Right"; enabled: radarRoot.keysOn; onActivated: radarRoot.call("animStepButton", 1) }
    Shortcut { sequences: [StandardKey.MoveToPreviousPage, "Ctrl+Left"]; enabled: radarRoot.keysOn; onActivated: radarRoot.call("animStepFile", -1) }
    Shortcut { sequences: [StandardKey.MoveToNextPage, "Ctrl+Right"]; enabled: radarRoot.keysOn; onActivated: radarRoot.call("animStepFile", 1) }
    Shortcut { sequence: "Home"; enabled: radarRoot.keysOn; onActivated: radarRoot.call("animToEnd", -1) }
    Shortcut { sequence: "End"; enabled: radarRoot.keysOn; onActivated: radarRoot.call("animToEnd", 1) }
    Shortcut { sequence: "Escape"; enabled: helpPanel.opened; onActivated: helpPanel.close() }
    Instantiator {
        model: Object.keys(radarRoot.layerKeys)
        delegate: Shortcut {
            required property string modelData
            sequence: radarRoot.layerKeys[modelData]
            enabled: radarRoot.keysOn
            onActivated: radarRoot.keyLayer(modelData)
        }
    }
    Shortcut { sequence: "L"; enabled: radarRoot.keysOn; onActivated: radarRoot.setLoop(!radarRoot.loop) }
    // 0 and + need Shift on some layouts (AZERTY): both forms.
    Shortcut { sequences: ["0", "Shift+0"]; enabled: radarRoot.keysOn; onActivated: radarRoot.keyNow() }
    Shortcut { sequences: ["+", "Shift++"]; enabled: radarRoot.keysOn; onActivated: radarRoot.stepSpeed(1) }
    Shortcut { sequence: "-"; enabled: radarRoot.keysOn; onActivated: radarRoot.stepSpeed(-1) }
    Shortcut { sequences: ["Ctrl++", "Ctrl+Shift++", "Ctrl+="]; enabled: radarRoot.keysOn; onActivated: radarRoot.zoomBy(1) }
    Shortcut { sequence: "Ctrl+-"; enabled: radarRoot.keysOn; onActivated: radarRoot.zoomBy(-1) }

    // ── Main layout ──────────────────────────────────────────────────────
    ColumnLayout {
        id: keyCatcher
        anchors.fill: parent
        spacing: 0
        // Ctrl while the keyboard is on the QML side: the page gets no key
        // then, so tell it (the readout under the pointer, and its cross).
        focus: true
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Control && !event.isAutoRepeat) {
                radarRoot.ctrlDown = true;
                if (mapHover.hovered)
                    radarRoot.call("setReadout", true);
            }
        }
        Keys.onReleased: function (event) {
            if (event.key === Qt.Key_Control && !event.isAutoRepeat) {
                radarRoot.ctrlDown = false;
                radarRoot.call("setReadout", false);
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                id: mapArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                WebEngineView {
                    id: webView
                    anchors.fill: parent
                    // 1 px nudge to force Chromium recompositing after popup reopen
                    anchors.bottomMargin: radarRoot._repaintNudge
                    // Match the page's --bg so the uninitialized web surface does not flash white
                    backgroundColor: radarRoot.isDark ? "#0f1117" : "#f0f2f5"
                    // Chromium resizes the page asynchronously; while it catches up
                    // it composites the stale old-size texture, which would otherwise
                    // paint past the view's bounds.
                    clip: true

                    settings.javascriptEnabled: true
                    settings.localContentCanAccessRemoteUrls: true
                    settings.localContentCanAccessFileUrls: true

                    // Prevent popups / navigation away from our page
                    onNewWindowRequested: function (req) {
                        Qt.openUrlExternally(req.requestedUrl);
                    }

                    // Disable the native Chromium context menu (Back/Forward/Reload/Save page/View source).
                    // Reload is handled by the header Refresh button instead, for a consistent UI.
                    onContextMenuRequested: function (request) {
                        request.accepted = true;
                    }

                    Component.onCompleted: pageLoadTimer.restart()

                    onJavaScriptConsoleMessage: function (level, message, lineNumber, sourceID) {
                        if (message === "[keys] escape") {
                            if (helpPanel.opened)
                                helpPanel.close();
                        } else if (message.indexOf("[keys] ") === 0) {
                            // The shortcuts above, while the page has the keyboard.
                            radarRoot.pageKey(message.slice(7));
                        } else if (message.indexOf("[ui] ") === 0) {
                            radarRoot.testUi(message.slice(5));
                        } else if (message.indexOf("[readout] ctrl:") === 0) {
                            radarRoot.ctrlDown = message.slice(15) === "1";
                        }
                    }

                    onLoadingChanged: function (loadRequest) {
                        console.log("[Advanced Weather Widget Weather Map] loading changed:", "status=", loadRequest.status, "url=", loadRequest.url, "errorCode=", loadRequest.errorCode, "error=", loadRequest.errorString);
                        if (loadRequest.status === WebEngineView.LoadStartedStatus) {
                            // A new page: the animation starts again on it.
                            startTimer.stop();
                            radarRoot.started = false;
                            radarRoot.startFailed = false;
                            radarRoot.animState = null;
                            radarRoot.solo = "";
                            radarRoot.soloSaved = null;
                            radarRoot.rangeKind = "";
                            radarRoot._kindPending = radarRoot.savedRangeKind !== "";
                            radarRoot.stepH = 3;
                            radarRoot.pastH = radarRoot.savedPastH;
                            radarRoot.futureH = radarRoot.savedFutureH;
                        } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                            viewportFixTimer.restart();
                            // mapTheme can still flip while the page is loading: Kirigami
                            // reports a different background color early in startup, and
                            // the component is rebuilt every time the popup reopens. Those
                            // setTheme calls land on a page that does not exist yet and are
                            // lost; re-assert it here. No-op when they already match.
                            radarRoot.call("setTheme", radarRoot.mapTheme);
                            startTimer.tries = 0;
                            startTimer.restart();
                        }
                    }

                    // After a (re)load, the map may size itself against a stale
                    // viewport, glitching it until it is panned. Recalculate
                    // once the page has settled, and nudge the Chromium surface.
                    Timer {
                        id: viewportFixTimer
                        interval: 300
                        repeat: false
                        onTriggered: {
                            radarRoot.call("fixViewport");
                            repaintNudgeTimer.restart();
                            viewportFixLateTimer.restart();
                        }
                    }
                    // Second pass: base tiles can finish loading well after
                    // LoadSucceeded, re-exposing the compositing artifact.
                    Timer {
                        id: viewportFixLateTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            radarRoot.call("fixViewport");
                            repaintNudgeTimer.restart();
                        }
                    }

                    onRenderProcessTerminated: function (terminationStatus, exitCode) {
                        console.warn("[Advanced Weather Widget Weather Map] render process terminated:", "status=", terminationStatus, "exitCode=", exitCode);
                    }

                    onTitleChanged: {
                        if (title.indexOf("ready:") === 0) {
                            if (parseInt(title.substring(6)) === radarRoot._readyToken && radarRoot._readyCallback) {
                                var cb = radarRoot._readyCallback;
                                radarRoot._readyCallback = null;
                                cb();
                            }
                        } else if (title.indexOf("zoom:") === 0) {
                            var z = parseInt(title.substring(5));
                            if (!isNaN(z) && z !== Plasmoid.configuration.radarZoom)
                                Plasmoid.configuration.radarZoom = z;
                        } else if (title.indexOf("proj:") === 0) {
                            // Switched with the globe button: the page already shows it.
                            var proj = title.substring(5) === "globe" ? "globe" : "flat";
                            if (proj !== Plasmoid.configuration.librewxrProjection)
                                Plasmoid.configuration.librewxrProjection = proj;
                        } else if (title.indexOf("night:") === 0) {
                            // Switched with the day and night button: the page already shows it.
                            var night = title.substring(6) === "1";
                            if (night !== (Plasmoid.configuration.librewxrDayNight !== false))
                                Plasmoid.configuration.librewxrDayNight = night;
                        } else if (title.indexOf("bg:") === 0) {
                            // Picked from the in-map picker: the page already swapped
                            // its tiles, so persist the choice without reloading.
                            var bg = title.substring(3);
                            if (bg.length > 0 && bg !== Plasmoid.configuration.mapBackground) {
                                radarRoot._backgroundFromMap = true;
                                Plasmoid.configuration.mapBackground = bg;
                            }
                        }
                    }

                    // Reload on location/server change (coalesced); the rest
                    // changes live, without a reload.
                    Connections {
                        target: radarRoot
                        function onLatChanged() {
                            radarRoot._placeChanged();
                        }
                        function onLonChanged() {
                            radarRoot._placeChanged();
                        }
                        function onServerUrlChanged() {
                            pageLoadTimer.restart();
                        }
                        function onPrepareModeChanged() {
                            pageLoadTimer.restart();
                        }
                        function onMapThemeChanged() {
                            console.log("[Advanced Weather Widget Weather Map] Plasma theme changed; mapTheme=", radarRoot.mapTheme);
                            radarRoot.call("setTheme", radarRoot.mapTheme);
                        }
                        function onWindRateChanged() {
                            radarRoot.call("setWindRate", radarRoot.windRate[0], radarRoot.windRate[1]);
                        }
                        function onWindLineWidthChanged() {
                            radarRoot.call("setWindWidth", radarRoot.windLineWidth);
                        }
                        function onWindDensityChanged() {
                            radarRoot.call("setWindDensity", radarRoot.windDensity);
                        }
                        function onWindPaletteChanged() {
                            radarRoot.call("setWindPalette", radarRoot.windPalette);
                        }
                        function onTempPaletteChanged() {
                            radarRoot.call("setTempPalette", radarRoot.tempPalette);
                        }
                        function onTempOpacityChanged() {
                            radarRoot.call("setTempOpacity", radarRoot.tempOpacity);
                        }
                        function onTempStepChanged() {
                            radarRoot.call("setTempStep", radarRoot.tempStep);
                        }
                        function onTempUnitChanged() {
                            radarRoot.call("setTempUnit", radarRoot.tempUnit);
                        }
                        function onWindUnitChanged() {
                            radarRoot.call("setWindUnit", radarRoot.windUnit, radarRoot.windUnitLabel);
                        }
                        function onProjectionChanged() {
                            radarRoot.call("setProjection", radarRoot.projection);
                        }
                        function onDayNightChanged() {
                            radarRoot.call("setDayNight", radarRoot.dayNight);
                        }
                        function onGlowChanged() {
                            radarRoot.call("setGlow", radarRoot.glow);
                        }
                        function onNightDepthChanged() {
                            radarRoot.call("setNightDepth", radarRoot.nightDepth);
                        }
                        function onMapBackgroundChanged() {
                            if (radarRoot._backgroundFromMap) {
                                // The map itself made the change; swapping tiles again
                                // would throw away the current pan and zoom.
                                radarRoot._backgroundFromMap = false;
                                return;
                            }
                            console.log("[Advanced Weather Widget Weather Map] map background changed; background=", radarRoot.mapBackground);
                            radarRoot.call("setBackground", radarRoot.mapBackground);
                        }
                    }
                }

                // The page cannot animate here.
                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: radarRoot.startFailed
                    icon.name: "dialog-warning"
                    text: i18n("The weather maps cannot play here")
                    explanation: i18n("The map page needs WebGL, which this graphics setup does not offer.")
                }

                // Pictures loaded out of those of the range, and the pictures
                // per second at most: small, at the bottom left of the map,
                // the models drawn under them.
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: modelsBadge.visible ? modelsBadge.top : parent.bottom
                    anchors.leftMargin: 10
                    anchors.bottomMargin: modelsBadge.visible ? 4 : 30
                    width: countLabel.implicitWidth + 12
                    height: countLabel.implicitHeight + 4
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.7)
                    visible: radarRoot.count > 0
                    QQC2.Label {
                        id: countLabel
                        anchors.centerIn: parent
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 11
                        text: i18n("%1/%2 · %3 fps", radarRoot.readyCount, radarRoot.count, radarRoot.maxFps)
                    }
                    HoverHandler { id: countHover }
                    QQC2.ToolTip.text: i18n("Pictures loaded / pictures in the range<br>Pictures per second at most, set in the settings of the column")
                    QQC2.ToolTip.visible: countHover.hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                // The models drawn: the global one, then the finer ones over
                // this view. Above the map's credits, which may take the whole width.
                Rectangle {
                    id: modelsBadge
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.bottomMargin: 30
                    width: modelsLabel.implicitWidth + 12
                    height: modelsLabel.implicitHeight + 4
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.7)
                    visible: !!(radarRoot.animState && radarRoot.animState.models && radarRoot.animState.models.length)
                    QQC2.Label {
                        id: modelsLabel
                        anchors.centerIn: parent
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: 11
                        text: modelsBadge.visible ? radarRoot.animState.models.join(", ") : ""
                    }
                    HoverHandler { id: modelsHover }
                    QQC2.ToolTip.text: i18n("The global model, then the finer regional<br>ones drawn over it in this view")
                    QQC2.ToolTip.visible: modelsHover.hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                // The cross while Ctrl is held, set by Qt at once. Only over
                // the map left uncovered: over the open column, no readout.
                // Only there while Ctrl is held: over the map, it kept every
                // hover from the page, whose cursor then stayed the map's
                // open hand over its buttons.
                Item {
                    visible: radarRoot.ctrlDown
                    anchors.fill: parent
                    anchors.rightMargin: layerPanel.width - layerPanel.foldedWidth
                    HoverHandler {
                        id: mapHover
                        onHoveredChanged: if (radarRoot.ctrlDown) radarRoot.call("setReadout", hovered)
                    }
                    HoverHandler {
                        enabled: radarRoot.ctrlDown
                        cursorShape: Qt.CrossCursor
                        onPointChanged: if (enabled) radarRoot.call("readoutAt", point.position.x, point.position.y)
                    }
                }

                // The time shown, top right, left of the map's own buttons
                // and clear of the column, open or folded.
                DateBox {
                    id: dateBox
                    map: radarRoot
                    anchors.right: parent.right
                    anchors.top: parent.top
                    // The page's buttons slide left with the open column
                    // (panelOver): the date keeps clear of them too.
                    anchors.rightMargin: layerPanel.width
                    anchors.topMargin: 8
                }
            }

            // The column's place beside the map is that of the folded column;
            // open, it grows to the left over the map.
            Item {
                Layout.preferredWidth: layerPanel.foldedWidth
                Layout.fillHeight: true
                z: 1
                LayerPanel {
                    id: layerPanel
                    map: radarRoot
                    anchors.right: parent.right
                    height: parent.height
                }
            }
        }

        TimeBar {
            id: timeBar
            map: radarRoot
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
        }
    }

    HelpPanel {
        id: helpPanel
        parent: radarRoot
        keys: radarRoot.layerKeys
        layers: {
            var o = {};
            radarRoot.layerIds.forEach(function (id) { o[id] = radarRoot.layerOn(id); });
            return o;
        }
        shownIds: radarRoot.layerOrder.filter(function (id) { return radarRoot.layerEnabled(id); })
    }

    function reload() {
        radarRoot._loadPage("reload requested");
    }
}
