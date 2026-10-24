'use strict';
// Unit tests for the frame layers of glue-adapter-maplibre.js, on a fake
// MapLibre. The page globals the adapter reads are stubbed here.
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

/** A fake MapLibre map: sources, layers and events, no drawing. */
class FakeMap {
  constructor() {
    this.handlers = {};
    this.sources = {};
    this.layers = [];
    this.loadedSources = {};
  }
  on(e, f) { (this.handlers[e] = this.handlers[e] || []).push(f); }
  once(e, f) { const g = (x) => { this.off(e, g); f(x); }; this.on(e, g); }
  off(e, f) { this.handlers[e] = (this.handlers[e] || []).filter((h) => h !== f); }
  fire(e, data) { (this.handlers[e] || []).slice().forEach((f) => f(data || {})); }
  addControl() {}
  getSource(id) { return this.sources[id]; }
  addSource(id, s) { this.sources[id] = Object.assign({ setData(d) { this.data = d; } }, s); }
  removeSource(id) { delete this.sources[id]; }
  getLayer(id) { return this.layers.find((l) => l.id === id); }
  addLayer(l) { this.layers.push(Object.assign({ layout: {} }, l)); }
  removeLayer(id) { this.layers = this.layers.filter((l) => l.id !== id); }
  moveLayer() {}
  getStyle() { return { layers: this.layers, sources: this.sources }; }
  isSourceLoaded(id) {
    if (!this.sources[id]) throw new Error('There is no source with ID ' + id);
    return !!this.loadedSources[id];
  }
  setPaintProperty(id, k, v) { const l = this.getLayer(id); if (l) l.paint[k] = v; }
  setLayoutProperty(id, k, v) { const l = this.getLayer(id); if (l) l.layout[k] = v; }
  setProjection() {}
  // The style MapLibre loads: the one given, through transformStyle if any.
  setStyle(style, opts) {
    this.loadedStyle = opts && opts.transformStyle ? opts.transformStyle(this.getStyle(), style) : style;
  }
  setSky(sky) { this.sky = sky; }
  setLight(l) { this.light = l; }
  getContainer() { return { clientWidth: 800, clientHeight: 330 }; }
  getMinZoom() { return 0; }
  getMaxZoom() { return 12; }
  setMinZoom() {}
  getCenter() { return { lat: 48, lng: 6 }; }
}

function loadAdapter(globals) {
  const src = fs.readFileSync(path.join(__dirname, '../glue-adapter-maplibre.js'), 'utf8');
  let map = null;
  const ctx = {
    console, clearTimeout, clearInterval, Date, Math, String,
    // The page's long timers (25 s wait, the Sun every minute) must not keep the test alive.
    setTimeout: (f, t) => { const h = setTimeout(f, t); if (t > 1000) h.unref(); return h; },
    setInterval: (f, t) => setInterval(f, t).unref(),
    PARAMS: new URLSearchParams(''),
    PROJECTION_INIT: 'flat', DAYNIGHT_INIT: false, BG_CURRENT: 'osm-dark',
    FALLBACK_BG: { dark: { url: 'https://tiles/{z}/{x}/{y}.png' }, light: { url: 'https://tiles/{z}/{x}/{y}.png' } },
    resolveBg: (id) => ({ url: 'https://' + id + '/{z}/{x}/{y}.png' }),
    WidgetEarth: require('../glue-earth.js'),
    document: { hidden: false, addEventListener() {} },
    GLOW_INIT: null,
  };
  Object.assign(ctx, globals);
  vm.runInNewContext(src + '\nthis.WidgetMapLibreAdapter = WidgetMapLibreAdapter;', ctx);
  const maplibregl = {
    Map: function () { map = new FakeMap(); return map; },
    NavigationControl: function () {},
    Marker: function () { this.setLngLat = () => this; this.addTo = () => this; },
  };
  const adapter = ctx.WidgetMapLibreAdapter(maplibregl);
  adapter.createMap('lv-map', { lat: 48, lon: 6, zoom: 6, maxZoom: 12 });
  map.fire('load');
  return { adapter, map, ctx };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

test('a frame layer destroyed while loading settles at once, not 25 s later', async () => {
  const { adapter } = loadAdapter();
  const handle = adapter.createFrameLayer('https://radar/{z}/{x}/{y}.webp', 'radar');
  let calls = 0;
  adapter.onLayerReady(handle, () => calls++);
  adapter.destroyFrameLayer(handle);
  assert.equal(calls, 0, 'not from inside the destroy: the viewer is still clearing its cache');
  await tick();
  assert.equal(calls, 1);
});

test('a frame layer that loads settles once, on its source data', async () => {
  const { adapter, map } = loadAdapter();
  const handle = adapter.createFrameLayer('https://radar/{z}/{x}/{y}.webp', 'radar');
  let calls = 0;
  adapter.onLayerReady(handle, () => calls++);
  map.loadedSources[handle.sourceId] = true;
  map.fire('sourcedata', { sourceId: handle.sourceId });
  map.fire('sourcedata', { sourceId: handle.sourceId });
  adapter.destroyFrameLayer(handle);
  await tick();
  assert.equal(calls, 1);
});

test('a base map change on the globe loads the new style already on the globe', () => {
  // A style without projection is a flat map: MapLibre would hold the
  // globe's minimum zoom as a flat one there, and the globe came back bigger.
  const { adapter, map, ctx } = loadAdapter();
  adapter.setProjection('globe');
  ctx.BG_CURRENT = 'cyclosm';
  adapter.setBasemap('light');
  assert.equal(map.loadedStyle.projection.type, 'globe');
  assert.ok(map.loadedStyle.sources['lv-base'], 'the base map is still there');
});

test('day and night on: a night in fine steps, as deep as before; the glow follows the Sun', () => {
  const { adapter, map } = loadAdapter();
  adapter.setDayNight(true);
  const opacity = map.getLayer('lv-night').paint['fill-opacity'];
  const steps = map.getSource('lv-night').data.features.length;
  assert.ok(steps >= 10, steps + ' steps');
  // Deep night: as dark as the four bands of 0.13 it replaces.
  const depth = 1 - Math.pow(1 - opacity, steps);
  assert.ok(Math.abs(depth - (1 - Math.pow(0.87, 4))) < 0.01, 'deep night ' + depth);
  assert.equal(map.light.anchor, 'map');
});

test('day and night off: no night, and the glow no longer follows the Sun', () => {
  const { adapter, map } = loadAdapter();
  adapter.setDayNight(true);
  adapter.setDayNight(false);
  assert.equal(map.getLayer('lv-night'), undefined);
  assert.equal(map.light.anchor, 'viewport');
});

test('day and night on a dark map: the day brightens in fine steps, as much as before', () => {
  const { adapter, map } = loadAdapter();
  adapter.setDayNight(true);
  const opacity = map.getLayer('lv-day').paint['fill-opacity'];
  const steps = map.getSource('lv-day').data.features.length;
  assert.ok(steps >= 10, steps + ' steps');
  const depth = 1 - Math.pow(1 - opacity, steps);
  assert.ok(Math.abs(depth - 0.07) < 0.005, 'full day ' + depth);
});

/** How much the globe's atmosphere blends in with the widest view (zoom 0). */
const blendAtZoom0 = (map) => map.sky['atmosphere-blend'][4];

test('the glow of the atmosphere is 30 % of full strength unless the widget says otherwise', () => {
  assert.ok(Math.abs(blendAtZoom0(loadAdapter().map) - 0.15) < 1e-9);
  assert.ok(Math.abs(blendAtZoom0(loadAdapter({ GLOW_INIT: '80' }).map) - 0.4) < 1e-9);
  assert.ok(Math.abs(blendAtZoom0(loadAdapter({ GLOW_INIT: 'x' }).map) - 0.15) < 1e-9, 'unreadable: default');
});

test('setGlow sets the glow live, from none to full strength', () => {
  const { adapter, map } = loadAdapter();
  adapter.setGlow(100);
  assert.equal(blendAtZoom0(map), 0.5);
  adapter.setGlow(0);
  assert.equal(blendAtZoom0(map), 0);
  adapter.setGlow(250);
  assert.equal(blendAtZoom0(map), 0.5, 'held within 0..100');
  assert.equal(adapter.getGlow(), 100);
});
