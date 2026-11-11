/*
 * mapIcons.js - icons of the Weather Map's layers and radar menu, in the
 * icon theme picked for the map (cfg weatherMapIconTheme).
 *
 * "weathermap" keeps the map's own drawings (contents/icons/weathermap/);
 * the bundled themes take a wi-* file of contents/icons/<theme>/<size>/;
 * "kde" takes an icon of the Plasma icon theme.
 *
 * .pragma library - no Qt globals, pure JS.
 */
.pragma library

// Map's own drawing (relative to contents/icons/) and whether it
// is a white drawing to tint with the text color.
var _own = {
    radar:         { file: "weathermap/radar.svg", mask: false },
    satellite:     { file: "weathermap/satellite.svg", mask: false },
    wind:          { file: "weathermap/vent-glyph.svg", mask: false },
    temperature:   { file: "weathermap/temperature-glyph.svg", mask: false },
    precipitation: { file: "weathermap/precipitations-glyph.svg", mask: false },
    clouds:        { file: "weathermap/nuages-glyph.svg", mask: true },
    pressure:      { file: "weathermap/pression-glyph.svg", mask: false },
    isobars:       { file: "weathermap/isobares-glyph.svg", mask: false },
    humidity:      { file: "weathermap/humidite-glyph.svg", mask: false },
    dewpoint:      { file: "weathermap/rosee-glyph.svg", mask: false },
    airquality:    { file: "weathermap/qualite-air-glyph.svg", mask: true },
    snow:          { file: "weathermap/radar/neige.svg", mask: false },
    lightning:     { file: "weathermap/radar/eclairs.svg", mask: false },
    cells:         { file: "flat-color/22/wi-thunderstorm.svg", mask: false },
    arrows:        { file: "weathermap/radar/fleches-vent.svg", mask: false },
    alerts:        { file: "weathermap/radar/alertes.svg", mask: false }
};

// wi-* stems, first one the theme has wins.
var _stems = {
    radar:         ["rain", "umbrella"],
    satellite:     ["day-cloudy"],
    wind:          ["strong-wind"],
    temperature:   ["thermometer"],
    precipitation: ["raindrops"],
    clouds:        ["cloudy"],
    pressure:      ["barometer"],
    isobars:       ["barometer"],
    humidity:      ["humidity"],
    dewpoint:      ["dew-point", "raindrop"],
    airquality:    ["smog"],
    snow:          ["snowflake-cold"],
    lightning:     ["lightning", "day-thunderstorm"],
    cells:         ["thunderstorm", "day-thunderstorm"],
    arrows:        ["wind-deg"],
    alerts:        ["storm-warning"]
};

// Stems a bundled theme lacks (Meteocons only ships a subset).
var _missing = {
    meteocons: { "rain": 1, "showers": 1, "cloud": 1, "dew-point": 1, "snow": 1,
                 "lightning": 1, "thunderstorm": 1, "windy": 1 }
};

// Plasma icon names: [wanted, fallback found in Breeze].
var _kde = {
    radar:         ["weather-showers-scattered", "weather-showers-scattered"],
    satellite:     ["weather-clouds", "weather-clouds"],
    wind:          ["weather-windy", "weather-clear-wind"],
    temperature:   ["thermometer", "weather-clear"],
    precipitation: ["weather-showers", "weather-showers"],
    clouds:        ["weather-many-clouds", "weather-many-clouds"],
    pressure:      ["weather-pressure", "weather-overcast"],
    isobars:       ["weather-pressure", "weather-overcast"],
    humidity:      ["weather-humidity", "raindrop"],
    dewpoint:      ["raindrop", "raindrop"],
    airquality:    ["weather-mist", "weather-fog"],
    snow:          ["weather-snow", "weather-snow"],
    lightning:     ["weather-storm", "weather-storm"],
    cells:         ["weather-showers-scattered-storm", "weather-storm"],
    arrows:        ["weather-clear-wind", "weather-clear-wind"],
    alerts:        ["dialog-warning", "dialog-warning"]
};

var THEMES = ["weathermap", "symbolic", "flat-color", "3d-oxygen", "meteocons", "kde"];

// Folder size for a drawn size: the smallest one at least as big.
function _sizeDir(px) {
    var sizes = [16, 22, 24, 32];
    for (var i = 0; i < sizes.length; ++i)
        if (sizes[i] >= px)
            return sizes[i];
    return 32;
}

/**
 * Icon of a map layer or radar option.
 * Returns { source, fallback, mask }: source is a URL or, for "kde", an icon
 * name (fallback is then a Breeze name to show if the theme lacks it).
 * Unknown key: source "".
 *
 * @param {string} key       - layer or option key (radar, wind, snow, cells…)
 * @param {string} theme     - one of THEMES
 * @param {real}   px        - drawn size
 * @param {string} iconsBase - resolved URL of contents/icons/ (ends with "/")
 */
function resolve(key, theme, px, iconsBase) {
    var own = _own[key];
    if (!own)
        return { source: "", fallback: "", mask: false };
    if (theme === "kde") {
        var k = _kde[key];
        return { source: k[0], fallback: k[1], mask: false };
    }
    if (THEMES.indexOf(theme) <= 0)
        return { source: iconsBase + own.file, fallback: "", mask: own.mask };
    var missing = _missing[theme] || {};
    var stems = _stems[key];
    var stem = stems[stems.length - 1];
    for (var i = 0; i < stems.length; ++i) {
        if (!missing[stems[i]]) {
            stem = stems[i];
            break;
        }
    }
    return {
        source: iconsBase + theme + "/" + _sizeDir(px) + "/wi-" + stem + ".svg",
        fallback: "",
        mask: theme === "symbolic"
    };
}
