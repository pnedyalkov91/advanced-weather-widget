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
 * configUtils.js — Shared configuration parsing utilities
 *
 * Eliminates the repeated pattern of parsing "key=value;key=value" config
 * strings into JS objects, used across main.qml, FullView, ForecastView,
 * TooltipContent, DetailsView, and CompactView.
 *
 * .pragma library — no Qt globals, pure JS.
 */
.pragma library

/**
 * Parses a semicolon-separated "key=value;key=value" config string into
 * a plain JS object { key: value, ... }.
 *
 * @param {string} raw — The raw config string (e.g. "foo=bar;baz=1")
 * @returns {Object} — Parsed key-value map
 *
 * Usage:
 *   var map = ConfigUtils.parseConfigMap(Plasmoid.configuration.panelCustomIcons || "");
 *   if ("temperature" in map) { ... }
 */
function parseConfigMap(raw) {
    var map = {};
    if (!raw || raw.length === 0)
        return map;
    var pairs = raw.split(";");
    for (var i = 0; i < pairs.length; i++) {
        var kv = pairs[i].split("=");
        if (kv.length === 2 && kv[0].trim().length > 0)
            map[kv[0].trim()] = kv[1].trim();
    }
    return map;
}

/**
 * Parses a semicolon-separated config string into a boolean map.
 * Values of "1" become true, everything else becomes false.
 *
 * @param {string} raw — The raw config string (e.g. "temperature=1;wind=0")
 * @returns {Object} — Parsed key-boolean map
 *
 * Usage:
 *   var iconMap = ConfigUtils.parseBoolMap(Plasmoid.configuration.panelItemIcons || "");
 *   var showIcon = (tok in iconMap) ? iconMap[tok] : true;
 */
function parseBoolMap(raw) {
    var map = {};
    if (!raw || raw.length === 0)
        return map;
    var pairs = raw.split(";");
    for (var i = 0; i < pairs.length; i++) {
        var kv = pairs[i].split("=");
        if (kv.length === 2)
            map[kv[0].trim()] = (kv[1].trim() === "1");
    }
    return map;
}

/**
 * Maps a WMO weather code + night flag to a condition custom icon key.
 * This mapping is used by the custom icon theme to look up per-condition
 * user-chosen icons.
 *
 * Previously duplicated in main.qml, FullView.qml, and ForecastView.qml.
 *
 * @param {int}  code  — WMO weather code
 * @param {bool} night — true if nighttime
 * @returns {string} — Condition key like "condition-clear-night"
 */
function resolveConditionKey(code, night) {
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

/**
 * Resolves a condition icon for the "custom" icon theme, handling
 * per-condition user overrides from a config string.
 *
 * Previously duplicated identically in FullView.qml and ForecastView.qml.
 *
 * @param {int}    code           — WMO weather code
 * @param {bool}   isNight        — true if nighttime
 * @param {int}    iconSize       — desired icon size in px
 * @param {string} iconsBaseDir   — resolved URL to icons/ folder
 * @param {string} iconTheme      — the active icon theme string
 * @param {string} customIconsRaw — raw config string for custom condition icons
 * @param {function} weatherCodeToIcon — W.weatherCodeToIcon function reference
 * @param {function} resolveConditionFn — IconResolver.resolveCondition function reference
 * @returns {Object} — { type, source, svgFallback, isMask }
 */
function resolveCustomConditionIcon(code, isNight, iconSize, iconsBaseDir, iconTheme, customIconsRaw, weatherCodeToIcon, resolveConditionFn) {
    if (iconTheme === "custom") {
        var m = parseConfigMap(customIconsRaw);
        if (m["condition-custom"] === "1") {
            var condKey = resolveConditionKey(code, isNight);
            var fallback = weatherCodeToIcon(code, isNight);
            var saved = (condKey in m && m[condKey].length > 0) ? m[condKey] : fallback;
            return { type: "kde", source: saved, svgFallback: "", isMask: false };
        }
        // condition-custom not set — fall back to KDE icons
        return resolveConditionFn(code, isNight, iconSize, iconsBaseDir, "kde");
    }
    return resolveConditionFn(code, isNight, iconSize, iconsBaseDir, iconTheme);
}
