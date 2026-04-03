/*
 * Copyright 2026  Petar Nedyalkov
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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/**
 * FullView.qml — Main widget popup
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window          // for Screen
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents

import "js/weather.js" as W
import "js/iconResolver.js" as IconResolver
import "components"

Rectangle {
    id: fullView
    property var weatherRoot

    // Layout.preferred* is what Plasma reads to size the panel popup window.
    // width/height are used when the widget sits on the desktop.
    // Compact size when no location is set to avoid overlapping other widgets.
    readonly property bool _hasLocation: weatherRoot && weatherRoot.hasSelectedTown
    Layout.preferredWidth: _hasLocation ? 540 : 280
    Layout.preferredHeight: _hasLocation ? 550 : 220
    width: _hasLocation ? 540 : 280
    height: _hasLocation ? 550 : 220
    clip: true

    // Maximum height: 90% of screen height, but no more than 40 grid units
    readonly property int maxHeight: Math.min(Screen.desktopAvailableHeight * 0.9, Kirigami.Units.gridUnit * 40)

    // Condition icon theme for the hero icon — "kde" uses system icons, others use SVGs
    readonly property string conditionIconTheme: {
        var t = Plasmoid.configuration.conditionIconTheme || "kde";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property url iconsBaseDir: Qt.resolvedUrl("../icons/")

    /** Resolve a condition icon, handling the "custom" theme with per-condition overrides */
    function resolveConditionIcon(code, isNight, iconSize) {
        if (fullView.conditionIconTheme === "custom") {
            var raw = Plasmoid.configuration.widgetConditionCustomIcons || "";
            var m = {};
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        m[kv[0].trim()] = kv[1].trim();
                });
            }
            if (m["condition-custom"] === "1") {
                var condKey;
                if (code === 0)
                    condKey = isNight ? "condition-clear-night" : "condition-clear";
                else if (code === 1)
                    condKey = isNight ? "condition-few-clouds-night" : "condition-few-clouds";
                else if (code === 2)
                    condKey = isNight ? "condition-cloudy-night" : "condition-cloudy-day";
                else if (code === 3)
                    condKey = "condition-overcast";
                else if (code === 45 || code === 48)
                    condKey = "condition-fog";
                else if (code === 51 || code === 53 || code === 55 || code === 61 || code === 80)
                    condKey = isNight ? "condition-showers-scattered-night" : "condition-showers-scattered-day";
                else if (code === 63 || code === 65 || code === 81 || code === 82)
                    condKey = isNight ? "condition-showers-night" : "condition-showers-day";
                else if (code === 56 || code === 66)
                    condKey = isNight ? "condition-freezing-scattered-rain-night" : "condition-freezing-scattered-rain-day";
                else if (code === 57 || code === 67)
                    condKey = isNight ? "condition-freezing-rain-night" : "condition-freezing-rain-day";
                else if (code === 71 || code === 77 || code === 85)
                    condKey = isNight ? "condition-snow-scattered-night" : "condition-snow-scattered-day";
                else if (code === 73 || code === 75 || code === 86)
                    condKey = isNight ? "condition-snow-night" : "condition-snow-day";
                else if (code === 95)
                    condKey = isNight ? "condition-storm-night" : "condition-storm-day";
                else if (code === 96)
                    condKey = isNight ? "condition-hail-storm-rain-night" : "condition-hail-storm-rain-day";
                else if (code === 99)
                    condKey = isNight ? "condition-hail-storm-snow-night" : "condition-hail-storm-snow-day";
                else
                    condKey = isNight ? "condition-clear-night" : "condition-clear";
                var fallback = W.weatherCodeToIcon(code, isNight);
                var saved = (condKey in m && m[condKey].length > 0) ? m[condKey] : fallback;
                return { type: "kde", source: saved, svgFallback: "", isMask: false };
            }
            // condition-custom not set — fall back to KDE icons
            return IconResolver.resolveCondition(code, isNight, iconSize, fullView.iconsBaseDir, "kde");
        }
        return IconResolver.resolveCondition(code, isNight, iconSize, fullView.iconsBaseDir, fullView.conditionIconTheme);
    }

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
    Item {
        anchors.fill: parent
        visible: !weatherRoot || !weatherRoot.hasSelectedTown
        z: 1

        MouseArea {
            anchors.fill: parent
            onClicked: if (weatherRoot)
                weatherRoot.openLocationSettings()
            cursorShape: Qt.PointingHandCursor
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 14

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
                Layout.alignment: Qt.AlignVCenter
            }

            Label {
                Layout.fillWidth: true
                text: Plasmoid.configuration.locationName || ""
                // #2
                color: Kirigami.Theme.textColor
                font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            PlasmaComponents.ToolButton {
                id: pinButton
                checkable: true
                checked: Plasmoid.configuration.keepOpen || false
                icon.name: "window-pin"
                flat: true
                display: AbstractButton.IconOnly
                width: 26
                height: 26
                visible: Plasmoid.formFactor !== 0  // hide on desktop (Planar)
                ToolTip.visible: hovered
                ToolTip.text: checked ? i18n("Unpin widget") : i18n("Keep widget open")
                onToggled: {
                    Plasmoid.configuration.keepOpen = checked;
                }
            }

            ToolButton {
                icon.name: "find-location"
                flat: true
                display: AbstractButton.IconOnly
                width: 22
                height: 22
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
                    font: weatherRoot ? weatherRoot.wf(15, true) : Qt.font({})
                    wrapMode: Text.WordWrap
                    Layout.maximumWidth: 130
                }
                Label {
                    text: weatherRoot ? i18n("Feels like: %1", weatherRoot.tempValue(weatherRoot.apparentC)) : ""
                    color: Kirigami.Theme.textColor
                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                }
            }

            // CENTRE — condition icon enlarged to 120 px (#6)
            WeatherIcon {
                anchors.centerIn: parent
                iconInfo: weatherRoot ? fullView.resolveConditionIcon(
                    weatherRoot.weatherCode, weatherRoot.isNightTime(), 32) : null
                iconSize: 120
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

        // ── Footer: "Updated HH:mm · Weather provider: <link>" ─────────
        Item {
            Layout.preferredHeight: 6
        }
        Label {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showUpdateText !== false && weatherRoot && !weatherRoot.loading && (weatherRoot.updateText || "").length > 0
            text: weatherRoot ? weatherRoot.updateText : ""
            textFormat: Text.RichText
            onLinkActivated: function(link) { Qt.openUrlExternally(link) }
            // #2
            color: Kirigami.Theme.textColor
            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            HoverHandler {
                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }
    }
}
