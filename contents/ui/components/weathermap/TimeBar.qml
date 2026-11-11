import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The time bar under the map: first picture, a step back, play or pause,
// a step ahead, last picture, the time line, the loop. map: the
// WeatherMapView.
Rectangle {
    id: bar
    property var map
    readonly property alias timeLine: timeLine

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    implicitHeight: 84
    // See-through as the widget's frame: the page blurs the map under it.
    color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, bar.map.panelOpacity / 100)
    Rectangle { width: parent.width; height: 1; color: bar.tint(0.10) }
    // The bar lies over the map: what nothing of the bar takes stops here.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: function (wheel) { wheel.accepted = true; }
    }

    // A button of the bar: a drawing of contents/icons/weathermap, kept
    // down while on (the loop).
    component BarIcon: PlasmaComponents.ToolButton {
        id: bi
        property string iconName
        property string tip
        property bool on: false
        checked: on
        display: PlasmaComponents.ToolButton.IconOnly
        icon.source: Qt.resolvedUrl("../../../icons/weathermap/" + iconName + ".svg")
        icon.width: Kirigami.Units.iconSizes.smallMedium
        icon.height: Kirigami.Units.iconSizes.smallMedium
        icon.color: Kirigami.Theme.textColor
        readonly property bool own: bar.map.ownControls
        Layout.preferredWidth: own ? 30 : implicitWidth
        Layout.preferredHeight: own ? 26 : implicitHeight
        background.opacity: own ? 0 : 1
        contentItem.opacity: own ? 0 : 1
        // The own look: a drawing on a light square under the hand, or behind it while on.
        Rectangle {
            visible: bi.own
            anchors.fill: parent
            radius: 3
            color: bar.tint(bi.on ? 0.18 : bi.hovered ? 0.08 : 0)
            WmIcon {
                anchors.centerIn: parent
                width: 22
                height: 22
                name: bi.iconName
                mask: true
                opacity: bi.enabled ? (bi.on || bi.iconName !== "boucle-glyph" ? 1 : 0.6) : 0.4
            }
        }
        PlasmaComponents.ToolTip {
            text: bi.tip
            visible: bi.hovered
            delay: Kirigami.Units.toolTipDelay
        }
    }
    // -3 h, +3 h.
    component StepPill: PlasmaComponents.Button {
        id: pill
        property string tip
        property string widest        // the longest text it takes: its width does not jump while playing
        TextMetrics { id: widestMetrics; font: pill.font; text: pill.widest }
        implicitWidth: Math.max(implicitContentWidth, widestMetrics.advanceWidth) + leftPadding + rightPadding
        readonly property bool own: bar.map.ownControls
        Layout.preferredWidth: own ? Math.max(62, Math.max(pillText.implicitWidth, ownMetrics.advanceWidth) + 20) : implicitWidth
        Layout.preferredHeight: own ? 30 : implicitHeight
        background.opacity: own ? 0 : 1
        contentItem.opacity: own ? 0 : 1
        TextMetrics { id: ownMetrics; font: pillText.font; text: pill.widest }
        // The own look: text on a light pill.
        Rectangle {
            visible: pill.own
            anchors.fill: parent
            radius: 8
            color: bar.tint(pill.hovered ? 0.13 : 0.07)
            opacity: pill.enabled ? 1 : 0.4
            PlasmaComponents.Label {
                id: pillText
                anchors.centerIn: parent
                text: pill.text
                color: bar.fg
                font.pixelSize: 14
            }
        }
        PlasmaComponents.ToolTip {
            text: pill.tip
            visible: pill.hovered
            delay: Kirigami.Units.toolTipDelay
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 6

        BarIcon {
            iconName: "debut-glyph"
            tip: i18n("First picture") + " (" + i18nc("@info keyboard key", "Home") + ")"
            enabled: bar.map.count > 0
            onClicked: bar.map.showIndex(0)
        }
        StepPill {
            text: "‹  −" + bar.map.stepLabel(bar.map.stepBackH)
            widest: "‹  −" + bar.map.stepLabel(1 / 6)
            tip: i18n("%1 back", bar.map.stepLabel(bar.map.stepBackH)) + " (←)"
            enabled: bar.map.count > 0
            onClicked: bar.map.call("animStepButton", -1)
        }
        // Play or pause: the big round.
        PlasmaComponents.RoundButton {
            id: playButton
            readonly property bool playing: bar.map.animState ? bar.map.animState.playing : false
            readonly property bool own: bar.map.ownControls
            highlighted: true
            enabled: bar.map.readyCount > 1
            icon.name: playing ? "media-playback-pause" : "media-playback-start"
            onClicked: bar.map.toggle()
            Layout.preferredWidth: own ? 38 : implicitWidth
            Layout.preferredHeight: own ? 38 : implicitHeight
            background.opacity: own ? 0 : 1
            contentItem.opacity: own ? 0 : 1
            // The own look: a big round of the accent, drawn play or pause.
            Rectangle {
                visible: playButton.own
                anchors.fill: parent
                radius: width / 2
                color: playButton.hovered ? Qt.lighter(bar.accent, 1.15) : bar.accent
                opacity: playButton.enabled ? 1 : 0.4
                Canvas {
                    anchors.fill: parent
                    property bool playing: playButton.playing
                    property color fill: Kirigami.Theme.highlightedTextColor
                    onPlayingChanged: requestPaint()
                    onFillChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d");
                        c.reset();
                        c.fillStyle = fill;
                        if (playing) {
                            c.fillRect(13, 11, 4, 16);
                            c.fillRect(21, 11, 4, 16);
                        } else {
                            c.beginPath();
                            c.moveTo(15, 10);
                            c.lineTo(28, 19);
                            c.lineTo(15, 28);
                            c.closePath();
                            c.fill();
                        }
                    }
                }
            }
            PlasmaComponents.ToolTip {
                text: i18n("Play or pause (Space)")
                visible: parent.hovered
                delay: Kirigami.Units.toolTipDelay
            }
        }
        StepPill {
            text: "+" + bar.map.stepLabel(bar.map.stepAheadH) + "  ›"
            widest: "+" + bar.map.stepLabel(1 / 6) + "  ›"
            tip: i18n("%1 ahead", bar.map.stepLabel(bar.map.stepAheadH)) + " (→)"
            enabled: bar.map.count > 0
            onClicked: bar.map.call("animStepButton", 1)
        }
        BarIcon {
            iconName: "fin-glyph"
            tip: i18n("Last picture") + " (" + i18nc("@info keyboard key", "End") + ")"
            enabled: bar.map.count > 0
            onClicked: bar.map.showIndex(bar.map.count - 1)
        }
        TimeLine {
            id: timeLine
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.preferredHeight: implicitHeight
            Layout.topMargin: -6
            times: bar.map.frameTimes
            ready: bar.map.frameReady
            failed: bar.map.frameFailed
            nowIndex: bar.map.nowIndex
            bounds: bar.map.frameBounds
            position: bar.map.animState ? bar.map.animState.index : -1
            fromFile: !!(bar.map.animState && bar.map.animState.fromFile)
            radar: bar.map.animState ? bar.map.animState.radar : null
            satellite: bar.map.animState ? bar.map.animState.satellite : null
            formatTime: bar.map.formatTime
            onPressedOn: bar.map.call("animPlay", false)
            onShowIndex: function (i) { bar.map.call("animShow", i); }
            onShowPosition: function (p) { bar.map.call("animShow", p); }
        }
        // Round again from the start at the end, or stop there.
        BarIcon {
            iconName: "boucle-glyph"
            on: bar.map.loop
            tip: (on ? i18n("Loop: on") : i18n("Loop: off, stops at the end")) + " (L)"
            enabled: bar.map.count > 0
            onClicked: bar.map.setLoop(!on)
        }
    }
}
