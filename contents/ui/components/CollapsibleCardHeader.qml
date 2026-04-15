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
 * CollapsibleCardHeader.qml — Reusable collapsed/expanded card header row
 *
 * Used by DetailsView for expandable cards (AQI, Pollen, Space Weather,
 * Alerts, Suntimes, Moonphase). Eliminates the repeated pattern of:
 *   WeatherIcon + Label + Item{fillWidth} + value content + chevron + MouseArea
 *
 * Usage:
 *   CollapsibleCardHeader {
 *       iconInfo: root.resolveIcon("airquality")
 *       iconSize: root.iconSize
 *       iconColor: root.accentFor("airquality")
 *       label: root.labelFor("airquality") + ":"
 *       showIcon: root.showIconFor("airquality")
 *       showChevron: !root.isList
 *       isExpanded: card._isArcExpanded
 *       weatherRoot: root.weatherRoot
 *       onToggleExpanded: root._aqiExpanded = !root._aqiExpanded
 *   }
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami

RowLayout {
    id: header

    // ── Public properties ─────────────────────────────────────────────────
    /** Icon info object from IconResolver.resolve() — null to hide icon */
    property var iconInfo: null

    /** Icon size in pixels */
    property int iconSize: 16

    /** Icon color override */
    property color iconColor: Kirigami.Theme.textColor

    /** Whether to show the icon */
    property bool showIcon: true

    /** The label text (e.g. "Air Quality:") */
    property string label: ""

    /** Whether to show the expand/collapse chevron */
    property bool showChevron: true

    /** Whether the card is currently expanded */
    property bool isExpanded: false

    /** Reference to weatherRoot for font helper */
    property var weatherRoot: null

    /** Whether the icon theme is symbolic (for icon color logic) */
    property bool isSymbolicTheme: false

    // ── Signals ───────────────────────────────────────────────────────────
    /** Emitted when the chevron is clicked */
    signal toggleExpanded()

    // ── Layout ────────────────────────────────────────────────────────────
    spacing: 8

    WeatherIcon {
        iconInfo: header.showIcon ? header.iconInfo : null
        iconSize: header.iconSize
        iconColor: header.isSymbolicTheme ? Kirigami.Theme.textColor : header.iconColor
        Layout.alignment: Qt.AlignVCenter
    }

    Label {
        text: header.label
        color: Kirigami.Theme.textColor
        opacity: 0.55
        font: header.weatherRoot ? header.weatherRoot.wf(11, false) : Qt.font({})
        Layout.alignment: Qt.AlignVCenter
    }

    Item { Layout.fillWidth: true }

    // ── Chevron ───────────────────────────────────────────────────────────
    Item {
        visible: header.showChevron
        implicitWidth: 14; implicitHeight: 14
        Layout.alignment: Qt.AlignVCenter
        Kirigami.Icon {
            anchors.fill: parent
            source: header.isExpanded ? "arrow-up" : "arrow-down"
            opacity: 0.45
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: header.toggleExpanded()
        }
    }
}
