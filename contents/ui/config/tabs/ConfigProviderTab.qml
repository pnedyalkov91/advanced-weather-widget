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
 * ConfigProviderTab.qml - Weather Provider + Data Refresh tab content
 *
 * Extracted from configGeneral.qml for readability.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

GridLayout {
    id: providerTab

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

    /** Reference to the root KCM (configGeneral) for cfg_* properties, functions and state */
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
    // SECTION: Weather Provider
    // ═══════════════════════════════════════════════════════════════
    SectionHeader {
        title: i18n("Weather Provider")
        Layout.columnSpan: providerTab.columns
    }

    // The single place that flips Adaptive on/off. Both the Switch and its
    // clickable label go through here. The label used to call
    // adaptiveSwitch.toggle(), which changes `checked` WITHOUT emitting
    // toggled() - so clicking the label moved the switch but never updated
    // cfg_weatherProvider, leaving the switch showing "off" while Adaptive was
    // still actually on (and the provider combo stuck read-only).
    function setAdaptive(on) {
        if (on) {
            providerTab.configRoot.cfg_weatherProvider = "adaptive";
        } else {
            // Restore whatever provider was manually selected before Adaptive
            // was turned on, instead of always resetting to Open-Meteo.
            var restore = providerTab.configRoot.cfg_lastManualProvider;
            if (!restore || restore === "adaptive")
                restore = "openMeteo";
            providerTab.configRoot.cfg_weatherProvider = restore;
            // No need to touch providerCombo.currentIndex here: its binding
            // follows cfg_weatherProvider by itself, and assigning it from JS
            // would permanently break that binding.
        }
    }

    // Adaptive toggle row
    RowLayout {
        Layout.columnSpan: providerTab.columns
        spacing: 12
        Switch {
            id: adaptiveSwitch
            checked: providerTab.configRoot.isAdaptive
            onToggled: providerTab.setAdaptive(checked)
        }
        Label {
            text: i18n("Adaptive (auto-fallback)")
            font.bold: true
            verticalAlignment: Text.AlignVCenter
            MouseArea {
                anchors.fill: parent
                // Drive the config value directly (not the switch) - the
                // switch's own binding then follows isAdaptive.
                onClicked: providerTab.setAdaptive(!providerTab.configRoot.isAdaptive)
            }
        }
    }

    // Adaptive description - shown only when Adaptive is ON
    Kirigami.InlineMessage {
        Layout.columnSpan: providerTab.columns
        Layout.fillWidth: true
        visible: providerTab.configRoot.isAdaptive
        type: Kirigami.MessageType.Information
        text: i18n("Providers are tried in order until one succeeds:\nOpen-Meteo  →  BBC Weather  →  met.no  →  Pirate Weather  →  Visual Crossing  →  Tomorrow.io  →  StormGlass  →  Weatherbit  →  QWeather  →  OpenWeatherMap  →  WeatherAPI.com\n If you want to choose a specific provider, please turn off Adaptive Mode.\nOpen-Meteo is always tried first - it is free and requires no API key. AEMET is intentionally not part of this list, as it only covers Spain and is not suitable for global use.")
    }

    // Manual provider selector - always visible now; read-only (disabled)
    // while Adaptive is ON instead of being hidden.
    Label {
        text: i18n("Provider:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: providerTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: providerCombo
        Layout.preferredWidth: 280
        model: providerTab.configRoot.providerModel
        textRole: "text"
        enabled: !providerTab.configRoot.isAdaptive
        opacity: enabled ? 1.0 : 0.6
        // While Adaptive is on, cfg_weatherProvider is "adaptive" itself (not
        // one of this combo's own values), so show the last manually-chosen
        // provider instead - the one Adaptive off will restore.
        currentIndex: providerTab.configRoot.providerIndexFor(providerTab.configRoot.isAdaptive ? (providerTab.configRoot.cfg_lastManualProvider || "openMeteo") : providerTab.configRoot.cfg_weatherProvider)
        onActivated: {
            providerTab.configRoot.cfg_weatherProvider = providerTab.configRoot.providerModel[currentIndex].value;
            providerTab.configRoot.apiTestState = 0;
            providerTab.configRoot.locationCheckState = 0;
            providerTab.configRoot.verifyProviderLocation();
        }
    }

    Item {
        // empty label cell: keeps the control in the second column
        visible: providerTab.columns === 2 && (providerTab.configRoot.isAdaptive)
        implicitWidth: 0
        implicitHeight: 0
    }
    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: providerTab.configRoot.isAdaptive
        text: i18n("Read-only while Adaptive mode is on - turn it off above to choose a specific provider.")
        opacity: 0.65
        font: Kirigami.Theme.smallFont
    }

    // Provider sub-label
    Item {
        // empty label cell: keeps the control in the second column
        visible: providerTab.columns === 2 && (providerTab.configRoot.isAdaptive === false)
        implicitWidth: 0
        implicitHeight: 0
    }
    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: providerTab.configRoot.isAdaptive === false
        opacity: 0.6
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        textFormat: Text.RichText
        onLinkActivated: function (link) {
            Qt.openUrlExternally(link);
        }
        text: {
            if (providerTab.configRoot.isOpenWeather)
                return i18n("Standard provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://openweathermap.org'>openweathermap.org</a>";
            if (providerTab.configRoot.isWeatherApi)
                return i18n("Alternative provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.weatherapi.com'>weatherapi.com</a>";
            if (providerTab.configRoot.isPirateWeather)
                return i18n("Dark Sky-compatible API with US alerts. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://pirateweather.net'>pirateweather.net</a>";
            if (providerTab.configRoot.isVisualCrossing)
                return i18n("Historical and forecast data provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.visualcrossing.com'>visualcrossing.com</a>";
            if (providerTab.configRoot.isTomorrowIo)
                return i18n("AI-powered weather intelligence. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.tomorrow.io'>tomorrow.io</a>";
            if (providerTab.configRoot.isStormGlass)
                return i18n("Marine and weather data provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://stormglass.io'>stormglass.io</a>";
            if (providerTab.configRoot.isWeatherbit)
                return i18n("High precision forecast provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.weatherbit.io'>weatherbit.io</a>";
            if (providerTab.configRoot.isQWeather)
                return i18n("Chinese weather provider with global coverage. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.qweather.com'>qweather.com</a>";
            if (providerTab.configRoot.isAemet)
                return i18n("Official Spanish meteorological agency - Spain locations only! API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.aemet.es'>aemet.es</a>";
            if (providerTab.configRoot.cfg_weatherProvider === "metno")
                return i18n("Free Norwegian Meteorological Institute service. No API key needed.") + "<br/>" + i18n("Provider website:") + " <a href='https://met.no'>met.no</a>";
            if (providerTab.configRoot.cfg_weatherProvider === "bbc")
                return i18n("Free BBC Weather service (data from the Met Office). No API key needed.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.bbc.com/weather'>bbc.com/weather</a>";
            return i18n("Free and open-source. No API key needed. Recommended.") + "<br/>" + i18n("Provider website:") + " <a href='https://open-meteo.com'>open-meteo.com</a>";
        }
        HoverHandler {
            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: providerTab.columns
        Layout.fillWidth: true
        visible: providerTab.configRoot.locationCheckState === 2
        type: Kirigami.MessageType.Positive
        text: providerTab.configRoot.locationCheckMessage
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: providerTab.columns
        Layout.fillWidth: true
        visible: providerTab.configRoot.locationCheckState === 3
        type: Kirigami.MessageType.Error
        text: providerTab.configRoot.locationCheckMessage
    }

    // ── API Key section ───────────────────────────────────────
    // Shown only when OpenWeather or WeatherAPI (or another key-requiring
    // provider) is selected
    Label {
        text: {
            if (providerTab.configRoot.isOpenWeather)
                return i18n("OpenWeatherMap API Key:");
            if (providerTab.configRoot.isPirateWeather)
                return i18n("Pirate Weather API Key:");
            if (providerTab.configRoot.isVisualCrossing)
                return i18n("Visual Crossing API Key:");
            if (providerTab.configRoot.isTomorrowIo)
                return i18n("Tomorrow.io API Key:");
            if (providerTab.configRoot.isStormGlass)
                return i18n("StormGlass API Key:");
            if (providerTab.configRoot.isWeatherbit)
                return i18n("Weatherbit API Key:");
            if (providerTab.configRoot.isQWeather)
                return i18n("QWeather API Key:");
            if (providerTab.configRoot.isAemet)
                return i18n("AEMET API Key:");
            return i18n("WeatherAPI.com API Key:");
        }
        visible: providerTab.configRoot.needsKeyUi && !providerTab.configRoot.isAdaptive
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        Layout.topMargin: providerTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: providerTab.configRoot.needsKeyUi && !providerTab.configRoot.isAdaptive

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: apiKeyField
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                placeholderText: {
                    if (providerTab.configRoot.isOpenWeather)
                        return i18n("Enter your OpenWeatherMap API key");
                    if (providerTab.configRoot.isPirateWeather)
                        return i18n("Enter your Pirate Weather API key");
                    if (providerTab.configRoot.isVisualCrossing)
                        return i18n("Enter your Visual Crossing API key");
                    if (providerTab.configRoot.isTomorrowIo)
                        return i18n("Enter your Tomorrow.io API key");
                    if (providerTab.configRoot.isStormGlass)
                        return i18n("Enter your StormGlass API key");
                    if (providerTab.configRoot.isWeatherbit)
                        return i18n("Enter your Weatherbit API key");
                    if (providerTab.configRoot.isQWeather)
                        return i18n("Enter your QWeather API key");
                    if (providerTab.configRoot.isAemet)
                        return i18n("Enter your AEMET API key");
                    return i18n("Enter your WeatherAPI.com key");
                }
                text: {
                    if (providerTab.configRoot.isOpenWeather)
                        return providerTab.configRoot.cfg_owApiKey;
                    if (providerTab.configRoot.isPirateWeather)
                        return providerTab.configRoot.cfg_pwApiKey;
                    if (providerTab.configRoot.isVisualCrossing)
                        return providerTab.configRoot.cfg_vcApiKey;
                    if (providerTab.configRoot.isTomorrowIo)
                        return providerTab.configRoot.cfg_tioApiKey;
                    if (providerTab.configRoot.isStormGlass)
                        return providerTab.configRoot.cfg_sgApiKey;
                    if (providerTab.configRoot.isWeatherbit)
                        return providerTab.configRoot.cfg_wbApiKey;
                    if (providerTab.configRoot.isQWeather)
                        return providerTab.configRoot.cfg_qwApiKey;
                    if (providerTab.configRoot.isAemet)
                        return providerTab.configRoot.cfg_aemetApiKey;
                    return providerTab.configRoot.cfg_waApiKey;
                }
                echoMode: TextInput.Password
                selectByMouse: true
                onTextEdited: {
                    providerTab.configRoot.apiTestState = 0;
                    if (providerTab.configRoot.isOpenWeather)
                        providerTab.configRoot.cfg_owApiKey = text;
                    else if (providerTab.configRoot.isPirateWeather)
                        providerTab.configRoot.cfg_pwApiKey = text;
                    else if (providerTab.configRoot.isVisualCrossing)
                        providerTab.configRoot.cfg_vcApiKey = text;
                    else if (providerTab.configRoot.isTomorrowIo)
                        providerTab.configRoot.cfg_tioApiKey = text;
                    else if (providerTab.configRoot.isStormGlass)
                        providerTab.configRoot.cfg_sgApiKey = text;
                    else if (providerTab.configRoot.isWeatherbit)
                        providerTab.configRoot.cfg_wbApiKey = text;
                    else if (providerTab.configRoot.isQWeather)
                        providerTab.configRoot.cfg_qwApiKey = text;
                    else if (providerTab.configRoot.isAemet)
                        providerTab.configRoot.cfg_aemetApiKey = text;
                    else
                        providerTab.configRoot.cfg_waApiKey = text;
                }
                onEditingFinished: {
                    if (providerTab.configRoot.isOpenWeather)
                        providerTab.configRoot.cfg_owApiKey = text.trim();
                    else if (providerTab.configRoot.isPirateWeather)
                        providerTab.configRoot.cfg_pwApiKey = text.trim();
                    else if (providerTab.configRoot.isVisualCrossing)
                        providerTab.configRoot.cfg_vcApiKey = text.trim();
                    else if (providerTab.configRoot.isTomorrowIo)
                        providerTab.configRoot.cfg_tioApiKey = text.trim();
                    else if (providerTab.configRoot.isStormGlass)
                        providerTab.configRoot.cfg_sgApiKey = text.trim();
                    else if (providerTab.configRoot.isWeatherbit)
                        providerTab.configRoot.cfg_wbApiKey = text.trim();
                    else if (providerTab.configRoot.isQWeather)
                        providerTab.configRoot.cfg_qwApiKey = text.trim();
                    else if (providerTab.configRoot.isAemet)
                        providerTab.configRoot.cfg_aemetApiKey = text.trim();
                    else
                        providerTab.configRoot.cfg_waApiKey = text.trim();
                }
            }

            ToolButton {
                icon.name: "view-visible"
                checkable: true
                onCheckedChanged: apiKeyField.echoMode = checked ? TextInput.Normal : TextInput.Password
                ToolTip.text: i18n("Show/hide key")
                ToolTip.visible: hovered
            }

            Button {
                text: i18n("Clear")
                icon.name: "edit-clear"
                visible: apiKeyField.text.length > 0
                onClicked: {
                    apiKeyField.text = "";
                    providerTab.configRoot.apiTestState = 0;
                    if (providerTab.configRoot.isOpenWeather)
                        providerTab.configRoot.cfg_owApiKey = "";
                    else if (providerTab.configRoot.isPirateWeather)
                        providerTab.configRoot.cfg_pwApiKey = "";
                    else if (providerTab.configRoot.isVisualCrossing)
                        providerTab.configRoot.cfg_vcApiKey = "";
                    else if (providerTab.configRoot.isTomorrowIo)
                        providerTab.configRoot.cfg_tioApiKey = "";
                    else if (providerTab.configRoot.isStormGlass)
                        providerTab.configRoot.cfg_sgApiKey = "";
                    else if (providerTab.configRoot.isWeatherbit)
                        providerTab.configRoot.cfg_wbApiKey = "";
                    else if (providerTab.configRoot.isQWeather)
                        providerTab.configRoot.cfg_qwApiKey = "";
                    else if (providerTab.configRoot.isAemet)
                        providerTab.configRoot.cfg_aemetApiKey = "";
                    else
                        providerTab.configRoot.cfg_waApiKey = "";
                }
            }

            Button {
                text: providerTab.configRoot.apiTestState === 1 ? i18n("Testing…") : i18n("Test API Key")
                icon.name: "network-connect"
                enabled: apiKeyField.text.trim().length > 0 && providerTab.configRoot.apiTestState !== 1
                onClicked: providerTab.configRoot.testApiKey(apiKeyField.text)
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: providerTab.configRoot.needsKeyUi && !providerTab.configRoot.isAdaptive && apiKeyField.text.trim().length === 0
            type: Kirigami.MessageType.Warning
            text: {
                var pLabel = providerTab.configRoot.providerDisplayName(providerTab.configRoot.cfg_weatherProvider);
                return i18n("An API key is required for %1. Weather data cannot be retrieved without it.", pLabel);
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: providerTab.configRoot.apiTestState === 2
            type: Kirigami.MessageType.Positive
            text: providerTab.configRoot.apiTestMessage
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: providerTab.configRoot.apiTestState === 3
            type: Kirigami.MessageType.Error
            text: providerTab.configRoot.apiTestMessage
        }
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: providerTab.columns
        Layout.fillWidth: true
        visible: providerTab.configRoot.isOpenWeather && !providerTab.configRoot.isAdaptive && apiKeyField.text.trim().length > 0
        type: Kirigami.MessageType.Information
        showCloseButton: true
        text: i18n("If you have just registered a new OpenWeatherMap API key, it might take up to 2 hours for it to become active. Please try again later if it doesn't work immediately.")
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: providerTab.columns
        Layout.fillWidth: true
        visible: providerTab.configRoot.isAemet && !providerTab.configRoot.isAdaptive
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("AEMET only covers locations in Spain - other locations show \"Failed\" rather than switching provider (it's intentionally left out of Adaptive Mode too, since it's the one provider here with its own request limit). There is a limit on the number of requests to the AEMET API per minute, so don't click the refresh button too many times, as you may hit the limit and have to wait at least 1 minute before making another request.A failed request retries automatically once.<br/><br/>Fields AEMET doesn't publish at all - pressure, visibility, snow cover, and a daily accumulated precipitation total - show as \"N/A\" here rather than a bug. UV is a daily figure only, not hour-by-hour, and wind can be missing for days further out where AEMET's own forecast confidence drops off.<br/><br/>Free key: <a href='https://opendata.aemet.es/centrodedescargas/altaUsuario'>opendata.aemet.es</a>. New keys expire 3 months after creation (AEMET's policy, changed July 2026) - you'll need to request a new one when that happens.<br/><br/>Please don't refresh too often, as AEMET has a request limit per minute. If you hit it, you'll have to wait at least 1 minute before making another request.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    // ── QWeather API Host section ─────────────────────────────
    Label {
        text: i18n("QWeather API Host:")
        visible: providerTab.configRoot.isQWeather && !providerTab.configRoot.isAdaptive
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        Layout.topMargin: providerTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: providerTab.configRoot.isQWeather && !providerTab.configRoot.isAdaptive

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Each QWeather project has a unique API host. Find yours at console.qweather.com under your project settings.")
        }
        TextField {
            id: qwHostField
            Layout.fillWidth: true
            placeholderText: "https://xxxxx.re.qweatherapi.com"
            text: providerTab.configRoot.cfg_qwApiHost
            selectByMouse: true
            onTextEdited: providerTab.configRoot.cfg_qwApiHost = text
            onEditingFinished: providerTab.configRoot.cfg_qwApiHost = text.trim()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // SECTION: Data Refresh
    // ═══════════════════════════════════════════════════════════════
    SectionHeader {
        title: i18n("Data Refresh")
        Layout.columnSpan: providerTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
    }

    Switch {
        Layout.columnSpan: providerTab.columns
        text: i18n("Refresh weather automatically")
        checked: providerTab.configRoot.cfg_autoRefresh
        onToggled: providerTab.configRoot.cfg_autoRefresh = checked
    }

    Label {
        text: i18n("Interval:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: providerTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        spacing: 8
        enabled: providerTab.configRoot.cfg_autoRefresh
        opacity: providerTab.configRoot.cfg_autoRefresh ? 1.0 : 0.5

        SpinBox {
            from: 5
            to: 180
            value: providerTab.configRoot.cfg_refreshIntervalMinutes
            onValueModified: providerTab.configRoot.cfg_refreshIntervalMinutes = value
        }
        Label {
            text: i18n("minutes")
        }
    }
}
