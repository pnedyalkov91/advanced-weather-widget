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
    spacing: 0
    property string _savedOrder: configRoot.cfg_widgetDetailsOrder
    property string _savedIcons: configRoot.cfg_widgetDetailsItemIcons
    property string _savedCustomIcons: configRoot.cfg_widgetDetailsCustomIcons
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
                    configRoot.cfg_widgetDetailsOrder = detailsSubPageRoot._savedOrder;
                    configRoot.cfg_widgetDetailsItemIcons = detailsSubPageRoot._savedIcons;
                    configRoot.cfg_widgetDetailsCustomIcons = detailsSubPageRoot._savedCustomIcons;
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
                if (configRoot.cfg_widgetDetailsOrder !== detailsSubPageRoot._savedOrder || configRoot.cfg_widgetDetailsItemIcons !== detailsSubPageRoot._savedIcons || configRoot.cfg_widgetDetailsCustomIcons !== detailsSubPageRoot._savedCustomIcons)
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
                                    var boundary = configRoot.firstDetailsDisabledIndex();
                                    var clamped = (boundary < 0) ? newIndex : Math.min(newIndex, boundary - 1);
                                    if (clamped !== oldIndex)
                                        detailsWorkingModel.move(oldIndex, clamped, 1);
                                }
                                onDropped: configRoot.applyDetailsItems()
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
                            // ── Configure button (suntimes / moonphase) ──────────
                            ToolButton {
                                visible: model.itemId === "suntimes" || model.itemId === "moonphase"
                                enabled: model.itemEnabled
                                opacity: model.itemEnabled ? 1.0 : 0.3
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                icon.name: "configure"
                                checkable: true
                                checked: detailsDelegateRoot.settingsExpanded
                                ToolTip.visible: hovered
                                ToolTip.text: model.itemId === "suntimes" ? i18n("Sun times options") : i18n("Moon phase options")
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
                                    detailsWorkingModel.setProperty(model.index, "itemShowIcon", !model.itemShowIcon);
                                    configRoot.applyDetailsItems();
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
                                    if (!nowOn)
                                        detailsDelegateRoot.settingsExpanded = false;
                                    detailsWorkingModel.setProperty(idx, "itemEnabled", nowOn);
                                    var boundary = configRoot.firstDetailsDisabledIndex();
                                    if (nowOn) {
                                        if (boundary > 0 && idx >= boundary)
                                            detailsWorkingModel.move(idx, boundary - 1, 1);
                                    } else {
                                        var lastEnabled = -1;
                                        for (var i = 0; i < detailsWorkingModel.count; ++i)
                                            if (detailsWorkingModel.get(i).itemEnabled)
                                                lastEnabled = i;
                                        if (lastEnabled >= 0 && idx <= lastEnabled)
                                            detailsWorkingModel.move(idx, lastEnabled, 1);
                                        else if (lastEnabled < 0 && idx > 0)
                                            detailsWorkingModel.move(idx, 0, 1);
                                    }
                                    configRoot.applyDetailsItems();
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
