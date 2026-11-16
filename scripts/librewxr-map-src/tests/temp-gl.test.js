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
// Unit tests for the temperature drawn by the graphics chip (glue-temp-gl.js):
// the shader's grid math (in JavaScript, line for line) against WidgetGrids,
// and when the chip or the tiles draw. The shader itself needs a browser.
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');

global.WidgetWind = require('../glue-wind.js');
global.WidgetTemp = require('../glue-temp.js');
global.WidgetGrids = require('../glue-grids.js');
require('../glue-temp-layer.js');
require('../glue-temp-gl.js');
const T = global.WidgetTemp, G = global.WidgetGrids, GL = T.TempLayerGL;

const near = (a, b, tol, what) => assert.ok(Math.abs(a - b) <= tol, (what || '') + ' ' + a + ' vs ' + b);

test('fineIdx: the shader finds the same column and row as WidgetGrids, on every grid', () => {
  for (const id of G.MODELS) {
    const d = G.of(id), b = G.bounds(d);
    let inside = 0;
    for (let i = 0; i < 15; i++) {
      for (let j = 0; j < 15; j++) {
        const lat = b.south + (b.north - b.south) * (i + 0.5) / 15, lon = b.west + (b.east - b.west) * (j + 0.5) / 15;
        const want = G.index(d, lat, lon), got = GL.fineIdx(d, lat, lon), out = !(want.col >= 0);
        if (out) { assert.equal(got, null, id + ' outside at ' + lat + ', ' + lon); continue; }
        inside++;
        near(got.col, want.col, 1e-6, id + ' col');
        near(got.row, want.row, 1e-6, id + ' row');
      }
    }
    assert.ok(inside > 50, id + ': ' + inside + ' points inside');
  }
});

test('fineIdx: the grids given every other point read the same places', () => {
  const full = G.of('metno_nordic_pp'), half = G.thin(full, 2), p = GL.fineIdx(full, 60, 10), q = GL.fineIdx(half, 60, 10);
  near(q.col * 2, p.col, 1e-6);
  near(q.row * 2, p.row, 1e-6);
});

test('fineParams: projected grids in units of the earth radius, small enough for 32-bit floats', () => {
  for (const id of ['ncep_hrrr_conus', 'ukmo_uk_deterministic_2km', 'metno_nordic_pp']) {
    const q = GL.fineParams(G.of(id));
    assert.ok(q.G.every((v) => Math.abs(v) < 10), id + ' ' + q.G);
  }
  assert.equal(GL.fineParams(G.of('meteofrance_arome_france0025')).kind, 0);
  assert.equal(GL.fineParams(G.of('meteoswiss_icon_ch1')).kind, 1);
});

test('packWZ and clean: no NaN for the chip, made once per array', () => {
  const w = Float32Array.from([NaN, 0.5, 1]), z = Float32Array.from([100, NaN, 300]);
  assert.deepEqual(Array.from(GL.packWZ(w, z)), [0, 100, 0.5, 0, 1, 300]);
  assert.equal(GL.packWZ(w, z), GL.packWZ(w, z));
  assert.deepEqual(Array.from(GL.packWZ(w, null)), [0, 0, 0.5, 0, 1, 0]);
  const v = Float32Array.from([1, NaN]);
  assert.deepEqual(Array.from(GL.clean(v)), [1, 0]);
  assert.equal(GL.clean(v), GL.clean(v));
});

const file = { grid: { lats: [90, -90], lons: [-180, 180] }, values: new Float32Array(4) };
const fine = (id) => ({ grid: { desc: G.of(id) }, values: new Float32Array(1), weights: new Float32Array(1) });

test('drawable: the file, with up to three finer models on known grids', () => {
  assert.equal(GL.drawable([file]), true);
  assert.equal(GL.drawable([fine('dwd_icon_d2'), fine('ncep_hrrr_conus'), fine('jma_msm'), file]), true);
  assert.equal(GL.drawable([fine('dwd_icon_d2'), fine('ncep_hrrr_conus'), fine('jma_msm'), fine('metno_nordic_pp'), file]), false);
  assert.equal(GL.drawable([{ grid: { lats: [1] }, values: new Float32Array(1) }, file]), false);   // an API grid
  assert.equal(GL.drawable([]), false);
});

// A layer on a fake map and adapter, past addTo(): only _show is looked at.
function layerOn() {
  const adapter = {
    lines: new Set(), cleared: 0, tiles: 0,
    setLines(owner, on) { if (on) this.lines.add(owner); else this.lines.delete(owner); },
    clearTemp() { this.cleared++; this.lines.delete('temperature'); },
    setTempTiles() { this.tiles++; this.lines.add('temperature'); },
    addLayer() {}
  };
  const layer = new GL(adapter, null, null, null, { manual: true });
  layer._map = { repaints: 0, triggerRepaint() { this.repaints++; } };
  layer._lut = T.buildLut(T.DEFAULT_STOPS, 5, 'C');
  return { layer, adapter };
}

test('_show: far out the chip draws, the tiles are cleared, the lines kept by the chip', () => {
  const { layer, adapter } = layerOn();
  layer._mode = 'file';
  layer._show([fine('dwd_icon_d2'), file]);
  assert.equal(layer._gpuOn, true);
  assert.equal(adapter.cleared, 1);
  assert.equal(adapter.tiles, 0);
  assert.deepEqual([...adapter.lines], ['temperature-gl']);
  assert.equal(layer.settled(), false);           // until the chip has drawn it
  layer._gl.drawn = layer._gpuVersion;
  assert.equal(layer.settled(), true);
});

test('_show: closer in (the API) back to the tiles, the chip lets go of the lines', () => {
  const { layer, adapter } = layerOn();
  layer._mode = 'file';
  layer._show([file]);
  layer._mode = 'api';
  layer._show([{ grid: { lats: [1], lons: [1] }, values: new Float32Array(1) }, file]);
  assert.equal(layer._gpuOn, false);
  assert.equal(adapter.tiles, 1);
  assert.deepEqual([...adapter.lines], ['temperature']);
});

test('a shader that does not build: the tiles draw the file from then on', async () => {
  const { layer, adapter } = layerOn();
  layer._mode = 'file';
  layer._show([file]);
  layer._gl.failed = true;
  layer._gl.onFail();
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(layer._gpuOn, false);
  assert.equal(adapter.tiles, 1);
  assert.ok(!adapter.lines.has('temperature-gl'));
  layer._show([{ grid: file.grid, values: new Float32Array(4) }]);    // the next picture
  assert.equal(adapter.tiles, 2);
  assert.equal(layer._gpuOn, false);
});

// The polar caps on the globe: past 85.05 degrees the mesh has one row of
// each side whose far end MapLibre puts at the pole (raw = +-32768), with
// v_merc still at the edge. v_pole (0 at the edge, +-1 at the pole) gives
// the shaders the real latitude there.
const mercY = (lat) => (1 - Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360)) / Math.PI) / 2;
const EDGE = 85.0511;

test('meshVertices: a row past each edge, at the edge in Mercator and flagged for the pole', () => {
  const v = GL.meshVertices(), cols = GL.MESH_X + 1, rows = v.length / 3 / cols;
  assert.equal(rows, GL.MESH_Y + 3);
  for (let i = 0; i < cols; i++) {
    const top = i * 3, bottom = ((rows - 1) * cols + i) * 3;
    assert.equal(v[top + 2], -1, 'north row flagged');
    assert.equal(v[bottom + 2], 1, 'south row flagged');
    near(v[top + 1], mercY(EDGE), 1e-6, 'north row at the edge (flat: nothing drawn)');
    near(v[bottom + 1], mercY(-EDGE), 1e-6, 'south row at the edge');
  }
  for (let k = cols * 3; k < (rows - 1) * cols * 3; k += 3) assert.equal(v[k + 2], 0, 'the body is not flagged');
});

test('fragLat: the latitude of Mercator in the body, from the edge to the pole in the caps', () => {
  for (const lat of [-80, -45, 0, 12.5, 60, 85]) near(GL.fragLat(mercY(lat), 0), lat, 1e-9, 'body ' + lat);
  near(GL.fragLat(mercY(EDGE), 0), EDGE, 1e-4, 'north edge');
  near(GL.fragLat(mercY(EDGE), -1), 90, 1e-9, 'north pole');
  near(GL.fragLat(mercY(-EDGE), 1), -90, 1e-9, 'south pole');
  near(GL.fragLat(mercY(EDGE), -0.5), (EDGE + 90) / 2, 1e-4, 'half way north');
  near(GL.fragLat(mercY(-EDGE), 0.5), -(EDGE + 90) / 2, 1e-4, 'half way south');
});

test('fragLat: one row is enough, the caps\' flat triangles follow the latitude within a hundredth of a degree', () => {
  // A cap triangle as the chip draws it: two points of the edge, one
  // column apart, and the pole; a fragment at weights a, b, c is the point
  // on that flat triangle, seen from the center of the Earth.
  const toXYZ = (lat, lon) => {
    const f = lat * Math.PI / 180, l = lon * Math.PI / 180;
    return [Math.cos(f) * Math.cos(l), Math.cos(f) * Math.sin(l), Math.sin(f)];
  };
  const dLon = 360 / GL.MESH_X;
  for (const south of [false, true]) {
    const s = south ? -1 : 1, e1 = toXYZ(s * EDGE, 0), e2 = toXYZ(s * EDGE, dLon), p = [0, 0, s];
    let worst = 0;
    for (let ia = 0; ia <= 20; ia++) {
      for (let ib = 0; ia + ib <= 20; ib++) {
        const a = ia / 20, b = ib / 20, c = 1 - a - b;
        const q = [0, 1, 2].map((k) => a * e1[k] + b * e2[k] + c * p[k]);
        const real = Math.atan2(q[2], Math.hypot(q[0], q[1])) * 180 / Math.PI;
        const got = GL.fragLat(mercY(s * EDGE), s * -c);
        worst = Math.max(worst, Math.abs(real - got));
      }
    }
    assert.ok(worst < 0.01, (south ? 'south' : 'north') + ' cap, worst ' + worst);
  }
});

test('the shaders read the latitude of the caps', () => {
  assert.match(GL.FS_HEAD, /in float v_pole;/);
  assert.match(GL.FS_HEAD, /lat = fragLat\(\);/, 'gridUv: every layer of the chip');
  assert.match(GL.VS_MAIN, /v_pole = a_pos\.z;/);
  assert.match(GL.VS_MAIN, /projectTile\(v_merc, raw\)/);
});
