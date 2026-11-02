/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * SimpleView.qml - Simple layout mode for the widget popup.
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
import org.kde.plasma.core as PlasmaCore

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

    // ── Weather alerts (the icon next to the condition icon, its tooltip) ─────────
    // weatherRoot.weatherAlerts as the Details tab reads it. The alerts that have not expired yet,
    // sorted by onset; "now" is a property that a timer refreshes, so an alert that expires while
    // the popup is open goes away (new Date() on its own is not a binding dependency).
    property var _alertNow: new Date()
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: simpleView._alertNow = new Date()
    }
    readonly property var _alertList: {
        var src = (weatherRoot && weatherRoot.weatherAlerts) ? weatherRoot.weatherAlerts : [];
        var now = simpleView._alertNow;
        var out = [];
        for (var i = 0; i < src.length; ++i) {
            var ex = src[i].expires ? new Date(src[i].expires) : null;
            if (ex && !isNaN(ex.getTime()) && ex < now)
                continue;
            out.push(src[i]);
        }
        out.sort(function (a, b) {
            var da = a.onset ? new Date(a.onset).getTime() : 0;
            var db = b.onset ? new Date(b.onset).getTime() : 0;
            return da - db;
        });
        return out;
    }
    function _alertColor(c) {
        c = (c || "").toLowerCase();
        if (c === "yellow")
            return isDark ? "#ffc107" : "#9a7b00";
        if (c === "orange")
            return isDark ? "#ff8c00" : "#c04000";
        if (c === "red")
            return isDark ? "#ff4444" : "#cc0000";
        return Kirigami.Theme.textColor;
    }
    function _alertDateTime(iso) {
        if (!iso || !weatherRoot)
            return "";
        var d = new Date(iso);
        if (isNaN(d.getTime()))
            return "";
        return weatherRoot.formatDateObj(d, true) + ", " + weatherRoot.formatTimeObj(d);
    }
    // Map an alert's source to a link to its provider
    function _alertProviderLink(src) {
        src = (src || "").trim();
        if (src === "NWS")
            return "<a href='https://www.weather.gov/'>NOAA NWS</a>";
        if (src === "MET Norway")
            return "<a href='https://www.met.no/'>MET Norway</a>";
        if (src === "MeteoAlarm")
            return "<a href='https://www.meteoalarm.org/'>EUMETNET MeteoAlarm</a>";
        if (src === "PirateWeather")
            return "<a href='https://pirateweather.net/'>Pirate Weather</a>";
        if (src === "VisualCrossing")
            return "<a href='https://www.visualcrossing.com/'>Visual Crossing</a>";
        if (src === "WeatherAPI")
            return "<a href='https://www.weatherapi.com/'>WeatherAPI.com</a>";
        if (src === "LibreWXR")
            return "<a href='https://librewxr.net/'>LibreWXR</a>";
        if (src === "FOSS Public Alert Server")
            return "<a href='https://alerts.kde.org/'>FOSS Public Alert Server</a>";
        if (src.length > 0)
            return src;
        return "<a href='https://www.meteoalarm.org/'>EUMETNET MeteoAlarm</a>";
    }
    function _formatNwsDescription(desc) {
        if (!desc)
            return "";
        var text = desc.replace(/\r?\n/g, "<br>");
        text = text.replace(/\*\s+WHAT\s*\.{3}/gi, "<br><b>WHAT:</b> ");
        text = text.replace(/\*\s+WHERE\s*\.{3}/gi, "<br><b>WHERE:</b> ");
        text = text.replace(/\*\s+WHEN\s*\.{3}/gi, "<br><b>WHEN:</b> ");
        text = text.replace(/\*\s+IMPACTS?\s*\.{3}/gi, "<br><b>IMPACTS:</b> ");
        text = text.replace(/\*\s+ADDITIONAL\s+DETAILS\s*\.{3}/gi, "<br><b>ADDITIONAL DETAILS:</b> ");
        text = text.replace(/\*\s+HAZARD\s*\.{3}/gi, "<br><b>HAZARD:</b> ");
        text = text.replace(/\*\s+SOURCE\s*\.{3}/gi, "<br><b>SOURCE:</b> ");
        text = text.replace(/\*\s+IMPACT\s*\.{3}/gi, "<br><b>IMPACT:</b> ");
        text = text.replace(/\*\s+PRECAUTIONARY\/PREPAREDNESS\s+ACTIONS\s*\.{3}/gi, "<br><b>PRECAUTIONARY ACTIONS:</b> ");
        text = text.replace(/(<br>\s*){3,}/g, "<br><br>");
        text = text.replace(/^(<br>)+/, "");
        return text;
    }
    // The town of the location and the area of the alert: the heading of an alert in the tooltip
    function _alertTooltipTitle(a) {
        var town = (Plasmoid.configuration.locationName || "").split(",")[0].trim();
        var area = a ? (a.area || "") : "";
        if (town && area)
            return town + ", " + area;
        return town || area;
    }
    // The fields of an alert (the same ones, in the same order, as the Details tab's tooltip)
    function _alertTooltipSub(a) {
        var lines = [];
        if (a.headline)
            lines.push("<b>" + i18n("Headline") + ":</b> " + a.headline);
        if (a.description) {
            if (a.source === "NWS")
                lines.push("<b>" + i18n("Description") + ":</b><br>" + _formatNwsDescription(a.description));
            else
                lines.push("<b>" + i18n("Description") + ":</b><br>" + a.description);
        }
        if (a.effective)
            lines.push("<b>" + i18n("Effective") + ":</b> " + _alertDateTime(a.effective));
        if (a.expires)
            lines.push("<b>" + i18n("Expires") + ":</b> " + _alertDateTime(a.expires));
        if (a.instruction)
            lines.push("<b>" + i18n("Instruction") + ":</b><br>" + a.instruction);
        if (a.source || a.senderName)
            lines.push("<b>" + i18n("Provider") + ":</b> " + _alertProviderLink(a.source));
        if (a.web)
            lines.push("<b>" + i18n("Website") + ":</b> <a href='" + a.web + "'>" + a.web + "</a>");
        return lines.join("<br>");
    }
    // The whole tooltip as one rich text: each alert is its heading and its fields, a rule between
    // alerts. One alert shows exactly what the Details tab's tooltip shows; with several, each
    // also gets its name (in the color of its level). A few only: a long list would not fit.
    readonly property string _alertTooltipHtml: {
        var list = simpleView._alertList;
        var shown = Math.min(list.length, 3);
        var parts = [];
        for (var i = 0; i < shown; ++i) {
            var a = list[i];
            var head = "";
            if (list.length > 1) {
                var name = a.displayName || a.headline || "";
                if (name)
                    head += "<b><font color='" + simpleView._alertColor(a.color) + "'>" + name + "</font></b><br>";
            }
            var title = simpleView._alertTooltipTitle(a);
            if (title)
                head += "<b>" + title + "</b><br>";
            parts.push(head + simpleView._alertTooltipSub(a));
        }
        var html = parts.join("<hr>");
        if (list.length > shown)
            html += "<hr><i>" + i18np("and %1 more alert", "and %1 more alerts", list.length - shown) + "</i>";
        return html;
    }

    // ── SECTION 1: Hero ───────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 130

        // LEFT - temperature + feels like
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

        // CENTER - condition icon + condition text
        ColumnLayout {
            id: condColumn
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

        // RIGHT - wind speed + compass rose + sunrise/sunset
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

        // ── Weather alert: a warning icon beside the condition icon ──────────────
        // Only there while there is an alert; it does not move the condition icon. The tooltip is
        // built like the Details tab's (a fixed-width rich text label: the heading and the fields
        // of each alert). Declared last, a child of the hero itself: on top of the other items.
        PlasmaCore.ToolTipArea {
            x: condColumn.x + condColumn.width / 2 + 50
            y: condColumn.y
            width: 32
            height: 32
            visible: simpleView._alertList.length > 0
            active: true
            mainItem: ColumnLayout {
                width: 380
                spacing: 6
                Label {
                    text: simpleView._alertTooltipHtml
                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    width: parent.width
                    Layout.fillWidth: true
                }
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 28
                height: 28
                source: "dialog-warning"
            }
        }
    }

    // ── SECTION 2: Stats chips - driven by widgetSimpleDetailsOrder ──────────

    // Normalise icon theme (mirrors DetailsView)
    readonly property string _iconTheme: {
        var t = Plasmoid.configuration.widgetIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property url _iconsBase: Qt.resolvedUrl("../icons/")
    readonly property bool _useWiFont: (Plasmoid.configuration.widgetIconTheme || "symbolic") === "wi-font" && wiFontReady

    // wi-font glyphs - matches _wiGlyphs in iconResolver.js
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

    // Flow wraps chips to widget width - each chip is <icon> Label  Value on one line
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

                        // Icon - wi-font glyph or WeatherIcon, directly in RowLayout like DetailsView
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

    // ── SECTION 3a: Forecast as a graph (Forecast layout = Graphs) ────────────
    // The same chart the Forecast tab uses, in its "Compact" style (ForecastChartStack: the
    // temperature graph with high / low lines, a weather icon for every day and the precipitation
    // strip). Pointing at a day lists its wind, pressure, Kp, UV and visibility in a card; which
    // ones is chosen with the "Show in forecast" switches of the settings.
    readonly property bool _graphsLayout: Plasmoid.configuration.simpleForecastLayout === "graphs"

    // Chart files, resolved from this file. Qt Graphs first; when that module is missing the
    // Loader fails and HistoryChartKQC.qml (KQuickCharts) takes over, as in the Forecast tab.
    readonly property string _chartGraphsUrl: String(Qt.resolvedUrl("components/HistoryChartGraphs.qml"))
    readonly property string _chartKqcUrl: String(Qt.resolvedUrl("components/HistoryChartKQC.qml"))
    property string _chartSource: _chartGraphsUrl

    // Daily precipitation of an entry of weatherRoot.dailyData (mm), NaN when it has none.
    // The first of these fields that holds a number is used.
    function _dayPrecip(d) {
        var keys = ["precipMm", "precipSumMm", "precipSum", "precip"];
        for (var i = 0; i < keys.length; ++i) {
            var v = d[keys[i]];
            if (typeof v === "number" && isFinite(v))
                return v;
        }
        return NaN;
    }

    // The details listed for the day under the pointer ("Show in forecast" switches of the settings;
    // all on by default). Own settings, separate from the Advanced mode's.
    readonly property bool _fcWind: Plasmoid.configuration.simpleForecastShowWind !== false
    readonly property bool _fcPressure: Plasmoid.configuration.simpleForecastShowPressure !== false
    readonly property bool _fcKp: Plasmoid.configuration.simpleForecastShowKpIndex !== false
    readonly property bool _fcUv: Plasmoid.configuration.simpleForecastShowUvIndex !== false
    readonly property bool _fcVis: Plasmoid.configuration.simpleForecastShowVisibility !== false

    function _isNum(v) {
        return typeof v === "number" && isFinite(v);
    }

    // The same days as the Standard layout shows (forecastDays, "Show Today"), as chart entries.
    // They carry what the details need (wind, pressure, Kp, UV, visibility) like the Forecast tab's.
    readonly property var _graphDays: {
        if (!weatherRoot || !weatherRoot.dailyData)
            return [];
        var total = Math.min(simpleView.forecastDays, weatherRoot.dailyData.length);
        var out = [];
        for (var i = simpleView.showToday ? 0 : 1; i < total; ++i) {
            var d = weatherRoot.dailyData[i];
            var kp = NaN, gScale = "";
            if (simpleView._fcKp) {
                var ke = weatherRoot.kpForecastForDate(d.dateStr || "");
                if (ke && isFinite(ke.kp)) {
                    kp = ke.kp;
                    gScale = ke.gScale || "G0";
                }
            }
            out.push({
                dateStr: d.dateStr || "",
                time: d.time,
                code: d.code,
                maxC: d.maxC,
                minC: d.minC,
                precipMm: simpleView._dayPrecip(d),
                isToday: weatherRoot.isDailyRowToday(i),
                windKmh: d.windKmh,
                windDeg: d.windDir,
                pressureHpa: d.pressureHpa,
                kp: kp,
                gScale: gScale,
                uv: d.uvMax,
                visibilityKm: d.visibilityKm
            });
        }
        return out;
    }

    // The details card of the compact graph (the same rows, colors and texts as the Forecast tab's
    // Compact graph style). A detail is listed when its switch is on and some day has a value.
    // (The closures do not capture the data: they only read weatherRoot.)
    readonly property var _detailMetrics: {
        var items = simpleView._graphDays;
        var wr = weatherRoot;
        var out = [];
        if (!wr || items.length < 2)
            return out;
        function has(key) {
            for (var i = 0; i < items.length; ++i)
                if (simpleView._isNum(items[i][key]))
                    return true;
            return false;
        }
        if (simpleView._fcWind && has("windKmh"))
            out.push({
                key: "windKmh",
                label: i18n("Wind"),
                color: "#66bb6a",
                fmt: function (v) {
                    return wr.windValue(v);
                },
                // the wind direction arrow after the value (a weather-icons glyph)
                glyph: function (i, entry) {
                    return entry && simpleView._isNum(entry.windDeg) ? W.windDirectionGlyph(entry.windDeg) : "";
                }
            });
        if (simpleView._fcPressure && has("pressureHpa"))
            out.push({
                key: "pressureHpa",
                label: i18n("Pressure"),
                color: "#ab47bc",
                fmt: function (v) {
                    return wr.pressureValue(v);
                }
            });
        if (simpleView._fcKp && has("kp"))
            out.push({
                key: "kp",
                label: i18n("Kp index (G scale)"),
                color: "#ffa726",
                fmt: function (v) {
                    return String(Math.round(v));
                },
                badge: function (i, key, v, e) {
                    return "Kp " + v.toFixed(1) + " (" + ((e && e.gScale) || "G0") + ")";
                }
            });
        if (simpleView._fcUv && has("uv"))
            out.push({
                key: "uv",
                label: i18n("UV index"),
                color: "#ffb300",
                fmt: function (v) {
                    return String(Math.round(v * 10) / 10);
                }
            });
        if (simpleView._fcVis && has("visibilityKm"))
            out.push({
                key: "visibilityKm",
                label: i18n("Visibility"),
                color: "#90a4ae",
                fmt: function (v) {
                    return wr.visibilityValue(v);
                }
            });
        return out;
    }

    Item {
        id: graphForecast
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: forecastGraphs.implicitHeight
        implicitHeight: forecastGraphs.implicitHeight
        visible: Plasmoid.configuration.simpleShowForecast !== false && simpleView._graphsLayout && simpleView._graphDays.length > 1

        // What the chart asks its "view" for: value, date and day texts
        QtObject {
            id: graphAdapter
            // (the same texts as the Forecast tab's daily graph)
            function _isNum(v) {
                return typeof v === "number" && isFinite(v);
            }
            function _temp(c) {
                return _isNum(c) && weatherRoot ? weatherRoot.tempValue(c) : "--";
            }
            function _precip(mm) {
                return _isNum(mm) && weatherRoot ? weatherRoot.precipSumText(mm) : "--";
            }
            /** The region's short date format without the year (day and month only) */
            function _regionDayMonthPattern() {
                var fmt = Qt.locale().dateFormat(Locale.ShortFormat);
                var f = fmt.replace(/[\s.\/\-,]*y+[^dM]*$/, "")      // year at the end (with a trailing "г." and the like)
                    .replace(/^\s*y+[\s.\/\-,]*/, "")              // year first
                    .replace(/[\s.\/\-,]*y+/, "");                  // year in the middle
                return f.trim() !== "" ? f : fmt;
            }
            /** The axis labels follow Appearance > Misc > Date format as it is set (a preset or a
             *  custom pattern). Only the two "Region default" choices, which have no pattern of
             *  their own, are shown as day and month. */
            function _date(ds, entry) {
                if (!weatherRoot || !ds)
                    return "--";
                var fmt = weatherRoot.dateFormatSetting;
                if (fmt !== "locale-long" && fmt !== "locale-short" && fmt)
                    return weatherRoot.formatIsoDate(ds, true);
                var p = ds.substring(0, 10).split("-");
                if (p.length !== 3)
                    return "--";
                return Qt.formatDate(new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10)), _regionDayMonthPattern());
            }
            // the title shown above the pointer: "Today", else the day name and the date
            function _day(ds, longName, entry) {
                if (!weatherRoot || !ds)
                    return "--";
                var name = i18n("Today");
                if (!entry || !entry.isToday) {
                    var parts = ds.split("-");
                    name = parts.length === 3 ? Qt.locale().dayName(new Date(parts[0], parts[1] - 1, parts[2]).getDay(), Locale.LongFormat) : "";
                }
                return name + ", " + weatherRoot.formatIsoDate(ds, true);
            }
        }

        ForecastChartStack {
            id: forecastGraphs
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            chartSource: simpleView._chartSource
            active: graphForecast.visible
            view: graphAdapter
            days: simpleView._graphDays
            metrics: []
            showMain: true
            mainIndex: 0
            outerFlickable: null
            // ONE compact graph (the Advanced mode's "Compact" graph style): temperature, icons and
            // the precipitation strip; the other details are listed for the day under the pointer
            combined: true
            detailMetrics: simpleView._detailMetrics
            glyphFont: simpleView.wiFontFamily

            // The temperature graph: high and low lines (the colors of the Standard layout),
            // a weather icon above every day, and the precipitation strip below.
            configureMain: function (chart) {
                chart.seriesDefs = Qt.binding(function () {
                    return [
                        {
                            key: "maxC",
                            color: "#ff6e40",
                            label: i18n("High")
                        },
                        {
                            key: "minC",
                            color: "#42a5f5",
                            label: i18n("Low")
                        }
                    ];
                });
                chart.precipLegend = i18n("Precipitation");
                chart.showIcons = true;
                chart.iconSize = Kirigami.Units.gridUnit * 2;
                chart.iconAt = function (i) {
                    // reads _graphDays, so the icons follow the data when it is refreshed
                    var d = simpleView._graphDays[i];
                    return d ? simpleView.resolveConditionIconFn(d.code, false, 48) : null;
                };
            }
            // Qt Graphs missing or too old: use the KQuickCharts chart instead
            onChartStatus: function (loader) {
                if (loader.status !== Loader.Error || simpleView._chartSource !== simpleView._chartGraphsUrl)
                    return;
                // Switching the source from inside its own status change would be a binding
                // loop (as in the Forecast tab), so do it a moment later.
                console.warn("SimpleView: Qt Graphs chart unavailable, using KDE Quick Charts");
                Qt.callLater(function () {
                    simpleView._chartSource = simpleView._chartKqcUrl;
                });
            }
        }

        // An info button in the bottom-right corner of the graph (it takes no room of its own,
        // it sits over the corner): its tooltip says how to use the graph. Declared after the
        // chart, so it is on top of it.
        PlasmaCore.ToolTipArea {
            anchors.right: forecastGraphs.right
            anchors.bottom: forecastGraphs.bottom
            anchors.rightMargin: Kirigami.Units.smallSpacing
            anchors.bottomMargin: Kirigami.Units.smallSpacing
            width: Kirigami.Units.iconSizes.small
            height: Kirigami.Units.iconSizes.small
            active: true
            mainItem: Label {
                width: Kirigami.Units.gridUnit * 18
                wrapMode: Text.Wrap
                text: i18n("Point at a day to see its details. Double-click the graph, or hold Ctrl and scroll the mouse wheel, to zoom in.")
            }
            Kirigami.Icon {
                anchors.fill: parent
                source: "help-about"
                opacity: 0.6
            }
        }
    }

    // ── SECTION 3b: Forecast squares (Forecast layout = Standard) ─────────────
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: Plasmoid.configuration.simpleShowForecast !== false && !simpleView._graphsLayout && weatherRoot && weatherRoot.dailyData && weatherRoot.dailyData.length > 0

        RowLayout {
            anchors.fill: parent
            spacing: 4

            Repeater {
                model: {
                    if (!weatherRoot || !weatherRoot.dailyData) return 0;
                    var total = Math.min(simpleView.forecastDays, weatherRoot.dailyData.length);
                    return simpleView.showToday ? total : Math.max(0, total - 1);
                }

                delegate: Rectangle {
                    required property int index
                    readonly property int dataIndex: simpleView.showToday ? index : index + 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: dataIndex === 0
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
                                if (weatherRoot && weatherRoot.isDailyRowToday(dataIndex)) return i18n("Today");
                                var ds = day.dateStr || "";
                                if (ds) {
                                    var parts = ds.split("-");
                                    if (parts.length === 3) {
                                        var dt = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
                                        return Qt.locale().dayName(dt.getDay(), Locale.LongFormat);
                                    }
                                }
                                return new Date(day.time * 1000).toLocaleDateString(Qt.locale(), "dddd");
                            }
                            color: Kirigami.Theme.textColor
                            font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({ bold: true })
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            Layout.maximumWidth: parent.width - 4
                        }

                        // Short date - shown for all days including Today
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            visible: day && (day.dateStr || day.time)
                            text: {
                                if (!day) return "";
                                var ds = day.dateStr || "";
                                if (ds)
                                    return weatherRoot.formatIsoDate(ds, true);
                                return weatherRoot.formatDateObj(new Date(day.time * 1000), true);
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
