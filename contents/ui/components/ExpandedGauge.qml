/*
 * Copyright 2026 Petar Nedyalkov
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
 * along with this program.  If not, see <https://gnu.org>.
 */

/**
 * ExpandedGauge.qml - shared expanded-card body for the Details tab gauges
 * (feels like, humidity, dew point, visibility, precipitation, precipitation
 * sum, UV index, snow cover).
 *
 * Same layout as the expanded Pressure card: a Canvas fills the card, a
 * collapse button sits top-right, and an overlay (icon, value, band label,
 * optional sub-line) is centred inside the dial.
 *
 * The component knows nothing about the individual gauges. The owner does the
 * drawing in its `draw` handler and bumps `paintKey` whenever something that
 * affects the picture changes:
 *
 *   ExpandedGauge {
 *       paintKey: "..."
 *       onDraw: function (ctx, w, h) { SomeGauge.draw(ctx, w, h, params) }
 *       onCollapseRequested: ...
 *   }
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: gauge
    clip: true

    /** DetailsView's weatherRoot - only used for the font helper wf(). */
    property var weatherRoot: null

    property var iconInfo: null
    property color iconColor: Kirigami.Theme.textColor
    property int iconSize: 16

    property string valueText: "--"
    property color valueColor: Kirigami.Theme.textColor
    property string bandText: ""
    property color bandColor: Kirigami.Theme.textColor
    property string subText: ""
    property color subColor: Kirigami.Theme.textColor

    /** Any string that changes whenever the drawing has to be redone. */
    property string paintKey: ""

    /** Emitted from the Canvas onPaint; the owner draws into ctx. */
    signal draw(var ctx, real w, real h)
    signal collapseRequested

    onPaintKeyChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 8
        height: parent.height - 8
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible)
            requestPaint()
        onPaint: {
            var ctx2d = getContext("2d");
            gauge.draw(ctx2d, width, height);
        }
    }

    // Collapse button
    Item {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 8
        width: 24
        height: 24
        z: 2
        Kirigami.Icon {
            anchors.fill: parent
            source: "arrow-up"
            opacity: 0.50
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: gauge.collapseRequested()
        }
    }

    // Centre overlay: icon + value + band label (+ optional sub-line)
    Column {
        anchors.horizontalCenter: canvas.horizontalCenter
        anchors.bottom: canvas.bottom
        anchors.bottomMargin: Math.round(canvas.height * 0.18)
        spacing: 2
        width: Math.max(40, Math.min(gauge.width * 0.5, 190))

        WeatherIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            iconInfo: gauge.iconInfo
            iconSize: gauge.iconSize
            iconColor: gauge.iconColor
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, parent.width)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: gauge.valueText
            color: gauge.valueColor
            font: gauge.weatherRoot ? gauge.weatherRoot.wf(15, true) : Qt.font({
                bold: true
            })
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: gauge.bandText.length > 0
            width: Math.min(implicitWidth, parent.width)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: gauge.bandText
            color: gauge.bandColor
            font: gauge.weatherRoot ? gauge.weatherRoot.wf(10, true) : Qt.font({
                bold: true
            })
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: gauge.subText.length > 0
            width: Math.min(implicitWidth, parent.width)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: gauge.subText
            color: gauge.subColor
            opacity: 0.6
            font: gauge.weatherRoot ? gauge.weatherRoot.wf(10, false) : Qt.font({})
        }
    }
}
