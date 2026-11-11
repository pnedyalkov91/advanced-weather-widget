import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The options of the radar (the wheel of the radar's line; the opacities
// are on the lines): its colors, its switches (snow, smoothing, lightning,
// storm cells, wind arrows, alerts), then the tile format and size, which
// the satellite follows too. options: window.animRadarOptions().
PlasmaComponents.Popup {
    id: menu
    property var schemes: []          // [[id, name]] from the catalog
    property var options: ({})
    // The widget's own look over the Plasma components, whose theme drawing is then hidden.
    property bool ownLook: false
    signal optionPicked(string key, var value)

    readonly property color fg: Kirigami.Theme.textColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    width: 230
    padding: 10
    margins: 6                       // kept inside the window
    closePolicy: PlasmaComponents.Popup.CloseOnEscape | PlasmaComponents.Popup.CloseOnPressOutsideParent

    component Caption: PlasmaComponents.Label {
        color: Kirigami.Theme.disabledTextColor
    }
    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 1
        color: menu.tint(0.12)
    }
    // A switch of the radar: its icon and its name, a button kept down while on.
    component Switch: PlasmaComponents.ToolButton {
        id: sw
        property string key
        property bool mask: false
        property string title
        readonly property bool on: !!menu.options[key]
        Layout.fillWidth: true
        text: title
        icon.width: 22
        icon.height: 22
        icon.color: mask ? menu.fg : "transparent"
        display: PlasmaComponents.ToolButton.TextBesideIcon
        checkable: true
        checked: on
        onClicked: {
            checked = Qt.binding(function () { return sw.on; });
            menu.optionPicked(sw.key, !sw.on);
        }
        Layout.preferredHeight: menu.ownLook ? 32 : implicitHeight
        background.opacity: menu.ownLook ? 0 : 1
        contentItem.opacity: menu.ownLook ? 0 : 1
        // The own look: its icon on a light square while on, and its name.
        Rectangle {
            visible: menu.ownLook
            anchors.fill: parent
            radius: 4
            color: menu.tint(sw.hovered ? 0.06 : 0)
            Rectangle {
                id: swBox
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 26
                radius: 3
                color: sw.on ? menu.tint(0.2) : "transparent"
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    roundToIconSize: false
                    source: sw.icon.source
                    isMask: sw.mask
                    color: sw.mask ? menu.fg : "transparent"
                    opacity: sw.on ? 1 : 0.6
                }
            }
            PlasmaComponents.Label {
                anchors.left: swBox.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: sw.title
                opacity: sw.on ? 1 : 0.75
            }
        }
    }
    // Two choices side by side, the one taken kept down.
    component Segmented: RowLayout {
        id: seg
        property string key
        property string title
        property var choices: []        // [[value, text]]
        spacing: 0
        PlasmaComponents.Label { text: seg.title; color: Kirigami.Theme.disabledTextColor; Layout.fillWidth: true }
        Item {
            implicitWidth: segRow.implicitWidth + (menu.ownLook ? 4 : 0)
            implicitHeight: menu.ownLook ? 26 : segRow.implicitHeight
            // The own look: the choices in a light box, the one taken filled.
            Rectangle {
                visible: menu.ownLook
                anchors.fill: parent
                radius: 4
                color: menu.tint(0.06)
                border.color: menu.tint(0.12)
            }
            Row {
                id: segRow
                anchors.centerIn: parent
                Repeater {
                    model: seg.choices
                    PlasmaComponents.ToolButton {
                        id: segButton
                        required property var modelData
                        readonly property bool taken: String(menu.options[seg.key]) === String(modelData[0])
                        text: modelData[1]
                        checkable: true
                        checked: taken
                        onClicked: {
                            checked = Qt.binding(function () { return taken; });
                            menu.optionPicked(seg.key, modelData[0]);
                        }
                        width: menu.ownLook ? 50 : implicitWidth
                        height: menu.ownLook ? 22 : implicitHeight
                        background.opacity: menu.ownLook ? 0 : 1
                        contentItem.opacity: menu.ownLook ? 0 : 1
                        Rectangle {
                            visible: menu.ownLook
                            anchors.fill: parent
                            radius: 3
                            color: segButton.taken ? Kirigami.Theme.highlightColor : "transparent"
                            PlasmaComponents.Label {
                                anchors.centerIn: parent
                                text: segButton.text
                                font.bold: segButton.taken
                                color: segButton.taken ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.disabledTextColor
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property string radarIcons: Qt.resolvedUrl("../../../icons/weathermap/radar/")

    contentItem: ColumnLayout {
        spacing: 2
        RowLayout {
            Caption { text: i18n("Colors"); Layout.fillWidth: true }
            PlasmaComponents.ComboBox {
                Layout.preferredWidth: 130
                model: menu.schemes.map(function (s) { return s[1]; })
                currentIndex: {
                    for (var i = 0; i < menu.schemes.length; i++)
                        if (menu.schemes[i][0] === menu.options.color)
                            return i;
                    return -1;
                }
                onActivated: function (i) { menu.optionPicked("color", menu.schemes[i][0]); }
            }
        }
        Separator {}
        Switch { key: "snow"; icon.source: menu.radarIcons + "neige.svg"; title: i18n("Snow") }
        Switch { key: "smooth"; icon.source: menu.radarIcons + "lissage.svg"; mask: true; title: i18n("Smoothing") }
        Switch { key: "lightning"; icon.source: menu.radarIcons + "eclairs.svg"; title: i18n("Lightning") }
        Switch { key: "cells"; icon.source: Qt.resolvedUrl("../../../icons/flat-color/22/wi-thunderstorm.svg"); title: i18n("Storm cells") }
        Switch { key: "arrows"; icon.source: menu.radarIcons + "fleches-vent.svg"; title: i18n("Wind arrows") }
        Switch { key: "alerts"; icon.source: menu.radarIcons + "alertes.svg"; title: i18n("Alerts") }
        Separator {}
        Segmented { key: "format"; title: i18n("Format"); choices: [["webp", "WebP"], ["png", "PNG"]] }
        Item { implicitHeight: 4 }
        Segmented { key: "tileSize"; title: i18n("Tiles"); choices: [["256", "256"], ["512", "512"]] }
    }
}
