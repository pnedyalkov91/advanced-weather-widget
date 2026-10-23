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
