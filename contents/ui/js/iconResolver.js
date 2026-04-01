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
 * iconResolver.js — Unified icon resolution for the weather widget
 *
 * Single source of truth for mapping weather item IDs to icons.
 * All views (Panel, Tooltip, Widget/Details, Forecast) import this module
 * instead of duplicating lookup tables.
 *
 * Resolution priority:
 *   1. KDE system icon (always tried first — works with any Plasma icon theme)
 *   2. Bundled SVG fallback (from contents/icons/<theme>/<size>/wi-<name>.svg)
 *
 * .pragma library — no Qt globals, pure JS.
 */
.pragma library

// ── KDE system icon names ───────────────────────────────────────────────────
// These are standard Breeze/Plasma icon names that exist in most KDE themes.
var _kdeIcons = {
    temperature:  "thermometer",
    feelslike:    "thermometer",
    humidity:     "weather-humidity",
    pressure:     "weather-pressure",
    wind:         "weather-windy",
    suntimes:     "weather-clear",
    "suntimes-sunrise": "weather-sunrise",
    "suntimes-sunset":  "weather-sunset",
    sunrise:      "weather-sunrise",
    sunset:       "weather-sunset",
    dewpoint:     "raindrop",
    visibility:   "weather-fog",
    moonphase:    "weather-clear-night",
    moonrise:     "weather-clear-night",
    moonset:      "weather-clear-night",
    condition:    "weather-few-clouds",
    location:     "mark-location",
    umbrella:     "weather-showers",
    preciprate:   "weather-showers",
    precipsum:    "flood",
    uvindex:      "weather-clear",
    airquality:   "weather-many-clouds",
    alerts:       "weather-storm",
    snowcover:    "weather-snow-scattered",
    pollen:       "weather-fog",
    spaceweather: "solar-eclipse"
};

// ── Bundled SVG filenames (without "wi-" prefix and ".svg" suffix) ───────────
// These map to files like: contents/icons/<theme>/<size>/wi-<stem>.svg
var _svgStems = {
    temperature:  "thermometer",
    feelslike:    "thermometer",
    humidity:     "humidity",
    pressure:     "barometer",
    wind:         "strong-wind",
    suntimes:     "sunrise",
    "suntimes-sunrise": "sunrise",
    "suntimes-sunset":  "sunset",
    sunrise:      "sunrise",
    sunset:       "sunset",
    dewpoint:     "raindrop",
    visibility:   "fog",
    moonphase:    "night-clear",
    moonrise:     "moonrise",
    moonset:      "moonset",
    condition:    "day-sunny",
    location:     "wind-deg",
    umbrella:     "umbrella",
    preciprate:   "raindrops",
    precipsum:    "flood",
    uvindex:      "hot",
    airquality:   "smog",
    alerts:       "storm-warning",
    snowcover:    "snowflake-cold",
    pollen:       "sandstorm",
    spaceweather: "solar-eclipse"
};

// ── Wi-font glyph code points ───────────────────────────────────────────────
// Used only as a last-resort fallback when neither KDE nor SVG icons work,
// or when the user explicitly selects wi-font theme for compact panel display.
var _wiGlyphs = {
    temperature:  "\uF055",
    feelslike:    "\uF053",
    humidity:     "\uF07A",
    pressure:     "\uF079",
    wind:         "\uF050",
    suntimes:     "\uF051",
    "suntimes-sunrise": "\uF051",
    "suntimes-sunset":  "\uF052",
    sunrise:      "\uF051",
    sunset:       "\uF052",
    dewpoint:     "\uF078",
    visibility:   "\uF0B6",
    moonphase:    "\uF0D0",
    moonrise:     "\uF0C9",
    moonset:      "\uF0CA",
    condition:    "\uF013",
    location:     "\uF0B1",
    umbrella:     "\uF084",
    preciprate:   "\uF04E",
    precipsum:    "\uF07C",
    uvindex:      "\uF072",
    airquality:   "\uF074",
    alerts:       "\uF0CE",
    snowcover:    "\uF076",
    pollen:       "\uF082",
    spaceweather: "\uF06E"
};

// ══════════════════════════════════════════════════════════════════════════════
// Public API
// ══════════════════════════════════════════════════════════════════════════════

/**
 * Resolves an icon for the given item ID.
 *
 * Returns: { type: "kde"|"svg", source: string, kdeFallback: string, isMask: bool }
 *
 * @param {string} itemId     — Logical icon ID (e.g. "humidity", "wind", "sunrise")
 * @param {int}    iconSize   — Desired icon size in px (16, 22, 24, or 32)
 * @param {string} iconsBaseDir — Resolved URL to the icons/ folder
 *                                 (e.g. Qt.resolvedUrl("../icons/") from the calling QML)
 * @param {string} svgTheme   — "kde" for KDE-first strategy, or SVG theme subfolder:
 *                               "symbolic", "flat-color", "3d-oxygen", etc.
 *                               When "kde": KDE system icon primary, symbolic SVG fallback.
 *                               Otherwise: bundled SVG primary, KDE emergency fallback.
 */
function resolve(itemId, iconSize, iconsBaseDir, svgTheme) {
    var isKde = (svgTheme === "kde");
    var theme = isKde ? "flat-color" : (svgTheme || "symbolic");
    var isMask = isKde ? false : (theme === "symbolic" || theme === "symbolic-light");
    var kdeIcon = _kdeIcons[itemId] || "";
    var svgStem = _svgStems[itemId] || "";

    var svgSource = "";
    if (svgStem.length > 0 && iconsBaseDir) {
        svgSource = iconsBaseDir + theme + "/" + iconSize + "/wi-" + svgStem + ".svg";
    }

    if (isKde) {
        // KDE theme: system icon primary, symbolic SVG fallback
        if (kdeIcon.length > 0)
            return { type: "kde", source: kdeIcon, svgFallback: svgSource, isMask: isMask };
        if (svgSource.length > 0)
            return { type: "svg", source: svgSource, svgFallback: "", isMask: isMask };
    } else {
        // Bundled SVG theme: SVG primary, KDE emergency fallback
        if (svgSource.length > 0)
            return { type: "svg", source: svgSource, svgFallback: "", isMask: isMask };
        if (kdeIcon.length > 0)
            return { type: "kde", source: kdeIcon, svgFallback: "", isMask: false };
    }

    return { type: "kde", source: "", svgFallback: "", isMask: false };
}

/**
 * Resolves a weather condition icon.
 * Priority: KDE system icon → bundled SVG.
 *
 * @param {int}    weatherCode — WMO weather code
 * @param {bool}   isNight     — true if nighttime
 * @param {int}    iconSize    — desired icon size
 * @param {string} iconsBaseDir — resolved URL to icons/ folder
 * @param {string} svgTheme    — SVG theme subfolder
 */
function resolveCondition(weatherCode, isNight, iconSize, iconsBaseDir, svgTheme) {
    var isKde = (svgTheme === "kde" || svgTheme === "kde-symbolic");
    var isMaskOverride = (svgTheme === "kde-symbolic");
    var theme = isKde ? (isMaskOverride ? "symbolic" : "flat-color") : (svgTheme || "symbolic");
    var isMask = isKde ? isMaskOverride : (theme === "symbolic" || theme === "symbolic-light");
    var kdeIcon = _conditionKdeIcon(weatherCode, isNight);
    if (isMaskOverride && kdeIcon.length > 0) kdeIcon += "-symbolic";
    var svgStem = _conditionSvgStem(weatherCode, isNight);

    var svgSource = "";
    if (svgStem.length > 0 && iconsBaseDir) {
        svgSource = iconsBaseDir + theme + "/" + iconSize + "/wi-" + svgStem + ".svg";
    }

    if (isKde) {
        if (kdeIcon.length > 0)
            return { type: "kde", source: kdeIcon, svgFallback: svgSource, isMask: isMask };
        if (svgSource.length > 0)
            return { type: "svg", source: svgSource, svgFallback: "", isMask: isMask };
    } else {
        if (svgSource.length > 0)
            return { type: "svg", source: svgSource, svgFallback: "", isMask: isMask };
        if (kdeIcon.length > 0)
            return { type: "kde", source: kdeIcon, svgFallback: "", isMask: false };
    }

    return { type: "kde", source: "weather-none-available", svgFallback: "", isMask: false };
}

/**
 * Resolves a moon phase icon.
 *
 * @param {string} moonPhaseSvgStem — e.g. "moon-alt-full" from moonphase.js
 * @param {int}    iconSize
 * @param {string} iconsBaseDir
 * @param {string} svgTheme
 */
function resolveMoonPhase(moonPhaseSvgStem, iconSize, iconsBaseDir, svgTheme) {
    var isKde = (svgTheme === "kde");
    var theme = isKde ? "flat-color" : (svgTheme || "symbolic");
    var isMask = isKde ? false : (theme === "symbolic" || theme === "symbolic-light");
    var svgSource = "";
    if (moonPhaseSvgStem && iconsBaseDir) {
        svgSource = iconsBaseDir + theme + "/" + iconSize + "/wi-" + moonPhaseSvgStem + ".svg";
    }

    if (isKde) {
        var moonKde = "weather-clear-night";
        return {
            type: "kde",
            source: moonKde,
            svgFallback: svgSource,
            isMask: isMask
        };
    }

    if (svgSource.length > 0) {
        return {
            type: "svg",
            source: svgSource,
            svgFallback: "",
            isMask: isMask
        };
    }

    return {
        type: "kde",
        source: "weather-clear-night",
        svgFallback: "",
        isMask: isMask
    };
}

/**
 * Returns the wi-font glyph for an item ID.
 * Useful for the panel compact view which still supports wi-font rendering.
 */
function wiGlyph(itemId) {
    return _wiGlyphs[itemId] || "\uF00D";
}

/**
 * Returns the KDE icon name for an item ID (or "" if none).
 */
function kdeIconName(itemId) {
    return _kdeIcons[itemId] || "";
}

/**
 * Returns the SVG stem for an item ID (without prefix/suffix).
 */
function svgStem(itemId) {
    return _svgStems[itemId] || "";
}

/**
 * Builds a full SVG URL for a given stem.
 */
function svgUrl(stem, iconSize, iconsBaseDir, svgTheme) {
    var theme = svgTheme || "symbolic";
    return iconsBaseDir + theme + "/" + iconSize + "/wi-" + stem + ".svg";
}

// ══════════════════════════════════════════════════════════════════════════════
// Internal helpers
// ══════════════════════════════════════════════════════════════════════════════

function _conditionKdeIcon(code, night) {
    var n = night ? true : false;
    var d = n ? "night" : "day";

    if (code < 0)   return "weather-none-available";
    if (code === 0)  return n ? "weather-clear-night" : "weather-clear";
    if (code === 1)  return n ? "weather-few-clouds-night" : "weather-few-clouds";
    if (code === 2)  return "weather-clouds-" + d;
    if (code === 3)  return "weather-many-clouds";
    if (code === 45 || code === 48) return "weather-fog";
    if (code === 51 || code === 53 || code === 55) return "weather-showers-scattered-" + d;
    if (code === 56) return "weather-freezing-scattered-rain-" + d;
    if (code === 57) return "weather-freezing-rain-" + d;
    if (code === 61) return "weather-showers-scattered-" + d;
    if (code === 63 || code === 65) return "weather-showers-" + d;
    if (code === 66) return "weather-freezing-scattered-rain-" + d;
    if (code === 67) return "weather-freezing-rain-" + d;
    if (code === 71) return "weather-snow-scattered-" + d;
    if (code === 73 || code === 75) return "weather-snow-" + d;
    if (code === 77) return "weather-snow-scattered-" + d;
    if (code === 80) return "weather-showers-scattered-" + d;
    if (code === 81 || code === 82) return "weather-showers-" + d;
    if (code === 85) return "weather-snow-scattered-" + d;
    if (code === 86) return "weather-snow-" + d;
    if (code === 95) return "weather-storm-" + d;
    if (code === 96) return "weather-showers-scattered-storm-" + d;
    if (code === 99) return "weather-snow-scattered-storm-" + d;

    return "weather-few-clouds-night";
}

function _conditionSvgStem(code, night) {
    if (code === 0)  return night ? "night-clear" : "day-sunny";
    if (code <= 2)   return night ? "night-alt-partly-cloudy" : "day-cloudy";
    if (code === 3)  return "cloudy";
    if (code <= 48)  return night ? "night-fog" : "day-fog";
    if (code <= 65)  return night ? "night-alt-rain" : "day-rain";
    if (code <= 75)  return night ? "night-alt-snow" : "day-snow";
    return night ? "night-alt-thunderstorm" : "day-thunderstorm";
}
