'use strict';
// Unit tests for the table wind layer of the MapLibre map (glue-wind-table.js),
// on a fake map with a plain lon/lat projection and a fake canvas.
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');

global.WidgetWind = require('../glue-wind.js');
const WidgetOpenData = require('../glue-wind-open.js');
require('../glue-wind-table.js');

// Each performance.now() call is 1 ms later: the layer's 4 ms slices end
// after a few nodes, so building the table takes several animation frames.
let clock = 0;
Object.defineProperty(globalThis, 'performance', { value: { now: () => (clock += 1) }, configurable: true });
let rafQueue = [];
global.requestAnimationFrame = (f) => rafQueue.push(f);
function flushRaf() {
  for (let i = 0; i < 10000 && rafQueue.length; i++) rafQueue.shift()();
}
global.Path2D = class { moveTo() {} lineTo() {} };
const ctx = { clearRect() {}, fillRect() {}, stroke() {} };
global.window = { devicePixelRatio: 1 };
global.document = {
  hidden: false,
  createElement: () => ({ style: {}, getContext: () => ctx, remove() {} }),
  addEventListener() {},
  removeEventListener() {},
};

/** A 300 x 120 px map of the box 15 W..15 E, 6 S..6 N, 10 px per degree. */
function fakeMap() {
  const handlers = {};
  const m = {
    zoom: 2,
    on: (e, f) => { (handlers[e] = handlers[e] || []).push(f); },
    off: () => {},
    fire: (e) => (handlers[e] || []).slice().forEach((f) => f()),
    unproject: ([x, y]) => ({ lng: x / 10 - 15, lat: 6 - y / 10 }),
    project: (ll) => ({ x: (ll.lng + 15) * 10, y: (6 - ll.lat) * 10 }),
    getBounds: () => ({ getWest: () => -15, getEast: () => 15, getSouth: () => -6, getNorth: () => 6 }),
    getZoom: () => m.zoom,
    getCenter: () => ({ lng: 0, lat: 0 }),
    getBearing: () => 0,
    getPitch: () => 0,
    getContainer: () => ({ clientWidth: 300, clientHeight: 120 }),
    getCanvas: () => ({ parentNode: { insertBefore() {} }, nextSibling: null }),
  };
  return m;
}

/** Open data stand-in: a uniform 5 m/s westerly kept and ready. */
function fakeOpen() {
  const grid = WidgetOpenData.toGrid(new Float32Array(12).fill(5), new Float32Array(12), 3, 4, 0, '10m');
  return { res: 0.25, kept: async () => grid, load: async () => null };
}

const source = { best: () => null, ensure: () => new Promise(() => {}), now: () => 0, ttlMs: 1e9, blockedUntil: 0 };

test('table layer: a move while the table is being built does not leave the wind hidden', async () => {
  const Layer = WidgetWind.createTableWindLayer({});
  const map = fakeMap(), layer = new Layer(source, fakeOpen(), {}, {});
  layer.addTo(map);
  try {
    await new Promise((r) => setImmediate(r));   // the kept wind comes in
    layer.settle();                               // build starts, its next slice waits for a frame
    assert.ok(rafQueue.length > 0);
    map.fire('movestart');                        // a real move: stop...
    map.zoom = 2.1;
    map.fire('move');
    map.fire('moveend');                          // ...and start again
    flushRaf();
    assert.equal(layer.isDrawing(), true);
    assert.equal(layer._canvas.style.visibility, '');
  } finally {
    layer.remove();
  }
});

test('table layer: a resize that leaves the view as it was keeps the particles going', async () => {
  const Layer = WidgetWind.createTableWindLayer({});
  const map = fakeMap(), layer = new Layer(source, fakeOpen(), {}, {});
  layer.addTo(map);
  try {
    await new Promise((r) => setImmediate(r));
    layer.settle();
    flushRaf();
    assert.equal(layer.isDrawing(), true);
    const job = layer._job;
    map.fire('movestart'); map.fire('move'); map.fire('resize'); map.fire('moveend');
    assert.equal(layer.isDrawing(), true);
    assert.equal(layer._job, job);
  } finally {
    layer.remove();
  }
});

test('table layer, manual: only the grids it is given, at the time they say, nothing asked', () => {
  const Layer = WidgetWind.createTableWindLayer({});
  let asked = 0;
  const src = Object.assign({}, source, { best: () => { asked++; return null; }, ensure: () => { asked++; return new Promise(() => {}); } });
  const map = fakeMap(), layer = new Layer(src, null, {}, { manual: true });
  const seen = [], tw = WidgetWind.WindField.timeWeights;
  WidgetWind.WindField.timeWeights = (times, nowSec) => { seen.push(nowSec); return tw(times, nowSec); };
  layer.addTo(map);
  try {
    layer.settle();
    flushRaf();
    assert.equal(layer.isDrawing(), false);       // nothing to draw yet
    const grid = WidgetOpenData.toGrid(new Float32Array(12).fill(5), new Float32Array(12), 3, 4, 3600e3, '10m');
    grid.at = 1800;
    layer.showFile(grid);
    assert.equal(layer.settled(), false);         // the table is being built
    flushRaf();
    assert.equal(layer.isDrawing(), true);
    assert.equal(layer.settled(), true);
    assert.equal(asked, 0);
    assert.ok(seen.length > 0 && seen.every((s) => s === 1800));
    const next = Object.assign({}, grid, { at: 2000 });
    layer.showFile(next);                          // swapped under running particles
    assert.equal(layer.isDrawing(), true);
    assert.equal(layer._grid(), next);
  } finally {
    WidgetWind.WindField.timeWeights = tw;
    layer.remove();
  }
});

test('table layer, manual, zoomed in: the API grid as the radar has it, at the time of the picture given', () => {
  const Layer = WidgetWind.createTableWindLayer({});
  const tiny = { west: 0, south: 0, east: 0.4, north: 0.2 };   // finer than the file: the API
  const spec = WidgetWind.WindField.gridSpec(tiny), pts = [];
  for (let i = 0; i < spec.lats.length * spec.lons.length; i++) pts.push({ elevation: 500, hourly: { time: [0, 3600], wind_speed_10m: [1, 2], wind_direction_10m: [270, 270] } });
  const api = { spec, fetchedAt: 0, grid: WidgetWind.WindField.buildGrid(spec, pts) };
  const src = Object.assign({}, source, { best: () => api, ensure: () => Promise.resolve(api) });
  const map = fakeMap();
  map.getBounds = () => ({ getWest: () => tiny.west, getEast: () => tiny.east, getSouth: () => tiny.south, getNorth: () => tiny.north });
  const layer = new Layer(src, null, {}, { manual: true });
  const seen = [], tw = WidgetWind.WindField.timeWeights;
  WidgetWind.WindField.timeWeights = (times, nowSec) => { seen.push([times.length, nowSec]); return tw(times, nowSec); };
  layer.addTo(map);
  try {
    layer.settle();
    const file = WidgetOpenData.toGrid(new Float32Array(12).fill(5), new Float32Array(12), 3, 4, 3600e3, '10m');
    file.at = 1800;
    layer.showFile(file);
    flushRaf();
    assert.equal(layer._grid(), api.grid);
    assert.ok(seen.length > 0 && seen.every(([n, s]) => n === 2 && s === 1800));
    seen.length = 0;
    layer.showFile(Object.assign({}, file, { at: 900 }));   // next picture: the API grid stays, its hour moves
    layer._frame();
    assert.equal(layer._grid(), api.grid);
    assert.deepEqual(seen, [[2, 900]]);
  } finally {
    WidgetWind.WindField.timeWeights = tw;
    layer.remove();
  }
});

test('table layer: valueAt reads the wind drawn, where it is drawn', () => {
  const Layer = WidgetWind.createTableWindLayer({});
  const map = fakeMap(), layer = new Layer(source, null, {}, { manual: true });
  layer.addTo(map);
  try {
    assert.equal(layer.valueAt(0, 0), null);       // nothing drawn yet
    layer.settle();
    const grid = WidgetOpenData.toGrid(new Float32Array(12).fill(5), new Float32Array(12), 3, 4, 3600e3, '10m');
    grid.at = 3600;
    layer.showFile(grid);
    flushRaf();
    const w = layer.valueAt(10, 20);
    assert.ok(Math.abs(w.speed - 5) < 1e-6);
    assert.ok(Math.abs(w.dir - 270) < 1e-6);         // u = +5: from the west
  } finally {
    layer.remove();
  }
});

test('table layer: colorOf gives the color of the particles at that speed', () => {
  const Layer = WidgetWind.createTableWindLayer({});
  const WF = WidgetWind.WindField, layer = new Layer(source, null, {}, { theme: 'dark' });
  for (const ms of [0.5, 5, 12, 40]) assert.equal(layer.colorOf(ms), WF.bandColor(WF.DEFAULT_PALETTE, WF.paletteBand(ms, WF.DEFAULT_PALETTE), 'dark'));
});

test('table layer: setFade is the opacity of its canvas, kept across a new one', () => {
  const Layer = WidgetWind.createTableWindLayer({});
  const layer = new Layer(source, null, {}, { manual: true });
  layer.setFade(0.25);
  layer.addTo(fakeMap());
  assert.equal(layer._canvas.style.opacity, '0.25');
  layer.setFade(1);
  assert.equal(layer._canvas.style.opacity, '1');
  layer.remove();
});
