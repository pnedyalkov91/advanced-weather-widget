/*
 * Copyright 2026 Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://gnu.org>.
 */

/**
 * ForecastView.qml - "Forecast" tab of the main widget popup
 *
 * Layouts (Appearance → Widget → Forecast):
 *   Daily forecast layout  "rows" (Standard) or "graphs": one temperature /
 *                          precipitation graph of all the days with an icon per
 *                          day; clicking a day opens its hourly forecast below
 *   Hourly layout          "cards", "strip" or "graphs": the hourly forecast of
 *                          an opened day as a graph (temperature line, icons,
 *                          precipitation bars, sunrise / sunset marks)
 *   In both graph layouts each stat that is switched on (wind, pressure, Kp, UV,
 *   precipitation sum, visibility) has a graph of its own below the temperature
 *   graph (components/ForecastChartStack.qml); an opened day is headed by an
 *   "Hourly forecast for <date>" separator, which closes the day when clicked.
 * The graphs use components/HistoryChartGraphs.qml (Qt Graphs) and fall back to
 * components/HistoryChartKQC.qml (KDE Quick Charts), the same charts as the
 * History tab.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W
import "js/iconResolver.js" as IconResolver
import "js/configUtils.js" as ConfigUtils
import "js/tempColors.js" as TempColorsJS
import "components"

Item {
    id: forecastRoot

    // Cached theme colors - a single PlasmaTheme attachment on the view root
    // instead of one per item: every Kirigami.Theme attachment re-syncs
    // (connect+disconnect on the window object) on each window expose, which
    // froze popup opening while hundreds of delegate items were alive.
    readonly property color themeTextColor: Kirigami.Theme.textColor
    readonly property color themeBackgroundColor: Kirigami.Theme.backgroundColor
    property var weatherRoot
    property var verticalScrollView
    property int expandedIndex: -1

    // ── Auto-open: expand the first available day's hourly forecast ────────
    readonly property bool autoOpen: Plasmoid.configuration.forecastAutoOpen !== false
    property bool _autoOpenDone: false

    // ── Expand-all: show hourly for every day simultaneously ───────────────
    readonly property bool expandAll: Plasmoid.configuration.forecastExpandAll === true
    // Per-day hourly cache: maps dateStr → hourly array; populated progressively
    property var _perDayHourlyData: ({})
    // Per-day loading state: maps dateStr → true while a fetch is in flight
    property var _loadingDays: ({})
    // Set of dateStr values the user has manually collapsed in expandAll mode
    property var _collapsedDays: ({})
    property var _expandAllQueue: []
    property int _expandAllActiveFetches: 0
    property int _expandAllFetchGeneration: 0
    readonly property int _expandAllMaxConcurrentFetches: 1

    // ── Past hours (today): grey out in place instead of removing ──────────
    // Off by default - "today"'s already-passed hours are filtered out of the
    // hourly forecast exactly as before. When on, they stay at their normal
    // timestamp position and are dimmed instead of disappearing.
    readonly property bool showPastHoursGreyed: Plasmoid.configuration.forecastShowPastHours === true
    readonly property real _pastHourOpacity: 0.4

    function _cancelExpandAllFetch(clearData) {
        _expandAllFetchGeneration++;
        _expandAllQueue = [];
        _expandAllActiveFetches = 0;
        expandAllFetchPump.stop();
        _loadingDays = {};
        if (clearData)
            _perDayHourlyData = {};
    }

    function _startExpandAll() {
        if (!weatherRoot || weatherRoot.dailyData.length === 0)
            return;
        _expandAllFetchGeneration++;
        _expandAllQueue = [];
        _expandAllActiveFetches = 0;
        _perDayHourlyData = {};
        var loading = {};
        var total = Math.min(Plasmoid.configuration.forecastDays, weatherRoot.dailyData.length);
        var startDi = forecastRoot.showToday ? 0 : 1;
        for (var di = startDi; di < total; di++) {
            var dateStr = weatherRoot.dailyData[di].dateStr || "";
            if (!dateStr)
                continue;
            _expandAllQueue.push(dateStr);
            loading[dateStr] = true;
        }
        _loadingDays = loading;
        expandAllFetchPump.restart();
    }

    function _pumpExpandAllQueue() {
        if (!expandAll || !weatherRoot)
            return;
        var generation = _expandAllFetchGeneration;
        while (_expandAllActiveFetches < _expandAllMaxConcurrentFetches && _expandAllQueue.length > 0) {
            var dateStr = _expandAllQueue.shift();
            _expandAllActiveFetches++;
            (function (ds, gen) {
                    weatherRoot.fetchHourlyForDateDirect(ds, function (hourlyArr) {
                        if (gen !== forecastRoot._expandAllFetchGeneration)
                            return;
                        var dataUpd = Object.assign({}, forecastRoot._perDayHourlyData);
                        dataUpd[ds] = hourlyArr || [];
                        forecastRoot._perDayHourlyData = dataUpd;
                        var loadDone = Object.assign({}, forecastRoot._loadingDays);
                        delete loadDone[ds];
                        forecastRoot._loadingDays = loadDone;
                        forecastRoot._expandAllActiveFetches = Math.max(0, forecastRoot._expandAllActiveFetches - 1);
                        if (forecastRoot._expandAllQueue.length > 0)
                            expandAllFetchPump.restart();
                    });
                })(dateStr, generation);
        }
    }

    Timer {
        id: expandAllFetchPump
        interval: 80
        repeat: false
        onTriggered: forecastRoot._pumpExpandAllQueue()
    }

    function activateForecast() {
        _autoOpenDone = false;
        _collapsedDays = {};
        _loadingDays = {};
        if (expandAll) {
            _autoOpenDone = true;
            _perDayHourlyData = {};
            _startExpandAll();
        } else {
            _cancelExpandAllFetch(true);
            _doAutoOpen();
        }
    }

    onExpandAllChanged: {
        if (expandAll) {
            expandedIndex = -1;
            _autoOpenDone = true;
            _collapsedDays = {};
            _loadingDays = {};
            if (visible && weatherRoot && weatherRoot.dailyData.length > 0)
                _startExpandAll();
        } else {
            _cancelExpandAllFetch(true);
            _collapsedDays = {};
            _autoOpenDone = false;
            if (visible)
                _doAutoOpen();
        }
    }

    onAutoOpenChanged: {
        _autoOpenDone = false;
        if (visible && !expandAll)
            _doAutoOpen();
    }

    function _doAutoOpen() {
        if (_autoOpenDone)
            return;
        if (!weatherRoot || weatherRoot.dailyData.length === 0)
            return;
        _autoOpenDone = true;
        if (expandAll) {
            _startExpandAll();
            return;
        }
        if (!autoOpen)
            return;
        var firstDataIndex = forecastRoot.showToday ? 0 : 1;
        if (firstDataIndex >= weatherRoot.dailyData.length)
            return;
        forecastRoot.expandedIndex = 0;
        weatherRoot.hourlyData = [];
        weatherRoot.fetchHourlyForDate(weatherRoot.dailyData[firstDataIndex].dateStr || "");
    }

    onVisibleChanged: {
        if (visible) {
            activateForecast();
        } else {
            _cancelExpandAllFetch(false);
        }
    }

    Connections {
        target: weatherRoot
        function onDailyDataChanged() {
            if (!forecastRoot.visible) {
                forecastRoot._autoOpenDone = false;
                forecastRoot._cancelExpandAllFetch(true);
                return;
            }
            if (forecastRoot.expandAll) {
                // expandAll always re-fetches when new data arrives -
                // independent of autoOpen and _autoOpenDone.
                forecastRoot._perDayHourlyData = {};
                forecastRoot._loadingDays = {};
                forecastRoot._startExpandAll();
            } else if (forecastRoot.expandedIndex >= 0) {
                // A day is already expanded (auto-opened or clicked) - re-fetch
                // its hourly data so the panel doesn't keep showing the forecast
                // from before the refresh. Keep the old data on screen while the
                // fetch is in flight to avoid a collapse/flash.
                var dataIndex = forecastRoot.showToday ? forecastRoot.expandedIndex : forecastRoot.expandedIndex + 1;
                if (dataIndex < weatherRoot.dailyData.length)
                    weatherRoot.fetchHourlyForDate(weatherRoot.dailyData[dataIndex].dateStr || "");
                else
                    forecastRoot.expandedIndex = -1;
            } else {
                forecastRoot._doAutoOpen();
            }
        }
    }

    // Set implicit height based on content
    implicitHeight: (weatherRoot && weatherRoot.dailyData.length > 0) ? forecastColumn.height : (emptyLabel.implicitHeight + 40)

    // Font for weather icons (wind direction glyph)
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    // Resolved at load time so the path is correct in all rendering contexts
    readonly property url iconsBaseDir: Qt.resolvedUrl("../icons/")

    // Forecast icon theme - uses the same theme as the main condition icon.
    readonly property string widgetIconTheme: {
        var t = Plasmoid.configuration.conditionIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property int iconSz: Plasmoid.configuration.widgetIconSize || 16
    readonly property string iconTheme: widgetIconTheme
    // Icon theme used for the optional daily-forecast stat items (Appearance → Widget → Items)
    readonly property string itemsIconTheme: {
        var t = Plasmoid.configuration.widgetIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property bool showSunEvents: Plasmoid.configuration.forecastShowSunEvents !== false
    readonly property bool showToday: Plasmoid.configuration.forecastShowToday !== false
    readonly property bool showWind: Plasmoid.configuration.forecastShowWind !== false
    readonly property string hourlyLayout: Plasmoid.configuration.forecastHourlyLayout || "cards"
    // "graphs" = the days as one graph (Daily layout); anything else = the standard rows
    readonly property bool dailyGraphs: Plasmoid.configuration.forecastLayout === "graphs"
    readonly property bool hourlyGraphs: hourlyLayout === "graphs"
    readonly property bool _forecastDualTemp: Plasmoid.configuration.dualTempEnabled === true && Plasmoid.configuration.dualTempInWidget !== false
    readonly property bool _forecastShowTempUnit: Plasmoid.configuration.showTempUnit === true
    readonly property int _forecastWindColumnWidth: 104
    readonly property int _forecastStatColumnWidth: 92
    readonly property int _forecastTempColumnWidth: _forecastDualTemp ? (_forecastShowTempUnit ? 178 : 132) : (_forecastShowTempUnit ? 82 : 58)

    // ── Hourly forecast extra stats ─────────────────────────────────
    readonly property bool _hourlyShowPrecipProb: Plasmoid.configuration.forecastHourlyShowPrecipProb !== false
    readonly property bool _hourlyShowWind: Plasmoid.configuration.forecastHourlyShowWind !== false
    readonly property bool _hourlyShowPressure: Plasmoid.configuration.forecastHourlyShowPressure === true
    readonly property bool _hourlyShowKpIndex: Plasmoid.configuration.forecastHourlyShowKpIndex === true
    readonly property bool _hourlyShowUvIndex: Plasmoid.configuration.forecastHourlyShowUvIndex === true
    readonly property bool _hourlyShowPrecipSum: Plasmoid.configuration.forecastHourlyShowPrecipSum === true
    readonly property bool _hourlyShowVisibility: Plasmoid.configuration.forecastHourlyShowVisibility === true
    readonly property int _hourlyExtraRowCount: {
        var c = 0;
        if (forecastRoot._hourlyShowPressure)
            c++;
        if (forecastRoot._hourlyShowKpIndex)
            c++;
        if (forecastRoot._hourlyShowUvIndex)
            c++;
        if (forecastRoot._hourlyShowPrecipSum)
            c++;
        if (forecastRoot._hourlyShowVisibility)
            c++;
        return c;
    }
    readonly property int _hourlyCardHeight: 200 + _hourlyExtraRowCount * 26
    // Sum of strip rows always shown: time(18) + icon(60) + trend(56) + temp(32) + 3×2 spacing
    readonly property int _hourlyStripBaseHeight: 172
    readonly property int _hourlyStripContentHeight: _hourlyStripBaseHeight + (_hourlyShowPrecipProb ? 20 : 0) + (_hourlyShowWind ? 30 : 0) + _hourlyExtraRowCount * 20 + (!_hourlyShowPrecipSum ? 20 : 0)
    // Reserve room for the horizontal scrollbar so it never covers the last row or the
    // day-section divider. Breeze (and other classic themes) render an always-visible,
    // thicker inline scrollbar than the default Plasma overlay, so size the reserve to
    // the actual scrollbar height at runtime (with a sensible floor).
    readonly property int _hourlyStripScrollbarReserve: Math.max(16, _stripScrollbarHeight + 6)
    property int _stripScrollbarHeight: 16
    readonly property int _hourlyStripHeight: _hourlyStripContentHeight + 8 + _hourlyStripScrollbarReserve
    // Height of an opened day's graph panel until its chart is loaded (the panel then
    // takes the chart's own height)
    readonly property real _hourlyGraphGuess: Kirigami.Units.gridUnit * 16
    // Size of the weather icons above the graphs
    readonly property real _graphIconSize: 40
    readonly property int _hourlyCardWidth: {
        var w = 100;
        if (_hourlyShowKpIndex)
            w = Math.max(w, 132);
        if (_hourlyShowVisibility)
            w = Math.max(w, 112);
        if (_hourlyShowPressure)
            w = Math.max(w, 108);
        if (_hourlyShowPrecipSum)
            w = Math.max(w, 104);
        if (_hourlyShowUvIndex)
            w = Math.max(w, 100);
        if (_hourlyShowWind)
            w = Math.max(w, 100);
        return w;
    }

    function _wheelDeltaX(wheel) {
        return wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x;
    }

    function _wheelDeltaY(wheel) {
        return wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y;
    }

    function _wheelWantsHorizontal(wheel) {
        if (wheel.modifiers & Qt.ShiftModifier)
            return true;
        var dx = Math.abs(_wheelDeltaX(wheel));
        var dy = Math.abs(_wheelDeltaY(wheel));
        return dx > 0 && dx >= dy;
    }

    function _isClassicMouseWheel(wheel) {
        return wheel.pixelDelta.x === 0 && wheel.pixelDelta.y === 0 && (wheel.angleDelta.x !== 0 || wheel.angleDelta.y !== 0);
    }

    function _hourlyWheelWantsHorizontal(wheel) {
        if (_wheelWantsHorizontal(wheel))
            return true;
        // Classic mouse wheels emit vertical angleDelta only.
        // In hourly horizontal views, map that to horizontal scroll.
        return _isClassicMouseWheel(wheel) && wheel.angleDelta.y !== 0;
    }

    function _scrollParentVertically(wheel) {
        if (!verticalScrollView)
            return false;
        var delta = _wheelDeltaY(wheel);
        if (delta === 0)
            return false;
        var scale = wheel.pixelDelta.y !== 0 ? 1 : 0.5;
        var amount = delta * scale;

        var flick = verticalScrollView.flickableItem || verticalScrollView.contentItem || verticalScrollView;
        if (flick && flick.contentHeight !== undefined && flick.contentY !== undefined) {
            var maxY = Math.max(0, flick.contentHeight - flick.height);
            flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - amount));
            return true;
        }

        var bar = verticalScrollView.ScrollBar ? verticalScrollView.ScrollBar.vertical : null;
        if (bar) {
            var maxPos = Math.max(0, 1.0 - bar.size);
            bar.position = Math.max(0, Math.min(maxPos, bar.position - amount / 1200));
            return true;
        }
        return false;
    }

    /** Resolve a condition icon, handling the "custom" theme with per-condition overrides.
     *  Delegates to ConfigUtils.resolveCustomConditionIcon() - single source of truth. */
    function resolveConditionIcon(code, isNight, iconSize) {
        return ConfigUtils.resolveCustomConditionIcon(code, isNight, iconSize, forecastRoot.iconsBaseDir, forecastRoot.widgetIconTheme, Plasmoid.configuration.widgetConditionCustomIcons || "", W.weatherCodeToIcon, IconResolver.resolveCondition);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Graph layouts (Daily layout / Hourly layout = Graphs)
    // ══════════════════════════════════════════════════════════════════════

    // Chart engine: Qt Graphs, else KDE Quick Charts (when a chart cannot be
    // loaded the next engine is used; shared by the daily and hourly charts)
    property bool _graphsOk: true
    property bool _kqcOk: true
    property bool _chartSwitching: false
    readonly property string _chartSource: _graphsOk ? "HistoryChartGraphs.qml" : (_kqcOk ? "HistoryChartKQC.qml" : "")

    /** Called when a chart Loader changes status: on an error, move on to the next engine. */
    function _onChartStatus(loader) {
        if (!loader || loader.status !== Loader.Error || _chartSource === "")
            return;
        // an error of an engine that has already been given up on (another chart got there first)
        if (String(loader.source).indexOf(_chartSource) < 0)
            return;
        // Switching the source from inside its own status change would be a
        // binding loop, so do it a moment later.
        // several graphs (the temperature graph and the metric graphs) report the same failure
        if (_chartSwitching)
            return;
        if (_graphsOk) {
            console.warn("Forecast: Qt Graphs chart unavailable, using KDE Quick Charts");
            _chartSwitching = true;
            Qt.callLater(function () {
                forecastRoot._graphsOk = false;
                forecastRoot._chartSwitching = false;
            });
        } else if (_kqcOk) {
            console.warn("Forecast: KDE Quick Charts (org.kde.quickcharts) unavailable, no chart");
            _chartSwitching = true;
            Qt.callLater(function () {
                forecastRoot._kqcOk = false;
                forecastRoot._chartSwitching = false;
            });
        }
    }

    // The Flickable behind the charts: a wheel turn the chart cannot use scrolls it
    readonly property var _outerFlickable: {
        if (!verticalScrollView)
            return null;
        var f = verticalScrollView.flickableItem || verticalScrollView.contentItem || verticalScrollView;
        return (f && f.contentHeight !== undefined && f.contentY !== undefined) ? f : null;
    }

    function _isNum(v) {
        return typeof v === "number" && isFinite(v);
    }

    function _toMins(t) {
        if (!t || t === "--")
            return -1;
        var p = t.split(":");
        return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
    }

    /** Open the hourly forecast of the day at delegate index `index` - the same as
     *  clicking its row in the standard layout. Clicking the day that is already
     *  open does nothing here (a double click on the graph zooms; the separator
     *  above the open day's hourly forecast closes it). */
    function _selectDay(index) {
        if (!weatherRoot)
            return;
        var di = showToday ? index : index + 1;
        if (di < 0 || di >= weatherRoot.dailyData.length)
            return;
        if (expandAll) {
            // all days are open unless closed by hand: open the one that was
            var ds = weatherRoot.dailyData[di].dateStr || "";
            if (_collapsedDays[ds]) {
                var col = Object.assign({}, _collapsedDays);
                delete col[ds];
                _collapsedDays = col;
            }
            return;
        }
        if (expandedIndex === index)
            return;
        expandedIndex = index;
        weatherRoot.hourlyData = [];
        weatherRoot.fetchHourlyForDate(weatherRoot.dailyData[di].dateStr || "");
    }

    // The days of the daily graph - the same days the standard rows show
    readonly property var _dailyChartDays: {
        var out = [];
        if (!weatherRoot || !weatherRoot.dailyData)
            return out;
        var dd = weatherRoot.dailyData;
        var total = Math.min(Plasmoid.configuration.forecastDays, dd.length);
        for (var di = showToday ? 0 : 1; di < total; ++di) {
            var d = dd[di];
            var kp = NaN, gScale = "";
            if (Plasmoid.configuration.forecastShowKpIndex === true) {
                var ke = weatherRoot.kpForecastForDate(d.dateStr || "");
                if (ke && isFinite(ke.kp)) {
                    kp = ke.kp;
                    gScale = ke.gScale || "G0";
                }
            }
            out.push({
                dateStr: d.dateStr || "",
                dataIndex: di,
                maxC: d.maxC,
                minC: d.minC,
                precipMm: d.precipMm,
                code: d.code,
                // the metric graphs
                windKmh: d.windKmh,
                pressureHpa: d.pressureHpa,
                kp: kp,
                gScale: gScale,
                uv: d.uvMax,
                precipSum: d.precipMm,
                visibilityKm: d.visibilityKm
            });
        }
        return out;
    }

    /** Colour of a Kp bar by its G scale (G0 = quiet ... G5 = extreme storm) */
    function _kpColor(g) {
        var map = {
            G0: "#66bb6a",
            G1: "#d4e157",
            G2: "#ffca28",
            G3: "#ffa726",
            G4: "#ff7043",
            G5: "#ef5350"
        };
        return map[g] || map.G0;
    }

    /** The graphs below the temperature graph, for the entries `items`: one for each stat
     *  that is switched on (the same switches as the stat rows / cards use) and has data.
     *  `hourly` picks the hourly switches instead of the daily ones. */
    function _metricList(items, hourly) {
        var out = [];
        var wr = weatherRoot;
        if (!wr || !items || items.length < 2)
            return out;
        var cfg = Plasmoid.configuration;
        var on = hourly ? {
            wind: _hourlyShowWind,
            pressure: _hourlyShowPressure,
            kp: _hourlyShowKpIndex,
            uv: _hourlyShowUvIndex,
            precip: _hourlyShowPrecipSum,
            vis: _hourlyShowVisibility
        } : {
            wind: showWind,
            pressure: cfg.forecastShowPressure === true,
            kp: cfg.forecastShowKpIndex === true,
            uv: cfg.forecastShowUvIndex === true,
            precip: cfg.forecastShowPrecipSum === true,
            vis: cfg.forecastShowVisibility === true
        };
        function has(key) {
            for (var i = 0; i < items.length; ++i)
                if (_isNum(items[i][key]))
                    return true;
            return false;
        }
        if (on.wind && has("windKmh"))
            out.push({
                key: "windKmh",
                label: i18n("Wind"),
                color: "#66bb6a",
                style: "line",
                fmt: function (v) {
                    return wr.windValue(v);
                },
                scaleMin: 0,
                minSpan: 10
            });
        if (on.pressure && has("pressureHpa"))
            out.push({
                key: "pressureHpa",
                label: i18n("Pressure"),
                color: "#ab47bc",
                style: "line",
                fmt: function (v) {
                    return wr.pressureValue(v);
                },
                minSpan: 6
            });
        if (on.kp && has("kp"))
            out.push({
                key: "kp",
                label: i18n("Kp index (G scale)"),
                color: "#ffa726",
                style: "bars",
                fmt: function (v) {
                    return String(Math.round(v));
                },
                badge: function (i, key, v) {
                    var e = items[i];
                    return "Kp " + v.toFixed(1) + " (" + ((e && e.gScale) || "G0") + ")";
                },
                barColorAt: function (i) {
                    return forecastRoot._kpColor(items[i] ? items[i].gScale : "G0");
                },
                scaleMin: 0,
                scaleMax: 9,
                scaleStep: 3
            });
        if (on.uv && has("uv"))
            out.push({
                key: "uv",
                label: i18n("UV index"),
                color: "#ffb300",
                style: "line",
                fmt: function (v) {
                    return String(Math.round(v * 10) / 10);
                },
                scaleMin: 0,
                minSpan: 6
            });
        if (on.precip && has("precipSum"))
            out.push({
                key: "precipSum",
                label: i18n("Precipitation sum"),
                color: "#26c6da",
                style: "bars",
                fmt: function (v) {
                    return wr.precipSumText(v);
                },
                scaleMin: 0,
                minSpan: 2
            });
        if (on.vis && has("visibilityKm"))
            out.push({
                key: "visibilityKm",
                label: i18n("Visibility"),
                color: "#90a4ae",
                style: "line",
                fmt: function (v) {
                    return wr.visibilityValue(v);
                },
                scaleMin: 0,
                minSpan: 10
            });
        return out;
    }

    // The metric graphs of the daily graph. The temperature graph's precipitation strip is
    // left out when the precipitation sum has a graph of its own (it would show the same bars).
    readonly property var _dailyMetrics: _metricList(_dailyChartDays, false)
    readonly property bool _dailyOwnPrecip: {
        for (var i = 0; i < _dailyMetrics.length; ++i)
            if (_dailyMetrics[i].key === "precipSum")
                return true;
        return false;
    }

    /** Fractional index (into `items`, which carry `minutes`) of the time of day `t` (minutes), or -1. */
    function _fracIndex(items, t) {
        for (var i = 0; i + 1 < items.length; ++i) {
            var a = items[i].minutes, b = items[i + 1].minutes;
            if (a >= 0 && b > a && t >= a && t <= b)
                return i + (t - a) / (b - a);
        }
        return -1;
    }

    /** Everything the hourly graph needs for one day:
     *  { items, percent, markers, shadeBefore }. The hours follow the same rules as
     *  the strip and the cards: for today the hours that have passed (less one hour)
     *  are dropped, or - with "keep past hours" on - kept and greyed out. */
    function _hourlyChartData(hourly, dataIndex, sunriseText, sunsetText, dayDate) {
        var result = {
            items: [],
            percent: false,
            markers: [],
            shadeBefore: -1
        };
        if (!hourly || !hourly.length || !weatherRoot)
            return result;
        var rise = _toMins(sunriseText), set_ = _toMins(sunsetText);
        var nowMins = -1;
        if (dataIndex === 0) {
            var now = new Date();
            nowMins = now.getHours() * 60 + now.getMinutes() - 60;
        }
        var items = [], anyProb = false;
        for (var i = 0; i < hourly.length; ++i) {
            var h = hourly[i];
            // the closing entry (the next day's 00:00) is the end of this day
            var m = h.isNextDay === true ? 1440 : _toMins(h.hour);
            var isPast = h.isNextDay !== true && nowMins >= 0 && m >= 0 && m < nowMins;
            if (isPast && !showPastHoursGreyed)
                continue;
            var key = (h.hour && h.hour !== "--") ? h.hour : "";
            var label = "--";
            if (key !== "") {
                var parts = key.split(":");
                if (parts.length >= 2) {
                    var dt = new Date();
                    dt.setHours(parseInt(parts[0], 10), parseInt(parts[1], 10), 0, 0);
                    label = weatherRoot.formatTimeObj(dt);
                } else {
                    label = key;
                }
            }
            // probability of precipitation, by the same rule as the strip / cards
            var ppText = W.hourlyPrecipProbText(h.precipProb, h.code);
            var prob = (ppText !== null && ppText !== undefined) ? parseFloat(ppText) : NaN;
            if (isFinite(prob))
                anyProb = true;
            // Kp: the 3-hour NOAA period, else the day's value (as the strip / cards do)
            var kpv = NaN, kpg = "";
            if (_hourlyShowKpIndex && dayDate) {
                var ke = weatherRoot.kpForecastForHour(dayDate, key) || weatherRoot.kpForecastForDate(dayDate);
                if (ke && isFinite(ke.kp)) {
                    kpv = ke.kp;
                    kpg = ke.gScale || "G0";
                }
            }
            var night = false;
            if (m >= 0 && rise >= 0 && set_ >= 0) {
                var mm1 = m % 1440;
                night = mm1 < rise || mm1 >= set_;
            }
            var title = label + " · " + weatherRoot.weatherCodeToText(h.code || 0);
            if (_isNum(h.windKmh))
                title += " · " + weatherRoot.windValue(h.windKmh);
            items.push({
                dateStr: key,
                tempC: h.tempC,
                prob: prob,
                mm: h.precipMm,
                precipMm: NaN,
                // the metric graphs
                windKmh: h.windKmh,
                pressureHpa: h.pressureHpa,
                kp: kpv,
                gScale: kpg,
                uv: h.uvIndex,
                precipSum: h.precipMm,
                visibilityKm: h.visibilityKm,
                code: h.code || 0,
                minutes: m,
                isNight: night,
                hourText: label,
                titleText: title
            });
            if (isPast)
                result.shadeBefore = items.length - 0.5;
        }
        // The bars show the chance of precipitation when the provider gives it,
        // otherwise the amount.
        for (var k = 0; k < items.length; ++k)
            items[k].precipMm = anyProb ? items[k].prob : (_isNum(items[k].mm) ? items[k].mm : NaN);
        result.items = items;
        result.percent = anyProb;
        if (showSunEvents && items.length > 1) {
            var events = [
                {
                    t: rise,
                    kind: "sunrise",
                    text: sunriseText
                },
                {
                    t: set_,
                    kind: "sunset",
                    text: sunsetText
                }
            ];
            for (var e = 0; e < events.length; ++e) {
                var ev = events[e];
                if (ev.t < 0 || (nowMins >= 0 && ev.t < nowMins))
                    continue;
                var pos = _fracIndex(items, ev.t);
                if (pos < 0)
                    continue;
                result.markers.push({
                    pos: pos,
                    label: weatherRoot.formatTimeForDisplay(ev.text),
                    iconInfo: IconResolver.resolve(ev.kind, 32, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                });
            }
        }
        return result;
    }

    // ── empty state ───────────────────────────────────────────────────────
    BusyIndicator {
        id: emptyBusy
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: emptyLabel.top
        anchors.bottomMargin: 8
        running: visible
        visible: weatherRoot && weatherRoot.loading && weatherRoot.dailyData.length === 0
    }

    Label {
        id: emptyLabel
        anchors.centerIn: parent
        visible: !weatherRoot || weatherRoot.dailyData.length === 0
        text: (weatherRoot && weatherRoot.loading) ? i18n("Loading forecast…") : i18n("No forecast data")
        color: forecastRoot.themeTextColor
        font: weatherRoot ? weatherRoot.wf(12, false) : Qt.font({})
    }

    Column {
        id: forecastColumn
        width: parent.width
        spacing: 0
        visible: weatherRoot && weatherRoot.dailyData.length > 0

        // ── Daily layout "Graphs": all the days as one graph ──────────────
        // Click a day to open its hourly forecast below (the same panel the
        // standard layout opens under a day's row).
        Item {
            id: dailyGraphBox
            width: parent.width
            visible: forecastRoot.dailyGraphs && forecastRoot._dailyChartDays.length > 1
            height: visible ? dailyGraphCol.implicitHeight + 12 : 0

            // What the chart asks for: formatted values and labels
            QtObject {
                id: dailyAdapter
                function _temp(c) {
                    return forecastRoot._isNum(c) && weatherRoot ? weatherRoot.tempValue(c) : "--";
                }
                function _precip(mm) {
                    return forecastRoot._isNum(mm) && weatherRoot ? weatherRoot.precipSumText(mm) : "--";
                }
                function _date(ds, entry) {
                    return weatherRoot && ds ? weatherRoot.formatIsoDate(ds, true) : "--";
                }
                function _day(ds, longName, entry) {
                    if (!weatherRoot || !ds)
                        return "--";
                    var name = i18n("Today");
                    if (!entry || entry.dataIndex !== 0) {
                        var parts = ds.split("-");
                        name = parts.length === 3 ? Qt.locale().dayName(new Date(parts[0], parts[1] - 1, parts[2]).getDay(), Locale.LongFormat) : "";
                    }
                    var t = name + ", " + weatherRoot.formatIsoDate(ds, true);
                    if (entry && entry.code !== undefined)
                        t += " · " + weatherRoot.weatherCodeToText(entry.code);
                    return t;
                }
            }

            ColumnLayout {
                id: dailyGraphCol
                x: 10
                y: 6
                width: parent.width - 24
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    visible: dailyStack._on && forecastRoot._dailyChartDays.length > 3
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: forecastRoot.themeTextColor
                        opacity: 0.7
                        font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                        text: {
                            var c = dailyStack.mainItem;
                            if (c && c.zoomed === true) {
                                var a = forecastRoot._dailyChartDays[Math.min(c.visibleFirst, forecastRoot._dailyChartDays.length - 1)];
                                var b = forecastRoot._dailyChartDays[Math.min(c.visibleLast, forecastRoot._dailyChartDays.length - 1)];
                                return a && b ? dailyAdapter._date(a.dateStr, a) + " – " + dailyAdapter._date(b.dateStr, b) : "";
                            }
                            return forecastRoot.expandAll ? i18n("Tip: double-click the graph, or hold Ctrl and scroll the mouse wheel, to zoom in") : i18n("Click a day to show its hourly forecast. Double-click the graph to zoom in");
                        }
                    }
                    ToolButton {
                        icon.name: "zoom-out"
                        display: AbstractButton.IconOnly
                        enabled: !!dailyStack.mainItem && dailyStack.mainItem.zoomed === true
                        onClicked: dailyStack.mainItem.zoomOut()
                        ToolTip.visible: hovered
                        ToolTip.text: i18n("Zoom out")
                        Accessible.name: i18n("Zoom out")
                    }
                    ToolButton {
                        icon.name: "zoom-in"
                        display: AbstractButton.IconOnly
                        enabled: !!dailyStack.mainItem && dailyStack.mainItem.canZoomIn === true
                        onClicked: dailyStack.mainItem.zoomIn()
                        ToolTip.visible: hovered
                        ToolTip.text: i18n("Zoom in (or double-click the graph, or hold Ctrl and scroll the mouse wheel)")
                        Accessible.name: i18n("Zoom in")
                    }
                    ToolButton {
                        icon.name: "zoom-original"
                        display: AbstractButton.IconOnly
                        enabled: !!dailyStack.mainItem && dailyStack.mainItem.zoomed === true
                        onClicked: dailyStack.mainItem.resetZoom()
                        ToolTip.visible: hovered
                        ToolTip.text: i18n("Restore")
                        Accessible.name: i18n("Restore")
                    }
                }

                // The temperature graph and a graph of its own for each stat that is switched on
                ForecastChartStack {
                    id: dailyStack
                    Layout.fillWidth: true
                    active: forecastRoot.dailyGraphs
                    chartSource: forecastRoot._chartSource
                    view: dailyAdapter
                    days: forecastRoot._dailyChartDays
                    metrics: forecastRoot._dailyMetrics
                    outerFlickable: forecastRoot._outerFlickable
                    selectable: true
                    selectedIndex: forecastRoot.expandAll ? -1 : forecastRoot.expandedIndex
                    onDaySelected: function (i) {
                        forecastRoot._selectDay(i);
                    }
                    onChartStatus: function (loader) {
                        forecastRoot._onChartStatus(loader);
                    }
                    configureMain: function (item) {
                        item.seriesDefs = [
                            {
                                key: "maxC",
                                color: item.highColor,
                                label: i18nc("@label chart legend", "High")
                            },
                            {
                                key: "minC",
                                color: item.lowColor,
                                label: i18nc("@label chart legend", "Low")
                            }
                        ];
                        item.showIcons = true;
                        item.iconSize = forecastRoot._graphIconSize;
                        item.iconAt = function (i) {
                            var d = forecastRoot._dailyChartDays[i];
                            return d ? forecastRoot.resolveConditionIcon(d.code, false, forecastRoot.iconSz) : null;
                        };
                        item.showPrecip = Qt.binding(function () {
                            return !forecastRoot._dailyOwnPrecip;
                        });
                    }
                }

                // Neither chart module could be loaded
                Label {
                    Layout.fillWidth: true
                    visible: forecastRoot.dailyGraphs && forecastRoot._dailyChartDays.length > 1 && forecastRoot._chartSource === ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: forecastRoot.themeTextColor
                    opacity: 0.7
                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                    text: i18n("The chart needs the Qt Graphs or the KDE Quick Charts QML module.")
                }
            }
        }

        Repeater {
            model: {
                if (!weatherRoot || weatherRoot.dailyData.length === 0)
                    return 0;
                var total = Math.min(Plasmoid.configuration.forecastDays, weatherRoot.dailyData.length);
                return forecastRoot.showToday ? total : Math.max(0, total - 1);
            }

            delegate: Column {
                required property int index
                readonly property int dataIndex: forecastRoot.showToday ? index : index + 1
                width: parent.width
                spacing: 0

                // Whether this day's hourly forecast is open
                readonly property bool _isExpanded: (forecastRoot.expandAll && !forecastRoot._collapsedDays[(weatherRoot && weatherRoot.dailyData[dataIndex] ? weatherRoot.dailyData[dataIndex].dateStr : "") || ""]) || forecastRoot.expandedIndex === index

                // Per-delegate hourly data: in expandAll mode pulls from the
                // per-day cache; in single-expand mode uses weatherRoot.hourlyData
                // (only valid for the currently expanded day).
                property var _dayHourlyData: {
                    var dateStr = (weatherRoot && weatherRoot.dailyData[dataIndex]) ? (weatherRoot.dailyData[dataIndex].dateStr || "") : "";
                    if (forecastRoot.expandAll && dateStr) {
                        if (forecastRoot._collapsedDays[dateStr])
                            return [];
                        return forecastRoot._perDayHourlyData[dateStr] || [];
                    }
                    if (!forecastRoot.expandAll && forecastRoot.expandedIndex === index)
                        return weatherRoot ? weatherRoot.hourlyData : [];
                    return [];
                }

                readonly property string _daySunriseText: {
                    if (weatherRoot && weatherRoot.dailyData[dataIndex] && weatherRoot.dailyData[dataIndex].sunriseTimeText)
                        return weatherRoot.dailyData[dataIndex].sunriseTimeText;
                    return weatherRoot ? weatherRoot.sunriseTimeText : "--";
                }

                readonly property string _daySunsetText: {
                    if (weatherRoot && weatherRoot.dailyData[dataIndex] && weatherRoot.dailyData[dataIndex].sunsetTimeText)
                        return weatherRoot.dailyData[dataIndex].sunsetTimeText;
                    return weatherRoot ? weatherRoot.sunsetTimeText : "--";
                }

                readonly property bool _dayOutsideQWeatherHourlyRange: {
                    if ((Plasmoid.configuration.weatherProvider || "adaptive") !== "qWeather")
                        return false;
                    var ds = (weatherRoot && weatherRoot.dailyData[dataIndex]) ? (weatherRoot.dailyData[dataIndex].dateStr || "") : "";
                    if (!ds)
                        return false;
                    var parts = ds.split("-");
                    if (parts.length < 3)
                        return false;
                    var year = parseInt(parts[0], 10);
                    var month = parseInt(parts[1], 10) - 1;
                    var day = parseInt(parts[2], 10);
                    if (isNaN(year) || isNaN(month) || isNaN(day))
                        return false;
                    var dayStartMs = new Date(year, month, day, 0, 0, 0, 0).getTime();
                    var hourlyLimitMs = (new Date()).getTime() + 168 * 3600 * 1000;
                    return dayStartMs >= hourlyLimitMs;
                }

                readonly property bool _dayOutsideAemetHourlyRange: {
                    if ((Plasmoid.configuration.weatherProvider || "adaptive") !== "aemet")
                        return false;
                    if (!weatherRoot || !weatherRoot.dailyData || !weatherRoot.dailyData[0] || !weatherRoot.dailyData[dataIndex])
                        return false;
                    // AEMET's "horaria" product covers today + tomorrow BY
                    // CALENDAR DAY - day 3 onward has only the 7-day "diaria"
                    // summary, with no hourly breakdown. This used to compare
                    // the day's midnight against a rolling (now + 48h), which
                    // is wrong at every hour of the day: day+2's midnight is
                    // always earlier than now+48h, so the third day was never
                    // flagged and sat on "Loading hourly data…" forever even
                    // though there was nothing to load. Compare calendar dates
                    // instead, relative to the forecast's own "today"
                    // (dailyData[0] - AEMET's own local date, the same source
                    // as every row's dateStr) rather than the device clock, so
                    // a device/municipality timezone difference can't shift it.
                    var todayParts = (weatherRoot.dailyData[0].dateStr || "").split("-");
                    var dayParts = (weatherRoot.dailyData[dataIndex].dateStr || "").split("-");
                    if (todayParts.length < 3 || dayParts.length < 3)
                        return false;
                    var todayUtc = Date.UTC(parseInt(todayParts[0], 10), parseInt(todayParts[1], 10) - 1, parseInt(todayParts[2], 10));
                    var dayUtc = Date.UTC(parseInt(dayParts[0], 10), parseInt(dayParts[1], 10) - 1, parseInt(dayParts[2], 10));
                    if (isNaN(todayUtc) || isNaN(dayUtc))
                        return false;
                    return Math.round((dayUtc - todayUtc) / 86400000) >= 2;
                }

                readonly property bool _dayIsLoading: {
                    var dateStr = (weatherRoot && weatherRoot.dailyData[dataIndex]) ? (weatherRoot.dailyData[dataIndex].dateStr || "") : "";
                    if (forecastRoot.expandAll && dateStr && !forecastRoot._collapsedDays[dateStr])
                        return !!forecastRoot._loadingDays[dateStr];
                    return false;
                }

                // ── day row ─────────────────────────────────────────
                Rectangle {
                    id: dayRow
                    width: parent.width
                    // With the daily graph the rows are not listed (the graphs show the same
                    // values); an opened day gets a separator instead, see hourlySeparator
                    height: forecastRoot.dailyGraphs ? 0 : Math.max(52, rowLayoutInner.implicitHeight + 12)
                    visible: height > 0
                    color: (rowMouse.containsMouse || (forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) ? Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.08) : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }

                    RowLayout {
                        id: rowLayoutInner
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 14
                        }
                        spacing: 0

                        // ── visibility flags for the optional per-day stat items,
                        // used to decide when to show a "•" separator between them ──
                        readonly property bool _windVisible: forecastRoot.showWind && (((Plasmoid.configuration.weatherProvider || "adaptive") === "aemet") || !isNaN(weatherRoot.dailyData[dataIndex].windKmh))
                        readonly property bool _pressureVisible: Plasmoid.configuration.forecastShowPressure === true
                        readonly property bool _kpVisible: Plasmoid.configuration.forecastShowKpIndex === true
                        readonly property bool _uvVisible: Plasmoid.configuration.forecastShowUvIndex === true
                        readonly property bool _precipVisible: Plasmoid.configuration.forecastShowPrecipSum === true
                        readonly property bool _visibilityVisible: Plasmoid.configuration.forecastShowVisibility === true

                        Kirigami.Icon {
                            source: ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) ? "arrow-down" : "arrow-right"
                            width: 14
                            height: 14
                            opacity: 0.45
                            Layout.alignment: Qt.AlignVCenter
                            Layout.rightMargin: 6
                        }

                        ColumnLayout {
                            Layout.preferredWidth: 110
                            Layout.minimumWidth: 110
                            Layout.maximumWidth: 110
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1
                            Label {
                                width: parent.width
                                elide: Text.ElideRight
                                text: {
                                    var di = dataIndex;
                                    if (di === 0)
                                        return i18n("Today");
                                    var ds = weatherRoot.dailyData[di].dateStr;
                                    if (!ds)
                                        return "";
                                    var parts = ds.split("-");
                                    if (parts.length !== 3)
                                        return "";
                                    var d = new Date(parts[0], parts[1] - 1, parts[2]);
                                    return Qt.locale().dayName(d.getDay(), Locale.LongFormat);
                                }
                                color: forecastRoot.themeTextColor
                                font: weatherRoot.wf(12, true)
                            }
                            Label {
                                text: {
                                    var ds = weatherRoot.dailyData[dataIndex].dateStr || "";
                                    if (!ds)
                                        return "";
                                    return weatherRoot.formatIsoDate(ds, true);
                                }
                                color: forecastRoot.themeTextColor
                                font: weatherRoot.wf(9, false)
                            }
                        }

                        WeatherIcon {
                            iconInfo: forecastRoot.resolveConditionIcon(weatherRoot.dailyData[dataIndex].code, false, forecastRoot.iconSz)
                            iconSize: 28
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            Layout.rightMargin: 4
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: weatherRoot.weatherCodeToText(weatherRoot.dailyData[dataIndex].code)
                            color: forecastRoot.themeTextColor
                            font: weatherRoot.wf(11, false)
                            wrapMode: Text.WordWrap
                        }

                        Item {
                            Layout.preferredWidth: 5
                        }

                        RowLayout {
                            visible: rowLayoutInner._windVisible
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: Math.max(forecastRoot._forecastWindColumnWidth, implicitWidth)
                            Layout.minimumWidth: forecastRoot._forecastWindColumnWidth
                            Layout.maximumWidth: Math.max(forecastRoot._forecastWindColumnWidth, implicitWidth)
                            spacing: 1

                            Item {
                                Layout.fillWidth: true
                            }

                            Item {
                                visible: !isNaN(weatherRoot.dailyData[dataIndex].windDir)
                                implicitWidth: forecastRoot.iconSz
                                implicitHeight: forecastRoot.iconSz
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: W.windDirectionGlyph(weatherRoot.dailyData[dataIndex].windDir)
                                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                    font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                    font.pixelSize: forecastRoot.iconSz
                                }
                            }

                            Label {
                                text: weatherRoot.windValue(weatherRoot.dailyData[dataIndex].windKmh)
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                font: weatherRoot.wf(10, false)
                                elide: Text.ElideRight
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        Label {
                            visible: rowLayoutInner._pressureVisible && rowLayoutInner._windVisible
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            text: "•"
                            color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
                            font: weatherRoot.wf(10, false)
                        }

                        RowLayout {
                            visible: Plasmoid.configuration.forecastShowPressure === true
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                            Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            spacing: 4
                            WeatherIcon {
                                iconInfo: IconResolver.resolve("pressure", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                iconSize: forecastRoot.iconSz
                            }
                            Label {
                                text: weatherRoot.pressureValue(weatherRoot.dailyData[dataIndex].pressureHpa)
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                font: weatherRoot.wf(10, false)
                            }
                        }

                        Label {
                            visible: rowLayoutInner._kpVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible)
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            text: "•"
                            color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
                            font: weatherRoot.wf(10, false)
                        }

                        RowLayout {
                            visible: Plasmoid.configuration.forecastShowKpIndex === true
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                            Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            spacing: 4
                            WeatherIcon {
                                iconInfo: IconResolver.resolve("spaceweather", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                iconSize: forecastRoot.iconSz
                            }
                            Label {
                                text: {
                                    var e = weatherRoot.kpForecastForDate(weatherRoot.dailyData[dataIndex].dateStr || "");
                                    if (!e || isNaN(e.kp))
                                        return i18n("No information");
                                    return "Kp " + e.kp.toFixed(1) + " (" + (e.gScale || "G0") + ")";
                                }
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                font: weatherRoot.wf(10, false)
                            }
                        }

                        Label {
                            visible: rowLayoutInner._uvVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible)
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            text: "•"
                            color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
                            font: weatherRoot.wf(10, false)
                        }

                        RowLayout {
                            visible: Plasmoid.configuration.forecastShowUvIndex === true
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                            Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            spacing: 4
                            WeatherIcon {
                                iconInfo: IconResolver.resolve("uvindex", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                iconSize: forecastRoot.iconSz
                            }
                            Label {
                                text: {
                                    var uv = weatherRoot.dailyData[dataIndex].uvMax;
                                    return isNaN(uv) ? "--" : "UV " + uv.toFixed(1);
                                }
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                font: weatherRoot.wf(10, false)
                            }
                        }

                        Label {
                            visible: rowLayoutInner._precipVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible)
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            text: "•"
                            color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
                            font: weatherRoot.wf(10, false)
                        }

                        RowLayout {
                            visible: Plasmoid.configuration.forecastShowPrecipSum === true
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                            Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            spacing: 4
                            WeatherIcon {
                                iconInfo: IconResolver.resolve("precipsum", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                iconSize: forecastRoot.iconSz
                            }
                            Label {
                                text: weatherRoot.precipSumText(weatherRoot.dailyData[dataIndex].precipMm)
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                font: weatherRoot.wf(10, false)
                            }
                        }

                        Label {
                            visible: rowLayoutInner._visibilityVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible || rowLayoutInner._precipVisible)
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            text: "•"
                            color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
                            font: weatherRoot.wf(10, false)
                        }

                        RowLayout {
                            visible: Plasmoid.configuration.forecastShowVisibility === true
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                            Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                            spacing: 4
                            WeatherIcon {
                                iconInfo: IconResolver.resolve("visibility", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                iconSize: forecastRoot.iconSz
                            }
                            Label {
                                text: weatherRoot.visibilityValue(weatherRoot.dailyData[dataIndex].visibilityKm)
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                font: weatherRoot.wf(10, false)
                            }
                        }

                        Label {
                            visible: rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible || rowLayoutInner._precipVisible || rowLayoutInner._visibilityVisible
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 6
                            Layout.rightMargin: 6
                            text: "•"
                            color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
                            font: weatherRoot.wf(10, false)
                        }

                        RowLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: Math.max(forecastRoot._forecastTempColumnWidth, implicitWidth)
                            Layout.minimumWidth: forecastRoot._forecastTempColumnWidth
                            Layout.maximumWidth: Math.max(forecastRoot._forecastTempColumnWidth, implicitWidth)
                            Item {
                                Layout.fillWidth: true
                            }
                            Label {
                                text: weatherRoot.tempValue(weatherRoot.dailyData[dataIndex].minC)
                                color: "#42a5f5"
                                font: weatherRoot.wf(12, false)
                            }
                            Label {
                                text: "/"
                                color: forecastRoot.themeTextColor
                                font: weatherRoot.wf(12, false)
                            }
                            Label {
                                text: weatherRoot.tempValue(weatherRoot.dailyData[dataIndex].maxC)
                                color: "#ff6e40"
                                font: weatherRoot.wf(12, true)
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var dateStr = weatherRoot.dailyData[dataIndex].dateStr || "";
                            if (forecastRoot.expandAll) {
                                // Toggle this specific day's collapsed state
                                var col = Object.assign({}, forecastRoot._collapsedDays);
                                if (col[dateStr]) {
                                    delete col[dateStr];
                                } else {
                                    col[dateStr] = true;
                                }
                                forecastRoot._collapsedDays = col;
                            } else {
                                if (forecastRoot.expandedIndex === index) {
                                    forecastRoot.expandedIndex = -1;
                                } else {
                                    forecastRoot.expandedIndex = index;
                                    if (weatherRoot) {
                                        weatherRoot.hourlyData = [];
                                        weatherRoot.fetchHourlyForDate(dateStr);
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Daily layout "Graphs": heading of an opened day's hourly forecast ──
                // A line, "Hourly forecast for <date>" and a line. Clicking it closes the day.
                Item {
                    id: hourlySeparator
                    width: parent.width
                    visible: forecastRoot.dailyGraphs && _isExpanded
                    height: visible ? Math.max(34, sepLabel.implicitHeight + 16) : 0

                    MouseArea {
                        id: sepMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        ToolTip.visible: containsMouse
                        ToolTip.delay: 600
                        ToolTip.text: i18n("Click to hide the hourly forecast")
                        onClicked: {
                            var dateStr = weatherRoot.dailyData[dataIndex].dateStr || "";
                            if (forecastRoot.expandAll) {
                                var col = Object.assign({}, forecastRoot._collapsedDays);
                                col[dateStr] = true;
                                forecastRoot._collapsedDays = col;
                            } else if (forecastRoot.expandedIndex === index) {
                                forecastRoot.expandedIndex = -1;
                            }
                        }
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 14
                        }
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            Layout.alignment: Qt.AlignVCenter
                            color: forecastRoot.themeTextColor
                            opacity: sepMouse.containsMouse ? 0.45 : 0.25
                        }
                        Label {
                            id: sepLabel
                            Layout.alignment: Qt.AlignVCenter
                            Layout.maximumWidth: Math.max(60, hourlySeparator.width - 80)
                            elide: Text.ElideRight
                            color: forecastRoot.themeTextColor
                            font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({})
                            text: {
                                if (!weatherRoot || !weatherRoot.dailyData[dataIndex])
                                    return "";
                                var ds = weatherRoot.dailyData[dataIndex].dateStr || "";
                                var name = i18n("Today");
                                if (dataIndex !== 0) {
                                    var parts = ds.split("-");
                                    name = parts.length === 3 ? Qt.locale().dayName(new Date(parts[0], parts[1] - 1, parts[2]).getDay(), Locale.LongFormat) : "";
                                }
                                var date = ds ? weatherRoot.formatIsoDate(ds, true) : "";
                                return i18n("Hourly forecast for %1", name !== "" ? name + ", " + date : date);
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            Layout.alignment: Qt.AlignVCenter
                            color: forecastRoot.themeTextColor
                            opacity: sepMouse.containsMouse ? 0.45 : 0.25
                        }
                    }
                }

                // ── inline hourly panel ─────────────────────────────
                Rectangle {
                    id: hourlyPanel
                    width: parent.width
                    // Graphs: as tall as the chart (a fixed guess until it is loaded)
                    readonly property real _graphPanelHeight: (hourlyLoader.item && hourlyLoader.item.implicitHeight > 0) ? hourlyLoader.item.implicitHeight : forecastRoot._hourlyGraphGuess
                    height: ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) ? (forecastRoot.hourlyLayout === "strip" ? forecastRoot._hourlyStripHeight : (forecastRoot.hourlyGraphs ? _graphPanelHeight : forecastRoot._hourlyCardHeight + 40)) : 0
                    visible: height > 0
                    clip: true
                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.04)
                    Behavior on height {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.InOutQuad
                        }
                    }

                    // Per-day loading spinner (expandAll parallel fetch)
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: _dayIsLoading
                        visible: _dayIsLoading
                    }

                    // Plain loading text for single-expand mode
                    Label {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        visible: !_dayIsLoading && ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) && _dayHourlyData.length === 0
                        text: _dayOutsideQWeatherHourlyRange ? i18n("QWeather provides hourly forecasts for up to 168 hours (7 days). Daily forecast is still available for this date.") : _dayOutsideAemetHourlyRange ? i18n("AEMET provides hourly forecasts for up to 48 hours. Daily forecast is still available for this date.") : (((Plasmoid.configuration.weatherProvider || "adaptive") === "aemet") && weatherRoot && weatherRoot.aemetRateLimited) ? i18n("AEMET: request limit reached for the moment. This will retry automatically - please wait a minute.") : i18n("Loading hourly data…")
                        color: forecastRoot.themeTextColor
                        font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Only instantiate the heavy hourly UI for the expanded day.
                    Loader {
                        id: hourlyLoader
                        anchors.fill: parent
                        active: ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) && weatherRoot && _dayHourlyData.length > 0
                        asynchronous: true
                        sourceComponent: forecastRoot.hourlyLayout === "strip" ? stripHourlyComponent : (forecastRoot.hourlyGraphs ? graphsHourlyComponent : cardsHourlyComponent)
                    }

                    Component {
                        id: graphsHourlyComponent
                        Item {
                            id: graphsRoot
                            // the panel is as tall as the chart plus its margins
                            implicitHeight: hourlyStack.mainItem ? hourlyStack.implicitHeight + 16 : 0

                            // chart data of this day (rebuilt when the hourly data change)
                            readonly property var _data: forecastRoot._hourlyChartData(_dayHourlyData, dataIndex, _daySunriseText, _daySunsetText, (weatherRoot && weatherRoot.dailyData[dataIndex] ? weatherRoot.dailyData[dataIndex].dateStr : "") || "")
                            // the graphs below the temperature graph
                            readonly property var _metrics: forecastRoot._metricList(_data.items, true)
                            readonly property bool _ownPrecip: {
                                for (var i = 0; i < _metrics.length; ++i)
                                    if (_metrics[i].key === "precipSum")
                                        return true;
                                return false;
                            }

                            // What the chart asks for: formatted values and labels
                            QtObject {
                                id: hourlyAdapter
                                function _temp(c) {
                                    return forecastRoot._isNum(c) && weatherRoot ? weatherRoot.tempValue(c) : "--";
                                }
                                function _precip(v) {
                                    if (!forecastRoot._isNum(v) || !weatherRoot)
                                        return "--";
                                    return graphsRoot._data.percent ? Math.round(v) + "%" : weatherRoot.precipSumText(v);
                                }
                                function _date(key, entry) {
                                    return entry ? entry.hourText : (key || "--");
                                }
                                function _day(key, longName, entry) {
                                    return entry ? entry.titleText : (key || "--");
                                }
                            }

                            ForecastChartStack {
                                id: hourlyStack
                                x: 10
                                y: 8
                                width: parent.width - 20
                                active: true
                                chartSource: forecastRoot._chartSource
                                view: hourlyAdapter
                                days: graphsRoot._data.items
                                metrics: graphsRoot._metrics
                                outerFlickable: forecastRoot._outerFlickable
                                minZoomDays: 6
                                markers: graphsRoot._data.markers
                                shadeBefore: graphsRoot._data.shadeBefore
                                // the widest time label ("12:00 PM" in a 12-hour locale)
                                labelSampleText: {
                                    var wide = new Date();
                                    wide.setHours(12, 0, 0, 0);
                                    return weatherRoot ? weatherRoot.formatTimeObj(wide) : "";
                                }
                                onChartStatus: function (loader) {
                                    forecastRoot._onChartStatus(loader);
                                }
                                configureMain: function (item) {
                                    item.seriesDefs = [
                                        {
                                            key: "tempC",
                                            color: item.highColor,
                                            label: i18n("Temperature")
                                        }
                                    ];
                                    item.showIcons = true;
                                    item.iconSize = forecastRoot._graphIconSize;
                                    item.iconAt = function (i) {
                                        var d = graphsRoot._data.items[i];
                                        return d ? forecastRoot.resolveConditionIcon(d.code, d.isNight, forecastRoot.iconSz) : null;
                                    };
                                    item.precipPercent = Qt.binding(function () {
                                        return graphsRoot._data.percent;
                                    });
                                    item.precipLegend = Qt.binding(function () {
                                        return graphsRoot._data.percent ? i18n("Chance of precipitation") : i18nc("@label chart legend", "Precipitation");
                                    });
                                    // the amount of precipitation has a graph of its own: the strip stays
                                    // only when it shows the chance of precipitation instead
                                    item.showPrecip = Qt.binding(function () {
                                        return graphsRoot._data.percent || !graphsRoot._ownPrecip;
                                    });
                                }
                            }

                            Label {
                                anchors.centerIn: parent
                                width: parent.width - 24
                                visible: forecastRoot._chartSource === ""
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                color: forecastRoot.themeTextColor
                                opacity: 0.7
                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                text: i18n("The chart needs the Qt Graphs or the KDE Quick Charts QML module.")
                            }
                        }
                    }

                    Component {
                        id: stripHourlyComponent
                        Item {
                            anchors.fill: parent

                            // ── STRIP LAYOUT ──────────────────────────────────
                            Flickable {
                                id: stripScrollView
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                flickableDirection: Flickable.HorizontalFlick
                                contentWidth: stripContent.width
                                contentHeight: stripContent.height
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.horizontal: ScrollBar {
                                    id: stripHBar
                                    policy: ScrollBar.AsNeeded
                                    // Feed the real (theme-dependent) scrollbar thickness back to the
                                    // strip height calc so the reserve matches Breeze's always-visible
                                    // inline scrollbar as well as the slim default-theme overlay.
                                    onImplicitHeightChanged: {
                                        if (implicitHeight > 0)
                                            forecastRoot._stripScrollbarHeight = implicitHeight;
                                    }
                                    Component.onCompleted: {
                                        if (implicitHeight > 0)
                                            forecastRoot._stripScrollbarHeight = implicitHeight;
                                    }
                                }

                                NumberAnimation {
                                    id: stripWheelAnimation
                                    target: stripScrollView
                                    property: "contentX"
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }

                                // Build combined model same as cards (with sun events)
                                property var _hourlyWithSun: {
                                    if (!_dayHourlyData || !_dayHourlyData.length)
                                        return [];
                                    function toMins(t) {
                                        if (!t || t === "--")
                                            return -1;
                                        var p = t.split(":");
                                        return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                    }
                                    // For today (index 0), hours before "now" (minus a 1 hour buffer so
                                    // the current hour stays visible) are either dropped, or - when
                                    // forecastShowPastHours is enabled - kept at their normal position and
                                    // flagged isPast so the delegates can grey them out instead.
                                    // The appended closing entry (isNextDay - the following day's 00:00, see the provider
                                    // fetchers) reads as minutes=0 same as a just-past midnight hour, so it's exempted here -
                                    // otherwise it would always look "in the past" and get filtered/greyed out of "today".
                                    var nowMins = -1;
                                    if (index === 0) {
                                        var _now = new Date();
                                        nowMins = _now.getHours() * 60 + _now.getMinutes() - 60;
                                    }
                                    var source;
                                    if (forecastRoot.showPastHoursGreyed) {
                                        source = nowMins >= 0 ? _dayHourlyData.map(function (h) {
                                            var m = toMins(h.hour);
                                            var isPast = h.isNextDay !== true && m >= 0 && m < nowMins;
                                            return isPast ? Object.assign({}, h, {
                                                isPast: true
                                            }) : h;
                                        }) : _dayHourlyData;
                                    } else {
                                        source = nowMins >= 0 ? _dayHourlyData.filter(function (h) {
                                            var m = toMins(h.hour);
                                            return h.isNextDay === true || m < 0 || m >= nowMins;
                                        }) : _dayHourlyData;
                                    }
                                    if (!forecastRoot.showSunEvents)
                                        return source;
                                    var rise = toMins(_daySunriseText);
                                    var set_ = toMins(_daySunsetText);
                                    // Only insert sun markers if they are still in the future (for today)
                                    var riseInserted = rise < 0 || (nowMins >= 0 && rise < nowMins);
                                    var setInserted = set_ < 0 || (nowMins >= 0 && set_ < nowMins);
                                    var result = [];
                                    source.forEach(function (h) {
                                        var hm = toMins(h.hour);
                                        if (!riseInserted && hm >= 0 && hm > rise) {
                                            result.push({
                                                isSunrise: true,
                                                isSunset: false,
                                                time: _daySunriseText
                                            });
                                            riseInserted = true;
                                        }
                                        if (!setInserted && hm >= 0 && hm > set_) {
                                            result.push({
                                                isSunrise: false,
                                                isSunset: true,
                                                time: _daySunsetText
                                            });
                                            setInserted = true;
                                        }
                                        result.push(h);
                                    });
                                    return result;
                                }

                                readonly property int colSpacing: 0
                                readonly property int _minColW: 100
                                // Visual height of the curve's own band (where the line moves
                                // between min/max temp). The canvas itself is taller than this
                                // (it extends down to wash color through the rows below), but
                                // rows are laid out as if it were still this height, and the
                                // curve's y-values stay within it, so nothing shifts position.
                                readonly property int _graphNominalHeight: 56
                                // Fill the available width evenly across columns when there are
                                // few enough hours that the fixed minimum would leave blank space
                                // on the right; fall back to that minimum (and horizontal
                                // scrolling, via the Flickable above) once more columns are
                                // needed than fit at it.
                                readonly property int colW: {
                                    var n = _hourlyWithSun.length;
                                    if (n <= 0 || width <= 0)
                                        return _minColW;
                                    var fitW = Math.floor(width / n) - colSpacing;
                                    return Math.max(_minColW, fitW);
                                }

                                // Column of rows
                                Item {
                                    id: stripContent
                                    height: forecastRoot._hourlyStripContentHeight
                                    width: stripScrollView._hourlyWithSun.length * (stripScrollView.colW + stripScrollView.colSpacing)

                                    // Temps array for trend line (only regular hourly entries)
                                    property var _temps: {
                                        var arr = [];
                                        var items = stripScrollView._hourlyWithSun;
                                        for (var i = 0; i < items.length; i++) {
                                            if (!items[i].isSunrise && !items[i].isSunset)
                                                arr.push({
                                                    col: i,
                                                    tempC: items[i].tempC
                                                });
                                        }
                                        return arr;
                                    }

                                    // ── Column dividers (GNOME Weather-style grid) ──
                                    // Thin lines at each interior column boundary, behind
                                    // everything else since they're declared first.
                                    Repeater {
                                        model: Math.max(0, stripScrollView._hourlyWithSun.length - 1)
                                        delegate: Rectangle {
                                            required property int index
                                            x: (index + 1) * (stripScrollView.colW + stripScrollView.colSpacing) - 1
                                            y: 0
                                            width: 1
                                            height: stripContent.height
                                            color: forecastRoot.themeTextColor
                                            opacity: 0.1
                                        }
                                    }

                                    // ── Row 0: time labels ──────────────────────
                                    Row {
                                        id: stripTimeRow
                                        x: 0
                                        y: 4
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: Item {
                                                required property var modelData
                                                width: stripScrollView.colW
                                                height: 18
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: {
                                                        if (modelData.isSunrise || modelData.isSunset)
                                                            return weatherRoot ? weatherRoot.formatTimeForDisplay(modelData.time) : "--";
                                                        if (!modelData.hour || modelData.hour === "--")
                                                            return "--";
                                                        var parts = modelData.hour.split(":");
                                                        if (parts.length < 2)
                                                            return modelData.hour;
                                                        var d = new Date();
                                                        d.setHours(parseInt(parts[0], 10), parseInt(parts[1], 10), 0, 0);
                                                        return weatherRoot ? weatherRoot.formatTimeObj(d) : "--";
                                                    }
                                                    color: forecastRoot.themeTextColor
                                                    font: weatherRoot ? weatherRoot.wf(9, modelData.isSunrise || modelData.isSunset) : Qt.font({})
                                                    opacity: (modelData.isSunrise || modelData.isSunset) ? 0.9 : 0.7
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 1: icons ────────────────────────────
                                    Row {
                                        id: stripIconRow
                                        x: 0
                                        y: stripTimeRow.y + stripTimeRow.height + 2
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: Item {
                                                required property var modelData
                                                width: stripScrollView.colW
                                                height: 60
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                WeatherIcon {
                                                    anchors.centerIn: parent
                                                    iconInfo: {
                                                        if (modelData.isSunrise)
                                                            return IconResolver.resolve("sunrise", 32, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme);
                                                        if (modelData.isSunset)
                                                            return IconResolver.resolve("sunset", 32, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme);
                                                        var isNight = false;
                                                        if (modelData.hour && modelData.hour !== "--") {
                                                            var p2 = modelData.hour.split(":");
                                                            if (p2.length >= 2) {
                                                                var hm2 = parseInt(p2[0], 10) * 60 + parseInt(p2[1], 10);
                                                                function _sm(t) {
                                                                    if (!t || t === "--")
                                                                        return -1;
                                                                    var p = t.split(":");
                                                                    return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                                                }
                                                                var rise2 = _sm(_daySunriseText);
                                                                var set2 = _sm(_daySunsetText);
                                                                if (rise2 >= 0 && set2 >= 0)
                                                                    isNight = hm2 < rise2 || hm2 >= set2;
                                                            }
                                                        }
                                                        return forecastRoot.resolveConditionIcon(modelData.code || 0, isNight, forecastRoot.iconSz);
                                                    }
                                                    iconSize: 56
                                                    iconColor: forecastRoot.themeTextColor
                                                }
                                            }
                                        }
                                    }

                                    // ── Trend line canvas ────────────────────────
                                    // Taller than just the curve's own band: it extends all the
                                    // way to the bottom of the strip so the temperature color
                                    // washes down through the rows below (fading with depth),
                                    // while the curve itself still only moves within the nominal
                                    // band at the top. Declared before those rows, so it paints
                                    // behind them.
                                    Canvas {
                                        id: trendCanvas
                                        x: 0
                                        y: stripIconRow.y + stripIconRow.height + 2
                                        width: stripContent.width
                                        height: stripContent.height - y
                                        property var temps: stripContent._temps
                                        onTempsChanged: requestPaint()
                                        onHeightChanged: requestPaint()

                                        // Detect light theme by background luminance
                                        readonly property bool darkTheme: {
                                            var bg = forecastRoot.themeBackgroundColor;
                                            return (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) < 0.5;
                                        }
                                        onDarkThemeChanged: requestPaint()

                                        // Map a temperature in °C to a CSS color string
                                        // (scale shared with the panel temperature, see js/tempColors.js)
                                        function tempColor(t) {
                                            return TempColorsJS.cssForTemperature(t, darkTheme);
                                        }

                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.clearRect(0, 0, width, height);
                                            var pts = temps;
                                            if (!pts || pts.length < 2)
                                                return;
                                            var minT = pts[0].tempC, maxT = pts[0].tempC;
                                            for (var i = 1; i < pts.length; i++) {
                                                if (pts[i].tempC < minT)
                                                    minT = pts[i].tempC;
                                                if (pts[i].tempC > maxT)
                                                    maxT = pts[i].tempC;
                                            }
                                            var range = maxT - minT;
                                            var pad = 6;
                                            var curveH = stripScrollView._graphNominalHeight;
                                            var cw = stripScrollView.colW + stripScrollView.colSpacing;
                                            // Each point sits at the center of its column, same as every
                                            // label row above/below it (the divider lines mark the actual
                                            // column boundaries, so every column - including the first and
                                            // last - reads the same way).
                                            function xOf(col) {
                                                return col * cw + cw / 2;
                                            }
                                            function yOf(t) {
                                                if (range < 0.01)
                                                    return curveH * 0.35;
                                                return pad + (1 - (t - minT) / range) * (curveH - pad * 2);
                                            }

                                            var xs = [], ys = [];
                                            for (var p = 0; p < pts.length; p++) {
                                                xs.push(xOf(pts[p].col));
                                                ys.push(yOf(pts[p].tempC));
                                            }

                                            // Catmull-Rom → bezier smoothing (same technique GNOME Weather-
                                            // style graphs use) so the curve rounds through each point
                                            // instead of joining them with straight segments.
                                            function smoothTo(xs2, ys2) {
                                                for (var s = 0; s < xs2.length - 1; s++) {
                                                    var sx0 = s > 0 ? xs2[s - 1] : xs2[s], sy0 = s > 0 ? ys2[s - 1] : ys2[s];
                                                    var sx1 = xs2[s], sy1 = ys2[s], sx2 = xs2[s + 1], sy2 = ys2[s + 1];
                                                    var sx3 = s + 2 < xs2.length ? xs2[s + 2] : sx2, sy3 = s + 2 < xs2.length ? ys2[s + 2] : sy2;
                                                    ctx.bezierCurveTo(sx1 + (sx2 - sx0) / 6, sy1 + (sy2 - sy0) / 6, sx2 - (sx3 - sx1) / 6, sy2 - (sy3 - sy1) / 6, sx2, sy2);
                                                }
                                            }

                                            // Horizontal color gradient sampled from the same per-temperature
                                            // scale used for the value labels below, so the curve's color
                                            // matches what the numbers already say.
                                            var gx0 = xs[0], gx1 = xs[xs.length - 1];
                                            if (gx1 <= gx0)
                                                gx1 = gx0 + 1;
                                            var fillGrad = ctx.createLinearGradient(gx0, 0, gx1, 0);
                                            var lineGrad = ctx.createLinearGradient(gx0, 0, gx1, 0);
                                            var STOPS = Math.min(pts.length, 7);
                                            for (var k = 0; k < STOPS; k++) {
                                                var off = STOPS === 1 ? 0 : k / (STOPS - 1);
                                                var c = tempColor(pts[Math.round(off * (pts.length - 1))].tempC);
                                                fillGrad.addColorStop(off, c);
                                                lineGrad.addColorStop(off, c);
                                            }

                                            // Filled area under the curve, flat-extended to the canvas'
                                            // own left/right/bottom edges (not just the first/last point)
                                            // so it always reaches the full width and washes all the way
                                            // down behind the rows below.
                                            ctx.beginPath();
                                            ctx.moveTo(0, ys[0]);
                                            ctx.lineTo(xs[0], ys[0]);
                                            smoothTo(xs, ys);
                                            ctx.lineTo(width, ys[ys.length - 1]);
                                            ctx.lineTo(width, height);
                                            ctx.lineTo(0, height);
                                            ctx.closePath();
                                            ctx.fillStyle = fillGrad;
                                            ctx.fill();

                                            // Fade the fill out with depth (destination-in mask) so the
                                            // color is clearest right under the curve and dissolves away
                                            // well before the bottom, instead of a flat wash competing
                                            // with the rows of text.
                                            ctx.globalCompositeOperation = "destination-in";
                                            var vFade = ctx.createLinearGradient(0, 0, 0, height);
                                            vFade.addColorStop(0, "rgba(255,255,255,0.4)");
                                            vFade.addColorStop(Math.min(0.95, curveH / height + 0.15), "rgba(255,255,255,0.12)");
                                            vFade.addColorStop(1, "rgba(255,255,255,0)");
                                            ctx.fillStyle = vFade;
                                            ctx.fillRect(0, 0, width, height);
                                            ctx.globalCompositeOperation = "source-over";

                                            // The curve itself, flat-extended to the true left/right
                                            // edges too (matching the fill), drawn on top.
                                            ctx.beginPath();
                                            ctx.moveTo(0, ys[0]);
                                            ctx.lineTo(xs[0], ys[0]);
                                            smoothTo(xs, ys);
                                            ctx.lineTo(width, ys[ys.length - 1]);
                                            ctx.lineWidth = 2.5;
                                            ctx.lineJoin = "round";
                                            ctx.lineCap = "round";
                                            ctx.strokeStyle = lineGrad;
                                            ctx.stroke();
                                        }
                                    }

                                    // ── Row 2: temperature labels ────────────────
                                    Row {
                                        id: stripTempRow
                                        x: 0
                                        y: trendCanvas.y + stripScrollView._graphNominalHeight + 2
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: Item {
                                                required property var modelData
                                                width: stripScrollView.colW
                                                height: 32
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: (modelData.isSunrise || modelData.isSunset) ? i18n(modelData.isSunrise ? "Sunrise" : "Sunset") : (weatherRoot ? weatherRoot.tempValue(modelData.tempC) : "--")
                                                    color: forecastRoot.themeTextColor
                                                    font: (modelData.isSunrise || modelData.isSunset) ? (weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})) : Qt.font({
                                                        family: Kirigami.Theme.defaultFont.family,
                                                        pixelSize: 20,
                                                        bold: true
                                                    })
                                                    opacity: (modelData.isSunrise || modelData.isSunset) ? 0.75 : 1.0
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 3: precipitation ─────────────────────
                                    Row {
                                        id: stripPrecipRow
                                        visible: forecastRoot._hourlyShowPrecipProb
                                        x: 0
                                        y: stripTempRow.y + stripTempRow.height + 2
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: RowLayout {
                                                required property var modelData
                                                readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                width: stripScrollView.colW
                                                height: 18
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                spacing: 2
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                                WeatherIcon {
                                                    visible: !parent._isSun
                                                    iconInfo: IconResolver.resolve("umbrella", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                    iconSize: 16
                                                    iconColor: forecastRoot.themeTextColor
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    visible: !parent._isSun
                                                    text: {
                                                        if (parent._isSun)
                                                            return "";
                                                        var ppText = W.hourlyPrecipProbText(modelData.precipProb, modelData.code);
                                                        if (ppText !== null)
                                                            return ppText;
                                                        var h = modelData.humidity;
                                                        return (!isNaN(h) && h !== undefined) ? Math.round(h) + "%" : "--";
                                                    }
                                                    color: forecastRoot.themeTextColor
                                                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 4: wind ───────────────────────────────
                                    Row {
                                        id: stripWindRow
                                        x: 0
                                        y: stripPrecipRow.visible ? (stripPrecipRow.y + stripPrecipRow.height + 2) : stripPrecipRow.y
                                        height: 28
                                        visible: forecastRoot._hourlyShowWind
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: Item {
                                                required property var modelData
                                                readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                width: stripScrollView.colW
                                                height: 28
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 2
                                                    Label {
                                                        visible: !parent.parent._isSun
                                                        text: weatherRoot && modelData.windKmh !== undefined ? weatherRoot.windValue(modelData.windKmh) : "--"
                                                        color: forecastRoot.themeTextColor
                                                        font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        opacity: 0.7
                                                    }
                                                    Text {
                                                        visible: !parent.parent._isSun && weatherRoot && !isNaN(modelData.windDeg)
                                                        text: W.windDirectionGlyph(modelData.windDeg)
                                                        font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                        font.pixelSize: 24
                                                        color: forecastRoot.themeTextColor
                                                        opacity: 0.7
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 5: pressure ───────────────────────────
                                    Row {
                                        id: stripPressureRow
                                        x: 0
                                        y: stripWindRow.visible ? (stripWindRow.y + stripWindRow.height + 2) : stripWindRow.y
                                        visible: forecastRoot._hourlyShowPressure
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: RowLayout {
                                                required property var modelData
                                                readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                width: stripScrollView.colW
                                                height: 18
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                spacing: 2
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                                WeatherIcon {
                                                    visible: !parent._isSun
                                                    iconInfo: IconResolver.resolve("pressure", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                    iconSize: 16
                                                    iconColor: forecastRoot.themeTextColor
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    visible: !parent._isSun
                                                    text: weatherRoot ? weatherRoot.pressureValue(modelData.pressureHpa) : "--"
                                                    color: forecastRoot.themeTextColor
                                                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 6: Kp/G index ─────────────────────────
                                    Row {
                                        id: stripKpRow
                                        x: 0
                                        y: stripPressureRow.visible ? (stripPressureRow.y + stripPressureRow.height + 2) : stripPressureRow.y
                                        visible: forecastRoot._hourlyShowKpIndex
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: RowLayout {
                                                required property var modelData
                                                readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                width: stripScrollView.colW
                                                height: 18
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                spacing: 2
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                                WeatherIcon {
                                                    visible: !parent._isSun
                                                    iconInfo: IconResolver.resolve("spaceweather", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                    iconSize: 16
                                                    iconColor: forecastRoot.themeTextColor
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    visible: !parent._isSun
                                                    text: {
                                                        if (!weatherRoot)
                                                            return i18n("No info");
                                                        var d = weatherRoot.dailyData[dataIndex].dateStr || "";
                                                        var e = weatherRoot.kpForecastForHour(d, modelData.hour || "") || weatherRoot.kpForecastForDate(d);
                                                        if (!e || isNaN(e.kp))
                                                            return i18n("No info");
                                                        return "Kp " + e.kp.toFixed(1) + " (" + (e.gScale || "G0") + ")";
                                                    }
                                                    color: forecastRoot.themeTextColor
                                                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 7: UV index ────────────────────────────
                                    Row {
                                        id: stripUvRow
                                        x: 0
                                        y: stripKpRow.visible ? (stripKpRow.y + stripKpRow.height + 2) : stripKpRow.y
                                        visible: forecastRoot._hourlyShowUvIndex
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: RowLayout {
                                                required property var modelData
                                                readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                width: stripScrollView.colW
                                                height: 18
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                spacing: 2
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                                WeatherIcon {
                                                    visible: !parent._isSun
                                                    iconInfo: IconResolver.resolve("uvindex", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                    iconSize: 16
                                                    iconColor: forecastRoot.themeTextColor
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    visible: !parent._isSun
                                                    text: {
                                                        var uv = modelData.uvIndex;
                                                        if (W.isNotSupported(uv))
                                                            return i18n("N/A");
                                                        return (uv === undefined || isNaN(uv)) ? "--" : "UV " + uv.toFixed(1);
                                                    }
                                                    color: forecastRoot.themeTextColor
                                                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 8: precipitation sum ──────────────────
                                    Row {
                                        id: stripPrecipSumRow
                                        x: 0
                                        y: stripUvRow.visible ? (stripUvRow.y + stripUvRow.height + 2) : stripUvRow.y
                                        visible: forecastRoot._hourlyShowPrecipSum
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: RowLayout {
                                                required property var modelData
                                                readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                width: stripScrollView.colW
                                                height: 18
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                spacing: 2
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                                WeatherIcon {
                                                    visible: !parent._isSun
                                                    iconInfo: IconResolver.resolve("precipsum", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                    iconSize: 16
                                                    iconColor: forecastRoot.themeTextColor
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    visible: !parent._isSun
                                                    text: weatherRoot ? weatherRoot.precipSumText(modelData.precipMm) : "--"
                                                    color: forecastRoot.themeTextColor
                                                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 9: visibility ──────────────────────────
                                    Row {
                                        id: stripVisibilityRow
                                        x: 0
                                        y: stripPrecipSumRow.visible ? (stripPrecipSumRow.y + stripPrecipSumRow.height + 2) : stripPrecipSumRow.y
                                        visible: forecastRoot._hourlyShowVisibility
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: RowLayout {
                                                required property var modelData
                                                readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                width: stripScrollView.colW
                                                height: 18
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                spacing: 2
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                                WeatherIcon {
                                                    visible: !parent._isSun
                                                    iconInfo: IconResolver.resolve("visibility", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                    iconSize: 16
                                                    iconColor: forecastRoot.themeTextColor
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    visible: !parent._isSun
                                                    text: weatherRoot ? weatherRoot.visibilityValue(modelData.visibilityKm) : "--"
                                                    color: forecastRoot.themeTextColor
                                                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }

                                    // ── Row 10: automatic precip amount ────────────
                                    // Mirrors the cards layout: shown only while an hour is
                                    // actively precipitating (trace amounts on a dry-coded hour
                                    // are skipped so it doesn't contradict a sunny icon at 0%),
                                    // and skipped row-wide when the explicit precip-sum stat is
                                    // on, since the two would show the same amount.
                                    Row {
                                        id: stripPrecipRateRow
                                        x: 0
                                        y: stripVisibilityRow.visible ? (stripVisibilityRow.y + stripVisibilityRow.height + 2) : stripVisibilityRow.y
                                        visible: !forecastRoot._hourlyShowPrecipSum
                                        spacing: stripScrollView.colSpacing
                                        Repeater {
                                            model: stripScrollView._hourlyWithSun
                                            delegate: RowLayout {
                                                required property var modelData
                                                readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                readonly property bool _hasRate: modelData.precipMm !== undefined && !isNaN(modelData.precipMm) && modelData.precipMm > 0 && W.isPrecipCode(modelData.code)
                                                width: stripScrollView.colW
                                                height: 18
                                                opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                                spacing: 2
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                                WeatherIcon {
                                                    visible: !parent._isSun && parent._hasRate
                                                    iconInfo: IconResolver.resolve("preciprate", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                    iconSize: 16
                                                    iconColor: forecastRoot.themeTextColor
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    visible: !parent._isSun && parent._hasRate
                                                    text: weatherRoot ? weatherRoot.precipValue(modelData.precipMm) : "--"
                                                    color: forecastRoot.themeTextColor
                                                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                    opacity: 0.7
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: stripScrollView
                                acceptedButtons: Qt.NoButton
                                onWheel: function (wheel) {
                                    if (forecastRoot._hourlyWheelWantsHorizontal(wheel)) {
                                        var delta = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : forecastRoot._wheelDeltaX(wheel);
                                        var pixelDelta = wheel.angleDelta.x === 0 && wheel.pixelDelta.x !== 0;
                                        if (delta === 0) {
                                            delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : forecastRoot._wheelDeltaY(wheel);
                                            pixelDelta = wheel.angleDelta.y === 0 && wheel.pixelDelta.y !== 0;
                                        }
                                        var maxX = Math.max(0, stripScrollView.contentWidth - stripScrollView.width);
                                        var targetX = pixelDelta ? Math.max(0, Math.min(maxX, stripScrollView.contentX - delta)) : Math.max(0, Math.min(maxX, stripScrollView.contentX - (delta / 120) * stripScrollView.colW * 2));
                                        stripWheelAnimation.to = targetX;
                                        stripWheelAnimation.restart();
                                        wheel.accepted = true;
                                    } else {
                                        wheel.accepted = forecastRoot._scrollParentVertically(wheel);
                                    }
                                }
                            }

                            // ── Chevron paging buttons (GNOME Weather-style) ──
                            // Siblings of the Flickable (not scrolled children of it), so
                            // they stay put at the strip's edges while the content pans
                            // underneath. Each pages by one viewport-width using the same
                            // animation the wheel handler above already drives.
                            Rectangle {
                                id: stripLeftChevron
                                visible: !stripScrollView.atXBeginning
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.top: stripIconRow.bottom
                                anchors.topMargin: 2 + stripScrollView._graphNominalHeight / 2 - height / 2
                                width: 26
                                height: 26
                                radius: width / 2
                                color: "black"
                                opacity: leftChevronArea.containsMouse ? 0.7 : 0.45
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: "arrow-left"
                                    width: 14
                                    height: 14
                                    color: "white"
                                }
                                MouseArea {
                                    id: leftChevronArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var target = Math.max(0, stripScrollView.contentX - stripScrollView.width);
                                        stripWheelAnimation.to = target;
                                        stripWheelAnimation.restart();
                                    }
                                }
                            }
                            Rectangle {
                                id: stripRightChevron
                                visible: !stripScrollView.atXEnd
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.top: stripIconRow.bottom
                                anchors.topMargin: 2 + stripScrollView._graphNominalHeight / 2 - height / 2
                                width: 26
                                height: 26
                                radius: width / 2
                                color: "black"
                                opacity: rightChevronArea.containsMouse ? 0.7 : 0.45
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: "arrow-right"
                                    width: 14
                                    height: 14
                                    color: "white"
                                }
                                MouseArea {
                                    id: rightChevronArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var maxX = Math.max(0, stripScrollView.contentWidth - stripScrollView.width);
                                        var target = Math.min(maxX, stripScrollView.contentX + stripScrollView.width);
                                        stripWheelAnimation.to = target;
                                        stripWheelAnimation.restart();
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: cardsHourlyComponent
                        Item {
                            anchors.fill: parent

                            // ── CARDS LAYOUT ───────────────────────────────────
                            ScrollView {
                                id: hourlyScrollView
                                anchors.fill: parent
                                anchors.margins: 8
                                clip: true
                                // ScrollView itself does not have flickableDirection.
                                // This property needs to be set on the internal flickableItem.
                                Component.onCompleted: {
                                    if (hourlyScrollView.flickableItem) {
                                        hourlyScrollView.flickableItem.flickableDirection = Flickable.HorizontalFlick;
                                    }
                                }
                                contentWidth: hourlyRow.implicitWidth
                                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                                ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                                NumberAnimation {
                                    id: hourlyWheelAnimation
                                    target: hourlyScrollView.ScrollBar.horizontal
                                    property: "position"
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }

                                // Auto-scroll to current hour for "Today" (index === 0)
                                Timer {
                                    id: scrollTimer
                                    interval: 150
                                    onTriggered: {
                                        if (index !== 0 || !_dayHourlyData.length)
                                            return;
                                        var now = new Date();
                                        var currentTotalMins = now.getHours() * 60 + now.getMinutes();
                                        var closestIdx = 0;
                                        var minDiff = 86400;
                                        for (var i = 0; i < _dayHourlyData.length; i++) {
                                            var h = _dayHourlyData[i].hour;
                                            if (!h)
                                                continue;
                                            var parts = h.split(":");
                                            if (parts.length < 2)
                                                continue;
                                            var hm = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                                            var diff = Math.abs(hm - currentTotalMins);
                                            if (diff < minDiff) {
                                                minDiff = diff;
                                                closestIdx = i;
                                            }
                                        }
                                        if (forecastRoot.showSunEvents && _daySunriseText && _daySunsetText) {
                                            function toMins(t) {
                                                if (!t || t === "--")
                                                    return -1;
                                                var p = t.split(":");
                                                return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                            }
                                            var rise = toMins(_daySunriseText);
                                            var set_ = toMins(_daySunsetText);
                                            var targetMins = closestIdx < _dayHourlyData.length ? toMins(_dayHourlyData[closestIdx].hour) : -1;
                                            if (rise >= 0 && targetMins >= 0 && rise < targetMins)
                                                closestIdx++;
                                            if (set_ >= 0 && targetMins >= 0 && set_ < targetMins)
                                                closestIdx++;
                                        }
                                        var hourlyWidth = hourlyRow._stretchedCardWidth;
                                        var sunWidth = hourlyRow._sunCardWidth;
                                        var spacing = 6;
                                        var scrollPos = 0;
                                        if (forecastRoot.showSunEvents && _daySunriseText && _daySunsetText) {
                                            function toMins2(t) {
                                                if (!t || t === "--")
                                                    return -1;
                                                var p = t.split(":");
                                                return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                            }
                                            var rise2 = toMins2(_daySunriseText);
                                            var set2 = toMins2(_daySunsetText);
                                            for (var j = 0; j < closestIdx; j++) {
                                                var hm2 = toMins2(_dayHourlyData[j].hour);
                                                if (rise2 >= 0 && hm2 > rise2) {
                                                    scrollPos += sunWidth + spacing;
                                                    rise2 = -1;
                                                }
                                                if (set2 >= 0 && hm2 > set2) {
                                                    scrollPos += sunWidth + spacing;
                                                    set2 = -1;
                                                }
                                                scrollPos += hourlyWidth + spacing;
                                            }
                                        } else {
                                            scrollPos = closestIdx * (hourlyWidth + spacing);
                                        }
                                        var bar = hourlyScrollView.ScrollBar.horizontal;
                                        if (!bar)
                                            return;
                                        var contentW = hourlyRow.implicitWidth || hourlyRow.width || (_dayHourlyData.length * (hourlyWidth + spacing));
                                        var viewW = hourlyScrollView.width;
                                        if (contentW > viewW) {
                                            var maxPos = Math.max(0, contentW - viewW);
                                            var targetPos = Math.min(scrollPos, maxPos);
                                            bar.position = targetPos / contentW;
                                        }
                                    }
                                }
                                Connections {
                                    target: weatherRoot
                                    function onHourlyDataChanged() {
                                        if (index !== 0 || !_dayHourlyData.length)
                                            return;
                                        scrollTimer.start();
                                    }
                                }

                                Row {
                                    id: hourlyRow
                                    spacing: 6
                                    height: parent.height

                                    // Build combined model: hourly entries + sunrise/sunset marker cards
                                    // inserted between the hour that precedes each event.
                                    property var _hourlyWithSun: {
                                        if (!_dayHourlyData || !_dayHourlyData.length)
                                            return [];
                                        function toMins(t) {
                                            if (!t || t === "--")
                                                return -1;
                                            var p = t.split(":");
                                            return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                        }
                                        // For today (index 0), hours before "now" (minus a 1 hour buffer so
                                        // the current hour stays visible) are either dropped, or - when
                                        // forecastShowPastHours is enabled - kept at their normal position and
                                        // flagged isPast so the delegate can grey them out instead.
                                        // The appended closing entry (isNextDay - the following day's 00:00,
                                        // see the provider fetchers) reads as minutes=0 same as a just-past
                                        // midnight hour, so it's exempted here - otherwise it would always
                                        // look "in the past" and get filtered/greyed out of "today".
                                        var nowMins = -1;
                                        if (index === 0) {
                                            var _now = new Date();
                                            nowMins = _now.getHours() * 60 + _now.getMinutes() - 60;
                                        }
                                        var source;
                                        if (forecastRoot.showPastHoursGreyed) {
                                            source = nowMins >= 0 ? _dayHourlyData.map(function (h) {
                                                var m = toMins(h.hour);
                                                var isPast = h.isNextDay !== true && m >= 0 && m < nowMins;
                                                return isPast ? Object.assign({}, h, {
                                                    isPast: true
                                                }) : h;
                                            }) : _dayHourlyData;
                                        } else {
                                            source = nowMins >= 0 ? _dayHourlyData.filter(function (h) {
                                                var m = toMins(h.hour);
                                                return h.isNextDay === true || m < 0 || m >= nowMins;
                                            }) : _dayHourlyData;
                                        }
                                        if (!forecastRoot.showSunEvents)
                                            return source;
                                        var rise = toMins(_daySunriseText);
                                        var set_ = toMins(_daySunsetText);
                                        var riseInserted = rise < 0 || (nowMins >= 0 && rise < nowMins);
                                        var setInserted = set_ < 0 || (nowMins >= 0 && set_ < nowMins);
                                        var result = [];
                                        source.forEach(function (h) {
                                            var hm = toMins(h.hour);
                                            if (!riseInserted && hm >= 0 && hm > rise) {
                                                result.push({
                                                    isSunrise: true,
                                                    isSunset: false,
                                                    time: _daySunriseText
                                                });
                                                riseInserted = true;
                                            }
                                            if (!setInserted && hm >= 0 && hm > set_) {
                                                result.push({
                                                    isSunset: true,
                                                    isSunrise: false,
                                                    time: _daySunsetText
                                                });
                                                setInserted = true;
                                            }
                                            result.push(h);
                                        });
                                        return result;
                                    }

                                    readonly property int _sunCardWidth: 70
                                    readonly property int _sunCount: {
                                        var c = 0;
                                        for (var i = 0; i < _hourlyWithSun.length; i++) {
                                            if (_hourlyWithSun[i].isSunrise || _hourlyWithSun[i].isSunset)
                                                c++;
                                        }
                                        return c;
                                    }
                                    readonly property int _regularCount: _hourlyWithSun.length - _sunCount
                                    // Fill the available width evenly across the regular hourly
                                    // cards when there are few enough hours that the fixed base
                                    // card width would leave blank space on the right; fall back
                                    // to that fixed minimum (and horizontal scrolling) once more
                                    // cards are needed than fit at it.
                                    readonly property int _stretchedCardWidth: {
                                        if (_regularCount <= 0 || hourlyScrollView.width <= 0)
                                            return forecastRoot._hourlyCardWidth;
                                        var totalSpacing = spacing * Math.max(0, _hourlyWithSun.length - 1);
                                        var avail = hourlyScrollView.width - totalSpacing - (_sunCount * _sunCardWidth);
                                        var fitW = Math.floor(avail / _regularCount);
                                        return Math.max(forecastRoot._hourlyCardWidth, fitW);
                                    }

                                    Repeater {
                                        model: parent._hourlyWithSun

                                        delegate: Rectangle {
                                            required property var modelData
                                            // Sunrise/sunset cards are slim; hourly cards are full height
                                            width: (modelData.isSunrise || modelData.isSunset) ? hourlyRow._sunCardWidth : hourlyRow._stretchedCardWidth
                                            height: forecastRoot._hourlyCardHeight
                                            radius: 8
                                            opacity: modelData.isPast === true ? forecastRoot._pastHourOpacity : 1.0
                                            color: (modelData.isSunrise || modelData.isSunset) ? Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.04) : Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.08)
                                            border.color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.12)
                                            border.width: 1

                                            // Only the branch this card needs is instantiated - a dormant
                                            // twin layout used to double every card's item and icon count.
                                            Loader {
                                                anchors.fill: parent
                                                sourceComponent: (modelData.isSunrise === true || modelData.isSunset === true) ? sunCardComp : hourCardComp
                                            }

                                            // ── Sunrise / Sunset card ─────────────────────────────
                                            Component {
                                                id: sunCardComp
                                                Item {
                                                    ColumnLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        WeatherIcon {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            iconInfo: IconResolver.resolve(modelData.isSunrise ? "sunrise" : "sunset", 32, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                            iconSize: 32
                                                            iconColor: forecastRoot.themeTextColor
                                                        }
                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            text: weatherRoot ? weatherRoot.formatTimeForDisplay(modelData.time) : "--"
                                                            color: forecastRoot.themeTextColor
                                                            font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({
                                                                bold: true
                                                            })
                                                        }
                                                    }
                                                }
                                            }

                                            // ── Regular hourly card ───────────────────────────────
                                            Component {
                                                id: hourCardComp
                                                Item {
                                                    ColumnLayout {
                                                        anchors {
                                                            fill: parent
                                                            margins: 6
                                                        }
                                                        spacing: 4

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            text: {
                                                                if (!modelData.hour || modelData.hour === "--")
                                                                    return "--";
                                                                var parts = modelData.hour.split(":");
                                                                if (parts.length < 2)
                                                                    return modelData.hour;
                                                                var h = parseInt(parts[0], 10);
                                                                var m = parseInt(parts[1], 10);
                                                                if (isNaN(h) || isNaN(m))
                                                                    return modelData.hour;
                                                                var d = new Date();
                                                                d.setHours(h, m, 0, 0);
                                                                return weatherRoot ? weatherRoot.formatTimeObj(d) : "--";
                                                            }
                                                            color: forecastRoot.themeTextColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        }

                                                        WeatherIcon {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            iconInfo: {
                                                                // Derive night flag from the hour vs sunrise/sunset
                                                                var isNight = false;
                                                                if (modelData.hour && modelData.hour !== "--") {
                                                                    var parts = modelData.hour.split(":");
                                                                    if (parts.length >= 2) {
                                                                        var hMins = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                                                                        function parseSunMins(t) {
                                                                            if (!t || t === "--")
                                                                                return -1;
                                                                            var p = t.split(":");
                                                                            return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                                                        }
                                                                        var rise = parseSunMins(_daySunriseText);
                                                                        var set_ = parseSunMins(_daySunsetText);
                                                                        if (rise >= 0 && set_ >= 0)
                                                                            isNight = hMins < rise || hMins >= set_;
                                                                    }
                                                                }
                                                                return forecastRoot.resolveConditionIcon(modelData.code || 0, isNight, forecastRoot.iconSz);
                                                            }
                                                            iconSize: 48
                                                        }

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            text: weatherRoot ? weatherRoot.tempValue(modelData.tempC) : "--"
                                                            color: forecastRoot.themeTextColor
                                                            font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                                bold: true
                                                            })
                                                        }

                                                        RowLayout {
                                                            visible: forecastRoot._hourlyShowWind
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 4
                                                            Label {
                                                                text: weatherRoot && modelData.windKmh !== undefined ? weatherRoot.windValue(modelData.windKmh) : "--"
                                                                color: forecastRoot.themeTextColor
                                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            }
                                                            Text {
                                                                visible: weatherRoot && !isNaN(modelData.windDeg)
                                                                text: W.windDirectionGlyph(modelData.windDeg)
                                                                font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                                font.pixelSize: 20
                                                                color: forecastRoot.themeTextColor
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                        }

                                                        RowLayout {
                                                            visible: forecastRoot._hourlyShowPressure
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 3
                                                            WeatherIcon {
                                                                iconInfo: IconResolver.resolve("pressure", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                                iconSize: 24
                                                                iconColor: forecastRoot.themeTextColor
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Label {
                                                                text: weatherRoot ? weatherRoot.pressureValue(modelData.pressureHpa) : "--"
                                                                color: forecastRoot.themeTextColor
                                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            }
                                                        }

                                                        RowLayout {
                                                            visible: forecastRoot._hourlyShowKpIndex
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 3
                                                            WeatherIcon {
                                                                iconInfo: IconResolver.resolve("spaceweather", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                                iconSize: 24
                                                                iconColor: forecastRoot.themeTextColor
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Label {
                                                                text: {
                                                                    if (!weatherRoot)
                                                                        return i18n("No info");
                                                                    var d = weatherRoot.dailyData[dataIndex].dateStr || "";
                                                                    var e = weatherRoot.kpForecastForHour(d, modelData.hour || "") || weatherRoot.kpForecastForDate(d);
                                                                    if (!e || isNaN(e.kp))
                                                                        return i18n("No info");
                                                                    return "Kp " + e.kp.toFixed(1) + " (" + (e.gScale || "G0") + ")";
                                                                }
                                                                color: forecastRoot.themeTextColor
                                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            }
                                                        }

                                                        RowLayout {
                                                            visible: forecastRoot._hourlyShowUvIndex
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 3
                                                            WeatherIcon {
                                                                iconInfo: IconResolver.resolve("uvindex", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                                iconSize: 24
                                                                iconColor: forecastRoot.themeTextColor
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Label {
                                                                text: {
                                                                    var uv = modelData.uvIndex;
                                                                    if (W.isNotSupported(uv))
                                                                        return i18n("N/A");
                                                                    return (uv === undefined || isNaN(uv)) ? "--" : "UV " + uv.toFixed(1);
                                                                }
                                                                color: forecastRoot.themeTextColor
                                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            }
                                                        }

                                                        RowLayout {
                                                            visible: forecastRoot._hourlyShowPrecipSum
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 3
                                                            WeatherIcon {
                                                                iconInfo: IconResolver.resolve("precipsum", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                                iconSize: 24
                                                                iconColor: forecastRoot.themeTextColor
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Label {
                                                                text: weatherRoot ? weatherRoot.precipSumText(modelData.precipMm) : "--"
                                                                color: forecastRoot.themeTextColor
                                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            }
                                                        }

                                                        RowLayout {
                                                            visible: forecastRoot._hourlyShowVisibility
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 3
                                                            WeatherIcon {
                                                                iconInfo: IconResolver.resolve("visibility", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                                iconSize: 24
                                                                iconColor: forecastRoot.themeTextColor
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Label {
                                                                text: weatherRoot ? weatherRoot.visibilityValue(modelData.visibilityKm) : "--"
                                                                color: forecastRoot.themeTextColor
                                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            }
                                                        }

                                                        RowLayout {
                                                            visible: forecastRoot._hourlyShowPrecipProb
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: 3
                                                            WeatherIcon {
                                                                iconInfo: IconResolver.resolve("umbrella", 32, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                                iconSize: 32
                                                                iconColor: forecastRoot.themeTextColor
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Label {
                                                                text: {
                                                                    var ppText = W.hourlyPrecipProbText(modelData.precipProb, modelData.code);
                                                                    if (ppText !== null)
                                                                        return ppText;
                                                                    var h = modelData.humidity;
                                                                    return (!isNaN(h) && h !== undefined) ? Math.round(h) + "%" : "--";
                                                                }
                                                                color: forecastRoot.themeTextColor
                                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            }
                                                        }

                                                        RowLayout {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            spacing: -5
                                                            // Open-Meteo can report a trace precip amount (e.g. 0.1 mm)
                                                            // for an hour whose weather code and probability are dry.
                                                            // Only show the rate when the code itself implies precipitation,
                                                            // so it doesn't contradict a clear/sunny icon at 0% probability.
                                                            // Skipped entirely when the explicit precip-sum stat below is
                                                            // already on, since the two show the same amount.
                                                            visible: !forecastRoot._hourlyShowPrecipSum && modelData.precipMm !== undefined && !isNaN(modelData.precipMm) && modelData.precipMm > 0 && W.isPrecipCode(modelData.code)
                                                            WeatherIcon {
                                                                iconInfo: IconResolver.resolve("preciprate", 32, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                                iconSize: 32
                                                                iconColor: forecastRoot.themeTextColor
                                                                opacity: 0.6
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Label {
                                                                text: weatherRoot ? weatherRoot.precipValue(modelData.precipMm) : "--"
                                                                color: forecastRoot.themeTextColor
                                                                opacity: 0.6
                                                                font: weatherRoot ? weatherRoot.wf(8, false) : Qt.font({})
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: hourlyScrollView
                                acceptedButtons: Qt.NoButton
                                onWheel: function (wheel) {
                                    var bar = hourlyScrollView.ScrollBar.horizontal;
                                    if (!bar)
                                        return;
                                    if (forecastRoot._hourlyWheelWantsHorizontal(wheel)) {
                                        var delta = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : forecastRoot._wheelDeltaX(wheel);
                                        var pixelDelta = wheel.angleDelta.x === 0 && wheel.pixelDelta.x !== 0;
                                        if (delta === 0) {
                                            delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : forecastRoot._wheelDeltaY(wheel);
                                            pixelDelta = wheel.angleDelta.y === 0 && wheel.pixelDelta.y !== 0;
                                        }
                                        var maxPos = Math.max(0, 1.0 - bar.size);
                                        var targetPos = pixelDelta ? Math.max(0, Math.min(maxPos, bar.position - delta / Math.max(1, hourlyRow.implicitWidth))) : Math.max(0, Math.min(maxPos, bar.position - (delta / 120) * 0.15));
                                        hourlyWheelAnimation.to = targetPos;
                                        hourlyWheelAnimation.restart();
                                        wheel.accepted = true;
                                    } else {
                                        wheel.accepted = forecastRoot._scrollParentVertically(wheel);
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    visible: !forecastRoot.dailyGraphs || _isExpanded
                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.08)
                }
            }
        }
    }
}
