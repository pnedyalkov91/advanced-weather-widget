import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
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
    color: Kirigami.Theme.backgroundColor
    Rectangle { width: parent.width; height: 1; color: bar.tint(0.10) }

    // A button of the bar: a drawing, a light square under the hand, or
    // behind it while on (the loop).
    component BarIcon: Item {
        id: bi
        property string iconName
        property string tip
        property bool on: false
        signal clicked()
        implicitWidth: 30
        implicitHeight: 26
        Rectangle {
            anchors.fill: parent
            radius: 3
            color: bar.tint(bi.on ? 0.18 : biArea.containsMouse ? 0.08 : 0)
        }
        WmIcon {
            anchors.centerIn: parent
            width: 22
            height: 22
            name: bi.iconName
            mask: true
            opacity: bi.enabled ? (bi.on || bi.iconName !== "boucle-glyph" ? 1 : 0.6) : 0.4
        }
        MouseArea {
            id: biArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: bi.clicked()
        }
        QQC2.ToolTip.text: tip
        QQC2.ToolTip.visible: biArea.containsMouse
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
    // -3 h, +3 h: text on a light pill.
    component StepPill: Rectangle {
        id: pill
        property alias text: pillText.text
        property string tip
        signal clicked()
        implicitWidth: Math.max(62, pillText.implicitWidth + 20)
        implicitHeight: 30
        radius: 8
        color: bar.tint(pillArea.containsMouse ? 0.13 : 0.07)
        opacity: enabled ? 1 : 0.4
        QQC2.Label {
            id: pillText
            anchors.centerIn: parent
            color: bar.fg
            font.pixelSize: 14
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: pill.clicked()
        }
        QQC2.ToolTip.text: tip
        QQC2.ToolTip.visible: pillArea.containsMouse
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
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
            text: "‹  −" + bar.map.stepText
            tip: i18n("%1 back (Left: one hour)", bar.map.stepText)
            enabled: bar.map.count > 0
            onClicked: bar.map.js("window.animStepHours(-1, " + bar.map.stepHours + ")")
        }
        // Play or pause: the big round.
        Rectangle {
            implicitWidth: 38
            implicitHeight: 38
            radius: 19
            color: playArea.containsMouse ? Qt.lighter(bar.accent, 1.15) : bar.accent
            opacity: bar.map.readyCount > 1 ? 1 : 0.4
            Canvas {
                anchors.fill: parent
                property bool playing: bar.map.animState ? bar.map.animState.playing : false
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
            MouseArea {
                id: playArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: bar.map.readyCount > 1
                onClicked: bar.map.toggle()
            }
            QQC2.ToolTip.text: i18n("Play or pause (Space)")
            QQC2.ToolTip.visible: playArea.containsMouse
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        StepPill {
            text: "+" + bar.map.stepText + "  ›"
            tip: i18n("%1 ahead (Right: one hour)", bar.map.stepText)
            enabled: bar.map.count > 0
            onClicked: bar.map.js("window.animStepHours(1, " + bar.map.stepHours + ")")
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
            anim: bar.map.animState
            formatTime: bar.map.formatTime
            onPressedOn: bar.map.js("window.animPlay(false)")
            onShowIndex: function (i) { bar.map.js("window.animShow(" + i + ")"); }
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
