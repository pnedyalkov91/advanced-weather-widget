import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    // ── Config properties ─────────────────────────────────────────────────
    property string cfg_weatherProvider: "adaptive"
    property string cfg_owApiKey: ""
    property string cfg_waApiKey: ""
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
    readonly property bool needsKeyUi: isOpenWeather || isWeatherApi

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
                        color: Kirigami.Theme.separatorColor
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
                    text: i18n("Providers are tried in order until one succeeds:\nOpen-Meteo  →  met.no  →  OpenWeatherMap  →  WeatherAPI.com\nOpen-Meteo is always tried first — it is free and requires no API key.")
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
                        }
                    }

                    // Provider sub-label
                    Label {
                        visible: root.isAdaptive === false
                        opacity: 0.6
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        text: {
                            if (root.isOpenWeather)
                                return i18n("Standard provider. API key required below.");
                            if (root.isWeatherApi)
                                return i18n("Alternative provider. API key required below.");
                            if (root.cfg_weatherProvider === "metno")
                                return i18n("Free Norwegian Meteorological Institute service. No API key needed.");
                            return i18n("Free and open-source. No API key needed. Recommended.");
                        }
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
                        text: root.isOpenWeather ? i18n("OpenWeatherMap API Key:") : i18n("WeatherAPI.com API Key:")
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextField {
                            id: apiKeyField
                            Layout.fillWidth: true
                            placeholderText: root.isOpenWeather ? i18n("Enter your OpenWeatherMap API key") : i18n("Enter your WeatherAPI.com key")
                            text: root.isOpenWeather ? root.cfg_owApiKey : root.cfg_waApiKey
                            echoMode: TextInput.Password
                            selectByMouse: true
                            onEditingFinished: {
                                if (root.isOpenWeather)
                                    root.cfg_owApiKey = text.trim();
                                else
                                    root.cfg_waApiKey = text.trim();
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
                                if (root.isOpenWeather)
                                    root.cfg_owApiKey = "";
                                else
                                    root.cfg_waApiKey = "";
                            }
                        }
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
