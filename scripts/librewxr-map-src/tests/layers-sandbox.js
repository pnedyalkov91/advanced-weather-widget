'use strict';
// Loads the layer fragments (glue-fields.js, glue-pressure.js, glue-airquality.js,
// glue-precip.js, glue-clouds.js, glue-humidity.js) under Node. In the page
// they run inside its module, after glue-controls.js, and reach its
// variables (ANIM_LAYERS, anim, the adapter, the readout): here those are
// stand-ins in a vm context, so the computed parts can be tested.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SRC = path.join(__dirname, '..');
const LAYERS = [
  ['glue-fields.js', 'WidgetFields'],
  ['glue-pressure.js', 'WidgetPressure'],
  ['glue-airquality.js', 'WidgetAirQuality'],
  ['glue-precip.js', 'WidgetPrecip'],
  ['glue-clouds.js', 'WidgetClouds'],
  ['glue-humidity.js', 'WidgetHumidity']
];

function fakeElement() {
  return {
    style: {}, dataset: {}, classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    appendChild(c) { return c; }, removeChild() {}, remove() {}, setAttribute() {}, addEventListener() {},
    querySelector() { return null; }, querySelectorAll() { return []; }, getContext() { return null; }
  };
}

/** The layers' modules, by name, and the page's stand-ins they filled in. */
function loadLayers() {
  const ctx = {
    console, setTimeout, clearTimeout, setInterval, clearInterval,
    // The page's switch of a layer, as glue-controls.js leaves it: here it notes the calls.
    window: { animSetLayer(id, on) { ctx.switched.push([id, on]); } },
    switched: [],
    document: {
      createElement: fakeElement, head: fakeElement(), body: fakeElement(), documentElement: fakeElement(),
      getElementById() { return null; }, addEventListener() {}, querySelector() { return null; }, querySelectorAll() { return []; }
    },
    ANIM_LAYERS: {}, ANIM_KEYS: {}, anim: null,
    _widgetAdapter: { getMap() { return null; }, setLines() {}, linesBefore() { return null; } },
    maplibregl: { addProtocol() {} },
    _windOpen: { base: 'b/', model: 'ecmwf_ifs025', importReader() {}, fetch() {} }, tempUnit: 'C', readout: {},
    readoutHtml() { return ''; },
    // The readout's helpers of glue-controls.js: the lines the layers add are noted.
    readouts: [],
    addReadout(track, line) { ctx.readouts.push({ track, line }); },
    readoutRow(icon, color, text) { return color + '|' + text; },
    animSetLayer() {},
    currentTheme() { return 'dark'; },
    tr(key, fallback) { return fallback; }
  };
  ctx.WidgetAnim = require('../glue-anim.js');
  ctx.WidgetOpenData = require('../glue-wind-open.js');
  ctx.WidgetTemp = require('../glue-temp.js');
  ctx.WidgetGrids = require('../glue-grids.js');
  // The shared GL layer (WidgetTemp.TempLayerGL), as the page loads it before them.
  if (!ctx.WidgetTemp.TempLayerGL) {
    global.WidgetWind = global.WidgetWind || require('../glue-wind.js');
    global.WidgetTemp = ctx.WidgetTemp;
    global.WidgetGrids = ctx.WidgetGrids;
    require('../glue-temp-layer.js');
    require('../glue-temp-gl.js');
  }
  ctx.self = ctx.window;
  vm.createContext(ctx);
  const code = LAYERS.map(([file]) => fs.readFileSync(path.join(SRC, file), 'utf8')).join('\n');
  vm.runInContext(code + '\n;this.__layers = { ' + LAYERS.map(([, name]) => name + ': ' + name).join(', ') + ' };', ctx, { filename: 'layers' });
  return Object.assign({ ctx }, ctx.__layers);
}

module.exports = { loadLayers };
