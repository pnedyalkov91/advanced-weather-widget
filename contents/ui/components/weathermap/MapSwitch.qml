import QtQuick
import org.kde.plasma.components as PlasmaComponents

// A switch of the Weather Maps: the Plasma theme's, or with own the
// widget's own small one (SmallSwitch). Used as a switch: text, checked,
// bold, hovered, toggled(); checked is already the new value in toggled.
Item {
    id: ms
    property bool own: false
    property string text
    property bool checked: false
    property bool bold: false
    readonly property bool hovered: box.item ? box.item.hovered : false
    signal toggled()

    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight

    Loader {
        id: box
        anchors.fill: parent
        sourceComponent: ms.own ? small : plasma
    }
    Component {
        id: plasma
        PlasmaComponents.Switch {
            id: plasmaSwitch
            text: ms.text
            font.bold: ms.bold
            checked: ms.checked
            onToggled: ms._toggled(plasmaSwitch)
        }
    }
    Component {
        id: small
        SmallSwitch {
            id: smallSwitch
            text: ms.text
            font.bold: ms.bold
            checked: ms.checked
            onToggled: ms._toggled(smallSwitch)
        }
    }
    // The new value goes out, then the inner switch follows ms.checked again.
    function _toggled(sw) {
        ms.checked = sw.checked;
        ms.toggled();
        sw.checked = Qt.binding(function () { return ms.checked; });
    }
}
