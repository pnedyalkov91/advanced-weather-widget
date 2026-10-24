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
 *   • Custom axis labels, grid and legend drawn with Kirigami units/fonts
 *     (Qt Graphs cannot size labels or put them on both sides itself)
 *   • A hover cursor in the highlight colour with a value badge per series
 *     that is pushed apart when badges would overlap
 *   • Daily precipitation bars in a strip below, sharing the same x scale
 *
 * Only loaded through a Loader (see HistoryView.qml): when the Qt Graphs QML
 * module is missing or too old to compile this file, the Loader reports an
 * error and the view falls back to HistoryChartCanvas.qml.
 *
 * Interface (shared with HistoryChartCanvas.qml):
 *   view  the HistoryView - provides _temp()/_precip()/_day()/_date()/_isNum()
 *   days  array of day objects from openMeteoHistory.js (the visible slice)
 *   canPan  true while zoomed in: dragging then emits panRequested()
 *   panRequested(days)            whole days to move the window (+ = later)
 *   zoomRequested(factor, anchor) Ctrl+wheel; factor < 1 zooms in, anchor is
 *                                 the pointer position across the plot (0..1)
 * The chart only reports gestures; HistoryView owns the zoom state.
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
    property bool canPan: false

    signal panRequested(int days)
    signal zoomRequested(real factor, real anchor)

    // Index of the day under the pointer, -1 when none.
    property int hoverIndex: -1

    readonly property int dayCount: days.length
    readonly property color highColor: "#ef5350"
    readonly property color lowColor: "#42a5f5"
    readonly property color meanColor: Kirigami.Theme.textColor
    readonly property color precipColor: "#26c6da"

    // ── Geometry ──────────────────────────────────────────────────────────
    readonly property real marginV: Kirigami.Units.largeSpacing
    readonly property real marginH: Kirigami.Units.largeSpacing
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

    // x positions of the date labels / vertical grid lines (indices into days)
    readonly property var dateIdx: {
        var n = days.length;
        var k = Math.min(5, n);
        var out = [];
        for (var i = 0; i < k; ++i) {
            var idx = k === 1 ? 0 : Math.round(i * (n - 1) / (k - 1));
            if (out.length === 0 || out[out.length - 1] !== idx)
                out.push(idx);
        }
        return out;
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

        // Widest axis label decides the left gutter (like the KDE applet's
        // ForecastGraphLabels, which sizes itself to its widest label).
        TextMetrics { id: tmLo; font: Kirigami.Theme.smallFont; text: root._fmtTemp(root.tempScale.lo) }
        TextMetrics { id: tmHi; font: Kirigami.Theme.smallFont; text: root._fmtTemp(root.tempScale.hi) }
        TextMetrics { id: tmP; font: Kirigami.Theme.smallFont; text: root._fmtPrecip(root.precipMax) }
        TextMetrics { id: tmDate; font: Kirigami.Theme.smallFont; text: "Wg" }

        readonly property real labelW: Math.ceil(Math.max(tmLo.width, tmHi.width, tmP.width)) + Kirigami.Units.smallSpacing
        readonly property real dateLabelH: Math.ceil(tmDate.height) + Kirigami.Units.smallSpacing

        // Qt Graphs view rectangle and its plot area (view minus margins)
        readonly property real gvX: labelW + Kirigami.Units.smallSpacing
        readonly property real gvW: width - gvX
        readonly property real gvY: dateLabelH
        readonly property real gvH: root.tempPlotH + 2 * root.marginV
        readonly property real px: gvX + root.marginH           // plot left
        readonly property real pw: Math.max(1, gvW - 2 * root.marginH)
        readonly property real py: gvY + root.marginV           // plot top
        readonly property real ph: root.tempPlotH

        readonly property real precipTop: gvY + gvH + Kirigami.Units.largeSpacing
        readonly property real precipBottom: precipTop + root.precipPlotH

        implicitHeight: precipBottom + Kirigami.Units.smallSpacing

        function xOf(i) { return px + (i + 0.5) / Math.max(1, root.dayCount) * pw; }
        function yOf(v) { return py + (root.tempScale.hi - v) / (root.tempScale.hi - root.tempScale.lo) * ph; }

        // ── grid ──────────────────────────────────────────────────────
        Repeater {
            model: root.dayCount > 1 ? root.tempScale.ticks : 0
            delegate: Rectangle {
                required property int index
                x: area.px
                width: area.pw
                height: 1
                y: area.py + index / (root.tempScale.ticks - 1) * area.ph - 0.5
                color: Kirigami.Theme.textColor
                opacity: 0.12
            }
        }
        Repeater {
            model: root.dayCount > 1 ? root.dateIdx : []
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

        // ── temperature axis labels ───────────────────────────────────
        Repeater {
            model: root.dayCount > 1 ? root.tempScale.ticks : 0
            delegate: Label {
                required property int index
                readonly property real value: root.tempScale.hi - index * (root.tempScale.hi - root.tempScale.lo) / (root.tempScale.ticks - 1)
                text: root._fmtTemp(value)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.textColor
                opacity: 0.75
                x: area.labelW - width - Kirigami.Units.smallSpacing / 2
                y: area.py + index / (root.tempScale.ticks - 1) * area.ph - height / 2
            }
        }

        // ── date labels (hidden while hovering - the cursor shows its own)
        Repeater {
            model: root.dayCount > 1 ? root.dateIdx : []
            delegate: Label {
                required property int modelData
                visible: root.hoverIndex < 0
                text: root.view ? root.view._date(root.days[modelData].dateStr) : ""
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.textColor
                opacity: 0.75
                x: Math.max(area.gvX, Math.min(area.width - width, area.xOf(modelData) - width / 2))
                y: 0
            }
        }

        // ── Qt Graphs: the three temperature splines ──────────────────
        Graphs.GraphsView {
            id: gv
            x: area.gvX
            y: area.gvY
            width: area.gvW
            height: area.gvH
            marginLeft: root.marginH
            marginRight: root.marginH
            marginTop: root.marginV
            marginBottom: root.marginV

            // The view does not clip the plot area; clip here so lines never
            // spill over neighbouring items.
            clip: true

            theme: Graphs.GraphsTheme {
                gridVisible: false
                backgroundVisible: false
                plotAreaBackgroundVisible: false
            }

            axisX: Graphs.ValueAxis {
                visible: false
                lineVisible: false
                min: -0.5
                max: Math.max(root.dayCount, 1) - 0.5
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
                area.rebuild();
            }
        }
        Component.onCompleted: rebuild()

        // ── precipitation bars ────────────────────────────────────────
        Rectangle {
            x: area.px
            y: area.precipBottom
            width: area.pw
            height: 1
            color: Kirigami.Theme.textColor
            opacity: 0.25
        }
        Repeater {
            model: root.dayCount > 1 ? root.days : []
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property real slot: area.pw / root.dayCount
                readonly property real bw: Math.max(1, Math.min(slot * 0.62, 14))
                readonly property bool has: isFinite(modelData.precipMm) && modelData.precipMm > 0
                visible: has
                x: area.px + index * slot + (slot - bw) / 2
                width: bw
                height: has ? Math.max(1, modelData.precipMm / root.precipMax * root.precipPlotH) : 0
                y: area.precipBottom - height
                radius: Math.min(2, bw / 2)
                color: root.precipColor
                opacity: root.hoverIndex < 0 || root.hoverIndex === index ? 0.9 : 0.55
            }
        }
        Label {
            text: root._fmtPrecip(root.precipMax)
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.textColor
            opacity: 0.75
            x: area.labelW - width - Kirigami.Units.smallSpacing / 2
            y: area.precipTop - height / 2
            visible: root.dayCount > 1
        }
        Label {
            text: root._fmtPrecip(0)
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.textColor
            opacity: 0.75
            x: area.labelW - width - Kirigami.Units.smallSpacing / 2
            y: area.precipBottom - height / 2
            visible: root.dayCount > 1
        }

        // ── hover cursor + value badges ───────────────────────────────
        readonly property bool hovering: root.hoverIndex >= 0 && root.hoverIndex < root.dayCount
        readonly property var hoverDay: hovering ? root.days[root.hoverIndex] : null
        readonly property real cursorX: hovering ? xOf(root.hoverIndex) : 0
        readonly property bool badgesRight: cursorX < area.width / 2

        Rectangle {
            visible: area.hovering
            x: area.cursorX - 1
            y: area.py - root.marginV / 2
            width: 2
            height: area.precipBottom - y
            color: Kirigami.Theme.highlightColor
        }

        Label {
            visible: area.hovering
            text: area.hoverDay && root.view ? root.view._day(area.hoverDay.dateStr, false) : ""
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.textColor
            x: Math.max(area.gvX, Math.min(area.width - width, area.cursorX - width / 2))
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
                    items.push({ i: i, y: yOf(vals[i]) - root.badgeH / 2 });
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
                var top = gvY, bottom = gvY + gvH;
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
                { color: root.highColor, text: area.hoverDay ? root._fmtTemp(area.hoverDay.maxC) : "", ok: !!area.hoverDay && isFinite(area.hoverDay.maxC) },
                { color: root.meanColor, text: area.hoverDay ? root._fmtTemp(area.hoverDay.meanC) : "", ok: !!area.hoverDay && isFinite(area.hoverDay.meanC) },
                { color: root.lowColor, text: area.hoverDay ? root._fmtTemp(area.hoverDay.minC) : "", ok: !!area.hoverDay && isFinite(area.hoverDay.minC) }
            ]
            delegate: Rectangle {
                id: badge
                required property var modelData
                required property int index
                visible: area.hovering && modelData.ok
                width: badgeText.implicitWidth + 8
                height: root.badgeH
                radius: 4
                color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(modelData.color, 0.18))
                border.width: 1
                border.color: Qt.alpha(modelData.color, 0.6)
                x: area.badgesRight ? area.cursorX + Kirigami.Units.largeSpacing
                                    : area.cursorX - Kirigami.Units.largeSpacing - width
                y: area.badgeYs[index]
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
            visible: area.hovering && !!area.hoverDay && isFinite(area.hoverDay.precipMm)
            width: precipBadgeText.implicitWidth + 8
            height: root.badgeH
            radius: 4
            color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(root.precipColor, 0.18))
            border.width: 1
            border.color: Qt.alpha(root.precipColor, 0.6)
            x: area.badgesRight ? area.cursorX + Kirigami.Units.largeSpacing
                                : area.cursorX - Kirigami.Units.largeSpacing - width
            y: {
                var pm = area.hoverDay && isFinite(area.hoverDay.precipMm) ? area.hoverDay.precipMm : 0;
                var barTop = area.precipBottom - pm / root.precipMax * root.precipPlotH;
                return Math.max(area.precipTop - root.badgeH / 2, Math.min(area.precipBottom - root.badgeH, barTop - root.badgeH / 2));
            }
            Label {
                id: precipBadgeText
                anchors.centerIn: parent
                text: area.hoverDay ? root._fmtPrecip(area.hoverDay.precipMm) : ""
                font: Kirigami.Theme.smallFont
                color: root.precipColor
            }
        }

        // ── hover tracking over the plot columns ──────────────────────
        HoverHandler {
            id: hoverHandler
            cursorShape: root.canPan ? Qt.OpenHandCursor : Qt.ArrowCursor
            onPointChanged: {
                if (!hovered || root.dayCount < 1) {
                    root.hoverIndex = -1;
                    return;
                }
                var xIn = point.position.x - area.px;
                var yIn = point.position.y;
                if (xIn < 0 || xIn > area.pw || yIn < area.gvY || yIn > area.precipBottom) {
                    root.hoverIndex = -1;
                    return;
                }
                root.hoverIndex = Math.max(0, Math.min(root.dayCount - 1, Math.floor(xIn / area.pw * root.dayCount)));
            }
            onHoveredChanged: {
                if (!hovered)
                    root.hoverIndex = -1;
            }
        }

        // ── zoom / pan gestures ───────────────────────────────────────
        // Drag sideways while zoomed in to move the window; Ctrl+wheel zooms
        // around the pointer. Plain wheel still scrolls the day list.
        DragHandler {
            id: panDrag
            enabled: root.canPan
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            property real _last: 0
            property real _acc: 0
            onActiveChanged: {
                _last = 0;
                _acc = 0;
            }
            onTranslationChanged: {
                if (!active)
                    return;
                _acc += translation.x - _last;
                _last = translation.x;
                var slot = area.pw / Math.max(1, root.dayCount);
                var steps = Math.trunc(_acc / slot);
                if (steps !== 0) {
                    _acc -= steps * slot;
                    root.panRequested(-steps);
                }
            }
        }
        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: function (event) {
                var a = Math.max(0, Math.min(1, (point.position.x - area.px) / area.pw));
                root.zoomRequested(event.angleDelta.y > 0 ? 0.7 : 1 / 0.7, a);
            }
        }
    }
}
