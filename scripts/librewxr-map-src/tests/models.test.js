'use strict';
// Unit tests for the catalogue of regional models (glue-models.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
global.WidgetGrids = require('../glue-grids.js');
const M = require('../glue-models.js');

const H = 3600e3;
const at = (s) => Date.parse(s);

test('list: every grid of WidgetGrids, finest first', () => {
  const ids = M.list.map((m) => m.id);
  assert.deepEqual(ids.slice().sort(), WidgetGrids.MODELS.slice().sort());
  for (let i = 1; i < M.list.length; i++) assert.ok(M.list[i - 1].res <= M.list[i].res, ids[i - 1] + ' before ' + ids[i]);
  assert.equal(M.get('ecmwf_ifs025'), null);
});

test('runFor: a past hour comes from the run that starts then (the analysis)', () => {
  const latest = at('2026-11-07T15:00:00Z');
  assert.equal(M.runFor('meteofrance_arome_france0025', at('2026-11-07T09:00:00Z'), latest), at('2026-11-07T09:00:00Z'));
  assert.equal(M.runFor('meteofrance_arome_france0025', at('2026-11-07T10:00:00Z'), latest), at('2026-11-07T09:00:00Z'));
  assert.equal(M.runFor('italia_meteo_arpae_icon_2i', at('2026-11-07T10:00:00Z'), at('2026-11-07T12:00:00Z')), at('2026-11-07T00:00:00Z'));
});

test('runFor: the future from the latest run that reaches it, a longer one when the latest is short', () => {
  // HRRR: runs every hour hold 18 h, those of 00, 06, 12 and 18 UTC 48 h.
  const latest = at('2026-11-07T19:00:00Z');
  assert.equal(M.runFor('ncep_hrrr_conus', at('2026-11-08T12:00:00Z'), latest), latest);                 // +17 h
  assert.equal(M.runFor('ncep_hrrr_conus', at('2026-11-08T15:00:00Z'), latest), at('2026-11-07T18:00:00Z'));  // +20 h: the 18 UTC run
  assert.equal(M.runFor('ncep_hrrr_conus', at('2026-11-09T21:00:00Z'), latest), null);                   // past every run
  // UKMO: every 3 h 54 h, the others 12 h.
  assert.equal(M.runFor('ukmo_uk_deterministic_2km', at('2026-11-08T06:00:00Z'), at('2026-11-07T16:00:00Z')), at('2026-11-07T15:00:00Z'));
  // MSM: 00 and 12 UTC 78 h, the others 39 h.
  assert.equal(M.runFor('jma_msm', at('2026-11-09T00:00:00Z'), at('2026-11-07T03:00:00Z')), at('2026-11-07T00:00:00Z'));
});

test('hasFile: within the range of that run, every hour', () => {
  const run = at('2026-11-07T19:00:00Z');
  assert.equal(M.hasFile('ncep_hrrr_conus', at('2026-11-08T13:00:00Z'), run), true);
  assert.equal(M.hasFile('ncep_hrrr_conus', at('2026-11-08T14:00:00Z'), run), false);
  assert.equal(M.hasFile('ncep_hrrr_conus', at('2026-11-07T18:00:00Z'), run), false);
  assert.equal(M.hasFile('ncep_hrrr_conus', null, run), false);
});

test('bounds: each model knows the latitudes and longitudes it covers', () => {
  const b = M.get('meteofrance_arome_france0025').bounds();
  [b.south, b.west, b.north, b.east].forEach((v, k) => assert.ok(Math.abs(v - [37.5, -12, 55.4, 16][k]) < 1e-9));
  assert.equal(M.get('meteofrance_arome_france0025').bounds(), b);    // once
});

const view = (south, west, north, east) => ({ south, west, north, east });

test('pickForView: over France, AROME among at most three, finest first', () => {
  const ids = M.pickForView(view(42, -5, 51, 9));
  assert.ok(ids.includes('meteofrance_arome_france0025'));
  assert.ok(ids.length >= 1 && ids.length <= 3);
  for (let i = 1; i < ids.length; i++) assert.ok(M.get(ids[i - 1]).res <= M.get(ids[i]).res);
});

test('pickForView: over much of Europe, the three covering most of it, France kept', () => {
  const ids = M.pickForView(view(36, -10, 60, 30));
  assert.equal(ids.length, 3);
  assert.ok(ids.includes('meteofrance_arome_france0025'));
});

test('pickForView: none for a view wider than 60 degrees, or over the open sea', () => {
  assert.deepEqual(M.pickForView(view(-60, -180, 80, 180)), []);
  assert.deepEqual(M.pickForView(view(30, -100, 50, -30)), []);       // 70 degrees wide
  assert.deepEqual(M.pickForView(view(30, -38, 38, -28)), []);        // mid Atlantic (HRDPS reaches 41 W further north)
});

test('pickForView: HRRR over the United States, MSM over Japan, nothing European', () => {
  const us = M.pickForView(view(30, -110, 45, -80));
  assert.ok(us.includes('ncep_hrrr_conus'));
  assert.ok(us.every((id) => !/meteofrance|dwd|ukmo|metno|meteoswiss|italia/.test(id)));
  assert.deepEqual(M.pickForView(view(33, 136, 38, 142)), ['jma_msm']);
});

test('step: grids past two million points are read one point in two', () => {
  assert.equal(M.get('metno_nordic_pp').step, 2);
  assert.equal(M.get('cmc_gem_hrdps').step, 2);
  assert.equal(M.get('ncep_hrrr_conus').step, 1);
  assert.equal(M.get('meteofrance_arome_france0025').step, 1);
});

test('wind: how each model gives its 10 m wind', () => {
  const kinds = Object.fromEntries(M.list.map((m) => [m.id, m.wind]));
  assert.deepEqual(kinds, {
    meteofrance_arome_france0025: 'uv', dwd_icon_d2: 'uv', jma_msm: 'uv', meteoswiss_icon_ch1: 'uv',
    ncep_hrrr_conus: 'uv-grid',
    italia_meteo_arpae_icon_2i: 'sd', cmc_gem_hrdps: 'sd', ukmo_uk_deterministic_2km: 'sd', metno_nordic_pp: 'sd'
  });
  assert.deepEqual(M.windVars('dwd_icon_d2'), ['wind_u_component_10m', 'wind_v_component_10m']);
  assert.deepEqual(M.windVars('metno_nordic_pp'), ['wind_speed_10m', 'wind_direction_10m']);
});

test('toEarthWind: speed and direction (from) as u and v; HRRR turned from its grid to true north', () => {
  const d = WidgetGrids.latlon({ nx: 2, ny: 1, south: 0, west: 0, dLon: 1, dLat: 1 });
  const sd = M.toEarthWind('metno_nordic_pp', Float32Array.from([10, 2]), Float32Array.from([90, 180]), d);
  assert.ok(Math.abs(sd.u[0] + 10) < 1e-5 && Math.abs(sd.v[0]) < 1e-5);     // from the east: blowing west
  assert.ok(Math.abs(sd.u[1]) < 1e-5 && Math.abs(sd.v[1] - 2) < 1e-5);      // from the south: blowing north
  // HRRR at Denver, 2026-11-07 22 UTC: grid-relative (-2.0, -2.2); the API gave 3.0 m/s from 38 degrees.
  const g = WidgetGrids.of('ncep_hrrr_conus'), p = WidgetGrids.index(g, 39.74, -104.99);
  const k = Math.round(p.row) * g.nx + Math.round(p.col);
  const u = new Float32Array(g.nx * g.ny), v = new Float32Array(g.nx * g.ny);
  u[k] = -2.0; v[k] = -2.2;
  const e = M.toEarthWind('ncep_hrrr_conus', u, v, g);
  const dir = (Math.atan2(-e.u[k], -e.v[k]) * 180 / Math.PI + 360) % 360;
  assert.ok(Math.abs(dir - 37.6) < 0.5, 'direction ' + dir);
  assert.ok(Math.abs(Math.hypot(e.u[k], e.v[k]) - Math.hypot(2, 2.2)) < 1e-5);
  // Other grids keep their u and v.
  assert.equal(M.toEarthWind('dwd_icon_d2', u, v, g).u, u);
});

test('labels: the global model then the finer ones by their short names', () => {
  assert.deepEqual(M.labels('ecmwf_ifs025', ['meteofrance_arome_france0025', 'dwd_icon_d2']), ['ECMWF', 'AROME', 'ICON-D2']);
  assert.deepEqual(M.labels('ecmwf_ifs025', []), ['ECMWF']);
  assert.deepEqual(M.labels('some_model', ['unknown', 'ukmo_uk_deterministic_2km']), ['some_model', 'UKV']);
});
