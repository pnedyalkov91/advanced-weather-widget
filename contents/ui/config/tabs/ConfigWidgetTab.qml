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
    /** Emitted when the user clicks Configure… to push the simple items sub-page */
    signal pushSimpleSubPage()

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
            // ═══════════════════════════════════════════════════════════════
            // SECTION: Layout
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Layout")
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            RowLayout {
                Kirigami.FormData.label: i18n("Mode:")
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: layoutModeCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: [
                        { text: i18n("Advanced (all tabs)"),             value: "advanced" },
                        { text: i18n("Simple"), value: "simple"   }
                    ]
                    Component.onCompleted: {
                        currentIndex = (widgetTab.configRoot.cfg_widgetLayoutMode === "simple") ? 1 : 0;
                    }
                    onActivated: widgetTab.configRoot.cfg_widgetLayoutMode = model[currentIndex].value
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Appearance
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Appearance")
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

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
                text: i18n("Configure weather icons…")
                icon.name: "configure"
                onClicked: widgetTab.configRoot.conditionIconDialog.openWithContext("widget")
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Behavior
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Behavior")
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            RowLayout {
                Kirigami.FormData.label: i18n("Default tab:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: defaultTabCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: [
                        { text: i18n("Details"),  value: "details"  },
                        { text: i18n("Forecast"), value: "forecast" },
                        { text: i18n("Radar"),    value: "radar"    }
                    ]
                    Component.onCompleted: {
                        var v = widgetTab.configRoot.cfg_widgetDefaultTab || "details";
                        if (v === "forecast") currentIndex = 1;
                        else if (v === "radar") currentIndex = 2;
                        else currentIndex = 0;
                    }
                    onActivated: widgetTab.configRoot.cfg_widgetDefaultTab = model[currentIndex].value
                }
            }
            RowLayout {
                Kirigami.FormData.label: i18n("Visible tabs:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: visibleTabsCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: [
                        { text: i18n("All tabs"),      value: "both"     },
                        { text: i18n("Details only"),  value: "details"  },
                        { text: i18n("Forecast only"), value: "forecast" },
                        { text: i18n("Radar only"),    value: "radar"    },
                        { text: i18n("None"),          value: "none"     }
                    ]
                    Component.onCompleted: {
                        var v = widgetTab.configRoot.cfg_widgetVisibleTabs || "both";
                        if (v === "details") currentIndex = 1;
                        else if (v === "forecast") currentIndex = 2;
                        else if (v === "radar") currentIndex = 3;
                        else if (v === "none") currentIndex = 4;
                        else currentIndex = 0;
                    }
                    onActivated: widgetTab.configRoot.cfg_widgetVisibleTabs = model[currentIndex].value
                }
            }
            RowLayout {
                Kirigami.FormData.label: i18n("Footer:")
                Switch {
                    id: footerSwitch
                    checked: widgetTab.configRoot.cfg_showUpdateText
                    onToggled: widgetTab.configRoot.cfg_showUpdateText = checked
                }
                Label {
                    text: i18n("Show update time and provider")
                    opacity: 0.8
                    MouseArea {
                        anchors.fill: parent
                        onClicked: footerSwitch.toggle()
                    }
                }
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Sunrise / Sunset:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowSunriseSunset
                    onToggled: widgetTab.configRoot.cfg_simpleShowSunriseSunset = checked
                }
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Date &amp; time in header:")
                Switch {
                    id: headerDateTimeSwitch
                    checked: widgetTab.configRoot.cfg_headerShowDateTime
                    onToggled: widgetTab.configRoot.cfg_headerShowDateTime = checked
                }
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Date format:")
                visible: widgetTab.configRoot.cfg_headerShowDateTime
                spacing: Kirigami.Units.smallSpacing
                ComboBox {
                    id: headerDateFormatCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    readonly property var _presets: [
                        { text: i18n("Region default (long)"),  value: "locale-long"  },
                        { text: i18n("Region default (short)"), value: "locale-short" },
                        { text: "Mon, Jan 1  (ddd, MMM d)",     value: "ddd, MMM d"   },
                        { text: "Monday, Jan 1  (dddd, MMM d)", value: "dddd, MMM d"  },
                        { text: "01/01/2025  (dd/MM/yyyy)",     value: "dd/MM/yyyy"   },
                        { text: "01.01.2025  (dd.MM.yyyy)",     value: "dd.MM.yyyy"   },
                        { text: "2025-01-01  (yyyy-MM-dd)",     value: "yyyy-MM-dd"   },
                        { text: i18n("Custom…"),                value: "__custom__"   }
                    ]
                    model: _presets
                    Component.onCompleted: {
                        var v = widgetTab.configRoot.cfg_headerDateFormat || "locale-long";
                        for (var i = 0; i < _presets.length - 1; ++i) {
                            if (_presets[i].value === v) { currentIndex = i; return; }
                        }
                        currentIndex = _presets.length - 1;
                    }
                    onActivated: {
                        var val = _presets[currentIndex].value;
                        if (val !== "__custom__")
                            widgetTab.configRoot.cfg_headerDateFormat = val;
                    }
                }
                TextField {
                    id: headerDateCustomField
                    visible: headerDateFormatCombo.currentIndex === headerDateFormatCombo._presets.length - 1
                    Layout.preferredWidth: 140
                    placeholderText: "ddd, MMM d"
                    text: {
                        var v = widgetTab.configRoot.cfg_headerDateFormat;
                        var presets = headerDateFormatCombo._presets;
                        for (var i = 0; i < presets.length - 1; ++i)
                            if (presets[i].value === v) return "";
                        return v;
                    }
                    onEditingFinished: {
                        if (text.trim().length > 0)
                            widgetTab.configRoot.cfg_headerDateFormat = text.trim();
                    }
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                visible: widgetTab.configRoot.cfg_headerShowDateTime &&
                         headerDateFormatCombo.currentIndex === headerDateFormatCombo._presets.length - 1
                type: Kirigami.MessageType.Information
                text: i18n("You can see date/time format reference at: <a href=\"https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method\">Qt documentation</a>")
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Time format:")
                visible: widgetTab.configRoot.cfg_headerShowDateTime
                spacing: Kirigami.Units.smallSpacing
                ComboBox {
                    id: headerTimeFormatCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    readonly property var _presets: [
                        { text: i18n("Region default"), value: "locale"    },
                        { text: "14:30  (HH:mm)",       value: "HH:mm"    },
                        { text: "14:30:05  (HH:mm:ss)", value: "HH:mm:ss" },
                        { text: "2:30 PM  (h:mm AP)",   value: "h:mm AP"  },
                        { text: "2:30:05 PM  (h:mm:ss AP)", value: "h:mm:ss AP" },
                        { text: i18n("Custom…"),         value: "__custom__" }
                    ]
                    model: _presets
                    Component.onCompleted: {
                        var v = widgetTab.configRoot.cfg_headerTimeFormat || "locale";
                        for (var i = 0; i < _presets.length - 1; ++i) {
                            if (_presets[i].value === v) { currentIndex = i; return; }
                        }
                        currentIndex = _presets.length - 1;
                    }
                    onActivated: {
                        var val = _presets[currentIndex].value;
                        if (val !== "__custom__")
                            widgetTab.configRoot.cfg_headerTimeFormat = val;
                    }
                }
                TextField {
                    id: headerTimeCustomField
                    visible: headerTimeFormatCombo.currentIndex === headerTimeFormatCombo._presets.length - 1
                    Layout.preferredWidth: 140
                    placeholderText: "HH:mm"
                    text: {
                        var v = widgetTab.configRoot.cfg_headerTimeFormat;
                        var presets = headerTimeFormatCombo._presets;
                        for (var i = 0; i < presets.length - 1; ++i)
                            if (presets[i].value === v) return "";
                        return v;
                    }
                    onEditingFinished: {
                        if (text.trim().length > 0)
                            widgetTab.configRoot.cfg_headerTimeFormat = text.trim();
                    }
                }
                Label {
                    visible: !headerTimeCustomField.visible && widgetTab.configRoot.cfg_headerTimeFormat !== "locale"
                    text: i18n("Use 24-hour format:")
                    opacity: 0.8
                }
                Switch {
                    id: header24hSwitch
                    visible: !headerTimeCustomField.visible && widgetTab.configRoot.cfg_headerTimeFormat !== "locale"
                    readonly property bool _is24h: {
                        var v = widgetTab.configRoot.cfg_headerTimeFormat;
                        return v === "locale" || v === "HH:mm" || v === "HH:mm:ss";
                    }
                    checked: _is24h
                    onToggled: {
                        var cur = headerTimeFormatCombo.currentIndex;
                        var presets = headerTimeFormatCombo._presets;
                        if (cur >= presets.length - 1) return;
                        var v = presets[cur].value;
                        if (v === "locale" || v === "") return;
                        if (checked) {
                            if (v === "h:mm AP")       widgetTab.configRoot.cfg_headerTimeFormat = "HH:mm";
                            else if (v === "h:mm:ss AP") widgetTab.configRoot.cfg_headerTimeFormat = "HH:mm:ss";
                        } else {
                            if (v === "HH:mm")    widgetTab.configRoot.cfg_headerTimeFormat = "h:mm AP";
                            else if (v === "HH:mm:ss") widgetTab.configRoot.cfg_headerTimeFormat = "h:mm:ss AP";
                        }
                        var newV = widgetTab.configRoot.cfg_headerTimeFormat;
                        for (var i = 0; i < presets.length - 1; ++i) {
                            if (presets[i].value === newV) { headerTimeFormatCombo.currentIndex = i; break; }
                        }
                    }
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                visible: widgetTab.configRoot.cfg_headerShowDateTime &&
                         headerTimeFormatCombo.currentIndex === headerTimeFormatCombo._presets.length - 1
                type: Kirigami.MessageType.Information
                text: i18n("You can see date/time format reference at: <a href=\"https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method\">Qt documentation</a>")
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Widget popup size
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Widget Size")
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

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
                        ? widgetTab.configRoot.cfg_widgetMinWidth : 540
                    onValueModified: widgetTab.configRoot.cfg_widgetMinWidth = value
                }
                Label {
                    visible: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual"
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
                        ? widgetTab.configRoot.cfg_widgetMinHeight : 550
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
            // ═══════════════════════════════════════════════════════════════
            // SECTION: Icons
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Icons")
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

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

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            // ── Warning — KDE themes lack some item icons ──
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.columnSpan: 2
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

            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Layout
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Layout")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Details layout:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
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

            // Cards height (hidden in list mode or simple mode)
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
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

            // Expanded cards height (hidden in list mode or simple mode)
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
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

            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Items — switches between advanced and simple mode
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                    ? i18n("Simple Mode Items") : i18n("Details Items")
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            // Advanced mode: details items preview + Configure
            Item {
                Kirigami.FormData.label: i18n("Details items:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
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
                        text: i18n("Configure…")
                        icon.name: "configure"
                        onClicked: widgetTab.pushSubPage()
                    }
                }
            }

            // Simple mode: simple chips preview + Configure
            Item {
                Kirigami.FormData.label: i18n("Simple chips:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                implicitWidth: simplePreviewRow.implicitWidth
                implicitHeight: simplePreviewRow.implicitHeight
                RowLayout {
                    id: simplePreviewRow
                    spacing: 10
                    Flow {
                        spacing: 4
                        Layout.maximumWidth: 260
                        Repeater {
                            model: widgetTab.configRoot.cfg_widgetSimpleDetailsOrder.split(";").filter(function (t) {
                                return t.length > 0;
                            })
                            delegate: Rectangle {
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.10)
                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                border.width: 1
                                implicitWidth: simpleChipLbl.implicitWidth + 10
                                implicitHeight: simpleChipLbl.implicitHeight + 6
                                Label {
                                    id: simpleChipLbl
                                    anchors.centerIn: parent
                                    text: {
                                        var d = modelData.trim();
                                        for (var i = 0; i < widgetTab.configRoot.allSimpleDefs.length; ++i)
                                            if (widgetTab.configRoot.allSimpleDefs[i].itemId === d)
                                                return widgetTab.configRoot.allSimpleDefs[i].label;
                                        return d;
                                    }
                                }
                            }
                        }
                    }
                    Button {
                        text: i18n("Configure…")
                        icon.name: "configure"
                        onClicked: widgetTab.pushSimpleSubPage()
                    }
                }
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Stats items:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowStatsChips
                    onToggled: widgetTab.configRoot.cfg_simpleShowStatsChips = checked
                }
            }
        }

        // ── SUB-TAB 2: Forecast ───────────────────────────────────────
        Kirigami.FormLayout {
            // ═══════════════════════════════════════════════════════════════
            // SECTION: General
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("General")
            }

            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            SpinBox {
                Kirigami.FormData.label: i18n("Forecast days:")
                from: 3
                to: 7
                value: widgetTab.configRoot.cfg_forecastDays
                onValueModified: widgetTab.configRoot.cfg_forecastDays = value
            }
            CheckBox {
                Kirigami.FormData.label: i18n("Hourly forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                text: i18n("Show sunrise/sunset markers")
                checked: widgetTab.configRoot.cfg_forecastShowSunEvents
                onToggled: widgetTab.configRoot.cfg_forecastShowSunEvents = checked
            }

            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Simple widget
            // ═══════════════════════════════════════════════════════════════
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Simple Widget")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowForecast
                    onToggled: widgetTab.configRoot.cfg_simpleShowForecast = checked
                }
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Compass in forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                enabled: widgetTab.configRoot.cfg_simpleShowForecast
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowForecastCompass
                    onToggled: widgetTab.configRoot.cfg_simpleShowForecastCompass = checked
                }
            }

        }
    }
}
