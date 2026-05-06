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
 * ConfigDetailsSubPage — extracted from configAppearance.qml
 * Requires: required property var configRoot
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

ColumnLayout {
    id: detailsSubPageRoot
    required property var configRoot
    required property var workingModel   // pass detailsWorkingModel or simpleWorkingModel at push time
    property string mode: "details"   // "details" | "simple"
    spacing: 0

    readonly property bool isSimple: mode === "simple"

    // Redirect to the right config key / model / helpers based on mode
    property string _savedOrder:       isSimple ? configRoot.cfg_widgetSimpleDetailsOrder       : configRoot.cfg_widgetDetailsOrder
    property string _savedIcons:       isSimple ? configRoot.cfg_widgetSimpleDetailsItemIcons    : configRoot.cfg_widgetDetailsItemIcons
    property string _savedCustomIcons: isSimple ? "" : configRoot.cfg_widgetDetailsCustomIcons

    function _applyItems()   { isSimple ? configRoot.applySimpleItems()   : configRoot.applyDetailsItems(); }
    function _firstDisabled(){ return isSimple ? configRoot.firstSimpleDisabledIndex() : configRoot.firstDetailsDisabledIndex(); }

    Component.onCompleted: isSimple ? configRoot.initSimpleModel() : configRoot.initDetailsModel()

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
                    if (detailsSubPageRoot.isSimple) {
                        configRoot.cfg_widgetSimpleDetailsOrder = detailsSubPageRoot._savedOrder;
                        configRoot.cfg_widgetSimpleDetailsItemIcons = detailsSubPageRoot._savedIcons;
                    } else {
                        configRoot.cfg_widgetDetailsOrder = detailsSubPageRoot._savedOrder;
                        configRoot.cfg_widgetDetailsItemIcons = detailsSubPageRoot._savedIcons;
                        configRoot.cfg_widgetDetailsCustomIcons = detailsSubPageRoot._savedCustomIcons;
                    }
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
                var curOrder = detailsSubPageRoot.isSimple ? configRoot.cfg_widgetSimpleDetailsOrder : configRoot.cfg_widgetDetailsOrder;
                var curIcons = detailsSubPageRoot.isSimple ? configRoot.cfg_widgetSimpleDetailsItemIcons : configRoot.cfg_widgetDetailsItemIcons;
                var curCustom = detailsSubPageRoot.isSimple ? "" : configRoot.cfg_widgetDetailsCustomIcons;
                if (curOrder !== detailsSubPageRoot._savedOrder || curIcons !== detailsSubPageRoot._savedIcons || curCustom !== detailsSubPageRoot._savedCustomIcons)
                    detailsLeaveDialog.open();
                else
                    stack.pop();
            }
        }
        Label {
            Layout.fillWidth: true
            text: detailsSubPageRoot.isSimple ? i18n("Simple Mode Items") : i18n("Details Items")
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
            model: detailsSubPageRoot.workingModel
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
                property bool settingsExpanded: false
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
                                    var boundary = detailsSubPageRoot._firstDisabled();
                                    var clamped = (boundary < 0) ? newIndex : Math.min(newIndex, boundary - 1);
                                    if (clamped !== oldIndex)
                                        detailsSubPageRoot.workingModel.move(oldIndex, clamped, 1);
                                }
                                onDropped: detailsSubPageRoot._applyItems()
                            }
                            // ── Item icon — mirrors the active widget icon theme ──
                            Item {
                                visible: !((model.itemId === "suntimes" || model.itemId === "moonphase") && configRoot.cfg_widgetIconTheme === "kde")
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                opacity: model.itemEnabled ? 1.0 : 0.35
                                // wi-font glyph
                                Text {
                                    anchors.centerIn: parent
                                    text: model.itemWiChar
                                    font.family: configRoot.wiFontReady ? configRoot.wiFontFamily : ""
                                    font.pixelSize: Kirigami.Units.iconSizes.smallMedium - 2
                                    color: Kirigami.Theme.textColor
                                    visible: configRoot.cfg_widgetIconTheme === "wi-font" && model.itemWiChar.length > 0 && configRoot.wiFontReady
                                }
                                // KDE / wi-font fallback
                                Kirigami.Icon {
                                    anchors.fill: parent
                                    source: model.itemFallback
                                    visible: (configRoot.cfg_widgetIconTheme === "wi-font" && (model.itemWiChar.length === 0 || !configRoot.wiFontReady)) || configRoot.cfg_widgetIconTheme === "kde"
                                    color: Kirigami.Theme.textColor
                                }
                                // KDE custom icon (overridden by the user)
                                Kirigami.Icon {
                                    anchors.fill: parent
                                    visible: configRoot.cfg_widgetIconTheme === "kde" && configRoot.getDetailsCustomIcon(model.itemId).length > 0
                                    source: {
                                        var _w = configRoot.cfg_widgetDetailsCustomIcons;
                                        var saved = configRoot.getDetailsCustomIcon(model.itemId);
                                        return saved.length > 0 ? saved : "";
                                    }
                                    color: Kirigami.Theme.textColor
                                }
                                // SVG theme icon (symbolic / flat-color / 3d-oxygen)
                                Kirigami.Icon {
                                    anchors.fill: parent
                                    visible: configRoot.cfg_widgetIconTheme !== "wi-font" && configRoot.cfg_widgetIconTheme !== "kde" && configRoot.cfg_widgetIconTheme.length > 0
                                    source: {
                                        var th = configRoot.cfg_widgetIconTheme;
                                        if (!th || th === "wi-font" || th === "kde")
                                            return "";
                                        var b = configRoot.iconsBase + th + "/16/wi-";
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
                                            return b + "moon-alt-full.svg";
                                        if (id === "visibility")
                                            return b + "fog.svg";
                                        if (id === "condition")
                                            return b + "day-cloudy.svg";
                                        if (id === "preciprate")
                                            return b + "raindrop.svg";
                                        if (id === "precipsum")
                                            return b + "flood.svg";
                                        if (id === "uvindex")
                                            return b + "hot.svg";
                                        if (id === "airquality")
                                            return b + "smog.svg";
                                        if (id === "alerts")
                                            return b + "storm-warning.svg";
                                        if (id === "snowcover")
                                            return b + "snowflake-cold.svg";
                                        if (id === "pollen")
                                            return b + "sandstorm.svg";
                                        if (id === "spaceweather")
                                            return b + "stars.svg";
                                        if (id === "datetime")
                                            return b + "time-3.svg";
                                        return "";
                                    }
                                    isMask: configRoot.cfg_widgetIconTheme === "symbolic"
                                    color: Kirigami.Theme.textColor
                                }
                            }
                            // ── Dual icons for suntimes (KDE themes) ─────────────
                            Row {
                                visible: model.itemId === "suntimes" && configRoot.cfg_widgetIconTheme === "kde"
                                spacing: 2
                                opacity: model.itemEnabled ? 1.0 : 0.35
                                Kirigami.Icon {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    source: {
                                        var _w = configRoot.cfg_widgetDetailsCustomIcons;
                                        var saved = configRoot.getDetailsCustomIcon("suntimes-sunrise");
                                        return saved.length > 0 ? saved : "weather-clear";
                                    }
                                    color: Kirigami.Theme.textColor
                                }
                                Kirigami.Separator {
                                    width: 1
                                    height: Kirigami.Units.iconSizes.smallMedium
                                }
                                Kirigami.Icon {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    source: {
                                        var _w = configRoot.cfg_widgetDetailsCustomIcons;
                                        var saved = configRoot.getDetailsCustomIcon("suntimes-sunset");
                                        return saved.length > 0 ? saved : "weather-clear";
                                    }
                                    color: Kirigami.Theme.textColor
                                }
                            }
                            // ── Dual icons for moonphase (KDE themes) ────────────
                            Row {
                                visible: model.itemId === "moonphase" && configRoot.cfg_widgetIconTheme === "kde"
                                spacing: 2
                                opacity: model.itemEnabled ? 1.0 : 0.35
                                Kirigami.Icon {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    source: {
                                        var _w = configRoot.cfg_widgetDetailsCustomIcons;
                                        var saved = configRoot.getDetailsCustomIcon("moonrise");
                                        return saved.length > 0 ? saved : "weather-clear-night";
                                    }
                                    color: Kirigami.Theme.textColor
                                }
                                Kirigami.Separator {
                                    width: 1
                                    height: Kirigami.Units.iconSizes.smallMedium
                                }
                                Kirigami.Icon {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    source: {
                                        var _w = configRoot.cfg_widgetDetailsCustomIcons;
                                        var saved = configRoot.getDetailsCustomIcon("moonset");
                                        return saved.length > 0 ? saved : "weather-clear-night";
                                    }
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
                            // ── Configure button (suntimes / moonphase / airquality / pollen / spaceweather / datetime) ──────────
                            ToolButton {
                                visible: model.itemId === "suntimes" || model.itemId === "moonphase" || model.itemId === "airquality" || model.itemId === "pollen" || model.itemId === "spaceweather" || model.itemId === "datetime"
                                enabled: model.itemEnabled
                                opacity: model.itemEnabled ? 1.0 : 0.3
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                icon.name: "configure"
                                checkable: true
                                checked: detailsDelegateRoot.settingsExpanded
                                ToolTip.visible: hovered
                                ToolTip.text: {
                                    if (model.itemId === "suntimes") return i18n("Sun times options");
                                    if (model.itemId === "moonphase") return i18n("Moon phase options");
                                    if (model.itemId === "airquality") return i18n("Air quality options");
                                    if (model.itemId === "pollen") return i18n("Pollen options");
                                    if (model.itemId === "spaceweather") return i18n("Space weather options");
                                    if (model.itemId === "datetime")     return i18n("Date / Time options");
                                    return i18n("Options");
                                }
                                onClicked: detailsDelegateRoot.settingsExpanded = !detailsDelegateRoot.settingsExpanded
                            }
                            // ── Configure icon button (KDE themes, suntimes/moonphase) — opens shared iconConfigDialog ──
                            ToolButton {
                                visible: configRoot.cfg_widgetIconTheme === "kde" && (model.itemId === "suntimes" || model.itemId === "moonphase")
                                enabled: model.itemEnabled
                                opacity: model.itemEnabled ? 1.0 : 0.3
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                icon.name: "color-picker"
                                ToolTip.visible: hovered
                                ToolTip.text: i18n("Configure icon\u2026")
                                onClicked: {
                                    iconConfigDialog.context = "details";
                                    iconConfigDialog.itemId = model.itemId;
                                    iconConfigDialog.itemLabel = model.itemLabel;
                                    iconConfigDialog.itemFallback = model.itemFallback;
                                    iconConfigDialog.isSuntimes = (model.itemId === "suntimes");
                                    iconConfigDialog.isMoonphase = (model.itemId === "moonphase");
                                    iconConfigDialog.open();
                                }
                            }
                            // ── Icon picker button (KDE themes, non-suntimes/moonphase) ──
                            ToolButton {
                                visible: configRoot.cfg_widgetIconTheme === "kde" && model.itemId !== "suntimes" && model.itemId !== "moonphase"
                                enabled: model.itemEnabled
                                opacity: model.itemEnabled ? 1.0 : 0.3
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                icon.name: "color-picker"
                                ToolTip.visible: hovered
                                ToolTip.text: i18n("Configure icon\u2026")
                                onClicked: {
                                    iconConfigDialog.context = "details";
                                    iconConfigDialog.itemId = model.itemId;
                                    iconConfigDialog.itemLabel = model.itemLabel;
                                    iconConfigDialog.itemFallback = model.itemFallback;
                                    iconConfigDialog.isSuntimes = false;
                                    iconConfigDialog.isMoonphase = false;
                                    iconConfigDialog.open();
                                }
                            }
                            // ── Eye toggle — show/hide prefix icon ────────────────
                            ToolButton {
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                enabled: model.itemEnabled
                                opacity: model.itemEnabled ? 1.0 : 0.25
                                icon.name: model.itemShowIcon ? "view-visible" : "view-hidden"
                                ToolTip.visible: hovered
                                ToolTip.text: model.itemShowIcon ? i18n("Hide prefix icon") : i18n("Show prefix icon")
                                onClicked: {
                                    detailsSubPageRoot.workingModel.setProperty(model.index, "itemShowIcon", !model.itemShowIcon);
                                    detailsSubPageRoot._applyItems();
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
                                    var wm = detailsSubPageRoot.workingModel;
                                    if (!nowOn)
                                        detailsDelegateRoot.settingsExpanded = false;
                                    wm.setProperty(idx, "itemEnabled", nowOn);
                                    var boundary = detailsSubPageRoot._firstDisabled();
                                    if (nowOn) {
                                        if (boundary > 0 && idx >= boundary)
                                            wm.move(idx, boundary - 1, 1);
                                    } else {
                                        var lastEnabled = -1;
                                        for (var i = 0; i < wm.count; ++i)
                                            if (wm.get(i).itemEnabled)
                                                lastEnabled = i;
                                        if (lastEnabled >= 0 && idx <= lastEnabled)
                                            wm.move(idx, lastEnabled, 1);
                                        else if (lastEnabled < 0 && idx > 0)
                                            wm.move(idx, 0, 1);
                                    }
                                    detailsSubPageRoot._applyItems();
                                }
                            }
                        }
                    }
                    // ── Inline suntimes options (non-KDE themes) ──────────
                    RowLayout {
                        visible: model.itemId === "suntimes" && detailsDelegateRoot.settingsExpanded
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
                                    text: i18n("Both (sunrise & sunset)"),
                                    value: "both"
                                },
                                {
                                    text: i18n("Sunrise only"),
                                    value: "sunrise"
                                },
                                {
                                    text: i18n("Sunset only"),
                                    value: "sunset"
                                },
                                {
                                    text: i18n("Upcoming (auto)"),
                                    value: "upcoming"
                                }
                            ]
                            textRole: "text"
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === configRoot.cfg_widgetSunTimesMode) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: configRoot.cfg_widgetSunTimesMode = model[currentIndex].value
                        }
                    }
                    // ── Inline moonphase options (non-KDE themes) ─────────
                    RowLayout {
                        visible: model.itemId === "moonphase" && detailsDelegateRoot.settingsExpanded
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.largeSpacing * 2
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.largeSpacing
                        Label {
                            text: i18n("Moon mode:")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                        }
                        ComboBox {
                            id: moonModeInlineCombo
                            Layout.fillWidth: true
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
                            textRole: "text"
                            Component.onCompleted: {
                                for (var i = 0; i < model.length; ++i)
                                    if (model[i].value === configRoot.cfg_widgetMoonMode) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: configRoot.cfg_widgetMoonMode = model[currentIndex].value
                        }
                    }
                    // ── Inline air quality options ─────────────────────────
                    ColumnLayout {
                        id: aqiOptions
                        visible: model.itemId === "airquality" && detailsDelegateRoot.settingsExpanded
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.largeSpacing * 2
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing
                        readonly property var __aqiAllKeys: ["pm2_5","pm10","no2","o3","so2","co"]
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: i18n("Show pollutants in expanded view:")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.8
                                Layout.fillWidth: true
                            }
                            CheckBox {
                                id: aqiAllToggle
                                text: i18n("Enable all")
                                tristate: true
                                checkState: {
                                    var n = aqiOptions.__aqiItems().length;
                                    if (n === 0) return Qt.Unchecked;
                                    if (n === aqiOptions.__aqiAllKeys.length) return Qt.Checked;
                                    return Qt.PartiallyChecked;
                                }
                                // Decide next state from the CURRENT state (before Qt auto-cycles)
                                nextCheckState: function() {
                                    var enableAll = checkState !== Qt.Checked;
                                    var newVal = enableAll ? aqiOptions.__aqiAllKeys.join(",") : "";
                                    if (newVal !== configRoot.cfg_aqiExpandedItems)
                                        configRoot.cfg_aqiExpandedItems = newVal;
                                    return enableAll ? Qt.Checked : Qt.Unchecked;
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing
                            CheckBox { text: i18n("PM2.5"); checked: aqiOptions.__aqiHas("pm2_5"); onToggled: aqiOptions.__aqiToggle("pm2_5", checked) }
                            CheckBox { text: i18n("PM10");  checked: aqiOptions.__aqiHas("pm10");  onToggled: aqiOptions.__aqiToggle("pm10", checked) }
                            CheckBox { text: i18n("NO₂");   checked: aqiOptions.__aqiHas("no2");   onToggled: aqiOptions.__aqiToggle("no2", checked) }
                            CheckBox { text: i18n("O₃");    checked: aqiOptions.__aqiHas("o3");    onToggled: aqiOptions.__aqiToggle("o3", checked) }
                            CheckBox { text: i18n("SO₂");   checked: aqiOptions.__aqiHas("so2");   onToggled: aqiOptions.__aqiToggle("so2", checked) }
                            CheckBox { text: i18n("CO");    checked: aqiOptions.__aqiHas("co");    onToggled: aqiOptions.__aqiToggle("co", checked) }
                        }
                        function __aqiItems() {
                            var s = configRoot.cfg_aqiExpandedItems;
                            if (s === undefined || s === null)
                                return ["pm2_5","pm10","no2","o3","so2","co"];
                            return s.length ? s.split(",") : [];
                        }
                        function __aqiHas(k) { return __aqiItems().indexOf(k) >= 0; }
                        function __aqiToggle(k, on) {
                            var arr = __aqiItems();
                            var i = arr.indexOf(k);
                            if (on && i < 0) arr.push(k);
                            else if (!on && i >= 0) arr.splice(i, 1);
                            var newVal = arr.join(",");
                            if (newVal !== configRoot.cfg_aqiExpandedItems)
                                configRoot.cfg_aqiExpandedItems = newVal;
                        }
                    }
                    // ── Inline pollen options ───────────────────────────────
                    ColumnLayout {
                        id: pollenOptions
                        visible: model.itemId === "pollen" && detailsDelegateRoot.settingsExpanded
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.largeSpacing * 2
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing
                        readonly property var __pollenAllKeys: ["alder","birch","grass","mugwort","olive","ragweed"]
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: i18n("Show pollen types in expanded view:")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.8
                                Layout.fillWidth: true
                            }
                            CheckBox {
                                id: pollenAllToggle
                                text: i18n("Enable all")
                                tristate: true
                                checkState: {
                                    var n = pollenOptions.__pollenItems().length;
                                    if (n === 0) return Qt.Unchecked;
                                    if (n === pollenOptions.__pollenAllKeys.length) return Qt.Checked;
                                    return Qt.PartiallyChecked;
                                }
                                nextCheckState: function() {
                                    var enableAll = checkState !== Qt.Checked;
                                    var newVal = enableAll ? pollenOptions.__pollenAllKeys.join(",") : "";
                                    if (newVal !== configRoot.cfg_pollenExpandedItems)
                                        configRoot.cfg_pollenExpandedItems = newVal;
                                    return enableAll ? Qt.Checked : Qt.Unchecked;
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing
                            CheckBox { text: i18n("Alder");   checked: pollenOptions.__pollenHas("alder");   onToggled: pollenOptions.__pollenToggle("alder", checked) }
                            CheckBox { text: i18n("Birch");   checked: pollenOptions.__pollenHas("birch");   onToggled: pollenOptions.__pollenToggle("birch", checked) }
                            CheckBox { text: i18n("Grass");   checked: pollenOptions.__pollenHas("grass");   onToggled: pollenOptions.__pollenToggle("grass", checked) }
                            CheckBox { text: i18n("Mugwort"); checked: pollenOptions.__pollenHas("mugwort"); onToggled: pollenOptions.__pollenToggle("mugwort", checked) }
                            CheckBox { text: i18n("Olive");   checked: pollenOptions.__pollenHas("olive");   onToggled: pollenOptions.__pollenToggle("olive", checked) }
                            CheckBox { text: i18n("Ragweed"); checked: pollenOptions.__pollenHas("ragweed"); onToggled: pollenOptions.__pollenToggle("ragweed", checked) }
                        }
                        function __pollenItems() {
                            var s = configRoot.cfg_pollenExpandedItems;
                            if (s === undefined || s === null)
                                return ["alder","birch","grass","mugwort","olive","ragweed"];
                            return s.length ? s.split(",") : [];
                        }
                        function __pollenHas(k) { return __pollenItems().indexOf(k) >= 0; }
                        function __pollenToggle(k, on) {
                            var arr = __pollenItems();
                            var i = arr.indexOf(k);
                            if (on && i < 0) arr.push(k);
                            else if (!on && i >= 0) arr.splice(i, 1);
                            var newVal = arr.join(",");
                            if (newVal !== configRoot.cfg_pollenExpandedItems)
                                configRoot.cfg_pollenExpandedItems = newVal;
                        }
                    }
                    // ── Inline space weather options ────────────────────────
                    ColumnLayout {
                        id: swOptions
                        visible: model.itemId === "spaceweather" && detailsDelegateRoot.settingsExpanded
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.largeSpacing * 2
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing
                        readonly property var __swAllKeys: ["gscale","kp","solarwind","aurora","bz","xray"]
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: i18n("Show space weather items in expanded view:")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.8
                                Layout.fillWidth: true
                            }
                            CheckBox {
                                id: swAllToggle
                                text: i18n("Enable all")
                                tristate: true
                                checkState: {
                                    var n = swOptions.__swItems().length;
                                    if (n === 0) return Qt.Unchecked;
                                    if (n === swOptions.__swAllKeys.length) return Qt.Checked;
                                    return Qt.PartiallyChecked;
                                }
                                nextCheckState: function() {
                                    var enableAll = checkState !== Qt.Checked;
                                    var newVal = enableAll ? swOptions.__swAllKeys.join(",") : "";
                                    if (newVal !== configRoot.cfg_spaceWeatherExpandedItems)
                                        configRoot.cfg_spaceWeatherExpandedItems = newVal;
                                    return enableAll ? Qt.Checked : Qt.Unchecked;
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing
                            CheckBox { text: i18n("Geomagnetic Storm"); checked: swOptions.__swHas("gscale");    onToggled: swOptions.__swToggle("gscale", checked) }
                            CheckBox { text: i18n("Kp Index");            checked: swOptions.__swHas("kp");       onToggled: swOptions.__swToggle("kp", checked) }
                            CheckBox { text: i18n("Solar Wind");          checked: swOptions.__swHas("solarwind"); onToggled: swOptions.__swToggle("solarwind", checked) }
                            CheckBox { text: i18n("Aurora Visibility");  checked: swOptions.__swHas("aurora");   onToggled: swOptions.__swToggle("aurora", checked) }
                            CheckBox { text: i18n("Magnetic Field (Bz)"); checked: swOptions.__swHas("bz");      onToggled: swOptions.__swToggle("bz", checked) }
                            CheckBox { text: i18n("X-ray Flare Class");  checked: swOptions.__swHas("xray");    onToggled: swOptions.__swToggle("xray", checked) }
                        }
                        function __swItems() {
                            var s = configRoot.cfg_spaceWeatherExpandedItems;
                            if (s === undefined || s === null)
                                return ["gscale","kp","solarwind","aurora","bz","xray"];
                            return s.length ? s.split(",") : [];
                        }
                        function __swHas(k) { return __swItems().indexOf(k) >= 0; }
                        function __swToggle(k, on) {
                            var arr = __swItems();
                            var i = arr.indexOf(k);
                            if (on && i < 0) arr.push(k);
                            else if (!on && i >= 0) arr.splice(i, 1);
                            var newVal = arr.join(",");
                            if (newVal !== configRoot.cfg_spaceWeatherExpandedItems)
                                configRoot.cfg_spaceWeatherExpandedItems = newVal;
                        }
                    }
                    // ── Inline datetime options ─────────────────────────────
                    ColumnLayout {
                        visible: model.itemId === "datetime" && detailsDelegateRoot.settingsExpanded
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.largeSpacing * 2
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing
                        // Date row
                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Switch {
                                id: detailsDtDateSwitch
                                checked: configRoot.cfg_detailsDateTimeFormat !== ""
                                onToggled: {
                                    if (!checked) {
                                        configRoot.cfg_detailsDateTimeFormat = "";
                                    } else {
                                        var ps = detailsDtDateCombo._presets;
                                        var v = ps[detailsDtDateCombo.currentIndex].value;
                                        configRoot.cfg_detailsDateTimeFormat = (v === "__custom__" || v === "") ? "locale-long" : v;
                                    }
                                }
                            }
                            Label {
                                text: i18n("Date:")
                                font: Kirigami.Theme.smallFont
                                opacity: detailsDtDateSwitch.checked ? 0.8 : 0.4
                            }
                            ComboBox {
                                id: detailsDtDateCombo
                                Layout.fillWidth: true
                                enabled: detailsDtDateSwitch.checked
                                textRole: "text"
                                readonly property var _presets: [
                                    { text: i18n("Region default (short)"), value: "locale-short" },
                                    { text: i18n("Region default (long)"),  value: "locale-long"  },
                                    { text: "Mon, Jan 1  (ddd, MMM d)",     value: "ddd, MMM d"   },
                                    { text: "01/01/2025  (dd/MM/yyyy)",     value: "dd/MM/yyyy"   },
                                    { text: "2025-01-01  (yyyy-MM-dd)",     value: "yyyy-MM-dd"   },
                                    { text: i18n("Custom…"),              value: "__custom__"   }
                                ]
                                model: _presets
                                Component.onCompleted: {
                                    var v = configRoot.cfg_detailsDateTimeFormat || "locale-long";
                                    for (var i = 0; i < _presets.length - 1; ++i)
                                        if (_presets[i].value === v) { currentIndex = i; return; }
                                    currentIndex = _presets.length - 1;
                                }
                                onActivated: {
                                    var val = _presets[currentIndex].value;
                                    if (val !== "__custom__") configRoot.cfg_detailsDateTimeFormat = val;
                                }
                            }
                            TextField {
                                visible: detailsDtDateSwitch.checked && detailsDtDateCombo.currentIndex === detailsDtDateCombo._presets.length - 1
                                Layout.preferredWidth: 100
                                placeholderText: "ddd, MMM d"
                                text: {
                                    var v = configRoot.cfg_detailsDateTimeFormat;
                                    var ps = detailsDtDateCombo._presets;
                                    for (var i = 0; i < ps.length - 1; ++i)
                                        if (ps[i].value === v) return "";
                                    return v;
                                }
                                onEditingFinished: if (text.trim().length > 0) configRoot.cfg_detailsDateTimeFormat = text.trim()
                            }
                        }
                        // Time row
                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Switch {
                                id: detailsDtTimeSwitch
                                checked: configRoot.cfg_detailsTimeFormat !== ""
                                onToggled: {
                                    if (!checked) {
                                        configRoot.cfg_detailsTimeFormat = "";
                                    } else {
                                        var ps = detailsDtTimeCombo._presets;
                                        var v = ps[detailsDtTimeCombo.currentIndex].value;
                                        configRoot.cfg_detailsTimeFormat = (v === "__custom__" || v === "") ? "locale" : v;
                                    }
                                }
                            }
                            Label {
                                text: i18n("Time:")
                                font: Kirigami.Theme.smallFont
                                opacity: detailsDtTimeSwitch.checked ? 0.8 : 0.4
                            }
                            Switch {
                                id: detailsDt24hSwitch
                                visible: detailsDtTimeSwitch.checked
                                checked: !(configRoot.cfg_detailsTimeFormat === "h:mm AP" || configRoot.cfg_detailsTimeFormat === "h:mm:ss AP")
                                ToolTip.visible: hovered
                                ToolTip.text: checked ? i18n("24-hour format") : i18n("12-hour format")
                                onToggled: {
                                    var cur = configRoot.cfg_detailsTimeFormat;
                                    if (!checked) {
                                        configRoot.cfg_detailsTimeFormat = (cur === "HH:mm:ss") ? "h:mm:ss AP" : "h:mm AP";
                                    } else {
                                        configRoot.cfg_detailsTimeFormat = (cur === "h:mm:ss AP") ? "HH:mm:ss" : "HH:mm";
                                    }
                                }
                            }
                            Label {
                                visible: detailsDtTimeSwitch.checked
                                text: detailsDt24hSwitch.checked ? i18n("24h") : i18n("12h")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                            }
                            ComboBox {
                                id: detailsDtTimeCombo
                                Layout.fillWidth: true
                                enabled: detailsDtTimeSwitch.checked
                                textRole: "text"
                                readonly property var _presets: [
                                    { text: i18n("Region default"),  value: "locale"     },
                                    { text: "14:30  (HH:mm)",        value: "HH:mm"      },
                                    { text: "14:30:05  (HH:mm:ss)",  value: "HH:mm:ss"   },
                                    { text: "2:30 PM  (h:mm AP)",    value: "h:mm AP"    },
                                    { text: i18n("Custom…"),        value: "__custom__" }
                                ]
                                model: _presets
                                Component.onCompleted: {
                                    var v = configRoot.cfg_detailsTimeFormat || "locale";
                                    for (var i = 0; i < _presets.length - 1; ++i)
                                        if (_presets[i].value === v) { currentIndex = i; return; }
                                    currentIndex = _presets.length - 1;
                                }
                                onActivated: {
                                    var val = _presets[currentIndex].value;
                                    if (val !== "__custom__") configRoot.cfg_detailsTimeFormat = val;
                                }
                            }
                            TextField {
                                visible: detailsDtTimeSwitch.checked && detailsDtTimeCombo.currentIndex === detailsDtTimeCombo._presets.length - 1
                                Layout.preferredWidth: 100
                                placeholderText: "HH:mm"
                                text: {
                                    var v = configRoot.cfg_detailsTimeFormat;
                                    var ps = detailsDtTimeCombo._presets;
                                    for (var i = 0; i < ps.length - 1; ++i)
                                        if (ps[i].value === v) return "";
                                    return v;
                                }
                                onEditingFinished: if (text.trim().length > 0) configRoot.cfg_detailsTimeFormat = text.trim()
                            }
                        }
                        // First day of week row
                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Label {
                                text: i18n("First day of week:")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.8
                            }
                            ComboBox {
                                id: calFirstDowCombo
                                Layout.fillWidth: true
                                textRole: "text"
                                readonly property var _opts: [
                                    { text: i18n("Use region defaults"), value: -1 },
                                    { text: i18n("Sunday"),              value: 0  },
                                    { text: i18n("Monday"),              value: 1  },
                                    { text: i18n("Friday"),              value: 5  },
                                    { text: i18n("Saturday"),            value: 6  }
                                ]
                                model: _opts
                                currentIndex: {
                                    var v = configRoot.cfg_calendarFirstDayOfWeek;
                                    for (var i = 0; i < _opts.length; i++)
                                        if (_opts[i].value === v) return i;
                                    return 0;
                                }
                                onActivated: configRoot.cfg_calendarFirstDayOfWeek = _opts[currentIndex].value
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
                visible: configRoot.cfg_widgetIconTheme === "kde"
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
                    source: "configure"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                }
                Label {
                    text: i18n("Configure display mode options")
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
