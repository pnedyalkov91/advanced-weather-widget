'use strict';
// Unit tests for the open-data wind reader (glue-wind-open.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const WidgetOpenData = require('../glue-wind-open.js');

/** A fetch() over an in-memory file: HEAD gives its size, "bytes=a-b"
    ranges give slices. calls keeps the request headers of every call. */
function fakeFetch(file) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const headers = init.headers || {};
    calls.push(headers);
    if (init.method === 'HEAD') {
      return { ok: true, status: 200, headers: { get: (h) => (h.toLowerCase() === 'content-length' ? String(file.length) : null) } };
    }
    const m = /^bytes=(\d+)-(\d+)$/.exec(headers.Range || '');
    const body = m ? file.slice(+m[1], +m[2] + 1) : file;
    return { ok: true, status: m ? 206 : 200, headers: { get: () => null }, arrayBuffer: async () => body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength) };
  };
  return { fetch, calls };
}

const latest = {
  reference_time: '2026-10-23T06:00:00Z',
  valid_times: ['2026-10-23T12:00Z', '2026-10-23T15:00Z', '2026-10-23T18:00Z'],
};

test('fileUrl: nearest valid hour of the latest run', () => {
  const f = WidgetOpenData.fileUrl(latest, 'ecmwf_ifs025', Date.parse('2026-10-23T15:20:00Z'));
  assert.equal(f.url, 'https://openmeteo.s3.amazonaws.com/data_spatial/ecmwf_ifs025/2026/10/23/0600Z/2026-10-23T1500.om');
  assert.equal(f.validMs, Date.parse('2026-10-23T15:00:00Z'));
});

test('fileUrl: another base for tests', () => {
  const f = WidgetOpenData.fileUrl(latest, 'ecmwf_ifs025', Date.parse('2026-10-23T17:00:00Z'), 'http://127.0.0.1:1/');
  assert.equal(f.url, 'http://127.0.0.1:1/ecmwf_ifs025/2026/10/23/0600Z/2026-10-23T1800.om');
});

test('varNames: 10 m and 700 hPa', () => {
  assert.deepEqual(WidgetOpenData.varNames('10m'), ['wind_u_component_10m', 'wind_v_component_10m']);
  assert.deepEqual(WidgetOpenData.varNames('700hPa'), ['wind_u_component_700hPa', 'wind_v_component_700hPa']);
});

test('mergeRanges: neighbours within the gap become one read', () => {
  const g = WidgetOpenData.mergeRanges([{ offset: 160, size: 40 }, { offset: 100, size: 50 }, { offset: 10000, size: 8 }], 64);
  assert.deepEqual(g.map((x) => [x.start, x.end]), [[100, 200], [10000, 10008]]);
  assert.equal(g[0].members.length, 2);
});

test('TailBackend: tail reads cost nothing, same-tick reads share a request', async () => {
  const file = new Uint8Array(1 << 20).map((_, i) => i & 255);
  const fake = fakeFetch(file);
  const b = new WidgetOpenData.TailBackend('x', 65536, fake.fetch);
  assert.equal(await b.count(), file.length);
  const t = await b.getBytes(file.length - 100, 50);
  assert.equal(t[0], (file.length - 100) & 255);
  assert.equal(b.requests, 2);              // HEAD + tail
  const [a, c] = await Promise.all([b.getBytes(1000, 10), b.getBytes(1020, 10)]);
  assert.equal(b.requests, 3);
  assert.equal(a[0], 1000 & 255);
  assert.equal(c[9], 1029 & 255);
  assert.ok(fake.calls.every((h) => !h['If-Match'] && !h['If-Unmodified-Since']));
});

test('TailBackend: a failed range rejects every read it carried', async () => {
  const b = new WidgetOpenData.TailBackend('x', 1024, async (url, init = {}) => (init.method === 'HEAD'
    ? { ok: true, status: 200, headers: { get: () => '100000' } }
    : { ok: false, status: 503, headers: { get: () => null }, arrayBuffer: async () => new ArrayBuffer(0) }));
  await assert.rejects(b.count());
});

test('toGrid: rows flipped to north-first, antimeridian column added', () => {
  const du = Float32Array.from([1, 2, 3, 4, 5, 6]);   // 3 rows x 2 cols, south first
  const g = WidgetOpenData.toGrid(du, du, 3, 2, 3600000, '10m');
  assert.deepEqual(Array.from(g.levels['10m'].u[0]), [5, 6, 5, 3, 4, 3, 1, 2, 1]);
  assert.deepEqual(g.lats, [90, 0, -90]);
  assert.deepEqual(g.times, [3600]);
  assert.equal(g.u, g.levels['10m'].u);
});

test('cacheKey and usableKept: kept wind per model and level, shown up to 3 h from now', () => {
  assert.equal(WidgetOpenData.cacheKey('ecmwf_ifs025', '700hPa'), 'ecmwf_ifs025:700hPa');
  const now = Date.parse('2026-10-23T15:00:00Z');
  assert.equal(WidgetOpenData.usableKept({ validMs: now - (3 * 3600 - 60) * 1000 }, now), true);
  assert.equal(WidgetOpenData.usableKept({ validMs: now + (3 * 3600 + 60) * 1000 }, now), false);
  assert.equal(WidgetOpenData.usableKept(null, now), false);
});

/** Open-Meteo's reader stand-in: two 3 x 2 fields named for both levels. */
function fakeReader() {
  const field = (name, k) => ({ getName: () => name, getDimensions: () => [3, 2],
    read: async () => Float32Array.from([1, 2, 3, 4, 5, 6].map((x) => x * k)) });
  const kids = [field('cape', 0), field('wind_u_component_10m', 1), field('wind_v_component_10m', 2),
    field('wind_u_component_700hPa', 3), field('wind_v_component_700hPa', 4), field('temperature_2m', 5)];
  // HSURF.om has no children: its root is the field itself (seen on the real file).
  const surface = Object.assign(field(null, 7), { numberOfChildren: () => 0 });
  return { OmDataType: { FloatArray: 20 },
    OmFileReader: { create: async (backend) => (/\/static\/HSURF\.om$/.test(backend.url) ? surface
      : { numberOfChildren: () => kids.length, getChild: async (i) => kids[i] }) } };
}

function memStore() {
  const m = new Map();
  return { m, get: async (k) => m.get(k) || null, put: async (k, v) => { m.set(k, v); } };
}

function loaderWith(nowMs, store) {
  let latestCalls = 0;
  const fetchFn = async (url) => {
    if (/latest\.json$/.test(url)) { latestCalls++; return { ok: true, json: async () => latest }; }
    throw new Error('unexpected ' + url);
  };
  const loader = new WidgetOpenData.Loader({ store, fetchFn, importReader: async () => fakeReader(), now: () => nowMs });
  return { loader, calls: () => latestCalls };
}

test('Loader.load: reads the level asked for, keeps it, and skips latest.json for 10 minutes', async () => {
  const store = memStore(), now = Date.parse('2026-10-23T15:20:00Z');
  const { loader, calls } = loaderWith(now, store);
  const a = await loader.load('700hPa');
  assert.equal(a.changed, true);
  assert.equal(a.grid.levels['700hPa'].u[0][0], 15);   // north row first: 5 * 3
  assert.equal(loader.res, 90);
  assert.ok(store.m.has('ecmwf_ifs025:700hPa'));
  const b = await loader.load('700hPa');
  assert.equal(b.changed, false);
  assert.equal(calls(), 1);
});

test('Loader.load: null when the network fails', async () => {
  const loader = new WidgetOpenData.Loader({ store: memStore(), fetchFn: async () => { throw new Error('offline'); },
    importReader: async () => fakeReader(), now: () => 0 });
  const warn = console.warn; console.warn = () => {};
  try { assert.equal(await loader.load('10m'), null); } finally { console.warn = warn; }
});

test('Loader.kept: the kept wind when recent enough, else null', async () => {
  const store = memStore(), now = Date.parse('2026-10-23T15:20:00Z');
  await loaderWith(now, store).loader.load('10m');
  const g = await loaderWith(now + 3600e3, store).loader.kept('10m');
  assert.equal(g.levels['10m'].u[0][0], 5);
  assert.equal(await loaderWith(now + 4 * 3600e3, store).loader.kept('10m'), null);
  assert.equal(await loaderWith(now, store).loader.kept('700hPa'), null);
});

test('toScalarGrid: rows flipped north-first, antimeridian column added', () => {
  const g = WidgetOpenData.toScalarGrid(Float32Array.from([5, 10, 15, 20, 25, 30]), 3, 2, 3600000);
  assert.deepEqual(Array.from(g.values), [25, 30, 25, 15, 20, 15, 5, 10, 5]);
  assert.deepEqual(g.lats, [90, 0, -90]);
  assert.deepEqual(g.lons, [-180, -90, 0]);
  assert.equal(g.res, 90);
  assert.deepEqual(g.times, [3600]);
});

test('Loader.loadTemp: reads temperature_2m, keeps it under its own key, wind keys untouched', async () => {
  const store = memStore(), now = Date.parse('2026-10-23T15:20:00Z');
  const res = await loaderWith(now, store).loader.loadTemp();
  assert.equal(res.changed, true);
  assert.equal(res.grid.values[0], 25);   // north row first: 5 * 5
  assert.ok(store.m.has('ecmwf_ifs025:t2m'));
  assert.equal(store.m.has('ecmwf_ifs025:10m'), false);
});

test('Loader.keptTemp: the kept temperature up to 3 h from now, else null', async () => {
  const store = memStore(), now = Date.parse('2026-10-23T15:20:00Z');
  await loaderWith(now, store).loader.loadTemp();
  assert.equal((await loaderWith(now + 3600e3, store).loader.keptTemp()).values[0], 25);
  assert.equal(await loaderWith(now + 4 * 3600e3, store).loader.keptTemp(), null);
});

test('Loader.loadSurface: read once, then from the store even years later', async () => {
  const store = memStore(), now = Date.parse('2026-10-23T15:20:00Z');
  let imports = 0;
  const make = (t) => new WidgetOpenData.Loader({ store, fetchFn: async () => { throw new Error('no fetch'); },
    importReader: async () => { imports++; return fakeReader(); }, now: () => t });
  const a = await make(now).loadSurface();
  assert.equal(a.values[0], 35);          // north row first: 5 * 7
  assert.ok(store.m.has('ecmwf_ifs025:hsurf'));
  const b = await make(now + 365 * 86400e3).loadSurface();
  assert.equal(b.values[0], 35);
  assert.equal(imports, 1);
});

test('Loader.loadSurface: null when the file cannot be read', async () => {
  const loader = new WidgetOpenData.Loader({ store: memStore(), fetchFn: async () => { throw new Error('offline'); },
    importReader: async () => { throw new Error('no reader'); }, now: () => 0 });
  const warn = console.warn; console.warn = () => {};
  try { assert.equal(await loader.loadSurface(), null); } finally { console.warn = warn; }
});

test('SURFACE_URL: the model ground height of the open-data bucket', () => {
  assert.equal(WidgetOpenData.SURFACE_URL('ecmwf_ifs025'), 'https://openmeteo.s3.amazonaws.com/data/ecmwf_ifs025/static/HSURF.om');
});

test('toModelGrid: a regional field kept as the file holds it, on its model grid, its size checked', () => {
  const d = new Float32Array(717 * 1121).fill(3);
  const g = WidgetOpenData.toModelGrid(d, 717, 1121, 3600000, 'meteofrance_arome_france0025');
  assert.equal(g.values, d);
  assert.equal(g.desc.id, 'meteofrance_arome_france0025');
  assert.deepEqual(g.times, [3600]);
  assert.throws(() => WidgetOpenData.toModelGrid(d, 700, 1121, 0, 'meteofrance_arome_france0025'), /717 x 1121/);
});
