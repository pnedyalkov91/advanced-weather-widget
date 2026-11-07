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

test('frameTimes: no hours before, now is the first picture', () => {
  const ft = A.frameTimes(at('2026-11-01T14:10:00Z'), 0, 12, 3);
  assert.equal(ft.times.length, 5);
  assert.equal(ft.now, 0);
  assert.equal(ft.times[0], at('2026-11-01T15:00:00Z'));
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

test('Frames.gridAt: the frame after next is unpacked ahead, when the page is idle', () => {
  const f = Object.create(A.Frames.prototype), idle = [];
  let unpacked = 0;
  f.times = [0, 3 * H, 6 * H, 9 * H];
  f.meta = { lats: [], lons: [], res: 1 };
  f.field = Object.assign({}, A.FIELDS.temperature, { unpack: (parts) => { unpacked++; return A.unpack(parts[0]); } });
  f.packed = [0, 10, 20, 30].map((t) => [A.pack(Float32Array.from([t]))]);
  f.idle = (cb) => idle.push(cb);
  f.gridAt(0.5);
  assert.equal(unpacked, 2);
  assert.equal(idle.length, 1);                     // frame 2 asked for
  idle.shift()();
  assert.equal(unpacked, 3);
  assert.equal(f.gridAt(1.5).valuesB[0], 20);       // already there when the step comes
  assert.equal(unpacked, 3);
  f.gridAt(1.6);
  assert.equal(idle.length, 1);                     // frame 3, once
  f.gridAt(1.7);
  assert.equal(idle.length, 1);
});

test('loadOrder: nearest to now first, the future first on a tie', () => {
  assert.deepEqual(A.loadOrder(5, 2), [2, 3, 1, 4, 0]);
});

test('Frames.gridAt: the two frames around and the share of the second, the time in between', () => {
  const f = Object.create(A.Frames.prototype);
  f.times = [0, 3 * H];
  f.meta = { lats: [], lons: [], res: 1 };
  f.field = A.FIELDS.temperature;
  f.packed = [[A.pack(Float32Array.from([0, NaN]))], [A.pack(Float32Array.from([10, 4]))]];
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

test('Player: the cap of pictures per second holds with a timer of 16 ms', () => {
  // A cap of 15 a second used to give 12.5: 66.7 ms waited for, 80 ms
  // reached at the timer's steps.
  for (const fps of [4, 8, 15]) {
    const { p, shown, clock } = fakePlayer([true, true, true], { stepMs: 100000, endPauseMs: 0, minFrameMs: 1000 / fps });
    p.show(0);
    p.play(true);
    for (clock.t = 16; clock.t <= 2000; clock.t += 16) p._tick();
    p.play(false);
    const got = (shown.length - 1) / 2;
    assert.ok(Math.abs(got - fps) <= 0.5, fps + ' a second asked, ' + got + ' shown');
  }
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

test('FIELDS.wind: u and v by half m/s on one byte, ends held, NaN kept', () => {
  const w = A.FIELDS.wind;
  const back = w.unpackPart(w.packPart(Float32Array.from([3.26, -12.7, NaN, 80, -80])));
  assert.deepEqual(Array.from(back.slice(0, 2)), [3.5, -12.5]);
  assert.ok(Number.isNaN(back[2]));
  assert.deepEqual(Array.from(back.slice(3)), [63.5, -63.5]);
});

test('decimate: one point in f each way, both ends kept', () => {
  // 3 rows x 5 columns -> 2 x 3
  const d = A.decimate(Float32Array.from([0, 1, 2, 3, 4, 10, 11, 12, 13, 14, 20, 21, 22, 23, 24]), 3, 5, 2);
  assert.deepEqual(Array.from(d), [0, 2, 4, 20, 22, 24]);
});

function windLoader(read) {
  return {
    base: 'b/', model: 'm',
    fetch: async () => ({ ok: true, json: async () => ({ reference_time: '2026-11-01T06:00:00Z' }) }),
    // 5 x 8 from the file, 45 degrees (south to north, no +180 column): u = hour, v = -hour
    _readVars: async (f, names) => {
      read.push(names.join(','));
      const h = new Date(f.validMs).getUTCHours();
      return { data: [new Float32Array(40).fill(h), new Float32Array(40).fill(-h)], ny: 5, nx: 8 };
    },
  };
}

test('Frames of the wind: both components read, every point of the file, mixed in time by the layer', async () => {
  global.WidgetOpenData = require('../glue-wind-open.js');
  const read = [];
  const f = new A.Frames(windLoader(read), { field: A.FIELDS.wind, now: () => at('2026-11-01T14:00:00Z'), pastH: 3, futureH: 3 });
  await f.load();
  assert.equal(read[0], 'wind_u_component_10m,wind_v_component_10m');
  const g = f.grid(1);
  assert.deepEqual([g.lats.length, g.lons.length, g.res], [5, 9, 45]);   // with the +180 column, as the radar reads it
  assert.deepEqual([g.lats[0], g.lats[4], g.lons[0], g.lons[8]], [90, -90, -180, 180]);
  assert.equal(g.u[0].length, 45);
  assert.equal(g.u[0][22], 15);
  assert.equal(g.v[0][22], -15);
  const m = f.gridAt(1.5);
  assert.deepEqual(m.times, [at('2026-11-01T15:00:00Z') / 1000, at('2026-11-01T18:00:00Z') / 1000]);
  assert.equal(m.at, at('2026-11-01T16:30:00Z') / 1000);
  assert.equal(m.u[1][0], 18);
});

test('Group: ready when every layer is, one grid each, settled when all are', () => {
  const mk = (ready, settled) => {
    const shown = [];
    return {
      shown,
      frames: { ready: (i) => ready[i], isFile: (p) => p === 0, gridAt: (p) => (ready[Math.floor(p)] ? { p } : null), failed: [false, ready[1] === false] },
      layer: { showFile: (g) => shown.push(g.p), settled: () => settled.v, setMoving: (on) => shown.push(on ? 'moving' : 'still') },
    };
  };
  const g = new A.Group([0, 3 * H], 0);
  assert.equal(g.ready(0), false);                  // no layer, nothing to show
  const s1 = { v: true }, s2 = { v: false };
  const temp = mk([true, true], s1), wind = mk([true, false], s2);
  g.add('temperature', temp.frames, temp.layer);
  g.add('wind', wind.frames, wind.layer);
  assert.deepEqual([g.ready(0), g.ready(1)], [true, false]);
  assert.deepEqual(g.failed(), [false, true]);
  assert.equal(g.gridAt(1), null);
  g.showFile(g.gridAt(0.5));
  assert.deepEqual([temp.shown, wind.shown], [[0.5], [0.5]]);
  assert.equal(g.settled(), false);
  s2.v = true;
  assert.equal(g.settled(), true);
  g.setMoving(true);
  assert.deepEqual(temp.shown, [0.5, 'moving']);
  assert.equal(g.timeAt(0.5), 1.5 * H);
  g.remove('wind');
  assert.equal(g.ready(1), true);
});

test('Gate: never more than n at once, the rest in turn', async () => {
  const g = new A.Gate(2);
  let running = 0, most = 0;
  const job = () => g.run(async () => {
    running++; most = Math.max(most, running);
    await new Promise((r) => setImmediate(r));
    running--;
  });
  await Promise.all([job(), job(), job(), job(), job()]);
  assert.equal(most, 2);
  await assert.rejects(g.run(async () => { throw new Error('x'); }));
  await job();                                       // a failure frees its place
});

/** An in-memory stand-in for frameStore(). */
function memStore() {
  const m = new Map();
  return {
    m,
    get: async (k) => (m.has(k) ? m.get(k) : null),
    put: async (k, v) => { m.set(k, v); },
    keys: async () => [...m.keys()],
    del: async (ks) => { ks.forEach((k) => m.delete(k)); },
  };
}

test('frameKey and parseKey: model, layer, run and hour, read back from the key alone', () => {
  const k = A.frameKey('ecmwf_ifs025', 'wind', at('2026-11-01T06:00:00Z'), at('2026-11-01T15:00:00Z'));
  assert.deepEqual(A.parseKey(k), { model: 'ecmwf_ifs025', field: 'wind', runMs: at('2026-11-01T06:00:00Z'), validMs: at('2026-11-01T15:00:00Z') });
  assert.equal(A.parseKey('something else'), null);
});

test('Frames with a store: read from the network once, from the store the next time', async () => {
  global.WidgetOpenData = require('../glue-wind-open.js');
  const read = [], store = memStore(), now = () => at('2026-11-01T14:00:00Z');
  const first = new A.Frames(windLoader(read), { field: A.FIELDS.wind, now, pastH: 3, futureH: 3, store, model: 'm' });
  await first.load();
  assert.equal(read.length, 3);
  assert.equal(store.m.size, 3);
  read.length = 0;
  const again = new A.Frames(windLoader(read), { field: A.FIELDS.wind, now, pastH: 3, futureH: 3, store, model: 'm' });
  const seen = [];
  again.onFrame = (i) => seen.push(i);
  await again.load();
  assert.equal(read.length, 0);
  assert.deepEqual(seen.sort(), [0, 1, 2]);
  assert.equal(again.grid(1).u[0][22], 15);
  assert.equal(again.grid(1).lons.length, 9);
});

test('Frames with a store: what failed in the store or the network does not stop the rest', async () => {
  global.WidgetOpenData = require('../glue-wind-open.js');
  const read = [], store = memStore();
  store.get = async () => { throw new Error('refused'); };
  store.put = async () => { throw new Error('full'); };
  const f = new A.Frames(windLoader(read), { field: A.FIELDS.wind, now: () => at('2026-11-01T14:00:00Z'), pastH: 3, futureH: 3, store, model: 'm' });
  await f.load();
  assert.equal(read.length, 3);
  assert.equal(f.ready(0) && f.ready(1) && f.ready(2), true);
});

test('pruneStore: hours past the longest range and those of a run since replaced go', async () => {
  const store = memStore(), latest = at('2026-11-01T06:00:00Z'), now = at('2026-11-01T14:00:00Z');
  const keep = [
    A.frameKey('m', A.FIELDS.wind.store, at('2026-10-31T18:00:00Z'), at('2026-10-31T21:00:00Z')),   // the past, from its own run
    A.frameKey('m', 'temperature', latest, at('2026-11-02T00:00:00Z')),                // the future, from the latest run
  ];
  const drop = [
    A.frameKey('m', A.FIELDS.wind.store, at('2026-11-01T00:00:00Z'), at('2026-11-02T00:00:00Z')),   // future of an older run
    A.frameKey('m', A.FIELDS.wind.store, at('2026-10-23T12:00:00Z'), at('2026-10-23T15:00:00Z')),   // older than 8 days and a bit
  ];
  drop.push(A.frameKey('m', 'wind', latest, at('2026-11-01T15:00:00Z')));   // a layer kept another way before (the wind at 0.5 degree)
  for (const k of keep.concat(drop, ['other|stuff'])) await store.put(k, {});
  await A.pruneStore(store, 'm', latest, now, 192);
  assert.deepEqual([...store.m.keys()].sort(), keep.concat(['other|stuff']).sort());
});

// === Switching layers: pictures kept, fades ===
test('Frames.pause keeps the pictures: a Frames taking them over is ready at once and reads nothing', async () => {
  global.WidgetOpenData = require('../glue-wind-open.js');
  const read = [];
  const loader = {
    base: 'b/', model: 'm',
    fetch: async () => ({ ok: true, json: async () => ({ reference_time: '2026-11-01T00:00:00Z' }) }),
    _readVars: async (f) => { read.push(f.validMs); return { data: [new Float32Array(12).fill(f.validMs % (12 * H) ? 10 : 0)], ny: 3, nx: 4 }; },
  };
  const now = () => at('2026-11-07T03:00:00Z');
  const first = new A.Frames(loader, { now, pastH: 3, futureH: 3 });
  await first.load();
  first.pause();
  assert.equal(first.stopped, true);
  read.length = 0;
  const again = new A.Frames(loader, { now, pastH: 3, futureH: 3, reuse: first });
  // The hour without file too, before latest.json is read again.
  assert.deepEqual([0, 1, 2].map((i) => again.ready(i)), [true, true, true]);
  assert.equal(again.grid(1).values[0], 5);
  await again.load();
  assert.deepEqual(read, []);
});

/** A clock and a frame loop driven by hand. */
function fakeFrames() {
  const c = { t: 0, cbs: [], later: [] };
  c.now = () => c.t;
  c.raf = (f) => { c.cbs.push(f); };
  c.defer = (f) => { c.later.push(f); };
  c.step = (ms) => { c.t += ms; const cbs = c.cbs; c.cbs = []; cbs.forEach((f) => f(c.t)); };
  c.run = (ms, every = 16) => { for (let n = 0; n < ms; n += every) c.step(every); };
  c.tick = () => { const l = c.later; c.later = []; l.forEach((f) => f()); };
  return c;
}

test('Fade: from where it is to the target in ms, a new target takes over at once', () => {
  const c = fakeFrames(), seen = [];
  const f = new A.Fade((v) => seen.push(+v.toFixed(2)), { ms: 400, now: c.now, raf: c.raf, from: 0 });
  let done = 0;
  f.to(1, () => done++);
  c.run(200);
  assert.ok(f.value > 0.4 && f.value < 0.6, String(f.value));
  f.to(0, () => done += 10);
  c.run(500);
  assert.equal(f.value, 0);
  assert.equal(done, 10, 'the first end never comes');
  assert.equal(seen[seen.length - 1], 0);
});

function fakeLayer() {
  return { fade: 1, removed: 0, setFade(v) { this.fade = v; }, remove() { this.removed++; } };
}
const fakeTrackFrames = () => ({ paused: 0, pause() { this.paused++; } });

test('Switcher: a layer switched off fades out, then goes; its pictures are kept', () => {
  const c = fakeFrames();
  const s = new A.Switcher({ ms: 400, now: c.now, raf: c.raf, defer: c.defer });
  const layer = fakeLayer(), frames = fakeTrackFrames();
  s.leave('pressure', layer, frames);
  assert.equal(frames.paused, 1);
  c.tick();
  c.run(200);
  assert.ok(layer.fade > 0 && layer.fade < 1);
  assert.equal(layer.removed, 0);
  c.run(300);
  assert.equal(layer.removed, 1);
  assert.equal(s.enter('pressure').reuse, frames);
});

test('Switcher: one color for another, the old one waits for the first picture of the new', () => {
  const c = fakeFrames();
  const s = new A.Switcher({ ms: 400, now: c.now, raf: c.raf, defer: c.defer, waitMs: 2000 });
  const temp = fakeLayer(), pres = fakeLayer();
  s.leave('temperature', temp, fakeTrackFrames());
  const e = s.enter('pressure');
  assert.equal(e.layer, null);                       // a new layer to make
  s.entered('pressure', pres);
  assert.equal(pres.fade, 0);
  c.tick();
  c.run(600);
  assert.equal(temp.fade, 1, 'still there while the new one has nothing');
  s.shown('pressure');
  c.run(200);
  assert.ok(temp.fade < 1 && pres.fade > 0);
  assert.ok(Math.abs(temp.fade + pres.fade - 1) < 0.1, 'one goes as the other comes');
  c.run(300);
  assert.equal(pres.fade, 1);
  assert.equal(temp.removed, 1);
});

test('Switcher: the old one does not wait for ever', () => {
  const c = fakeFrames();
  const s = new A.Switcher({ ms: 400, now: c.now, raf: c.raf, defer: c.defer, waitMs: 1000 });
  const temp = fakeLayer();
  s.leave('temperature', temp, fakeTrackFrames());
  s.enter('pressure');
  s.entered('pressure', fakeLayer());
  c.tick();
  c.run(1500);
  assert.equal(temp.removed, 1);
});

test('Switcher: switched on again while it fades out, the same layer comes back', () => {
  const c = fakeFrames();
  const s = new A.Switcher({ ms: 400, now: c.now, raf: c.raf, defer: c.defer });
  const temp = fakeLayer(), frames = fakeTrackFrames();
  s.leave('temperature', temp, frames);
  c.tick();
  c.run(200);
  const e = s.enter('temperature');
  assert.equal(e.layer, temp);
  assert.equal(e.reuse, frames);
  s.entered('temperature', temp);
  s.shown('temperature');
  c.run(500);
  assert.equal(temp.fade, 1);
  assert.equal(temp.removed, 0);
});

test('Switcher: at most `keep` sets of pictures kept, the oldest go first', () => {
  const c = fakeFrames();
  const s = new A.Switcher({ ms: 0, now: c.now, raf: c.raf, defer: c.defer, keep: 2 });
  const f = { a: fakeTrackFrames(), b: fakeTrackFrames(), d: fakeTrackFrames() };
  for (const id of ['a', 'b', 'd']) s.leave(id, fakeLayer(), f[id]);
  assert.equal(s.enter('a').reuse, null);
  assert.equal(s.enter('b').reuse, f.b);
});

test('Switcher.clear: every layer leaving goes at once, nothing kept', () => {
  const c = fakeFrames();
  const s = new A.Switcher({ ms: 400, now: c.now, raf: c.raf, defer: c.defer });
  const temp = fakeLayer();
  s.leave('temperature', temp, fakeTrackFrames());
  s.clear();
  assert.equal(temp.removed, 1);
  assert.equal(s.enter('temperature').reuse, null);
});

test('Group: onShow of a layer, once, after its first picture', () => {
  const g = new A.Group([0, 3 * H], 0);
  let n = 0;
  g.add('t', { ready: () => true, gridAt: (p) => ({ p }) }, { showFile() {} }, { onShow: () => n++ });
  g.showFile(g.gridAt(0));
  g.showFile(g.gridAt(1));
  assert.equal(n, 1);
});

test('Switcher: a layer without setFade just comes and goes; flush ends the fades out at once', () => {
  const c = fakeFrames();
  const s = new A.Switcher({ ms: 400, now: c.now, raf: c.raf, defer: c.defer });
  const bare = { removed: 0, remove() { this.removed++; } }, frames = fakeTrackFrames();
  s.entered('isobars', bare);
  s.shown('isobars');
  s.leave('isobars', bare, frames);
  s.flush();
  assert.equal(bare.removed, 1);
  assert.equal(s.enter('isobars').reuse, frames, 'pictures still kept');
});

test('Switcher.drop: the pictures kept for a layer go (its data changed)', () => {
  const c = fakeFrames();
  const s = new A.Switcher({ ms: 0, now: c.now, raf: c.raf, defer: c.defer });
  s.leave('airquality', fakeLayer(), fakeTrackFrames());
  s.drop('airquality');
  assert.equal(s.enter('airquality').reuse, null);
});

// === Playing on while layers come and go ===
const trackOf = (ready) => {
  const shown = [];
  return {
    shown,
    frames: { ready: (i) => !!ready[i], isFile: () => true, gridAt: (p) => (ready[Math.floor(p)] ? { p } : null), failed: ready.map(() => false) },
    layer: { showFile: (g) => shown.push(g.p), settled: () => true },
  };
};

test('Group: a layer still loading does not hold the others; it joins once it has the picture', () => {
  const g = new A.Group([0, 3 * H, 6 * H], 0);
  const wind = trackOf([true, true, true]), temp = trackOf([false, true, false]);
  g.add('wind', wind.frames, wind.layer);
  let shownTemp = 0;
  g.add('temperature', temp.frames, temp.layer, { optional: true, onShow: () => shownTemp++ });
  assert.deepEqual([0, 1, 2].map((i) => g.ready(i)), [true, true, true]);
  g.showFile(g.gridAt(0));
  assert.deepEqual([wind.shown, temp.shown, shownTemp], [[0], [], 0]);
  g.showFile(g.gridAt(1));
  assert.deepEqual([wind.shown, temp.shown, shownTemp], [[0, 1], [1], 1]);
  // Loaded: it counts again.
  g.setOptional('temperature', false);
  assert.equal(g.ready(2), false);
});

test('Group: layers all still loading count as before', () => {
  const g = new A.Group([0, 3 * H], 0);
  const temp = trackOf([false, true]);
  g.add('temperature', temp.frames, temp.layer, { optional: true });
  assert.deepEqual([g.ready(0), g.ready(1)], [false, true]);
  assert.equal(g.gridAt(0), null);
});

test('Group: a layer leaving still gets the pictures, without counting for ready or settled', () => {
  const g = new A.Group([0, 3 * H], 0);
  const wind = trackOf([true, true]), old = trackOf([true, false]);
  old.layer.settled = () => false;
  g.add('wind', wind.frames, wind.layer);
  g.addGhost('pressure', old.frames, old.layer);
  assert.equal(g.ready(1), true);
  assert.equal(g.settled(), true);
  g.showFile(g.gridAt(0.5));
  assert.deepEqual(old.shown, [0.5]);
  g.showFile(g.gridAt(1));          // it has no picture there: nothing
  assert.deepEqual(old.shown, [0.5]);
  g.removeGhost('pressure');
  g.showFile(g.gridAt(0));
  assert.deepEqual(old.shown, [0.5]);
});

test('Switcher: onGone once a layer is gone, after its fade, a flush or a clear', () => {
  const c = fakeFrames(), gone = [];
  const s = new A.Switcher({ ms: 400, now: c.now, raf: c.raf, defer: c.defer, onGone: (key, layer) => gone.push(key) });
  s.leave('a', fakeLayer(), fakeTrackFrames());
  c.tick();
  c.run(500);
  s.leave('b', fakeLayer(), fakeTrackFrames());
  s.flush();
  s.leave('d', fakeLayer(), fakeTrackFrames());
  s.clear();
  assert.deepEqual(gone, ['a', 'b', 'd']);
});

const AROME = 'meteofrance_arome_france0025';

test('schedule of AROME: runs every 3 h, hourly files for 51 h', () => {
  const s = A.scheduleOf(AROME), latest = at('2026-11-07T15:00:00Z');
  assert.equal(s.runFor(at('2026-11-07T11:00:00Z'), latest), at('2026-11-07T09:00:00Z'));
  assert.equal(s.runFor(at('2026-11-09T12:00:00Z'), latest), latest);
  assert.equal(s.hasFile(at('2026-11-09T18:00:00Z'), latest), true);    // +51 h
  assert.equal(s.hasFile(at('2026-11-09T21:00:00Z'), latest), false);   // +54 h
  assert.equal(A.scheduleOf('ecmwf_ifs025').runFor, A.runFor);
});

/** A loader over regional files of AROME's size, latest run 15Z; reads
    lists the urls asked. */
function aromeLoader(reads) {
  return {
    base: 'b/', model: 'ecmwf_ifs025',
    fetch: async (url) => { reads.push(url); return { ok: true, json: async () => ({ reference_time: '2026-11-07T15:00:00Z' }) }; },
    _readVars: async (f) => {
      reads.push(f.url);
      const d = new Float32Array(717 * 1121).fill(12);
      d[0] = NaN;
      return { data: [d], ny: 717, nx: 1121 };
    }
  };
}

test('Frames of AROME: its own latest.json and files, a regional grid with its edge weights', async () => {
  global.WidgetOpenData = require('../glue-wind-open.js');
  global.WidgetTemp = require('../glue-temp.js');
  global.WidgetGrids = require('../glue-grids.js');
  const reads = [];
  const f = new A.Frames(aromeLoader(reads), { field: A.FIELDS.temperatureFine, fileModel: AROME, now: () => at('2026-11-07T16:10:00Z'), pastH: 3, futureH: 3 });
  await f.load();
  assert.equal(reads[0], 'b/' + AROME + '/latest.json');
  assert.ok(reads.includes('b/' + AROME + '/2026/11/07/1500Z/2026-11-07T1800.om'));
  assert.ok(reads.includes('b/' + AROME + '/2026/11/07/1200Z/2026-11-07T1200.om'));
  const g = f.grid(1);
  assert.equal(g.desc.id, AROME);
  assert.equal(g.values.length, 717 * 1121);
  assert.equal(g.weights.length, 717 * 1121);
  assert.ok(Number.isNaN(g.weights[0]));                 // the missing value: first point of the file (south-west)
  assert.equal(g.weights[1120], 0);                      // grid edge (south-east)
  assert.equal(g.weights[358 * 1121 + 560], 1);          // middle
  assert.equal(f.grid(1).weights, g.weights);            // worked out once
});

test('Frames.gridAt: the fine model rides along when it has the picture', () => {
  const coarse = Object.create(A.Frames.prototype);
  coarse.field = A.FIELDS.temperature;
  coarse.times = [0, 3 * H];
  coarse.meta = { lats: [], lons: [], res: 1 };
  coarse.packed = [[A.pack(Float32Array.from([1]))], [A.pack(Float32Array.from([3]))]];
  coarse.idle = () => {};
  assert.equal(coarse.gridAt(0).fine, undefined);
  coarse.fine = { fineAt: (pos) => (pos < 1 ? { tag: pos } : null) };
  assert.deepEqual(coarse.gridAt(0.5).fine, { tag: 0.5 });
  assert.equal(coarse.gridAt(1).fine, undefined);
});

/** Frames of one-point pictures at 0, 3, 6 and 9 h, those of `have` in,
    loaded when done. */
function smallFrames(have, done) {
  const f = Object.create(A.Frames.prototype);
  f.field = A.FIELDS.temperature;
  f.times = [0, 3 * H, 6 * H, 9 * H];
  f.meta = { lats: [], lons: [], res: 1 };
  f.packed = f.times.map((t, i) => (have.includes(i) ? [A.pack(Float32Array.from([i * 10]))] : null));
  f.failed = f.times.map(() => false);
  f.idle = () => {};
  f.done = done;
  return f;
}

test('Frames.fineAt: full weight between two pictures in', () => {
  const g = smallFrames([0, 1, 2, 3], true).fineAt(1.5);
  assert.equal(g.fade, 1);
  assert.equal(g.mix, 0.5);
});

test('Frames.fineAt: fades out toward a picture it will never have, in toward the first it has', () => {
  const f = smallFrames([1, 2], true);
  const out = f.fineAt(2.25);
  assert.equal(out.values[0], 20);           // picture 2 held
  assert.equal(out.fade, 0.75);
  assert.equal(f.fineAt(2).fade, 1);
  assert.equal(f.fineAt(3), null);
  const into = f.fineAt(0.5);
  assert.equal(into.values[0], 10);          // picture 1 ahead
  assert.equal(into.fade, 0.5);
});

test('Frames.fineAt: a picture still loading is waited for at full weight', () => {
  const g = smallFrames([1, 2], false).fineAt(2.25);
  assert.equal(g.fade, 1);
  assert.equal(smallFrames([1, 2], false).fineAt(0.5), null);
});
