'use strict';
// Unit tests for the model grids and their projections (glue-grids.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const G = require('../glue-grids.js');

const near = (a, b, tol, what) => assert.ok(Math.abs(a - b) <= tol, (what || '') + ' ' + a + ' vs ' + b);

test('latlon: a point falls at its column and row, south row first', () => {
  const d = G.latlon({ nx: 5, ny: 3, south: 40, west: -10, dLon: 0.5, dLat: 1 });
  const p = G.index(d, 41, -9);
  assert.equal(p.col, 2);
  assert.equal(p.row, 1);
  assert.ok(Number.isNaN(G.index(d, 43, -9).col));      // north of the grid
  assert.deepEqual(G.lonLatAt(d, 4, 2), { lat: 42, lon: -8 });
});

test('sample: bilinear on the file as it is, NaN next to a missing value', () => {
  const d = G.latlon({ nx: 3, ny: 2, south: 0, west: 0, dLon: 1, dLat: 1 });
  const v = Float32Array.from([0, 10, 20, 100, 110, NaN]);   // row 0 (south), then row 1
  assert.equal(G.sample(d, v, 0.5, 0.5), 55);
  assert.ok(Number.isNaN(G.sample(d, v, 0.5, 1.5)));
  assert.ok(Number.isNaN(G.sample(d, v, 5, 5)));
});

for (const kind of ['rotated', 'lcc', 'laea']) {
  test(kind + ': forward then inverse comes back', () => {
    const d = { rotated: G.of('meteoswiss_icon_ch1'), lcc: G.of('ncep_hrrr_conus'), laea: G.of('ukmo_uk_deterministic_2km') }[kind];
    for (const [lat, lon] of [[46.5, 7.5], [40, -100], [55, -3], [62, 10]]) {
      const p = G.forward(d.proj, lat, lon), q = G.inverse(d.proj, p.x, p.y);
      near(q.lat, lat, 1e-6, kind + ' lat');
      near(q.lon, lon, 1e-6, kind + ' lon');
    }
  });
}

test('lcc: the tangent cone holds the scale on its parallel, the meridian of origin is x = 0', () => {
  const p = G.forward(G.of('ncep_hrrr_conus').proj, 38.5, -97.5), q = G.forward(G.of('ncep_hrrr_conus').proj, 38.5, -96.5);
  assert.equal(Math.round(p.x), 0);
  // One degree of longitude along 38.5 N: R cos(38.5) pi / 180.
  near(Math.hypot(q.x - p.x, q.y - p.y), 6371229 * Math.cos(38.5 * Math.PI / 180) * Math.PI / 180, 2);
});

// The bounding boxes published in latest.json on 2026-11-07, south, west, north, east.
const BBOX = {
  meteofrance_arome_france0025: [37.5, -12.0, 55.4, 16.0],
  dwd_icon_d2: [43.18, -3.94, 58.08, 20.339998],
  italia_meteo_arpae_icon_2i: [33.7, 3.0, 48.9, 22.0],
  jma_msm: [22.4, 120.0, 47.6, 150.0],
  meteoswiss_icon_ch1: [42.57854, 1.2333984, 49.786846, 16.846222],
  cmc_gem_hrdps: [39.626034, -133.62952, 47.87646, -40.708527],
  ncep_hrrr_conus: [21.137995, -122.72, 47.842403, -60.918],
  ukmo_uk_deterministic_2km: [44.508755, -17.152863, 61.92511, 15.352753],
  metno_nordic_pp: [52.302723, 1.918457, 72.18527, 41.764282]
};

for (const id of Object.keys(BBOX)) {
  test('grid of ' + id + ': first and last points, or its extent, as latest.json says', () => {
    const d = G.of(id), b = BBOX[id];
    const sw = G.lonLatAt(d, 0, 0), ne = G.lonLatAt(d, d.nx - 1, d.ny - 1), box = G.bounds(d);
    // Grids given by their corners publish the corners; the others their extent.
    const corners = Math.abs(sw.lat - b[0]) < 0.01 && Math.abs(ne.lat - b[2]) < 0.01;
    const got = corners ? [sw.lat, sw.lon, ne.lat, ne.lon] : [box.south, box.west, box.north, box.east];
    got.forEach((v, k) => near(v, b[k], 0.01, id + ' ' + ['south', 'west', 'north', 'east'][k]));
  });
}

test('of: the size of a file is checked against the grid', () => {
  assert.equal(G.of('meteofrance_arome_france0025', 717, 1121).nx, 1121);
  assert.throws(() => G.of('meteofrance_arome_france0025', 700, 1121), /717 x 1121/);
  assert.equal(G.of('ecmwf_ifs025'), null);
  assert.equal(G.of('meteofrance_arome_france0025'), G.of('meteofrance_arome_france0025'));   // one per model
});

test('index: a projected grid finds its own points again', () => {
  for (const id of ['cmc_gem_hrdps', 'ncep_hrrr_conus', 'ukmo_uk_deterministic_2km', 'metno_nordic_pp', 'meteoswiss_icon_ch1']) {
    const d = G.of(id), c = Math.floor(d.nx / 3), r = Math.floor(d.ny / 2), ll = G.lonLatAt(d, c, r), p = G.index(d, ll.lat, ll.lon);
    near(p.col, c, 1e-3, id + ' col');
    near(p.row, r, 1e-3, id + ' row');
  }
});

test('res: about the step in degrees, for the edge feather', () => {
  near(G.of('meteofrance_arome_france0025').res, 0.025, 1e-9);
  near(G.of('ncep_hrrr_conus').res, 3000 / 111195, 1e-4);
  near(G.of('italia_meteo_arpae_icon_2i').res, 0.0225, 1e-9);
});

test('projected grids: the grid point nearest a city is the one the Open-Meteo API answers with', () => {
  // City, then the point the API gave on 2026-11-07 for that model (elevation=nan).
  const cases = {
    meteoswiss_icon_ch1: [[47.37, 8.54], [47.37077, 8.538208]],
    cmc_gem_hrdps: [[45.50, -73.57], [45.49491, -73.56671]],
    ncep_hrrr_conus: [[39.74, -104.99], [39.746895, -104.987076]],
    ukmo_uk_deterministic_2km: [[51.51, -0.13], [51.51147, -0.13078308]],
    metno_nordic_pp: [[59.91, 10.75], [59.906296, 10.744095]]
  };
  for (const id of Object.keys(cases)) {
    const d = G.of(id), [[la, lo], [alat, alon]] = cases[id], p = G.index(d, la, lo);
    const q = G.lonLatAt(d, Math.round(p.col), Math.round(p.row));
    near(q.lat, alat, 2e-4, id + ' lat');
    near(q.lon, alon, 2e-4, id + ' lon');
  }
});
