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
 * ForecastView.qml — "Forecast" tab of the main widget popup
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W
import "js/iconResolver.js" as IconResolver
import "components"

Item {
    id: forecastRoot
    property var weatherRoot
    property int expandedIndex: -1

    // Set implicit height based on content
    implicitHeight: (weatherRoot && weatherRoot.dailyData.length > 0) ? forecastColumn.height : (emptyLabel.implicitHeight + 40) // extra space for centering

    // Font for weather icons (wind direction glyph)
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    // Resolved at load time so the path is correct in all rendering contexts
    readonly property url iconsBaseDir: Qt.resolvedUrl("../icons/")

    // Forecast icon theme — uses the same theme as the main condition icon.
    readonly property string widgetIconTheme: {
        var t = Plasmoid.configuration.conditionIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property int iconSz: Plasmoid.configuration.widgetIconSize || 16
    readonly property string iconTheme: widgetIconTheme
    readonly property bool showSunEvents: Plasmoid.configuration.forecastShowSunEvents !== false

    /** Resolve a condition icon, handling the "custom" theme with per-condition overrides */
    function resolveConditionIcon(code, isNight, iconSize) {
        if (forecastRoot.widgetIconTheme === "custom") {
            var raw = Plasmoid.configuration.widgetConditionCustomIcons || "";
            var m = {};
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        m[kv[0].trim()] = kv[1].trim();
                });
            }
            if (m["condition-custom"] === "1") {
                var condKey;
                if (code === 0)
                    condKey = isNight ? "condition-clear-night" : "condition-clear";
                else if (code === 1)
                    condKey = isNight ? "condition-few-clouds-night" : "condition-few-clouds";
                else if (code === 2)
                    condKey = isNight ? "condition-cloudy-night" : "condition-cloudy-day";
                else if (code === 3)
                    condKey = "condition-overcast";
                else if (code === 45 || code === 48)
                    condKey = "condition-fog";
                else if (code === 51 || code === 53 || code === 55 || code === 61 || code === 80)
                    condKey = isNight ? "condition-showers-scattered-night" : "condition-showers-scattered-day";
                else if (code === 63 || code === 65 || code === 81 || code === 82)
                    condKey = isNight ? "condition-showers-night" : "condition-showers-day";
                else if (code === 56 || code === 66)
                    condKey = isNight ? "condition-freezing-scattered-rain-night" : "condition-freezing-scattered-rain-day";
                else if (code === 57 || code === 67)
                    condKey = isNight ? "condition-freezing-rain-night" : "condition-freezing-rain-day";
                else if (code === 71 || code === 77 || code === 85)
                    condKey = isNight ? "condition-snow-scattered-night" : "condition-snow-scattered-day";
                else if (code === 73 || code === 75 || code === 86)
                    condKey = isNight ? "condition-snow-night" : "condition-snow-day";
                else if (code === 95)
                    condKey = isNight ? "condition-storm-night" : "condition-storm-day";
                else if (code === 96)
                    condKey = isNight ? "condition-hail-storm-rain-night" : "condition-hail-storm-rain-day";
                else if (code === 99)
                    condKey = isNight ? "condition-hail-storm-snow-night" : "condition-hail-storm-snow-day";
                else
                    condKey = isNight ? "condition-clear-night" : "condition-clear";
                var fallback = W.weatherCodeToIcon(code, isNight);
                var saved = (condKey in m && m[condKey].length > 0) ? m[condKey] : fallback;
                return { type: "kde", source: saved, svgFallback: "", isMask: false };
            }
            return IconResolver.resolveCondition(code, isNight, iconSize, forecastRoot.iconsBaseDir, "kde");
        }
        return IconResolver.resolveCondition(code, isNight, iconSize, forecastRoot.iconsBaseDir, forecastRoot.widgetIconTheme);
    }

    // ── empty state ───────────────────────────────────────────────────────
    Label {
        id: emptyLabel
        anchors.centerIn: parent
        visible: !weatherRoot || weatherRoot.dailyData.length === 0
        text: (weatherRoot && weatherRoot.loading) ? i18n("Loading forecast…") : i18n("No forecast data")
        color: Kirigami.Theme.textColor
        font: weatherRoot ? weatherRoot.wf(12, false) : Qt.font({})
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        visible: weatherRoot && weatherRoot.dailyData.length > 0

        Column {
            id: forecastColumn
            width: parent.width
            spacing: 0

            Repeater {
                model: weatherRoot && weatherRoot.dailyData.length > 0 ? Math.min(Plasmoid.configuration.forecastDays, weatherRoot.dailyData.length) : 0

                delegate: Column {
                    required property int index
                    width: parent.width
                    spacing: 0

                    // ── day row ─────────────────────────────────────────
                    Rectangle {
                        id: dayRow
                        width: parent.width
                        height: Math.max(52, rowLayoutInner.implicitHeight + 12)
                        color: (rowMouse.containsMouse || forecastRoot.expandedIndex === index) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        RowLayout {
                            id: rowLayoutInner
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 14
                            }
                            spacing: 0

                            Kirigami.Icon {
                                source: forecastRoot.expandedIndex === index ? "arrow-down" : "arrow-right"
                                width: 14
                                height: 14
                                opacity: 0.45
                                Layout.alignment: Qt.AlignVCenter
                                Layout.rightMargin: 6
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 110
                                Layout.minimumWidth: 110
                                Layout.maximumWidth: 110
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1
                                Label {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: {
                                        if (index === 0)
                                            return i18n("Today");
                                        var ds = weatherRoot.dailyData[index].dateStr;
                                        if (!ds)
                                            return "";
                                        var parts = ds.split("-");
                                        if (parts.length !== 3)
                                            return "";
                                        var d = new Date(parts[0], parts[1] - 1, parts[2]);
                                        return Qt.locale().dayName(d.getDay(), Locale.LongFormat);
                                    }
                                    color: Kirigami.Theme.textColor
                                    font: weatherRoot.wf(12, true)
                                }
                                Label {
                                    text: {
                                        var ds = weatherRoot.dailyData[index].dateStr || "";
                                        if (!ds)
                                            return "";
                                        var d = new Date(ds);
                                        var fmt = Qt.locale().dateFormat(Locale.ShortFormat);
                                        return Qt.formatDate(d, fmt);
                                    }
                                    color: Kirigami.Theme.textColor
                                    font: weatherRoot.wf(9, false)
                                }
                            }

                            WeatherIcon {
                                iconInfo: forecastRoot.resolveConditionIcon(
                                    weatherRoot.dailyData[index].code, false,
                                    forecastRoot.iconSz)
                                iconSize: 28
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.rightMargin: 4
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: weatherRoot.weatherCodeToText(weatherRoot.dailyData[index].code)
                                color: Kirigami.Theme.textColor
                                font: weatherRoot.wf(11, false)
                                wrapMode: Text.WordWrap
                            }

                            Item {
                                Layout.preferredWidth: 8
                            }

                            RowLayout {
                                spacing: 2
                                Layout.alignment: Qt.AlignRight
                                Label {
                                    text: weatherRoot.tempValue(weatherRoot.dailyData[index].minC)
                                    color: "#42a5f5"
                                    font: weatherRoot.wf(12, false)
                                }
                                Label {
                                    text: "/"
                                    color: Kirigami.Theme.textColor
                                    font: weatherRoot.wf(12, false)
                                }
                                Label {
                                    text: weatherRoot.tempValue(weatherRoot.dailyData[index].maxC)
                                    color: "#ff6e40"
                                    font: weatherRoot.wf(12, true)
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (forecastRoot.expandedIndex === index) {
                                    forecastRoot.expandedIndex = -1;
                                } else {
                                    forecastRoot.expandedIndex = index;
                                    if (weatherRoot) {
                                        weatherRoot.hourlyData = [];
                                        weatherRoot.fetchHourlyForDate(weatherRoot.dailyData[index].dateStr || "");
                                    }
                                }
                            }
                        }
                    }

                    // ── inline hourly panel ─────────────────────────────
                    Rectangle {
                        width: parent.width
                        height: forecastRoot.expandedIndex === index ? 240 : 0
                        visible: height > 0
                        clip: true
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        Behavior on height {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.InOutQuad
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: !weatherRoot || weatherRoot.hourlyData.length === 0
                            text: i18n("Loading hourly data…")
                            color: Kirigami.Theme.textColor
                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                        }

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: weatherRoot && weatherRoot.hourlyData.length > 0
                            clip: true
                            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                            ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                            Row {
                                spacing: 6
                                height: parent.height

                                // Build combined model: hourly entries + sunrise/sunset marker cards
                                // inserted between the hour that precedes each event.
                                property var _hourlyWithSun: {
                                    if (!weatherRoot || !weatherRoot.hourlyData.length) return [];
                                    if (!forecastRoot.showSunEvents)
                                        return weatherRoot.hourlyData;
                                    function toMins(t) {
                                        if (!t || t === "--") return -1;
                                        var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                    }
                                    var rise = toMins(weatherRoot.sunriseTimeText);
                                    var set_ = toMins(weatherRoot.sunsetTimeText);
                                    var riseInserted = rise < 0, setInserted = set_ < 0;
                                    var result = [];
                                    weatherRoot.hourlyData.forEach(function(h) {
                                        var hm = toMins(h.hour);
                                        if (!riseInserted && hm >= 0 && hm > rise) {
                                            result.push({ isSunrise: true,  isSunset: false, time: weatherRoot.sunriseTimeText });
                                            riseInserted = true;
                                        }
                                        if (!setInserted && hm >= 0 && hm > set_) {
                                            result.push({ isSunrise: false, isSunset: true,  time: weatherRoot.sunsetTimeText });
                                            setInserted = true;
                                        }
                                        result.push(h);
                                    });
                                    return result;
                                }

                                Repeater {
                                    model: parent._hourlyWithSun

                                    delegate: Rectangle {
                                        required property var modelData
                                        // Sunrise/sunset cards are slim; hourly cards are full height
                                        width: (modelData.isSunrise || modelData.isSunset) ? 70 : 100
                                        height: 200
                                        radius: 8
                                        color: (modelData.isSunrise || modelData.isSunset)
                                            ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                                            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                                        border.width: 1

                                        // ── Sunrise / Sunset card ─────────────────────────────
                                        ColumnLayout {
                                            visible: modelData.isSunrise === true || modelData.isSunset === true
                                            anchors.centerIn: parent
                                            spacing: 6
                                            WeatherIcon {
                                                Layout.alignment: Qt.AlignHCenter
                                                iconInfo: IconResolver.resolve(
                                                    modelData.isSunrise ? "sunrise" : "sunset",
                                                    32,
                                                    forecastRoot.iconsBaseDir,
                                                    forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                    (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom" || forecastRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : forecastRoot.widgetIconTheme)
                                                iconSize: 32
                                                iconColor: Kirigami.Theme.textColor
                                            }
                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: weatherRoot ? weatherRoot.formatTimeForDisplay(modelData.time) : "--"
                                                color: Kirigami.Theme.textColor
                                                font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({ bold: true })
                                            }
                                        }

                                        // ── Regular hourly card ───────────────────────────────
                                        ColumnLayout {
                                            visible: !(modelData.isSunrise === true || modelData.isSunset === true)
                                            anchors {
                                                fill: parent
                                                margins: 6
                                            }
                                            spacing: 4


                                            // Fix bug with time formatting – formatted according to system locale (12h/24h)
                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: {
                                                    if (!modelData.hour || modelData.hour === "--")
                                                        return "--";
                                                    var parts = modelData.hour.split(":");
                                                    if (parts.length < 2)
                                                        return modelData.hour;
                                                    var h = parseInt(parts[0], 10);
                                                    var m = parseInt(parts[1], 10);
                                                    if (isNaN(h) || isNaN(m))
                                                        return modelData.hour;
                                                    var d = new Date();
                                                    d.setHours(h, m, 0, 0);
                                                    return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
                                                }
                                                color: Kirigami.Theme.textColor
                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                            }

                                            WeatherIcon {
                                                Layout.alignment: Qt.AlignHCenter
                                                iconInfo: {
                                                    // Derive night flag from the hour vs sunrise/sunset
                                                    var isNight = false;
                                                    if (modelData.hour && modelData.hour !== "--") {
                                                        var parts = modelData.hour.split(":");
                                                        if (parts.length >= 2) {
                                                            var hMins = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                                                            function parseSunMins(t) {
                                                                if (!t || t === "--") return -1;
                                                                var p = t.split(":");
                                                                return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                                            }
                                                            var rise = parseSunMins(weatherRoot ? weatherRoot.sunriseTimeText : "--");
                                                            var set_ = parseSunMins(weatherRoot ? weatherRoot.sunsetTimeText : "--");
                                                            if (rise >= 0 && set_ >= 0)
                                                                isNight = hMins < rise || hMins >= set_;
                                                        }
                                                    }
                                                    return forecastRoot.resolveConditionIcon(
                                                        modelData.code || 0, isNight,
                                                        forecastRoot.iconSz);
                                                }
                                                iconSize: 48
                                            }

                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: weatherRoot ? weatherRoot.tempValue(modelData.tempC) : "--"
                                                color: Kirigami.Theme.textColor
                                                font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                    bold: true
                                                })
                                            }

                                            // Wind speed + direction (using font glyph for direction)
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 4
                                                Label {
                                                    text: weatherRoot && modelData.windKmh !== undefined ? weatherRoot.windValue(modelData.windKmh) : "--"
                                                    color: Kirigami.Theme.textColor
                                                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                }
                                                Text {
                                                    visible: weatherRoot && !isNaN(modelData.windDeg)
                                                    text: W.windDirectionGlyph(modelData.windDeg)
                                                    font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                    font.pixelSize: 20  // adjust to match visual size
                                                    color: Kirigami.Theme.textColor
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }

                                            // Precipitation probability
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 3
                                                WeatherIcon {
                                                    iconInfo: IconResolver.resolve("umbrella", 32, forecastRoot.iconsBaseDir,
                                                        forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                        (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom" || forecastRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : forecastRoot.widgetIconTheme)
                                                    iconSize: 32
                                                    iconColor: Kirigami.Theme.textColor
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    text: {
                                                        var pp = modelData.precipProb;
                                                        if (pp !== undefined && pp !== null && !isNaN(pp))
                                                            return Math.round(pp) + "%";
                                                        var h = modelData.humidity;
                                                        return (!isNaN(h) && h !== undefined) ? Math.round(h) + "%" : "--";
                                                    }
                                                    color: Kirigami.Theme.textColor
                                                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                }
                                            }

                                            // Precipitation rate (mm/h)
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: -5
                                                visible: modelData.precipMm !== undefined && !isNaN(modelData.precipMm) && modelData.precipMm > 0
                                                WeatherIcon {
                                                    iconInfo: IconResolver.resolve("preciprate", 32, forecastRoot.iconsBaseDir,
                                                        forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                        (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom" || forecastRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : forecastRoot.widgetIconTheme)
                                                    iconSize: 32
                                                    iconColor: Kirigami.Theme.textColor
                                                    opacity: 0.6
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    text: weatherRoot ? weatherRoot.precipValue(modelData.precipMm) : "--"
                                                    color: Kirigami.Theme.textColor
                                                    opacity: 0.6
                                                    font: weatherRoot ? weatherRoot.wf(8, false) : Qt.font({})
                                                }
                                            }

                                        } // ColumnLayout (regular)
                                    } // Rectangle delegate
                                } // Repeater
                            } // ScrollView content Row
                        } // ScrollView
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                    }
                }
            }
        }
    }
}
