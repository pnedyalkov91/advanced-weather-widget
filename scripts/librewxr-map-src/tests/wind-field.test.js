'use strict';
// Unit tests for the pure math of the radar wind layer (glue-wind.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const { WindField } = require('../glue-wind.js');

const close = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);

test('toUV: meteorological direction is where the wind comes from', () => {
  let r = WindField.toUV(10, 0);   // north wind blows toward the south
  close(r.u, 0); close(r.v, -10);
  r = WindField.toUV(10, 270);     // west wind blows toward the east
  close(r.u, 10); close(r.v, 0);
  r = WindField.toUV(10, 180);
  close(r.u, 0); close(r.v, 10);
  r = WindField.toUV(10, 90);
  close(r.u, -10); close(r.v, 0);
});

const wrap = (x) => ((x + 180) % 360 + 360) % 360 - 180;
const yOfLat = (lat) => Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360));
const latOfY = (y) => (2 * Math.atan(Math.exp(y)) - Math.PI / 2) * 180 / Math.PI;

/** Grid points of a spec inside a lat/lon box, longitudes wrapped, as 'lat,lon' strings. */
function pointsIn(spec, box) {
  const out = new Set();
  for (const la of spec.lats) {
    for (const lo of spec.lons) {
      const w = wrap(lo);
      if (la >= box.south && la <= box.north && w >= box.west && w <= box.east) out.add(la.toFixed(3) + ',' + w.toFixed(3));
    }
  }
  return out;
}

test('gridSpec: two pans of the same view put Alaska on the same grid points', () => {
  // The two screenshots: same zoom and size, Alaska on the left edge, then
  // past +180 on the right edge. The wind there must come from the same points.
  const westPan = WindField.gridSpec({ west: -150, east: 75, south: -58, north: 80 });
  const eastPan = WindField.gridSpec({ west: -28, east: 197, south: -58, north: 80 });
  const alaska = { west: -170, east: -140, south: 50, north: 75 };
  const a = pointsIn(westPan, alaska), b = pointsIn(eastPan, alaska);
  assert.ok(a.size >= 2, [...a].join(' '));
  assert.deepEqual([...b].sort(), [...a].sort());
});

test('gridSpec: a vertical pan keeps the same meridians and parallels', () => {
  // Same zoom and size: the Mercator height of the view does not change.
  const h = yOfLat(55) - yOfLat(35);
  const low = WindField.gridSpec({ west: 0, east: 40, south: 35, north: latOfY(yOfLat(35) + h) });
  const high = WindField.gridSpec({ west: 0, east: 40, south: 45, north: latOfY(yOfLat(45) + h) });
  assert.deepEqual(high.lons, low.lons);
  const shared = (spec, other) => spec.lats.filter((x) => x >= other.south && x <= other.north);
  assert.ok(shared(low, high).length >= 2);
  assert.deepEqual(shared(low, high), shared(high, low));
});

test('gridSpec: at most 12 x 12 points, regular, covering the widened view or a full turn', () => {
  const views = [
    { west: -150, east: 75, south: -58, north: 80 },      // whole world
    { west: -28, east: 197, south: -58, north: 80 },
    { west: 0, east: 20, south: -30, north: 30 },         // tall view on the equator
    { west: -10, east: 30, south: 38, north: 58 },        // Europe
    { west: 6.3, south: 47.85, east: 6.8, north: 48.2 },  // ~37 km
    { west: 6.55, south: 48.0, east: 6.56, north: 48.005 } // far in
  ];
  for (const b of views) {
    const s = WindField.gridSpec(b);
    const tag = JSON.stringify(b);
    assert.ok(s.lats.length >= 2 && s.lats.length <= 12, tag + ' rows ' + s.lats.length);
    assert.ok(s.lons.length >= 2 && s.lons.length <= 12, tag + ' cols ' + s.lons.length);
    // The widened view, or one full turn that sample() repeats around the world.
    const covers = s.west <= b.west - 0.3 * (b.east - b.west) + 1e-9 && s.east >= b.east + 0.3 * (b.east - b.west) - 1e-9;
    assert.ok(covers || Math.abs(s.east - s.west - 360) < 1e-6, tag);
    assert.ok(s.north >= Math.min(85.05, b.north) && s.south <= Math.max(-85.05, b.south), tag);
    assert.ok(s.north <= 90 && s.south >= -90, tag);
    close(s.lats[0], s.north, 1e-4); close(s.lons[0], s.west, 1e-4);
    for (let i = 1; i < s.lats.length; i++) close(s.lats[i - 1] - s.lats[i], s.lats[0] - s.lats[1], 1e-3);
    for (let j = 1; j < s.lons.length; j++) close(s.lons[j] - s.lons[j - 1], s.lons[1] - s.lons[0], 1e-3);
  }
});

test('gridSpec: zoomed out past a full turn, one turn of the lattice at the usual step', () => {
  // 970 px wide popup: zoom 2 shows 341 degrees, zoom 0.5 almost three worlds.
  const world = WindField.gridSpec({ west: -110, east: 130, south: -60, north: 75 });
  for (const z of [2, 1, 0.5]) {
    const w = 970 / (256 * 2 ** z) * 360;
    const s = WindField.gridSpec({ west: 10 - w / 2, east: 10 + w / 2, south: -60, north: 75 });
    assert.equal(s.lonStep, world.lonStep, 'zoom ' + z);
    close(s.east - s.west, 360, 1e-6);
    assert.ok(s.lons.length <= 12, 'zoom ' + z + ' cols ' + s.lons.length);
  }
});

test('gridSpec: zoomed far in, still at least 5 points per side', () => {
  const s = WindField.gridSpec({ west: 6.55, south: 48.0, east: 6.56, north: 48.005 });
  assert.ok(s.lons.length >= 5, 'cols ' + s.lons.length);
  assert.ok(s.lats.length >= 5, 'rows ' + s.lats.length);
});

test('pointLists: rows x cols coordinates, row-major, longitudes wrapped into -180..180', () => {
  const pl = WindField.pointLists({ lats: [60, 50], lons: [170, 190, 210] });
  assert.equal(pl.latitude, '60,60,60,50,50,50');
  assert.equal(pl.longitude, '170,-170,-150,170,-170,-150');
});

test('buildGrid + sample: a grid with more columns than rows', () => {
  const spec = { lats: [48.1, 48.0], lons: [6.5, 6.6, 6.7] };
  const mk = (u) => ({ elevation: 0, hourly: { time: [1000], wind_speed_10m: [u], wind_direction_10m: [270] } });
  const g = WindField.buildGrid(spec, [1, 2, 3, 4, 5, 6].map(mk));
  const tw = { i: 0, frac: 0 };
  close(WindField.sample(g, 48.1, 6.7, tw, NaN, 0).u, 3);
  close(WindField.sample(g, 48.0, 6.5, tw, NaN, 0).u, 4);
  close(WindField.sample(g, 48.05, 6.65, tw, NaN, 0).u, 4);   // (2 + 3 + 5 + 6) / 4
  assert.equal(WindField.sample(g, 48.05, 6.75, tw, NaN, 0), null);
});

test('pointLists: n*n coordinates, row-major (lat rows, lon columns)', () => {
  const spec = { n: 2, lats: [48.1, 48.0], lons: [6.5, 6.6] };
  const pl = WindField.pointLists(spec);
  assert.equal(pl.latitude, '48.1,48.1,48,48');
  assert.equal(pl.longitude, '6.5,6.6,6.5,6.6');
});

test('pointLists: longitudes past the antimeridian are wrapped into -180..180 for Open-Meteo', () => {
  // Zoomed out on the whole world, the one-turn box starts west of -180.
  const spec = WindField.gridSpec({ west: -200, east: 160, south: -70, north: 80 });
  assert.ok(spec.west < -180, 'the spec itself stays unwrapped');
  const lons = WindField.pointLists(spec).longitude.split(',').map(Number);
  assert.ok(lons.every((x) => x >= -180 && x < 180), lons.join(','));
  assert.equal(lons[0], 36);   // -324 is the same meridian as 36
});

test('timeWeights: hour index and fraction, clamped at both ends', () => {
  const t = [0, 3600, 7200];
  assert.deepEqual(WindField.timeWeights(t, 1800), { i: 0, frac: 0.5 });
  assert.deepEqual(WindField.timeWeights(t, 5400), { i: 1, frac: 0.5 });
  assert.deepEqual(WindField.timeWeights(t, 9000), { i: 2, frac: 0 });
  assert.deepEqual(WindField.timeWeights(t, -10), { i: 0, frac: 0 });
});

function twoByTwo(uNW, uNE, uSW, uSE, elev) {
  // One hour, v = 0 everywhere, u per corner; elevation optional.
  const spec = { n: 2, lats: [48.1, 48.0], lons: [6.5, 6.6] };
  const mk = (u, e) => ({ elevation: e, hourly: { time: [1000], wind_speed_10m: [Math.abs(u)], wind_direction_10m: [u >= 0 ? 270 : 90] } });
  const el = elev || [0, 0, 0, 0];
  return WindField.buildGrid(spec, [mk(uNW, el[0]), mk(uNE, el[1]), mk(uSW, el[2]), mk(uSE, el[3])]);
}

test('buildGrid + sample: corners are exact, centre is the bilinear mean, outside is null', () => {
  const g = twoByTwo(1, 3, 5, 7);
  const tw = { i: 0, frac: 0 };
  close(WindField.sample(g, 48.1, 6.5, tw, NaN, 0).u, 1);
  close(WindField.sample(g, 48.1, 6.6, tw, NaN, 0).u, 3);
  close(WindField.sample(g, 48.0, 6.5, tw, NaN, 0).u, 5);
  close(WindField.sample(g, 48.0, 6.6, tw, NaN, 0).u, 7);
  close(WindField.sample(g, 48.05, 6.55, tw, NaN, 0).u, 4);
  assert.equal(WindField.sample(g, 48.2, 6.55, tw, NaN, 0), null);
  assert.equal(WindField.sample(g, 48.05, 6.7, tw, NaN, 0), null);
});

test('sample: time blending between two hours', () => {
  const g = twoByTwo(2, 2, 2, 2);
  g.times = [1000, 4600];
  g.u.push(new Float32Array([6, 6, 6, 6]));
  g.v.push(new Float32Array([0, 0, 0, 0]));
  close(WindField.sample(g, 48.05, 6.55, { i: 0, frac: 0.5 }, NaN, 0).u, 4);
});

test('sample: elevation weighting favours grid points at the particle altitude', () => {
  // West column in a valley (400 m, u = 1), east column on a ridge (900 m, u = 10).
  const g = twoByTwo(1, 10, 1, 10, [400, 900, 400, 900]);
  const tw = { i: 0, frac: 0 };
  const plain = WindField.sample(g, 48.05, 6.55, tw, NaN, 0).u;
  close(plain, 5.5);
  const valley = WindField.sample(g, 48.05, 6.55, tw, 400, 250).u;
  assert.ok(valley < 2, `valley particle should follow the valley wind, got ${valley}`);
  const ridge = WindField.sample(g, 48.05, 6.55, tw, 900, 250).u;
  assert.ok(ridge > 9, `ridge particle should follow the ridge wind, got ${ridge}`);
});

test('buildGrid + sample: the 700 hPa level is built alongside 10 m and selected by name', () => {
  const spec = { n: 2, lats: [48.1, 48.0], lons: [6.5, 6.6] };
  const mk = () => ({ elevation: 0, hourly: { time: [1000], wind_speed_10m: [1], wind_direction_10m: [270], wind_speed_700hPa: [9], wind_direction_700hPa: [180] } });
  const g = WindField.buildGrid(spec, [mk(), mk(), mk(), mk()]);
  const tw = { i: 0, frac: 0 };
  close(WindField.sample(g, 48.05, 6.55, tw, NaN, 0).u, 1);
  close(WindField.sample(g, 48.05, 6.55, tw, NaN, 0, '10m').u, 1);
  const aloft = WindField.sample(g, 48.05, 6.55, tw, NaN, 0, '700hPa');
  close(aloft.u, 0); close(aloft.v, 9);
  // Unknown level or a grid without that level falls back to 10 m.
  close(WindField.sample(g, 48.05, 6.55, tw, NaN, 0, '500hPa').u, 1);
  const old = WindField.buildGrid(spec, [mk(), mk(), mk(), mk()].map(p => ({ elevation: 0, hourly: { time: [1000], wind_speed_10m: [1], wind_direction_10m: [270] } })));
  close(WindField.sample(old, 48.05, 6.55, tw, NaN, 0, '700hPa').u, 1);
});

test('sample: skips missing (NaN) corners', () => {
  const g = twoByTwo(1, 3, 5, 7);
  g.u[0][1] = NaN; g.v[0][1] = NaN;
  const r = WindField.sample(g, 48.1, 6.55, { i: 0, frac: 0 }, NaN, 0);
  close(r.u, 1); // only the NW corner remains on the north edge
});

test('needsFetch: null, stale, zoom change, out of box', () => {
  const spec = { west: 6.0, south: 47.8, east: 7.0, north: 48.3, lonStep: 0.1, latStep: 0.05 };
  const cached = { spec, grid: {}, zoom: 10, fetchedAt: 1000 };
  const inside = { bounds: { west: 6.2, south: 47.9, east: 6.8, north: 48.2 }, zoom: 10 };
  assert.equal(WindField.needsFetch(inside, null, 2000, 3600000), true);
  assert.equal(WindField.needsFetch(inside, cached, 2000, 3600000), false);
  assert.equal(WindField.needsFetch(inside, cached, 1000 + 3600001, 3600000), true);
  assert.equal(WindField.needsFetch({ bounds: inside.bounds, zoom: 11 }, cached, 2000, 3600000), true);
  assert.equal(WindField.needsFetch({ bounds: { west: 5.9, south: 47.9, east: 6.8, north: 48.2 }, zoom: 10 }, cached, 2000, 3600000), true);
});

test('needsFetch: a stored grid from before the fixed lattice is fetched again', () => {
  const spec = { west: 6.0, south: 47.8, east: 7.0, north: 48.3, n: 12 };
  const view = { bounds: { west: 6.2, south: 47.9, east: 6.8, north: 48.2 }, zoom: 10 };
  assert.equal(WindField.needsFetch(view, { spec, grid: {}, zoom: 10, fetchedAt: 1000 }, 2000, 3600000), true);
});

const WEST_PAN = { west: -150, east: 75, south: -58, north: 80 };   // the two screenshots
const EAST_PAN = { west: -28, east: 197, south: -58, north: 80 };

test('needsFetch: a grid spanning a full turn serves any east-west pan', () => {
  const spec = WindField.gridSpec(WEST_PAN);
  assert.ok(spec.east - spec.west >= 360, 'world view: the box spans a full turn');
  const cached = { spec, grid: {}, zoom: 2.5, fetchedAt: 1000 };
  assert.equal(WindField.needsFetch({ bounds: EAST_PAN, zoom: 2.5 }, cached, 2000, 3600000), false);
});

test('needsFetch: the same view on the next copy of the world needs no fetch', () => {
  const b = { west: 6.2, south: 47.9, east: 6.8, north: 48.2 };
  const spec = WindField.gridSpec(b);
  const cached = { spec, grid: {}, zoom: 10, fetchedAt: 1000 };
  const shifted = { west: b.west + 360, south: b.south, east: b.east + 360, north: b.north };
  assert.equal(WindField.needsFetch({ bounds: shifted, zoom: 10 }, cached, 2000, 3600000), false);
  const back = { west: b.west - 720, south: b.south, east: b.east - 720, north: b.north };
  assert.equal(WindField.needsFetch({ bounds: back, zoom: 10 }, cached, 2000, 3600000), false);
});

test('coverage: a grid spanning a full turn covers any east-west pan', () => {
  close(WindField.coverage(EAST_PAN, WindField.gridSpec(WEST_PAN)), 1);
  const b = { west: 6.2, south: 47.9, east: 6.8, north: 48.2 };
  close(WindField.coverage({ west: b.west + 360, south: b.south, east: b.east + 360, north: b.north }, WindField.gridSpec(b)), 1);
});

test('sample: a longitude on another copy of the world gets the same wind', () => {
  // A full-turn grid whose values depend on the wrapped longitude only, as
  // Open-Meteo answers the same meridian the same way.
  const spec = WindField.gridSpec(WEST_PAN);
  const pts = [];
  for (const la of spec.lats) {
    for (const lo of spec.lons) {
      const w = wrap(lo);
      pts.push({ elevation: 0, hourly: { time: [1000], wind_speed_10m: [5 + w / 100 + la / 1000], wind_direction_10m: [270] } });
    }
  }
  const g = WindField.buildGrid(spec, pts);
  const tw = { i: 0, frac: 0 };
  for (const lon of [-150, 150, 179, 200, 350, -300]) {
    const a = WindField.sample(g, 60, lon, tw, NaN, 0);
    const b = WindField.sample(g, 60, lon + 360, tw, NaN, 0);
    const c = WindField.sample(g, 60, lon - 360, tw, NaN, 0);
    assert.ok(a && b && c, 'lon ' + lon);
    close(b.u, a.u, 1e-4); close(c.u, a.u, 1e-4);
  }
});

test('needsFetch: the world grid serves the views of the whole world only', () => {
  const world = { spec: WindField.gridSpec(WindField.WORLD), world: true, grid: {}, zoom: null, fetchedAt: 1000 };
  const at = (b, zoom) => WindField.needsFetch({ bounds: b, zoom }, world, 2000, 3600000);
  assert.equal(at({ west: -150, east: 75, south: -58, north: 80 }, 2.5), false);
  const w = 970 / (256 * 2 ** 1) * 360;
  assert.equal(at({ west: 10 - w / 2, east: 10 + w / 2, south: -80, north: 80 }, 1), false);
  assert.equal(at({ west: 6.2, south: 47.9, east: 6.8, north: 48.2 }, 10), true);
  assert.equal(WindField.needsFetch({ bounds: { west: -150, east: 75, south: -58, north: 80 }, zoom: 2.5 }, world, 1000 + 3600001, 3600000), true, 'expired');
});

test('coverage: fraction of the view covered by a grid spec', () => {
  const spec = { west: 6.0, south: 48.0, east: 7.0, north: 49.0 };
  close(WindField.coverage({ west: 6.2, south: 48.2, east: 6.8, north: 48.8 }, spec), 1);
  close(WindField.coverage({ west: 5.0, south: 47.0, east: 7.0, north: 49.0 }, spec), 0.25);
  close(WindField.coverage({ west: 8.0, south: 48.0, east: 9.0, north: 49.0 }, spec), 0);
  close(WindField.coverage({ west: 6.0, south: 48.0, east: 7.0, north: 49.0 }, null), 0);
});

test('screenVelocity: scaled, clamped, screen y points down', () => {
  let r = WindField.screenVelocity(5, 0, { k: 3, min: 2, max: 60 });
  close(r.dx, 15); close(r.dy, 0); close(r.speed, 5);
  r = WindField.screenVelocity(0, 5, { k: 3, min: 2, max: 60 });
  close(r.dx, 0); close(r.dy, -15);
  r = WindField.screenVelocity(0.3, 0, { k: 3, min: 2, max: 60 });
  close(r.dx, 2);
  r = WindField.screenVelocity(50, 0, { k: 3, min: 2, max: 60 });
  close(r.dx, 60);
  r = WindField.screenVelocity(0, 0, { k: 3, min: 2, max: 60 });
  close(r.dx, 0); close(r.dy, 0);
});

test('worldPx / worldToLatLng: Web Mercator with 256 px tiles, round trip', () => {
  const scale = 256 * Math.pow(2, 10);
  let p = WindField.worldPx(0, 0, 10);
  close(p.x, scale / 2); close(p.y, scale / 2);
  p = WindField.worldPx(48.01754, 6.5882, 10);   // Remiremont: z10 tile 530/355, pixel 189,225
  assert.equal(Math.floor(p.x / 256), 530); assert.equal(Math.floor(p.y / 256), 355);
  assert.equal(Math.floor(p.x % 256), 189); assert.equal(Math.floor(p.y % 256), 225);
  const ll = WindField.worldToLatLng(p.x, p.y, 10);
  close(ll.lat, 48.01754, 1e-9); close(ll.lon, 6.5882, 1e-9);
});

test('terrariumMeters: (R*256 + G + B/256) - 32768', () => {
  assert.equal(WindField.terrariumMeters(0, 0, 0), -32768);
  assert.equal(WindField.terrariumMeters(128, 0, 0), 0);
  assert.equal(WindField.terrariumMeters(129, 148, 0), 404);
});

// Map rotation (leaflet-rotate): the canvas stays upright, so each screen
// pixel is mapped to the world through an affine frame taken from Leaflet's
// own conversions, and world velocities are turned back into screen ones.
test('viewFrame: identity when the map is not rotated', () => {
  const f = WindField.viewFrame({ x: 1000, y: 2000 }, { x: 1001, y: 2000 }, { x: 1000, y: 2001 });
  const w = WindField.screenToWorld(f, 10, 20);
  close(w.x, 1010); close(w.y, 2020);
  const d = WindField.worldToScreenVector(f, 3, -4);
  close(d.dx, 3); close(d.dy, -4);
});

test('viewFrame: map turned 90 degrees clockwise, screen right is world north', () => {
  // With the world turned clockwise on screen, one screen pixel to the right
  // goes one world pixel up (north), one pixel down goes one world pixel right.
  const f = WindField.viewFrame({ x: 100, y: 100 }, { x: 100, y: 99 }, { x: 101, y: 100 });
  const w = WindField.screenToWorld(f, 10, 0);
  close(w.x, 100); close(w.y, 90);
  // A wind blowing north (world dy < 0) must move the particle to the right.
  const d = WindField.worldToScreenVector(f, 0, -5);
  close(d.dx, 5); close(d.dy, 0);
  // Round trip keeps the length (pure rotation).
  const e = WindField.worldToScreenVector(f, 3, 4);
  close(Math.hypot(e.dx, e.dy), 5);
});

// Animation loop: a timer, then one rAF per frame. Restarting the layer
// (moveend, rotate...) while a rAF is still pending must not leave the old
// chain alive next to the new one, or the particles run at 2x, 3x...
test('layer loop: restart while a frame is pending keeps a single chain', () => {
  const { createWindLayer } = require('../glue-wind.js');
  const L = {
    Layer: { extend: (proto) => { function C() {} C.prototype = proto; return C; } },
    setOptions: (o, opts) => { o.options = Object.assign(Object.create(o.options || {}), opts || {}); }
  };
  const saved = { setTimeout, clearTimeout, requestAnimationFrame: global.requestAnimationFrame };
  const timers = [], rafs = [];
  global.setTimeout = (fn) => { timers.push(fn); return timers.length; };
  global.clearTimeout = (id) => { timers[id - 1] = null; };
  global.requestAnimationFrame = (fn) => { rafs.push(fn); return rafs.length; };
  try {
    const layer = new (createWindLayer(L))();
    layer.initialize(null, null, {});
    layer._settled = true;        // drawing starts once the map settled (see settle())
    let frames = 0;
    layer._frame = () => { frames++; };
    const pending = () => timers.filter(Boolean).length;
    const fire = (q) => { const fn = q.shift(); if (fn) fn(); };

    layer._start();
    assert.equal(pending(), 1);
    fire(timers);                 // timer fired: one rAF pending, no timer
    assert.equal(rafs.length, 1);
    layer._stop(true);            // rotate event: stop...
    layer._start();               // ...and restart before the rAF ran
    assert.equal(pending(), 1);
    fire(rafs);                   // the stale rAF must not draw nor reschedule
    assert.equal(frames, 0);
    assert.equal(pending(), 1);
  } finally {
    global.setTimeout = saved.setTimeout;
    global.clearTimeout = saved.clearTimeout;
    global.requestAnimationFrame = saved.requestAnimationFrame;
  }
});

test('cadenceSpeed: nearest-rank percentile of the first count speeds', () => {
  const speeds = new Float32Array([5, 1, 9, 3, 7, 2, 10, 4, 8, 6, 99, 99]);  // last two are stale
  assert.equal(WindField.cadenceSpeed(speeds, 10, 0.9), 9);
  assert.equal(WindField.cadenceSpeed(speeds, 10, 1), 10);
  assert.equal(WindField.cadenceSpeed(speeds, 10, 0.5), 5);
  assert.equal(WindField.cadenceSpeed(speeds, 0, 0.98), 0);
});

test('targetFps: a few fast streams in calm air raise the cadence', () => {
  // Zoomed out: 95 particles drift at the 2 px/s floor, 5 sit in a storm
  // at 55 px/s. The mean (4.65 px/s) would keep the base rate and let the
  // storm jump 4.6 px per frame; the 98th percentile follows the storm.
  const speeds = new Float32Array(100);
  speeds.fill(2, 0, 95);
  speeds.fill(55, 95);
  const fast = WindField.cadenceSpeed(speeds, 100, 0.98);
  assert.equal(fast, 55);
  close(WindField.targetFps(fast, 12, 30, 2.5), 22);
  assert.equal(WindField.targetFps(4.65, 12, 30, 2.5), 12);   // what the mean gave
  assert.equal(WindField.targetFps(200, 12, 30, 2.5), 30);    // never above the ceiling
});

test('lineWidth: particle width kept within 0.5..2 px, 1 px when unset', () => {
  assert.equal(WindField.lineWidth(0.8), 0.8);
  assert.equal(WindField.lineWidth(1.6), 1.6);
  assert.equal(WindField.lineWidth(0.1), 0.5);
  assert.equal(WindField.lineWidth(5), 2);
  assert.equal(WindField.lineWidth(NaN), 1);
  assert.equal(WindField.lineWidth(undefined), 1);
  assert.equal(WindField.lineWidth(0), 1);
});

test('parsePalette: round trip of the default palette', () => {
  const s = WindField.formatPalette(WindField.DEFAULT_PALETTE);
  assert.deepEqual(WindField.parsePalette(s), WindField.DEFAULT_PALETTE);
  assert.equal(WindField.DEFAULT_PALETTE.length, 8);
  close(WindField.DEFAULT_PALETTE[4].max, 50 / 3.6, 1e-3);
  assert.equal(WindField.DEFAULT_PALETTE[7].max, Infinity);
  assert.equal(WindField.DEFAULT_PALETTE[1].color, '#2ecc40');
});

test('parsePalette: null on wrong count, decreasing thresholds or bad colour', () => {
  const s = WindField.formatPalette(WindField.DEFAULT_PALETTE);
  assert.equal(WindField.parsePalette('1:ffffff,inf:000000'), null);
  assert.equal(WindField.parsePalette(s.replace('3.333', '0.5')), null);
  assert.equal(WindField.parsePalette(s.replace('2ecc40', 'zzzzzz')), null);
  assert.equal(WindField.parsePalette(''), null);
  assert.equal(WindField.parsePalette(null), null);
});

test('paletteBand: bounds are inclusive upper limits in m/s', () => {
  const p = WindField.DEFAULT_PALETTE;
  assert.equal(WindField.paletteBand(0, p), 0);
  assert.equal(WindField.paletteBand(5 / 3.6, p), 0);
  assert.equal(WindField.paletteBand(6 / 3.6, p), 1);
  assert.equal(WindField.paletteBand(100 / 3.6, p), 6);
  assert.equal(WindField.paletteBand(150 / 3.6, p), 7);
});

test('bandColor: white turns indigo on a light map', () => {
  const p = WindField.DEFAULT_PALETTE;
  assert.equal(WindField.bandColor(p, 0, 'light'), '#1a237e');
  assert.equal(WindField.bandColor(p, 0, 'dark'), '#ffffff');
  assert.equal(WindField.bandColor(p, 4, 'light'), '#ffdc00');
});

test('particleCount: one particle per 300 px2 times the density, within 200..max', () => {
  assert.equal(WindField.particleCount(800 * 330, 1, 1500), 880);
  assert.equal(WindField.particleCount(800 * 330, 0.5, 1500), 440);
  assert.equal(WindField.particleCount(800 * 330, 2, 1500), 1500);
  assert.equal(WindField.particleCount(100 * 100, 1, 1500), 200);
});

test('wantApi: the API only once its grid is finer than the file', () => {
  assert.equal(WindField.wantApi({ lonStep: 0.352 }, 0.25), false);
  assert.equal(WindField.wantApi({ lonStep: 0.176 }, 0.25), true);
});

test('pow2Steps round: steps are 360/2^k and 90/2^k', () => {
  const saved = WindField.pow2Steps;
  WindField.pow2Steps = 'round';
  try {
    for (const b of [{ west: -5, east: 15, south: 40, north: 55 }, { west: 100, east: 103, south: 10, north: 12 }]) {
      const s = WindField.gridSpec(b);
      close(Math.log2(360 / s.lonStep) % 1, 0, 1e-9);
      close(Math.log2(90 / s.latStep) % 1, 0, 1e-9);
    }
  } finally { WindField.pow2Steps = saved; }
});

test('pow2Steps round: a coarser kept grid is fetched again, an equal one is reused', () => {
  const saved = WindField.pow2Steps;
  WindField.pow2Steps = 'round';
  try {
    const view = { bounds: { west: -5, east: 15, south: 40, north: 55 }, zoom: 6 };
    const entry = (b) => ({ spec: WindField.gridSpec(b), grid: {}, fetchedAt: 0, zoom: view.zoom });
    const coarse = entry({ west: -60, east: 70, south: -10, north: 80 });
    assert.ok(coarse.spec.lonStep > WindField.gridSpec(view.bounds).lonStep);
    assert.equal(WindField.needsFetch(view, coarse, 0, 1e9), true);
    assert.equal(WindField.needsFetch(view, entry(view.bounds), 0, 1e9), false);
  } finally { WindField.pow2Steps = saved; }
});

test('warmUpFrames: enough frames for the trails to reach 95% of their length', () => {
  assert.equal(WindField.warmUpFrames(0.9), 29);    // 0.9^29 < 0.05 <= 0.9^28
  assert.equal(WindField.warmUpFrames(0.8), 14);
  assert.equal(WindField.warmUpFrames(0.99), 60);   // capped: never stall the page
  assert.equal(WindField.warmUpFrames(1), 0);
  assert.equal(WindField.warmUpFrames(0), 0);
  assert.equal(WindField.warmUpFrames(undefined), 0);
});


// Right after a page load the widget recalibrates the viewport: nothing is
// drawn before settle(), and its 1 px pan-and-back (nudging) is no move.
test('layer: no drawing before settle, the fixViewport nudge restarts nothing', () => {
  const { createWindLayer } = require('../glue-wind.js');
  const L = {
    Layer: { extend: (proto) => { function C() {} C.prototype = proto; return C; } },
    setOptions: (o, opts) => { o.options = Object.assign(Object.create(o.options || {}), opts || {}); }
  };
  const saved = { setTimeout, clearTimeout };
  const timers = [];
  global.setTimeout = (fn) => { timers.push(fn); return timers.length; };
  global.clearTimeout = (id) => { timers[id - 1] = null; };
  try {
    const layer = new (createWindLayer(L))();
    layer.initialize(null, null, {});
    layer._settled = false;
    layer._start();
    assert.equal(timers.filter(Boolean).length, 0, 'drew before settle');
    layer._settled = true;
    layer._start();
    assert.equal(timers.filter(Boolean).length, 1);

    let stops = 0, resets = 0;
    layer._stop = () => { stops++; layer._running = false; };
    layer._reset = () => { resets++; };
    layer.nudging = true;
    layer._onMoveStart(); layer._onMoveEnd();
    assert.equal(stops + resets, 0, 'the nudge restarted the particles');
    layer.nudging = false;
    layer._onMoveStart(); layer._onMoveEnd();
    assert.equal(stops, 1); assert.equal(resets, 1);
  } finally {
    global.setTimeout = saved.setTimeout;
    global.clearTimeout = saved.clearTimeout;
  }
});

test('sameView: a 1 px resize or shift is the same view, a pan or a zoom is not', () => {
  const frame = (ox, oy) => WindField.viewFrame({ x: ox, y: oy }, { x: ox + 1, y: oy }, { x: ox, y: oy + 1 });
  const v = (zoom, w, h, ox, oy) => ({ zoom, w, h, frame: frame(ox, oy) });
  const a = v(7, 843, 473, 1000, 2000);
  assert.ok(WindField.sameView(a, v(7, 843, 472, 1000, 2001), 2), 'repaint nudge');
  assert.ok(!WindField.sameView(a, v(7, 843, 473, 1010, 2000), 2), 'pan');
  assert.ok(!WindField.sameView(a, v(8, 843, 473, 1000, 2000), 2), 'zoom');
  assert.ok(!WindField.sameView(a, v(7, 700, 473, 1000, 2000), 2), 'real resize');
  assert.ok(!WindField.sameView(null, a, 2));
});

// The widget nudges the view by 1 px to make Chromium repaint, and each
// nudge resizes the map: a running layer must not respawn its particles
// for that, or the wind visibly restarts several times on every opening.
test('layer: a map event that leaves the view in place restarts nothing', () => {
  const { createWindLayer } = require('../glue-wind.js');
  const L = {
    Layer: { extend: (proto) => { function C() {} C.prototype = proto; return C; } },
    setOptions: (o, opts) => { o.options = Object.assign(Object.create(o.options || {}), opts || {}); }
  };
  const layer = new (createWindLayer(L))();
  layer.initialize(null, null, {});
  const frame = (ox, oy) => WindField.viewFrame({ x: ox, y: oy }, { x: ox + 1, y: oy }, { x: ox, y: oy + 1 });
  let now = { zoom: 7, w: 843, h: 473, frame: frame(1000, 2000) };
  layer._viewNow = () => now;
  let resets = 0;
  layer._reset = () => { resets++; layer._lastView = layer._viewNow(); };
  layer._reset();
  layer._running = true;
  now = { zoom: 7, w: 843, h: 472, frame: frame(1000, 2001) };
  layer._onMoveEnd();
  assert.equal(resets, 1, 'the 1 px nudge restarted the particles');
  now = { zoom: 8, w: 843, h: 472, frame: frame(2000, 4002) };
  layer._onMoveEnd();
  assert.equal(resets, 2);
  layer._running = false;      // stopped (popup closed, pan): any event restarts
  layer._onMoveEnd();
  assert.equal(resets, 3);
});

test('afterEnsure: draw a grid covering most of the view, ask again while it does not serve all of it', () => {
  const view = { bounds: { west: 0, south: 40, east: 20, north: 50 }, zoom: 5 };
  const ttl = 3600 * 1000, now = 10000;
  const entry = (bounds, zoom) => ({ spec: WindField.gridSpec(bounds), zoom, fetchedAt: now, grid: {} });
  // Fetched for this very view: draw it, nothing more to ask.
  assert.deepEqual(WindField.afterEnsure(view, entry(view.bounds, 5), now, ttl), { draw: true, retry: false });
  // The grid of the previous zoom level, handed back during the rate limit:
  // covers most of the view, so draw it, but ask again for the full one.
  const prev = entry({ west: 5, south: 42.5, east: 15, north: 47.5 }, 6);
  assert.ok(WindField.coverage(view.bounds, prev.spec) >= 0.5);
  assert.deepEqual(WindField.afterEnsure(view, prev, now, ttl), { draw: true, retry: true });
  // Too small a patch, or nothing at all: wait and ask again.
  const far = entry({ west: 8, south: 44, east: 12, north: 46 }, 7);
  assert.deepEqual(WindField.afterEnsure(view, far, now, ttl), { draw: false, retry: true });
  assert.deepEqual(WindField.afterEnsure(view, null, now, ttl), { draw: false, retry: true });
});
