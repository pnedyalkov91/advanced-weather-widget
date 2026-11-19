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
  for (let i = 0; i < spec.lats.length * spec.lons.length; i++) {
    out.push({ elevation: 400 + i, hourly: { time: [1000, 4600], wind_speed_10m: [2, 3], wind_direction_10m: [270, 270] } });
  }
  return out;
}

function fakeFetch(log, fail) {
  return (url) => {
    log.push(url);
    if (fail) return Promise.resolve({ ok: false, status: 429 });
    const count = url.split('latitude=')[1].split('&')[0].split(',').length;
    const points = fakePoints({ lats: new Array(count), lons: [0] });
    return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(points) });
  };
}

function fakeStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v), removeItem: (k) => m.delete(k), map: m };
}

// The world grid is fetched beside the view grids; most tests count the latter.
const WORLD_URL = new WindSource({ fetch: () => {}, storage: null }).url(WindField.gridSpec(WindField.WORLD));
const views = (log) => log.filter((u) => u !== WORLD_URL);
const worlds = (log) => log.filter((u) => u === WORLD_URL);

test('url: all rows*cols coordinates, m/s, unix time, 2 past + 4 forecast hours', () => {
  const src = new WindSource({ fetch: () => {}, storage: null });
  const spec = WindField.gridSpec(view.bounds);
  const url = src.url(spec);
  assert.ok(url.startsWith('https://api.open-meteo.com/v1/forecast?latitude='));
  assert.equal(url.split('&longitude=')[1].split('&')[0].split(',').length, spec.lats.length * spec.lons.length);
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
  assert.equal(views(log).length, 1);
  assert.equal(e1.grid.lons.length, e1.spec.lons.length);
  assert.equal(e1.zoom, 10);
  assert.ok(storage.map.has(WindSource.STORAGE_KEY));
  t += 60 * 1000;
  const e2 = await src.ensure(view);
  assert.equal(views(log).length, 1, 'no second fetch while the view stays inside the box');
  assert.equal(e2, e1);
});

test('restore: a fresh page reuses the stored grid without fetching', async () => {
  const log = [];
  const storage = fakeStorage();
  const a = new WindSource({ fetch: fakeFetch(log), storage, now: () => 1000 });
  await a.ensure(view);
  const b = new WindSource({ fetch: fakeFetch(log), storage, now: () => 2000 });
  const e = await b.ensure(view);
  assert.equal(views(log).length, 1);
  assert.equal(e.grid.lons.length, e.spec.lons.length);
});

test('ensure: expired cache triggers a new fetch', async () => {
  const log = [];
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch(log), storage: null, now: () => t, ttlMs: 3600000 });
  await src.ensure(view);
  t += 3600001;
  await src.ensure(view);
  assert.equal(views(log).length, 2);
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
  assert.equal(views(log).length, 2);
  t += 1000;                              // still inside the backoff
  await src.ensure(view);
  assert.equal(views(log).length, 2, 'no fetch during the backoff');
  t += 600000;                            // backoff over
  await src.ensure(view);
  assert.equal(views(log).length, 3);
});

test('ensure: a fetch that never answers times out, backs off, then the next try goes through', { timeout: 2000 }, async () => {
  const log = [];
  let t = 1000;
  let hang = true;
  const answer = fakeFetch(log);
  const src = new WindSource({
    fetch: (url) => (hang ? (log.push(url), new Promise(() => {})) : answer(url)),
    storage: null, now: () => t, timeoutMs: 20,
  });
  assert.equal(await src.ensure(view), null, 'gives up instead of waiting forever');
  assert.equal(src.inflight, null);
  assert.ok(src.blockedUntil > t, 'backs off like any failure');
  hang = false;
  t = src.blockedUntil + 1;
  const e = await src.ensure(view);
  assert.equal(views(log).length, 2);
  assert.ok(e && e.grid);
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
  assert.equal(views(log).length, 2);
  t += 1000; await src.ensure(view);      // fails: retry capped at 3 s
  assert.equal(views(log).length, 3);
  assert.equal(src.blockedUntil, t + 3000);
  fail = false;
  t += 3000; await src.ensure(view);      // succeeds: counter reset
  assert.equal(views(log).length, 4);
  assert.equal(src.failures, 0);
});

test('ensure: at most one fetch per minIntervalMs, the best grid at hand meanwhile', async () => {
  const log = [];
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch(log), storage: null, now: () => t, minIntervalMs: 15000 });
  const first = await src.ensure(view);
  const far = { bounds: { west: 2.0, south: 44.0, east: 2.5, north: 44.3 }, zoom: 10 };
  t += 5000;
  await src.ensureWorld();
  const during = await src.ensure(far);   // outside the box, but too soon
  assert.notEqual(during, first);
  assert.equal(during, src.world, 'the world grid covers the view meanwhile');
  assert.equal(views(log).length, 1);
  assert.equal(src.blockedUntil, 1000 + 15000);
  t += 10000;
  await src.ensure(far);                  // interval over: fetch
  assert.equal(views(log).length, 2);
});

const region = { bounds: { west: 2, south: 44, east: 11, north: 50 }, zoom: 6 };   // around the city view
const japan = { bounds: { west: 135, south: 33, east: 140, north: 37 }, zoom: 7 };

test('ensure: the world grid is fetched beside the first view grid, then once an hour', async () => {
  const log = [];
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch(log), storage: null, now: () => t, minIntervalMs: 0 });
  await src.ensure(view);
  await src.ensureWorld();
  assert.equal(worlds(log).length, 1);
  assert.equal(src.world.spec.north, 90);
  assert.equal(src.world.spec.south, -90);
  assert.equal(src.world.spec.east - src.world.spec.west, 360);
  assert.ok(src.world.spec.lats.length * src.world.spec.lons.length <= 144);
  t += 30 * 60 * 1000;
  await src.ensure(view); await src.ensureWorld();
  assert.equal(worlds(log).length, 1, 'still fresh');
  t += 31 * 60 * 1000;
  await src.ensure(view); await src.ensureWorld();
  assert.equal(worlds(log).length, 2);
});

test('ensure: a view of the whole world is served by the world grid, with one request', async () => {
  const log = [];
  const src = new WindSource({ fetch: fakeFetch(log), storage: null, now: () => 1000 });
  const world = { bounds: { west: -150, east: 75, south: -58, north: 80 }, zoom: 2.5 };
  const e = await src.ensure(world);
  await src.ensureWorld();
  assert.equal(log.length, 1);
  assert.equal(e, src.world);
  const pan = { bounds: { west: -28, east: 197, south: -58, north: 80 }, zoom: 2.5 };
  assert.equal(await src.ensure(pan), src.world);
  assert.equal(log.length, 1);
});

test('ensure: zooming back to a level already seen asks nothing', async () => {
  const log = [];
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch(log), storage: null, now: () => t, minIntervalMs: 0 });
  const city = await src.ensure(view);
  t += 1000; await src.ensure(region);
  t += 1000; const back = await src.ensure(view);
  assert.equal(views(log).length, 2);
  assert.equal(back, city);
});

test('ensure: at most maxEntries grids kept, the least recently used dropped', async () => {
  const log = [];
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch(log), storage: null, now: () => t, minIntervalMs: 0, maxEntries: 2 });
  await src.ensure(view);
  t += 1000; await src.ensure(region);
  t += 1000; await src.ensure(view);      // used again: now the most recent
  t += 1000; await src.ensure(japan);     // drops region
  assert.equal(views(log).length, 3);
  t += 1000; await src.ensure(view);
  assert.equal(views(log).length, 3, 'view was kept');
  t += 1000; await src.ensure(region);
  assert.equal(views(log).length, 4, 'region was dropped');
});

test('best: the finest grid covering the whole view, the world grid when no other does', async () => {
  let t = 1000;
  const src = new WindSource({ fetch: fakeFetch([]), storage: null, now: () => t, minIntervalMs: 0 });
  assert.equal(src.best(view), null, 'nothing yet');
  const city = await src.ensure(view);
  t += 1000; const reg = await src.ensure(region);
  await src.ensureWorld();
  assert.equal(src.best(view), city);
  assert.equal(src.best(region), reg);
  assert.equal(src.best(japan), src.world);
  const zoomedOut = { bounds: { west: -10, south: 35, east: 25, north: 58 }, zoom: 4.5 };
  assert.equal(src.best(zoomedOut), src.world, 'a partial grid would leave a blank strip');
});

test('restore: every grid comes back from storage, old ones and the old key dropped', async () => {
  const storage = fakeStorage();
  storage.setItem('awwWind:last', '{"spec":{}}');
  let t = 1000;
  const a = new WindSource({ fetch: fakeFetch([]), storage, now: () => t, minIntervalMs: 0 });
  await a.ensure(view);
  t += 1000; await a.ensure(region);
  await a.ensureWorld();
  const log = [];
  const b = new WindSource({ fetch: fakeFetch(log), storage, now: () => t + 1000 });
  assert.equal(b.best(view).spec.lonStep, a.best(view).spec.lonStep);
  assert.equal(b.best(region).spec.lonStep, a.best(region).spec.lonStep);
  assert.ok(b.best(japan).world);
  await b.ensure(view); await b.ensure(region);
  assert.equal(log.length, 0, 'served from storage');
  assert.equal(storage.getItem('awwWind:last'), null, 'the old single-grid key is removed');
  const c = new WindSource({ fetch: fakeFetch([]), storage, now: () => t + 4 * 3600 * 1000 });
  assert.equal(c.best(view), null, 'grids older than keepMs are not drawn');
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

test('DemTiles: a grid reaching the poles is clamped to Mercator, and skipped when too large', async () => {
  const loaded = [];
  const dem = new DemTiles({ loadTile: (url) => { loaded.push(url); return Promise.resolve(new Float32Array(65536)); } });
  const keys = dem.tileKeysFor({ west: 0, south: 80, east: 1, north: 90 }, 3);
  assert.ok(keys.length > 0 && keys.length < 10, keys.join(' '));
  await dem.ensure(WindField.gridSpec(WindField.WORLD), 9);
  assert.equal(loaded.length, 0);
});

test('url: one request for the wind and the temperature', () => {
  const url = new WindSource({ fetch: () => {}, storage: null }).url(WindField.gridSpec(view.bounds));
  const hourly = url.split('hourly=')[1].split('&')[0].split(',');
  assert.equal(hourly.filter((v) => v === 'temperature_2m').length, 1);
  for (const v of ['wind_speed_10m', 'wind_direction_10m', 'wind_speed_700hPa', 'wind_direction_700hPa']) assert.ok(hourly.includes(v), v);
});

test('restore: drops the grids kept before the temperature', async () => {
  const storage = fakeStorage();
  const a = new WindSource({ fetch: fakeFetch([]), storage, now: () => 1000, minIntervalMs: 0 });
  await a.ensure(view);
  const kept = storage.getItem(WindSource.STORAGE_KEY);
  storage.map.clear();
  storage.setItem('awwWind:grids', kept);   // where the grids were kept before the temperature
  const b = new WindSource({ fetch: fakeFetch([]), storage, now: () => 2000 });
  assert.equal(b.best(view), null);
  assert.equal(storage.getItem('awwWind:grids'), null);
});

test('DemTiles maxKept: the oldest tiles go first', async () => {
  const dem = new DemTiles({ maxKept: 2, loadTile: () => Promise.resolve(new Float32Array(65536)) });
  const tile = (x) => ({ west: -180 + (x + 0.2) * 360 / 1024, east: -180 + (x + 0.8) * 360 / 1024, south: 48.01, north: 48.03 });
  await dem.ensure(tile(530), 10);
  await dem.ensure(tile(531), 10);
  await dem.ensure(tile(532), 10);
  assert.deepEqual(Object.keys(dem.tiles).sort(), ['10/531/355', '10/532/355']);
});

test('DemTiles ensureTile: one tile by its own key, loaded once, then read whole', async () => {
  const loaded = [];
  const dem = new DemTiles({ loadTile: (url) => { loaded.push(url); return Promise.resolve(new Float32Array(65536).fill(7)); } });
  assert.equal(dem.tileData(2, 3, 1), null);
  await dem.ensureTile(2, 3, 1);
  await dem.ensureTile(2, 3, 1);
  assert.deepEqual(loaded.map((u) => u.split('terrarium/')[1]), ['2/3/1.png']);
  assert.equal(dem.tileData(2, 3, 1)[123], 7);
});

test('DemTiles ensureTile: a tile that fails resolves all the same, and stays missing', async () => {
  const dem = new DemTiles({ loadTile: () => Promise.reject(new Error('404')) });
  const warn = console.warn;
  console.warn = () => {};
  try { await dem.ensureTile(2, 4, 1); } finally { console.warn = warn; }
  assert.equal(dem.tileData(2, 4, 1), null);
});

test('WindSource for the animation: the hours asked for, no world grid', async () => {
  const urls = [];
  const fetch = (u) => { urls.push(u); return Promise.resolve({ ok: true, json: () => Promise.resolve([]) }); };
  const src = new WindSource({ fetch, storage: null, pastH: 27, futureH: 51, world: false });
  assert.match(src.url(WindField.gridSpec({ west: 6, south: 45, east: 7, north: 46 })), /past_hours=27&forecast_hours=51/);
  assert.equal(await src.ensureWorld(), null);
  assert.equal(urls.length, 0);
  src.entries = [{ spec: {}, fetchedAt: 0 }];
  src.setHours(27, 51);
  assert.equal(src.entries.length, 1);              // same hours: the grids stay
  src.setHours(51, 51);
  assert.equal(src.entries.length, 0);              // other hours: they no longer cover the range
  assert.match(src.url(WindField.gridSpec({ west: 6, south: 45, east: 7, north: 46 })), /past_hours=51&/);
});

test('DemTiles: past maxKept, the tile asked for least recently goes first', async () => {
  const { DemTiles } = require('../glue-wind.js');
  const dem = new DemTiles({ maxKept: 2, loadTile: (url) => Promise.resolve(url) });
  await dem.ensureTile(9, 1, 1);
  await dem.ensureTile(9, 2, 2);
  await dem.ensureTile(9, 1, 1);           // asked again: now the most recent
  await dem.ensureTile(9, 3, 3);
  assert.ok(dem.tileData(9, 1, 1), '9/1/1 kept');
  assert.equal(dem.tileData(9, 2, 2), null);
  assert.ok(dem.tileData(9, 3, 3), '9/3/3 kept');
  assert.equal(dem.count, 2);
});
