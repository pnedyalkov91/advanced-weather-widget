'use strict';
// Unit tests for glue-prepare.js: the animation frames the map gets while the
// page is hidden, so it can load before the popup opens.
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const P = require('../glue-prepare.js');

/** A window and document with a clock, timers, a message channel and native
    animation frames that the test drives by hand. */
function page(state) {
  const native = new Map(), timers = [], listeners = [];
  let nextNative = 1, clock = 1000;
  const doc = {
    visibilityState: state,
    addEventListener: (type, fn) => { if (type === 'visibilitychange') listeners.push(fn); }
  };
  const win = {
    performance: { now: () => clock },
    requestAnimationFrame: (cb) => { native.set(nextNative, cb); return nextNative++; },
    cancelAnimationFrame: (id) => { native.delete(id); },
    setTimeout: (fn, ms) => { timers.push({ at: clock + ms, fn }); return timers.length; },
    setInterval: () => 0,
    MessageChannel: function () {
      const port1 = { onmessage: null };
      this.port1 = port1;
      this.port2 = { postMessage: () => Promise.resolve().then(() => port1.onmessage && port1.onmessage({})) };
    }
  };
  return {
    win, doc, native,
    /** Runs what the native frame would run. */
    paint: (t) => { const due = [...native.values()]; native.clear(); due.forEach((cb) => cb(t)); },
    /** Moves the clock on and fires the timers that came due. */
    advance: async (ms) => {
      clock += ms;
      for (const t of timers.filter((x) => x.at <= clock)) { timers.splice(timers.indexOf(t), 1); t.fn(); }
      await settle();
    },
    show: (s) => { doc.visibilityState = s; listeners.forEach((fn) => fn()); }
  };
}
const settle = () => new Promise((r) => setTimeout(r, 0));

test('visible page: frames come from the browser', async () => {
  const p = page('visible'), prep = P.create(p.win, p.doc);
  let ran = 0;
  p.win.requestAnimationFrame(() => ran++);
  await settle();
  assert.equal(ran, 0, 'nothing before the browser paints');
  assert.equal(p.native.size, 1);
  p.paint(5);
  assert.equal(ran, 1);
  assert.equal(prep.preparing(), false);
});

test('hidden page at start: prepares, frames come without the browser', async () => {
  const p = page('hidden'), prep = P.create(p.win, p.doc);
  assert.equal(prep.preparing(), true);
  let stamp = null;
  p.win.requestAnimationFrame((t) => { stamp = t; });
  await settle();
  assert.equal(p.native.size, 0, 'the browser is not asked');
  assert.equal(stamp, 1000, 'run with the time of the frame');
});

test('hidden page: at most one frame every GAP ms', async () => {
  const p = page('hidden'); P.create(p.win, p.doc);
  const runs = [];
  const loop = () => { runs.push(p.win.performance.now()); p.win.requestAnimationFrame(loop); };
  p.win.requestAnimationFrame(loop);
  await settle();
  assert.equal(runs.length, 1);
  await p.advance(P.GAP - 1);
  assert.equal(runs.length, 1, 'too soon');
  await p.advance(1);
  assert.equal(runs.length, 2);
  assert.ok(runs[1] - runs[0] >= P.GAP);
});

test('a frame asked during a frame waits for the next one', async () => {
  const p = page('hidden'); P.create(p.win, p.doc);
  let inner = 0;
  p.win.requestAnimationFrame(() => p.win.requestAnimationFrame(() => inner++));
  await settle();
  assert.equal(inner, 0);
  await p.advance(P.GAP);
  assert.equal(inner, 1);
});

test('after end: frames wait, and go to the browser when the page shows', async () => {
  const p = page('hidden'), prep = P.create(p.win, p.doc);
  prep.end();
  assert.equal(prep.preparing(), false);
  let ran = 0;
  p.win.requestAnimationFrame(() => ran++);
  await p.advance(1000);
  assert.equal(ran, 0, 'held while hidden');
  p.show('visible');
  assert.equal(p.native.size, 1, 'handed to the browser');
  p.paint(7);
  assert.equal(ran, 1);
});

test('begin while hidden serves the frames held so far', async () => {
  const p = page('hidden'), prep = P.create(p.win, p.doc);
  prep.end();
  let ran = 0;
  p.win.requestAnimationFrame(() => ran++);
  await p.advance(1000);
  prep.begin();
  await settle();
  assert.equal(ran, 1);
});

test('a frame asked while visible is taken back when the page hides', async () => {
  // MapLibre asks once and waits: a request left with the browser would
  // never run while hidden, and the map would never ask again.
  const p = page('visible'), prep = P.create(p.win, p.doc);
  let ran = 0;
  p.win.requestAnimationFrame(() => ran++);
  p.show('hidden');
  assert.equal(p.native.size, 0, 'cancelled with the browser');
  prep.begin();
  await settle();
  assert.equal(ran, 1);
  p.paint(9);
  assert.equal(ran, 1, 'not run twice');
});

test('hiding does not start a preparation by itself', async () => {
  const p = page('visible'), prep = P.create(p.win, p.doc);
  p.show('hidden');
  assert.equal(prep.preparing(), false);
  let ran = 0;
  p.win.requestAnimationFrame(() => ran++);
  await p.advance(1000);
  assert.equal(ran, 0);
});

test('cancelAnimationFrame works on held and browser frames', async () => {
  const p = page('hidden'), prep = P.create(p.win, p.doc);
  prep.end();
  let ran = 0;
  const held = p.win.requestAnimationFrame(() => ran++);
  p.win.cancelAnimationFrame(held);
  prep.begin();
  await settle();
  assert.equal(ran, 0);
  p.show('visible');
  const shown = p.win.requestAnimationFrame(() => ran++);
  p.win.cancelAnimationFrame(shown);
  assert.equal(p.native.size, 0);
});

test('a preparation that never settles stops after LIMIT ms', async () => {
  const p = page('hidden'), prep = P.create(p.win, p.doc);
  let runs = 0;
  const loop = () => { runs++; p.win.requestAnimationFrame(loop); };
  p.win.requestAnimationFrame(loop);
  await settle();
  for (let t = 0; t < P.LIMIT; t += 1000) await p.advance(1000);
  assert.equal(prep.preparing(), false);
  const at = runs;
  await p.advance(5000);
  assert.equal(runs, at, 'no more frames');
});

test('a frame that throws does not stop the others', async () => {
  const p = page('hidden'); P.create(p.win, p.doc);
  let ran = 0;
  p.win.setTimeout = () => 0; // the error is rethrown later, out of the frame
  p.win.requestAnimationFrame(() => { throw new Error('boom'); });
  p.win.requestAnimationFrame(() => ran++);
  await settle();
  assert.equal(ran, 1);
});


/** A page whose timers the test fires, and a server whose latest image the
    test sets; reload() counts the viewer reloads asked for. */
function watched(state) {
  const p = page(state), intervals = [];
  p.win.setInterval = (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; };
  p.server = { latest: 1000, asked: 0 };
  p.reloads = 0;
  p.prep = P.create(p.win, p.doc, {
    latest: () => { p.server.asked++; return Promise.resolve(p.server.latest); },
    reload: () => { p.reloads++; }
  });
  p.tick = async () => { intervals.filter((i) => i.ms === P.REFRESH).forEach((i) => i.fn()); await settle(); };
  return p;
}

test('hidden page: a newer radar image has the viewer reload onto it', async () => {
  // The viewer keeps the image it shows when its list grows: hidden, it
  // would open on the image of login time.
  const p = watched('hidden');
  await settle();
  await p.tick();
  assert.equal(p.reloads, 0, 'same image as at load');
  p.server.latest = 1600;
  await p.tick();
  assert.equal(p.reloads, 1);
  await p.tick();
  assert.equal(p.reloads, 1, 'once per new image');
});

test('hidden page: the list is read every REFRESH ms, out of a preparation too', async () => {
  const p = watched('hidden');
  await settle();
  p.prep.end();
  const before = p.server.asked;
  p.server.latest = 1600;
  await p.tick();
  assert.equal(p.server.asked, before + 1);
  assert.equal(p.reloads, 1);
});

test('visible page: the viewer keeps its own pace', async () => {
  const p = watched('visible');
  await settle();
  const before = p.server.asked;
  p.server.latest = 1600;
  await p.tick();
  assert.equal(p.server.asked, before, 'nothing read');
  assert.equal(p.reloads, 0);
});

test('a list that cannot be read changes nothing', async () => {
  const p = watched('hidden');
  await settle();
  p.server.latest = null;
  await p.tick();
  p.server.latest = 1000;
  await p.tick();
  assert.equal(p.reloads, 0, 'the image of the load is still the latest');
});
