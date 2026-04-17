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

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: root

    // ── Config properties ─────────────────────────────────────────────────
    property string cfg_weatherProvider: "adaptive"
    property string cfg_owApiKey: ""
    property string cfg_waApiKey: ""
    property string cfg_pwApiKey: ""
    property string cfg_vcApiKey: ""
    property string cfg_tioApiKey: ""
    property string cfg_sgApiKey: ""
    property string cfg_wbApiKey: ""
    property string cfg_qwApiKey: ""
    property bool cfg_autoRefresh: true
    property int cfg_refreshIntervalMinutes: 15

    // ── Legacy props — keep bound so KCM doesn't lose them ────────────────
    property bool cfg_showScrollbox: true
    property int cfg_scrollboxLines: 2
    property string cfg_scrollboxItems: "Humidity;Wind;Pressure;Dew Point;Visibility"
    property bool cfg_animateTransitions: true

    // ── Derived state ─────────────────────────────────────────────────────
    readonly property bool isAdaptive: cfg_weatherProvider === "adaptive"
    readonly property bool isOpenWeather: cfg_weatherProvider === "openWeather"
    readonly property bool isWeatherApi: cfg_weatherProvider === "weatherApi"
    readonly property bool isPirateWeather: cfg_weatherProvider === "pirateWeather"
    readonly property bool isVisualCrossing: cfg_weatherProvider === "visualCrossing"
    readonly property bool isTomorrowIo: cfg_weatherProvider === "tomorrowIo"
    readonly property bool isStormGlass: cfg_weatherProvider === "stormGlass"
    readonly property bool isWeatherbit: cfg_weatherProvider === "weatherbit"
    readonly property bool isQWeather: cfg_weatherProvider === "qWeather"
    readonly property bool needsKeyUi: isOpenWeather || isWeatherApi || isPirateWeather || isVisualCrossing || isTomorrowIo || isStormGlass || isWeatherbit || isQWeather

    // ── API key test state ────────────────────────────────────────────────
    // 0 = idle, 1 = testing, 2 = success, 3 = error
    property int apiTestState: 0
    property string apiTestMessage: ""
    property int _testGen: 0

    // ── Provider location check state ─────────────────────────────────
    // 0 = idle, 1 = checking, 2 = ok, 3 = error
    property int locationCheckState: 0
    property string locationCheckMessage: ""
    property int _locGen: 0

    function verifyProviderLocation() {
        _locGen++;
        var myGen = _locGen;
        var lat = Plasmoid.configuration.latitude;
        var lon = Plasmoid.configuration.longitude;
        if (!lat && !lon) {
            locationCheckState = 0;
            return;
        }
        var provider = cfg_weatherProvider;
        if (provider === "adaptive" || provider === "openMeteo") {
            locationCheckState = 0;
            return;  // Open-Meteo/adaptive always works
        }
        locationCheckState = 1;
        locationCheckMessage = i18n("Checking location availability…");

        var req = new XMLHttpRequest();
        var url;
        if (provider === "openWeather") {
            var owKey = (cfg_owApiKey || "").trim();
            if (!owKey) { locationCheckState = 0; return; }
            url = "https://api.openweathermap.org/data/2.5/weather?lat="
                + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon)
                + "&units=metric&appid=" + encodeURIComponent(owKey);
        } else if (provider === "weatherApi") {
            var waKey = (cfg_waApiKey || "").trim();
            if (!waKey) { locationCheckState = 0; return; }
            url = "https://api.weatherapi.com/v1/current.json?key="
                + encodeURIComponent(waKey)
                + "&q=" + encodeURIComponent(lat + "," + lon);
        } else if (provider === "pirateWeather") {
            var pwKey = (cfg_pwApiKey || "").trim();
            if (!pwKey) { locationCheckState = 0; return; }
            url = "https://api.pirateweather.net/forecast/"
                + encodeURIComponent(pwKey) + "/"
                + lat + "," + lon
                + "?units=ca&exclude=minutely,hourly,daily,alerts";
        } else if (provider === "visualCrossing") {
            var vcKey = (cfg_vcApiKey || "").trim();
            if (!vcKey) { locationCheckState = 0; return; }
            url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/"
                + lat + "," + lon + "?key=" + encodeURIComponent(vcKey)
                + "&unitGroup=metric&include=current";
        } else if (provider === "tomorrowIo") {
            var tioKey = (cfg_tioApiKey || "").trim();
            if (!tioKey) { locationCheckState = 0; return; }
            url = "https://api.tomorrow.io/v4/weather/realtime?location="
                + lat + "," + lon + "&units=metric&apikey=" + encodeURIComponent(tioKey);
        } else if (provider === "stormGlass") {
            var sgKey = (cfg_sgApiKey || "").trim();
            if (!sgKey) { locationCheckState = 0; return; }
            url = "https://api.stormglass.io/v2/weather/point?lat="
                + encodeURIComponent(lat) + "&lng=" + encodeURIComponent(lon)
                + "&params=airTemperature";
        } else if (provider === "weatherbit") {
            var wbKey = (cfg_wbApiKey || "").trim();
            if (!wbKey) { locationCheckState = 0; return; }
            url = "https://api.weatherbit.io/v2.0/current?lat="
                + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon)
                + "&key=" + encodeURIComponent(wbKey) + "&units=M";
        } else if (provider === "metno") {
            url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat="
                + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon);
        } else if (provider === "qWeather") {
            var qwKey = (cfg_qwApiKey || "").trim();
            if (!qwKey) { locationCheckState = 0; return; }
            var qwLoc = encodeURIComponent(lon.toFixed(2) + "," + lat.toFixed(2));
            url = "https://devapi.qweather.com/v7/weather/now?location=" + qwLoc
                + "&key=" + encodeURIComponent(qwKey) + "&unit=m";
        } else {
            locationCheckState = 0;
            return;
        }
        req.open("GET", url);
        if (provider === "metno")
            req.setRequestHeader("User-Agent",
                "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
        if (provider === "stormGlass")
            req.setRequestHeader("Authorization", (cfg_sgApiKey || "").trim());
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (_locGen !== myGen) return;
            var pLabel = root.providerDisplayName(provider);
            if (req.status === 200) {
                locationCheckState = 2;
                locationCheckMessage = i18n("Location is available on %1.", pLabel);
            } else {
                locationCheckState = 3;
                locationCheckMessage = i18n("Location is not available on %1 (HTTP %2). Try a different provider or location.", pLabel, req.status);
            }
        };
        req.send();
    }

    function providerDisplayName(p) {
        if (p === "openWeather") return "OpenWeatherMap";
        if (p === "weatherApi") return "WeatherAPI.com";
        if (p === "metno") return "met.no";
        if (p === "pirateWeather") return "Pirate Weather";
        if (p === "visualCrossing") return "Visual Crossing";
        if (p === "tomorrowIo") return "Tomorrow.io";
        if (p === "stormGlass") return "StormGlass";
        if (p === "weatherbit") return "Weatherbit";
        if (p === "qWeather") return "QWeather";
        return "Open-Meteo";
    }

    function testApiKey() {
        _testGen++;
        var myGen = _testGen;
        var key = apiKeyField.text.trim();
        if (!key) {
            apiTestState = 3;
            apiTestMessage = i18n("API key is empty.");
            return;
        }
        apiTestState = 1;
        apiTestMessage = i18n("Testing connection…");

        var req = new XMLHttpRequest();
        var url;
        var useAuthHeader = false;
        if (root.isOpenWeather) {
            url = "https://api.openweathermap.org/data/2.5/weather?lat=42.7&lon=23.3&units=metric&appid="
                + encodeURIComponent(key);
        } else if (root.isPirateWeather) {
            url = "https://api.pirateweather.net/forecast/"
                + encodeURIComponent(key) + "/42.7,23.3"
                + "?units=ca&exclude=minutely,hourly,daily,alerts";
        } else if (root.isVisualCrossing) {
            url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/42.7,23.3"
                + "?key=" + encodeURIComponent(key) + "&unitGroup=metric&include=current";
        } else if (root.isTomorrowIo) {
            url = "https://api.tomorrow.io/v4/weather/realtime?location=42.7,23.3&units=metric&apikey="
                + encodeURIComponent(key);
        } else if (root.isStormGlass) {
            url = "https://api.stormglass.io/v2/weather/point?lat=42.7&lng=23.3&params=airTemperature";
            useAuthHeader = true;
        } else if (root.isWeatherbit) {
            url = "https://api.weatherbit.io/v2.0/current?lat=42.7&lon=23.3&key="
                + encodeURIComponent(key) + "&units=M";
        } else if (root.isQWeather) {
            url = "https://devapi.qweather.com/v7/weather/now?location=23.30,42.70&key="
                + encodeURIComponent(key) + "&unit=m";
        } else {
            url = "https://api.weatherapi.com/v1/current.json?key="
                + encodeURIComponent(key) + "&q=42.7,23.3";
        }
        req.open("GET", url);
        if (useAuthHeader) req.setRequestHeader("Authorization", key);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (_testGen !== myGen) return;
            if (req.status === 200) {
                // QWeather returns HTTP 200 even on auth failure — check body code
                if (root.isQWeather) {
                    try {
                        var qwBody = JSON.parse(req.responseText);
                        if (qwBody.code !== "200") {
                            apiTestState = 3;
                            apiTestMessage = i18n("QWeather error (code %1). Check your API key.", qwBody.code);
                            return;
                        }
                    } catch (e) {
                        apiTestState = 3;
                        apiTestMessage = i18n("Invalid response from QWeather.");
                        return;
                    }
                }
                apiTestState = 2;
                var pLabel = root.providerDisplayName(root.cfg_weatherProvider);
                apiTestMessage = i18n("Connection successful! %1 key is valid.", pLabel);
                root.verifyProviderLocation();
            } else if (req.status === 401 || req.status === 403) {
                apiTestState = 3;
                apiTestMessage = i18n("Invalid API key. Please check and try again.");
            } else {
                apiTestState = 3;
                apiTestMessage = i18n("Connection failed (HTTP %1).", req.status);
            }
        };
        req.send();
    }

    // Providers without Adaptive — Adaptive is handled by the switch above
    readonly property var providerModel: [
        {
            text: i18n("Open-Meteo (recommended, free)"),
            value: "openMeteo"
        },
        {
            text: i18n("met.no (free)"),
            value: "metno"
        },
        {
            text: i18n("OpenWeatherMap (Key Required)"),
            value: "openWeather"
        },
        {
            text: i18n("WeatherAPI.com (Key Required)"),
            value: "weatherApi"
        },
        {
            text: i18n("Pirate Weather (Key Required)"),
            value: "pirateWeather"
        },
        {
            text: i18n("Visual Crossing (Key Required)"),
            value: "visualCrossing"
        },
        {
            text: i18n("Tomorrow.io (Key Required)"),
            value: "tomorrowIo"
        },
        {
            text: i18n("StormGlass (Key Required)"),
            value: "stormGlass"
        },
        {
            text: i18n("Weatherbit (Key Required)"),
            value: "weatherbit"
        },
        {
            text: i18n("QWeather (Key Required)"),
            value: "qWeather"
        }
    ]

    function providerIndexFor(val) {
        for (var i = 0; i < providerModel.length; ++i)
            if (providerModel[i].value === val)
                return i;
        return 0;
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 12

            // ══════════════════════════════════════════════════════════════
            // SECTION: Adaptive Mode
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                // Section header
                RowLayout {
                    Layout.fillWidth: true
                    Kirigami.Heading {
                        text: i18n("Weather Provider")
                        level: 4
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                        opacity: 0.5
                    }
                }

                Item {
                    Layout.preferredHeight: 8
                }

                // Adaptive toggle row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Switch {
                        id: adaptiveSwitch
                        checked: root.isAdaptive
                        onToggled: {
                            if (checked) {
                                root.cfg_weatherProvider = "adaptive";
                            } else {
                                // Fall back to Open-Meteo when disabling adaptive
                                root.cfg_weatherProvider = "openMeteo";
                                providerCombo.currentIndex = root.providerIndexFor("openMeteo");
                            }
                        }
                    }
                    Label {
                        text: i18n("Adaptive (auto-fallback)")
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            onClicked: adaptiveSwitch.toggle()
                        }
                    }
                }

                // Adaptive description — shown only when Adaptive is ON
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: root.isAdaptive
                    type: Kirigami.MessageType.Information
                    text: i18n("Providers are tried in order until one succeeds:\nOpen-Meteo  →  met.no  →  Pirate Weather  →  Visual Crossing  →  Tomorrow.io  →  StormGlass  →  Weatherbit  →  QWeather  →  OpenWeatherMap  →  WeatherAPI.com\nOpen-Meteo is always tried first — it is free and requires no API key.")
                }

                Item {
                    Layout.preferredHeight: 8
                }

                // Manual provider selector — hidden when Adaptive is ON
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: !root.isAdaptive

                    Label {
                        text: i18n("Provider:")
                        opacity: 0.75
                    }

                    ComboBox {
                        id: providerCombo
                        Layout.preferredWidth: 280
                        model: root.providerModel
                        textRole: "text"
                        currentIndex: root.providerIndexFor(root.cfg_weatherProvider)
                        onActivated: {
                            root.cfg_weatherProvider = root.providerModel[currentIndex].value;
                            root.apiTestState = 0;
                            root.locationCheckState = 0;
                            root.verifyProviderLocation();
                        }
                    }

                    // Provider sub-label
                    Label {
                        visible: root.isAdaptive === false
                        opacity: 0.6
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        textFormat: Text.RichText
                        onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                        text: {
                            if (root.isOpenWeather)
                                return i18n("Standard provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://openweathermap.org'>openweathermap.org</a>";
                            if (root.isWeatherApi)
                                return i18n("Alternative provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.weatherapi.com'>weatherapi.com</a>";
                            if (root.isPirateWeather)
                                return i18n("Dark Sky-compatible API with US alerts. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://pirateweather.net'>pirateweather.net</a>";
                            if (root.isVisualCrossing)
                                return i18n("Historical and forecast data provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.visualcrossing.com'>visualcrossing.com</a>";
                            if (root.isTomorrowIo)
                                return i18n("AI-powered weather intelligence. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.tomorrow.io'>tomorrow.io</a>";
                            if (root.isStormGlass)
                                return i18n("Marine and weather data provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://stormglass.io'>stormglass.io</a>";
                            if (root.isWeatherbit)
                                return i18n("High precision forecast provider. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.weatherbit.io'>weatherbit.io</a>";
                            if (root.isQWeather)
                                return i18n("Chinese weather provider with global coverage. API key required below.") + "<br/>" + i18n("Provider website:") + " <a href='https://www.qweather.com'>qweather.com</a>";
                            if (root.cfg_weatherProvider === "metno")
                                return i18n("Free Norwegian Meteorological Institute service. No API key needed.") + "<br/>" + i18n("Provider website:") + " <a href='https://met.no'>met.no</a>";
                            return i18n("Free and open-source. No API key needed. Recommended.") + "<br/>" + i18n("Provider website:") + " <a href='https://open-meteo.com'>open-meteo.com</a>";
                        }
                        HoverHandler {
                            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.locationCheckState === 2
                        type: Kirigami.MessageType.Positive
                        text: root.locationCheckMessage
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.locationCheckState === 3
                        type: Kirigami.MessageType.Error
                        text: root.locationCheckMessage
                    }
                }

                // ── API Key section ───────────────────────────────────────
                // Shown only when OpenWeather or WeatherAPI is selected
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    spacing: 8
                    visible: root.needsKeyUi && !root.isAdaptive

                    Label {
                        text: {
                            if (root.isOpenWeather) return i18n("OpenWeatherMap API Key:");
                            if (root.isPirateWeather) return i18n("Pirate Weather API Key:");
                            if (root.isVisualCrossing) return i18n("Visual Crossing API Key:");
                            if (root.isTomorrowIo) return i18n("Tomorrow.io API Key:");
                            if (root.isStormGlass) return i18n("StormGlass API Key:");
                            if (root.isWeatherbit) return i18n("Weatherbit API Key:");
                            if (root.isQWeather) return i18n("QWeather API Key:");
                            return i18n("WeatherAPI.com API Key:");
                        }
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextField {
                            id: apiKeyField
                            Layout.fillWidth: true
                            placeholderText: {
                                if (root.isOpenWeather) return i18n("Enter your OpenWeatherMap API key");
                                if (root.isPirateWeather) return i18n("Enter your Pirate Weather API key");
                                if (root.isVisualCrossing) return i18n("Enter your Visual Crossing API key");
                                if (root.isTomorrowIo) return i18n("Enter your Tomorrow.io API key");
                                if (root.isStormGlass) return i18n("Enter your StormGlass API key");
                                if (root.isWeatherbit) return i18n("Enter your Weatherbit API key");
                                if (root.isQWeather) return i18n("Enter your QWeather API key");
                                return i18n("Enter your WeatherAPI.com key");
                            }
                            text: {
                                if (root.isOpenWeather) return root.cfg_owApiKey;
                                if (root.isPirateWeather) return root.cfg_pwApiKey;
                                if (root.isVisualCrossing) return root.cfg_vcApiKey;
                                if (root.isTomorrowIo) return root.cfg_tioApiKey;
                                if (root.isStormGlass) return root.cfg_sgApiKey;
                                if (root.isWeatherbit) return root.cfg_wbApiKey;
                                if (root.isQWeather) return root.cfg_qwApiKey;
                                return root.cfg_waApiKey;
                            }
                            echoMode: TextInput.Password
                            selectByMouse: true
                            onTextEdited: {
                                root.apiTestState = 0;
                                if (root.isOpenWeather) root.cfg_owApiKey = text;
                                else if (root.isPirateWeather) root.cfg_pwApiKey = text;
                                else if (root.isVisualCrossing) root.cfg_vcApiKey = text;
                                else if (root.isTomorrowIo) root.cfg_tioApiKey = text;
                                else if (root.isStormGlass) root.cfg_sgApiKey = text;
                                else if (root.isWeatherbit) root.cfg_wbApiKey = text;
                                else if (root.isQWeather) root.cfg_qwApiKey = text;
                                else root.cfg_waApiKey = text;
                            }
                            onEditingFinished: {
                                if (root.isOpenWeather) root.cfg_owApiKey = text.trim();
                                else if (root.isPirateWeather) root.cfg_pwApiKey = text.trim();
                                else if (root.isVisualCrossing) root.cfg_vcApiKey = text.trim();
                                else if (root.isTomorrowIo) root.cfg_tioApiKey = text.trim();
                                else if (root.isStormGlass) root.cfg_sgApiKey = text.trim();
                                else if (root.isWeatherbit) root.cfg_wbApiKey = text.trim();
                                else if (root.isQWeather) root.cfg_qwApiKey = text.trim();
                                else root.cfg_waApiKey = text.trim();
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
                                root.apiTestState = 0;
                                if (root.isOpenWeather) root.cfg_owApiKey = "";
                                else if (root.isPirateWeather) root.cfg_pwApiKey = "";
                                else if (root.isVisualCrossing) root.cfg_vcApiKey = "";
                                else if (root.isTomorrowIo) root.cfg_tioApiKey = "";
                                else if (root.isStormGlass) root.cfg_sgApiKey = "";
                                else if (root.isWeatherbit) root.cfg_wbApiKey = "";
                                else if (root.isQWeather) root.cfg_qwApiKey = "";
                                else root.cfg_waApiKey = "";
                            }
                        }

                        Button {
                            text: root.apiTestState === 1 ? i18n("Testing…") : i18n("Test API Key")
                            icon.name: "network-connect"
                            enabled: apiKeyField.text.trim().length > 0 && root.apiTestState !== 1
                            onClicked: root.testApiKey()
                        }
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.needsKeyUi && !root.isAdaptive && apiKeyField.text.trim().length === 0
                        type: Kirigami.MessageType.Warning
                        text: {
                            var pLabel = root.providerDisplayName(root.cfg_weatherProvider);
                            return i18n("An API key is required for %1. Weather data cannot be retrieved without it.", pLabel);
                        }
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.apiTestState === 2
                        type: Kirigami.MessageType.Positive
                        text: root.apiTestMessage
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.apiTestState === 3
                        type: Kirigami.MessageType.Error
                        text: root.apiTestMessage
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════
            // SECTION: Data Refresh
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Kirigami.Heading {
                        text: i18n("Data Refresh")
                        level: 4
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Kirigami.Theme.textColor
                        opacity: 0.5
                    }
                }

                Item {
                    Layout.preferredHeight: 4
                }

                CheckBox {
                    text: i18n("Refresh weather automatically")
                    checked: root.cfg_autoRefresh
                    onToggled: root.cfg_autoRefresh = checked
                }

                RowLayout {
                    spacing: 8
                    enabled: root.cfg_autoRefresh
                    opacity: root.cfg_autoRefresh ? 1.0 : 0.5

                    Label {
                        text: i18n("Interval:")
                    }
                    SpinBox {
                        from: 5
                        to: 180
                        value: root.cfg_refreshIntervalMinutes
                        onValueModified: root.cfg_refreshIntervalMinutes = value
                    }
                    Label {
                        text: i18n("minutes")
                    }
                }
            }

            Item {
                Layout.preferredHeight: 16
            }
        }
    }
}
