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
import org.kde.plasma.plasmoid
// NOTE: adjust this path if ExpandedGauge.qml does not live next to ui/js/
import "../js/gaugeAnim.js" as GA

Item {
    id: gauge
    clip: true

    /** DetailsView's weatherRoot - only used for the font helper wf(). */
    property var weatherRoot: null

    property var iconInfo: null
    property color iconColor: Kirigami.Theme.textColor
    property int iconSize: 16

    /** Card title (Feels Like, Precipitation Sum, ...), shown right after the icon. */
    property string title: ""

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
    /** true: the info icon sits right after the value text (the title) instead of the top-left corner. */
    property bool infoNextToValue: false

    /** Widest the centred overlay may get (dial layout). Long texts wrap instead of being cut. */
    property int overlayMaxWidth: 190

    /** Any string that changes whenever the drawing has to be redone. */
    property string paintKey: ""

    /** Emitted from the Canvas onPaint; the owner draws into ctx. */
    signal draw(var ctx, real w, real h)
    signal collapseRequested

    readonly property bool _side: layoutMode === "side"
    readonly property bool _paged: pageCount > 1

    /** Scene animations (Settings -> Widget -> Details -> Animations). */
    readonly property bool animated: Plasmoid.configuration.detailsAnimations === true

    /** Frame interval of the scene while animating (ms). ~15 fps is plenty for ambient motion. */
    property int animInterval: 66

    // ── When may the scene move? ──────────────────────────────────────────
    // Only while somebody can actually see it (same idea as BareWeather's
    // `popupActive: planar || expanded`). A closed popup keeps its items "visible"
    // in QML, so a panel widget has to ask the popup state; on the desktop or in a
    // window the widget is always shown.
    // NOTE: in Plasma 6 `expanded` is a property of the PlasmoidItem root (here
    // weatherRoot), NOT of the attached `Plasmoid` object - FullView.qml does the same.
    property bool animDebug: false   // set true to log why the scene is (not) moving
    readonly property bool _popupShown: {
        var ff = Plasmoid.formFactor;
        var inPanel = ff === PlasmaCore.Types.Horizontal || ff === PlasmaCore.Types.Vertical;
        if (!inPanel)
            return true;
        // unknown state => assume shown, never freeze the scene by mistake
        return gauge.weatherRoot && gauge.weatherRoot.expanded !== undefined ? gauge.weatherRoot.expanded === true : true;
    }
    // ...and only while the card is inside the scrolled area of the Details tab.
    // This is polled (2x a second, only while animating) instead of being driven by
    // geometry signals: the card moves when cards above it expand or collapse, which
    // none of its own signals report. Unknown = visible, so it can never leave the
    // scene frozen by mistake.
    property Item _flick: null
    property bool _inView: true
    readonly property bool _animating: animated && _popupShown && visible && width > 0 && height > 0 && _inView

    function _findFlickable() {
        var p = gauge.parent;
        while (p) {
            if (p.contentY !== undefined && p.contentHeight !== undefined)
                return p;
            p = p.parent;
        }
        return null;
    }
    function _updateInView() {
        if (!_flick)
            _flick = _findFlickable();
        if (!_flick || !(_flick.height > 0) || !(gauge.height > 0)) {
            _inView = true;
            return;
        }
        var top = gauge.mapToItem(_flick, 0, 0).y;
        _inView = top < _flick.height && top + gauge.height > 0;
    }
    on_AnimatingChanged: if (animDebug)
        console.log("ExpandedGauge animating=" + _animating + " animated=" + animated + " popup=" + _popupShown
                    + " visible=" + visible + " size=" + width + "x" + height + " inView=" + _inView)

    Timer {
        running: gauge.animated && gauge._popupShown && gauge.visible
        interval: 500
        repeat: true
        triggeredOnStart: true
        onTriggered: gauge._updateInView()
    }
    Connections {
        target: gauge._flick
        ignoreUnknownSignals: true
        function onContentYChanged() { gauge._updateInView(); }
    }

    onPaintKeyChanged: {
        canvas.requestPaint();
        dialCanvas.requestPaint();
    }
    onAnimatedChanged: {
        canvas.requestPaint();
        dialCanvas.requestPaint();
    }

    // Repaints only the moving scene, and only while it is really on screen.
    Timer {
        running: gauge._animating
        interval: gauge.animInterval
        repeat: true
        onTriggered: canvas.requestPaint()
    }

    // Layer 1: the scene. With animations off it draws the whole gauge (scene + dial)
    // once per change, exactly like before. With animations on it draws the scene only.
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
            GA.setEnabled(gauge.animated);
            GA.setLayer(gauge.animated ? "scene" : "all");
            gauge.draw(ctx2d, width, height);
            GA.setLayer("all");
        }
    }

    // Layer 2 (animations on only): the dial, ticks, labels and markers. They never move,
    // so this canvas is painted when the data or the size changes - not every frame.
    Canvas {
        id: dialCanvas
        visible: gauge.animated
        anchors.fill: canvas
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible)
            requestPaint()
        onPaint: {
            var ctx2d = getContext("2d");
            GA.setEnabled(true);
            GA.setLayer("dial");
            gauge.draw(ctx2d, width, height);
            GA.setLayer("all");
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
        // top-left corner, or on the placeholder right after the value text
        x: gauge.infoNextToValue ? overlay.x + valueRow.x + infoSlot.x - 3 : 8
        y: gauge.infoNextToValue ? overlay.y + valueRow.y + infoSlot.y - 3 : 6
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
        width: gauge._side ? Math.max(40, canvas.width * 0.42 - 12) : Math.max(40, Math.min(gauge.width * 0.5, gauge.overlayMaxWidth))
        x: gauge._side ? Math.round(canvas.width * 0.58) : Math.round((canvas.width - width) / 2)
        y: gauge._side ? Math.round(canvas.y + (canvas.height - height) / 2) : Math.round(canvas.y + canvas.height - height - canvas.height * 0.18)

        // icon + card title, so gauges that look alike can be told apart
        Row {
            id: titleRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5
            WeatherIcon {
                id: titleIcon
                anchors.verticalCenter: parent.verticalCenter
                iconInfo: gauge.iconInfo
                iconSize: gauge.iconSize
                iconColor: gauge.iconColor
            }
            Label {
                id: titleLabel
                visible: gauge.title.length > 0
                anchors.verticalCenter: parent.verticalCenter
                // Sized from an invisible single-line twin (same font and render type, so the
                // measurement is exact) and wrapped only at spaces: a title is never cut in
                // the middle of a word, whatever font, scaling or language is in use.
                width: Math.min(Math.ceil(titleProbe.implicitWidth) + 3, overlay.width - titleIcon.width - titleRow.spacing)
                wrapMode: Text.WordWrap
                text: gauge.title
                color: Kirigami.Theme.textColor
                opacity: 0.65
                font: gauge.weatherRoot ? gauge.weatherRoot.wf(11, false) : Qt.font({})
                Label {
                    id: titleProbe
                    visible: false
                    text: gauge.title
                    font: titleLabel.font
                    wrapMode: Text.NoWrap
                }
            }
        }
        // value: wraps onto more lines instead of being elided; with
        // infoNextToValue an empty slot after it carries the info icon
        Row {
            id: valueRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            Label {
                id: valueLabel
                width: Math.min(Math.ceil(valueProbe.implicitWidth) + 3, overlay.width - (gauge.infoNextToValue && gauge.infoText.length > 0 ? 22 : 0))
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: gauge.valueText
                color: gauge.valueColor
                font: gauge.weatherRoot ? gauge.weatherRoot.wf(15, true) : Qt.font({
                    bold: true
                })
                Label {
                    id: valueProbe
                    visible: false
                    text: gauge.valueText
                    font: valueLabel.font
                    wrapMode: Text.NoWrap
                }
            }
            Item {
                id: infoSlot
                visible: gauge.infoNextToValue && (gauge.infoText.length > 0 || gauge.infoTitle.length > 0)
                width: visible ? 18 : 0
                height: 18
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: gauge.bandText.length > 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: gauge.bandText
            color: gauge.bandColor
            font: gauge.weatherRoot ? gauge.weatherRoot.wf(10, true) : Qt.font({
                bold: true
            })
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: gauge.subText.length > 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
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
