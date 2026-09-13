// ==========================================================================
// Glue script 1: query-param parsing + widget globals (BEFORE the engine).
// ==========================================================================
var PARAMS = new URLSearchParams(window.location.search);

function paramNum(name, fallback) {
  var v = parseFloat(PARAMS.get(name));
  return isNaN(v) ? fallback : v;
}

// Contract defaults: lat/lon (0), zoom (7 clamped 3..12), server, hour12,
// locale, strings, bglist, bg, layer, color (rounded 0..12), arrows, theme.
var LAT = paramNum('lat', 0);
var LON = paramNum('lon', 0);
var INIT_ZOOM = Math.max(3, Math.min(12, paramNum('zoom', 7)));
var API_BASE = PARAMS.get('server') || 'https://api.librewxr.net';
var HOUR12 = PARAMS.get('hour12') === '1';
var SYS_LOCALE = PARAMS.get('locale') || undefined;

var STRINGS = {};
try { STRINGS = JSON.parse(PARAMS.get('strings') || '{}'); } catch (e) {}

function tr(key, fallback) {
  return STRINGS[key] || fallback;
}

var BG_LIST = [];
try { BG_LIST = JSON.parse(PARAMS.get('bglist') || '[]'); } catch (e) {}

// "auto" resolves against the current map theme; an explicit id stays put.
function bgEntry(id) {
  for (var i = 0; i < BG_LIST.length; i++) {
    if (BG_LIST[i].id === id) return BG_LIST[i];
  }
  return null;
}

// Fallback tiles for the (unexpected) case where QML sent no choices at all.
// Keyless vendor vector styles cannot serve as the raster fallback: they need
// MapLibre, and without a WebGL context there is nothing to draw. The dark
// entry is the OpenFreeMap Dark vector style with the standard OSM raster
// tiles as the stand-in until MapLibre has loaded (or if it never does); the
// light entry is plain OSM-standard raster tiles.
var FALLBACK_BG = {
  dark: {
    id: 'auto',
    styleUrl: 'https://tiles.openfreemap.org/styles/dark',
    vector: true,
    // Raster stand-in used until MapLibre has loaded, and if it never does.
    url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '&copy; <a href="https://openstreetmap.org">OpenStreetMap</a> contributors | Tiles by <a href="https://openfreemap.org/">OpenFreeMap</a> | <a href="https://librewxr.net/">LibreWXR</a>'
  },
  light: {
    id: 'auto',
    url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '&copy; <a href="https://openstreetmap.org">OpenStreetMap</a> contributors | <a href="https://librewxr.net/">LibreWXR</a>'
  }
};

function resolveBg(id, theme) {
  if (id === 'auto') {
    var themed = bgEntry(theme === 'dark' ? 'openfreemap-dark' : 'osm-standard');
    return themed || FALLBACK_BG[theme] || FALLBACK_BG.dark;
  }
  return bgEntry(id) || FALLBACK_BG[theme] || FALLBACK_BG.dark;
}

var ARROWS_ON = PARAMS.get('arrows') === '1';
var ACTIVE_LAYER = PARAMS.get('layer') || 'radar';   // 'radar' | 'satellite' | 'both'
var CELLS_INIT = PARAMS.get('cells') || '';
var ALERTS_INIT = PARAMS.get('alerts') === '1';
var SMOOTH_INIT = PARAMS.get('smooth') === null ? true : PARAMS.get('smooth') === '1';
var SNOW_INIT = PARAMS.get('snow') === null ? true : PARAMS.get('snow') === '1';
var FORMAT_INIT = PARAMS.get('format') || 'webp';
var TILESIZE_INIT = PARAMS.get('tilesize') || 'auto';
var CURRENT_COLOR = Math.max(0, Math.min(12, Math.round(paramNum('color', 10))));
var ACTIVE_THEME = PARAMS.get('theme') === 'light' ? 'light' : 'dark';
var BG_CURRENT = PARAMS.get('bg') || 'auto';

// The page ships a generic UI font stack (-apple-system, Segoe UI, Roboto...),
// none of which is what Plasma is using, so the toolbar and its dropdowns end
// up in a different typeface from the rest of the widget. QML passes the
// theme's font family; feed it to --font-ui, which the viewer stylesheet
// already keys off. Quoted because family names carry spaces.
(function () {
  var family = (PARAMS.get('font') || '').trim();
  if (!family) return;
  var stack = '"' + family.replace(/"/g, '') + '", "Noto Sans", sans-serif';
  var style = document.createElement('style');
  style.textContent = ':root { --font-ui: ' + stack + '; }';
  document.head.appendChild(style);
})();

// Wind layer (glue-wind.js): on/off, frame rate and elevation weighting are
// test knobs seeded from the URL; the QML side only drives on/off.
var WIND_ON = PARAMS.get('wind') === '1';
var WIND_FPS = Math.max(4, Math.min(30, paramNum('windfps', 10)));
var WIND_MAX_FPS = Math.max(WIND_FPS, Math.min(30, paramNum('windmaxfps', 20)));
var WIND_RELIEF = PARAMS.get('windrelief') !== '0';
var WIND_LEVEL = PARAMS.get('windlevel') === '700hPa' ? '700hPa' : '10m';
