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
 * DetailsView.qml — Dynamic "Details" tab content for the popup
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

import "js/weather.js" as W
import "js/moonphase.js" as Moon
import "js/moonpath.js" as MoonPath
import "js/sunpath.js" as SunPath
import "js/suncalc.js" as SC
import "js/iconResolver.js" as IconResolver
import "js/airQuality.js" as AQI
import "js/pollen.js" as Pollen
import "js/spaceWeather.js" as SW
import "components"

Item {
    id: root
    property var weatherRoot

    // Helper: true if weatherRoot exists and has a valid (non-NaN) temperature
    readonly property bool hasData: weatherRoot && !isNaN(weatherRoot.temperatureC)

    // Implicit height based on content (ScrollView's contentHeight) or empty label
    implicitHeight: Math.max(hasData ? detailsScroll.contentHeight : (emptyLabel.implicitHeight + 40), 50)

    // Font for weather icons
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    // ── Icon size from configuration ──────────────────────────────────────
    readonly property int iconSize: Plasmoid.configuration.widgetIconSize || 16
    // Smaller glyph size for decorative indicators inside arc card info rows
    // (sunrise ↑↓ and moonrise ↑↓ above the time label). Proportional to
    // iconSize but capped so they fit inside the 44 px bottom row.
    readonly property int glyphIconSize: Math.max(12, Math.round(iconSize * 0.55))

    // ── Theme helper — true when KDE is using a dark colour scheme ────────
    readonly property bool isDark: Kirigami.Theme.textColor.r > 0.5

    // ── Colour palette — adapts to dark / light theme ─────────────────────
    readonly property color cardBg: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
    readonly property color cardBorder: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)
    readonly property color valueColor: Kirigami.Theme.textColor

    // Accent colours — shift toward darker hues on light themes for contrast
    readonly property color accentBlue: isDark ? "#5ea8ff" : "#1a6fcc"
    readonly property color accentWarm: isDark ? "#ffb347" : "#b86000"
    readonly property color accentTeal: isDark ? "#4ecdc4" : "#007070"
    readonly property color accentGold: isDark ? "#ffcf63" : "#9c7400"
    readonly property color accentOrange: isDark ? "#ff8c52" : "#c04000"
    readonly property color accentViolet: isDark ? "#c4b4ff" : "#5030a0"

    // Pick the text-safe variant of a band/scale color on light themes.
    // band objects from airQuality.js and pollen.js carry both .color (vivid)
    // and .textColor (high-contrast dark variant).
    function bandTextColor(band) {
        if (!band) return Kirigami.Theme.textColor;
        return isDark ? band.color : band.textColor;
    }

    // ── icon theme ────────────────────────────────────────────────────────
    // Normalise legacy "wi-font" to "symbolic"; "kde" is valid.
    readonly property string iconTheme: {
        var t = Plasmoid.configuration.widgetIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property int iconSz: iconSize
    readonly property bool isList: (Plasmoid.configuration.widgetDetailsLayout || "cards2") === "list"
    readonly property string sunTimesMode: Plasmoid.configuration.widgetSunTimesMode || "both"
    readonly property string moonMode: Plasmoid.configuration.widgetMoonMode || "full"

    /** Returns "sunrise" or "sunset" depending on which is next (for upcoming mode) */
    function upcomingSunEvent() {
        if (!weatherRoot)
            return "sunrise";
        var utcOff = weatherRoot.locationUtcOffsetMins || 0;
        var nowM = SunPath.nowMinsAt(utcOff);
        var riseM = SunPath.parseMins(weatherRoot.sunriseTimeText);
        var setM = SunPath.parseMins(weatherRoot.sunsetTimeText);
        if (riseM >= 0 && nowM < riseM)
            return "sunrise";
        if (setM >= 0 && nowM < setM)
            return "sunset";
        return "sunrise";
    }

    /** Returns "moonrise" or "moonset" depending on which is next (for upcoming mode) */
    function upcomingMoonEvent(riseText, setText) {
        var utcOff = (weatherRoot ? weatherRoot.locationUtcOffsetMins : 0) || 0;
        var nowM = SunPath.nowMinsAt(utcOff);
        var riseM = SunPath.parseMins(riseText);
        var setM = SunPath.parseMins(setText);
        if (riseM >= 0 && nowM < riseM)
            return "moonrise";
        if (setM >= 0 && nowM < setM)
            return "moonset";
        return "moonrise";
    }

    /** Whether to show sunrise items in sun collapsed/list row */
    function showSunrise() {
        var m = sunTimesMode;
        if (m === "both")
            return true;
        if (m === "sunrise")
            return true;
        if (m === "sunset")
            return false;
        return upcomingSunEvent() === "sunrise"; // upcoming
    }

    /** Whether to show sunset items in sun collapsed/list row */
    function showSunset() {
        var m = sunTimesMode;
        if (m === "both")
            return true;
        if (m === "sunrise")
            return false;
        if (m === "sunset")
            return true;
        return upcomingSunEvent() === "sunset"; // upcoming
    }

    /** Whether to show moonrise items in moon collapsed/list row */
    function showMoonrise(riseText, setText) {
        var m = moonMode;
        if (m === "full" || m === "times" || m === "moonrise")
            return true;
        if (m === "moonset" || m === "phase")
            return false;
        // "upcoming" and "upcoming-times"
        return upcomingMoonEvent(riseText, setText) === "moonrise";
    }

    /** Whether to show moonset items in moon collapsed/list row */
    function showMoonset(riseText, setText) {
        var m = moonMode;
        if (m === "full" || m === "times" || m === "moonset")
            return true;
        if (m === "moonrise" || m === "phase")
            return false;
        // "upcoming" and "upcoming-times"
        return upcomingMoonEvent(riseText, setText) === "moonset";
    }

    /** Whether to show the moon phase name in collapsed/list row */
    function showMoonPhase() {
        var m = moonMode;
        return m !== "times" && m !== "moonrise" && m !== "moonset" && m !== "upcoming-times";
    }

    // Collapse state for the two arc cards.
    property bool _sunExpanded: true
    property bool _moonExpanded: true
    property bool _alertsExpanded: false
    property bool _aqiExpanded: false
    property bool _pollenExpanded: false
    property bool _swExpanded: false
    property int _currentAlertIndex: 0


    readonly property int regularCardHeight: Plasmoid.configuration.widgetCardsHeightAuto ? 30 : (Plasmoid.configuration.widgetCardsHeight || 30)

    // ── Resolved icons base URL ───────────────────────────────────────────
    readonly property string iconsBaseDir: Qt.resolvedUrl("../icons/")

    // ── Icon resolution via IconResolver ──────────────────────────────────
    /** Returns a saved custom icon name for the given item, or "" */
    function getDetailsCustomIcon(itemId) {
        var raw = Plasmoid.configuration.widgetDetailsCustomIcons || "";
        if (raw.length === 0)
            return "";
        var m = {};
        raw.split(";").forEach(function (pair) {
            var kv = pair.split("=");
            if (kv.length === 2 && kv[0].trim().length > 0)
                m[kv[0].trim()] = kv[1].trim();
        });
        return (itemId in m) ? m[itemId] : "";
    }
    /** Resolves an icon for the given detail card ID */
    function resolveIcon(itemId) {
        if (root.iconTheme === "kde") {
            var custom = getDetailsCustomIcon(itemId);
            if (custom.length > 0)
                return {
                    type: "kde",
                    source: custom,
                    svgFallback: "",
                    isMask: false
                };
        }
        return IconResolver.resolve(itemId, root.iconSize, root.iconsBaseDir, root.iconTheme);
    }
    /** Resolves the current moon phase icon */
    function resolveMoonPhaseIcon() {
        var stem = Moon.moonPhaseSvgStem(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
        // Always use bundled SVG for moon phase (flat-color for KDE theme)
        var theme = (root.iconTheme === "kde") ? "flat-color" : root.iconTheme;
        return IconResolver.resolveMoonPhase(stem, root.iconSize, root.iconsBaseDir, theme);
    }
    function accentFor(id) {
        return ({
                feelslike: root.accentWarm,
                humidity: root.accentBlue,
                pressure: root.accentTeal,
                wind: root.accentBlue,
                suntimes: root.accentGold,
                dewpoint: root.accentTeal,
                visibility: Kirigami.Theme.textColor,
                moonphase: root.accentViolet,
                condition: Kirigami.Theme.textColor,
                preciprate: root.accentBlue,
                precipsum: root.accentBlue,
                uvindex: root.accentOrange,
                airquality: root.accentTeal,
                pollen: root.accentGold,
                spaceweather: root.accentViolet,
                alerts: root.accentOrange,
                snowcover: root.accentBlue
            })[id] || root.accentBlue;
    }

    // When the icon theme is symbolic, icons should render monochrome (textColor).
    // Accent colours are only applied for non-mask themes (flat-color, 3d-oxygen, kde).
    function iconColorFor(c) {
        return (root.iconTheme === "symbolic") ? Kirigami.Theme.textColor : c;
    }
    function labelFor(id) {
        return ({
                feelslike: i18n("Feels Like"),
                humidity: i18n("Humidity"),
                pressure: i18n("Pressure"),
                wind: i18n("Wind"),
                suntimes: i18n("Sunrise/Sunset"),
                dewpoint: i18n("Dew Point"),
                visibility: i18n("Visibility"),
                moonphase: i18n("Moon"),
                condition: i18n("Condition"),
                preciprate: i18n("Precipitation"),
                precipsum: i18n("Precipitation Sum"),
                uvindex: i18n("UV Index"),
                airquality: i18n("Air Quality"),
                pollen: i18n("Pollen"),
                spaceweather: i18n("Space Weather"),
                alerts: i18n("Alerts"),
                snowcover: i18n("Snow Cover")
            })[id] || id;
    }
    function dataValue(id) {
        if (!weatherRoot)
            return "--";
        switch (id) {
        case "feelslike":
            return weatherRoot.tempValue(weatherRoot.apparentC);
        case "humidity":
            return isNaN(weatherRoot.humidityPercent) ? "--" : Math.round(weatherRoot.humidityPercent) + "%";
        case "pressure":
            return weatherRoot.pressureValue(weatherRoot.pressureHpa);
        case "dewpoint":
            return weatherRoot.tempValue(weatherRoot.dewPointC);
        case "visibility":
            return isNaN(weatherRoot.visibilityKm) ? "--" : weatherRoot.visibilityKm.toFixed(1) + " km";
        case "condition":
            return weatherRoot.weatherCodeToText(weatherRoot.weatherCode, weatherRoot.isNightTime());
        case "preciprate":
            return weatherRoot.precipValue(weatherRoot.precipMmh);
        case "precipsum":
            return weatherRoot.precipSumText(weatherRoot.precipSumMm);
        case "uvindex":
            return weatherRoot.uvIndexText(weatherRoot.uvIndex);
        case "airquality":
            return weatherRoot.airQualityText();
        case "pollen":
            return weatherRoot.pollenText();
        case "spaceweather":
            return weatherRoot.spaceWeatherText();
        case "alerts":
            return weatherRoot.alertsText();
        case "snowcover":
            return weatherRoot.snowDepthText(weatherRoot.snowDepthCm);
        case "wind":
            // Wind is handled specially in the card
            return "";
        case "suntimes":
            // Handled in expanded card
            return "";
        case "moonphase":
            // Handled in expanded card
            return "";
        default:
            return "";
        }
    }

    // List of detail IDs in configured order
    property var detailIds: (Plasmoid.configuration.widgetDetailsOrder || "feelslike;humidity;pressure;wind;suntimes;dewpoint;visibility;moonphase").split(";").map(s => s.trim()).filter(s => s.length > 0)

    // Per-item icon visibility map (parsed from "id=1;id=0;…" config string)
    readonly property var iconShowMap: {
        var map = {};
        var raw = Plasmoid.configuration.widgetDetailsItemIcons || "";
        raw.split(";").forEach(function (pair) {
            var kv = pair.split("=");
            if (kv.length === 2)
                map[kv[0].trim()] = (kv[1].trim() === "1");
        });
        return map;
    }
    function showIconFor(itemId) {
        return (itemId in iconShowMap) ? iconShowMap[itemId] : true;
    }

    // Build rows: each row is an array of 1 or 2 IDs.
    function buildRows() {
        var rows = [];
        var i = 0;
        if (root.isList) {
            while (i < detailIds.length) {
                rows.push([detailIds[i]]);
                i++;
            }
        } else {
            while (i < detailIds.length) {
                if (i + 1 < detailIds.length) {
                    rows.push([detailIds[i], detailIds[i + 1]]);
                    i += 2;
                } else {
                    rows.push([detailIds[i]]);
                    i++;
                }
            }
        }
        return rows;
    }

    // ── empty state ───────────────────────────────────────────────────────
    Label {
        id: emptyLabel
        anchors.centerIn: parent
        visible: !root.hasData
        text: (weatherRoot && weatherRoot.loading) ? i18n("Loading details…") : i18n("No details data")
        color: Kirigami.Theme.textColor
        opacity: 0.4
        font: weatherRoot ? weatherRoot.wf(12, false) : Qt.font({})
    }

    // ── UI when data exists ───────────────────────────────────────────────
    ScrollView {
        id: detailsScroll
        anchors.fill: parent
        clip: true
        contentWidth: Math.max(availableWidth, 560)
        ScrollBar.horizontal.policy: ScrollBar.AsNeeded
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        visible: root.hasData

        Column {
            id: detailsColumn
            width: Math.max(detailsScroll.availableWidth, 560)
            spacing: root.isList ? 0 : 8
            bottomPadding: 4

            Repeater {
                model: root.buildRows()

                delegate: RowLayout {
                    id: rowItem
                    required property var modelData   // array of 1 or 2 IDs
                    width: parent.width
                    spacing: root.isList ? 0 : 8

                    Repeater {
                        model: rowItem.modelData

                        delegate: Rectangle {
                            id: card
                            required property string modelData   // the detail ID

                            // Card height
                            readonly property bool isExpandedCard: card.modelData === "suntimes" || card.modelData === "moonphase" || (card.modelData === "alerts" && weatherRoot && weatherRoot.weatherAlerts && weatherRoot.weatherAlerts.length > 1) || card.modelData === "airquality" || card.modelData === "pollen" || card.modelData === "spaceweather"
                            // suntimes and moonphase: height scales with card width
                            // so the arc grows when the widget is stretched.
                            readonly property int autoHeight: {
                                var arcLikeHeight = Plasmoid.configuration.widgetExpandedCardsHeightAuto
                                    ? Math.max(165, Math.round(card.width * 0.55))
                                    : Plasmoid.configuration.widgetExpandedCardsHeight;
                                if (card.modelData === "alerts") {
                                    var n = weatherRoot ? (weatherRoot.weatherAlerts || []).length : 0;
                                    if (n <= 1) return 30;
                                    return arcLikeHeight;
                                }
                                if (card.modelData === "airquality")
                                    return arcLikeHeight;
                                if (card.modelData === "pollen") {
                                    return arcLikeHeight;
                                }
                                if (card.modelData === "spaceweather")
                                    return arcLikeHeight;
                                if (card.modelData === "suntimes" || card.modelData === "moonphase")
                                    return arcLikeHeight;
                                if (isExpandedCard)
                                    return 80;
                                return 30;  // ← adjust this value to change regular card height
                            }
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            // List mode: compact fixed height; Cards mode: auto or manual
                            // Arc cards animate between expanded (arc view) and
                            // collapsed (compact header-only row, ~44 px).
                            readonly property bool _isArcExpanded: {
                                if (!card.isExpandedCard)
                                    return true;
                                if (card.modelData === "suntimes")
                                    return root._sunExpanded;
                                if (card.modelData === "moonphase")
                                    return root._moonExpanded;
                                if (card.modelData === "alerts")
                                    return root._alertsExpanded;
                                if (card.modelData === "airquality")
                                    return root._aqiExpanded;
                                if (card.modelData === "pollen")
                                    return root._pollenExpanded;
                                if (card.modelData === "spaceweather")
                                    return root._swExpanded;
                                return true;
                            }
                            Layout.preferredHeight: root.isList ? (card.isExpandedCard ? 44 : 38) : (card.isExpandedCard ? (card._isArcExpanded ? autoHeight : root.regularCardHeight) : (Plasmoid.configuration.widgetCardsHeightAuto ? autoHeight : Plasmoid.configuration.widgetCardsHeight))
                            Behavior on Layout.preferredHeight {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.InOutQuad
                                }
                            }
                            radius: root.isList ? 0 : 10
                            // List mode: no card background — just a flat row
                            color: root.isList ? "transparent" : root.cardBg
                            border.color: root.isList ? "transparent" : root.cardBorder
                            border.width: root.isList ? 0 : 1

                            // ── Separator line shown in list mode ─────────────────
                            Rectangle {
                                visible: root.isList
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                height: 1
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
                            }

                            // Standard item: single row
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8
                                visible: !card.isExpandedCard && card.modelData !== "wind" && !(card.modelData === "alerts" && weatherRoot && weatherRoot.weatherAlerts && weatherRoot.weatherAlerts.length > 0) && card.modelData !== "airquality" && card.modelData !== "pollen" && card.modelData !== "spaceweather"

                                WeatherIcon {
                                    iconInfo: root.showIconFor(card.modelData) ? root.resolveIcon(card.modelData) : null
                                    iconSize: root.iconSize
                                    iconColor: root.iconColorFor(root.accentFor(card.modelData))
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                // label (dim)
                                Label {
                                    text: root.labelFor(card.modelData) + ":"
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.55
                                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                // scalar value
                                Label {
                                    visible: card.modelData !== "wind"
                                    text: root.dataValue(card.modelData)
                                    color: root.valueColor
                                    font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                        bold: true
                                    })
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            // Wind special (icon + speed + arrow)
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8
                                visible: card.modelData === "wind"

                                WeatherIcon {
                                    iconInfo: root.showIconFor("wind") ? root.resolveIcon("wind") : null
                                    iconSize: root.iconSize
                                    iconColor: root.iconColorFor(root.accentFor("wind"))
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Label {
                                    text: root.labelFor("wind") + ":"
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.55
                                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                // Speed and arrow
                                RowLayout {
                                    visible: card.modelData === "wind"
                                    spacing: 6
                                    Label {
                                        text: weatherRoot ? weatherRoot.windValue(weatherRoot.windKmh) : "--"
                                        color: root.valueColor
                                        font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                            bold: true
                                        })
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item {
                                        visible: weatherRoot && !isNaN(weatherRoot.windDirection)
                                        implicitWidth: root.iconSize
                                        implicitHeight: root.iconSize
                                        Layout.alignment: Qt.AlignVCenter
                                        Text {
                                            anchors.centerIn: parent
                                            text: W.windDirectionGlyph(weatherRoot.windDirection)
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: root.iconSize
                                            color: Kirigami.Theme.textColor
                                        }
                                    }
                                }
                            } // RowLayout (standard)

                            // ── Air Quality display ──────────────────────────────────
                            Item {
                                id: aqiCard
                                anchors.fill: parent
                                clip: true
                                visible: card.modelData === "airquality"

                                readonly property real aqiValue: weatherRoot ? weatherRoot.airQualityIndex : NaN
                                readonly property var  aqiBand:  !isNaN(aqiValue) ? AQI.infoForIndex(aqiValue) : null
                                readonly property real aqhiValue: !isNaN(aqiValue) ? AQI.aqhiFromAqi(aqiValue) : NaN

                                // Helper: build the 6 pollutant row data objects
                                readonly property var pollutants: {
                                    if (!weatherRoot) return [];
                                    var r = weatherRoot;
                                    return [
                                        { key: "pm2_5", value: r.aqiPm2_5, si: AQI.subIndex("pm2_5", r.aqiPm2_5) },
                                        { key: "pm10",  value: r.aqiPm10,  si: AQI.subIndex("pm10",  r.aqiPm10)  },
                                        { key: "no2",   value: r.aqiNo2,   si: AQI.subIndex("no2",   r.aqiNo2)   },
                                        { key: "o3",    value: r.aqiO3,    si: AQI.subIndex("o3",    r.aqiO3)    },
                                        { key: "so2",   value: r.aqiSo2,   si: AQI.subIndex("so2",   r.aqiSo2)   },
                                        { key: "co",    value: r.aqiCo,    si: AQI.subIndex("co",    r.aqiCo)    }
                                    ];
                                }

                                // ── Collapsed header row ──────────────────────────────
                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 10
                                        rightMargin: 10
                                    }
                                    height: root.regularCardHeight
                                    spacing: 8
                                    visible: !card._isArcExpanded

                                    WeatherIcon {
                                        iconInfo: root.showIconFor("airquality") ? root.resolveIcon("airquality") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentFor("airquality"))
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: root.labelFor("airquality") + ":"
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.55
                                        font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item { Layout.fillWidth: true }

                                    // Colored band square
                                    Rectangle {
                                        visible: aqiCard.aqiBand !== null
                                        width: 10; height: 10
                                        radius: 2
                                        color: aqiCard.aqiBand ? root.bandTextColor(aqiCard.aqiBand) : "transparent"
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: isNaN(aqiCard.aqiValue) ? "--"
                                            : i18n("AQI") + ": " + Math.round(aqiCard.aqiValue) + " | " + i18n("AQHI") + ": " + Math.round(aqiCard.aqhiValue)
                                        color: aqiCard.aqiBand ? root.bandTextColor(aqiCard.aqiBand) : root.valueColor
                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // Expand chevron
                                    Item {
                                        visible: !root.isList
                                        implicitWidth: 14; implicitHeight: 14
                                        Layout.alignment: Qt.AlignVCenter
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: "arrow-down"
                                            opacity: 0.45
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root._aqiExpanded = true
                                        }
                                    }
                                }

                                // ── Expanded view ─────────────────────────────────────
                                ColumnLayout {
                                    visible: card._isArcExpanded
                                    anchors {
                                        fill: parent
                                        leftMargin: 10
                                        rightMargin: 10
                                        topMargin: 6
                                        bottomMargin: 6
                                    }
                                    spacing: 4

                                    // Header row with collapse button
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("airquality") ? root.resolveIcon("airquality") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("airquality"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("airquality") + ":"
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item { Layout.fillWidth: true }
                                        // Collapse chevron
                                        Item {
                                            implicitWidth: 14; implicitHeight: 14
                                            Layout.alignment: Qt.AlignVCenter
                                            Kirigami.Icon {
                                                anchors.fill: parent
                                                source: "arrow-up"
                                                opacity: 0.45
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root._aqiExpanded = false
                                            }
                                        }
                                    }

                                    ScrollView {
                                        id: aqiScrollView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                        ColumnLayout {
                                            width: aqiScrollView.availableWidth
                                            spacing: 4

                                    // Pollutant rows
                                    Repeater {
                                        model: aqiCard.pollutants
                                        delegate: Item {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 48

                                            readonly property var band: !isNaN(modelData.si) ? AQI.bandForSubIndex(modelData.si) : null
                                            readonly property real pct: !isNaN(modelData.si) ? AQI.scalePercent(modelData.si, 150) : 0

                                            ColumnLayout {
                                                anchors.fill: parent
                                                spacing: 2

                                                // Top row: name | label badge | value
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    // Pollutant name
                                                    Label {
                                                        text: {
                                                            switch (modelData.key) {
                                                                case "pm2_5": return i18n("Particulate Matter (PM2.5)");
                                                                case "pm10":  return i18n("Particulate Matter (PM10)");
                                                                case "no2":   return i18n("Nitrogen Dioxide (NO₂)");
                                                                case "o3":    return i18n("Ozone (O₃)");
                                                                case "so2":   return i18n("Sulfur Dioxide (SO₂)");
                                                                case "co":    return i18n("Carbon Monoxide (CO)");
                                                                default:      return modelData.key;
                                                            }
                                                        }
                                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                                        color: Kirigami.Theme.textColor
                                                        Layout.minimumWidth: 46
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    // Band label
                                                    Label {
                                                        visible: band !== null && !isNaN(modelData.si)
                                                        text: band ? i18n(band.shortLabel) : ""
                                                        color: root.bandTextColor(band)
                                                        font: weatherRoot ? weatherRoot.wf(9, true) : Qt.font({ bold: true })
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    PlasmaCore.ToolTipArea {
                                                        visible: band !== null && !isNaN(modelData.si)
                                                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                                                        Layout.alignment: Qt.AlignVCenter
                                                        active: true
                                                        mainItem: Label {
                                                            text: band ? i18n(band.description) : ""
                                                            wrapMode: Text.Wrap
                                                            width: 260
                                                        }
                                                        Kirigami.Icon {
                                                            anchors.centerIn: parent
                                                            width: 16; height: 16
                                                            source: "help-about"
                                                            opacity: 0.6
                                                        }
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    // Concentration value
                                                    Label {
                                                        text: isNaN(modelData.value) ? "--"
                                                            : modelData.value.toFixed(1) + " " + AQI.unitFor(modelData.key)
                                                        font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                        color: Kirigami.Theme.textColor
                                                        opacity: 0.8
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                }

                                                // Slider bar
                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 22

                                                    // Track background — smooth gradient across all bands
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        height: 8
                                                        radius: 4
                                                        opacity: 0.35
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop { position: 0.0;    color: "#4CAF50" }
                                                            GradientStop { position: 0.167;  color: "#CDDC39" }
                                                            GradientStop { position: 0.333;  color: "#FF9800" }
                                                            GradientStop { position: 0.5;    color: "#F44336" }
                                                            GradientStop { position: 0.75;   color: "#9C27B0" }
                                                            GradientStop { position: 1.0;    color: "#7B1FA2" }
                                                        }
                                                    }

                                                    // Filled progress with gradient
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width * pct / 100
                                                        height: 8
                                                        radius: 4
                                                        opacity: 0.85
                                                        visible: !isNaN(modelData.si)
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop { position: 0.0; color: "#4CAF50" }
                                                            GradientStop { position: Math.min(1.0, 25 / Math.max(1, modelData.si)); color: "#CDDC39" }
                                                            GradientStop { position: Math.min(1.0, 50 / Math.max(1, modelData.si)); color: "#FF9800" }
                                                            GradientStop { position: Math.min(1.0, 75 / Math.max(1, modelData.si)); color: "#F44336" }
                                                            GradientStop { position: Math.min(1.0, 100 / Math.max(1, modelData.si)); color: "#9C27B0" }
                                                            GradientStop { position: 1.0; color: band ? band.color : "#4CAF50" }
                                                        }
                                                    }

                                                    // Thumb circle with index value
                                                    Rectangle {
                                                        x: Math.min(parent.width - width, Math.max(0, parent.width * pct / 100 - width / 2))
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 22; height: 22
                                                        radius: 11
                                                        color: band ? band.color : "#4CAF50"
                                                        border.color: Kirigami.Theme.textColor
                                                        border.width: 1
                                                        visible: !isNaN(modelData.si)

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Math.round(modelData.si)
                                                            color: "white"
                                                            font.pixelSize: 11
                                                            font.bold: true
                                                            horizontalAlignment: Text.AlignHCenter
                                                            verticalAlignment: Text.AlignVCenter
                                                            style: root.isDark ? Text.Outline : Text.Normal
                                                            styleColor: Qt.rgba(0, 0, 0, 0.55)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    } // Repeater (pollutants)
                                        } // ColumnLayout inside ScrollView
                                    } // ScrollView
                                } // ColumnLayout expanded
                            } // Item (aqiCard)

                            // ── Pollen display ──────────────────────────────────────
                            Item {
                                id: pollenCard
                                anchors.fill: parent
                                clip: true
                                visible: card.modelData === "pollen"

                                // Filter to only pollen entries that have real values
                                readonly property var entries: {
                                    if (!weatherRoot || !weatherRoot.pollenData) return [];
                                    return weatherRoot.pollenData.filter(function(p) { return !isNaN(p.value); });
                                }

                                // Dominant pollen (highest value)
                                readonly property var dominant: {
                                    var best = null;
                                    for (var i = 0; i < entries.length; i++) {
                                        if (!best || entries[i].value > best.value) best = entries[i];
                                    }
                                    return best;
                                }

                                function pollenName(key) {
                                    switch (key) {
                                        case "alder":   return i18n("Alder");
                                        case "birch":   return i18n("Birch");
                                        case "grass":   return i18n("Grass");
                                        case "mugwort": return i18n("Mugwort");
                                        case "olive":   return i18n("Olive");
                                        case "ragweed": return i18n("Ragweed");
                                        default:        return key;
                                    }
                                }

                                // ── Collapsed header row ──────────────────────────────
                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 10
                                        rightMargin: 10
                                    }
                                    height: root.regularCardHeight
                                    spacing: 8
                                    visible: !card._isArcExpanded

                                    WeatherIcon {
                                        iconInfo: root.showIconFor("pollen") ? root.resolveIcon("pollen") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentFor("pollen"))
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: root.labelFor("pollen") + ":"
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.55
                                        font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item { Layout.fillWidth: true }
                                    

                                    // Dominant pollen info
                                    Rectangle {
                                        visible: pollenCard.dominant !== null
                                        width: 10; height: 10
                                        radius: 2
                                        color: pollenCard.dominant ? Pollen.colorForValue(pollenCard.dominant.value) : "transparent"
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: {
                                            if (!pollenCard.dominant) return "--";
                                            var d = pollenCard.dominant;
                                            return pollenCard.pollenName(d.key) + ": "
                                                + i18n(Pollen.labelForValue(d.value))
                                                + " (" + d.value.toFixed(1) + " grains/m³)";
                                        }
                                        color: pollenCard.dominant ? root.bandTextColor(Pollen.bandForValue(pollenCard.dominant.value)) : root.valueColor
                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                        elide: Text.ElideRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // Expand chevron
                                    Item {
                                        visible: !root.isList
                                        implicitWidth: 14; implicitHeight: 14
                                        Layout.alignment: Qt.AlignVCenter
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: "arrow-down"
                                            opacity: 0.45
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root._pollenExpanded = true
                                        }
                                    }
                                }

                                // ── Expanded view ─────────────────────────────────────
                                ColumnLayout {
                                    visible: card._isArcExpanded
                                    anchors {
                                        fill: parent
                                        leftMargin: 10
                                        rightMargin: 10
                                        topMargin: 6
                                        bottomMargin: 6
                                    }
                                    spacing: 4

                                    // Header row
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("pollen") ? root.resolveIcon("pollen") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("pollen"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("pollen") + ":"
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item { Layout.fillWidth: true }
                                        // Collapse chevron
                                        Item {
                                            implicitWidth: 14; implicitHeight: 14
                                            Layout.alignment: Qt.AlignVCenter
                                            Kirigami.Icon {
                                                anchors.fill: parent
                                                source: "arrow-up"
                                                opacity: 0.45
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root._pollenExpanded = false
                                            }
                                        }
                                    }

                                    ScrollView {
                                        id: pollenScrollView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                        ColumnLayout {
                                            width: pollenScrollView.availableWidth
                                            spacing: 4

                                            // No data notice
                                            Label {
                                                visible: pollenCard.entries.length === 0
                                                text: i18n("Pollen data not available for this location.")
                                                color: Kirigami.Theme.disabledTextColor
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                            }

                                            // Pollen rows (KPI-style)
                                            Repeater {
                                                model: pollenCard.entries
                                                delegate: RowLayout {
                                                    id: pollenRow
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 40
                                                    spacing: 10

                                                    readonly property var band: Pollen.bandForValue(modelData.value)
                                                    readonly property real pct: Pollen.scalePercent(modelData.value)

                                                    Text {
                                                        text: "\uF082"  // wi-pollen glyph
                                                        font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                        font.pixelSize: root.glyphIconSize
                                                        color: root.bandTextColor(pollenRow.band)
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    ColumnLayout {
                                                        spacing: 1
                                                        Layout.alignment: Qt.AlignVCenter
                                                        Label {
                                                            text: pollenCard.pollenName(modelData.key)
                                                            font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                            color: Kirigami.Theme.textColor
                                                            opacity: 0.6
                                                        }
                                                        Label {
                                                            text: modelData.value.toFixed(1) + " grains/m³"
                                                            font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({ bold: true })
                                                            color: root.bandTextColor(pollenRow.band)
                                                        }
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    ColumnLayout {
                                                        Layout.preferredWidth: 80
                                                        spacing: 2
                                                        Item {
                                                            Layout.fillWidth: true
                                                            implicitHeight: 6
                                                            Rectangle {
                                                                anchors.fill: parent
                                                                radius: 4
                                                                color: Kirigami.Theme.separatorColor
                                                                opacity: 0.4
                                                            }
                                                            Rectangle {
                                                                width: parent.width * pollenRow.pct / 100
                                                                height: parent.height
                                                                radius: 4
                                                                color: pollenRow.band.color
                                                                opacity: 0.85
                                                            }
                                                        }
                                                        Label {
                                                            text: i18n(pollenRow.band.label)
                                                            color: root.bandTextColor(pollenRow.band)
                                                            font: weatherRoot ? weatherRoot.wf(9, true) : Qt.font({ bold: true })
                                                            Layout.alignment: Qt.AlignHCenter
                                                        }
                                                    }
                                                    PlasmaCore.ToolTipArea {
                                                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                                                        Layout.alignment: Qt.AlignVCenter
                                                        active: true
                                                        mainItem: Label {
                                                            text: i18n(pollenRow.band.description)
                                                            wrapMode: Text.Wrap
                                                            width: 260
                                                        }
                                                        Kirigami.Icon {
                                                            anchors.centerIn: parent
                                                            width: 16; height: 16
                                                            source: "help-about"
                                                            opacity: 0.6
                                                        }
                                                    }
                                                }
                                            } // Repeater (pollen)
                                        }
                                    }
                                } // ColumnLayout expanded
                            } // Item (pollenCard)

                            // ── Space Weather display ────────────────────────────────
                            Item {
                                id: swCard
                                anchors.fill: parent
                                clip: true
                                visible: card.modelData === "spaceweather"

                                readonly property var sw: weatherRoot ? weatherRoot.spaceWeather : null
                                readonly property real kp: sw && !isNaN(sw.kp) ? sw.kp : NaN
                                readonly property string gScale: sw ? (sw.gScale || "G0") : "G0"
                                readonly property color gColor: Qt.color(root.isDark ? SW.gScaleColor(gScale) : SW.gScaleTextColor(gScale))
                                readonly property color kpColor: kp >= 5 ? gColor
                                    : (kp >= 3 ? Qt.color(root.isDark ? "#FFEB3B" : "#5D4800") : Qt.color(root.isDark ? "#4CAF50" : "#1B5E20"))
                                // Vivid variants for progress bar fills (always use bright colors)
                                readonly property color gColorVivid: Qt.color(SW.gScaleColor(gScale))
                                readonly property color kpColorVivid: kp >= 5 ? gColorVivid
                                    : (kp >= 3 ? Qt.color("#FFEB3B") : Qt.color("#4CAF50"))

                                // ── Collapsed header ─────────────────────────────────
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    height: root.regularCardHeight
                                    spacing: 8
                                    visible: !card._isArcExpanded

                                    WeatherIcon {
                                        iconInfo: root.showIconFor("spaceweather") ? root.resolveIcon("spaceweather") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentFor("spaceweather"))
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: root.labelFor("spaceweather") + ":"
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.55
                                        font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label {
                                        text: weatherRoot ? weatherRoot.spaceWeatherText() : "--"
                                        color: swCard.kpColor
                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item {
                                        visible: !root.isList
                                        implicitWidth: 14; implicitHeight: 14
                                        Layout.alignment: Qt.AlignVCenter
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: "arrow-down"
                                            opacity: 0.45
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root._swExpanded = true
                                        }
                                    }
                                }

                                // ── Expanded view ─────────────────────────────────────
                                ColumnLayout {
                                    visible: card._isArcExpanded
                                    anchors {
                                        fill: parent
                                        leftMargin: 10; rightMargin: 10
                                        topMargin: 6; bottomMargin: 6
                                    }
                                    spacing: 0

                                    // Header row
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        WeatherIcon {
                                            iconInfo: root.showIconFor("spaceweather") ? root.resolveIcon("spaceweather") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("spaceweather"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("spaceweather") + ":"
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item { Layout.fillWidth: true }
                                        Item {
                                            implicitWidth: 14; implicitHeight: 14
                                            Layout.alignment: Qt.AlignVCenter
                                            Kirigami.Icon {
                                                anchors.fill: parent
                                                source: "arrow-up"
                                                opacity: 0.45
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root._swExpanded = false
                                            }
                                        }
                                    }

                                    ScrollView {
                                        id: swScrollView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                        ColumnLayout {
                                            width: swScrollView.availableWidth
                                            spacing: 0

                                    // ── Data rows ────────────────────────────────────
                                    // Each row: thin separator + icon column + label + value

                                    // Row 1: Geomagnetic Storm (G Scale)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        spacing: 10

                                        Rectangle {
                                            width: root.glyphIconSize + 6; height: root.glyphIconSize + 6
                                            radius: (root.glyphIconSize + 6) / 2
                                            color: swCard.gColorVivid
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                anchors.centerIn: parent
                                                text: swCard.gScale
                                                font: weatherRoot ? weatherRoot.wf(8, true) : Qt.font({ bold: true })
                                                color: "white"
                                                style: Text.Outline
                                                styleColor: Qt.rgba(0, 0, 0, 0.4)
                                            }
                                        }
                                        ColumnLayout {
                                            spacing: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                text: i18n("Geomagnetic Storm")
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.6
                                            }
                                            Label {
                                                text: i18n(SW.gScaleDescription(swCard.gScale))
                                                font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                                color: swCard.gColor
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    // Row 2: Kp Index
                                    Rectangle {
                                        Layout.fillWidth: true; height: 1
                                        color: Kirigami.Theme.separatorColor; opacity: 0.5
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        spacing: 10

                                        Text {
                                            text: "\uF06E"  // wi-stars
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: root.glyphIconSize
                                            color: swCard.kpColor
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        ColumnLayout {
                                            spacing: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                text: i18n("Kp Index")
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.6
                                            }
                                            Label {
                                                text: isNaN(swCard.kp) ? "--" : swCard.kp.toFixed(1)
                                                font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({ bold: true })
                                                color: swCard.kpColor
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        // Kp bar (0–9)
                                        Item {
                                            Layout.preferredWidth: 80
                                            implicitHeight: 6
                                            Layout.alignment: Qt.AlignVCenter
                                            // Track
                                            Rectangle {
                                                anchors.fill: parent; radius: 3
                                                color: Kirigami.Theme.separatorColor; opacity: 0.4
                                            }
                                            // Fill
                                            Rectangle {
                                                width: isNaN(swCard.kp) ? 0 : Math.min(parent.width, parent.width * swCard.kp / 9)
                                                height: parent.height; radius: 3
                                                color: swCard.kpColorVivid; opacity: 0.85
                                            }
                                        }
                                    }

                                    // Row 3: Solar Wind Speed
                                    Rectangle {
                                        Layout.fillWidth: true; height: 1
                                        color: Kirigami.Theme.separatorColor; opacity: 0.5
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        spacing: 10

                                        readonly property real windSpeed: swCard.sw && !isNaN(swCard.sw.solarWind) ? swCard.sw.solarWind : 0
                                        // Color coding: 300-400 normal (green), 500-700 activity (orange), 700+ storm (red)
                                        readonly property color windColor: windSpeed < 300 ? Qt.color(root.isDark ? "#4CAF50" : "#1B5E20")
                                            : (windSpeed < 500 ? Qt.color(root.isDark ? "#4CAF50" : "#1B5E20")
                                            : (windSpeed < 700 ? Qt.color(root.isDark ? "#FF9800" : "#7A3500")
                                            : Qt.color(root.isDark ? "#D32F2F" : "#7F0000")))
                                        readonly property color windColorVivid: windSpeed < 500 ? Qt.color("#4CAF50")
                                            : (windSpeed < 700 ? Qt.color("#FF9800") : Qt.color("#D32F2F"))
                                        readonly property string windStatus: windSpeed < 500 ? i18n("Normal")
                                            : (windSpeed < 700 ? i18n("Increased Activity")
                                            : i18n("Storm"))

                                        Text {
                                            text: "\uF050"  // wi-wind
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: root.glyphIconSize
                                            color: parent.windColor
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        ColumnLayout {
                                            spacing: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                text: i18n("Solar Wind")
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.6
                                            }
                                            Label {
                                                text: (swCard.sw && !isNaN(swCard.sw.solarWind))
                                                    ? Math.round(swCard.sw.solarWind) + " km/s"
                                                    : "--"
                                                font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({ bold: true })
                                                color: parent.parent.windColor
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        // Progress bar (0–1000 km/s)
                                        Item {
                                            Layout.preferredWidth: 80
                                            implicitHeight: 6
                                            Layout.alignment: Qt.AlignVCenter
                                            // Track
                                            Rectangle {
                                                anchors.fill: parent; radius: 3
                                                color: Kirigami.Theme.separatorColor; opacity: 0.4
                                            }
                                            // Fill
                                            Rectangle {
                                                width: isNaN(parent.parent.windSpeed) ? 0 : Math.min(parent.width, parent.width * parent.parent.windSpeed / 1000)
                                                height: parent.height; radius: 3
                                                color: parent.parent.windColorVivid; opacity: 0.85
                                            }
                                        }
                                        Label {
                                            visible: parent.windSpeed >= 500
                                            text: parent.windStatus
                                            color: parent.windColor
                                            font: weatherRoot ? weatherRoot.wf(9, true) : Qt.font({ bold: true })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }

                                    // Row 3.5: Aurora Probability
                                    Rectangle {
                                        Layout.fillWidth: true; height: 1
                                        color: Kirigami.Theme.separatorColor; opacity: 0.5
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        spacing: 10

                                        readonly property real auroraPercent: swCard.sw && !isNaN(swCard.sw.auroraPercent) ? swCard.sw.auroraPercent : 0
                                        readonly property color auroraColor: auroraPercent < 10 ? Qt.color(root.isDark ? "#4CAF50" : "#1B5E20")
                                            : (auroraPercent < 30 ? Qt.color(root.isDark ? "#FFEB3B" : "#5D4800")
                                            : (auroraPercent < 70 ? Qt.color(root.isDark ? "#FF9800" : "#7A3500")
                                            : Qt.color(root.isDark ? "#D32F2F" : "#7F0000")))
                                        readonly property color auroraColorVivid: auroraPercent < 10 ? Qt.color("#4CAF50")
                                            : (auroraPercent < 30 ? Qt.color("#FFEB3B")
                                            : (auroraPercent < 70 ? Qt.color("#FF9800")
                                            : Qt.color("#D32F2F")))

                                        Text {
                                            text: "\uF0C5"  // wi-moon-alt-full (represents night/aurora)
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: root.glyphIconSize
                                            color: parent.auroraColor
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        ColumnLayout {
                                            spacing: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                text: i18n("Aurora Visibility")
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.6
                                            }
                                            Label {
                                                text: Math.round(parent.parent.auroraPercent) + "%"
                                                font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({ bold: true })
                                                color: parent.parent.auroraColor
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        // Progress bar (0–100%)
                                        Item {
                                            Layout.preferredWidth: 80
                                            implicitHeight: 6
                                            Layout.alignment: Qt.AlignVCenter
                                            // Track
                                            Rectangle {
                                                anchors.fill: parent; radius: 3
                                                color: Kirigami.Theme.separatorColor; opacity: 0.4
                                            }
                                            // Fill
                                            Rectangle {
                                                width: parent.width * parent.parent.auroraPercent / 100
                                                height: parent.height; radius: 3
                                                color: parent.parent.auroraColorVivid; opacity: 0.85
                                            }
                                        }
                                    }

                                    // Row 5: Bz (Magnetic Field)
                                    Rectangle {
                                        Layout.fillWidth: true; height: 1
                                        color: Kirigami.Theme.separatorColor; opacity: 0.5
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        spacing: 10

                                        readonly property bool activeBz: swCard.sw && !isNaN(swCard.sw.bz) && swCard.sw.bz < 0

                                        Text {
                                            text: "\uF0C6"  // wi-wind (repurposed for field)
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: root.glyphIconSize
                                            color: parent.activeBz ? Qt.color(root.isDark ? "#FF9800" : "#7A3500") : root.accentViolet
                                            Layout.alignment: Qt.AlignVCenter
                                            rotation: 90
                                        }
                                        ColumnLayout {
                                            spacing: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                text: i18n("Bz (Magnetic Field)")
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.6
                                            }
                                            Label {
                                                text: (swCard.sw && !isNaN(swCard.sw.bz))
                                                    ? (swCard.sw.bz >= 0 ? "+" : "") + swCard.sw.bz.toFixed(1) + " nT"
                                                    : "--"
                                                font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({ bold: true })
                                                color: parent.parent.activeBz ? Qt.color(root.isDark ? "#FF9800" : "#7A3500") : root.accentViolet
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Label {
                                            visible: parent.activeBz
                                            text: i18n("Active")
                                            color: Qt.color(root.isDark ? "#FF9800" : "#7A3500")
                                            font: weatherRoot ? weatherRoot.wf(9, true) : Qt.font({ bold: true })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }

                                    // Row 6: X-ray Flare Class
                                    Rectangle {
                                        Layout.fillWidth: true; height: 1
                                        color: Kirigami.Theme.separatorColor; opacity: 0.5
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        spacing: 10

                                        readonly property string xCls: swCard.sw ? (swCard.sw.xrayClass || "--") : "--"
                                        readonly property color xColor: Qt.color(root.isDark ? SW.xrayClassColor(xCls) : SW.xrayClassTextColor(xCls))
                                        readonly property color xColorVivid: Qt.color(SW.xrayClassColor(xCls))
                                        readonly property bool flareWarning: xCls === "M" || xCls === "X"

                                        Rectangle {
                                            width: root.glyphIconSize; height: root.glyphIconSize
                                            radius: 3
                                            color: parent.xColorVivid
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                anchors.centerIn: parent
                                                text: parent.parent.xCls
                                                font: weatherRoot ? weatherRoot.wf(8, true) : Qt.font({ bold: true })
                                                color: "white"
                                                style: Text.Outline
                                                styleColor: Qt.rgba(0, 0, 0, 0.4)
                                            }
                                        }
                                        ColumnLayout {
                                            spacing: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            Label {
                                                text: i18n("X-ray Flare Class")
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.6
                                            }
                                            Label {
                                                text: (swCard.sw && swCard.sw.xrayClassFull && swCard.sw.xrayClassFull !== "--")
                                                    ? swCard.sw.xrayClassFull
                                                    : "--"
                                                font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({ bold: true })
                                                color: parent.parent.xColor
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Label {
                                            visible: parent.flareWarning
                                            text: i18n("Flare Warning")
                                            color: parent.xColor
                                            font: weatherRoot ? weatherRoot.wf(9, true) : Qt.font({ bold: true })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true; height: 1
                                        color: Kirigami.Theme.separatorColor; opacity: 0.5
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                        textFormat: Text.RichText
                                        text: i18n("Provider:") + " <a href='https://www.swpc.noaa.gov/'>NOAA SWPC</a>"
                                        color: Kirigami.Theme.disabledTextColor
                                        font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                        onLinkActivated: function(link) { Qt.openUrlExternally(link); }
                                    }

                                        }
                                    }

                                } // ColumnLayout expanded
                            } // Item (swCard)

                            // ── Alerts display ──────────────────────────────────────
                            Item {
                                id: alertsCard
                                anchors.fill: parent
                                clip: true
                                visible: card.modelData === "alerts" && weatherRoot
                                         && weatherRoot.weatherAlerts && weatherRoot.weatherAlerts.length > 0

                                readonly property var alerts: weatherRoot ? (weatherRoot.weatherAlerts || []) : []
                                readonly property bool hasMultiple: alerts.length > 1

                                // Alerts active right now (onset <= now <= expires)
                                readonly property var todayAlerts: {
                                    var now = new Date();
                                    var result = [];
                                    for (var i = 0; i < alerts.length; i++) {
                                        var a = alerts[i];
                                        var onset = a.onset ? new Date(a.onset) : null;
                                        var expires = a.expires ? new Date(a.expires) : null;
                                        var started = !onset || onset <= now;
                                        var notExpired = !expires || expires >= now;
                                        if (started && notExpired)
                                            result.push(a);
                                    }
                                    // If nothing is active yet, show the earliest-future one
                                    if (result.length === 0 && alerts.length > 0) {
                                        var best = alerts[0];
                                        for (var j = 1; j < alerts.length; j++) {
                                            if (alerts[j].onset && (!best.onset || alerts[j].onset < best.onset))
                                                best = alerts[j];
                                        }
                                        result.push(best);
                                    }
                                    return result;
                                }
                                readonly property int safeIndex: Math.min(Math.max(0, root._currentAlertIndex),
                                                                         Math.max(0, todayAlerts.length - 1))
                                readonly property bool todayHasMultiple: todayAlerts.length > 1

                                // All alerts sorted by onset date (for expanded view)
                                readonly property var sortedAlerts: {
                                    var copy = alerts.slice();
                                    copy.sort(function (a, b) {
                                        var da = a.onset ? new Date(a.onset).getTime() : 0;
                                        var db = b.onset ? new Date(b.onset).getTime() : 0;
                                        return da - db;
                                    });
                                    return copy;
                                }

                                // Active alerts (onset <= now <= expires), sorted by priority then onset
                                readonly property var activeAlerts: {
                                    var now = new Date();
                                    var result = [];
                                    for (var i = 0; i < alerts.length; i++) {
                                        var a = alerts[i];
                                        var onset   = a.onset   ? new Date(a.onset)   : null;
                                        var expires = a.expires ? new Date(a.expires) : null;
                                        if ((!onset || onset <= now) && (!expires || expires >= now))
                                            result.push(a);
                                    }
                                    result.sort(function (a, b) {
                                        var da = a.onset ? new Date(a.onset).getTime() : 0;
                                        var db = b.onset ? new Date(b.onset).getTime() : 0;
                                        return da - db;
                                    });
                                    return result;
                                }

                                // Future alerts (onset > now), sorted by onset ascending
                                readonly property var futureAlerts: {
                                    var now = new Date();
                                    var result = [];
                                    for (var i = 0; i < alerts.length; i++) {
                                        var a = alerts[i];
                                        var onset = a.onset ? new Date(a.onset) : null;
                                        if (onset && onset > now)
                                            result.push(a);
                                    }
                                    result.sort(function (a, b) {
                                        return new Date(a.onset).getTime() - new Date(b.onset).getTime();
                                    });
                                    return result;
                                }

                                function alertColorDot(c) {
                                    c = (c || "").toLowerCase();
                                    if (c === "yellow") return "#ffc107";
                                    if (c === "orange") return "#ff8c00";
                                    if (c === "red")    return "#dc3545";
                                    return "#999";
                                }
                                // Map MeteoAlarm awareness_type number to Weather Icons glyph
                                // 1=Wind, 2=Snow/Ice, 3=Thunderstorm, 4=Fog,
                                // 5=High temp, 6=Low temp, 7=Coastal, 8=Fire,
                                // 9=Avalanche, 10=Rain, 11=Flooding, 12=Rain-Flood
                                function alertTypeIcon(typeNum) {
                                    return weatherRoot ? weatherRoot.alertTypeGlyph(typeNum) : "\uf0ce";
                                }
                                    // Collect unique awareness types across today's alerts
                                function uniqueAlertTypes() {
                                    var seen = {};
                                    var result = [];
                                    var src = todayAlerts;
                                    for (var i = 0; i < src.length; i++) {
                                        var a = src[i];
                                        var t = a.awarenessType || 0;
                                        var key = t + "|" + (a.color || "");
                                        if (!seen[key]) {
                                            seen[key] = true;
                                            result.push({ type: t, color: a.color || "" });
                                        }
                                    }
                                    return result;
                                }
                                function alertColorText(c) {
                                    c = (c || "").toLowerCase();
                                    if (c === "yellow") return root.isDark ? "#ffc107" : "#9a7b00";
                                    if (c === "orange") return root.isDark ? "#ff8c00" : "#c04000";
                                    if (c === "red")    return root.isDark ? "#ff4444" : "#cc0000";
                                    return Kirigami.Theme.textColor;
                                }
                                function formatAlertDate(iso) {
                                    if (!iso) return "";
                                    var d = new Date(iso);
                                    if (isNaN(d.getTime())) return "";
                                    return Qt.formatDate(d, "MMM d");
                                }
                                function alertDateRange(a) {
                                    var from = formatAlertDate(a.onset);
                                    var to = formatAlertDate(a.expires);
                                    if (from && to && from !== to)
                                        return from + " \u2013 " + to;
                                    if (from) return from;
                                    if (to) return to;
                                    return "";
                                }
                                function formatAlertDateTime(iso) {
                                    if (!iso) return "";
                                    var d = new Date(iso);
                                    if (isNaN(d.getTime())) return "";
                                    return Qt.formatDateTime(d, "MMM d, hh:mm");
                                }
                                function alertTooltipTitle(a) {
                                    var town = (Plasmoid.configuration.locationName || "").split(",")[0].trim();
                                    var area = a ? (a.area || "") : "";
                                    if (town && area) return town + ", " + area;
                                    return town || area;
                                }
                                function _truncate(str, max) {
                                    if (!str) return "";
                                    return str.length > max ? str.substring(0, max).trimRight() + "…" : str;
                                }
                                function alertTooltipSub(a) {
                                    var lines = [];
                                    if (a.headline)
                                        lines.push("<b>" + i18n("Headline") + ":</b> " + a.headline);
                                    if (a.description)
                                        lines.push("<b>" + i18n("Description") + ":</b><br>" + a.description);
                                    if (a.effective)
                                        lines.push("<b>" + i18n("Effective") + ":</b> " + formatAlertDateTime(a.effective));
                                    if (a.expires)
                                        lines.push("<b>" + i18n("Expires") + ":</b> " + formatAlertDateTime(a.expires));
                                    if (a.instruction)
                                        lines.push("<b>" + i18n("Instruction") + ":</b><br>" + a.instruction);
                                    if (a.senderName)
                                        lines.push("<b>" + i18n("Provider") + ":</b> " + a.senderName);
                                    if (a.web)
                                        lines.push("<b>" + i18n("Website") + ":</b> " + a.web);
                                    return lines.join("<br>");
                                }

                                // ── Single alert (no expand needed) ──────────────────
                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 10
                                        rightMargin: 10
                                    }
                                    spacing: 8
                                    visible: !alertsCard.hasMultiple

                                    WeatherIcon {
                                        iconInfo: root.showIconFor("alerts") ? root.resolveIcon("alerts") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentFor("alerts"))
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: root.labelFor("alerts") + ":"
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.55
                                        font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: alertsCard.alerts.length > 0
                                              ? alertsCard.alertTypeIcon(alertsCard.alerts[0].awarenessType || 0) : ""
                                        font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                        font.pixelSize: 14
                                        color: alertsCard.alerts.length > 0
                                               ? alertsCard.alertColorText(alertsCard.alerts[0].color) : "#999"
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: alertsCard.alerts.length > 0
                                              ? (alertsCard.alerts[0].displayName || alertsCard.alerts[0].headline || "") : ""
                                        color: alertsCard.alerts.length > 0
                                               ? alertsCard.alertColorText(alertsCard.alerts[0].color)
                                               : Kirigami.Theme.textColor
                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                        elide: Text.ElideRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    PlasmaCore.ToolTipArea {
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        active: true
                                        mainItem: ColumnLayout {
                                            width: 380
                                            spacing: 6
                                            Label {
                                                text: alertsCard.alerts.length > 0 ? alertsCard.alertTooltipTitle(alertsCard.alerts[0]) : ""
                                                font.bold: true
                                                wrapMode: Text.Wrap
                                                width: parent.width
                                                Layout.fillWidth: true
                                            }
                                            Label {
                                                text: alertsCard.alerts.length > 0 ? alertsCard.alertTooltipSub(alertsCard.alerts[0]) : ""
                                                textFormat: Text.RichText
                                                wrapMode: Text.Wrap
                                                width: parent.width
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            source: "help-about"
                                        }
                                    }
                                }

                                // ── Collapsed header (multiple alerts) ───────────────
                                RowLayout {
                                    id: alertsHeader
                                    visible: alertsCard.hasMultiple && !card._isArcExpanded
                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        right: parent.right
                                        leftMargin: 10
                                        rightMargin: 10
                                    }
                                    height: card._isArcExpanded ? 0 : root.regularCardHeight
                                    spacing: 8

                                    WeatherIcon {
                                        iconInfo: root.showIconFor("alerts") ? root.resolveIcon("alerts") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentFor("alerts"))
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: root.labelFor("alerts") + ":"
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.55
                                        font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // Left arrow (only when multiple today alerts)
                                    Item {
                                        visible: alertsCard.todayHasMultiple
                                        implicitWidth: 16; implicitHeight: 16
                                        Layout.alignment: Qt.AlignVCenter
                                        opacity: alertsCard.safeIndex > 0 ? 0.75 : 0.20
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: "arrow-left"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: alertsCard.safeIndex > 0
                                            onClicked: root._currentAlertIndex = alertsCard.safeIndex - 1
                                        }
                                    }

                                    // Icon for the currently displayed warning
                                    Text {
                                        text: {
                                            var a = alertsCard.todayAlerts[alertsCard.safeIndex];
                                            return a ? alertsCard.alertTypeIcon(a.awarenessType || 0) : "";
                                        }
                                        font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                        font.pixelSize: 14
                                        color: {
                                            var a = alertsCard.todayAlerts[alertsCard.safeIndex];
                                            return a ? alertsCard.alertColorText(a.color) : "#999";
                                        }
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        text: {
                                            var a = alertsCard.todayAlerts[alertsCard.safeIndex];
                                            return a ? (a.displayName || a.headline || "") : "";
                                        }
                                        color: {
                                            var a = alertsCard.todayAlerts[alertsCard.safeIndex];
                                            return a ? alertsCard.alertColorText(a.color) : Kirigami.Theme.textColor;
                                        }
                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // Right arrow (only when multiple today alerts)
                                    Item {
                                        visible: alertsCard.todayHasMultiple
                                        implicitWidth: 16; implicitHeight: 16
                                        Layout.alignment: Qt.AlignVCenter
                                        opacity: alertsCard.safeIndex < alertsCard.todayAlerts.length - 1 ? 0.75 : 0.20
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: "arrow-right"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: alertsCard.safeIndex < alertsCard.todayAlerts.length - 1
                                            onClicked: root._currentAlertIndex = alertsCard.safeIndex + 1
                                        }
                                    }

                                    // Info tooltip for current alert
                                    PlasmaCore.ToolTipArea {
                                        Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        active: true
                                        mainItem: ColumnLayout {
                                            width: 380
                                            spacing: 6
                                            Label {
                                                text: {
                                                    var a = alertsCard.todayAlerts[alertsCard.safeIndex];
                                                    return alertsCard.alertTooltipTitle(a);
                                                }
                                                font.bold: true
                                                wrapMode: Text.Wrap
                                                width: parent.width
                                                Layout.fillWidth: true
                                            }
                                            Label {
                                                text: {
                                                    var a = alertsCard.todayAlerts[alertsCard.safeIndex];
                                                    return a ? alertsCard.alertTooltipSub(a) : "";
                                                }
                                                textFormat: Text.RichText
                                                wrapMode: Text.Wrap
                                                width: parent.width
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            source: "help-about"
                                        }
                                    }

                                    // Expand chevron
                                    Item {
                                        visible: !root.isList
                                        implicitWidth: 14; implicitHeight: 14
                                        Layout.alignment: Qt.AlignVCenter
                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            source: "arrow-down"
                                            opacity: 0.45
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root._alertsExpanded = true
                                        }
                                    }
                                }

                                // ── Expanded view (multiple alerts with dates) ───────
                                ColumnLayout {
                                    visible: alertsCard.hasMultiple && card._isArcExpanded
                                    anchors {
                                        fill: parent
                                        leftMargin: 10
                                        rightMargin: 10
                                        topMargin: 6
                                        bottomMargin: 6
                                    }
                                    spacing: 4

                                    // Header row
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("alerts") ? root.resolveIcon("alerts") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("alerts"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("alerts") + ":"
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item { Layout.fillWidth: true }
                                        Item {
                                            implicitWidth: 14; implicitHeight: 14
                                            Layout.alignment: Qt.AlignVCenter
                                            Kirigami.Icon {
                                                anchors.fill: parent
                                                source: "arrow-up"
                                                opacity: 0.45
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root._alertsExpanded = false
                                            }
                                        }
                                    }

                                    // All alert rows sorted by date (scrollable)
                                    ScrollView {
                                        id: alertsScrollView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                        ColumnLayout {
                                            width: alertsScrollView.availableWidth
                                            spacing: 4

                                            Repeater {
                                                model: alertsCard.activeAlerts
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    required property int index
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                            Text {
                                                text: alertsCard.alertTypeIcon(modelData.awarenessType || 0)
                                                font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                font.pixelSize: 12
                                                color: alertsCard.alertColorText(modelData.color)
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Label {
                                                text: modelData.displayName || modelData.headline || ""
                                                color: alertsCard.alertColorText(modelData.color)
                                                font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Label {
                                                text: alertsCard.alertDateRange(modelData)
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.55
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                Layout.alignment: Qt.AlignVCenter
                                                visible: text.length > 0
                                            }
                                            PlasmaCore.ToolTipArea {
                                                Layout.preferredWidth: 26
                                                Layout.minimumWidth: 26
                                                Layout.preferredHeight: 26
                                                Layout.alignment: Qt.AlignVCenter
                                                active: true
                                                mainItem: ColumnLayout {
                                                    width: 380
                                                    spacing: 6
                                                    Label {
                                                        text: alertsCard.alertTooltipTitle(modelData)
                                                        font.bold: true
                                                        wrapMode: Text.Wrap
                                                        width: parent.width
                                                        Layout.fillWidth: true
                                                    }
                                                    Label {
                                                        text: alertsCard.alertTooltipSub(modelData)
                                                        textFormat: Text.RichText
                                                        wrapMode: Text.Wrap
                                                        width: parent.width
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                                Kirigami.Icon {
                                                    anchors.centerIn: parent
                                                    width: 18; height: 18
                                                    source: "help-about"
                                                }
                                            }
                                                }
                                            } // Repeater (active)

                                            // ── Future alerts separator ───────────────
                                            RowLayout {
                                                visible: alertsCard.futureAlerts.length > 0
                                                Layout.fillWidth: true
                                                Layout.topMargin: 4
                                                spacing: 6

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 1
                                                    color: Kirigami.Theme.disabledTextColor
                                                    opacity: 0.4
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    text: i18n("Future alerts")
                                                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                    color: Kirigami.Theme.disabledTextColor
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 1
                                                    color: Kirigami.Theme.disabledTextColor
                                                    opacity: 0.4
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }

                                            Repeater {
                                                model: alertsCard.futureAlerts
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    required property int index
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                            Text {
                                                text: alertsCard.alertTypeIcon(modelData.awarenessType || 0)
                                                font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                font.pixelSize: 12
                                                color: alertsCard.alertColorText(modelData.color)
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Label {
                                                text: modelData.displayName || modelData.headline || ""
                                                color: alertsCard.alertColorText(modelData.color)
                                                font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Label {
                                                text: alertsCard.alertDateRange(modelData)
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.55
                                                font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                Layout.alignment: Qt.AlignVCenter
                                                visible: text.length > 0
                                            }
                                            PlasmaCore.ToolTipArea {
                                                Layout.preferredWidth: 26
                                                Layout.minimumWidth: 26
                                                Layout.preferredHeight: 26
                                                Layout.alignment: Qt.AlignVCenter
                                                active: true
                                                mainItem: ColumnLayout {
                                                    width: 380
                                                    spacing: 6
                                                    Label {
                                                        text: alertsCard.alertTooltipTitle(modelData)
                                                        font.bold: true
                                                        wrapMode: Text.Wrap
                                                        width: parent.width
                                                        Layout.fillWidth: true
                                                    }
                                                    Label {
                                                        text: alertsCard.alertTooltipSub(modelData)
                                                        textFormat: Text.RichText
                                                        wrapMode: Text.Wrap
                                                        width: parent.width
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                                Kirigami.Icon {
                                                    anchors.centerIn: parent
                                                    width: 18; height: 18
                                                    source: "help-about"
                                                }
                                            }
                                                }
                                            } // Repeater (future)
                                    } // ColumnLayout inside ScrollView
                                    } // ScrollView

                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                        textFormat: Text.RichText
                                        text: i18n("Provider:") + " <a href='https://www.meteoalarm.org/'>EUMETNET</a>"
                                        color: Kirigami.Theme.disabledTextColor
                                        font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                        onLinkActivated: function(link) { Qt.openUrlExternally(link); }
                                    }
                                }

                            }

                            // ═══════════════════════════════════════════════════════════════
                            // Suntimes — animated sun/moon arc card
                            //
                            // DAY:   sun travels left→noon→right   (warm gold palette)
                            // NIGHT: moon travels right→midnight→left  (cool blue palette)
                            //        stars appear; bottom row flips: sunset left, sunrise right
                            //
                            // ═════════════════════════════════════════════════════════════════
                            // Suntimes — animated sun/moon arc card
                            //
                            // DAY:   sun travels left→noon→right   (warm gold palette)
                            // NIGHT: moon travels right→midnight→left (cool pink/violet palette)
                            //        stars appear in sky; bottom row flips labels
                            //
                            // _isNight is driven by an explicit _updateProg() function — NOT
                            // a QML binding — because QML bindings only re-evaluate when their
                            // declared QML dependencies change.  new Date() inside a JS call is
                            // NOT a QML dependency, so a binding would freeze at the value it
                            // had when sunrise/sunset strings last changed, making night mode
                            // never trigger after the widget first loads with daytime data.
                            // ═════════════════════════════════════════════════════════════════
                            Item {
                                id: suntimesCard
                                anchors.fill: parent
                                clip: true
                                // Arc card hidden in list mode (compact row used instead)
                                visible: card.modelData === "suntimes" && !root.isList

                                // ── Collapse / expand header ──────────────────────────
                                // Styled like a standard item row so it blends when collapsed.
                                RowLayout {
                                    id: sunHeader
                                    visible: !card._isArcExpanded
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    // height=0 when expanded so canvas anchors to parent.top
                                    height: card._isArcExpanded ? 0 : root.regularCardHeight
                                    spacing: 8

                                    // Leading icon — sunrise or sunset depending on day/night
                                    // Kirigami.Icon {
                                    //     source: {
                                    //         var stem = suntimesCard._isNight ? "sunset" : "sunrise";
                                    //         return root.svgBase.length > 0
                                    //             ? (root.svgBase + stem + ".svg")
                                    //             : Qt.resolvedUrl("../icons/symbolic/32/wi-" + stem + ".svg");
                                    //     }
                                    //     isMask: true
                                    //     color: root.accentFor("suntimes")
                                    //     implicitWidth: root.iconSize
                                    //     implicitHeight: root.iconSize
                                    //     Layout.alignment: Qt.AlignVCenter
                                    // }

                                    WeatherIcon {
                                        iconInfo: {
                                            if (!root.showIconFor("suntimes"))
                                                return null;
                                            var m = root.sunTimesMode;
                                            if (m === "sunrise")
                                                return root.resolveIcon("suntimes-sunrise");
                                            if (m === "sunset")
                                                return root.resolveIcon("suntimes-sunset");
                                            if (m === "upcoming")
                                                return root.resolveIcon(root.upcomingSunEvent() === "sunrise" ? "suntimes-sunrise" : "suntimes-sunset");
                                            // "both" — prefer custom sunrise icon if set
                                            var custom = root.getDetailsCustomIcon("suntimes-sunrise");
                                            if (custom.length > 0 && root.iconTheme === "kde")
                                                return { type: "kde", source: custom, svgFallback: "", isMask: false };
                                            return root.resolveIcon("suntimes");
                                        }
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentFor("suntimes"))
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    // Dim label — matches standard row style
                                    Label {
                                        text: {
                                            var m = root.sunTimesMode;
                                            if (m === "sunrise")
                                                return i18n("Sunrise") + ":";
                                            if (m === "sunset")
                                                return i18n("Sunset") + ":";
                                            if (m === "upcoming")
                                                return (root.upcomingSunEvent() === "sunrise" ? i18n("Sunrise") : i18n("Sunset")) + ":";
                                            return root.labelFor("suntimes") + ":";
                                        }
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.55
                                        font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                        elide: Text.ElideRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }
                                    // Bold value — sunrise / sunset times
                                    Label {
                                        text: {
                                            if (!root.weatherRoot)
                                                return "--";
                                            var m = root.sunTimesMode, r = root.weatherRoot;
                                            if (m === "sunrise")
                                                return r.formatTimeForDisplay(r.sunriseTimeText);
                                            if (m === "sunset")
                                                return r.formatTimeForDisplay(r.sunsetTimeText);
                                            if (m === "upcoming") {
                                                var nowM = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                                                var riseM = SunPath.parseMins(r.sunriseTimeText);
                                                var setM = SunPath.parseMins(r.sunsetTimeText);
                                                if (riseM >= 0 && nowM < riseM)
                                                    return r.formatTimeForDisplay(r.sunriseTimeText);
                                                if (setM >= 0 && nowM < setM)
                                                    return r.formatTimeForDisplay(r.sunsetTimeText);
                                                return r.formatTimeForDisplay(r.sunriseTimeText);
                                            }
                                            return r.formatTimeForDisplay(r.sunriseTimeText) + " / " + r.formatTimeForDisplay(r.sunsetTimeText);
                                        }
                                        color: root.valueColor
                                        font: root.weatherRoot ? root.weatherRoot.wf(13, true) : Qt.font({
                                            bold: true
                                        })
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    // Chevron
                                    Kirigami.Icon {
                                        source: card._isArcExpanded ? "arrow-up" : "arrow-down"
                                        implicitWidth: 14
                                        implicitHeight: 14
                                        opacity: 0.45
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                                // MouseArea must be a sibling of the RowLayout, not a child.
                                // Inside a RowLayout, anchors.fill is ignored so the area gets 0 size.
                                MouseArea {
                                    anchors.top: sunHeader.top
                                    anchors.left: sunHeader.left
                                    anchors.right: sunHeader.right
                                    height: sunHeader.height
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root._sunExpanded = !card._isArcExpanded;
                                    }
                                }

                                // ── Collapse button (expanded state only) ─────────
                                Item {
                                    visible: card._isArcExpanded
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: 6
                                    anchors.rightMargin: 8
                                    width: 24
                                    height: 24
                                    Kirigami.Icon {
                                        anchors.fill: parent
                                        source: "arrow-up"
                                        opacity: 0.50
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._sunExpanded = false
                                    }
                                }

                                // ── Day / night flag ──────────────────────────────────
                                // Use weatherRoot.isNightTime() which reads the API's own
                                // is_day field (0=night, 1=day).  This is correct for ANY
                                // location regardless of the machine's local timezone.
                                // All previous attempts computed this from sunrise/sunset vs
                                // new Date().getHours() — which is always machine-local time,
                                // not location-local time — and therefore always failed for
                                // users checking a location in a different timezone.
                                readonly property bool _isNight: root.weatherRoot ? root.weatherRoot.isNightTime() : false

                                // ── Arc position (_prog) ───────────────────────────────
                                // Uses UTC + location UTC-offset (from API) for reliable
                                // local-time computation in Qt's V4 engine.
                                // toLocaleTimeString/Intl with timeZone is NOT supported.
                                readonly property int _utcOffset: root.weatherRoot ? root.weatherRoot.locationUtcOffsetMins : 0
                                property real _prog: 0.5

                                // _now is updated every minute and on every weather refresh.
                                // The two centre Labels reference it so QML treats it as a
                                // dependency and re-evaluates their text: bindings automatically.
                                // Without this, SunPath helpers call new Date() internally which
                                // is NOT a QML property — bindings would freeze on first eval.
                                property int _now: 0
                                function _refreshNow() {
                                    _now = (new Date()).getTime(); // ms timestamp — just needs to change
                                }

                                function _updateProg() {
                                    _refreshNow();
                                    if (root.weatherRoot) {
                                        _prog = SunPath.sunProgress(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText, suntimesCard._utcOffset);
                                    } else {
                                        _prog = 0.5;
                                    }
                                    sunCanvas.requestPaint();
                                }

                                Component.onCompleted: _updateProg()

                                Timer {
                                    interval: 60000
                                    running: suntimesCard.visible
                                    repeat: true
                                    triggeredOnStart: true
                                    onTriggered: suntimesCard._updateProg()
                                }

                                Connections {
                                    target: root.weatherRoot
                                    function onSunriseTimeTextChanged() {
                                        suntimesCard._updateProg();
                                    }
                                    function onSunsetTimeTextChanged() {
                                        suntimesCard._updateProg();
                                    }
                                    // Repaint when is_day flag changes
                                    function onIsDayChanged() {
                                        sunCanvas.requestPaint();
                                    }
                                    // Re-evaluate time labels on every weather refresh.
                                    // temperatureC changes on every provider response.
                                    function onTemperatureCChanged() {
                                        suntimesCard._updateProg();
                                    }
                                }

                                // ── Glow-pulse: 0→1→0 over 3 s, looping ──────────────
                                property real glowPulse: 0
                                SequentialAnimation on glowPulse {
                                    running: suntimesCard.visible
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: 0
                                        to: 1
                                        duration: 1500
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        from: 1
                                        to: 0
                                        duration: 1500
                                        easing.type: Easing.InOutSine
                                    }
                                }
                                onGlowPulseChanged: sunCanvas.requestPaint()

                                // ── Arc canvas ────────────────────────────────────────
                                Canvas {
                                    id: sunCanvas
                                    anchors.top: sunHeader.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: parent.height - sunHeader.height - 50
                                    antialiasing: true
                                    onWidthChanged: requestPaint()

                                    onPaint: {
                                        var ctx2d = getContext("2d");
                                        // _prog drives arc dot position (visual).
                                        // _isNight drives sun vs moon — from API is_day flag.
                                        SunPath.drawSunArc(ctx2d, width, height, suntimesCard._prog, root.isDark, suntimesCard.glowPulse, root.weatherRoot ? root.weatherRoot.sunriseTimeText : "--", root.weatherRoot ? root.weatherRoot.sunsetTimeText : "--", suntimesCard._utcOffset, suntimesCard._isNight);
                                    }
                                } // Canvas

                                // ── Night colour: soft pink/rose ──────────────────────
                                readonly property color _nightLeft: root.isDark ? "#f0a0c0" : "#c0406a"
                                readonly property color _nightRight: root.isDark ? "#c090f0" : "#8030b0"
                                readonly property color _nightCentre: root.isDark ? "#d8a0e0" : "#9040c0"

                                // ── Arc geometry helpers for positioning time labels ──
                                readonly property real _arcR: {
                                    var cx = sunCanvas.width / 2;
                                    var hY = sunCanvas.height - 14;
                                    return Math.min(cx - 28, hY - 12);
                                }

                                // ── Bottom info row ───────────────────────────────────
                                // Centre only: day/night length + remaining time
                                RowLayout {
                                    visible: card._isArcExpanded
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    anchors.bottomMargin: 4
                                    height: 38
                                    spacing: 4

                                    // ── Centre column ─────────────────────────────────
                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Layout.alignment: Qt.AlignVCenter

                                        Label {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: {
                                                void (suntimesCard._now); // reactive — re-evals every minute
                                                if (!root.weatherRoot)
                                                    return "--";
                                                if (suntimesCard._isNight) {
                                                    var nl = SunPath.nightLengthMins(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText);
                                                    return i18n("Night") + ": " + SunPath.formatDuration(nl);
                                                }
                                                var dl = SunPath.dayLengthMins(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText);
                                                return i18n("Day") + ": " + SunPath.formatDuration(dl);
                                            }
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.65
                                            font: root.weatherRoot ? root.weatherRoot.wf(10, false) : Qt.font({})
                                            elide: Text.ElideRight
                                        }

                                        Label {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: {
                                                void (suntimesCard._now); // reactive — re-evals every minute
                                                if (!root.weatherRoot)
                                                    return "--";
                                                if (suntimesCard._isNight) {
                                                    var until = SunPath.minsUntilSunrise(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText, suntimesCard._utcOffset);
                                                    var mp = SunPath.moonProgress(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText, suntimesCard._utcOffset);
                                                    var phase = SunPath.nightPhaseLabel(mp, until);
                                                    if (phase === "approaching")
                                                        return i18n("Dawn approaching — ") + SunPath.formatDuration(until);
                                                    if (phase === "evening")
                                                        return i18n("Evening — ") + SunPath.formatDuration(until) + i18n(" until dawn");
                                                    if (phase === "midnight")
                                                        return i18n("Around midnight — ") + SunPath.formatDuration(until) + i18n(" until dawn");
                                                    return SunPath.formatDuration(until) + " " + i18n("until dawn");
                                                }
                                                var rem = SunPath.remainingMins(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText, suntimesCard._utcOffset);
                                                return rem > 0 ? SunPath.formatDuration(rem) + " " + i18n("left") : i18n("Daylight over");
                                            }
                                            color: suntimesCard._isNight ? suntimesCard._nightCentre : root.accentOrange
                                            font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({
                                                bold: true
                                            })
                                            elide: Text.ElideRight
                                        }
                                    }
                                } // RowLayout (info row)

                                // ── Time labels positioned under arc horizon dots ──
                                Label {
                                    visible: card._isArcExpanded
                                    x: sunCanvas.width / 2 - suntimesCard._arcR - implicitWidth / 2
                                    y: sunCanvas.y + sunCanvas.height - 14 + 8
                                    text: {
                                        if (!root.weatherRoot)
                                            return "--";
                                        var t = root.weatherRoot.sunriseTimeText;
                                        return root.weatherRoot.formatTimeForDisplay(t);
                                    }
                                    color: suntimesCard._isNight ? suntimesCard._nightLeft : root.accentGold
                                    font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                }
                                Label {
                                    visible: card._isArcExpanded
                                    x: sunCanvas.width / 2 + suntimesCard._arcR - implicitWidth / 2
                                    y: sunCanvas.y + sunCanvas.height - 14 + 8
                                    text: {
                                        if (!root.weatherRoot)
                                            return "--";
                                        var t = root.weatherRoot.sunsetTimeText;
                                        return root.weatherRoot.formatTimeForDisplay(t);
                                    }
                                    color: suntimesCard._isNight ? suntimesCard._nightRight : root.accentOrange
                                    font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                }

                            } // Item (suntimes)

                            // ── LIST MODE: compact sunrise/sunset row ─────────────
                            // Direct child of card Rectangle — never hidden by arc Item
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                visible: card.modelData === "suntimes" && root.isList
                                spacing: 8

                                WeatherIcon {
                                    iconInfo: {
                                        if (!root.showIconFor("suntimes"))
                                            return null;
                                        var m = root.sunTimesMode;
                                        if (m === "sunrise")
                                            return root.resolveIcon("suntimes-sunrise");
                                        if (m === "sunset")
                                            return root.resolveIcon("suntimes-sunset");
                                        if (m === "upcoming")
                                            return root.resolveIcon(root.upcomingSunEvent() === "sunrise" ? "suntimes-sunrise" : "suntimes-sunset");
                                        // "both" — prefer custom sunrise icon if set
                                        var custom = root.getDetailsCustomIcon("suntimes-sunrise");
                                        if (custom.length > 0 && root.iconTheme === "kde")
                                            return { type: "kde", source: custom, svgFallback: "", isMask: false };
                                        return root.resolveIcon("suntimes");
                                    }
                                    iconSize: root.iconSize
                                    iconColor: root.iconColorFor(root.accentFor("suntimes"))
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Label {
                                    text: {
                                        var m = root.sunTimesMode;
                                        if (m === "sunrise")
                                            return i18n("Sunrise") + ":";
                                        if (m === "sunset")
                                            return i18n("Sunset") + ":";
                                        if (m === "upcoming")
                                            return (root.upcomingSunEvent() === "sunrise" ? i18n("Sunrise") : i18n("Sunset")) + ":";
                                        return root.labelFor("suntimes") + ":";
                                    }
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.55
                                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                // Sunrise / Sunset — mode-aware right side
                                RowLayout {
                                    spacing: 6
                                    Layout.alignment: Qt.AlignVCenter

                                    // Sunrise icon + time
                                    WeatherIcon {
                                        visible: root.showSunrise()
                                        iconInfo: root.resolveIcon("suntimes-sunrise")
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentGold)
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        visible: root.showSunrise()
                                        text: root.weatherRoot ? root.weatherRoot.formatTimeForDisplay(root.weatherRoot.sunriseTimeText) : "--"
                                        color: root.accentGold
                                        font: root.weatherRoot ? root.weatherRoot.wf(12, true) : Qt.font({
                                            bold: true
                                        })
                                    }
                                    // Separator
                                    Label {
                                        visible: root.sunTimesMode === "both"
                                        text: "/"
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.30
                                        font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                    }
                                    // Sunset icon + time
                                    WeatherIcon {
                                        visible: root.showSunset()
                                        iconInfo: root.resolveIcon("suntimes-sunset")
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentOrange)
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Label {
                                        visible: root.showSunset()
                                        text: root.weatherRoot ? root.weatherRoot.formatTimeForDisplay(root.weatherRoot.sunsetTimeText) : "--"
                                        color: root.accentOrange
                                        font: root.weatherRoot ? root.weatherRoot.wf(12, true) : Qt.font({
                                            bold: true
                                        })
                                    }
                                }
                            }

                            // ═══════════════════════════════════════════════════════════════
                            // Moon Phase — animated arc card
                            //
                            // The moon travels clockwise from left (moonrise) → top (transit)
                            // → right (moonset), exactly mirroring the sun arc architecture.
                            // The body is a phase-accurate crescent/full/new disc.
                            // Stars are always shown in the background.
                            // Bottom row: [↑ moonrise] [phase name · illumination%] [↓ moonset]
                            // ═══════════════════════════════════════════════════════════════
                            Item {
                                id: moonCard
                                anchors.fill: parent
                                clip: true
                                // Arc card hidden in list mode (compact row used instead)
                                visible: card.modelData === "moonphase" && !root.isList

                                // ── Collapse / expand header ──────────────────────────
                                RowLayout {
                                    id: moonHeader
                                    visible: !card._isArcExpanded
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    height: card._isArcExpanded ? 0 : root.regularCardHeight
                                    spacing: 8

                                    WeatherIcon {
                                        iconInfo: {
                                            if (!root.showIconFor("moonphase"))
                                                return null;
                                            var m = root.moonMode;
                                            if (m === "moonrise")
                                                return root.resolveIcon("moonrise");
                                            if (m === "moonset")
                                                return root.resolveIcon("moonset");
                                            if (m === "times")
                                                return root.resolveIcon("moonrise");
                                            if (m === "upcoming-times")
                                                return root.resolveIcon(root.upcomingMoonEvent(moonCard._moonriseText, moonCard._moonsetText) === "moonrise" ? "moonrise" : "moonset");
                                            if (m === "upcoming")
                                                return root.resolveMoonPhaseIcon();
                                            return root.resolveMoonPhaseIcon();
                                        }
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentViolet)
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    // Dim label
                                    Label {
                                        text: {
                                            var m = root.moonMode;
                                            if (m === "times")
                                                return i18n("Moonrise/Moonset") + ":";
                                            if (m === "moonrise")
                                                return i18n("Moonrise") + ":";
                                            if (m === "moonset")
                                                return i18n("Moonset") + ":";
                                            if (m === "upcoming-times") {
                                                var ev2 = root.upcomingMoonEvent(moonCard._moonriseText, moonCard._moonsetText);
                                                return (ev2 === "moonrise" ? i18n("Moonrise") : i18n("Moonset")) + ":";
                                            }
                                            if (m === "upcoming")
                                                return root.labelFor("moonphase") + ":";
                                            return root.labelFor("moonphase") + ":";
                                        }
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.55
                                        font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                        elide: Text.ElideRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: {
                                            if (!root.weatherRoot)
                                                return "--";
                                            var m = root.moonMode;
                                            var r = root.weatherRoot;
                                            if (m === "full") {
                                                return r.moonPhaseLabel() + "  " + r.formatTimeForDisplay(moonCard._moonriseText) + " / " + r.formatTimeForDisplay(moonCard._moonsetText);
                                            }
                                            if (m === "times") {
                                                return r.formatTimeForDisplay(moonCard._moonriseText) + " / " + r.formatTimeForDisplay(moonCard._moonsetText);
                                            }
                                            if (m === "moonrise")
                                                return r.formatTimeForDisplay(moonCard._moonriseText);
                                            if (m === "moonset")
                                                return r.formatTimeForDisplay(moonCard._moonsetText);
                                            if (m === "upcoming") {
                                                var ev = root.upcomingMoonEvent(moonCard._moonriseText, moonCard._moonsetText);
                                                return r.moonPhaseLabel() + "  " + r.formatTimeForDisplay(ev === "moonrise" ? moonCard._moonriseText : moonCard._moonsetText);
                                            }
                                            if (m === "upcoming-times") {
                                                var ev3 = root.upcomingMoonEvent(moonCard._moonriseText, moonCard._moonsetText);
                                                return r.formatTimeForDisplay(ev3 === "moonrise" ? moonCard._moonriseText : moonCard._moonsetText);
                                            }
                                            if (m === "phase")
                                                return r.moonPhaseLabel();
                                            return r.moonPhaseLabel();
                                        }
                                        color: root.accentViolet
                                        font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({
                                            bold: false
                                        })
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    // Chevron
                                    Kirigami.Icon {
                                        source: card._isArcExpanded ? "arrow-up" : "arrow-down"
                                        implicitWidth: 14
                                        implicitHeight: 14
                                        opacity: 0.45
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                                MouseArea {
                                    anchors.top: moonHeader.top
                                    anchors.left: moonHeader.left
                                    anchors.right: moonHeader.right
                                    height: moonHeader.height
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root._moonExpanded = !card._isArcExpanded;
                                    }
                                }

                                // ── Collapse button (expanded state only) ─────────
                                Item {
                                    visible: card._isArcExpanded
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: 6
                                    anchors.rightMargin: 8
                                    width: 24
                                    height: 24
                                    Kirigami.Icon {
                                        anchors.fill: parent
                                        source: "arrow-up"
                                        opacity: 0.50
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._moonExpanded = false
                                    }
                                }

                                // ── Location UTC offset ───────────────────────────────
                                readonly property int _utcOffset: root.weatherRoot ? root.weatherRoot.locationUtcOffsetMins : 0

                                // ── Computed moonrise / moonset ───────────────────────
                                // Calculated astronomically from lat/lon — no API needed.
                                // Recomputed once on load and whenever weather data updates.
                                property string _moonriseText: "--"
                                property string _moonsetText: "--"

                                function _computeTimes() {
                                    var lat = Plasmoid.configuration.latitude;
                                    var lon = Plasmoid.configuration.longitude;
                                    if (isNaN(lat) || isNaN(lon) || (lat === 0 && lon === 0)) {
                                        _moonriseText = "--";
                                        _moonsetText = "--";
                                        return;
                                    }
                                    var t = SC.getMoonTimes(new Date(), lat, lon, moonCard._utcOffset);
                                    _moonriseText = t.rise;
                                    _moonsetText = t.set;
                                }

                                // ── Moon arc progress ─────────────────────────────────
                                property real _prog: 0.5

                                function _updateProg() {
                                    _prog = MoonPath.moonArcProgress(moonCard._moonriseText, moonCard._moonsetText, moonCard._utcOffset);
                                    moonCanvas.requestPaint();
                                }

                                Component.onCompleted: {
                                    _computeTimes();
                                    _updateProg();
                                }

                                // Recompute at midnight (times change each day)
                                Timer {
                                    interval: 60000
                                    running: moonCard.visible
                                    repeat: true
                                    triggeredOnStart: true
                                    onTriggered: {
                                        moonCard._computeTimes();
                                        moonCard._updateProg();
                                    }
                                }

                                // Also recompute when a new location is set
                                Connections {
                                    target: root.weatherRoot
                                    function onLocationUtcOffsetMinsChanged() {
                                        moonCard._computeTimes();
                                        moonCard._updateProg();
                                    }
                                }

                                // ── Glow pulse: 0→1→0 over 3.5 s ─────────────────────
                                property real glowPulse: 0
                                SequentialAnimation on glowPulse {
                                    running: moonCard.visible
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: 0
                                        to: 1
                                        duration: 1750
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        from: 1
                                        to: 0
                                        duration: 1750
                                        easing.type: Easing.InOutSine
                                    }
                                }
                                onGlowPulseChanged: moonCanvas.requestPaint()

                                // ── Arc canvas ────────────────────────────────────────
                                Canvas {
                                    id: moonCanvas
                                    anchors.top: moonHeader.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: parent.height - moonHeader.height - 50
                                    antialiasing: true
                                    onWidthChanged: requestPaint()

                                    onPaint: {
                                        var ctx2d = getContext("2d");
                                        MoonPath.drawMoonArc(ctx2d, width, height, moonCard._prog, root.isDark, moonCard.glowPulse, Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
                                    }
                                } // Canvas

                                // ── Arc geometry helpers for positioning time labels ──
                                readonly property real _arcR: {
                                    var cx = moonCanvas.width / 2;
                                    var hY = moonCanvas.height - 14;
                                    return Math.min(cx - 28, hY - 12);
                                }

                                // ── Bottom info row ───────────────────────────────────
                                // Centre only: [phase glyph + name]
                                RowLayout {
                                    visible: card._isArcExpanded
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    anchors.bottomMargin: 4
                                    height: 38
                                    spacing: 4

                                    // ── Phase glyph + name (centre) ───────────────────
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Layout.alignment: Qt.AlignVCenter
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        WeatherIcon {
                                            iconInfo: root.resolveMoonPhaseIcon()
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentViolet)
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.weatherRoot ? root.weatherRoot.moonPhaseLabel() : "--"
                                            color: root.accentViolet
                                            font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({
                                                bold: false
                                            })
                                            elide: Text.ElideRight
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                    }
                                } // RowLayout (info row)

                                // ── Time labels positioned under arc horizon dots ──
                                Label {
                                    visible: card._isArcExpanded
                                    x: moonCanvas.width / 2 - moonCard._arcR - implicitWidth / 2
                                    y: moonCanvas.y + moonCanvas.height - 14 + 8
                                    text: root.weatherRoot ? root.weatherRoot.formatTimeForDisplay(moonCard._moonriseText) : "--"
                                    color: root.accentViolet
                                    font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                }
                                Label {
                                    visible: card._isArcExpanded
                                    x: moonCanvas.width / 2 + moonCard._arcR - implicitWidth / 2
                                    y: moonCanvas.y + moonCanvas.height - 14 + 8
                                    text: root.weatherRoot ? root.weatherRoot.formatTimeForDisplay(moonCard._moonsetText) : "--"
                                    color: root.accentViolet
                                    opacity: 0.75
                                    font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                }

                            } // Item (moonphase)

                            // ── LIST MODE: compact moon phase row ─────────────────
                            // Direct child of card Rectangle — never hidden by arc Item
                            Item {
                                id: listMoonRow
                                anchors.fill: parent
                                visible: card.modelData === "moonphase" && root.isList

                                // Compute moon times directly here — moonCard.visible is
                                // false in list mode so its Timer never fires.
                                readonly property int _utcOffset: root.weatherRoot ? root.weatherRoot.locationUtcOffsetMins : 0
                                property string _riseText: "--"
                                property string _setText: "--"

                                function _compute() {
                                    var lat = Plasmoid.configuration.latitude;
                                    var lon = Plasmoid.configuration.longitude;
                                    if (isNaN(lat) || isNaN(lon) || (lat === 0 && lon === 0)) {
                                        _riseText = "--";
                                        _setText = "--";
                                        return;
                                    }
                                    var t = SC.getMoonTimes(new Date(), lat, lon, listMoonRow._utcOffset);
                                    _riseText = t.rise;
                                    _setText = t.set;
                                }

                                Component.onCompleted: _compute()
                                Timer {
                                    interval: 3600000   // refresh hourly
                                    running: listMoonRow.visible
                                    repeat: true
                                    onTriggered: listMoonRow._compute()
                                }
                                Connections {
                                    target: root.weatherRoot
                                    function onLocationUtcOffsetMinsChanged() {
                                        listMoonRow._compute();
                                    }
                                }

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 10
                                        rightMargin: 10
                                    }
                                    spacing: 8

                                    WeatherIcon {
                                        iconInfo: {
                                            if (!root.showIconFor("moonphase"))
                                                return null;
                                            var m = root.moonMode;
                                            if (m === "moonrise")
                                                return root.resolveIcon("moonrise");
                                            if (m === "moonset")
                                                return root.resolveIcon("moonset");
                                            if (m === "times")
                                                return root.resolveIcon("moonrise");
                                            if (m === "upcoming-times")
                                                return root.resolveIcon(root.upcomingMoonEvent(listMoonRow._riseText, listMoonRow._setText) === "moonrise" ? "moonrise" : "moonset");
                                            if (m === "upcoming")
                                                return root.resolveMoonPhaseIcon();
                                            return root.resolveMoonPhaseIcon();
                                        }
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentViolet)
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // Label — mode-aware
                                    Label {
                                        text: {
                                            var m = root.moonMode;
                                            if (m === "times")
                                                return i18n("Moonrise/Moonset") + ":";
                                            if (m === "moonrise")
                                                return i18n("Moonrise") + ":";
                                            if (m === "moonset")
                                                return i18n("Moonset") + ":";
                                            if (m === "upcoming-times") {
                                                var ev2 = root.upcomingMoonEvent(listMoonRow._riseText, listMoonRow._setText);
                                                return (ev2 === "moonrise" ? i18n("Moonrise") : i18n("Moonset")) + ":";
                                            }
                                            if (m === "upcoming")
                                                return root.labelFor("moonphase") + ":";
                                            return root.labelFor("moonphase") + ":";
                                        }
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.55
                                        font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    // ── Right side: mode-aware content ──────
                                    RowLayout {
                                        spacing: 8
                                        Layout.alignment: Qt.AlignVCenter

                                        // Phase icon + name (hidden in "times" mode)
                                        WeatherIcon {
                                            visible: root.showMoonPhase()
                                            iconInfo: root.resolveMoonPhaseIcon()
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentViolet)
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            visible: root.showMoonPhase()
                                            text: root.weatherRoot ? root.weatherRoot.moonPhaseLabel() : "--"
                                            color: root.accentViolet
                                            font: root.weatherRoot ? root.weatherRoot.wf(12, true) : Qt.font({
                                                bold: true
                                            })
                                        }

                                        // Moonrise icon + time
                                        RowLayout {
                                            visible: root.showMoonrise(listMoonRow._riseText, listMoonRow._setText)
                                            spacing: 3
                                            Layout.alignment: Qt.AlignVCenter
                                            WeatherIcon {
                                                iconInfo: root.resolveIcon("moonrise")
                                                iconSize: root.iconSize
                                                iconColor: root.iconColorFor(root.accentViolet)
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Label {
                                                text: root.weatherRoot ? root.weatherRoot.formatTimeForDisplay(listMoonRow._riseText) : "--"
                                                color: root.accentViolet
                                                font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                            }
                                        }
                                        // Separator
                                        Label {
                                            visible: root.showMoonrise(listMoonRow._riseText, listMoonRow._setText) && root.showMoonset(listMoonRow._riseText, listMoonRow._setText)
                                            text: "/"
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.30
                                            font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        // Moonset icon + time
                                        RowLayout {
                                            visible: root.showMoonset(listMoonRow._riseText, listMoonRow._setText)
                                            spacing: 3
                                            Layout.alignment: Qt.AlignVCenter
                                            WeatherIcon {
                                                iconInfo: root.resolveIcon("moonset")
                                                iconSize: root.iconSize
                                                iconColor: root.iconColorFor(root.accentViolet)
                                                opacity: 0.75
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Label {
                                                text: root.weatherRoot ? root.weatherRoot.formatTimeForDisplay(listMoonRow._setText) : "--"
                                                color: root.accentViolet
                                                opacity: 0.75
                                                font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                            }
                                        }
                                    }
                                }
                            }
                        } // Rectangle (card)
                    } // Repeater (items)

                    // spacer for odd rows
                    Item {
                        Layout.fillWidth: true
                        visible: rowItem.modelData.length === 1 && !root.isList
                    }
                } // RowLayout (row)
            } // Repeater (rows)
        } // Column
    } // ScrollView
}
