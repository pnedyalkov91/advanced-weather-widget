import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import org.kde.plasma.components as PlasmaComponents
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

KCM.AbstractKCM {
    id: root
    Kirigami.ColumnView.fillWidth: true

    FontLoader {
        id: wiFont
        source: "../fonts/weathericons-regular-webfont.ttf"
    }

    // ── Shared icon-config dialog for the Custom icon theme ─────────────────
    // Opens when the user clicks the configure button on a panel item.
    // For suntimes: shows separate sunrise + sunset icon pickers plus mode combo.
    // For other items: shows a single icon picker.
    // KIconThemes.IconDialog is still used to browse; changes apply immediately.

    property string _editingIconKey: ""   // key passed to setCustomIcon/getCustomIcon

    // Two separate KIconThemes dialogs so sunrise and sunset can each have one open
    KIconThemes.IconDialog {
        id: iconDialogMain
        onIconNameChanged: {
            if (iconName && root._editingIconKey.length > 0)
                root.setCustomIcon(root._editingIconKey, iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogRise
        onIconNameChanged: {
            if (iconName)
                root.setCustomIcon("suntimes-sunrise", iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogSet
        onIconNameChanged: {
            if (iconName)
                root.setCustomIcon("suntimes-sunset", iconName);
        }
    }
    // ── Tooltip icon dialogs (for Custom tooltip icon theme) ─────────────
    KIconThemes.IconDialog {
        id: iconDialogTooltipMain
        onIconNameChanged: {
            if (iconName && root._editingIconKey.length > 0)
                root.setTooltipCustomIcon(root._editingIconKey, iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogTooltipRise
        onIconNameChanged: {
            if (iconName)
                root.setTooltipCustomIcon("suntimes-sunrise", iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogTooltipSet
        onIconNameChanged: {
            if (iconName)
                root.setTooltipCustomIcon("suntimes-sunset", iconName);
        }
    }

    // ── Per-condition icon picker — single shared KIconThemes dialog ──────────
    // Feeds into conditionIconDialog._tempMap; only committed on OK.
    property string _editingConditionKey: ""

    KIconThemes.IconDialog {
        id: iconDialogCondition
        onIconNameChanged: {
            if (iconName && root._editingConditionKey.length > 0)
                conditionIconDialog._setTempIcon(root._editingConditionKey, iconName);
        }
    }

    // ── Condition icon dialog — redesigned ─────────────────────────────────────
    // KDE vs Custom switch + 9 per-condition rows + OK / Cancel (temp-state pattern).
    Dialog {
        id: conditionIconDialog
        property string context: "panel"   // "panel" | "tooltip"
        property bool useCustom: false
        property var _tempMap: ({})
        property string _tempMapStr: ""    // reactive trigger — updated alongside _tempMap

        // The 9 weather-condition slots (order matches Open-Meteo code ranges)
        readonly property var conditionSlots: [
            {
                key: "condition-clear",
                label: i18n("Clear (day)"),
                defaultIcon: "weather-clear"
            },
            {
                key: "condition-clear-night",
                label: i18n("Clear (night)"),
                defaultIcon: "weather-clear-night"
            },
            {
                key: "condition-cloudy-day",
                label: i18n("Partly cloudy (day)"),
                defaultIcon: "weather-few-clouds"
            },
            {
                key: "condition-cloudy-night",
                label: i18n("Partly cloudy (night)"),
                defaultIcon: "weather-few-clouds-night"
            },
            {
                key: "condition-overcast",
                label: i18n("Overcast"),
                defaultIcon: "weather-overcast"
            },
            {
                key: "condition-fog",
                label: i18n("Fog"),
                defaultIcon: "weather-fog"
            },
            {
                key: "condition-rain",
                label: i18n("Rain"),
                defaultIcon: "weather-showers"
            },
            {
                key: "condition-snow",
                label: i18n("Snow"),
                defaultIcon: "weather-snow"
            },
            {
                key: "condition-storm",
                label: i18n("Storm / Thunderstorm"),
                defaultIcon: "weather-storm"
            }
        ]

        // Raw config string for the active context
        function _rawConfig() {
            return context === "tooltip" ? root.cfg_tooltipCustomIcons : root.cfg_panelCustomIcons;
        }

        // Open and snapshot current saved state into _tempMap
        function openWithContext(ctx) {
            context = ctx;
            var m = root.parseCustomIcons(_rawConfig());
            // Deep-copy into a plain object so we don't alias the original
            var copy = {};
            for (var k in m)
                if (m.hasOwnProperty(k))
                    copy[k] = m[k];
            _tempMap = copy;
            useCustom = (copy["condition-custom"] === "1");
            _tempMapStr = JSON.stringify(copy);
            open();
        }

        // Write a key into the temp map and fire reactive update
        function _setTempIcon(key, name) {
            var m = {};
            for (var k in _tempMap)
                if (_tempMap.hasOwnProperty(k))
                    m[k] = _tempMap[k];
            if (name && name.length > 0)
                m[key] = name;
            else
                delete m[key];
            _tempMap = m;
            _tempMapStr = JSON.stringify(m);
        }

        // Read from temp map (binding must read _tempMapStr first to be reactive)
        function _getTempIcon(key) {
            var _t = _tempMapStr;   // reactive dependency
            return (_tempMap && key in _tempMap) ? _tempMap[key] : "";
        }

        // Commit temp state to the real config key
        function _commit() {
            var m = root.parseCustomIcons(_rawConfig());
            if (useCustom) {
                m["condition-custom"] = "1";
                conditionSlots.forEach(function (s) {
                    if (s.key in _tempMap && _tempMap[s.key].length > 0)
                        m[s.key] = _tempMap[s.key];
                    else
                        delete m[s.key];
                });
            } else {
                // KDE mode: strip condition-custom flag and all per-slot keys
                delete m["condition-custom"];
                conditionSlots.forEach(function (s) {
                    delete m[s.key];
                });
            }
            var serialized = root.serializeCustomIcons(m);
            if (context === "tooltip")
                root.cfg_tooltipCustomIcons = serialized;
            else
                root.cfg_panelCustomIcons = serialized;
        }

        title: i18n("Condition Icons")
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        standardButtons: Dialog.NoButton
        width: 480

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            // ── Icon-source switch ─────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Label {
                    text: i18n("Icon source:")
                    font.bold: true
                    opacity: 0.85
                }

                RadioButton {
                    text: i18n("KDE System Icons (automatic, follows weather code)")
                    checked: !conditionIconDialog.useCustom
                    onClicked: conditionIconDialog.useCustom = false
                }
                RadioButton {
                    text: i18n("Custom per-condition icons")
                    checked: conditionIconDialog.useCustom
                    onClicked: conditionIconDialog.useCustom = true
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // ── KDE mode: informational text ──────────────────────────────
            Label {
                visible: !conditionIconDialog.useCustom
                Layout.fillWidth: true
                text: i18n("The condition icon will automatically reflect the current weather using your KDE system icon theme. No customisation is needed.")
                opacity: 0.65
                font: Kirigami.Theme.smallFont
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 420
            }

            // ── Custom mode: 9 per-condition rows ─────────────────────────
            ColumnLayout {
                visible: conditionIconDialog.useCustom
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: conditionIconDialog.conditionSlots

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        // Icon preview (custom if set, else KDE default for slot)
                        Kirigami.Icon {
                            source: {
                                var _t = conditionIconDialog._tempMapStr;
                                var saved = conditionIconDialog._getTempIcon(modelData.key);
                                return saved.length > 0 ? saved : modelData.defaultIcon;
                            }
                            implicitWidth: Kirigami.Units.iconSizes.medium
                            implicitHeight: Kirigami.Units.iconSizes.medium
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Label + current icon name
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                text: modelData.label
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Label {
                                text: {
                                    var _t = conditionIconDialog._tempMapStr;
                                    var saved = conditionIconDialog._getTempIcon(modelData.key);
                                    return saved.length > 0 ? saved : modelData.defaultIcon;
                                }
                                font: Kirigami.Theme.smallFont
                                opacity: 0.55
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        // Browse button
                        Button {
                            text: i18n("Browse…")
                            icon.name: "document-open"
                            onClicked: {
                                root._editingConditionKey = modelData.key;
                                iconDialogCondition.open();
                            }
                        }

                        // Reset button (reverts slot to its default)
                        Button {
                            text: i18n("Reset")
                            icon.name: "edit-undo"
                            enabled: {
                                var _t = conditionIconDialog._tempMapStr;
                                return conditionIconDialog._getTempIcon(modelData.key).length > 0;
                            }
                            onClicked: conditionIconDialog._setTempIcon(modelData.key, "")
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                }

                Button {
                    text: i18n("Reset All to Defaults")
                    icon.name: "edit-clear-all"
                    onClicked: {
                        conditionIconDialog.conditionSlots.forEach(function (s) {
                            conditionIconDialog._setTempIcon(s.key, "");
                        });
                    }
                }
            }
        }

        footer: DialogButtonBox {
            Button {
                text: i18n("OK")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: {
                    conditionIconDialog._commit();
                    conditionIconDialog.close();
                }
            }
            Button {
                text: i18n("Cancel")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: conditionIconDialog.close()
            }
        }
    }

    // The configure dialog itself — shared between Panel and Tooltip tabs.
    // Set context = "panel" or "tooltip" before opening.
    Dialog {
        id: iconConfigDialog
        property string itemId: ""
        property string itemLabel: ""
        property string itemFallback: ""
        property bool isSuntimes: false
        property string context: "panel"   // "panel" | "tooltip"

        function getIcon(id) {
            return context === "tooltip" ? root.getTooltipCustomIcon(id) : root.getCustomIcon(id);
        }
        function setIcon(id, name) {
            if (context === "tooltip")
                root.setTooltipCustomIcon(id, name);
            else
                root.setCustomIcon(id, name);
        }
        // Which icon strings to watch for reactive re-evaluation
        function watchRaw() {
            return context === "tooltip" ? root.cfg_tooltipCustomIcons : root.cfg_panelCustomIcons;
        }

        title: i18n("Configure icon — %1", itemLabel)
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Close
        width: Math.min(implicitWidth + 40, 480)

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            // ── Single-item picker (all non-suntimes items) ───────────────
            ColumnLayout {
                visible: !iconConfigDialog.isSuntimes
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true

                Label {
                    text: i18n("Icon:")
                    font.bold: true
                    opacity: 0.85
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true

                    // Live preview
                    Kirigami.Icon {
                        source: {
                            var _w = iconConfigDialog.watchRaw();
                            var saved = iconConfigDialog.getIcon(iconConfigDialog.itemId);
                            return saved.length > 0 ? saved : iconConfigDialog.itemFallback;
                        }
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Browse button
                    Button {
                        text: i18n("Browse…")
                        icon.name: "document-open"
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: {
                            root._editingIconKey = iconConfigDialog.itemId;
                            if (iconConfigDialog.context === "tooltip")
                                iconDialogTooltipMain.open();
                            else
                                iconDialogMain.open();
                        }
                    }

                    // Reset button
                    Button {
                        text: i18n("Reset to default")
                        icon.name: "edit-undo"
                        enabled: {
                            var _w = iconConfigDialog.watchRaw();
                            return iconConfigDialog.getIcon(iconConfigDialog.itemId).length > 0;
                        }
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: iconConfigDialog.setIcon(iconConfigDialog.itemId, "")
                    }
                }
            }

            // ── Suntimes picker (sunrise + sunset + mode) ─────────────────
            ColumnLayout {
                visible: iconConfigDialog.isSuntimes
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true

                // Mode selector
                Label {
                    text: i18n("Display mode:")
                    font.bold: true
                    opacity: 0.85
                }
                ComboBox {
                    id: sunModeDialogCombo
                    Layout.fillWidth: true
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Upcoming (next sunrise or sunset)"),
                            value: "upcoming"
                        },
                        {
                            text: i18n("Both  07:17 / 18:03"),
                            value: "both"
                        },
                        {
                            text: i18n("Sunrise only  07:17"),
                            value: "sunrise"
                        },
                        {
                            text: i18n("Sunset only   18:03"),
                            value: "sunset"
                        }
                    ]
                    Component.onCompleted: {
                        for (var i = 0; i < model.length; ++i)
                            if (model[i].value === root.cfg_panelSunTimesMode) {
                                currentIndex = i;
                                break;
                            }
                    }
                    onActivated: root.cfg_panelSunTimesMode = model[currentIndex].value
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                }

                // Sunrise icon
                Label {
                    text: i18n("Sunrise icon:")
                    font.bold: true
                    opacity: 0.85
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true

                    Kirigami.Icon {
                        source: {
                            var _w = iconConfigDialog.watchRaw();
                            var saved = iconConfigDialog.getIcon("suntimes-sunrise");
                            return saved.length > 0 ? saved : "weather-sunrise";
                        }
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Button {
                        text: i18n("Browse…")
                        icon.name: "document-open"
                        onClicked: {
                            if (iconConfigDialog.context === "tooltip")
                                iconDialogTooltipRise.open();
                            else
                                iconDialogRise.open();
                        }
                    }
                    Button {
                        text: i18n("Reset")
                        icon.name: "edit-undo"
                        enabled: {
                            var _w = iconConfigDialog.watchRaw();
                            return iconConfigDialog.getIcon("suntimes-sunrise").length > 0;
                        }
                        onClicked: iconConfigDialog.setIcon("suntimes-sunrise", "")
                    }
                }

                // Sunset icon
                Label {
                    text: i18n("Sunset icon:")
                    font.bold: true
                    opacity: 0.85
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true

                    Kirigami.Icon {
                        source: {
                            var _w = iconConfigDialog.watchRaw();
                            var saved = iconConfigDialog.getIcon("suntimes-sunset");
                            return saved.length > 0 ? saved : "weather-sunset";
                        }
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Button {
                        text: i18n("Browse…")
                        icon.name: "document-open"
                        onClicked: {
                            if (iconConfigDialog.context === "tooltip")
                                iconDialogTooltipSet.open();
                            else
                                iconDialogSet.open();
                        }
                    }
                    Button {
                        text: i18n("Reset")
                        icon.name: "edit-undo"
                        enabled: {
                            var _w = iconConfigDialog.watchRaw();
                            return iconConfigDialog.getIcon("suntimes-sunset").length > 0;
                        }
                        onClicked: iconConfigDialog.setIcon("suntimes-sunset", "")
                    }
                }
            }
        }
    }

    // ── Panel config aliases ──────────────────────────────────────────────
    property string cfg_panelInfoMode: "single"
    property int cfg_panelScrollSeconds: 4
    property int cfg_panelMultiLines: 2
    property bool cfg_panelMultiAnimate: true
    property string cfg_panelMultilineIconStyle: "colorful"  // "symbolic" | "colorful"
    property int cfg_panelMultilineIconSize: 0      // 0 = auto; >0 = manual px
    property int cfg_panelIconSize: 22
    property int cfg_panelFontSize: 0
    property bool cfg_singlePanelRow: true
    property string cfg_panelItemOrder: "location;temperature;humidity"
    property string cfg_panelItemIcons: "location=1;condition=1;temperature=1;suntimes=1;wind=1;feelslike=1;humidity=1;pressure=1;moonphase=1"
    property string cfg_panelSeparator: " \u2022 "
    property string cfg_panelSunTimesMode: "upcoming"
    property int cfg_panelItemSpacing: 5
    property bool cfg_panelFillWidth: false
    property int cfg_panelWidth: 0      // 0 = auto; >0 = manual width (per-chip for single, text-col for multiline)
    property bool cfg_panelShowTemperature: true
    property bool cfg_panelShowWeatherIcon: false
    property bool cfg_panelShowSunTimes: false
    property bool cfg_panelShowWind: false
    property bool cfg_panelShowFeelsLike: false
    property bool cfg_panelShowHumidity: true
    property bool cfg_panelShowPressure: false
    property bool cfg_panelShowCondition: false
    property bool cfg_panelShowLocation: true

    // Simple mode sub‑options
    property int cfg_panelSimpleLayoutType: 0
    property int cfg_panelSimpleWidgetOrder: 0
    property string cfg_panelSimpleIconStyle: "symbolic"

    // ── Widget config aliases ─────────────────────────────────────────────
    property string cfg_tooltipStyle: "verbose"
    property string cfg_forecastLayout: "rows"
    property int cfg_forecastDays: 5
    property bool cfg_roundValues: true
    property bool cfg_showScrollbox: true
    property bool cfg_showUpdateText: true
    // Issue #7: widgetDetailsOrder replaces individual booleans
    property string cfg_widgetDetailsOrder: "feelslike;humidity;pressure;wind;dewpoint;visibility;moonphase;suntimes"
    property string cfg_widgetDetailsLayout: "cards2"  // "cards2" | "list"
    property int cfg_widgetIconSize: 16
    property string cfg_widgetIconTheme: "symbolic"   // "kde" | "wi-font" | "flat-color" | "symbolic" | "3d-oxygen"
    property int cfg_widgetWidth: 0       // 0 = default 540 px
    property int cfg_widgetHeight: 0       // 0 = default 500 px
    property bool cfg_widgetShowFeelsLike: true
    property bool cfg_widgetShowHumidity: true
    property bool cfg_widgetShowPressure: true
    property bool cfg_widgetShowWind: true
    property bool cfg_widgetShowSunrise: true
    property bool cfg_widgetShowDewPoint: true
    property bool cfg_widgetShowVisibility: true

    // ✦ NEW: Cards height properties ✦
    property bool cfg_widgetCardsHeightAuto: true
    property int cfg_widgetCardsHeight: 44

    // ── Tooltip config aliases ────────────────────────────────────────────
    property string cfg_tooltipItemOrder: "temperature;wind;humidity;pressure;suntimes"
    property string cfg_tooltipItemIcons: "temperature=1;condition=1;feelslike=1;wind=1;humidity=1;pressure=1;suntimes=1;moonphase=1"
    property string cfg_tooltipIconTheme: "symbolic"
    property int cfg_tooltipIconSize: 22
    property string cfg_tooltipCustomIcons: ""
    property bool cfg_tooltipEnabled: true
    property bool cfg_tooltipUseIcons: true
    property string cfg_tooltipSunTimesMode: "both" // "both" | "sunrise" | "sunset" | "upcoming"
    property string cfg_tooltipLocationWrap: "truncate"  // "truncate" | "wrap"
    property string cfg_tooltipWidthMode: "auto"
    property int cfg_tooltipWidthManual: 320
    property string cfg_tooltipHeightMode: "auto"
    property int cfg_tooltipHeightManual: 300

    // ── Units config aliases (Issue #8) ──────────────────────────────────
    property string cfg_unitsMode: "metric"
    property string cfg_temperatureUnit: "C"
    property string cfg_pressureUnit: "hPa"
    property string cfg_windSpeedUnit: "kmh"
    property string cfg_precipitationUnit: "mm"

    // ── Font config aliases ───────────────────────────────────────────────
    property bool cfg_useSystemFont: true
    property string cfg_fontFamily: "Noto Sans"
    property int cfg_fontSize: 11
    property bool cfg_fontBold: false

    // ── Panel font config aliases ─────────────────────────────────────────
    property bool cfg_panelUseSystemFont: true
    property string cfg_panelFontFamily: ""
    property bool cfg_panelFontBold: false

    // ── Panel icon theme ("wi-font" | "symbolic" | "flat-color" |
    //                     "3d-oxygen" | "3d-adwaita" | "kde") ─────
    property string cfg_panelIconTheme: "symbolic"
    property string cfg_panelSymbolicVariant: "dark"  // "dark" | "light" for symbolic SVG theme
    property string cfg_panelCustomIcons: ""      // "id=iconName;id=iconName;..." for custom theme

    // Manual size properties for simple mode
    property string cfg_simpleIconSizeMode: "auto"
    property int cfg_simpleIconSizeManual: 32
    property string cfg_simpleFontSizeMode: "auto"
    property int cfg_simpleFontSizeManual: 14

    // ── Custom icon map helpers ──────────────────────────────────────────
    function parseCustomIcons(raw) {
        var m = {};
        if (!raw || raw.length === 0)
            return m;
        raw.split(";").forEach(function (pair) {
            var kv = pair.split("=");
            if (kv.length === 2 && kv[0].trim().length > 0)
                m[kv[0].trim()] = kv[1].trim();
        });
        return m;
    }
    function serializeCustomIcons(map) {
        var parts = [];
        for (var k in map)
            if (map.hasOwnProperty(k) && map[k].length > 0)
                parts.push(k + "=" + map[k]);
        return parts.join(";");
    }
    function setCustomIcon(itemId, iconName) {
        var m = parseCustomIcons(root.cfg_panelCustomIcons);
        if (iconName.length > 0)
            m[itemId] = iconName;
        else
            delete m[itemId];
        root.cfg_panelCustomIcons = serializeCustomIcons(m);
    }
    function getCustomIcon(itemId) {
        var m = parseCustomIcons(root.cfg_panelCustomIcons);
        return (itemId in m) ? m[itemId] : "";
    }
    // ── Tooltip custom icon map helpers ──────────────────────────────────
    function setTooltipCustomIcon(itemId, iconName) {
        var m = parseCustomIcons(root.cfg_tooltipCustomIcons);
        if (iconName.length > 0)
            m[itemId] = iconName;
        else
            delete m[itemId];
        root.cfg_tooltipCustomIcons = serializeCustomIcons(m);
    }
    function getTooltipCustomIcon(itemId) {
        var m = parseCustomIcons(root.cfg_tooltipCustomIcons);
        return (itemId in m) ? m[itemId] : "";
    }

    // ─────────────────────────────────────────────────────────────────────
    // Panel item definitions (Issue #3: feelslike uses F055, not F05D)
    // ─────────────────────────────────────────────────────────────────────
    readonly property var allPanelItemDefs: [
        {
            itemId: "condition",
            label: i18n("Condition"),
            description: i18n("Weather icon + condition text"),
            wiChar: "\uF00D",
            iconFallback: "weather-clear"
        },
        {
            itemId: "temperature",
            label: i18n("Temperature"),
            description: i18n("Current temperature"),
            wiChar: "\uF055",
            iconFallback: "thermometer"
        },
        {
            itemId: "suntimes",
            label: i18n("Sunrise/Sunset"),
            description: i18n("Sunrise and sunset times"),
            wiChar: "\uF051",
            iconFallback: "weather-clear-night"
        },
        {
            itemId: "wind",
            label: i18n("Wind"),
            description: i18n("Wind speed and direction"),
            wiChar: "\uF059",
            iconFallback: "weather-windy"
        },
        // Issue #3: feelslike now uses F055 (thermometer), not F05D
        {
            itemId: "feelslike",
            label: i18n("Feels Like"),
            description: i18n("Apparent (feels-like) temperature"),
            wiChar: "\uF055",
            iconFallback: "thermometer"
        },
        {
            itemId: "humidity",
            label: i18n("Humidity"),
            description: i18n("Relative humidity percentage"),
            wiChar: "\uF07A",
            iconFallback: "weather-showers"
        },
        {
            itemId: "pressure",
            label: i18n("Pressure"),
            description: i18n("Atmospheric pressure"),
            wiChar: "\uF079",
            iconFallback: "weather-overcast"
        },
        {
            itemId: "location",
            label: i18n("Location Name"),
            description: i18n("City / location name"),
            wiChar: "\uF0B1",
            iconFallback: "mark-location"
        },
        {
            itemId: "moonphase",
            label: i18n("Moon Phase"),
            description: i18n("Current moon phase"),
            wiChar: "\uF0D0",
            iconFallback: "weather-clear-night"
        }
    ]

    // Widget details item definitions (Issue #7)
    // Widget details item definitions — with wi-font icons matching Panel items
    readonly property var allDetailsDefs: [
        {
            itemId: "feelslike",
            label: i18n("Feels Like"),
            description: i18n("Apparent temperature"),
            wiChar: "\uF055",
            iconFallback: "thermometer"
        },
        {
            itemId: "humidity",
            label: i18n("Humidity"),
            description: i18n("Relative humidity %"),
            wiChar: "\uF07A",
            iconFallback: "weather-showers"
        },
        {
            itemId: "pressure",
            label: i18n("Pressure"),
            description: i18n("Atmospheric pressure"),
            wiChar: "\uF079",
            iconFallback: "weather-overcast"
        },
        {
            itemId: "wind",
            label: i18n("Wind"),
            description: i18n("Wind speed + direction"),
            wiChar: "\uF050",
            iconFallback: "weather-windy"
        },
        {
            itemId: "suntimes",
            label: i18n("Sunrise/Sunset"),
            description: i18n("Sun rise & set times"),
            wiChar: "\uF051",
            iconFallback: "weather-clear"
        },
        {
            itemId: "dewpoint",
            label: i18n("Dew Point"),
            description: i18n("Dew point temperature"),
            wiChar: "\uF055",
            iconFallback: "thermometer"
        },
        {
            itemId: "visibility",
            label: i18n("Visibility"),
            description: i18n("Visibility distance"),
            wiChar: "\uF0B6",
            iconFallback: "weather-fog"
        },
        {
            itemId: "moonphase",
            label: i18n("Moon Phase"),
            description: i18n("Current moon phase"),
            wiChar: "\uF0D0",
            iconFallback: "weather-clear-night"
        }
    ]

    // Tooltip item definitions — with wi-font icons matching Panel items
    readonly property var allTooltipDefs: [
        {
            itemId: "temperature",
            label: i18n("Temperature"),
            description: i18n("Current temperature"),
            wiChar: "\uF055",
            iconFallback: "thermometer"
        },
        {
            itemId: "condition",
            label: i18n("Condition"),
            description: i18n("Weather condition text"),
            wiChar: "\uF013",
            iconFallback: "weather-few-clouds"
        },
        {
            itemId: "feelslike",
            label: i18n("Feels Like"),
            description: i18n("Apparent temperature"),
            wiChar: "\uF055",
            iconFallback: "thermometer"
        },
        {
            itemId: "wind",
            label: i18n("Wind"),
            description: i18n("Wind speed + direction"),
            wiChar: "\uF050",
            iconFallback: "weather-windy"
        },
        {
            itemId: "humidity",
            label: i18n("Humidity"),
            description: i18n("Relative humidity %"),
            wiChar: "\uF07A",
            iconFallback: "weather-showers"
        },
        {
            itemId: "pressure",
            label: i18n("Pressure"),
            description: i18n("Atmospheric pressure"),
            wiChar: "\uF079",
            iconFallback: "weather-overcast"
        },
        {
            itemId: "suntimes",
            label: i18n("Sunrise/Sunset"),
            description: i18n("Sun rise & set times"),
            wiChar: "\uF051",
            iconFallback: "weather-clear"
        },
        {
            itemId: "moonphase",
            label: i18n("Moon Phase"),
            description: i18n("Current moon phase"),
            wiChar: "\uF0D0",
            iconFallback: "weather-clear-night"
        }
    ]

    // ── Working models ────────────────────────────────────────────────────
    ListModel {
        id: panelWorkingModel
    }
    ListModel {
        id: detailsWorkingModel
    }
    ListModel {
        id: tooltipWorkingModel
    }

    // ─────────────────────────────────────────────────────────────────────
    // Panel items helpers
    // ─────────────────────────────────────────────────────────────────────
    function parsePanelItemIcons() {
        var raw = cfg_panelItemIcons || "";
        var map = {};
        raw.split(";").forEach(function (pair) {
            var kv = pair.split("=");
            if (kv.length === 2)
                map[kv[0].trim()] = (kv[1].trim() === "1");
        });
        return map;
    }
    function serializePanelItemIcons(map) {
        return allPanelItemDefs.map(function (d) {
            return d.itemId + "=" + ((d.itemId in map ? map[d.itemId] : true) ? "1" : "0");
        }).join(";");
    }
    function initPanelModel() {
        panelWorkingModel.clear();
        var iconMap = parsePanelItemIcons();
        var enabled = cfg_panelItemOrder.split(";").filter(function (t) {
            return t.trim().length > 0;
        });
        enabled.forEach(function (tok) {
            tok = tok.trim();
            for (var j = 0; j < allPanelItemDefs.length; ++j) {
                if (allPanelItemDefs[j].itemId === tok) {
                    panelWorkingModel.append({
                        itemId: allPanelItemDefs[j].itemId,
                        itemLabel: allPanelItemDefs[j].label,
                        itemDesc: allPanelItemDefs[j].description,
                        itemWiChar: allPanelItemDefs[j].wiChar,
                        itemFallback: allPanelItemDefs[j].iconFallback,
                        itemEnabled: true,
                        itemShowIcon: (tok in iconMap) ? iconMap[tok] : true
                    });
                    break;
                }
            }
        });
        allPanelItemDefs.forEach(function (def) {
            if (enabled.indexOf(def.itemId) < 0) {
                panelWorkingModel.append({
                    itemId: def.itemId,
                    itemLabel: def.label,
                    itemDesc: def.description,
                    itemWiChar: def.wiChar,
                    itemFallback: def.iconFallback,
                    itemEnabled: false,
                    itemShowIcon: (def.itemId in iconMap) ? iconMap[def.itemId] : true
                });
            }
        });
    }
    function firstPanelDisabledIndex() {
        for (var i = 0; i < panelWorkingModel.count; ++i)
            if (!panelWorkingModel.get(i).itemEnabled)
                return i;
        return -1;
    }
    function applyPanelItems() {
        var ids = [], iconMap = {};
        for (var i = 0; i < panelWorkingModel.count; ++i) {
            var item = panelWorkingModel.get(i);
            iconMap[item.itemId] = item.itemShowIcon;
            if (item.itemEnabled)
                ids.push(item.itemId);
        }
        cfg_panelItemOrder = ids.join(";");
        cfg_panelItemIcons = serializePanelItemIcons(iconMap);
        cfg_panelShowCondition = ids.indexOf("condition") >= 0;
        cfg_panelShowTemperature = ids.indexOf("temperature") >= 0;
        cfg_panelShowSunTimes = ids.indexOf("suntimes") >= 0;
        cfg_panelShowWind = ids.indexOf("wind") >= 0;
        cfg_panelShowFeelsLike = ids.indexOf("feelslike") >= 0;
        cfg_panelShowHumidity = ids.indexOf("humidity") >= 0;
        cfg_panelShowPressure = ids.indexOf("pressure") >= 0;
        cfg_panelShowLocation = ids.indexOf("location") >= 0;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Details items helpers (Issue #7)
    // ─────────────────────────────────────────────────────────────────────
    function initDetailsModel() {
        detailsWorkingModel.clear();
        var enabled = cfg_widgetDetailsOrder.split(";").filter(function (t) {
            return t.trim().length > 0;
        });
        enabled.forEach(function (tok) {
            tok = tok.trim();
            for (var j = 0; j < allDetailsDefs.length; ++j) {
                if (allDetailsDefs[j].itemId === tok) {
                    detailsWorkingModel.append({
                        itemId: allDetailsDefs[j].itemId,
                        itemLabel: allDetailsDefs[j].label,
                        itemDesc: allDetailsDefs[j].description,
                        itemEnabled: true,
                        itemWiChar: allDetailsDefs[j].wiChar,
                        itemFallback: allDetailsDefs[j].iconFallback
                    });
                    break;
                }
            }
        });
        allDetailsDefs.forEach(function (def) {
            if (enabled.indexOf(def.itemId) < 0) {
                detailsWorkingModel.append({
                    itemId: def.itemId,
                    itemLabel: def.label,
                    itemDesc: def.description,
                    itemEnabled: false,
                    itemWiChar: def.wiChar,
                    itemFallback: def.iconFallback
                });
            }
        });
    }
    function applyDetailsItems() {
        var ids = [];
        for (var i = 0; i < detailsWorkingModel.count; ++i) {
            if (detailsWorkingModel.get(i).itemEnabled)
                ids.push(detailsWorkingModel.get(i).itemId);
        }
        cfg_widgetDetailsOrder = ids.join(";");
        // Sync legacy booleans
        cfg_widgetShowFeelsLike = ids.indexOf("feelslike") >= 0;
        cfg_widgetShowHumidity = ids.indexOf("humidity") >= 0;
        cfg_widgetShowPressure = ids.indexOf("pressure") >= 0;
        cfg_widgetShowWind = ids.indexOf("wind") >= 0;
        cfg_widgetShowDewPoint = ids.indexOf("dewpoint") >= 0;
        cfg_widgetShowVisibility = ids.indexOf("visibility") >= 0;
        cfg_widgetShowSunrise = ids.indexOf("suntimes") >= 0;
    }
    function firstDetailsDisabledIndex() {
        for (var i = 0; i < detailsWorkingModel.count; ++i)
            if (!detailsWorkingModel.get(i).itemEnabled)
                return i;
        return -1;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tooltip items helpers
    // ─────────────────────────────────────────────────────────────────────
    function parseTooltipItemIcons() {
        var raw = cfg_tooltipItemIcons || "";
        var map = {};
        raw.split(";").forEach(function (pair) {
            var kv = pair.split("=");
            if (kv.length === 2)
                map[kv[0].trim()] = (kv[1].trim() === "1");
        });
        return map;
    }
    function serializeTooltipItemIcons(map) {
        return allTooltipDefs.map(function (d) {
            return d.itemId + "=" + ((d.itemId in map ? map[d.itemId] : true) ? "1" : "0");
        }).join(";");
    }
    function firstTooltipDisabledIndex() {
        for (var i = 0; i < tooltipWorkingModel.count; ++i)
            if (!tooltipWorkingModel.get(i).itemEnabled)
                return i;
        return -1;
    }
    function initTooltipModel() {
        tooltipWorkingModel.clear();
        var iconMap = parseTooltipItemIcons();
        var enabled = cfg_tooltipItemOrder.split(";").filter(function (t) {
            return t.trim().length > 0;
        });
        enabled.forEach(function (tok) {
            tok = tok.trim();
            for (var j = 0; j < allTooltipDefs.length; ++j) {
                if (allTooltipDefs[j].itemId === tok) {
                    tooltipWorkingModel.append({
                        itemId: allTooltipDefs[j].itemId,
                        itemLabel: allTooltipDefs[j].label,
                        itemDesc: allTooltipDefs[j].description,
                        itemEnabled: true,
                        itemWiChar: allTooltipDefs[j].wiChar,
                        itemFallback: allTooltipDefs[j].iconFallback,
                        itemShowIcon: (tok in iconMap) ? iconMap[tok] : true
                    });
                    break;
                }
            }
        });
        allTooltipDefs.forEach(function (def) {
            if (enabled.indexOf(def.itemId) < 0) {
                tooltipWorkingModel.append({
                    itemId: def.itemId,
                    itemLabel: def.label,
                    itemDesc: def.description,
                    itemEnabled: false,
                    itemWiChar: def.wiChar,
                    itemFallback: def.iconFallback,
                    itemShowIcon: (def.itemId in iconMap) ? iconMap[def.itemId] : true
                });
            }
        });
    }
    function applyTooltipItems() {
        var ids = [], iconMap = {};
        for (var i = 0; i < tooltipWorkingModel.count; ++i) {
            var item = tooltipWorkingModel.get(i);
            iconMap[item.itemId] = item.itemShowIcon;
            if (item.itemEnabled)
                ids.push(item.itemId);
        }
        cfg_tooltipItemOrder = ids.join(";");
        cfg_tooltipItemIcons = serializeTooltipItemIcons(iconMap);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Combo init helper
    // ─────────────────────────────────────────────────────────────────────
    function setCombo(combo, value) {
        for (var i = 0; i < combo.model.length; ++i)
            if (combo.model[i].value === value) {
                combo.currentIndex = i;
                return;
            }
    }

    // Component.onCompleted intentionally removed:
    // Each ComboBox initialises itself via its own Component.onCompleted.
    // The root's onCompleted fires before the deferred mainPage Component is
    // instantiated by StackView, so any ID references (panelModeCombo etc.)
    // are undefined at that point — self-init inside each ComboBox is the fix.

    // ══════════════════════════════════════════════════════════════════════
    // TAB BAR — 4 tabs: Panel, Widget, Tooltip, Units
    // ══════════════════════════════════════════════════════════════════════
    header: PlasmaComponents.TabBar {
        id: tabBar
        visible: stack.depth <= 1

        PlasmaComponents.TabButton {
            icon.name: "view-list-details"
            text: i18n("Panel")
        }
        PlasmaComponents.TabButton {
            icon.name: "plasma-symbolic"
            text: i18n("Widget")
        }
        PlasmaComponents.TabButton {
            icon.name: "preferences-desktop-feedback"
            text: i18n("Tooltip")
        }
        PlasmaComponents.TabButton {
            icon.name: "preferences-desktop"
            text: i18n("Misc")
        }
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: mainPage
    }

    // ════════════════════════════════════════════════════════════════════════
    // MAIN PAGE — StackLayout switches tabs
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: mainPage
        Kirigami.ScrollablePage {
            anchors.fill: parent
            StackLayout {
                currentIndex: tabBar.currentIndex
                Layout.fillWidth: true

                // TAB 0 — PANEL
                Kirigami.FormLayout {
                    Kirigami.Separator {
                        Kirigami.FormData.label: i18n("Panel display settings")
                        Kirigami.FormData.isSection: true
                    }
                    ComboBox {
                        id: panelModeCombo
                        Kirigami.FormData.label: i18n("Display mode:")
                        Layout.preferredWidth: 290
                        model: [
                            {
                                text: i18n("Single line (all items at once)"),
                                value: "single"
                            },
                            {
                                text: i18n("Multiple lines (tall panel)"),
                                value: "multiline"
                            },
                            {
                                text: i18n("Simple (icon + temperature)"),
                                value: "simple"
                            }
                        ]
                        textRole: "text"
                        Component.onCompleted: {
                            for (var i = 0; i < model.length; ++i)
                                if (model[i].value === root.cfg_panelInfoMode) {
                                    currentIndex = i;
                                    break;
                                }
                        }
                        onActivated: root.cfg_panelInfoMode = model[currentIndex].value
                    }

                    // ── Vertical panel truncation warning ──
                    Kirigami.InlineMessage {
                        visible: root.cfg_panelInfoMode === "single" || root.cfg_panelInfoMode === "multiline"
                        Layout.fillWidth: true
                        type: Kirigami.MessageType.Information
                        text: i18n("In a vertical panel, long item labels may be truncated. " + "Consider using \"Simple\" mode, increasing the panel width, or reducing the font size.")
                        showCloseButton: false
                    }

                    // ── Simple mode sub‑options ──

                    Kirigami.Separator {
                        visible: root.cfg_panelInfoMode !== "single" && root.cfg_panelInfoMode !== "multiline"
                        Kirigami.FormData.label: i18n("Simple display mode settings")
                        Kirigami.FormData.isSection: true
                    }

                    RowLayout {
                        visible: root.cfg_panelInfoMode === "simple"
                        Kirigami.FormData.label: i18n("Layout type:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: simpleLayoutCombo
                            Layout.preferredWidth: 290
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Horizontal"),
                                    value: 0
                                },
                                {
                                    text: i18n("Vertical"),
                                    value: 1
                                },
                                {
                                    text: i18n("Compressed"),
                                    value: 2
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_panelSimpleLayoutType) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_panelSimpleLayoutType = model[currentIndex].value
                        }
                    }

                    RowLayout {
                        visible: root.cfg_panelInfoMode === "simple" && root.cfg_panelSimpleLayoutType !== 2
                        Kirigami.FormData.label: i18n("Items Order:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: simpleOrderCombo
                            Layout.preferredWidth: 200
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Icon first"),
                                    value: 0
                                },
                                {
                                    text: i18n("Temperature first"),
                                    value: 1
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_panelSimpleWidgetOrder) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_panelSimpleWidgetOrder = model[currentIndex].value
                        }
                    }

                    RowLayout {
                        visible: root.cfg_panelInfoMode === "simple"
                        Kirigami.FormData.label: i18n("Weather icon style:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: simpleIconStyleCombo
                            Layout.preferredWidth: 200
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Colorful"),
                                    value: "colorful"
                                },
                                {
                                    text: i18n("Symbolic"),
                                    value: "symbolic"
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_panelSimpleIconStyle) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_panelSimpleIconStyle = model[currentIndex].value
                        }
                    }

                    // Icon size mode
                    RowLayout {
                        visible: root.cfg_panelInfoMode === "simple"
                        Kirigami.FormData.label: i18n("Icon size:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: simpleIconSizeModeCombo
                            Layout.preferredWidth: 120
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Auto"),
                                    value: "auto"
                                },
                                {
                                    text: i18n("Manual"),
                                    value: "manual"
                                }
                            ]
                            // Bind current index to the config value
                            currentIndex: root.cfg_simpleIconSizeMode === "auto" ? 0 : 1
                            onCurrentIndexChanged: {
                                var newMode = model[currentIndex].value;
                                if (root.cfg_simpleIconSizeMode !== newMode) {
                                    root.cfg_simpleIconSizeMode = newMode;
                                    // When switching to manual, set a sensible default if empty
                                    if (newMode === "manual" && root.cfg_simpleIconSizeManual === 0) {
                                        root.cfg_simpleIconSizeManual = 32;
                                    }
                                }
                            }
                        }
                        SpinBox {
                            id: iconSizeSpin
                            enabled: root.cfg_simpleIconSizeMode === "manual"
                            from: 16
                            to: 120
                            value: root.cfg_simpleIconSizeManual
                            onValueModified: root.cfg_simpleIconSizeManual = value
                            Layout.preferredWidth: 80
                        }
                        Label {
                            text: "px"
                            opacity: 0.65
                            visible: enabled
                        }
                    }

                    // Font size mode
                    RowLayout {
                        visible: root.cfg_panelInfoMode === "simple"
                        Kirigami.FormData.label: i18n("Font size:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: simpleFontSizeModeCombo
                            Layout.preferredWidth: 120
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Auto"),
                                    value: "auto"
                                },
                                {
                                    text: i18n("Manual"),
                                    value: "manual"
                                }
                            ]
                            currentIndex: root.cfg_simpleFontSizeMode === "auto" ? 0 : 1
                            onCurrentIndexChanged: {
                                var newMode = model[currentIndex].value;
                                if (root.cfg_simpleFontSizeMode !== newMode) {
                                    root.cfg_simpleFontSizeMode = newMode;
                                    if (newMode === "manual" && root.cfg_simpleFontSizeManual === 0) {
                                        root.cfg_simpleFontSizeManual = 14;
                                    }
                                }
                            }
                        }
                        SpinBox {
                            enabled: root.cfg_simpleFontSizeMode === "manual"
                            from: 8
                            to: 72
                            value: root.cfg_simpleFontSizeManual
                            onValueModified: root.cfg_simpleFontSizeManual = value
                            Layout.preferredWidth: 80
                        }
                        Label {
                            text: "px"
                            opacity: 0.65
                            visible: enabled
                        }
                    }
                    // ... (rest of the file unchanged)

                    // ── Multiple lines options (hidden in Simple mode) ─────
                    SpinBox {
                        Kirigami.FormData.label: i18n("Scroll interval (sec):")
                        visible: root.cfg_panelInfoMode === "multiline"
                        from: 1
                        to: 30
                        value: root.cfg_panelScrollSeconds
                        onValueModified: root.cfg_panelScrollSeconds = value
                        ToolTip.text: i18n("How often the rows scroll to reveal the next item")
                        ToolTip.visible: hovered
                    }
                    SpinBox {
                        Kirigami.FormData.label: i18n("Lines:")
                        visible: root.cfg_panelInfoMode === "multiline"
                        from: 1
                        to: 8
                        value: root.cfg_panelMultiLines
                        onValueModified: root.cfg_panelMultiLines = value
                        ToolTip.text: i18n("Number of item rows visible at once. Resize the panel height in KDE settings to match.")
                        ToolTip.visible: hovered
                    }
                    CheckBox {
                        Kirigami.FormData.label: i18n("Scroll animation:")
                        visible: root.cfg_panelInfoMode === "multiline"
                        text: i18n("Animate row scrolling")
                        checked: root.cfg_panelMultiAnimate
                        onToggled: root.cfg_panelMultiAnimate = checked
                    }
                    // Multiline mode: icon style (symbolic vs colorful)
                    RowLayout {
                        Kirigami.FormData.label: i18n("Main icon style:")
                        visible: root.cfg_panelInfoMode === "multiline"
                        spacing: 8
                        ComboBox {
                            id: mlIconStyleCombo
                            Layout.preferredWidth: 180
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Colorful (KDE color icons)"),
                                    value: "colorful"
                                },
                                {
                                    text: i18n("Symbolic (follows theme colour)"),
                                    value: "symbolic"
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_panelMultilineIconStyle) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_panelMultilineIconStyle = model[currentIndex].value
                        }
                        SpinBox {
                            id: mlIconSizeSpinBox
                            from: 0
                            to: 128
                            value: root.cfg_panelMultilineIconSize
                            onValueModified: root.cfg_panelMultilineIconSize = value
                            ToolTip.visible: hovered
                            ToolTip.text: i18n("Icon size in px. 0 = auto.")
                        }
                        Label {
                            text: root.cfg_panelMultilineIconSize === 0 ? i18n("px  (auto)") : i18n("px")
                            opacity: 0.65
                        }
                    }
                    RowLayout {
                        Kirigami.FormData.label: i18n("Item width:")
                        spacing: 8
                        SpinBox {
                            from: 0
                            to: 600
                            value: root.cfg_panelWidth
                            onValueModified: root.cfg_panelWidth = value
                        }
                        Label {
                            text: i18n("px")
                            opacity: 0.65
                        }
                        Label {
                            text: root.cfg_panelInfoMode === "multiline" ? i18n("0 = auto. Increase if items are cut off.") : i18n("0 = auto (120 px per chip). Increase if values are truncated.")
                            opacity: 0.65
                            font: Kirigami.Theme.smallFont
                            wrapMode: Text.WordWrap
                            Layout.maximumWidth: 260
                        }
                    }

                    RowLayout {
                        visible: root.cfg_panelInfoMode !== "multiline" && root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: i18n("Separator:")
                        spacing: 6
                        ComboBox {
                            id: separatorCombo
                            Layout.preferredWidth: 185
                            model: [
                                {
                                    text: i18n("Bullet  \u2022"),
                                    value: " \u2022 "
                                },
                                {
                                    text: i18n("Pipe  |"),
                                    value: " | "
                                },
                                {
                                    text: i18n("Dash  \u2013"),
                                    value: " \u2013 "
                                },
                                {
                                    text: i18n("Space"),
                                    value: "   "
                                },
                                {
                                    text: i18n("Small circle  \u26ac"),
                                    value: " \u26ac "
                                },
                                {
                                    text: i18n("Custom\u2026"),
                                    value: "__custom__"
                                }
                            ]
                            textRole: "text"
                            Component.onCompleted: {
                                var found = false;
                                for (var n = 0; n < model.length - 1; ++n) {
                                    if (model[n].value === root.cfg_panelSeparator) {
                                        currentIndex = n;
                                        found = true;
                                        break;
                                    }
                                }
                                if (!found)
                                    currentIndex = model.length - 1;
                            }
                            onActivated: {
                                if (model[currentIndex].value !== "__custom__")
                                    root.cfg_panelSeparator = model[currentIndex].value;
                            }
                        }
                        TextField {
                            Layout.preferredWidth: 72
                            visible: separatorCombo.currentIndex === separatorCombo.model.length - 1
                            text: root.cfg_panelSeparator
                            placeholderText: "e.g. \u203a"
                            onTextChanged: root.cfg_panelSeparator = text
                        }
                    }
                    RowLayout {
                        visible: root.cfg_panelInfoMode !== "multiline" && root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: i18n("Item spacing:")
                        spacing: 8
                        SpinBox {
                            from: 0
                            to: 32
                            value: root.cfg_panelItemSpacing
                            onValueModified: root.cfg_panelItemSpacing = value
                        }
                        Label {
                            text: "px"
                            opacity: 0.65
                        }
                    }
                    CheckBox {
                        visible: root.cfg_panelInfoMode === "single"
                        Kirigami.FormData.label: i18n("Fill panel:")
                        text: i18n("Expand widget to fill available panel space")
                        checked: root.cfg_panelFillWidth
                        onToggled: root.cfg_panelFillWidth = checked
                    }
                    Kirigami.Separator {
                        visible: root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: i18n("Panel items settings")
                        Kirigami.FormData.isSection: true
                    }
                    // ── Panel font — Switch + native Platform.FontDialog (like KDE clock) ──
                    Platform.FontDialog {
                        id: panelFontDialog
                        title: i18n("Choose a Panel Font")
                        modality: Qt.WindowModal

                        // fontChosen is the source-of-truth font object.
                        // Initialised from saved config; updated on Accept.
                        property font fontChosen: Qt.font({
                            family: root.cfg_panelFontFamily || Kirigami.Theme.defaultFont.family,
                            pointSize: root.cfg_panelFontSize > 0 ? root.cfg_panelFontSize : 11,
                            bold: root.cfg_panelFontBold
                        })
                        onAccepted: {
                            fontChosen = font;
                            root.cfg_panelFontFamily = fontChosen.family;
                            root.cfg_panelFontSize = Math.max(6, fontChosen.pointSize > 0 ? fontChosen.pointSize : 11);
                            root.cfg_panelFontBold = fontChosen.bold;
                            root.cfg_panelUseSystemFont = false;
                        }
                    }
                    RowLayout {
                        visible: root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: i18n("Panel font:")
                        spacing: Kirigami.Units.smallSpacing
                        // Switch: OFF = Automatic, ON = Manual
                        Switch {
                            id: panelFontSwitch
                            checked: !root.cfg_panelUseSystemFont
                            onToggled: {
                                root.cfg_panelUseSystemFont = !checked;
                                if (checked) {
                                    // Manual mode: seed family if empty
                                    if (root.cfg_panelFontFamily.length === 0)
                                        root.cfg_panelFontFamily = Kirigami.Theme.defaultFont.family;
                                } else {
                                    // Automatic mode: reset size to 0 so panelFontPx
                                    // falls back to the theme default pixel size
                                    root.cfg_panelFontSize = 0;
                                }
                            }
                        }
                        Label {
                            text: panelFontSwitch.checked ? i18n("Manual") : i18n("Automatic")
                            opacity: 0.8
                        }
                    }
                    Label {
                        visible: !panelFontSwitch.checked && root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: ""
                        text: i18n("Text will follow the system font and expand to fill the available space.")
                        opacity: 0.65
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.WordWrap
                        Layout.maximumWidth: 300
                    }
                    RowLayout {
                        visible: panelFontSwitch.checked && root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: ""
                        spacing: Kirigami.Units.smallSpacing
                        Button {
                            text: i18nc("@action:button", "Choose Style…")
                            icon.name: "settings-configure"
                            onClicked: {
                                panelFontDialog.currentFont = panelFontDialog.fontChosen;
                                panelFontDialog.open();
                            }
                        }
                    }
                    ColumnLayout {
                        visible: panelFontSwitch.checked && root.cfg_panelFontFamily.length > 0 && root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: ""
                        spacing: 2
                        Label {
                            // fontChosen.pointSize always reflects what was chosen in
                            // the dialog; cfg_panelFontSize can be 0 before first open.
                            text: i18nc("@info %1 size %2 family", "%1pt %2", panelFontDialog.fontChosen.pointSize > 0 ? panelFontDialog.fontChosen.pointSize : (root.cfg_panelFontSize > 0 ? root.cfg_panelFontSize : 11), root.cfg_panelFontFamily)
                            font: panelFontDialog.fontChosen
                        }
                        Label {
                            text: i18n("Note: size may be reduced if the panel is not thick enough.")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.65
                            wrapMode: Text.WordWrap
                            Layout.maximumWidth: 300
                        }
                    }
                    // Icon theme selector
                    RowLayout {
                        visible: root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: i18n("Icon theme:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: iconThemeCombo
                            Layout.preferredWidth: 200
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Font icons (default)"),
                                    value: "wi-font"
                                },
                                {
                                    text: i18n("Symbolic (SVG)"),
                                    value: "symbolic"
                                },
                                {
                                    text: i18n("Flat Color (SVG)"),
                                    value: "flat-color"
                                },
                                {
                                    text: i18n("3D Oxygen (SVG)"),
                                    value: "3d-oxygen"
                                },
                                {
                                    text: i18n("Custom"),
                                    value: "custom"
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_panelIconTheme) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_panelIconTheme = model[currentIndex].value
                        }
                        // Icon size selector — visible for all non-font themes
                        Label {
                            text: i18n("Size:")
                            visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value !== "wi-font" && root.cfg_panelInfoMode !== "simple"
                            opacity: 0.8
                        }
                        ComboBox {
                            id: iconSizeCombo
                            visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value !== "wi-font" && root.cfg_panelInfoMode !== "simple"
                            Layout.preferredWidth: 90
                            textRole: "text"
                            model: [
                                {
                                    text: "16 px",
                                    value: 16
                                },
                                {
                                    text: "22 px",
                                    value: 22
                                },
                                {
                                    text: "24 px",
                                    value: 24
                                },
                                {
                                    text: "32 px",
                                    value: 32
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_panelIconSize) {
                                        currentIndex = i;
                                        break;
                                    }
                                if (currentIndex < 0)
                                    currentIndex = 1;  // default 22
                            }
                            onActivated: root.cfg_panelIconSize = model[currentIndex].value
                        }
                    }
                    // Custom theme: description + button to open Panel Items with icon pickers
                    RowLayout {
                        visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value === "custom" && root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: ""
                        spacing: Kirigami.Units.largeSpacing
                        ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Label {
                                text: i18n("Uses KDE system icons by default. Click the button to customise each item's icon.")
                                opacity: 0.65
                                font: Kirigami.Theme.smallFont
                                wrapMode: Text.WordWrap
                                Layout.maximumWidth: 220
                            }
                        }
                        Button {
                            text: i18n("Set your own icons…")
                            icon.name: "color-picker"
                            onClicked: {
                                root.initPanelModel();
                                stack.push(panelItemsSubPage);
                            }
                        }
                    }
                    // Panel items configure button + preview chips
                    Item {
                        visible: root.cfg_panelInfoMode !== "simple"
                        Kirigami.FormData.label: i18n("Panel items:")
                        implicitWidth: panelPreviewRow.implicitWidth
                        implicitHeight: panelPreviewRow.implicitHeight
                        RowLayout {
                            id: panelPreviewRow
                            spacing: 10
                            Flow {
                                spacing: 4
                                Layout.maximumWidth: 260
                                Repeater {
                                    model: root.cfg_panelItemOrder.split(";").filter(function (t) {
                                        return t.length > 0;
                                    })
                                    delegate: Rectangle {
                                        radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.10)
                                        border.color: Qt.rgba(1, 1, 1, 0.22)
                                        border.width: 1
                                        implicitWidth: chipLbl.implicitWidth + 10
                                        implicitHeight: chipLbl.implicitHeight + 6
                                        Label {
                                            id: chipLbl
                                            anchors.centerIn: parent
                                            text: {
                                                var d = modelData.trim();
                                                for (var i = 0; i < root.allPanelItemDefs.length; ++i)
                                                    if (root.allPanelItemDefs[i].itemId === d)
                                                        return root.allPanelItemDefs[i].label;
                                                return d;
                                            }
                                        }
                                    }
                                }
                            }
                            Button {
                                text: i18n("Configure\u2026")
                                icon.name: "configure"
                                onClicked: {
                                    root.initPanelModel();
                                    stack.push(panelItemsSubPage);
                                }
                            }
                        }
                    }
                }

                // ════════════════════════════════════════════════════════
                // TAB 1 — WIDGET
                // ════════════════════════════════════════════════════════
                Kirigami.FormLayout {
                    Kirigami.Separator {
                        Kirigami.FormData.label: i18n("Widget settings")
                        Kirigami.FormData.isSection: true
                    }
                    SpinBox {
                        Kirigami.FormData.label: i18n("Forecast days:")
                        from: 3
                        to: 7
                        value: root.cfg_forecastDays
                        onValueModified: root.cfg_forecastDays = value
                    }
                    CheckBox {
                        Kirigami.FormData.label: i18n("Footer:")
                        text: i18n("Show update time and provider")
                        checked: root.cfg_showUpdateText
                        onToggled: root.cfg_showUpdateText = checked
                    }

                    // ── Widget items ──────────────────────────────────────
                    Kirigami.Separator {
                        Kirigami.FormData.label: i18n("Widget items")
                        Kirigami.FormData.isSection: true
                    }

                    // ── Widget icon theme selector ────────────────────────
                    RowLayout {
                        Kirigami.FormData.label: i18n("Icon theme:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: widgetIconThemeCombo
                            Layout.preferredWidth: 200
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Symbolic (SVG)"),
                                    value: "symbolic"
                                },
                                {
                                    text: i18n("Flat Color (SVG)"),
                                    value: "flat-color"
                                },
                                {
                                    text: i18n("3D Oxygen (SVG)"),
                                    value: "3d-oxygen"
                                }
                            ]
                            Component.onCompleted: {
                                var theme = root.cfg_widgetIconTheme;
                                if (theme === "kde" || theme === "wi-font")
                                    theme = "symbolic";
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === theme) {
                                        currentIndex = i;
                                        break;
                                    }
                                if (currentIndex < 0)
                                    currentIndex = 0;
                            }
                            onActivated: root.cfg_widgetIconTheme = model[currentIndex].value
                        }
                    }

                    // ── Widget icon size (shown for SVG themes) ───────────
                    RowLayout {
                        Kirigami.FormData.label: i18n("Icon size:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: widgetIconSizeCombo
                            Layout.preferredWidth: 120
                            textRole: "text"
                            model: [
                                {
                                    text: "16 px",
                                    value: 16
                                },
                                {
                                    text: "22 px",
                                    value: 22
                                },
                                {
                                    text: "24 px",
                                    value: 24
                                },
                                {
                                    text: "32 px",
                                    value: 32
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_widgetIconSize) {
                                        currentIndex = i;
                                        break;
                                    }
                                if (currentIndex < 0)
                                    currentIndex = 0;
                            }
                            onActivated: root.cfg_widgetIconSize = model[currentIndex].value
                        }
                    }

                    // ── Cards height (hidden in list mode) ────────────────
                    RowLayout {
                        visible: root.cfg_widgetDetailsLayout !== "list"
                        Kirigami.FormData.label: i18n("Cards height:")
                        spacing: Kirigami.Units.largeSpacing
                        ComboBox {
                            id: cardsHeightModeCombo
                            Layout.preferredWidth: 130
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Auto"),
                                    value: true
                                },
                                {
                                    text: i18n("Manual"),
                                    value: false
                                }
                            ]
                            // Bind current index to config
                            currentIndex: root.cfg_widgetCardsHeightAuto ? 0 : 1
                            onActivated: {
                                var newMode = model[currentIndex].value;
                                if (root.cfg_widgetCardsHeightAuto !== newMode) {
                                    root.cfg_widgetCardsHeightAuto = newMode;
                                }
                            }
                        }
                        SpinBox {
                            enabled: !root.cfg_widgetCardsHeightAuto
                            from: 30
                            to: 120
                            value: root.cfg_widgetCardsHeight
                            onValueModified: root.cfg_widgetCardsHeight = value
                        }
                        Label {
                            visible: !root.cfg_widgetCardsHeightAuto
                            text: "px"
                            opacity: 0.65
                        }
                    }

                    // Issue #7: Details items configurator (enable/disable, no drag)
                    Item {
                        Kirigami.FormData.label: i18n("Details items:")
                        implicitWidth: detailsPreviewRow.implicitWidth
                        implicitHeight: detailsPreviewRow.implicitHeight
                        RowLayout {
                            id: detailsPreviewRow
                            spacing: 10
                            Flow {
                                spacing: 4
                                Layout.maximumWidth: 260
                                Repeater {
                                    model: root.cfg_widgetDetailsOrder.split(";").filter(function (t) {
                                        return t.length > 0;
                                    })
                                    delegate: Rectangle {
                                        radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.10)
                                        border.color: Qt.rgba(1, 1, 1, 0.22)
                                        border.width: 1
                                        implicitWidth: detailChipLbl.implicitWidth + 10
                                        implicitHeight: detailChipLbl.implicitHeight + 6
                                        Label {
                                            id: detailChipLbl
                                            anchors.centerIn: parent
                                            text: {
                                                var d = modelData.trim();
                                                for (var i = 0; i < root.allDetailsDefs.length; ++i)
                                                    if (root.allDetailsDefs[i].itemId === d)
                                                        return root.allDetailsDefs[i].label;
                                                return d;
                                            }
                                        }
                                    }
                                }
                            }
                            Button {
                                text: i18n("Configure…")
                                icon.name: "configure"
                                onClicked: {
                                    root.initDetailsModel();
                                    stack.push(detailsSubPage);
                                }
                            }
                        }
                    }
                }

                // ════════════════════════════════════════════════════════
                // TAB 2 — TOOLTIP
                // ════════════════════════════════════════════════════════
                Kirigami.FormLayout {
                    // ── Enable / Disable tooltip ──────────────────────────
                    RowLayout {
                        Kirigami.FormData.label: i18n("Tooltip:")
                        spacing: Kirigami.Units.smallSpacing
                        Switch {
                            id: tooltipEnabledSwitch
                            checked: root.cfg_tooltipEnabled
                            onToggled: root.cfg_tooltipEnabled = checked
                        }
                        Label {
                            text: tooltipEnabledSwitch.checked ? i18n("Enabled") : i18n("Disabled")
                            opacity: 0.8
                        }
                    }

                    Kirigami.Separator {
                        visible: root.cfg_tooltipEnabled
                        Kirigami.FormData.label: i18n("Tooltip items settings")
                        Kirigami.FormData.isSection: true
                    }

                    // ── Location name style ──────────────────────────
                    RowLayout {
                        visible: root.cfg_tooltipEnabled
                        Kirigami.FormData.label: i18n("Location name:")
                        ComboBox {
                            id: ttLocationWrapCombo
                            Layout.preferredWidth: 200
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Truncate (single line)"),
                                    value: "truncate"
                                },
                                {
                                    text: i18n("Wrap to next line"),
                                    value: "wrap"
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_tooltipLocationWrap) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_tooltipLocationWrap = model[currentIndex].value
                        }
                    }

                    // ── Icons / Text switch ───────────────────────────────

                    // ── Tooltip size ─────────────────────────────────

                    // Width
                    RowLayout {
                        visible: root.cfg_tooltipEnabled
                        Kirigami.FormData.label: i18n("Tooltip width:")
                        spacing: Kirigami.Units.smallSpacing
                        ComboBox {
                            id: ttWidthModeCombo
                            Layout.preferredWidth: 120
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Auto"),
                                    value: "auto"
                                },
                                {
                                    text: i18n("Manual"),
                                    value: "manual"
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_tooltipWidthMode) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_tooltipWidthMode = model[currentIndex].value
                        }
                        SpinBox {
                            visible: root.cfg_tooltipWidthMode === "manual"
                            from: 200
                            to: 800
                            stepSize: 10
                            value: root.cfg_tooltipWidthManual
                            onValueModified: root.cfg_tooltipWidthManual = value
                        }
                        Label {
                            visible: root.cfg_tooltipWidthMode === "manual"
                            text: i18n("px")
                            opacity: 0.7
                        }
                    }

                    // Height
                    RowLayout {
                        visible: root.cfg_tooltipEnabled
                        Kirigami.FormData.label: i18n("Tooltip height:")
                        spacing: Kirigami.Units.smallSpacing
                        ComboBox {
                            id: ttHeightModeCombo
                            Layout.preferredWidth: 120
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Auto"),
                                    value: "auto"
                                },
                                {
                                    text: i18n("Manual"),
                                    value: "manual"
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_tooltipHeightMode) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_tooltipHeightMode = model[currentIndex].value
                        }
                        SpinBox {
                            visible: root.cfg_tooltipHeightMode === "manual"
                            from: 100
                            to: 800
                            stepSize: 10
                            value: root.cfg_tooltipHeightManual
                            onValueModified: root.cfg_tooltipHeightManual = value
                        }
                        Label {
                            visible: root.cfg_tooltipHeightMode === "manual"
                            text: i18n("px")
                            opacity: 0.7
                        }
                    }
                    RowLayout {
                        visible: root.cfg_tooltipEnabled
                        Kirigami.FormData.label: i18n("Prefix style:")
                        spacing: Kirigami.Units.smallSpacing
                        Switch {
                            id: ttUseIconsSwitch
                            checked: root.cfg_tooltipUseIcons
                            onToggled: root.cfg_tooltipUseIcons = checked
                        }
                        Label {
                            text: ttUseIconsSwitch.checked ? i18n("Icons") : i18n("Text labels (Temperature, Wind…)")
                            opacity: 0.8
                        }
                    }

                    // ── Tooltip icon theme selector (hidden in Text mode or disabled tooltip) ──
                    RowLayout {
                        Kirigami.FormData.label: i18n("Icon theme:")
                        spacing: Kirigami.Units.largeSpacing
                        visible: root.cfg_tooltipEnabled && root.cfg_tooltipUseIcons
                        ComboBox {
                            id: ttIconThemeCombo
                            Layout.preferredWidth: 200
                            textRole: "text"
                            model: [
                                {
                                    text: i18n("Font icons (default)"),
                                    value: "wi-font"
                                },
                                {
                                    text: i18n("Symbolic (SVG)"),
                                    value: "symbolic"
                                },
                                {
                                    text: i18n("Flat Color (SVG)"),
                                    value: "flat-color"
                                },
                                {
                                    text: i18n("3D Oxygen (SVG)"),
                                    value: "3d-oxygen"
                                },
                                {
                                    text: i18n("Custom"),
                                    value: "custom"
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_tooltipIconTheme) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: root.cfg_tooltipIconTheme = model[currentIndex].value
                        }
                        Label {
                            text: i18n("Size:")
                            visible: ttIconThemeCombo.model[ttIconThemeCombo.currentIndex].value !== "wi-font"
                            opacity: 0.8
                        }
                        ComboBox {
                            id: ttIconSizeCombo
                            visible: ttIconThemeCombo.model[ttIconThemeCombo.currentIndex].value !== "wi-font"
                            Layout.preferredWidth: 90
                            textRole: "text"
                            model: [
                                {
                                    text: "16 px",
                                    value: 16
                                },
                                {
                                    text: "22 px",
                                    value: 22
                                },
                                {
                                    text: "24 px",
                                    value: 24
                                },
                                {
                                    text: "32 px",
                                    value: 32
                                }
                            ]
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === root.cfg_tooltipIconSize) {
                                        currentIndex = i;
                                        break;
                                    }
                                if (currentIndex < 0)
                                    currentIndex = 1;
                            }
                            onActivated: root.cfg_tooltipIconSize = model[currentIndex].value
                        }
                    }
                    // Custom theme hint (hidden in Text mode or disabled tooltip)
                    RowLayout {
                        Kirigami.FormData.label: ""
                        visible: root.cfg_tooltipEnabled && root.cfg_tooltipUseIcons && ttIconThemeCombo.model[ttIconThemeCombo.currentIndex].value === "custom"
                        spacing: Kirigami.Units.largeSpacing
                        ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Label {
                                text: i18n("Uses KDE system icons by default. Click the button to customise each item’s icon.")
                                opacity: 0.65
                                font: Kirigami.Theme.smallFont
                                wrapMode: Text.WordWrap
                                Layout.maximumWidth: 220
                            }
                        }
                        Button {
                            text: i18n("Set your own icons…")
                            icon.name: "color-picker"
                            onClicked: {
                                root.initTooltipModel();
                                stack.push(tooltipSubPage);
                            }
                        }
                    }

                    Kirigami.Separator {
                        visible: root.cfg_tooltipEnabled
                        Kirigami.FormData.label: i18n("Tooltip items")
                        Kirigami.FormData.isSection: true
                    }
                    Item {
                        visible: root.cfg_tooltipEnabled
                        Kirigami.FormData.label: i18n("Tooltip items:")
                        implicitWidth: ttPreviewRow.implicitWidth
                        implicitHeight: ttPreviewRow.implicitHeight
                        RowLayout {
                            id: ttPreviewRow
                            spacing: 10
                            Flow {
                                spacing: 4
                                Layout.maximumWidth: 260
                                Repeater {
                                    model: root.cfg_tooltipItemOrder.split(";").filter(function (t) {
                                        return t.length > 0;
                                    })
                                    delegate: Rectangle {
                                        radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.10)
                                        border.color: Qt.rgba(1, 1, 1, 0.22)
                                        border.width: 1
                                        implicitWidth: ttChipLbl.implicitWidth + 10
                                        implicitHeight: ttChipLbl.implicitHeight + 6
                                        Label {
                                            id: ttChipLbl
                                            anchors.centerIn: parent
                                            text: {
                                                var d = modelData.trim();
                                                for (var i = 0; i < root.allTooltipDefs.length; ++i)
                                                    if (root.allTooltipDefs[i].itemId === d)
                                                        return root.allTooltipDefs[i].label;
                                                return d;
                                            }
                                        }
                                    }
                                }
                            }
                            Button {
                                text: i18n("Configure…")
                                icon.name: "configure"
                                onClicked: {
                                    root.initTooltipModel();
                                    stack.push(tooltipSubPage);
                                }
                            }
                        }
                    }
                }

                // TAB 3 — MISC (renamed from Units; includes Round Values)
                // ════════════════════════════════════════════════════════
                Kirigami.FormLayout {
                    Kirigami.Separator {
                        Kirigami.FormData.label: i18n("Display")
                        Kirigami.FormData.isSection: true
                    }
                    RowLayout {
                        Kirigami.FormData.label: i18n("Round values:")
                        spacing: 12
                        Switch {
                            id: roundValuesSwitch
                            checked: root.cfg_roundValues
                            onToggled: root.cfg_roundValues = checked
                        }
                        Label {
                            text: roundValuesSwitch.checked ? i18n("Values are rounded to whole numbers") : i18n("Values show decimal places")
                            opacity: 0.8
                        }
                    }

                    Kirigami.Separator {
                        Kirigami.FormData.label: i18n("Units")
                        Kirigami.FormData.isSection: true
                    }
                    ComboBox {
                        id: unitsModeCombo
                        Kirigami.FormData.label: i18n("Unit preset:")
                        Layout.preferredWidth: 270
                        model: [
                            {
                                text: i18n("Metric (°C, km/h, hPa, mm)"),
                                value: "metric"
                            },
                            {
                                text: i18n("Imperial (°F, mph, inHg, in)"),
                                value: "imperial"
                            },
                            {
                                text: i18n("Use KDE locale settings"),
                                value: "kde"
                            },
                            {
                                text: i18n("Custom (set each unit manually)"),
                                value: "custom"
                            }
                        ]
                        Component.onCompleted: {
                            for (var i = 0; i < model.length; ++i)
                                if (model[i].value === root.cfg_unitsMode) {
                                    currentIndex = i;
                                    break;
                                }
                            // Apply kde resolution immediately on load so the
                            // individual unit combos reflect the actual locale.
                            if (root.cfg_unitsMode === "kde") {
                                var isImp = (Qt.locale().measurementSystem === 1);
                                root.cfg_temperatureUnit = isImp ? "F" : "C";
                                root.cfg_windSpeedUnit = isImp ? "mph" : "kmh";
                                root.cfg_pressureUnit = isImp ? "inHg" : "hPa";
                                root.cfg_precipitationUnit = isImp ? "in" : "mm";
                            }
                        }
                        textRole: "text"
                        onActivated: {
                            var mode = model[currentIndex].value;
                            root.cfg_unitsMode = mode;
                            if (mode === "metric") {
                                root.cfg_temperatureUnit = "C";
                                root.cfg_windSpeedUnit = "kmh";
                                root.cfg_pressureUnit = "hPa";
                                root.cfg_precipitationUnit = "mm";
                                setCombo(tempUnitCombo, "C");
                                setCombo(windUnitCombo, "kmh");
                                setCombo(pressUnitCombo, "hPa");
                            } else if (mode === "imperial") {
                                root.cfg_temperatureUnit = "F";
                                root.cfg_windSpeedUnit = "mph";
                                root.cfg_pressureUnit = "inHg";
                                root.cfg_precipitationUnit = "in";
                                setCombo(tempUnitCombo, "F");
                                setCombo(windUnitCombo, "mph");
                                setCombo(pressUnitCombo, "inHg");
                            } else if (mode === "kde") {
                                var isImperial = (Qt.locale().measurementSystem === 1);
                                root.cfg_temperatureUnit = isImperial ? "F" : "C";
                                root.cfg_windSpeedUnit = isImperial ? "mph" : "kmh";
                                root.cfg_pressureUnit = isImperial ? "inHg" : "hPa";
                                root.cfg_precipitationUnit = isImperial ? "in" : "mm";
                                setCombo(tempUnitCombo, root.cfg_temperatureUnit);
                                setCombo(windUnitCombo, root.cfg_windSpeedUnit);
                                setCombo(pressUnitCombo, root.cfg_pressureUnit);
                            }
                            // "custom": don't auto-change, user sets below
                        }
                    }
                    Kirigami.Separator {
                        Kirigami.FormData.label: i18n("Individual units")
                        Kirigami.FormData.isSection: true
                    }
                    ComboBox {
                        id: tempUnitCombo
                        Kirigami.FormData.label: i18n("Temperature:")
                        enabled: root.cfg_unitsMode === "custom"
                        opacity: enabled ? 1.0 : 0.5
                        Layout.preferredWidth: 200
                        model: [
                            {
                                text: i18n("Celsius (°C)"),
                                value: "C"
                            },
                            {
                                text: i18n("Fahrenheit (°F)"),
                                value: "F"
                            }
                        ]
                        Component.onCompleted: {
                            for (var i = 0; i < model.length; ++i)
                                if (model[i].value === root.cfg_temperatureUnit) {
                                    currentIndex = i;
                                    break;
                                }
                        }
                        textRole: "text"
                        onActivated: if (root.cfg_unitsMode === "custom")
                            root.cfg_temperatureUnit = model[currentIndex].value
                    }
                    ComboBox {
                        id: windUnitCombo
                        Kirigami.FormData.label: i18n("Wind speed:")
                        enabled: root.cfg_unitsMode === "custom"
                        opacity: enabled ? 1.0 : 0.5
                        Layout.preferredWidth: 200
                        model: [
                            {
                                text: "km/h",
                                value: "kmh"
                            },
                            {
                                text: "mph",
                                value: "mph"
                            },
                            {
                                text: "m/s",
                                value: "ms"
                            },
                            {
                                text: i18n("Knots (kn)"),
                                value: "kn"
                            }
                        ]
                        Component.onCompleted: {
                            for (var i = 0; i < model.length; ++i)
                                if (model[i].value === root.cfg_windSpeedUnit) {
                                    currentIndex = i;
                                    break;
                                }
                        }
                        textRole: "text"
                        onActivated: if (root.cfg_unitsMode === "custom")
                            root.cfg_windSpeedUnit = model[currentIndex].value
                    }
                    ComboBox {
                        id: pressUnitCombo
                        Kirigami.FormData.label: i18n("Pressure:")
                        enabled: root.cfg_unitsMode === "custom"
                        opacity: enabled ? 1.0 : 0.5
                        Layout.preferredWidth: 200
                        model: [
                            {
                                text: "hPa",
                                value: "hPa"
                            },
                            {
                                text: "mmHg",
                                value: "mmHg"
                            },
                            {
                                text: "inHg",
                                value: "inHg"
                            }
                        ]
                        Component.onCompleted: {
                            for (var i = 0; i < model.length; ++i)
                                if (model[i].value === root.cfg_pressureUnit) {
                                    currentIndex = i;
                                    break;
                                }
                        }
                        textRole: "text"
                        onActivated: if (root.cfg_unitsMode === "custom")
                            root.cfg_pressureUnit = model[currentIndex].value
                    }
                    Label {
                        Kirigami.FormData.label: ""
                        text: i18n("Individual dropdowns are editable only in Custom mode.\nOther presets set units automatically.")
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                        font: Kirigami.Theme.smallFont
                        Layout.maximumWidth: 340
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SUB-PAGE: Panel Items
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: panelItemsSubPage
        ColumnLayout {
            id: panelSubPageRoot
            spacing: 0
            // Snapshot state captured when sub-page opens — used to restore on Discard
            property string _savedOrder: root.cfg_panelItemOrder
            property string _savedIcons: root.cfg_panelItemIcons

            Dialog {
                id: panelLeaveDialog
                title: i18n("Apply Settings?")
                modal: true
                parent: Overlay.overlay
                anchors.centerIn: parent
                standardButtons: Dialog.NoButton
                Label {
                    text: i18n("Keep the changes you made to Panel Items?")
                    wrapMode: Text.WordWrap
                }
                footer: DialogButtonBox {
                    Button {
                        text: i18n("Keep Changes")
                        DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                        onClicked: {
                            panelLeaveDialog.accept();
                            stack.pop();
                        }
                    }
                    Button {
                        text: i18n("Discard")
                        DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
                        onClicked: {
                            root.cfg_panelItemOrder = panelSubPageRoot._savedOrder;
                            root.cfg_panelItemIcons = panelSubPageRoot._savedIcons;
                            panelLeaveDialog.close();
                            stack.pop();
                        }
                    }
                    Button {
                        text: i18n("Cancel")
                        DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                        onClicked: panelLeaveDialog.close()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.leftMargin: 4
                Layout.rightMargin: 8
                Layout.bottomMargin: 4
                spacing: 4
                Button {
                    icon.name: "go-previous"
                    text: i18n("Back")
                    flat: true
                    onClicked: {
                        // Show confirm if anything changed from the snapshot
                        if (root.cfg_panelItemOrder !== panelSubPageRoot._savedOrder || root.cfg_panelItemIcons !== panelSubPageRoot._savedIcons)
                            panelLeaveDialog.open();
                        else
                            stack.pop();
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: i18n("Panel Items")
                    font.bold: true
                }
            }
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ListView {
                    id: panelItemList
                    width: parent.width
                    implicitHeight: contentHeight
                    clip: true
                    spacing: 0
                    model: panelWorkingModel
                    highlightMoveDuration: Kirigami.Units.longDuration
                    displaced: Transition {
                        YAnimator {
                            duration: Kirigami.Units.longDuration
                        }
                    }
                    section.property: "itemEnabled"
                    section.criteria: ViewSection.FullString
                    section.delegate: Kirigami.ListSectionHeader {
                        required property string section
                        width: panelItemList.width
                        label: section === "true" ? i18n("Enabled") : i18n("Available")
                    }
                    delegate: Item {
                        id: panelDelegateRoot
                        property bool settingsExpanded: false
                        width: panelItemList.width
                        implicitHeight: panelDelegateCol.implicitHeight
                        ColumnLayout {
                            id: panelDelegateCol
                            spacing: 0
                            width: parent.width
                            ItemDelegate {
                                id: panelRowDelegate
                                Layout.fillWidth: true
                                hoverEnabled: true
                                down: false
                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Kirigami.ListItemDragHandle {
                                        listItem: panelRowDelegate
                                        listView: panelItemList
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.0
                                        onMoveRequested: function (oldIndex, newIndex) {
                                            var boundary = root.firstPanelDisabledIndex();
                                            var clamped = (boundary < 0) ? newIndex : Math.min(newIndex, boundary - 1);
                                            if (clamped !== oldIndex)
                                                panelWorkingModel.move(oldIndex, clamped, 1);
                                        }
                                        onDropped: root.applyPanelItems()
                                    }
                                    // Icon — mirrors the active panel icon theme so
                                    // the preview matches what appears on the panel.
                                    Item {
                                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                        opacity: model.itemEnabled ? 1.0 : 0.35

                                        // wi-font char (default theme)
                                        Text {
                                            anchors.centerIn: parent
                                            text: model.itemWiChar
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: Kirigami.Units.iconSizes.smallMedium - 2
                                            color: Kirigami.Theme.textColor
                                            visible: root.cfg_panelIconTheme === "wi-font" && model.itemWiChar.length > 0 && wiFont.status === FontLoader.Ready
                                        }
                                        // Kirigami fallback for wi-font (no char) or KDE theme
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: model.itemFallback
                                            visible: (root.cfg_panelIconTheme === "wi-font" && (model.itemWiChar.length === 0 || wiFont.status !== FontLoader.Ready)) || root.cfg_panelIconTheme === "kde"
                                            // "custom" has its own preview block below
                                        }
                                        // SVG theme icon (symbolic / flat-color / 3d-oxygen)
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            visible: root.cfg_panelIconTheme !== "wi-font" && root.cfg_panelIconTheme !== "kde" && root.cfg_panelIconTheme !== "custom" && root.cfg_panelIconTheme.length > 0
                                            source: {
                                                var th = root.cfg_panelIconTheme;
                                                if (!th || th === "wi-font" || th === "kde" || th === "custom")
                                                    return "";
                                                var sz = root.cfg_panelIconSize || 22;
                                                var b = Qt.resolvedUrl("../icons/" + th + "/" + sz + "/wi-");
                                                var id = model.itemId;
                                                if (id === "temperature" || id === "feelslike")
                                                    return b + "thermometer.svg";
                                                if (id === "humidity")
                                                    return b + "humidity.svg";
                                                if (id === "pressure")
                                                    return b + "barometer.svg";
                                                if (id === "wind")
                                                    return b + "strong-wind.svg";
                                                if (id === "suntimes")
                                                    return b + "sunrise.svg";
                                                if (id === "moonphase")
                                                    return b + "wi-moon-alt-full.svg";
                                                if (id === "condition")
                                                    return b + "day-cloudy.svg";
                                                if (id === "location")
                                                    return b + "wind-deg.svg";
                                                return "";
                                            }
                                            isMask: root.cfg_panelIconTheme === "symbolic"
                                            color: Kirigami.Theme.textColor
                                        }
                                        // Custom theme: show the saved custom icon (falls back to KDE default)
                                        // For condition: always show weather-clear (or saved condition-clear) as preview
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            visible: root.cfg_panelIconTheme === "custom"
                                            source: {
                                                var _w = root.cfg_panelCustomIcons;
                                                if (model.itemId === "condition") {
                                                    var m = root.parseCustomIcons(root.cfg_panelCustomIcons);
                                                    return ("condition-clear" in m && m["condition-clear"].length > 0) ? m["condition-clear"] : "weather-clear";
                                                }
                                                var saved = root.getCustomIcon(model.itemId);
                                                return saved.length > 0 ? saved : model.itemFallback;
                                            }
                                        }
                                    }
                                    // Labels
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Label {
                                            Layout.fillWidth: true
                                            text: model.itemLabel
                                            elide: Text.ElideRight
                                            opacity: model.itemEnabled ? 1.0 : 0.55
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: model.itemDesc
                                            font: Kirigami.Theme.smallFont
                                            elide: Text.ElideRight
                                            opacity: 0.55
                                        }
                                    }
                                    // Sun times gear (only in non-custom themes — custom uses the configure dialog)
                                    ToolButton {
                                        visible: model.itemId === "suntimes" && root.cfg_panelIconTheme !== "custom"
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.3
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        icon.name: "configure"
                                        checkable: true
                                        checked: panelDelegateRoot.settingsExpanded
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Sun times options")
                                        onClicked: panelDelegateRoot.settingsExpanded = !panelDelegateRoot.settingsExpanded
                                    }
                                    // Configure icon button (custom theme only) — opens the icon-config dialog
                                    ToolButton {
                                        visible: root.cfg_panelIconTheme === "custom"
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.3
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        icon.name: "color-picker"
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Configure icon…")
                                        onClicked: {
                                            if (model.itemId === "condition") {
                                                conditionIconDialog.openWithContext("panel");
                                            } else {
                                                iconConfigDialog.context = "panel";
                                                iconConfigDialog.itemId = model.itemId;
                                                iconConfigDialog.itemLabel = model.itemLabel;
                                                iconConfigDialog.itemFallback = model.itemFallback;
                                                iconConfigDialog.isSuntimes = (model.itemId === "suntimes");
                                                for (var i = 0; i < sunModeDialogCombo.model.length; ++i)
                                                    if (sunModeDialogCombo.model[i].value === root.cfg_panelSunTimesMode) {
                                                        sunModeDialogCombo.currentIndex = i;
                                                        break;
                                                    }
                                                iconConfigDialog.open();
                                            }
                                        }
                                    }
                                    // Eye toggle
                                    ToolButton {
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.25
                                        icon.name: model.itemShowIcon ? "view-visible" : "view-hidden"
                                        ToolTip.visible: hovered
                                        ToolTip.text: model.itemShowIcon ? i18n("Hide prefix icon") : i18n("Show prefix icon")
                                        onClicked: {
                                            panelWorkingModel.setProperty(model.index, "itemShowIcon", !model.itemShowIcon);
                                            root.applyPanelItems();
                                        }
                                    }
                                    // Enable/disable (font-enable / font-disable)
                                    ToolButton {
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        icon.name: model.itemEnabled ? "font-enable" : "font-disable"
                                        ToolTip.visible: hovered
                                        ToolTip.text: model.itemEnabled ? i18n("Disable item") : i18n("Enable item")
                                        onClicked: {
                                            var idx = model.index;
                                            var nowOn = !model.itemEnabled;
                                            if (!nowOn)
                                                panelDelegateRoot.settingsExpanded = false;
                                            panelWorkingModel.setProperty(idx, "itemEnabled", nowOn);
                                            var boundary = root.firstPanelDisabledIndex();
                                            if (nowOn) {
                                                if (boundary > 0 && idx >= boundary)
                                                    panelWorkingModel.move(idx, boundary - 1, 1);
                                            } else {
                                                var lastEnabled = -1;
                                                for (var i = 0; i < panelWorkingModel.count; ++i)
                                                    if (panelWorkingModel.get(i).itemEnabled)
                                                        lastEnabled = i;
                                                if (lastEnabled >= 0 && idx <= lastEnabled)
                                                    panelWorkingModel.move(idx, lastEnabled, 1);
                                                else if (lastEnabled < 0 && idx > 0)
                                                    panelWorkingModel.move(idx, 0, 1);
                                            }
                                            root.applyPanelItems();
                                        }
                                    }
                                }
                            }
                            // Inline sun times options (only for non-custom themes)
                            RowLayout {
                                visible: model.itemId === "suntimes" && panelDelegateRoot.settingsExpanded && root.cfg_panelIconTheme !== "custom"
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.largeSpacing * 2
                                Layout.rightMargin: Kirigami.Units.largeSpacing
                                Layout.bottomMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.largeSpacing
                                Label {
                                    text: i18n("Sun times mode:")
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.8
                                }
                                ComboBox {
                                    id: sunTimesInlineCombo
                                    Layout.fillWidth: true
                                    model: [
                                        {
                                            text: i18n("Upcoming (next sunrise or sunset)"),
                                            value: "upcoming"
                                        },
                                        {
                                            text: i18n("Both  07:17 / 18:03"),
                                            value: "both"
                                        },
                                        {
                                            text: i18n("Sunrise only  07:17"),
                                            value: "sunrise"
                                        },
                                        {
                                            text: i18n("Sunset only   18:03"),
                                            value: "sunset"
                                        }
                                    ]
                                    textRole: "text"
                                    Component.onCompleted: {
                                        for (var i = 0; i < model.length; ++i)
                                            if (model[i].value === root.cfg_panelSunTimesMode) {
                                                currentIndex = i;
                                                break;
                                            }
                                    }
                                    onActivated: root.cfg_panelSunTimesMode = model[currentIndex].value
                                }
                            }

                            Kirigami.Separator {
                                Layout.fillWidth: true
                                opacity: 0.4
                            }
                        }
                    }
                }
            }
            // ── Button guide ─────────────────────────────────────────────────
            // Explains what each toolbar button on each row does.
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Label {
                    text: i18n("Button guide")
                    font.bold: true
                    opacity: 0.85
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    // Drag handle
                    RowLayout {
                        spacing: 4
                        Kirigami.Icon {
                            source: "handle-sort"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Drag to reorder enabled items")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }

                    // Configure icon (custom theme only)
                    RowLayout {
                        visible: root.cfg_panelIconTheme === "custom"
                        spacing: 4
                        Kirigami.Icon {
                            source: "color-picker"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Choose a custom icon for this item")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }

                    // Eye toggle
                    RowLayout {
                        spacing: 4
                        Kirigami.Icon {
                            source: "view-visible"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Show / hide the prefix icon on the panel")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }

                    // Enable / disable
                    RowLayout {
                        spacing: 4
                        Kirigami.Icon {
                            source: "font-enable"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Enable or disable this item on the panel")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SUB-PAGE: Widget Details Items — full parity with Panel Items sub-page
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: detailsSubPage
        ColumnLayout {
            id: detailsSubPageRoot
            spacing: 0
            property string _savedOrder: root.cfg_widgetDetailsOrder
            Dialog {
                id: detailsLeaveDialog
                title: i18n("Apply Settings?")
                modal: true
                parent: Overlay.overlay
                anchors.centerIn: parent
                standardButtons: Dialog.NoButton
                Label {
                    text: i18n("Keep the changes you made to Details Items?")
                    wrapMode: Text.WordWrap
                }
                footer: DialogButtonBox {
                    Button {
                        text: i18n("Keep Changes")
                        DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                        onClicked: {
                            detailsLeaveDialog.accept();
                            stack.pop();
                        }
                    }
                    Button {
                        text: i18n("Discard")
                        DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
                        onClicked: {
                            root.cfg_widgetDetailsOrder = detailsSubPageRoot._savedOrder;
                            detailsLeaveDialog.close();
                            stack.pop();
                        }
                    }
                    Button {
                        text: i18n("Cancel")
                        DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                        onClicked: detailsLeaveDialog.close()
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.leftMargin: 4
                Layout.rightMargin: 8
                Layout.bottomMargin: 4
                spacing: 4
                Button {
                    icon.name: "go-previous"
                    text: i18n("Back")
                    flat: true
                    onClicked: {
                        if (root.cfg_widgetDetailsOrder !== detailsSubPageRoot._savedOrder)
                            detailsLeaveDialog.open();
                        else
                            stack.pop();
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: i18n("Details Items")
                    font.bold: true
                }
            }
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ListView {
                    id: detailsList
                    width: parent.width
                    implicitHeight: contentHeight
                    clip: true
                    spacing: 0
                    model: detailsWorkingModel
                    highlightMoveDuration: Kirigami.Units.longDuration
                    displaced: Transition {
                        YAnimator {
                            duration: Kirigami.Units.longDuration
                        }
                    }
                    section.property: "itemEnabled"
                    section.criteria: ViewSection.FullString
                    section.delegate: Kirigami.ListSectionHeader {
                        required property string section
                        width: detailsList.width
                        label: section === "true" ? i18n("Shown") : i18n("Hidden")
                    }
                    delegate: Item {
                        id: detailsDelegateRoot
                        width: detailsList.width
                        implicitHeight: detailsDelegateCol.implicitHeight
                        ColumnLayout {
                            id: detailsDelegateCol
                            spacing: 0
                            width: parent.width
                            ItemDelegate {
                                id: detailsRowDelegate
                                Layout.fillWidth: true
                                hoverEnabled: true
                                down: false
                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    // ── Drag handle (only active for enabled items) ──────
                                    Kirigami.ListItemDragHandle {
                                        listItem: detailsRowDelegate
                                        listView: detailsList
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.0
                                        onMoveRequested: function (oldIndex, newIndex) {
                                            var boundary = root.firstDetailsDisabledIndex();
                                            var clamped = (boundary < 0) ? newIndex : Math.min(newIndex, boundary - 1);
                                            if (clamped !== oldIndex)
                                                detailsWorkingModel.move(oldIndex, clamped, 1);
                                        }
                                        onDropped: root.applyDetailsItems()
                                    }
                                    // ── Item icon — mirrors the active widget icon theme ──
                                    Item {
                                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                        opacity: model.itemEnabled ? 1.0 : 0.35
                                        // wi-font glyph
                                        Text {
                                            anchors.centerIn: parent
                                            text: model.itemWiChar
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: Kirigami.Units.iconSizes.smallMedium - 2
                                            color: Kirigami.Theme.textColor
                                            visible: root.cfg_widgetIconTheme === "wi-font" && model.itemWiChar.length > 0 && wiFont.status === FontLoader.Ready
                                        }
                                        // KDE / wi-font fallback
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: model.itemFallback
                                            visible: (root.cfg_widgetIconTheme === "wi-font" && (model.itemWiChar.length === 0 || wiFont.status !== FontLoader.Ready)) || root.cfg_widgetIconTheme === "kde"
                                        }
                                        // SVG theme icon (symbolic / flat-color / 3d-oxygen)
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            visible: root.cfg_widgetIconTheme !== "wi-font" && root.cfg_widgetIconTheme !== "kde" && root.cfg_widgetIconTheme.length > 0
                                            source: {
                                                var th = root.cfg_widgetIconTheme;
                                                if (!th || th === "wi-font" || th === "kde")
                                                    return "";
                                                var b = Qt.resolvedUrl("../icons/" + th + "/16/wi-");
                                                var id = model.itemId;
                                                if (id === "feelslike" || id === "dewpoint")
                                                    return b + "thermometer.svg";
                                                if (id === "humidity")
                                                    return b + "humidity.svg";
                                                if (id === "pressure")
                                                    return b + "barometer.svg";
                                                if (id === "wind")
                                                    return b + "strong-wind.svg";
                                                if (id === "suntimes")
                                                    return b + "sunrise.svg";
                                                if (id === "moonphase")
                                                    return b + "wi-moon-alt-full.svg";
                                                if (id === "visibility")
                                                    return b + "fog.svg";
                                                return "";
                                            }
                                            isMask: root.cfg_widgetIconTheme === "symbolic"
                                            color: Kirigami.Theme.textColor
                                        }
                                    }
                                    // ── Labels ───────────────────────────────────────────
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Label {
                                            Layout.fillWidth: true
                                            text: model.itemLabel
                                            elide: Text.ElideRight
                                            opacity: model.itemEnabled ? 1.0 : 0.55
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: model.itemDesc
                                            font: Kirigami.Theme.smallFont
                                            elide: Text.ElideRight
                                            opacity: 0.55
                                        }
                                    }
                                    // ── Enable / disable toggle ───────────────────────────
                                    ToolButton {
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        icon.name: model.itemEnabled ? "font-enable" : "font-disable"
                                        ToolTip.visible: hovered
                                        ToolTip.text: model.itemEnabled ? i18n("Hide from details") : i18n("Show in details")
                                        onClicked: {
                                            var idx = model.index;
                                            var nowOn = !model.itemEnabled;
                                            detailsWorkingModel.setProperty(idx, "itemEnabled", nowOn);
                                            var boundary = root.firstDetailsDisabledIndex();
                                            if (nowOn) {
                                                // Re-enabling: move from disabled zone to just before first disabled
                                                if (boundary > 0 && idx >= boundary)
                                                    detailsWorkingModel.move(idx, boundary - 1, 1);
                                            } else {
                                                // Disabling: move to end of enabled group
                                                var lastEnabled = -1;
                                                for (var i = 0; i < detailsWorkingModel.count; ++i)
                                                    if (detailsWorkingModel.get(i).itemEnabled)
                                                        lastEnabled = i;
                                                if (lastEnabled >= 0 && idx <= lastEnabled)
                                                    detailsWorkingModel.move(idx, lastEnabled, 1);
                                                else if (lastEnabled < 0 && idx > 0)
                                                    detailsWorkingModel.move(idx, 0, 1);
                                            }
                                            root.applyDetailsItems();
                                        }
                                    }
                                }
                            }
                            Kirigami.Separator {
                                Layout.fillWidth: true
                                opacity: 0.4
                            }
                        }
                    }
                }
            }
            // ── Button guide ──────────────────────────────────────────────────
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                Label {
                    text: i18n("Button guide")
                    font.bold: true
                    opacity: 0.85
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    RowLayout {
                        spacing: 4
                        Kirigami.Icon {
                            source: "handle-sort"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Drag to reorder shown items")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                    RowLayout {
                        spacing: 4
                        Kirigami.Icon {
                            source: "font-enable"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Show or hide this detail item")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SUB-PAGE: Tooltip Items — full parity with Panel Items sub-page
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: tooltipSubPage
        ColumnLayout {
            id: ttSubPageRoot
            spacing: 0
            property string _savedOrder: root.cfg_tooltipItemOrder
            property string _savedIcons: root.cfg_tooltipItemIcons

            Dialog {
                id: ttLeaveDialog
                title: i18n("Apply Settings?")
                modal: true
                parent: Overlay.overlay
                anchors.centerIn: parent
                standardButtons: Dialog.NoButton
                Label {
                    text: i18n("Keep the changes you made to Tooltip Items?")
                    wrapMode: Text.WordWrap
                }
                footer: DialogButtonBox {
                    Button {
                        text: i18n("Keep Changes")
                        DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                        onClicked: {
                            ttLeaveDialog.accept();
                            stack.pop();
                        }
                    }
                    Button {
                        text: i18n("Discard")
                        DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
                        onClicked: {
                            root.cfg_tooltipItemOrder = ttSubPageRoot._savedOrder;
                            root.cfg_tooltipItemIcons = ttSubPageRoot._savedIcons;
                            ttLeaveDialog.close();
                            stack.pop();
                        }
                    }
                    Button {
                        text: i18n("Cancel")
                        DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                        onClicked: ttLeaveDialog.close()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.leftMargin: 4
                Layout.rightMargin: 8
                Layout.bottomMargin: 4
                spacing: 4
                Button {
                    icon.name: "go-previous"
                    text: i18n("Back")
                    flat: true
                    onClicked: {
                        if (root.cfg_tooltipItemOrder !== ttSubPageRoot._savedOrder || root.cfg_tooltipItemIcons !== ttSubPageRoot._savedIcons)
                            ttLeaveDialog.open();
                        else
                            stack.pop();
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: i18n("Tooltip Items")
                    font.bold: true
                }
            }
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ListView {
                    id: tooltipItemList
                    width: parent.width
                    implicitHeight: contentHeight
                    clip: true
                    spacing: 0
                    model: tooltipWorkingModel
                    highlightMoveDuration: Kirigami.Units.longDuration
                    displaced: Transition {
                        YAnimator {
                            duration: Kirigami.Units.longDuration
                        }
                    }
                    section.property: "itemEnabled"
                    section.criteria: ViewSection.FullString
                    section.delegate: Kirigami.ListSectionHeader {
                        required property string section
                        width: tooltipItemList.width
                        label: section === "true" ? i18n("Enabled") : i18n("Available")
                    }
                    delegate: Item {
                        id: ttDelegateRoot
                        property bool settingsExpanded: false
                        width: tooltipItemList.width
                        implicitHeight: ttDelegateCol.implicitHeight
                        ColumnLayout {
                            id: ttDelegateCol
                            spacing: 0
                            width: parent.width
                            ItemDelegate {
                                id: ttRowDelegate
                                Layout.fillWidth: true
                                hoverEnabled: true
                                down: false
                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    // Drag handle
                                    Kirigami.ListItemDragHandle {
                                        listItem: ttRowDelegate
                                        listView: tooltipItemList
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.0
                                        onMoveRequested: function (oldIndex, newIndex) {
                                            var boundary = root.firstTooltipDisabledIndex();
                                            var clamped = (boundary < 0) ? newIndex : Math.min(newIndex, boundary - 1);
                                            if (clamped !== oldIndex)
                                                tooltipWorkingModel.move(oldIndex, clamped, 1);
                                        }
                                        onDropped: root.applyTooltipItems()
                                    }
                                    // Icon — reflects active tooltip icon theme
                                    Item {
                                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                        opacity: model.itemEnabled ? 1.0 : 0.35
                                        // wi-font char
                                        Text {
                                            anchors.centerIn: parent
                                            text: model.itemWiChar
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: Kirigami.Units.iconSizes.smallMedium - 2
                                            color: Kirigami.Theme.textColor
                                            visible: root.cfg_tooltipIconTheme === "wi-font" && model.itemWiChar.length > 0 && wiFont.status === FontLoader.Ready
                                        }
                                        // KDE / fallback icon
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: model.itemFallback
                                            visible: (root.cfg_tooltipIconTheme === "wi-font" && (model.itemWiChar.length === 0 || wiFont.status !== FontLoader.Ready)) || root.cfg_tooltipIconTheme === "kde"
                                        }
                                        // SVG theme icon
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            visible: root.cfg_tooltipIconTheme !== "wi-font" && root.cfg_tooltipIconTheme !== "kde" && root.cfg_tooltipIconTheme !== "custom" && root.cfg_tooltipIconTheme.length > 0
                                            source: {
                                                var th = root.cfg_tooltipIconTheme;
                                                if (!th || th === "wi-font" || th === "kde" || th === "custom")
                                                    return "";
                                                var sz = root.cfg_tooltipIconSize || 22;
                                                var b = Qt.resolvedUrl("../icons/" + th + "/" + sz + "/wi-");
                                                var id = model.itemId;
                                                if (id === "temperature" || id === "feelslike")
                                                    return b + "thermometer.svg";
                                                if (id === "humidity")
                                                    return b + "humidity.svg";
                                                if (id === "pressure")
                                                    return b + "barometer.svg";
                                                if (id === "wind")
                                                    return b + "strong-wind.svg";
                                                if (id === "suntimes")
                                                    return b + "sunrise.svg";
                                                if (id === "moonphase")
                                                    return b + "wi-moon-alt-full.svg";
                                                if (id === "condition")
                                                    return b + "day-cloudy.svg";
                                                if (id === "location")
                                                    return b + "wind-deg.svg";
                                                return "";
                                            }
                                            isMask: root.cfg_tooltipIconTheme === "symbolic"
                                            color: Kirigami.Theme.textColor
                                        }
                                        // Custom theme
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            visible: root.cfg_tooltipIconTheme === "custom"
                                            source: {
                                                var _w = root.cfg_tooltipCustomIcons;
                                                if (model.itemId === "condition") {
                                                    var m = root.parseCustomIcons(root.cfg_tooltipCustomIcons);
                                                    return ("condition-clear" in m && m["condition-clear"].length > 0) ? m["condition-clear"] : "weather-clear";
                                                }
                                                var saved = root.getTooltipCustomIcon(model.itemId);
                                                return saved.length > 0 ? saved : model.itemFallback;
                                            }
                                        }
                                    }
                                    // Labels
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Label {
                                            Layout.fillWidth: true
                                            text: model.itemLabel
                                            elide: Text.ElideRight
                                            opacity: model.itemEnabled ? 1.0 : 0.55
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: model.itemDesc
                                            font: Kirigami.Theme.smallFont
                                            elide: Text.ElideRight
                                            opacity: 0.55
                                        }
                                    }
                                    // Suntimes settings gear (non-custom themes)
                                    ToolButton {
                                        visible: model.itemId === "suntimes" && root.cfg_tooltipIconTheme !== "custom"
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.3
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        icon.name: "configure"
                                        checkable: true
                                        checked: ttDelegateRoot.settingsExpanded
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Sun times options")
                                        onClicked: ttDelegateRoot.settingsExpanded = !ttDelegateRoot.settingsExpanded
                                    }
                                    // Configure icon button (custom theme only)
                                    ToolButton {
                                        visible: root.cfg_tooltipIconTheme === "custom"
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.3
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        icon.name: "color-picker"
                                        ToolTip.visible: hovered
                                        ToolTip.text: i18n("Configure icon…")
                                        onClicked: {
                                            if (model.itemId === "condition") {
                                                conditionIconDialog.openWithContext("tooltip");
                                            } else {
                                                iconConfigDialog.context = "tooltip";
                                                iconConfigDialog.itemId = model.itemId;
                                                iconConfigDialog.itemLabel = model.itemLabel;
                                                iconConfigDialog.itemFallback = model.itemFallback;
                                                iconConfigDialog.isSuntimes = (model.itemId === "suntimes");
                                                for (var i = 0; i < sunModeDialogCombo.model.length; ++i)
                                                    if (sunModeDialogCombo.model[i].value === root.cfg_panelSunTimesMode) {
                                                        sunModeDialogCombo.currentIndex = i;
                                                        break;
                                                    }
                                                iconConfigDialog.open();
                                            }
                                        }
                                    }
                                    // Eye toggle — show/hide prefix icon
                                    ToolButton {
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        enabled: model.itemEnabled
                                        opacity: model.itemEnabled ? 1.0 : 0.25
                                        icon.name: model.itemShowIcon ? "view-visible" : "view-hidden"
                                        ToolTip.visible: hovered
                                        ToolTip.text: model.itemShowIcon ? i18n("Hide prefix icon") : i18n("Show prefix icon")
                                        onClicked: {
                                            tooltipWorkingModel.setProperty(model.index, "itemShowIcon", !model.itemShowIcon);
                                            root.applyTooltipItems();
                                        }
                                    }
                                    // Enable / disable
                                    ToolButton {
                                        implicitWidth: Kirigami.Units.iconSizes.medium
                                        implicitHeight: Kirigami.Units.iconSizes.medium
                                        icon.name: model.itemEnabled ? "font-enable" : "font-disable"
                                        ToolTip.visible: hovered
                                        ToolTip.text: model.itemEnabled ? i18n("Disable item") : i18n("Enable item")
                                        onClicked: {
                                            var idx = model.index;
                                            var nowOn = !model.itemEnabled;
                                            if (!nowOn)
                                                ttDelegateRoot.settingsExpanded = false;
                                            tooltipWorkingModel.setProperty(idx, "itemEnabled", nowOn);
                                            var boundary = root.firstTooltipDisabledIndex();
                                            if (nowOn) {
                                                if (boundary > 0 && idx >= boundary)
                                                    tooltipWorkingModel.move(idx, boundary - 1, 1);
                                            } else {
                                                var lastEnabled = -1;
                                                for (var i = 0; i < tooltipWorkingModel.count; ++i)
                                                    if (tooltipWorkingModel.get(i).itemEnabled)
                                                        lastEnabled = i;
                                                if (lastEnabled >= 0 && idx <= lastEnabled)
                                                    tooltipWorkingModel.move(idx, lastEnabled, 1);
                                                else if (lastEnabled < 0 && idx > 0)
                                                    tooltipWorkingModel.move(idx, 0, 1);
                                            }
                                            root.applyTooltipItems();
                                        }
                                    }
                                }
                            }
                            // Inline suntimes mode (non-custom themes)
                            RowLayout {
                                visible: model.itemId === "suntimes" && ttDelegateRoot.settingsExpanded && root.cfg_tooltipIconTheme !== "custom"
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.largeSpacing * 2
                                Layout.rightMargin: Kirigami.Units.largeSpacing
                                Layout.bottomMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.largeSpacing
                                Label {
                                    text: i18n("Sun times mode:")
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.8
                                }
                                ComboBox {
                                    Layout.fillWidth: true
                                    model: [
                                        {
                                            text: i18n("Both  07:17 / 18:03"),
                                            value: "both"
                                        },
                                        {
                                            text: i18n("Upcoming (next sunrise or sunset)"),
                                            value: "upcoming"
                                        },
                                        {
                                            text: i18n("Sunrise only  07:17"),
                                            value: "sunrise"
                                        },
                                        {
                                            text: i18n("Sunset only   18:03"),
                                            value: "sunset"
                                        }
                                    ]
                                    textRole: "text"
                                    Component.onCompleted: {
                                        for (var i = 0; i < model.length; ++i)
                                            if (model[i].value === root.cfg_tooltipSunTimesMode) {
                                                currentIndex = i;
                                                break;
                                            }
                                    }
                                    onActivated: root.cfg_tooltipSunTimesMode = model[currentIndex].value
                                }
                            }
                            Kirigami.Separator {
                                Layout.fillWidth: true
                                opacity: 0.4
                            }
                        }
                    }
                }
            }
            // ── Button guide ──────────────────────────────────────────────────
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                Label {
                    text: i18n("Button guide")
                    font.bold: true
                    opacity: 0.85
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    RowLayout {
                        spacing: 4
                        Kirigami.Icon {
                            source: "handle-sort"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Drag to reorder enabled items")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                    RowLayout {
                        visible: root.cfg_tooltipIconTheme === "custom"
                        spacing: 4
                        Kirigami.Icon {
                            source: "color-picker"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Choose a custom icon for this item")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                    RowLayout {
                        spacing: 4
                        Kirigami.Icon {
                            source: "view-visible"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Show / hide the prefix icon")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                    RowLayout {
                        spacing: 4
                        Kirigami.Icon {
                            source: "font-enable"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        Label {
                            text: i18n("Enable or disable this item")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                }
            }
        }
    }
}
