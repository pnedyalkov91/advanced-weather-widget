/*
 * Copyright 2026 Petar Nedyalkov
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
 * along with this program.  If not, see <https://gnu.org>.
 */

/**
 * DetailsView.qml - Dynamic "Details" tab content for the popup
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

import "js/weather.js" as W
import "js/moonphase.js" as Moon
import "js/moonpath.js" as MoonPath
import "js/sunpath.js" as SunPath
import "js/feelsLikeGauge.js" as FeelsLikeGauge
import "js/humidityGauge.js" as HumidityGauge
import "js/dewPointGauge.js" as DewPointGauge
import "js/visibilityGauge.js" as VisibilityGauge
import "js/precipGauge.js" as PrecipGauge
import "js/precipSumGauge.js" as PrecipSumGauge
import "js/uvGauge.js" as UvGauge
import "js/snowGauge.js" as SnowGauge
import "js/windGauge.js" as WindGauge
import "js/barometerGauge.js" as BarometerGauge
import "js/aqiGauge.js" as AqiGauge
import "js/pollenGauge.js" as PollenGauge
import "js/alertGauge.js" as AlertGauge
import "js/spaceWeatherGauge.js" as SwGauge
import "js/suncalc.js" as SC
import "js/iconResolver.js" as IconResolver
import "js/configUtils.js" as ConfigUtils
import "js/airQuality.js" as AQI
import "js/pollen.js" as Pollen
import "js/spaceWeather.js" as SW
import "components"

Item {
    id: root

    // Cached theme colors - a single PlasmaTheme attachment on the view root
    // instead of one per item: every Kirigami.Theme attachment re-syncs
    // (connect+disconnect on the window object) on each window expose, which
    // froze popup opening while hundreds of delegate items were alive.
    readonly property color themeTextColor: Kirigami.Theme.textColor
    readonly property color themeBackgroundColor: Kirigami.Theme.backgroundColor
    readonly property color themeDisabledTextColor: Kirigami.Theme.disabledTextColor
    readonly property color themeHighlightColor: Kirigami.Theme.highlightColor
    readonly property color themeHighlightedTextColor: Kirigami.Theme.highlightedTextColor
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

    // ── Theme helper - true when KDE is using a dark colour scheme ────────
    readonly property bool isDark: root.themeTextColor.r > 0.5

    // ── Colour palette - adapts to dark / light theme ─────────────────────
    readonly property color cardBg: Qt.rgba(root.themeTextColor.r, root.themeTextColor.g, root.themeTextColor.b, 0.07)
    readonly property color cardBorder: Qt.rgba(root.themeTextColor.r, root.themeTextColor.g, root.themeTextColor.b, 0.13)
    readonly property color valueColor: root.themeTextColor

    // Accent colours - shift toward darker hues on light themes for contrast
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
        if (!band)
            return root.themeTextColor;
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

    // Ticks once a minute. upcomingSunEvent()/upcomingMoonEvent() below call
    // helpers that read new Date() internally, which is not a QML
    // dependency - same root cause as suntimesCard._isNight. Rather than
    // caching one result, these two are read from many different icon/label
    // bindings scattered across this file, so instead each function reads
    // this tick property first: any binding that calls into either function,
    // however indirectly, then picks up _nowTick as a real dependency and
    // re-evaluates every minute instead of only when sunrise/sunset text
    // next changes value (roughly once a day).
    property int _nowTick: 0
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._nowTick = (new Date()).getTime()
    }

    /** Returns "sunrise" or "sunset" depending on which is next (for upcoming mode) */
    function upcomingSunEvent() {
        void (root._nowTick);
        if (!weatherRoot)
            return "sunrise";
        var utcOff = weatherRoot.locationUtcOffsetMins || 0;
        var nowM = SunPath.nowMinsAt(utcOff);
        var riseM = SunPath.parseMins(weatherRoot.sunriseTimeText);
        var setM = SunPath.parseMins(weatherRoot.sunsetTimeText);
        var untilRise = SunPath.minsUntilNextEvent(riseM, nowM);
        var untilSet = SunPath.minsUntilNextEvent(setM, nowM);
        if (untilRise < 0 && untilSet < 0)
            return "sunrise";
        if (untilRise < 0)
            return "sunset";
        if (untilSet < 0)
            return "sunrise";
        return untilRise <= untilSet ? "sunrise" : "sunset";
    }

    /** Returns "moonrise" or "moonset" depending on which is next (for upcoming mode) */
    function upcomingMoonEvent(riseText, setText) {
        void (root._nowTick);
        var utcOff = (weatherRoot ? weatherRoot.locationUtcOffsetMins : 0) || 0;
        return MoonPath.nextMoonEvent(riseText, setText, utcOff);
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

    // ── Expanded view item visibility helpers ─────────────────────────────
    // Empty string == user explicitly disabled all items (no fallback to defaults).
    // undefined/null == schema not yet ready; fall back to defaults.
    function _aqiItemVisible(key) {
        var itemsStr = Plasmoid.configuration.aqiExpandedItems;
        if (itemsStr === undefined || itemsStr === null)
            return ["pm2_5", "pm10", "no2", "o3", "so2", "co"].indexOf(key) >= 0;
        return itemsStr.split(",").indexOf(key) >= 0;
    }
    function _pollenItemVisible(key) {
        var itemsStr = Plasmoid.configuration.pollenExpandedItems;
        if (itemsStr === undefined || itemsStr === null)
            return ["alder", "birch", "grass", "mugwort", "olive", "ragweed"].indexOf(key) >= 0;
        return itemsStr.split(",").indexOf(key) >= 0;
    }
    function _swItemVisible(key) {
        var itemsStr = Plasmoid.configuration.spaceWeatherExpandedItems;
        if (itemsStr === undefined || itemsStr === null)
            return ["gscale", "kp", "solarwind", "aurora", "bz", "xray"].indexOf(key) >= 0;
        return itemsStr.split(",").indexOf(key) >= 0;
    }
    function _anyAqiVisible() {
        return ["pm2_5", "pm10", "no2", "o3", "so2", "co"].some(_aqiItemVisible);
    }
    function _anyPollenVisible() {
        return ["alder", "birch", "grass", "mugwort", "olive", "ragweed"].some(_pollenItemVisible);
    }
    function _anySwVisible() {
        return ["gscale", "kp", "solarwind", "aurora", "bz", "xray"].some(_swItemVisible);
    }

    // Auto-collapse expanded cards when their sub-items are all disabled
    Connections {
        target: Plasmoid.configuration
        function onAqiExpandedItemsChanged() {
            if (!root._anyAqiVisible())
                root._aqiExpanded = false;
        }
        function onPollenExpandedItemsChanged() {
            if (!root._anyPollenVisible())
                root._pollenExpanded = false;
        }
        function onSpaceWeatherExpandedItemsChanged() {
            if (!root._anySwVisible())
                root._swExpanded = false;
        }
    }

    // ── Persisted expand / collapse state ────────────────────────────────
    // This view is destroyed whenever the popup unloads it (and on every
    // plasmashell restart), so the open/closed state of the expandable cards
    // lives in Plasmoid.configuration.detailsExpandedCards: a JSON map
    // { cardId: bool }. A card with no entry keeps its default below.
    function _loadExpanded(id, def) {
        try {
            var m = JSON.parse(Plasmoid.configuration.detailsExpandedCards || "{}");
            if (m && typeof m[id] === "boolean")
                return m[id];
        } catch (e) {}
        return def;
    }
    function _saveExpanded(id, on) {
        var m = {};
        try {
            m = JSON.parse(Plasmoid.configuration.detailsExpandedCards || "{}") || {};
        } catch (e) {
            m = {};
        }
        if (m[id] === on)
            return;
        m[id] = on;
        Plasmoid.configuration.detailsExpandedCards = JSON.stringify(m);
    }

    // Collapse state for the two arc cards.
    property bool _sunExpanded: _loadExpanded("suntimes", true)
    property bool _moonExpanded: _loadExpanded("moonphase", true)
    // Wind compass / pressure gauge default to collapsed (opt-in expansion) so
    // adding the feature doesn't change every user's existing card layout.
    property bool _windExpanded: _loadExpanded("wind", false)
    property bool _pressureExpanded: _loadExpanded("pressure", false)
    property bool _alertsExpanded: _loadExpanded("alerts", false)
    property bool _aqiExpanded: _loadExpanded("airquality", false)
    property bool _pollenExpanded: _loadExpanded("pollen", false)
    property bool _swExpanded: _loadExpanded("spaceweather", false)
    property bool _dtExpanded: _loadExpanded("datetime", false)
    on_SunExpandedChanged: _saveExpanded("suntimes", _sunExpanded)
    on_MoonExpandedChanged: _saveExpanded("moonphase", _moonExpanded)
    on_WindExpandedChanged: _saveExpanded("wind", _windExpanded)
    on_PressureExpandedChanged: _saveExpanded("pressure", _pressureExpanded)
    on_AlertsExpandedChanged: _saveExpanded("alerts", _alertsExpanded)
    on_AqiExpandedChanged: _saveExpanded("airquality", _aqiExpanded)
    on_PollenExpandedChanged: _saveExpanded("pollen", _pollenExpanded)
    on_SwExpandedChanged: _saveExpanded("spaceweather", _swExpanded)
    on_DtExpandedChanged: _saveExpanded("datetime", _dtExpanded)

    // ── Expandable gauge cards (cards mode only) ─────────────────────────
    // Feels like, humidity, dew point, visibility, precipitation, precipitation
    // sum, UV index and snow cover. Collapsed = the regular compact row (plus a
    // chevron); expanded = a Canvas gauge drawn by js/<name>Gauge.js, in the
    // same style as the pressure card. All default to collapsed.
    readonly property var _gaugeIds: ["feelslike", "humidity", "dewpoint", "visibility", "preciprate", "precipsum", "uvindex", "snowcover"]
    // id -> bool, read straight from the persisted map (see _saveExpanded above),
    // so a click re-evaluates every binding that reads it.
    readonly property var _gaugeExpanded: {
        try {
            var m = JSON.parse(Plasmoid.configuration.detailsExpandedCards || "{}");
            return (m && typeof m === "object") ? m : {};
        } catch (e) {
            return {};
        }
    }
    function _isGaugeId(id) {
        return _gaugeIds.indexOf(id) >= 0;
    }
    function _setGaugeExpanded(id, on) {
        _saveExpanded(id, on);
    }

    // ── Expand / collapse all (header button in FullView.qml) ────────────
    // Cards that can be expanded right now: cards mode only, the ones shown in
    // widgetDetailsOrder, and not the AQI / pollen / space weather cards whose
    // sub-items are all switched off (their chevron is hidden, so expanding
    // them would only show an empty gauge).
    function _isExpandableCard(id) {
        if (isList)
            return false;
        switch (id) {
        case "suntimes":
        case "moonphase":
        case "wind":
        case "pressure":
        case "alerts":
        case "datetime":
            return true;
        case "airquality":
            return _anyAqiVisible();
        case "pollen":
            return _anyPollenVisible();
        case "spaceweather":
            return _anySwVisible();
        }
        return _isGaugeId(id);
    }
    function _cardExpanded(id) {
        switch (id) {
        case "suntimes":
            return _sunExpanded;
        case "moonphase":
            return _moonExpanded;
        case "wind":
            return _windExpanded;
        case "pressure":
            return _pressureExpanded;
        case "alerts":
            return _alertsExpanded;
        case "airquality":
            return _aqiExpanded;
        case "pollen":
            return _pollenExpanded;
        case "spaceweather":
            return _swExpanded;
        case "datetime":
            return _dtExpanded;
        }
        return _gaugeExpanded[id] === true;
    }
    // Sets the property behind a card. The gauge cards have none: they are
    // read straight from the persisted map (see _gaugeExpanded).
    function _setCardProperty(id, on) {
        switch (id) {
        case "suntimes":
            _sunExpanded = on;
            break;
        case "moonphase":
            _moonExpanded = on;
            break;
        case "wind":
            _windExpanded = on;
            break;
        case "pressure":
            _pressureExpanded = on;
            break;
        case "alerts":
            _alertsExpanded = on;
            break;
        case "airquality":
            _aqiExpanded = on;
            break;
        case "pollen":
            _pollenExpanded = on;
            break;
        case "spaceweather":
            _swExpanded = on;
            break;
        case "datetime":
            _dtExpanded = on;
            break;
        }
    }

    readonly property var _expandableIds: detailIds.filter(function (id) {
        return root._isExpandableCard(id);
    })
    /** The header button is only offered when there is something to toggle. */
    readonly property bool canToggleAll: hasData && _expandableIds.length > 0
    /** True when every expandable card is open (the button then collapses). */
    readonly property bool allExpanded: {
        var ids = _expandableIds;
        if (ids.length === 0)
            return false;
        for (var i = 0; i < ids.length; i++) {
            if (!_cardExpanded(ids[i]))
                return false;
        }
        return true;
    }

    function setAllExpanded(on) {
        var ids = _expandableIds;
        if (ids.length === 0)
            return;
        // One write to the persisted map instead of one per card. The property
        // handlers (on_XExpandedChanged -> _saveExpanded) then find the value
        // already stored and skip their own write.
        var m = {};
        try {
            m = JSON.parse(Plasmoid.configuration.detailsExpandedCards || "{}") || {};
        } catch (e) {
            m = {};
        }
        for (var i = 0; i < ids.length; i++)
            m[ids[i]] = on;
        Plasmoid.configuration.detailsExpandedCards = JSON.stringify(m);
        for (var j = 0; j < ids.length; j++)
            _setCardProperty(ids[j], on);
    }
    function toggleAllExpanded() {
        setAllExpanded(!allExpanded);
    }

    /** Metric the gauge shows (metric units; the JS converts for display). */
    function _gaugeValue(id) {
        var w = weatherRoot;
        if (!w)
            return NaN;
        switch (id) {
        case "feelslike":
            return w.apparentC;
        case "humidity":
            return w.humidityPercent;
        case "dewpoint":
            return w.dewPointC;
        case "visibility":
            return w.visibilityKm;
        case "preciprate":
            return w.precipMmh;
        case "precipsum":
            return w.precipSumMm;
        case "uvindex":
            return w.uvIndex;
        case "snowcover":
            return w.snowDepthCm;
        }
        return NaN;
    }
    /** Secondary metric: air temperature (feels like / dew point), today's peak (UV). */
    function _gaugeValue2(id) {
        var w = weatherRoot;
        if (!w)
            return NaN;
        switch (id) {
        case "feelslike":
        case "dewpoint":
            return w.temperatureC;
        case "uvindex":
            {
                var d = w.dailyData;
                // isNaN(null) is false, so null must be rejected explicitly
                if (d && d.length > 0 && d[0].uvMax !== undefined && d[0].uvMax !== null && !isNaN(d[0].uvMax))
                    return d[0].uvMax;
                return NaN;
            }
        }
        return NaN;
    }
    /** {key, color} of the band the value falls in. */
    function _gaugeInfo(id, v) {
        switch (id) {
        case "feelslike":
            return FeelsLikeGauge.info(v, isDark);
        case "humidity":
            return HumidityGauge.info(v, isDark);
        case "dewpoint":
            return DewPointGauge.info(v, isDark);
        case "visibility":
            return VisibilityGauge.info(v, isDark);
        case "preciprate":
            return PrecipGauge.info(v, isDark);
        case "precipsum":
            return PrecipSumGauge.info(v, isDark);
        case "uvindex":
            return UvGauge.info(v, isDark);
        case "snowcover":
            return SnowGauge.info(v, isDark);
        }
        return {
            key: "",
            color: root.accentFor(id)
        };
    }
    function _gaugeDraw(id, ctx, w, h, p) {
        switch (id) {
        case "feelslike":
            FeelsLikeGauge.draw(ctx, w, h, p);
            break;
        case "humidity":
            HumidityGauge.draw(ctx, w, h, p);
            break;
        case "dewpoint":
            DewPointGauge.draw(ctx, w, h, p);
            break;
        case "visibility":
            VisibilityGauge.draw(ctx, w, h, p);
            break;
        case "preciprate":
            PrecipGauge.draw(ctx, w, h, p);
            break;
        case "precipsum":
            PrecipSumGauge.draw(ctx, w, h, p);
            break;
        case "uvindex":
            UvGauge.draw(ctx, w, h, p);
            break;
        case "snowcover":
            SnowGauge.draw(ctx, w, h, p);
            break;
        }
    }
    /** Band key -> translated label. Literal i18n() calls so xgettext finds them. */
    function _gaugeBandText(id, key) {
        if (!key)
            return "";
        switch (key) {
        case "dry":
            return i18n("Dry");
        case "comfortable":
            return i18n("Comfortable");
        case "humid":
            return i18n("Humid");
        case "veryhumid":
            return i18n("Very humid");
        case "oppressive":
            return i18n("Oppressive");
        case "fog":
            return i18n("Fog");
        case "poor":
            return i18n("Poor");
        case "moderate":
            return i18n("Moderate");
        case "good":
            return i18n("Good");
        case "excellent":
            return i18n("Excellent");
        case "none":
            return id === "snowcover" ? i18n("No snow") : i18n("None");
        case "light":
            return i18n("Light");
        case "heavy":
            return i18n("Heavy");
        case "extreme":
            return i18n("Extreme");
        case "low":
            return i18n("Low");
        case "high":
            return i18n("High");
        case "veryhigh":
            return i18n("Very high");
        case "deep":
            return i18n("Deep");
        case "verydeep":
            return i18n("Very deep");
        case "freezing":
            return i18n("Freezing");
        case "cold":
            return i18n("Cold");
        case "cool":
            return i18n("Cool");
        case "warm":
            return i18n("Warm");
        case "hot":
            return i18n("Hot");
        case "extremeheat":
            return i18n("Extreme heat");
        }
        return "";
    }
    /** Beaufort band key (windGauge.js) -> translated label. */
    function _windBandText(key) {
        switch (key) {
        case "calm":
            return i18n("Calm");
        case "lightair":
            return i18n("Light air");
        case "lightbreeze":
            return i18n("Light breeze");
        case "gentlebreeze":
            return i18n("Gentle breeze");
        case "moderatebreeze":
            return i18n("Moderate breeze");
        case "freshbreeze":
            return i18n("Fresh breeze");
        case "strongbreeze":
            return i18n("Strong breeze");
        case "neargale":
            return i18n("Near gale");
        case "gale":
            return i18n("Gale");
        case "stronggale":
            return i18n("Strong gale");
        case "storm":
            return i18n("Storm");
        case "violentstorm":
            return i18n("Violent storm");
        case "hurricane":
            return i18n("Hurricane");
        }
        return "";
    }
    /**
     * Pressure change over the last 3 hours, from the readings main.qml collects
     * (weatherRoot.pressureSamples = [[ms, hPa], ...]). The sample about 3 h before the
     * newest one is compared with it (at least 1 h apart, the change is scaled to 3 h).
     * -> { ok: false } while there is not enough history, else { ok, d3 (hPa / 3 h) }
     */
    function _pressureTendency() {
        var s = root.weatherRoot ? root.weatherRoot.pressureSamples : null;
        if (!s || s.length < 2)
            return {
                ok: false
            };
        var latest = s[s.length - 1];
        var target = latest[0] - 3 * 3600000;
        var best = null, bestDist = 1e18;
        for (var i = 0; i < s.length - 1; i++) {
            if (latest[0] - s[i][0] < 3600000)
                continue;
            var dist = Math.abs(s[i][0] - target);
            if (dist < bestDist) {
                best = s[i];
                bestDist = dist;
            }
        }
        if (!best)
            return {
                ok: false
            };
        return {
            ok: true,
            d3: (latest[1] - best[1]) * 10800000 / (latest[0] - best[0])
        };
    }
    /** "+1.2 hPa / 3 h" in the display unit. */
    function _pressureDeltaText(d3, unit) {
        var ratio = parseFloat(String(W.formatPressureValue(1000, unit)).replace(",", ".")) / 1000;
        if (!isFinite(ratio) || ratio <= 0 || ratio > 1.5)
            ratio = 1;
        var v = d3 * ratio;
        return i18n("%1 %2 / 3 h", (v > 0 ? "+" : "") + v.toFixed(ratio < 0.5 ? 2 : 1), i18n(W.pressureUnitLabel(unit)));
    }
    /** Tendency key (barometerGauge.js) -> translated label. */
    function _tendencyText(key) {
        switch (key) {
        case "steady":
            return i18n("Steady");
        case "rising_slowly":
            return i18n("Rising slowly");
        case "rising":
            return i18n("Rising");
        case "rising_quickly":
            return i18n("Rising quickly");
        case "rising_rapidly":
            return i18n("Rising very rapidly");
        case "falling_slowly":
            return i18n("Falling slowly");
        case "falling":
            return i18n("Falling");
        case "falling_quickly":
            return i18n("Falling quickly");
        case "falling_rapidly":
            return i18n("Falling very rapidly");
        }
        return "";
    }
    /** Pressure band key (barometerGauge.js) -> translated label. */
    function _pressureBandText(key) {
        switch (key) {
        case "low":
            return i18n("Low");
        case "high":
            return i18n("High");
        case "normal":
            return i18n("Normal");
        }
        return "";
    }
    /** Optional small line under the band label. */
    function _gaugeSubText(id) {
        var w = weatherRoot;
        if (!w)
            return "";
        if (id === "feelslike" || id === "dewpoint")
            return isNaN(w.temperatureC) ? "" : i18n("Air %1", w.tempValue(w.temperatureC));
        if (id === "uvindex") {
            var pk = _gaugeValue2("uvindex");
            return isNaN(pk) ? "" : i18n("Peak %1", (Math.round(pk * 10) / 10).toString());
        }
        return "";
    }
    property int _currentAlertIndex: 0

    readonly property int regularCardHeight: Plasmoid.configuration.widgetCardsHeightAuto ? 30 : (Plasmoid.configuration.widgetCardsHeight || 30)

    // ── Resolved icons base URL ───────────────────────────────────────────
    readonly property string iconsBaseDir: Qt.resolvedUrl("../icons/")

    // ── Icon resolution via IconResolver ──────────────────────────────────
    /** Returns a saved custom icon name for the given item, or "".
     *  Delegates to ConfigUtils.parseConfigMap() - single source of truth. */
    function getDetailsCustomIcon(itemId) {
        var m = ConfigUtils.parseConfigMap(Plasmoid.configuration.widgetDetailsCustomIcons || "");
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
        void (root._nowTick);
        var stem = Moon.moonPhaseSvgStem(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
        // Always use bundled SVG for moon phase (flat-color for KDE theme)
        var theme = (root.iconTheme === "kde") ? "flat-color" : root.iconTheme;
        return IconResolver.resolveMoonPhase(stem, root.iconSize, root.iconsBaseDir, theme);
    }
    /** Resolves the wind icon - meteocons compass when dynamic, otherwise static.
     *  Preserves the KDE-theme custom icon path from resolveIcon(). */
    function resolveWindIcon() {
        if (root.iconTheme === "kde") {
            var custom = getDetailsCustomIcon("wind");
            if (custom.length > 0)
                return {
                    type: "kde",
                    source: custom,
                    svgFallback: "",
                    isMask: false
                };
        }
        return IconResolver.resolveWindDirection(W.windDirectionCompassStem(root.weatherRoot ? root.weatherRoot.windDirection : NaN), root.iconSize, root.iconsBaseDir, root.iconTheme);
    }
    function accentFor(id) {
        return ({
                feelslike: root.accentWarm,
                humidity: root.accentBlue,
                pressure: root.accentTeal,
                wind: root.accentBlue,
                suntimes: root.accentGold,
                dewpoint: root.accentTeal,
                visibility: root.themeTextColor,
                moonphase: root.accentViolet,
                condition: root.themeTextColor,
                preciprate: root.accentBlue,
                precipsum: root.accentBlue,
                uvindex: root.accentOrange,
                airquality: root.accentTeal,
                pollen: root.accentGold,
                spaceweather: root.accentViolet,
                alerts: root.accentOrange,
                snowcover: root.accentBlue,
                datetime: root.accentGold
            })[id] || root.accentBlue;
    }

    // When the icon theme is symbolic, icons should render monochrome (textColor).
    // Accent colours are only applied for non-mask themes (flat-color, 3d-oxygen, kde).
    function iconColorFor(c) {
        return (root.iconTheme === "symbolic") ? root.themeTextColor : c;
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
                snowcover: i18n("Snow Cover"),
                datetime: i18n("Date / Time")
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
            return weatherRoot.visibilityValue(weatherRoot.visibilityKm);
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
        case "datetime":
            return weatherRoot.formatDateTimeNow(false);
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
    readonly property var detailIds: (Plasmoid.configuration.widgetDetailsOrder || "feelslike;humidity;pressure;wind;suntimes;dewpoint;visibility;moonphase").split(";").map(s => s.trim()).filter(s => s.length > 0)

    // Cached row layout - only rebuilds when detailIds or isList changes,
    // not on every weatherRoot property update.
    readonly property var _cachedRows: buildRows()

    // Per-detail cached values computed at root level.
    // Each card delegate uses _detailValue(id) which reads one of these root properties,
    // so each card only subscribes to its own relevant property - not the full switch.
    readonly property string _dvFeelslike: weatherRoot ? weatherRoot.tempValue(weatherRoot.apparentC) : "--"
    readonly property string _dvHumidity: weatherRoot && !isNaN(weatherRoot.humidityPercent) ? Math.round(weatherRoot.humidityPercent) + "%" : "--"
    readonly property string _dvPressure: weatherRoot ? weatherRoot.pressureValue(weatherRoot.pressureHpa) : "--"
    readonly property string _dvDewpoint: weatherRoot ? weatherRoot.tempValue(weatherRoot.dewPointC) : "--"
    readonly property string _dvVisibility: weatherRoot ? weatherRoot.visibilityValue(weatherRoot.visibilityKm) : "--"
    // _dvCondition depends on isNightTime(), which internally calls new
    // Date() (see suntimesCard._isNight further down for the full
    // writeup) - so, like _isNight, this must be a plain property
    // recomputed on a timer and on weatherRoot signals, NOT a readonly
    // binding, or the day/night wording here goes stale until weatherCode
    // next happens to change value.
    property string _dvCondition: "--"
    readonly property string _dvPreciprate: weatherRoot ? weatherRoot.precipValue(weatherRoot.precipMmh) : "--"
    readonly property string _dvPrecipsum: weatherRoot ? weatherRoot.precipSumText(weatherRoot.precipSumMm) : "--"
    readonly property string _dvUvindex: weatherRoot ? weatherRoot.uvIndexText(weatherRoot.uvIndex) : "--"
    readonly property string _dvAirquality: weatherRoot ? weatherRoot.airQualityText() : "--"
    readonly property string _dvPollen: weatherRoot ? weatherRoot.pollenText() : "--"
    readonly property string _dvSpaceweather: weatherRoot ? weatherRoot.spaceWeatherText() : "--"
    readonly property string _dvAlerts: weatherRoot ? weatherRoot.alertsText() : "--"
    readonly property string _dvSnowcover: weatherRoot ? weatherRoot.snowDepthText(weatherRoot.snowDepthCm) : "--"
    function _updateDvCondition() {
        _dvCondition = weatherRoot ? weatherRoot.weatherCodeToText(weatherRoot.weatherCode, weatherRoot.isNightTime()) : "--";
    }
    Component.onCompleted: _updateDvCondition()
    Timer {
        interval: 60000
        running: root.detailIds.indexOf("condition") >= 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root._updateDvCondition()
    }
    Connections {
        target: root.weatherRoot
        // Same two triggers suntimesCard uses: a full data refresh, and the
        // separate is_day signal path - so "condition" catches up promptly
        // instead of waiting for the 60s timer or for weatherCode to change.
        function onWeatherDataChanged() {
            root._updateDvCondition();
        }
        function onIsDayChanged() {
            root._updateDvCondition();
        }
    }

    property int _dateTimeTick: 0
    Timer {
        interval: 60000
        running: root.detailIds.indexOf("datetime") >= 0
        repeat: true
        onTriggered: root._dateTimeTick++
    }
    readonly property string _dvDatetime: {
        var _ = root._dateTimeTick;
        if (!weatherRoot)
            return "--";
        return weatherRoot.formatDateTimeNow(false);
    }

    function _detailValue(id) {
        switch (id) {
        case "feelslike":
            return _dvFeelslike;
        case "humidity":
            return _dvHumidity;
        case "pressure":
            return _dvPressure;
        case "dewpoint":
            return _dvDewpoint;
        case "visibility":
            return _dvVisibility;
        case "condition":
            return _dvCondition;
        case "preciprate":
            return _dvPreciprate;
        case "precipsum":
            return _dvPrecipsum;
        case "uvindex":
            return _dvUvindex;
        case "airquality":
            return _dvAirquality;
        case "pollen":
            return _dvPollen;
        case "spaceweather":
            return _dvSpaceweather;
        case "alerts":
            return _dvAlerts;
        case "snowcover":
            return _dvSnowcover;
        case "datetime":
            return _dvDatetime;
        default:
            return "--";
        }
    }

    // AQI computed once at root level - not per-delegate - to avoid
    // re-running AQI lookups and building pollutants array N times.
    readonly property var aqiRootDisplays: weatherRoot ? (weatherRoot.aqiData, weatherRoot.airQualityDisplays()) : []
    readonly property var aqiRootPollutants: {
        if (!weatherRoot)
            return [];
        var r = weatherRoot;
        return [
            {
                key: "pm2_5",
                value: r.aqiPm2_5(),
                si: AQI.subIndex("pm2_5", r.aqiPm2_5())
            },
            {
                key: "pm10",
                value: r.aqiPm10(),
                si: AQI.subIndex("pm10", r.aqiPm10())
            },
            {
                key: "no2",
                value: r.aqiNo2(),
                si: AQI.subIndex("no2", r.aqiNo2())
            },
            {
                key: "o3",
                value: r.aqiO3(),
                si: AQI.subIndex("o3", r.aqiO3())
            },
            {
                key: "so2",
                value: r.aqiSo2(),
                si: AQI.subIndex("so2", r.aqiSo2())
            },
            {
                key: "co",
                value: r.aqiCo(),
                si: AQI.subIndex("co", r.aqiCo())
            }
        ];
    }

    // Pollen computed once at root level - not per-delegate - to avoid
    // re-running filter() N times (once per card) on every pollenData write.
    readonly property var pollenEntries: {
        var pd = weatherRoot ? weatherRoot.pollenData : null;
        if (!pd)
            return [];
        return pd.filter(function (p) {
            return !isNaN(p.value);
        });
    }
    readonly property var pollenDominant: {
        var best = null;
        for (var i = 0; i < pollenEntries.length; i++) {
            if (!best || pollenEntries[i].value > best.value)
                best = pollenEntries[i];
        }
        return best;
    }

    // Per-item icon visibility map - delegates to ConfigUtils.parseBoolMap()
    readonly property var iconShowMap: ConfigUtils.parseBoolMap(Plasmoid.configuration.widgetDetailsItemIcons || "")
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
        color: root.themeTextColor
        opacity: 0.4
        font: weatherRoot ? weatherRoot.wf(12, false) : Qt.font({})
    }

    // ── UI when data exists ───────────────────────────────────────────────
    // Flickable instead of ScrollView: styled ScrollViews (e.g. KDE Union) pad the
    // view by scrollbar size, which created a binding loop on bottomPadding (and a
    // crash in plasmawindowed). Attached ScrollBars on a Flickable overlay the
    // content, so there is no style padding to loop on (see _showGap below for the
    // gap that keeps the cards clear of the vertical bar).
    Flickable {
        id: detailsScroll
        anchors.fill: parent
        clip: true
        visible: root.hasData
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: detailsColumn.width
        contentHeight: detailsColumn.height

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        // The vertical scrollbar overlays the right edge, so when the content is
        // taller than the view the cards leave room for it (same 24 px as the
        // History tab); when everything fits they use the full width.
        //
        // Rule: gap <=> contentHeight > height (exactly when the bar is shown).
        // It is set from the handlers below rather than bound, and card heights
        // are computed from the full-width card size (see _refScale), so adding
        // the gap cannot change the content height and flip the rule back.
        // The flip guard is only a safety net: if the state still flip-flops it
        // keeps the gap on for a moment, then re-evaluates.
        readonly property real _scrollBarGap: 24
        property bool _showGap: false
        property int _gapFlips: 0
        property bool _gapLocked: false

        function _updateGap() {
            if (_gapLocked || height <= 0)
                return;
            var want = contentHeight > height;
            if (want === _showGap)
                return;
            if (_gapFlips >= 3) {
                _showGap = true;
                _gapLocked = true;
                _gapFlipReset.restart();
                return;
            }
            _gapFlips++;
            _gapFlipReset.restart();
            _showGap = want;
        }
        Timer {
            id: _gapFlipReset
            interval: 600
            onTriggered: {
                detailsScroll._gapFlips = 0;
                if (detailsScroll._gapLocked) {
                    detailsScroll._gapLocked = false;
                    detailsScroll._updateGap();
                }
            }
        }
        onContentHeightChanged: _updateGap()
        onHeightChanged: _updateGap()
        Component.onCompleted: _updateGap()

        Column {
            id: detailsColumn
            width: Math.max(detailsScroll.width - (detailsScroll._showGap ? detailsScroll._scrollBarGap : 0), 560)
            // Card width as it would be WITHOUT the scrollbar gap: card heights use
            // it so showing/hiding the gap never changes the content height.
            readonly property real _refScale: Math.max(detailsScroll.width, 560) / width
            spacing: root.isList ? 0 : 8
            // Clear the horizontal scrollbar when the content is wider than the view
            // (compares widths only, so it cannot loop with the vertical bar).
            bottomPadding: width > detailsScroll.width ? 16 : 4

            Repeater {
                model: root._cachedRows

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
                            readonly property bool isExpandedCard: card.modelData === "suntimes" || card.modelData === "moonphase" || (card.modelData === "alerts" && (!root.isList || (weatherRoot && weatherRoot.weatherAlerts && weatherRoot.weatherAlerts.length > 1))) || card.modelData === "airquality" || card.modelData === "pollen" || card.modelData === "spaceweather" || (card.modelData === "datetime" && !root.isList) || ((card.modelData === "wind" || card.modelData === "pressure") && !root.isList) || (!root.isList && root._isGaugeId(card.modelData))
                            // suntimes and moonphase: height scales with card width
                            // so the arc grows when the widget is stretched.
                            readonly property int autoHeight: {
                                var arcLikeHeight = Plasmoid.configuration.widgetExpandedCardsHeightAuto ? Math.max(165, Math.round(card.width * detailsColumn._refScale * 0.55)) : Plasmoid.configuration.widgetExpandedCardsHeight;
                                if (card.modelData === "alerts") {
                                    var n = weatherRoot ? (weatherRoot.weatherAlerts || []).length : 0;
                                    if (root.isList && n <= 1)
                                        return 30;
                                    return arcLikeHeight;
                                }
                                if (card.modelData === "airquality")
                                    return arcLikeHeight;
                                if (card.modelData === "pollen") {
                                    return arcLikeHeight;
                                }
                                if (card.modelData === "spaceweather")
                                    return arcLikeHeight;
                                if (card.modelData === "suntimes" || card.modelData === "moonphase" || card.modelData === "datetime")
                                    return arcLikeHeight;
                                if (card.modelData === "wind" || card.modelData === "pressure")
                                    return arcLikeHeight;
                                if (root._isGaugeId(card.modelData) && !root.isList)
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
                                if (card.modelData === "wind")
                                    return root._windExpanded;
                                if (card.modelData === "pressure")
                                    return root._pressureExpanded;
                                if (card.modelData === "alerts")
                                    return root._alertsExpanded;
                                if (card.modelData === "airquality")
                                    return root._aqiExpanded;
                                if (card.modelData === "pollen")
                                    return root._pollenExpanded;
                                if (card.modelData === "spaceweather")
                                    return root._swExpanded;
                                if (card.modelData === "datetime")
                                    return root._dtExpanded;
                                if (root._isGaugeId(card.modelData))
                                    return root._gaugeExpanded[card.modelData] === true;
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
                            // List mode: no card background - just a flat row
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
                                color: Qt.rgba(root.themeTextColor.r, root.themeTextColor.g, root.themeTextColor.b, 0.10)
                            }

                            // Standard item: single row
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8
                                visible: !card.isExpandedCard && card.modelData !== "wind" && !(card.modelData === "alerts" && weatherRoot && weatherRoot.weatherAlerts && weatherRoot.weatherAlerts.length > 0) && card.modelData !== "airquality" && card.modelData !== "pollen" && card.modelData !== "spaceweather" && card.modelData !== "datetime"

                                WeatherIcon {
                                    iconInfo: root.showIconFor(card.modelData) ? root.resolveIcon(card.modelData) : null
                                    iconSize: root.iconSize
                                    iconColor: root.iconColorFor(root.accentFor(card.modelData))
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                // label (dim)
                                Label {
                                    text: root.labelFor(card.modelData) + ":"
                                    color: root.themeTextColor
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
                                    text: root._detailValue(card.modelData)
                                    color: root.valueColor
                                    font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                        bold: true
                                    })
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            // Wind special (icon + speed + arrow) - LIST MODE only.
                            // Cards mode uses the expandable compass card below.
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8
                                visible: card.modelData === "wind" && root.isList

                                WeatherIcon {
                                    iconInfo: root.showIconFor("wind") ? root.resolveWindIcon() : null
                                    iconSize: root.iconSize
                                    iconColor: root.iconColorFor(root.accentFor("wind"))
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Label {
                                    text: root.labelFor("wind") + ":"
                                    color: root.themeTextColor
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
                                            color: root.themeTextColor
                                        }
                                    }
                                }
                            } // RowLayout (standard)

                            // ── Wind compass (cards mode, expandable) ─────────────
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "wind" && !root.isList
                                sourceComponent: Item {
                                    id: windCard
                                    anchors.fill: parent
                                    clip: true

                                    // Collapsed header - styled like a standard row
                                    RowLayout {
                                        id: windHeader
                                        visible: !card._isArcExpanded
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        height: card._isArcExpanded ? 0 : root.regularCardHeight
                                        spacing: 8

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("wind") ? root.resolveWindIcon() : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("wind"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("wind") + ":"
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                            elide: Text.ElideRight
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: root.weatherRoot ? root.weatherRoot.windValue(root.weatherRoot.windKmh) : "--"
                                            color: root.valueColor
                                            font: root.weatherRoot ? root.weatherRoot.wf(13, true) : Qt.font({
                                                bold: true
                                            })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            visible: root.weatherRoot && !isNaN(root.weatherRoot.windDirection)
                                            implicitWidth: root.iconSize
                                            implicitHeight: root.iconSize
                                            Layout.alignment: Qt.AlignVCenter
                                            Text {
                                                anchors.centerIn: parent
                                                text: root.weatherRoot ? W.windDirectionGlyph(root.weatherRoot.windDirection) : ""
                                                font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                font.pixelSize: root.iconSize
                                                color: root.themeTextColor
                                            }
                                        }
                                        Kirigami.Icon {
                                            source: "arrow-down"
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            opacity: 0.45
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.top: windHeader.top
                                        anchors.left: windHeader.left
                                        anchors.right: windHeader.right
                                        height: windHeader.height
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._windExpanded = !card._isArcExpanded
                                    }

                                    readonly property real wKmh: root.weatherRoot ? root.weatherRoot.windKmh : NaN
                                    readonly property real wDir: root.weatherRoot ? root.weatherRoot.windDirection : NaN
                                    readonly property var winfo: WindGauge.info(wKmh, root.isDark)

                                    // Expanded: compass on the left, speed / Beaufort band / bearing
                                    // on the right, collapse button top-right (shared ExpandedGauge).
                                    ExpandedGauge {
                                        visible: card._isArcExpanded
                                        anchors.fill: parent
                                        weatherRoot: root.weatherRoot
                                        title: root.labelFor("wind")
                                        layoutMode: "side"
                                        iconInfo: root.showIconFor("wind") ? root.resolveWindIcon() : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(windCard.winfo.color)
                                        valueText: root.weatherRoot ? root.weatherRoot.windValue(windCard.wKmh) : "--"
                                        valueColor: root.valueColor
                                        bandText: root._windBandText(windCard.winfo.key)
                                        bandColor: windCard.winfo.color
                                        subText: isNaN(windCard.wDir) ? "" : (WindGauge.cardinal(windCard.wDir) + " " + Math.round(windCard.wDir) + "°")
                                        subColor: root.themeTextColor
                                        paintKey: windCard.wKmh + "|" + windCard.wDir + "|" + root.isDark + "|" + root.themeTextColor
                                        onDraw: function (ctx, w, h) {
                                            WindGauge.draw(ctx, w, h, {
                                                v: windCard.wKmh,
                                                dir: windCard.wDir,
                                                isDark: root.isDark,
                                                text: String(root.themeTextColor)
                                            });
                                        }
                                        onCollapseRequested: root._windExpanded = false
                                    }
                                }
                            }

                            // ── Pressure gauge (cards mode, expandable) ───────────
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "pressure" && !root.isList
                                sourceComponent: Item {
                                    id: pressureCard
                                    anchors.fill: parent
                                    clip: true

                                    // Collapsed header
                                    RowLayout {
                                        id: pressureHeader
                                        visible: !card._isArcExpanded
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        height: card._isArcExpanded ? 0 : root.regularCardHeight
                                        spacing: 8

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("pressure") ? root.resolveIcon("pressure") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("pressure"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("pressure") + ":"
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                            elide: Text.ElideRight
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: root.weatherRoot ? root.weatherRoot.pressureValue(root.weatherRoot.pressureHpa) : "--"
                                            color: root.valueColor
                                            font: root.weatherRoot ? root.weatherRoot.wf(13, true) : Qt.font({
                                                bold: true
                                            })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Kirigami.Icon {
                                            source: "arrow-down"
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            opacity: 0.45
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.top: pressureHeader.top
                                        anchors.left: pressureHeader.left
                                        anchors.right: pressureHeader.right
                                        height: pressureHeader.height
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._pressureExpanded = !card._isArcExpanded
                                    }

                                    readonly property real hpa: root.weatherRoot ? root.weatherRoot.pressureHpa : NaN
                                    readonly property string pUnit: root.weatherRoot ? root.weatherRoot._pressureUnit() : "hPa"
                                    readonly property var pinfo: BarometerGauge.info(hpa, root.isDark)
                                    // Tendency: change over the last 3 h and where the pressure was then
                                    readonly property var tend: root._pressureTendency()
                                    readonly property var tendInfo: tend.ok ? BarometerGauge.tendency(tend.d3) : ({
                                            key: "",
                                            dir: 0
                                        })
                                    readonly property real prevHpa: (tend.ok && !isNaN(hpa)) ? hpa - tend.d3 : NaN
                                    // Tick labels in the display unit (hPa / inHg / mmHg ...)
                                    readonly property var tickLabels: {
                                        var out = [];
                                        for (var i = 0; i < BarometerGauge.TICKS.length; i++)
                                            out.push(W.formatPressureValue(BarometerGauge.TICKS[i], pressureCard.pUnit));
                                        return out;
                                    }

                                    // Expanded: barometer dial + overlay + collapse button
                                    ExpandedGauge {
                                        visible: card._isArcExpanded
                                        anchors.fill: parent
                                        weatherRoot: root.weatherRoot
                                        title: root.labelFor("pressure")
                                        iconInfo: root.showIconFor("pressure") ? root.resolveIcon("pressure") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(pressureCard.pinfo.color)
                                        valueText: root.weatherRoot ? root.weatherRoot.pressureValue(pressureCard.hpa) : "--"
                                        valueColor: root.valueColor
                                        bandText: root._pressureBandText(pressureCard.pinfo.key)
                                        bandColor: pressureCard.pinfo.color
                                        subText: pressureCard.tend.ok ? (root._tendencyText(pressureCard.tendInfo.key) + " \u00B7 " + root._pressureDeltaText(pressureCard.tend.d3, pressureCard.pUnit)) : i18n("Tendency: collecting data")
                                        subColor: pressureCard.tend.ok ? BarometerGauge.tendencyColor(pressureCard.tendInfo.dir, root.isDark) : root.themeTextColor
                                        infoTitle: i18n("Pressure tendency")
                                        infoText: pressureCard.tend.ok ? i18n("Change over the last 3 hours, worked out from the readings the widget has collected. The open ring on the dial marks the pressure 3 hours ago.") : i18n("The widget collects pressure readings as it updates; about an hour of readings is needed to work out the trend.")
                                        infoWidth: 280
                                        paintKey: pressureCard.hpa + "|" + pressureCard.prevHpa + "|" + pressureCard.pUnit + "|" + root.isDark + "|" + root.themeTextColor
                                        onDraw: function (ctx, w, h) {
                                            BarometerGauge.draw(ctx, w, h, {
                                                v: pressureCard.hpa,
                                                isDark: root.isDark,
                                                text: String(root.themeTextColor),
                                                labels: pressureCard.tickLabels,
                                                prev: pressureCard.prevHpa,
                                                trendDir: pressureCard.tendInfo.dir
                                            });
                                        }
                                        onCollapseRequested: root._pressureExpanded = false
                                    }
                                }
                            }

                            // ── Expandable gauges (cards mode) ────────────────────
                            // Feels like / humidity / dew point / visibility / precipitation /
                            // precipitation sum / UV index / snow cover. One Loader, built only
                            // for these card types (see the pressure note above). Collapsed it
                            // looks like the regular row plus a chevron; expanded it hosts the
                            // shared ExpandedGauge, drawn by js/<name>Gauge.js.
                            Loader {
                                anchors.fill: parent
                                active: !root.isList && root._isGaugeId(card.modelData)
                                sourceComponent: Item {
                                    id: gaugeCard
                                    anchors.fill: parent
                                    clip: true

                                    readonly property string gid: card.modelData
                                    readonly property real gv: root._gaugeValue(gid)
                                    readonly property real gv2: root._gaugeValue2(gid)
                                    readonly property var ginfo: root._gaugeInfo(gid, gv)
                                    readonly property bool gImperial: root.weatherRoot ? root.weatherRoot._isImperial() : false
                                    readonly property string gTempUnit: root.weatherRoot ? root.weatherRoot._tempUnit() : "C"

                                    // Collapsed header: same as a regular row + chevron
                                    RowLayout {
                                        id: gaugeHeader
                                        visible: !card._isArcExpanded
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        height: card._isArcExpanded ? 0 : root.regularCardHeight
                                        spacing: 8

                                        WeatherIcon {
                                            iconInfo: root.showIconFor(gaugeCard.gid) ? root.resolveIcon(gaugeCard.gid) : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor(gaugeCard.gid))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor(gaugeCard.gid) + ":"
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                            elide: Text.ElideRight
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: root._detailValue(gaugeCard.gid)
                                            color: root.valueColor
                                            font: root.weatherRoot ? root.weatherRoot.wf(13, true) : Qt.font({
                                                bold: true
                                            })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Kirigami.Icon {
                                            source: "arrow-down"
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            opacity: 0.45
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                    MouseArea {
                                        visible: !card._isArcExpanded
                                        anchors.top: gaugeHeader.top
                                        anchors.left: gaugeHeader.left
                                        anchors.right: gaugeHeader.right
                                        height: gaugeHeader.height
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._setGaugeExpanded(gaugeCard.gid, true)
                                    }

                                    // Expanded: dial + overlay + collapse button
                                    ExpandedGauge {
                                        visible: card._isArcExpanded
                                        anchors.fill: parent
                                        weatherRoot: root.weatherRoot
                                        title: root.labelFor(gaugeCard.gid)
                                        iconInfo: root.showIconFor(gaugeCard.gid) ? root.resolveIcon(gaugeCard.gid) : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(gaugeCard.ginfo.color)
                                        valueText: root._detailValue(gaugeCard.gid)
                                        valueColor: root.valueColor
                                        bandText: root._gaugeBandText(gaugeCard.gid, gaugeCard.ginfo.key)
                                        bandColor: gaugeCard.ginfo.color
                                        subText: root._gaugeSubText(gaugeCard.gid)
                                        subColor: root.themeTextColor
                                        paintKey: gaugeCard.gid + "|" + gaugeCard.gv + "|" + gaugeCard.gv2 + "|" + root.isDark + "|" + gaugeCard.gImperial + "|" + gaugeCard.gTempUnit + "|" + root.themeTextColor
                                        onDraw: function (ctx, w, h) {
                                            root._gaugeDraw(gaugeCard.gid, ctx, w, h, {
                                                v: gaugeCard.gv,
                                                v2: gaugeCard.gv2,
                                                isDark: root.isDark,
                                                text: String(root.themeTextColor),
                                                imperial: gaugeCard.gImperial,
                                                tempUnit: gaugeCard.gTempUnit
                                            });
                                        }
                                        onCollapseRequested: root._setGaugeExpanded(gaugeCard.gid, false)
                                    }
                                }
                            }

                            // ── Air Quality display ──────────────────────────────────
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "airquality"
                                sourceComponent: Item {
                                    id: aqiCard
                                    anchors.fill: parent
                                    clip: true

                                    // Computed once at root level to avoid per-delegate re-evaluation
                                    readonly property var aqiDisplays: root.aqiRootDisplays
                                    readonly property var _visibleDisplays: aqiCard.aqiDisplays.filter(function (d) {
                                        return !isNaN(d.value);
                                    })
                                    readonly property var pollutants: root.aqiRootPollutants

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
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }

                                        // One colored badge per active standard (1-3, from the
                                        // Misc tab's "show standards" switches; exactly 1 when
                                        // none of them are on).
                                        Row {
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 10

                                            Label {
                                                visible: aqiCard._visibleDisplays.length === 0
                                                text: "--"
                                                color: root.valueColor
                                                font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                    bold: true
                                                })
                                            }

                                            Repeater {
                                                model: aqiCard._visibleDisplays
                                                delegate: Row {
                                                    spacing: 4
                                                    Rectangle {
                                                        width: 10
                                                        height: 10
                                                        radius: 2
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: modelData.band ? root.bandTextColor(modelData.band) : "transparent"
                                                    }
                                                    Label {
                                                        text: i18n(modelData.standardLabel) + ": " + Math.round(modelData.value)
                                                        color: modelData.band ? root.bandTextColor(modelData.band) : root.valueColor
                                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                            bold: true
                                                        })
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }

                                        // Expand chevron
                                        Item {
                                            visible: !root.isList && root._anyAqiVisible()
                                            implicitWidth: 14
                                            implicitHeight: 14
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

                                    // ── Expanded view: one dial per pollutant, switched with < > ──
                                    // Pages = the pollutants enabled in the settings. The scale (position,
                                    // band, ticks) comes from airQuality.js; aqiGauge.js only draws it.
                                    readonly property var pages: aqiCard.pollutants.filter(function (p) {
                                        return root._aqiItemVisible(p.key);
                                    })
                                    property int page: 0
                                    readonly property int safePage: Math.min(Math.max(0, page), Math.max(0, pages.length - 1))
                                    readonly property var cur: pages.length > 0 ? pages[safePage] : null
                                    readonly property bool curHasSi: cur !== null && !isNaN(cur.si)
                                    readonly property var curBand: curHasSi ? AQI.bandForSubIndex(cur.si) : null
                                    readonly property real curT: curHasSi ? AQI.scalePercent(cur.si, 100) / 100 : NaN
                                    readonly property var scaleTicks: {
                                        var vals = [0, 25, 50, 75, 100];
                                        var out = [];
                                        for (var i = 0; i < vals.length; i++)
                                            out.push({
                                                t: AQI.scalePercent(vals[i], 100) / 100,
                                                label: String(vals[i])
                                            });
                                        return out;
                                    }

                                    function pollutantName(key) {
                                        switch (key) {
                                        case "pm2_5":
                                            return i18n("Particulate Matter (PM2.5)");
                                        case "pm10":
                                            return i18n("Particulate Matter (PM10)");
                                        case "no2":
                                            return i18n("Nitrogen Dioxide (NO₂)");
                                        case "o3":
                                            return i18n("Ozone (O₃)");
                                        case "so2":
                                            return i18n("Sulfur Dioxide (SO₂)");
                                        case "co":
                                            return i18n("Carbon Monoxide (CO)");
                                        default:
                                            return key;
                                        }
                                    }

                                    ExpandedGauge {
                                        visible: card._isArcExpanded
                                        anchors.fill: parent
                                        weatherRoot: root.weatherRoot
                                        title: root.labelFor("airquality")
                                        iconInfo: root.showIconFor("airquality") ? root.resolveIcon("airquality") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(aqiCard.curBand ? root.bandTextColor(aqiCard.curBand) : root.accentFor("airquality"))
                                        valueText: (aqiCard.cur && !isNaN(aqiCard.cur.value)) ? (aqiCard.cur.value.toFixed(1) + " " + i18n(AQI.unitFor(aqiCard.cur.key))) : "--"
                                        valueColor: root.valueColor
                                        bandText: aqiCard.curBand ? (i18n(aqiCard.curBand.shortLabel) + " · " + Math.round(aqiCard.cur.si)) : ""
                                        bandColor: root.bandTextColor(aqiCard.curBand)
                                        subText: aqiCard.cur ? aqiCard.pollutantName(aqiCard.cur.key) : ""
                                        subColor: root.themeTextColor
                                        pageCount: aqiCard.pages.length
                                        pageIndex: aqiCard.safePage
                                        onPreviousRequested: aqiCard.page = aqiCard.safePage - 1
                                        onNextRequested: aqiCard.page = aqiCard.safePage + 1
                                        onPageSelected: function (i) {
                                            aqiCard.page = i;
                                        }
                                        infoText: aqiCard.curBand ? i18n(aqiCard.curBand.description) : ""
                                        infoWidth: 260
                                        paintKey: (aqiCard.cur ? aqiCard.cur.key : "") + "|" + aqiCard.curT + "|" + (aqiCard.curHasSi ? aqiCard.cur.si : "") + "|" + root.isDark + "|" + root.themeTextColor
                                        onDraw: function (ctx, w, h) {
                                            AqiGauge.draw(ctx, w, h, {
                                                t: aqiCard.curT,
                                                si: aqiCard.curHasSi ? aqiCard.cur.si : NaN,
                                                bandColor: aqiCard.curBand ? aqiCard.curBand.color : "#4CAF50",
                                                key: aqiCard.cur ? aqiCard.cur.key : "",
                                                ticks: aqiCard.scaleTicks,
                                                isDark: root.isDark,
                                                text: String(root.themeTextColor)
                                            });
                                        }
                                        onCollapseRequested: root._aqiExpanded = false
                                    }
                                }
                            }

                            // ── Pollen display ──────────────────────────────────────
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "pollen"
                                sourceComponent: Item {
                                    id: pollenCard
                                    anchors.fill: parent
                                    clip: true

                                    // Computed once at root level to avoid per-delegate re-evaluation
                                    readonly property var entries: root.pollenEntries
                                    readonly property var dominant: root.pollenDominant

                                    function pollenName(key) {
                                        switch (key) {
                                        case "alder":
                                            return i18n("Alder");
                                        case "birch":
                                            return i18n("Birch");
                                        case "grass":
                                            return i18n("Grass");
                                        case "mugwort":
                                            return i18n("Mugwort");
                                        case "olive":
                                            return i18n("Olive");
                                        case "ragweed":
                                            return i18n("Ragweed");
                                        default:
                                            return key;
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
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }

                                        // Dominant pollen info
                                        Rectangle {
                                            visible: pollenCard.dominant !== null
                                            width: 10
                                            height: 10
                                            radius: 2
                                            color: pollenCard.dominant ? Pollen.colorForValue(pollenCard.dominant.value) : "transparent"
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: {
                                                if (!pollenCard.dominant)
                                                    return "--";
                                                var d = pollenCard.dominant;
                                                return pollenCard.pollenName(d.key) + ": " + i18n(Pollen.labelForValue(d.value)) + " (" + d.value.toFixed(1) + " " + i18n("grains/m³") + ")";
                                            }
                                            color: pollenCard.dominant ? root.bandTextColor(Pollen.bandForValue(pollenCard.dominant.value)) : root.valueColor
                                            font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                bold: true
                                            })
                                            elide: Text.ElideRight
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        // Expand chevron
                                        Item {
                                            visible: !root.isList && root._anyPollenVisible()
                                            implicitWidth: 14
                                            implicitHeight: 14
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

                                    // ── Expanded view: one dial per pollen type, switched with < > ──
                                    // Pages = the types enabled in the settings that have a reading.
                                    // The scale (position, colour zones, ticks) comes from pollen.js.
                                    readonly property var pages: pollenCard.entries.filter(function (e) {
                                        return root._pollenItemVisible(e.key);
                                    })
                                    property int page: 0
                                    readonly property int safePage: Math.min(Math.max(0, page), Math.max(0, pages.length - 1))
                                    readonly property var cur: pages.length > 0 ? pages[safePage] : null
                                    readonly property var curBand: cur ? Pollen.bandForValue(cur.value) : null
                                    readonly property real curT: cur ? Pollen.scalePercent(cur.value) / 100 : NaN
                                    readonly property var scaleZones: {
                                        function p(v) {
                                            return Pollen.scalePercent(v) / 100;
                                        }
                                        return [
                                            {
                                                from: 0,
                                                to: p(2.5),
                                                color: String(Qt.color(Pollen.colorForValue(1.2)))
                                            },
                                            {
                                                from: p(2.5),
                                                to: p(4.9),
                                                color: String(Qt.color(Pollen.colorForValue(3.7)))
                                            },
                                            {
                                                from: p(4.9),
                                                to: p(7.3),
                                                color: String(Qt.color(Pollen.colorForValue(6.1)))
                                            },
                                            {
                                                from: p(7.3),
                                                to: 1,
                                                color: String(Qt.color(Pollen.colorForValue(9.6)))
                                            }
                                        ];
                                    }
                                    readonly property var scaleTicks: {
                                        var vals = [0, 2.5, 4.9, 7.3, 12];
                                        var out = [];
                                        for (var i = 0; i < vals.length; i++)
                                            out.push({
                                                t: Pollen.scalePercent(vals[i]) / 100,
                                                label: String(vals[i])
                                            });
                                        return out;
                                    }

                                    ExpandedGauge {
                                        visible: card._isArcExpanded
                                        anchors.fill: parent
                                        weatherRoot: root.weatherRoot
                                        title: root.labelFor("pollen")
                                        iconInfo: root.showIconFor("pollen") ? root.resolveIcon("pollen") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(pollenCard.curBand ? root.bandTextColor(pollenCard.curBand) : root.accentFor("pollen"))
                                        valueText: pollenCard.cur ? (pollenCard.cur.value.toFixed(1) + " " + i18n("grains/m³")) : "--"
                                        valueColor: root.valueColor
                                        bandText: pollenCard.curBand ? i18n(pollenCard.curBand.label) : ""
                                        bandColor: root.bandTextColor(pollenCard.curBand)
                                        subText: pollenCard.cur ? pollenCard.pollenName(pollenCard.cur.key) : ""
                                        subColor: root.themeTextColor
                                        pageCount: pollenCard.pages.length
                                        pageIndex: pollenCard.safePage
                                        onPreviousRequested: pollenCard.page = pollenCard.safePage - 1
                                        onNextRequested: pollenCard.page = pollenCard.safePage + 1
                                        onPageSelected: function (i) {
                                            pollenCard.page = i;
                                        }
                                        infoText: pollenCard.curBand ? i18n(pollenCard.curBand.description) : ""
                                        infoWidth: 260
                                        paintKey: (pollenCard.cur ? pollenCard.cur.key : "") + "|" + pollenCard.curT + "|" + root.isDark + "|" + root.themeTextColor
                                        onDraw: function (ctx, w, h) {
                                            PollenGauge.draw(ctx, w, h, {
                                                t: pollenCard.curT,
                                                bandColor: pollenCard.curBand ? pollenCard.curBand.color : "#8BC34A",
                                                zones: pollenCard.scaleZones,
                                                key: pollenCard.cur ? pollenCard.cur.key : "",
                                                ticks: pollenCard.scaleTicks,
                                                isDark: root.isDark,
                                                text: String(root.themeTextColor)
                                            });
                                        }
                                        onCollapseRequested: root._pollenExpanded = false
                                    }

                                    // No reading at all for this location
                                    Label {
                                        visible: card._isArcExpanded && pollenCard.entries.length === 0
                                        anchors.top: parent.top
                                        anchors.topMargin: 12
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 90
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        text: i18n("Pollen data not available for this location.")
                                        color: root.themeDisabledTextColor
                                        font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                    }
                                }
                            }

                            // ── Space Weather display ────────────────────────────────
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "spaceweather"
                                sourceComponent: Item {
                                    id: swCard
                                    anchors.fill: parent
                                    clip: true

                                    readonly property var sw: weatherRoot ? weatherRoot.spaceWeather : null
                                    readonly property real kp: sw && !isNaN(sw.kp) ? sw.kp : NaN
                                    readonly property string gScale: sw ? (sw.gScale || "G0") : "G0"
                                    readonly property color gColor: Qt.color((root.isDark ? SW.gScaleColor(gScale) : SW.gScaleTextColor(gScale)) || "#4CAF50")
                                    readonly property color kpColor: kp >= 5 ? gColor : (kp >= 3 ? Qt.color(root.isDark ? "#FFEB3B" : "#5D4800") : Qt.color(root.isDark ? "#4CAF50" : "#1B5E20"))
                                    // Vivid variants for progress bar fills (always use bright colors)
                                    readonly property color gColorVivid: Qt.color(SW.gScaleColor(gScale) || "#4CAF50")
                                    readonly property color kpColorVivid: kp >= 5 ? gColorVivid : (kp >= 3 ? Qt.color("#FFEB3B") : Qt.color("#4CAF50"))

                                    // ── Collapsed header ─────────────────────────────────
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
                                            iconInfo: root.showIconFor("spaceweather") ? root.resolveIcon("spaceweather") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("spaceweather"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("spaceweather") + ":"
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: weatherRoot ? weatherRoot.spaceWeatherText() : "--"
                                            color: swCard.kpColor
                                            font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                bold: true
                                            })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            visible: !root.isList && root._anySwVisible()
                                            implicitWidth: 14
                                            implicitHeight: 14
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

                                    // ── Expanded view: one dial per metric, switched with < > ──
                                    // Pages = the metrics enabled in the settings. The scales are
                                    // worked out here from spaceWeather.js; spaceWeatherGauge.js draws.
                                    readonly property var pages: ["gscale", "kp", "solarwind", "aurora", "bz", "xray"].filter(function (k) {
                                        return root._swItemVisible(k);
                                    })
                                    property int page: 0
                                    readonly property int safePage: Math.min(Math.max(0, page), Math.max(0, pages.length - 1))
                                    readonly property string curKey: pages.length > 0 ? pages[safePage] : ""

                                    readonly property real solarWind: sw && !isNaN(sw.solarWind) ? sw.solarWind : NaN
                                    readonly property real auroraPct: sw && !isNaN(sw.auroraPercent) ? sw.auroraPercent : NaN
                                    readonly property real bzValue: sw && !isNaN(sw.bz) ? sw.bz : NaN
                                    readonly property string xCls: sw ? (sw.xrayClass || "--") : "--"
                                    readonly property string xFull: (sw && sw.xrayClassFull && sw.xrayClassFull !== "--") ? sw.xrayClassFull : "--"

                                    function _col(c) {
                                        return String(Qt.color(c));
                                    }
                                    function _zones(spec) {
                                        var out = [], from = 0;
                                        for (var i = 0; i < spec.length; i++) {
                                            out.push({
                                                from: from,
                                                to: spec[i][0],
                                                color: spec[i][1]
                                            });
                                            from = spec[i][0];
                                        }
                                        return out;
                                    }
                                    function _ticks(spec) {
                                        var out = [];
                                        for (var i = 0; i < spec.length; i++)
                                            out.push({
                                                t: spec[i][0],
                                                label: spec[i][1]
                                            });
                                        return out;
                                    }
                                    // Everything one page needs: reading position, zones, ticks, texts, colours
                                    function _pageData(key) {
                                        var dark = root.isDark;
                                        var d = {
                                            kind: key,
                                            t: NaN,
                                            valueText: "--",
                                            bandText: "",
                                            title: "",
                                            color: root.themeTextColor,
                                            vivid: "#8E9BAE",
                                            zones: [],
                                            ticks: [],
                                            south: false,
                                            hint: ""
                                        };
                                        var i;
                                        if (key === "gscale") {
                                            var n = parseInt(String(gScale).substring(1), 10);
                                            if (isNaN(n))
                                                n = 0;
                                            n = Math.min(5, Math.max(0, n));
                                            var gz = [], gt = [];
                                            for (i = 0; i <= 5; i++) {
                                                gz.push([(i + 1) / 6, _col(SW.gScaleColor("G" + i) || "#4CAF50")]);
                                                gt.push([(i + 0.5) / 6, "G" + i]);
                                            }
                                            d.zones = _zones(gz);
                                            d.ticks = _ticks(gt);
                                            d.t = (n + 0.5) / 6;
                                            d.valueText = gScale;
                                            d.bandText = i18n(SW.gScaleDescription(gScale));
                                            d.title = i18n("Geomagnetic Storm");
                                            d.color = gColor;
                                            d.vivid = _col(gColorVivid);
                                        } else if (key === "kp") {
                                            d.zones = _zones([[3 / 9, "#4CAF50"], [5 / 9, "#FFEB3B"], [6 / 9, _col(SW.gScaleColor("G1"))], [7 / 9, _col(SW.gScaleColor("G2"))], [8 / 9, _col(SW.gScaleColor("G3"))], [1, _col(SW.gScaleColor("G4"))]]);
                                            d.ticks = _ticks([[0, "0"], [3 / 9, "3"], [5 / 9, "5"], [7 / 9, "7"], [1, "9"]]);
                                            d.t = isNaN(kp) ? NaN : kp / 9;
                                            d.valueText = isNaN(kp) ? "--" : kp.toFixed(1);
                                            d.bandText = isNaN(kp) ? "" : i18n(SW.kpTextLevel(kp));
                                            d.title = i18n("Kp Index");
                                            d.color = kpColor;
                                            d.vivid = _col(kpColorVivid);
                                        } else if (key === "solarwind") {
                                            var v = solarWind;
                                            d.zones = _zones([[0.5, "#4CAF50"], [0.7, "#FF9800"], [1, "#D32F2F"]]);
                                            d.ticks = _ticks([[0, "0"], [0.3, "300"], [0.5, "500"], [0.7, "700"], [1, "1000"]]);
                                            d.t = isNaN(v) ? NaN : v / 1000;
                                            d.valueText = isNaN(v) ? "--" : Math.round(v) + " " + i18n("km/s");
                                            d.bandText = isNaN(v) ? "" : i18n(SW.solarWindTextLevel(v));
                                            d.title = i18n("Solar Wind");
                                            var wv = isNaN(v) ? 0 : v;
                                            d.color = wv < 500 ? (dark ? "#4CAF50" : "#1B5E20") : (wv < 700 ? (dark ? "#FF9800" : "#7A3500") : (dark ? "#D32F2F" : "#7F0000"));
                                            d.vivid = wv < 500 ? "#4CAF50" : (wv < 700 ? "#FF9800" : "#D32F2F");
                                        } else if (key === "aurora") {
                                            var a = auroraPct;
                                            d.zones = _zones([[0.1, "#4CAF50"], [0.3, "#FFEB3B"], [0.7, "#FF9800"], [1, "#D32F2F"]]);
                                            d.ticks = _ticks([[0, "0"], [0.1, "10"], [0.3, "30"], [0.7, "70"], [1, "100"]]);
                                            d.t = isNaN(a) ? NaN : a / 100;
                                            d.valueText = isNaN(a) ? "--" : Math.round(a) + "%";
                                            d.bandText = isNaN(a) ? "" : i18n(SW.auroraTextLevel(a));
                                            d.title = i18n("Aurora Visibility");
                                            var av = isNaN(a) ? 0 : a;
                                            d.color = av < 10 ? (dark ? "#4CAF50" : "#1B5E20") : (av < 30 ? (dark ? "#FFEB3B" : "#5D4800") : (av < 70 ? (dark ? "#FF9800" : "#7A3500") : (dark ? "#D32F2F" : "#7F0000")));
                                            d.vivid = av < 10 ? "#4CAF50" : (av < 30 ? "#FFEB3B" : (av < 70 ? "#FF9800" : "#D32F2F"));
                                        } else if (key === "bz") {
                                            var b = bzValue;
                                            var active = !isNaN(b) && b < 0;
                                            d.zones = _zones([[0.25, "#D32F2F"], [0.5, "#FF9800"], [1, _col(root.accentViolet)]]);
                                            d.ticks = _ticks([[0, "-20"], [0.25, "-10"], [0.5, "0"], [0.75, "+10"], [1, "+20"]]);
                                            d.t = isNaN(b) ? NaN : Math.min(1, Math.max(0, (b + 20) / 40));
                                            d.valueText = isNaN(b) ? "--" : (b >= 0 ? "+" : "") + b.toFixed(1) + " nT";
                                            d.bandText = isNaN(b) ? "" : (active ? i18n("Active") : i18n("Quiet"));
                                            d.title = i18n("Bz (Magnetic Field)");
                                            d.color = active ? (dark ? "#FF9800" : "#7A3500") : root.accentViolet;
                                            d.vivid = active ? "#FF9800" : _col(root.accentViolet);
                                            d.south = active;
                                            d.hint = i18n("A southward field (negative Bz) lets the solar wind couple with Earth's magnetic field.");
                                        } else if (key === "xray") {
                                            var idx = ["A", "B", "C", "M", "X"].indexOf(xCls);
                                            var cc = ["A", "B", "C", "M", "X"];
                                            var xz = [], xt = [];
                                            for (i = 0; i < 5; i++) {
                                                xz.push([(i + 1) / 5, _col(SW.xrayClassColor(cc[i]))]);
                                                xt.push([(i + 0.5) / 5, cc[i]]);
                                            }
                                            d.zones = _zones(xz);
                                            d.ticks = _ticks(xt);
                                            if (idx >= 0) {
                                                // each class is a decade: C1.0 .. C9.9 fills one fifth of the scale
                                                var m = /^[ABCMX]\s*([0-9]+(\.[0-9]+)?)/.exec(xFull);
                                                var frac = m ? Math.min(0.999, Math.max(0, Math.log(parseFloat(m[1])) / Math.LN10)) : 0.5;
                                                d.t = (idx + frac) / 5;
                                            }
                                            d.valueText = xFull;
                                            d.bandText = idx < 0 ? "" : (idx <= 1 ? i18n("Quiet") : (idx === 2 ? i18n("Minor") : i18n("Flare Warning")));
                                            d.title = i18n("X-ray Flare Class");
                                            d.color = Qt.color(dark ? SW.xrayClassColor(xCls) : SW.xrayClassTextColor(xCls));
                                            d.vivid = _col(SW.xrayClassColor(xCls));
                                        }
                                        return d;
                                    }
                                    readonly property var pd: _pageData(curKey)

                                    ExpandedGauge {
                                        visible: card._isArcExpanded
                                        anchors.fill: parent
                                        weatherRoot: root.weatherRoot
                                        title: root.labelFor("spaceweather")
                                        iconInfo: root.showIconFor("spaceweather") ? root.resolveIcon("spaceweather") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(root.accentFor("spaceweather"))
                                        valueText: swCard.pd.valueText
                                        valueColor: root.valueColor
                                        bandText: swCard.pd.bandText
                                        bandColor: swCard.pd.color
                                        subText: swCard.pd.title
                                        subColor: root.themeTextColor
                                        pageCount: swCard.pages.length
                                        pageIndex: swCard.safePage
                                        onPreviousRequested: swCard.page = swCard.safePage - 1
                                        onNextRequested: swCard.page = swCard.safePage + 1
                                        onPageSelected: function (i) {
                                            swCard.page = i;
                                        }
                                        infoText: (swCard.pd.hint.length > 0 ? swCard.pd.hint + "<br>" : "") + i18n("Provider:") + " NOAA SWPC (swpc.noaa.gov)"
                                        infoWidth: 280
                                        paintKey: swCard.curKey + "|" + swCard.pd.t + "|" + swCard.pd.vivid + "|" + swCard.pd.south + "|" + root.isDark + "|" + root.themeTextColor
                                        onDraw: function (ctx, w, h) {
                                            SwGauge.draw(ctx, w, h, {
                                                kind: swCard.curKey,
                                                t: swCard.pd.t,
                                                bandColor: swCard.pd.vivid,
                                                zones: swCard.pd.zones,
                                                ticks: swCard.pd.ticks,
                                                south: swCard.pd.south,
                                                isDark: root.isDark,
                                                text: String(root.themeTextColor)
                                            });
                                        }
                                        onCollapseRequested: root._swExpanded = false
                                    }
                                }
                            }

                            // ── Alerts display ──────────────────────────────────────
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "alerts" && weatherRoot && (!root.isList || (weatherRoot.weatherAlerts && weatherRoot.weatherAlerts.length > 0))
                                sourceComponent: Item {
                                    id: alertsCard
                                    anchors.fill: parent
                                    clip: true

                                    readonly property var alerts: weatherRoot ? (weatherRoot.weatherAlerts || []) : []
                                    readonly property bool hasMultiple: alerts.length > 1
                                    // No alerts at all: a compact "None" row that expands to the "all clear" view
                                    readonly property bool clear: alerts.length === 0

                                    // todayAlerts/activeAlerts/futureAlerts compare each alert's
                                    // onset/expires against new Date() ("now"). new Date() is not a
                                    // QML dependency, so as readonly bindings these only re-evaluate
                                    // when `alerts` itself changes (a fresh API fetch) - not when
                                    // wall-clock time actually crosses an alert's onset or expiry.
                                    // Same bug as suntimesCard._isNight; same fix: plain properties,
                                    // recomputed on a timer and whenever `alerts` changes.
                                    property var todayAlerts: []
                                    property var activeAlerts: []
                                    property var futureAlerts: []
                                    readonly property int safeIndex: Math.min(Math.max(0, root._currentAlertIndex), Math.max(0, todayAlerts.length - 1))
                                    readonly property bool todayHasMultiple: todayAlerts.length > 1

                                    // All alerts sorted by onset date (for expanded view).
                                    // Only depends on `alerts` (no "now" comparison), so this one
                                    // was never affected by the staleness bug above.
                                    readonly property var sortedAlerts: {
                                        var copy = alerts.slice();
                                        copy.sort(function (a, b) {
                                            var da = a.onset ? new Date(a.onset).getTime() : 0;
                                            var db = b.onset ? new Date(b.onset).getTime() : 0;
                                            return da - db;
                                        });
                                        return copy;
                                    }

                                    function _updateAlertWindows() {
                                        var now = new Date();

                                        // Alerts active right now (onset <= now <= expires)
                                        var current = [];
                                        for (var i = 0; i < alerts.length; i++) {
                                            var a = alerts[i];
                                            var onset = a.onset ? new Date(a.onset) : null;
                                            var expires = a.expires ? new Date(a.expires) : null;
                                            var started = !onset || onset <= now;
                                            var notExpired = !expires || expires >= now;
                                            if (started && notExpired)
                                                current.push(a);
                                        }

                                        // todayAlerts: the active set, or (if none active yet) the
                                        // earliest-future one
                                        var today = current.slice();
                                        if (today.length === 0 && alerts.length > 0) {
                                            var best = alerts[0];
                                            for (var j = 1; j < alerts.length; j++) {
                                                if (alerts[j].onset && (!best.onset || alerts[j].onset < best.onset))
                                                    best = alerts[j];
                                            }
                                            today.push(best);
                                        }

                                        // activeAlerts: the same active set, sorted by onset
                                        var active = current.slice();
                                        active.sort(function (a, b) {
                                            var da = a.onset ? new Date(a.onset).getTime() : 0;
                                            var db = b.onset ? new Date(b.onset).getTime() : 0;
                                            return da - db;
                                        });

                                        // futureAlerts: onset strictly in the future, sorted by onset
                                        var future = [];
                                        for (var k = 0; k < alerts.length; k++) {
                                            var af = alerts[k];
                                            var onsetF = af.onset ? new Date(af.onset) : null;
                                            if (onsetF && onsetF > now)
                                                future.push(af);
                                        }
                                        future.sort(function (a, b) {
                                            return new Date(a.onset).getTime() - new Date(b.onset).getTime();
                                        });

                                        todayAlerts = today;
                                        activeAlerts = active;
                                        futureAlerts = future;
                                    }

                                    Component.onCompleted: _updateAlertWindows()
                                    onAlertsChanged: _updateAlertWindows()
                                    Timer {
                                        interval: 60000
                                        running: alertsCard.visible
                                        repeat: true
                                        triggeredOnStart: true
                                        onTriggered: alertsCard._updateAlertWindows()
                                    }

                                    function alertColorDot(c) {
                                        c = (c || "").toLowerCase();
                                        if (c === "yellow")
                                            return "#ffc107";
                                        if (c === "orange")
                                            return "#ff8c00";
                                        if (c === "red")
                                            return "#dc3545";
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
                                                result.push({
                                                    type: t,
                                                    color: a.color || ""
                                                });
                                            }
                                        }
                                        return result;
                                    }
                                    function alertColorText(c) {
                                        c = (c || "").toLowerCase();
                                        if (c === "yellow")
                                            return root.isDark ? "#ffc107" : "#9a7b00";
                                        if (c === "orange")
                                            return root.isDark ? "#ff8c00" : "#c04000";
                                        if (c === "red")
                                            return root.isDark ? "#ff4444" : "#cc0000";
                                        return root.themeTextColor;
                                    }
                                    // Map alert source string to a clickable provider link
                                    function alertProviderLink(src) {
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
                                        // Unknown source - show as plain text
                                        if (src.length > 0)
                                            return src;
                                        return "<a href='https://www.meteoalarm.org/'>EUMETNET MeteoAlarm</a>";
                                    }
                                    function formatAlertDate(iso) {
                                        if (!iso)
                                            return "";
                                        var d = new Date(iso);
                                        if (isNaN(d.getTime()))
                                            return "";
                                        return root.weatherRoot ? root.weatherRoot.formatDateObj(d, false) : Qt.formatDate(d, "MMM d");
                                    }
                                    function alertDateRange(a) {
                                        var from = formatAlertDate(a.onset);
                                        var to = formatAlertDate(a.expires);
                                        if (from && to && from !== to)
                                            return from + " \u2013 " + to;
                                        if (from)
                                            return from;
                                        if (to)
                                            return to;
                                        return "";
                                    }
                                    // Uses the selected date and time formats for both endpoints.
                                    function alertTimeRange(a) {
                                        if (!a)
                                            return "";
                                        var f = a.onset || a.effective ? new Date(a.onset || a.effective) : null;
                                        var t = a.expires ? new Date(a.expires) : null;
                                        if (f && isNaN(f.getTime()))
                                            f = null;
                                        if (t && isNaN(t.getTime()))
                                            t = null;
                                        var wr = root.weatherRoot;
                                        function dt(d) {
                                            return wr ? (wr.formatDateObj(d, false) + ", " + wr.formatTimeObj(d)) : Qt.formatDateTime(d, "MMM d, hh:mm");
                                        }
                                        function tm(d) {
                                            return wr ? wr.formatTimeObj(d) : Qt.formatTime(d, "hh:mm");
                                        }
                                        if (f && t)
                                            return f.toDateString() === t.toDateString() ? (dt(f) + " \u2013 " + tm(t)) : (dt(f) + " \u2013 " + dt(t));
                                        if (f)
                                            return dt(f);
                                        if (t)
                                            return i18n("Until") + " " + dt(t);
                                        return "";
                                    }
                                    function formatAlertDateTime(iso) {
                                        if (!iso)
                                            return "";
                                        var d = new Date(iso);
                                        if (isNaN(d.getTime()))
                                            return "";
                                        return root.weatherRoot ? (root.weatherRoot.formatDateObj(d, false) + ", " + root.weatherRoot.formatTimeObj(d)) : Qt.formatDateTime(d, "MMM d, hh:mm");
                                    }
                                    function alertTooltipTitle(a) {
                                        var town = (Plasmoid.configuration.locationName || "").split(",")[0].trim();
                                        var area = a ? (a.area || "") : "";
                                        if (town && area)
                                            return town + ", " + area;
                                        return town || area;
                                    }
                                    function _truncate(str, max) {
                                        if (!str)
                                            return "";
                                        return str.length > max ? str.substring(0, max).trimRight() + "…" : str;
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
                                    function alertTooltipSub(a) {
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
                                            lines.push("<b>" + i18n("Effective") + ":</b> " + formatAlertDateTime(a.effective));
                                        if (a.expires)
                                            lines.push("<b>" + i18n("Expires") + ":</b> " + formatAlertDateTime(a.expires));
                                        if (a.instruction)
                                            lines.push("<b>" + i18n("Instruction") + ":</b><br>" + a.instruction);
                                        if (a.source || a.senderName)
                                            lines.push("<b>" + i18n("Provider") + ":</b> " + alertProviderLink(a.source));
                                        if (a.web)
                                            lines.push("<b>" + i18n("Website") + ":</b> <a href='" + a.web + "'>" + a.web + "</a>");
                                        return lines.join("<br>");
                                    }

                                    // ── No alerts: compact row (expands to the "all clear" view) ──
                                    RowLayout {
                                        anchors {
                                            fill: parent
                                            leftMargin: 10
                                            rightMargin: 10
                                        }
                                        spacing: 8
                                        visible: alertsCard.clear && !alertsCard.open

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("alerts") ? root.resolveIcon("alerts") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("alerts"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("alerts") + ":"
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: weatherRoot ? weatherRoot.alertsText() : "--"
                                            color: root.valueColor
                                            font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                                bold: true
                                            })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            visible: !root.isList
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            Layout.alignment: Qt.AlignVCenter
                                            Kirigami.Icon {
                                                anchors.fill: parent
                                                source: "arrow-down"
                                                opacity: 0.45
                                            }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        visible: alertsCard.clear && !alertsCard.open && !root.isList
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root._alertsExpanded = true
                                    }

                                    // ── Single alert ────────────────────────────────────────
                                    RowLayout {
                                        anchors {
                                            fill: parent
                                            leftMargin: 10
                                            rightMargin: 10
                                        }
                                        spacing: 8
                                        visible: !alertsCard.hasMultiple && !alertsCard.clear && !alertsCard.open

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("alerts") ? root.resolveIcon("alerts") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("alerts"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("alerts") + ":"
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: alertsCard.alerts.length > 0 ? alertsCard.alertTypeIcon(alertsCard.alerts[0].awarenessType || 0) : ""
                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                            font.pixelSize: 14
                                            color: alertsCard.alerts.length > 0 ? alertsCard.alertColorText(alertsCard.alerts[0].color) : "#999"
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: alertsCard.alerts.length > 0 ? (alertsCard.alerts[0].displayName || alertsCard.alerts[0].headline || "") : ""
                                            color: alertsCard.alerts.length > 0 ? alertsCard.alertColorText(alertsCard.alerts[0].color) : root.themeTextColor
                                            font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                bold: true
                                            })
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
                                                width: 18
                                                height: 18
                                                source: "help-about"
                                            }
                                        }

                                        // Expand chevron (cards mode)
                                        Item {
                                            visible: !root.isList
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            Layout.alignment: Qt.AlignVCenter
                                            Kirigami.Icon {
                                                anchors.fill: parent
                                                source: "arrow-down"
                                                opacity: 0.45
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -6
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root._alertsExpanded = true
                                            }
                                        }
                                    }

                                    // ── Collapsed header (multiple alerts) ───────────────
                                    RowLayout {
                                        id: alertsHeader
                                        visible: alertsCard.hasMultiple && !alertsCard.open
                                        anchors {
                                            top: parent.top
                                            left: parent.left
                                            right: parent.right
                                            leftMargin: 10
                                            rightMargin: 10
                                        }
                                        height: alertsCard.open ? 0 : root.regularCardHeight
                                        spacing: 8

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("alerts") ? root.resolveIcon("alerts") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("alerts"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("alerts") + ":"
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        // Left arrow (only when multiple today alerts)
                                        Item {
                                            visible: alertsCard.todayHasMultiple
                                            implicitWidth: 16
                                            implicitHeight: 16
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
                                                return a ? alertsCard.alertColorText(a.color) : root.themeTextColor;
                                            }
                                            font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                bold: true
                                            })
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        // Right arrow (only when multiple today alerts)
                                        Item {
                                            visible: alertsCard.todayHasMultiple
                                            implicitWidth: 16
                                            implicitHeight: 16
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
                                            Layout.preferredWidth: 26
                                            Layout.preferredHeight: 26
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
                                                    font: weatherRoot ? weatherRoot.wf(12, true) : Qt.font({
                                                        bold: true
                                                    })
                                                    wrapMode: Text.Wrap
                                                    width: parent.width
                                                    Layout.fillWidth: true
                                                }
                                                Label {
                                                    text: {
                                                        var a = alertsCard.todayAlerts[alertsCard.safeIndex];
                                                        return a ? alertsCard.alertTooltipSub(a) : "";
                                                    }
                                                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                                    textFormat: Text.RichText
                                                    wrapMode: Text.Wrap
                                                    width: parent.width
                                                    Layout.fillWidth: true
                                                }
                                            }
                                            Kirigami.Icon {
                                                anchors.centerIn: parent
                                                width: 18
                                                height: 18
                                                source: "help-about"
                                            }
                                        }

                                        // Expand chevron
                                        Item {
                                            visible: !root.isList
                                            implicitWidth: 14
                                            implicitHeight: 14
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

                                    // ── Expanded view: severity dial + hazard scene, switched with < > ──
                                    // One page per alert: the ones in force first, then the upcoming
                                    // ones (the order the old list used). One alert = one page, no pager.
                                    readonly property bool open: !root.isList && card._isArcExpanded
                                    readonly property var pages: {
                                        var p = alertsCard.activeAlerts.concat(alertsCard.futureAlerts);
                                        return p.length > 0 ? p : alertsCard.todayAlerts;
                                    }
                                    property int page: 0
                                    readonly property int safePage: Math.min(Math.max(0, page), Math.max(0, pages.length - 1))
                                    readonly property var cur: pages.length > 0 ? pages[safePage] : null
                                    readonly property string curColor: cur ? (cur.color || "") : ""
                                    readonly property var curInfo: AlertGauge.info(curColor)
                                    readonly property var levelLabels: [i18n("Yellow"), i18n("Orange"), i18n("Red")]
                                    readonly property color clearColor: root.isDark ? "#4CAF50" : "#2E7D32"

                                    function levelText(c) {
                                        switch (AlertGauge.levelOf(c)) {
                                        case 1:
                                            return i18n("Yellow warning");
                                        case 2:
                                            return i18n("Orange warning");
                                        case 3:
                                            return i18n("Red warning");
                                        }
                                        return i18n("Warning");
                                    }

                                    ExpandedGauge {
                                        visible: alertsCard.open
                                        anchors.fill: parent
                                        weatherRoot: root.weatherRoot
                                        title: root.labelFor("alerts")
                                        iconInfo: root.showIconFor("alerts") ? root.resolveIcon("alerts") : null
                                        iconSize: root.iconSize
                                        iconColor: root.iconColorFor(alertsCard.clear ? alertsCard.clearColor : alertsCard.curInfo.color)
                                        valueText: alertsCard.clear ? i18n("No active alerts") : (alertsCard.cur ? (alertsCard.cur.displayName || alertsCard.cur.headline || "--") : "--")
                                        valueColor: alertsCard.clear ? root.valueColor : alertsCard.alertColorText(alertsCard.curColor)
                                        bandText: alertsCard.clear ? i18n("All clear") : ""
                                        bandColor: alertsCard.clear ? alertsCard.clearColor : alertsCard.alertColorText(alertsCard.curColor)
                                        subText: alertsCard.clear ? i18n("No warnings in effect") : (alertsCard.cur ? alertsCard.alertTimeRange(alertsCard.cur) : "")
                                        subColor: root.themeTextColor
                                        infoNextToValue: true
                                        overlayMaxWidth: 240
                                        pageCount: alertsCard.pages.length
                                        pageIndex: alertsCard.safePage
                                        onPreviousRequested: alertsCard.page = alertsCard.safePage - 1
                                        onNextRequested: alertsCard.page = alertsCard.safePage + 1
                                        onPageSelected: function (i) {
                                            alertsCard.page = i;
                                        }
                                        infoTitle: alertsCard.cur ? alertsCard.alertTooltipTitle(alertsCard.cur) : ""
                                        infoText: alertsCard.cur ? alertsCard.alertTooltipSub(alertsCard.cur) : ""
                                        infoWidth: 380
                                        paintKey: alertsCard.clear + "|" + alertsCard.safePage + "|" + alertsCard.pages.length + "|" + alertsCard.curColor + "|" + (alertsCard.cur ? (alertsCard.cur.awarenessType || 0) : 0) + "|" + root.isDark + "|" + root.themeTextColor
                                        onDraw: function (ctx, w, h) {
                                            AlertGauge.draw(ctx, w, h, {
                                                clear: alertsCard.clear,
                                                okLabel: i18n("Clear"),
                                                color: alertsCard.curColor,
                                                type: alertsCard.cur ? (alertsCard.cur.awarenessType || 0) : 0,
                                                labels: alertsCard.levelLabels,
                                                isDark: root.isDark,
                                                text: String(root.themeTextColor)
                                            });
                                        }
                                        onCollapseRequested: root._alertsExpanded = false
                                    }
                                }
                            }

                            // ═══════════════════════════════════════════════════════════════
                            // Date / Time - live clock + calendar card
                            // ═══════════════════════════════════════════════════════════════
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "datetime" && !root.isList
                                sourceComponent: Item {
                                    id: datetimeCard
                                    anchors.fill: parent
                                    clip: true

                                    property int _tick: 0
                                    Timer {
                                        interval: 1000
                                        running: datetimeCard.visible
                                        repeat: true
                                        onTriggered: datetimeCard._tick++
                                    }

                                    // ── Collapsed header row ──────────────────────────────
                                    RowLayout {
                                        id: dtHeader
                                        anchors {
                                            top: parent.top
                                            left: parent.left
                                            right: parent.right
                                            leftMargin: 10
                                            rightMargin: 10
                                        }
                                        height: root.regularCardHeight
                                        spacing: 8
                                        visible: !card._isArcExpanded

                                        WeatherIcon {
                                            iconInfo: root.showIconFor("datetime") ? root.resolveIcon("datetime") : null
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("datetime"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("datetime") + ":"
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: {
                                                var _ = datetimeCard._tick;
                                                return weatherRoot ? weatherRoot.formatDateTimeNow(false) : "--";
                                            }
                                            color: root.valueColor
                                            font: weatherRoot ? weatherRoot.wf(12, true) : Qt.font({
                                                bold: true
                                            })
                                            elide: Text.ElideRight
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Item {
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            Layout.alignment: Qt.AlignVCenter
                                            Kirigami.Icon {
                                                anchors.fill: parent
                                                source: "arrow-down"
                                                opacity: 0.45
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root._dtExpanded = true
                                            }
                                        }
                                    }

                                    // ── Expanded view ─────────────────────────────────────
                                    ColumnLayout {
                                        id: dtExpanded
                                        visible: card._isArcExpanded
                                        anchors {
                                            fill: parent
                                            leftMargin: 10
                                            rightMargin: 10
                                            topMargin: 4
                                            bottomMargin: 4
                                        }
                                        spacing: 2

                                        // Collapse chevron - top-right only
                                        Item {
                                            Layout.fillWidth: true
                                            height: 14
                                            Item {
                                                anchors.right: parent.right
                                                width: 14
                                                height: 14
                                                Kirigami.Icon {
                                                    anchors.fill: parent
                                                    source: "arrow-up"
                                                    opacity: 0.45
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root._dtExpanded = false
                                                }
                                            }
                                        }

                                        // ── Calendar grid ─────────────────────────────────
                                        Item {
                                            id: calItem
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            // Month offset for prev/next navigation (0 = current month)
                                            property int _offset: 0
                                            // Reset to current month when card collapses
                                            property bool watchExpanded: root._dtExpanded
                                            onWatchExpandedChanged: if (!root._dtExpanded)
                                                _offset = 0

                                            // "Today" - always real today (for highlight)
                                            readonly property int _todayDay: {
                                                var _ = datetimeCard._tick;
                                                return new Date().getDate();
                                            }
                                            readonly property int _todayMonth: {
                                                var _ = datetimeCard._tick;
                                                return new Date().getMonth();
                                            }
                                            readonly property int _todayYear: {
                                                var _ = datetimeCard._tick;
                                                return new Date().getFullYear();
                                            }

                                            // "Viewed" month - today + offset
                                            readonly property date _viewDate: new Date(_todayYear, _todayMonth + _offset, 1)
                                            readonly property int _viewMonth: _viewDate.getMonth()
                                            readonly property int _viewYear: _viewDate.getFullYear()
                                            readonly property int _firstDow: _viewDate.getDay()   // 0=Sun
                                            readonly property int _daysInMonth: new Date(_viewYear, _viewMonth + 1, 0).getDate()
                                            readonly property int _fdo: {
                                                var cfg = Plasmoid.configuration.calendarFirstDayOfWeek;
                                                var firstDow = (cfg >= 0) ? cfg : Qt.locale().firstDayOfWeek;
                                                return (_firstDow - firstDow + 7) % 7;
                                            }

                                            ColumnLayout {
                                                anchors.fill: parent
                                                spacing: 2

                                                // Month + year header with prev/next buttons
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    // Prev month
                                                    Item {
                                                        implicitWidth: 16
                                                        implicitHeight: 16
                                                        Layout.alignment: Qt.AlignVCenter
                                                        Kirigami.Icon {
                                                            anchors.fill: parent
                                                            source: "arrow-left"
                                                            opacity: 0.55
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: calItem._offset--
                                                        }
                                                    }

                                                    Label {
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: calItem._viewDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                                                        color: root.themeTextColor
                                                        opacity: calItem._offset === 0 ? 0.75 : 1.0
                                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                            bold: true
                                                        })
                                                    }

                                                    // Next month
                                                    Item {
                                                        implicitWidth: 16
                                                        implicitHeight: 16
                                                        Layout.alignment: Qt.AlignVCenter
                                                        Kirigami.Icon {
                                                            anchors.fill: parent
                                                            source: "arrow-right"
                                                            opacity: 0.55
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: calItem._offset++
                                                        }
                                                    }
                                                }

                                                // Day-of-week header row
                                                Row {
                                                    id: dowHeader
                                                    Layout.fillWidth: true
                                                    spacing: 0
                                                    Repeater {
                                                        model: 7
                                                        delegate: Item {
                                                            required property int index
                                                            width: dowHeader.width / 7
                                                            height: 16
                                                            Label {
                                                                anchors.centerIn: parent
                                                                text: {
                                                                    var loc = Qt.locale();
                                                                    var cfg = Plasmoid.configuration.calendarFirstDayOfWeek;
                                                                    var firstDow = (cfg >= 0) ? cfg : loc.firstDayOfWeek;
                                                                    var d = (index + firstDow) % 7;
                                                                    return loc.dayName(d === 0 ? 7 : d, Locale.NarrowFormat);
                                                                }
                                                                font: weatherRoot ? weatherRoot.wf(9, true) : Qt.font({
                                                                    bold: true,
                                                                    pixelSize: 9
                                                                })
                                                                color: root.themeTextColor
                                                                opacity: 0.45
                                                            }
                                                        }
                                                    }
                                                }

                                                // Calendar day cells - 6 rows × 7 cols = 42 slots
                                                Grid {
                                                    id: calGrid
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    columns: 7
                                                    rows: 6
                                                    spacing: 0

                                                    Repeater {
                                                        model: 42
                                                        delegate: Item {
                                                            required property int index
                                                            width: calGrid.width / 7
                                                            height: calGrid.height / 6

                                                            readonly property int _dayNum: index - calItem._fdo + 1
                                                            readonly property bool _valid: _dayNum >= 1 && _dayNum <= calItem._daysInMonth
                                                            readonly property bool _isToday: _valid && _dayNum === calItem._todayDay && calItem._viewMonth === calItem._todayMonth && calItem._viewYear === calItem._todayYear

                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: Math.min(parent.width, parent.height) - 2
                                                                height: width
                                                                radius: width / 2
                                                                color: parent._isToday ? root.themeHighlightColor : "transparent"
                                                                opacity: parent._isToday ? 0.9 : 1.0
                                                            }
                                                            Label {
                                                                anchors.centerIn: parent
                                                                visible: parent._valid
                                                                text: parent._dayNum
                                                                font: weatherRoot ? weatherRoot.wf(10, parent._isToday) : Qt.font({
                                                                    pixelSize: 10,
                                                                    bold: parent._isToday
                                                                })
                                                                color: parent._isToday ? root.themeHighlightedTextColor : root.themeTextColor
                                                                opacity: parent._isToday ? 1.0 : 0.75
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── LIST MODE: compact datetime row ──────────────────────────
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                visible: card.modelData === "datetime" && root.isList
                                spacing: 8

                                WeatherIcon {
                                    iconInfo: root.showIconFor("datetime") ? root.resolveIcon("datetime") : null
                                    iconSize: root.iconSize
                                    iconColor: root.iconColorFor(root.accentFor("datetime"))
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Label {
                                    text: root.labelFor("datetime") + ":"
                                    color: root.themeTextColor
                                    opacity: 0.55
                                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: root._dvDatetime
                                    color: root.valueColor
                                    font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                        bold: true
                                    })
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            // ═══════════════════════════════════════════════════════════════
                            // Suntimes - animated sun/moon arc card
                            //
                            // DAY:   sun travels left→noon→right   (warm gold palette)
                            // NIGHT: moon travels right→midnight→left  (cool blue palette)
                            //        stars appear; bottom row flips: sunset left, sunrise right
                            //
                            // ═════════════════════════════════════════════════════════════════
                            // Suntimes - animated sun/moon arc card
                            //
                            // DAY:   sun travels left→noon→right   (warm gold palette)
                            // NIGHT: moon travels right→midnight→left (cool pink/violet palette)
                            //        stars appear in sky; bottom row flips labels
                            //
                            // _isNight is driven by an explicit _updateProg() function - NOT
                            // a QML binding - because QML bindings only re-evaluate when their
                            // declared QML dependencies change.  new Date() inside a JS call is
                            // NOT a QML dependency, so a binding would freeze at the value it
                            // had when sunrise/sunset strings last changed, making night mode
                            // never trigger after the widget first loads with daytime data.
                            // ═════════════════════════════════════════════════════════════════
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "suntimes" && !root.isList
                                sourceComponent: Item {
                                    id: suntimesCard
                                    anchors.fill: parent
                                    clip: true
                                    // Arc card hidden in list mode (compact row used instead)

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

                                        // Leading icon - sunrise or sunset depending on day/night
                                        // Kirigami.Icon {
                                        //     source: {
                                        //         var stem = suntimesCard._isNight ? "sunset" : "sunrise";
                                        //         return root.svgBase.length > 0
                                        //             ? (root.svgBase + stem + ".svg")
                                        //             : Qt.resolvedUrl("../icons/symbolic/wi-" + stem + ".svg");
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
                                                // "both" - prefer custom sunrise icon if set
                                                var custom = root.getDetailsCustomIcon("suntimes-sunrise");
                                                if (custom.length > 0 && root.iconTheme === "kde")
                                                    return {
                                                        type: "kde",
                                                        source: custom,
                                                        svgFallback: "",
                                                        isMask: false
                                                    };
                                                return root.resolveIcon("suntimes");
                                            }
                                            iconSize: root.iconSize
                                            iconColor: root.iconColorFor(root.accentFor("suntimes"))
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        // Dim label - matches standard row style
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
                                            color: root.themeTextColor
                                            opacity: 0.55
                                            font: root.weatherRoot ? root.weatherRoot.wf(11, false) : Qt.font({})
                                            elide: Text.ElideRight
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        // Bold value - sunrise / sunset times
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
                                    // new Date().getHours() - which is always machine-local time,
                                    // not location-local time - and therefore always failed for
                                    // users checking a location in a different timezone.
                                    //
                                    // Must be a plain property recomputed from _updateProg(), NOT
                                    // a QML binding (see the header comment above this Loader) -
                                    // isNightTime() calls new Date() internally, which is not a
                                    // QML dependency, so a binding here only re-evaluates when
                                    // sunriseTimeText/sunsetTimeText actually change VALUE (i.e.
                                    // once a day). Confirmed via [SunArc-debug] logging 2026-09-11:
                                    // it flipped true at 00:05 local (correct for night) and then
                                    // silently stayed true straight through the 06:06 sunrise and
                                    // for 2.5+ hours into broad daylight, freezing the arc dot at
                                    // moonProgress()'s clamped endpoint (mProg=1) since drawSunArc
                                    // kept using the moon path while _prog kept climbing normally.
                                    property bool _isNight: false

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
                                    // is NOT a QML property - bindings would freeze on first eval.
                                    property int _now: 0
                                    function _refreshNow() {
                                        _now = (new Date()).getTime(); // ms timestamp - just needs to change
                                    }

                                    function _updateProg() {
                                        _refreshNow();
                                        if (root.weatherRoot) {
                                            _prog = SunPath.sunProgress(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText, suntimesCard._utcOffset);
                                            _isNight = root.weatherRoot.isNightTime();
                                        } else {
                                            _prog = 0.5;
                                            _isNight = false;
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
                                        // weatherData changes once per provider response - covers
                                        // sunrise, sunset, and all other weather field updates.
                                        function onWeatherDataChanged() {
                                            suntimesCard._updateProg();
                                        }
                                        // Recompute when is_day flag changes (separate signal path).
                                        // _isNight is now a plain property (see above), so this must
                                        // go through _updateProg() too, not just requestPaint() - a
                                        // bare repaint would redraw with the last computed value.
                                        function onIsDayChanged() {
                                            suntimesCard._updateProg();
                                        }
                                    }

                                    // Glow pulse disabled: infinite animation caused 60fps
                                    // Canvas repaints (see perf) which compounded layout/render
                                    // stalls on NVIDIA EGL during location changes.
                                    readonly property real glowPulse: 0

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
                                            // _isNight drives sun vs moon - from API is_day flag.
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
                                                    void (suntimesCard._now); // reactive - re-evals every minute
                                                    if (!root.weatherRoot)
                                                        return "--";
                                                    if (suntimesCard._isNight) {
                                                        var nl = SunPath.nightLengthMins(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText);
                                                        return i18n("Night") + ": " + root.durationText(nl);
                                                    }
                                                    var dl = SunPath.dayLengthMins(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText);
                                                    return i18n("Day") + ": " + root.durationText(dl);
                                                }
                                                color: root.themeTextColor
                                                opacity: 0.65
                                                font: root.weatherRoot ? root.weatherRoot.wf(10, false) : Qt.font({})
                                                elide: Text.ElideRight
                                            }

                                            Label {
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: {
                                                    void (suntimesCard._now); // reactive - re-evals every minute
                                                    if (!root.weatherRoot)
                                                        return "--";
                                                    if (suntimesCard._isNight) {
                                                        var until = SunPath.minsUntilSunrise(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText, suntimesCard._utcOffset);
                                                        var mp = SunPath.moonProgress(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText, suntimesCard._utcOffset);
                                                        var phase = SunPath.nightPhaseLabel(mp, until);
                                                        if (phase === "approaching")
                                                            return i18n("Dawn approaching - ") + root.durationText(until);
                                                        if (phase === "evening")
                                                            return i18n("Evening - ") + root.durationText(until) + i18n(" until dawn");
                                                        if (phase === "midnight")
                                                            return i18n("Around midnight - ") + root.durationText(until) + i18n(" until dawn");
                                                        return root.durationText(until) + " " + i18n("until dawn");
                                                    }
                                                    var rem = SunPath.remainingMins(root.weatherRoot.sunriseTimeText, root.weatherRoot.sunsetTimeText, suntimesCard._utcOffset);
                                                    return rem > 0 ? root.durationText(rem) + " " + i18n("left") : i18n("Daylight over");
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
                                        font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({
                                            bold: true
                                        })
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
                                        font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({
                                            bold: true
                                        })
                                    }
                                }
                            }

                            // ── LIST MODE: compact sunrise/sunset row ─────────────
                            // Direct child of card Rectangle - never hidden by arc Item
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
                                        // "both" - prefer custom sunrise icon if set
                                        var custom = root.getDetailsCustomIcon("suntimes-sunrise");
                                        if (custom.length > 0 && root.iconTheme === "kde")
                                            return {
                                                type: "kde",
                                                source: custom,
                                                svgFallback: "",
                                                isMask: false
                                            };
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
                                    color: root.themeTextColor
                                    opacity: 0.55
                                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                // Sunrise / Sunset - mode-aware right side
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
                                        color: root.themeTextColor
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
                            // Moon Phase - animated arc card
                            //
                            // The moon travels clockwise from left (moonrise) → top (transit)
                            // → right (moonset), exactly mirroring the sun arc architecture.
                            // The body is a phase-accurate crescent/full/new disc.
                            // Stars are always shown in the background.
                            // Bottom row: [↑ moonrise] [phase name · illumination%] [↓ moonset]
                            // ═══════════════════════════════════════════════════════════════
                            // Built only for its own card type - a dormant twin of every heavy
                            // section in every card multiplied item count ~9x and froze the details tab.
                            Loader {
                                anchors.fill: parent
                                active: card.modelData === "moonphase" && !root.isList
                                sourceComponent: Item {
                                    id: moonCard
                                    anchors.fill: parent
                                    clip: true
                                    // Arc card hidden in list mode (compact row used instead)

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
                                            color: root.themeTextColor
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
                                    // Calculated astronomically from lat/lon - no API needed.
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

                                    // Glow pulse disabled: infinite animation caused 60fps
                                    // Canvas repaints (see perf) which compounded layout/render
                                    // stalls on NVIDIA EGL during location changes.
                                    readonly property real glowPulse: 0

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
                                        font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({
                                            bold: true
                                        })
                                    }
                                    Label {
                                        visible: card._isArcExpanded
                                        x: moonCanvas.width / 2 + moonCard._arcR - implicitWidth / 2
                                        y: moonCanvas.y + moonCanvas.height - 14 + 8
                                        text: root.weatherRoot ? root.weatherRoot.formatTimeForDisplay(moonCard._moonsetText) : "--"
                                        color: root.accentViolet
                                        opacity: 0.75
                                        font: root.weatherRoot ? root.weatherRoot.wf(11, true) : Qt.font({
                                            bold: true
                                        })
                                    }
                                }
                            }

                            // ── LIST MODE: compact moon phase row ─────────────────
                            // Direct child of card Rectangle - never hidden by arc Item
                            Item {
                                id: listMoonRow
                                anchors.fill: parent
                                visible: card.modelData === "moonphase" && root.isList

                                // Compute moon times directly here - moonCard.visible is
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

                                    // Label - mode-aware
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
                                        color: root.themeTextColor
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
                                            color: root.themeTextColor
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

    // Keep duration units translatable; the JS arc helpers return literal h/m.
    function durationText(totalMins) {
        if (!isFinite(totalMins))
            return "--";
        if (totalMins <= 0)
            return i18n("%1m", 0);
        var h = Math.floor(totalMins / 60);
        var m = totalMins % 60;
        if (h === 0)
            return i18n("%1m", m);
        if (m === 0)
            return i18n("%1h", h);
        return i18n("%1h %2m", h, m);
    }
}
