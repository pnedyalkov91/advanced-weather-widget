/**
 * FullView.qml — Main widget popup
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window          // for Screen
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W

Rectangle {
    id: fullView
    property var weatherRoot

    // Layout.preferred* is what Plasma reads to size the panel popup window.
    // width/height are used when the widget sits on the desktop.
    // 600 px tall: 252 px fixed chrome + 336 px for 4 card-rows (78+8 each).
    Layout.preferredWidth: 540
    Layout.preferredHeight: 550
    width: 540
    height: 550
    clip: true

    // Maximum height: 90% of screen height, but no more than 40 grid units
    readonly property int maxHeight: Math.min(Screen.desktopAvailableHeight * 0.9, Kirigami.Units.gridUnit * 40)

    // Always transparent — Plasma draws the background via backgroundHints
    // (DefaultBackground | ConfigurableBackground set in main.qml).
    // On the desktop the standard Plasma frame is used; in the panel the
    // popup dialog shell provides its own background.  The user can toggle
    // the background on/off with the button that appears in desktop edit mode.
    color: "transparent"

    // Reset to the configured default tab every time the popup opens
    property int activeTab: Plasmoid.configuration.widgetDefaultTab === "forecast" ? 1 : 0

    Connections {
        target: Plasmoid
        function onExpandedChanged() {
            if (Plasmoid.expanded)
                fullView.activeTab = Plasmoid.configuration.widgetDefaultTab === "forecast" ? 1 : 0;
        }
    }

    // ── No-location placeholder ───────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 14
        visible: !weatherRoot || !weatherRoot.hasSelectedTown

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            source: "mark-location"
            width: 64
            height: 64
            opacity: 0.4
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18n("No location set")
            // #2: textColor instead of hardcoded white
            color: Qt.tint(Kirigami.Theme.textColor, Qt.rgba(0, 0, 0, 0))
            opacity: 0.6
            font: weatherRoot ? weatherRoot.wf(14, true) : Qt.font({
                bold: true
            })
        }
        Button {
            Layout.alignment: Qt.AlignHCenter
            text: i18n("Set Location…")
            icon.name: "mark-location"
            onClicked: if (weatherRoot)
                weatherRoot.openLocationSettings()
        }
    }

    // ── Main content ──────────────────────────────────────────────────────
    ColumnLayout {
        id: mainContent
        anchors {
            fill: parent
            topMargin: 14
            leftMargin: 16
            rightMargin: 16
            bottomMargin: 8
        }
        spacing: 0
        visible: weatherRoot && weatherRoot.hasSelectedTown

        // ── Header: location pin + name + detect + refresh ────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Kirigami.Icon {
                source: "mark-location"
                width: 13
                height: 13
                opacity: 0.4
                Layout.alignment: Qt.AlignVCenter
            }

            Label {
                Layout.fillWidth: true
                text: Plasmoid.configuration.locationName || ""
                // #2
                color: Kirigami.Theme.textColor
                opacity: 0.65
                font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            ToolButton {
                icon.name: "find-location"
                flat: true
                display: AbstractButton.IconOnly
                width: 22
                height: 22
                opacity: 0.55
                ToolTip.visible: hovered
                ToolTip.text: i18n("Detect / change location…")
                onClicked: if (weatherRoot)
                    weatherRoot.openLocationSettings()
            }

            Label {
                visible: weatherRoot && weatherRoot.loading
                text: i18n("Updating…")
                // #2
                color: Kirigami.Theme.textColor
                opacity: 0.35
                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
            }

            ToolButton {
                icon.name: "view-refresh"
                enabled: weatherRoot && !weatherRoot.loading
                opacity: enabled ? 0.6 : 0.25
                flat: true
                display: AbstractButton.IconOnly
                width: 26
                height: 26
                ToolTip.visible: hovered
                ToolTip.text: i18n("Refresh")
                onClicked: if (weatherRoot)
                    weatherRoot.refreshWeather()
            }
        }

        Item {
            Layout.preferredHeight: 8
        }

        // ── Hero: three-column layout ─────────────────────────────────
        //   LEFT  — current temperature stack
        //   CENTRE— condition icon 120 px centred  (#6)
        //   RIGHT — today's High / Low             (#7)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 120

            // LEFT — temp + condition + feels-like
            ColumnLayout {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                spacing: 1
                width: 130

                Label {
                    text: weatherRoot ? weatherRoot.tempValue(weatherRoot.temperatureC) : "--"
                    // #2
                    color: Kirigami.Theme.textColor
                    font {
                        pixelSize: Math.round(Kirigami.Units.gridUnit * 3.6)
                        bold: true
                    }
                    minimumPixelSize: 26
                    fontSizeMode: Text.HorizontalFit
                    Layout.maximumWidth: 130
                }
                Label {
                    text: weatherRoot ? weatherRoot.weatherCodeToText(weatherRoot.weatherCode, weatherRoot.isNightTime()) : ""
                    color: Kirigami.Theme.textColor
                    opacity: 0.6
                    font: weatherRoot ? weatherRoot.wf(13, false) : Qt.font({})
                    wrapMode: Text.WordWrap
                    Layout.maximumWidth: 130
                }
                Label {
                    text: weatherRoot ? i18n("Feels like: %1", weatherRoot.tempValue(weatherRoot.apparentC)) : ""
                    color: Kirigami.Theme.textColor
                    opacity: 0.38
                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                }
            }

            // CENTRE — condition icon enlarged to 120 px (#6)
            Kirigami.Icon {
                anchors.centerIn: parent
                source: weatherRoot ? W.weatherCodeToIcon(weatherRoot.weatherCode, weatherRoot.isNightTime()) : "weather-none-available"
                width: 120
                height: 120
                smooth: true
            }

            // RIGHT — today's High / Low (#7)
            ColumnLayout {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                // High
                ColumnLayout {
                    spacing: 1
                    Layout.alignment: Qt.AlignHCenter
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: i18n("High")
                        color: Kirigami.Theme.textColor
                        opacity: 0.45
                        font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: (weatherRoot && weatherRoot.dailyData && weatherRoot.dailyData.length > 0) ? weatherRoot.tempValue(weatherRoot.dailyData[0].maxC) : "--"
                        color: "#ff6e40"
                        font: weatherRoot ? weatherRoot.wf(15, true) : Qt.font({
                            bold: true
                        })
                    }
                }

                // Low
                ColumnLayout {
                    spacing: 1
                    Layout.alignment: Qt.AlignHCenter
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: i18n("Low")
                        color: Kirigami.Theme.textColor
                        opacity: 0.45
                        font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: (weatherRoot && weatherRoot.dailyData && weatherRoot.dailyData.length > 0) ? weatherRoot.tempValue(weatherRoot.dailyData[0].minC) : "--"
                        color: "#42a5f5"
                        font: weatherRoot ? weatherRoot.wf(15, true) : Qt.font({
                            bold: true
                        })
                    }
                }
            }
        }

        Item {
            Layout.preferredHeight: 12
        }

        // ── Tab bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 17
            // #2: tab bar background adapts to theme
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)

            RowLayout {
                anchors {
                    fill: parent
                    margins: 3
                }
                spacing: 0

                Repeater {
                    model: [i18n("Details"), i18n("Forecast")]
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        readonly property bool isActive: fullView.activeTab === index
                        color: isActive ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.17) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }
                        Label {
                            anchors.centerIn: parent
                            text: parent.modelData
                            // #2
                            color: Kirigami.Theme.textColor
                            opacity: parent.isActive ? 1.0 : 0.42
                            font: weatherRoot ? weatherRoot.wf(11, parent.isActive) : Qt.font({
                                bold: parent.isActive
                            })
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 140
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fullView.activeTab = index
                        }
                    }
                }
            }
        }

        Item {
            Layout.preferredHeight: 10
        }

        // ── Tab content ───────────────────────────────────────────────
        StackLayout {
            id: tabContent
            Layout.fillWidth: true
            currentIndex: fullView.activeTab
            // Explicitly follow the current child's implicitHeight
            implicitHeight: currentItem ? currentItem.implicitHeight : 0

            DetailsView {
                id: detailsView
                weatherRoot: fullView.weatherRoot
            }
            ForecastView {
                id: forecastView
                weatherRoot: fullView.weatherRoot
            }
        }

        // ── Footer: "Updated HH:mm (Provider)" ───────────────────────
        Item {
            Layout.preferredHeight: 6
        }
        Label {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showUpdateText !== false && weatherRoot && !weatherRoot.loading && (weatherRoot.updateText || "").length > 0
            text: weatherRoot ? weatherRoot.updateText : ""
            // #2
            color: Kirigami.Theme.textColor
            opacity: 0.32
            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
