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
    linesBefore: () => undefined
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
