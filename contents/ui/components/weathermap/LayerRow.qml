import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// One line of the layer column: the layer's icon (a click switches it on
// or off), its opacity on a thin line, then a wheel that opens its options
// (the default content) and the switch of its color legend. The whole line
// is greyed while the layer is off. customGear: the wheel only says
// gearClicked() (the radar opens its own menu). compact (the column
// folded): the icon alone, its opacity a bar under it, set with the wheel
// over it.
Item {
    id: row
    property string iconName           // in contents/icons/weathermap
    property bool iconMask: false       // a white drawing, tinted with the theme's text
    property string title
    property bool checked: false
    property bool active: checked
    property real iconSize: 28
    property int opacityValue: -1      // percent; -1: no slider
    property bool hasOptions: true
    property bool customGear: false
    property bool hasLegend: false     // a color legend over the map, shown or not
    property bool legendOn: true
    property bool compact: false
    // soloable: a double click on the icon asks for this layer alone
    // (soloRequested; with Ctrl, both), a single click then waits a moment.
    property bool soloable: false
    property bool soloed: false
    property string soloTip
    property string key               // the keyboard letter that switches the layer, shown in the tip
    readonly property string _keyText: key ? " (" + key + ")" : ""
    property real _wheel: 0
    property bool _turning: false      // Shift + wheel just moved: the tip shows the opacity
    default property alias options: optionsColumn.data
    readonly property alias optionsPopup: popup
    readonly property alias gearItem: gear
    signal toggled(bool on)
    signal opacityPicked(int pct)
    signal legendToggled(bool on)
    signal gearClicked()
    signal soloRequested(bool withCtrl)

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color offColor: Kirigami.Theme.disabledTextColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    implicitWidth: 169
    implicitHeight: compact ? 38 : 34
    readonly property real dim: active ? 1 : 0.35

    // The icon: the layer's switch.
    Item {
        id: iconBox
        x: row.compact ? (row.width - width) / 2 : 3
        width: 32
        height: row.compact ? 32 : parent.height
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 4
            color: row.tint(iconArea.containsMouse ? 0.08 : 0)
            border.width: row.soloed ? 1.5 : 0
            border.color: row.accent
        }
        WmIcon {
            anchors.centerIn: parent
            width: row.iconSize
            height: row.iconSize
            name: row.iconName
            mask: row.iconMask
            opacity: row.dim
        }
        MouseArea {
            id: iconArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (row.soloable)
                    clickWait.restart();
                else
                    row.toggled(!row.checked);
            }
            onDoubleClicked: function (mouse) {
                if (!row.soloable)
                    return;
                clickWait.stop();
                row.soloRequested((mouse.modifiers & Qt.ControlModifier) !== 0);
            }
        }
        // A single click, once no second one came.
        Timer {
            id: clickWait
            interval: 230
            onTriggered: row.toggled(!row.checked)
        }
        // Folded: Shift + wheel sets the opacity (5 % a notch, toward you more
        // opaque); the wheel alone scrolls the column.
        WheelHandler {
            enabled: row.compact && row.opacityValue >= 0 && row.checked
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            acceptedModifiers: Qt.ShiftModifier
            onWheel: function (event) {
                // Some systems turn Shift + wheel into a sideways wheel.
                row._wheel -= event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                var notches = Math.trunc(row._wheel / 120);
                if (notches === 0)
                    return;
                row._wheel -= notches * 120;
                var v = Math.max(0, Math.min(100, row.opacityValue + notches * 5));
                row._turning = true;
                turnEnd.restart();
                if (v !== row.opacityValue)
                    row.opacityPicked(v);
            }
        }
        Timer { id: turnEnd; interval: 1200; onTriggered: row._turning = false }
        // The opacity while Shift + wheel changes it: a tip of its own, the
        // shared one may already be shown (or timed out) for the hover.
        QQC2.ToolTip {
            visible: row._turning
            delay: 0
            timeout: -1
            text: "<b>" + i18n("Opacity: %1 %", row.opacityValue) + "</b>"
        }
        QQC2.ToolTip.text: row.compact && row.opacityValue >= 0
            ? "<b>" + row.title + "</b>" + row._keyText + (row.checked ? "<br>" + i18n("Opacity: %1 % (Shift + wheel)", row.opacityValue) : "")
            : row.title + row._keyText + (row.soloTip ? "<br><i>" + row.soloTip + "</i>" : "")
        QQC2.ToolTip.visible: iconArea.containsMouse && !row._turning
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // Folded: the opacity as a bar under the icon, as wide as the icon.
    Item {
        visible: row.compact && row.opacityValue >= 0
        x: (row.width - 28) / 2
        y: 33
        width: 28
        height: 2.5
        opacity: row.dim
        Rectangle { anchors.fill: parent; radius: 1.2; color: row.tint(0.15) }
        Rectangle {
            width: parent.width * Math.max(0, row.opacityValue) / 100
            height: parent.height
            radius: 1.2
            color: row.checked ? row.accent : row.offColor
        }
    }

    // The opacity, its value in a tip under the hand.
    QQC2.Slider {
        id: slider
        visible: !row.compact && row.opacityValue >= 0
        enabled: row.checked
        x: iconBox.x + iconBox.width + 2
        width: gear.x - x - 2   // as long on every line, with a wheel or not
        anchors.verticalCenter: parent.verticalCenter
        height: 20
        from: 0
        to: 100
        opacity: row.dim
        // A thin line and a small round handle.
        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 2
            radius: 1
            color: row.checked ? row.accent : row.offColor
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 10
            height: 10
            radius: 5
            color: slider.pressed ? row.accent : Kirigami.Theme.backgroundColor
            border.color: row.checked ? row.accent : row.offColor
            border.width: 1
        }
        // No stepSize: the style would draw a mark every 5 %; rounded below.
        Binding on value {
            when: !slider.pressed
            value: Math.max(0, row.opacityValue)
            restoreMode: Binding.RestoreNone
        }
        onMoved: row.opacityPicked(Math.round(value / 5) * 5)
        HoverHandler { id: sliderHover }
        QQC2.ToolTip.text: i18n("Opacity: %1 %", row.opacityValue)
        // A layer off (greyed) needs no tip.
        QQC2.ToolTip.visible: row.active && (slider.pressed || sliderHover.hovered)
        QQC2.ToolTip.delay: slider.pressed ? 0 : Kirigami.Units.toolTipDelay
    }

    // The wheel of the options.
    Rectangle {
        id: gear
        visible: !row.compact && row.hasOptions
        x: row.width - width - 4
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: 12
        color: gearArea.containsMouse || popup.visible ? row.tint(0.10) : "transparent"
        WmIcon {
            anchors.centerIn: parent
            width: 16
            height: 16
            name: "gear"
            mask: true
            opacity: 0.85 * row.dim
        }
        MouseArea {
            id: gearArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (row.customGear)
                    row.gearClicked();
                else
                    popup.visible ? popup.close() : popup.open();
            }
        }
        QQC2.ToolTip.text: i18n("%1: options", row.title)
        QQC2.ToolTip.visible: row.active && gearArea.containsMouse && !popup.visible
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // Under the line, its right edge on the wheel's.
    QQC2.Popup {
        id: popup
        margins: 6                   // kept inside the window
        x: gear.x + gear.width - width
        y: gear.y + gear.height + 6
        // As wide as its longest line (the translations differ), 230 at least.
        width: Math.max(230, Math.ceil(contentItem.implicitWidth) + leftPadding + rightPadding)
        padding: 12
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent
        contentItem: ColumnLayout {
            spacing: 6
            QQC2.Label {
                text: row.title
                font.bold: true
            }
            ColumnLayout {
                id: optionsColumn
                Layout.fillWidth: true
                spacing: 4
            }
            SmallSwitch {
                visible: row.hasLegend
                text: i18n("Color legend on the map")
                checked: row.legendOn
                onToggled: {
                    row.legendToggled(checked);
                    checked = Qt.binding(function () { return row.legendOn; });
                }
            }
        }
    }
}
