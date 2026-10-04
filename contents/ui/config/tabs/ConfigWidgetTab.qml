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
 * ConfigWidgetTab.qml - Widget tab with sub-tabs: General, Details, Forecast
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

    /** Emitted when the user clicks Configure… to push the details sub-page */
    signal pushSubPage()
    /** Emitted when the user clicks Configure… to push the simple items sub-page */
    signal pushSimpleSubPage()

    /** Icon theme choices shared by all combos */
    readonly property var iconThemeModel: [
        { text: i18n("KDE Icon Theme"),        value: "kde"          },
        { text: i18n("Symbolic (Bundled)"),        value: "symbolic"     },
        { text: i18n("Flat Color (Bundled)"),      value: "flat-color"   },
        { text: i18n("3D Oxygen (Bundled)"),       value: "3d-oxygen"    },
        { text: i18n("Meteocons (Bundled)"),       value: "meteocons"    }
    ]

    /** Condition icon theme choices - adds KDE Symbolic and Custom options */
    readonly property var conditionIconThemeModel: [
        { text: i18n("KDE Icon Theme (Colorful)"),        value: "kde"          },
        { text: i18n("KDE Icon Theme (Symbolic)"),          value: "kde-symbolic" },
        { text: i18n("Symbolic (Bundled)"),        value: "symbolic"     },
        { text: i18n("Flat Color (Bundled)"),      value: "flat-color"   },
        { text: i18n("3D Oxygen (Bundled)"),       value: "3d-oxygen"    },
        { text: i18n("Meteocons (Bundled)"),       value: "meteocons"    },
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

    // Refresh both icon theme combos (General > Weather icon theme, Details >
    // Icon theme) after the icon theme scope dialog (configAppearance.qml)
    // applied a theme from another tab, or was cancelled.
    Connections {
        target: widgetTab.configRoot
        function onIconThemesSynced() {
            conditionIconThemeCombo.currentIndex = widgetTab.findConditionThemeIndex(
                widgetTab.configRoot.cfg_conditionIconTheme);
            widgetIconThemeCombo.currentIndex = widgetTab.findThemeIndex(
                widgetTab.configRoot.cfg_widgetIconTheme);
        }
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

    // Tab pages live in a plain ColumnLayout and only the selected one is visible.
    // A StackLayout is as tall as its TALLEST page, which left empty space and a
    // permanent scrollbar under the shorter tabs; layouts ignore hidden items.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // ── SUB-TAB 0: General ────────────────────────────────────────
        GridLayout {
            id: _form1
            visible: subTabBar.currentIndex === 0
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

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Layout
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Layout")
                Layout.columnSpan: _form1.columns
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            Label {
                text: i18n("Mode:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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
            SectionHeader {
                title: i18n("Appearance")
                Layout.columnSpan: _form1.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            Label {
                text: i18n("Weather icon theme:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: conditionIconThemeCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: widgetTab.conditionIconThemeModel
                    Component.onCompleted: currentIndex = widgetTab.findConditionThemeIndex(
                        widgetTab.configRoot.cfg_conditionIconTheme)
                    // Asks "Apply everywhere / only here / Cancel" when the theme also
                    // exists in other icon theme settings (see configAppearance.qml).
                    // "KDE Symbolic" and "Custom…" are specific to this combo and
                    // are applied directly, exactly as before.
                    onActivated: widgetTab.configRoot.requestIconTheme("condition", model[currentIndex].value)
                }
            }
            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2 && (widgetTab.configRoot.cfg_conditionIconTheme === "custom")
                implicitWidth: 0
                implicitHeight: 0
            }
            Button {
                visible: widgetTab.configRoot.cfg_conditionIconTheme === "custom"
                text: i18n("Configure weather icons…")
                icon.name: "configure"
                onClicked: widgetTab.configRoot.conditionIconDialog.openWithContext("widget")
            }

            Label {
                text: i18n("Icon glow:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Switch {
                    checked: widgetTab.configRoot.cfg_iconGlowEnabled
                    onToggled: widgetTab.configRoot.cfg_iconGlowEnabled = checked
                }
                Label {
                    text: widgetTab.configRoot.cfg_iconGlowEnabled ? i18n("Enabled") : i18n("Disabled")
                    opacity: 0.8
                    MouseArea {
                        anchors.fill: parent
                        onClicked: widgetTab.configRoot.cfg_iconGlowEnabled = !widgetTab.configRoot.cfg_iconGlowEnabled
                    }
                }
            }
            Label {
                text: i18n("Glow intensity:")
                visible: widgetTab.configRoot.cfg_iconGlowEnabled
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_iconGlowEnabled
                spacing: Kirigami.Units.largeSpacing
                Slider {
                    Layout.preferredWidth: 160
                    from: 0.1
                    to: 1.0
                    stepSize: 0.05
                    value: widgetTab.configRoot.cfg_iconGlowIntensity
                    onMoved: widgetTab.configRoot.cfg_iconGlowIntensity = value
                }
                Label {
                    text: Math.round(widgetTab.configRoot.cfg_iconGlowIntensity * 100) + "%"
                    opacity: 0.65
                    Layout.preferredWidth: 40
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Behavior
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Behavior")
                Layout.columnSpan: _form1.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            Label {
                text: i18n("Default tab:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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
            Label {
                text: i18n("Visible tabs:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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
            Label {
                text: i18n("Footer:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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

            Label {
                text: i18n("Sunrise / Sunset:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowSunriseSunset
                    onToggled: widgetTab.configRoot.cfg_simpleShowSunriseSunset = checked
                }
            }

            Label {
                text: i18n("Date and time in header:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    id: headerDateTimeSwitch
                    checked: widgetTab.configRoot.cfg_headerShowDateTime
                    onToggled: widgetTab.configRoot.cfg_headerShowDateTime = checked
                }
            }

            Label {
                text: i18n("Date format:")
                visible: widgetTab.configRoot.cfg_headerShowDateTime
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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
                Layout.columnSpan: _form1.columns
                Layout.fillWidth: true
                visible: widgetTab.configRoot.cfg_headerShowDateTime &&
                         headerDateFormatCombo.currentIndex === headerDateFormatCombo._presets.length - 1
                type: Kirigami.MessageType.Information
                text: i18n("You can see date/time format reference at: <a href=\"https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method\">Qt documentation</a>")
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            Label {
                text: i18n("Time format:")
                visible: widgetTab.configRoot.cfg_headerShowDateTime
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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
                Layout.columnSpan: _form1.columns
                Layout.fillWidth: true
                visible: widgetTab.configRoot.cfg_headerShowDateTime &&
                         headerTimeFormatCombo.currentIndex === headerTimeFormatCombo._presets.length - 1
                type: Kirigami.MessageType.Information
                text: i18n("You can see date/time format reference at: <a href=\"https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method\">Qt documentation</a>")
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Widget popup size
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Widget Size")
                Layout.columnSpan: _form1.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            Label {
                text: i18n("Minimum width:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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
                    // Auto placeholder mirrors the actual auto-mode value computed
                    // in main.qml's fullRepresentation block - keep these in sync.
                    value: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual"
                        ? widgetTab.configRoot.cfg_widgetMinWidth
                        : (widgetTab.configRoot.cfg_widgetLayoutMode === "simple" ? 765 : 800)
                    onValueModified: widgetTab.configRoot.cfg_widgetMinWidth = value
                }
                Label {
                    visible: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual"
                    text: "px"
                    opacity: 0.65
                }
            }
            Label {
                text: i18n("Minimum height:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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
                    // Auto placeholder mirrors the actual auto-mode value computed
                    // in main.qml's fullRepresentation block - keep these in sync.
                    value: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual"
                        ? widgetTab.configRoot.cfg_widgetMinHeight
                        : (widgetTab.configRoot.cfg_widgetLayoutMode === "simple" ? 550 : 750)
                    onValueModified: widgetTab.configRoot.cfg_widgetMinHeight = value
                }
                Label {
                    visible: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual"
                    text: "px"
                    opacity: 0.65
                }
            }

            // Invisible filler row: it lets the second column take ALL spare width, so the
            // label column keeps its width when rows are shown or hidden.
            Item { visible: _form1.columns === 2; implicitWidth: 0; implicitHeight: 0 }
            Item { visible: _form1.columns === 2; Layout.fillWidth: true; implicitWidth: 0; implicitHeight: 0 }
        }

        // ── SUB-TAB 1: Details ────────────────────────────────────────
        GridLayout {
            id: _form2
            visible: subTabBar.currentIndex === 1
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

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Icons
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Icons")
                Layout.columnSpan: _form2.columns
            }
            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            Label {
                text: i18n("Icon theme:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: widgetIconThemeCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: widgetTab.iconThemeModel
                    Component.onCompleted: currentIndex = widgetTab.findThemeIndex(
                        widgetTab.configRoot.cfg_widgetIconTheme)
                    // Asks "Apply everywhere / only here / Cancel" when the theme also
                    // exists in other icon theme settings (see configAppearance.qml).
                    onActivated: widgetTab.configRoot.requestIconTheme("details", model[currentIndex].value)
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

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            // ── Warning - KDE themes lack some item icons ──
            Kirigami.InlineMessage {
                Layout.columnSpan: _form2.columns
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

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Layout
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Layout")
                Layout.columnSpan: _form2.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }
            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Label {
                text: i18n("Details layout:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
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
            Label {
                text: i18n("Cards height:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
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
            Label {
                text: i18n("Expanded cards height:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
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
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Items - switches between advanced and simple mode
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                    ? i18n("Simple Mode Items") : i18n("Details Items")
                Layout.columnSpan: _form2.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }
            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            // Advanced mode: details items preview + Configure
            Label {
                text: i18n("Details items:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            Item {
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
            Label {
                text: i18n("Simple chips:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            Item {
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

            Label {
                text: i18n("Stats items:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowStatsChips
                    onToggled: widgetTab.configRoot.cfg_simpleShowStatsChips = checked
                }
            }

            // Invisible filler row: it lets the second column take ALL spare width, so the
            // label column keeps its width when rows are shown or hidden.
            Item { visible: _form2.columns === 2; implicitWidth: 0; implicitHeight: 0 }
            Item { visible: _form2.columns === 2; Layout.fillWidth: true; implicitWidth: 0; implicitHeight: 0 }
        }

        // ── SUB-TAB 2: Forecast ───────────────────────────────────────
        GridLayout {
            id: _form3
            visible: subTabBar.currentIndex === 2
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

            // ═══════════════════════════════════════════════════════════════
            // SECTION: General
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("General")
                Layout.columnSpan: _form3.columns
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            Label {
                text: i18n("Forecast days:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            SpinBox {
                from: 3
                to: 16
                value: widgetTab.configRoot.cfg_forecastDays
                onValueModified: widgetTab.configRoot.cfg_forecastDays = value
            }
            Label {
                text: i18n("Show Today:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowToday
                    onToggled: widgetTab.configRoot.cfg_forecastShowToday = checked
                }
            }
            Label {
                text: i18n("Auto-open hourly forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    id: forecastAutoOpenSwitch
                    checked: widgetTab.configRoot.cfg_forecastAutoOpen
                    onToggled: widgetTab.configRoot.cfg_forecastAutoOpen = checked
                }
                Label {
                    text: forecastAutoOpenSwitch.checked
                        ? i18n("Opens today's hourly forecast automatically (or the next available day)")
                        : i18n("All days start collapsed")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    opacity: 0.7
                }
            }
            Label {
                text: i18n("Expand all days:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    id: forecastExpandAllSwitch
                    checked: widgetTab.configRoot.cfg_forecastExpandAll
                    onToggled: widgetTab.configRoot.cfg_forecastExpandAll = checked
                }
                Label {
                    text: forecastExpandAllSwitch.checked
                        ? i18n("All days show hourly forecast when opening the tab")
                        : i18n("Only the clicked day expands")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    opacity: 0.7
                }
            }
            Label {
                text: i18n("Show past weather info for today:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    id: forecastShowPastHoursSwitch
                    checked: widgetTab.configRoot.cfg_forecastShowPastHours
                    onToggled: widgetTab.configRoot.cfg_forecastShowPastHours = checked
                }
                Label {
                    text: forecastShowPastHoursSwitch.checked
                        ? i18n("Already-passed hours for today stay in place, greyed out, instead of being removed")
                        : i18n("Already-passed hours are removed from today's hourly forecast")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    opacity: 0.7
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Daily Forecast Settings
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Daily Forecast Settings")
                Layout.columnSpan: _form3.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

            Label {
                text: i18n("Pressure forecast:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowPressure
                    onToggled: widgetTab.configRoot.cfg_forecastShowPressure = checked
                }
            }
            Label {
                text: i18n("Kp index/G forecast:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    id: forecastShowKpIndexSwitch
                    checked: widgetTab.configRoot.cfg_forecastShowKpIndex
                    onToggled: widgetTab.configRoot.cfg_forecastShowKpIndex = checked
                }
                Label {
                    visible: forecastShowKpIndexSwitch.checked
                    text: i18n("The geomagnetic (Kp/G) forecast is only available up to 3 days ahead")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    opacity: 0.7
                }
            }
            Label {
                text: i18n("UV index forecast:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowUvIndex
                    onToggled: widgetTab.configRoot.cfg_forecastShowUvIndex = checked
                }
            }
            Label {
                text: i18n("Precip sum:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowPrecipSum
                    onToggled: widgetTab.configRoot.cfg_forecastShowPrecipSum = checked
                }
            }
            Label {
                text: i18n("Visibility:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowVisibility
                    onToggled: widgetTab.configRoot.cfg_forecastShowVisibility = checked
                }
            }
            Label {
                text: i18n("Wind:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowWind
                    onToggled: widgetTab.configRoot.cfg_forecastShowWind = checked
                }
            }

            Kirigami.InlineMessage {
                Layout.columnSpan: _form3.columns
                Layout.fillWidth: true
                visible: [
                    widgetTab.configRoot.cfg_forecastShowPressure,
                    widgetTab.configRoot.cfg_forecastShowKpIndex,
                    widgetTab.configRoot.cfg_forecastShowUvIndex,
                    widgetTab.configRoot.cfg_forecastShowPrecipSum,
                    widgetTab.configRoot.cfg_forecastShowVisibility,
                    widgetTab.configRoot.cfg_forecastShowWind
                ].filter(function(v) { return v === true; }).length >= 2
                type: Kirigami.MessageType.Information
                text: i18n("You may need to increase the widget's width to see all the selected information")
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Hourly Forecast Settings
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Hourly Forecast Settings")
                Layout.columnSpan: _form3.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Label {
                text: i18n("Hourly layout:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            ComboBox {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                textRole: "text"
                readonly property var _opts: [
                    { text: i18n("Cards"),  value: "cards" },
                    { text: i18n("Strip"),  value: "strip" }
                ]
                model: _opts
                currentIndex: {
                    var v = widgetTab.configRoot.cfg_forecastHourlyLayout;
                    for (var i = 0; i < _opts.length; i++)
                        if (_opts[i].value === v) return i;
                    return 0;
                }
                onActivated: widgetTab.configRoot.cfg_forecastHourlyLayout = _opts[currentIndex].value
            }
            Label {
                text: i18n("Sunrise/sunset markers:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowSunEvents
                    onToggled: widgetTab.configRoot.cfg_forecastShowSunEvents = checked
                }
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Label {
                text: i18n("Precip probability:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastHourlyShowPrecipProb
                    onToggled: widgetTab.configRoot.cfg_forecastHourlyShowPrecipProb = checked
                }
            }
            Label {
                text: i18n("Pressure forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastHourlyShowPressure
                    onToggled: widgetTab.configRoot.cfg_forecastHourlyShowPressure = checked
                }
            }
            Label {
                text: i18n("Kp index/G forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    id: forecastHourlyShowKpIndexSwitch
                    checked: widgetTab.configRoot.cfg_forecastHourlyShowKpIndex
                    onToggled: widgetTab.configRoot.cfg_forecastHourlyShowKpIndex = checked
                }
                Label {
                    visible: forecastHourlyShowKpIndexSwitch.checked
                    text: i18n("The geomagnetic (Kp/G) forecast is only available up to 3 days ahead")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    opacity: 0.7
                }
            }
            Label {
                text: i18n("UV index forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastHourlyShowUvIndex
                    onToggled: widgetTab.configRoot.cfg_forecastHourlyShowUvIndex = checked
                }
            }
            Label {
                text: i18n("Precip sum:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastHourlyShowPrecipSum
                    onToggled: widgetTab.configRoot.cfg_forecastHourlyShowPrecipSum = checked
                }
            }
            Label {
                text: i18n("Visibility:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastHourlyShowVisibility
                    onToggled: widgetTab.configRoot.cfg_forecastHourlyShowVisibility = checked
                }
            }
            Label {
                text: i18n("Wind:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastHourlyShowWind
                    onToggled: widgetTab.configRoot.cfg_forecastHourlyShowWind = checked
                }
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode === "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Simple widget
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Simple Widget")
                Layout.columnSpan: _form3.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode === "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            Label {
                text: i18n("Forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowForecast
                    onToggled: widgetTab.configRoot.cfg_simpleShowForecast = checked
                }
            }

            Label {
                text: i18n("Compass in forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                enabled: widgetTab.configRoot.cfg_simpleShowForecast
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowForecastCompass
                    onToggled: widgetTab.configRoot.cfg_simpleShowForecastCompass = checked
                }
            }


            // Invisible filler row: it lets the second column take ALL spare width, so the
            // label column keeps its width when rows are shown or hidden.
            Item { visible: _form3.columns === 2; implicitWidth: 0; implicitHeight: 0 }
            Item { visible: _form3.columns === 2; Layout.fillWidth: true; implicitWidth: 0; implicitHeight: 0 }
        }
    }
}
