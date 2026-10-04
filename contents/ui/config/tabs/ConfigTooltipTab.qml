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
 * ConfigTooltipTab.qml - Tooltip tab content
 *
 * Extracted from configAppearance.qml for readability.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

GridLayout {
    id: tooltipTab

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

    /** Emitted when the user clicks Configure… to push the tooltip sub-page */
    signal pushSubPage()

    // Refresh the icon theme combo after the icon theme scope dialog
    // (configAppearance.qml) applied a theme from another tab or was cancelled.
    Connections {
        target: tooltipTab.configRoot
        function onIconThemesSynced() {
            ttIconThemeCombo.syncFromConfig();
        }
    }

    // ── Enable / Disable tooltip ──────────────────────────
    Label {
        text: i18n("Tooltip:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: tooltipTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Switch {
            id: tooltipEnabledSwitch
            checked: tooltipTab.configRoot.cfg_tooltipEnabled
            onToggled: tooltipTab.configRoot.cfg_tooltipEnabled = checked
        }
        Label {
            text: tooltipEnabledSwitch.checked ? i18n("Enabled") : i18n("Disabled")
            opacity: 0.8
        }
    }

    SectionHeader {
        title: i18n("Tooltip items settings")
        Layout.columnSpan: tooltipTab.columns
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
    }

    // ── Location name style ──────────────────────────
    Label {
        text: i18n("Location name:")
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: tooltipTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
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
                    if (model[i].value === tooltipTab.configRoot.cfg_tooltipLocationWrap) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: tooltipTab.configRoot.cfg_tooltipLocationWrap = model[currentIndex].value
        }
    }

    // ── Tooltip size ─────────────────────────────────

    // Width
    Label {
        text: i18n("Tooltip width:")
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: tooltipTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
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
                    if (model[i].value === tooltipTab.configRoot.cfg_tooltipWidthMode) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: tooltipTab.configRoot.cfg_tooltipWidthMode = model[currentIndex].value
        }
        SpinBox {
            visible: tooltipTab.configRoot.cfg_tooltipWidthMode === "manual"
            from: 200
            to: 800
            stepSize: 10
            value: tooltipTab.configRoot.cfg_tooltipWidthManual
            onValueModified: tooltipTab.configRoot.cfg_tooltipWidthManual = value
        }
        Label {
            visible: tooltipTab.configRoot.cfg_tooltipWidthMode === "manual"
            text: i18n("px")
            opacity: 0.7
        }
    }

    // Height
    Label {
        text: i18n("Tooltip height:")
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: tooltipTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
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
                    if (model[i].value === tooltipTab.configRoot.cfg_tooltipHeightMode) {
                        currentIndex = i;
                        break;
                    }
            }
            onActivated: tooltipTab.configRoot.cfg_tooltipHeightMode = model[currentIndex].value
        }
        SpinBox {
            visible: tooltipTab.configRoot.cfg_tooltipHeightMode === "manual"
            from: 100
            to: 800
            stepSize: 10
            value: tooltipTab.configRoot.cfg_tooltipHeightManual
            onValueModified: tooltipTab.configRoot.cfg_tooltipHeightManual = value
        }
        Label {
            visible: tooltipTab.configRoot.cfg_tooltipHeightMode === "manual"
            text: i18n("px")
            opacity: 0.7
        }
    }
    Label {
        text: i18n("Prefix style:")
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: tooltipTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
        spacing: Kirigami.Units.smallSpacing
        Switch {
            id: ttUseIconsSwitch
            checked: tooltipTab.configRoot.cfg_tooltipUseIcons
            onToggled: tooltipTab.configRoot.cfg_tooltipUseIcons = checked
        }
        Label {
            text: ttUseIconsSwitch.checked ? i18n("Icons") : i18n("Text labels (Temperature, Wind\u2026)")
            opacity: 0.8
        }
    }

    // ── Tooltip icon theme selector (hidden in Text mode or disabled tooltip) ──
    Label {
        text: i18n("Icon theme:")
        visible: tooltipTab.configRoot.cfg_tooltipEnabled && tooltipTab.configRoot.cfg_tooltipUseIcons
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: tooltipTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        spacing: Kirigami.Units.largeSpacing
        visible: tooltipTab.configRoot.cfg_tooltipEnabled && tooltipTab.configRoot.cfg_tooltipUseIcons
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
                    text: i18n("Custom"),
                    value: "custom"
                }
            ]
            // Re-read cfg_tooltipIconTheme. Also called via iconThemesSynced when
            // another tab applied a theme here, or the scope dialog was cancelled.
            function syncFromConfig() {
                var idx = 0;
                for (var i = 0; i < model.length; ++i)
                    if (model[i].value === tooltipTab.configRoot.cfg_tooltipIconTheme) {
                        idx = i;
                        break;
                    }
                currentIndex = idx;
            }
            Component.onCompleted: syncFromConfig()
            // Asks "Apply everywhere / only here / Cancel" when the theme also
            // exists in other icon theme settings (see configAppearance.qml).
            onActivated: tooltipTab.configRoot.requestIconTheme("tooltip", model[currentIndex].value)
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
                    if (model[i].value === tooltipTab.configRoot.cfg_tooltipIconSize) {
                        currentIndex = i;
                        break;
                    }
                if (currentIndex < 0)
                    currentIndex = 1;
            }
            onActivated: tooltipTab.configRoot.cfg_tooltipIconSize = model[currentIndex].value
        }
    }
    // Custom theme hint (hidden in Text mode or disabled tooltip)
    Item {
        // empty label cell: keeps the control in the second column
        visible: tooltipTab.columns === 2 && (tooltipTab.configRoot.cfg_tooltipEnabled && tooltipTab.configRoot.cfg_tooltipUseIcons && ttIconThemeCombo.model[ttIconThemeCombo.currentIndex].value === "custom")
        implicitWidth: 0
        implicitHeight: 0
    }
    RowLayout {
        Layout.fillWidth: true
        visible: tooltipTab.configRoot.cfg_tooltipEnabled && tooltipTab.configRoot.cfg_tooltipUseIcons && ttIconThemeCombo.model[ttIconThemeCombo.currentIndex].value === "custom"
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
                tooltipTab.configRoot.initTooltipModel();
                tooltipTab.pushSubPage();
            }
        }
    }

    SectionHeader {
        title: i18n("Tooltip items")
        Layout.columnSpan: tooltipTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
    }
    Label {
        text: i18n("Tooltip items:")
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        Layout.topMargin: tooltipTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
    }
    Item {
        visible: tooltipTab.configRoot.cfg_tooltipEnabled
        implicitWidth: ttPreviewRow.implicitWidth
        implicitHeight: ttPreviewRow.implicitHeight
        RowLayout {
            id: ttPreviewRow
            spacing: 10
            Flow {
                spacing: 4
                Layout.maximumWidth: 260
                Repeater {
                    model: tooltipTab.configRoot.cfg_tooltipItemOrder.split(";").filter(function (t) {
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
                                for (var i = 0; i < tooltipTab.configRoot.allTooltipDefs.length; ++i)
                                    if (tooltipTab.configRoot.allTooltipDefs[i].itemId === d)
                                        return tooltipTab.configRoot.allTooltipDefs[i].label;
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
                    tooltipTab.configRoot.initTooltipModel();
                    tooltipTab.pushSubPage();
                }
            }
        }
    }

    // Invisible filler row: it lets the second column take ALL spare width, so the
    // label column keeps its width when rows are shown or hidden.
    Item { visible: tooltipTab.columns === 2; implicitWidth: 0; implicitHeight: 0 }
    Item { visible: tooltipTab.columns === 2; Layout.fillWidth: true; implicitWidth: 0; implicitHeight: 0 }
}
