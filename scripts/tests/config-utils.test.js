'use strict';
// Unit tests for contents/ui/js/configUtils.js, a QML ".pragma library"
// file: loaded here without its pragma line.
// Run: node --test scripts/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const src = fs.readFileSync(path.join(__dirname, '../../contents/ui/js/configUtils.js'), 'utf8')
  .replace(/^\.pragma library$/m, '');
const U = {};
vm.runInNewContext(src, U);

test('colorFromText: hex colors as copied from color pickers and editors', () => {
  assert.equal(U.colorFromText('#1E64FF'), '#1e64ff');
  assert.equal(U.colorFromText('1e64ff'), '#1e64ff');
  assert.equal(U.colorFromText('  #ffdc00\n'), '#ffdc00');
  assert.equal(U.colorFromText('#f80'), '#ff8800');
});

test('colorFromText: anything else is no color', () => {
  assert.equal(U.colorFromText(''), '');
  assert.equal(U.colorFromText(null), '');
  assert.equal(U.colorFromText('#12345'), '');
  assert.equal(U.colorFromText('#gg0000'), '');
  assert.equal(U.colorFromText('wind 38 km/h'), '');
  assert.equal(U.colorFromText('#ff000080'), '');
});

const MUTED = [[-40, '#1d2a5c'], [-20, '#3d5a99'], [-10, '#7f9cc4'], [0, '#e6e6e6'], [10, '#d9c49a'], [20, '#b88a55'], [30, '#8c5a2b'], [40, '#5a3115']];
const plain = (v) => JSON.parse(JSON.stringify(v));   // out of the vm's realm, for deepEqual

test('tempPaletteStops: empty, builtin, custom, broken', () => {
  assert.deepEqual(plain(U.tempPaletteStops('', '[]')), plain(U.TEMP_BUILTINS[0].stops));
  assert.deepEqual(plain(U.tempPaletteStops('builtin:muted', '[]')), MUTED.map(([t, color]) => ({ t, color })));
  assert.deepEqual(plain(U.tempPaletteStops('builtin:bluered', '[]')).length, 8);
  const mine = '[{"name":"Mine","stops":[{"t":0,"color":"#000000"},{"t":10,"color":"#ffffff"}]}]';
  assert.deepEqual(plain(U.tempPaletteStops('Mine', mine)), [{ t: 0, color: '#000000' }, { t: 10, color: '#ffffff' }]);
  assert.deepEqual(plain(U.tempPaletteStops('Mine', 'nimp')), plain(U.TEMP_BUILTINS[0].stops));
  const down = '[{"name":"Mine","stops":[{"t":10,"color":"#000000"},{"t":0,"color":"#ffffff"}]}]';
  assert.deepEqual(plain(U.tempPaletteStops('Mine', down)), plain(U.TEMP_BUILTINS[0].stops));
  assert.deepEqual(plain(U.tempPaletteStops('Other', mine)), plain(U.TEMP_BUILTINS[0].stops));
});

test('TEMP_BUILTINS: vivid first with an empty id, then muted and blue-red', () => {
  assert.deepEqual(plain(U.TEMP_BUILTINS.map((b) => b.id)), ['', 'builtin:muted', 'builtin:bluered']);
  assert.deepEqual(plain(U.TEMP_BUILTINS.map((b) => b.key)), ['vivid', 'muted', 'bluered']);
});

test('formatTempPalette: the page form of the vivid palette', () => {
  assert.equal(U.formatTempPalette(U.TEMP_BUILTINS[0].stops),
    '-40:3b3050,-30:4b3a9c,-20:3f63c4,-10:2aa3a8,0:7ccf5a,5:d6d63a,10:f2c230,20:e8862a,30:d23a22,40:7a0f12');
});

test('tempToUnit / tempFromUnit: Celsius and Fahrenheit, to 0.1', () => {
  assert.equal(U.tempToUnit(0, 'F'), 32);
  assert.equal(U.tempToUnit(-40, 'F'), -40);
  assert.equal(U.tempToUnit(12.5, 'C'), 12.5);
  assert.equal(U.tempFromUnit(32, 'F'), 0);
  assert.equal(U.tempFromUnit(50, 'F'), 10);
  assert.equal(U.tempFromUnit(51, 'F'), 10.6);
  assert.equal(U.tempFromUnit(12.34, 'C'), 12.3);
});

test('effectiveTempUnit: the KDE locale or the widget setting', () => {
  assert.equal(U.effectiveTempUnit('kde', 'C', 1), 'F');
  assert.equal(U.effectiveTempUnit('metric', 'F', 0), 'F');
  assert.equal(U.effectiveTempUnit('kde', 'F', 0), 'C');
  assert.equal(U.effectiveTempUnit('metric', '', 0), 'C');
});

test('tempPaletteProblem: a name, free, 2 to 12 points going up', () => {
  const two = [{ t: 0, color: '#000000' }, { t: 10, color: '#ffffff' }];
  assert.equal(U.tempPaletteProblem('', two, []), 'name');
  assert.equal(U.tempPaletteProblem('  ', two, []), 'name');
  assert.equal(U.tempPaletteProblem('Vivid', two, ['Vivid', 'Muted']), 'taken');
  assert.equal(U.tempPaletteProblem('Mine', two.slice(0, 1), []), 'count');
  assert.equal(U.tempPaletteProblem('Mine', Array.from({ length: 13 }, (_, i) => ({ t: i, color: '#000000' })), []), 'count');
  assert.equal(U.tempPaletteProblem('Mine', [two[1], two[0]], []), 'order');
  assert.equal(U.tempPaletteProblem('Mine', two, ['Other']), '');
});

test('tempAddStop: one more point 5 degrees of the unit above the last, same color', () => {
  const two = [{ t: 0, color: '#000000' }, { t: 10, color: '#ff0000' }];
  assert.deepEqual(plain(U.tempAddStop(two, 'C')), [...two, { t: 15, color: '#ff0000' }]);
  assert.deepEqual(plain(U.tempAddStop(two, 'F')).pop(), { t: 12.8, color: '#ff0000' });
  assert.equal(two.length, 2, 'the list given is left as it is');
});

test('weatherStackOrder: the stack of the weather layers, top first, from the setting', () => {
  const all = ['radar', 'satellite', 'wind', 'precipitation', 'clouds', 'temperature', 'pressure', 'humidity', 'dewpoint', 'airquality'];
  assert.deepEqual(plain(U.weatherStackOrder('')), all);
  assert.deepEqual(plain(U.weatherStackOrder('not json')), all);
  assert.deepEqual(plain(U.weatherStackOrder('["clouds","isobars","wind","radar","clouds"]')).slice(0, 4), ['clouds', 'wind', 'radar', 'satellite']);
  assert.equal(U.weatherStackOrder('["clouds"]').length, all.length);
});

test('weatherStackMove: a layer dragged from one place to another', () => {
  const o = ['a', 'b', 'c', 'd'];
  assert.deepEqual(plain(U.weatherStackMove(o, 3, 0)), ['d', 'a', 'b', 'c']);
  assert.deepEqual(plain(U.weatherStackMove(o, 0, 2)), ['b', 'c', 'a', 'd']);
  assert.deepEqual(plain(U.weatherStackMove(o, 1, 9)), o);
  assert.deepEqual(o, ['a', 'b', 'c', 'd'], 'the list given is left as it is');
});

test('timeLineStale: now still on its frame, or moved to another one', () => {
  const H = 3600e3, t0 = Date.parse('2026-11-09T18:00:00Z');
  const times = [t0 - 3 * H, t0, t0 + 3 * H, t0 + 6 * H];
  assert.equal(U.timeLineStale(times, 1, t0 + H), false);
  assert.equal(U.timeLineStale(times, 1, t0 + 1.4 * H), false);
  // Nearer the next frame: stale.
  assert.equal(U.timeLineStale(times, 1, t0 + 1.6 * H), true);
  // The next morning, past the range's end: stale.
  assert.equal(U.timeLineStale(times, 1, t0 + 14 * H), true);
  // Now on the last frame and just past it: kept.
  assert.equal(U.timeLineStale(times, 3, t0 + 6.4 * H), false);
  assert.equal(U.timeLineStale(times, 3, t0 + 7.6 * H), true);
  // Nothing to judge.
  assert.equal(U.timeLineStale([], 0, t0), false);
  assert.equal(U.timeLineStale(null, 0, t0), false);
  assert.equal(U.timeLineStale([t0], 0, t0 + 14 * H), true);
  assert.equal(U.timeLineStale([t0], 0, t0 + 0.5 * H), false);
});
