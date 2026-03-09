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

PlasmoidItem {
    id: root

    implicitWidth: 540
    implicitHeight: 550
    switchWidth: 200
    switchHeight: 100
    preferredRepresentation: fullRepresentation

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
    property string sunriseTimeText: "--"
    property string sunsetTimeText: "--"
    property int weatherCode: -1
    property int isDay: -1   // -1=unknown, 0=night, 1=day (populated by API when available)
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
    }

    // And update it when the full representation is created:
    onFullRepresentationItemChanged: {
        fullViewItem = fullRepresentationItem;
    }

    // ══════════════════════════════════════════════════════════════════════
    // Service — all API calls delegated to WeatherService
    // ══════════════════════════════════════════════════════════════════════

    WeatherService {
        id: weatherService
        weatherRoot: root
    }

    // ══════════════════════════════════════════════════════════════════════
    // Auto-detect location — runs even without opening the settings dialog.
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

    PositionSource {
        id: mainPositionSource
        active: Plasmoid.configuration.autoDetectLocation
        updateInterval: 300000   // re-check every 5 minutes

        onPositionChanged: {
            var c = position.coordinate;
            if (!c || !c.isValid)
                return;
            var lat = c.latitude;
            var lon = c.longitude;

            // Persist coordinates immediately — this is what triggers
            // onLatitudeChanged / onLongitudeChanged in the Connections block
            // below and therefore the weather refresh.
            Plasmoid.configuration.latitude = lat;
            Plasmoid.configuration.longitude = lon;
            if (!isNaN(c.altitude) && c.altitude > 0)
                Plasmoid.configuration.altitude = Math.round(c.altitude);

            // Only silently update the name when one is already confirmed.
            // If locationName is empty the user hasn't yet seen the
            // "Confirm your location" dialog — don't bypass it by writing a
            // name from here; let configLocation.qml handle first-time naming.
            if ((Plasmoid.configuration.locationName || "").trim().length > 0)
                _autoReverseGeocode(lat, lon);
        }

        onSourceErrorChanged: {
            // GeoClue2 unavailable — silently ignore so the widget still
            // shows weather for any manually-stored coordinates.
            if (sourceError !== PositionSource.NoError)
                console.warn("PositionSource error:", sourceError);
        }
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
            } catch (e) {}
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
        return W.formatTemp(celsius, _tempUnit(), Plasmoid.configuration.roundValues);
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

    function getSimpleModeIconSource() {
        var theme = Plasmoid.configuration.panelIconTheme || "wi-font";
        var code = weatherCode;
        var night = isNightTime();
        var style = Plasmoid.configuration.panelSimpleIconStyle || "symbolic";

        // For colorful style, always use KDE system icons (they are naturally colorful)
        if (style === "colorful" || theme === "kde" || theme === "custom") {
            return W.weatherCodeToIcon(code, night);
        } else {
            // For SVG themes, return the appropriate SVG path
            var iconSz = Plasmoid.configuration.panelIconSize || 22;
            var resolvedTheme = theme;
            if (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light")
                resolvedTheme = "symbolic-light";
            var base = Qt.resolvedUrl("../icons/" + resolvedTheme + "/" + iconSz + "/wi-");

            var stem;
            if (code === 0)
                stem = night ? "night-clear" : "day-sunny";
            else if (code <= 2)
                stem = night ? "night-alt-partly-cloudy" : "day-cloudy";
            else if (code === 3)
                stem = "cloudy";
            else if (code <= 48)
                stem = night ? "night-fog" : "day-fog";
            else if (code <= 65)
                stem = night ? "night-alt-rain" : "day-rain";
            else if (code <= 75)
                stem = night ? "night-alt-snow" : "day-snow";
            else
                stem = night ? "night-alt-thunderstorm" : "day-thunderstorm";

            return base + stem + ".svg";
        }
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
        var key = Moon.moonPhaseNameKey();
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
        return Moon.moonPhaseFontIcon();
    }
    function moonPhaseSvgUrl() {
        return Qt.resolvedUrl("../icons/wi-" + Moon.moonPhaseSvgStem() + ".svg");
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
        if (tok === "moonphase")
            return moonPhaseGlyph();
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
            // location: F0B1 renders via wi-font Text element
            return {
                type: "wi",
                source: g
            };
        }

        // ── Custom icon theme — user picks each icon individually ────────────
        if (theme === "custom") {
            // Parse saved mapping: "location=mark-location;temperature=thermometer;..."
            var customMap = {};
            var raw = Plasmoid.configuration.panelCustomIcons || "";
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        customMap[kv[0].trim()] = kv[1].trim();
                });
            }
            // Default KDE fallbacks when no custom icon saved for this item
            var defaults = {
                condition: W.weatherCodeToIcon(weatherCode, isNightTime()),
                temperature: "thermometer",
                feelslike: "thermometer",
                humidity: "weather-showers",
                pressure: "weather-overcast",
                wind: "weather-windy",
                moonphase: "weather-clear-night",
                location: "mark-location"
            };

            // Condition: per-weather-code custom icons when condition-custom=1
            if (tok === "condition") {
                if (customMap["condition-custom"] === "1") {
                    var code2 = weatherCode;
                    var night2 = isNightTime();
                    var condKey;
                    if (code2 === 0)
                        condKey = night2 ? "condition-clear-night" : "condition-clear";
                    else if (code2 <= 2)
                        condKey = night2 ? "condition-cloudy-night" : "condition-cloudy-day";
                    else if (code2 === 3)
                        condKey = "condition-overcast";
                    else if (code2 <= 48)
                        condKey = "condition-fog";
                    else if (code2 <= 65)
                        condKey = "condition-rain";
                    else if (code2 <= 75)
                        condKey = "condition-snow";
                    else
                        condKey = "condition-storm";
                    var fallback2 = W.weatherCodeToIcon(code2, night2);
                    var condSaved2 = (condKey in customMap && customMap[condKey].length > 0) ? customMap[condKey] : fallback2;
                    return {
                        type: "kde",
                        source: condSaved2
                    };
                }
                // KDE mode (condition-custom not set) → system icon based on weather code
                return {
                    type: "kde",
                    source: W.weatherCodeToIcon(weatherCode, isNightTime())
                };
            }

            // Suntimes: pick sunrise or sunset icon independently
            if (tok === "suntimes") {
                var mode2 = Plasmoid.configuration.panelSunTimesMode || "upcoming";
                var nowM2 = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                var riseM2 = parseSunTimeMins(sunriseTimeText);
                var setM2 = parseSunTimeMins(sunsetTimeText);
                var useSet2 = (mode2 === "sunset") || (mode2 === "upcoming" && riseM2 >= 0 && nowM2 >= riseM2 && (setM2 < 0 || nowM2 < setM2));
                var sunKey2 = useSet2 ? "suntimes-sunset" : "suntimes-sunrise";
                var sunDef2 = useSet2 ? "weather-sunset" : "weather-sunrise";
                var sunSaved2 = (sunKey2 in customMap && customMap[sunKey2].length > 0) ? customMap[sunKey2] : sunDef2;
                return {
                    type: "kde",
                    source: sunSaved2
                };
            }

            var iconName = (tok in customMap && customMap[tok].length > 0) ? customMap[tok] : (tok in defaults ? defaults[tok] : "");
            return {
                type: "kde",
                source: iconName
            };
        }

        // ── KDE system theme ──────────────────────────────────────────────────
        if (theme === "kde") {
            if (tok === "temperature" || tok === "feelslike")
                return {
                    type: "kde",
                    source: "temperature"
                };
            if (tok === "humidity")
                return {
                    type: "kde",
                    source: "weather-humidity"
                };
            if (tok === "pressure")
                return {
                    type: "kde",
                    source: "weather-pressure"
                };
            if (tok === "wind")
                return {
                    type: "kde",
                    source: "weather-wind-beaufort-0"
                };
            if (tok === "condition")
                return {
                    type: "kde",
                    source: W.weatherCodeToIcon(weatherCode, isNightTime())
                };
            if (tok === "suntimes") {
                var mode3 = Plasmoid.configuration.panelSunTimesMode || "upcoming";
                var nowM3 = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                var riseM3 = parseSunTimeMins(sunriseTimeText);
                var setM3 = parseSunTimeMins(sunsetTimeText);
                var useSet3 = (mode3 === "sunset") || (mode3 === "upcoming" && riseM3 >= 0 && nowM3 >= riseM3 && (setM3 < 0 || nowM3 < setM3));
                return {
                    type: "kde",
                    source: useSet3 ? "weather-sunset" : "weather-sunrise"
                };
            }
            if (tok === "moonphase")
                return {
                    type: "kde",
                    source: "weather-clear-night"
                };
            if (tok === "location")
                return {
                    type: "kde",
                    source: "mark-location"
                };
            return {
                type: "kde",
                source: ""
            };
        }

        // ── SVG themes: symbolic | flat-color | 3d-oxygen | 3d-adwaita ───────
        // Files live under icons/<theme>/32/wi-<name>.svg
        // Using size 32 as a safe universal size that all themes provide.
        var iconSz = Plasmoid.configuration.panelIconSize || 22;
        // For symbolic theme, the light variant uses a parallel folder "symbolic-light".
        // All other themes are not affected.
        var resolvedTheme = theme;
        if (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light")
            resolvedTheme = "symbolic-light";
        var base = Qt.resolvedUrl("../icons/" + resolvedTheme + "/" + iconSz + "/wi-");

        if (tok === "temperature" || tok === "feelslike")
            return {
                type: "svg",
                source: base + "thermometer.svg"
            };
        if (tok === "humidity")
            return {
                type: "svg",
                source: base + "humidity.svg"
            };
        if (tok === "pressure")
            return {
                type: "svg",
                source: base + "barometer.svg"
            };
        if (tok === "wind")
            return {
                type: "svg",
                source: base + "strong-wind.svg"
            };
        // Use wi-wind-deg.svg as location icon for all SVG themes
        if (tok === "location")
            return {
                type: "svg",
                source: base + "wind-deg.svg"
            };
        if (tok === "condition") {
            var code = weatherCode;
            var night = isNightTime();
            var stem;
            if (code === 0)
                stem = night ? "night-clear" : "day-sunny";
            else if (code <= 2)
                stem = night ? "night-alt-partly-cloudy" : "day-cloudy";
            else if (code === 3)
                stem = "cloudy";
            else if (code <= 48)
                stem = night ? "night-fog" : "day-fog";
            else if (code <= 65)
                stem = night ? "night-alt-rain" : "day-rain";
            else if (code <= 75)
                stem = night ? "night-alt-snow" : "day-snow";
            else
                stem = night ? "night-alt-thunderstorm" : "day-thunderstorm";
            return {
                type: "svg",
                source: base + stem + ".svg"
            };
        }
        if (tok === "suntimes") {
            var mode2 = Plasmoid.configuration.panelSunTimesMode || "upcoming";
            if (mode2 === "sunset")
                return {
                    type: "svg",
                    source: base + "sunset.svg"
                };
            if (mode2 === "sunrise")
                return {
                    type: "svg",
                    source: base + "sunrise.svg"
                };
            if (mode2 === "both")
                return {
                    type: "svg",
                    source: base + "sunrise.svg"
                }; // CompactView handles both-mode split
            // "upcoming": pick based on current time
            var nowM2 = (new Date()).getHours() * 60 + (new Date()).getMinutes();
            var riseM2 = parseSunTimeMins(sunriseTimeText);
            var setM2 = parseSunTimeMins(sunsetTimeText);
            var useSet2 = (riseM2 >= 0 && nowM2 >= riseM2 && (setM2 < 0 || nowM2 < setM2));
            return {
                type: "svg",
                source: base + (useSet2 ? "sunset" : "sunrise") + ".svg"
            };
        }
        if (tok === "moonphase")
            // moonPhaseSvgStem() returns e.g. "moon-new" → wi-moon-new.svg
            return {
                type: "svg",
                source: base + Moon.moonPhaseSvgStem() + ".svg"
            };

        return {
            type: "svg",
            source: ""
        };
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
        if (tok === "moonphase")
            return moonPhaseLabel();
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

    // Moon phase refresh — re-evaluate glyphs/labels once per hour
    Timer {
        interval: 3600000
        running: true
        repeat: true
        onTriggered: {
            var dummy = Moon.getMoonAge();
        }
    }

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
