/*
 * ForecastChartStack - the Forecast tab's "Graphs" layouts: the temperature graph
 * (with the weather icons and the precipitation strip) and, below it, one graph
 * of its own for each metric (wind, pressure, Kp index, UV index, precipitation
 * sum, visibility).
 *
 * All the graphs are the same chart as the History tab uses (HistoryChartGraphs.qml,
 * or HistoryChartKQC.qml as the fallback; `chartSource` says which). They line up
 * (same left gutter, same days) and zoom and scroll together: zooming or dragging
 * one of them moves all of them.
 *
 * Input
 *   chartSource   the chart file to load ("" = none)
 *   active        whether the graphs are wanted at all
 *   view          adapter for the chart (_temp, _precip, _date, _day; see HistoryChart*.qml)
 *   days          the entries (one per day / hour)
 *   metrics       [{ key, label, color, style ("line" | "bars"), fmt(v), badge(i, key, v),
 *                    barColorAt(i), scaleMin, scaleMax, scaleStep, minSpan }]
 *   configureMain function(chart): sets up the temperature graph (series, icons, ...)
 *   markers / shadeBefore / labelSampleText / minZoomDays / selectable / selectedIndex
 *                 passed on to every graph
 *   outerFlickable  the page's Flickable, the wheel falls through to it
 * Output
 *   mainItem      the temperature graph (zoom state for the toolbar buttons)
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
    property var configureMain: null
    property var markers: []
    property real shadeBefore: -1
    property string labelSampleText: ""
    property int minZoomDays: 3
    property bool selectable: false
    property int selectedIndex: -1
    property var outerFlickable: null
    /** Plot height of a metric graph */
    property real metricPlotH: Kirigami.Units.gridUnit * 3.5

    readonly property var mainItem: mainLoader.item
    readonly property bool _on: active && chartSource !== "" && days.length > 1

    signal chartStatus(var loader)
    signal daySelected(int index)

    spacing: Kirigami.Units.largeSpacing

    // ── the graphs line up and move together ───────────────────────────────
    property real gutter: 0
    property bool _syncing: false

    function _items() {
        var out = [];
        if (mainLoader.item)
            out.push(mainLoader.item);
        for (var i = 0; i < metricRepeater.count; ++i) {
            var l = metricRepeater.itemAt(i);
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

    /** What every graph of the stack has in common */
    function _setup(it) {
        it.view = Qt.binding(function () { return stack.view; });
        it.outerFlickable = Qt.binding(function () { return stack.outerFlickable; });
        it.days = Qt.binding(function () { return stack.days; });
        it.minZoomDays = Qt.binding(function () { return stack.minZoomDays; });
        it.labelSampleText = Qt.binding(function () { return stack.labelSampleText; });
        it.markers = Qt.binding(function () { return stack.markers; });
        it.shadeBefore = Qt.binding(function () { return stack.shadeBefore; });
        it.selectable = Qt.binding(function () { return stack.selectable; });
        it.selectedIndex = Qt.binding(function () { return stack.selectedIndex; });
        it.minPlotX = Qt.binding(function () { return stack.gutter; });
        it.daySelected.connect(function (i) { stack.daySelected(i); });
        it.zoomChanged.connect(function () { stack._follow(it); });
        it.scrollFracChanged.connect(function () { stack._follow(it); });
        it.naturalPlotXChanged.connect(function () { stack._updateGutter(); });
        Qt.callLater(function () {
            stack._updateGutter();
            // a graph that appears while the others are zoomed in joins their view
            var m = mainLoader.item;
            if (m && m !== it && m.zoomed)
                it.setView(m.zoom, m.scrollFrac);
        });
    }

    // ── the temperature graph ──────────────────────────────────────────────
    Loader {
        id: mainLoader
        Layout.fillWidth: true
        active: stack._on
        source: stack.chartSource
        onLoaded: {
            stack._setup(item);
            if (stack.configureMain)
                stack.configureMain(item);
        }
        onStatusChanged: stack.chartStatus(mainLoader)
    }

    // ── one graph per metric ───────────────────────────────────────────────
    Repeater {
        id: metricRepeater
        model: stack._on ? stack.metrics : []

        delegate: Loader {
            id: metricLoader
            required property var modelData
            Layout.fillWidth: true
            source: stack.chartSource
            onLoaded: {
                var m = modelData;
                stack._setup(item);
                // the sunrise / sunset lines, without their labels (the temperature graph has them)
                item.markers = Qt.binding(function () {
                    return stack.markers.map(function (mk) { return { pos: mk.pos, label: "", iconInfo: null }; });
                });
                item.showPrecip = false;
                item.showScrollBar = false;
                item.tempPlotH = Qt.binding(function () { return stack.metricPlotH; });
                item.seriesDefs = [{ key: m.key, color: m.color, label: m.label }];
                item.style = m.style || "line";
                item.valueFormat = m.fmt || null;
                item.badgeFormat = m.badge || null;
                item.barColorAt = m.barColorAt || null;
                item.scaleMin = m.scaleMin !== undefined ? m.scaleMin : NaN;
                item.scaleMax = m.scaleMax !== undefined ? m.scaleMax : NaN;
                item.scaleStep = m.scaleStep !== undefined ? m.scaleStep : NaN;
                item.scaleMinSpan = m.minSpan !== undefined ? m.minSpan : 4;
            }
            onStatusChanged: stack.chartStatus(metricLoader)
        }
    }
}
