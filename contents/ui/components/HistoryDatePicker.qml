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
 * HistoryDatePicker.qml - small month-grid calendar for the History tab.
 *
 * Qt Quick Controls has no date picker, so this is a self-contained one.
 * Everything is exchanged as ISO "YYYY-MM-DD" strings (see openMeteoHistory.js),
 * which sidesteps Date/timezone pitfalls entirely.
 *
 *   minDate / maxDate   inclusive selectable range
 *   selectedDate        the highlighted day ("" = none)
 *   rangeStart/rangeEnd optional range to shade (for custom ranges)
 *   signal picked(string iso)
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../providers/openMeteoHistory.js" as H

Item {
    id: picker

    property string minDate: H.EARLIEST_DATE
    property string maxDate: H.latestAvailable()
    property string selectedDate: ""
    property string rangeStart: ""
    property string rangeEnd: ""

    signal picked(string iso)

    // Month currently shown. Month is 0-based, like Date.
    property int viewYear: 2000
    property int viewMonth: 0

    readonly property int _minYear: parseInt(minDate.substring(0, 4), 10)
    readonly property int _maxYear: parseInt(maxDate.substring(0, 4), 10)
    readonly property int _firstDow: Qt.locale().firstDayOfWeek % 7   // Locale: Sunday = 0 … Saturday = 6

    implicitWidth: 280
    implicitHeight: layout.implicitHeight

    function _clampView() {
        // Never show a month that lies completely outside [minDate, maxDate].
        var lo = parseInt(minDate.substring(0, 4), 10) * 12 + parseInt(minDate.substring(5, 7), 10) - 1;
        var hi = parseInt(maxDate.substring(0, 4), 10) * 12 + parseInt(maxDate.substring(5, 7), 10) - 1;
        var cur = viewYear * 12 + viewMonth;
        if (cur < lo) cur = lo;
        if (cur > hi) cur = hi;
        viewYear = Math.floor(cur / 12);
        viewMonth = cur % 12;
    }

    /** Jump the visible month to the one holding `iso` (or the selection / max). */
    function showMonthOf(iso) {
        var s = H.isIso(iso) ? iso : (H.isIso(selectedDate) ? selectedDate : maxDate);
        viewYear = parseInt(s.substring(0, 4), 10);
        viewMonth = parseInt(s.substring(5, 7), 10) - 1;
        _clampView();
    }

    function stepMonth(delta) {
        var cur = viewYear * 12 + viewMonth + delta;
        viewYear = Math.floor(cur / 12);
        viewMonth = cur % 12;
        _clampView();
    }

    readonly property bool _canGoPrev: (viewYear * 12 + viewMonth) > (parseInt(minDate.substring(0, 4), 10) * 12 + parseInt(minDate.substring(5, 7), 10) - 1)
    readonly property bool _canGoNext: (viewYear * 12 + viewMonth) < (parseInt(maxDate.substring(0, 4), 10) * 12 + parseInt(maxDate.substring(5, 7), 10) - 1)

    Component.onCompleted: showMonthOf(selectedDate)

    // 42 cells (6 weeks) for the visible month: { iso, day, inMonth }
    readonly property var _cells: {
        var first = new Date(viewYear, viewMonth, 1);
        var offset = (first.getDay() - _firstDow + 7) % 7;
        var out = [];
        for (var i = 0; i < 42; ++i) {
            var d = new Date(viewYear, viewMonth, 1 - offset + i);
            out.push({
                iso: H.toIso(d),
                day: d.getDate(),
                inMonth: d.getMonth() === viewMonth
            });
        }
        return out;
    }

    // Month names / year list. Built once per range change.
    readonly property var _monthNames: {
        var n = [];
        for (var m = 0; m < 12; ++m)
            n.push(Qt.locale().monthName(m, Locale.LongFormat));
        return n;
    }
    readonly property var _years: {
        var y = [];
        for (var v = _maxYear; v >= _minYear; --v)
            y.push(String(v));
        return y;
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        spacing: 6

        // ── Header: ‹  [Month ▾] [Year ▾]  › ─────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            ToolButton {
                icon.name: "go-previous"
                flat: true
                enabled: picker._canGoPrev
                display: AbstractButton.IconOnly
                onClicked: picker.stepMonth(-1)
            }
            ComboBox {
                id: monthBox
                Layout.fillWidth: true
                model: picker._monthNames
                currentIndex: picker.viewMonth
                onActivated: function (idx) {
                    picker.viewMonth = idx;
                    picker._clampView();
                }
            }
            ComboBox {
                id: yearBox
                Layout.preferredWidth: 84
                model: picker._years
                currentIndex: picker._maxYear - picker.viewYear
                onActivated: function (idx) {
                    picker.viewYear = picker._maxYear - idx;
                    picker._clampView();
                }
            }
            ToolButton {
                icon.name: "go-next"
                flat: true
                enabled: picker._canGoNext
                display: AbstractButton.IconOnly
                onClicked: picker.stepMonth(1)
            }
        }

        // ── Weekday header ───────────────────────────────────────────
        Grid {
            Layout.fillWidth: true
            columns: 7
            Repeater {
                model: 7
                delegate: Label {
                    required property int index
                    width: layout.width / 7
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((picker._firstDow + index) % 7, Locale.ShortFormat)
                    color: Kirigami.Theme.textColor
                    opacity: 0.55
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }
        }

        // ── Day grid ─────────────────────────────────────────────────
        Grid {
            id: dayGrid
            Layout.fillWidth: true
            columns: 7
            Repeater {
                model: picker._cells
                delegate: Item {
                    id: cell
                    required property var modelData
                    readonly property bool selectable: modelData.iso >= picker.minDate && modelData.iso <= picker.maxDate
                    readonly property bool isSelected: modelData.iso === picker.selectedDate
                    readonly property bool inRange: picker.rangeStart !== "" && picker.rangeEnd !== ""
                        && modelData.iso >= picker.rangeStart && modelData.iso <= picker.rangeEnd
                    readonly property bool isToday: modelData.iso === H.todayIso()

                    width: layout.width / 7
                    height: 32

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 6
                        color: cell.isSelected
                            ? Kirigami.Theme.highlightColor
                            : (cell.inRange
                                ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                                : (hover.hovered && cell.selectable
                                    ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
                                    : "transparent"))
                        border.width: cell.isToday && !cell.isSelected ? 1 : 0
                        border.color: Kirigami.Theme.highlightColor
                    }
                    Label {
                        anchors.centerIn: parent
                        text: cell.modelData.day
                        color: cell.isSelected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        opacity: !cell.selectable ? 0.2 : (cell.modelData.inMonth ? 1.0 : 0.45)
                    }
                    HoverHandler {
                        id: hover
                        cursorShape: cell.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    TapHandler {
                        enabled: cell.selectable
                        onTapped: picker.picked(cell.modelData.iso)
                    }
                }
            }
        }
    }
}
