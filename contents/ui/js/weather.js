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
 * weather.js — Pure weather utility functions
 *
 * .pragma library: No Qt APIs, no i18n, no QML-specific globals.
 * All functions take explicit parameters so callers remain in full control.
 * Import via: import "js/weather.js" as W
 *
 * Unit strings (km/h, hPa, ...) are marked with I18N_NOOP so xgettext extracts
 * them; formatWind()/formatPressure() return the English key, and the QML
 * caller is responsible for wrapping it in i18n() before display.
 */
.pragma library

function I18N_NOOP(s) { return s; }

// ── "Not supported" sentinel ─────────────────────────────────────────────────
//
// Numeric weather fields are normally NaN when a value is simply not loaded yet
// (transient) — formatters render that as "--". Some providers, however, never
// expose a given field at all (e.g. BBC has no precipitation amount and no
// per-hour UV index). Those providers set the field to NOT_SUPPORTED so the
// formatters can render a distinct, honest "Not supported" instead of "--".
var NOT_SUPPORTED = -9999;
function isNotSupported(v) { return v === NOT_SUPPORTED; }

/**
 * Magnus-formula dew-point approximation.
 * T in °C, rh in % → dew point in °C (rounded to 1 decimal), NaN if unusable.
 * Shared helper so providers that lack a native dew point (BBC, met.no, …)
 * can derive one from temperature + humidity.
 */
function dewPoint(T, rh) {
    if (isNaN(T) || isNaN(rh) || rh <= 0)
        return NaN;
    var b = 17.67, c = 243.5;
    var gamma = Math.log(rh / 100.0) + (b * T) / (c + T);
    return Math.round((c * gamma) / (b - gamma) * 10) / 10;
}

// ── Open-Meteo national high-resolution models ───────────────────────────────
//
// Open-Meteo re-hosts the official national weather models. Passing the right
// `models=` value to the SAME forecast endpoint yields the official per-country
// high-resolution forecast (e.g. DWD ICON for Germany, Météo-France AROME for
// France) — same JSON shape, so no parsing changes are needed.
//
// Every value below was verified against the live API to return a non-null
// `current` block (temperature_2m + weather_code + wind + humidity) AND a
// multi-day `daily.temperature_2m_max`. Where a `_seamless` variant exists it is
// preferred: it blends the high-res short-range model (best near-term accuracy)
// with the provider's global model for the long tail, giving both accuracy and
// the full forecast horizon.
//
// Countries whose national model does NOT return usable `current` data
// (Australia's ACCESS, Korea's LDPS/GDPS/KMA-seamless all come back null via
// Open-Meteo) are intentionally omitted → they fall back to Open-Meteo's
// default global "best_match", i.e. the widget's previous behaviour.
//
// Keyed by ISO 3166-1 alpha-2 country code (uppercase).
var OPEN_METEO_COUNTRY_MODELS = {
    // DWD ICON — Germany + immediate Central-European neighbours the 2km
    // ICON-D2 domain covers well (Austria, Switzerland handled separately below).
    "DE": "dwd_icon_seamless",
    "AT": "dwd_icon_seamless",   // GeoSphere Austria has no usable OM current model; ICON-D2 covers Austria
    "PL": "dwd_icon_seamless",
    "CZ": "dwd_icon_seamless",
    "BE": "dwd_icon_seamless",
    "LU": "dwd_icon_seamless",

    // Météo-France AROME/ARPEGE
    "FR": "meteofrance_seamless",

    // UK Met Office (UKV 2km near-term)
    "GB": "ukmo_seamless",
    "IE": "ukmo_seamless",

    // NOAA — GFS seamless includes HRRR (3km CONUS) in the near term
    "US": "gfs_seamless",

    // MeteoSwiss ICON-CH (1–2km, Alpine)
    "CH": "meteoswiss_icon_seamless",
    "LI": "meteoswiss_icon_seamless",

    // MET Norway Nordic (1km) — covers the Nordics + Baltic
    "NO": "metno_seamless",
    "SE": "metno_seamless",
    "FI": "metno_seamless",

    // Environment Canada GEM HRDPS (2.5km)
    "CA": "gem_seamless",

    // CMA GRAPES (China) — no seamless variant; direct global model returns data
    "CN": "cma_grapes_global",

    // JMA MSM (Japan, 5km)
    "JP": "jma_seamless",

    // KNMI HARMONIE-AROME (Netherlands, 2km)
    "NL": "knmi_seamless",

    // DMI HARMONIE-AROME (Denmark + surrounding Europe, 2km)
    "DK": "dmi_seamless",

    // ItaliaMeteo ARPAE ICON-2I (Italy, 2km) — no seamless variant
    "IT": "italia_meteo_arpae_icon_2i"
};

/**
 * Resolves the Open-Meteo `models=` value to use for a given config setting and
 * location country.
 *
 * @param {string} setting     The `openMeteoModel` config value:
 *                             "auto"    → pick the national model by country;
 *                             "default" → force the global best_match;
 *                             "<id>"    → force a specific model id.
 * @param {string} countryCode ISO-3166 alpha-2 (any case); used only for "auto".
 * @returns {string} A model id, or "" meaning "add no models= param" (best_match).
 */
function resolveOpenMeteoModel(setting, countryCode) {
    var s = (setting || "auto").trim();
    if (s === "default" || s === "best_match")
        return "";                       // no models= param → global best_match
    if (s !== "auto" && s.length > 0)
        return s;                        // explicit user override
    var cc = (countryCode || "").toUpperCase();
    return OPEN_METEO_COUNTRY_MODELS[cc] || "";   // "" → fall back to best_match
}

/** Builds the "&models=<id>" URL fragment, or "" when best_match should be used. */
function openMeteoModelParam(setting, countryCode) {
    var m = resolveOpenMeteoModel(setting, countryCode);
    return m ? "&models=" + m : "";
}

// Display metadata for each national model id: the issuing weather service's
// name (shown in the footer) and its homepage. Keyed by Open-Meteo model id.
var OPEN_METEO_MODEL_INFO = {
    "dwd_icon_seamless":            { name: "DWD Germany",       url: "https://www.dwd.de" },
    "meteofrance_seamless":         { name: "Météo-France",      url: "https://meteofrance.com" },
    "ukmo_seamless":                { name: "UK Met Office",     url: "https://www.metoffice.gov.uk" },
    "gfs_seamless":                 { name: "NOAA U.S.",         url: "https://www.weather.gov" },
    "meteoswiss_icon_seamless":     { name: "MeteoSwiss",        url: "https://www.meteoswiss.admin.ch" },
    "metno_seamless":               { name: "MET Norway",        url: "https://www.met.no" },
    "gem_seamless":                 { name: "GEM Canada",        url: "https://weather.gc.ca" },
    "cma_grapes_global":            { name: "CMA China",         url: "https://www.cma.gov.cn" },
    "jma_seamless":                 { name: "JMA Japan",         url: "https://www.jma.go.jp" },
    "knmi_seamless":                { name: "KNMI Netherlands",  url: "https://www.knmi.nl" },
    "dmi_seamless":                 { name: "DMI Denmark",       url: "https://www.dmi.dk" },
    "italia_meteo_arpae_icon_2i":   { name: "ItaliaMeteo",       url: "https://www.italiameteo.org" }
};

/**
 * Returns { name, url } describing the active national high-resolution model
 * for the given config setting + country, or null when the plain global
 * best_match is in use (nothing extra to show in the footer).
 */
function openMeteoModelInfo(setting, countryCode) {
    var m = resolveOpenMeteoModel(setting, countryCode);
    return m && OPEN_METEO_MODEL_INFO[m] ? OPEN_METEO_MODEL_INFO[m] : null;
}

// ── Wind direction ──────────────────────────────────────────────────────────

/**
 * Converts a compass abbreviation ("N", "NNE", "SW", …) to degrees.
 * Used by providers (e.g. BBC) that report wind direction as text.
 * Returns NaN for unknown/empty input.
 */
var _COMPASS_DEGREES = {
    "N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5,
    "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
    "S": 180, "SSW": 202.5, "SW": 225, "WSW": 247.5,
    "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5
};
function compassToDegrees(abbr) {
    if (!abbr) return NaN;
    var v = _COMPASS_DEGREES[String(abbr).toUpperCase().trim()];
    return (v === undefined) ? NaN : v;
}

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

/** Converts a Pirate Weather / Dark Sky icon string to WMO weather code */
function pirateWeatherIconToWmo(icon) {
    if (!icon) return 2;
    switch (icon) {
        case "clear-day":
        case "clear-night":
            return 0;
        case "partly-cloudy-day":
        case "partly-cloudy-night":
            return 2;
        case "cloudy":
            return 3;
        case "rain":
            return 63;
        case "snow":
            return 73;
        case "sleet":
            return 66;
        case "wind":
            return 2;
        case "fog":
            return 45;
        case "thunderstorm":
            return 95;
        case "hail":
            return 99;
        default:
            return 2;
    }
}

/**
 * Converts a BBC Weather (Met Office) numeric weatherType to a WMO weather code.
 * BBC uses the standard Met Office 0–30 code table; see
 * https://www.metoffice.gov.uk/services/data/datapoint/code-definitions
 */
function bbcWeatherTypeToWmo(code) {
    switch (Number(code)) {
        case 0:  // Clear sky (night)
        case 1:  // Sunny (day)
            return 0;
        case 2:  // Partly cloudy (night)
        case 3:  // Sunny intervals (day)
            return 2;
        case 5:  // Mist
        case 6:  // Fog
            return 45;
        case 7:  // Light cloud
            return 3;
        case 8:  // Thick cloud
            return 3;
        case 9:  // Light rain shower (night)
        case 10: // Light rain shower (day)
        case 11: // Drizzle
        case 12: // Light rain
            return 61;
        case 13: // Heavy rain shower (night)
        case 14: // Heavy rain shower (day)
        case 15: // Heavy rain
            return 63;
        case 16: // Sleet shower (night)
        case 17: // Sleet shower (day)
        case 18: // Sleet
            return 66;
        case 19: // Hail shower (night)
        case 20: // Hail shower (day)
        case 21: // Hail
            return 77;
        case 22: // Light snow shower (night)
        case 23: // Light snow shower (day)
        case 24: // Light snow
            return 71;
        case 25: // Heavy snow shower (night)
        case 26: // Heavy snow shower (day)
        case 27: // Heavy snow
            return 75;
        case 28: // Thunder shower (night)
        case 29: // Thunder shower (day)
        case 30: // Thunder
            return 95;
        default:
            return 2;
    }
}

/**
 * Determines day/night from a BBC weatherType code.
 * Even codes below 30 are night variants, odd codes are day variants;
 * 0 (clear sky) is night, 1 (sunny) is day. Returns 1/0/-1.
 */
function bbcWeatherTypeIsDay(code) {
    var c = Number(code);
    if (isNaN(c)) return -1;
    if (c === 5 || c === 6 || c === 7 || c === 8) return -1; // mist/fog/cloud: ambiguous
    if (c >= 0 && c <= 30) return (c % 2 === 1) ? 1 : 0;
    return -1;
}

// ── Unit formatters ─────────────────────────────────────────────────────────

/**
 * Formats a temperature value.
 * @param {number} celsius   Raw value in Celsius
 * @param {string} unit      "C" or "F"
 * @param {boolean} round    Round to integer if true
 */
function formatTemp(celsius, unit, round, showUnit) {
    if (isNaN(celsius) || celsius === null || celsius === undefined) return "--";
    var value = (unit === "F") ? (celsius * 9 / 5 + 32) : celsius;
    var numStr = round ? String(Math.round(value)) : Number(value).toFixed(1);
    if (showUnit) return numStr + " \u00B0" + unit;
    return numStr + "\u00B0"; // Unicode degree symbol
}

/** True for WMO weather codes whose icon implies some form of precipitation
 *  (drizzle/rain/showers, snow, thunderstorm). */
function isPrecipCode(code) {
    return (code >= 51 && code <= 67) || (code >= 71 && code <= 86) ||
        code === 95 || code === 96 || code === 99;
}

/**
 * Formats an hourly precipitation-probability percentage for display.
 * Open-Meteo's `weather_code` and `precipitation_probability` are derived
 * from different model fields and can disagree for a given hour (e.g. a
 * thunderstorm code with a 0% probability) — this is an upstream data
 * inconsistency, not a bug in how we read the API. When the icon implies
 * precipitation, floor the displayed percentage to a small nonzero value
 * so it doesn't visually contradict the icon.
 * @param {number} precipProb  Precipitation probability (0-100), may be NaN
 * @param {number} code        WMO weather code driving the hour's icon
 */
function hourlyPrecipProbText(precipProb, code) {
    if (precipProb === undefined || precipProb === null || isNaN(precipProb))
        return null;
    var pct = Math.round(precipProb);
    if (pct < 5 && isPrecipCode(code))
        pct = 5;
    return pct + "%";
}

/** English unit-label keys for wind speed; wrap in i18n() before display. */
var WIND_UNIT_LABELS = {
    mph: I18N_NOOP("mph"),
    ms:  I18N_NOOP("m/s"),
    kn:  I18N_NOOP("kn"),
    kmh: I18N_NOOP("km/h")
};

/** English unit-label keys for pressure; wrap in i18n() before display. */
var PRESSURE_UNIT_LABELS = {
    mmHg: I18N_NOOP("mmHg"),
    inHg: I18N_NOOP("inHg"),
    hPa:  I18N_NOOP("hPa")
};

/**
 * Formats a wind speed value's number only (no unit suffix).
 * @param {number} kmh   Speed in km/h
 * @param {string} unit  "kmh" | "mph" | "ms" | "kn"
 */
function formatWindValue(kmh, unit) {
    if (isNaN(kmh) || kmh === null || kmh === undefined) return "--";
    if (unit === "mph") return (kmh * 0.621371).toFixed(1);
    if (unit === "ms")  return (kmh / 3.6).toFixed(1);
    if (unit === "kn")  return (kmh * 0.539957).toFixed(1);
    return String(Math.round(kmh));
}

/** Returns the English unit-label key for the given wind unit; wrap in i18n(). */
function windUnitLabel(unit) {
    return WIND_UNIT_LABELS[unit] || WIND_UNIT_LABELS.kmh;
}

/**
 * Formats a pressure value's number only (no unit suffix).
 * @param {number} hpa   Pressure in hPa
 * @param {string} unit  "hPa" | "mmHg" | "inHg"
 */
function formatPressureValue(hpa, unit) {
    if (isNaN(hpa) || hpa === null || hpa === undefined) return "--";
    if (unit === "mmHg") return (hpa * 0.750062).toFixed(0);
    if (unit === "inHg") return (hpa * 0.02953).toFixed(2);
    return String(Math.round(hpa));
}

/** Returns the English unit-label key for the given pressure unit; wrap in i18n(). */
function pressureUnitLabel(unit) {
    return PRESSURE_UNIT_LABELS[unit] || PRESSURE_UNIT_LABELS.hPa;
}

// windDirSvgFilename() removed — was a duplicate of windDirectionSvgStem().
// Callers should use windDirectionSvgStem() instead.
