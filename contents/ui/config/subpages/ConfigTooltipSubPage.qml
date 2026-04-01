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
 * ConfigTooltipSubPage — extracted from configAppearance.qml
 * Requires: required property var configRoot
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

ColumnLayout {
    id: ttSubPageRoot
    required property var configRoot
    spacing: 0
    property string _savedOrder: configRoot.cfg_tooltipItemOrder
    property string _savedIcons: configRoot.cfg_tooltipItemIcons

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
                    configRoot.cfg_tooltipItemOrder = ttSubPageRoot._savedOrder;
                    configRoot.cfg_tooltipItemIcons = ttSubPageRoot._savedIcons;
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
                if (configRoot.cfg_tooltipItemOrder !== ttSubPageRoot._savedOrder || configRoot.cfg_tooltipItemIcons !== ttSubPageRoot._savedIcons)
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
                                    var boundary = configRoot.firstTooltipDisabledIndex();
                                    var clamped = (boundary < 0) ? newIndex : Math.min(newIndex, boundary - 1);
                                    if (clamped !== oldIndex)
                                        tooltipWorkingModel.move(oldIndex, clamped, 1);
                                }
                                onDropped: configRoot.applyTooltipItems()
                            }
                            // Icon — reflects active tooltip icon theme
                            Item {
                                visible: model.itemId !== "suntimes" && model.itemId !== "moonphase"
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                opacity: model.itemEnabled ? 1.0 : 0.35
                                // wi-font char
                                Text {
                                    anchors.centerIn: parent
                                    text: model.itemWiChar
                                    font.family: configRoot.wiFontReady ? configRoot.wiFontFamily : ""
                                    font.pixelSize: Kirigami.Units.iconSizes.smallMedium - 2
                                    color: Kirigami.Theme.textColor
                                    visible: configRoot.cfg_tooltipIconTheme === "wi-font" && model.itemWiChar.length > 0 && configRoot.wiFontReady
                                }
                                // KDE / fallback icon
                                Kirigami.Icon {
                                    anchors.fill: parent
                                    source: model.itemFallback
                                    visible: (configRoot.cfg_tooltipIconTheme === "wi-font" && (model.itemWiChar.length === 0 || !configRoot.wiFontReady)) || configRoot.cfg_tooltipIconTheme === "kde"
                                }
                                // SVG theme icon
                                Kirigami.Icon {
                                    anchors.fill: parent
                                    visible: configRoot.cfg_tooltipIconTheme !== "wi-font" && configRoot.cfg_tooltipIconTheme !== "kde" && configRoot.cfg_tooltipIconTheme !== "custom" && configRoot.cfg_tooltipIconTheme.length > 0
                                    source: {
                                        var th = configRoot.cfg_tooltipIconTheme;
                                        if (!th || th === "wi-font" || th === "kde" || th === "custom")
                                            return "";
                                        var sz = configRoot.cfg_tooltipIconSize || 22;
                                        var b = configRoot.iconsBase + th + "/" + sz + "/wi-";
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
                                            return b + "moon-alt-full.svg";
                                        if (id === "condition")
                                            return b + "day-cloudy.svg";
                                        if (id === "location")
                                            return b + "wind-deg.svg";
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
                                        return "";
                                    }
                                    isMask: configRoot.cfg_tooltipIconTheme === "symbolic"
                                    color: Kirigami.Theme.textColor
                                }
                                // Custom theme
                                Kirigami.Icon {
                                    anchors.fill: parent
                                    visible: configRoot.cfg_tooltipIconTheme === "custom"
                                    source: {
                                        var _w = configRoot.cfg_tooltipCustomIcons;
                                        if (model.itemId === "condition") {
                                            var m = configRoot.parseCustomIcons(configRoot.cfg_tooltipCustomIcons);
                                            return ("condition-clear" in m && m["condition-clear"].length > 0) ? m["condition-clear"] : "weather-clear";
                                        }
                                        var saved = configRoot.getTooltipCustomIcon(model.itemId);
                                        return saved.length > 0 ? saved : model.itemFallback;
                                    }
                                }
                            }
                            // ── Dual icons for suntimes (sunrise | sunset) ───────
                            Row {
                                visible: model.itemId === "suntimes"
                                spacing: 2
                                opacity: model.itemEnabled ? 1.0 : 0.35
                                Item {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uF051"
                                        font.family: configRoot.wiFontReady ? configRoot.wiFontFamily : ""
                                        font.pixelSize: parent.width - 2
                                        color: Kirigami.Theme.textColor
                                        visible: configRoot.cfg_tooltipIconTheme === "wi-font" && configRoot.wiFontReady
                                    }
                                    Kirigami.Icon {
                                        anchors.fill: parent
                                        visible: configRoot.cfg_tooltipIconTheme !== "wi-font" || !configRoot.wiFontReady
                                        source: {
                                            var th = configRoot.cfg_tooltipIconTheme;
                                            if (th === "custom") {
                                                var _w = configRoot.cfg_tooltipCustomIcons;
                                                var s = configRoot.getTooltipCustomIcon("suntimes-sunrise");
                                                return s.length > 0 ? s : "weather-sunrise";
                                            }
                                            if (th === "kde" || th === "wi-font")
                                                return "weather-sunrise";
                                            var sz = configRoot.cfg_tooltipIconSize || 22;
                                            return configRoot.iconsBase + th + "/" + sz + "/wi-sunrise.svg";
                                        }
                                        isMask: configRoot.cfg_tooltipIconTheme === "symbolic"
                                        color: Kirigami.Theme.textColor
                                    }
                                }
                                Kirigami.Separator {
                                    width: 1
                                    height: Kirigami.Units.iconSizes.smallMedium
                                }
                                Item {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uF052"
                                        font.family: configRoot.wiFontReady ? configRoot.wiFontFamily : ""
                                        font.pixelSize: parent.width - 2
                                        color: Kirigami.Theme.textColor
                                        visible: configRoot.cfg_tooltipIconTheme === "wi-font" && configRoot.wiFontReady
                                    }
                                    Kirigami.Icon {
                                        anchors.fill: parent
                                        visible: configRoot.cfg_tooltipIconTheme !== "wi-font" || !configRoot.wiFontReady
                                        source: {
                                            var th = configRoot.cfg_tooltipIconTheme;
                                            if (th === "custom") {
                                                var _w = configRoot.cfg_tooltipCustomIcons;
                                                var s = configRoot.getTooltipCustomIcon("suntimes-sunset");
                                                return s.length > 0 ? s : "weather-sunset";
                                            }
                                            if (th === "kde" || th === "wi-font")
                                                return "weather-sunset";
                                            var sz = configRoot.cfg_tooltipIconSize || 22;
                                            return configRoot.iconsBase + th + "/" + sz + "/wi-sunset.svg";
                                        }
                                        isMask: configRoot.cfg_tooltipIconTheme === "symbolic"
                                        color: Kirigami.Theme.textColor
                                    }
                                }
                            }
                            // ── Dual icons for moonphase (moonrise | moonset) ────
                            Row {
                                visible: model.itemId === "moonphase"
                                spacing: 2
                                opacity: model.itemEnabled ? 1.0 : 0.35
                                Item {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uF0C9"
                                        font.family: configRoot.wiFontReady ? configRoot.wiFontFamily : ""
                                        font.pixelSize: parent.width - 2
                                        color: Kirigami.Theme.textColor
                                        visible: configRoot.cfg_tooltipIconTheme === "wi-font" && configRoot.wiFontReady
                                    }
                                    Kirigami.Icon {
                                        anchors.fill: parent
                                        visible: configRoot.cfg_tooltipIconTheme !== "wi-font" || !configRoot.wiFontReady
                                        source: {
                                            var th = configRoot.cfg_tooltipIconTheme;
                                            if (th === "custom") {
                                                var _w = configRoot.cfg_tooltipCustomIcons;
                                                var s = configRoot.getTooltipCustomIcon("moonrise");
                                                return s.length > 0 ? s : "weather-clear-night";
                                            }
                                            if (th === "kde" || th === "wi-font")
                                                return "weather-clear-night";
                                            var sz = configRoot.cfg_tooltipIconSize || 22;
                                            return configRoot.iconsBase + th + "/" + sz + "/wi-moonrise.svg";
                                        }
                                        isMask: configRoot.cfg_tooltipIconTheme === "symbolic"
                                        color: Kirigami.Theme.textColor
                                    }
                                }
                                Kirigami.Separator {
                                    width: 1
                                    height: Kirigami.Units.iconSizes.smallMedium
                                }
                                Item {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uF0CA"
                                        font.family: configRoot.wiFontReady ? configRoot.wiFontFamily : ""
                                        font.pixelSize: parent.width - 2
                                        color: Kirigami.Theme.textColor
                                        visible: configRoot.cfg_tooltipIconTheme === "wi-font" && configRoot.wiFontReady
                                    }
                                    Kirigami.Icon {
                                        anchors.fill: parent
                                        visible: configRoot.cfg_tooltipIconTheme !== "wi-font" || !configRoot.wiFontReady
                                        source: {
                                            var th = configRoot.cfg_tooltipIconTheme;
                                            if (th === "custom") {
                                                var _w = configRoot.cfg_tooltipCustomIcons;
                                                var s = configRoot.getTooltipCustomIcon("moonset");
                                                return s.length > 0 ? s : "weather-clear-night";
                                            }
                                            if (th === "kde" || th === "wi-font")
                                                return "weather-clear-night";
                                            var sz = configRoot.cfg_tooltipIconSize || 22;
                                            return configRoot.iconsBase + th + "/" + sz + "/wi-moonset.svg";
                                        }
                                        isMask: configRoot.cfg_tooltipIconTheme === "symbolic"
                                        color: Kirigami.Theme.textColor
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
                            // Sun times / Moon phase configure button (all themes)
                            ToolButton {
                                visible: model.itemId === "suntimes" || model.itemId === "moonphase"
                                enabled: model.itemEnabled
                                opacity: model.itemEnabled ? 1.0 : 0.3
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                icon.name: "configure"
                                checkable: true
                                checked: ttDelegateRoot.settingsExpanded
                                ToolTip.visible: hovered
                                ToolTip.text: model.itemId === "suntimes" ? i18n("Sun times options") : i18n("Moon phase options")
                                onClicked: ttDelegateRoot.settingsExpanded = !ttDelegateRoot.settingsExpanded
                            }
                            // Configure icon button (custom theme, suntimes/moonphase) — opens icon-config dialog
                            ToolButton {
                                visible: configRoot.cfg_tooltipIconTheme === "custom" && (model.itemId === "suntimes" || model.itemId === "moonphase")
                                enabled: model.itemEnabled
                                opacity: model.itemEnabled ? 1.0 : 0.3
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                icon.name: "color-picker"
                                ToolTip.visible: hovered
                                ToolTip.text: i18n("Configure icon…")
                                onClicked: {
                                    iconConfigDialog.context = "tooltip";
                                    iconConfigDialog.itemId = model.itemId;
                                    iconConfigDialog.itemLabel = model.itemLabel;
                                    iconConfigDialog.itemFallback = model.itemFallback;
                                    iconConfigDialog.isSuntimes = (model.itemId === "suntimes");
                                    iconConfigDialog.isMoonphase = (model.itemId === "moonphase");
                                    iconConfigDialog.open();
                                }
                            }
                            // Configure icon button (custom theme, other items)
                            ToolButton {
                                visible: configRoot.cfg_tooltipIconTheme === "custom" && model.itemId !== "suntimes" && model.itemId !== "moonphase"
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
                                        iconConfigDialog.isSuntimes = false;
                                        iconConfigDialog.isMoonphase = false;
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
                                    configRoot.applyTooltipItems();
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
                                    var boundary = configRoot.firstTooltipDisabledIndex();
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
                                    configRoot.applyTooltipItems();
                                }
                            }
                        }
                    }
                    // Inline suntimes mode (non-custom themes)
                    RowLayout {
                        visible: model.itemId === "suntimes" && ttDelegateRoot.settingsExpanded
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
                                    if (model[i].value === configRoot.cfg_tooltipSunTimesMode) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: configRoot.cfg_tooltipSunTimesMode = model[currentIndex].value
                        }
                    }
                    // Inline moon phase options (non-custom themes)
                    RowLayout {
                        visible: model.itemId === "moonphase" && ttDelegateRoot.settingsExpanded
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.largeSpacing * 2
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.largeSpacing
                        Label {
                            text: i18n("Moon phase mode:")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                        }
                        ComboBox {
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
                                    text: i18n("Moon phase only"),
                                    value: "phase"
                                },
                                {
                                    text: i18n("Moonrise & moonset only"),
                                    value: "times"
                                },
                                {
                                    text: i18n("Upcoming rise/set only"),
                                    value: "upcoming-times"
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
                                    if (model[i].value === configRoot.cfg_tooltipMoonPhaseMode) {
                                        currentIndex = i;
                                        break;
                                    }
                            }
                            onActivated: configRoot.cfg_tooltipMoonPhaseMode = model[currentIndex].value
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
                visible: configRoot.cfg_tooltipIconTheme === "custom"
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
