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
 *   view  the HistoryView - provides _temp()/_precip()/_day()/_date()
 *   days  array of day objects from openMeteoHistory.js
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var view: null
    property var days: []
    property int hoverIndex: -1

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

    Canvas {
        id: chart
        Layout.fillWidth: true
        Layout.preferredHeight: 150
        renderTarget: Canvas.Image

        readonly property real tempFrac: 0.68
        readonly property var _days: root.days
        readonly property int _hover: root.hoverIndex
        readonly property color _textColor: Kirigami.Theme.textColor

        on_DaysChanged: requestPaint()
        on_HoverChanged: requestPaint()
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

            var slot = cw / n;
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
                ctx.fillRect(chart._hover * slot, 0, slot, ch);
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
            for (var j = 0; j < n; ++j) {
                var dj = days[j];
                if (!isFinite(dj.maxC) || !isFinite(dj.minC))
                    continue;
                var y1 = ty(dj.maxC), y2 = ty(dj.minC);
                ctx.globalAlpha = 0.85;
                ctx.fillRect(j * slot + (slot - bw) / 2, y1, bw, Math.max(2, y2 - y1));
            }
            ctx.globalAlpha = 1.0;

            ctx.strokeStyle = chart._tc(0.9);
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            var pen = false;
            for (var k = 0; k < n; ++k) {
                var m = days[k].meanC;
                if (!isFinite(m)) { pen = false; continue; }
                var px = k * slot + slot / 2, py = ty(m);
                if (pen) ctx.lineTo(px, py); else ctx.moveTo(px, py);
                pen = true;
            }
            ctx.stroke();

            var pmax = 5;
            for (var q = 0; q < n; ++q)
                if (isFinite(days[q].precipMm))
                    pmax = Math.max(pmax, days[q].precipMm);
            ctx.fillStyle = "#26c6da";
            for (var r = 0; r < n; ++r) {
                var pm = days[r].precipMm;
                if (!isFinite(pm) || pm <= 0)
                    continue;
                var h = Math.max(1, pm / pmax * precipH);
                ctx.globalAlpha = 0.8;
                ctx.fillRect(r * slot + (slot - bw) / 2, precipTop + precipH - h, bw, h);
            }
            ctx.globalAlpha = 1.0;

            ctx.strokeStyle = chart._tc(0.25);
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(0, precipTop + precipH + 0.5);
            ctx.lineTo(cw, precipTop + precipH + 0.5);
            ctx.stroke();
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: function (mouse) {
                var n = root.days.length;
                if (n < 1)
                    return;
                root.hoverIndex = Math.max(0, Math.min(n - 1, Math.floor(mouse.x / width * n)));
            }
            onExited: root.hoverIndex = -1
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Label {
            text: root.days.length > 0 && root.view ? root.view._date(root.days[0].dateStr) : ""
            color: Kirigami.Theme.textColor
            opacity: 0.6
            font: Kirigami.Theme.smallFont
        }
        Item { Layout.fillWidth: true }
        Label {
            text: root.days.length > 0 && root.view ? root.view._date(root.days[root.days.length - 1].dateStr) : ""
            color: Kirigami.Theme.textColor
            opacity: 0.6
            font: Kirigami.Theme.smallFont
        }
    }
}
