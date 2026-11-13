// ==========================================================================
// Glue script 2e: the air temperature under the radar (pure math).
// WidgetTemp holds the palettes, the bands and the legend of the temperature
// layer, and is loadable under Node for tests; glue-temp-layer.js draws it.
// Temperatures are in °C everywhere; the widget's unit (C or F) only sets
// where the bands and the legend ticks fall.
// ==========================================================================
var WidgetTemp = (function () {
  'use strict';

  /* The "Vivid" palette, the default one: close to the temperature maps
     people know, cold purples and blues up to dark reds. */
  var DEFAULT_STOPS = [[-40, '#3b3050'], [-30, '#4b3a9c'], [-20, '#3f63c4'], [-10, '#2aa3a8'], [0, '#7ccf5a'],
    [5, '#d6d63a'], [10, '#f2c230'], [20, '#e8862a'], [30, '#d23a22'], [40, '#7a0f12']]
    .map(function (s) { return { t: s[0], color: s[1] }; });

  var MIN_STOPS = 2, MAX_STOPS = 12;

  // Colors for every 0.1 °C from -60 to +60: drawing a pixel is one lookup.
  var LUT_MIN = -60, LUT_STEP = 0.1, LUT_SIZE = 1201;

  var STEPS = [0, 2, 2.5, 5, 10];   // band widths offered; 0 is a smooth gradient
  var DEFAULT_STEP = 5, DEFAULT_OPACITY = 45;

  function toF(c) { return c * 9 / 5 + 32; }
  function fromF(f) { return (f - 32) * 5 / 9; }

  function rgb(color) {
    return [1, 3, 5].map(function (i) { return parseInt(color.substr(i, 2), 16); });
  }

  /** A palette from its URL form: 2 to 12 "t:rrggbb" separated by commas, t
      in °C going up. null when anything is wrong. */
  function parsePalette(s) {
    var parts = String(s == null ? '' : s).split(',');
    if (parts.length < MIN_STOPS || parts.length > MAX_STOPS) return null;
    var out = [], prev = -Infinity;
    for (var i = 0; i < parts.length; i++) {
      var m = /^\s*(-?\d+(?:\.\d+)?):#?([0-9a-fA-F]{6})\s*$/.exec(parts[i]);
      if (!m) return null;
      var t = parseFloat(m[1]);
      if (!(t > prev)) return null;
      out.push({ t: t, color: '#' + m[2].toLowerCase() });
      prev = t;
    }
    return out;
  }

  /** The palette of the page's parameter: the vivid one when it is empty or
      does not read (a broken settings entry). */
  function paletteFromParam(s) { return parsePalette(s) || DEFAULT_STOPS; }

  /** The URL form of a palette (see parsePalette), temperatures to 0.1 °C. */
  function formatPalette(stops) {
    return stops.map(function (s) {
      return String(Math.round(s.t * 10) / 10) + ':' + s.color.replace('#', '');
    }).join(',');
  }

  /** Color of a temperature: linear between two points, the end colors
      held below the first point and above the last. */
  function colorAt(stops, t) {
    var last = stops.length - 1, c;
    if (t <= stops[0].t) c = rgb(stops[0].color);
    else if (t >= stops[last].t) c = rgb(stops[last].color);
    else {
      for (var i = 1; i <= last; i++) {
        if (t > stops[i].t) continue;
        var a = rgb(stops[i - 1].color), b = rgb(stops[i].color);
        var f = (t - stops[i - 1].t) / (stops[i].t - stops[i - 1].t);
        c = a.map(function (v, k) { return v + (b[k] - v) * f; });
        break;
      }
    }
    return c.map(function (v) { return Math.round(v); });
  }

  /** The temperature (°C) whose color a band takes: the middle of the band
      holding tC, bands being `step` wide in the widget's unit. step 0 keeps
      tC (smooth gradient). */
  function bandCenterC(tC, step, unit) {
    if (!(step > 0)) return tC;
    if (unit === 'F') return fromF(Math.floor(toF(tC) / step) * step + step / 2);
    return Math.floor(tC / step) * step + step / 2;
  }

  /** Index of a temperature (°C) in the lookup table, held within it. */
  function lutIndex(tC) {
    var i = Math.round((tC - LUT_MIN) / LUT_STEP);
    return i < 0 ? 0 : (i >= LUT_SIZE ? LUT_SIZE - 1 : i);
  }

  /** RGB triplets for every LUT_STEP from LUT_MIN, bands applied. */
  function buildLut(stops, step, unit) {
    var lut = new Uint8ClampedArray(LUT_SIZE * 3);
    for (var i = 0; i < LUT_SIZE; i++) {
      var c = colorAt(stops, bandCenterC(LUT_MIN + i * LUT_STEP, step, unit));
      lut[i * 3] = c[0]; lut[i * 3 + 1] = c[1]; lut[i * 3 + 2] = c[2];
    }
    return lut;
  }

  /** Ticks of the legend, which spans the palette from its first point to
      its last: one every 10 °C, or every 20 °F. pos runs from 0 to 1. */
  function legendTicks(stops, unit) {
    var lo = stops[0].t, hi = stops[stops.length - 1].t, every = unit === 'F' ? 20 : 10;
    var conv = unit === 'F' ? toF : function (c) { return c; };
    var back = unit === 'F' ? fromF : function (c) { return c; };
    var out = [];
    for (var v = Math.ceil(conv(lo) / every) * every; v <= conv(hi) + 1e-9; v += every) {
      out.push({ label: String(v), pos: hi > lo ? (back(v) - lo) / (hi - lo) : 0 });
    }
    return out;
  }

  /** Band width from the widget: 0, 2, 2.5, 5 or 10; anything else gives 5. */
  function normStep(n) {
    if (n === null || n === undefined || n === '') return DEFAULT_STEP;
    var v = Number(n);
    return STEPS.indexOf(v) >= 0 ? v : DEFAULT_STEP;
  }

  /** Opacity of the layer in percent, 0 to 100; unreadable gives 45. */
  function normOpacity(n) {
    var v = parseFloat(n);
    if (!isFinite(v)) return DEFAULT_OPACITY;
    return Math.round(Math.max(0, Math.min(100, v)));
  }

  function normUnit(u) { return u === 'F' ? 'F' : 'C'; }

  /* A model gives the temperature of its own ground, one height per cell;
     Open-Meteo brings it to the real height of a place at 6.5 °C per km,
     and so do we, pixel by pixel. */
  var LAPSE = 0.0065;   // °C per m

  /** tSrc (°C), valid at height zSrc (m), brought to the pixel's height zPix.
      Depths at sea count as sea level; a missing height changes nothing. */
  function correct(tSrc, zSrc, zPix) {
    if (!isFinite(zSrc) || !isFinite(zPix)) return tSrc;
    return tSrc + LAPSE * (zSrc - Math.max(0, zPix));
  }

  /** Value at lat/lon of a grid of lats (north to south) and lons (west to
      east), values row by row: bilinear, on whichever copy of the world the
      longitude is. NaN outside the grid or next to a missing value. */
  var scratch = { k: 0, nx: 0, fr: 0, fc: 0 };
  function sampleScalar(grid, values, lat, lon) {
    return scalarCell(grid, lat, lon, scratch) ? cellValue(values, scratch) : NaN;
  }

  /** The cell of such a grid lat/lon falls in, into c: k (its north-west
      point), nx (the row's length), fr and fc (the share of the next row
      and column); false outside the grid. Found once, it serves every
      field of the grid at that point (cellValue, or WidgetGrids.valueAt:
      the same sum). */
  function scalarCell(grid, lat, lon, c) {
    var lats = grid.lats, lons = grid.lons, rows = lats.length, cols = lons.length;
    var north = lats[0], south = lats[rows - 1], west = lons[0], east = lons[cols - 1];
    if (lon < west) lon += 360 * Math.ceil((west - lon) / 360);
    else if (lon > east) lon -= 360 * Math.ceil((lon - east) / 360);
    if (lat > north || lat < south || lon < west || lon > east) return false;
    var r = (north - lat) / (north - south) * (rows - 1);
    var x = (lon - west) / (east - west) * (cols - 1);
    var i0 = Math.min(rows - 2, Math.floor(r)), j0 = Math.min(cols - 2, Math.floor(x));
    c.k = i0 * cols + j0;
    c.nx = cols;
    c.fr = r - i0;
    c.fc = x - j0;
    return true;
  }

  /** Bilinear value of a field in cell c; NaN next to a missing value. */
  function cellValue(values, c) {
    var k = c.k, nx = c.nx, fc = c.fc;
    var top = values[k] * (1 - fc) + values[k + 1] * fc;
    var bottom = values[k + nx] * (1 - fc) + values[k + nx + 1] * fc;
    return top * (1 - c.fr) + bottom * c.fr;
  }

  /** How far each point of a grid is inside its data, from 0 on the
      grid's edge or next to a missing value to 1 at feather points in
      (chamfer distance); NaN where the value is missing. A finer model
      blends into the coarse one with it, so its border leaves no step.
      jitter (points, one per point, optional) pushes the start of the
      blend that far in: see edgeNoise. */
  function edgeWeights(values, rows, cols, feather, jitter) {
    var n = rows * cols, d = new Float32Array(n), BIG = 1e9, D = Math.SQRT2, r, c, k;
    for (k = 0; k < n; k++) {
      r = Math.floor(k / cols); c = k - r * cols;
      d[k] = !isFinite(values[k]) ? -1 : (r === 0 || c === 0 || r === rows - 1 || c === cols - 1 ? 0 : BIG);
    }
    function at(i) { return d[i] < 0 ? 0 : d[i]; }
    function relax(k, i, step) { var v = at(i) + step; if (v < d[k]) d[k] = v; }
    for (r = 1; r < rows - 1; r++) {
      for (c = 1; c < cols - 1; c++) {
        k = r * cols + c;
        if (d[k] <= 0) continue;
        relax(k, k - 1, 1); relax(k, k - cols, 1); relax(k, k - cols - 1, D); relax(k, k - cols + 1, D);
      }
    }
    for (r = rows - 2; r > 0; r--) {
      for (c = cols - 2; c > 0; c--) {
        k = r * cols + c;
        if (d[k] <= 0) continue;
        relax(k, k + 1, 1); relax(k, k + cols, 1); relax(k, k + cols + 1, D); relax(k, k + cols - 1, D);
      }
    }
    var w = new Float32Array(n);
    for (k = 0; k < n; k++) w[k] = d[k] < 0 ? NaN : Math.max(0, Math.min(1, (d[k] - (jitter ? jitter[k] : 0)) / feather));
    return w;
  }

  // Integer hash of a lattice node, 0..1.
  function hash01(i, j) {
    var h = (Math.imul(i, 374761393) + Math.imul(j, 668265263)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }
  // Smooth value noise, 0..1, one lattice node per unit.
  function valueNoise(x, y) {
    var i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j;
    fx = fx * fx * (3 - 2 * fx);
    fy = fy * fy * (3 - 2 * fy);
    var a = hash01(i, j), b = hash01(i + 1, j), c = hash01(i, j + 1), d = hash01(i + 1, j + 1);
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy;
  }

  /** A fixed noise of the earth, 0..1, at lat/lon: bumps of about 1.5
      degrees with finer ones over them. Where a finer model starts to
      blend in moves by it, so that over a flat sea, where the two models
      differ by a little, the band their blend crosses follows a ragged
      line and no longer the model's straight border. */
  function edgeNoise(lat, lon) {
    return (2 * valueNoise(lon / 1.5, lat / 1.5) + valueNoise(lon / 0.5 + 17.3, lat / 0.5 + 5.1)) / 3;
  }

  return {
    LAPSE: LAPSE, correct: correct, sampleScalar: sampleScalar, scalarCell: scalarCell, cellValue: cellValue,
    edgeWeights: edgeWeights, edgeNoise: edgeNoise,
    DEFAULT_STOPS: DEFAULT_STOPS, LUT_MIN: LUT_MIN, LUT_STEP: LUT_STEP, LUT_SIZE: LUT_SIZE,
    parsePalette: parsePalette, paletteFromParam: paletteFromParam, formatPalette: formatPalette, colorAt: colorAt,
    bandCenterC: bandCenterC, lutIndex: lutIndex, buildLut: buildLut, legendTicks: legendTicks,
    normStep: normStep, normOpacity: normOpacity, normUnit: normUnit
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetTemp; }
