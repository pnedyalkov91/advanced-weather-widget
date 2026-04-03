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
 * ConfigWidgetTab.qml — Widget tab with sub-tabs: General, Details, Forecast
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: widgetTab
    spacing: 0

    /** Reference to the root KCM (configAppearance) for cfg_* properties */
    required property var configRoot

    /** Emitted when the user clicks Configure… to push the details sub-page */
    signal pushSubPage()

    /** Icon theme choices shared by all combos */
    readonly property var iconThemeModel: [
        { text: i18n("KDE Icon Theme"),        value: "kde"          },
        { text: i18n("Symbolic (Bundled)"),        value: "symbolic"     },
        { text: i18n("Flat Color (Bundled)"),      value: "flat-color"   },
        { text: i18n("3D Oxygen (Bundled)"),       value: "3d-oxygen"    }
    ]

    /** Condition icon theme choices — adds KDE Symbolic and Custom options */
    readonly property var conditionIconThemeModel: [
        { text: i18n("KDE Icon Theme"),        value: "kde"          },
        { text: i18n("KDE Symbolic"),          value: "kde-symbolic" },
        { text: i18n("Symbolic (Bundled)"),        value: "symbolic"     },
        { text: i18n("Flat Color (Bundled)"),      value: "flat-color"   },
        { text: i18n("3D Oxygen (Bundled)"),       value: "3d-oxygen"    },
        { text: i18n("Custom\u2026"),          value: "custom"       }
    ]

    function findThemeIndex(theme) {
        if (theme === "wi-font") theme = "symbolic";
        for (var i = 0; i < iconThemeModel.length; ++i)
            if (iconThemeModel[i].value === theme) return i;
        return 0;
    }

    function findConditionThemeIndex(theme) {
        if (theme === "wi-font") theme = "symbolic";
        for (var i = 0; i < conditionIconThemeModel.length; ++i)
            if (conditionIconThemeModel[i].value === theme) return i;
        return 0;
    }

    PlasmaComponents.TabBar {
        id: subTabBar
        Layout.fillWidth: true
        PlasmaComponents.TabButton {
            icon.name: "preferences-system-windows"
            text: i18n("General")
        }
        PlasmaComponents.TabButton {
            icon.name: "view-list-details"
            text: i18n("Details")
        }
        PlasmaComponents.TabButton {
            icon.name: "weather-few-clouds"
            text: i18n("Forecast")
        }
    }

    Item { Layout.preferredHeight: Kirigami.Units.largeSpacing }

    StackLayout {
        currentIndex: subTabBar.currentIndex
        Layout.fillWidth: true
        Layout.fillHeight: true

        // ── SUB-TAB 0: General ────────────────────────────────────────
        Kirigami.FormLayout {
            RowLayout {
                Kirigami.FormData.label: i18n("Weather icon theme:")
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: conditionIconThemeCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: widgetTab.conditionIconThemeModel
                    Component.onCompleted: currentIndex = widgetTab.findConditionThemeIndex(
                        widgetTab.configRoot.cfg_conditionIconTheme)
                    onActivated: widgetTab.configRoot.cfg_conditionIconTheme = model[currentIndex].value
                }
            }
            Button {
                visible: widgetTab.configRoot.cfg_conditionIconTheme === "custom"
                text: i18n("Configure weather icons\u2026")
                icon.name: "configure"
                onClicked: widgetTab.configRoot.conditionIconDialog.openWithContext("widget")
            }
            RowLayout {
                Kirigami.FormData.label: i18n("Default tab:")
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: defaultTabCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: [
                        { text: i18n("Details"),  value: "details"  },
                        { text: i18n("Forecast"), value: "forecast" }
                    ]
                    Component.onCompleted: currentIndex = widgetTab.configRoot.cfg_widgetDefaultTab === "forecast" ? 1 : 0
                    onActivated: widgetTab.configRoot.cfg_widgetDefaultTab = model[currentIndex].value
                }
            }
            CheckBox {
                Kirigami.FormData.label: i18n("Footer:")
                text: i18n("Show update time and provider")
                checked: widgetTab.configRoot.cfg_showUpdateText
                onToggled: widgetTab.configRoot.cfg_showUpdateText = checked
            }

            // ── Minimum popup size ────────────────────────────────────
            RowLayout {
                Kirigami.FormData.label: i18n("Minimum width:")
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: minWidthModeCombo
                    Layout.preferredWidth: 130
                    textRole: "text"
                    model: [
                        { text: i18n("Auto"),   value: "auto"   },
                        { text: i18n("Manual"), value: "manual" }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual" ? 1 : 0
                    onActivated: widgetTab.configRoot.cfg_widgetMinWidthMode = model[currentIndex].value
                }
                SpinBox {
                    enabled: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual"
                    from: 200
                    to: 2000
                    stepSize: 10
                    value: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual"
                        ? widgetTab.configRoot.cfg_widgetMinWidth : 750
                    onValueModified: widgetTab.configRoot.cfg_widgetMinWidth = value
                }
                Label {
                    text: "px"
                    opacity: 0.65
                }
            }
            RowLayout {
                Kirigami.FormData.label: i18n("Minimum height:")
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: minHeightModeCombo
                    Layout.preferredWidth: 130
                    textRole: "text"
                    model: [
                        { text: i18n("Auto"),   value: "auto"   },
                        { text: i18n("Manual"), value: "manual" }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual" ? 1 : 0
                    onActivated: widgetTab.configRoot.cfg_widgetMinHeightMode = model[currentIndex].value
                }
                SpinBox {
                    enabled: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual"
                    from: 200
                    to: 2000
                    stepSize: 10
                    value: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual"
                        ? widgetTab.configRoot.cfg_widgetMinHeight : 750
                    onValueModified: widgetTab.configRoot.cfg_widgetMinHeight = value
                }
                Label {
                    visible: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual"
                    text: "px"
                    opacity: 0.65
                }
            }
        }

        // ── SUB-TAB 1: Details ────────────────────────────────────────
        Kirigami.FormLayout {
            // Icon theme + Icon size on same row
            RowLayout {
                Kirigami.FormData.label: i18n("Icon theme:")
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: widgetIconThemeCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: widgetTab.iconThemeModel
                    Component.onCompleted: currentIndex = widgetTab.findThemeIndex(
                        widgetTab.configRoot.cfg_widgetIconTheme)
                    onActivated: widgetTab.configRoot.cfg_widgetIconTheme = model[currentIndex].value
                }
                Label {
                    text: i18n("Size:")
                    opacity: 0.8
                }
                ComboBox {
                    id: widgetIconSizeCombo
                    Layout.preferredWidth: 90
                    textRole: "text"
                    model: [
                        { text: "16 px", value: 16 },
                        { text: "22 px", value: 22 },
                        { text: "24 px", value: 24 },
                        { text: "32 px", value: 32 }
                    ]
                    Component.onCompleted: {
                        for (var i = 0; i < model.length; ++i)
                            if (model[i].value === widgetTab.configRoot.cfg_widgetIconSize) {
                                currentIndex = i; break;
                            }
                        if (currentIndex < 0) currentIndex = 0;
                    }
                    onActivated: widgetTab.configRoot.cfg_widgetIconSize = model[currentIndex].value
                }
            }

            // ── Warning — KDE themes lack some item icons ──
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: widgetTab.configRoot.cfg_widgetIconTheme === "kde"
                type: Kirigami.MessageType.Warning
                text: i18n("KDE icon themes don't fully support many item icons. You can set your own icons by clicking \"Set your own icons\".")
                showCloseButton: true
                actions: [
                    Kirigami.Action {
                        text: i18n("Set your own icons\u2026")
                        icon.name: "view-visible"
                        onTriggered: {
                            widgetTab.configRoot.initDetailsModel();
                            widgetTab.pushSubPage();
                        }
                    }
                ]
            }

            // Details layout
            RowLayout {
                Kirigami.FormData.label: i18n("Details layout:")
                ComboBox {
                    id: detailsLayoutCombo
                    Layout.preferredWidth: 160
                    textRole: "text"
                    model: [
                        { text: i18n("Cards (2 columns)"), value: "cards2" },
                        { text: i18n("List"),              value: "list"   }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetDetailsLayout === "list" ? 1 : 0
                    onActivated: widgetTab.configRoot.cfg_widgetDetailsLayout = model[currentIndex].value
                }
            }

            // Cards height (hidden in list mode)
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
                Kirigami.FormData.label: i18n("Cards height:")
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: cardsHeightModeCombo
                    Layout.preferredWidth: 130
                    textRole: "text"
                    model: [
                        { text: i18n("Auto"),   value: true  },
                        { text: i18n("Manual"), value: false }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetCardsHeightAuto ? 0 : 1
                    onActivated: {
                        var newMode = model[currentIndex].value;
                        if (widgetTab.configRoot.cfg_widgetCardsHeightAuto !== newMode)
                            widgetTab.configRoot.cfg_widgetCardsHeightAuto = newMode;
                    }
                }
                SpinBox {
                    enabled: !widgetTab.configRoot.cfg_widgetCardsHeightAuto
                    from: 30
                    to: 120
                    value: widgetTab.configRoot.cfg_widgetCardsHeight
                    onValueModified: widgetTab.configRoot.cfg_widgetCardsHeight = value
                }
                Label {
                    visible: !widgetTab.configRoot.cfg_widgetCardsHeightAuto
                    text: "px"
                    opacity: 0.65
                }
            }

            // Expanded cards height (hidden in list mode)
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
                Kirigami.FormData.label: i18n("Expanded cards height:")
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: expandedCardsHeightModeCombo
                    Layout.preferredWidth: 130
                    textRole: "text"
                    model: [
                        { text: i18n("Auto"),   value: true  },
                        { text: i18n("Manual"), value: false }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto ? 0 : 1
                    onActivated: {
                        var newMode = model[currentIndex].value;
                        if (widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto !== newMode)
                            widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto = newMode;
                    }
                }
                SpinBox {
                    enabled: !widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto
                    from: 120
                    to: 500
                    value: widgetTab.configRoot.cfg_widgetExpandedCardsHeight
                    onValueModified: widgetTab.configRoot.cfg_widgetExpandedCardsHeight = value
                }
                Label {
                    visible: !widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto
                    text: "px"
                    opacity: 0.65
                }
            }

            // Details items configurator
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
                            model: widgetTab.configRoot.cfg_widgetDetailsOrder.split(";").filter(function (t) {
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
                                        for (var i = 0; i < widgetTab.configRoot.allDetailsDefs.length; ++i)
                                            if (widgetTab.configRoot.allDetailsDefs[i].itemId === d)
                                                return widgetTab.configRoot.allDetailsDefs[i].label;
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
                            widgetTab.configRoot.initDetailsModel();
                            widgetTab.pushSubPage();
                        }
                    }
                }
            }
        }

        // ── SUB-TAB 2: Forecast ───────────────────────────────────────
        Kirigami.FormLayout {
            SpinBox {
                Kirigami.FormData.label: i18n("Forecast days:")
                from: 3
                to: 7
                value: widgetTab.configRoot.cfg_forecastDays
                onValueModified: widgetTab.configRoot.cfg_forecastDays = value
            }
            CheckBox {
                Kirigami.FormData.label: i18n("Hourly forecast:")
                text: i18n("Show sunrise/sunset markers")
                checked: widgetTab.configRoot.cfg_forecastShowSunEvents
                onToggled: widgetTab.configRoot.cfg_forecastShowSunEvents = checked
            }

        }
    }
}
