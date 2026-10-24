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
 * HistoryChartCanvas.qml - fallback chart for the History tab.
 *
 * Plain Canvas drawing, used only when the Qt Graphs QML module is not
 * available (or too old) for HistoryChartGraphs.qml. Same interface:
 *   view          the HistoryView - provides _temp()/_precip()/_day()/_date()
 *   days          array of day objects from openMeteoHistory.js
 *   zoomed / canZoomIn / visibleFirst / visibleLast
 *   zoomIn() / zoomOut() / resetZoom() / zoomTo(zoom, anchor)
 * Zooming makes the plot wider than the chart and scrolls it sideways (drag,
 * mouse wheel, touchpad swipe, scroll bar), see
 * HistoryChartGraphs.qml (same transparent-Flickable + pinned-item scheme).
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var view: null
    property var days: []
    /** The Flickable (day list) the chart sits in; the wheel falls through to it. */
    property var outerFlickable: null
    property int hoverIndex: -1

    readonly property int dayCount: days.length

    // ── Zoom ──────────────────────────────────────────────────────────────
    property real zoom: 1
    readonly property int minZoomDays: 3
    readonly property real maxZoom: Math.max(1, dayCount / minZoomDays)
    readonly property bool zoomed: zoom > 1.001
    readonly property bool canZoomIn: zoom < maxZoom - 0.001
    readonly property real slot: stage.width * zoom / Math.max(1, dayCount)
    readonly property int visibleFirst: (dayCount > 0 && slot > 0)
        ? Math.max(0, Math.min(dayCount - 1, Math.floor(scroller.contentX / slot + 0.001))) : 0
    readonly property int visibleLast: (dayCount > 0 && slot > 0)
        ? Math.max(visibleFirst, Math.min(dayCount - 1, Math.ceil((scroller.contentX + stage.width) / slot - 0.001) - 1)) : 0

    function zoomTo(z, anchor) {
        var a = (typeof anchor === "number") ? Math.max(0, Math.min(1, anchor)) : 0.5;
        var nz = Math.max(1, Math.min(maxZoom, z));
        if (nz < 1.05)
            nz = 1;
        if (Math.abs(nz - zoom) < 0.001)
            return;
        var vw = stage.width;
        var focus = (scroller.contentX + a * vw) / (vw * zoom);
        zoom = nz;
        scroller.contentX = Math.max(0, Math.min(vw * nz - vw, focus * vw * nz - a * vw));
    }
    /** Mouse wheel / touchpad over the zoomed chart. A wheel notch, a sideways
     *  touchpad swipe or Shift+wheel scrolls the chart; a vertical touchpad
     *  swipe, or any wheel movement once the chart is at its end, scrolls the
     *  day list behind it instead (outerFlickable). */
    function wheelPan(event) {
        var tp = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0;
        var dx = tp ? event.pixelDelta.x : event.angleDelta.x;
        var dy = tp ? event.pixelDelta.y : event.angleDelta.y;
        var d = 0;
        if (Math.abs(dx) > Math.abs(dy))
            d = dx;
        else if (!tp || (event.modifiers & Qt.ShiftModifier))
            d = dy;
        var maxX = scroller.contentWidth - scroller.width;
        var nx = Math.max(0, Math.min(maxX, scroller.contentX - d));
        event.accepted = true;
        if (d === 0 || nx === scroller.contentX) {
            // Nothing to pan: a WheelHandler cannot pass the event on, so
            // scroll the page behind the chart by hand.
            var f = outerFlickable;
            if (f) {
                var wy = tp ? event.pixelDelta.y : event.angleDelta.y / 2;
                f.contentY = Math.max(f.originY, Math.min(f.originY + f.contentHeight - f.height, f.contentY - wy));
            }
            return;
        }
        root.hoverIndex = -1;
        scroller.contentX = nx;
    }

    function zoomIn() { zoomTo(zoom * 2, 0.5); }
    function zoomOut() { zoomTo(zoom / 2, 0.5); }
    function resetZoom() {
        zoom = 1;
        scroller.contentX = 0;
    }

    onDaysChanged: {
        hoverIndex = -1;
        resetZoom();
    }

    spacing: Kirigami.Units.smallSpacing

    // Legend / hover readout
    Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: Kirigami.Theme.textColor
        font: Kirigami.Theme.smallFont
        text: {
            var i = root.hoverIndex;
            if (!root.view || i < 0 || i >= root.days.length)
                return i18n("Temperature range and daily precipitation");
            var d = root.days[i];
            if (!d.hasData)
                return root.view._day(d.dateStr, false) + " · " + i18n("No data");
            return root.view._day(d.dateStr, false) + " · "
                + root.view._temp(d.maxC) + " / " + root.view._temp(d.minC)
                + " · " + root.view._precip(d.precipMm);
        }
    }

    Item {
        id: stage
        Layout.fillWidth: true
        readonly property real plotH: 150
        Layout.preferredHeight: plotH + hbar.implicitHeight   // reserved even when unzoomed: no header height jump

        Flickable {
            id: scroller
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: stage.plotH
            contentWidth: stage.width * root.zoom
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: false          // see "drag to scroll" below
            clip: true

            ScrollBar.horizontal: ScrollBar {
                id: hbar
                parent: stage
                anchors.left: scroller.left
                anchors.right: scroller.right
                anchors.top: scroller.bottom
                visible: root.zoomed
                policy: ScrollBar.AlwaysOn
            }

            Item {
                id: pinned
                x: scroller.contentX
                width: stage.width
                height: scroller.height

                Canvas {
                    id: chart
                    anchors.fill: parent
                    renderTarget: Canvas.Image

                    readonly property real tempFrac: 0.68
                    readonly property var _days: root.days
                    readonly property int _hover: root.hoverIndex
                    readonly property real _off: scroller.contentX
                    readonly property real _slot: root.slot
                    readonly property color _textColor: Kirigami.Theme.textColor

                    on_DaysChanged: requestPaint()
                    on_HoverChanged: requestPaint()
                    on_OffChanged: requestPaint()
                    on_SlotChanged: requestPaint()
                    on_TextColorChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    function _tc(a) {
                        var c = Kirigami.Theme.textColor;
                        return Qt.rgba(c.r, c.g, c.b, a);
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var days = chart._days;
                        var n = days.length;
                        var cw = width, ch = height;
                        if (n < 2 || cw <= 0 || ch <= 0)
                            return;

                        var slot = chart._slot;
                        var off = chart._off;
                        var i0 = Math.max(0, Math.floor(off / slot) - 1);
                        var i1 = Math.min(n - 1, Math.ceil((off + cw) / slot) + 1);
                        var tempH = Math.round(ch * tempFrac);
                        var precipTop = tempH + 10;
                        var precipH = ch - precipTop;

                        var lo = Infinity, hi = -Infinity;
                        for (var i = 0; i < n; ++i) {
                            var d = days[i];
                            if (isFinite(d.maxC)) { hi = Math.max(hi, d.maxC); lo = Math.min(lo, d.maxC); }
                            if (isFinite(d.minC)) { hi = Math.max(hi, d.minC); lo = Math.min(lo, d.minC); }
                        }
                        if (!isFinite(lo) || !isFinite(hi))
                            return;
                        if (hi - lo < 4) {
                            var mid = (hi + lo) / 2;
                            hi = mid + 2;
                            lo = mid - 2;
                        }
                        var padT = 6, padB = 6;
                        var span = hi - lo;
                        function ty(v) {
                            return padT + (hi - v) / span * (tempH - padT - padB);
                        }

                        if (chart._hover >= 0 && chart._hover < n) {
                            ctx.fillStyle = chart._tc(0.08);
                            ctx.fillRect(chart._hover * slot - off, 0, slot, ch);
                        }

                        if (lo < 0 && hi > 0) {
                            ctx.strokeStyle = chart._tc(0.35);
                            ctx.lineWidth = 1;
                            ctx.setLineDash([3, 3]);
                            ctx.beginPath();
                            ctx.moveTo(0, Math.round(ty(0)) + 0.5);
                            ctx.lineTo(cw, Math.round(ty(0)) + 0.5);
                            ctx.stroke();
                            ctx.setLineDash([]);
                        }

                        var grad = ctx.createLinearGradient(0, padT, 0, tempH - padB);
                        grad.addColorStop(0.0, "#ef5350");
                        grad.addColorStop(1.0, "#42a5f5");
                        ctx.fillStyle = grad;
                        var bw = Math.max(1, Math.min(slot * 0.62, 14));
                        for (var j = i0; j <= i1; ++j) {
                            var dj = days[j];
                            if (!isFinite(dj.maxC) || !isFinite(dj.minC))
                                continue;
                            var y1 = ty(dj.maxC), y2 = ty(dj.minC);
                            ctx.globalAlpha = 0.85;
                            ctx.fillRect(j * slot - off + (slot - bw) / 2, y1, bw, Math.max(2, y2 - y1));
                        }
                        ctx.globalAlpha = 1.0;

                        ctx.strokeStyle = chart._tc(0.9);
                        ctx.lineWidth = 1.5;
                        ctx.beginPath();
                        var pen = false;
                        for (var k = i0; k <= i1; ++k) {
                            var m = days[k].meanC;
                            if (!isFinite(m)) { pen = false; continue; }
                            var px = k * slot - off + slot / 2, py = ty(m);
                            if (pen) ctx.lineTo(px, py); else ctx.moveTo(px, py);
                            pen = true;
                        }
                        ctx.stroke();

                        var pmax = 5;
                        for (var q = 0; q < n; ++q)
                            if (isFinite(days[q].precipMm))
                                pmax = Math.max(pmax, days[q].precipMm);
                        ctx.fillStyle = "#26c6da";
                        for (var r = i0; r <= i1; ++r) {
                            var pm = days[r].precipMm;
                            if (!isFinite(pm) || pm <= 0)
                                continue;
                            var h = Math.max(1, pm / pmax * precipH);
                            ctx.globalAlpha = 0.8;
                            ctx.fillRect(r * slot - off + (slot - bw) / 2, precipTop + precipH - h, bw, h);
                        }
                        ctx.globalAlpha = 1.0;

                        ctx.strokeStyle = chart._tc(0.25);
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(0, precipTop + precipH + 0.5);
                        ctx.lineTo(cw, precipTop + precipH + 0.5);
                        ctx.stroke();
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.zoomed ? Qt.OpenHandCursor : Qt.ArrowCursor
                    acceptedButtons: Qt.NoButton
                    onPositionChanged: function (mouse) {
                        var n = root.dayCount;
                        if (n < 1 || panDrag.active)
                            return;
                        root.hoverIndex = Math.max(0, Math.min(n - 1, Math.floor((mouse.x + scroller.contentX) / root.slot)));
                    }
                    onExited: root.hoverIndex = -1
                }

                WheelHandler {
                    enabled: root.zoomed
                    acceptedModifiers: Qt.NoModifier
                    onWheel: function (event) { root.wheelPan(event); }
                }
                WheelHandler {
                    enabled: root.zoomed
                    acceptedModifiers: Qt.ShiftModifier
                    onWheel: function (event) { root.wheelPan(event); }
                }
                WheelHandler {
                    // sideways touchpad swipes / tilt wheels
                    enabled: root.zoomed
                    orientation: Qt.Horizontal
                    onWheel: function (event) { root.wheelPan(event); }
                }
                WheelHandler {
                    acceptedModifiers: Qt.ControlModifier
                    onWheel: function (event) {
                        root.hoverIndex = -1;
                        root.zoomTo(root.zoom * (event.angleDelta.y > 0 ? 1.4 : 1 / 1.4),
                                    Math.max(0, Math.min(1, point.position.x / stage.width)));
                    }
                }
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
                    _startX = scroller.contentX;
                    root.hoverIndex = -1;
                }
            }
            onTranslationChanged: {
                if (active)
                    scroller.contentX = Math.max(0, Math.min(scroller.contentWidth - scroller.width, _startX - translation.x));
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Label {
            text: root.dayCount > 0 && root.view ? root.view._date(root.days[root.visibleFirst].dateStr) : ""
            color: Kirigami.Theme.textColor
            opacity: 0.6
            font: Kirigami.Theme.smallFont
        }
        Item { Layout.fillWidth: true }
        Label {
            text: root.dayCount > 0 && root.view ? root.view._date(root.days[root.visibleLast].dateStr) : ""
            color: Kirigami.Theme.textColor
            opacity: 0.6
            font: Kirigami.Theme.smallFont
        }
    }
}
