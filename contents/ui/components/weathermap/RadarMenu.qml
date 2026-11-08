import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// The options of the radar (the wheel of the radar's line; the opacities
// are on the lines): its colors, its switches (snow, smoothing, lightning,
// storm cells, wind arrows, alerts), then the tile format and size, which
// the satellite follows too. options: window.animRadarOptions().
QQC2.Popup {
    id: menu
    property var schemes: []          // [[id, name]] from the catalog
    property var options: ({})
    signal optionPicked(string key, var value)

    readonly property color fg: Kirigami.Theme.textColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    width: 230
    padding: 10
    margins: 6                       // kept inside the window
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

    component Caption: QQC2.Label {
        color: Kirigami.Theme.disabledTextColor
    }
    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 1
        color: menu.tint(0.12)
    }
    // A switch of the radar: its icon on a light square while on, and its name.
    component Switch: Item {
        id: sw
        property string key
        property url icon
        property bool mask: false
        property string title
        readonly property bool on: !!menu.options[key]
        Layout.fillWidth: true
        implicitHeight: 32
        Rectangle {
            anchors.fill: parent
            radius: 4
            color: menu.tint(swArea.containsMouse ? 0.06 : 0)
        }
        Rectangle {
            id: box
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
                source: sw.icon
                isMask: sw.mask
                color: sw.mask ? menu.fg : "transparent"
                opacity: sw.on ? 1 : 0.6
            }
        }
        QQC2.Label {
            anchors.left: box.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: sw.title
            opacity: sw.on ? 1 : 0.75
        }
        MouseArea {
            id: swArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: menu.optionPicked(sw.key, !sw.on)
        }
    }
    // Two choices side by side, the one taken highlighted.
    component Segmented: RowLayout {
        id: seg
        property string key
        property string title
        property var choices: []        // [[value, text]]
        spacing: 0
        QQC2.Label { text: seg.title; color: Kirigami.Theme.disabledTextColor; Layout.fillWidth: true }
        Rectangle {
            implicitWidth: segRow.implicitWidth + 4
            implicitHeight: 26
            radius: 4
            color: menu.tint(0.06)
            border.color: menu.tint(0.12)
            Row {
                id: segRow
                anchors.centerIn: parent
                spacing: 0
                Repeater {
                    model: seg.choices
                    Rectangle {
                        required property var modelData
                        readonly property bool taken: String(menu.options[seg.key]) === String(modelData[0])
                        width: 50
                        height: 22
                        radius: 3
                        color: taken ? Kirigami.Theme.highlightColor : "transparent"
                        QQC2.Label {
                            anchors.centerIn: parent
                            text: modelData[1]
                            font.bold: parent.taken
                            color: parent.taken ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.disabledTextColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: menu.optionPicked(seg.key, modelData[0])
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
            QQC2.ComboBox {
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
        Switch { key: "snow"; icon: menu.radarIcons + "neige.svg"; title: i18n("Snow") }
        Switch { key: "smooth"; icon: menu.radarIcons + "lissage.svg"; mask: true; title: i18n("Smoothing") }
        Switch { key: "lightning"; icon: menu.radarIcons + "eclairs.svg"; title: i18n("Lightning") }
        Switch { key: "cells"; icon: Qt.resolvedUrl("../../../icons/flat-color/22/wi-thunderstorm.svg"); title: i18n("Storm cells") }
        Switch { key: "arrows"; icon: menu.radarIcons + "fleches-vent.svg"; title: i18n("Wind arrows") }
        Switch { key: "alerts"; icon: menu.radarIcons + "alertes.svg"; title: i18n("Alerts") }
        Separator {}
        Segmented { key: "format"; title: i18n("Format"); choices: [["webp", "WebP"], ["png", "PNG"]] }
        Item { implicitHeight: 4 }
        Segmented { key: "tileSize"; title: i18n("Tiles"); choices: [["256", "256"], ["512", "512"]] }
    }
}
