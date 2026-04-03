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
 * ConfigPanelTab.qml — Panel tab content
 *
 * Extracted from configAppearance.qml for readability.
 * Contains display mode, simple mode options, multiline options,
 * separator, font, icon theme, and panel items preview.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: panelTab

    /** Reference to the root KCM (configAppearance) for cfg_* properties */
    required property var configRoot

    /** Emitted when the user clicks Configure… to push the panel sub-page */
    signal pushSubPage()

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
                if (model[i].value === panelTab.configRoot.cfg_panelInfoMode) {
                    currentIndex = i;
                    break;
                }
        }
        onActivated: panelTab.configRoot.cfg_panelInfoMode = model[currentIndex].value
    }

    // ── Vertical panel truncation warning ──
    Kirigami.InlineMessage {
        visible: panelTab.configRoot.cfg_panelInfoMode === "single" || panelTab.configRoot.cfg_panelInfoMode === "multiline"
        Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        text: i18n("In a vertical panel, long item labels may be truncated. " + "Consider using \"Simple\" mode, increasing the panel width, or reducing the font size.")
        showCloseButton: false
    }

    // ── Simple mode sub‑options ──

    Kirigami.Separator {
        visible: panelTab.configRoot.cfg_panelInfoMode !== "single" && panelTab.configRoot.cfg_panelInfoMode !== "multiline"
        Kirigami.FormData.label: i18n("Simple display mode settings")
        Kirigami.FormData.isSection: true
    }

    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple"
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
                    if (model[i].value === panelTab.configRoot.cfg_panelSimpleLayoutType) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: panelTab.configRoot.cfg_panelSimpleLayoutType = model[currentIndex].value
        }
    }

    // ── Horizontal-layout content filter ──────────────────
    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleLayoutType === 0
        Kirigami.FormData.label: i18n("Show:")
        spacing: Kirigami.Units.largeSpacing
        ComboBox {
            id: simpleHorizContentCombo
            Layout.preferredWidth: 200
            textRole: "text"
            model: [
                {
                    text: i18n("Icon and temperature"),
                    value: "both"
                },
                {
                    text: i18n("Temperature only"),
                    value: "temp_only"
                },
                {
                    text: i18n("Icon only"),
                    value: "icon_only"
                }
            ]
            Component.onCompleted: {
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === panelTab.configRoot.cfg_panelSimpleHorizontalContent) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: panelTab.configRoot.cfg_panelSimpleHorizontalContent = model[currentIndex].value
        }
    }

    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleLayoutType !== 2 && (panelTab.configRoot.cfg_panelSimpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent === "both")
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
                    if (model[i].value === panelTab.configRoot.cfg_panelSimpleWidgetOrder) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: panelTab.configRoot.cfg_panelSimpleWidgetOrder = model[currentIndex].value
        }
    }

    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && (panelTab.configRoot.cfg_panelSimpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "temp_only")
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
                },
                {
                    text: i18n("Custom…"),
                    value: "custom"
                }
            ]
            Component.onCompleted: {
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === panelTab.configRoot.cfg_panelSimpleIconStyle) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: panelTab.configRoot.cfg_panelSimpleIconStyle = model[currentIndex].value
        }
        Button {
            visible: panelTab.configRoot.cfg_panelSimpleIconStyle === "custom"
            text: i18n("Configure weather icons…")
            icon.name: "color-picker"
            onClicked: panelTab.configRoot.conditionIconDialog.openWithContext("panel")
        }
    }

    // Icon size mode
    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && (panelTab.configRoot.cfg_panelSimpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "temp_only")
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
            currentIndex: panelTab.configRoot.cfg_simpleIconSizeMode === "auto" ? 0 : 1
            onCurrentIndexChanged: {
                var newMode = model[currentIndex].value;
                if (panelTab.configRoot.cfg_simpleIconSizeMode !== newMode) {
                    panelTab.configRoot.cfg_simpleIconSizeMode = newMode;
                    if (newMode === "manual" && panelTab.configRoot.cfg_simpleIconSizeManual === 0)
                        panelTab.configRoot.cfg_simpleIconSizeManual = 32;
                }
            }
        }
        ComboBox {
            id: iconSizeSpin
            enabled: panelTab.configRoot.cfg_simpleIconSizeMode === "manual"
            Layout.preferredWidth: 90
            textRole: "text"
            property var allSizes: [
                { text: "16 px", value: 16 },
                { text: "24 px", value: 24 },
                { text: "32 px", value: 32 },
                { text: "48 px", value: 48 },
                { text: "64 px", value: 64 }
            ]
            model: panelTab.configRoot.cfg_panelSimpleIconStyle === "colorful"
                ? allSizes.filter(function(s) { return s.value <= 48; })
                : allSizes
            currentIndex: {
                if (panelTab.configRoot.cfg_simpleIconSizeMode === "auto") {
                    var target = panelTab.configRoot.cfg_simplePanelDim > 0
                        ? panelTab.configRoot._autoIconSz(panelTab.configRoot.cfg_panelSimpleLayoutType)
                        : (panelTab.configRoot.cfg_simpleIconAutoSz > 0 ? panelTab.configRoot.cfg_simpleIconAutoSz : 24);
                    var best = 0;
                    for (var i = 0; i < model.length; i++) {
                        if (Math.abs(model[i].value - target) < Math.abs(model[best].value - target))
                            best = i;
                    }
                    return best;
                }
                for (var j = 0; j < model.length; j++) {
                    if (model[j].value === panelTab.configRoot.cfg_simpleIconSizeManual)
                        return j;
                }
                return 2;
            }
            onActivated: {
                if (panelTab.configRoot.cfg_simpleIconSizeMode === "manual")
                    panelTab.configRoot.cfg_simpleIconSizeManual = model[currentIndex].value;
            }
        }
    }

    // Font size mode
    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && (panelTab.configRoot.cfg_panelSimpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
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
            currentIndex: panelTab.configRoot.cfg_simpleFontSizeMode === "auto" ? 0 : 1
            onCurrentIndexChanged: {
                var newMode = model[currentIndex].value;
                if (panelTab.configRoot.cfg_simpleFontSizeMode !== newMode) {
                    panelTab.configRoot.cfg_simpleFontSizeMode = newMode;
                    if (newMode === "manual" && panelTab.configRoot.cfg_simpleFontSizeManual === 0)
                        panelTab.configRoot.cfg_simpleFontSizeManual = 14;
                }
            }
        }
        SpinBox {
            enabled: panelTab.configRoot.cfg_simpleFontSizeMode === "manual"
            from: 8
            to: 72
            value: panelTab.configRoot.cfg_simpleFontSizeMode === "auto"
                ? (panelTab.configRoot.cfg_simplePanelDim > 0
                    ? panelTab.configRoot._autoFontSz(panelTab.configRoot.cfg_panelSimpleLayoutType)
                    : (panelTab.configRoot.cfg_simpleFontAutoSz > 0 ? panelTab.configRoot.cfg_simpleFontAutoSz : panelTab.configRoot.cfg_simpleFontSizeManual))
                : panelTab.configRoot.cfg_simpleFontSizeManual
            onValueModified: {
                if (panelTab.configRoot.cfg_simpleFontSizeMode === "manual")
                    panelTab.configRoot.cfg_simpleFontSizeManual = value;
            }
            Layout.preferredWidth: 80
        }
        Label {
            text: "px"
            opacity: 0.65
        }
    }

    // ── Compressed badge options (only in compressed layout) ───────────
    Kirigami.Separator {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleLayoutType === 2
        Kirigami.FormData.label: i18n("Temperature badge")
        Kirigami.FormData.isSection: true
    }

    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleLayoutType === 2
        Kirigami.FormData.label: i18n("Badge position:")
        spacing: Kirigami.Units.largeSpacing
        ComboBox {
            id: badgePosCombo
            Layout.preferredWidth: 200
            textRole: "text"
            model: [
                { text: i18n("Bottom Right"), value: "bottom-right" },
                { text: i18n("Bottom Left"),  value: "bottom-left"  },
                { text: i18n("Top Right"),    value: "top-right"    },
                { text: i18n("Top Left"),     value: "top-left"     },
                { text: i18n("Bottom Center"), value: "bottom-center" },
                { text: i18n("Top Center"),    value: "top-center"    }
            ]
            Component.onCompleted: {
                var cur = panelTab.configRoot.cfg_compressedBadgePosition || "bottom-right";
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === cur) { currentIndex = i; break; }
            }
            onActivated: panelTab.configRoot.cfg_compressedBadgePosition = model[currentIndex].value
        }
    }

    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleLayoutType === 2
        Kirigami.FormData.label: i18n("Badge spacing:")
        spacing: Kirigami.Units.largeSpacing
        SpinBox {
            from: -20
            to: 20
            value: panelTab.configRoot.cfg_compressedBadgeSpacing
            onValueModified: panelTab.configRoot.cfg_compressedBadgeSpacing = value
        }
        Label {
            text: "px"
            opacity: 0.65
        }
    }

    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleLayoutType === 2
        Kirigami.FormData.label: i18n("Badge background:")
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            id: badgeColorPreview
            width: 24; height: 24
            radius: 4
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
            border.width: 1
            color: {
                var c = panelTab.configRoot.cfg_compressedBadgeColor;
                if (c && c.length > 0)
                    return Qt.rgba(Qt.color(c).r, Qt.color(c).g, Qt.color(c).b,
                                   panelTab.configRoot.cfg_compressedBadgeOpacity);
                return Qt.rgba(Kirigami.Theme.backgroundColor.r,
                               Kirigami.Theme.backgroundColor.g,
                               Kirigami.Theme.backgroundColor.b,
                               panelTab.configRoot.cfg_compressedBadgeOpacity);
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: badgeColorDialog.open()
            }
        }
        TextField {
            Layout.preferredWidth: 140
            readOnly: true
            text: {
                var c = panelTab.configRoot.cfg_compressedBadgeColor;
                return (c && c.length > 0) ? c : i18n("Theme default");
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: badgeColorDialog.open()
            }
        }
        Button {
            text: i18n("Reset")
            visible: (panelTab.configRoot.cfg_compressedBadgeColor || "").length > 0
            onClicked: panelTab.configRoot.cfg_compressedBadgeColor = ""
        }
    }

    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleLayoutType === 2
        Kirigami.FormData.label: i18n("Badge opacity:")
        spacing: Kirigami.Units.largeSpacing
        Slider {
            id: badgeOpacitySlider
            Layout.preferredWidth: 160
            from: 0.0
            to: 1.0
            stepSize: 0.05
            value: panelTab.configRoot.cfg_compressedBadgeOpacity
            onMoved: panelTab.configRoot.cfg_compressedBadgeOpacity = value
        }
        Label {
            text: Math.round(panelTab.configRoot.cfg_compressedBadgeOpacity * 100) + "%"
            opacity: 0.65
            Layout.preferredWidth: 40
        }
    }

    Platform.ColorDialog {
        id: badgeColorDialog
        title: i18n("Badge Background Color")
        currentColor: {
            var c = panelTab.configRoot.cfg_compressedBadgeColor;
            return (c && c.length > 0) ? c : Kirigami.Theme.backgroundColor;
        }
        onAccepted: panelTab.configRoot.cfg_compressedBadgeColor = color.toString()
    }

    // ── Multiple lines options (hidden in Simple mode) ─────
    SpinBox {
        Kirigami.FormData.label: i18n("Scroll interval (sec):")
        visible: panelTab.configRoot.cfg_panelInfoMode === "multiline"
        from: 1
        to: 30
        value: panelTab.configRoot.cfg_panelScrollSeconds
        onValueModified: panelTab.configRoot.cfg_panelScrollSeconds = value
        ToolTip.text: i18n("How often the rows scroll to reveal the next item")
        ToolTip.visible: hovered
    }
    SpinBox {
        Kirigami.FormData.label: i18n("Lines:")
        visible: panelTab.configRoot.cfg_panelInfoMode === "multiline"
        from: 1
        to: 8
        value: panelTab.configRoot.cfg_panelMultiLines
        onValueModified: panelTab.configRoot.cfg_panelMultiLines = value
        ToolTip.text: i18n("Number of item rows visible at once. Resize the panel height in KDE settings to match.")
        ToolTip.visible: hovered
    }
    CheckBox {
        Kirigami.FormData.label: i18n("Scroll animation:")
        visible: panelTab.configRoot.cfg_panelInfoMode === "multiline"
        text: i18n("Animate row scrolling")
        checked: panelTab.configRoot.cfg_panelMultiAnimate
        onToggled: panelTab.configRoot.cfg_panelMultiAnimate = checked
    }
    // Multiline mode: icon style (symbolic vs colorful)
    RowLayout {
        Kirigami.FormData.label: i18n("Main icon style:")
        visible: panelTab.configRoot.cfg_panelInfoMode === "multiline"
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
                },
                {
                    text: i18n("Custom…"),
                    value: "custom"
                }
            ]
            Component.onCompleted: {
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === panelTab.configRoot.cfg_panelMultilineIconStyle) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: panelTab.configRoot.cfg_panelMultilineIconStyle = model[currentIndex].value
        }
        Button {
            visible: panelTab.configRoot.cfg_panelMultilineIconStyle === "custom"
            text: i18n("Configure…")
            icon.name: "color-picker"
            onClicked: panelTab.configRoot.conditionIconDialog.openWithContext("panel")
        }
        ComboBox {
            id: mlIconSizeCombo
            Layout.preferredWidth: 100
            textRole: "text"
            property var sizeModel: [
                { text: i18n("Auto"),  value: 0  },
                { text: "16 px",       value: 16 },
                { text: "24 px",       value: 24 },
                { text: "32 px",       value: 32 },
                { text: "48 px",       value: 48 },
                { text: "64 px",       value: 64 }
            ]
            model: sizeModel
            currentIndex: {
                for (var i = 0; i < sizeModel.length; i++)
                    if (sizeModel[i].value === panelTab.configRoot.cfg_panelMultilineIconSize)
                        return i;
                return 0;
            }
            onActivated: panelTab.configRoot.cfg_panelMultilineIconSize = sizeModel[currentIndex].value
        }
    }
    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode !== "simple"
        Kirigami.FormData.label: i18n("Item width:")
        spacing: 8
        SpinBox {
            from: 0
            to: 600
            value: panelTab.configRoot.cfg_panelWidth
            onValueModified: panelTab.configRoot.cfg_panelWidth = value
        }
        Label {
            text: i18n("px")
            opacity: 0.65
        }
        Label {
            text: panelTab.configRoot.cfg_panelInfoMode === "multiline" ? i18n("0 = auto. Increase if items are cut off.") : i18n("0 = auto (120 px per chip). Increase if values are truncated.")
            opacity: 0.65
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.maximumWidth: 260
        }
    }

    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode !== "multiline" && panelTab.configRoot.cfg_panelInfoMode !== "simple"
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
                    if (model[n].value === panelTab.configRoot.cfg_panelSeparator) {
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
                    panelTab.configRoot.cfg_panelSeparator = model[currentIndex].value;
            }
        }
        TextField {
            Layout.preferredWidth: 72
            visible: separatorCombo.currentIndex === separatorCombo.model.length - 1
            text: panelTab.configRoot.cfg_panelSeparator
            placeholderText: "e.g. \u203a"
            onTextChanged: panelTab.configRoot.cfg_panelSeparator = text
        }
    }
    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode !== "multiline" && panelTab.configRoot.cfg_panelInfoMode !== "simple"
        Kirigami.FormData.label: i18n("Item spacing:")
        spacing: 8
        SpinBox {
            from: 0
            to: 32
            value: panelTab.configRoot.cfg_panelItemSpacing
            onValueModified: panelTab.configRoot.cfg_panelItemSpacing = value
        }
        Label {
            text: "px"
            opacity: 0.65
        }
    }
    CheckBox {
        visible: panelTab.configRoot.cfg_panelInfoMode === "single"
        Kirigami.FormData.label: i18n("Fill panel:")
        text: i18n("Expand widget to fill available panel space")
        checked: panelTab.configRoot.cfg_panelFillWidth
        onToggled: panelTab.configRoot.cfg_panelFillWidth = checked
    }
    Kirigami.Separator {
        visible: panelTab.configRoot.cfg_panelInfoMode !== "simple"
        Kirigami.FormData.label: i18n("Panel items settings")
        Kirigami.FormData.isSection: true
    }
    // ── Panel font — Switch + native Platform.FontDialog (like KDE clock) ──
    Platform.FontDialog {
        id: panelFontDialog
        title: i18n("Choose a Panel Font")
        modality: Qt.WindowModal

        property font fontChosen: Qt.font({
            family: panelTab.configRoot.cfg_panelFontFamily || Kirigami.Theme.defaultFont.family,
            pointSize: panelTab.configRoot.cfg_panelFontSize > 0 ? panelTab.configRoot.cfg_panelFontSize : 11,
            bold: panelTab.configRoot.cfg_panelFontBold
        })
        onAccepted: {
            fontChosen = font;
            panelTab.configRoot.cfg_panelFontFamily = fontChosen.family;
            panelTab.configRoot.cfg_panelFontSize = Math.max(6, fontChosen.pointSize > 0 ? fontChosen.pointSize : 11);
            panelTab.configRoot.cfg_panelFontBold = fontChosen.bold;
            panelTab.configRoot.cfg_panelUseSystemFont = false;
        }
    }
    RowLayout {
        visible: panelTab.configRoot.cfg_panelInfoMode !== "simple"
        Kirigami.FormData.label: i18n("Panel font:")
        spacing: Kirigami.Units.smallSpacing
        Switch {
            id: panelFontSwitch
            checked: !panelTab.configRoot.cfg_panelUseSystemFont
            onToggled: {
                panelTab.configRoot.cfg_panelUseSystemFont = !checked;
                if (checked) {
                    if (panelTab.configRoot.cfg_panelFontFamily.length === 0)
                        panelTab.configRoot.cfg_panelFontFamily = Kirigami.Theme.defaultFont.family;
                } else {
                    panelTab.configRoot.cfg_panelFontSize = 0;
                }
            }
        }
        Label {
            text: panelFontSwitch.checked ? i18n("Manual") : i18n("Automatic")
            opacity: 0.8
        }
    }
    Label {
        visible: !panelFontSwitch.checked && panelTab.configRoot.cfg_panelInfoMode !== "simple"
        Kirigami.FormData.label: ""
        text: i18n("Text will follow the system font and expand to fill the available space.")
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
        Layout.maximumWidth: 300
    }
    RowLayout {
        visible: panelFontSwitch.checked && panelTab.configRoot.cfg_panelInfoMode !== "simple"
        Kirigami.FormData.label: ""
        spacing: Kirigami.Units.smallSpacing
        Button {
            text: i18nc("@action:button", "Choose Style\u2026")
            icon.name: "settings-configure"
            onClicked: {
                panelFontDialog.currentFont = panelFontDialog.fontChosen;
                panelFontDialog.open();
            }
        }
    }
    ColumnLayout {
        visible: panelFontSwitch.checked && panelTab.configRoot.cfg_panelFontFamily.length > 0 && panelTab.configRoot.cfg_panelInfoMode !== "simple"
        Kirigami.FormData.label: ""
        spacing: 2
        Label {
            text: i18nc("@info %1 size %2 family", "%1pt %2", panelFontDialog.fontChosen.pointSize > 0 ? panelFontDialog.fontChosen.pointSize : (panelTab.configRoot.cfg_panelFontSize > 0 ? panelTab.configRoot.cfg_panelFontSize : 11), panelTab.configRoot.cfg_panelFontFamily)
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
        visible: panelTab.configRoot.cfg_panelInfoMode !== "simple"
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
                    text: i18n("Symbolic (Bundled)"),
                    value: "symbolic"
                },
                {
                    text: i18n("Flat Color (Bundled)"),
                    value: "flat-color"
                },
                {
                    text: i18n("3D Oxygen (Bundled)"),
                    value: "3d-oxygen"
                },
                {
                    text: i18n("KDE Icon Theme"),
                    value: "custom"
                }
            ]
            Component.onCompleted: {
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === panelTab.configRoot.cfg_panelIconTheme) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: panelTab.configRoot.cfg_panelIconTheme = model[currentIndex].value
        }
        Label {
            text: i18n("Size:")
            visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value !== "wi-font" && panelTab.configRoot.cfg_panelInfoMode !== "simple"
            opacity: 0.8
        }
        ComboBox {
            id: iconSizeCombo
            visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value !== "wi-font" && panelTab.configRoot.cfg_panelInfoMode !== "simple"
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
                    if (model[i].value === panelTab.configRoot.cfg_panelIconSize) {
                        currentIndex = i;
                        break;
                    }
                if (currentIndex < 0)
                    currentIndex = 1;
            }
            onActivated: panelTab.configRoot.cfg_panelIconSize = model[currentIndex].value
        }
    }
    // Custom theme: description + button to open Panel Items with icon pickers
    RowLayout {
        visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value === "custom" && panelTab.configRoot.cfg_panelInfoMode !== "simple"
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
            text: i18n("Set your own icons\u2026")
            icon.name: "color-picker"
            onClicked: {
                panelTab.configRoot.initPanelModel();
                panelTab.pushSubPage();
            }
        }
    }
    // Panel items configure button + preview chips
    Item {
        visible: panelTab.configRoot.cfg_panelInfoMode !== "simple"
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
                    model: panelTab.configRoot.cfg_panelItemOrder.split(";").filter(function (t) {
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
                                for (var i = 0; i < panelTab.configRoot.allPanelItemDefs.length; ++i)
                                    if (panelTab.configRoot.allPanelItemDefs[i].itemId === d)
                                        return panelTab.configRoot.allPanelItemDefs[i].label;
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
                    panelTab.configRoot.initPanelModel();
                    panelTab.pushSubPage();
                }
            }
        }
    }
}
