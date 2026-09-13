'use strict';
// Unit tests for the Open-Meteo grid source, its cache/backoff and the
// elevation tiles of the radar wind layer (glue-wind.js), with fake I/O.
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const { WindField, WindSource, DemTiles } = require('../glue-wind.js');

const view = { bounds: { west: 6.5, south: 48.0, east: 6.7, north: 48.1 }, zoom: 10 };

function fakePoints(spec) {
  const out = [];
  for (let i = 0; i < spec.n * spec.n; i++) {
    out.push({ elevation: 400 + i, hourly: { time: [1000, 4600], wind_speed_10m: [2, 3], wind_direction_10m: [270, 270] } });
  }
  return out;
}

function fakeFetch(log, fail) {
  return (url) => {
    log.push(url);
    if (fail) return Promise.resolve({ ok: false, status: 429 });
    const spec = WindField.gridSpec(view.bounds);
    return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(fakePoints(spec)) });
  };
}

function fakeStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v), map: m };
}

test('url: all n*n coordinates, m/s, unix time, 2 past + 4 forecast hours', () => {
  const src = new WindSource({ fetch: () => {}, storage: null });
  const spec = WindField.gridSpec(view.bounds);
  const url = src.url(spec);
  assert.ok(url.startsWith('https://api.open-meteo.com/v1/forecast?latitude='));
  assert.equal(url.split('&longitude=')[1].split('&')[0].split(',').length, spec.n * spec.n);
  for (const p of ['hourly=wind_speed_10m,wind_direction_10m,wind_speed_700hPa,wind_direction_700hPa', 'wind_speed_unit=ms', 'timeformat=unixtime', 'past_hours=2', 'forecast_hours=4']) {
    assert.ok(url.includes(p), p);
  }
});

test('ensure: fetches once, builds the grid, persists, then serves from memory', async () => {
  const log = [];
  const storage = fakeStorage();
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch(log), storage, now: () => t });
  const e1 = await src.ensure(view);
  assert.equal(log.length, 1);
  assert.equal(e1.grid.n, e1.spec.n);
  assert.equal(e1.zoom, 10);
  assert.ok(storage.map.has(WindSource.STORAGE_KEY));
  t += 60 * 1000;
  const e2 = await src.ensure(view);
  assert.equal(log.length, 1, 'no second fetch while the view stays inside the box');
  assert.equal(e2, e1);
});

test('restore: a fresh page reuses the stored grid without fetching', async () => {
  const log = [];
  const storage = fakeStorage();
  const a = new WindSource({ fetch: fakeFetch(log), storage, now: () => 1000 });
  await a.ensure(view);
  const b = new WindSource({ fetch: fakeFetch(log), storage, now: () => 2000 });
  const e = await b.ensure(view);
  assert.equal(log.length, 1);
  assert.equal(e.grid.n, e.spec.n);
});

test('ensure: expired cache triggers a new fetch', async () => {
  const log = [];
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch(log), storage: null, now: () => t, ttlMs: 3600000 });
  await src.ensure(view);
  t += 3600001;
  await src.ensure(view);
  assert.equal(log.length, 2);
});

test('ensure: a failed fetch backs off and keeps the previous grid', async () => {
  const log = [];
  let t = 1000;
  let fail = false;
  const fetch = (url) => fakeFetch(log, fail)(url);
  const src = new WindSource({ fetch, storage: null, now: () => t, ttlMs: 1000, backoffMs: 600000, minIntervalMs: 0 });
  const first = await src.ensure(view);
  fail = true;
  t += 2000;                              // expired -> tries again, fails
  const second = await src.ensure(view);
  assert.equal(second, first, 'stale grid kept after a failure');
  assert.equal(log.length, 2);
  t += 1000;                              // still inside the backoff
  await src.ensure(view);
  assert.equal(log.length, 2, 'no fetch during the backoff');
  t += 600000;                            // backoff over
  await src.ensure(view);
  assert.equal(log.length, 3);
});

test('ensure: the retry delay doubles on repeated failures and resets on success', async () => {
  const log = [];
  let t = 0;
  let fail = true;
  const fetch = (url) => fakeFetch(log, fail)(url);
  const src = new WindSource({ fetch, storage: null, now: () => t, ttlMs: 1, backoffMs: 1000, maxBackoffMs: 3000, minIntervalMs: 0 });
  await src.ensure(view);                 // fails: retry in 1 s
  t += 1000; await src.ensure(view);      // fails: retry in 2 s
  t += 1000; await src.ensure(view);      // still blocked
  assert.equal(log.length, 2);
  t += 1000; await src.ensure(view);      // fails: retry capped at 3 s
  assert.equal(log.length, 3);
  assert.equal(src.blockedUntil, t + 3000);
  fail = false;
  t += 3000; await src.ensure(view);      // succeeds: counter reset
  assert.equal(log.length, 4);
  assert.equal(src.failures, 0);
});

test('ensure: at most one fetch per minIntervalMs, the stale grid is kept meanwhile', async () => {
  const log = [];
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch(log), storage: null, now: () => t, minIntervalMs: 15000 });
  const first = await src.ensure(view);
  const far = { bounds: { west: 2.0, south: 44.0, east: 2.5, north: 44.3 }, zoom: 10 };
  t += 5000;
  const during = await src.ensure(far);   // outside the box, but too soon
  assert.equal(during, first);
  assert.equal(log.length, 1);
  assert.equal(src.blockedUntil, 1000 + 15000);
  t += 10000;
  await src.ensure(far);                  // interval over: fetch
  assert.equal(log.length, 2);
});

test('DemTiles: tile keys covering a spec, elevation lookup, NaN when missing', async () => {
  const loaded = [];
  const loadTile = (url) => {
    loaded.push(url);
    const t = new Float32Array(65536);
    t.fill(404);
    return Promise.resolve(t);
  };
  const dem = new DemTiles({ loadTile });
  const spec = { west: 6.58, south: 48.01, east: 6.60, north: 48.03 };   // inside z10 tile 530/355
  assert.deepEqual(dem.tileKeysFor(spec, 10), ['10/530/355']);
  assert.ok(Number.isNaN(dem.elevationAtWorld(530 * 256 + 189, 355 * 256 + 225, 10)));
  await dem.ensure(spec, 10);
  assert.equal(loaded.length, 1);
  assert.ok(loaded[0].endsWith('/10/530/355.png'));
  assert.equal(dem.elevationAtWorld(530 * 256 + 189, 355 * 256 + 225, 10), 404);
  await dem.ensure(spec, 10);
  assert.equal(loaded.length, 1, 'tiles are loaded once');
});
