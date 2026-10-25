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
 * HistoryChartGraphs.qml - History tab chart built on Qt Graphs, in the style
 * of the KDE Plasma Weather applet's forecast graph (kdeplasma-addons,
 * applets/weather/qml/DayForecastGraph.qml and graph/*):
 *
 *   • GraphsView + SplineSeries for the temperature lines, styled with
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
 * Only loaded through a Loader (see HistoryView.qml): when the Qt Graphs QML
 * module is missing or too old to compile this file, the Loader reports an
 * error and the view falls back to HistoryChartCanvas.qml.
 *
 * Interface (shared with HistoryChartCanvas.qml):
 *   view          the HistoryView - provides _temp()/_precip()/_day()/_date()
 *   days          array of day objects from openMeteoHistory.js
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

ColumnLayout {
    id: root

    property var view: null
    property var days: []
    /** The Flickable (day list) the chart sits in; the wheel falls through to it. */
    property var outerFlickable: null

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
    readonly property int minZoomDays: 3                 // most zoomed-in view
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
                f.contentY = Math.max(f.originY, Math.min(f.originY + f.contentHeight - f.height, f.contentY - wy));
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

    // ── Geometry ──────────────────────────────────────────────────────────
    readonly property real marginV: Kirigami.Units.largeSpacing
    readonly property real tempPlotH: Kirigami.Units.gridUnit * 6
    readonly property real precipPlotH: Kirigami.Units.gridUnit * 2.5
    readonly property real badgeH: Kirigami.Units.gridUnit + 4

    spacing: Kirigami.Units.smallSpacing

    // ── Temperature scale: "nice" bounds so grid lines carry round labels ─
    readonly property var tempScale: _computeScale(days)

    function _niceStep(rough) {
        var p = Math.pow(10, Math.floor(Math.log(rough) / Math.LN10));
        var f = rough / p;
        var nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
        return nf * p;
    }

    function _computeScale(ds) {
        var lo = Infinity, hi = -Infinity;
        for (var i = 0; i < ds.length; ++i) {
            var a = ds[i].maxC, b = ds[i].minC;
            if (isFinite(a)) { hi = Math.max(hi, a); lo = Math.min(lo, a); }
            if (isFinite(b)) { hi = Math.max(hi, b); lo = Math.min(lo, b); }
        }
        if (!isFinite(lo) || !isFinite(hi))
            return { lo: 0, hi: 10, ticks: 3 };
        var step = _niceStep(Math.max(hi - lo, 4) / 3);
        var nlo = Math.floor(lo / step) * step;
        var nhi = Math.ceil(hi / step) * step;
        if (nhi - nlo < step * 2)
            nhi = nlo + step * 2;
        return { lo: nlo, hi: nhi, ticks: Math.round((nhi - nlo) / step) + 1 };
    }

    readonly property real precipMax: {
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

    function _fmtTemp(v) { return view ? view._temp(v) : String(v); }
    function _fmtPrecip(v) { return view ? view._precip(v) : String(v); }

    // ── Legend ────────────────────────────────────────────────────────────
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: [
                { label: i18nc("@label chart legend", "High"), color: root.highColor },
                { label: i18nc("@label chart legend", "Mean"), color: root.meanColor },
                { label: i18nc("@label chart legend", "Low"), color: root.lowColor },
                { label: i18nc("@label chart legend", "Precipitation"), color: root.precipColor }
            ]
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

        TextMetrics { id: tmDate; font: Kirigami.Theme.smallFont; text: root.view && root.dayCount > 0 ? root.view._date(root.days[0].dateStr) : "00.00.0000" }
        TextMetrics { id: tmH; font: Kirigami.Theme.smallFont; text: "Wg" }
        TextMetrics { id: tmLo; font: Kirigami.Theme.smallFont; text: root._fmtTemp(root.tempScale.lo) }
        TextMetrics { id: tmHi; font: Kirigami.Theme.smallFont; text: root._fmtTemp(root.tempScale.hi) }
        TextMetrics { id: tmP; font: Kirigami.Theme.smallFont; text: root._fmtPrecip(root.precipMax) }

        // Left gutter for the axis labels (widest label + a little air), so
        // the plot starts clear of them. The plot ("viewport") is `vw` wide.
        readonly property real plotX: Math.ceil(Math.max(tmLo.width, tmHi.width, tmP.width)) + Kirigami.Units.largeSpacing * 2
        readonly property real vw: Math.max(1, width - plotX)

        readonly property real dateLabelH: Math.ceil(tmH.height) + Kirigami.Units.smallSpacing

        // Vertical layout (the Qt Graphs view is the temperature band)
        readonly property real gvY: dateLabelH
        readonly property real gvH: root.tempPlotH + 2 * root.marginV
        readonly property real py: gvY + root.marginV           // plot top
        readonly property real ph: root.tempPlotH
        readonly property real precipTop: gvY + gvH + Kirigami.Units.largeSpacing
        readonly property real precipBottom: precipTop + root.precipPlotH
        readonly property real plotBottom: precipBottom + Kirigami.Units.smallSpacing

        // Room for the scroll bar. Always reserved: the view sits in a ListView
        // header, and a header that changes height makes the list jump.
        readonly property real sbH: hbar.implicitHeight
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
        function xOf(i) { return pad + i * step - scroller.contentX; }
        function yOf(v) { return py + (root.tempScale.hi - v) / (root.tempScale.hi - root.tempScale.lo) * ph; }

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
                var left = Math.max(0, Math.min(vw - w, c - w / 2));
                if (left < prevRight + gap) {
                    // collides with the previous label: the last day wins
                    if (idx === n - 1 && out.length > 0 && out[out.length - 1] !== 0) {
                        out.pop();
                        prevRight = out.length > 0 ? Math.max(0, Math.min(vw - w, xOf(out[out.length - 1]) - w / 2)) + w : -1e9;
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
            visible: root.dayCount > 1
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
                visible: root.zoomed
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
                        width: 1
                        x: area.xOf(modelData) - 0.5
                        y: area.py
                        height: area.ph
                        color: Kirigami.Theme.textColor
                        opacity: 0.12
                    }
                }
                Repeater {
                    model: area.labelIdx
                    delegate: Label {
                        required property int modelData
                        visible: root.hoverIndex < 0 && modelData < root.dayCount
                        text: root.view && modelData < root.dayCount ? root.view._date(root.days[modelData].dateStr) : ""
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.textColor
                        opacity: 0.75
                        x: Math.max(0, Math.min(area.vw - width, area.xOf(modelData) - width / 2))
                        y: 0
                    }
                }

                // ── Qt Graphs: the three temperature splines ───────────
                // Always viewport-sized; scrolling just moves the x range.
                Graphs.GraphsView {
                    id: gv
                    x: 0
                    y: area.gvY
                    width: area.vw
                    height: area.gvH
                    marginLeft: 0
                    marginRight: 0
                    marginTop: root.marginV
                    marginBottom: root.marginV

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
                        min: root.tempScale.lo
                        max: root.tempScale.hi
                    }

                    Graphs.SplineSeries { id: highSeries; color: root.highColor; width: 3 }
                    Graphs.SplineSeries { id: meanSeries; color: root.meanColor; width: 2 }
                    Graphs.SplineSeries { id: lowSeries; color: root.lowColor; width: 3 }
                }

                // ── precipitation bars ─────────────────────────────────
                Repeater {
                    model: root.dayCount > 1 ? root.days : []
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
                    model: pinned.showDots ? [
                        { key: "maxC", color: root.highColor },
                        { key: "meanC", color: root.meanColor },
                        { key: "minC", color: root.lowColor }
                    ] : []
                    delegate: Repeater {
                        id: dotSeries
                        required property var modelData
                        model: root.days
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property real v: modelData[dotSeries.modelData.key]
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
                    model: [
                        { key: "maxC", color: root.highColor },
                        { key: "meanC", color: root.meanColor },
                        { key: "minC", color: root.lowColor }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property real v: pinned.hoverDay ? pinned.hoverDay[modelData.key] : NaN
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
                    text: pinned.hoverDay && root.view ? root.view._day(pinned.hoverDay.dateStr, false) : ""
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.textColor
                    x: Math.max(0, Math.min(area.vw - width, pinned.cursorX - width / 2))
                    y: 0
                }

                // De-overlap the temperature badges (same idea as the KDE applet's
                // ForecastGraphLine.positionLabelsY): sort, push apart, keep centred.
                readonly property var badgeYs: {
                    if (!hovering)
                        return [0, 0, 0];
                    var d = hoverDay;
                    var vals = [d.maxC, d.meanC, d.minC];
                    var items = [];
                    for (var i = 0; i < 3; ++i)
                        if (isFinite(vals[i]))
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
                    var out = [0, 0, 0];
                    for (var j = 0; j < items.length; ++j)
                        out[items[j].i] = items[j].y;
                    return out;
                }

                Repeater {
                    model: [
                        { color: root.highColor, text: pinned.hoverDay ? root._fmtTemp(pinned.hoverDay.maxC) : "", ok: !!pinned.hoverDay && isFinite(pinned.hoverDay.maxC) },
                        { color: root.meanColor, text: pinned.hoverDay ? root._fmtTemp(pinned.hoverDay.meanC) : "", ok: !!pinned.hoverDay && isFinite(pinned.hoverDay.meanC) },
                        { color: root.lowColor, text: pinned.hoverDay ? root._fmtTemp(pinned.hoverDay.minC) : "", ok: !!pinned.hoverDay && isFinite(pinned.hoverDay.minC) }
                    ]
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
                    visible: pinned.hovering && !!pinned.hoverDay && isFinite(pinned.hoverDay.precipMm)
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
                    cursorShape: root.zoomed ? Qt.OpenHandCursor : Qt.ArrowCursor
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
            model: root.dayCount > 1 ? [
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
            visible: root.dayCount > 1 && root.hoverIndex < 0
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
                    root.zoomTo(root.zoom * (wheel.angleDelta.y > 0 ? 1.4 : 1 / 1.4),
                                Math.max(0, Math.min(1, wheel.x / area.vw)));
                    wheel.accepted = true;
                } else {
                    root.wheelPan(wheel);
                }
            }
        }

        // ── double click: zoom in around the pointer ──────────────────
        // At the closest zoom a further double click restores the full view.
        TapHandler {
            acceptedButtons: Qt.LeftButton
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
            var all = [
                { s: highSeries, key: "maxC" },
                { s: meanSeries, key: "meanC" },
                { s: lowSeries, key: "minC" }
            ];
            for (var a = 0; a < all.length; ++a) {
                all[a].s.clear();
                for (var i = 0; i < root.days.length; ++i) {
                    var v = root.days[i][all[a].key];
                    // Days without data are skipped, so the line bridges the gap.
                    if (typeof v === "number" && isFinite(v))
                        all[a].s.append(i, v);
                }
            }
        }
        Connections {
            target: root
            function onDaysChanged() {
                root.hoverIndex = -1;
                root.resetZoom();
                area.rebuild();
            }
        }
        Component.onCompleted: rebuild()
    }
}
