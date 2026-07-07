/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * SimpleView.qml — Simple layout mode for the widget popup.
 *
 * Layout:
 *   ┌─────────────────────────────────────────────────────────────┐
 *   │ [Temp / Feels like]  [Icon / Condition]  [Wind compass]     │
 *   ├─────────────────────────────────────────────────────────────┤
 *   │         [Humidity chip]    [Precip chip]                    │
 *   ├─────────────────────────────────────────────────────────────┤
 *   │  [Mon]  [Tue]  [Wed]  [Thu]  [Fri]  [Sat]  [Sun]  ...      │
 *   │  [icon] [icon] [icon] [icon] [icon] [icon] [icon]           │
 *   │  ↑ 12°  ↑ 10°  ...                                         │
 *   │  ↓  4°  ↓  3°  ...                                         │
 *   └─────────────────────────────────────────────────────────────┘
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W
import "js/configUtils.js" as ConfigUtils
import "js/iconResolver.js" as IconResolver
import "js/windCompass.js" as WindCompass
import "components"

ColumnLayout {
    id: simpleView

    required property var weatherRoot

    // Passed in from FullView so we can reuse the same resolver
    required property var resolveConditionIconFn

    spacing: 8

    FontLoader {
        id: svWiFont
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    readonly property bool wiFontReady: svWiFont.status === FontLoader.Ready
    readonly property string wiFontFamily: wiFontReady ? svWiFont.font.family : ""
    readonly property bool isDark: Kirigami.Theme.textColor.r > 0.5

    // ── Helpers ──────────────────────────────────────────────────────────────
    readonly property string _svTemp:      weatherRoot ? weatherRoot.tempValue(weatherRoot.temperatureC) : "--"
    readonly property string _svCond:      weatherRoot ? weatherRoot.weatherCodeToText(weatherRoot.weatherCode, weatherRoot.isNightTime()) : ""
    readonly property string _svFeels:     weatherRoot ? i18n("Feels like: %1", weatherRoot.tempValue(weatherRoot.apparentC)) : ""
    readonly property var    _svCondIcon:  weatherRoot ? resolveConditionIconFn(weatherRoot.weatherCode, weatherRoot.isNightTime(), 32) : null
    readonly property int    forecastDays: Plasmoid.configuration.forecastDays || 5
    readonly property bool   showToday:    Plasmoid.configuration.forecastShowToday !== false

    // ── SECTION 1: Hero ───────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 130

        // LEFT — temperature + feels like
        ColumnLayout {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            spacing: 2
            width: 140

            Label {
                text: simpleView._svTemp
                color: Kirigami.Theme.textColor
                font { pixelSize: Math.round(Kirigami.Units.gridUnit * 3.8); bold: true }
                minimumPixelSize: 26
                fontSizeMode: Text.HorizontalFit
                Layout.maximumWidth: 140
            }
            Label {
                text: simpleView._svFeels
                color: Kirigami.Theme.textColor
                opacity: 0.65
                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
            }
        }

        // CENTER — condition icon + condition text
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            WeatherIcon {
                iconInfo: simpleView._svCondIcon
                iconSize: 96
                Layout.alignment: Qt.AlignHCenter
            }
            Label {
                text: simpleView._svCond
                color: Kirigami.Theme.textColor
                font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({})
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.maximumWidth: 130
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // RIGHT — wind speed + compass rose + sunrise/sunset
        ColumnLayout {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4

            // Wind speed
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: weatherRoot ? weatherRoot.windValue(weatherRoot.windKmh) : "--"
                color: Kirigami.Theme.textColor
                font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
            }

            // Compass rose (Canvas)
            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 70
                height: 70

                Canvas {
                    id: windCompass
                    anchors.fill: parent

                    readonly property real windDeg: weatherRoot ? weatherRoot.windDirection : NaN
                    readonly property real windKmh: weatherRoot ? weatherRoot.windKmh : NaN
                    readonly property color textCol: Kirigami.Theme.textColor

                    onWindDegChanged: requestPaint()
                    onWindKmhChanged: requestPaint()
                    onTextColChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        WindCompass.drawWindCompass(ctx, width, height,
                            windDeg, String(textCol), null, "",
                            simpleView.isDark, windKmh);
                    }
                }
            }

            // Sunrise / Sunset with theme-aware icons
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                visible: Plasmoid.configuration.simpleShowSunriseSunset !== false

                Text {
                    visible: simpleView._useWiFont
                    Layout.alignment: Qt.AlignVCenter
                    text: "\uF051"
                    font.family: simpleView.wiFontFamily
                    font.pixelSize: Plasmoid.configuration.widgetIconSize || 16
                    color: Kirigami.Theme.textColor
                    opacity: 0.75
                }
                WeatherIcon {
                    visible: !simpleView._useWiFont
                    Layout.alignment: Qt.AlignVCenter
                    iconInfo: IconResolver.resolve("suntimes-sunrise", Plasmoid.configuration.widgetIconSize || 16, simpleView._iconsBase, simpleView._iconTheme)
                    iconSize: Plasmoid.configuration.widgetIconSize || 16
                    opacity: 0.75
                }
                Label {
                    text: weatherRoot ? weatherRoot.formatTimeForDisplay(weatherRoot.sunriseTimeText) : "--"
                    color: Kirigami.Theme.textColor
                    opacity: 0.7
                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                }
                Label {
                    text: "/"
                    color: Kirigami.Theme.textColor
                    opacity: 0.4
                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                }
                Text {
                    visible: simpleView._useWiFont
                    Layout.alignment: Qt.AlignVCenter
                    text: "\uF052"
                    font.family: simpleView.wiFontFamily
                    font.pixelSize: Plasmoid.configuration.widgetIconSize || 16
                    color: Kirigami.Theme.textColor
                    opacity: 0.75
                }
                WeatherIcon {
                    visible: !simpleView._useWiFont
                    Layout.alignment: Qt.AlignVCenter
                    iconInfo: IconResolver.resolve("suntimes-sunset", Plasmoid.configuration.widgetIconSize || 16, simpleView._iconsBase, simpleView._iconTheme)
                    iconSize: Plasmoid.configuration.widgetIconSize || 16
                    opacity: 0.75
                }
                Label {
                    text: weatherRoot ? weatherRoot.formatTimeForDisplay(weatherRoot.sunsetTimeText) : "--"
                    color: Kirigami.Theme.textColor
                    opacity: 0.7
                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                }
            }
        }
    }

    // ── SECTION 2: Stats chips — driven by widgetSimpleDetailsOrder ──────────

    // Normalise icon theme (mirrors DetailsView)
    readonly property string _iconTheme: {
        var t = Plasmoid.configuration.widgetIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property url _iconsBase: Qt.resolvedUrl("../icons/")
    readonly property bool _useWiFont: (Plasmoid.configuration.widgetIconTheme || "symbolic") === "wi-font" && wiFontReady

    // wi-font glyphs — matches _wiGlyphs in iconResolver.js
    readonly property var _wiChars: ({
        "feelslike":    "\uF053",
        "humidity":     "\uF07A",
        "pressure":     "\uF079",
        "dewpoint":     "\uF078",
        "visibility":   "\uF0B6",
        "preciprate":   "\uF04E",
        "precipsum":    "\uF07C",
        "uvindex":      "\uF072",
        "airquality":   "\uF074",
        "pollen":       "\uF082",
        "spaceweather": "\uF06E",
        "alerts":       "\uF0CE",
        "snowcover":    "\uF076"
    })

    // Enabled chip IDs from the simple-mode config key (order preserved)
    readonly property var _chipIds: {
        var raw = Plasmoid.configuration.widgetSimpleDetailsOrder || "humidity;pressure;preciprate;precipsum";
        return raw.split(";").map(function(s) { return s.trim(); }).filter(function(s) { return s.length > 0; });
    }

    // Per-item icon visibility (mirrors widgetDetailsItemIcons logic)
    readonly property var _chipShowIcon: {
        var raw = Plasmoid.configuration.widgetSimpleDetailsItemIcons || "";
        var map = {};
        raw.split(";").forEach(function(pair) {
            var kv = pair.split("=");
            if (kv.length === 2) map[kv[0].trim()] = (kv[1].trim() === "1");
        });
        return map;
    }

    function _chipLabel(id) {
        return ({
            feelslike:    i18n("Feels Like"),
            humidity:     i18n("Humidity"),
            pressure:     i18n("Pressure"),
            dewpoint:     i18n("Dew Point"),
            visibility:   i18n("Visibility"),
            preciprate:   i18n("Precipitation"),
            precipsum:    i18n("Precip Sum"),
            uvindex:      i18n("UV Index"),
            airquality:   i18n("Air Quality"),
            pollen:       i18n("Pollen"),
            spaceweather: i18n("Space Weather"),
            alerts:       i18n("Alerts"),
            snowcover:    i18n("Snow Cover")
        })[id] || id;
    }

    function _chipValue(id) {
        if (!weatherRoot) return "--";
        switch (id) {
        case "feelslike":    return weatherRoot.tempValue(weatherRoot.apparentC);
        case "humidity":     return isNaN(weatherRoot.humidityPercent) ? "--" : Math.round(weatherRoot.humidityPercent) + "%";
        case "pressure":     return weatherRoot.pressureValue(weatherRoot.pressureHpa);
        case "dewpoint":     return weatherRoot.tempValue(weatherRoot.dewPointC);
        case "visibility":   return isNaN(weatherRoot.visibilityKm) ? "--" : weatherRoot.visibilityKm.toFixed(1) + " " + i18n("km");
        case "preciprate":   return weatherRoot.precipValue(weatherRoot.precipMmh);
        case "precipsum":    return weatherRoot.precipSumText(weatherRoot.precipSumMm);
        case "uvindex":      return weatherRoot.uvIndexText(weatherRoot.uvIndex);
        case "airquality":   return weatherRoot.airQualityText();
        case "pollen":       return weatherRoot.pollenText();
        case "spaceweather": return weatherRoot.spaceWeatherText();
        case "alerts":       return weatherRoot.alertsText();
        case "snowcover":    return weatherRoot.snowDepthText(weatherRoot.snowDepthCm);
        default:             return "--";
        }
    }

    // Flow wraps chips to widget width — each chip is <icon> Label  Value on one line
    Item {
        Layout.fillWidth: true
        implicitHeight: chipsFlow.implicitHeight
        visible: Plasmoid.configuration.simpleShowStatsChips !== false

        Flow {
            id: chipsFlow
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 4

            Repeater {
                model: simpleView._chipIds

                delegate: Rectangle {
                    id: chipRect
                    required property string modelData
                    readonly property string chipId: modelData
                    readonly property bool showIcon: !(chipId in simpleView._chipShowIcon) || simpleView._chipShowIcon[chipId]
                    readonly property int _iconSz: {
                        var s = Plasmoid.configuration.widgetIconSize || 22;
                        if (s <= 16) return 16;
                        if (s <= 22) return 22;
                        if (s <= 24) return 24;
                        return 32;
                    }
                    readonly property var _iconInfo: IconResolver.resolve(chipRect.chipId, chipRect._iconSz, simpleView._iconsBase, simpleView._iconTheme)
                    // Each chip sizes to its content; Flow distributes them
                    width: chipRow.implicitWidth + 20
                    height: Math.max(36, chipRect._iconSz + 16)
                    radius: 6
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)

                    // Single line: [icon]  Label  Value
                    RowLayout {
                        id: chipRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        spacing: 5

                        // Icon — wi-font glyph or WeatherIcon, directly in RowLayout like DetailsView
                        Text {
                            visible: chipRect.showIcon && simpleView._useWiFont
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: chipRect._iconSz
                            Layout.preferredHeight: chipRect._iconSz
                            text: simpleView._wiChars[chipRect.chipId] || ""
                            font.family: simpleView.wiFontFamily
                            font.pixelSize: chipRect._iconSz - 2
                            color: Kirigami.Theme.textColor
                            opacity: 0.75
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        WeatherIcon {
                            visible: chipRect.showIcon && !simpleView._useWiFont
                            Layout.alignment: Qt.AlignVCenter
                            iconInfo: chipRect._iconInfo
                            iconSize: chipRect._iconSz
                        }

                        Label {
                            Layout.alignment: Qt.AlignVCenter
                            text: simpleView._chipLabel(chipRect.chipId)
                            color: Kirigami.Theme.textColor
                            opacity: 0.6
                            font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                        }

                        Label {
                            Layout.alignment: Qt.AlignVCenter
                            text: simpleView._chipValue(chipRect.chipId)
                            color: Kirigami.Theme.textColor
                            font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({ bold: true })
                        }
                    }
                }
            }
        }
    }

    // ── SECTION 3: Forecast squares ───────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: Plasmoid.configuration.simpleShowForecast !== false && weatherRoot && weatherRoot.dailyData && weatherRoot.dailyData.length > 0

        RowLayout {
            anchors.fill: parent
            spacing: 4

            Repeater {
                model: {
                    if (!weatherRoot || !weatherRoot.dailyData) return 0;
                    return weatherRoot.forecastDisplayCount(simpleView.showToday, simpleView.forecastDays);
                }

                delegate: Rectangle {
                    required property int index
                    readonly property int dataIndex: weatherRoot ? (weatherRoot.firstForecastDataIndex(simpleView.showToday) + index) : index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    readonly property string dayDateStr: day && day.dateStr ? day.dateStr : ""
                    readonly property bool isToday: weatherRoot && dayDateStr.length > 0 && dayDateStr === weatherRoot.locationDateString()
                    color: isToday
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)

                    readonly property var day: weatherRoot.dailyData[dataIndex]

                    ColumnLayout {
                        anchors {
                            fill: parent
                            topMargin: 8
                            bottomMargin: 8
                            leftMargin: 4
                            rightMargin: 4
                        }
                        spacing: 1

                        // Full day name
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: {
                                if (!day) return "";
                                var ds = day.dateStr || "";
                                if (isToday) return i18n("Today");
                                if (ds && weatherRoot)
                                    return weatherRoot.dayNameForDateStr(ds, Locale.LongFormat);
                                return new Date(day.time * 1000).toLocaleDateString(Qt.locale(), "dddd");
                            }
                            color: Kirigami.Theme.textColor
                            font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({ bold: true })
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            Layout.maximumWidth: parent.width - 4
                        }

                        // Short date — shown for all days including Today
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            visible: day && (day.dateStr || day.time)
                            text: {
                                if (!day) return "";
                                var ds = day.dateStr || "";
                                if (ds && weatherRoot)
                                    return weatherRoot.formatDateStrForDisplay(ds, Qt.locale().dateFormat(Locale.ShortFormat));
                                return Qt.formatDate(new Date(day.time * 1000), Qt.locale().dateFormat(Locale.ShortFormat));
                            }
                            color: Kirigami.Theme.textColor
                            opacity: 0.5
                            font: weatherRoot ? weatherRoot.wf(8, false) : Qt.font({})
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Condition icon + text grouped together, filling available height
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                WeatherIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    iconInfo: day ? resolveConditionIconFn(day.code, false, 48) : null
                                    iconSize: 48
                                }

                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, parent.parent.width - 8)
                                    visible: day && day.code !== undefined
                                    text: day && weatherRoot ? weatherRoot.weatherCodeToText(day.code) : ""
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.7
                                    font: weatherRoot ? weatherRoot.wf(8, false) : Qt.font({})
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // Mini wind compass (speed + compass rose)
                        Column {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 1
                            visible: Plasmoid.configuration.simpleShowForecastCompass !== false && day && !isNaN(day.windKmh)

                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: day ? weatherRoot.windValue(day.windKmh) : ""
                                color: Kirigami.Theme.textColor
                                font: weatherRoot ? weatherRoot.wf(8, true) : Qt.font({ bold: true })
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Canvas {
                                width: 64; height: 64

                                readonly property real windDeg: day ? (isNaN(day.windDir) ? NaN : day.windDir) : NaN
                                readonly property real windKmhVal: day ? day.windKmh : NaN
                                readonly property color textCol: Kirigami.Theme.textColor

                                onWindDegChanged: requestPaint()
                                onWindKmhValChanged: requestPaint()
                                onTextColChanged: requestPaint()
                                Component.onCompleted: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d");
                                    WindCompass.drawWindCompass(ctx, width, height,
                                        windDeg, String(textCol), null, "",
                                        simpleView.isDark, windKmhVal, true);
                                }
                            }
                        }

                        // Low / High on one line:  ↓ 6°  ↑ 22°
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6
                            spacing: 4
                            Label {
                                text: "↓"
                                color: "#42a5f5"
                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                            }
                            Label {
                                text: day ? weatherRoot.tempValue(day.minC) : "--"
                                color: "#42a5f5"
                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                            }
                            Label {
                                text: "↑"
                                color: "#ff6e40"
                                font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({ bold: true })
                            }
                            Label {
                                text: day ? weatherRoot.tempValue(day.maxC) : "--"
                                color: "#ff6e40"
                                font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({ bold: true })
                            }
                        }


                    }
                }
            }
        }
    }
}
