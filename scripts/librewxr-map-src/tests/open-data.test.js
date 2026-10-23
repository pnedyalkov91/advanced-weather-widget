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
