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
  addControl(c) { (this.controls = this.controls || []).push(c); }
  removeControl(c) { this.controls = (this.controls || []).filter((x) => x !== c); }
  getSource(id) { return this.sources[id]; }
  addSource(id, s) {
    this.sources[id] = Object.assign({
      uploads: 0, plays: 0, pauses: 0,
      setData(d) { this.data = d; },
      setTiles(t) { this.tiles = t; },
      setCoordinates(c) { this.coordinates = c; },
      play() { this.plays++; },
      pause() { this.pauses++; }
    }, s);
  }
  removeSource(id) { delete this.sources[id]; }
  getLayer(id) { return this.layers.find((l) => l.id === id); }
  // Layers in drawing order: a layer added or moved before another goes right under it.
  addLayer(l, before) {
    const layer = Object.assign({ layout: {}, paint: {} }, l, { layout: Object.assign({}, l.layout), paint: Object.assign({}, l.paint) });
    const i = before ? this.layers.findIndex((x) => x.id === before) : -1;
    if (i >= 0) this.layers.splice(i, 0, layer); else this.layers.push(layer);
  }
  removeLayer(id) { this.layers = this.layers.filter((l) => l.id !== id); }
  moveLayer(id, before) {
    const l = this.getLayer(id);
    if (!l) return;
    this.removeLayer(id);
    const i = before ? this.layers.findIndex((x) => x.id === before) : -1;
    if (i >= 0) this.layers.splice(i, 0, l); else this.layers.push(l);
  }
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
  getZoom() { return 5; }
}

function loadAdapter(globals, opts = {}) {
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
    document: {
      hidden: false,
      addEventListener() {},
    },
    ImageData: function (data, w, h) { this.data = data; this.width = w; this.height = h; },
    createImageBitmap: (img) => Promise.resolve(img),
    GLOW_INIT: null, NIGHTDEPTH_INIT: null,
  };
  Object.assign(ctx, globals);
  vm.runInNewContext(src + '\nthis.WidgetMapLibreAdapter = WidgetMapLibreAdapter;', ctx);
  const protocols = {};
  const maplibregl = {
    Map: function () { map = new FakeMap(); return map; },
    addProtocol: (name, handler) => { protocols[name] = handler; },
    NavigationControl: function () {},
    AttributionControl: function (opts) { this.opts = opts || {}; },
    Marker: function () { this.setLngLat = () => this; this.addTo = () => this; },
  };
  const adapter = ctx.WidgetMapLibreAdapter(maplibregl);
  adapter.createMap('lv-map', { lat: 48, lon: 6, zoom: 6, maxZoom: 12 });
  if (opts.load !== false) map.fire('load');
  return { adapter, map, ctx, protocols };
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

/** The darkest night and the lightest day in the shade tile of the whole world, 0..1. */
async function shadeOf(map, protocols) {
  const url = map.getSource('lv-night').tiles[0].replace('{z}/{x}/{y}', '0/0/0');
  const name = url.slice(0, url.indexOf('://'));
  const px = (await protocols[name]({ url, type: 'image' }, new AbortController())).data.data;
  let night = 0, day = 0;
  for (let k = 0; k < px.length; k += 4) {
    if (px[k] === 0) night = Math.max(night, px[k + 3]);
    else day = Math.max(day, px[k + 3]);
  }
  return { night: night / 255, day: day / 255 };
}

test('day and night on: one raster of tiles made by the page, 40 % dark at its deepest by default; the glow follows the Sun', async () => {
  const { adapter, map, protocols } = loadAdapter();
  adapter.setDayNight(true);
  assert.equal(map.getLayer('lv-night').type, 'raster');
  assert.equal(map.getSource('lv-night').type, 'raster', 'tiles: the globe extends them to the poles');
  assert.equal(map.getLayer('lv-day'), undefined, 'no layer of its own for the day');
  assert.ok(Math.abs((await shadeOf(map, protocols)).night - 0.4) <= 1 / 255);
  assert.equal(map.light.anchor, 'map');
});

test('the darkness of the night comes from the widget, and changes live', async () => {
  const { adapter, map, protocols } = loadAdapter({ NIGHTDEPTH_INIT: '60' });
  adapter.setDayNight(true);
  assert.ok(Math.abs((await shadeOf(map, protocols)).night - 0.6) <= 1 / 255, 'from the page address');
  const tiles = map.getSource('lv-night').tiles[0];
  adapter.setNightDepth(25);
  assert.notEqual(map.getSource('lv-night').tiles[0], tiles, 'new tiles asked for');
  assert.ok(Math.abs((await shadeOf(map, protocols)).night - 0.25) <= 1 / 255, 'live');
  adapter.setNightDepth('x');
  assert.ok(Math.abs((await shadeOf(map, protocols)).night - 0.25) <= 1 / 255, 'unreadable: unchanged');
  adapter.setDayNight(false);
  adapter.setNightDepth(50);
  adapter.setDayNight(true);
  assert.ok(Math.abs((await shadeOf(map, protocols)).night - 0.5) <= 1 / 255, 'kept while off');
  assert.equal(adapter.getNightDepth(), 50);
});

test('day and night off: no night, and the glow no longer follows the Sun', () => {
  const { adapter, map } = loadAdapter();
  adapter.setDayNight(true);
  adapter.setDayNight(false);
  assert.equal(map.getLayer('lv-night'), undefined);
  assert.equal(map.getSource('lv-night'), undefined);
  assert.equal(map.light.anchor, 'viewport');
});

test('day and night on a dark map: a light veil over the day, as much as before', async () => {
  const { adapter, map, protocols } = loadAdapter();
  adapter.setDayNight(true);
  assert.ok(Math.abs((await shadeOf(map, protocols)).day - 0.07) <= 1 / 255);
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

/** Frame layers the map draws now (not held back with visibility none). */
const shownFrames = (map) => map.layers.filter((l) => /^lv-layer-/.test(l.id) && l.layout.visibility !== 'none').map((l) => l.id);
function sixFrames(adapter) {
  const handles = [0, 1, 2, 3, 4, 5].map(() => adapter.createFrameLayer('https://radar/{z}/{x}/{y}.webp', 'radar'));
  adapter.setFrameOpacity(handles[0], 0.8);
  return handles;
}

test('after a move, the hidden frames come back two at a time, each pair once the map is idle', () => {
  const { adapter, map } = loadAdapter();
  sixFrames(adapter);
  map.fire('movestart');
  assert.equal(shownFrames(map).length, 1, 'only the frame on screen while moving');
  map.fire('moveend');
  assert.equal(shownFrames(map).length, 1, 'not before the map has its own tiles: a zoom goes on by steps');
  map.fire('idle');
  assert.equal(shownFrames(map).length, 3);
  map.fire('idle');
  assert.equal(shownFrames(map).length, 5);
  map.fire('idle');
  assert.equal(shownFrames(map).length, 6);
});

test('a new move cuts the frames coming back short', () => {
  const { adapter, map } = loadAdapter();
  sixFrames(adapter);
  map.fire('movestart');
  map.fire('moveend');
  map.fire('idle');
  map.fire('movestart');
  assert.equal(shownFrames(map).length, 1);
  map.fire('moveend');
  map.fire('idle');
  assert.equal(shownFrames(map).length, 3, 'one pair per idle, not two');
});

test('a frame the viewer waits for or shows comes back at once', () => {
  const { adapter, map } = loadAdapter();
  const h = sixFrames(adapter);
  map.fire('movestart');
  map.fire('moveend');
  adapter.onLayerReady(h[5], () => {});
  assert.ok(shownFrames(map).includes(h[5].layerId), 'waited for');
  adapter.setFrameOpacity(h[4], 0.5);
  assert.ok(shownFrames(map).includes(h[4].layerId), 'shown');
  map.fire('idle');
  map.fire('idle');
  assert.equal(shownFrames(map).length, 6);
});

test('a frame held back stays so when a base map change puts the layers back', () => {
  const { adapter, map, ctx } = loadAdapter();
  sixFrames(adapter);
  map.fire('movestart');
  map.fire('moveend');
  map.fire('idle');
  ctx.BG_CURRENT = 'cyclosm';
  adapter.setBasemap('dark');
  map.layers = [];
  map.fire('style.load');
  assert.equal(shownFrames(map).length, 3);
});

test('a light theme on the same base map takes the light veil off the day', async () => {
  const { adapter, map, protocols } = loadAdapter();
  adapter.setDayNight(true);
  const tiles = map.getSource('lv-night').tiles[0];
  adapter.setBasemap('light');
  assert.notEqual(map.getSource('lv-night').tiles[0], tiles, 'new tiles asked for');
  assert.equal((await shadeOf(map, protocols)).day, 0);
});

/** What glue-prepare.js gives the page: a preparation the test can watch. */
function preparation(active) {
  return { active, begins: 0, ends: 0,
    begin() { this.active = true; this.begins++; },
    end() { this.active = false; this.ends++; },
    preparing() { return this.active; } };
}
/** An adapter on a hidden page that prepares in `mode`, with the viewer's
    moveend callback counted. */
function hiddenPage(mode) {
  const prep = preparation(true);
  const page = loadAdapter({ PREPARE_MODE: mode, widgetPrepare: prep,
    document: { hidden: true, visibilityState: 'hidden', addEventListener() {} } });
  page.prep = prep;
  page.moves = 0;
  page.adapter.onViewportChange(() => page.moves++);
  return page;
}
/** Every source loaded, as when the map has its tiles. */
function allLoaded(map) { for (const id in map.sources) map.loadedSources[id] = true; }

test('first image: the preparation ends once the shown image and the base map are in', () => {
  const { adapter, map, prep } = hiddenPage('first');
  const h = adapter.createFrameLayer('https://radar/1/{z}/{x}/{y}.webp', 'radar');
  map.fire('render');
  assert.equal(prep.ends, 0, 'no image shown yet');
  adapter.setFrameOpacity(h, 0.8);
  map.fire('render');
  assert.equal(prep.ends, 0, 'tiles still loading');
  allLoaded(map);
  map.fire('render');
  assert.equal(prep.ends, 1);
  map.fire('render');
  assert.equal(prep.ends, 1, 'once');
});

test('first image: a hidden page does not pass map moves to the viewer', () => {
  // A move restarts the viewer's preload of every image: page hidden, only
  // the shown image is prepared.
  const page = hiddenPage('first');
  page.map.fire('moveend');
  assert.equal(page.moves, 0);
  page.ctx.document.visibilityState = 'visible';
  page.ctx.document.hidden = false;
  page.map.fire('moveend');
  assert.equal(page.moves, 1, 'on screen, as before');
});

test('whole animation: once the shown image is in, the viewer preloads all, and the preparation waits for them', () => {
  const page = hiddenPage('all'), { adapter, map, prep } = page;
  const shown = adapter.createFrameLayer('https://radar/1/{z}/{x}/{y}.webp', 'radar');
  adapter.setFrameOpacity(shown, 0.8);
  allLoaded(map);
  map.fire('render');
  assert.equal(page.moves, 1, 'the preload is asked');
  assert.equal(prep.ends, 0);
  const other = adapter.createFrameLayer('https://radar/2/{z}/{x}/{y}.webp', 'radar');
  adapter.onLayerReady(other, () => {});
  map.fire('render');
  assert.equal(prep.ends, 0, 'an image still loading');
  allLoaded(map);
  map.fire('sourcedata', { sourceId: other.sourceId });
  map.fire('render');
  assert.equal(prep.ends, 1);
  assert.equal(page.moves, 1, 'asked once');
});

test('a new image while hidden, after a preparation, starts another one', () => {
  const { adapter, map, prep } = hiddenPage('first');
  const h = adapter.createFrameLayer('https://radar/1/{z}/{x}/{y}.webp', 'radar');
  adapter.setFrameOpacity(h, 0.8);
  allLoaded(map);
  map.fire('render');
  assert.equal(prep.active, false);
  adapter.createFrameLayer('https://radar/2/{z}/{x}/{y}.webp', 'radar');
  assert.equal(prep.begins, 1);
  assert.equal(prep.active, true);
});

test('no preparation asked: map moves reach the viewer as before', () => {
  const page = loadAdapter({ document: { hidden: true, visibilityState: 'hidden', addEventListener() {} } });
  let moves = 0;
  page.adapter.onViewportChange(() => moves++);
  page.map.fire('moveend');
  assert.equal(moves, 1);
  page.adapter.createFrameLayer('https://radar/1/{z}/{x}/{y}.webp', 'radar');
  page.map.fire('render');
});

// === Temperature layer ===
const ids = (map) => map.layers.map((l) => l.id);
const provider = () => Promise.resolve(new Uint8ClampedArray(256 * 256 * 4));

test('the temperature goes right over the base map and the night, under the frames', () => {
  const { adapter, map } = loadAdapter({ DAYNIGHT_INIT: true });
  adapter.createFrameLayer('https://radar/a/{z}/{x}/{y}.webp', 'radar');
  adapter.createFrameLayer('https://radar/b/{z}/{x}/{y}.webp', 'radar');
  adapter.setTempTiles(provider, 1, 0.45);
  // The fake map only holds the layers added at run time: lv-base is in the style.
  const order = ids(map).filter((id) => id.indexOf('lv-') === 0);
  assert.deepEqual(order.slice(0, 2), ['lv-night', 'lv-temp']);
  assert.ok(order[2].indexOf('lv-layer-radar-') === 0);
  assert.equal(map.getLayer('lv-temp').paint['raster-opacity'], 0.45);
  const src = map.getSource('lv-temp-src');
  assert.equal(src.type, 'raster');
  assert.deepEqual([...src.tiles], ['lvtemp://1/{z}/{x}/{y}']);
  // Drawn on 256 px, shown on 512: a quarter of the tiles to draw and of the elevation to fetch.
  assert.equal(src.tileSize, 512);
});

test('the temperature tiles come from the layer, z/x/y and the abort signal passed on', async () => {
  const { adapter, protocols } = loadAdapter();
  const asked = [];
  const ctl = new AbortController();
  adapter.setTempTiles((z, x, y, signal) => {
    asked.push([z, x, y, signal]);
    return Promise.resolve(new Uint8ClampedArray(256 * 256 * 4).fill(9));
  }, 3, 0.45);
  const res = await protocols.lvtemp({ url: 'lvtemp://3/5/16/11' }, ctl);
  assert.deepEqual(asked, [[5, 16, 11, ctl.signal]]);
  assert.equal(res.data.width, 256);
  assert.equal(res.data.data[0], 9);
});

test('new temperature tiles: same source, new tile address', () => {
  const { adapter, map } = loadAdapter();
  adapter.setTempTiles(provider, 1, 0.45);
  adapter.setTempTiles(provider, 2, 0.45);
  assert.deepEqual([...map.getSource('lv-temp-src').tiles], ['lvtemp://2/{z}/{x}/{y}']);
  assert.equal(ids(map).filter((id) => id === 'lv-temp').length, 1);
});

test('the night switched on later still goes under the temperature', () => {
  const { adapter, map } = loadAdapter();
  adapter.setTempTiles(provider, 1, 0.45);
  adapter.setDayNight(true);
  const order = ids(map).filter((id) => id.indexOf('lv-') === 0);
  assert.ok(order.indexOf('lv-night') < order.indexOf('lv-temp'));
});

test('a satellite frame added later still goes over the temperature', () => {
  const { adapter, map } = loadAdapter();
  adapter.setTempTiles(provider, 1, 0.45);
  const sat = adapter.createFrameLayer('https://sat/{z}/{x}/{y}.webp', 'satellite');
  assert.ok(ids(map).indexOf('lv-temp') < ids(map).indexOf(sat.layerId));
});

test('a base map change puts the temperature back, at the same place', () => {
  const { adapter, map, ctx } = loadAdapter();
  const radar = adapter.createFrameLayer('https://radar/{z}/{x}/{y}.webp', 'radar');
  adapter.setTempTiles(provider, 4, 0.3);
  ctx.BG_CURRENT = 'cyclosm';
  adapter.setBasemap('light');
  // What MapLibre does with a new style: only its own layers and sources are left.
  map.layers = []; map.sources = {};
  for (const l of map.loadedStyle.layers) map.addLayer(l);
  for (const id in map.loadedStyle.sources) map.addSource(id, map.loadedStyle.sources[id]);
  map.fire('style.load');
  const order = ids(map);
  assert.ok(order.indexOf('lv-temp') > order.indexOf('lv-base'));
  assert.ok(order.indexOf('lv-temp') < order.indexOf(radar.layerId));
  assert.equal(map.getLayer('lv-temp').paint['raster-opacity'], 0.3);
  assert.deepEqual([...map.getSource('lv-temp-src').tiles], ['lvtemp://4/{z}/{x}/{y}']);
});

test('setTempOpacity changes the layer only; clearTemp removes layer and source', async () => {
  const { adapter, map, protocols } = loadAdapter();
  adapter.setTempTiles(provider, 1, 0.45);
  adapter.setTempOpacity(0.8);
  assert.equal(map.getLayer('lv-temp').paint['raster-opacity'], 0.8);
  adapter.clearTemp();
  assert.equal(map.getLayer('lv-temp'), undefined);
  assert.equal(map.getSource('lv-temp-src'), undefined);
  // A tile asked for just before: empty.
  const res = await protocols.lvtemp({ url: 'lvtemp://1/0/0/0' }, new AbortController());
  assert.equal(res.data.data.every((v) => v === 0), true);
});

test('setDataAttribution adds the Open-Meteo line once, and takes it away', () => {
  const { adapter, map } = loadAdapter();
  const lines = () => map.controls.filter((c) => c.opts && c.opts.customAttribution).map((c) => c.opts.customAttribution);
  assert.deepEqual(lines(), []);
  adapter.setDataAttribution(true);
  adapter.setDataAttribution(true);
  assert.equal(lines().length, 1);
  assert.ok(/open-meteo\.com/.test(lines()[0]));
  adapter.setDataAttribution(false);
  assert.deepEqual(lines(), []);
  assert.equal(map.controls.filter((c) => c instanceof Object && 'opts' in c).length, 1, 'one attribution control at a time');
});

test('temperature tiles given before the style loads show once it has', () => {
  const { adapter, map } = loadAdapter({}, { load: false });
  adapter.setTempTiles(provider, 2, 0.45);
  assert.equal(map.getLayer('lv-temp'), undefined);
  map.fire('load');
  assert.ok(map.getLayer('lv-temp'));
  assert.deepEqual([...map.getSource('lv-temp-src').tiles], ['lvtemp://2/{z}/{x}/{y}']);
});

// === Coasts and borders over the color layers ===
const LINES = { type: 'FeatureCollection', features: [] };
const linesGlobals = (fetched) => ({
  fetch: (url) => { fetched.push(url); return Promise.resolve({ ok: true, arrayBuffer: () => Promise.resolve('bin') }); },
  WidgetEarth: Object.assign({}, require('../glue-earth.js'), { decodeLines: (b) => (b === 'bin' ? LINES : null) })
});

test('the temperature brings the coasts and borders right over it, under the frames', async () => {
  const fetched = [];
  const { adapter, map } = loadAdapter(linesGlobals(fetched));
  const radar = adapter.createFrameLayer('https://radar/{z}/{x}/{y}.webp', 'radar');
  adapter.setTempTiles(provider, 1, 0.45);
  await tick(); await tick();
  const order = ids(map);
  assert.equal(order.indexOf('lv-lines'), order.indexOf('lv-temp') + 1);
  assert.ok(order.indexOf('lv-lines') < order.indexOf(radar.layerId));
  assert.equal(map.getLayer('lv-lines').type, 'line');
  assert.equal(map.getSource('lv-lines-src').data, LINES);
  // The widget's own file, read once.
  assert.deepEqual(fetched, ['vendor/coast-borders.bin']);
});

test('the lines are fetched once, whatever asks for them', async () => {
  const fetched = [];
  const { adapter } = loadAdapter(linesGlobals(fetched));
  adapter.setTempTiles(provider, 1, 0.45);
  adapter.clearTemp();
  adapter.setTempTiles(provider, 2, 0.45);
  adapter.setLines('pressure', true);
  await tick(); await tick();
  assert.equal(fetched.length, 1);
});

const linesVisible = (map) => !!map.getLayer('lv-lines') && map.getLayer('lv-lines').layout.visibility !== 'none';

test('the lines stay while one layer still wants them, then only hide', async () => {
  const { adapter, map } = loadAdapter(linesGlobals([]));
  adapter.setTempTiles(provider, 1, 0.45);
  adapter.setLines('pressure', true);
  await tick(); await tick();
  adapter.clearTemp();
  assert.ok(linesVisible(map));
  const source = map.getSource('lv-lines-src');
  adapter.setLines('pressure', false);
  assert.equal(linesVisible(map), false);
  // Kept, tiles and all: the next color layer shows them at once.
  assert.equal(map.getSource('lv-lines-src'), source);
});

test('one color layer for another: the same lines, never made again', async () => {
  const { adapter, map } = loadAdapter(linesGlobals([]));
  const radar = adapter.createFrameLayer('https://radar/{z}/{x}/{y}.webp', 'radar');
  adapter.setTempTiles(provider, 1, 0.45);
  await tick(); await tick();
  const source = map.getSource('lv-lines-src'), layer = map.getLayer('lv-lines');
  adapter.clearTemp();
  adapter.setLines('pressure', true);
  map.addLayer({ id: 'lv-pres-gl', type: 'custom' }, adapter.linesBefore());
  assert.equal(map.getSource('lv-lines-src'), source);
  assert.equal(map.getLayer('lv-lines'), layer);
  assert.ok(linesVisible(map));
  adapter.setLines('pressure', false);
  adapter.setTempTiles(provider, 2, 0.45);
  const order = ids(map);
  assert.ok(order.indexOf('lv-temp') < order.indexOf('lv-lines'), order.join());
  assert.ok(order.indexOf('lv-lines') < order.indexOf(radar.layerId));
  assert.ok(linesVisible(map));
});

test('the night switched on later goes under the lines kept hidden', async () => {
  const { adapter, map } = loadAdapter(linesGlobals([]));
  adapter.setTempTiles(provider, 1, 0.45);
  await tick(); await tick();
  adapter.clearTemp();
  adapter.setDayNight(true);
  assert.ok(ids(map).indexOf('lv-night') < ids(map).indexOf('lv-lines'));
});

test('turned off before the file arrives: no lines', async () => {
  const { adapter, map } = loadAdapter(linesGlobals([]));
  adapter.setTempTiles(provider, 1, 0.45);
  adapter.clearTemp();
  await tick(); await tick();
  assert.equal(linesVisible(map), false);
});

test('a color layer of another script goes under the lines through linesBefore()', async () => {
  const { adapter, map } = loadAdapter(linesGlobals([]));
  const radar = adapter.createFrameLayer('https://radar/{z}/{x}/{y}.webp', 'radar');
  assert.equal(adapter.linesBefore(), undefined);
  adapter.setLines('pressure', true);
  await tick(); await tick();
  assert.equal(adapter.linesBefore(), 'lv-lines');
  map.addLayer({ id: 'lv-pres-gl', type: 'custom' }, adapter.linesBefore());
  const order = ids(map);
  assert.ok(order.indexOf('lv-pres-gl') < order.indexOf('lv-lines'));
  assert.ok(order.indexOf('lv-lines') < order.indexOf(radar.layerId));
});

test('a satellite frame added later goes over the lines too', async () => {
  const { adapter, map } = loadAdapter(linesGlobals([]));
  adapter.setTempTiles(provider, 1, 0.45);
  await tick(); await tick();
  const sat = adapter.createFrameLayer('https://sat/{z}/{x}/{y}.webp', 'satellite');
  assert.ok(ids(map).indexOf('lv-lines') < ids(map).indexOf(sat.layerId));
});

test('a base map change puts the lines back over the temperature', async () => {
  const { adapter, map, ctx } = loadAdapter(linesGlobals([]));
  adapter.setTempTiles(provider, 4, 0.3);
  await tick(); await tick();
  ctx.BG_CURRENT = 'cyclosm';
  adapter.setBasemap('light');
  map.layers = []; map.sources = {};
  for (const l of map.loadedStyle.layers) map.addLayer(l);
  for (const id in map.loadedStyle.sources) map.addSource(id, map.loadedStyle.sources[id]);
  map.fire('style.load');
  const order = ids(map);
  assert.equal(order.indexOf('lv-lines'), order.indexOf('lv-temp') + 1);
  assert.equal(map.getSource('lv-lines-src').data, LINES);
});

test('lines switched off: none drawn, even wanted; back on, they come back', async () => {
  const { adapter, map } = loadAdapter(linesGlobals([]));
  adapter.setTempTiles(provider, 1, 0.45);
  await tick(); await tick();
  adapter.setLinesShown(false);
  assert.equal(linesVisible(map), false);
  adapter.setLinesShown(true);
  assert.ok(linesVisible(map));
  assert.equal(ids(map).indexOf('lv-lines'), ids(map).indexOf('lv-temp') + 1);
});

test('the widget can open the page with the lines off, and nothing is fetched', async () => {
  const fetched = [];
  const { adapter, map } = loadAdapter(Object.assign(linesGlobals(fetched), { LINES_INIT: false }));
  adapter.setTempTiles(provider, 1, 0.45);
  await tick(); await tick();
  assert.equal(map.getLayer('lv-lines'), undefined);
  assert.deepEqual(fetched, []);
  assert.equal(adapter.getLinesShown(), false);
});
