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
  assert.deepEqual(R.framesOf(cat, 'radar'), radar);
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

// An adapter as glue-adapter-maplibre.js gives it, layers ready on demand.
function fakeAdapter() {
  const a = { made: [], opacity: {}, gone: [], waiting: {}, n: 0 };
  a.createFrameLayer = (url, kind, opts) => {
    const h = { sourceId: 's' + a.n, layerId: 'l' + a.n++, url, kind, anim: !!(opts && opts.anim) };
    a.made.push(h);
    a.opacity[h.layerId] = 0;
    return h;
  };
  a.onLayerReady = (h, cb) => { (a.waiting[h.layerId] = a.waiting[h.layerId] || []).push(cb); };
  a.ready = (h) => { const w = a.waiting[h.layerId] || []; delete a.waiting[h.layerId]; w.forEach((cb) => cb()); };
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

test('Overlay: other tile options make every layer again', () => {
  const { a, o } = overlay(radar.slice(0, 2));
  o.setOn(true);
  a.made.forEach((h) => a.ready(h));
  o.show(T0 * 1000);
  o.setUrl((f) => 'v' + f.time);
  assert.equal(a.gone.length, 2);
  assert.equal(a.made.length, 4);
  assert.equal(a.made[2].url, 'v' + radar[0].time);
  a.ready(a.made[2]);
  assert.deepEqual(a.shown(), [a.made[2].layerId]);   // the time shown comes back with the new tiles
});

test('Overlay: range and on/off for the time bar', () => {
  const { o } = overlay(radar);
  assert.deepEqual(o.range(), { start: T0 * 1000, end: T0 * 1000 + 180 * MIN });
  assert.equal(o.on, false);
});
