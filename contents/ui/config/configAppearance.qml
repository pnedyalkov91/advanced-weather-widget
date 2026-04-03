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
        source: "../../fonts/weathericons-regular-webfont.ttf"
    }

    // Resolved from this file's location (ui/config/) so sub-pages
    // can access the correct paths via configRoot without needing to
    // know their own directory depth.
    readonly property url iconsBase: Qt.resolvedUrl("../../icons/")
    readonly property bool wiFontReady: wiFont.status === FontLoader.Ready
    readonly property string wiFontFamily: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""

    // Expose the condition icon dialog so external tabs (ConfigWidgetTab) can open it
    property alias conditionIconDialog: conditionIconDialog

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
    // ── Details icon dialogs (for KDE theme custom icon picking) ─────────────
    KIconThemes.IconDialog {
        id: iconDialogDetailsMain
        onIconNameChanged: {
            if (iconName && root._editingIconKey.length > 0)
                root.setDetailsCustomIcon(root._editingIconKey, iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogDetailsRise
        onIconNameChanged: {
            if (iconName)
                root.setDetailsCustomIcon("suntimes-sunrise", iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogDetailsSet
        onIconNameChanged: {
            if (iconName)
                root.setDetailsCustomIcon("suntimes-sunset", iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogDetailsMoonrise
        onIconNameChanged: {
            if (iconName)
                root.setDetailsCustomIcon("moonrise", iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogDetailsMoonset
        onIconNameChanged: {
            if (iconName)
                root.setDetailsCustomIcon("moonset", iconName);
        }
    }
    // ── Panel moonrise/moonset icon dialogs ──────────────────────────────
    KIconThemes.IconDialog {
        id: iconDialogMoonrise
        onIconNameChanged: {
            if (iconName)
                root.setCustomIcon("moonrise", iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogMoonset
        onIconNameChanged: {
            if (iconName)
                root.setCustomIcon("moonset", iconName);
        }
    }
    // ── Tooltip moonrise/moonset icon dialogs ────────────────────────────
    KIconThemes.IconDialog {
        id: iconDialogTooltipMoonrise
        onIconNameChanged: {
            if (iconName)
                root.setTooltipCustomIcon("moonrise", iconName);
        }
    }
    KIconThemes.IconDialog {
        id: iconDialogTooltipMoonset
        onIconNameChanged: {
            if (iconName)
                root.setTooltipCustomIcon("moonset", iconName);
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
    // KDE vs Custom switch + per-condition rows + OK / Cancel (temp-state pattern).
    Dialog {
        id: conditionIconDialog
        property string context: "panel"   // "panel" | "tooltip"
        property bool useCustom: false
        property var _tempMap: ({})
        property string _tempMapStr: ""    // reactive trigger — updated alongside _tempMap

        // Weather-condition slots — one per distinct KDE icon from _conditionKdeIcon
        readonly property var conditionSlots: [
            // ── Clear ──
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
            // ── Mainly clear ──
            {
                key: "condition-few-clouds",
                label: i18n("Mainly clear (day)"),
                defaultIcon: "weather-few-clouds"
            },
            {
                key: "condition-few-clouds-night",
                label: i18n("Mainly clear (night)"),
                defaultIcon: "weather-few-clouds-night"
            },
            // ── Partly cloudy ──
            {
                key: "condition-cloudy-day",
                label: i18n("Partly cloudy (day)"),
                defaultIcon: "weather-clouds-day"
            },
            {
                key: "condition-cloudy-night",
                label: i18n("Partly cloudy (night)"),
                defaultIcon: "weather-clouds-night"
            },
            // ── Overcast ──
            {
                key: "condition-overcast",
                label: i18n("Overcast"),
                defaultIcon: "weather-many-clouds"
            },
            // ── Fog ──
            {
                key: "condition-fog",
                label: i18n("Fog"),
                defaultIcon: "weather-fog"
            },
            // ── Light rain / Drizzle ──
            {
                key: "condition-showers-scattered-day",
                label: i18n("Light rain / Drizzle (day)"),
                defaultIcon: "weather-showers-scattered-day"
            },
            {
                key: "condition-showers-scattered-night",
                label: i18n("Light rain / Drizzle (night)"),
                defaultIcon: "weather-showers-scattered-night"
            },
            // ── Rain ──
            {
                key: "condition-showers-day",
                label: i18n("Rain (day)"),
                defaultIcon: "weather-showers-day"
            },
            {
                key: "condition-showers-night",
                label: i18n("Rain (night)"),
                defaultIcon: "weather-showers-night"
            },
            // ── Freezing drizzle / Light freezing rain ──
            {
                key: "condition-freezing-scattered-rain-day",
                label: i18n("Freezing drizzle (day)"),
                defaultIcon: "weather-freezing-scattered-rain-day"
            },
            {
                key: "condition-freezing-scattered-rain-night",
                label: i18n("Freezing drizzle (night)"),
                defaultIcon: "weather-freezing-scattered-rain-night"
            },
            // ── Freezing rain ──
            {
                key: "condition-freezing-rain-day",
                label: i18n("Freezing rain (day)"),
                defaultIcon: "weather-freezing-rain-day"
            },
            {
                key: "condition-freezing-rain-night",
                label: i18n("Freezing rain (night)"),
                defaultIcon: "weather-freezing-rain-night"
            },
            // ── Light snow / Snow grains ──
            {
                key: "condition-snow-scattered-day",
                label: i18n("Light snow (day)"),
                defaultIcon: "weather-snow-scattered-day"
            },
            {
                key: "condition-snow-scattered-night",
                label: i18n("Light snow (night)"),
                defaultIcon: "weather-snow-scattered-night"
            },
            // ── Snow ──
            {
                key: "condition-snow-day",
                label: i18n("Snow (day)"),
                defaultIcon: "weather-snow-day"
            },
            {
                key: "condition-snow-night",
                label: i18n("Snow (night)"),
                defaultIcon: "weather-snow-night"
            },
            // ── Thunderstorm ──
            {
                key: "condition-storm-day",
                label: i18n("Thunderstorm (day)"),
                defaultIcon: "weather-storm-day"
            },
            {
                key: "condition-storm-night",
                label: i18n("Thunderstorm (night)"),
                defaultIcon: "weather-storm-night"
            },
            // ── Thunderstorm with hail ──
            {
                key: "condition-hail-storm-rain-day",
                label: i18n("Thunderstorm with hail (day)"),
                defaultIcon: "weather-showers-scattered-storm-day"
            },
            {
                key: "condition-hail-storm-rain-night",
                label: i18n("Thunderstorm with hail (night)"),
                defaultIcon: "weather-showers-scattered-storm-night"
            },
            // ── Thunderstorm with heavy hail ──
            {
                key: "condition-hail-storm-snow-day",
                label: i18n("Thunderstorm, heavy hail (day)"),
                defaultIcon: "weather-snow-scattered-storm-day"
            },
            {
                key: "condition-hail-storm-snow-night",
                label: i18n("Thunderstorm, heavy hail (night)"),
                defaultIcon: "weather-snow-scattered-storm-night"
            }
        ]

        // Raw config string for the active context
        function _rawConfig() {
            if (context === "tooltip")
                return root.cfg_tooltipCustomIcons;
            if (context === "widget")
                return root.cfg_widgetConditionCustomIcons;
            return root.cfg_panelCustomIcons;
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
            else if (context === "widget")
                root.cfg_widgetConditionCustomIcons = serialized;
            else
                root.cfg_panelCustomIcons = serialized;
        }

        title: i18n("Condition Icons")
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        standardButtons: Dialog.NoButton
        width: 480
        height: Math.min(implicitHeight, 600)

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

            // ── Custom mode: scrollable per-condition rows ────────────────
            ScrollView {
                visible: conditionIconDialog.useCustom
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
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

    // The configure dialog itself — shared between Panel, Tooltip and Details tabs.
    // Set context = "panel", "tooltip" or "details" before opening.
    Dialog {
        id: iconConfigDialog
        property string itemId: ""
        property string itemLabel: ""
        property string itemFallback: ""
        property bool isSuntimes: false
        property bool isMoonphase: false
        property string context: "panel"   // "panel" | "tooltip" | "details"

        function getIcon(id) {
            if (context === "tooltip")
                return root.getTooltipCustomIcon(id);
            if (context === "details")
                return root.getDetailsCustomIcon(id);
            return root.getCustomIcon(id);
        }
        function setIcon(id, name) {
            if (context === "tooltip")
                root.setTooltipCustomIcon(id, name);
            else if (context === "details")
                root.setDetailsCustomIcon(id, name);
            else
                root.setCustomIcon(id, name);
        }
        // Which icon strings to watch for reactive re-evaluation
        function watchRaw() {
            if (context === "tooltip")
                return root.cfg_tooltipCustomIcons;
            if (context === "details")
                return root.cfg_widgetDetailsCustomIcons;
            return root.cfg_panelCustomIcons;
        }

        title: i18n("Configure icon — %1", itemLabel)
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Close
        width: Math.min(implicitWidth + 40, 480)

        onOpened: {
            // Re-sync mode combos when dialog opens (may have different context)
            if (isSuntimes) {
                var sunCur = sunModeDialogCombo._currentMode();
                for (var i = 0; i < sunModeDialogCombo.model.length; ++i) {
                    if (sunModeDialogCombo.model[i].value === sunCur) {
                        sunModeDialogCombo.currentIndex = i;
                        break;
                    }
                }
            }
            if (isMoonphase) {
                var moonCur = moonModeDialogCombo._currentMode();
                for (var j = 0; j < moonModeDialogCombo.model.length; ++j) {
                    if (moonModeDialogCombo.model[j].value === moonCur) {
                        moonModeDialogCombo.currentIndex = j;
                        break;
                    }
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            // ── Single-item picker (all non-suntimes/moonphase items) ───────────────
            ColumnLayout {
                visible: !iconConfigDialog.isSuntimes && !iconConfigDialog.isMoonphase
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
                            else if (iconConfigDialog.context === "details")
                                iconDialogDetailsMain.open();
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
                    visible: false
                    text: i18n("Display mode:")
                    font.bold: true
                    opacity: 0.85
                }
                ComboBox {
                    id: sunModeDialogCombo
                    visible: false
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
                    function _currentMode() {
                        if (iconConfigDialog.context === "details")
                            return root.cfg_widgetSunTimesMode;
                        if (iconConfigDialog.context === "tooltip")
                            return root.cfg_tooltipSunTimesMode;
                        return root.cfg_panelSunTimesMode;
                    }
                    Component.onCompleted: {
                        var cur = _currentMode();
                        for (var i = 0; i < model.length; ++i)
                            if (model[i].value === cur) {
                                currentIndex = i;
                                break;
                            }
                    }
                    onActivated: {
                        var v = model[currentIndex].value;
                        if (iconConfigDialog.context === "details")
                            root.cfg_widgetSunTimesMode = v;
                        else if (iconConfigDialog.context === "tooltip")
                            root.cfg_tooltipSunTimesMode = v;
                        else
                            root.cfg_panelSunTimesMode = v;
                    }
                }

                Kirigami.Separator {
                    visible: false
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
                            else if (iconConfigDialog.context === "details")
                                iconDialogDetailsRise.open();
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
                            else if (iconConfigDialog.context === "details")
                                iconDialogDetailsSet.open();
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

            // ── Moonphase picker (moonrise + moonset + mode) ────────────────
            ColumnLayout {
                visible: iconConfigDialog.isMoonphase
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true

                // Mode selector
                Label {
                    visible: false
                    text: i18n("Display mode:")
                    font.bold: true
                    opacity: 0.85
                }
                ComboBox {
                    id: moonModeDialogCombo
                    visible: false
                    Layout.fillWidth: true
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Phase + moonrise & moonset"),
                            value: "full"
                        },
                        {
                            text: i18n("Phase + upcoming rise/set"),
                            value: "upcoming"
                        },
                        {
                            text: i18n("Upcoming rise/set only"),
                            value: "upcoming-times"
                        },
                        {
                            text: i18n("Moon phase only"),
                            value: "phase"
                        },
                        {
                            text: i18n("Moonrise & moonset only"),
                            value: "times"
                        },
                        {
                            text: i18n("Moonrise only"),
                            value: "moonrise"
                        },
                        {
                            text: i18n("Moonset only"),
                            value: "moonset"
                        }
                    ]
                    function _currentMode() {
                        if (iconConfigDialog.context === "panel")
                            return root.cfg_panelMoonPhaseMode;
                        if (iconConfigDialog.context === "tooltip")
                            return root.cfg_tooltipMoonPhaseMode;
                        return root.cfg_widgetMoonMode;
                    }
                    Component.onCompleted: {
                        var cur = _currentMode();
                        for (var i = 0; i < model.length; ++i)
                            if (model[i].value === cur) {
                                currentIndex = i;
                                break;
                            }
                    }
                    onActivated: {
                        var v = model[currentIndex].value;
                        if (iconConfigDialog.context === "panel")
                            root.cfg_panelMoonPhaseMode = v;
                        else if (iconConfigDialog.context === "tooltip")
                            root.cfg_tooltipMoonPhaseMode = v;
                        else
                            root.cfg_widgetMoonMode = v;
                    }
                }

                Kirigami.Separator {
                    visible: false
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                }

                // Moonrise icon
                Label {
                    text: i18n("Moonrise icon:")
                    font.bold: true
                    opacity: 0.85
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true

                    Kirigami.Icon {
                        source: {
                            var _w = iconConfigDialog.watchRaw();
                            var saved = iconConfigDialog.getIcon("moonrise");
                            return saved.length > 0 ? saved : "weather-clear-night";
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
                                iconDialogTooltipMoonrise.open();
                            else if (iconConfigDialog.context === "details")
                                iconDialogDetailsMoonrise.open();
                            else
                                iconDialogMoonrise.open();
                        }
                    }
                    Button {
                        text: i18n("Reset")
                        icon.name: "edit-undo"
                        enabled: {
                            var _w = iconConfigDialog.watchRaw();
                            return iconConfigDialog.getIcon("moonrise").length > 0;
                        }
                        onClicked: iconConfigDialog.setIcon("moonrise", "")
                    }
                }

                // Moonset icon
                Label {
                    text: i18n("Moonset icon:")
                    font.bold: true
                    opacity: 0.85
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true

                    Kirigami.Icon {
                        source: {
                            var _w = iconConfigDialog.watchRaw();
                            var saved = iconConfigDialog.getIcon("moonset");
                            return saved.length > 0 ? saved : "weather-clear-night";
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
                                iconDialogTooltipMoonset.open();
                            else if (iconConfigDialog.context === "details")
                                iconDialogDetailsMoonset.open();
                            else
                                iconDialogMoonset.open();
                        }
                    }
                    Button {
                        text: i18n("Reset")
                        icon.name: "edit-undo"
                        enabled: {
                            var _w = iconConfigDialog.watchRaw();
                            return iconConfigDialog.getIcon("moonset").length > 0;
                        }
                        onClicked: iconConfigDialog.setIcon("moonset", "")
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
    property string cfg_panelItemIcons: "location=1;condition=1;temperature=1;suntimes=1;wind=1;feelslike=1;humidity=1;pressure=1;moonphase=1;preciprate=1;uvindex=1;airquality=1;pollen=1;alerts=1;snowcover=1"
    property string cfg_panelSeparator: " \u2022 "
    property string cfg_panelSunTimesMode: "upcoming"
    property string cfg_panelMoonPhaseMode: "full"   // "full" | "upcoming" | "upcoming-times" | "phase" | "times" | "moonrise" | "moonset"
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
    property string cfg_panelSimpleHorizontalContent: "both"
    property int cfg_panelSimpleWidgetOrder: 0
    property string cfg_panelSimpleIconStyle: "symbolic"
    // Compressed badge options
    property string cfg_compressedBadgePosition: "bottom-right"
    property int cfg_compressedBadgeSpacing: 0
    property string cfg_compressedBadgeColor: ""
    property double cfg_compressedBadgeOpacity: 0.85

    // ── Widget config aliases ─────────────────────────────────────────────
    property string cfg_tooltipStyle: "verbose"
    property string cfg_forecastLayout: "rows"
    property int cfg_forecastDays: 5
    property string cfg_forecastIconTheme: "symbolic"
    property bool cfg_forecastShowSunEvents: true
    property bool cfg_roundValues: true
    property bool cfg_showScrollbox: true
    property bool cfg_showUpdateText: true
    // Issue #7: widgetDetailsOrder replaces individual booleans
    property string cfg_widgetDetailsOrder: "feelslike;humidity;pressure;wind;dewpoint;visibility;moonphase;suntimes"
    property string cfg_widgetDetailsItemIcons: "feelslike=1;humidity=1;pressure=1;wind=1;suntimes=1;dewpoint=1;visibility=1;moonphase=1;preciprate=1;uvindex=1;airquality=1;pollen=1;alerts=1;snowcover=1"
    property string cfg_widgetDetailsCustomIcons: ""
    property string cfg_widgetDetailsLayout: "cards2"  // "cards2" | "list"
    property string cfg_widgetSunTimesMode: "both"   // "both" | "sunrise" | "sunset" | "upcoming"
    property string cfg_widgetMoonMode: "full"        // "full" | "upcoming" | "times"
    property int cfg_widgetIconSize: 16
    property string cfg_widgetIconTheme: "symbolic"   // "kde" | "wi-font" | "flat-color" | "symbolic" | "3d-oxygen"
    property string cfg_conditionIconTheme: "kde"      // controls main hero condition icon in widget popup
    property string cfg_widgetConditionCustomIcons: ""   // custom per-condition icons for the widget popup
    property string cfg_widgetDefaultTab: "details"  // "details" | "forecast"
    property int cfg_widgetWidth: 0       // 0 = default 540 px
    property int cfg_widgetHeight: 0       // 0 = default 500 px
    property string cfg_widgetMinWidthMode: "auto"   // "auto" = 750, "manual" = user-set
    property int cfg_widgetMinWidth: 750
    property string cfg_widgetMinHeightMode: "auto"
    property int cfg_widgetMinHeight: 750
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
    property bool cfg_widgetExpandedCardsHeightAuto: false
    property int cfg_widgetExpandedCardsHeight: 200

    // ── Tooltip config aliases ────────────────────────────────────────────
    property string cfg_tooltipItemOrder: "temperature;wind;humidity;pressure;suntimes"
    property string cfg_tooltipItemIcons: "temperature=1;condition=1;feelslike=1;wind=1;humidity=1;pressure=1;suntimes=1;moonphase=1;preciprate=1;uvindex=1;airquality=1;pollen=1;alerts=1;snowcover=1"
    property string cfg_tooltipIconTheme: "symbolic"
    property int cfg_tooltipIconSize: 22
    property string cfg_tooltipCustomIcons: ""
    property bool cfg_tooltipEnabled: true
    property bool cfg_tooltipUseIcons: true
    property string cfg_tooltipSunTimesMode: "both" // "both" | "sunrise" | "sunset" | "upcoming"
    property string cfg_tooltipMoonPhaseMode: "full"  // "full" | "upcoming" | "upcoming-times" | "phase" | "times" | "moonrise" | "moonset"
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
    property bool cfg_showTempUnit: false

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
    property int cfg_simpleIconAutoSz: 0   // written by CompactView; read-only here
    property int cfg_simpleFontAutoSz: 0   // written by CompactView; read-only here
    // Panel geometry written back by CompactView so the config page can
    // recompute auto sizes for the CURRENTLY SELECTED layout type even
    // before the user clicks Apply (config dialog buffers cfg_* values).
    property int cfg_simplePanelDim: 48        // _fullPanelW (vertical) or _fullPanelH (horizontal)
    property bool cfg_simplePanelIsVertical: false

    // Compute auto icon size for a given layout type using the live panel dim.
    // Mirrors CompactView simpleIconSz formula exactly.
    function _autoIconSz(lt) {
        var dim = root.cfg_simplePanelDim > 0 ? root.cfg_simplePanelDim : 48;
        if (root.cfg_simplePanelIsVertical)
            return lt === 0 ? Math.max(16, Math.round(dim / 2)) : Math.max(16, dim);
        else
            return lt === 1 ? Math.max(16, Math.round(dim / 2)) : Math.max(16, dim);
    }
    // Compute auto font size for a given layout type using the live panel dim.
    // Mirrors CompactView simpleFontSz formula exactly.
    function _autoFontSz(lt) {
        var dim = root.cfg_simplePanelDim > 0 ? root.cfg_simplePanelDim : 48;
        if (root.cfg_simplePanelIsVertical)
            return Math.max(8, Math.round(dim / 3));
        else
            return lt === 1 ? Math.max(8, Math.round(dim / 3)) : Math.max(8, Math.round(dim * 11 / 24));
    }

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
    // ── Details custom icon map helpers ──────────────────────────────────
    function setDetailsCustomIcon(itemId, iconName) {
        var m = parseCustomIcons(root.cfg_widgetDetailsCustomIcons);
        if (iconName.length > 0)
            m[itemId] = iconName;
        else
            delete m[itemId];
        root.cfg_widgetDetailsCustomIcons = serializeCustomIcons(m);
    }
    function getDetailsCustomIcon(itemId) {
        var m = parseCustomIcons(root.cfg_widgetDetailsCustomIcons);
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
        },
        {
            itemId: "preciprate",
            label: i18n("Precipitation"),
            description: i18n("Precipitation rate (mm/h)"),
            wiChar: "\uF04E",
            iconFallback: "weather-showers"
        },
        {
            itemId: "precipsum",
            label: i18n("Precipitation Sum"),
            description: i18n("Today's total precipitation (mm/in)"),
            wiChar: "\uF07C",
            iconFallback: "flood"
        },
        {
            itemId: "uvindex",
            label: i18n("UV Index"),
            description: i18n("Ultraviolet index"),
            wiChar: "\uF072",
            iconFallback: "weather-clear"
        },
        {
            itemId: "airquality",
            label: i18n("Air Quality"),
            description: i18n("Air quality index"),
            wiChar: "\uF074",
            iconFallback: "weather-many-clouds"
        },
        {
            itemId: "pollen",
            label: i18n("Pollen"),
            description: i18n("Dominant pollen type and index"),
            wiChar: "\uF082",
            iconFallback: "sandstorm"
        },
        {
            itemId: "spaceweather",
            label: i18n("Space Weather"),
            description: i18n("NOAA Kp index and geomagnetic activity"),
            wiChar: "\uF06E",
            iconFallback: "weather-clear-night"
        },
        {
            itemId: "alerts",
            label: i18n("Alerts"),
            description: i18n("Weather alerts"),
            wiChar: "\uF0CE",
            iconFallback: "weather-storm"
        },
        {
            itemId: "snowcover",
            label: i18n("Snow Cover"),
            description: i18n("Snow depth (cm/in)"),
            wiChar: "\uF076",
            iconFallback: "weather-snow-scattered"
        }
    ]

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
            wiChar: "\uF078",
            iconFallback: "raindrop"
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
            label: i18n("Moon phase and moonrise/moonset"),
            description: i18n("Moon phase, moonrise & moonset"),
            wiChar: "\uF0D0",
            iconFallback: "weather-clear-night"
        },
        {
            itemId: "preciprate",
            label: i18n("Precipitation"),
            description: i18n("Precipitation rate (mm/h)"),
            wiChar: "\uF04E",
            iconFallback: "weather-showers"
        },
        {
            itemId: "precipsum",
            label: i18n("Precipitation Sum"),
            description: i18n("Today's total precipitation (mm/in)"),
            wiChar: "\uF07C",
            iconFallback: "flood"
        },
        {
            itemId: "uvindex",
            label: i18n("UV Index"),
            description: i18n("Ultraviolet index"),
            wiChar: "\uF072",
            iconFallback: "weather-clear"
        },
        {
            itemId: "airquality",
            label: i18n("Air Quality"),
            description: i18n("Air quality index"),
            wiChar: "\uF074",
            iconFallback: "weather-many-clouds"
        },
        {
            itemId: "pollen",
            label: i18n("Pollen"),
            description: i18n("Dominant pollen type and index"),
            wiChar: "\uF082",
            iconFallback: "sandstorm"
        },
        {
            itemId: "spaceweather",
            label: i18n("Space Weather"),
            description: i18n("NOAA Kp index and geomagnetic activity"),
            wiChar: "\uF06E",
            iconFallback: "weather-clear-night"
        },
        {
            itemId: "alerts",
            label: i18n("Alerts"),
            description: i18n("Weather alerts"),
            wiChar: "\uF0CE",
            iconFallback: "weather-storm"
        },
        {
            itemId: "snowcover",
            label: i18n("Snow Cover"),
            description: i18n("Snow depth (cm/in)"),
            wiChar: "\uF076",
            iconFallback: "weather-snow-scattered"
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
            label: i18n("Moon phase and moonrise/moonset"),
            description: i18n("Moon phase, moonrise & moonset"),
            wiChar: "\uF0D0",
            iconFallback: "weather-clear-night"
        },
        {
            itemId: "preciprate",
            label: i18n("Precipitation"),
            description: i18n("Precipitation rate (mm/h)"),
            wiChar: "\uF04E",
            iconFallback: "weather-showers"
        },
        {
            itemId: "precipsum",
            label: i18n("Precipitation Sum"),
            description: i18n("Today's total precipitation (mm/in)"),
            wiChar: "\uF07C",
            iconFallback: "flood"
        },
        {
            itemId: "uvindex",
            label: i18n("UV Index"),
            description: i18n("Ultraviolet index"),
            wiChar: "\uF072",
            iconFallback: "weather-clear"
        },
        {
            itemId: "airquality",
            label: i18n("Air Quality"),
            description: i18n("Air quality index"),
            wiChar: "\uF074",
            iconFallback: "weather-many-clouds"
        },
        {
            itemId: "pollen",
            label: i18n("Pollen"),
            description: i18n("Dominant pollen type and index"),
            wiChar: "\uF082",
            iconFallback: "sandstorm"
        },
        {
            itemId: "spaceweather",
            label: i18n("Space Weather"),
            description: i18n("NOAA Kp index and geomagnetic activity"),
            wiChar: "\uF06E",
            iconFallback: "solar-eclipse"
        },
        {
            itemId: "alerts",
            label: i18n("Alerts"),
            description: i18n("Weather alerts"),
            wiChar: "\uF0CE",
            iconFallback: "weather-storm"
        },
        {
            itemId: "snowcover",
            label: i18n("Snow Cover"),
            description: i18n("Snow depth (cm/in)"),
            wiChar: "\uF076",
            iconFallback: "weather-snow-scattered"
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
            var v = (d.itemId in map) ? map[d.itemId] : true;
            return d.itemId + "=" + (v !== false ? "1" : "0");
        }).join(";");
    }
    /**
     * _initItemModel — shared helper for panel / details / tooltip item lists.
     * model     : ListModel to populate
     * defs      : allPanelItemDefs / allDetailsDefs / allTooltipDefs
     * orderStr  : semicolon-separated enabled order string
     * extraFn   : optional function(def, tok, iconMap) → extra fields object
     */
    function _initItemModel(model, defs, orderStr, extraFn) {
        model.clear();
        var enabled = orderStr.split(";").map(function (t) {
            return t.trim();
        }).filter(function (t) {
            return t.length > 0;
        });
        enabled.forEach(function (tok) {
            for (var j = 0; j < defs.length; ++j) {
                if (defs[j].itemId === tok) {
                    var entry = {
                        itemId: defs[j].itemId,
                        itemLabel: defs[j].label,
                        itemDesc: defs[j].description,
                        itemEnabled: true,
                        itemWiChar: defs[j].wiChar,
                        itemFallback: defs[j].iconFallback
                    };
                    if (extraFn)
                        Object.assign(entry, extraFn(defs[j], tok));
                    model.append(entry);
                    break;
                }
            }
        });
        defs.forEach(function (def) {
            if (enabled.indexOf(def.itemId) < 0) {
                var entry = {
                    itemId: def.itemId,
                    itemLabel: def.label,
                    itemDesc: def.description,
                    itemEnabled: false,
                    itemWiChar: def.wiChar,
                    itemFallback: def.iconFallback
                };
                if (extraFn)
                    Object.assign(entry, extraFn(def, def.itemId));
                model.append(entry);
            }
        });
    }

    function initPanelModel() {
        var iconMap = parsePanelItemIcons();
        _initItemModel(panelWorkingModel, allPanelItemDefs, cfg_panelItemOrder, function (def, tok) {
            return {
                itemShowIcon: (tok in iconMap) ? iconMap[tok] : true
            };
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
    // Details items helpers
    // ─────────────────────────────────────────────────────────────────────
    function parseDetailsItemIcons() {
        var raw = cfg_widgetDetailsItemIcons || "";
        var map = {};
        raw.split(";").forEach(function (pair) {
            var kv = pair.split("=");
            if (kv.length === 2)
                map[kv[0].trim()] = (kv[1].trim() === "1");
        });
        return map;
    }
    function serializeDetailsItemIcons(map) {
        return allDetailsDefs.map(function (d) {
            var v = (d.itemId in map) ? map[d.itemId] : true;
            return d.itemId + "=" + (v !== false ? "1" : "0");
        }).join(";");
    }
    function initDetailsModel() {
        // Ensure arc cards always present (migrate old configs)
        var raw = cfg_widgetDetailsOrder.split(";").map(function (t) {
            return t.trim();
        }).filter(function (t) {
            return t.length > 0;
        });
        if (raw.indexOf("suntimes") < 0)
            raw.push("suntimes");
        if (raw.indexOf("moonphase") < 0)
            raw.push("moonphase");
        var iconMap = parseDetailsItemIcons();
        _initItemModel(detailsWorkingModel, allDetailsDefs, raw.join(";"), function (def, tok) {
            return {
                itemShowIcon: (tok in iconMap) ? iconMap[tok] : true
            };
        });
    }
    function applyDetailsItems() {
        var ids = [], iconMap = {};
        for (var i = 0; i < detailsWorkingModel.count; ++i) {
            var item = detailsWorkingModel.get(i);
            iconMap[item.itemId] = item.itemShowIcon;
            if (item.itemEnabled)
                ids.push(item.itemId);
        }
        cfg_widgetDetailsOrder = ids.join(";");
        cfg_widgetDetailsItemIcons = serializeDetailsItemIcons(iconMap);
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
            var v = (d.itemId in map) ? map[d.itemId] : true;
            return d.itemId + "=" + (v !== false ? "1" : "0");
        }).join(";");
    }
    function firstTooltipDisabledIndex() {
        for (var i = 0; i < tooltipWorkingModel.count; ++i)
            if (!tooltipWorkingModel.get(i).itemEnabled)
                return i;
        return -1;
    }
    function initTooltipModel() {
        var iconMap = parseTooltipItemIcons();
        _initItemModel(tooltipWorkingModel, allTooltipDefs, cfg_tooltipItemOrder, function (def, tok) {
            return {
                itemShowIcon: (tok in iconMap) ? iconMap[tok] : true
            };
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
                ConfigPanelTab {
                    configRoot: root
                    onPushSubPage: stack.push(panelSubPage)
                }

                // ════════════════════════════════════════════════════════
                // TAB 1 — WIDGET
                // ════════════════════════════════════════════════════════
                ConfigWidgetTab {
                    configRoot: root
                    onPushSubPage: stack.push(detailsSubPage)
                }

                // ════════════════════════════════════════════════════════
                // TAB 2 — TOOLTIP
                // ════════════════════════════════════════════════════════
                ConfigTooltipTab {
                    configRoot: root
                    onPushSubPage: stack.push(tooltipSubPage)
                }

                // TAB 3 — MISC (renamed from Units; includes Round Values)
                // ════════════════════════════════════════════════════════
                ConfigMiscTab {
                    configRoot: root
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SUB-PAGE: Panel Items
    // ════════════════════════════════════════════════════════════════════════
    // Panel items sub-page — extracted to ConfigPanelSubPage.qml
    Component {
        id: panelSubPage
        ConfigPanelSubPage {
            configRoot: root
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SUB-PAGE: Widget Details Items — full parity with Panel Items sub-page
    // ════════════════════════════════════════════════════════════════════════
    // Details items sub-page — extracted to ConfigDetailsSubPage.qml
    Component {
        id: detailsSubPage
        ConfigDetailsSubPage {
            configRoot: root
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SUB-PAGE: Tooltip Items — full parity with Panel Items sub-page
    // ════════════════════════════════════════════════════════════════════════
    // Tooltip items sub-page — extracted to ConfigTooltipSubPage.qml
    Component {
        id: tooltipSubPage
        ConfigTooltipSubPage {
            configRoot: root
        }
    }
}
