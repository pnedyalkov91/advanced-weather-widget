'use strict';
// Unit tests for the temperature animation (glue-anim.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const A = require('../glue-anim.js');

const H = 3600e3;
const at = (s) => Date.parse(s);

test('frameTimes: every 3 h around the step nearest to now', () => {
  const ft = A.frameTimes(at('2026-11-01T14:10:00Z'), 24, 48, 3);
  assert.equal(ft.times.length, 25);
  assert.equal(ft.times[ft.now], at('2026-11-01T15:00:00Z'));
  assert.equal(ft.times[0], at('2026-10-31T15:00:00Z'));
  assert.equal(ft.times[24], at('2026-11-03T15:00:00Z'));
});

test('runFor: the run of that hour, never newer than the latest one', () => {
  const latest = at('2026-11-01T06:00:00Z');
  assert.equal(A.runFor(at('2026-10-31T21:00:00Z'), latest), at('2026-10-31T18:00:00Z'));
  assert.equal(A.runFor(at('2026-10-31T18:00:00Z'), latest), at('2026-10-31T18:00:00Z'));
  assert.equal(A.runFor(at('2026-11-01T15:00:00Z'), latest), latest);
  assert.equal(A.runFor(at('2026-11-03T00:00:00Z'), latest), latest);
  // Past the 6 days of the 06 UTC run: the 00 UTC one, 15 days long.
  assert.equal(A.runFor(at('2026-11-07T06:00:00Z'), latest), latest);
  assert.equal(A.runFor(at('2026-11-07T09:00:00Z'), latest), at('2026-11-01T00:00:00Z'));
  assert.equal(A.runFor(at('2026-11-07T09:00:00Z'), at('2026-11-01T12:00:00Z')), at('2026-11-01T12:00:00Z'));
});

test('hasFile: every 3 h for 6 days, then every 6 h', () => {
  const run = at('2026-11-01T00:00:00Z');
  assert.equal(A.hasFile(at('2026-11-07T00:00:00Z'), run), true);
  assert.equal(A.hasFile(at('2026-11-07T03:00:00Z'), run), false);
  assert.equal(A.hasFile(at('2026-11-07T06:00:00Z'), run), true);
  assert.equal(A.hasFile(at('2026-11-06T21:00:00Z'), run), true);
});

test('Frames: an hour without file is halfway between its neighbors', async () => {
  global.WidgetOpenData = require('../glue-wind-open.js');
  const read = [];
  const loader = {
    base: 'b/', model: 'm',
    fetch: async () => ({ ok: true, json: async () => ({ reference_time: '2026-11-01T00:00:00Z' }) }),
    _readVars: async (f) => { read.push(new Date(f.validMs).toISOString()); return { data: [new Float32Array(12).fill(f.validMs % (12 * H) ? 10 : 0)], ny: 3, nx: 4 }; },
  };
  const f = new A.Frames(loader, { now: () => at('2026-11-07T03:00:00Z'), pastH: 3, futureH: 3 });
  await f.load();
  assert.equal(read.includes('2026-11-07T03:00:00.000Z'), false);
  assert.deepEqual(f.between, [false, true, false]);
  assert.equal(f.grid(1).values[0], 5);            // between 0 at 00 h and 10 at 06 h
});

test('frameUrl: run folder, then the valid hour', () => {
  assert.equal(A.frameUrl(at('2026-10-31T21:00:00Z'), at('2026-10-31T18:00:00Z'), 'ecmwf_ifs025', 'https://x/data_spatial/'),
    'https://x/data_spatial/ecmwf_ifs025/2026/10/31/1800Z/2026-10-31T2100.om');
});

test('pack and unpack: half degrees, ends held, NaN kept', () => {
  const back = A.unpack(A.pack(Float32Array.from([12.34, -45.66, NaN, 0, -95, 52])));
  assert.equal(back[0], 12.5);
  assert.equal(back[1], -45.5);
  assert.ok(Number.isNaN(back[2]));
  assert.equal(back[3], 0);
  assert.equal(back[4], -80);
  assert.equal(back[5], 47);
});

test('Frames: the pictures of the old range are taken over, the rest is read', async () => {
  global.WidgetOpenData = require('../glue-wind-open.js');
  const read = [];
  const loader = {
    base: 'b/', model: 'm',
    fetch: async () => ({ ok: true, json: async () => ({ reference_time: '2026-11-01T06:00:00Z' }) }),
    _readVars: async (f) => { read.push(f.validMs); return { data: [new Float32Array(12).fill(5)], ny: 3, nx: 4 }; },
  };
  const now = () => at('2026-11-01T14:00:00Z');
  const small = new A.Frames(loader, { now, pastH: 3, futureH: 3 });
  await small.load();
  assert.equal(read.length, 3);
  read.length = 0;
  const big = new A.Frames(loader, { now, pastH: 6, futureH: 6, reuse: small });
  assert.equal(big.ready(big.nowIndex), true);
  await big.load();
  assert.deepEqual(read.sort(), [at('2026-11-01T09:00:00Z'), at('2026-11-01T21:00:00Z')]);
  assert.equal(big.grid(0).values[0], 5);
});

test('loadOrder: nearest to now first, the future first on a tie', () => {
  assert.deepEqual(A.loadOrder(5, 2), [2, 3, 1, 4, 0]);
});

test('Frames.gridAt: the two frames around and the share of the second, the time in between', () => {
  const f = Object.create(A.Frames.prototype);
  f.times = [0, 3 * H];
  f.meta = { lats: [], lons: [], res: 1 };
  f.packed = [A.pack(Float32Array.from([0, NaN])), A.pack(Float32Array.from([10, 4]))];
  const g = f.gridAt(0.25);
  assert.deepEqual([g.values[0], g.valuesB[0], g.mix], [0, 10, 0.25]);   // mixed where the layer reads them
  assert.ok(Number.isNaN(g.values[1]));
  assert.equal(g.times[0], 0.75 * H / 1000);
  assert.equal(f.gridAt(0.5).values, g.values);                       // unpacked once
  assert.equal(f.gridAt(1).values[0], 10);          // the last frame alone
  f.between = [false, true];
  assert.equal(f.isFile(0), true);
  assert.equal(f.isFile(0.25), false);
  assert.equal(f.isFile(1), false);                 // no file: halfway between its neighbors
  f.packed[1] = null;
  assert.equal(f.gridAt(0.5).values[0], 0);         // the next one not read yet
});

function fakePlayer(ready, opts) {
  const shown = [];
  const clock = { t: 0, settled: true };
  const frames = { times: ready.map((_, i) => i * 3 * H), nowIndex: 0, ready: (i) => ready[i], isFile: (i) => i === Math.floor(i) && !!ready[i] && !(opts && opts.between || [])[i],
    gridAt: (pos) => (ready[Math.floor(pos)] ? { pos } : null) };
  const layer = { showFile: (g) => shown.push(+g.pos.toFixed(3)), settled: () => clock.settled };
  const p = new A.Player(frames, layer, Object.assign({ now: () => clock.t }, opts));
  return { p, shown, clock };
}

test('Player: in between pictures as the map draws them, up to the next frame', () => {
  const { p, shown, clock } = fakePlayer([true, true, true], { stepMs: 1000, endPauseMs: 500, minFrameMs: 100 });
  p.show(0);
  p.play(true);
  clock.t = 50;
  p._tick();
  assert.deepEqual(shown, [0]);                      // too soon after the last picture
  clock.t = 250; clock.settled = false;
  p._tick();
  assert.deepEqual(shown, [0]);                      // the map is still drawing
  clock.settled = true;
  p._tick();
  assert.deepEqual(shown, [0, 0.25]);
  clock.t = 1750;
  p._tick();
  assert.deepEqual(shown, [0, 0.25, 1]);             // held at the next frame
  clock.t = 3000;
  p._tick();
  p._tick();
  assert.deepEqual(shown, [0, 0.25, 1, 2]);          // the last one stays
  clock.t = 3600;
  p._tick();
  assert.deepEqual(shown, [0, 0.25, 1, 2, 0]);
  p.play(false);
});

test('Player: a frame not read is jumped over after stepMs', () => {
  const { p, shown, clock } = fakePlayer([true, false, true], { stepMs: 1000, endPauseMs: 0 });
  p.show(0);
  p.play(true);
  clock.t = 500;
  p._tick();
  assert.deepEqual(shown, [0]);
  clock.t = 1000;
  p._tick();
  assert.deepEqual(shown, [0, 2]);
  p.play(false);
});

test('Player.seek: only the last position asked counts, once the map is free', () => {
  const { p, shown, clock } = fakePlayer([true, true, true, true], {});
  p.show(0);
  clock.settled = false;
  p.seek(1); p.seek(2); p.seek(3); p.seek(2);
  assert.deepEqual(shown, [0]);
  clock.settled = true;
  p._tick();
  assert.deepEqual(shown, [0, 2]);
  p._tick();
  assert.deepEqual(shown, [0, 2]);                   // nothing more to do
  assert.equal(p.timer, null);
});

test('Player.seek: a map that never answers does not hold it for ever', () => {
  const { p, shown, clock } = fakePlayer([true, true], {});
  p.show(0);
  clock.settled = false;
  p.seek(1);
  clock.t = 2000;
  p._tick();
  assert.deepEqual(shown, [0, 1]);
  p.play(false);
});

test('Player.step: one hour at a time on the hour grid, paused, held at the ends', () => {
  const { p, shown } = fakePlayer([true, true, true], {});
  p.show(0);
  p.play(true);
  p.step(1, 3);
  assert.equal(p.playing, false);
  assert.deepEqual(shown, [0, 0.333]);
  p.step(1, 3); p.step(1, 3);
  assert.deepEqual(shown, [0, 0.333, 0.667, 1]);
  p.show(1.5);                                       // between hours
  p.step(-1, 3);
  assert.deepEqual(shown.slice(-1), [1.333]);
  p.show(0);
  p.step(-1, 3);
  assert.deepEqual(shown.slice(-1), [0]);
});

test('Player.stepFile: to the next frame from its file, none past the ends', () => {
  const { p, shown } = fakePlayer([true, true, true, true], { between: [false, false, true, false] });
  p.show(0.5);
  p.stepFile(1);
  assert.deepEqual(shown.slice(-1), [1]);
  p.stepFile(1);
  assert.deepEqual(shown.slice(-1), [3]);            // 2 is worked out, not from a file
  p.stepFile(1);
  assert.deepEqual(shown.slice(-1), [3]);
  p.stepFile(-1);
  assert.deepEqual(shown.slice(-1), [1]);
});
