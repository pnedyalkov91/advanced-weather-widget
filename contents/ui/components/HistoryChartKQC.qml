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
 * HistoryChartKQC.qml - fallback History tab chart built on KDE's
 * KQuickCharts (import org.kde.quickcharts, KDE Frameworks 6), used when the
 * Qt Graphs module is not available.
 *
 * Same look, interface and behaviour as HistoryChartGraphs.qml (Qt Graphs).
 * Only the drawing differs:
 *
 *   - the three temperature lines are Charts.LineChart items (interpolate:
 *     true gives smoothed lines), with the dots drawn here
 *   - the daily precipitation is one Charts.BarChart
 *
 * Grid, axis labels, date labels, hover cursor / badges, zoom, wheel,
 * double-click and the scroll bar are the same code as in the Qt Graphs chart.
 *
 * Why only a window of days is handed to KQuickCharts: LineChart builds its
 * smoothed curve with one point per 2 px of item width (and a scene-graph
 * segment per 6 points), and it recomputes everything whenever its geometry
 * changes - even when it is only moved. A chart as wide as the whole zoomed
 * period (tens of thousands of pixels) therefore froze Plasma. Now each
 * LineChart / BarChart holds just the days in and around the view (never much
 * wider than the chart itself) and sits inside a plain Item that slides with
 * the scroll position, so scrolling moves one Item and never touches the
 * KQuickCharts geometry. The dots are drawn here, from the same coordinates.
 *
 * Only loaded through a Loader (see HistoryView.qml and ForecastView.qml), and
 * only when the Qt Graphs chart could not be loaded.
 *
 * The interface, including the options the Forecast tab uses (seriesDefs,
 * precipPercent, showIcons / iconAt, markers, shadeBefore, selectable /
 * selectedIndex / daySelected, labelSampleText), is documented in
 * HistoryChartGraphs.qml; the defaults give the History chart.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.quickcharts as Charts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var view: null
    property var days: []
    /** The Flickable (day list) the chart sits in; the wheel falls through to it. */
    property var outerFlickable: null

    // ── Options (the Forecast tab uses them; the defaults are the History chart) ──
    property var seriesDefs: [
        { key: "maxC", color: highColor, label: i18nc("@label chart legend", "High") },
        { key: "meanC", color: meanColor, label: i18nc("@label chart legend", "Mean") },
        { key: "minC", color: lowColor, label: i18nc("@label chart legend", "Low") }
    ]
    readonly property int nSeries: Math.min(3, seriesDefs.length)
    property string precipLegend: i18nc("@label chart legend", "Precipitation")
    property bool precipPercent: false
    property bool showIcons: false
    property var iconAt: null
    property real iconSize: Kirigami.Units.gridUnit * 1.5
    property var markers: []
    property real shadeBefore: -1
    property bool selectable: false
    property int selectedIndex: -1
    property string labelSampleText: ""
    // One metric on its own (the Forecast tab's wind / pressure / ... graphs):
    /** false: no precipitation strip below the plot (and none in the legend) */
    property bool showPrecip: true
    /** "line": the series are lines; "bars": the first series is drawn as bars */
    property string style: "line"
    /** function(v) -> text for the axis labels and the hover badges (default: view._temp) */
    property var valueFormat: null
    /** function(index, key, v) -> text of a hover badge (default: valueFormat) */
    property var badgeFormat: null
    /** function(index) -> colour of one bar ("bars" style; default: the series colour) */
    property var barColorAt: null
    /** forced ends / step of the value axis (NaN: from the data) and its smallest span */
    property real scaleMin: NaN
    property real scaleMax: NaN
    property real scaleStep: NaN
    property real scaleMinSpan: 4
    /** least width of the left gutter, so that charts stacked above each other line up */
    property real minPlotX: 0
    /** false: no scroll bar under the chart (a chart that follows another one's zoom) */
    property bool showScrollBar: true
    /** Width of the left gutter the axis labels need (what `minPlotX` is compared with). */
    readonly property real naturalPlotX: area.naturalX
    /** An entry was clicked (only when `selectable`). */
    signal daySelected(int index)

    // Index of the day under the pointer, -1 when none.
    property int hoverIndex: -1

    readonly property int dayCount: days.length
    readonly property color highColor: "#ef5350"
    readonly property color lowColor: "#42a5f5"
    readonly property color meanColor: Kirigami.Theme.textColor
    readonly property color precipColor: "#26c6da"

    // ── Zoom ──────────────────────────────────────────────────────────────
    // 1 = whole period fits; the plot is `zoom` times as wide as the chart.
    property real zoom: 1
    property int minZoomDays: 3                          // most zoomed-in view
    readonly property real maxZoom: Math.max(1, dayCount / minZoomDays)
    readonly property bool zoomed: zoom > 1.001
    readonly property bool canZoomIn: zoom < maxZoom - 0.001
    // Days whose point is within half a step of the viewport.
    readonly property int visibleFirst: dayCount > 0
        ? Math.max(0, Math.min(dayCount - 1, Math.round((scroller.contentX - area.pad) / area.step))) : 0
    readonly property int visibleLast: dayCount > 0
        ? Math.max(visibleFirst, Math.min(dayCount - 1, Math.round((scroller.contentX + area.vw - area.pad) / area.step))) : 0

    /** Zoom to `z` (1 … maxZoom); `anchor` (0..1 across the chart) stays put. */
    function zoomTo(z, anchor) {
        var a = (typeof anchor === "number") ? Math.max(0, Math.min(1, anchor)) : 0.5;
        var nz = Math.max(1, Math.min(maxZoom, z));
        if (nz < 1.05)
            nz = 1;
        if (Math.abs(nz - zoom) < 0.001)
            return;
        wheelAnim.stop();
        var vw = area.vw;
        var focus = (scroller.contentX + a * vw) / (vw * zoom);
        zoom = nz;
        scroller.contentX = Math.max(0, Math.min(vw * nz - vw, focus * vw * nz - a * vw));
    }
    /** Mouse wheel / touchpad over the chart (called from the MouseArea
     *  `wheelArea`, the same approach ForecastView uses for its hourly strip).
     *  While zoomed in, a wheel notch, a sideways touchpad swipe or
     *  Shift+wheel scrolls the chart; a vertical touchpad swipe, or any wheel
     *  movement once the chart is at its end (or not zoomed), scrolls the day
     *  list behind it instead (outerFlickable). */
    function wheelPan(event) {
        var tp = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0;
        var dx = tp ? event.pixelDelta.x : event.angleDelta.x;
        var dy = tp ? event.pixelDelta.y : event.angleDelta.y;
        var d = 0;
        if (Math.abs(dx) > Math.abs(dy))
            d = dx;
        else if (!tp || (event.modifiers & Qt.ShiftModifier))
            d = dy;
        event.accepted = true;
        var base = wheelAnim.running ? wheelAnim.to : scroller.contentX;
        var maxX = scroller.contentWidth - scroller.width;
        var nx = base;
        if (zoomed && d !== 0) {
            // A notch (120) moves about two days; a touchpad moves 1:1.
            var move = tp ? d : d / 120 * Math.max(area.step * 2, Kirigami.Units.gridUnit * 2);
            nx = Math.max(0, Math.min(maxX, base - move));
        }
        if (nx === base) {
            // Nothing to pan: scroll the page behind the chart instead.
            var f = outerFlickable;
            if (f) {
                var wy = tp ? event.pixelDelta.y : event.angleDelta.y / 2;
                var oy = f.originY || 0;
                f.contentY = Math.max(oy, Math.min(oy + f.contentHeight - f.height, f.contentY - wy));
            }
            return;
        }
        root.hoverIndex = -1;
        if (tp) {
            wheelAnim.stop();
            scroller.contentX = nx;
        } else {
            wheelAnim.stop();
            wheelAnim.from = scroller.contentX;
            wheelAnim.to = nx;
            wheelAnim.start();
        }
    }

    function zoomIn() { zoomTo(zoom * 2, 0.5); }
    function zoomOut() { zoomTo(zoom / 2, 0.5); }
    function resetZoom() {
        wheelAnim.stop();
        zoom = 1;
        scroller.contentX = 0;
    }

    /** Where the view starts, as a fraction (0..1) of the whole plot: together with `zoom`
     *  this is the state that charts stacked above each other pass on to one another. */
    readonly property real scrollFrac: area.vw * zoom > 0 ? scroller.contentX / (area.vw * zoom) : 0
    function setView(z, frac) {
        var nz = Math.max(1, Math.min(maxZoom, z));
        var vw = area.vw;
        var nx = Math.max(0, Math.min(vw * nz - vw, frac * vw * nz));
        if (Math.abs(nz - zoom) < 0.001 && Math.abs(nx - scroller.contentX) < 0.5)
            return;
        wheelAnim.stop();
        zoom = nz;
        scroller.contentX = nx;
    }

    // ── Geometry ──────────────────────────────────────────────────────────
    readonly property real marginV: Kirigami.Units.largeSpacing
    property real tempPlotH: Kirigami.Units.gridUnit * 6
    readonly property real precipPlotH: Kirigami.Units.gridUnit * 2.5
    readonly property real badgeH: Kirigami.Units.gridUnit + 4

    spacing: Kirigami.Units.smallSpacing

    // ── Temperature scale: "nice" bounds so grid lines carry round labels ─
    readonly property var tempScale: _computeScale(days, seriesDefs, scaleMin, scaleMax, scaleStep, scaleMinSpan)

    function _niceStep(rough) {
        var p = Math.pow(10, Math.floor(Math.log(rough) / Math.LN10));
        var f = rough / p;
        var nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
        return nf * p;
    }

    function _computeScale(ds, defs, fixLo, fixHi, fixStep, minSpan) {
        var lo = Infinity, hi = -Infinity;
        for (var i = 0; i < ds.length; ++i) {
            for (var k = 0; k < defs.length; ++k) {
                var a = ds[i][defs[k].key];
                if (typeof a === "number" && isFinite(a)) { hi = Math.max(hi, a); lo = Math.min(lo, a); }
            }
        }
        var forcedLo = isFinite(fixLo), forcedHi = isFinite(fixHi);
        if (!isFinite(lo) || !isFinite(hi)) {
            lo = forcedLo ? fixLo : 0;
            hi = forcedHi ? fixHi : lo + 10;
            if (!isFinite(fixStep))
                return { lo: lo, hi: hi, ticks: 3 };
        }
        if (forcedLo)
            lo = fixLo;
        if (forcedHi)
            hi = fixHi;
        var step = isFinite(fixStep) && fixStep > 0 ? fixStep : _niceStep(Math.max(hi - lo, minSpan) / 3);
        var nlo = forcedLo ? lo : Math.floor(lo / step) * step;
        var nhi = forcedHi ? hi : Math.ceil(hi / step) * step;
        if (nhi - nlo < step * 2)
            nhi = nlo + step * 2;
        return { lo: nlo, hi: nhi, ticks: Math.max(2, Math.round((nhi - nlo) / step) + 1) };
    }

    readonly property real precipMax: {
        if (precipPercent)
            return 100;
        var m = 5;
        for (var i = 0; i < days.length; ++i)
            if (isFinite(days[i].precipMm))
                m = Math.max(m, days[i].precipMm);
        return _niceStep(m / 2) * 2;     // 5, 10, 20, 50 …
    }

    // Rain total of the days currently in view.
    readonly property real visiblePrecipSum: {
        var s = 0;
        for (var i = visibleFirst; i <= visibleLast && i < days.length; ++i)
            if (isFinite(days[i].precipMm))
                s += days[i].precipMm;
        return s;
    }

    function _fmtTemp(v) { return valueFormat ? valueFormat(v) : (view ? view._temp(v) : String(v)); }
    function _badgeText(i, key, v) { return badgeFormat ? badgeFormat(i, key, v) : _fmtTemp(v); }
    function _fmtPrecip(v) { return view ? view._precip(v) : String(v); }
    function _dateText(i) { return view && i >= 0 && i < days.length ? view._date(days[i].dateStr, days[i]) : ""; }
    function _titleText(i) { return view && i >= 0 && i < days.length ? view._day(days[i].dateStr, false, days[i]) : ""; }

    // ── Data for KQuickCharts ─────────────────────────────────────────────
    // A LineChart cannot skip a day, so each series is cut to the span between
    // its first and last day with data, and gaps inside that span are filled
    // linearly (the same straight bridge the Qt Graphs chart draws).
    // `real[i]` tells whether entry i is a measured value (dots are drawn only for those).
    function _series(ds, key) {
        var a = -1, b = -1;
        for (var i = 0; i < ds.length; ++i) {
            var v = ds[i][key];
            if (typeof v === "number" && isFinite(v)) {
                if (a < 0)
                    a = i;
                b = i;
            }
        }
        if (a < 0 || b <= a)
            return { start: Math.max(a, 0), count: a < 0 ? 0 : 1, values: [], real: [] };
        var vals = [], real = [];
        var prev = a;
        for (var k = a; k <= b; ++k) {
            var x = ds[k][key];
            if (typeof x === "number" && isFinite(x)) {
                vals.push(x);
                real.push(true);
                prev = k;
            } else {
                var nx = k + 1;
                while (nx <= b && !(typeof ds[nx][key] === "number" && isFinite(ds[nx][key])))
                    ++nx;
                var y0 = ds[prev][key], y1 = ds[nx][key];
                vals.push(y0 + (y1 - y0) * (k - prev) / (nx - prev));
                real.push(false);
            }
        }
        return { start: a, count: b - a + 1, values: vals, real: real };
    }
    readonly property var seriesData: {
        var o = {};
        for (var i = 0; i < seriesDefs.length; ++i)
            o[seriesDefs[i].key] = _series(days, seriesDefs[i].key);
        return o;
    }
    // Daily precipitation for the BarChart (missing days count as 0)
    readonly property var precipArray: {
        var out = [];
        for (var i = 0; i < days.length; ++i)
            out.push(isFinite(days[i].precipMm) ? days[i].precipMm : 0);
        return out;
    }

    // ── Legend ────────────────────────────────────────────────────────────
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: root.showPrecip ? root.seriesDefs.concat([{ label: root.precipLegend, color: root.precipColor }]) : root.seriesDefs
            delegate: RowLayout {
                id: legendItem
                required property var modelData
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    Layout.preferredWidth: legendLabel.height * 0.8
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: 2
                    color: legendItem.modelData.color
                }
                Label {
                    id: legendLabel
                    text: legendItem.modelData.label
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.textColor
                    opacity: 0.75
                }
            }
        }
    }

    // ── Chart area (everything is positioned explicitly: labels, grid and
    //    the cursor must line up with the plot to the pixel) ──────────────
    Item {
        id: area
        Layout.fillWidth: true

        TextMetrics { id: tmDate; font: Kirigami.Theme.smallFont; text: root.labelSampleText !== "" ? root.labelSampleText : (root.view && root.dayCount > 0 ? root._dateText(0) : "00.00.0000") }
        TextMetrics { id: tmH; font: Kirigami.Theme.smallFont; text: "Wg" }
        TextMetrics { id: tmLo; font: Kirigami.Theme.smallFont; text: root._fmtTemp(root.tempScale.lo) }
        TextMetrics { id: tmHi; font: Kirigami.Theme.smallFont; text: root._fmtTemp(root.tempScale.hi) }
        TextMetrics { id: tmP; font: Kirigami.Theme.smallFont; text: root._fmtPrecip(root.precipMax) }

        // Left gutter for the axis labels (widest label + a little air), so
        // the plot starts clear of them. The plot ("viewport") is `vw` wide.
        readonly property real naturalX: Math.ceil(Math.max(tmLo.width, tmHi.width, root.showPrecip ? tmP.width : 0)) + Kirigami.Units.largeSpacing * 2
        readonly property real plotX: Math.max(root.minPlotX, naturalX)
        readonly property real vw: Math.max(1, width - plotX)

        readonly property real dateLabelH: Math.ceil(tmH.height) + Kirigami.Units.smallSpacing

        // Vertical layout (the line charts are the temperature band)
        // Row of icons (Forecast tab) above the date labels
        readonly property real iconH: root.showIcons ? root.iconSize + Kirigami.Units.smallSpacing : 0
        readonly property real gvY: iconH + dateLabelH
        readonly property real gvH: root.tempPlotH + 2 * root.marginV
        readonly property real py: gvY + root.marginV           // plot top
        readonly property real ph: root.tempPlotH
        // Without the precipitation strip the plot ends where the value plot does
        readonly property real precipTop: root.showPrecip ? gvY + gvH + Kirigami.Units.largeSpacing : py + ph
        readonly property real precipBottom: root.showPrecip ? precipTop + root.precipPlotH : py + ph
        readonly property real plotBottom: root.showPrecip ? precipBottom + Kirigami.Units.smallSpacing : gvY + gvH + Kirigami.Units.smallSpacing

        // Room for the scroll bar. Always reserved: the view sits in a ListView
        // header, and a header that changes height makes the list jump.
        readonly property real sbH: root.showScrollBar ? hbar.implicitHeight : 0
        implicitHeight: plotBottom + sbH

        // Horizontal layout: the whole period is `contentW` wide, `step` per
        // day; only the part starting at scroller.contentX is on screen.
        // The first day sits `pad` from the left end of the content and the
        // last day `pad` from the right end, so at zoom 1 the graph runs from
        // edge to edge. `step` is the distance between two days.
        readonly property real contentW: vw * root.zoom
        readonly property real pad: root.dayCount > 1 ? Math.max(8, Kirigami.Units.smallSpacing * 2) : vw / 2
        readonly property real step: root.dayCount > 1 ? Math.max(0.001, (contentW - 2 * pad) / (root.dayCount - 1)) : 1

        // The days KQuickCharts is given: the ones in view plus a few either
        // side. The count only depends on the zoom, so while panning the
        // charts keep their size and only the data shifts by whole days.
        readonly property int winCount: Math.min(root.dayCount, Math.ceil(vw / step) + 4)
        readonly property int winFirst: root.dayCount > 0
            ? Math.max(0, Math.min(root.dayCount - winCount, Math.floor((scroller.contentX - pad) / step) - 1)) : 0
        readonly property int winLast: winFirst + winCount - 1

        /** x of day i's point, in chart (viewport) coordinates */
        function xOf(i) { return pad + i * step - scroller.contentX; }
        function yOf(v) { return py + (root.tempScale.hi - v) / (root.tempScale.hi - root.tempScale.lo) * ph; }

        /** Left edge of day idx's date label. Labels are centred on their
         *  vertical line; the first day's label starts at its line and the last
         *  day's ends at it (so the line never sits off to one side of a label
         *  that is pushed in from the edge); all are kept inside the view. */
        function labelLeft(idx) {
            var w = tmDate.width;
            var c = xOf(idx);
            var l = idx === 0 ? c : (idx === root.dayCount - 1 ? c - w : c - w / 2);
            return Math.max(0, Math.min(vw - w, l));
        }

        // Date labels / vertical grid lines: whole multiples of `step` days
        // whose label fits completely inside the view (the two end days may
        // sit against the edge), thinned so that no two labels touch.
        readonly property var labelIdx: {
            var n = root.dayCount;
            if (n < 2)
                return [];
            var w = tmDate.width;
            var gap = Kirigami.Units.largeSpacing * 2;
            var every = Math.max(1, Math.ceil((w + gap) / step));
            var first = Math.max(0, Math.floor((scroller.contentX - pad) / step) - 1);
            var last = Math.min(n - 1, Math.ceil((scroller.contentX + vw - pad) / step) + 1);
            var cand = [];
            for (var i = Math.ceil(first / every) * every; i <= last; i += every)
                cand.push(i);
            if (cand.length === 0 || cand[cand.length - 1] !== n - 1)
                cand.push(n - 1);
            var out = [];
            var prevRight = -1e9;
            for (var k = 0; k < cand.length; ++k) {
                var idx = cand[k];
                var c = xOf(idx);
                if (c < 0 || c > vw)
                    continue;               // point not in view
                var isEnd = idx === 0 || idx === n - 1;
                if (!isEnd && (c - w / 2 < 0 || c + w / 2 > vw))
                    continue;               // label would be cut or pushed
                var left = labelLeft(idx);
                if (left < prevRight + gap) {
                    // collides with the previous label: the last day wins
                    if (idx === n - 1 && out.length > 0 && out[out.length - 1] !== 0) {
                        out.pop();
                        prevRight = out.length > 0 ? labelLeft(out[out.length - 1]) + w : -1e9;
                        if (left < prevRight + gap)
                            continue;
                    } else {
                        continue;
                    }
                }
                out.push(idx);
                prevRight = left + w;
            }
            return out;
        }

        // ── horizontal grid (fixed) ───────────────────────────────────
        Repeater {
            model: root.dayCount > 1 ? root.tempScale.ticks : 0
            delegate: Rectangle {
                required property int index
                x: area.plotX
                width: area.vw
                height: 1
                y: area.py + index / (root.tempScale.ticks - 1) * area.ph - 0.5
                color: Kirigami.Theme.textColor
                opacity: 0.12
            }
        }
        Rectangle {
            x: area.plotX
            width: area.vw
            height: 1
            y: area.precipTop
            visible: root.dayCount > 1 && root.showPrecip
            color: Kirigami.Theme.textColor
            opacity: 0.12
        }
        Rectangle {
            x: area.plotX
            width: area.vw
            height: 1
            y: area.precipBottom
            color: Kirigami.Theme.textColor
            opacity: 0.25
        }

        // Smooth mouse-wheel scrolling (same feel as ForecastView's hourly strip)
        NumberAnimation {
            id: wheelAnim
            target: scroller
            property: "contentX"
            duration: 140
            easing.type: Easing.OutCubic
        }

        // ── scrolling surface ─────────────────────────────────────────
        // Transparent: it only supplies drag/flick/scroll-bar behaviour. The
        // content below is pinned to the viewport (x follows contentX).
        Flickable {
            id: scroller
            anchors.left: parent.left
            anchors.leftMargin: area.plotX
            anchors.right: parent.right
            anchors.top: parent.top
            height: area.plotBottom
            contentWidth: area.contentW
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: false          // see "drag to scroll" below
            clip: true

            ScrollBar.horizontal: ScrollBar {
                id: hbar
                parent: scroller.parent
                anchors.left: scroller.left
                anchors.right: scroller.right
                anchors.top: scroller.bottom
                visible: root.zoomed && root.showScrollBar
                policy: ScrollBar.AlwaysOn
            }

            Item {
                id: pinned
                x: scroller.contentX
                width: area.vw
                height: scroller.height

                // ── vertical grid + date labels ────────────────────────
                Repeater {
                    model: area.labelIdx
                    delegate: Rectangle {
                        required property int modelData
                        // runs through the precipitation strip too, so the bars
                        // can be read against the same dates; snapped to a whole
                        // pixel so every line is equally crisp
                        width: 1
                        x: Math.round(area.xOf(modelData) - 0.5)
                        y: area.py
                        height: area.precipBottom - area.py
                        color: Kirigami.Theme.textColor
                        opacity: 0.12
                    }
                }
                Repeater {
                    model: area.labelIdx
                    delegate: Label {
                        required property int modelData
                        visible: root.hoverIndex < 0 && modelData < root.dayCount
                        text: modelData < root.dayCount ? root._dateText(modelData) : ""
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.textColor
                        opacity: 0.75
                        x: Math.max(0, Math.min(area.vw - width, area.xOf(modelData)
                            - (modelData === 0 ? 0 : (modelData === root.dayCount - 1 ? width : width / 2))))
                        y: area.iconH
                    }
                }

                // ── selected entry (Forecast tab: the day whose hours are shown) ──
                Rectangle {
                    visible: root.selectedIndex >= 0 && root.selectedIndex < root.dayCount
                    x: area.xOf(root.selectedIndex) - area.step / 2
                    y: area.gvY
                    width: area.step
                    height: area.precipBottom - area.gvY
                    color: Kirigami.Theme.highlightColor
                    opacity: 0.14
                }

                // ── marks such as sunrise / sunset (Forecast tab, hourly) ──
                Repeater {
                    model: root.markers
                    delegate: Item {
                        id: mark
                        required property var modelData
                        readonly property real mx: area.xOf(modelData.pos)
                        visible: mx >= 0 && mx <= area.vw
                        Rectangle {
                            x: Math.round(mark.mx - 0.5)
                            y: area.py
                            width: 1
                            height: area.precipBottom - area.py
                            color: Kirigami.Theme.textColor
                            opacity: 0.3
                        }
                        Row {
                            spacing: 2
                            x: Math.min(area.vw - width, mark.mx + 3)
                            y: area.gvY
                            Loader {
                                active: !!mark.modelData.iconInfo
                                visible: active
                                source: "WeatherIcon.qml"
                                onLoaded: {
                                    item.iconInfo = Qt.binding(function () { return mark.modelData.iconInfo; });
                                    item.iconSize = Kirigami.Units.gridUnit;
                                    item.iconColor = Qt.binding(function () { return Kirigami.Theme.textColor; });
                                }
                            }
                            Label {
                                text: mark.modelData.label
                                font: Kirigami.Theme.smallFont
                                color: Kirigami.Theme.textColor
                                opacity: 0.8
                            }
                        }
                    }
                }

                // ── hover column ───────────────────────────────────────
                // (a BarChart cannot dim a single bar, so the hovered day gets a band)
                Rectangle {
                    visible: root.hoverIndex >= 0 && root.hoverIndex < root.dayCount
                    x: area.xOf(root.hoverIndex) - area.step / 2
                    y: area.gvY
                    width: area.step
                    height: area.precipBottom - area.gvY
                    color: Kirigami.Theme.textColor
                    opacity: 0.08
                }

                // ── KQuickCharts: the three temperature lines ──────────
                // One LineChart per series, holding only the days of the
                // window (area.winFirst … winLast) that the series covers. The
                // chart is the same size whatever the scroll position; its
                // holder Item slides, so point i sits exactly at area.xOf(i)
                // and the y range is the plot's scale.
                Repeater {
                    model: root.dayCount > 1 && root.style === "line" ? root.seriesDefs.slice(0, 3) : []
                    delegate: Item {
                        id: holder
                        required property var modelData
                        readonly property var sd: root.seriesData[modelData.key]
                        // first / last day of this series inside the window
                        readonly property int first: sd ? Math.max(sd.start, area.winFirst) : 0
                        readonly property int last: sd ? Math.min(sd.start + sd.count - 1, area.winLast) : -1
                        readonly property bool ok: !!sd && sd.count >= 2 && last > first

                        visible: ok
                        x: area.xOf(first)
                        y: area.py
                        width: Math.max(1, (last - first) * area.step)
                        height: area.ph

                        Charts.LineChart {
                            anchors.fill: parent
                            interpolate: true
                            lineWidth: holder.modelData.key === "meanC" ? 2.5 : 3
                            fillOpacity: 0
                            yRange {
                                from: root.tempScale.lo
                                to: root.tempScale.hi
                                automatic: false
                            }
                            valueSources: [
                                Charts.ArraySource {
                                    array: holder.ok
                                        ? holder.sd.values.slice(holder.first - holder.sd.start, holder.last - holder.sd.start + 1)
                                        : []
                                }
                            ]
                            colorSource: Charts.ArraySource { array: [holder.modelData.color] }
                        }
                    }
                }

                // ── a dot per measured day (like the KDE weather applet) ──
                // Drawn here rather than by LineChart's pointDelegate, which
                // would be rebuilt whenever the chart is resized; left out
                // when the days are too close together.
                Repeater {
                    model: pinned.showDots && root.dayCount > 1 && root.style === "line" ? root.seriesDefs : []
                    delegate: Item {
                        id: dotSet
                        required property var modelData
                        readonly property var sd: root.seriesData[modelData.key]

                        Repeater {
                            model: dotSet.sd ? area.winCount : 0
                            delegate: Rectangle {
                                required property int index
                                readonly property int day: area.winFirst + index
                                readonly property int rel: day - dotSet.sd.start
                                visible: rel >= 0 && rel < dotSet.sd.count && dotSet.sd.real[rel] === true
                                width: pinned.dotSize
                                height: width
                                radius: width / 2
                                x: area.xOf(day) - width / 2
                                y: visible ? area.yOf(dotSet.sd.values[rel]) - height / 2 : 0
                                color: dotSet.modelData.color
                                border.width: 1
                                border.color: Kirigami.Theme.backgroundColor
                            }
                        }
                    }
                }

                // ── precipitation bars (one BarChart, a slot per day) ───
                // Window of days only, like the lines; slot i is `step` wide
                // and centred on area.xOf(i).
                Item {
                    visible: root.dayCount > 1 && root.showPrecip
                    x: area.xOf(area.winFirst) - area.step / 2
                    y: area.precipTop
                    width: area.winCount * area.step
                    height: root.precipPlotH

                    Charts.BarChart {
                        anchors.fill: parent
                        barWidth: Math.max(1, Math.min(area.step * 0.62, 14))
                        radius: Math.min(2, barWidth / 2)
                        yRange {
                            from: 0
                            to: root.precipMax
                            automatic: false
                        }
                        valueSources: [
                            Charts.ArraySource { array: root.precipArray.slice(area.winFirst, area.winFirst + area.winCount) }
                        ]
                        // same 0.9 opacity as the bars of the Qt Graphs chart
                        colorSource: Charts.ArraySource { array: [Qt.alpha(root.precipColor, 0.9)] }
                    }
                }

                // ── dot size ───────────────────────────────────────────
                readonly property real dotSize: Kirigami.Units.gridUnit * 0.4
                readonly property bool showDots: area.step >= dotSize * 2.4

                // ── "bars" style: the first series as bars from the bottom of the plot ──
                Repeater {
                    model: root.style === "bars" && root.dayCount > 1 && root.seriesDefs.length > 0 ? root.days : []
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property real v: typeof modelData[root.seriesDefs[0].key] === "number" ? modelData[root.seriesDefs[0].key] : NaN
                        readonly property real bw: Math.max(1, Math.min(area.step * 0.62, 14))
                        readonly property bool has: typeof v === "number" && isFinite(v) && v > root.tempScale.lo
                        readonly property real bx: area.xOf(index) - bw / 2
                        visible: has && bx + bw > 0 && bx < area.vw
                        x: bx
                        width: bw
                        y: has ? Math.min(area.py + area.ph - 1, area.yOf(Math.min(v, root.tempScale.hi))) : 0
                        height: has ? area.py + area.ph - y : 0
                        radius: Math.min(2, bw / 2)
                        color: root.barColorAt ? root.barColorAt(index) : root.seriesDefs[0].color
                        opacity: root.hoverIndex < 0 || root.hoverIndex === index ? 0.9 : 0.55
                    }
                }

                // ── hours that have already passed (greyed out) ────────
                Rectangle {
                    visible: root.shadeBefore >= 0 && width > 0
                    x: 0
                    y: area.gvY
                    width: Math.max(0, Math.min(area.vw, area.xOf(root.shadeBefore)))
                    height: area.precipBottom - area.gvY
                    color: Kirigami.Theme.backgroundColor
                    opacity: 0.55
                }

                // ── one icon per entry, thinned out when they would touch ──
                Repeater {
                    model: root.showIcons && root.dayCount > 0 ? root.dayCount : 0
                    delegate: Item {
                        id: iconSlot
                        required property int index
                        readonly property int every: Math.max(1, Math.ceil((root.iconSize + Kirigami.Units.smallSpacing) / area.step))
                        readonly property real cx: area.xOf(index)
                        readonly property var info: root.iconAt ? root.iconAt(index) : null
                        // the first and last icon are pushed in from the edge rather than cut -
                        // unless the icons are so close that this would make them touch
                        readonly property bool roomAtEdge: area.step >= root.iconSize + Kirigami.Units.smallSpacing
                        visible: index % every === 0 && cx >= 0 && cx <= area.vw
                            && (roomAtEdge || (cx - root.iconSize / 2 >= 0 && cx + root.iconSize / 2 <= area.vw))
                        x: Math.max(0, Math.min(area.vw - root.iconSize, cx - root.iconSize / 2))
                        y: 0
                        width: root.iconSize
                        height: root.iconSize
                        Loader {
                            anchors.fill: parent
                            active: iconSlot.visible && !!iconSlot.info
                            // WeatherIcon.qml sits next to this file; it is only loaded when the
                            // Forecast tab asks for icons, so the History chart does not depend on it
                            source: "WeatherIcon.qml"
                            onLoaded: {
                                item.iconInfo = Qt.binding(function () { return iconSlot.info; });
                                item.iconSize = Qt.binding(function () { return root.iconSize; });
                                item.iconColor = Qt.binding(function () { return Kirigami.Theme.textColor; });
                            }
                        }
                    }
                }

                // ── hover cursor + value badges ────────────────────────
                readonly property bool hovering: root.hoverIndex >= 0 && root.hoverIndex < root.dayCount
                readonly property var hoverDay: hovering ? root.days[root.hoverIndex] : null
                readonly property real cursorX: hovering ? area.xOf(root.hoverIndex) : 0
                readonly property bool badgesRight: cursorX < area.vw / 2

                Rectangle {
                    visible: pinned.hovering
                    x: pinned.cursorX - 1
                    y: area.py - root.marginV / 2
                    width: 2
                    height: area.precipBottom - y
                    color: Kirigami.Theme.highlightColor
                }

                // Larger dots where the cursor crosses each line (as in the KDE
                // weather applet's forecast graph)
                Repeater {
                    model: root.style === "line" ? root.seriesDefs : []
                    delegate: Rectangle {
                        required property var modelData
                        readonly property real v: pinned.hoverDay && typeof pinned.hoverDay[modelData.key] === "number" ? pinned.hoverDay[modelData.key] : NaN
                        visible: pinned.hovering && isFinite(v)
                        width: Kirigami.Units.gridUnit * 0.6
                        height: width
                        radius: width / 2
                        x: pinned.cursorX - width / 2
                        y: isFinite(v) ? area.yOf(v) - height / 2 : 0
                        color: modelData.color
                        border.width: 2
                        border.color: Kirigami.Theme.backgroundColor
                    }
                }

                Label {
                    visible: pinned.hovering
                    text: pinned.hovering ? root._titleText(root.hoverIndex) : ""
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.textColor
                    x: Math.max(0, Math.min(area.vw - width, pinned.cursorX - width / 2))
                    y: area.iconH
                }

                // De-overlap the temperature badges (same idea as the KDE applet's
                // ForecastGraphLine.positionLabelsY): sort, push apart, keep centred.
                readonly property var badgeYs: {
                    var nS = root.seriesDefs.length;
                    var zeros = [];
                    for (var z = 0; z < nS; ++z)
                        zeros.push(0);
                    if (!hovering)
                        return zeros;
                    var d = hoverDay;
                    var vals = [];
                    for (var q = 0; q < nS; ++q)
                        vals.push(d[root.seriesDefs[q].key]);
                    var items = [];
                    for (var i = 0; i < nS; ++i)
                        if (typeof vals[i] === "number" && isFinite(vals[i]))
                            items.push({ i: i, y: area.yOf(vals[i]) - root.badgeH / 2 });
                    items.sort(function (a, b) { return a.y - b.y; });
                    var pref = items.map(function (it) { return it.y; });
                    for (var k = 1; k < items.length; ++k) {
                        var minY = items[k - 1].y + root.badgeH + Kirigami.Units.smallSpacing;
                        if (items[k].y < minY)
                            items[k].y = minY;
                    }
                    if (items.length > 0) {
                        var c1 = (pref[0] + pref[pref.length - 1]) / 2;
                        var c2 = (items[0].y + items[items.length - 1].y) / 2;
                        var shift = c1 - c2;
                        for (var m = 0; m < items.length; ++m)
                            items[m].y += shift;
                        var top = area.gvY, bottom = area.gvY + area.gvH;
                        if (items[0].y < top)
                            shift = top - items[0].y;
                        else if (items[items.length - 1].y + root.badgeH > bottom)
                            shift = bottom - root.badgeH - items[items.length - 1].y;
                        else
                            shift = 0;
                        for (var n2 = 0; n2 < items.length; ++n2)
                            items[n2].y += shift;
                    }
                    var out = zeros;
                    for (var j = 0; j < items.length; ++j)
                        out[items[j].i] = items[j].y;
                    return out;
                }

                Repeater {
                    model: root.seriesDefs.map(function (sd) {
                        var v = pinned.hoverDay ? pinned.hoverDay[sd.key] : NaN;
                        return { color: sd.color, text: pinned.hoverDay ? root._badgeText(root.hoverIndex, sd.key, v) : "", ok: typeof v === "number" && isFinite(v) };
                    })
                    delegate: Rectangle {
                        id: badge
                        required property var modelData
                        required property int index
                        visible: pinned.hovering && modelData.ok
                        width: badgeText.implicitWidth + 8
                        height: root.badgeH
                        radius: 4
                        color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(modelData.color, 0.18))
                        border.width: 1
                        border.color: Qt.alpha(modelData.color, 0.6)
                        x: pinned.badgesRight ? pinned.cursorX + Kirigami.Units.largeSpacing
                                              : pinned.cursorX - Kirigami.Units.largeSpacing - width
                        y: pinned.badgeYs[index]
                        Label {
                            id: badgeText
                            anchors.centerIn: parent
                            text: badge.modelData.text
                            font: Kirigami.Theme.smallFont
                            color: badge.modelData.color === root.meanColor ? Kirigami.Theme.textColor : badge.modelData.color
                        }
                    }
                }

                // Precipitation badge, sitting on top of the hovered bar
                Rectangle {
                    id: precipBadge
                    visible: root.showPrecip && pinned.hovering && !!pinned.hoverDay && isFinite(pinned.hoverDay.precipMm)
                    width: precipBadgeText.implicitWidth + 8
                    height: root.badgeH
                    radius: 4
                    color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(root.precipColor, 0.18))
                    border.width: 1
                    border.color: Qt.alpha(root.precipColor, 0.6)
                    x: pinned.badgesRight ? pinned.cursorX + Kirigami.Units.largeSpacing
                                          : pinned.cursorX - Kirigami.Units.largeSpacing - width
                    y: {
                        var pm = pinned.hoverDay && isFinite(pinned.hoverDay.precipMm) ? pinned.hoverDay.precipMm : 0;
                        var barTop = area.precipBottom - pm / root.precipMax * root.precipPlotH;
                        return Math.max(area.precipTop - root.badgeH / 2, Math.min(area.precipBottom - root.badgeH, barTop - root.badgeH / 2));
                    }
                    Label {
                        id: precipBadgeText
                        anchors.centerIn: parent
                        text: pinned.hoverDay ? root._fmtPrecip(pinned.hoverDay.precipMm) : ""
                        font: Kirigami.Theme.smallFont
                        color: root.precipColor
                    }
                }

                // ── hover tracking + Ctrl+wheel zoom ───────────────────
                HoverHandler {
                    id: hoverHandler
                    cursorShape: root.zoomed ? Qt.OpenHandCursor : (root.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor)
                    onPointChanged: {
                        if (!hovered || root.dayCount < 1 || panDrag.active) {
                            root.hoverIndex = -1;
                            return;
                        }
                        var xIn = point.position.x;
                        var yIn = point.position.y;
                        if (xIn < 0 || xIn > area.vw || yIn < area.gvY || yIn > area.precipBottom) {
                            root.hoverIndex = -1;
                            return;
                        }
                        root.hoverIndex = Math.max(0, Math.min(root.dayCount - 1, Math.round((xIn + scroller.contentX - area.pad) / area.step)));
                    }
                    onHoveredChanged: {
                        if (!hovered)
                            root.hoverIndex = -1;
                    }
                }
            }
        }

        // ── axis labels, in the left gutter (fixed) ───────────────────
        Repeater {
            model: root.dayCount > 1 ? root.tempScale.ticks : 0
            delegate: Label {
                required property int index
                readonly property real value: root.tempScale.hi - index * (root.tempScale.hi - root.tempScale.lo) / (root.tempScale.ticks - 1)
                text: root._fmtTemp(value)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.textColor
                opacity: 0.8
                x: area.plotX - width - Kirigami.Units.largeSpacing
                y: area.py + index / (root.tempScale.ticks - 1) * area.ph - height / 2
            }
        }
        Repeater {
            model: root.dayCount > 1 && root.showPrecip ? [
                { v: root.precipMax, y: area.precipTop },
                { v: 0, y: area.precipBottom }
            ] : []
            delegate: Label {
                id: pLabel
                required property var modelData
                text: root._fmtPrecip(modelData.v)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.textColor
                opacity: 0.8
                x: area.plotX - width - Kirigami.Units.largeSpacing
                y: Math.min(modelData.y - height / 2, area.precipBottom - height)
            }
        }

        // Rain total of what is in view, in the corner of the precipitation strip
        Rectangle {
            visible: root.dayCount > 1 && root.showPrecip && root.hoverIndex < 0 && !root.precipPercent
            x: area.width - width
            y: area.precipTop - height / 2
            width: totalText.implicitWidth + 8
            height: totalText.implicitHeight
            radius: 3
            color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.6)
            Label {
                id: totalText
                anchors.centerIn: parent
                text: i18nc("@label rain total shown in the chart", "Total: %1", root._fmtPrecip(root.visiblePrecipSum))
                font: Kirigami.Theme.smallFont
                color: root.precipColor
            }
        }

        // ── wheel / touchpad ──────────────────────────────────────────
        // A MouseArea above the plot, as ForecastView does for its hourly
        // strip: it takes only wheel events (no buttons), so hover and the
        // drag below still work, and nothing underneath (the charts,
        // the Flickable) gets to swallow the wheel first.
        MouseArea {
            id: wheelArea
            x: area.plotX
            y: 0
            width: area.vw
            height: area.plotBottom
            z: 20
            acceptedButtons: Qt.NoButton
            onWheel: function (wheel) {
                if (wheel.modifiers & Qt.ControlModifier) {
                    root.hoverIndex = -1;
                    root.zoomTo(root.zoom * (wheel.angleDelta.y > 0 ? 1.4 : 1 / 1.4),
                                Math.max(0, Math.min(1, wheel.x / area.vw)));
                    wheel.accepted = true;
                } else {
                    root.wheelPan(wheel);
                }
            }
        }

        // ── click: select an entry (Forecast tab); double click: zoom in around
        // the pointer. At the closest zoom a further double click restores the
        // full view.
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: function (eventPoint, button) {
                if (!root.selectable || tapCount !== 1 || root.dayCount < 1)
                    return;
                var x = eventPoint.position.x - area.plotX;
                var y = eventPoint.position.y;
                if (x < 0 || x > area.vw || y < 0 || y > area.plotBottom)
                    return;
                root.daySelected(Math.max(0, Math.min(root.dayCount - 1, Math.round((x + scroller.contentX - area.pad) / area.step))));
            }
            onDoubleTapped: function (eventPoint, button) {
                var x = eventPoint.position.x - area.plotX;
                var y = eventPoint.position.y;
                if (x < 0 || x > area.vw || y < 0 || y > area.plotBottom || root.dayCount < 2)
                    return;
                root.hoverIndex = -1;
                if (root.canZoomIn)
                    root.zoomTo(root.zoom * 2, x / area.vw);
                else
                    root.resetZoom();
            }
        }

        // ── drag to scroll while zoomed in ────────────────────────────
        // The Flickable is deliberately not interactive: a Flickable swallows
        // the plain mouse wheel, and the wheel should keep scrolling the day
        // list behind the chart. Dragging and the scroll bar move contentX.
        DragHandler {
            id: panDrag
            enabled: root.zoomed
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            property real _startX: 0
            onActiveChanged: {
                if (active) {
                    wheelAnim.stop();
                    _startX = scroller.contentX;
                    root.hoverIndex = -1;
                }
            }
            onTranslationChanged: {
                if (active)
                    scroller.contentX = Math.max(0, Math.min(scroller.contentWidth - scroller.width, _startX - translation.x));
            }
        }

        Connections {
            target: root
            function onDaysChanged() {
                root.hoverIndex = -1;
                root.resetZoom();
            }
        }
    }
}
