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
 * ConfigAlertsTab.qml - Weather Alerts tab content
 *
 * Extracted from configGeneral.qml for readability.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: alertsTab

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    spacing: Kirigami.Units.smallSpacing * 2

    /** Reference to the root KCM (configGeneral) for cfg_* properties */
    required property var configRoot

    // Section title with a thin rule, same look as the Notifications page.
    component SectionHeader: RowLayout {
        required property string title
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: parent.title
            font.bold: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.5
        }
    }

    // A Switch whose label wraps onto several lines instead of forcing the
    // whole page wider than the (resizable) settings window.
    component WrappingSwitch: Switch {
        id: wrappingSwitch
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        contentItem: Label {
            text: wrappingSwitch.text
            font: wrappingSwitch.font
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            leftPadding: wrappingSwitch.indicator && !wrappingSwitch.mirrored
                ? wrappingSwitch.indicator.width + wrappingSwitch.spacing : 0
            rightPadding: wrappingSwitch.indicator && wrappingSwitch.mirrored
                ? wrappingSwitch.indicator.width + wrappingSwitch.spacing : 0
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // SECTION: Weather Alerts
    // ═══════════════════════════════════════════════════════════════
    SectionHeader {
        title: i18n("Weather Alerts Provider")
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Label {
            text: i18n("Alerts provider:")
        }

        ComboBox {
            id: alertsProviderCombo
            Layout.preferredWidth: 280
            model: [
                {
                    text: i18n("MeteoAlarm + NOAA NWS (Native)"),
                    value: "native"
                },
                {
                    text: i18n("LibreWXR"),
                    value: "librewxr"
                },
                {
                    text: i18n("FOSS Public Alert Server"),
                    value: "foss"
                }
            ]
            textRole: "text"
            currentIndex: {
                for (var i = 0; i < model.length; i++)
                    if (model[i].value === alertsTab.configRoot.cfg_alertsProvider)
                        return i;
                return 0;
            }
            onActivated: alertsTab.configRoot.cfg_alertsProvider = model[currentIndex].value
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "native"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://www.meteoalarm.org/'>EUMETNET MeteoAlarm</a> + <a href='https://www.weather.gov/'>NOAA NWS</a><br/><br/>" + "European locations use the official MeteoAlarm feeds (38 countries), US locations use the NOAA National Weather Service alerts API, with met.no MetAlerts as a fallback. If your weather provider delivers its own alerts (e.g. WeatherAPI.com, Pirate Weather), those are used directly.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "librewxr"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://librewxr.net/'>LibreWXR</a><br/><br/>" + "LibreWXR is a free, open-source weather API that aggregates official CAP alerts worldwide (WMO Severe Weather Information Centre, NOAA NWS, and others) and matches them to your exact location. Alert notifications work the same as with the native provider.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "foss"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://alerts.kde.org/'>FOSS Public Alert Server</a><br/><br/>" + "KDE's FOSS Public Alert Server collects official severe-weather warnings in CAP format from agencies worldwide and matches them to your exact location. Alert notifications work the same as with the native provider.")
        onLinkActivated: Qt.openUrlExternally(link)
    }
}
