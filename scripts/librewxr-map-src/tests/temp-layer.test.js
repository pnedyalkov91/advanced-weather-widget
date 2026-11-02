'use strict';
// Unit tests for the temperature layer of the MapLibre map (glue-temp-layer.js),
// on a fake adapter, a fake map, a fake DOM and the real temperature math.
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');

global.WidgetWind = require('../glue-wind.js');
global.WidgetTemp = require('../glue-temp.js');
const WidgetOpenData = require('../glue-wind-open.js');
require('../glue-temp-layer.js');
const T = global.WidgetTemp;
const { WindField, WindSource } = global.WidgetWind;

// Each performance.now() call is 1 ms later: a slice of a few ms draws a few rows.
let clock = 0;
Object.defineProperty(globalThis, 'performance', { value: { now: () => (clock += 1) }, configurable: true });
let rafQueue = [];
global.requestAnimationFrame = (f) => rafQueue.push(f);
function flushRaf() { for (let i = 0; i < 100000 && rafQueue.length; i++) rafQueue.shift()(); }
const tick = () => new Promise((r) => setTimeout(r, 0));
async function settle() { for (let i = 0; i < 10; i++) { await tick(); flushRaf(); } }

function element(tag) {
  const el = {
    tag, style: {}, children: [], innerHTML: '', className: '', id: '', width: 0, height: 0, removed: false, image: null,
    appendChild(c) { this.children.push(c); return c; },
    remove() { this.removed = true; },
    getContext() {
      return {
        fillStyle: '', fillRect() {}, clearRect() {},
        createImageData: (w, h) => ({ width: w, height: h, data: new Uint8ClampedArray(w * h * 4) }),
        putImageData: (img) => { el.image = img; },
      };
    },
  };
  return el;
}
const container = element('div');
global.document = { createElement: element, getElementById: (id) => (id === 'lv-map' ? container : null) };

const NOW = Date.parse('2026-10-30T12:00:00Z');
const EUROPE = { west: -10, south: 35, east: 30, north: 60 };

function fakeMap(zoom) {
  const handlers = {};
  return {
    zoom,
    on: (e, f) => { (handlers[e] = handlers[e] || []).push(f); },
    off: (e, f) => { handlers[e] = (handlers[e] || []).filter((h) => h !== f); },
    fire: (e) => (handlers[e] || []).slice().forEach((f) => f()),
    getZoom() { return this.zoom; },
    getContainer: () => ({ clientWidth: 100, clientHeight: 50 }),
  };
}

/** The adapter: every setTempTiles() kept, its provider called by tile(). */
function fakeAdapter(bounds) {
  return {
    bounds, tiles: [], opacities: [], cleared: 0,
    getBounds() { return this.bounds; },
    setTempTiles(provider, version, opacity) { this.tiles.push({ provider, version, opacity }); },
    setTempOpacity(o) { this.opacities.push(o); },
    clearTemp() { this.cleared++; },
  };
}

/** The file: 6.3 °C everywhere; the model's ground at 2076 m everywhere. */
function fakeOpen(opts = {}) {
  const grid = WidgetOpenData.toScalarGrid(new Float32Array(12).fill(6.3), 3, 4, NOW);
  const surface = WidgetOpenData.toScalarGrid(new Float32Array(12).fill(2076), 3, 4, null);
  return {
    res: 0.25,
    keptTemp: async () => (opts.fail ? null : grid),
    loadTemp: async () => (opts.fail ? null : { grid, changed: false }),
    loadSurface: async () => (opts.noSurface ? null : surface),
  };
}

/** Elevation tiles: `height` everywhere once ensureTile() has resolved
    (at once, or when resolve() is called if lazy); none at all if failing. */
function fakeDem(height, opts = {}) {
  const d = { loaded: !opts.lazy, asked: [], waiting: [] };
  d.ensureTile = (z, x, y) => {
    d.asked.push(z + '/' + x + '/' + y);
    return d.loaded ? Promise.resolve() : new Promise((r) => d.waiting.push(r));
  };
  d.resolve = () => { d.loaded = true; d.waiting.splice(0).forEach((r) => r()); };
  const data = new Float32Array(65536).fill(height);   // one array per tile, as DemTiles keeps them
  d.tileData = () => (d.loaded && !opts.fail ? data : null);
  d.elevationAtWorld = () => (d.loaded && !opts.fail ? height : NaN);
  return d;
}

/** An API grid over bounds: 10 °C half an hour ago, 12 °C in half an hour, ground at 1000 m. */
function apiEntry(bounds) {
  const spec = WindField.gridSpec(bounds);
  const points = [];
  for (let i = 0; i < spec.lats.length * spec.lons.length; i++) {
    points.push({ elevation: 1000, hourly: { time: [NOW / 1000 - 1800, NOW / 1000 + 1800],
      wind_speed_10m: [1, 1], wind_direction_10m: [270, 270], temperature_2m: [10, 12] } });
  }
  return { spec, fetchedAt: NOW, grid: WindField.buildGrid(spec, points) };
}

const stubSource = (entry) => ({ calls: 0, best: () => entry, ensure() { this.calls++; return Promise.resolve(entry); }, now: () => NOW });

const OPTS = { stops: T.DEFAULT_STOPS, step: 5, unit: 'C', opacity: 45, fetchDelayMs: 0, now: () => NOW };

/** The colors of an image, as "r,g,b,a" strings. */
function colors(img) {
  const set = new Set();
  for (let i = 0; i < img.data.length; i += 4) set.add(Array.from(img.data.slice(i, i + 4)).join(','));
  return [...set];
}
function colorOf(tC, step = 5, unit = 'C') {
  const lut = T.buildLut(T.DEFAULT_STOPS, step, unit), i = T.lutIndex(tC) * 3;
  return [lut[i], lut[i + 1], lut[i + 2], 255].join(',');
}

/** Tile z/x/y holding lat/lon. */
function tileOf(lat, lon, z) {
  const p = WindField.worldPx(lat, lon, z);
  return [z, Math.floor(p.x / 256), Math.floor(p.y / 256)];
}

/** The pixels of a tile, once every slice of it is drawn. */
async function drawTile(layer, z, x, y, signal) {
  const p = layer.tile(z, x, y, signal);
  await settle();
  return { data: await p };
}

const MONT_BLANC = tileOf(45.83, 6.87, 5);

test('wide view: tiles drawn from the file, corrected with the model height', async () => {
  const adapter = fakeAdapter(EUROPE);
  const layer = new T.TempLayer(adapter, stubSource(null), fakeOpen(), fakeDem(4792), OPTS);
  layer.addTo(fakeMap(4));
  await settle();
  // Uncorrected tiles first if the file comes before the model's heights, then corrected ones.
  assert.ok(adapter.tiles.length >= 1);
  assert.equal(adapter.tiles[adapter.tiles.length - 1].opacity, 0.45);
  assert.deepEqual(colors(await drawTile(layer, ...MONT_BLANC)), [colorOf(T.correct(6.3, 2076, 4792))]);
  assert.equal(layer.isDrawing(), true);
});

test('zoomed in: drawn from the API grid, no second request when the wind already has it', async () => {
  const bounds = { west: 6.80, south: 45.80, east: 6.95, north: 45.87 };
  const log = [];
  const fetch = (url) => {
    log.push(url);
    const count = url.split('latitude=')[1].split('&')[0].split(',').length;
    const pts = [];
    for (let i = 0; i < count; i++) {
      pts.push({ elevation: 1000, hourly: { time: [NOW / 1000 - 1800, NOW / 1000 + 1800],
        wind_speed_10m: [1, 1], wind_direction_10m: [270, 270], temperature_2m: [10, 12] } });
    }
    return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(pts) });
  };
  const source = new WindSource({ fetch, storage: null, now: () => NOW });
  const map = fakeMap(10);
  await source.ensure({ bounds, zoom: map.zoom + 1 });          // the wind layer's request
  const before = log.length;
  const adapter = fakeAdapter(bounds);
  const layer = new T.TempLayer(adapter, source, fakeOpen(), fakeDem(1000), OPTS);
  layer.addTo(map);
  await settle();
  assert.equal(log.length, before, 'no request of its own');
  assert.deepEqual(colors(await drawTile(layer, ...tileOf(45.83, 6.87, 15))), [colorOf(11)]);
});

test('no open data: the API grid draws every zoom', async () => {
  const adapter = fakeAdapter(EUROPE);
  const layer = new T.TempLayer(adapter, stubSource(apiEntry(EUROPE)), fakeOpen({ fail: true }), fakeDem(1000), OPTS);
  layer.addTo(fakeMap(4));
  await settle();
  assert.deepEqual(colors(await drawTile(layer, ...MONT_BLANC)), [colorOf(11)]);
});

test('past the edge of the API grid, the file fills the tile', async () => {
  const bounds = { west: 6.80, south: 45.80, east: 6.95, north: 45.87 };
  const adapter = fakeAdapter(bounds);
  const layer = new T.TempLayer(adapter, stubSource(apiEntry(bounds)), fakeOpen(), fakeDem(1000), Object.assign({}, OPTS, { step: 2 }));
  layer.addTo(fakeMap(10));
  await settle();
  // 11 °C from the grid, 13.3 °C from the file: two bands of 2 °C.
  assert.deepEqual(colors(await drawTile(layer, ...tileOf(45.83, 6.87, 9))).sort(),
    [colorOf(11, 2), colorOf(T.correct(6.3, 2076, 1000), 2)].sort());
});

test('a tile waits for its elevation tile, then draws corrected', async () => {
  const adapter = fakeAdapter(EUROPE);
  const dem = fakeDem(4792, { lazy: true });
  const layer = new T.TempLayer(adapter, stubSource(null), fakeOpen(), dem, OPTS);
  layer.addTo(fakeMap(4));
  await settle();
  let done = false;
  const p = layer.tile(...MONT_BLANC).then((d) => { done = true; return d; });
  await settle();
  assert.equal(done, false);
  assert.deepEqual(dem.asked, [MONT_BLANC.join('/')]);
  dem.resolve();
  await settle();
  assert.deepEqual(colors({ data: await p }), [colorOf(T.correct(6.3, 2076, 4792))]);
});

test('no elevation tile (failed): the tile draws uncorrected', async () => {
  const adapter = fakeAdapter(EUROPE);
  const layer = new T.TempLayer(adapter, stubSource(null), fakeOpen(), fakeDem(4792, { fail: true }), OPTS);
  layer.addTo(fakeMap(4));
  await settle();
  assert.deepEqual(colors(await drawTile(layer, ...MONT_BLANC)), [colorOf(6.3)]);
});

test('past zoom 12, a tile reads the elevation tile it lies in', async () => {
  const dem = fakeDem(0);
  const layer = new T.TempLayer(fakeAdapter(EUROPE), stubSource(null), fakeOpen(), dem, OPTS);
  layer.addTo(fakeMap(4));
  await settle();
  const [z, x, y] = tileOf(45.83, 6.87, 14);
  await drawTile(layer, z, x, y);
  assert.deepEqual(dem.asked, ['12/' + (x >> 2) + '/' + (y >> 2)]);
});

test('a tile is drawn a few rows per frame, and given up once its request is aborted', async () => {
  const layer = new T.TempLayer(fakeAdapter(EUROPE), stubSource(null), fakeOpen(), fakeDem(0), OPTS);
  layer.addTo(fakeMap(4));
  await settle();
  const ctl = new AbortController();
  let done = false;
  const p = layer.tile(...MONT_BLANC, ctl.signal).then((d) => { done = true; return d; });
  for (let i = 0; i < 5; i++) await tick();
  assert.ok(rafQueue.length > 0, 'the drawing waits for a frame');
  rafQueue.shift()();
  await tick();
  assert.equal(done, false, 'one frame draws part of the tile');
  ctl.abort();
  await settle();
  assert.equal(done, true);
  assert.deepEqual(colors({ data: await p }), ['0,0,0,0']);
});

test('tiles on both sides of the antimeridian are filled', async () => {
  const layer = new T.TempLayer(fakeAdapter({ west: 170, south: -30, east: 190, north: -10 }), stubSource(null), fakeOpen(), fakeDem(0), OPTS);
  layer.addTo(fakeMap(5));
  await settle();
  const want = [colorOf(T.correct(6.3, 2076, 0))];
  assert.deepEqual(colors(await drawTile(layer, 3, 0, 4)), want);
  assert.deepEqual(colors(await drawTile(layer, 3, 7, 4)), want);
});

test('a move over the same data keeps the tiles', async () => {
  const adapter = fakeAdapter(EUROPE);
  const map = fakeMap(4);
  new T.TempLayer(adapter, stubSource(null), fakeOpen(), fakeDem(0), OPTS).addTo(map);
  await settle();
  const count = adapter.tiles.length;
  adapter.bounds = { west: 0, south: 40, east: 40, north: 65 };
  map.zoom = 5;
  map.fire('moveend');
  await settle();
  assert.equal(adapter.tiles.length, count);
});

test('setOpacity changes the layer only, the tiles stay', async () => {
  const adapter = fakeAdapter(EUROPE);
  const layer = new T.TempLayer(adapter, stubSource(null), fakeOpen(), fakeDem(0), OPTS);
  layer.addTo(fakeMap(4));
  await settle();
  const count = adapter.tiles.length;
  layer.setOpacity(80);
  await settle();
  assert.deepEqual(adapter.opacities, [0.8]);
  assert.equal(adapter.tiles.length, count);
});

test('setPalette, setStep and setUnit make new tiles and remake the legend', async () => {
  const adapter = fakeAdapter(EUROPE);
  const layer = new T.TempLayer(adapter, stubSource(null), fakeOpen(), fakeDem(2076), OPTS);
  layer.addTo(fakeMap(4));
  await settle();
  const legend = container.children[container.children.length - 1];
  assert.equal(legend.id, 'lv-temp-legend');
  assert.ok(legend.innerHTML.includes('°C'));
  const v = adapter.tiles[adapter.tiles.length - 1].version;
  layer.setUnit('F');
  await settle();
  assert.ok(legend.innerHTML.includes('°F'));
  assert.ok(legend.innerHTML.includes('>100<'), 'Fahrenheit ticks');
  layer.setStep(0);
  await settle();
  layer.setPalette([{ t: 0, color: '#000000' }, { t: 10, color: '#ffffff' }]);
  await settle();
  assert.deepEqual(adapter.tiles.slice(-3).map((t) => t.version), [v + 1, v + 2, v + 3]);
  // Still in Fahrenheit: 0 to 10 °C is 32 to 50 °F, one tick at 40.
  assert.ok(legend.innerHTML.includes('>40<') && !legend.innerHTML.includes('>100<'), 'ticks follow the palette');
  // 6.3 °C (ground at the model's height) on a black to white ramp, smooth: a gray.
  assert.deepEqual(colors(await drawTile(layer, ...MONT_BLANC)), ['161,161,161,255']);
});

test('remove clears the layer and the legend; tiles asked later stay empty', async () => {
  const adapter = fakeAdapter(EUROPE);
  const map = fakeMap(4);
  const layer = new T.TempLayer(adapter, stubSource(null), fakeOpen(), fakeDem(0), OPTS);
  layer.addTo(map);
  await settle();
  const legend = container.children[container.children.length - 1];
  const count = adapter.tiles.length;
  layer.remove();
  map.fire('moveend');
  await settle();
  assert.equal(adapter.cleared, 1);
  assert.equal(legend.removed, true);
  assert.equal(adapter.tiles.length, count);
  assert.deepEqual(colors(await drawTile(layer, ...MONT_BLANC)), ['0,0,0,0']);
});

test('the API held back: tries again once it allows, then new tiles from the view grid', async () => {
  const bounds = { west: 6.80, south: 45.80, east: 6.95, north: 45.87 };
  const fine = apiEntry(bounds);
  let calls = 0;
  const source = {
    blockedUntil: NOW - 1000, ttlMs: 3600e3,
    best: () => null,
    ensure() { calls++; return Promise.resolve(calls === 1 ? null : fine); },   // held back first, then the grid
    now: () => NOW,
  };
  const adapter = fakeAdapter(bounds);
  const layer = new T.TempLayer(adapter, source, fakeOpen({ fail: true }), fakeDem(1000), Object.assign({}, OPTS, { retryMinMs: 0 }));
  layer.addTo(fakeMap(10));
  for (let i = 0; i < 5; i++) { await new Promise((r) => setTimeout(r, 5)); await settle(); }
  assert.equal(calls, 2);
  assert.equal(adapter.tiles.length, 1);
  assert.deepEqual(colors(await drawTile(layer, ...tileOf(45.83, 6.87, 15))), [colorOf(11)]);
});

test('manual mode, wide view: the file grid given, nothing loaded; settled once its tiles are drawn', async () => {
  const adapter = fakeAdapter(EUROPE);
  const open = fakeOpen();
  let loads = 0;
  open.loadTemp = async () => { loads++; return null; };
  open.keptTemp = async () => { loads++; return null; };
  const layer = new T.TempLayer(adapter, stubSource(apiEntry(EUROPE)), open, fakeDem(2076), Object.assign({ manual: true }, OPTS));
  layer.addTo(fakeMap(4));
  await settle();
  assert.equal(loads, 0);
  assert.equal(adapter.tiles.length, 0);
  assert.equal(layer.settled(), false);
  layer.showFile(WidgetOpenData.toScalarGrid(new Float32Array(12).fill(-3), 3, 4, NOW));
  const last = adapter.tiles[adapter.tiles.length - 1];
  assert.equal(layer.settled(), false);           // the map has not asked for the tiles yet
  const p = last.provider(...MONT_BLANC);
  assert.equal(layer.settled(), false);
  await settle();
  assert.deepEqual(colors({ data: await p }), [colorOf(-3)]);
  assert.equal(layer.settled(), true);
  layer.remove();
});

test('manual mode: a picture between two times is mixed, the relief offsets of a tile computed once', async () => {
  const adapter = fakeAdapter(EUROPE);
  const open = fakeOpen();                               // model ground at 2076 m
  const layer = new T.TempLayer(adapter, stubSource(null), open, fakeDem(4792), Object.assign({ manual: true }, OPTS));
  layer.addTo(fakeMap(4));
  await settle();
  const g = (v) => WidgetOpenData.toScalarGrid(new Float32Array(12).fill(v), 3, 4, NOW);
  const a = g(0), b = g(10);
  const draw = async () => adapter.tiles[adapter.tiles.length - 1].provider(...MONT_BLANC);
  layer.showFile(a);
  const p1 = draw();
  await settle();
  assert.deepEqual(colors({ data: await p1 }), [colorOf(T.correct(0, 2076, 4792))]);
  const offsets = [...layer._relief.values()][0].offsets;
  layer.showFile(Object.assign({}, a, { valuesB: b.values, mix: 0.5 }));
  const p2 = draw();
  await settle();
  assert.deepEqual(colors({ data: await p2 }), [colorOf(T.correct(5, 2076, 4792))]);
  assert.equal(layer._relief.size, 1);
  assert.equal([...layer._relief.values()][0].offsets, offsets);
  layer.remove();
});

test('manual mode: smaller tiles while the animation plays, full ones again once it stops', async () => {
  const adapter = fakeAdapter(EUROPE);
  const layer = new T.TempLayer(adapter, stubSource(null), fakeOpen(), fakeDem(2076), Object.assign({ manual: true, movingStep: 2 }, OPTS));
  layer.addTo(fakeMap(4));
  await settle();
  const g = (v) => WidgetOpenData.toScalarGrid(new Float32Array(12).fill(v), 3, 4, NOW);
  const draw = async () => { const p = adapter.tiles[adapter.tiles.length - 1].provider(...MONT_BLANC); await settle(); return p; };
  layer.setMoving(true);
  layer.showFile(g(4));
  const small = await draw();
  assert.equal(small.length, 128 * 128 * 4);
  assert.deepEqual(colors({ data: small }), [colorOf(4)]);
  const before = adapter.tiles.length;
  layer.setMoving(false);
  assert.equal(adapter.tiles.length, before + 1);      // the same picture, drawn again
  const full = await draw();
  assert.equal(full.length, 256 * 256 * 4);
  assert.deepEqual(colors({ data: full }), [colorOf(4)]);
  layer.remove();
});

test('manual mode, zoomed in: the API grid as the radar has it, at the time of the picture given', async () => {
  const bounds = { west: 6.80, south: 45.80, east: 6.95, north: 45.87 };
  const adapter = fakeAdapter(bounds), source = stubSource(apiEntry(bounds));
  const layer = new T.TempLayer(adapter, source, fakeOpen(), fakeDem(1000), Object.assign({ manual: true }, OPTS));
  layer.addTo(fakeMap(10));
  await settle();
  const file = (t) => WidgetOpenData.toScalarGrid(new Float32Array(12).fill(-3), 3, 4, t);
  layer.showFile(file(NOW + 1800e3));
  await settle();
  assert.deepEqual(colors(await drawTile(layer, ...tileOf(45.83, 6.87, 15))), [colorOf(12)]);
  layer.showFile(file(NOW - 1800e3));             // the next picture: same grid, another hour
  await settle();
  assert.deepEqual(colors(await drawTile(layer, ...tileOf(45.83, 6.87, 15))), [colorOf(10)]);
  layer.remove();
});

test('valueAt: the temperature drawn under a point, corrected to its height', async () => {
  const adapter = fakeAdapter(EUROPE);
  const layer = new T.TempLayer(adapter, stubSource(null), fakeOpen(), fakeDem(4792), OPTS);
  const map = fakeMap(4);
  layer.addTo(map);
  assert.equal(layer.valueAt(45.83, 6.87), null);   // nothing shown yet
  await settle();
  assert.ok(Math.abs(layer.valueAt(45.83, 6.87) - T.correct(6.3, 2076, 4792)) < 1e-6);
  layer.remove();
});

test('colorOf: the color of the band a temperature is drawn in', async () => {
  const layer = new T.TempLayer(fakeAdapter(EUROPE), stubSource(null), fakeOpen(), fakeDem(2076), OPTS);
  layer.addTo(fakeMap(4));
  const rgb = colorOf(6.3).split(',').slice(0, 3).join(', ');
  assert.equal(layer.colorOf(6.3), 'rgb(' + rgb + ')');
  layer.remove();
});
