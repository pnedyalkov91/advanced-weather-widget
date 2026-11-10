/*
 * Copyright 2026 Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of
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
 * configUtils.js - Shared configuration parsing utilities
 *
 * Eliminates the repeated pattern of parsing "key=value;key=value" config
 * strings into JS objects, used across main.qml, FullView, ForecastView,
 * TooltipContent, DetailsView, and CompactView.
 *
 * .pragma library - no Qt globals, pure JS.
 */
.pragma library

/**
 * Parses a semicolon-separated "key=value;key=value" config string into
 * a plain JS object { key: value, ... }.
 *
 * @param {string} raw - The raw config string (e.g. "foo=bar;baz=1")
 * @returns {Object} - Parsed key-value map
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
 * @param {string} raw - The raw config string (e.g. "temperature=1;wind=0")
 * @returns {Object} - Parsed key-boolean map
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
 * @param {int}  code  - WMO weather code
 * @param {bool} night - true if nighttime
 * @returns {string} - Condition key like "condition-clear-night"
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
 * @param {int}    code           - WMO weather code
 * @param {bool}   isNight        - true if nighttime
 * @param {int}    iconSize       - desired icon size in px
 * @param {string} iconsBaseDir   - resolved URL to icons/ folder
 * @param {string} iconTheme      - the active icon theme string
 * @param {string} customIconsRaw - raw config string for custom condition icons
 * @param {function} weatherCodeToIcon - W.weatherCodeToIcon function reference
 * @param {function} resolveConditionFn - IconResolver.resolveCondition function reference
 * @returns {Object} - { type, source, svgFallback, isMask }
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
        // condition-custom not set - fall back to KDE icons
        return resolveConditionFn(code, isNight, iconSize, iconsBaseDir, "kde");
    }
    return resolveConditionFn(code, isNight, iconSize, iconsBaseDir, iconTheme);
}

/**
 * Reads a color out of a text, as copied from a color picker or an editor:
 * "#rrggbb", "rrggbb" or "#rgb", spaces around allowed.
 *
 * @param {string} text - The text to read
 * @returns {string} - The color as "#rrggbb" in lower case, "" when the text is no color
 */
function colorFromText(text) {
    var m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(text === null || text === undefined ? "" : text).trim());
    if (!m)
        return "";
    var hex = m[1].toLowerCase();
    if (hex.length === 3)
        hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
    return "#" + hex;
}

/**
 * The temperature palettes that come with the widget, for the radar map's
 * temperature layer: points of { t (°C), color }, a gradient between them.
 * The map page has the first one too (glue-temp.js, DEFAULT_STOPS).
 * id is what librewxrTempPalette holds for each ("" for the default one).
 */
var TEMP_BUILTINS = [
    { id: "", key: "vivid", stops: [[-40, "#3b3050"], [-30, "#4b3a9c"], [-20, "#3f63c4"], [-10, "#2aa3a8"], [0, "#7ccf5a"],
        [5, "#d6d63a"], [10, "#f2c230"], [20, "#e8862a"], [30, "#d23a22"], [40, "#7a0f12"]] },
    { id: "builtin:muted", key: "muted", stops: [[-40, "#1d2a5c"], [-20, "#3d5a99"], [-10, "#7f9cc4"], [0, "#e6e6e6"],
        [10, "#d9c49a"], [20, "#b88a55"], [30, "#8c5a2b"], [40, "#5a3115"]] },
    { id: "builtin:bluered", key: "bluered", stops: [[-40, "#2c1a6b"], [-20, "#2166ac"], [-10, "#67a9cf"], [0, "#f7f7f7"],
        [10, "#fddbc7"], [20, "#ef8a62"], [30, "#b2182b"], [40, "#67001f"]] }
].map(function (b) {
    return { id: b.id, key: b.key, stops: b.stops.map(function (s) { return { t: s[0], color: s[1] }; }) };
});

/**
 * Whether a palette's points can be drawn: 2 to 12, colors "#rrggbb",
 * temperatures going up.
 */
function tempStopsValid(stops) {
    if (!Array.isArray(stops) || stops.length < 2 || stops.length > 12)
        return false;
    for (var i = 0; i < stops.length; i++) {
        var s = stops[i];
        if (!s || typeof s.t !== "number" || !isFinite(s.t) || !/^#[0-9a-f]{6}$/i.test(String(s.color)))
            return false;
        if (i > 0 && !(s.t > stops[i - 1].t))
            return false;
    }
    return true;
}

/**
 * The points of the temperature palette chosen in the settings.
 *
 * @param {string} selection - librewxrTempPalette: "", "builtin:…" or the name of a palette made in the settings
 * @param {string} customJson - librewxrTempPalettes: [{ name, stops: [{ t, color }] }]
 * @returns {Array} - The points; the vivid palette for anything that does not read
 */
function tempPaletteStops(selection, customJson) {
    var i;
    for (i = 0; i < TEMP_BUILTINS.length; i++) {
        if (TEMP_BUILTINS[i].id === (selection || ""))
            return TEMP_BUILTINS[i].stops;
    }
    var list = [];
    try {
        list = JSON.parse(customJson || "[]");
    } catch (e) {
        return TEMP_BUILTINS[0].stops;
    }
    if (!Array.isArray(list))
        return TEMP_BUILTINS[0].stops;
    for (i = 0; i < list.length; i++) {
        if (list[i] && list[i].name === selection && tempStopsValid(list[i].stops))
            return list[i].stops.map(function (s) { return { t: s.t, color: String(s.color).toLowerCase() }; });
    }
    return TEMP_BUILTINS[0].stops;
}

/**
 * A temperature palette in the map page's form: "t:rrggbb" separated by
 * commas, t in °C to 0.1.
 */
function formatTempPalette(stops) {
    return stops.map(function (s) {
        return String(Math.round(s.t * 10) / 10) + ":" + String(s.color).replace("#", "");
    }).join(",");
}

/** A temperature in °C, in the unit "C" or "F". */
function tempToUnit(celsius, unit) {
    return unit === "F" ? Math.round((celsius * 9 / 5 + 32) * 10) / 10 : celsius;
}

/** A temperature in the unit "C" or "F", in °C to 0.1. */
function tempFromUnit(value, unit) {
    var c = unit === "F" ? (value - 32) * 5 / 9 : value;
    return Math.round(c * 10) / 10;
}

/**
 * The temperature unit the widget shows, as main.qml decides it: the
 * locale's measurement system in "kde" mode (1 = imperial), else the setting.
 */
function effectiveTempUnit(unitsMode, temperatureUnit, measurementSystem) {
    if (unitsMode === "kde")
        return measurementSystem === 1 ? "F" : "C";
    return temperatureUnit === "F" ? "F" : "C";
}

/**
 * What keeps a temperature palette from being saved, for the editor:
 * "name" (none given), "taken" (another palette has it), "count" (not 2 to
 * 12 points), "order" (temperatures not going up), or "" when it can be.
 */
function tempPaletteProblem(name, stops, takenNames) {
    var n = String(name || "").trim();
    if (!n)
        return "name";
    if (takenNames.indexOf(n) >= 0)
        return "taken";
    if (stops.length < 2 || stops.length > 12)
        return "count";
    for (var i = 1; i < stops.length; i++) {
        if (!(stops[i].t > stops[i - 1].t))
            return "order";
    }
    return "";
}

/** The points of a palette and one more, 5 degrees of the unit above the last, in its color. */
function tempAddStop(stops, unit) {
    var last = stops[stops.length - 1];
    var next = tempFromUnit(tempToUnit(last.t, unit) + 5, unit);
    return stops.concat([{ t: next, color: last.color }]);
}

/**
 * The stack of the Weather Maps' layers, top first. The map page has the
 * same default (STACK_DEFAULT in glue-adapter-maplibre.js), without the
 * wind: its particles are drawn on a canvas over the map, so over every
 * layer whatever its place here, which orders the column only.
 */
var WEATHER_STACK = ["radar", "satellite", "wind", "precipitation", "clouds",
    "temperature", "pressure", "isobars", "humidity", "dewpoint", "airquality"];

/**
 * The stack chosen: weatherMapLayerOrder read, unknown ids and repeats
 * left out, a missing one right after its neighbour above it in the
 * default (an order saved before that layer came).
 * @param {string} json - weatherMapLayerOrder
 * @returns {Array} - every id of WEATHER_STACK, top first
 */
function weatherStackOrder(json) {
    var list = [];
    try {
        list = JSON.parse(json || "[]");
    } catch (e) {
        list = [];
    }
    var out = [];
    (Array.isArray(list) ? list : []).forEach(function (id) {
        if (WEATHER_STACK.indexOf(id) >= 0 && out.indexOf(id) < 0)
            out.push(id);
    });
    WEATHER_STACK.forEach(function (id, i) {
        if (out.indexOf(id) >= 0)
            return;
        var at = 0;
        for (var j = i - 1; j >= 0; j--) {
            var k = out.indexOf(WEATHER_STACK[j]);
            if (k >= 0) {
                at = k + 1;
                break;
            }
        }
        out.splice(at, 0, id);
    });
    return out;
}

/** A new list with the item at from moved to to; the same items when either is out of range. */
function weatherStackMove(order, from, to) {
    var out = order.slice();
    if (from < 0 || from >= out.length || to < 0 || to >= out.length)
        return out;
    out.splice(to, 0, out.splice(from, 1)[0]);
    return out;
}

/**
 * Whether the Weather Map's time line no longer has now where the clock
 * is: another of its frames is nearer nowMs, or nowMs is more than half a
 * step past its last one (the map left open overnight).
 * @param {Array} times - the frames' times (ms)
 * @param {number} nowIndex - the frame that stands for now
 * @param {number} nowMs - the clock
 * @returns {boolean}
 */
function timeLineStale(times, nowIndex, nowMs) {
    if (!times || !times.length || nowIndex < 0 || nowIndex >= times.length)
        return false;
    var nearest = 0;
    for (var k = 1; k < times.length; k++) {
        if (Math.abs(times[k] - nowMs) < Math.abs(times[nearest] - nowMs))
            nearest = k;
    }
    if (nearest !== nowIndex)
        return true;
    var step = times.length < 2 ? 3 * 3600e3 : nowIndex > 0 ? times[nowIndex] - times[nowIndex - 1] : times[1] - times[0];
    return Math.abs(nowMs - times[nowIndex]) > step / 2;
}
