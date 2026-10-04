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
 * ConfigPanelTab.qml - Panel tab content
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

GridLayout {
    id: panelTab

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

    /** Reference to the root KCM (configAppearance) for cfg_* properties */
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

    /** Emitted when the user clicks Configure… to push the panel sub-page */
    signal pushSubPage

    // Refresh the icon theme combo after the icon theme scope dialog
    // (configAppearance.qml) applied a theme from another tab or was cancelled.
    Connections {
        target: panelTab.configRoot
        function onIconThemesSynced() {
            iconThemeCombo.syncFromConfig();
            simpleIconStyleCombo.syncFromConfig();
            mlIconStyleCombo.syncFromConfig();
        }
    }

    readonly property bool isSystemTrayConfig: configRoot.isSystemTrayConfig === true
    readonly property string _panelInfoMode: isSystemTrayConfig ? "simple" : configRoot.cfg_panelInfoMode
    readonly property int _simpleLayoutType: isSystemTrayConfig ? 2 : configRoot.cfg_panelSimpleLayoutType
    readonly property string _simpleIconStyle: isSystemTrayConfig ? configRoot.cfg_traySimpleIconStyle : configRoot.cfg_panelSimpleIconStyle
    readonly property string _badgePosition: isSystemTrayConfig ? configRoot.cfg_trayCompressedBadgePosition : configRoot.cfg_compressedBadgePosition
    readonly property int _badgeSpacing: isSystemTrayConfig ? configRoot.cfg_trayCompressedBadgeSpacing : configRoot.cfg_compressedBadgeSpacing
    readonly property string _badgeColor: isSystemTrayConfig ? configRoot.cfg_trayCompressedBadgeColor : configRoot.cfg_compressedBadgeColor
    readonly property double _badgeOpacity: isSystemTrayConfig ? configRoot.cfg_trayCompressedBadgeOpacity : configRoot.cfg_compressedBadgeOpacity
    readonly property bool _isSimpleCompressed: _panelInfoMode === "simple" && _simpleLayoutType === 2

    function _setBadgePosition(value) {
        if (isSystemTrayConfig)
            configRoot.cfg_trayCompressedBadgePosition = value;
        else
            configRoot.cfg_compressedBadgePosition = value;
    }

    function _setBadgeSpacing(value) {
        if (isSystemTrayConfig)
            configRoot.cfg_trayCompressedBadgeSpacing = value;
        else
            configRoot.cfg_compressedBadgeSpacing = value;
    }

    function _setBadgeColor(value) {
        if (isSystemTrayConfig)
            configRoot.cfg_trayCompressedBadgeColor = value;
        else
            configRoot.cfg_compressedBadgeColor = value;
    }

    function _setBadgeOpacity(value) {
        if (isSystemTrayConfig)
            configRoot.cfg_trayCompressedBadgeOpacity = value;
        else
            configRoot.cfg_compressedBadgeOpacity = value;
    }

    SectionHeader {
        title: panelTab.isSystemTrayConfig ? i18n("System tray display settings") : i18n("Panel display settings")
        Layout.columnSpan: panelTab.columns
    }
    Label {
        text: i18n("Display mode:")
        visible: !panelTab.isSystemTrayConfig
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: panelModeCombo
        visible: !panelTab.isSystemTrayConfig
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

    Label {
        text: i18n("Display mode:")
        visible: panelTab.isSystemTrayConfig
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    Label {
        visible: panelTab.isSystemTrayConfig
        text: i18n("Simple (icon + temperature)")
        opacity: 0.8
    }

    // ── Vertical panel truncation warning ──
    Kirigami.InlineMessage {
        Layout.columnSpan: panelTab.columns
        visible: !panelTab.isSystemTrayConfig && (panelTab._panelInfoMode === "single" || panelTab._panelInfoMode === "multiline")
        Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        text: i18n("In a vertical panel, long item labels may be truncated. " + "Consider using \"Simple\" mode, increasing the panel width, or reducing the font size.")
        showCloseButton: false
    }

    // ── Simple mode sub‑options ──

    SectionHeader {
        title: panelTab.isSystemTrayConfig ? i18n("System tray icon settings") : i18n("Simple display mode settings")
        Layout.columnSpan: panelTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: panelTab._panelInfoMode !== "single" && panelTab._panelInfoMode !== "multiline"
    }

    Label {
        text: i18n("Layout type:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple"
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

    Label {
        text: i18n("Layout type:")
        visible: panelTab.isSystemTrayConfig
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    Label {
        visible: panelTab.isSystemTrayConfig
        text: i18n("Compressed")
        opacity: 0.8
    }

    // ── Horizontal-layout content filter ──────────────────
    Label {
        text: i18n("Show:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && panelTab._simpleLayoutType === 0
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && panelTab._simpleLayoutType === 0
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

    Label {
        text: i18n("Items Order:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && panelTab._simpleLayoutType !== 2 && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent === "both")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && panelTab._simpleLayoutType !== 2 && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent === "both")
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

    Label {
        text: i18n("Widget panel area:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple"
        spacing: Kirigami.Units.largeSpacing
        ComboBox {
            id: simpleClickAreaModeCombo
            Layout.preferredWidth: 160
            textRole: "text"
            model: [
                {
                    text: i18n("Auto"),
                    value: "auto"
                },
                {
                    text: i18n("Fill panel"),
                    value: "fill"
                },
                {
                    text: i18n("Manual"),
                    value: "manual"
                }
            ]
            currentIndex: {
                var cur = panelTab.configRoot.cfg_panelSimpleClickAreaMode || "auto";
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === cur)
                        return i;
                return 0;
            }
            onActivated: panelTab.configRoot.cfg_panelSimpleClickAreaMode = model[currentIndex].value
        }
        SpinBox {
            visible: panelTab.configRoot.cfg_panelSimpleClickAreaMode === "manual"
            from: 20
            to: 600
            value: panelTab.configRoot.cfg_panelSimpleClickAreaSize
            onValueModified: panelTab.configRoot.cfg_panelSimpleClickAreaSize = value
            Layout.preferredWidth: 90
        }
        Label {
            visible: panelTab.configRoot.cfg_panelSimpleClickAreaMode === "manual"
            text: panelTab.configRoot.cfg_simplePanelIsVertical ? i18n("px height") : i18n("px width")
            opacity: 0.65
        }
    }

    Label {
        text: i18n("Weather icon style:")
        visible: panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "temp_only")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "temp_only")
        spacing: Kirigami.Units.largeSpacing
        ComboBox {
            id: simpleIconStyleCombo
            Layout.preferredWidth: 200
            textRole: "text"
            model: panelTab.isSystemTrayConfig ? [
                {
                    text: i18n("KDE Icon Theme (Colorful)"),
                    value: "colorful"
                },
                {
                    text: i18n("KDE Icon Theme (Symbolic)"),
                    value: "symbolic"
                }
            ] : [
                {
                    text: i18n("KDE Icon Theme (Colorful)"),
                    value: "colorful"
                },
                {
                    text: i18n("KDE Icon Theme (Symbolic)"),
                    value: "symbolic"
                },
                {
                    text: i18n("Symbolic (Bundled)"),
                    value: "symbolic-bundled"
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
                    text: i18n("Meteocons (Bundled)"),
                    value: "meteocons"
                },
                {
                    text: i18n("Custom…"),
                    value: "custom"
                }
            ]
            // Re-read the simple icon style. Also called via iconThemesSynced when
            // another tab applied a theme here, or the scope dialog was cancelled.
            function syncFromConfig() {
                var idx = 0;
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === panelTab._simpleIconStyle) {
                        idx = i;
                        break;
                    }
                currentIndex = idx;
            }
            Component.onCompleted: syncFromConfig()
            // Asks "Apply everywhere / only here / Cancel" - "Colorful"/"Symbolic"
            // and "Custom…" are all automatic-or-overridden renderings of the same
            // KDE system icon source (see configAppearance.qml), so any of them can
            // trigger the dialog if another setting would change too.
            onActivated: panelTab.configRoot.requestIconTheme("panel-simple", model[currentIndex].value)
        }
        Button {
            visible: !panelTab.isSystemTrayConfig && panelTab._simpleIconStyle === "custom"
            text: i18n("Configure weather icons…")
            icon.name: "color-picker"
            // Routed through Panel Items (same destination as the Single-line/
            // Multi-line "Set your own icons…" flow) instead of jumping straight
            // to the Condition Icons dialog - the Condition row's pencil there
            // opens the identical dialog, sharing the same cfg_panelCustomIcons.
            onClicked: {
                panelTab.configRoot.initPanelModel();
                panelTab.pushSubPage();
            }
        }
    }

    // Icon size mode
    Label {
        text: i18n("Icon size:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "temp_only")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "temp_only")
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
                    text: i18n("Large"),
                    value: "large"
                },
                {
                    text: i18n("Manual"),
                    value: "manual"
                }
            ]
            currentIndex: panelTab.configRoot.cfg_simpleIconSizeMode === "large" ? 1 : (panelTab.configRoot.cfg_simpleIconSizeMode === "manual" ? 2 : 0)
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
                {
                    text: "16 px",
                    value: 16
                },
                {
                    text: "24 px",
                    value: 24
                },
                {
                    text: "32 px",
                    value: 32
                },
                {
                    text: "48 px",
                    value: 48
                },
                {
                    text: "64 px",
                    value: 64
                }
            ]
            model: panelTab._simpleIconStyle === "colorful" ? allSizes.filter(function (s) {
                return s.value <= 48;
            }) : allSizes
            currentIndex: {
                if (panelTab.configRoot.cfg_simpleIconSizeMode !== "manual") {
                    var target = panelTab.configRoot.cfg_simplePanelDim > 0 ? panelTab.configRoot._autoIconSz(panelTab._simpleLayoutType, panelTab.configRoot.cfg_simpleIconSizeMode) : (panelTab.configRoot.cfg_simpleIconAutoSz > 0 ? panelTab.configRoot.cfg_simpleIconAutoSz : 24);
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

    // ── Simple mode: font size ────────────────────────────────────────────────
    Label {
        text: i18n("Font size:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
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
                    text: i18n("Large"),
                    value: "large"
                },
                {
                    text: i18n("Manual"),
                    value: "manual"
                }
            ]
            currentIndex: panelTab.configRoot.cfg_simpleFontSizeMode === "large" ? 1 : (panelTab.configRoot.cfg_simpleFontSizeMode === "manual" ? 2 : 0)
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
            value: panelTab.configRoot.cfg_simpleFontSizeMode !== "manual" ? (panelTab.configRoot.cfg_simplePanelDim > 0 ? panelTab.configRoot._autoFontSz(panelTab._simpleLayoutType, panelTab.configRoot.cfg_simpleFontSizeMode) : (panelTab.configRoot.cfg_simpleFontAutoSz > 0 ? panelTab.configRoot.cfg_simpleFontAutoSz : panelTab.configRoot.cfg_simpleFontSizeManual)) : panelTab.configRoot.cfg_simpleFontSizeManual
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

    // ── Simple mode: temperature color ───────────────────────────────────────
    Label {
        text: i18n("Temperature color:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        spacing: Kirigami.Units.smallSpacing
        Rectangle {
            width: 24
            height: 24
            radius: 4
            opacity: panelTab.configRoot.cfg_simpleTempColorDynamic ? 0.4 : 1.0
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
            border.width: 1
            color: {
                var c = panelTab.configRoot.cfg_simpleTempColor;
                return (c && c.length > 0) ? c : Kirigami.Theme.textColor;
            }
            MouseArea {
                anchors.fill: parent
                enabled: !panelTab.configRoot.cfg_simpleTempColorDynamic
                cursorShape: Qt.PointingHandCursor
                onClicked: simpleTempColorDialog.open()
            }
        }
        TextField {
            Layout.preferredWidth: 110
            readOnly: true
            enabled: !panelTab.configRoot.cfg_simpleTempColorDynamic
            text: {
                var c = panelTab.configRoot.cfg_simpleTempColor;
                return (c && c.length > 0) ? c : i18n("Default");
            }
            MouseArea {
                anchors.fill: parent
                enabled: !panelTab.configRoot.cfg_simpleTempColorDynamic
                cursorShape: Qt.PointingHandCursor
                onClicked: simpleTempColorDialog.open()
            }
        }
        Button {
            text: i18n("Reset")
            visible: (panelTab.configRoot.cfg_simpleTempColor || "").length > 0
            enabled: !panelTab.configRoot.cfg_simpleTempColorDynamic
            onClicked: panelTab.configRoot.cfg_simpleTempColor = ""
        }
    }

    // ── Simple mode: temperature color follows the forecast curve ────────────
    Label {
        text: i18n("Color by temperature:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        spacing: Kirigami.Units.smallSpacing
        Switch {
            checked: panelTab.configRoot.cfg_simpleTempColorDynamic
            onToggled: panelTab.configRoot.cfg_simpleTempColorDynamic = checked

            ToolTip.visible: hovered
            ToolTip.text: i18n("Color the panel temperature with the same cold to hot scale as the forecast curve, instead of a fixed color.")
            ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        Label {
            text: panelTab.configRoot.cfg_simpleTempColorDynamic ? i18n("Enabled") : i18n("Disabled")
            opacity: 0.8
        }
    }

    Label {
        text: i18n("Temperature shadow:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        spacing: Kirigami.Units.largeSpacing
        Switch {
            checked: panelTab.configRoot.cfg_panelSimpleTempShadowEnabled
            onToggled: panelTab.configRoot.cfg_panelSimpleTempShadowEnabled = checked
        }
        Label {
            text: panelTab.configRoot.cfg_panelSimpleTempShadowEnabled ? i18n("Enabled") : i18n("Disabled")
            opacity: 0.8
        }
    }

    Label {
        text: i18n("Shadow intensity:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleTempShadowEnabled && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleTempShadowEnabled && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        spacing: Kirigami.Units.largeSpacing
        Slider {
            id: simpleShadowIntensitySlider
            Layout.preferredWidth: 160
            from: 0.1
            to: 1.0
            stepSize: 0.05
            value: panelTab.configRoot.cfg_panelSimpleTempShadowIntensity
            onMoved: panelTab.configRoot.cfg_panelSimpleTempShadowIntensity = value
        }
        Label {
            text: Math.round(panelTab.configRoot.cfg_panelSimpleTempShadowIntensity * 100) + "%"
            opacity: 0.65
            Layout.preferredWidth: 40
        }
    }

    Label {
        text: i18n("Shadow color:")
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleTempShadowEnabled && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: !panelTab.isSystemTrayConfig && panelTab._panelInfoMode === "simple" && panelTab.configRoot.cfg_panelSimpleTempShadowEnabled && (panelTab._simpleLayoutType !== 0 || panelTab.configRoot.cfg_panelSimpleHorizontalContent !== "icon_only")
        spacing: Kirigami.Units.smallSpacing
        Rectangle {
            width: 24
            height: 24
            radius: 4
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
            border.width: 1
            color: {
                var c = panelTab.configRoot.cfg_panelSimpleTempShadowColor;
                return (c && c.length > 0) ? c : Kirigami.Theme.backgroundColor;
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: simpleShadowColorDialog.open()
            }
        }
        TextField {
            Layout.preferredWidth: 110
            readOnly: true
            text: {
                var c = panelTab.configRoot.cfg_panelSimpleTempShadowColor;
                return (c && c.length > 0) ? c : i18n("Default");
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: simpleShadowColorDialog.open()
            }
        }
        Button {
            text: i18n("Reset")
            visible: (panelTab.configRoot.cfg_panelSimpleTempShadowColor || "").length > 0
            onClicked: panelTab.configRoot.cfg_panelSimpleTempShadowColor = ""
        }
    }

    // ── Compressed badge options (only in compressed layout) ───────────
    SectionHeader {
        title: i18n("Temperature badge")
        Layout.columnSpan: panelTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: panelTab._isSimpleCompressed
    }

    Label {
        text: i18n("Badge position:")
        visible: panelTab._isSimpleCompressed
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._isSimpleCompressed
        spacing: Kirigami.Units.largeSpacing
        ComboBox {
            id: badgePosCombo
            Layout.preferredWidth: 200
            textRole: "text"
            model: [
                {
                    text: i18n("Bottom Right"),
                    value: "bottom-right"
                },
                {
                    text: i18n("Bottom Left"),
                    value: "bottom-left"
                },
                {
                    text: i18n("Top Right"),
                    value: "top-right"
                },
                {
                    text: i18n("Top Left"),
                    value: "top-left"
                },
                {
                    text: i18n("Bottom Center"),
                    value: "bottom-center"
                },
                {
                    text: i18n("Top Center"),
                    value: "top-center"
                }
            ]
            Component.onCompleted: {
                var cur = panelTab._badgePosition || "bottom-right";
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === cur) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: panelTab._setBadgePosition(model[currentIndex].value)
        }
    }

    Label {
        text: i18n("Badge spacing:")
        visible: panelTab._isSimpleCompressed
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._isSimpleCompressed
        spacing: Kirigami.Units.largeSpacing
        SpinBox {
            from: -20
            to: 20
            value: panelTab._badgeSpacing
            onValueModified: panelTab._setBadgeSpacing(value)
        }
        Label {
            text: "px"
            opacity: 0.65
        }
    }

    Label {
        text: i18n("Badge background:")
        visible: panelTab._isSimpleCompressed
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._isSimpleCompressed
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            id: badgeColorPreview
            width: 24
            height: 24
            radius: 4
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
            border.width: 1
            color: {
                var c = panelTab._badgeColor;
                if (c && c.length > 0)
                    return Qt.rgba(Qt.color(c).r, Qt.color(c).g, Qt.color(c).b, panelTab._badgeOpacity);
                return Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, panelTab._badgeOpacity);
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
                var c = panelTab._badgeColor;
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
            visible: (panelTab._badgeColor || "").length > 0
            onClicked: panelTab._setBadgeColor("")
        }
    }

    Label {
        text: i18n("Badge opacity:")
        visible: panelTab._isSimpleCompressed
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._isSimpleCompressed
        spacing: Kirigami.Units.largeSpacing
        Slider {
            id: badgeOpacitySlider
            Layout.preferredWidth: 160
            from: 0.0
            to: 1.0
            stepSize: 0.05
            value: panelTab._badgeOpacity
            onMoved: panelTab._setBadgeOpacity(value)
        }
        Label {
            text: Math.round(panelTab._badgeOpacity * 100) + "%"
            opacity: 0.65
            Layout.preferredWidth: 40
        }
    }

    Platform.ColorDialog {
        id: badgeColorDialog
        title: panelTab.isSystemTrayConfig ? i18n("System Tray Badge Background Color") : i18n("Badge Background Color")
        currentColor: {
            var c = panelTab._badgeColor;
            return (c && c.length > 0) ? c : Kirigami.Theme.backgroundColor;
        }
        onAccepted: panelTab._setBadgeColor(color.toString())
    }

    // ── Multiple lines options (hidden in Simple mode) ─────
    Label {
        text: i18n("Scroll interval (sec):")
        visible: panelTab._panelInfoMode === "multiline"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    SpinBox {
        visible: panelTab._panelInfoMode === "multiline"
        from: 1
        to: 30
        value: panelTab.configRoot.cfg_panelScrollSeconds
        onValueModified: panelTab.configRoot.cfg_panelScrollSeconds = value
        ToolTip.text: i18n("How often the rows scroll to reveal the next item")
        ToolTip.visible: hovered
    }
    Label {
        text: i18n("Lines:")
        visible: panelTab._panelInfoMode === "multiline"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    SpinBox {
        visible: panelTab._panelInfoMode === "multiline"
        from: 1
        to: 8
        value: panelTab.configRoot.cfg_panelMultiLines
        onValueModified: panelTab.configRoot.cfg_panelMultiLines = value
        ToolTip.text: i18n("Number of item rows visible at once. Resize the panel height in KDE settings to match.")
        ToolTip.visible: hovered
    }
    Label {
        text: i18n("Scroll animation:")
        visible: panelTab._panelInfoMode === "multiline"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    CheckBox {
        visible: panelTab._panelInfoMode === "multiline"
        text: i18n("Animate row scrolling")
        checked: panelTab.configRoot.cfg_panelMultiAnimate
        onToggled: panelTab.configRoot.cfg_panelMultiAnimate = checked
    }
    // Multiline mode: icon style (symbolic vs colorful)
    Label {
        text: i18n("Main icon style:")
        visible: panelTab._panelInfoMode === "multiline"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._panelInfoMode === "multiline"
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
            // Re-read cfg_panelMultilineIconStyle. Also called via iconThemesSynced
            // when another tab applied a theme here, or the scope dialog was cancelled.
            function syncFromConfig() {
                var idx = 0;
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === panelTab.configRoot.cfg_panelMultilineIconStyle) {
                        idx = i;
                        break;
                    }
                currentIndex = idx;
            }
            Component.onCompleted: syncFromConfig()
            // Asks "Apply everywhere / only here / Cancel" - "Colorful"/"Symbolic"
            // and "Custom…" are all automatic-or-overridden renderings of the same
            // KDE system icon source (see configAppearance.qml), so any of them can
            // trigger the dialog if another setting would change too.
            onActivated: panelTab.configRoot.requestIconTheme("panel-multiline", model[currentIndex].value)
        }
        Button {
            visible: panelTab.configRoot.cfg_panelMultilineIconStyle === "custom"
            text: i18n("Configure…")
            icon.name: "color-picker"
            // Routed through Panel Items, matching every other panel-mode entry
            // point - the Condition row's pencil there opens the identical
            // dialog, sharing the same cfg_panelCustomIcons.
            onClicked: {
                panelTab.configRoot.initPanelModel();
                panelTab.pushSubPage();
            }
        }
        ComboBox {
            id: mlIconSizeCombo
            Layout.preferredWidth: 100
            textRole: "text"
            property var sizeModel: [
                {
                    text: i18n("Auto"),
                    value: 0
                },
                {
                    text: "16 px",
                    value: 16
                },
                {
                    text: "24 px",
                    value: 24
                },
                {
                    text: "32 px",
                    value: 32
                },
                {
                    text: "48 px",
                    value: 48
                },
                {
                    text: "64 px",
                    value: 64
                }
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
    Label {
        text: i18n("Item width:")
        visible: panelTab._panelInfoMode !== "simple"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        Layout.fillWidth: true
        visible: panelTab._panelInfoMode !== "simple"
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
            text: panelTab._panelInfoMode === "multiline" ? i18n("0 = auto. Increase if items are cut off.") : i18n("0 = auto (120 px per chip). Increase if values are truncated.")
            opacity: 0.65
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.maximumWidth: 260
        }
    }

    Label {
        text: i18n("Separator:")
        visible: panelTab._panelInfoMode !== "multiline" && panelTab._panelInfoMode !== "simple"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._panelInfoMode !== "multiline" && panelTab._panelInfoMode !== "simple"
        spacing: 6
        ComboBox {
            id: separatorCombo
            Layout.preferredWidth: 185
            model: [
                {
                    text: i18n("Bullet  \u2022"),
                    value: "\u2022"
                },
                {
                    text: i18n("Pipe  |"),
                    value: "|"
                },
                {
                    text: i18n("Dash  \u2013"),
                    value: "\u2013"
                },
                {
                    text: i18n("None"),
                    value: ""
                },
                {
                    text: i18n("Small circle  \u26ac"),
                    value: "\u26ac"
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
    Label {
        text: i18n("Item spacing:")
        visible: panelTab._panelInfoMode !== "multiline" && panelTab._panelInfoMode !== "simple"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._panelInfoMode !== "multiline" && panelTab._panelInfoMode !== "simple"
        spacing: 8
        SpinBox {
            id: itemSpacingSpin
            from: -16
            to: 32
            value: panelTab.configRoot.cfg_panelItemSpacing
            onValueModified: panelTab.configRoot.cfg_panelItemSpacing = value
        }
        Label {
            text: "px"
            opacity: 0.65
        }
    }
    Kirigami.InlineMessage {
        Layout.columnSpan: panelTab.columns
        visible: panelTab._panelInfoMode !== "multiline" && panelTab._panelInfoMode !== "simple" && panelTab.configRoot.cfg_panelItemSpacing < 0
        Layout.fillWidth: true
        type: Kirigami.MessageType.Warning
        text: i18n("Negative spacing pulls panel items closer together than their natural gap and can make icons or text overlap.")
        showCloseButton: false
    }
    Label {
        text: i18n("Fill panel:")
        visible: panelTab._panelInfoMode === "single"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    CheckBox {
        visible: panelTab._panelInfoMode === "single"
        text: i18n("Expand widget to fill available panel space")
        checked: panelTab.configRoot.cfg_panelFillWidth
        onToggled: panelTab.configRoot.cfg_panelFillWidth = checked
    }
    SectionHeader {
        title: i18n("Panel items settings")
        Layout.columnSpan: panelTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: panelTab._panelInfoMode !== "simple"
    }
    // ── Simple mode font style dialog ─────────────────────────────────────────
    Platform.FontDialog {
        id: simpleFontDialog
        title: i18n("Choose Simple Mode Font")
        modality: Qt.WindowModal
        property font fontChosen: Qt.font({
            family: panelTab.configRoot.cfg_simpleFontFamily || Kirigami.Theme.defaultFont.family,
            pointSize: panelTab.configRoot.cfg_simpleFontSizeManual > 0 ? panelTab.configRoot.cfg_simpleFontSizeManual : 14,
            bold: panelTab.configRoot.cfg_simpleFontBold
        })
        onAccepted: {
            fontChosen = font;
            panelTab.configRoot.cfg_simpleFontFamily = fontChosen.family;
            panelTab.configRoot.cfg_simpleFontBold = fontChosen.bold;
        }
    }

    // ── Simple mode temperature color dialog ──────────────────────────────────
    Platform.ColorDialog {
        id: simpleTempColorDialog
        title: i18n("Temperature Color")
        currentColor: {
            var c = panelTab.configRoot.cfg_simpleTempColor;
            return (c && c.length > 0) ? c : Kirigami.Theme.textColor;
        }
        onAccepted: panelTab.configRoot.cfg_simpleTempColor = color.toString()
    }

    // ── Simple mode shadow color dialog ───────────────────────────────────────
    Platform.ColorDialog {
        id: simpleShadowColorDialog
        title: i18n("Shadow Color")
        currentColor: {
            var c = panelTab.configRoot.cfg_panelSimpleTempShadowColor;
            return (c && c.length > 0) ? c : Kirigami.Theme.backgroundColor;
        }
        onAccepted: panelTab.configRoot.cfg_panelSimpleTempShadowColor = color.toString()
    }

    // ── Panel font - Switch + native Platform.FontDialog (like KDE clock) ──
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
    Label {
        text: i18n("Panel font:")
        visible: panelTab._panelInfoMode !== "simple"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._panelInfoMode !== "simple"
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
    Item {
        // empty label cell: keeps the control in the second column
        visible: panelTab.columns === 2 && (!panelFontSwitch.checked && panelTab._panelInfoMode !== "simple")
        implicitWidth: 0
        implicitHeight: 0
    }
    Label {
        visible: !panelFontSwitch.checked && panelTab._panelInfoMode !== "simple"
        text: i18n("Text will follow the system font and expand to fill the available space.")
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.maximumWidth: 300
    }
    Item {
        // empty label cell: keeps the control in the second column
        visible: panelTab.columns === 2 && (panelFontSwitch.checked && panelTab._panelInfoMode !== "simple")
        implicitWidth: 0
        implicitHeight: 0
    }
    RowLayout {
        visible: panelFontSwitch.checked && panelTab._panelInfoMode !== "simple"
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
    Item {
        // empty label cell: keeps the control in the second column
        visible: panelTab.columns === 2 && (panelFontSwitch.checked && panelTab.configRoot.cfg_panelFontFamily.length > 0 && panelTab._panelInfoMode !== "simple")
        implicitWidth: 0
        implicitHeight: 0
    }
    ColumnLayout {
        visible: panelFontSwitch.checked && panelTab.configRoot.cfg_panelFontFamily.length > 0 && panelTab._panelInfoMode !== "simple"
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
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.maximumWidth: 300
        }
    }
    // Icon theme selector
    Label {
        text: i18n("Icon theme:")
        visible: panelTab._panelInfoMode !== "simple"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: panelTab._panelInfoMode !== "simple"
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
                    text: i18n("Meteocons (Bundled)"),
                    value: "meteocons"
                },
                {
                    text: i18n("KDE Icon Theme"),
                    value: "custom"
                }
            ]
            // Re-read cfg_panelIconTheme. Also called via iconThemesSynced when
            // another tab applied a theme here, or the scope dialog was cancelled.
            function syncFromConfig() {
                var idx = 0;
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === panelTab.configRoot.cfg_panelIconTheme) {
                        idx = i;
                        break;
                    }
                currentIndex = idx;
            }
            Component.onCompleted: syncFromConfig()
            // Asks "Apply everywhere / only here / Cancel" when the theme also
            // exists in other icon theme settings (see configAppearance.qml).
            onActivated: panelTab.configRoot.requestIconTheme("panel", model[currentIndex].value)
        }
        Label {
            text: i18n("Size:")
            visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value !== "wi-font" && panelTab._panelInfoMode !== "simple"
            opacity: 0.8
        }
        ComboBox {
            id: iconSizeCombo
            visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value !== "wi-font" && panelTab._panelInfoMode !== "simple"
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
    Item {
        // empty label cell: keeps the control in the second column
        visible: panelTab.columns === 2 && (iconThemeCombo.model[iconThemeCombo.currentIndex].value === "custom" && panelTab._panelInfoMode !== "simple")
        implicitWidth: 0
        implicitHeight: 0
    }
    RowLayout {
        Layout.fillWidth: true
        visible: iconThemeCombo.model[iconThemeCombo.currentIndex].value === "custom" && panelTab._panelInfoMode !== "simple"
        spacing: Kirigami.Units.largeSpacing
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: Kirigami.Units.smallSpacing
            Label {
                text: i18n("Uses KDE system icons by default. Click the button to customise each item's icon.")
                opacity: 0.65
                font: Kirigami.Theme.smallFont
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.minimumWidth: 0
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
    Label {
        text: i18n("Panel items:")
        visible: panelTab._panelInfoMode !== "simple"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        Layout.topMargin: panelTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
    }
    Item {
        visible: panelTab._panelInfoMode !== "simple"
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

    // Invisible filler row: it lets the second column take ALL spare width, so the
    // label column keeps its width when rows are shown or hidden.
    Item { visible: panelTab.columns === 2; implicitWidth: 0; implicitHeight: 0 }
    Item { visible: panelTab.columns === 2; Layout.fillWidth: true; implicitWidth: 0; implicitHeight: 0 }
}
