/*
 * ForecastChartStack - the Forecast tab's "Graphs" layouts: the temperature graph
 * (with the weather icons and the precipitation strip) and one graph of its own for
 * each metric (wind, pressure, Kp index, UV index, precipitation sum, visibility).
 *
 * All the graphs are the same chart as the History tab uses (HistoryChartGraphs.qml,
 * or HistoryChartKQC.qml as the fallback; `chartSource` says which). They line up
 * (same left gutter, same days) and zoom and scroll together: zooming or dragging
 * one of them moves all of them.
 *
 * The temperature graph is a block like the others: it sits at `mainIndex` among the
 * metric graphs (0 = on top) and is left out when `showMain` is false.
 *
 * Input
 *   chartSource   the chart file to load ("" = none)
 *   active        whether the graphs are wanted at all
 *   view          adapter for the chart (_temp, _precip, _date, _day; see HistoryChart*.qml)
 *   days          the entries (one per day / hour)
 *   metrics       [{ key, label, color, style ("line" | "bars"), fmt(v), badge(i, key, v, entry),
 *                    barColorAt(i, entry), scaleMin, scaleMax, scaleStep, minSpan }]
 *                 The graphs are only rebuilt when the list of keys changes (selecting another
 *                 day or refreshing the data keeps them), so the closures must not capture the data.
 *   showMain      false: no temperature graph (its icons and precipitation strip go with it)
 *   mainIndex     how many metric graphs come before the temperature graph (0 = on top)
 *   configureMain function(chart): sets up the temperature graph (series, icons, ...)
 *   markers / shadeBefore / labelSampleText / minZoomDays / selectable / selectedIndex
 *                 passed on to every graph
 *   outerFlickable  the page's Flickable, the wheel falls through to it
 *   outerScroll   function(wheelEvent): scrolls the page (used when a graph is not zoomed)
 * Output
 *   ready         every graph is loaded (the caller can keep the old height until then)
 *   mainItem      the graph that tells the zoom state for the toolbar buttons: the temperature
 *                 graph, or the first graph when there is none
 *   chartStatus(loader)  a graph's Loader changed status (the caller falls back to
 *                 the next chart engine on an error)
 *   daySelected(index)   a graph was clicked (only when `selectable`)
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: stack

    property string chartSource: ""
    property bool active: true
    property var view: null
    property var days: []
    property var metrics: []
    property bool showMain: true
    property int mainIndex: 0
    property var configureMain: null
    property var markers: []
    property real shadeBefore: -1
    property string labelSampleText: ""
    property int minZoomDays: 3
    property bool selectable: false
    property int selectedIndex: -1
    property var outerFlickable: null
    property var outerScroll: null
    /** Plot height of a metric graph */
    property real metricPlotH: Kirigami.Units.gridUnit * 3.5

    /** The graph whose zoom state the toolbar shows (the temperature graph, else the first one) */
    property var mainItem: null
    /** The temperature graph itself (null when it is not shown) */
    property var _mainChart: null

    // The graphs are only recreated when the SET (or the order) of graphs changes, not each time
    // the data (and with it the `metrics` array) is rebuilt: recreating them is what made the
    // page jump when another day was selected. The temperature graph is one of the blocks.
    property var _blockModel: []
    property string _blockSig: ""
    function _syncBlocks() {
        var list = metrics || [];
        var at = Math.max(0, Math.min(list.length, mainIndex));
        var blocks = [];
        for (var i = 0; i <= list.length; ++i) {
            if (showMain && i === at)
                blocks.push({
                    key: "__main",
                    isMain: true
                });
            if (i < list.length)
                blocks.push(list[i]);
        }
        var sig = blocks.map(function (b) {
            return b.key;
        }).join("|");
        if (sig !== _blockSig) {
            _blockSig = sig;
            _blockModel = blocks;
        }
    }
    // A metric graph takes its color (and, for Kp, its bar colors) from `metrics` when it is
    // created. When only a color changes (the settings were changed) the set of graphs stays
    // the same and nothing is recreated, so the graphs that are already there are re-styled here.
    function _restyle() {
        var list = metrics || [];
        for (var i = 0; i < blockRepeater.count; ++i) {
            var l = blockRepeater.itemAt(i);
            if (!l || !l.item || l.isMain)
                continue;
            for (var k = 0; k < list.length; ++k) {
                var m = list[k];
                if (m.key !== l.modelData.key)
                    continue;
                var defs = l.item.seriesDefs;
                var cur = defs && defs.length > 0 ? String(defs[0].color) : "";
                if (cur !== String(m.color) || !!l.item.barColorAt !== !!m.barColorAt) {
                    l.item.seriesDefs = [
                        {
                            key: m.key,
                            color: m.color,
                            label: m.label
                        }
                    ];
                    l.item.barColorAt = m.barColorAt || null;
                }
                break;
            }
        }
    }
    function _refresh() {
        _syncBlocks();
        _restyle();
    }
    onMetricsChanged: _refresh()
    onShowMainChanged: _refresh()
    onMainIndexChanged: _refresh()
    Component.onCompleted: _syncBlocks()

    /** Which loaded graph is the temperature graph / the one that tells the zoom state */
    function _updateLeader() {
        var main = null, first = null;
        for (var i = 0; i < blockRepeater.count; ++i) {
            var l = blockRepeater.itemAt(i);
            if (!l || !l.item)
                continue;
            if (!first)
                first = l.item;
            if (l.isMain)
                main = l.item;
        }
        if (_mainChart !== main)
            _mainChart = main;
        var lead = main || first;
        if (mainItem !== lead)
            mainItem = lead;
    }

    property bool ready: false
    function _checkReady() {
        _updateLeader();
        var ok = _on && blockRepeater.count > 0;
        for (var i = 0; ok && i < blockRepeater.count; ++i) {
            var l = blockRepeater.itemAt(i);
            if (!l || !l.item)
                ok = false;
        }
        ready = ok;
    }
    on_OnChanged: _checkReady()
    readonly property bool _on: active && chartSource !== "" && days.length > 1

    signal chartStatus(var loader)
    signal daySelected(int index)

    spacing: Kirigami.Units.largeSpacing

    // ── the graphs line up and move together ───────────────────────────────
    property real gutter: 0
    property bool _syncing: false

    function _items() {
        var out = [];
        for (var i = 0; i < blockRepeater.count; ++i) {
            var l = blockRepeater.itemAt(i);
            if (l && l.item)
                out.push(l.item);
        }
        return out;
    }

    function _updateGutter() {
        var g = 0, its = _items();
        for (var i = 0; i < its.length; ++i)
            g = Math.max(g, its[i].naturalPlotX);
        if (Math.abs(g - gutter) > 0.5)
            gutter = g;
    }

    /** `src` was zoomed or scrolled: the others follow */
    function _follow(src) {
        if (_syncing || !src)
            return;
        _syncing = true;
        var its = _items();
        for (var i = 0; i < its.length; ++i)
            if (its[i] !== src)
                its[i].setView(src.zoom, src.scrollFrac);
        _syncing = false;
    }

    // (a Timer rather than Qt.callLater: it dies with the stack, a delayed call to a stack
    // that has been destroyed meanwhile - e.g. a day that was closed - logs errors)
    property var _pendingJoin: []
    Timer {
        id: joinTimer
        interval: 0
        onTriggered: {
            stack._updateGutter();
            stack._updateLeader();
            var m = stack.mainItem;
            var list = stack._pendingJoin;
            stack._pendingJoin = [];
            for (var i = 0; i < list.length; ++i) {
                // a graph that appears while the others are zoomed in joins their view
                var it = list[i];
                if (it && m && m !== it && m.zoomed)
                    it.setView(m.zoom, m.scrollFrac);
            }
        }
    }
    Timer {
        id: readyTimer
        interval: 0
        onTriggered: stack._checkReady()
    }

    /** What every graph of the stack has in common */
    function _setup(it) {
        it.view = Qt.binding(function () {
            return stack.view;
        });
        it.outerFlickable = Qt.binding(function () {
            return stack.outerFlickable;
        });
        it.outerScroll = Qt.binding(function () {
            return stack.outerScroll;
        });
        it.days = Qt.binding(function () {
            return stack.days;
        });
        it.minZoomDays = Qt.binding(function () {
            return stack.minZoomDays;
        });
        it.labelSampleText = Qt.binding(function () {
            return stack.labelSampleText;
        });
        it.markers = Qt.binding(function () {
            return stack.markers;
        });
        it.shadeBefore = Qt.binding(function () {
            return stack.shadeBefore;
        });
        it.selectable = Qt.binding(function () {
            return stack.selectable;
        });
        it.selectedIndex = Qt.binding(function () {
            return stack.selectedIndex;
        });
        it.minPlotX = Qt.binding(function () {
            return stack.gutter;
        });
        it.daySelected.connect(function (i) {
            stack.daySelected(i);
        });
        it.zoomChanged.connect(function () {
            stack._follow(it);
        });
        it.scrollFracChanged.connect(function () {
            stack._follow(it);
        });
        it.naturalPlotXChanged.connect(function () {
            stack._updateGutter();
        });
        _pendingJoin.push(it);
        joinTimer.restart();
    }

    // ── the graphs: the temperature graph and one per metric, in the chosen order ──
    Repeater {
        id: blockRepeater
        model: stack._on ? stack._blockModel : []

        delegate: Loader {
            id: blockLoader
            required property var modelData
            readonly property bool isMain: modelData.isMain === true
            Layout.fillWidth: true
            source: stack.chartSource
            onLoaded: {
                var m = modelData;
                stack._setup(item);
                if (isMain) {
                    // the temperature graph
                    if (stack.configureMain)
                        stack.configureMain(item);
                    return;
                }
                // the sunrise / sunset lines, without their labels (the temperature graph has them)
                item.markers = Qt.binding(function () {
                    return stack.markers.map(function (mk) {
                        return {
                            pos: mk.pos,
                            label: "",
                            iconInfo: null
                        };
                    });
                });
                // the date labels are thinned as if they were as wide as the icons of the temperature graph
                item.labelMinWidth = Qt.binding(function () {
                    return stack._mainChart ? (stack._mainChart.showIcons ? stack._mainChart.iconSize : 0) : 0;
                });
                item.showPrecip = false;
                // the scroll bar belongs to the graph that tells the zoom state
                item.showScrollBar = Qt.binding(function () {
                    return stack.mainItem === item;
                });
                item.tempPlotH = Qt.binding(function () {
                    return stack.metricPlotH;
                });
                item.seriesDefs = [
                    {
                        key: m.key,
                        color: m.color,
                        label: m.label
                    }
                ];
                item.style = m.style || "line";
                item.valueFormat = m.fmt || null;
                item.badgeFormat = m.badge || null;
                item.barColorAt = m.barColorAt || null;
                item.scaleMin = m.scaleMin !== undefined ? m.scaleMin : NaN;
                item.scaleMax = m.scaleMax !== undefined ? m.scaleMax : NaN;
                item.scaleStep = m.scaleStep !== undefined ? m.scaleStep : NaN;
                item.scaleMinSpan = m.minSpan !== undefined ? m.minSpan : 4;
            }
            onStatusChanged: stack.chartStatus(blockLoader)
            onItemChanged: readyTimer.restart()
        }
        onItemAdded: readyTimer.restart()
        onItemRemoved: readyTimer.restart()
    }
}
