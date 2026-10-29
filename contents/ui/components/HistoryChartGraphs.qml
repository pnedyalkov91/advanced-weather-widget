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
 * HistoryChartGraphs.qml - History tab chart built on Qt Graphs, in the style
 * of the KDE Plasma Weather applet's forecast graph (kdeplasma-addons,
 * applets/weather/qml/DayForecastGraph.qml and graph/*):
 *
 *   • GraphsView + LineSeries (smoothed by js/chartMath.js) for the temperature lines, styled with
 *     Kirigami.Theme (no background / grid from the Qt Graphs theme)
 *   • Custom grid, axis labels and legend drawn with Kirigami units/fonts
 *     (Qt Graphs cannot size labels or put them on both sides itself). The
 *     axis labels sit inside the plot, so the graph uses the full width.
 *   • A hover cursor in the highlight colour with a value badge per series
 *     that is pushed apart when badges would overlap
 *   • Daily precipitation bars in a strip below, sharing the same x scale,
 *     with the period's rain total in its corner
 *
 * The first day sits at the left edge of the plot and the last day at the right
 * edge (a few pixels of padding keep the end points and bars from being cut).
 *
 * Zoom: the chart owns it. zoom = 1 fits the whole period into the width; at
 * zoom = 4 the plot is four times as wide and scrolls sideways (drag, mouse
 * wheel, touchpad swipe or the scroll bar below the chart). The axis labels
 * sit in a gutter on the left and stay put. Implementation: a transparent
 * horizontal Flickable provides the scrolling and its content is one "pinned" item that follows contentX, so
 * only the visible part is ever drawn - the Qt Graphs view is never wider
 * than the popup, however many days are zoomed into.
 *
 * Only loaded through a Loader (see HistoryView.qml and ForecastView.qml):
 * when the Qt Graphs QML module is missing or too old to compile this file,
 * the Loader reports an error and the view falls back to HistoryChartKQC.qml.
 *
 * The same chart is used by the History tab (daily history, three temperature
 * lines) and by the Forecast tab (daily forecast: high / low; hourly forecast:
 * one temperature line). The Forecast tab switches the extra features below
 * on; the defaults give the History chart.
 *
 * Interface (shared with HistoryChartKQC.qml):
 *   view          provides _temp(c) / _precip(v) / _day(key, long, entry) / _date(key, entry)
 *   days          array of entries: { dateStr, <series keys>, precipMm, ... }
 *   seriesDefs    the lines: [{ key, color, label }] (up to 3); default High / Mean / Low
 *   precipLegend  legend text of the bars; precipPercent: bars are 0-100 %
 *   showIcons / iconAt(i) / iconSize   an icon above every entry (iconAt returns an iconInfo)
 *   markers       [{ pos, label, iconInfo }] vertical marks (sunrise / sunset), pos = entry index
 *   shadeBefore   entry index before which the plot is greyed out (-1: none)
 *   selectable / selectedIndex / daySelected(index)   click an entry to select it
 *   labelSampleText   widest x label, to space the labels (default: the first one)
 *   showPrecip        false: no precipitation strip (a graph of a single metric)
 *   style             "line" (default) or "bars" (the first series drawn as bars)
 *   valueFormat(v) / badgeFormat(i, key, v, entry) / barColorAt(i, entry)   labels and bar colours
 *   scaleMin / scaleMax / scaleStep / scaleMinSpan   force the ends / step of the value axis
 *   tempPlotH / minPlotX / showScrollBar   plot height, least left gutter, scroll bar
 *   setView(zoom, scrollFrac) / scrollFrac   let stacked charts zoom and scroll together
 *   zoomed / canZoomIn      state for the toolbar buttons
 *   visibleFirst / visibleLast  indices of the days currently in view
 *   zoomIn() / zoomOut() / resetZoom() / zoomTo(zoom, anchor)
 *   Double click (or Ctrl + wheel) zooms around the pointer. While zoomed in, the wheel and
 *   sideways touchpad swipes scroll the chart; at either end (and for
 *   vertical touchpad swipes) they fall through to the day list.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtGraphs as Graphs
import org.kde.kirigami as Kirigami
import "../js/chartMath.js" as ChartMath

ColumnLayout {
    id: root

    property var view: null
    property var days: []
    /** The Flickable (day list) the chart sits in; the wheel falls through to it. */
    property var outerFlickable: null
    /** function(wheelEvent) -> bool: scrolls the page behind the chart (preferred over
     *  outerFlickable, which is not always reachable) */
    property var outerScroll: null
    /** Labels are thinned as if they were at least this wide (the graphs of a stack share the
     *  icon width of the top graph, so that all of them show the same dates) */
    property real labelMinWidth: 0

    // ── Options (the Forecast tab uses them; the defaults are the History chart) ──
    property var seriesDefs: [
        {
            key: "maxC",
            color: highColor,
            label: i18nc("@label chart legend", "High")
        },
        {
            key: "meanC",
            color: meanColor,
            label: i18nc("@label chart legend", "Mean")
        },
        {
            key: "minC",
            color: lowColor,
            label: i18nc("@label chart legend", "Low")
        }
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
    /** function(index, key, v, entry) -> text of a hover badge (default: valueFormat) */
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
    readonly property int visibleFirst: dayCount > 0 ? Math.max(0, Math.min(dayCount - 1, Math.round((scroller.contentX - area.pad) / area.step))) : 0
    readonly property int visibleLast: dayCount > 0 ? Math.max(visibleFirst, Math.min(dayCount - 1, Math.round((scroller.contentX + area.vw - area.pad) / area.step))) : 0

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
            if (outerScroll) {
                outerScroll(event);
                return;
            }
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

    function zoomIn() {
        zoomTo(zoom * 2, 0.5);
    }
    function zoomOut() {
        zoomTo(zoom / 2, 0.5);
    }
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
                if (typeof a === "number" && isFinite(a)) {
                    hi = Math.max(hi, a);
                    lo = Math.min(lo, a);
                }
            }
        }
        var forcedLo = isFinite(fixLo), forcedHi = isFinite(fixHi);
        if (!isFinite(lo) || !isFinite(hi)) {
            lo = forcedLo ? fixLo : 0;
            hi = forcedHi ? fixHi : lo + 10;
            if (!isFinite(fixStep))
                return {
                    lo: lo,
                    hi: hi,
                    ticks: 3
                };
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
        return {
            lo: nlo,
            hi: nhi,
            ticks: Math.max(2, Math.round((nhi - nlo) / step) + 1)
        };
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

    function _lineWidth(i) {
        return i < seriesDefs.length && seriesDefs[i].key === "meanC" ? 2 : 3;
    }
    function _fmtTemp(v) {
        return valueFormat ? valueFormat(v) : (view ? view._temp(v) : String(v));
    }
    function _badgeText(i, key, v) {
        return badgeFormat ? badgeFormat(i, key, v, (i >= 0 && i < days.length) ? days[i] : null) : _fmtTemp(v);
    }
    function _fmtPrecip(v) {
        return view ? view._precip(v) : String(v);
    }
    function _dateText(i) {
        return view && i >= 0 && i < days.length ? view._date(days[i].dateStr, days[i]) : "";
    }
    function _titleText(i) {
        return view && i >= 0 && i < days.length ? view._day(days[i].dateStr, false, days[i]) : "";
    }

    // ── Legend ────────────────────────────────────────────────────────────
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: root.showPrecip ? root.seriesDefs.concat([
                {
                    label: root.precipLegend,
                    color: root.precipColor
                }
            ]) : root.seriesDefs
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
        clip: true      // the plot may be a moment wider than the item while it is resized

        TextMetrics {
            id: tmDate
            font: Kirigami.Theme.smallFont
            text: root.labelSampleText !== "" ? root.labelSampleText : (root.view && root.dayCount > 0 ? root._dateText(0) : "00.00.0000")
        }
        TextMetrics {
            id: tmH
            font: Kirigami.Theme.smallFont
            text: "Wg"
        }
        TextMetrics {
            id: tmLo
            font: Kirigami.Theme.smallFont
            text: root._fmtTemp(root.tempScale.lo)
        }
        TextMetrics {
            id: tmHi
            font: Kirigami.Theme.smallFont
            text: root._fmtTemp(root.tempScale.hi)
        }
        TextMetrics {
            id: tmP
            font: Kirigami.Theme.smallFont
            text: root._fmtPrecip(root.precipMax)
        }

        // Left gutter for the axis labels (widest label + a little air), so
        // the plot starts clear of them. The plot ("viewport") is `vw` wide.
        readonly property real naturalX: Math.ceil(Math.max(tmLo.width, tmHi.width, root.showPrecip ? tmP.width : 0)) + Kirigami.Units.largeSpacing * 2
        readonly property real plotX: Math.max(root.minPlotX, naturalX)
        // The plot follows the item's width only once it has stopped changing for a moment:
        // resizing the widget makes the width change on every frame, and re-laying out (and
        // re-rendering) the plots of up to a dozen graphs each time made Plasma lag.
        property real settledW: 0
        onWidthChanged: {
            if (settledW <= 0 || !visible)
                settledW = width;
            else
                settleTimer.restart();
        }
        Timer {
            id: settleTimer
            interval: 90
            onTriggered: area.settledW = area.width
        }
        readonly property real vw: Math.max(1, (settledW > 0 ? settledW : width) - plotX)

        readonly property real dateLabelH: Math.ceil(tmH.height) + Kirigami.Units.smallSpacing

        // Vertical layout (the Qt Graphs view is the temperature band)
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

        /** x of day i's point, in chart (viewport) coordinates */
        function xOf(i) {
            return pad + i * step - scroller.contentX;
        }
        function yOf(v) {
            return py + (root.tempScale.hi - v) / (root.tempScale.hi - root.tempScale.lo) * ph;
        }

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

        // Date labels / vertical grid lines (and the icons above them, which sit over their
        // labels). The first and the last entry always have one; the others are spread over the
        // width, as many as fit, whatever the width of the widget. A "cell" is what is drawn
        // for an entry - its label or its icon, whichever is wider - kept inside the view.
        function cellLeft(idx, cw) {
            return Math.max(0, Math.min(vw - cw, labelLeft(idx) + tmDate.width / 2 - cw / 2));
        }
        /** do the cells of `list` (ascending) keep `gap` apart? */
        function cellsFit(list, cw, gap) {
            for (var k = 1; k < list.length; ++k)
                if (cellLeft(list[k], cw) < cellLeft(list[k - 1], cw) + cw + gap)
                    return false;
            return true;
        }
        /** `k` entries of `n` spread evenly, the first and the last among them */
        function spread(k, n) {
            var out = [];
            for (var i = 0; i < k; ++i)
                out.push(Math.round(i * (n - 1) / (k - 1)));
            return out;
        }

        readonly property var _labelIdxRaw: {
            var n = root.dayCount;
            if (n < 2)
                return [];
            var w = tmDate.width;
            var gap = Kirigami.Units.largeSpacing * 2;
            // with icons, an icon sits over every label: a cell is as wide as the wider of the two
            var cw = Math.max(w, root.labelMinWidth, root.showIcons ? root.iconSize : 0);

            if (!root.zoomed) {
                // the whole period is in view: the most entries that fit, evenly spread
                for (var k = Math.min(n, Math.floor(vw / (cw + gap)) + 1); k >= 2; --k) {
                    var even = spread(k, n);
                    if (cellsFit(even, cw, gap))
                        return even;
                }
                return [0];
            }

            // zoomed in: whole multiples of a stride, so that scrolling does not move them
            var every = Math.max(1, Math.ceil((cw + gap) / step));
            var first = Math.max(0, Math.floor((scroller.contentX - pad) / step) - 1);
            var last = Math.min(n - 1, Math.ceil((scroller.contentX + vw - pad) / step) + 1);
            var cand = [];
            for (var i = Math.ceil(first / every) * every; i <= last; i += every)
                cand.push(i);
            if (cand.length === 0 || cand[cand.length - 1] !== n - 1)
                cand.push(n - 1);
            var out = [];
            for (var q = 0; q < cand.length; ++q) {
                var idx = cand[q];
                var c = xOf(idx);
                if (c < 0 || c > vw)
                    continue;               // point not in view
                var isEnd = idx === 0 || idx === n - 1;
                if (!isEnd && (c - cw / 2 < 0 || c + cw / 2 > vw))
                    continue;               // would be cut or pushed
                var cl = cellLeft(idx, cw);
                if (out.length > 0 && cl < cellLeft(out[out.length - 1], cw) + cw + gap) {
                    if (idx !== n - 1)
                        continue;
                    // the last entry always stays: it pushes out the ones before it (not the first)
                    while (out.length > 0 && out[out.length - 1] !== 0 && cl < cellLeft(out[out.length - 1], cw) + cw + gap)
                        out.pop();
                    if (out.length > 0 && cl < cellLeft(out[out.length - 1], cw) + cw + gap)
                        continue;
                }
                out.push(idx);
            }
            return out;
        }

        // The label indices only change when the set of labels does: a new array each time
        // the view scrolls or the width changes would rebuild every label and icon.
        property var labelIdx: []
        property string _labelSig: ""
        on_LabelIdxRawChanged: {
            var sig = _labelIdxRaw.join(",");
            if (sig !== _labelSig) {
                _labelSig = sig;
                labelIdx = _labelIdxRaw;
            }
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
                        x: Math.max(0, Math.min(area.vw - width, area.xOf(modelData) - (modelData === 0 ? 0 : (modelData === root.dayCount - 1 ? width : width / 2))))
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
                                    item.iconInfo = Qt.binding(function () {
                                        return mark.modelData.iconInfo;
                                    });
                                    item.iconSize = Kirigami.Units.gridUnit;
                                    item.iconColor = Qt.binding(function () {
                                        return Kirigami.Theme.textColor;
                                    });
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

                // ── Qt Graphs: the temperature splines ─────────────────
                // Always viewport-sized; scrolling just moves the x range.
                Graphs.GraphsView {
                    id: gv
                    x: 0
                    y: area.gvY
                    width: area.vw
                    height: area.gvH
                    marginLeft: 0
                    marginRight: 0
                    marginTop: 0
                    marginBottom: 0

                    // The view does not clip the plot area; clip here so lines
                    // never spill over neighbouring items.
                    clip: true

                    theme: Graphs.GraphsTheme {
                        gridVisible: false
                        backgroundVisible: false
                        plotAreaBackgroundVisible: false
                    }

                    axisX: Graphs.ValueAxis {
                        visible: false
                        lineVisible: false
                        min: (scroller.contentX - area.pad) / area.step
                        max: (scroller.contentX + area.vw - area.pad) / area.step
                    }
                    axisY: Graphs.ValueAxis {
                        visible: false
                        lineVisible: false
                        // The view is `marginV` taller than the plot at both ends: a line along the
                        // highest / lowest grid line is then drawn whole, not cut in half by the
                        // edge of the plot area.
                        readonly property real _pad: root.tempPlotH > 0 ? (root.tempScale.hi - root.tempScale.lo) * root.marginV / root.tempPlotH : 0
                        min: root.tempScale.lo - _pad
                        max: root.tempScale.hi + _pad
                    }

                    // Three slots; the ones beyond root.seriesDefs stay empty and hidden. The points are
                    // the smoothed curve (area.rebuild), so these are plain lines.
                    Graphs.LineSeries {
                        id: series0
                        visible: root.style === "line" && root.nSeries > 0
                        color: root.nSeries > 0 ? root.seriesDefs[0].color : "transparent"
                        width: root._lineWidth(0)
                    }
                    Graphs.LineSeries {
                        id: series1
                        visible: root.style === "line" && root.nSeries > 1
                        color: root.nSeries > 1 ? root.seriesDefs[1].color : "transparent"
                        width: root._lineWidth(1)
                    }
                    Graphs.LineSeries {
                        id: series2
                        visible: root.style === "line" && root.nSeries > 2
                        color: root.nSeries > 2 ? root.seriesDefs[2].color : "transparent"
                        width: root._lineWidth(2)
                    }
                }

                // ── precipitation bars ─────────────────────────────────
                Repeater {
                    model: root.dayCount > 1 && root.showPrecip ? root.days : []
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property real bw: Math.max(1, Math.min(area.step * 0.62, 14))
                        readonly property bool has: isFinite(modelData.precipMm) && modelData.precipMm > 0
                        readonly property real bx: area.xOf(index) - bw / 2
                        visible: has && bx + bw > 0 && bx < area.vw
                        x: bx
                        width: bw
                        height: has ? Math.max(1, modelData.precipMm / root.precipMax * root.precipPlotH) : 0
                        y: area.precipBottom - height
                        radius: Math.min(2, bw / 2)
                        color: root.precipColor
                        opacity: root.hoverIndex < 0 || root.hoverIndex === index ? 0.9 : 0.55
                    }
                }

                // ── dots on the lines ──────────────────────────────────
                // One dot per day and series, left out when the days are too
                // close together for them to read as dots.
                readonly property real dotSize: Kirigami.Units.gridUnit * 0.4
                readonly property bool showDots: area.step >= dotSize * 2.4
                Repeater {
                    model: pinned.showDots && root.style === "line" ? root.seriesDefs : []
                    delegate: Repeater {
                        id: dotSeries
                        required property var modelData
                        model: root.days
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property real v: typeof modelData[dotSeries.modelData.key] === "number" ? modelData[dotSeries.modelData.key] : NaN
                            readonly property real cx: area.xOf(index)
                            visible: isFinite(v) && cx > -width && cx < area.vw + width
                            width: pinned.dotSize
                            height: width
                            radius: width / 2
                            x: cx - width / 2
                            y: isFinite(v) ? area.yOf(v) - height / 2 : 0
                            color: dotSeries.modelData.color
                            border.width: 1
                            border.color: Kirigami.Theme.backgroundColor
                        }
                    }
                }

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
                        color: root.barColorAt ? root.barColorAt(index, (index >= 0 && index < root.days.length) ? root.days[index] : null) : root.seriesDefs[0].color
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
                    model: root.showIcons && root.dayCount > 0 ? area.labelIdx : []
                    delegate: Item {
                        id: iconSlot
                        required property int modelData
                        readonly property int index: modelData
                        readonly property var info: root.iconAt ? root.iconAt(modelData) : null
                        // centred over its date label (the labels are the ones that are thinned
                        // out to fit, so the icons stay on the same days)
                        visible: modelData < root.dayCount
                        x: Math.max(0, Math.min(area.vw - root.iconSize, area.labelLeft(modelData) + tmDate.width / 2 - root.iconSize / 2))
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
                                item.iconInfo = Qt.binding(function () {
                                    return iconSlot.info;
                                });
                                item.iconSize = Qt.binding(function () {
                                    return root.iconSize;
                                });
                                item.iconColor = Qt.binding(function () {
                                    return Kirigami.Theme.textColor;
                                });
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
                            items.push({
                                i: i,
                                y: area.yOf(vals[i]) - root.badgeH / 2
                            });
                    items.sort(function (a, b) {
                        return a.y - b.y;
                    });
                    var pref = items.map(function (it) {
                        return it.y;
                    });
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
                        return {
                            color: sd.color,
                            text: pinned.hoverDay ? root._badgeText(root.hoverIndex, sd.key, v) : "",
                            ok: typeof v === "number" && isFinite(v)
                        };
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
                        x: pinned.badgesRight ? pinned.cursorX + Kirigami.Units.largeSpacing : pinned.cursorX - Kirigami.Units.largeSpacing - width
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
                    x: pinned.badgesRight ? pinned.cursorX + Kirigami.Units.largeSpacing : pinned.cursorX - Kirigami.Units.largeSpacing - width
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
                {
                    v: root.precipMax,
                    y: area.precipTop
                },
                {
                    v: 0,
                    y: area.precipBottom
                }
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
        // drag below still work, and nothing underneath (the Qt Graphs view,
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
                    root.zoomTo(root.zoom * (wheel.angleDelta.y > 0 ? 1.4 : 1 / 1.4), Math.max(0, Math.min(1, wheel.x / area.vw)));
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

        function rebuild() {
            var slots = [series0, series1, series2];
            for (var a = 0; a < slots.length; ++a) {
                slots[a].clear();
                if (a >= root.seriesDefs.length)
                    continue;
                var key = root.seriesDefs[a].key;
                var xs = [], ys = [];
                for (var i = 0; i < root.days.length; ++i) {
                    var v = root.days[i][key];
                    // Days without data are skipped, so the line bridges the gap.
                    if (typeof v === "number" && isFinite(v)) {
                        xs.push(i);
                        ys.push(v);
                    }
                }
                var c = ChartMath.smooth(xs, ys, ChartMath.samplesPerSegment(xs.length));
                for (var k = 0; k < c.x.length; ++k)
                    slots[a].append(c.x[k], c.y[k]);
            }
        }
        // The data and the series definitions are set one after the other (the Forecast tab
        // sets its own definitions right after the data): build the lines once, afterwards,
        // rather than once for each - and never fill a line with the wrong data first.
        Timer {
            id: rebuildTimer
            interval: 0
            onTriggered: area.rebuild()
        }
        Connections {
            target: root
            function onDaysChanged() {
                root.hoverIndex = -1;
                root.resetZoom();
                rebuildTimer.restart();
            }
            function onSeriesDefsChanged() {
                rebuildTimer.restart();
            }
        }
        Component.onCompleted: {
            _labelSig = _labelIdxRaw.join(",");
            labelIdx = _labelIdxRaw;
            rebuildTimer.restart();
        }
    }
}
