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
            readonly property bool playing: bar.map.animState ? bar.map.animState.playing : false
            highlighted: true
            enabled: bar.map.readyCount > 1
            icon.name: playing ? "media-playback-pause" : "media-playback-start"
            onClicked: bar.map.toggle()
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
