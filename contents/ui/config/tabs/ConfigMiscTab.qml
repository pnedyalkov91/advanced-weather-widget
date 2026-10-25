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
 * ConfigMiscTab.qml - Misc (display + units) tab content
 *
 * Extracted from configAppearance.qml for readability.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

GridLayout {
    id: miscTab

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

    // Effective values. The new keys are empty until chosen; the older
    // header-only keys are the fallback, so an existing setting carries over.
    readonly property string dateFormatValue: configRoot.cfg_displayDateFormat || configRoot.cfg_headerDateFormat || "locale-long"
    readonly property string timeFormatValue: configRoot.cfg_displayTimeFormat || configRoot.cfg_headerTimeFormat || "locale"

    /** Preview text for the Date and Time section, built with plain Qt. */
    function previewText() {
        var now = new Date();
        var df = dateFormatValue;
        var tf = timeFormatValue;
        var ds = df === "locale-long" ? now.toLocaleDateString(Qt.locale(), Locale.LongFormat)
               : df === "locale-short" ? now.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
               : Qt.formatDate(now, df);
        var ts = Qt.formatTime(now, tf === "locale" ? Qt.locale().timeFormat(Locale.ShortFormat) : tf);
        return ds + "  " + ts;
    }

    function setCombo(combo, value) {
        for (var i = 0; i < combo.model.length; ++i)
            if (combo.model[i].value === value) {
                combo.currentIndex = i;
                return;
            }
    }

    SectionHeader {
        title: i18n("Display")
        Layout.columnSpan: miscTab.columns
    }
    Label {
        text: i18n("Round values:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        spacing: 12
        Switch {
            id: roundValuesSwitch
            checked: miscTab.configRoot.cfg_roundValues
            onToggled: miscTab.configRoot.cfg_roundValues = checked
        }
        Label {
            text: roundValuesSwitch.checked ? i18n("Values are rounded to whole numbers") : i18n("Values show decimal places")
            opacity: 0.8
        }
    }
    Label {
        text: i18n("Show temperature unit:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        spacing: 12
        Switch {
            id: showTempUnitSwitch
            checked: miscTab.configRoot.cfg_showTempUnit
            onToggled: miscTab.configRoot.cfg_showTempUnit = checked
        }
        Label {
            text: showTempUnitSwitch.checked ? i18n("Showing °C / °F after values") : i18n("Showing ° only")
            opacity: 0.8
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // SECTION: Date and Time - applies everywhere (panel, tooltip, header,
    // Details, Forecast, Radar, History)
    // ═══════════════════════════════════════════════════════════════════
    SectionHeader {
        title: i18n("Date and Time")
        Layout.columnSpan: miscTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
    }
    Label {
        text: i18n("Date format:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        ComboBox {
            id: dateFormatCombo
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
                var v = miscTab.dateFormatValue;
                for (var i = 0; i < _presets.length - 1; ++i) {
                    if (_presets[i].value === v) { currentIndex = i; return; }
                }
                currentIndex = _presets.length - 1;
            }
            onActivated: {
                var val = _presets[currentIndex].value;
                if (val !== "__custom__")
                    miscTab.configRoot.cfg_displayDateFormat = val;
            }
        }
        TextField {
            id: dateCustomField
            visible: dateFormatCombo.currentIndex === dateFormatCombo._presets.length - 1
            Layout.preferredWidth: 140
            placeholderText: "ddd, MMM d"
            text: {
                var v = miscTab.dateFormatValue;
                var presets = dateFormatCombo._presets;
                for (var i = 0; i < presets.length - 1; ++i)
                    if (presets[i].value === v) return "";
                return v;
            }
            onEditingFinished: {
                if (text.trim().length > 0)
                    miscTab.configRoot.cfg_displayDateFormat = text.trim();
            }
        }
    }
    Kirigami.InlineMessage {
        Layout.columnSpan: miscTab.columns
        Layout.fillWidth: true
        visible: dateCustomField.visible
        type: Kirigami.MessageType.Information
        text: i18n("You can see date/time format reference at: <a href=\"https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method\">Qt documentation</a>")
        onLinkActivated: link => Qt.openUrlExternally(link)
    }

    Label {
        text: i18n("Time format:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        ComboBox {
            id: timeFormatCombo
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
                var v = miscTab.timeFormatValue;
                for (var i = 0; i < _presets.length - 1; ++i) {
                    if (_presets[i].value === v) { currentIndex = i; return; }
                }
                currentIndex = _presets.length - 1;
            }
            onActivated: {
                var val = _presets[currentIndex].value;
                if (val !== "__custom__")
                    miscTab.configRoot.cfg_displayTimeFormat = val;
            }
        }
        TextField {
            id: timeCustomField
            visible: timeFormatCombo.currentIndex === timeFormatCombo._presets.length - 1
            Layout.preferredWidth: 140
            placeholderText: "HH:mm"
            text: {
                var v = miscTab.timeFormatValue;
                var presets = timeFormatCombo._presets;
                for (var i = 0; i < presets.length - 1; ++i)
                    if (presets[i].value === v) return "";
                return v;
            }
            onEditingFinished: {
                if (text.trim().length > 0)
                    miscTab.configRoot.cfg_displayTimeFormat = text.trim();
            }
        }
        Label {
            visible: !timeCustomField.visible && miscTab.timeFormatValue !== "locale"
            text: i18n("Use 24-hour format:")
            opacity: 0.8
        }
        Switch {
            id: time24hSwitch
            visible: !timeCustomField.visible && miscTab.timeFormatValue !== "locale"
            checked: {
                var v = miscTab.timeFormatValue;
                return v === "locale" || v === "HH:mm" || v === "HH:mm:ss";
            }
            onToggled: {
                var v = miscTab.timeFormatValue;
                var map = checked
                    ? { "h:mm AP": "HH:mm", "h:mm:ss AP": "HH:mm:ss" }
                    : { "HH:mm": "h:mm AP", "HH:mm:ss": "h:mm:ss AP" };
                if (!(v in map))
                    return;
                miscTab.configRoot.cfg_displayTimeFormat = map[v];
                var presets = timeFormatCombo._presets;
                for (var i = 0; i < presets.length - 1; ++i)
                    if (presets[i].value === map[v]) { timeFormatCombo.currentIndex = i; break; }
            }
        }
    }
    Kirigami.InlineMessage {
        Layout.columnSpan: miscTab.columns
        Layout.fillWidth: true
        visible: timeCustomField.visible
        type: Kirigami.MessageType.Information
        text: i18n("You can see date/time format reference at: <a href=\"https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method\">Qt documentation</a>")
        onLinkActivated: link => Qt.openUrlExternally(link)
    }

    Label {
        text: i18n("Preview:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    Label {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        wrapMode: Text.WordWrap
        opacity: 0.8
        text: miscTab.previewText()
    }
    Item {
        // empty label cell: keeps the hint in the second column
        visible: miscTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Label {
        text: i18n("Applies everywhere: panel, tooltip, widget header, Details, Forecast, Radar and History. Where space is tight (forecast and history lists, alerts), \"Region default (long)\" is shown in its short form.")
        wrapMode: Text.WordWrap
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.maximumWidth: 340
    }

    SectionHeader {
        title: i18n("Dual temperature")
        Layout.columnSpan: miscTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
    }
    Label {
        text: i18n("Show both units:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        spacing: 12
        Switch {
            id: dualTempSwitch
            checked: miscTab.configRoot.cfg_dualTempEnabled
            onToggled: miscTab.configRoot.cfg_dualTempEnabled = checked
        }
        Label {
            text: dualTempSwitch.checked ? i18n("Displaying °C and °F together") : i18n("Showing primary unit only")
            opacity: 0.8
        }
    }
    Label {
        text: i18n("Swap order:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        enabled: miscTab.configRoot.cfg_dualTempEnabled
        opacity: enabled ? 1.0 : 0.5
        spacing: 12
        Switch {
            id: dualTempSwapSwitch
            checked: miscTab.configRoot.cfg_dualTempSwapOrder
            onToggled: miscTab.configRoot.cfg_dualTempSwapOrder = checked
        }
        Label {
            text: dualTempSwapSwitch.checked ? i18n("Secondary unit shown first (e.g. °F / °C)") : i18n("Primary unit shown first (e.g. °C / °F)")
            opacity: 0.8
        }
    }
    Label {
        text: i18n("Separator:")
        visible: miscTab.configRoot.cfg_dualTempEnabled
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    RowLayout {
        visible: miscTab.configRoot.cfg_dualTempEnabled
        spacing: Kirigami.Units.smallSpacing
        TextField {
            id: dualTempSepField
            Layout.preferredWidth: 80
            Component.onCompleted: text = miscTab.configRoot.cfg_dualTempSeparator
            onTextChanged: miscTab.configRoot.cfg_dualTempSeparator = text.length > 0 ? text : " / "
            onEditingFinished: miscTab.configRoot.cfg_dualTempSeparator = text.length > 0 ? text : " / "
        }
        Label {
            text: i18n("Preview: 20°C") + (dualTempSepField.text || " / ") + i18n("68°F")
            opacity: 0.65
            font: Kirigami.Theme.smallFont
        }
    }
    Label {
        text: i18n("Show in:")
        visible: miscTab.configRoot.cfg_dualTempEnabled
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    Flow {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: miscTab.configRoot.cfg_dualTempEnabled
        spacing: Kirigami.Units.largeSpacing
        Switch {
            text: i18n("Widget")
            checked: miscTab.configRoot.cfg_dualTempInWidget
            onToggled: miscTab.configRoot.cfg_dualTempInWidget = checked
        }
        Switch {
            text: i18n("Panel")
            checked: miscTab.configRoot.cfg_dualTempInPanel
            onToggled: miscTab.configRoot.cfg_dualTempInPanel = checked
        }
        Switch {
            text: i18n("Tooltip")
            checked: miscTab.configRoot.cfg_dualTempInTooltip
            onToggled: miscTab.configRoot.cfg_dualTempInTooltip = checked
        }
    }

    SectionHeader {
        title: i18n("Units")
        Layout.columnSpan: miscTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
    }
    Label {
        text: i18n("Unit preset:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: unitsModeCombo
        Layout.preferredWidth: 270
        model: [
            {
                text: i18n("Metric (°C, km/h, hPa, mm)"),
                value: "metric"
            },
            {
                text: i18n("Imperial (°F, mph, inHg, in)"),
                value: "imperial"
            },
            {
                text: i18n("Use KDE locale settings"),
                value: "kde"
            },
            {
                text: i18n("Custom (set each unit manually)"),
                value: "custom"
            }
        ]
        Component.onCompleted: {
            for (var i = 0; i < model.length; ++i)
                if (model[i].value === miscTab.configRoot.cfg_unitsMode) {
                    currentIndex = i;
                    break;
                }
            if (miscTab.configRoot.cfg_unitsMode === "kde") {
                var isImp = (Qt.locale().measurementSystem === 1);
                miscTab.configRoot.cfg_temperatureUnit = isImp ? "F" : "C";
                miscTab.configRoot.cfg_windSpeedUnit = isImp ? "mph" : "kmh";
                miscTab.configRoot.cfg_pressureUnit = isImp ? "inHg" : "hPa";
                miscTab.configRoot.cfg_precipitationUnit = isImp ? "in" : "mm";
            }
        }
        textRole: "text"
        onActivated: {
            var mode = model[currentIndex].value;
            miscTab.configRoot.cfg_unitsMode = mode;
            if (mode === "metric") {
                miscTab.configRoot.cfg_temperatureUnit = "C";
                miscTab.configRoot.cfg_windSpeedUnit = "kmh";
                miscTab.configRoot.cfg_pressureUnit = "hPa";
                miscTab.configRoot.cfg_precipitationUnit = "mm";
                miscTab.setCombo(tempUnitCombo, "C");
                miscTab.setCombo(windUnitCombo, "kmh");
                miscTab.setCombo(pressUnitCombo, "hPa");
            } else if (mode === "imperial") {
                miscTab.configRoot.cfg_temperatureUnit = "F";
                miscTab.configRoot.cfg_windSpeedUnit = "mph";
                miscTab.configRoot.cfg_pressureUnit = "inHg";
                miscTab.configRoot.cfg_precipitationUnit = "in";
                miscTab.setCombo(tempUnitCombo, "F");
                miscTab.setCombo(windUnitCombo, "mph");
                miscTab.setCombo(pressUnitCombo, "inHg");
            } else if (mode === "kde") {
                var isImperial = (Qt.locale().measurementSystem === 1);
                miscTab.configRoot.cfg_temperatureUnit = isImperial ? "F" : "C";
                miscTab.configRoot.cfg_windSpeedUnit = isImperial ? "mph" : "kmh";
                miscTab.configRoot.cfg_pressureUnit = isImperial ? "inHg" : "hPa";
                miscTab.configRoot.cfg_precipitationUnit = isImperial ? "in" : "mm";
                miscTab.setCombo(tempUnitCombo, miscTab.configRoot.cfg_temperatureUnit);
                miscTab.setCombo(windUnitCombo, miscTab.configRoot.cfg_windSpeedUnit);
                miscTab.setCombo(pressUnitCombo, miscTab.configRoot.cfg_pressureUnit);
            }
        }
    }
    SectionHeader {
        title: i18n("Individual units")
        Layout.columnSpan: miscTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
    }
    Label {
        text: i18n("Temperature:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: tempUnitCombo
        enabled: miscTab.configRoot.cfg_unitsMode === "custom"
        opacity: enabled ? 1.0 : 0.5
        Layout.preferredWidth: 200
        model: [
            {
                text: i18n("Celsius (°C)"),
                value: "C"
            },
            {
                text: i18n("Fahrenheit (°F)"),
                value: "F"
            }
        ]
        Component.onCompleted: {
            for (var i = 0; i < model.length; ++i)
                if (model[i].value === miscTab.configRoot.cfg_temperatureUnit) {
                    currentIndex = i;
                    break;
                }
        }
        textRole: "text"
        onActivated: if (miscTab.configRoot.cfg_unitsMode === "custom")
            miscTab.configRoot.cfg_temperatureUnit = model[currentIndex].value
    }
    Label {
        text: i18n("Wind speed:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: windUnitCombo
        enabled: miscTab.configRoot.cfg_unitsMode === "custom"
        opacity: enabled ? 1.0 : 0.5
        Layout.preferredWidth: 200
        model: [
            {
                text: i18n("km/h"),
                value: "kmh"
            },
            {
                text: i18n("mph"),
                value: "mph"
            },
            {
                text: i18n("m/s"),
                value: "ms"
            },
            {
                text: i18n("Knots (kn)"),
                value: "kn"
            }
        ]
        Component.onCompleted: {
            for (var i = 0; i < model.length; ++i)
                if (model[i].value === miscTab.configRoot.cfg_windSpeedUnit) {
                    currentIndex = i;
                    break;
                }
        }
        textRole: "text"
        onActivated: if (miscTab.configRoot.cfg_unitsMode === "custom")
            miscTab.configRoot.cfg_windSpeedUnit = model[currentIndex].value
    }
    Label {
        text: i18n("Pressure:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: pressUnitCombo
        enabled: miscTab.configRoot.cfg_unitsMode === "custom"
        opacity: enabled ? 1.0 : 0.5
        Layout.preferredWidth: 200
        model: [
            {
                text: i18n("hPa"),
                value: "hPa"
            },
            {
                text: i18n("mmHg"),
                value: "mmHg"
            },
            {
                text: i18n("inHg"),
                value: "inHg"
            }
        ]
        Component.onCompleted: {
            for (var i = 0; i < model.length; ++i)
                if (model[i].value === miscTab.configRoot.cfg_pressureUnit) {
                    currentIndex = i;
                    break;
                }
        }
        textRole: "text"
        onActivated: if (miscTab.configRoot.cfg_unitsMode === "custom")
            miscTab.configRoot.cfg_pressureUnit = model[currentIndex].value
    }
    Item {
        // empty label cell: keeps the control in the second column
        visible: miscTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Label {
        text: i18n("Individual dropdowns are editable only in Custom mode.\nOther presets set units automatically.")
        wrapMode: Text.WordWrap
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.maximumWidth: 340
    }

    SectionHeader {
        title: i18n("Air Quality")
        Layout.columnSpan: miscTab.columns
        Layout.topMargin: Kirigami.Units.largeSpacing
    }
    Label {
        text: i18n("Show air quality standards:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    Switch {
        id: aqiShowUsSwitch
        text: i18n("US AQI (0-500)")
        checked: miscTab.configRoot.cfg_aqiShowUs
        onToggled: miscTab.configRoot.cfg_aqiShowUs = checked
    }
    Item {
        // empty label cell: keeps the control in the second column
        visible: miscTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Switch {
        id: aqiShowEuSwitch
        text: i18n("European CAQI (0-100+)")
        checked: miscTab.configRoot.cfg_aqiShowEu
        onToggled: miscTab.configRoot.cfg_aqiShowEu = checked
    }
    Item {
        // empty label cell: keeps the control in the second column
        visible: miscTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Switch {
        id: aqiShowCaSwitch
        text: i18n("Canadian AQHI (1-10+)")
        checked: miscTab.configRoot.cfg_aqiShowCa
        onToggled: miscTab.configRoot.cfg_aqiShowCa = checked
    }
    Item {
        // empty label cell: keeps the control in the second column
        visible: miscTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Label {
        text: i18n("Turn on any combination to show them side by side instead of a single standard below.")
        wrapMode: Text.WordWrap
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.maximumWidth: 340
    }
    Label {
        text: i18n("Air Quality index standard:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: miscTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: aqiStandardCombo
        Layout.preferredWidth: 270
        enabled: !(miscTab.configRoot.cfg_aqiShowUs || miscTab.configRoot.cfg_aqiShowEu || miscTab.configRoot.cfg_aqiShowCa)
        model: [
            {
                text: i18n("Automatic (based on location)"),
                value: "auto"
            },
            {
                text: i18n("US AQI (0-500)"),
                value: "us"
            },
            {
                text: i18n("European CAQI (0-100+)"),
                value: "eu"
            },
            {
                text: i18n("Canadian AQHI (1-10+)"),
                value: "ca"
            }
        ]
        Component.onCompleted: miscTab.setCombo(aqiStandardCombo, miscTab.configRoot.cfg_aqiStandard)
        textRole: "text"
        onActivated: miscTab.configRoot.cfg_aqiStandard = model[currentIndex].value
    }
    Item {
        // empty label cell: keeps the control in the second column
        visible: miscTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Label {
        text: (miscTab.configRoot.cfg_aqiShowUs || miscTab.configRoot.cfg_aqiShowEu || miscTab.configRoot.cfg_aqiShowCa)
              ? i18n("Turn off all three switches above to pick a single standard here instead.")
              : i18n("Automatic uses US AQI worldwide, switching to European CAQI or Canadian AQHI based on your location's country.")
        wrapMode: Text.WordWrap
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.maximumWidth: 340
    }

    // Invisible filler row: it lets the second column take ALL spare width, so the
    // label column keeps its width when rows are shown or hidden.
    Item { visible: miscTab.columns === 2; implicitWidth: 0; implicitHeight: 0 }
    Item { visible: miscTab.columns === 2; Layout.fillWidth: true; implicitWidth: 0; implicitHeight: 0 }
}
