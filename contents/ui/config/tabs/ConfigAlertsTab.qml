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

GridLayout {
    id: alertsTab

    Layout.fillWidth: true
    // children with a maximum width would otherwise cap the grid itself and make
    // it flip between one and two columns
    Layout.maximumWidth: Number.POSITIVE_INFINITY
    Layout.alignment: Qt.AlignTop
    // Label and control on one line when there is room (like the wide mode of
    // Kirigami.FormLayout); the label goes above its control in a narrow window.
    columns: width >= Kirigami.Units.gridUnit * 30 ? 2 : 1
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: columns === 1 ? Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing * 2

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

    // ═══════════════════════════════════════════════════════════════
    // SECTION: Weather Alerts
    // ═══════════════════════════════════════════════════════════════
    SectionHeader {
        title: i18n("Weather Alerts Provider")
        Layout.columnSpan: alertsTab.columns
    }

    Label {
        text: i18n("Alerts provider:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: alertsTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
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

    Kirigami.InlineMessage {
        Layout.columnSpan: alertsTab.columns
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "native"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://www.meteoalarm.org/'>EUMETNET MeteoAlarm</a> + <a href='https://www.weather.gov/'>NOAA NWS</a><br/><br/>" + "European locations use the official MeteoAlarm feeds (38 countries), US locations use the NOAA National Weather Service alerts API, with met.no MetAlerts as a fallback. If your weather provider delivers its own alerts (e.g. WeatherAPI.com, Pirate Weather), those are used directly.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: alertsTab.columns
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "librewxr"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://librewxr.net/'>LibreWXR</a><br/><br/>" + "LibreWXR is a free, open-source weather API that aggregates official CAP alerts worldwide (WMO Severe Weather Information Centre, NOAA NWS, and others) and matches them to your exact location. Alert notifications work the same as with the native provider.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: alertsTab.columns
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "foss"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://alerts.kde.org/'>FOSS Public Alert Server</a><br/><br/>" + "KDE's FOSS Public Alert Server collects official severe-weather warnings in CAP format from agencies worldwide and matches them to your exact location. Alert notifications work the same as with the native provider.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    // Invisible filler row: it lets the second column take ALL spare width, so the
    // label column keeps its width when rows are shown or hidden.
    Item { visible: alertsTab.columns === 2; implicitWidth: 0; implicitHeight: 0 }
    Item { visible: alertsTab.columns === 2; Layout.fillWidth: true; implicitWidth: 0; implicitHeight: 0 }
}
