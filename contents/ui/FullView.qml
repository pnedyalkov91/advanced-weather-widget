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
import org.kde.plasma.extras as PlasmaExtras

import "js/weather.js" as W
import "js/iconResolver.js" as IconResolver
import "js/configUtils.js" as ConfigUtils
import "components"

Rectangle {
    id: fullView
    property var weatherRoot
    property bool inSystemTray: false

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

    /** Resolve a condition icon, handling the "custom" theme with per-condition overrides.
     *  Delegates to ConfigUtils.resolveCustomConditionIcon() — single source of truth. */
    function resolveConditionIcon(code, isNight, iconSize) {
        return ConfigUtils.resolveCustomConditionIcon(
            code, isNight, iconSize, fullView.iconsBaseDir,
            fullView.conditionIconTheme,
            Plasmoid.configuration.widgetConditionCustomIcons || "",
            W.weatherCodeToIcon, IconResolver.resolveCondition);
    }

    // Always transparent — Plasma draws the background via backgroundHints
    // (DefaultBackground | ConfigurableBackground set in main.qml).
    // On the desktop the standard Plasma frame is used; in the panel the
    // popup dialog shell provides its own background.  The user can toggle
    // the background on/off with the button that appears in desktop edit mode.
    color: "transparent"

    // Header summary cached once per weatherData change — avoids N separate Label
    // bindings each subscribing to individual weatherRoot accessor properties.
    readonly property string _fvTemp:       weatherRoot ? weatherRoot.tempValue(weatherRoot.temperatureC) : "--"
    readonly property string _fvCondition:  weatherRoot ? weatherRoot.weatherCodeToText(weatherRoot.weatherCode, weatherRoot.isNightTime()) : ""
    readonly property string _fvFeelsLike:  weatherRoot ? i18n("Feels like: %1", weatherRoot.tempValue(weatherRoot.apparentC)) : ""
    readonly property string _fvHigh:       (weatherRoot && weatherRoot.dailyData && weatherRoot.dailyData.length > 0) ? weatherRoot.tempValue(weatherRoot.dailyData[0].maxC) : "--"
    readonly property string _fvLow:        (weatherRoot && weatherRoot.dailyData && weatherRoot.dailyData.length > 0) ? weatherRoot.tempValue(weatherRoot.dailyData[0].minC) : "--"
    readonly property var    _fvCondIcon:   weatherRoot ? fullView.resolveConditionIcon(weatherRoot.weatherCode, weatherRoot.isNightTime(), 32) : null

    // Per-tab visibility flags (both visible by default)
    readonly property string visibleTabs: Plasmoid.configuration.widgetVisibleTabs || "both"
    readonly property bool showDetailsTab: visibleTabs === "both" || visibleTabs === "details"
    readonly property bool showForecastTab: visibleTabs === "both" || visibleTabs === "forecast"
    readonly property bool showAnyTab: showDetailsTab || showForecastTab

    // Resolve the default tab, falling back if the preferred tab is hidden.
    // Returns 0 for Details, 1 for Forecast.
    function _resolvedDefaultTab() {
        var want = Plasmoid.configuration.widgetDefaultTab === "forecast" ? 1 : 0;
        if (want === 1 && !fullView.showForecastTab) return fullView.showDetailsTab ? 0 : 0;
        if (want === 0 && !fullView.showDetailsTab) return fullView.showForecastTab ? 1 : 0;
        return want;
    }

    // Reset to the configured default tab every time the popup opens
    property int activeTab: _resolvedDefaultTab()

    // Reset to default tab each time the popup is opened.
    // Plasmoid.expanded is not a signal in Plasma 6; watch it via onExpandedChanged
    // on the root PlasmoidItem (weatherRoot) which IS a PlasmoidItem property.
    Connections {
        target: weatherRoot
        function onExpandedChanged() {
            if (weatherRoot.expanded)
                fullView.activeTab = fullView._resolvedDefaultTab();
        }
    }

    // ── Restore default (starred) location on startup ─────────────────────
    // Runs once after the widget initialises. If the currently active location
    // differs from the starred entry in savedLocations, it switches back.
    property bool _startupRestoreDone: false

    function _restoreDefaultLocation() {
        if (_startupRestoreDone)
            return;
        _startupRestoreDone = true;

        var locs;
        try {
            locs = JSON.parse(Plasmoid.configuration.savedLocations || "[]");
            if (!Array.isArray(locs)) locs = [];
        } catch (e) { return; }

        var starred = null;
        for (var i = 0; i < locs.length; i++) {
            if (locs[i].starred) { starred = locs[i]; break; }
        }
        if (!starred) return;

        var curLat = Plasmoid.configuration.latitude || 0;
        var curLon = Plasmoid.configuration.longitude || 0;
        if (Math.abs(starred.lat - curLat) < 0.01 && Math.abs(starred.lon - curLon) < 0.01)
            return; // already on the default location

        if (weatherRoot)
            weatherRoot.applyLocation(starred);
    }

    // Small delay lets weatherRoot and Plasmoid.configuration fully initialise
    // before the restore runs.
    Timer {
        id: _startupRestoreTimer
        interval: 300
        repeat: false
        onTriggered: fullView._restoreDefaultLocation()
    }

    Component.onCompleted: _startupRestoreTimer.start()

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
            topMargin: fullView.inSystemTray ? 4 : 14
            leftMargin: 16
            rightMargin: 16
            bottomMargin: 8
        }
        spacing: 0
        visible: weatherRoot && weatherRoot.hasSelectedTown

        // ── Header: location pin + name + switcher + detect + refresh ────────────
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
                text: weatherRoot ? (weatherRoot._activeLocName, weatherRoot._locName()) : (Plasmoid.configuration.locationName || "")
                // #2
                color: Kirigami.Theme.textColor
                font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            // ── Location switcher dropdown ────────────────────────────────
            ToolButton {
                id: locationSwitcherBtn
                icon.name: "go-down"
                flat: true
                display: AbstractButton.IconOnly
                width: 20
                height: 20
                visible: {
                    try {
                        var locs = JSON.parse(Plasmoid.configuration.savedLocations || "[]");
                        return Array.isArray(locs) && locs.length > 0;
                    } catch (e) { return false; }
                }
                ToolTip.visible: hovered
                ToolTip.text: i18n("Switch location")
                onClicked: locationMenu.open()

                Menu {
                    id: locationMenu
                    y: locationSwitcherBtn.height

                    // Current location
                    MenuItem {
                        text: (Plasmoid.configuration.locationName || i18n("Current")) + (Plasmoid.configuration.autoDetectLocation ? " (" + i18n("auto") + ")" : "")
                        icon.name: "mark-location"
                        font.bold: true
                        enabled: false
                    }

                    MenuSeparator {}

                    // Saved locations — Repeater works correctly in Qt6 QQC2 Menu;
                    // Instantiator+insertItem breaks onTriggered in Qt6.
                    Repeater {
                        model: {
                            try {
                                var locs = JSON.parse(Plasmoid.configuration.savedLocations || "[]");
                                return Array.isArray(locs) ? locs : [];
                            } catch (e) { return []; }
                        }
                        delegate: MenuItem {
                            required property var modelData
                            required property int index
                            readonly property bool isActive: {
                                var dLat = Math.abs((modelData.lat || 0) - (Plasmoid.configuration.latitude || 0));
                                var dLon = Math.abs((modelData.lon || 0) - (Plasmoid.configuration.longitude || 0));
                                return dLat < 0.01 && dLon < 0.01;
                            }
                            text: modelData.name || i18n("Unknown")
                            icon.name: modelData.starred ? "starred-symbolic" : (isActive ? "dialog-ok-apply" : "go-next")
                            font.bold: isActive
                            onTriggered: {
                                if (weatherRoot)
                                    weatherRoot.applyLocation(modelData);
                            }
                        }
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: i18n("Save current location…")
                        icon.name: "list-add"
                        onTriggered: {
                            var name = Plasmoid.configuration.locationName || "";
                            if (!name) return;
                            var entry = {
                                name: name,
                                lat: Plasmoid.configuration.latitude,
                                lon: Plasmoid.configuration.longitude,
                                altitude: Plasmoid.configuration.altitude || 0,
                                timezone: Plasmoid.configuration.timezone || "",
                                countryCode: Plasmoid.configuration.countryCode || ""
                            };
                            var locs;
                            try {
                                locs = JSON.parse(Plasmoid.configuration.savedLocations || "[]");
                                if (!Array.isArray(locs)) locs = [];
                            } catch (e) { locs = []; }
                            // Avoid duplicates by lat/lon
                            var isDup = false;
                            for (var i = 0; i < locs.length; i++) {
                                if (Math.abs(locs[i].lat - entry.lat) < 0.01 && Math.abs(locs[i].lon - entry.lon) < 0.01) {
                                    isDup = true;
                                    break;
                                }
                            }
                            if (!isDup) {
                                locs.push(entry);
                                Plasmoid.configuration.savedLocations = JSON.stringify(locs);
                            }
                        }
                    }
                }
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
                visible: !fullView.inSystemTray && Plasmoid.formFactor !== 0  // hide on desktop (Planar) and in tray (Plasma's own pin is in native header)
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
                visible: !fullView.inSystemTray
                ToolTip.visible: hovered
                ToolTip.text: i18n("Detect / change location…")
                onClicked: if (weatherRoot)
                    weatherRoot.openLocationSettings()
            }

            Label {
                visible: !fullView.inSystemTray && weatherRoot && weatherRoot.loading
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
                visible: !fullView.inSystemTray
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
                    text: fullView._fvTemp
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
                    text: fullView._fvCondition
                    color: Kirigami.Theme.textColor
                    font: weatherRoot ? weatherRoot.wf(15, true) : Qt.font({})
                    wrapMode: Text.WordWrap
                    Layout.maximumWidth: 130
                }
                Label {
                    text: fullView._fvFeelsLike
                    color: Kirigami.Theme.textColor
                    font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                }
            }

            // CENTRE — condition icon enlarged to 120 px (#6)
            WeatherIcon {
                anchors.centerIn: parent
                iconInfo: fullView._fvCondIcon
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
                        text: fullView._fvHigh
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
                        text: fullView._fvLow
                        color: "#42a5f5"
                        font: weatherRoot ? weatherRoot.wf(15, true) : Qt.font({
                            bold: true
                        })
                    }
                }
            }
        }

        Item {
            Layout.preferredHeight: (fullView.showDetailsTab && fullView.showForecastTab) ? 12 : 0
        }

        // ── Tab bar — only shown when both tabs are enabled ────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 17
            visible: fullView.showDetailsTab && fullView.showForecastTab
            // #2: tab bar background adapts to theme
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)

            RowLayout {
                anchors {
                    fill: parent
                    margins: 3
                }
                spacing: 0

                Repeater {
                    model: {
                        var tabs = [];
                        if (fullView.showDetailsTab) tabs.push({ label: i18n("Details"), logicalIdx: 0 });
                        if (fullView.showForecastTab) tabs.push({ label: i18n("Forecast"), logicalIdx: 1 });
                        return tabs;
                    }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        readonly property bool isActive: fullView.activeTab === modelData.logicalIdx
                        color: isActive ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.17) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }
                        Label {
                            anchors.centerIn: parent
                            text: parent.modelData.label
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
                            onClicked: fullView.activeTab = modelData.logicalIdx
                        }
                    }
                }
            }
        }

        Item {
            Layout.preferredHeight: (fullView.showDetailsTab && fullView.showForecastTab) ? 10 : 0
        }

        // ── Tab content ───────────────────────────────────────────────
        StackLayout {
            id: tabContent
            Layout.fillWidth: true
            visible: fullView.showAnyTab
            currentIndex: fullView.activeTab
            // Explicitly follow the current child's implicitHeight
            implicitHeight: (children && children[currentIndex]) ? children[currentIndex].implicitHeight : 0

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
