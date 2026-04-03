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
 * main.qml — Advanced Weather Widget root
 *
 * Responsibilities:
 *  - Declare all weather data properties (the "model")
 *  - Expose helper functions used by sub-views (tempValue, windValue, ...)
 *  - Host WeatherService (API fetching)
 *  - Wire timers and config Connections
 *  - Declare compactRepresentation and fullRepresentation
 *
 * Sub-views receive `weatherRoot: root` so they can read data and call
 * helpers without duplicating logic.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtPositioning
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

import "js/weather.js" as W
import "js/moonphase.js" as Moon
import "js/suncalc.js" as SC
import "js/iconResolver.js" as IconResolver

PlasmoidItem {
    id: root

    implicitWidth: 540
    implicitHeight: 550
    switchWidth: 200
    switchHeight: 100

    preferredRepresentation: fullRepresentation
    hideOnWindowDeactivate: !Plasmoid.configuration.keepOpen

    // ══════════════════════════════════════════════════════════════════════
    // Weather data model
    // ══════════════════════════════════════════════════════════════════════

    property bool loading: false
    property real temperatureC: NaN
    property real apparentC: NaN
    property real windKmh: NaN
    property real windDirection: NaN   // degrees 0=N, 90=E, 180=S, 270=W
    property real pressureHpa: NaN
    property real humidityPercent: NaN
    property real visibilityKm: NaN
    property real dewPointC: NaN
    property real precipMmh: NaN           // Current precipitation rate (mm/h)
    readonly property real precipSumMm: dailyData.length > 0 && !isNaN(dailyData[0].precipMm) ? dailyData[0].precipMm : NaN
    property real uvIndex: NaN             // UV index (0–11+)
    property real airQualityIndex: NaN     // AQI numeric value (provider scale)
    property string airQualityLabel: ""    // "Good", "Moderate", etc.
    property real aqiPm10:  NaN
    property real aqiPm2_5: NaN
    property real aqiCo:    NaN
    property real aqiNo2:   NaN
    property real aqiSo2:   NaN
    property real aqiO3:    NaN
    property var weatherAlerts: []         // [{headline, severity, description}]
    property var pollenData: []             // [{key, value}] UPI 0–12 per pollen type
    property var spaceWeather: null         // NOAA SWPC data object
    property real snowDepthCm: NaN         // Current snow depth (cm)
    property string sunriseTimeText: "--"
    property string sunsetTimeText: "--"
    property string moonriseTimeText: "--"
    property string moonsetTimeText: "--"
    property int weatherCode: -1
    property int isDay: -1   // -1=unknown, 0=night, 1=day (populated by API when available)
    // UTC offset of the weather location in minutes (e.g. -420 for California UTC-7).
    // Set by WeatherService from the API response. Used by sunpath.js to convert
    // UTC clock time to location-local time without relying on Intl (unsupported in Qt V4).
    property int locationUtcOffsetMins: 0
    property var dailyData: []
    property var hourlyData: []
    property int panelScrollIndex: 0
    property string updateText: ""

    // hasSelectedTown is true when we have a named location OR when auto-detect
    // mode has already acquired non-zero GPS coordinates (so weather can load
    // even before the reverse-geocode name arrives on first placement).
    readonly property bool hasSelectedTown: (Plasmoid.configuration.locationName || "").trim().length > 0 || (Plasmoid.configuration.autoDetectLocation && (Plasmoid.configuration.latitude !== 0.0 || Plasmoid.configuration.longitude !== 0.0))

    // ══════════════════════════════════════════════════════════════════════
    // Representations
    // ══════════════════════════════════════════════════════════════════════

    toolTipMainText: ""  // suppress Plasma's built-in metadata tooltip
    toolTipSubText: ""

    compactRepresentation: CompactView {
        weatherRoot: root
    }

    fullRepresentation: FullView {
        weatherRoot: root
        // ── Minimum popup size ───────────────────────────────────────────
        // Plasma reads Layout.minimumWidth/Height from the fullRepresentation
        // item — NOT from PlasmoidItem — to enforce resize limits.
        // Use a compact size when no location is configured yet.

        Layout.minimumWidth: {
            if (!root.hasSelectedTown) return 280;
            if ((Plasmoid.configuration.widgetMinWidthMode || "auto") === "manual")
                return Math.max(200, Plasmoid.configuration.widgetMinWidth || 800);
            return 800;
        }
        Layout.minimumHeight: {
            if (!root.hasSelectedTown) return 220;
            if ((Plasmoid.configuration.widgetMinHeightMode || "auto") === "manual")
                return Math.max(200, Plasmoid.configuration.widgetMinHeight || 750);
            return 750;
        }
    }


    // ══════════════════════════════════════════════════════════════════════
    // Service — all API calls delegated to WeatherService
    // ══════════════════════════════════════════════════════════════════════

    WeatherService {
        id: weatherService
        weatherRoot: root
    }

    // ══════════════════════════════════════════════════════════════════════
    // Auto-detect location — 3-tier fallback
    //
    // Tier 1: GeoClue2 explicitly (PositionSource name: "geoclue2")
    // Tier 2: Any available Qt Positioning plugin (PositionSource, no name)
    // Tier 3: IP-based geolocation (geo.kamero.ai → reallyfreegeoip.org)
    //
    // Active whenever the user has chosen "Automatically detect location".
    // On every position update it:
    //   1. Writes lat/lon/alt directly to Plasmoid.configuration so the
    //      weather fetch and the config dialog both see the fresh values.
    //   2. Triggers a weather refresh (via onLatitudeChanged / onLongitudeChanged).
    //   3. Calls _autoReverseGeocode to update the city name — but ONLY when
    //      a name is already stored. First-time naming (empty locationName) is
    //      handled exclusively by configLocation.qml's confirm dialog so the
    //      user can review the detected place before it is saved.
    // ══════════════════════════════════════════════════════════════════════

    // Which tier is currently active: 0 = idle, 1 = geoclue2, 2 = generic, 3 = IP
    property int _locationTier: 0

    function _applyAutoPosition(lat, lon, alt) {
        // Deactivate sources after a successful fix to avoid duplicate callbacks
        geoclue2Source.active = false;
        genericPositionSource.active = false;
        Plasmoid.configuration.latitude = lat;
        Plasmoid.configuration.longitude = lon;
        if (!isNaN(alt) && alt > 0)
            Plasmoid.configuration.altitude = Math.round(alt);
        // Always reverse-geocode: on first run locationName is empty and
        // would never get populated if we skipped it.
        _autoReverseGeocode(lat, lon);
    }

    function _startAutoDetect() {
        if (!Plasmoid.configuration.autoDetectLocation) return;
        _locationTier = 1;
        geoclue2Source.active = true;
        geoclue2Source.update();
        // Timeout: if GeoClue2 doesn't respond within 8 s, escalate
        _geoclue2Timer.restart();
    }

    function _escalateToGenericSource() {
        geoclue2Source.active = false;
        _locationTier = 2;
        genericPositionSource.active = true;
        genericPositionSource.update();
        _genericSourceTimer.restart();
    }

    function _escalateToIpGeo() {
        genericPositionSource.active = false;
        _locationTier = 3;
        _ipGeolocate();
    }

    Timer {
        id: _geoclue2Timer; interval: 8000; repeat: false
        onTriggered: {
            if (_locationTier === 1) {
                console.log("[Location] GeoClue2 timed out, trying generic PositionSource…");
                _escalateToGenericSource();
            }
        }
    }
    Timer {
        id: _genericSourceTimer; interval: 8000; repeat: false
        onTriggered: {
            if (_locationTier === 2) {
                console.log("[Location] Generic PositionSource timed out, trying IP geolocation…");
                _escalateToIpGeo();
            }
        }
    }
    Timer {
        id: _ipGeoTimer; interval: 10000; repeat: false
        property var _activeReq: null
        onTriggered: {
            if (_locationTier === 3 && _activeReq) {
                console.warn("[Location] Tier 3 IP geolocation timed out");
                _activeReq.abort();
                _activeReq = null;
                _locationTier = 0;
            }
        }
    }
    Timer {
        id: _autoDetectRepeatTimer
        interval: 300000   // re-check every 5 minutes
        repeat: true
        running: Plasmoid.configuration.autoDetectLocation
        onTriggered: _startAutoDetect()
    }

    // Tier 1 — GeoClue2 explicitly
    PositionSource {
        id: geoclue2Source
        name: "geoclue2"
        active: false
        updateInterval: 300000

        onPositionChanged: {
            var c = position.coordinate;
            if (!c || !c.isValid) return;
            _geoclue2Timer.stop();
            _locationTier = 0;
            console.log("[Location] Tier 1 (GeoClue2): position acquired");
            _applyAutoPosition(c.latitude, c.longitude, c.altitude);
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && _locationTier === 1) {
                console.log("[Location] Tier 1 (GeoClue2) error:", sourceError, "— escalating");
                _geoclue2Timer.stop();
                _escalateToGenericSource();
            }
        }
    }

    // Tier 2 — any available Qt Positioning plugin
    PositionSource {
        id: genericPositionSource
        active: false
        updateInterval: 300000

        onPositionChanged: {
            var c = position.coordinate;
            if (!c || !c.isValid) return;
            _genericSourceTimer.stop();
            _locationTier = 0;
            console.log("[Location] Tier 2 (generic PositionSource): position acquired");
            _applyAutoPosition(c.latitude, c.longitude, c.altitude);
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && _locationTier === 2) {
                console.log("[Location] Tier 2 (generic) error:", sourceError, "— escalating to IP");
                _genericSourceTimer.stop();
                _escalateToIpGeo();
            }
        }
    }

    // Tier 3 — IP-based geolocation
    function _ipGeolocate() {
        console.log("[Location] Tier 3: trying geo.kamero.ai…");
        var req = new XMLHttpRequest();
        _ipGeoTimer._activeReq = req;
        _ipGeoTimer.restart();
        req.open("GET", "https://geo.kamero.ai/api/geo");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            if (req.status === 200) {
                try {
                    var data = JSON.parse(req.responseText);
                    var lat = parseFloat(data.latitude);
                    var lon = parseFloat(data.longitude);
                    if (!isNaN(lat) && !isNaN(lon)) {
                        _ipGeoTimer.stop();
                        _ipGeoTimer._activeReq = null;
                        _locationTier = 0;
                        console.log("[Location] Tier 3 (geo.kamero.ai): position acquired");
                        _applyAutoPosition(lat, lon, NaN);
                        return;
                    }
                } catch (e) { console.warn("[Location] geo.kamero.ai parse error:", e); }
            }
            // Fallback to reallyfreegeoip.org
            _ipGeolocateFallback();
        };
        req.send();
    }

    function _ipGeolocateFallback() {
        console.log("[Location] Tier 3 fallback: trying reallyfreegeoip.org…");
        var req = new XMLHttpRequest();
        _ipGeoTimer._activeReq = req;
        _ipGeoTimer.restart();
        req.open("GET", "https://reallyfreegeoip.org/json/");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            _ipGeoTimer.stop();
            _ipGeoTimer._activeReq = null;
            if (req.status === 200) {
                try {
                    var data = JSON.parse(req.responseText);
                    var lat = parseFloat(data.latitude);
                    var lon = parseFloat(data.longitude);
                    if (!isNaN(lat) && !isNaN(lon)) {
                        _locationTier = 0;
                        console.log("[Location] Tier 3 (reallyfreegeoip.org): position acquired");
                        _applyAutoPosition(lat, lon, NaN);
                        return;
                    }
                } catch (e) { console.warn("[Location] reallyfreegeoip parse error:", e); }
            }
            _locationTier = 0;
            console.warn("[Location] All 3 tiers failed — no position available");
        };
        req.send();
    }

    /**
     * Reverse-geocodes lat/lon via Nominatim and writes the nearest city
     * name directly to Plasmoid.configuration.locationName.
     * Uses the system locale language with English fallback.
     * Falls back through: city → town → village → hamlet → suburb →
     *                     municipality → county → display_name.
     */
    function _autoReverseGeocode(lat, lon) {
        var req = new XMLHttpRequest();
        var lang = Qt.locale().name.split("_")[0];
        var acceptLang = (lang.length > 0) ? lang + ",en;q=0.8" : "en";
        req.open("GET", "https://nominatim.openstreetmap.org/reverse" + "?format=jsonv2&zoom=10&addressdetails=1" + "&accept-language=" + acceptLang + "&lat=" + lat + "&lon=" + lon);
        req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status !== 200)
                return;
            try {
                var data = JSON.parse(req.responseText);
                if (!data)
                    return;
                var a = (data.address) ? data.address : {};
                var city = a.city || a.town || a.village || a.hamlet || a.suburb || a.municipality || a.county || "";
                var country = a.country || "";
                var name;
                if (city.length > 0 && country.length > 0)
                    name = city + ", " + country;
                else if (city.length > 0)
                    name = city;
                else if (country.length > 0)
                    name = country;
                else
                    name = data.display_name || "";
                if (name.length > 0)
                    Plasmoid.configuration.locationName = name;
                // Capture country code for MeteoAlarm alerts
                var cc = (a.country_code || "").toUpperCase();
                if (cc.length > 0)
                    Plasmoid.configuration.countryCode = cc;
            } catch (e) { console.warn("[Location] reverse geocode parse error:", e); }
        };
        req.send();
    }

    /** Refresh current weather + forecast (called by button, timers, config changes) */
    function refreshWeather() {
        weatherService.refreshNow();
    }

    /** Fetch hourly data for a specific date — called by FullView */
    function fetchHourlyForDate(dateStr) {
        weatherService.fetchHourlyForDate(dateStr);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Value formatters — delegate pure math to weather.js, inject config here
    // ══════════════════════════════════════════════════════════════════════

    // Returns the effective temperature unit, respecting "kde" locale mode.
    function _tempUnit() {
        if (Plasmoid.configuration.unitsMode === "kde")
            return Qt.locale().measurementSystem === 1 ? "F" : "C";
        return Plasmoid.configuration.temperatureUnit || "C";
    }
    function tempValue(celsius) {
        return W.formatTemp(celsius, _tempUnit(), Plasmoid.configuration.roundValues, Plasmoid.configuration.showTempUnit);
    }

    function _windUnit() {
        if (Plasmoid.configuration.unitsMode === "kde")
            return Qt.locale().measurementSystem === 1 ? "mph" : "kmh";
        return Plasmoid.configuration.windSpeedUnit || "kmh";
    }
    function windValue(kmh) {
        return W.formatWind(kmh, _windUnit());
    }

    function _pressureUnit() {
        if (Plasmoid.configuration.unitsMode === "kde")
            return Qt.locale().measurementSystem === 1 ? "inHg" : "hPa";
        return Plasmoid.configuration.pressureUnit || "hPa";
    }
    function pressureValue(hpa) {
        return W.formatPressure(hpa, _pressureUnit());
    }

    function _isImperial() {
        if (Plasmoid.configuration.unitsMode === "kde")
            return Qt.locale().measurementSystem === 1;
        return (_tempUnit() === "F");
    }

    function precipValue(mmh) {
        if (isNaN(mmh)) return "--";
        if (_isImperial())
            return (mmh / 25.4).toFixed(2) + " in/h";
        return mmh.toFixed(1) + " mm/h";
    }

    function precipSumText(mm) {
        if (isNaN(mm)) return "--";
        if (_isImperial())
            return (mm / 25.4).toFixed(2) + " in";
        return mm.toFixed(1) + " mm";
    }

    function uvIndexText(uv) {
        if (isNaN(uv)) return "--";
        var v = Math.round(uv * 10) / 10;
        if (v <= 2) return v + " (" + i18n("Low") + ")";
        if (v <= 5) return v + " (" + i18n("Moderate") + ")";
        if (v <= 7) return v + " (" + i18n("High") + ")";
        if (v <= 10) return v + " (" + i18n("Very High") + ")";
        return v + " (" + i18n("Extreme") + ")";
    }

    function airQualityText() {
        if (isNaN(airQualityIndex)) return "--";
        // EU AQI band
        var label = "";
        var square = "";
        if (airQualityIndex < 25)       { label = i18n("Good");           square = "\u{1F7E2}"; }  // 🟢
        else if (airQualityIndex < 50)  { label = i18n("Fair");           square = "\u{1F7E1}"; }  // 🟡
        else if (airQualityIndex < 75)  { label = i18n("Moderate");       square = "\u{1F7E0}"; }  // 🟠
        else if (airQualityIndex < 100) { label = i18n("Poor");           square = "\u{1F534}"; }  // 🔴
        else if (airQualityIndex < 150) { label = i18n("Very Poor");      square = "\u{1F7E3}"; }  // 🟣
        else                            { label = i18n("Extremely Poor"); square = "\u{1F7E4}"; }  // 🟤
        // Compute AQHI from EU AQI
        var aqhi;
        var aqi = airQualityIndex;
        if (aqi <= 0)        aqhi = 1;
        else if (aqi <= 25)  aqhi = 1 + (aqi / 25) * 2;
        else if (aqi <= 50)  aqhi = 4 + ((aqi - 25) / 25) * 2;
        else if (aqi <= 75)  aqhi = 7;
        else if (aqi <= 100) aqhi = 8 + ((aqi - 75) / 25);
        else                 aqhi = 10;
        return square + " " + label + " · " + i18n("AQI") + ": " + Math.round(aqi) + " | " + i18n("AQHI") + ": " + Math.round(aqhi);
    }

    /**
     * Returns the dominant pollen display text for the panel / tooltip chip.
     * Format: "<PollenName>: <Label> (<value>)"
     */
    function pollenText() {
        if (!pollenData || pollenData.length === 0) return "--";
        var best = null;
        for (var i = 0; i < pollenData.length; i++) {
            var p = pollenData[i];
            if (isNaN(p.value) || p.value === null) continue;
            if (!best || p.value > best.value) best = p;
        }
        if (!best) return "--";
        var label = "";
        if (best.value < 2.5)      label = i18n("Low");
        else if (best.value < 4.9) label = i18n("Moderate");
        else if (best.value < 7.3) label = i18n("High");
        else                       label = i18n("Very High");
        var name = "";
        switch (best.key) {
            case "alder":   name = i18n("Alder");   break;
            case "birch":   name = i18n("Birch");   break;
            case "grass":   name = i18n("Grass");   break;
            case "mugwort": name = i18n("Mugwort"); break;
            case "olive":   name = i18n("Olive");   break;
            case "ragweed": name = i18n("Ragweed"); break;
            default:        name = best.key;
        }
        return name + ": " + label + " (" + best.value.toFixed(1) + ")";
    }

    /**
     * Returns the space weather display text for the panel / tooltip chip.
     * Collapsed: "Kp 3.3" — or "Kp 5.0 · G1" when storm active.
     */
    function spaceWeatherText() {
        var sw = spaceWeather;
        if (!sw || isNaN(sw.kp)) return "--";
        return "Kp " + sw.kp.toFixed(1) + " · " + (sw.gScale || "G0");
    }

    function snowDepthText(cm) {
        if (isNaN(cm)) return "--";
        if (_isImperial())
            return (cm / 2.54).toFixed(1) + " in";
        return cm.toFixed(1) + " cm";
    }

    /** Returns a numeric priority for an alert color — higher = more severe. */
    function alertColorPriority(color) {
        var c = (color || "").toLowerCase();
        if (c === "red")    return 3;
        if (c === "orange") return 2;
        if (c === "yellow") return 1;
        return 0;
    }

    /**
     * Returns the single highest-priority currently-active alert,
     * or the first alert if none are active yet.
     */
    function primaryAlert() {
        if (!weatherAlerts || weatherAlerts.length === 0) return null;
        var now = new Date();
        var best = null;
        for (var i = 0; i < weatherAlerts.length; i++) {
            var a = weatherAlerts[i];
            var onset   = a.onset   ? new Date(a.onset)   : null;
            var expires = a.expires ? new Date(a.expires) : null;
            var active  = (!onset || onset <= now) && (!expires || expires >= now);
            if (!active) continue;
            if (!best || alertColorPriority(a.color) > alertColorPriority(best.color))
                best = a;
        }
        return best || weatherAlerts[0];
    }

    function alertsText() {
        if (!weatherAlerts || weatherAlerts.length === 0) return i18n("None");
        var p = primaryAlert();
        return p ? (p.displayName || p.headline || i18n("1 Alert")) : i18n("None");
    }

    function alertTypeGlyph(typeNum) {
        switch (typeNum) {
            case 1:  return "\uF050"; // wind
            case 2:  return "\uF076"; // snow/ice
            case 3:  return "\uF01E"; // thunderstorm
            case 4:  return "\uF014"; // fog
            case 5:  return "\uF072"; // high temperature
            case 6:  return "\uF076"; // low temperature
            case 7:  return "\uF0CD"; // coastal event
            case 8:  return "\uF0C7"; // forest fire
            case 9:  return "\uF076"; // avalanche
            case 10: return "\uF019"; // rain
            case 11: return "\uF04E"; // flooding
            case 12: return "\uF019"; // rain-flood
            default: return "\uF0CE"; // generic warning
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Weather code / condition helpers  (need i18n — must stay in QML)
    // ══════════════════════════════════════════════════════════════════════

    /**
     * Returns the human-readable condition string for a WMO weather code (WW).
     * Uses the full Open-Meteo / WMO WW code table.
     * Pass night=true (or call isNightTime()) to get "Clear night" for code 0.
     * Forecast rows pass no night argument — daytime descriptions are used.
     */
    function weatherCodeToText(code, night) {
        var n = (night === true);
        switch (code) {
        case 0:
            return n ? i18n("Clear night") : i18n("Clear sky");
        case 1:
            return i18n("Mainly clear");
        case 2:
            return i18n("Partly cloudy");
        case 3:
            return i18n("Overcast");
        case 45:
            return i18n("Fog");
        case 48:
            return i18n("Rime fog");
        case 51:
            return i18n("Light drizzle");
        case 53:
            return i18n("Drizzle");
        case 55:
            return i18n("Heavy drizzle");
        case 56:
            return i18n("Light freezing drizzle");
        case 57:
            return i18n("Freezing drizzle");
        case 61:
            return i18n("Light rain");
        case 63:
            return i18n("Rain");
        case 65:
            return i18n("Heavy rain");
        case 66:
            return i18n("Light freezing rain");
        case 67:
            return i18n("Freezing rain");
        case 71:
            return i18n("Light snow");
        case 73:
            return i18n("Snow");
        case 75:
            return i18n("Heavy snow");
        case 77:
            return i18n("Snow grains");
        case 80:
            return i18n("Light showers");
        case 81:
            return i18n("Showers");
        case 82:
            return i18n("Heavy showers");
        case 85:
            return i18n("Light snow showers");
        case 86:
            return i18n("Snow showers");
        case 95:
            return i18n("Thunderstorm");
        case 96:
            return i18n("Thunderstorm with hail");
        case 99:
            return i18n("Heavy thunderstorm with hail");
        default:
            return i18n("Partly cloudy");
        }
    }

    /** Returns the condition icon SVG stem for a weather code + night flag. */
    function _conditionSvgStem(code, night) {
        return IconResolver._conditionSvgStem(code, night);
    }

    // Icons base directory — resolved once so it works in all contexts
    readonly property string _iconsBaseDir: Qt.resolvedUrl("../icons/") + ""

    function getSimpleModeIconSource() {
        var theme = Plasmoid.configuration.panelIconTheme || "wi-font";
        var code  = weatherCode;
        var night = isNightTime();
        var style = Plasmoid.configuration.panelSimpleIconStyle || "symbolic";
        // Custom style: use per-condition custom icons from panelCustomIcons
        if (style === "custom") {
            var customMap = {};
            var raw = Plasmoid.configuration.panelCustomIcons || "";
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        customMap[kv[0].trim()] = kv[1].trim();
                });
            }
            if (customMap["condition-custom"] === "1") {
                var condKey = _resolveConditionKey(code, night);
                if (condKey in customMap && customMap[condKey].length > 0)
                    return customMap[condKey];
            }
            return W.weatherCodeToIcon(code, night);
        }
        if (style === "colorful" || theme === "kde" || theme === "custom")
            return W.weatherCodeToIcon(code, night);
        var iconSz = Plasmoid.configuration.panelIconSize || 22;
        var resolvedTheme = (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light")
            ? "symbolic-light" : theme;
        return IconResolver.svgUrl(IconResolver._conditionSvgStem(code, night), iconSz, _iconsBaseDir, resolvedTheme);
    }

    function getMultilineModeIconSource() {
        var code  = weatherCode;
        var night = isNightTime();
        var style = Plasmoid.configuration.panelMultilineIconStyle || "colorful";
        if (style === "custom") {
            var customMap = {};
            var raw = Plasmoid.configuration.panelCustomIcons || "";
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        customMap[kv[0].trim()] = kv[1].trim();
                });
            }
            if (customMap["condition-custom"] === "1") {
                var condKey = _resolveConditionKey(code, night);
                if (condKey in customMap && customMap[condKey].length > 0)
                    return customMap[condKey];
            }
            return W.weatherCodeToIcon(code, night);
        }
        return W.weatherCodeToIcon(code, night);
    }

    function getSimpleModeIconChar() {
        var code = weatherCode;
        var night = isNightTime();
        if (code === 0)
            return night ? "\uF02E" : "\uF00D";
        if (code <= 2)
            return night ? "\uF086" : "\uF002";
        if (code === 3)
            return "\uF013";
        if (code <= 48)
            return "\uF014";
        if (code <= 65)
            return night ? "\uF028" : "\uF019";
        if (code <= 75)
            return "\uF064";
        if (code <= 99)
            return "\uF01E";
        return "\uF041";
    }

    function isNightTime() {
        // Prefer the API-reported is_day flag — accurate on first load
        // before sunrise/sunset strings have been populated.
        if (isDay >= 0)
            return isDay === 0;
        // Fallback: derive from stored sunrise/sunset times.
        var now = new Date();
        var nowMins = now.getHours() * 60 + now.getMinutes();
        function parseMins(t) {
            if (!t || t === "--")
                return -1;
            var p = t.split(":");
            return (p.length < 2) ? -1 : parseInt(p[0]) * 60 + parseInt(p[1]);
        }
        var rise = parseMins(sunriseTimeText);
        var set_ = parseMins(sunsetTimeText);
        if (rise < 0 || set_ < 0)
            return false;
        return nowMins < rise || nowMins >= set_;
    }

    // ══════════════════════════════════════════════════════════════════════
    // Moon phase helpers  (i18n wrapping for labels done here)
    // ══════════════════════════════════════════════════════════════════════

    function moonPhaseLabel() {
        // Each string is a literal so xgettext can extract all 8 translations.
        // moonPhaseNameKey() returns the English key; we map it here.
        var key = Moon.moonPhaseNameKey(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
        if (key === "New Moon")
            return i18n("New Moon");
        if (key === "Waxing Crescent")
            return i18n("Waxing Crescent");
        if (key === "First Quarter")
            return i18n("First Quarter");
        if (key === "Waxing Gibbous")
            return i18n("Waxing Gibbous");
        if (key === "Full Moon")
            return i18n("Full Moon");
        if (key === "Waning Gibbous")
            return i18n("Waning Gibbous");
        if (key === "Last Quarter")
            return i18n("Last Quarter");
        if (key === "Waning Crescent")
            return i18n("Waning Crescent");
        return key; // fallback: untranslated (should never be reached)
    }

    function moonPhaseGlyph() {
        return Moon.moonPhaseFontIcon(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
    }

    /** Compute moonrise / moonset using suncalc.js and update root properties */
    function _computeMoonTimes() {
        var lat = Plasmoid.configuration.latitude;
        var lon = Plasmoid.configuration.longitude;
        if (isNaN(lat) || isNaN(lon) || (lat === 0 && lon === 0)) {
            moonriseTimeText = "--";
            moonsetTimeText = "--";
            return;
        }
        var t = SC.getMoonTimes(new Date(), lat, lon, locationUtcOffsetMins);
        moonriseTimeText = t.rise || "--";
        moonsetTimeText  = t.set  || "--";
    }

    onLoadingChanged: {
        if (!loading && !isNaN(temperatureC))
            _computeMoonTimes();
    }

    // ══════════════════════════════════════════════════════════════════════
    // Panel item helpers — used by CompactView to build panel chips
    // ══════════════════════════════════════════════════════════════════════

    function parseSunTimeMins(t) {
        if (!t || t === "--")
            return -1;
        var p = t.split(":");
        return (p.length < 2) ? -1 : parseInt(p[0]) * 60 + parseInt(p[1]);
    }

    /**
     * Re-formats an internal "HH:mm" (24 h) string to the system locale short
     * time format.  Qt.locale().timeFormat(Locale.ShortFormat) returns the
     * platform time format string, e.g. "h:mm AP" (12 h) or "HH:mm" (24 h).
     * Using Qt.formatTime on a synthetic Date applies that format correctly
     * without any manual AM/PM logic.
     */
    function formatTimeForDisplay(hhmmStr) {
        if (!hhmmStr || hhmmStr === "--")
            return "--";
        var parts = hhmmStr.split(":");
        if (parts.length < 2)
            return hhmmStr;
        var h = parseInt(parts[0], 10);
        var m = parseInt(parts[1], 10);
        if (isNaN(h) || isNaN(m))
            return hhmmStr;
        var d = new Date();
        d.setHours(h, m, 0, 0);
        return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function parsePanelItemIcons() {
        var raw = Plasmoid.configuration.panelItemIcons || "";
        var map = {};
        raw.split(";").forEach(function (pair) {
            var kv = pair.split("=");
            if (kv.length === 2)
                map[kv[0].trim()] = (kv[1].trim() === "1");
        });
        return map;
    }

    /** Returns the wi-font glyph (or Kirigami icon name) for a panel chip */
    function panelItemGlyph(tok) {
        if (tok === "temperature")
            return "\uF055";        // wi-thermometer
        if (tok === "feelslike")
            return "\uF055";        // wi-thermometer
        if (tok === "humidity")
            return "\uF07A";        // wi-humidity
        if (tok === "pressure")
            return "\uF079";        // wi-barometer
        if (tok === "location")
            return "\uF0B1";       // wi-direction (F0B1)
        if (tok === "moonphase") {
            var mm = Plasmoid.configuration.panelMoonPhaseMode || "full";
            if (mm === "moonrise") return "\uF0C9";
            if (mm === "moonset") return "\uF0CA";
            if (mm === "upcoming-times") return _moonUpcoming() === "rise" ? "\uF0C9" : "\uF0CA";
            return moonPhaseGlyph();
        }
        if (tok === "moonphase-moonrise")
            return "\uF0C9";
        if (tok === "moonphase-moonset")
            return "\uF0CA";
        if (tok === "wind")
            return W.windDirectionGlyph(windDirection);
        if (tok === "condition") {
            var n = isNightTime(), c = weatherCode;
            if (c === 0)
                return n ? "\uF02E" : "\uF00D";
            if (c <= 2)
                return n ? "\uF086" : "\uF002";
            if (c === 3)
                return "\uF013";
            if (c === 45 || c === 48)
                return "\uF014";
            if (c <= 65)
                return n ? "\uF028" : "\uF019";
            if (c <= 75)
                return "\uF064";
            if (c <= 99)
                return "\uF01E";
            return "\uF041";
        }
        if (tok === "suntimes") {
            var mode = Plasmoid.configuration.panelSunTimesMode || "upcoming";
            if (mode === "sunset")
                return "\uF052";
            var nowMins = (new Date()).getHours() * 60 + (new Date()).getMinutes();
            var riseMins = parseSunTimeMins(sunriseTimeText);
            var setMins = parseSunTimeMins(sunsetTimeText);
            if (mode === "upcoming") {
                if (riseMins >= 0 && nowMins < riseMins)
                    return "\uF051";
                if (setMins >= 0 && nowMins < setMins)
                    return "\uF052";
            }
            return "\uF051";
        }
        if (tok === "preciprate")
            return "\uF04E";        // wi-sprinkle (rain drop)
        if (tok === "precipsum")
            return "\uF07C";        
        if (tok === "uvindex")
            return "\uF072";        // wi-hot
        if (tok === "airquality")
            return "\uF074";        // wi-smog
        if (tok === "pollen")
            return "\uF082";        // wi-sandstorm
        if (tok === "spaceweather")
            return "\uF06E";        // wi-solar-eclipse
        if (tok === "alerts") {
            var pa = primaryAlert();
            if (pa) return alertTypeGlyph(pa.awarenessType || 0);
            return "\uF0CE";        // wi-gale-warning (flag)
        }
        if (tok === "snowcover")
            return "\uF076";        // wi-snowflake-cold
        return "";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // panelItemIconInfo(tok) — returns { type, source } for the active icon theme
    //
    //   type: "wi"       → wi-font glyph char (Text element)
    //         "kirigami" → Kirigami icon name
    //         "svg"      → resolved URL of an SVG in contents/icons/<theme>/
    //         "kde"      → KDE system icon name (Kirigami.Icon, may be missing)
    //
    // SVG file name convention (files must exist under contents/icons/<theme>/):
    //   thermometer.svg  humidity.svg  barometer.svg  wind.svg
    //   sunrise.svg  sunset.svg  location.svg
    //   condition-<code>.svg  (e.g. condition-0.svg for clear sky)
    //   moon-<phase>.svg  (e.g. wi-moon-alt-full.svg)
    // ─────────────────────────────────────────────────────────────────────────
    function panelItemIconInfo(tok) {
        var theme = Plasmoid.configuration.panelIconTheme || "wi-font";

        // ── Font icons (default) ──────────────────────────────────────────────
        if (theme === "wi-font") {
            var g = panelItemGlyph(tok);
            return { type: "wi", source: g, svgFallback: "", isMask: false };
        }

        // ── Custom icon theme — user picks each icon individually ────────────
        if (theme === "custom") {
            var customMap = {};
            var raw = Plasmoid.configuration.panelCustomIcons || "";
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        customMap[kv[0].trim()] = kv[1].trim();
                });
            }
            var defaults = {
                condition: W.weatherCodeToIcon(weatherCode, isNightTime()),
                temperature: "thermometer",
                feelslike: "thermometer",
                humidity: "weather-showers",
                pressure: "weather-overcast",
                wind: "weather-windy",
                moonphase: "weather-clear-night",
                location: "mark-location",
                preciprate: "weather-showers",
                precipsum: "flood",
                uvindex: "weather-clear",
                airquality: "weather-many-clouds",
                pollen: "sandstorm",
                spaceweather: "stars",
                alerts: "weather-storm",
                snowcover: "weather-snow-scattered"
            };

            if (tok === "condition") {
                if (customMap["condition-custom"] === "1") {
                    var code2 = weatherCode;
                    var night2 = isNightTime();
                    var condKey = _resolveConditionKey(code2, night2);
                    var fallback2 = W.weatherCodeToIcon(code2, night2);
                    var condSaved2 = (condKey in customMap && customMap[condKey].length > 0) ? customMap[condKey] : fallback2;
                    return { type: "kde", source: condSaved2, svgFallback: "", isMask: false };
                }
                return { type: "kde", source: W.weatherCodeToIcon(weatherCode, isNightTime()), svgFallback: "", isMask: false };
            }

            if (tok === "suntimes") {
                var mode2 = Plasmoid.configuration.panelSunTimesMode || "upcoming";
                var nowM2 = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                var riseM2 = parseSunTimeMins(sunriseTimeText);
                var setM2 = parseSunTimeMins(sunsetTimeText);
                var useSet2 = (mode2 === "sunset") || (mode2 === "upcoming" && riseM2 >= 0 && nowM2 >= riseM2 && (setM2 < 0 || nowM2 < setM2));
                var sunKey2 = useSet2 ? "suntimes-sunset" : "suntimes-sunrise";
                var sunDef2 = useSet2 ? "weather-sunset" : "weather-sunrise";
                var sunSaved2 = (sunKey2 in customMap && customMap[sunKey2].length > 0) ? customMap[sunKey2] : sunDef2;
                return { type: "kde", source: sunSaved2, svgFallback: "", isMask: false };
            }

            if (tok === "moonphase" || tok === "moonphase-moonrise" || tok === "moonphase-moonset") {
                if (tok === "moonphase-moonrise") {
                    var mrSaved = (("moonrise" in customMap) && customMap["moonrise"].length > 0) ? customMap["moonrise"] : "weather-clear-night";
                    return { type: "kde", source: mrSaved, svgFallback: "", isMask: false };
                }
                if (tok === "moonphase-moonset") {
                    var msSaved = (("moonset" in customMap) && customMap["moonset"].length > 0) ? customMap["moonset"] : "weather-clear-night";
                    return { type: "kde", source: msSaved, svgFallback: "", isMask: false };
                }
                var mm2 = Plasmoid.configuration.panelMoonPhaseMode || "full";
                if (mm2 === "moonrise") {
                    var mrS2 = (("moonrise" in customMap) && customMap["moonrise"].length > 0) ? customMap["moonrise"] : "weather-clear-night";
                    return { type: "kde", source: mrS2, svgFallback: "", isMask: false };
                }
                if (mm2 === "moonset") {
                    var msS2 = (("moonset" in customMap) && customMap["moonset"].length > 0) ? customMap["moonset"] : "weather-clear-night";
                    return { type: "kde", source: msS2, svgFallback: "", isMask: false };
                }
                if (mm2 === "upcoming-times") {
                    var utKey = _moonUpcoming() === "rise" ? "moonrise" : "moonset";
                    var utSaved = ((utKey in customMap) && customMap[utKey].length > 0) ? customMap[utKey] : "weather-clear-night";
                    return { type: "kde", source: utSaved, svgFallback: "", isMask: false };
                }
                // Phase-showing modes: use bundled SVG moon phase icon
                var iconSzC = Plasmoid.configuration.panelIconSize || 22;
                var moonStemC = Moon.moonPhaseSvgStem(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
                return IconResolver.resolveMoonPhase(moonStemC, iconSzC, _iconsBaseDir, "flat-color");
            }

            var iconName = (tok in customMap && customMap[tok].length > 0) ? customMap[tok] : (tok in defaults ? defaults[tok] : "");
            return { type: "kde", source: iconName, svgFallback: "", isMask: false };
        }

        // ── KDE / SVG themes — unified via IconResolver ──────────────────────
        // KDE theme: KDE icon primary, symbolic SVG fallback.
        // SVG themes: SVG primary, KDE fallback.
        // KDE theme: KDE primary, symbolic SVG fallback (handled by IconResolver).
        var iconSz = Plasmoid.configuration.panelIconSize || 22;
        var svgTheme = (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light")
            ? "symbolic-light" : theme;

        // Dynamic items: condition, suntimes, moonphase
        if (tok === "condition")
            return IconResolver.resolveCondition(weatherCode, isNightTime(), iconSz, _iconsBaseDir, svgTheme);

        if (tok === "suntimes") {
            var sunTok = _resolveSuntimesTok();
            return IconResolver.resolve(sunTok, iconSz, _iconsBaseDir, svgTheme);
        }

        if (tok === "moonphase" || tok === "moonphase-moonrise" || tok === "moonphase-moonset") {
            if (tok === "moonphase-moonrise")
                return IconResolver.resolve("moonrise", iconSz, _iconsBaseDir, svgTheme);
            if (tok === "moonphase-moonset")
                return IconResolver.resolve("moonset", iconSz, _iconsBaseDir, svgTheme);
            var mm3 = Plasmoid.configuration.panelMoonPhaseMode || "full";
            if (mm3 === "moonrise") return IconResolver.resolve("moonrise", iconSz, _iconsBaseDir, svgTheme);
            if (mm3 === "moonset") return IconResolver.resolve("moonset", iconSz, _iconsBaseDir, svgTheme);
            if (mm3 === "upcoming-times") return IconResolver.resolve(_moonUpcoming() === "rise" ? "moonrise" : "moonset", iconSz, _iconsBaseDir, svgTheme);
            var moonStem = Moon.moonPhaseSvgStem(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
            return IconResolver.resolveMoonPhase(moonStem, iconSz, _iconsBaseDir, svgTheme);
        }

        // Standard items: temperature, humidity, pressure, wind, location, etc.
        return IconResolver.resolve(tok, iconSz, _iconsBaseDir, svgTheme);
    }

    /** Determines whether to show sunrise or sunset for suntimes panel item */
    function _resolveSuntimesTok() {
        var mode = Plasmoid.configuration.panelSunTimesMode || "upcoming";
        if (mode === "sunset") return "suntimes-sunset";
        if (mode === "sunrise") return "suntimes-sunrise";
        if (mode === "both") return "suntimes-sunrise"; // CompactView handles both-mode split
        // "upcoming": pick based on current time
        var nowM = (new Date()).getHours() * 60 + (new Date()).getMinutes();
        var riseM = parseSunTimeMins(sunriseTimeText);
        var setM = parseSunTimeMins(sunsetTimeText);
        var useSet = (riseM >= 0 && nowM >= riseM && (setM < 0 || nowM < setM));
        return useSet ? "suntimes-sunset" : "suntimes-sunrise";
    }

    /** Returns "rise" or "set" depending on which moon event is next */
    function _moonUpcoming() {
        var nowM = (new Date()).getHours() * 60 + (new Date()).getMinutes();
        var riseM = parseSunTimeMins(moonriseTimeText);
        var setM = parseSunTimeMins(moonsetTimeText);
        if (riseM >= 0 && nowM < riseM) return "rise";
        if (setM >= 0 && nowM < setM) return "set";
        return "rise";
    }

    /** Maps a WMO code + night flag to a condition custom icon key */
    function _resolveConditionKey(code, night) {
        if (code === 0) return night ? "condition-clear-night" : "condition-clear";
        if (code === 1) return night ? "condition-few-clouds-night" : "condition-few-clouds";
        if (code === 2) return night ? "condition-cloudy-night" : "condition-cloudy-day";
        if (code === 3) return "condition-overcast";
        if (code === 45 || code === 48) return "condition-fog";
        if (code === 51 || code === 53 || code === 55 || code === 61 || code === 80)
            return night ? "condition-showers-scattered-night" : "condition-showers-scattered-day";
        if (code === 63 || code === 65 || code === 81 || code === 82)
            return night ? "condition-showers-night" : "condition-showers-day";
        if (code === 56 || code === 66)
            return night ? "condition-freezing-scattered-rain-night" : "condition-freezing-scattered-rain-day";
        if (code === 57 || code === 67)
            return night ? "condition-freezing-rain-night" : "condition-freezing-rain-day";
        if (code === 71 || code === 77 || code === 85)
            return night ? "condition-snow-scattered-night" : "condition-snow-scattered-day";
        if (code === 73 || code === 75 || code === 86)
            return night ? "condition-snow-night" : "condition-snow-day";
        if (code === 95) return night ? "condition-storm-night" : "condition-storm-day";
        if (code === 96) return night ? "condition-hail-storm-rain-night" : "condition-hail-storm-rain-day";
        if (code === 99) return night ? "condition-hail-storm-snow-night" : "condition-hail-storm-snow-day";
        return night ? "condition-clear-night" : "condition-clear";
    }


    /** Returns the display text for a panel chip */
    function panelItemTextOnly(tok) {
        var mode = Plasmoid.configuration.panelSunTimesMode || "upcoming";
        if (tok === "location")
            return (Plasmoid.configuration.locationName || "").split(",")[0].trim();
        if (tok === "temperature")
            return tempValue(temperatureC);
        if (tok === "condition")
            return weatherCodeToText(weatherCode, isNightTime());
        if (tok === "wind")
            return windValue(windKmh);
        if (tok === "feelslike")
            return tempValue(apparentC);
        if (tok === "humidity")
            return isNaN(humidityPercent) ? "--" : Math.round(humidityPercent) + "%";
        if (tok === "pressure")
            return pressureValue(pressureHpa);
        if (tok === "moonphase" || tok === "moonphase-moonrise" || tok === "moonphase-moonset") {
            if (tok === "moonphase-moonrise")
                return formatTimeForDisplay(moonriseTimeText);
            if (tok === "moonphase-moonset")
                return formatTimeForDisplay(moonsetTimeText);
            var mm = Plasmoid.configuration.panelMoonPhaseMode || "full";
            if (mm === "phase") return moonPhaseLabel();
            if (mm === "moonrise") return formatTimeForDisplay(moonriseTimeText);
            if (mm === "moonset") return formatTimeForDisplay(moonsetTimeText);
            if (mm === "upcoming-times")
                return _moonUpcoming() === "rise" ? formatTimeForDisplay(moonriseTimeText) : formatTimeForDisplay(moonsetTimeText);
            // "full", "upcoming", "times" — main chip shows phase label; CompactView handles multi-chip
            return moonPhaseLabel();
        }
        if (tok === "suntimes") {
            var nowMins = (new Date()).getHours() * 60 + (new Date()).getMinutes();
            var riseMins = parseSunTimeMins(sunriseTimeText);
            var setMins = parseSunTimeMins(sunsetTimeText);
            if (mode === "upcoming") {
                if (riseMins >= 0 && nowMins < riseMins)
                    return formatTimeForDisplay(sunriseTimeText);
                if (setMins >= 0 && nowMins < setMins)
                    return formatTimeForDisplay(sunsetTimeText);
                return formatTimeForDisplay(sunriseTimeText);
            }
            if (mode === "sunrise")
                return formatTimeForDisplay(sunriseTimeText);
            if (mode === "sunset")
                return formatTimeForDisplay(sunsetTimeText);
            return formatTimeForDisplay(sunriseTimeText) + " / " + formatTimeForDisplay(sunsetTimeText);
        }
        if (tok === "preciprate")
            return precipValue(precipMmh);
        if (tok === "precipsum")
            return precipSumText(precipSumMm);
        if (tok === "uvindex")
            return uvIndexText(uvIndex);
        if (tok === "airquality")
            return airQualityText();
        if (tok === "pollen")
            return pollenText();
        if (tok === "spaceweather")
            return spaceWeatherText();
        if (tok === "alerts")
            return alertsText();
        if (tok === "snowcover")
            return snowDepthText(snowDepthCm);
        return "";
    }

    // ══════════════════════════════════════════════════════════════════════
    // Font helper — sub-views call weatherRoot.wf(px, bold)
    // ══════════════════════════════════════════════════════════════════════

    function wf(pixelSize, bold) {
        if (Plasmoid.configuration.useSystemFont)
            return Qt.font({
                bold: bold || false
            });
        return Qt.font({
            family: Plasmoid.configuration.fontFamily || "sans-serif",
            pixelSize: Plasmoid.configuration.fontSize ? Plasmoid.configuration.fontSize + (pixelSize - 11) : pixelSize,
            bold: (Plasmoid.configuration.fontBold || bold) || false
        });
    }

    // wpf() — panel-specific font (uses panelUseSystemFont / panelFontFamily / panelFontBold).
    // The pixelSize parameter is always used as-is (multiline derives it from row height;
    // single-line passes panelFontPx which already incorporates panelFontSize).
    // wpf() — panel font; in manual mode converts stored pointSize to pixelSize.
    // Platform.FontDialog returns pointSize; Qt.font() needs pixelSize.
    // Standard 96 dpi conversion: 1pt = 4/3 px.
    function wpf(pixelSize, bold) {
        if (Plasmoid.configuration.panelUseSystemFont)
            return Qt.font({
                pixelSize: pixelSize,
                bold: bold || false
            });
        var savedPt = Plasmoid.configuration.panelFontSize || 0;
        var usePx = (savedPt > 0) ? Math.round(savedPt * 4 / 3) : pixelSize;
        return Qt.font({
            family: Plasmoid.configuration.panelFontFamily || Kirigami.Theme.defaultFont.family,
            pixelSize: usePx,
            bold: (Plasmoid.configuration.panelFontBold || bold) || false
        });
    }

    // ══════════════════════════════════════════════════════════════════════
    // Navigation helpers
    // ══════════════════════════════════════════════════════════════════════

    function openLocationSettings() {
        var action = Plasmoid.internalAction("configure");
        if (action)
            action.trigger();
    }

    // ══════════════════════════════════════════════════════════════════════
    // Timers
    // ══════════════════════════════════════════════════════════════════════

    // Auto-refresh weather data
    Timer {
        interval: Math.max(5, Plasmoid.configuration.refreshIntervalMinutes) * 60000
        running: Plasmoid.configuration.autoRefresh
        repeat: true
        onTriggered: refreshWeather()
    }

    // Config-change debounce — coalesces rapid-fire signals that occur when
    // KDE KCM applies all cfg_ values at once on Apply/OK.  latitude, longitude,
    // timezone and locationName are written to Plasmoid.configuration one by one;
    // each triggers onXxxChanged → without debouncing, refreshWeather() fires
    // with only the first value updated (e.g. lat written, lon still 0) which
    // sends a bad API request and shows garbage data.  The 350 ms window allows
    // all config keys to settle before a single real refresh is performed.
    Timer {
        id: refreshDebounce
        interval: 350
        repeat: false
        onTriggered: refreshWeather()
    }

    // Panel scroll ticker removed — "scroll/cycle" mode was removed.
    // The multiline Timer in CompactView.qml handles scrolling independently.


    // ══════════════════════════════════════════════════════════════════════
    // Startup + config change reactions
    // ══════════════════════════════════════════════════════════════════════

    Component.onCompleted: {
        // DefaultBackground: Plasma draws the standard widget frame on the desktop.
        // ConfigurableBackground: tells Plasma to show the "Show / Hide background"
        // toggle button when the widget is on the desktop in edit mode.
        // Must be set here (not as a static binding) so Plasma picks it up after
        // the component is fully live — same pattern used by Wunderground and others.
        Plasmoid.backgroundHints = PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground;
        refreshDebounce.restart();
        if (Plasmoid.configuration.autoDetectLocation)
            _startAutoDetect();
    }

    Connections {
        target: Plasmoid.configuration
        function onLocationNameChanged() {
            refreshDebounce.restart();
        }
        function onLatitudeChanged() {
            refreshDebounce.restart();
        }
        function onLongitudeChanged() {
            refreshDebounce.restart();
        }
        function onTimezoneChanged() {
            refreshDebounce.restart();
        }
        function onWeatherProviderChanged() {
            refreshDebounce.restart();
        }
        function onForecastDaysChanged() {
            refreshDebounce.restart();
        }
        function onPanelInfoModeChanged() {
            root.panelScrollIndex = 0;
        }
    }
}
