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
 * sum, UV index, snow cover, wind, pressure, air quality, pollen, alerts).
 *
 * Same layout as the expanded Pressure card: a Canvas fills the card, a
 * collapse button sits top-right, and an overlay (icon, value, band label,
 * optional sub-line) is centred inside the dial.
 *
 * Optional parts:
 *   - layoutMode "side": the overlay moves to the right half (the wind
 *     compass is a full circle on the left, not a semicircle dial).
 *   - pageCount > 1: a pager (previous / dots / next) at the bottom centre,
 *     for the cards that flip through several meters or alerts.
 *   - infoText / infoTitle: an info icon at the top-left with a tooltip.
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
import org.kde.plasma.core as PlasmaCore

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

    /** "dial": overlay centred inside a semicircle dial. "side": overlay on the right half. */
    property string layoutMode: "dial"

    /** Pager (only shown when pageCount > 1). */
    property int pageCount: 1
    property int pageIndex: 0
    signal previousRequested
    signal nextRequested
    signal pageSelected(int index)

    /** Info tooltip (icon shown when either is non-empty). infoText is rich text. */
    property string infoTitle: ""
    property string infoText: ""
    property int infoWidth: 380

    /** Any string that changes whenever the drawing has to be redone. */
    property string paintKey: ""

    /** Emitted from the Canvas onPaint; the owner draws into ctx. */
    signal draw(var ctx, real w, real h)
    signal collapseRequested

    readonly property bool _side: layoutMode === "side"
    readonly property bool _paged: pageCount > 1

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

    // Info icon + tooltip (top-left)
    PlasmaCore.ToolTipArea {
        visible: gauge.infoText.length > 0 || gauge.infoTitle.length > 0
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 6
        anchors.leftMargin: 8
        width: 24
        height: 24
        z: 2
        active: visible
        mainItem: ColumnLayout {
            width: gauge.infoWidth
            spacing: 6
            Label {
                visible: gauge.infoTitle.length > 0
                text: gauge.infoTitle
                font: gauge.weatherRoot ? gauge.weatherRoot.wf(12, true) : Qt.font({
                    bold: true
                })
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Label {
                visible: gauge.infoText.length > 0
                text: gauge.infoText
                font: gauge.weatherRoot ? gauge.weatherRoot.wf(11, false) : Qt.font({})
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: "help-about"
            opacity: 0.6
        }
    }

    // Overlay: icon + value + band label (+ optional sub-line)
    Column {
        id: overlay
        spacing: 2
        width: gauge._side ? Math.max(40, canvas.width * 0.42 - 12) : Math.max(40, Math.min(gauge.width * 0.5, 190))
        x: gauge._side ? Math.round(canvas.width * 0.58) : Math.round((canvas.width - width) / 2)
        y: gauge._side ? Math.round(canvas.y + (canvas.height - height) / 2) : Math.round(canvas.y + canvas.height - height - canvas.height * 0.18)

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

    // Pager: previous / dots (or "n / m") / next, bottom centre
    Row {
        id: pager
        visible: gauge._paged
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        spacing: 2
        z: 2

        Item {
            width: 18
            height: 18
            opacity: gauge.pageIndex > 0 ? 0.75 : 0.20
            Kirigami.Icon {
                anchors.fill: parent
                source: "arrow-left"
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: gauge.pageIndex > 0
                onClicked: gauge.previousRequested()
            }
        }

        Repeater {
            model: gauge.pageCount <= 12 ? gauge.pageCount : 0
            delegate: Item {
                required property int index
                width: 12
                height: 18
                Rectangle {
                    anchors.centerIn: parent
                    width: index === gauge.pageIndex ? 7 : 5
                    height: width
                    radius: width / 2
                    color: Kirigami.Theme.textColor
                    opacity: index === gauge.pageIndex ? 0.80 : 0.25
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: gauge.pageSelected(index)
                }
            }
        }
        Label {
            visible: gauge.pageCount > 12
            height: 18
            verticalAlignment: Text.AlignVCenter
            text: (gauge.pageIndex + 1) + " / " + gauge.pageCount
            color: Kirigami.Theme.textColor
            opacity: 0.7
            font: gauge.weatherRoot ? gauge.weatherRoot.wf(10, false) : Qt.font({})
        }

        Item {
            width: 18
            height: 18
            opacity: gauge.pageIndex < gauge.pageCount - 1 ? 0.75 : 0.20
            Kirigami.Icon {
                anchors.fill: parent
                source: "arrow-right"
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: gauge.pageIndex < gauge.pageCount - 1
                onClicked: gauge.nextRequested()
            }
        }
    }
}
