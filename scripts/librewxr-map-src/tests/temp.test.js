'use strict';
// Unit tests for the temperature math of the radar map (glue-temp.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const T = require('../glue-temp.js');

test('parsePalette: signed and decimal temperatures, 2 to 12 points', () => {
  assert.deepEqual(T.parsePalette('-12.5:2166AC,30:b2182b'), [{ t: -12.5, color: '#2166ac' }, { t: 30, color: '#b2182b' }]);
  assert.equal(T.parsePalette('10:ffffff'), null);                 // one point
  assert.equal(T.parsePalette('10:ffffff,5:000000'), null);       // not ascending
  assert.equal(T.parsePalette('0:fff,10:000000'), null);          // short color
  assert.equal(T.parsePalette(Array(13).fill(0).map((_, i) => i + ':000000').join(',')), null);
  assert.equal(T.parsePalette(''), null);
});

test('formatPalette round-trips DEFAULT_STOPS', () => {
  assert.deepEqual(T.parsePalette(T.formatPalette(T.DEFAULT_STOPS)), T.DEFAULT_STOPS);
});

test('colorAt: ends held, linear in between', () => {
  const s = [{ t: 0, color: '#000000' }, { t: 10, color: '#ff0000' }];
  assert.deepEqual(T.colorAt(s, -5), [0, 0, 0]);
  assert.deepEqual(T.colorAt(s, 5), [128, 0, 0]);     // rounded
  assert.deepEqual(T.colorAt(s, 99), [255, 0, 0]);
});

test('bandCenterC: the middle of the band, in the unit of the widget', () => {
  assert.equal(T.bandCenterC(12, 5, 'C'), 12.5);
  assert.equal(T.bandCenterC(-0.1, 5, 'C'), -2.5);
  assert.equal(T.bandCenterC(12, 0, 'C'), 12);
  // 12 °C = 53.6 °F, band 50-55 °F, middle 52.5 °F = 11.388... °C
  assert.ok(Math.abs(T.bandCenterC(12, 5, 'F') - 11.3889) < 1e-3);
});

test('buildLut and lutIndex: banded colors, clamped ends', () => {
  const lut = T.buildLut(T.DEFAULT_STOPS, 5, 'C');
  const at = (t) => Array.from(lut.slice(T.lutIndex(t) * 3, T.lutIndex(t) * 3 + 3));
  assert.deepEqual(at(10.1), at(14.9));
  assert.notDeepEqual(at(14.9), at(15.1));
  assert.equal(T.lutIndex(-200), 0);
  assert.equal(T.lutIndex(200), T.LUT_SIZE - 1);
});

test('legendTicks: every 10 °C over the palette, every 20 °F in Fahrenheit', () => {
  assert.deepEqual(T.legendTicks(T.DEFAULT_STOPS, 'C').map((k) => k.label), ['-40', '-30', '-20', '-10', '0', '10', '20', '30', '40']);
  assert.equal(T.legendTicks(T.DEFAULT_STOPS, 'C')[4].pos, 0.5);
  assert.deepEqual(T.legendTicks(T.DEFAULT_STOPS, 'F').map((k) => k.label), ['-40', '-20', '0', '20', '40', '60', '80', '100']);
});

test('normStep, normOpacity, normUnit', () => {
  assert.equal(T.normStep('2'), 2); assert.equal(T.normStep('2.5'), 2.5); assert.equal(T.normStep(3), 5); assert.equal(T.normStep('0'), 0);
  assert.equal(T.normOpacity('5'), 10); assert.equal(T.normOpacity('x'), 45); assert.equal(T.normOpacity(100), 100);
  assert.equal(T.normUnit('F'), 'F'); assert.equal(T.normUnit('K'), 'C');
});

test('correct: the Mont Blanc case measured on 2026-10-30', () => {
  assert.ok(Math.abs(T.correct(6.3, 2076, 4792) - -11.354) < 1e-3);
  assert.ok(Math.abs(T.correct(6.3, 2076, 1034) - 13.073) < 1e-3);
});

test('correct: sea depths count as sea level, missing heights change nothing', () => {
  assert.equal(T.correct(10, 0, -3000), 10);
  assert.equal(T.correct(10, 500, NaN), 10);
  assert.equal(T.correct(10, NaN, 300), 10);
});

test('sampleScalar: bilinear, wrapped across the antimeridian, NaN outside', () => {
  const g = { lats: [10, 0], lons: [-180, 0, 180] };
  const v = Float32Array.from([0, 10, 0, 20, 30, 20]);
  assert.equal(T.sampleScalar(g, v, 5, -90), 15);
  assert.equal(T.sampleScalar(g, v, 5, 270), 15);      // same meridian, next world copy
  assert.ok(Number.isNaN(T.sampleScalar(g, v, 20, 0)));
});

test('paletteFromParam: a param that does not parse gives the vivid palette', () => {
  assert.deepEqual(T.paletteFromParam('nimp'), T.DEFAULT_STOPS);
  assert.deepEqual(T.paletteFromParam(''), T.DEFAULT_STOPS);
  assert.deepEqual(T.paletteFromParam(null), T.DEFAULT_STOPS);
  assert.deepEqual(T.paletteFromParam('0:000000,10:ffffff'), [{ t: 0, color: '#000000' }, { t: 10, color: '#ffffff' }]);
});

test('the vivid palette is the same in the page and in the settings', () => {
  const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
  const src = fs.readFileSync(path.join(__dirname, '../../../contents/ui/js/configUtils.js'), 'utf8').replace(/^\.pragma library$/m, '');
  const U = {};
  vm.runInNewContext(src, U);
  assert.deepEqual(JSON.parse(JSON.stringify(U.TEMP_BUILTINS[0].stops)), T.DEFAULT_STOPS);
});

test('edgeWeights: 0 on the grid edge and next to a hole, NaN in the hole', () => {
  const n = 9, v = new Float32Array(n * n).fill(1);
  v[4 * n + 4] = NaN;
  const w = T.edgeWeights(v, n, n, 4);
  assert.ok(Number.isNaN(w[4 * n + 4]));
  assert.equal(w[4 * n + 3], 0.25);      // next to the hole
  assert.equal(w[4 * n + 2], 0.5);       // two from the hole and from the edge
  assert.equal(w[4 * n + 8], 0);         // on the edge
});

test('edgeWeights: in two dimensions the nearest edge counts', () => {
  const n = 7, v = new Float32Array(n * n).fill(1);
  const w = T.edgeWeights(v, n, n, 2);
  assert.equal(w[0], 0);                 // corner
  assert.equal(w[1 * n + 3], 0.5);       // one row in from the top
  assert.equal(w[3 * n + 3], 1);         // center, three in from every side
});

test('edgeWeights: a jitter (in points) moves where the blend starts, never past the edge', () => {
  const n = 9, v = new Float32Array(n * n).fill(1), jitter = new Float32Array(n * n).fill(1);
  const w = T.edgeWeights(v, n, n, 2, jitter);
  assert.equal(w[4 * n + 1], 0);          // one in from the edge, pushed back by one
  assert.equal(w[4 * n + 2], 0.5);
  assert.equal(w[4 * n + 4], 1);
  assert.equal(w[0], 0);
});

test('edgeNoise: the same everywhere it is asked, between 0 and 1, smooth, and not flat', () => {
  assert.equal(T.edgeNoise(46.2, -11.7), T.edgeNoise(46.2, -11.7));
  let lo = 1, hi = 0, jump = 0;
  for (let lat = 30; lat < 40; lat += 0.05) {
    for (let lon = -20; lon < -10; lon += 0.05) {
      const a = T.edgeNoise(lat, lon);
      assert.ok(a >= 0 && a <= 1, 'noise ' + a);
      lo = Math.min(lo, a); hi = Math.max(hi, a);
      jump = Math.max(jump, Math.abs(T.edgeNoise(lat, lon + 0.05) - a), Math.abs(T.edgeNoise(lat + 0.05, lon) - a));
    }
  }
  assert.ok(hi - lo > 0.6, 'range ' + lo + '..' + hi);
  assert.ok(jump < 0.15, 'largest step over 0.05 degrees: ' + jump);
});
