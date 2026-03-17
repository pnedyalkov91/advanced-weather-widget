/**
 * weather.js — Pure weather utility functions
 *
 * .pragma library: No Qt APIs, no i18n, no QML-specific globals.
 * All functions take explicit parameters so callers remain in full control.
 * Import via: import "js/weather.js" as W
 */
.pragma library

// ── Wind direction ──────────────────────────────────────────────────────────

/**
 * Maps wind degrees to a wi-font directional arrow glyph (16-point compass).
 * Glyphs are not sequential so a lookup table is used.
 * F060=N, F0D1=NNE, F05E=NE,  F05E=ENE,
 * F061=E, F05B=ESE, F05B=SE,  F05B=SSE,
 * F05C=S, F05A=SSW, F05A=SW,  F059=WSW,
 * F059=W, F05D=WNW, F05D=NW,  F05D=NNW
 */
function windDirectionGlyph(degrees) {
    if (isNaN(degrees) || degrees === null || degrees === undefined)
        return "\uF059"; // wi-wind fallback
        var glyphs = [
            "\uF060", // N
            "\uF05E", // NNE
            "\uF05E", // NE
            "\uF05E", // ENE
            "\uF061", // E
            "\uF05B", // ESE
            "\uF05B", // SE
            "\uF05B", // SSE
            "\uF05C", // S
            "\uF05A", // SSW
            "\uF05A", // SW
            "\uF059", // WSW
            "\uF059", // W
            "\uF05D", // WNW
            "\uF05D", // NW
            "\uF05D"  // NNW
        ];
        var idx = Math.floor(((degrees + 11.25) % 360) / 22.5) % 16;
        return glyphs[idx];
}

/**
 * Returns the wi-direction SVG filename stem (e.g. "direction-up-right")
 * for use as: Qt.resolvedUrl("../icons/wi-" + W.windDirectionSvgStem(deg) + ".svg")
 */
function windDirectionSvgStem(degrees) {
    if (isNaN(degrees) || degrees === null || degrees === undefined)
        return "strong-wind";
    var mapping = [
        "up", "up-right", "up-right", "up-right",
        "right", "down-right", "down-right", "down-right",
        "down", "down-left", "down-left", "down-left",
        "left", "up-left", "up-left", "up-left"
    ];
    var idx16 = Math.floor(((degrees + 11.25) % 360) / 22.5) % 16;
    return "direction-" + mapping[idx16];
}

// ── Plasma/Breeze theme icon names ──────────────────────────────────────────

/**
 * Returns a KDE icon name for a WMO weather code.
 *
 * Maps every Open-Meteo WMO code to the best matching icon from the
 * Breeze icon theme, using proper day/night variants wherever they exist.
 *
 * symbolic: when true, appends "-symbolic" so the active icon theme
 *   serves the monochrome variant (standard Plasma convention).
 */
function weatherCodeToIcon(code, night, symbolic) {
    var n = (night !== undefined) ? night : false;
    var s = (symbolic === true) ? "-symbolic" : "";
    var d = n ? "night" : "day";   // day/night suffix for icons that have both

    if (code < 0)   return "weather-none-available";

    // 0 — Clear sky
    if (code === 0)
        return (n ? "weather-clear-night" : "weather-clear") + s;

    // 1 — Mainly clear
    if (code === 1)
        return (n ? "weather-few-clouds-night" : "weather-few-clouds") + s;

    // 2 — Partly cloudy
    if (code === 2)
        return "weather-clouds-" + d + s;

    // 3 — Overcast
    if (code === 3)
        return "weather-many-clouds" + s;

    // 45, 48 — Fog / rime fog
    if (code === 45 || code === 48)
        return "weather-fog" + s;

    // 51, 53, 55 — Drizzle (light → dense)
    if (code === 51 || code === 53 || code === 55)
        return "weather-showers-scattered-" + d + s;

    // 56, 57 — Freezing drizzle (light, dense)
    if (code === 56)
        return "weather-freezing-scattered-rain-" + d + s;
    if (code === 57)
        return "weather-freezing-rain-" + d + s;

    // 61, 63, 65 — Rain (slight, moderate, heavy)
    if (code === 61)
        return "weather-showers-scattered-" + d + s;
    if (code === 63 || code === 65)
        return "weather-showers-" + d + s;

    // 66, 67 — Freezing rain (light, heavy)
    if (code === 66)
        return "weather-freezing-scattered-rain-" + d + s;
    if (code === 67)
        return "weather-freezing-rain-" + d + s;

    // 71, 73, 75 — Snow fall (slight, moderate, heavy)
    if (code === 71)
        return "weather-snow-scattered-" + d + s;
    if (code === 73 || code === 75)
        return "weather-snow-" + d + s;

    // 77 — Snow grains
    if (code === 77)
        return "weather-snow-scattered-" + d + s;

    // 80, 81, 82 — Rain showers (slight, moderate, violent)
    if (code === 80)
        return "weather-showers-scattered-" + d + s;
    if (code === 81 || code === 82)
        return "weather-showers-" + d + s;

    // 85, 86 — Snow showers (slight, heavy)
    if (code === 85)
        return "weather-snow-scattered-" + d + s;
    if (code === 86)
        return "weather-snow-" + d + s;

    // 95 — Thunderstorm (slight or moderate)
    if (code === 95)
        return "weather-storm-" + d + s;

    // 96 — Thunderstorm with slight hail
    if (code === 96)
        return "weather-showers-scattered-storm-" + d + s;

    // 99 — Thunderstorm with heavy hail
    if (code === 99)
        return "weather-snow-scattered-storm-" + d + s;

    return "weather-few-clouds-night" + s;  // safe fallback
}

// ── Provider code converters ────────────────────────────────────────────────

/** Converts an OpenWeather condition code to WMO weather code */
function openWeatherCodeToWmo(code) {
    if (code >= 200 && code < 300) return 95;
    if (code >= 300 && code < 600) return 63;
    if (code >= 600 && code < 700) return 73;
    if (code >= 700 && code < 800) return 45;
    if (code === 800)              return 0;
    if (code === 801 || code === 802) return 2;
    if (code === 803 || code === 804) return 3;
    return 2;
}

/** Converts a met.no symbol_code string to WMO weather code */
function metNoSymbolToWmo(s) {
    if (!s) return 2;
    if (s.indexOf("thunder") >= 0)                          return 95;
    if (s.indexOf("snow") >= 0 || s.indexOf("sleet") >= 0) return 73;
    if (s.indexOf("rain") >= 0 || s.indexOf("drizzle") >= 0) return 63;
    if (s.indexOf("fog") >= 0)                              return 45;
    if (s.indexOf("clearsky") >= 0)                         return 0;
    if (s.indexOf("cloudy") >= 0)                           return 3;
    return 2;
}

/** Converts a WeatherAPI.com condition code to WMO weather code */
function weatherApiCodeToWmo(code) {
    if (code >= 1273)                                          return 95;
    if (code >= 1114 && code <= 1237)                          return 73;
    if ((code >= 1063 && code <= 1201) || (code >= 1240 && code <= 1246)) return 63;
    if (code === 1000)                                         return 0;
    if (code === 1003)                                         return 2;
    if (code === 1006 || code === 1009)                        return 3;
    if (code === 1030 || code === 1135 || code === 1147)       return 45;
    return 2;
}

// ── Unit formatters ─────────────────────────────────────────────────────────

/**
 * Formats a temperature value.
 * @param {number} celsius   Raw value in Celsius
 * @param {string} unit      "C" or "F"
 * @param {boolean} round    Round to integer if true
 */
function formatTemp(celsius, unit, round) {
    if (isNaN(celsius) || celsius === null || celsius === undefined) return "--";
    var value = (unit === "F") ? (celsius * 9 / 5 + 32) : celsius;
    var numStr = round ? String(Math.round(value)) : Number(value).toFixed(1);
    return numStr + "\u00B0"; // Unicode degree symbol
}

/**
 * Formats a wind speed value.
 * @param {number} kmh   Speed in km/h
 * @param {string} unit  "kmh" | "mph" | "ms" | "kn"
 */
function formatWind(kmh, unit) {
    if (isNaN(kmh) || kmh === null || kmh === undefined) return "--";
    if (unit === "mph") return (kmh * 0.621371).toFixed(1) + " mph";
    if (unit === "ms")  return (kmh / 3.6).toFixed(1) + " m/s";
    if (unit === "kn")  return (kmh * 0.539957).toFixed(1) + " kn";
    return Math.round(kmh) + " km/h";
}

/**
 * Formats a pressure value.
 * @param {number} hpa   Pressure in hPa
 * @param {string} unit  "hPa" | "mmHg" | "inHg"
 */
function formatPressure(hpa, unit) {
    if (isNaN(hpa) || hpa === null || hpa === undefined) return "--";
    if (unit === "mmHg") return (hpa * 0.750062).toFixed(0) + " mmHg";
    if (unit === "inHg") return (hpa * 0.02953).toFixed(2) + " inHg";
    return Math.round(hpa) + " hPa";
}

/**
 * Returns the wind SVG filename stem for the 16-point compass rose
 * in /contents/icons/wind/.  E.g.: windDirSvgFilename(45) => "ne"
 * Use as: Qt.resolvedUrl("../../icons/wind/wind-" + W.windDirSvgFilename(deg) + ".svg")
 */
function windDirSvgFilename(degrees) {
    if (degrees === undefined || degrees === null || isNaN(degrees))
        return "n"; // fallback
    var dirs = ["n","nne","ne","ene","e","ese","se","sse","s","ssw","sw","wsw","w","wnw","nw","nnw"];
    var idx = Math.floor(((degrees + 11.25) % 360) / 22.5) % 16;
    return dirs[idx];
}
