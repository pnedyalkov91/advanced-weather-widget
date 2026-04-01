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
 * ConfigMiscTab.qml — Misc (display + units) tab content
 *
 * Extracted from configAppearance.qml for readability.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: miscTab

    /** Reference to the root KCM (configAppearance) for cfg_* properties */
    required property var configRoot

    function setCombo(combo, value) {
        for (var i = 0; i < combo.model.length; ++i)
            if (combo.model[i].value === value) {
                combo.currentIndex = i;
                return;
            }
    }

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Display")
        Kirigami.FormData.isSection: true
    }
    RowLayout {
        Kirigami.FormData.label: i18n("Round values:")
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
    RowLayout {
        Kirigami.FormData.label: i18n("Show temperature unit:")
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

    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Units")
        Kirigami.FormData.isSection: true
    }
    ComboBox {
        id: unitsModeCombo
        Kirigami.FormData.label: i18n("Unit preset:")
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
    Kirigami.Separator {
        Kirigami.FormData.label: i18n("Individual units")
        Kirigami.FormData.isSection: true
    }
    ComboBox {
        id: tempUnitCombo
        Kirigami.FormData.label: i18n("Temperature:")
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
    ComboBox {
        id: windUnitCombo
        Kirigami.FormData.label: i18n("Wind speed:")
        enabled: miscTab.configRoot.cfg_unitsMode === "custom"
        opacity: enabled ? 1.0 : 0.5
        Layout.preferredWidth: 200
        model: [
            {
                text: "km/h",
                value: "kmh"
            },
            {
                text: "mph",
                value: "mph"
            },
            {
                text: "m/s",
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
    ComboBox {
        id: pressUnitCombo
        Kirigami.FormData.label: i18n("Pressure:")
        enabled: miscTab.configRoot.cfg_unitsMode === "custom"
        opacity: enabled ? 1.0 : 0.5
        Layout.preferredWidth: 200
        model: [
            {
                text: "hPa",
                value: "hPa"
            },
            {
                text: "mmHg",
                value: "mmHg"
            },
            {
                text: "inHg",
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
    Label {
        Kirigami.FormData.label: ""
        text: i18n("Individual dropdowns are editable only in Custom mode.\nOther presets set units automatically.")
        wrapMode: Text.WordWrap
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        Layout.maximumWidth: 340
    }
}
