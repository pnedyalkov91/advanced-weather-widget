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

test('gridSpec: widened bounds, N clamped to 6..12, rows north to south', () => {
  // ~37 km wide at 48N, widened to ~60 km -> 60/3 = 20 -> clamped to 12
  const wide = WindField.gridSpec({ west: 6.3, south: 47.85, east: 6.8, north: 48.2 });
  assert.equal(wide.n, 12);
  assert.equal(wide.lats.length, 12);
  assert.equal(wide.lons.length, 12);
  close(wide.west, 6.3 - 0.5 * 0.3); close(wide.east, 6.8 + 0.5 * 0.3);
  close(wide.south, 47.85 - 0.35 * 0.3); close(wide.north, 48.2 + 0.35 * 0.3);
  assert.ok(wide.lats[0] > wide.lats[11], 'lats descend (north first)');
  assert.ok(wide.lons[0] < wide.lons[11], 'lons ascend (west first)');
  close(wide.lats[0], wide.north, 1e-4); close(wide.lats[11], wide.south, 1e-4);
  // ~7 km wide -> widened ~12 km -> 4 -> clamped to 6
  const narrow = WindField.gridSpec({ west: 6.55, south: 48.0, east: 6.65, north: 48.05 });
  assert.equal(narrow.n, 6);
});

test('pointLists: n*n coordinates, row-major (lat rows, lon columns)', () => {
  const spec = { n: 2, lats: [48.1, 48.0], lons: [6.5, 6.6] };
  const pl = WindField.pointLists(spec);
  assert.equal(pl.latitude, '48.1,48.1,48,48');
  assert.equal(pl.longitude, '6.5,6.6,6.5,6.6');
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
  const spec = { west: 6.0, south: 47.8, east: 7.0, north: 48.3 };
  const cached = { spec, grid: {}, zoom: 10, fetchedAt: 1000 };
  const inside = { bounds: { west: 6.2, south: 47.9, east: 6.8, north: 48.2 }, zoom: 10 };
  assert.equal(WindField.needsFetch(inside, null, 2000, 3600000), true);
  assert.equal(WindField.needsFetch(inside, cached, 2000, 3600000), false);
  assert.equal(WindField.needsFetch(inside, cached, 1000 + 3600001, 3600000), true);
  assert.equal(WindField.needsFetch({ bounds: inside.bounds, zoom: 11 }, cached, 2000, 3600000), true);
  assert.equal(WindField.needsFetch({ bounds: { west: 5.9, south: 47.9, east: 6.8, north: 48.2 }, zoom: 10 }, cached, 2000, 3600000), true);
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
