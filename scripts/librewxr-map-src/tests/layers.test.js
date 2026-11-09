'use strict';
// Unit tests for the animation's layers beyond temperature and wind
// (glue-pressure.js, glue-airquality.js, glue-precip.js, glue-clouds.js,
// glue-humidity.js), loaded in a sandbox of the page (layers-sandbox.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadLayers } = require('./layers-sandbox.js');

const L = loadLayers();
const H = 3600e3;
const at = (s) => Date.parse(s);
// Values made in the sandbox come from another realm: compare them as plain data.
const plain = (x) => JSON.parse(JSON.stringify(x));

test('the layers register with the page: their fields and their layers', () => {
  for (const id of ['pressure', 'isobars', 'airquality', 'precipitation', 'clouds', 'humidity', 'dewpoint'])
    assert.ok(L.ctx.ANIM_LAYERS[id], 'layer ' + id);
  for (const id of ['pressure', 'isobars', 'airquality', 'precipitation', 'clouds', 'humidity', 'dewpoint'])
    assert.ok(L.ctx.WidgetAnim.FIELDS[id], 'field ' + id);
  for (const f of ['presSetOpacity', 'aqSetOpacity', 'precipSetOpacity', 'cloudSetOpacity', 'humiditySetOpacity', 'dewpointSetOpacity',
    'aqSetPollutant', 'precipSetKinds', 'cloudSetLevels'])
    assert.equal(typeof L.ctx.window[f], 'function', f);
});

test('the colored layers take turns: one switched on switches the others off', () => {
  L.ctx.switched.length = 0;
  L.ctx.window.animSetLayer('humidity', true);
  assert.deepEqual(plain(L.ctx.switched), [['dewpoint', false], ['airquality', false], ['temperature', false], ['pressure', false], ['humidity', true]]);
  L.ctx.switched.length = 0;
  L.ctx.window.animSetLayer('wind', true);
  L.ctx.window.animSetLayer('humidity', false);
  assert.deepEqual(plain(L.ctx.switched), [['wind', true], ['humidity', false]]);
});

test('isobars: a field rising eastward gives straight north-south lines, at the right longitude', () => {
  // 5 x 9 at 45 degrees, 1001 hPa at -180 rising 4 hPa a column.
  const rows = 5, cols = 9, values = new Float32Array(rows * cols);
  for (let i = 0; i < rows; i++) for (let j = 0; j < cols; j++) values[i * cols + j] = 1001 + j * 4;
  const lines = plain(L.WidgetPressure.contours({ rows, cols, values }, 45, 4, 90, null, 0));
  const l1004 = lines.filter((f) => f.properties.p === 1004);
  assert.equal(l1004.length, 1);
  const lons = new Set(l1004[0].geometry.coordinates.map((c) => c[0]));
  assert.deepEqual([...lons], [-180 + 0.75 * 45]);   // three quarters of the way to the next column
  const lats = l1004[0].geometry.coordinates.map((c) => c[1]).sort((a, b) => a - b);
  assert.deepEqual([lats[0], lats[lats.length - 1]], [-90, 90]);
  assert.deepEqual([...new Set(lines.map((f) => f.properties.p))].sort(), [1004, 1008, 1012, 1016, 1020, 1024, 1028, 1032]);
  assert.equal(lines.find((f) => f.properties.p === 1020).properties.major, 1);
});

test('pressure marks: a deep low on the equator is an L, a flat field has none', () => {
  const rows = 9, cols = 17, values = new Float32Array(rows * cols).fill(1013);
  values[4 * cols + 8] = 990;
  const marks = plain(L.WidgetPressure.extrema({ rows, cols, values }, 22.5, 4, 2.5, 90));
  assert.deepEqual(marks, [{ sym: 'L', p: 990, lon: 0, lat: 0, strong: true }]);
  assert.deepEqual(plain(L.WidgetPressure.extrema({ rows, cols, values: new Float32Array(rows * cols).fill(1013) }, 22.5, 4, 2.5, 90)), []);
});

test('air quality: a value and its byte, on the log scale and on the UV steps', () => {
  const aq = L.WidgetAirQuality;
  for (const v of [0, 10, 25, 250, 2000]) assert.ok(Math.abs(aq.valueOf(aq.byteOf(v, aq.POLL.pm2_5), aq.POLL.pm2_5) - v) < 1e-6 * (v + 1), 'pm2.5 ' + v);
  assert.equal(Math.round(aq.byteOf(2000, aq.POLL.pm2_5)), 254);
  assert.equal(aq.byteOf(6, aq.POLL.uv_index), 60);
  assert.equal(aq.valueOf(60, aq.POLL.uv_index), 6);
});

test('air quality: clean air shows nothing, whatever the pollutant', () => {
  const aq = L.WidgetAirQuality;
  for (const id of Object.keys(aq.POLL)) assert.equal(aq.buildLut(aq.POLL[id])[3], 0, id);
  assert.equal(aq.buildLut(aq.POLL.dust)[Math.ceil(aq.byteOf(20, aq.POLL.dust)) * 4 + 3], 255);
});

test('precipitation: the run of a file, never newer than the latest, the long range from the runs of 00 and 12', () => {
  const p = L.WidgetPrecip, ref = at('2026-11-08T06:00:00Z');
  assert.equal(p.runOf(at('2026-11-08T09:00:00Z'), ref), ref);
  assert.equal(p.runOf(at('2026-11-08T06:00:00Z'), ref), at('2026-11-08T00:00:00Z'));   // a run has no rain at its own hour
  assert.equal(p.runOf(at('2026-11-09T12:00:00Z'), ref), ref);
  assert.equal(p.runOf(ref + 150 * H, ref), at('2026-11-08T00:00:00Z'));
  assert.equal(p.hasFile(ref + 3 * H, ref), true);
  assert.equal(p.hasFile(ref, ref), false);
  assert.equal(p.hasFile(at('2026-11-08T00:00:00Z') + 153 * H, at('2026-11-08T00:00:00Z')), false);   // every 6 h past 144 h
  assert.equal(p.hasFile(at('2026-11-08T00:00:00Z') + 156 * H, at('2026-11-08T00:00:00Z')), true);
});

test('precipitation: the picture of an hour is what fell from 1.5 h before to 1.5 h after, from the files of that window', () => {
  const p = L.WidgetPrecip, ref = at('2026-11-08T06:00:00Z');
  const files = plain(p.filesFor(at('2026-11-08T09:00:00Z'), ref));
  assert.deepEqual(files, [
    { t: at('2026-11-08T09:00:00Z'), run: ref, w: 0.5 },
    { t: at('2026-11-08T12:00:00Z'), run: ref, w: 0.5 }
  ]);
});

test('precipitation: two files mixed by their shares, the kind of the wetter one', () => {
  const p = L.WidgetPrecip;
  for (const v of [0.1, 1, 5, 50]) assert.ok(Math.abs(p.rateOf(p.byteOf(v)) - v) < 1e-9, 'rate ' + v);
  const b2 = Math.round(p.byteOf(2));
  const out = p.combine([
    { w: 0.5, parts: [Uint8Array.from([b2, 0]), Uint8Array.from([1, 0])] },
    { w: 0.5, parts: [Uint8Array.from([0, 0]), Uint8Array.from([2, 0])] }
  ]);
  assert.ok(Math.abs(p.rateOf(out[0][0]) - 1) < 0.05, 'half of 2 mm/h: ' + p.rateOf(out[0][0]));
  assert.equal(out[1][0], 1);
  assert.deepEqual([out[0][1], out[1][1]], [0, 0]);   // dry stays dry
});

test('clouds: the four levels in one picture, one point out of two, a byte of percent each', () => {
  const n = 5 * 8, data = [100, 50, 20, 0].map((v) => new Float32Array(n).fill(v));   // total, high, mid, low
  const r = L.WidgetClouds.readFile({ data, ny: 5, nx: 8 }, at('2026-11-08T12:00:00Z'));
  const px = Array.from(r.parts[0].slice(0, 4));
  assert.deepEqual(px, [0, 51, 127, 255]);   // low, mid, high, total (50 % is 127.49...)
  assert.equal(r.meta.res, 90);
  assert.equal(r.parts[0].length, r.meta.lats.length * r.meta.lons.length * 4);
});

test('dew point: the Magnus formula, the air temperature itself when saturated', () => {
  const dp = L.WidgetHumidity.dewPoint;
  assert.ok(Math.abs(dp(20, 50) - 9.26) < 0.02, String(dp(20, 50)));
  assert.ok(Math.abs(dp(-5, 100) + 5) < 1e-9);
  assert.ok(Math.abs(dp(30, 70) - 23.9) < 0.1, String(dp(30, 70)));
});
