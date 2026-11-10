// === PRESSURE AND ISOBARS (glue-pressure.js; MapLibre page, after glue-controls.js) ===
// Mean sea level pressure in the animation: a colored field drawn in tiles
// (layer 'pressure') and isobars drawn by MapLibre as lines with labels and
// H/L marks (layer 'isobars'). Both read pressure_msl from the same files
// and share the store key. It lives inside the page's module, where it reaches
// ANIM_LAYERS, anim and the adapter; the other layers after it borrow its
// drawing by the graphics chip (GLLayer, FS_HEAD). Timings in window.presStats.
var WidgetPressure = (function () {
  'use strict';
  var DEG = Math.PI / 180;
  var TILE = 256, LATTICE = 4, MAXZOOM = 8;
  var P_MIN = 910, P_SCALE = 1.5;        // byte b is P_MIN + b / 1.5 hPa (910 to 1079 hPa)
  var NAN_B = 255;
  var opts = { step: 4, smooth: 2, opacity: 0.6, bands: 0, chaikin: 1, hlRadius: 6, hlMin: 2.5, linkDeg: 8, tropicLat: 20, tropicMin: 5, weakRatio: 0.6, minFrames: 3, clip: true, hideLabels: true, minorZoom: 4, gpu: true };
  var stats = { tile: [], contour: [], hl: [], setData: [], upload: [], render: [], atlas: [], features: 0, segments: 0 };
  function note(list, ms) { list.push(ms); if (list.length > 40) list.shift(); }
  function mean(list) { return list.length ? list.reduce(function (a, b) { return a + b; }, 0) / list.length : 0; }
  window.presStats = function () {
    return {
      tileMs: +mean(stats.tile).toFixed(2), contourMs: +mean(stats.contour).toFixed(1), hlMs: +mean(stats.hl).toFixed(1),
      setDataToLoadedMs: +mean(stats.setData).toFixed(1), uploadMs: +mean(stats.upload).toFixed(1), renderMs: +mean(stats.render).toFixed(2), atlasMs: +mean(stats.atlas).toFixed(1), features: stats.features, segments: stats.segments
    };
  };
  // Opacity of the pressure colors in percent (the isobars keep theirs):
  // only the colors are drawn again, the lines stay as they are.
  window.presSetOpacity = function (percent) {
    opts.opacity = Math.max(0, Math.min(100, percent === "" || percent === null || !isFinite(+percent) ? 60 : +percent)) / 100;
    var t = anim && anim.group.track('pressure');
    if (t) t.layer.redraw();
    if (presLegend) presLegend.querySelector('canvas').style.opacity = String(opts.opacity);
    return opts.opacity;
  };
  // The isobars' own settings: their opacity (0..1), the width of the
  // lines (times the usual one), the values on the lines and the H/L marks.
  // The space between two lines is opts.step.
  // Their color ('' follows the theme) and the size of the values in px.
  var iso = { opacity: 0.8, width: 1, labels: true, marks: true, color: '', textSize: 11 };
  /** The ink of the lines and their values: [r, g, b] 0..1 and as CSS. */
  function isoInk() {
    var m = /^#?([0-9a-f]{6})$/i.exec(iso.color || ''), rgb;
    if (m) {
      var n = parseInt(m[1], 16);
      rgb = [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255];
    } else rgb = currentTheme() === 'dark' ? [1, 1, 1] : [0.1, 0.1, 0.14];
    var css = 'rgb(' + rgb.map(function (c) { return Math.round(c * 255); }).join(',') + ')';
    return { rgb: rgb, css: css };
  }
  function isoLayer() { var t = anim && anim.group.track('isobars'); return t ? t.layer : null; }
  window.isoSetOpacity = function (percent) {
    iso.opacity = Math.max(0, Math.min(100, isFinite(+percent) ? +percent : 80)) / 100;
    var l = isoLayer();
    if (l) l.restyleIso();
    return iso.opacity;
  };
  /** o: { width, step (hPa), labels, marks }, any of them. */
  window.isoSetOptions = function (o) {
    o = o || {};
    if (isFinite(+o.width) && +o.width > 0) iso.width = Math.max(0.3, Math.min(3, +o.width));
    if ('labels' in o) iso.labels = !!o.labels;
    if ('marks' in o) iso.marks = !!o.marks;
    if ('color' in o) iso.color = /^#[0-9a-f]{6}$/i.test(o.color || '') ? o.color : '';
    if (isFinite(+o.textSize) && +o.textSize > 0) iso.textSize = Math.max(8, Math.min(24, +o.textSize));
    var stepChanged = false;
    if ([2, 4, 8].indexOf(+o.step) >= 0 && +o.step !== opts.step) { opts.step = +o.step; stepChanged = true; }
    var l = isoLayer();
    if (l) { l.restyleIso(); if (stepChanged || 'marks' in o) l.redraw(); }
    return Object.assign({ step: opts.step }, iso);
  };
  // The map, for the bench (views and screenshots).
  window.presMap = function () { return _widgetAdapter.getMap(); };
  window.presOptions = function (o) {
    for (var k in o) opts[k] = o[k];
    lut = null;
    if (anim) ['pressure', 'isobars'].forEach(function (id) { var t = anim.group.track(id); if (t) t.layer.redraw(); });
    return opts;
  };

  // --- packing: hPa on one byte ---
  function hPa(values) {
    // The files may give Pa: hPa wanted.
    var probe = values[(values.length / 2) | 0];
    if (!(probe > 2000)) return values;
    var out = new Float32Array(values.length);
    for (var i = 0; i < values.length; i++) out[i] = values[i] / 100;
    return out;
  }
  function pack(values) {
    var out = new Uint8Array(values.length);
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      out[i] = isFinite(v) ? Math.max(0, Math.min(254, Math.round((v - P_MIN) * P_SCALE))) : NAN_B;
    }
    return out;
  }
  // The 256 values a byte stands for: one lookup a point (a few ms for a
  // picture; a division a point took 30, at every step).
  var UNPACK = new Float32Array(256);
  for (var b = 0; b < 256; b++) UNPACK[b] = b === NAN_B ? NaN : P_MIN + b / P_SCALE;
  function unpack(p) {
    var out = new Float32Array(p.length);
    for (var i = 0; i < p.length; i++) out[i] = UNPACK[p[i]];
    return out;
  }
  function field(id) {
    return {
      id: id, store: 'pressure', vars: ['pressure_msl'],
      read: function (e, t) {
        var g = WidgetOpenData.toScalarGrid(hPa(e.data[0]), e.ny, e.nx, t);
        return { meta: { lats: g.lats, lons: g.lons, res: g.res }, parts: [pack(g.values)] };
      },
      unpack: function (parts) { return unpack(parts[0]); },
      grid: function (m, a, b, mix, tA, tB, at) {
        if (!b) return { lats: m.lats, lons: m.lons, res: m.res, times: [tA / 1000], values: a };
        return { lats: m.lats, lons: m.lons, res: m.res, times: [at / 1000], values: a, valuesB: b, mix: mix };
      }
    };
  }
  WidgetAnim.FIELDS.pressure = field('pressure');
  WidgetAnim.FIELDS.isobars = field('isobars');

  /** A layer of its own sources and layers, put back after a new base
      map: taken off what is left of it, added again, its picture shown. */
  function readd(layer) {
    var map = layer.map, grid = layer.grid;
    if (!map) return;
    layer.remove();
    layer.addTo(map);
    if (grid) layer.showFile(grid);
  }
  /** A GL layer put back after a new base map, at its place. */
  function readdGL(map, gl, under) {
    if (map && !map.getLayer(gl.id)) map.addLayer(gl, under ? beforeLines(map) : beforeOverlays(map));
  }

  /** Pressure at lat/lon of a grid given to showFile (mixed when it has two). */
  function sample(g, lat, lon) {
    var p = WidgetTemp.sampleScalar(g, g.values, lat, lon);
    if (g.valuesB && g.mix > 0) p += (WidgetTemp.sampleScalar(g, g.valuesB, lat, lon) - p) * g.mix;
    return p;
  }

  // --- colors ---
  var STOPS = [[960, '#4b1d6e'], [975, '#2c4f9e'], [990, '#2f8fd0'], [1003, '#6cc4c0'], [1013, '#d9e8c4'],
    [1020, '#f3d58a'], [1030, '#ee9a50'], [1040, '#d6504a'], [1052, '#7d1834']];
  var lut = null, LUT_MIN = 940, LUT_STEP = 0.25, LUT_N = 520;
  function rgb(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }
  function buildLut() {
    var out = new Uint8Array(LUT_N * 3), s = STOPS.map(function (x) { return [x[0], rgb(x[1])]; });
    for (var i = 0; i < LUT_N; i++) {
      var p = LUT_MIN + i * LUT_STEP;
      if (opts.bands > 0) p = (Math.floor(p / opts.bands) + 0.5) * opts.bands;
      var k = 0;
      while (k < s.length - 2 && p > s[k + 1][0]) k++;
      var f = Math.max(0, Math.min(1, (p - s[k][0]) / (s[k + 1][0] - s[k][0])));
      for (var c = 0; c < 3; c++) out[i * 3 + c] = Math.round(s[k][1][c] + (s[k + 1][1][c] - s[k][1][c]) * f);
    }
    return out;
  }

  function latOfRow(row, z) {
    var y = Math.PI * (1 - 2 * row / (TILE * Math.pow(2, z)));
    return (2 * Math.atan(Math.exp(y)) - Math.PI / 2) / DEG;
  }

  // --- the colored field, in tiles of a protocol of its own ---
  var fillLayer = null;
  maplibregl.addProtocol('lvpres', function (params) {
    var m = /^lvpres:\/\/(\d+)\/(\d+)\/(\d+)\/(\d+)/.exec(params.url);
    var px = fillLayer ? fillLayer.tile(+m[1], +m[2], +m[3], +m[4]) : new Uint8ClampedArray(TILE * TILE * 4);
    return createImageBitmap(new ImageData(px, TILE, TILE)).then(function (bitmap) {
      if (fillLayer) fillLayer.served(+m[1]);
      return { data: bitmap };
    });
  });

  /** Where the page's own layers start: the pressure goes right under them,
      over the base map, its night and the temperature. */
  function beforeOverlays(map) {
    var layers = map.getStyle().layers;
    for (var i = 0; i < layers.length; i++) {
      var id = layers[i].id;
      if (layers[i].type === 'custom' || id.indexOf('lv-layer-') === 0 || id.indexOf('lv-alerts') === 0) return id;
    }
    return undefined;
  }
  /** Color layers go under the coasts and borders the adapter draws. */
  function beforeLines(map) { return _widgetAdapter.linesBefore() || beforeOverlays(map); }
  /** The isobars' line layer (by the chip or not), null without them. */
  function isoLine(map) { return map.getLayer('lv-iso-gl') ? 'lv-iso-gl' : map.getLayer('lv-iso') ? 'lv-iso' : null; }
  /** Rain and clouds go right under the isobars when they show, so the
      lines stay readable over them; else as the color layers. */
  function beforeIsobars(map) { return isoLine(map) || (map.getLayer('lv-iso-label') ? 'lv-iso-label' : null) || beforeLines(map); }
  function firstCustom(map) {
    var layers = map.getStyle().layers;
    for (var i = 0; i < layers.length; i++) if (layers[i].type === 'custom') return layers[i].id;
    return undefined;
  }

  function FillLayer() {
    this.map = null;
    this.grid = null;
    this.version = 0;
    this.servedVersion = -1;
    this.inflight = 0;
  }
  FillLayer.prototype = {
    addTo: function (map) {
      this.map = map;
      fillLayer = this;
      map.addSource('lv-pres-src', { type: 'raster', tiles: this._tiles(), tileSize: 2 * TILE, maxzoom: MAXZOOM });
      map.addLayer({ id: 'lv-pres', type: 'raster', source: 'lv-pres-src',
        paint: { 'raster-opacity': opts.opacity, 'raster-fade-duration': 0, 'raster-resampling': 'linear' } }, beforeLines(map));
      _widgetAdapter.setLines('pressure', true);
      return this;
    },
    _tiles: function () { return ['lvpres://' + this.version + '/{z}/{x}/{y}']; },
    remove: function () {
      var map = this.map;
      if (!map) return;
      if (map.getLayer('lv-pres')) map.removeLayer('lv-pres');
      if (map.getSource('lv-pres-src')) map.removeSource('lv-pres-src');
      _widgetAdapter.setLines('pressure', false);
      if (fillLayer === this) fillLayer = null;
      this.map = null;
    },
    showFile: function (grid) {
      this.grid = grid;
      this.redraw();
    },
    redraw: function () {
      if (!this.map || !this.grid) return;
      this.version++;
      this.inflight = 0;
      var src = this.map.getSource('lv-pres-src');
      if (src) src.setTiles(this._tiles());
      this.map.setPaintProperty('lv-pres', 'raster-opacity', opts.opacity * (this.fade == null ? 1 : this.fade));
    },
    setFade: function (f) {
      this.fade = f;
      if (this.map && this.map.getLayer('lv-pres')) this.map.setPaintProperty('lv-pres', 'raster-opacity', opts.opacity * f);
    },
    settled: function () { return this.servedVersion === this.version && this.inflight === 0; },
    served: function (v) { if (v === this.version) { this.inflight = Math.max(0, this.inflight - 1); this.servedVersion = v; } },
    reload: function () {},
    tile: function (version, z, x, y) {
      var px = new Uint8ClampedArray(TILE * TILE * 4), g = this.grid;
      if (!g || version !== this.version) return px;
      this.inflight++;
      var t0 = performance.now();
      lut = lut || buildLut();
      // The pressure on a lattice every 4 px, blended between: it is smooth.
      var n = TILE / LATTICE + 1, lat = new Float32Array(n * n), scale = TILE * Math.pow(2, z);
      for (var i = 0; i < n; i++) {
        var la = latOfRow(y * TILE + i * LATTICE, z);
        for (var j = 0; j < n; j++) {
          var lo = (x * TILE + j * LATTICE) / scale * 360 - 180;
          lat[i * n + j] = sample(g, la, lo);
        }
      }
      for (var row = 0; row < TILE; row++) {
        var li = (row / LATTICE) | 0, fr = (row - li * LATTICE) / LATTICE;
        for (var col = 0; col < TILE; col++) {
          var lj = (col / LATTICE) | 0, fc = (col - lj * LATTICE) / LATTICE, k = li * n + lj;
          var top = lat[k] + (lat[k + 1] - lat[k]) * fc, bot = lat[k + n] + (lat[k + n + 1] - lat[k + n]) * fc;
          var p = top + (bot - top) * fr, o = (row * TILE + col) * 4;
          if (!isFinite(p)) continue;
          var li3 = Math.max(0, Math.min(LUT_N - 1, Math.round((p - LUT_MIN) / LUT_STEP))) * 3;
          px[o] = lut[li3]; px[o + 1] = lut[li3 + 1]; px[o + 2] = lut[li3 + 2]; px[o + 3] = 255;
        }
      }
      note(stats.tile, performance.now() - t0);
      return px;
    },
    valueAt: function (lat, lon) { return this.grid ? sample(this.grid, lat, lon) : null; }
  };

  // --- isobars ---
  /** The field on a 0.5 degree grid, smoothed `passes` times by a 1-2-1
      filter: at 0.25 degree the lines zigzag over the mountains. */
  function smoothHalf(values, rows, cols, passes) {
    var R = ((rows - 1) >> 1) + 1, C = ((cols - 1) >> 1) + 1, out = new Float32Array(R * C);
    for (var i = 0; i < R; i++) {
      for (var j = 0; j < C; j++) {
        var s = 0, w = 0;
        for (var di = -1; di <= 1; di++) {
          var r = Math.max(0, Math.min(rows - 1, 2 * i + di));
          for (var dj = -1; dj <= 1; dj++) {
            var c = 2 * j + dj;
            if (c < 0) c += cols - 1; else if (c >= cols) c -= cols - 1;
            var ww = (di ? 1 : 2) * (dj ? 1 : 2), v = values[r * cols + c];
            if (isFinite(v)) { s += v * ww; w += ww; }
          }
        }
        out[i * C + j] = w ? s / w : NaN;
      }
    }
    var tmp = new Float32Array(R * C);
    for (var p = 1; p < passes; p++) {
      for (i = 0; i < R; i++) {
        for (j = 0; j < C; j++) {
          var a = out[i * C + (j > 0 ? j - 1 : C - 2)], b = out[i * C + j], d = out[i * C + (j < C - 1 ? j + 1 : 1)];
          tmp[i * C + j] = (a + 2 * b + d) / 4;
        }
      }
      for (i = 0; i < R; i++) {
        for (j = 0; j < C; j++) {
          var up = tmp[Math.max(0, i - 1) * C + j], mid = tmp[i * C + j], dn = tmp[Math.min(R - 1, i + 1) * C + j];
          out[i * C + j] = (up + 2 * mid + dn) / 4;
        }
      }
    }
    return { values: out, rows: R, cols: C };
  }

  var smoothed = new WeakMap();
  function smoothOf(g, values) {
    var key = values, hit = smoothed.get(key);
    if (hit && hit.passes === opts.smooth) return hit.s;
    var s = smoothHalf(values, g.lats.length, g.lons.length, opts.smooth);
    smoothed.set(key, { passes: opts.smooth, s: s });
    return s;
  }

  /* Segments of a cell by case (bit 8 top left, 4 top right, 2 bottom
     right, 1 bottom left set when at or above the level); edges 0 top,
     1 right, 2 bottom, 3 left. 5 and 10 are saddles, settled by the center. */
  var CASES = [[], [[3, 2]], [[2, 1]], [[3, 1]], [[0, 1]], null, [[0, 2]], [[3, 0]],
    [[3, 0]], [[0, 2]], null, [[0, 1]], [[3, 1]], [[2, 1]], [[3, 2]], []];

  /** Isobars of field f (R x C, lat from 90 down, lon from -180, step res)
      every `step` hPa, as GeoJSON features, between latitudes +-maxLat. */
  function contours(f, res, step, maxLat, box, smoothPasses) {
    var R = f.rows, C = f.cols, v = f.values;
    var r0 = Math.ceil((90 - maxLat) / res), r1 = Math.floor((90 + maxLat) / res), c0 = 0, c1 = C - 1;
    if (box) { r0 = Math.max(r0, box.r0); r1 = Math.min(r1, box.r1); c0 = box.c0; c1 = box.c1; }
    var byLevel = new Map(), segCount = 0;
    function edgeId(i, j, e) {
      // Horizontal edges even, vertical odd; a cell's bottom is the top of the one below.
      if (e === 0) return (i * C + j) * 2;
      if (e === 2) return ((i + 1) * C + j) * 2;
      if (e === 3) return (i * C + j) * 2 + 1;
      return (i * C + j + 1) * 2 + 1;
    }
    for (var i = r0; i < r1; i++) {
      for (var j = c0; j < c1; j++) {
        var tl = v[i * C + j], tr = v[i * C + j + 1], bl = v[(i + 1) * C + j], br = v[(i + 1) * C + j + 1];
        if (!(isFinite(tl) && isFinite(tr) && isFinite(bl) && isFinite(br))) continue;
        var lo = Math.min(tl, tr, bl, br), hi = Math.max(tl, tr, bl, br);
        for (var L = Math.ceil(lo / step) * step; L <= hi; L += step) {
          var idx = (tl >= L ? 8 : 0) | (tr >= L ? 4 : 0) | (br >= L ? 2 : 0) | (bl >= L ? 1 : 0);
          var segs = CASES[idx];
          if (!segs) {
            var high = (tl + tr + bl + br) / 4 >= L;
            segs = idx === 5 ? (high ? [[3, 0], [2, 1]] : [[3, 2], [0, 1]]) : (high ? [[0, 1], [3, 2]] : [[3, 0], [2, 1]]);
          }
          if (!segs.length) continue;
          var lev = byLevel.get(L);
          if (!lev) { lev = []; byLevel.set(L, lev); }
          for (var s = 0; s < segs.length; s++) { lev.push(edgeId(i, j, segs[s][0]), edgeId(i, j, segs[s][1])); segCount++; }
        }
      }
    }
    function point(id, L) {
      var cell = id >> 1, i = (cell / C) | 0, j = cell - i * C, a = v[cell], b, f;
      if (id & 1) { b = v[cell + C]; f = (L - a) / (b - a); return [-180 + j * res, 90 - (i + f) * res]; }
      b = v[cell + 1]; f = (L - a) / (b - a);
      return [-180 + (j + f) * res, 90 - i * res];
    }
    var features = [];
    byLevel.forEach(function (ends, L) {
      var n = ends.length / 2, at = new Map(), used = new Uint8Array(n);
      for (var s = 0; s < n; s++) {
        for (var e = 0; e < 2; e++) {
          var id = ends[2 * s + e], l = at.get(id);
          if (l) l.push(s); else at.set(id, [s]);
        }
      }
      function other(id, s) { var l = at.get(id); return l[0] === s ? (l.length > 1 ? l[1] : -1) : l[0]; }
      for (s = 0; s < n; s++) {
        if (used[s]) continue;
        used[s] = 1;
        var ids = [ends[2 * s], ends[2 * s + 1]];
        // Forward from the second end, then back from the first.
        for (var dir = 0; dir < 2; dir++) {
          var cur = s, id = dir ? ids[0] : ids[ids.length - 1];
          for (;;) {
            var nx = other(id, cur);
            if (nx < 0 || used[nx]) break;
            used[nx] = 1;
            var nid = ends[2 * nx] === id ? ends[2 * nx + 1] : ends[2 * nx];
            if (dir) ids.unshift(nid); else ids.push(nid);
            cur = nx;
            id = nid;
          }
        }
        if (ids.length < 4) continue;
        var coords = ids.map(function (k) { return point(k, L); });
        for (var c = 0; c < smoothPasses; c++) coords = chaikin(coords);
        features.push({ type: 'Feature', properties: { p: L, major: L % 20 === 0 ? 1 : 0, minor: L % opts.step ? 1 : 0 }, geometry: { type: 'LineString', coordinates: coords } });
      }
    });
    stats.segments = segCount;
    return features;
  }

  function chaikin(c) {
    var closed = c.length > 3 && c[0][0] === c[c.length - 1][0] && c[0][1] === c[c.length - 1][1];
    var out = closed ? [] : [c[0]];
    for (var i = 0; i < c.length - 1; i++) {
      var a = c[i], b = c[i + 1];
      out.push([a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25], [a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75]);
    }
    if (closed) out.push(out[0]); else out.push(c[c.length - 1]);
    return out;
  }

  /** Highs and lows: points of the field 1 degree apart that are the
      highest (lowest) within radius cells and stand out from its mean. */
  function extrema(f, res, radius, minDiff, maxLat) {
    var R = f.rows, C = f.cols, v = f.values, out = [];
    var r0 = Math.ceil((90 - maxLat) / res), r1 = Math.floor((90 + maxLat) / res);
    for (var i = r0; i <= r1; i += 2) {
      for (var j = 0; j < C - 1; j += 2) {
        var p = v[i * C + j], isMax = true, isMin = true, sum = 0, n = 0;
        if (!isFinite(p)) continue;
        for (var di = -radius; di <= radius && (isMax || isMin); di += 2) {
          var r = i + di;
          if (r < 0 || r >= R) continue;
          for (var dj = -radius; dj <= radius; dj += 2) {
            if (!di && !dj) continue;
            var c = j + dj;
            if (c < 0) c += C - 1; else if (c >= C - 1) c -= C - 1;
            var q = v[r * C + c];
            if (!isFinite(q)) continue;
            if (q >= p) isMax = false;
            if (q <= p) isMin = false;
            sum += q; n++;
          }
        }
        // Near the equator the pressure swings 1 to 2 hPa twice a day (the
        // atmospheric tide): only a deep centre there, a tropical cyclone.
        var lat = 90 - i * res, need = Math.abs(lat) < opts.tropicLat ? Math.max(minDiff, opts.tropicMin) : minDiff;
        var prom = n ? Math.abs(p - sum / n) : 0;
        if (!n || !(isMax || isMin) || prom < need * opts.weakRatio) continue;
        out.push({ sym: isMax ? 'H' : 'L', p: p, lon: -180 + j * res, lat: 90 - i * res, strong: prom >= need });
      }
    }
    return out;
  }

  /** Rows and columns of the 0.5 degree grid around the view (a third of
      it more each way); null when the view is too wide to bother. */
  function viewBox(map, res, C) {
    var b = map.getBounds(), w = b.getWest(), e = b.getEast(), s = b.getSouth(), n = b.getNorth();
    var mx = (e - w) / 3, my = (n - s) / 3;
    w -= mx; e += mx; s = Math.max(-90, s - my); n = Math.min(90, n + my);
    var box = { r0: Math.max(0, Math.floor((90 - n) / res)), r1: Math.ceil((90 - s) / res), c0: 0, c1: C - 1 };
    if (w >= -180 && e <= 180) { box.c0 = Math.floor((w + 180) / res); box.c1 = Math.min(C - 1, Math.ceil((e + 180) / res)); }
    return box;
  }

  /* Highs and lows of the forecast pictures only, followed from one to the
     next: a centre found again within linkDeg glides there, one that comes
     or goes fades, one seen in a single picture is not shown at all. */
  var marksKept = new WeakMap();
  function markKey() { return [opts.hlRadius, opts.hlMin, opts.smooth, opts.tropicLat, opts.tropicMin, opts.weakRatio].join('/'); }

  function marksOf(frames, k) {
    var parts = frames.packed[k], m = frames.meta;
    if (!parts || !m) return null;
    var hit = marksKept.get(parts);
    if (hit && hit.key === markKey()) return hit.marks;
    var t0 = performance.now(), f = smoothHalf(frames.field.unpack(parts), m.lats.length, m.lons.length, opts.smooth);
    var marks = extrema(f, 2 * m.res, 2 * opts.hlRadius, opts.hlMin, 80);
    note(stats.hl, performance.now() - t0);
    marksKept.set(parts, { key: markKey(), marks: marks });
    return marks;
  }

  function dist(a, b) {
    var dl = Math.abs(a.lon - b.lon);
    if (dl > 180) dl = 360 - dl;
    var dx = dl * Math.cos((a.lat + b.lat) / 2 * DEG), dy = a.lat - b.lat;
    return Math.sqrt(dx * dx + dy * dy);
  }

  /** For each mark of A, the index of its mark in B (-1 when none): same
      kind, within linkDeg, nearest pairs first. */
  function link(A, B) {
    var out = A.map(function () { return -1; });
    if (!A || !B) return out;
    var pairs = [];
    for (var i = 0; i < A.length; i++) {
      for (var j = 0; j < B.length; j++) {
        if (A[i].sym !== B[j].sym) continue;
        var d = dist(A[i], B[j]);
        if (d < opts.linkDeg) pairs.push([d, i, j]);
      }
    }
    pairs.sort(function (x, y) { return x[0] - y[0]; });
    var takenB = {};
    pairs.forEach(function (q) { if (out[q[1]] < 0 && !takenB[q[2]]) { out[q[1]] = q[2]; takenB[q[2]] = true; } });
    return out;
  }

  /* Tracks over the whole range: a mark linked to one of the picture
     before carries its track on. A track shows when it lasts minFrames
     pictures and is strong once (above the threshold); weaker marks only
     carry a track on: hysteresis, so a centre near the threshold neither
     blinks in nor out. */
  var trackCache = { frames: null, sig: '', data: null }, trackGen = 0;
  function tracks(frames) {
    var n = frames.times.length;
    var sig = markKey() + '|' + opts.linkDeg + '|' + opts.minFrames + '|' + frames.packed.map(function (p) { return p ? 1 : 0; }).join('');
    if (trackCache.frames === frames && trackCache.sig === sig) return trackCache.data;
    var marks = [], ids = [], next = 0, len = {}, strong = {};
    for (var k = 0; k < n; k++) {
      var M = marksOf(frames, k);
      marks[k] = M;
      ids[k] = [];
      if (!M) continue;
      var back = k > 0 && marks[k - 1] ? link(marks[k - 1], M) : null;
      for (var j = 0; j < M.length; j++) {
        var b = back ? back.indexOf(j) : -1, id = b >= 0 ? ids[k - 1][b] : next++;
        ids[k][j] = id;
        len[id] = (len[id] || 0) + 1;
        if (M[j].strong) strong[id] = true;
      }
    }
    // gen: the ids of another build are other centres, never mixed up with these.
    var data = { marks: marks, ids: ids, gen: ++trackGen, shown: function (id) { return len[id] >= opts.minFrames && !!strong[id]; } };
    trackCache = { frames: frames, sig: sig, data: data };
    return data;
  }

  /** The marks to show at position pos of the animation: { sym, p, lon, lat, op }. */
  function trackedMarks(frames, pos) {
    var T = tracks(frames), i = Math.floor(pos + 1e-6), f = pos - i;
    if (f < 1e-3) f = 0;
    var A = T.marks[i], out = [];
    if (!A) return out;
    var B = f ? T.marks[i + 1] || [] : [], idsA = T.ids[i], idsB = f ? T.ids[i + 1] || [] : [];
    A.forEach(function (a, k) {
      var id = idsA[k];
      if (!T.shown(id)) return;
      var j = idsB.indexOf(id);
      if (j >= 0) {
        var b = B[j], dl = b.lon - a.lon;
        if (dl > 180) dl -= 360; else if (dl < -180) dl += 360;
        var lon = a.lon + dl * f;
        if (lon > 180) lon -= 360; else if (lon < -180) lon += 360;
        out.push({ id: T.gen + '/' + id, sym: a.sym, p: a.p + (b.p - a.p) * f, lon: lon, lat: a.lat + (b.lat - a.lat) * f, op: 1 });
      } else out.push({ id: T.gen + '/' + id, sym: a.sym, p: a.p, lon: a.lon, lat: a.lat, op: 1 - f });
    });
    B.forEach(function (b, j) {
      var id = idsB[j];
      if (T.shown(id) && idsA.indexOf(id) < 0) out.push({ id: T.gen + '/' + id, sym: b.sym, p: b.p, lon: b.lon, lat: b.lat, op: f });
    });
    return out;
  }

  /** Bench: per forecast picture, the marks shown and those born or gone
      since the one before. */
  window.presTrackStats = function () {
    var t = anim && anim.group.track('isobars');
    if (!t) return null;
    var T = tracks(t.frames), out = [];
    for (var k = 1; k < T.marks.length; k++) {
      if (!T.marks[k] || !T.marks[k - 1]) continue;
      var now = T.ids[k].filter(T.shown), before = T.ids[k - 1].filter(T.shown);
      var born = now.filter(function (id) { return before.indexOf(id) < 0; }).length;
      var gone = before.filter(function (id) { return now.indexOf(id) < 0; }).length;
      out.push(now.length + ' (+' + born + ' -' + gone + ')');
    }
    return out.join(' ');
  };

  function IsobarLayer() {
    this.map = null;
    this.grid = null;
    this.version = 0;
    this.loaded = -1;
  }
  IsobarLayer.prototype = {
    addTo: function (map) {
      var self = this, dark = currentTheme() === 'dark';
      var ink = dark ? 'rgba(255,255,255,0.8)' : 'rgba(25,25,35,0.8)';
      this.map = map;
      var empty = { type: 'FeatureCollection', features: [] };
      map.addSource('lv-iso-src', { type: 'geojson', data: empty, tolerance: 0.5, buffer: 64 });
      // Under the animation's satellite and radar (or the coasts), over the rest.
      var before = _widgetAdapter.linesBefore() || firstCustom(map);
      map.addLayer({ id: 'lv-iso', type: 'line', source: 'lv-iso-src', layout: { 'line-join': 'round', 'line-cap': 'round' },
        paint: { 'line-color': ink, 'line-width': ['case', ['==', ['get', 'major'], 1], 1.3, ['==', ['get', 'minor'], 1], 0.5, 0.75],
          'line-opacity': ['case', ['==', ['get', 'minor'], 1], 0.6, 1] } }, before);
      map.addLayer({ id: 'lv-iso-label', type: 'symbol', source: 'lv-iso-src',
        layout: { 'symbol-placement': 'line', 'symbol-spacing': 350, 'text-field': ['to-string', ['get', 'p']],
          'text-font': ['Noto Sans Regular'], 'text-size': 11, 'text-keep-upright': true },
        paint: { 'text-color': ink } }, before);
      this._onData = function (e) {
        if (e.sourceId === 'lv-iso-src' && e.isSourceLoaded && self._sentAt && self.loaded !== self.version) {
          self.loaded = self.version;
          note(stats.setData, performance.now() - self._sentAt);
        }
      };
      map.on('sourcedata', this._onData);
      this.restyleIso();
      this._onMoveEnd = function () { if (opts.clip && !self.moving) self.redraw(); };
      map.on('moveend', this._onMoveEnd);
      // Its place in the stack: the adapter's restack().
      return this;
    },
    remove: function () {
      var map = this.map;
      if (!map) return;
      map.off('sourcedata', this._onData);
      map.off('moveend', this._onMoveEnd);
      (this._pool || []).forEach(function (mk) { mk.marker.remove(); });
      this._pool = null;
      ['lv-iso-label', 'lv-iso'].forEach(function (id) { if (map.getLayer(id)) map.removeLayer(id); });
      ['lv-iso-src'].forEach(function (id) { if (map.getSource(id)) map.removeSource(id); });
      this.map = null;
    },
    showFile: function (grid) { this.grid = grid; this.redraw(); },
    redraw: function () {
      var g = this.grid, map = this.map;
      if (!g || !map) return;
      var t0 = performance.now(), a = smoothOf(g, g.values), f = a;
      if (g.valuesB && g.mix > 0) {
        var b = smoothOf(g, g.valuesB), m = g.mix, out = new Float32Array(a.values.length);
        for (var k = 0; k < out.length; k++) out[k] = a.values[k] + (b.values[k] - a.values[k]) * m;
        f = { values: out, rows: a.rows, cols: a.cols };
      }
      var res = 2 * g.res, box = opts.clip ? viewBox(map, res, f.cols) : null;
      // Closer in, a line between two: 1034 between 1032 and 1036.
      var step = map.getZoom() >= opts.minorZoom ? opts.step / 2 : opts.step;
      var lines = contours(f, res, step, 84, box, this.moving ? 0 : opts.chaikin);
      var t1 = performance.now();
      var track = anim && anim.group.track('isobars'), pos = anim ? anim.player.index : -1;
      var marks = track && pos >= 0 ? trackedMarks(track.frames, pos) : [];
      note(stats.contour, t1 - t0);
      stats.features = lines.length;
      this.version++;
      this._sentAt = performance.now();
      map.getSource('lv-iso-src').setData({ type: 'FeatureCollection', features: lines });
      this._marks(marks);
    },
    settled: function () { return this.loaded === this.version; },
    reload: function () {},
    /** H and L as HTML markers, moved each picture: a symbol layer costs a
        new placement of every label of the map each time. */
    /** One marker per followed centre (its track id): a centre keeps its
        marker from birth to end. Handed out by place in the list, a marker
        jumped to another centre whenever one started to fade. */
    _marks: function (marks) {
      if (!iso.marks) marks = [];
      var pool = this._pool || (this._pool = new Map()), dark = currentTheme() === 'dark', seen = new Set();
      for (var k = 0; k < marks.length; k++) {
        var m = marks[k], mk = pool.get(m.id);
        seen.add(m.id);
        if (!mk) {
          var el = document.createElement('div');
          el.className = 'lv-hl-mark';
          el.dataset.id = m.id;
          el.style.cssText = 'font: bold 20px/1 "Noto Sans", sans-serif; text-align: center; pointer-events: none; text-shadow: 0 0 3px ' + (dark ? '#000' : '#fff') + ', 0 0 3px ' + (dark ? '#000' : '#fff');
          el.innerHTML = '<div></div><div style="font-size: 11px"></div>';
          el.firstChild.textContent = m.sym;
          el.style.color = m.sym === 'H' ? (dark ? '#ff8a7a' : '#c0392b') : (dark ? '#8ab8ff' : '#1f5fbf');
          mk = { el: el, marker: new maplibregl.Marker({ element: el }).setLngLat([m.lon, m.lat]).addTo(this.map), p: null };
          pool.set(m.id, mk);
        }
        var p = Math.round(m.p);
        if (mk.p !== p) { mk.el.lastChild.textContent = p; mk.p = p; }
        // Hidden where the globe covers it (MapLibre leaves it at 0.2).
        mk.op = m.op;
        mk.marker.setOpacity(String(m.op * Math.min(1, iso.opacity / 0.8)), '0');
        mk.marker.setLngLat([m.lon, m.lat]);
      }
      pool.forEach(function (mk, id) {
        if (!seen.has(id)) { mk.marker.remove(); pool.delete(id); }
      });
    },
    /** The isobars' settings (iso) on the layers MapLibre draws. */
    restyleIso: function () {
      var map = this.map;
      if (!map) return;
      var ink = isoInk();
      if (map.getLayer('lv-iso')) {
        var w = iso.width;
        map.setPaintProperty('lv-iso', 'line-width', ['case', ['==', ['get', 'major'], 1], 1.3 * w, ['==', ['get', 'minor'], 1], 0.5 * w, 0.75 * w]);
        map.setPaintProperty('lv-iso', 'line-color', ink.css);
        map.setPaintProperty('lv-iso', 'line-opacity', ['case', ['==', ['get', 'minor'], 1], Math.min(1, 0.6 * iso.opacity / 0.8), Math.min(1, iso.opacity / 0.8)]);
      }
      if (map.getLayer('lv-iso-label')) {
        map.setPaintProperty('lv-iso-label', 'text-opacity', Math.min(1, iso.opacity / 0.8));
        map.setPaintProperty('lv-iso-label', 'text-color', ink.css);
        map.setLayoutProperty('lv-iso-label', 'text-size', iso.textSize);
        map.setLayoutProperty('lv-iso-label', 'visibility', iso.labels && !(this.moving && opts.hideLabels) ? 'visible' : 'none');
      }
      (this._pool || new Map()).forEach(function (mk) { mk.marker.setOpacity(String(mk.op * Math.min(1, iso.opacity / 0.8)), '0'); });
      map.triggerRepaint();
    },
    /** While it plays: rougher lines, no labels on them; all back on pause. */
    setMoving: function (on) {
      this.moving = !!on;
      if (!this.map) return;
      this.restyleIso();
      if (!on) this.redraw();
    }
  };

  // --- drawing by the graphics chip (opts.gpu) ---
  /* A layer of MapLibre's own (type custom) drawing one mesh over the
     world, Mercator 0..1, fine enough to follow the globe, with a row on
     each side reaching the pole. The fragment shader works out lat/lon and
     reads the fields from textures: the two forecast pictures and their
     share (u_mix), so a picture between two costs one number. Textures
     are uploaded in render(), where MapLibre expects the GL state to
     change, and kept while in use. */
  var MESH_X = 256, MESH_Y = 128, MERC_MAX_LAT = 85.0511;
  var FS_HEAD = [
    '#version 300 es',
    'precision highp float;',
    'in vec2 v_merc;',
    'out vec4 fragColor;',
    'const float PI = 3.141592653589793;',
    'uniform vec2 u_size;',
    // lat/lon of the fragment, and where it falls in a grid of u_size from 90N/180W
    'vec2 gridUv(out float lat) {',
    '  float lon = fract(v_merc.x) * 360.0 - 180.0;',
    '  lat = degrees(atan(sinh(PI * (1.0 - 2.0 * v_merc.y))));',
    '  return vec2((lon + 180.0) / 360.0 * (u_size.x - 1.0) + 0.5, (90.0 - lat) / 180.0 * (u_size.y - 1.0) + 0.5) / u_size;',
    '}'
  ].join('\n') + '\n';

  var PRES_FS = FS_HEAD + [
    'uniform sampler2D u_a, u_b, u_lut;',
    'uniform float u_mix, u_fill, u_lines, u_opacity, u_step, u_dpr, u_lutMin, u_lutSpan, u_width;',
    'uniform vec4 u_ink;',
    'void main() {',
    '  float lat; vec2 uv = gridUv(lat);',
    '  float p = 1000.0 + mix(texture(u_a, uv).r, texture(u_b, uv).r, u_mix);',
    '  vec4 col = vec4(0.0);',
    '  if (u_fill > 0.5) {',
    '    vec3 c = texture(u_lut, vec2((p - u_lutMin) / u_lutSpan, 0.5)).rgb;',
    '    col = vec4(c * u_opacity, u_opacity);',
    '  }',
    '  if (u_lines > 0.5) {',
    // The stored values go by 1/1.5 hPa: a flat area can sit right on a
    // level and would fill as a line; a hair off, it no longer does.
    '    float d = (p + 0.013) / u_step, w = fwidth(d);',
    '    float dist = abs(fract(d + 0.5) - 0.5) / max(w, 1e-5);',
    '    float level = floor(d + 0.5) * u_step, m20 = mod(level, 20.0), m4 = mod(level, 4.0);',
    '    bool major = m20 < 0.5 || m20 > 19.5, minor = m4 > 0.5 && m4 < 3.5;',
    '    float width = (major ? 1.3 : (minor ? 0.5 : 0.75)) * u_dpr * u_width;',
    '    float a = clamp(width * 0.5 + 0.5 - dist, 0.0, 1.0) * (minor ? 0.6 : 1.0) * u_ink.a;',
    '    col = vec4(u_ink.rgb * a, a) + col * (1.0 - a);',
    '  }',
    '  fragColor = col;',
    '}'
  ].join('\n');

  function mercY(lat) { return (1 - Math.log(Math.tan(Math.PI / 4 + lat * DEG / 2)) / Math.PI) / 2; }

  /** A custom layer drawing with fragment shader fs; draw(gl, u, layer)
      binds its textures and uniforms and says whether there is anything to
      draw. */
  function GLLayer(id, fs, draw) {
    this.id = id;
    this.type = 'custom';
    this.renderingMode = '2d';
    this.fs = fs;
    this.draw = draw;
    this.programs = {};
    this.drawn = -1;
    this.fade = 1;                    // 0..1 over the opacity (fading in or out)
    this.textures = new Map();        // data array -> { tex, used }
    this.frame = 0;
  }
  GLLayer.prototype = {
    onAdd: function (map, gl) {
      this.map = map;
      // x, y in Mercator (0..1) and the pole flag: the rows past the edges
      // reach the poles on the globe (as MapLibre's own tiles do) with the
      // colors of the edge; flat they are not drawn.
      var v = [];
      for (var j = -1; j <= MESH_Y + 1; j++) {
        var jj = Math.max(0, Math.min(MESH_Y, j));
        var y = mercY(MERC_MAX_LAT) + (mercY(-MERC_MAX_LAT) - mercY(MERC_MAX_LAT)) * jj / MESH_Y;
        for (var i = 0; i <= MESH_X; i++) v.push(i / MESH_X, y, j < 0 ? -1 : j > MESH_Y ? 1 : 0);
      }
      var idx = [];
      for (j = 0; j < MESH_Y + 2; j++) {
        for (i = 0; i < MESH_X; i++) {
          var k = j * (MESH_X + 1) + i;
          idx.push(k, k + 1, k + MESH_X + 1, k + 1, k + MESH_X + 2, k + MESH_X + 1);
        }
      }
      this.vbo = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(v), gl.STATIC_DRAW);
      this.ibo = gl.createBuffer();
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.ibo);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint32Array(idx), gl.STATIC_DRAW);
      this.count = idx.length;
    },
    onRemove: function (map, gl) {
      var self = this;
      this.textures.forEach(function (t) { gl.deleteTexture(t.tex); });
      this.textures.clear();
      Object.keys(this.programs).forEach(function (k) { gl.deleteProgram(self.programs[k].p); gl.deleteVertexArray(self.programs[k].vao); });
      gl.deleteBuffer(this.vbo);
      gl.deleteBuffer(this.ibo);
      // Made again by onAdd and program() if the layer is put back (new base map).
      this.programs = {};
      this.drawn = -1;
    },
    program: function (gl, sd) {
      var hit = this.programs[sd.variantName];
      if (hit) return hit;
      var vs = '#version 300 es\n' + sd.vertexShaderPrelude + '\n' + sd.define + '\n' +
        'in vec3 a_pos;\nuniform float u_shift;\nout vec2 v_merc;\n' +
        'void main() {\n' +
        '  v_merc = vec2(a_pos.x + u_shift, a_pos.y);\n' +
        '  vec2 raw = vec2(0.0, a_pos.z < -0.5 ? -32768.0 : (a_pos.z > 0.5 ? 32767.0 : 0.0));\n' +
        '  gl_Position = projectTile(v_merc, raw);\n' +
        '}';
      function sh(type, src) {
        var s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) console.warn('[gl] shader: ' + gl.getShaderInfoLog(s));
        return s;
      }
      var p = gl.createProgram();
      gl.attachShader(p, sh(gl.VERTEX_SHADER, vs));
      gl.attachShader(p, sh(gl.FRAGMENT_SHADER, this.fs));
      gl.linkProgram(p);
      if (!gl.getProgramParameter(p, gl.LINK_STATUS)) console.warn('[gl] link: ' + gl.getProgramInfoLog(p));
      var loc = {}, n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
      for (var i = 0; i < n; i++) {
        var name = gl.getActiveUniform(p, i).name.replace(/\[0\]$/, '');
        loc[name] = gl.getUniformLocation(p, name);
      }
      var vao = gl.createVertexArray();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
      var ap = gl.getAttribLocation(p, 'a_pos');
      gl.enableVertexAttribArray(ap);
      gl.vertexAttribPointer(ap, 3, gl.FLOAT, false, 0, 0);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.ibo);
      gl.bindVertexArray(null);
      hit = this.programs[sd.variantName] = { p: p, loc: loc, vao: vao };
      return hit;
    },
    /** The texture of a data array (made once): R16F floats, or RGBA8
        bytes (then nearest). unit: the texture unit it is bound to. */
    texture: function (gl, unit, data, w, h, kind) {
      var hit = this.textures.get(data);
      // The unit first: a new texture is bound to make it, and bound on the
      // unit still active it took the place of the one before (picture A
      // read as B for a frame, at every new picture).
      gl.activeTexture(gl.TEXTURE0 + unit);
      if (!hit) {
        var t0 = performance.now(), tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
        var filter = kind === 'rgba-nearest' ? gl.NEAREST : gl.LINEAR;
        if (kind === 'rgba' || kind === 'rgba-nearest') gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
        else if (kind === 'r8') gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, w, h, 0, gl.RED, gl.UNSIGNED_BYTE, data);
        else if (kind === 'rg') gl.texImage2D(gl.TEXTURE_2D, 0, gl.RG16F, w, h, 0, gl.RG, gl.FLOAT, data);
        else gl.texImage2D(gl.TEXTURE_2D, 0, gl.R16F, w, h, 0, gl.RED, gl.FLOAT, data);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        hit = { tex: tex, used: 0 };
        this.textures.set(data, hit);
        note(stats.upload, performance.now() - t0);
      }
      hit.used = this.frame;
      gl.bindTexture(gl.TEXTURE_2D, hit.tex);
      return hit.tex;
    },
    /** Drop the textures no draw has used for a few frames. */
    _sweep: function (gl) {
      var self = this;
      if (this.textures.size <= 6) return;
      this.textures.forEach(function (t, key) {
        if (self.frame - t.used > 2) { gl.deleteTexture(t.tex); self.textures.delete(key); }
      });
    },
    render: function (gl, args) {
      var t0 = performance.now(), sd = args.shaderData, pr = this.program(gl, sd), u = pr.loc, d = args.defaultProjectionData;
      this.frame++;
      gl.useProgram(pr.p);
      if (!this.draw(gl, u, this)) return;
      gl.uniformMatrix4fv(u.u_projection_matrix, false, d.mainMatrix);
      if (u.u_projection_fallback_matrix) gl.uniformMatrix4fv(u.u_projection_fallback_matrix, false, d.fallbackMatrix);
      if (u.u_projection_tile_mercator_coords) gl.uniform4fv(u.u_projection_tile_mercator_coords, d.tileMercatorCoords);
      if (u.u_projection_clipping_plane) gl.uniform4fv(u.u_projection_clipping_plane, d.clippingPlane);
      if (u.u_projection_transition) gl.uniform1f(u.u_projection_transition, d.projectionTransition);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      gl.disable(gl.DEPTH_TEST);
      gl.disable(gl.STENCIL_TEST);
      gl.disable(gl.CULL_FACE);
      gl.bindVertexArray(pr.vao);
      // Flat, the copies of the world on either side; on the globe one is all.
      var shifts = sd.variantName === 'globe' ? [0] : [-1, 0, 1];
      for (var k = 0; k < shifts.length; k++) {
        gl.uniform1f(u.u_shift, shifts[k]);
        gl.drawElements(gl.TRIANGLES, this.count, gl.UNSIGNED_INT, 0);
      }
      gl.bindVertexArray(null);
      this._sweep(gl);
      note(stats.render, performance.now() - t0);
    }
  };

  /** A palette of RGB triplets as RGBA bytes, made once per palette. */
  var rgbaOf = new WeakMap();
  function rgba(rgb) {
    var hit = rgbaOf.get(rgb);
    if (hit) return hit;
    var n = rgb.length / 3, out = new Uint8Array(n * 4);
    for (var i = 0; i < n; i++) { out[i * 4] = rgb[i * 3]; out[i * 4 + 1] = rgb[i * 3 + 1]; out[i * 4 + 2] = rgb[i * 3 + 2]; out[i * 4 + 3] = 255; }
    rgbaOf.set(rgb, out);
    return out;
  }

  // -- the pressure --
  var glShared = { grid: null, a: null, b: null, mix: 0, version: 0 };

  /* The smoothed pictures, as pressure - 1000 hPa (half floats keep 0.06
     hPa there), kept by forecast picture (its packed bytes, which last the
     whole session; the unpacked values are made again now and then), and
     made ahead while the page is idle: reaching a new picture used to
     smooth it in the middle of a frame (50 ms). */
  var texKept = new WeakMap(), texPending = new Set();

  function texOf(values, rows, cols) {
    var s = smoothHalf(values, rows, cols, opts.smooth), q = new Float32Array(s.values.length);
    for (var i = 0; i < q.length; i++) q[i] = s.values[i] - 1000;
    return { q: q, rows: s.rows, cols: s.cols, passes: opts.smooth };
  }

  /** The packed bytes of the picture these values come from (the values
      themselves when not found). */
  function partsOf(values) {
    var ids = ['isobars', 'pressure'];
    for (var n = 0; n < ids.length; n++) {
      var t = anim && anim.group.track(ids[n]), kept = t && t.frames.unpacked || [];
      for (var k = 0; k < kept.length; k++) if (kept[k].values === values) return t.frames.packed[kept[k].i];
    }
    return values;
  }

  function texData(g, values) {
    var key = partsOf(values), hit = texKept.get(key);
    if (hit && hit.passes === opts.smooth) return hit;
    hit = texOf(values, g.lats.length, g.lons.length);
    texKept.set(key, hit);
    return hit;
  }

  /* The next two pictures are smoothed by a worker, off the page's own
     thread: done in the page, even in its idle time, the 50 ms of a
     picture held the map back at every step. The worker gets the packed
     bytes and unpacks them as Frames does. */
  var texWorker = null, texJobs = new Map(), texJobId = 0;
  function worker() {
    if (texWorker !== null) return texWorker;
    try {
      var src = 'var smoothHalf = ' + smoothHalf.toString() + ';\n' +
        'onmessage = function (e) { var d = e.data, b = d.bytes, v = new Float32Array(b.length);\n' +
        '  for (var i = 0; i < b.length; i++) v[i] = b[i] === 255 ? NaN : d.min + b[i] / d.scale;\n' +
        '  var s = smoothHalf(v, d.rows, d.cols, d.passes);\n' +
        '  for (i = 0; i < s.values.length; i++) s.values[i] -= 1000;\n' +
        '  postMessage({ id: d.id, q: s.values, rows: s.rows, cols: s.cols, passes: d.passes }, [s.values.buffer]); };';
      texWorker = new Worker(URL.createObjectURL(new Blob([src], { type: 'text/javascript' })));
      texWorker.onmessage = function (e) {
        var d = e.data, parts = texJobs.get(d.id);
        texJobs.delete(d.id);
        if (!parts) return;
        texPending.delete(parts);
        if (!texKept.has(parts)) texKept.set(parts, { q: d.q, rows: d.rows, cols: d.cols, passes: d.passes });
      };
    } catch (err) {
      console.warn('[pres] no worker: ' + err);
      texWorker = false;
    }
    return texWorker;
  }

  /** The next two pictures smoothed ahead, by the worker. */
  function warmTex() {
    var t = anim && (anim.group.track('isobars') || anim.group.track('pressure')), w = worker();
    if (!t || !t.frames.meta || !w) return;
    var fr = t.frames, i = Math.floor(anim.player.index), m = fr.meta;
    [i + 1, i + 2].forEach(function (k) {
      var parts = fr.packed[k];
      if (!parts || texPending.has(parts) || (texKept.get(parts) || {}).passes === opts.smooth) return;
      texPending.add(parts);
      var id = ++texJobId;
      texJobs.set(id, parts);
      w.postMessage({ id: id, bytes: parts[0], rows: m.lats.length, cols: m.lons.length, passes: opts.smooth, min: P_MIN, scale: P_SCALE });
    });
  }

  var arrIds = new WeakMap(), arrNext = 0;
  function arrId(x) { if (!x) return 0; var k = arrIds.get(x); if (!k) { k = ++arrNext; arrIds.set(x, k); } return k; }
  window.presDrawLog = [];
  function drawLog(e) { var L = window.presDrawLog; L.push(e); if (L.length > 4000) L.shift(); }

  function presDraw(mode) {
    return function (gl, u, layer) {
      if (!glShared.a) return false;
      var a = texData(glShared.grid, glShared.a), b = texData(glShared.grid, glShared.b);
      layer.texture(gl, 0, a.q, a.cols, a.rows); gl.uniform1i(u.u_a, 0);
      layer.texture(gl, 1, b.q, b.cols, b.rows); gl.uniform1i(u.u_b, 1);
      if (mode === 'fill') {
        lut = lut || buildLut();
        layer.texture(gl, 2, rgba(lut), LUT_N, 1, 'rgba'); gl.uniform1i(u.u_lut, 2);
      }
      gl.uniform2f(u.u_size, a.cols, a.rows);
      gl.uniform1f(u.u_mix, glShared.mix);
      drawLog({ t: performance.timeOrigin + performance.now(), mode: mode, a: arrId(glShared.a), b: arrId(glShared.b), qa: arrId(a.q), qb: arrId(b.q), mix: +glShared.mix.toFixed(3), pos: anim ? +anim.player.index.toFixed(3) : -1 });
      gl.uniform1f(u.u_fill, mode === 'fill' ? 1 : 0);
      gl.uniform1f(u.u_lines, mode === 'lines' ? 1 : 0);
      gl.uniform1f(u.u_opacity, opts.opacity * layer.fade);
      gl.uniform1f(u.u_step, layer.map.getZoom() >= opts.minorZoom ? opts.step / 2 : opts.step);
      gl.uniform1f(u.u_dpr, window.devicePixelRatio || 1);
      gl.uniform1f(u.u_lutMin, LUT_MIN);
      gl.uniform1f(u.u_lutSpan, LUT_N * LUT_STEP);
      if (u.u_width) gl.uniform1f(u.u_width, iso.width);
      var ink = isoInk().rgb;
      gl.uniform4f(u.u_ink, ink[0], ink[1], ink[2], mode === 'lines' ? iso.opacity : 0.8);
      layer.drawn = glShared.version;
      return true;
    };
  }

  /** Both pressure layers take the picture at once. */
  function glShow(grid) {
    glShared.grid = grid;
    glShared.a = grid.values;
    glShared.b = grid.valuesB && grid.mix > 0 ? grid.valuesB : grid.values;
    glShared.mix = grid.valuesB ? grid.mix || 0 : 0;
    glShared.version++;
    warmTex();
  }

  function FillLayerGL() { this.map = null; this.grid = null; this.gl = new GLLayer('lv-pres-gl', PRES_FS, presDraw('fill')); }
  FillLayerGL.prototype = {
    addTo: function (map) { this.map = map; map.addLayer(this.gl, beforeLines(map)); _widgetAdapter.setLines('pressure', true); return this; },
    remove: function () {
      if (!this.map) return;
      if (this.map.getLayer('lv-pres-gl')) this.map.removeLayer('lv-pres-gl');
      _widgetAdapter.setLines('pressure', false);
      this.map = null;
    },
    showFile: function (grid) { this.grid = grid; glShow(grid); if (this.map) this.map.triggerRepaint(); },
    restyle: function () { readdGL(this.map, this.gl, true); },
    redraw: function () { lut = null; if (this.map) this.map.triggerRepaint(); },
    setFade: function (f) { this.gl.fade = f; if (this.map) this.map.triggerRepaint(); },
    settled: function () { return this.gl.drawn === glShared.version; },
    reload: function () {}
  };

  /** Isobars by the chip; the values on them (CPU lines, labels only) and
      the highs and lows as before. */
  function IsobarLayerGL() { IsobarLayer.call(this); this.gl = new GLLayer('lv-iso-gl', PRES_FS, presDraw('lines')); }
  IsobarLayerGL.prototype = Object.create(IsobarLayer.prototype);
  IsobarLayerGL.prototype.addTo = function (map) {
    IsobarLayer.prototype.addTo.call(this, map);
    // The lines come from the chip: MapLibre keeps only the values on them.
    map.removeLayer('lv-iso');
    map.addLayer(this.gl, 'lv-iso-label');
    return this;
  };
  IsobarLayerGL.prototype.remove = function () {
    if (this.map && this.map.getLayer('lv-iso-gl')) this.map.removeLayer('lv-iso-gl');
    IsobarLayer.prototype.remove.call(this);
  };
  IsobarLayer.prototype.restyle = function () { readd(this); };
  FillLayer.prototype.restyle = function () { readd(this); };
  IsobarLayerGL.prototype.showFile = function (grid) {
    this.grid = grid;
    glShow(grid);
    var track = anim && anim.group.track('isobars'), pos = anim ? anim.player.index : -1;
    this._marks(track && pos >= 0 ? trackedMarks(track.frames, pos) : []);
    if (!this.moving) IsobarLayer.prototype.redraw.call(this);
    if (this.map) this.map.triggerRepaint();
  };
  IsobarLayerGL.prototype.redraw = function () {
    if (this.grid && !this.moving) IsobarLayer.prototype.redraw.call(this);
    if (this.map) this.map.triggerRepaint();
  };
  IsobarLayerGL.prototype.settled = function () {
    return this.gl.drawn === glShared.version && (this.moving || this.loaded === this.version);
  };

  // Legend of the pressure colors, as the temperature's (same place, same
  // look: the two never show together), its colors as light as the layer.
  var PRES_LEGEND_LO = 950, PRES_LEGEND_HI = 1050, presLegend = null;
  (function () {
    var css = document.createElement('style');
    css.textContent = [
      '#lv-pres-legend { position: absolute; top: 8px; left: 50%; transform: translateX(-50%); z-index: 5; pointer-events: none;',
      '  display: grid; grid-template-columns: 240px auto; column-gap: 6px; padding: 3px 8px 5px; border-radius: 6px;',
      '  font: 11px var(--font-ui, sans-serif); background: rgba(20, 22, 28, 0.72); color: #eee; }',
      'body[data-theme="light"] #lv-pres-legend { background: rgba(255, 255, 255, 0.82); color: #222; }',
      '#lv-pres-legend .lv-temp-ticks { grid-column: 1; grid-row: 1; position: relative; height: 14px; }',
      '#lv-pres-legend .lv-temp-ticks span { position: absolute; transform: translateX(-50%); white-space: nowrap; }',
      '#lv-pres-legend .lv-temp-bar { grid-column: 1; grid-row: 2; width: 240px; height: 8px; border-radius: 2px; }',
      '#lv-pres-legend .lv-temp-unit { grid-column: 2; grid-row: 2; align-self: center; }',
      '@media (max-width: 320px) { #lv-pres-legend { display: none; } }'
    ].join('\n');
    document.head.appendChild(css);
  })();
  function showPresLegend(map) {
    if (presLegend) return;
    lut = lut || buildLut();
    presLegend = document.createElement('div');
    presLegend.id = 'lv-pres-legend';
    var ticks = [];
    for (var p = 960; p <= 1040; p += 20) {
      ticks.push('<span style="left:' + ((p - PRES_LEGEND_LO) / (PRES_LEGEND_HI - PRES_LEGEND_LO) * 100).toFixed(2) + '%">' + p + '</span>');
    }
    presLegend.innerHTML = '<div class="lv-temp-ticks">' + ticks.join('') + '</div><span class="lv-temp-unit">hPa</span>';
    var bar = document.createElement('canvas'), g = bar.getContext('2d'), W = 240;
    bar.width = W;
    bar.height = 10;
    bar.className = 'lv-temp-bar';
    bar.style.opacity = String(opts.opacity);
    for (var x = 0; x < W; x++) {
      var v = PRES_LEGEND_LO + (x + 0.5) / W * (PRES_LEGEND_HI - PRES_LEGEND_LO);
      var i = Math.max(0, Math.min(LUT_N - 1, Math.round((v - LUT_MIN) / LUT_STEP))) * 3;
      g.fillStyle = 'rgb(' + lut[i] + ',' + lut[i + 1] + ',' + lut[i + 2] + ')';
      g.fillRect(x, 0, 1, 10);
    }
    presLegend.appendChild(bar);
    (document.getElementById('lv-map') || map.getContainer()).appendChild(presLegend);
  }
  function hidePresLegend() {
    if (presLegend) presLegend.remove();
    presLegend = null;
  }
  ANIM_LAYERS.pressure = function (m) {
    var layer = (opts.gpu ? new FillLayerGL() : new FillLayer()).addTo(m), plainRemove = layer.remove;
    showPresLegend(m);
    layer.remove = function () { hidePresLegend(); return plainRemove.apply(this, arguments); };
    var plainFade = layer.setFade;
    layer.setFade = function (f) { if (presLegend) presLegend.style.opacity = String(f); return plainFade.call(this, f); };
    return layer;
  };
  ANIM_LAYERS.isobars = function (m) { return (opts.gpu ? new IsobarLayerGL() : new IsobarLayer()).addTo(m); };

  // The Ctrl readout gets the pressure too: a barometer dial in the color
  // of the pressure there, its needle from 960 hPa (left) to 1050 (right).
  function barometer(p) {
    var a = Math.max(-120, Math.min(120, (p - 1005) / 45 * 120));
    return '<svg viewBox="0 0 16 16" width="20" height="20">' +
      '<circle cx="8" cy="8" r="7" fill="currentColor" stroke="rgba(255,255,255,0.6)" stroke-width="0.8"/>' +
      '<g transform="rotate(' + a.toFixed(0) + ' 8 8)"><path d="M8 8.6V2.6" stroke="rgba(0,0,0,0.75)" stroke-width="1.4" stroke-linecap="round"/></g>' +
      '<circle cx="8" cy="8" r="1.3" fill="rgba(0,0,0,0.75)"/></svg>';
  }
  function colorOf(p) {
    lut = lut || buildLut();
    var i = Math.max(0, Math.min(LUT_N - 1, Math.round((p - LUT_MIN) / LUT_STEP))) * 3;
    return 'rgb(' + lut[i] + ', ' + lut[i + 1] + ', ' + lut[i + 2] + ')';
  }
  var plainReadout = readoutHtml;
  readoutHtml = function () {
    var html = plainReadout(), map = _widgetAdapter.getMap();
    var t = anim && (anim.group.track('pressure') || anim.group.track('isobars'));
    if (!t || !t.layer.grid || !map || !readout.known) return html;
    // Inside the map and on the globe, as for the other lines.
    var c = map.getContainer().getBoundingClientRect(), x = readout.x - c.left, y = readout.y - c.top;
    if (x < 0 || y < 0 || x > c.width || y > c.height) return html;
    var ll = map.unproject([x, y]);
    if (!ll || !isFinite(ll.lat) || Math.abs(ll.lat) > 85) return html;
    var back = map.project(ll);
    if (Math.abs(back.x - x) > 1 || Math.abs(back.y - y) > 1) return html;
    var p = sample(t.layer.grid, ll.lat, ll.lng);
    if (!isFinite(p)) return html;
    return html + '<div class="lv-readout-row"><span class="lv-readout-icon" style="color:' + colorOf(p) + '">' + barometer(p) +
      '</span><span>' + localNumber(p, 1) + ' hPa</span></div>';
  };

  return { contours: contours, extrema: extrema, smoothHalf: smoothHalf, opts: opts, GLLayer: GLLayer, readdGL: readdGL, FS_HEAD: FS_HEAD, beforeOverlays: beforeOverlays, beforeLines: beforeLines, beforeIsobars: beforeIsobars, sample: sample };
})();
