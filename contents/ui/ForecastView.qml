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
import "js/configUtils.js" as ConfigUtils
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
    readonly property bool showSunEvents:   Plasmoid.configuration.forecastShowSunEvents !== false
    readonly property bool showToday:       Plasmoid.configuration.forecastShowToday !== false
    readonly property string hourlyLayout:  Plasmoid.configuration.forecastHourlyLayout || "cards"

    /** Resolve a condition icon, handling the "custom" theme with per-condition overrides.
     *  Delegates to ConfigUtils.resolveCustomConditionIcon() — single source of truth. */
    function resolveConditionIcon(code, isNight, iconSize) {
        return ConfigUtils.resolveCustomConditionIcon(
            code, isNight, iconSize, forecastRoot.iconsBaseDir,
            forecastRoot.widgetIconTheme,
            Plasmoid.configuration.widgetConditionCustomIcons || "",
            W.weatherCodeToIcon, IconResolver.resolveCondition);
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
                model: {
                    if (!weatherRoot || weatherRoot.dailyData.length === 0) return 0;
                    var total = Math.min(Plasmoid.configuration.forecastDays, weatherRoot.dailyData.length);
                    return forecastRoot.showToday ? total : Math.max(0, total - 1);
                }

                delegate: Column {
                    required property int index
                    readonly property int dataIndex: forecastRoot.showToday ? index : index + 1
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
                                        var di = dataIndex;
                                        if (di === 0)
                                            return i18n("Today");
                                        var ds = weatherRoot.dailyData[di].dateStr;
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
                                        var ds = weatherRoot.dailyData[dataIndex].dateStr || "";
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
                                    weatherRoot.dailyData[dataIndex].code, false,
                                    forecastRoot.iconSz)
                                iconSize: 28
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.rightMargin: 4
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: weatherRoot.weatherCodeToText(weatherRoot.dailyData[dataIndex].code)
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
                                    text: weatherRoot.tempValue(weatherRoot.dailyData[dataIndex].minC)
                                    color: "#42a5f5"
                                    font: weatherRoot.wf(12, false)
                                }
                                Label {
                                    text: "/"
                                    color: Kirigami.Theme.textColor
                                    font: weatherRoot.wf(12, false)
                                }
                                Label {
                                    text: weatherRoot.tempValue(weatherRoot.dailyData[dataIndex].maxC)
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
                        id: hourlyPanel
                        width: parent.width
                        height: forecastRoot.expandedIndex === index ? (forecastRoot.hourlyLayout === "strip" ? 200 : 240) : 0
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

                        // ── STRIP LAYOUT ──────────────────────────────────
                        Flickable {
                            id: stripScrollView
                            anchors.fill: parent
                            anchors.margins: 4
                            visible: weatherRoot && weatherRoot.hourlyData.length > 0 && forecastRoot.hourlyLayout === "strip"
                            clip: true
                            flickableDirection: Flickable.HorizontalFlick
                            contentWidth: stripContent.width
                            contentHeight: height
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                            // Build combined model same as cards (with sun events)
                            property var _hourlyWithSun: {
                                if (!weatherRoot || !weatherRoot.hourlyData.length) return [];
                                function toMins(t) {
                                    if (!t || t === "--") return -1;
                                    var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                }
                                // For today (index 0) filter out past hours; keep 1 hour buffer so current hour stays visible
                                var nowMins = -1;
                                if (index === 0) {
                                    var _now = new Date();
                                    nowMins = _now.getHours() * 60 + _now.getMinutes() - 60;
                                }
                                var source = nowMins >= 0
                                    ? weatherRoot.hourlyData.filter(function(h) { var m = toMins(h.hour); return m < 0 || m >= nowMins; })
                                    : weatherRoot.hourlyData;
                                if (!forecastRoot.showSunEvents)
                                    return source;
                                var rise = toMins(weatherRoot.sunriseTimeText);
                                var set_ = toMins(weatherRoot.sunsetTimeText);
                                // Only insert sun markers if they are still in the future (for today)
                                var riseInserted = rise < 0 || (nowMins >= 0 && rise < nowMins);
                                var setInserted  = set_  < 0 || (nowMins >= 0 && set_  < nowMins);
                                var result = [];
                                source.forEach(function(h) {
                                    var hm = toMins(h.hour);
                                    if (!riseInserted && hm >= 0 && hm > rise) {
                                        result.push({ isSunrise: true, isSunset: false, time: weatherRoot.sunriseTimeText });
                                        riseInserted = true;
                                    }
                                    if (!setInserted && hm >= 0 && hm > set_) {
                                        result.push({ isSunrise: false, isSunset: true, time: weatherRoot.sunsetTimeText });
                                        setInserted = true;
                                    }
                                    result.push(h);
                                });
                                return result;
                            }

                            readonly property int colW: 68
                            readonly property int colSpacing: 0

                            // Column of rows
                            Item {
                                id: stripContent
                                height: stripScrollView.height
                                width: Math.max(stripScrollView.width, stripScrollView._hourlyWithSun.length * (stripScrollView.colW + stripScrollView.colSpacing))

                                // Temps array for trend line (only regular hourly entries)
                                property var _temps: {
                                    var arr = [];
                                    var items = stripScrollView._hourlyWithSun;
                                    for (var i = 0; i < items.length; i++) {
                                        if (!items[i].isSunrise && !items[i].isSunset)
                                            arr.push({ col: i, tempC: items[i].tempC });
                                    }
                                    return arr;
                                }

                                // ── Row 0: time labels ──────────────────────
                                Row {
                                    id: stripTimeRow
                                    x: 0; y: 4
                                    spacing: stripScrollView.colSpacing
                                    Repeater {
                                        model: stripScrollView._hourlyWithSun
                                        delegate: Item {
                                            required property var modelData
                                            width: stripScrollView.colW
                                            height: 18
                                            Label {
                                                anchors.centerIn: parent
                                                text: {
                                                    if (modelData.isSunrise || modelData.isSunset)
                                                        return weatherRoot ? weatherRoot.formatTimeForDisplay(modelData.time) : "--";
                                                    if (!modelData.hour || modelData.hour === "--") return "--";
                                                    var parts = modelData.hour.split(":");
                                                    if (parts.length < 2) return modelData.hour;
                                                    var d = new Date();
                                                    d.setHours(parseInt(parts[0],10), parseInt(parts[1],10), 0, 0);
                                                    return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
                                                }
                                                color: Kirigami.Theme.textColor
                                                font: weatherRoot ? weatherRoot.wf(9, modelData.isSunrise || modelData.isSunset) : Qt.font({})
                                                opacity: (modelData.isSunrise || modelData.isSunset) ? 0.9 : 0.7
                                            }
                                        }
                                    }
                                }

                                // ── Row 1: icons ────────────────────────────
                                Row {
                                    id: stripIconRow
                                    x: 0; y: stripTimeRow.y + stripTimeRow.height + 2
                                    spacing: stripScrollView.colSpacing
                                    Repeater {
                                        model: stripScrollView._hourlyWithSun
                                        delegate: Item {
                                            required property var modelData
                                            width: stripScrollView.colW
                                            height: 48
                                            WeatherIcon {
                                                anchors.centerIn: parent
                                                iconInfo: {
                                                    if (modelData.isSunrise)
                                                        return IconResolver.resolve("sunrise", 32, forecastRoot.iconsBaseDir,
                                                            forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                            (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom") ? "symbolic" : forecastRoot.widgetIconTheme);
                                                    if (modelData.isSunset)
                                                        return IconResolver.resolve("sunset", 32, forecastRoot.iconsBaseDir,
                                                            forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                            (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom") ? "symbolic" : forecastRoot.widgetIconTheme);
                                                    var isNight = false;
                                                    if (modelData.hour && modelData.hour !== "--") {
                                                        var p2 = modelData.hour.split(":");
                                                        if (p2.length >= 2) {
                                                            var hm2 = parseInt(p2[0],10)*60+parseInt(p2[1],10);
                                                            function _sm(t) { if (!t||t==="--") return -1; var p=t.split(":"); return p.length<2?-1:parseInt(p[0],10)*60+parseInt(p[1],10); }
                                                            var rise2=_sm(weatherRoot?weatherRoot.sunriseTimeText:"--");
                                                            var set2=_sm(weatherRoot?weatherRoot.sunsetTimeText:"--");
                                                            if (rise2>=0&&set2>=0) isNight=hm2<rise2||hm2>=set2;
                                                        }
                                                    }
                                                    return forecastRoot.resolveConditionIcon(modelData.code||0, isNight, forecastRoot.iconSz);
                                                }
                                                iconSize: 44
                                                iconColor: Kirigami.Theme.textColor
                                            }
                                        }
                                    }
                                }

                                // ── Trend line canvas ────────────────────────
                                Canvas {
                                    id: trendCanvas
                                    x: 0
                                    y: stripIconRow.y + stripIconRow.height + 2
                                    width: stripContent.width
                                    height: 32
                                    property var temps: stripContent._temps
                                    onTempsChanged: requestPaint()

                                    // Detect light theme by background luminance
                                    readonly property bool darkTheme: {
                                        var bg = Kirigami.Theme.backgroundColor;
                                        return (0.299*bg.r + 0.587*bg.g + 0.114*bg.b) < 0.5;
                                    }
                                    onDarkThemeChanged: requestPaint()

                                    // Map a temperature in °C to a CSS color string
                                    function tempColor(t) {
                                        // Dark theme: bright/pastel stops readable on dark bg
                                        // Light theme: deeper/saturated stops readable on light bg
                                        var stops = darkTheme ? [
                                            { t: -10, r:  50, g: 100, b: 255 },
                                            { t:   0, r:   0, g: 180, b: 255 },
                                            { t:  10, r:  80, g: 220, b: 160 },
                                            { t:  20, r: 220, g: 220, b:  40 },
                                            { t:  30, r: 255, g: 130, b:   0 },
                                            { t:  40, r: 220, g:  30, b:  30 }
                                        ] : [
                                            { t: -10, r:  20, g:  60, b: 200 },
                                            { t:   0, r:   0, g: 120, b: 210 },
                                            { t:  10, r:   0, g: 160, b:  80 },
                                            { t:  20, r: 170, g: 150, b:   0 },
                                            { t:  30, r: 210, g:  80, b:   0 },
                                            { t:  40, r: 180, g:  10, b:  10 }
                                        ];
                                        if (t <= stops[0].t) return "rgba(" + stops[0].r + "," + stops[0].g + "," + stops[0].b + ",1.0)";
                                        if (t >= stops[stops.length-1].t) { var s=stops[stops.length-1]; return "rgba("+s.r+","+s.g+","+s.b+",1.0)"; }
                                        for (var i = 1; i < stops.length; i++) {
                                            if (t <= stops[i].t) {
                                                var frac = (t - stops[i-1].t) / (stops[i].t - stops[i-1].t);
                                                var r = Math.round(stops[i-1].r + frac * (stops[i].r - stops[i-1].r));
                                                var g = Math.round(stops[i-1].g + frac * (stops[i].g - stops[i-1].g));
                                                var b = Math.round(stops[i-1].b + frac * (stops[i].b - stops[i-1].b));
                                                return "rgba(" + r + "," + g + "," + b + ",1.0)";
                                            }
                                        }
                                        return "rgba(0,0,0,0.8)";
                                    }

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        var pts = temps;
                                        if (!pts || pts.length < 2) return;
                                        var minT = pts[0].tempC, maxT = pts[0].tempC;
                                        for (var i = 1; i < pts.length; i++) {
                                            if (pts[i].tempC < minT) minT = pts[i].tempC;
                                            if (pts[i].tempC > maxT) maxT = pts[i].tempC;
                                        }
                                        var range = maxT - minT;
                                        var pad = 5;
                                        var cw = stripScrollView.colW + stripScrollView.colSpacing;
                                        function xOf(col) { return col * cw + cw / 2; }
                                        function yOf(t) {
                                            if (range < 0.01) return height / 2;
                                            return pad + (1 - (t - minT) / range) * (height - pad * 2);
                                        }
                                        // Draw segment by segment, each with its midpoint color
                                        ctx.lineWidth = 2.5;
                                        ctx.lineJoin = "round";
                                        ctx.lineCap = "round";
                                        for (var j = 1; j < pts.length; j++) {
                                            var x0 = xOf(pts[j-1].col), y0 = yOf(pts[j-1].tempC);
                                            var x1 = xOf(pts[j].col),   y1 = yOf(pts[j].tempC);
                                            var midT = (pts[j-1].tempC + pts[j].tempC) / 2;
                                            // Use a short linear gradient along the segment for smooth color transition
                                            var grad = ctx.createLinearGradient(x0, y0, x1, y1);
                                            grad.addColorStop(0, tempColor(pts[j-1].tempC));
                                            grad.addColorStop(1, tempColor(pts[j].tempC));
                                            ctx.strokeStyle = grad;
                                            ctx.beginPath();
                                            ctx.moveTo(x0, y0);
                                            ctx.lineTo(x1, y1);
                                            ctx.stroke();
                                        }
                                        // Dots colored by temp
                                        for (var k = 0; k < pts.length; k++) {
                                            ctx.fillStyle = tempColor(pts[k].tempC);
                                            ctx.beginPath();
                                            ctx.arc(xOf(pts[k].col), yOf(pts[k].tempC), 3, 0, Math.PI * 2);
                                            ctx.fill();
                                        }
                                    }
                                }

                                // ── Row 2: temperature labels ────────────────
                                Row {
                                    id: stripTempRow
                                    x: 0; y: trendCanvas.y + trendCanvas.height + 2
                                    spacing: stripScrollView.colSpacing
                                    Repeater {
                                        model: stripScrollView._hourlyWithSun
                                        delegate: Item {
                                            required property var modelData
                                            width: stripScrollView.colW
                                            height: 18
                                            Label {
                                                anchors.centerIn: parent
                                                text: (modelData.isSunrise || modelData.isSunset) ? i18n(modelData.isSunrise ? "Sunrise" : "Sunset")
                                                      : (weatherRoot ? weatherRoot.tempValue(modelData.tempC) : "--")
                                                color: Kirigami.Theme.textColor
                                                font: weatherRoot ? weatherRoot.wf(10, !(modelData.isSunrise || modelData.isSunset)) : Qt.font({})
                                                opacity: (modelData.isSunrise || modelData.isSunset) ? 0.75 : 1.0
                                            }
                                        }
                                    }
                                }

                                // ── Row 3: precipitation ─────────────────────
                                Row {
                                    id: stripPrecipRow
                                    x: 0; y: stripTempRow.y + stripTempRow.height + 2
                                    spacing: stripScrollView.colSpacing
                                    Repeater {
                                        model: stripScrollView._hourlyWithSun
                                        delegate: RowLayout {
                                            required property var modelData
                                            readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                            width: stripScrollView.colW
                                            height: 18
                                            spacing: 1
                                            Item { Layout.fillWidth: true }
                                            WeatherIcon {
                                                visible: !parent._isSun
                                                iconInfo: IconResolver.resolve("umbrella", 16, forecastRoot.iconsBaseDir,
                                                    forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                    (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom") ? "symbolic" : forecastRoot.widgetIconTheme)
                                                iconSize: 14
                                                iconColor: "#7ec8e3"
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Label {
                                                visible: !parent._isSun
                                                text: {
                                                    if (parent._isSun) return "";
                                                    var pp = modelData.precipProb;
                                                    if (pp !== undefined && !isNaN(pp)) return Math.round(pp) + "%";
                                                    var h = modelData.humidity;
                                                    return (!isNaN(h) && h !== undefined) ? Math.round(h) + "%" : "--";
                                                }
                                                color: Kirigami.Theme.textColor
                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                opacity: 0.7
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Item { Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }
                        }

                        // Wheel scroll for strip layout — redirect vertical wheel → horizontal flick
                        MouseArea {
                            anchors.fill: stripScrollView
                            visible: stripScrollView.visible
                            acceptedButtons: Qt.NoButton
                            onWheel: function(wheel) {
                                var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                                var step = stripScrollView.colW * 2 * (delta > 0 ? -1 : 1);
                                stripScrollView.contentX = Math.max(0,
                                    Math.min(stripScrollView.contentWidth - stripScrollView.width,
                                             stripScrollView.contentX + step));
                                wheel.accepted = true;
                            }
                        }

                        // ── CARDS LAYOUT ───────────────────────────────────
                        ScrollView {
                            id: hourlyScrollView
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: weatherRoot && weatherRoot.hourlyData.length > 0 && forecastRoot.hourlyLayout === "cards"
                            clip: true
                            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                            ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                            // Auto-scroll to current hour for "Today" (index === 0)
                            Timer {
                                id: scrollTimer
                                interval: 150
                                onTriggered: {
                                    if (index !== 0 || !weatherRoot.hourlyData.length) return;
                                    var now = new Date();
                                    var currentTotalMins = now.getHours() * 60 + now.getMinutes();
                                    // Find the closest hour in the data
                                    var closestIdx = 0;
                                    var minDiff = 86400;
                                    for (var i = 0; i < weatherRoot.hourlyData.length; i++) {
                                        var h = weatherRoot.hourlyData[i].hour;
                                        if (!h) continue;
                                        var parts = h.split(":");
                                        if (parts.length < 2) continue;
                                        var hm = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                                        var diff = Math.abs(hm - currentTotalMins);
                                        if (diff < minDiff) {
                                            minDiff = diff;
                                            closestIdx = i;
                                        }
                                    }
                                    // Account for sunrise/sunset cards inserted before this index
                                    if (forecastRoot.showSunEvents && weatherRoot.sunriseTimeText && weatherRoot.sunsetTimeText) {
                                        function toMins(t) {
                                            if (!t || t === "--") return -1;
                                            var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                        }
                                        var rise = toMins(weatherRoot.sunriseTimeText);
                                        var set_ = toMins(weatherRoot.sunsetTimeText);
                                        var targetMins = closestIdx < weatherRoot.hourlyData.length ? toMins(weatherRoot.hourlyData[closestIdx].hour) : -1;
                                        if (rise >= 0 && targetMins >= 0 && rise < targetMins) closestIdx++;
                                        if (set_ >= 0 && targetMins >= 0 && set_ < targetMins) closestIdx++;
                                    }
                                    // Calculate scroll position using actual card widths
                                    var hourlyWidth = 100;
                                    var sunWidth = 70;
                                    var spacing = 6;
                                    var scrollPos = 0;
                                    // Count cards before closestIdx (accounting for sun cards)
                                    if (forecastRoot.showSunEvents && weatherRoot.sunriseTimeText && weatherRoot.sunsetTimeText) {
                                        function toMins2(t) {
                                            if (!t || t === "--") return -1;
                                            var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                        }
                                        var rise2 = toMins2(weatherRoot.sunriseTimeText);
                                        var set2 = toMins2(weatherRoot.sunsetTimeText);
                                        for (var j = 0; j < closestIdx; j++) {
                                            var hm2 = toMins2(weatherRoot.hourlyData[j].hour);
                                            // Check if a sun card appears before this hour
                                            if (rise2 >= 0 && hm2 > rise2) { scrollPos += sunWidth + spacing; rise2 = -1; }
                                            if (set2 >= 0 && hm2 > set2) { scrollPos += sunWidth + spacing; set2 = -1; }
                                            scrollPos += hourlyWidth + spacing;
                                        }
                                    } else {
                                        scrollPos = closestIdx * (hourlyWidth + spacing);
                                    }
                                    var bar = hourlyScrollView.ScrollBar.horizontal;
                                    if (!bar) return;
                                    var contentW = hourlyRow.implicitWidth || hourlyRow.width || (weatherRoot.hourlyData.length * (hourlyWidth + spacing));
                                    var viewW = hourlyScrollView.width;
                                    if (contentW > viewW) {
                                        var maxPos = Math.max(0, contentW - viewW);
                                        var targetPos = Math.min(scrollPos, maxPos);
                                        bar.position = targetPos / contentW;
                                    }
                                }
                            }
                            Connections {
                                target: weatherRoot
                                function onHourlyDataChanged() {
                                    if (index !== 0 || !weatherRoot.hourlyData.length) return;
                                    scrollTimer.start();
                                }
                            }

                            Row {
                                id: hourlyRow
                                spacing: 6
                                height: parent.height

                                // Build combined model: hourly entries + sunrise/sunset marker cards
                                // inserted between the hour that precedes each event.
                                property var _hourlyWithSun: {
                                    if (!weatherRoot || !weatherRoot.hourlyData.length) return [];
                                    function toMins(t) {
                                        if (!t || t === "--") return -1;
                                        var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                    }
                                    // For today (index 0) filter out past hours; keep 1 hour buffer
                                    var nowMins = -1;
                                    if (index === 0) {
                                        var _now = new Date();
                                        nowMins = _now.getHours() * 60 + _now.getMinutes() - 60;
                                    }
                                    var source = nowMins >= 0
                                        ? weatherRoot.hourlyData.filter(function(h) { var m = toMins(h.hour); return m < 0 || m >= nowMins; })
                                        : weatherRoot.hourlyData;
                                    if (!forecastRoot.showSunEvents)
                                        return source;
                                    var rise = toMins(weatherRoot.sunriseTimeText);
                                    var set_ = toMins(weatherRoot.sunsetTimeText);
                                    var riseInserted = rise < 0 || (nowMins >= 0 && rise < nowMins);
                                    var setInserted  = set_  < 0 || (nowMins >= 0 && set_  < nowMins);
                                    var result = [];
                                    source.forEach(function(h) {
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

                        // Overlay: translate vertical mouse-wheel → horizontal scroll
                        MouseArea {
                            anchors.fill: hourlyScrollView
                            visible: hourlyScrollView.visible
                            acceptedButtons: Qt.NoButton
                            onWheel: function(wheel) {
                                var bar = hourlyScrollView.ScrollBar.horizontal
                                if (!bar) return
                                var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                                var step = 0.15 * (delta > 0 ? -1 : 1)
                                bar.position = Math.max(0, Math.min(1.0 - bar.size, bar.position + step))
                                wheel.accepted = true
                            }
                        }
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
