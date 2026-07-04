import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../js/iconResolver.js" as IconResolver
import "../js/weather.js" as W

Item {
    id: root
    property var hostRoot
    property var serviceRoot
    property var wiFont
    property var hourlyItems: []
    property bool autoScrollToCurrent: false

    function _scrollToAnchor() {
        if (!autoScrollToCurrent || !hourlyItems || hourlyItems.length === 0)
            return;
        var targetIndex = -1;
        for (var index = 0; index < hourlyItems.length; index++) {
            if (hourlyItems[index].autoScrollTarget === true) {
                targetIndex = index;
                break;
            }
        }
        if (targetIndex < 0)
            return;
        hourlyList.positionViewAtIndex(targetIndex, ListView.Beginning);
    }

    ListView {
        id: hourlyList
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        orientation: ListView.Horizontal
        spacing: 6
        model: root.hourlyItems || []
        reuseItems: true
        cacheBuffer: width
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOff
        }
        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        onModelChanged: scrollTimer.restart()
        Component.onCompleted: scrollTimer.restart()

        delegate: Rectangle {
            required property var modelData
            readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true

            width: _isSun ? 70 : root.hostRoot._hourlyCardWidth
            height: root.hostRoot._hourlyCardHeight
            radius: 8
            color: _isSun
                ? Qt.rgba(root.hostRoot.themeTextColor.r, root.hostRoot.themeTextColor.g, root.hostRoot.themeTextColor.b, 0.04)
                : Qt.rgba(root.hostRoot.themeTextColor.r, root.hostRoot.themeTextColor.g, root.hostRoot.themeTextColor.b, 0.08)
            border.color: Qt.rgba(root.hostRoot.themeTextColor.r, root.hostRoot.themeTextColor.g, root.hostRoot.themeTextColor.b, 0.12)
            border.width: 1

            ColumnLayout {
                visible: parent._isSun
                anchors.centerIn: parent
                spacing: 6

                WeatherIcon {
                    Layout.alignment: Qt.AlignHCenter
                    iconInfo: IconResolver.resolve(
                        modelData.isSunrise ? "sunrise" : "sunset",
                        32,
                        root.hostRoot.iconsBaseDir,
                        root.hostRoot.widgetIconTheme === "kde" ? "flat-color" :
                        (root.hostRoot.widgetIconTheme === "wi-font" || root.hostRoot.widgetIconTheme === "custom" || root.hostRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : root.hostRoot.widgetIconTheme)
                    iconSize: 32
                    iconColor: root.hostRoot.themeTextColor
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.displayTime || "--"
                    color: root.hostRoot.themeTextColor
                    font: root.serviceRoot ? root.serviceRoot.wf(10, true) : Qt.font({ bold: true })
                }
            }

            ColumnLayout {
                visible: !parent._isSun
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.displayTime || "--"
                    color: root.hostRoot.themeTextColor
                    font: root.serviceRoot ? root.serviceRoot.wf(9, false) : Qt.font({})
                }

                WeatherIcon {
                    Layout.alignment: Qt.AlignHCenter
                    iconInfo: root.hostRoot.resolveConditionIcon(modelData.code || 0, modelData.isNight === true, root.hostRoot.iconSz)
                    iconSize: 48
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.tempText || "--"
                    color: root.hostRoot.themeTextColor
                    font: root.serviceRoot ? root.serviceRoot.wf(11, true) : Qt.font({ bold: true })
                }

                RowLayout {
                    visible: root.hostRoot._hourlyShowWind
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    Label {
                        text: modelData.windText || "--"
                        color: root.hostRoot.themeTextColor
                        font: root.serviceRoot ? root.serviceRoot.wf(9, false) : Qt.font({})
                    }

                    Text {
                        visible: !isNaN(modelData.windDeg)
                        text: W.windDirectionGlyph(modelData.windDeg)
                        font.family: root.wiFont && root.wiFont.status === FontLoader.Ready ? root.wiFont.font.family : ""
                        font.pixelSize: 20
                        color: root.hostRoot.themeTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                RowLayout {
                    visible: root.hostRoot._hourlyShowPressure
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    WeatherIcon {
                        iconInfo: IconResolver.resolve("pressure", 24, root.hostRoot.iconsBaseDir, root.hostRoot.itemsIconTheme)
                        iconSize: 24
                        iconColor: root.hostRoot.themeTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: modelData.pressureText || "--"
                        color: root.hostRoot.themeTextColor
                        font: root.serviceRoot ? root.serviceRoot.wf(9, false) : Qt.font({})
                    }
                }

                RowLayout {
                    visible: root.hostRoot._hourlyShowKpIndex
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    WeatherIcon {
                        iconInfo: IconResolver.resolve("spaceweather", 24, root.hostRoot.iconsBaseDir, root.hostRoot.itemsIconTheme)
                        iconSize: 24
                        iconColor: root.hostRoot.themeTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: modelData.kpText || i18n("No info")
                        color: root.hostRoot.themeTextColor
                        font: root.serviceRoot ? root.serviceRoot.wf(9, false) : Qt.font({})
                    }
                }

                RowLayout {
                    visible: root.hostRoot._hourlyShowUvIndex
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    WeatherIcon {
                        iconInfo: IconResolver.resolve("uvindex", 24, root.hostRoot.iconsBaseDir, root.hostRoot.itemsIconTheme)
                        iconSize: 24
                        iconColor: root.hostRoot.themeTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: modelData.uvText || "--"
                        color: root.hostRoot.themeTextColor
                        font: root.serviceRoot ? root.serviceRoot.wf(9, false) : Qt.font({})
                    }
                }

                RowLayout {
                    visible: root.hostRoot._hourlyShowPrecipSum
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    WeatherIcon {
                        iconInfo: IconResolver.resolve("precipsum", 24, root.hostRoot.iconsBaseDir, root.hostRoot.itemsIconTheme)
                        iconSize: 24
                        iconColor: root.hostRoot.themeTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: modelData.precipText || "--"
                        color: root.hostRoot.themeTextColor
                        font: root.serviceRoot ? root.serviceRoot.wf(9, false) : Qt.font({})
                    }
                }

                RowLayout {
                    visible: root.hostRoot._hourlyShowVisibility
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    WeatherIcon {
                        iconInfo: IconResolver.resolve("visibility", 24, root.hostRoot.iconsBaseDir, root.hostRoot.itemsIconTheme)
                        iconSize: 24
                        iconColor: root.hostRoot.themeTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: modelData.visibilityText || "--"
                        color: root.hostRoot.themeTextColor
                        font: root.serviceRoot ? root.serviceRoot.wf(9, false) : Qt.font({})
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    WeatherIcon {
                        iconInfo: IconResolver.resolve("umbrella", 32, root.hostRoot.iconsBaseDir,
                            root.hostRoot.widgetIconTheme === "kde" ? "flat-color" :
                            (root.hostRoot.widgetIconTheme === "wi-font" || root.hostRoot.widgetIconTheme === "custom" || root.hostRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : root.hostRoot.widgetIconTheme)
                        iconSize: 32
                        iconColor: root.hostRoot.themeTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: modelData.precipDisplayText || "--"
                        color: root.hostRoot.themeTextColor
                        font: root.serviceRoot ? root.serviceRoot.wf(9, false) : Qt.font({})
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: -5
                    visible: modelData.precipRateVisible === true

                    WeatherIcon {
                        iconInfo: IconResolver.resolve("preciprate", 32, root.hostRoot.iconsBaseDir,
                            root.hostRoot.widgetIconTheme === "kde" ? "flat-color" :
                            (root.hostRoot.widgetIconTheme === "wi-font" || root.hostRoot.widgetIconTheme === "custom" || root.hostRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : root.hostRoot.widgetIconTheme)
                        iconSize: 32
                        iconColor: root.hostRoot.themeTextColor
                        opacity: 0.6
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Label {
                        text: modelData.precipRateText || "--"
                        color: root.hostRoot.themeTextColor
                        opacity: 0.6
                        font: root.serviceRoot ? root.serviceRoot.wf(8, false) : Qt.font({})
                    }
                }
            }
        }
    }

    Timer {
        id: scrollTimer
        interval: 0
        onTriggered: root._scrollToAnchor()
    }

    NumberAnimation {
        id: wheelAnimation
        target: hourlyList
        property: "contentX"
        duration: 140
        easing.type: Easing.OutCubic
    }

    MouseArea {
        anchors.fill: hourlyList
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            if (root.hostRoot._hourlyWheelWantsHorizontal(wheel)) {
                var delta = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : root.hostRoot._wheelDeltaX(wheel);
                var pixelDelta = wheel.angleDelta.x === 0 && wheel.pixelDelta.x !== 0;
                if (delta === 0) {
                    delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : root.hostRoot._wheelDeltaY(wheel);
                    pixelDelta = wheel.angleDelta.y === 0 && wheel.pixelDelta.y !== 0;
                }
                var maxX = Math.max(0, hourlyList.contentWidth - hourlyList.width);
                var targetX = pixelDelta
                    ? Math.max(0, Math.min(maxX, hourlyList.contentX - delta))
                    : Math.max(0, Math.min(maxX, hourlyList.contentX - (delta / 120) * root.hostRoot._hourlyCardWidth * 0.8));
                wheelAnimation.to = targetX;
                wheelAnimation.restart();
                wheel.accepted = true;
            } else {
                wheel.accepted = root.hostRoot._scrollParentVertically(wheel);
            }
        }
    }
}
