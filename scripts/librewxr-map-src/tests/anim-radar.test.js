/*
 * Copyright 2026 rcspam
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

'use strict';
// Unit tests for the radar and satellite images over the animation (glue-anim-radar.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const R = require('../glue-anim-radar.js');

const MIN = 60e3, H = 60 * MIN;
// Radar images every 10 min from 21:30 to 00:20 (s, as the catalog gives them).
const T0 = Date.parse('2026-11-07T21:30:00Z') / 1000;
const radar = Array.from({ length: 18 }, (_, i) => ({ time: T0 + i * 600, path: '/v2/radar/' + (T0 + i * 600) }));
const sat = Array.from({ length: 12 }, (_, i) => ({ time: T0 - 11 * 3600 + i * 3600, path: '/v2/satellite/' + (T0 - 11 * 3600 + i * 3600) }));

test('framesOf: the past radar then the nowcast, the satellite infrared', () => {
  const cat = { radar: { past: radar.slice(0, 12), nowcast: radar.slice(12) }, satellite: { infrared: sat } };
  const run = radar[11].time;
  assert.deepEqual(R.framesOf(cat, 'radar'), radar.slice(0, 12).concat(radar.slice(12).map((f) => Object.assign({}, f, { run }))));
  assert.deepEqual(R.framesOf(cat, 'satellite'), sat);
  assert.deepEqual(R.framesOf({ radar: { past: radar } }, 'satellite'), []);
  assert.deepEqual(R.framesOf(null, 'radar'), []);
});

test('rangeOf: from the first image to one gap past the last', () => {
  assert.deepEqual(R.rangeOf(radar, 10 * MIN), { start: T0 * 1000, end: T0 * 1000 + 18 * 10 * MIN });
  assert.deepEqual(R.rangeOf(sat, H), { start: (T0 - 11 * 3600) * 1000, end: T0 * 1000 + H });
  assert.equal(R.rangeOf([], H), null);
});

test('frameAt: the latest image at or before the time, inside the range only', () => {
  const t = T0 * 1000;
  assert.equal(R.frameAt(radar, t, 10 * MIN), 0);
  assert.equal(R.frameAt(radar, t + 9 * MIN, 10 * MIN), 0);
  assert.equal(R.frameAt(radar, t + 10 * MIN, 10 * MIN), 1);
  assert.equal(R.frameAt(radar, t + 175 * MIN, 10 * MIN), 17);   // the last one, until its gap is over
  assert.equal(R.frameAt(radar, t + 180 * MIN, 10 * MIN), -1);
  assert.equal(R.frameAt(radar, t - 1, 10 * MIN), -1);
  assert.equal(R.frameAt([], t, 10 * MIN), -1);
});

test('tileUrl: radar with its color, smoothing, snow and query; satellite plain', () => {
  const o = { size: 256, color: 10, smooth: true, snow: false, format: 'webp', arrows: 'light', cells: '', lightning: 'bolts' };
  assert.equal(R.tileUrl('http://x', radar[0], 'radar', o),
    'http://x/v2/radar/' + T0 + '/256/{z}/{x}/{y}/10/1_0.webp?arrows=light&lightning=bolts');
  assert.equal(R.tileUrl('http://x', radar[0], 'radar', Object.assign({}, o, { arrows: '', lightning: '' })),
    'http://x/v2/radar/' + T0 + '/256/{z}/{x}/{y}/10/1_0.webp');
  assert.equal(R.tileUrl('http://x', sat[0], 'satellite', Object.assign({}, o, { size: 512, format: 'png' })),
    'http://x' + sat[0].path + '/512/{z}/{x}/{y}/0/0_0.png');
});

test('slowFactor: the radar steps of 10 min take a third of a 3 h step each', () => {
  const range = R.rangeOf(radar, 10 * MIN);
  assert.equal(R.RADAR_SLOW, 6);
  assert.equal(R.slowFactor(range.start, range), R.RADAR_SLOW);
  assert.equal(R.slowFactor(range.end - 1, range), R.RADAR_SLOW);
  assert.equal(R.slowFactor(range.end, range), 1);
  assert.equal(R.slowFactor(range.start - 1, range), 1);
  assert.equal(R.slowFactor(range.start, null), 1);
});

test('slowFactor: an image of the radar or satellite lasts a third of a step whatever the time line\'s step', () => {
  const range = R.rangeOf(radar, 10 * MIN);
  // 3 h steps (a forecast layer on): as before.
  assert.equal(R.slowFactor(range.start, range, 3), 6);
  assert.equal(R.slowFactor(range.end, range, 3), 1);
  // The radar alone, a step of 10 min: one image a third of a step.
  assert.equal(R.slowFactor(range.start, range, 1 / 6), 1 / 3);
  // Radar and satellite alone, a step of 1 h: 6 radar images, 2 steps.
  assert.equal(R.slowFactor(range.start, range, 1), 2);
  // The satellite alone (hourly), a step of 1 h: a third of a step.
  assert.equal(R.slowFactor(range.start, null, 1), 1 / 3);
});

// An adapter as glue-adapter-maplibre.js gives it, layers ready on demand.
function fakeAdapter() {
  const a = { made: [], opacity: {}, gone: [], waiting: {}, n: 0 };
  a.createFrameLayer = (url, kind, opts) => {
    const h = { sourceId: 's' + a.n, layerId: 'l' + a.n++, url, kind, anim: !!(opts && opts.anim), tileSize: opts && opts.tileSize };
    a.made.push(h);
    a.opacity[h.layerId] = 0;
    return h;
  };
  a.onLayerReady = (h, cb) => { (a.waiting[h.layerId] = a.waiting[h.layerId] || []).push(cb); };
  a.ready = (h) => { const w = a.waiting[h.layerId] || []; delete a.waiting[h.layerId]; w.forEach((cb) => cb()); };
  // Settled on a tile error.
  a.fail = (h) => { const w = a.waiting[h.layerId] || []; delete a.waiting[h.layerId]; w.forEach((cb) => cb(false)); };
  a.setFrameOpacity = (h, v) => { a.opacity[h.layerId] = v; };
  a.destroyFrameLayer = (h) => { a.gone.push(h.layerId); delete a.opacity[h.layerId]; };
  a.raise = () => {};
  a.shown = () => Object.keys(a.opacity).filter((k) => a.opacity[k] > 0);
  return a;
}

function overlay(frames, opts) {
  const a = fakeAdapter();
  const o = new R.Overlay(a, Object.assign({ kind: 'radar', gapMs: 10 * MIN, opacity: 0.8, url: (f) => 'u' + f.time }, opts));
  o.setFrames(frames);
  return { a, o };
}

test('Overlay: off, nothing is made; on, every image is preloaded hidden', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  o.show(T0 * 1000);
  assert.equal(a.made.length, 0);
  o.setOn(true);
  assert.equal(a.made.length, 3);
  assert.ok(a.made.every((h) => h.anim && h.kind === 'radar'));
  assert.deepEqual(a.shown(), []);
});

test('Overlay: the image of the time shows once its tiles are in, the one before goes', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  o.setOn(true);
  o.show(T0 * 1000 + 12 * MIN);                     // image 1, not ready yet
  assert.deepEqual(a.shown(), []);
  a.ready(a.made[1]);
  assert.deepEqual(a.shown(), [a.made[1].layerId]);
  assert.equal(a.opacity[a.made[1].layerId], 0.8);
  a.ready(a.made[0]);
  o.show(T0 * 1000 + 1 * MIN);                      // image 0, ready: at once
  assert.deepEqual(a.shown(), [a.made[0].layerId]);
  assert.equal(o.shownTime(), T0 * 1000);
});

test('Overlay: an image that comes in after the time moved on stays hidden', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  o.setOn(true);
  a.ready(a.made[0]);
  o.show(T0 * 1000 + 12 * MIN);                     // waits for image 1
  o.show(T0 * 1000 + 1 * MIN);                      // back to 0
  a.ready(a.made[1]);
  assert.deepEqual(a.shown(), [a.made[0].layerId]);
});

test('Overlay: out of the range nothing shows; off hides it all', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000);
  assert.equal(a.shown().length, 1);
  o.show(T0 * 1000 + 31 * MIN);
  assert.deepEqual(a.shown(), []);
  assert.equal(o.shownTime(), null);
  o.show(T0 * 1000);
  o.setOn(false);
  assert.deepEqual(a.shown(), []);
  assert.equal(a.gone.length, 3);                   // their layers go with it
});

test('Overlay: the opacity applies to the image shown and to the next ones', () => {
  const { a, o } = overlay(radar.slice(0, 2));
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000);
  o.setOpacity(0.5);
  assert.equal(a.opacity[a.made[0].layerId], 0.5);
  o.show(T0 * 1000 + 10 * MIN);
  assert.equal(a.opacity[a.made[1].layerId], 0.5);
  assert.equal(a.opacity[a.made[0].layerId], 0);
});

test('Overlay: new frames keep the layers still listed, drop the others, make the new', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  o.setOn(true);
  o.setFrames(radar.slice(1, 4));
  assert.deepEqual(a.gone, [a.made[0].layerId]);
  assert.equal(a.made.length, 4);
  assert.equal(a.made[3].url, 'u' + radar[3].time);
});

test('Overlay: other tile options make every layer again, the image shown staying until its new one is in', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000 + 12 * MIN);                     // image 1 on the map
  o.setUrl((f) => 'v' + f.time);
  assert.deepEqual(a.gone.sort(), [a.made[0].layerId, a.made[2].layerId].sort());   // the hidden ones go at once
  assert.deepEqual(a.shown(), [a.made[1].layerId]);  // no blink: the old image stays
  assert.equal(o.shownTime(), radar[1].time * 1000);  // and still counts as shown
  assert.equal(a.made.length, 6);
  assert.equal(a.made[3].url, 'v' + radar[1].time);  // the image shown is made again first
  o.setOpacity(0.5);
  assert.equal(a.opacity[a.made[1].layerId], 0.5);   // the old one follows the opacity meanwhile
  a.ready(a.made[3]);
  assert.deepEqual(a.shown(), [a.made[3].layerId]);
  assert.ok(a.gone.includes(a.made[1].layerId));     // then the old one goes
});

test('Overlay: the old image goes too when the time leaves the range or the source is switched off', () => {
  const { a, o } = overlay(radar.slice(0, 2));
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000);
  o.setUrl((f) => 'v' + f.time);
  o.setOn(false);
  assert.deepEqual(a.shown(), []);
  assert.ok(a.gone.includes(a.made[0].layerId));
});

test('Overlay: range and on/off for the time bar', () => {
  const { o } = overlay(radar);
  assert.deepEqual(o.range(), { start: T0 * 1000, end: T0 * 1000 + 180 * MIN });
  assert.equal(o.on, false);
});

test('the satellite: its last image stays until the end of the radar, as it comes about an hour late', () => {
  const last = T0 * 1000, radarEnd = last + 100 * MIN;   // the last satellite image, the end of the radar's nowcast
  assert.deepEqual(R.rangeOf(sat, H, radarEnd), { start: (T0 - 11 * 3600) * 1000, end: radarEnd });
  assert.deepEqual(R.rangeOf(sat, H, last + 10 * MIN), { start: (T0 - 11 * 3600) * 1000, end: last + H });   // never shorter than its gap
  assert.equal(R.frameAt(sat, radarEnd - MIN, H, radarEnd), 11);
  assert.equal(R.frameAt(sat, radarEnd, H, radarEnd), -1);
  assert.equal(R.frameAt(sat, last - 30 * MIN, H, radarEnd), 10);   // before the last, each image keeps its hour
  let until = radarEnd;
  const { o } = overlay(sat, { kind: 'satellite', gapMs: H, until: () => until });
  assert.deepEqual(o.range(), { start: (T0 - 11 * 3600) * 1000, end: radarEnd });
  o.setOn(true);
  o.show(last + 90 * MIN);
  assert.equal(o.wanted, sat[11].path);
  until = null;                                          // no radar known: one gap, as before
  assert.deepEqual(o.range(), { start: (T0 - 11 * 3600) * 1000, end: last + H });
});

test('Overlay.lastTime: the time of the last image, where a solo view ends (both sources show there)', () => {
  const { o } = overlay(radar);
  assert.equal(o.lastTime(), (T0 + 17 * 600) * 1000);
  assert.equal(R.frameAt(radar, o.lastTime(), 10 * MIN), 17);
  assert.equal(overlay([]).o.lastTime(), null);
});

// A clock and frames of the page run by hand, for the fades.
function fadeClock() {
  const c = { t: 0, queue: [] };
  c.now = () => c.t;
  c.raf = (f) => c.queue.push(f);
  c.step = (ms) => { c.t += ms; const q = c.queue; c.queue = []; q.forEach((f) => f()); };
  return c;
}

test('Overlay: switched on, its first image fades in', () => {
  const c = fadeClock();
  const { a, o } = overlay(radar.slice(0, 2), { fadeMs: 400, now: c.now, raf: c.raf });
  o.show(T0 * 1000);
  o.setOn(true);
  c.step(200);
  assert.deepEqual(a.shown(), []);                   // nothing to fade before the tiles are in
  a.ready(a.made[0]);
  const id = a.made[0].layerId;
  c.step(0);
  assert.equal(a.opacity[id], 0);
  c.step(200);
  assert.ok(Math.abs(a.opacity[id] - 0.4) < 1e-9);  // halfway to 0.8
  c.step(200);
  assert.equal(a.opacity[id], 0.8);
  a.ready(a.made[1]);
  o.show(T0 * 1000 + 10 * MIN);                      // the next image: at once, no fade
  assert.equal(a.opacity[a.made[1].layerId], 0.8);
});

test('Overlay: switched off, it fades out, then its layers go', () => {
  const c = fadeClock();
  const { a, o } = overlay(radar.slice(0, 2), { fadeMs: 400, now: c.now, raf: c.raf });
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000);
  c.step(0); c.step(400);
  const id = a.made[0].layerId;
  assert.equal(a.opacity[id], 0.8);
  o.setOn(false);
  c.step(0); c.step(200);
  assert.ok(Math.abs(a.opacity[id] - 0.4) < 1e-9);
  assert.equal(a.gone.length, 0);
  c.step(200);
  assert.equal(a.gone.length, 2);
  assert.deepEqual(a.shown(), []);
});

test('Overlay: switched on again while it fades out, it comes back from where it is', () => {
  const c = fadeClock();
  const { a, o } = overlay(radar.slice(0, 2), { fadeMs: 400, now: c.now, raf: c.raf });
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000);
  c.step(0); c.step(400);
  o.setOn(false);
  c.step(0); c.step(300);
  o.setOn(true);
  c.step(0); c.step(400);
  assert.equal(a.gone.length, 0);                    // the layers stayed
  assert.equal(a.opacity[a.made[0].layerId], 0.8);
});

test('Overlay: switched on out of its range, the image that comes in later is not faded', () => {
  const c = fadeClock();
  const { a, o } = overlay(radar.slice(0, 2), { fadeMs: 400, now: c.now, raf: c.raf });
  o.show(T0 * 1000 - H);
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000);
  assert.equal(a.opacity[a.made[0].layerId], 0.8);
});

// The step buttons over a forecast animation: the radar's 10 min or the
// satellite's hour where they are on, the files' 3 h elsewhere.
test('stepTime: the source finer than the step where the time is', () => {
  const r = { start: 12 * H, end: 15 * H, last: 15 * H - 10 * MIN, gap: 10 * MIN };
  const s = { start: 3 * H, end: 15 * H, last: 14 * H, gap: H };
  // In the radar: 10 min on its grid, both ways.
  assert.equal(R.stepTime(13 * H, 1, 16 * H, [r, s]), 13 * H + 10 * MIN);
  assert.equal(R.stepTime(13 * H + 5 * MIN, -1, 10 * H, [r, s]), 13 * H);
  // Back from the radar's first image: the satellite's hour.
  assert.equal(R.stepTime(12 * H, -1, 9 * H, [r, s]), 11 * H);
  // In the satellite only: an hour.
  assert.equal(R.stepTime(6 * H, 1, 9 * H, [r, s]), 7 * H);
  // The satellite off: 3 h, stopping on the radar's first image.
  assert.equal(R.stepTime(6 * H, 1, 9 * H, [r]), 9 * H);
  assert.equal(R.stepTime(10 * H, 1, 13 * H, [r]), 12 * H);
  // Back into the radar from after it: its last image.
  assert.equal(R.stepTime(17 * H, -1, 14 * H, [r]), 15 * H - 10 * MIN);
  // Out of every range and no edge on the way: the files' step.
  assert.equal(R.stepTime(18 * H, 1, 21 * H, [r, s]), 21 * H);
  // Nothing on: the files' step.
  assert.equal(R.stepTime(13 * H, 1, 15 * H, []), 15 * H);
  // An hour of the satellite stops on the radar's first or last image too.
  const r2 = { start: 13 * H + 50 * MIN, end: 17 * H, last: 16 * H + 50 * MIN, gap: 10 * MIN };
  assert.equal(R.stepTime(13 * H, 1, 16 * H, [r2, s]), 13 * H + 50 * MIN);
  const s2 = { start: 3 * H, end: 20 * H, last: 19 * H, gap: H };
  assert.equal(R.stepTime(18 * H, -1, 15 * H, [r2, s2]), 17 * H);
  assert.equal(R.stepTime(17 * H, -1, 15 * H, [r2, s2]), 16 * H + 50 * MIN);
});

test('stepHours: the step of each button where the time is', () => {
  const r = { start: 12 * H, end: 15 * H, last: 15 * H - 10 * MIN, gap: 10 * MIN };
  const s = { start: 3 * H, end: 15 * H, last: 14 * H, gap: H };
  assert.equal(R.stepHours(13 * H, 1, 3, [r, s]), 1 / 6);
  assert.equal(R.stepHours(12 * H, -1, 3, [r, s]), 1);
  assert.equal(R.stepHours(12 * H, 1, 3, [r, s]), 1 / 6);
  assert.equal(R.stepHours(20 * H, 1, 3, [r, s]), 3);
  assert.equal(R.stepHours(13 * H, 1, 1 / 6, [r, s]), 1 / 6);
});

// After a zoom, an image settled long ago has no tiles at the new scale yet.
function zoomedAdapter(a) {
  a.loaded = {};
  a.frameLoaded = (h) => a.loaded[h.layerId] !== false;
  return a;
}

test('Overlay: after a zoom, an image without its tiles waits for them, the one before staying', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  zoomedAdapter(a);
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000);
  a.loaded[a.made[1].layerId] = false;               // the map zoomed out
  assert.equal(o.loadedAt(T0 * 1000 + 12 * MIN), false);
  o.show(T0 * 1000 + 12 * MIN);
  assert.deepEqual(a.shown(), [a.made[0].layerId]);  // no hole: image 0 stays
  assert.equal((a.waiting[a.made[1].layerId] || []).length, 1, 'waited for once, not twice');
  a.loaded[a.made[1].layerId] = true;
  a.ready(a.made[1]);
  assert.deepEqual(a.shown(), [a.made[1].layerId]);
  assert.equal(o.loadedAt(T0 * 1000 + 12 * MIN), true);
});

test('Overlay: an image whose tiles failed (no network yet after a sleep) is made again when asked again', () => {
  const clock = { t: 0 };
  const { a, o } = overlay(radar.slice(0, 3), { now: () => clock.t });
  o.setOn(true);
  o.show(T0 * 1000);
  const first = a.made[0];
  a.fail(first);
  assert.deepEqual(a.shown(), [first.layerId], 'put all the same: the play never hangs on it');
  // Asked again at once: not yet, a failing server is not hammered.
  const n0 = a.made.length;
  o.show(T0 * 1000 + MIN);
  assert.equal(a.made.length, n0);
  // A few seconds later (back to now, the cursor left on it): made again.
  clock.t = 5000;
  o.show(T0 * 1000 + 2 * MIN);
  assert.ok(a.gone.includes(first.layerId), 'the empty layer goes');
  const again = a.made[a.made.length - 1];
  assert.equal(again.url, first.url);
  a.ready(again);
  assert.deepEqual(a.shown(), [again.layerId]);
  // In now: asked again, nothing is made.
  const n = a.made.length;
  clock.t = 60000;
  o.show(T0 * 1000);
  assert.equal(a.made.length, n);
});

test('Overlay: an image failing again and again is tried three times, then again at the next catalog', () => {
  const clock = { t: 0 };
  const { a, o } = overlay(radar.slice(0, 3), { now: () => clock.t });
  o.setOn(true);
  const last = () => a.made[a.made.length - 1];
  o.show(T0 * 1000);
  a.fail(a.made[0]);
  for (let k = 0; k < 2; k++) {
    clock.t += 10000;
    o.show(T0 * 1000);
    a.fail(last());
  }
  const n = a.made.length;
  assert.equal(n, 5, 'three tries of image 0, and images 1 and 2');
  clock.t += 10000;
  o.show(T0 * 1000);
  assert.equal(a.made.length, n, 'given up: the play does not ask for it on every pass');
  o.setFrames(radar.slice(0, 3));
  assert.equal(a.made.length, n + 1, 'a new catalog: one more chance');
  assert.equal(last().url, 'u' + radar[0].time);
});

test('Overlay: a new catalog makes the failed images again, the image shown kept', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  o.setOn(true);
  o.show(T0 * 1000 + 12 * MIN);
  a.ready(a.made[1]);
  a.fail(a.made[2]);
  const n = a.made.length;
  o.setFrames(radar.slice(0, 4));
  assert.ok(a.gone.includes(a.made[2].layerId));
  const urls = a.made.slice(n).map((h) => h.url);
  assert.deepEqual(urls.sort(), ['u' + radar[2].time, 'u' + radar[3].time].sort());
  assert.deepEqual(a.shown(), [a.made[1].layerId], 'the image shown, fine, stays');
});

test('Overlay: loadedAt is true out of the range or off, so the play never waits there', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  zoomedAdapter(a);
  assert.equal(o.loadedAt(T0 * 1000), true);         // off
  o.setOn(true);
  assert.equal(o.loadedAt(T0 * 1000 - MIN), true);   // before the range
  assert.equal(o.loadedAt(T0 * 1000), false);        // not settled yet
});

test('tileSizes: 512 px files on a 512 grid, a 256 grid on HiDPI for sharpness; 256 asked stays 256', () => {
  assert.deepEqual(R.tileSizes('auto', 1), { size: 512, grid: 512 });
  assert.deepEqual(R.tileSizes('auto', 1.15), { size: 512, grid: 512 });
  assert.deepEqual(R.tileSizes('auto', 1.5), { size: 512, grid: 256 });
  assert.deepEqual(R.tileSizes('512', 1), { size: 512, grid: 512 });
  assert.deepEqual(R.tileSizes('512', 2), { size: 512, grid: 256 });
  assert.deepEqual(R.tileSizes('256', 1), { size: 256, grid: 256 });
  assert.deepEqual(R.tileSizes('256', 2), { size: 256, grid: 256 });
  assert.deepEqual(R.tileSizes('nonsense', 1), { size: 256, grid: 256 });
});

test('Overlay: its images are made on its grid, the new one after other tile options', () => {
  const { a, o } = overlay(radar.slice(0, 2), { tileSize: 512 });
  o.setOn(true);
  assert.deepEqual(a.made.map((h) => h.tileSize), [512, 512]);
  o.setUrl((f) => 'v' + f.time, 256);
  assert.deepEqual(a.made.slice(2).map((h) => h.tileSize), [256, 256]);
});

// A WebSocket stand-in: listeners by type, fire(type, event) calls them.
function fakeSocketClass() {
  function FakeSocket(url) {
    this.url = url;
    this.handlers = {};
    FakeSocket.made.push(this);
  }
  FakeSocket.made = [];
  FakeSocket.OPEN = 1;
  FakeSocket.prototype.addEventListener = function (type, fn) { (this.handlers[type] = this.handlers[type] || []).push(fn); };
  FakeSocket.prototype.fire = function (type, ev) { (this.handlers[type] || []).forEach((fn) => fn(ev || {})); };
  return FakeSocket;
}

test('watchPush: the viewer socket hands its catalogs to the page', () => {
  const win = { WebSocket: fakeSocketClass() };
  const got = [];
  const push = R.watchPush(win, (c) => got.push(c));
  const s = new win.WebSocket('wss://api.example/v2/ws?topics=weather-maps');
  assert.ok(s instanceof win.WebSocket, 'still a WebSocket for the viewer');
  assert.equal(win.WebSocket.OPEN, 1, 'constants kept');
  assert.equal(push.open(), false);
  s.fire('open');
  assert.equal(push.open(), true);
  s.fire('message', { data: JSON.stringify({ type: 'hello', available: ['weather-maps'] }) });
  s.fire('message', { data: JSON.stringify({ type: 'snapshot', topic: 'weather-maps', data: { a: 1 } }) });
  s.fire('message', { data: JSON.stringify({ type: 'update', topic: 'lightning', data: { b: 2 } }) });
  s.fire('message', { data: 'not json' });
  s.fire('message', { data: JSON.stringify({ type: 'update', topic: 'weather-maps', data: { a: 2 } }) });
  assert.deepEqual(got, [{ a: 1 }, { a: 2 }]);
  s.fire('close');
  assert.equal(push.open(), false);
});

test('watchPush: other sockets and a socket that never opened are left alone', () => {
  const win = { WebSocket: fakeSocketClass() };
  const got = [];
  const push = R.watchPush(win, (c) => got.push(c));
  const other = new win.WebSocket('wss://elsewhere/feed');
  other.fire('open');
  other.fire('message', { data: JSON.stringify({ type: 'snapshot', topic: 'weather-maps', data: {} }) });
  assert.equal(push.open(), false);
  assert.deepEqual(got, []);
  const dead = new win.WebSocket('ws://localhost:8099/v2/ws?topics=weather-maps');
  dead.fire('close');
  assert.equal(push.open(), false);
});

test('watchPush: no WebSocket in the page, never open', () => {
  const push = R.watchPush({}, () => {});
  assert.equal(push.open(), false);
  push.drop();
});

test('watchPush.drop: an open socket (dead after a sleep) is closed and no longer counts', () => {
  const win = { WebSocket: fakeSocketClass() };
  win.WebSocket.prototype.close = function () { this.closed = (this.closed || 0) + 1; };
  const push = R.watchPush(win, () => {});
  const s = new win.WebSocket('wss://api.example/v2/ws?topics=weather-maps');
  const never = new win.WebSocket('wss://api.example/v2/ws?topics=weather-maps');
  s.fire('open');
  assert.equal(push.open(), true);
  push.drop();
  assert.equal(push.open(), false, 'the page polls again at once');
  assert.equal(s.closed, 1, 'closed, so the viewer opens a new one');
  assert.equal(never.closed, undefined, 'a socket never opened is left to itself');
  // Its close event, late, counts nothing twice; a new socket counts again.
  s.fire('close');
  assert.equal(push.open(), false);
  const again = new win.WebSocket('wss://api.example/v2/ws?topics=weather-maps');
  again.fire('open');
  assert.equal(push.open(), true);
  push.drop();
  push.drop();
  assert.equal(again.closed, 1);
});

test('lastPast: the last observed radar image, never the nowcast', () => {
  const cat = { radar: { past: radar.slice(0, 12), nowcast: radar.slice(12) } };
  assert.equal(R.lastPast(cat), radar[11].time * 1000);
  assert.equal(R.lastPast({ radar: { past: [] } }), null);
  assert.equal(R.lastPast(null), null);
});

test('nowTime: with lightning and the radar on, now is the last observed image', () => {
  const nowStep = Date.parse('2026-11-12T12:00:00Z'), last = Date.parse('2026-11-12T13:10:00Z');
  assert.equal(R.nowTime({ lightning: true, radar: true, nowStep, lastPast: last }), last);
  // Lightning off, the radar off, or no image: the step of now.
  assert.equal(R.nowTime({ lightning: false, radar: true, nowStep, lastPast: last }), nowStep);
  assert.equal(R.nowTime({ lightning: true, radar: false, nowStep, lastPast: last }), nowStep);
  assert.equal(R.nowTime({ lightning: true, radar: true, nowStep, lastPast: null }), nowStep);
});

test('Overlay.progress: null off; on, the images whose tiles are in, out of all', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  assert.equal(o.progress(), null);
  zoomedAdapter(a);
  o.setOn(true);
  a.made.forEach((h) => { a.loaded[h.layerId] = false; });
  assert.deepEqual(o.progress(), { done: 0, total: 3 });
  a.loaded[a.made[0].layerId] = true;
  a.loaded[a.made[2].layerId] = true;
  assert.deepEqual(o.progress(), { done: 2, total: 3 });
});

test('Overlay.progress: counted as the map says for the loading bar (frameCounted) when it can', () => {
  const { a, o } = overlay(radar.slice(0, 3));
  zoomedAdapter(a);
  a.counted = {};
  a.frameCounted = (h) => a.counted[h.layerId] !== false;
  o.setOn(true);
  a.made.forEach((h) => { a.loaded[h.layerId] = false; });
  a.counted[a.made[1].layerId] = false;
  assert.deepEqual(o.progress(), { done: 2, total: 3 }, 'held back in a move, loaded before: not a download');
});

test('framesOf: the nowcast images carry the run they come from (the last observed image)', () => {
  const c = { radar: { past: [{ time: 100, path: '/p/100' }, { time: 700, path: '/p/700' }], nowcast: [{ time: 1300, path: '/p/1300' }] } };
  const f = R.framesOf(c, 'radar');
  assert.equal(f[0].run, undefined);
  assert.equal(f[2].path, '/p/1300');
  assert.equal(f[2].run, 700);
});

test('Overlay: a nowcast image made again with each new run, and once observed; the past kept', () => {
  const cat = (past, nowcast) => R.framesOf({ radar: { past: past.map((t) => ({ time: t, path: '/p/' + t })), nowcast: nowcast.map((t) => ({ time: t, path: '/p/' + t })) } }, 'radar');
  const { a, o } = overlay(cat([0, 600], [1200, 1800]));
  o.setOn(true);
  const first = a.made.map((h) => h.layerId);
  assert.equal(a.made.length, 4);
  // A new run: 1200 observed now, 1800 forecast again from it, 2400 new.
  o.setFrames(cat([0, 600, 1200], [1800, 2400]));
  assert.deepEqual(a.gone.sort(), [first[2], first[3]].sort());
  assert.equal(a.made.length, 7);
  // The same catalog again: nothing made again.
  o.setFrames(cat([0, 600, 1200], [1800, 2400]));
  assert.equal(a.made.length, 7);
});

test('nativeZoom: radar and satellite tiles stop where a file pixel gets finer than the data', () => {
  const base = 'http://localhost:8099/v2/radar/1763400000/';
  // 256 files: level 9 at most, 512 files one level less (same pixel on the ground).
  assert.equal(R.nativeZoom(base + '256/{z}/{x}/{y}/2/1_1.webp', 12), 9);
  assert.equal(R.nativeZoom(base + '512/{z}/{x}/{y}/2/1_1.webp', 12), 8);
  assert.equal(R.nativeZoom('http://localhost:8099/v2/satellite/1763400000/256/{z}/{x}/{y}/0/0_0.webp', 12), 9);
  // Never above the map's own last level.
  assert.equal(R.nativeZoom(base + '256/{z}/{x}/{y}/2/1_1.webp', 7), 7);
  // Lightning, arrows and cells are stretched with the rest (tried for now).
  assert.equal(R.nativeZoom(base + '256/{z}/{x}/{y}/2/1_1.webp?lightning=bolts', 12), 9);
  assert.equal(R.nativeZoom(base + '256/{z}/{x}/{y}/2/1_1.webp?arrows=dark&cells=light', 12), 9);
  // An address of another shape keeps the map's level.
  assert.equal(R.nativeZoom('https://example.org/tiles/{z}/{x}/{y}.png', 12), 12);
});

test('sharpEdges: a radar tile without smoothing keeps its cells square when stretched', () => {
  const base = 'http://localhost:8099/v2/radar/1763400000/256/{z}/{x}/{y}/';
  assert.equal(R.sharpEdges(base + '2/0_1.webp', 'radar'), true);
  assert.equal(R.sharpEdges(base + '2/0_0.png?lightning=bolts', 'radar'), true);
  assert.equal(R.sharpEdges(base + '2/1_1.webp', 'radar'), false);
  assert.equal(R.sharpEdges('http://localhost:8099/v2/satellite/1763400000/256/{z}/{x}/{y}/0/0_0.webp', 'satellite'), false);
});
