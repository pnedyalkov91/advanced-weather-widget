// ==========================================================================
// Glue script 2c'': the regional models drawn over the global one, finest
// first: their grid (WidgetGrids), how often their runs start and how far
// each one goes, as the open-data bucket held them on 2026-11-07 (about
// eleven days of runs kept, one file an hour, temperature_2m in all).
// WidgetModels is loadable under Node for tests.
// ==========================================================================
var WidgetModels = (function () {
  'use strict';

  var HOUR = 3600e3;
  var Grids = typeof WidgetGrids !== 'undefined' ? WidgetGrids : require('./glue-grids.js');

  /* id, label, every (hours between runs), range(h): the hours run of
     UTC hour h holds; wind: how the files give the 10 m wind, 'uv' (east
     and north components), 'uv-grid' (along the grid's axes, turned to
     true north here; Open-Meteo's API does so for HRRR) or 'sd' (speed,
     and direction it blows from). Checked against the API on 2026-11-07. */
  var TABLE = [
    { id: 'meteofrance_arome_france0025', label: 'AROME', every: 3, range: function () { return 51; }, wind: 'uv' },
    { id: 'dwd_icon_d2', label: 'ICON-D2', every: 3, range: function () { return 48; }, wind: 'uv' },
    { id: 'italia_meteo_arpae_icon_2i', label: 'ICON-2I', every: 12, range: function () { return 72; }, wind: 'sd' },
    { id: 'jma_msm', label: 'MSM', every: 3, range: function (h) { return h % 12 === 0 ? 78 : 39; }, wind: 'uv' },
    { id: 'meteoswiss_icon_ch1', label: 'ICON-CH1', every: 3, range: function () { return 33; }, wind: 'uv' },
    { id: 'cmc_gem_hrdps', label: 'HRDPS', every: 6, range: function () { return 48; }, wind: 'sd' },
    { id: 'ncep_hrrr_conus', label: 'HRRR', every: 1, range: function (h) { return h % 6 === 0 ? 48 : 18; }, wind: 'uv-grid' },
    { id: 'ukmo_uk_deterministic_2km', label: 'UKV', every: 1, range: function (h) { return h % 3 === 0 ? 54 : 12; }, wind: 'sd' },
    // 56 to 58 hours depending on the run: the shortest.
    { id: 'metno_nordic_pp', label: 'MEPS', every: 1, range: function () { return 56; }, wind: 'sd' }
  ];

  var SCAN_H = 96;              // how far back a run is looked for
  var MAX_POINTS = 2e6;         // larger grids are read one point in two
  var VIEW_MAX_DEG = 60;        // no regional model in a view wider than this
  var VIEW_MAX_MODELS = 3;
  var MIN_SHARE = 0.02;         // a model covering less of the view is left out
  var SAMPLES = 12;             // points each way the view is probed with

  var byId = {};
  var list = TABLE.map(function (t, k) {
    var g = Grids.of(t.id), box = null;
    var m = {
      id: t.id, label: t.label, every: t.every, range: t.range, wind: t.wind, grid: g, res: g.res, order: k,
      step: g.nx * g.ny > MAX_POINTS ? 2 : 1,
      // The latitudes and longitudes it covers, worked out once.
      bounds: function () { return box || (box = Grids.bounds(g)); }
    };
    byId[t.id] = m;
    return m;
  }).sort(function (a, b) { return a.res - b.res || a.order - b.order; });

  function get(id) { return byId[id] || null; }

  // The short names of the global models the layers start from.
  var GLOBAL_LABELS = { ecmwf_ifs025: 'ECMWF', gfs_global: 'GFS', icon_global: 'ICON' };

  /** The models drawn, for a reader: global model baseId, then the finer
      ones of fineIds in their order (unknown ids left out). */
  function labels(baseId, fineIds) {
    return [GLOBAL_LABELS[baseId] || baseId].concat((fineIds || []).map(get).filter(Boolean).map(function (m) { return m.label; }));
  }

  /** The share of view { south, west, north, east } inside model m's grid,
      probed at SAMPLES x SAMPLES points. */
  function coverage(m, view) {
    var b = m.bounds(), inside = 0;
    if (view.north < b.south || view.south > b.north) return 0;
    for (var i = 0; i < SAMPLES; i++) {
      var lat = view.south + (view.north - view.south) * (i + 0.5) / SAMPLES;
      for (var j = 0; j < SAMPLES; j++) {
        var lon = view.west + (view.east - view.west) * (j + 0.5) / SAMPLES;
        if (Grids.index(m.grid, lat, lon).col >= 0) inside++;
      }
    }
    return inside / (SAMPLES * SAMPLES);
  }

  /** The models to draw over view { south, west, north, east }: none when
      it is wider than VIEW_MAX_DEG; else the VIEW_MAX_MODELS covering most
      of it (each at least MIN_SHARE), finest first. */
  function pickForView(view, opts) {
    opts = opts || {};
    var maxDeg = opts.maxDeg || VIEW_MAX_DEG, max = opts.max || VIEW_MAX_MODELS;
    if (view.east - view.west > maxDeg) return [];
    return list.map(function (m) { return { m: m, share: coverage(m, view) }; })
      .filter(function (c) { return c.share >= MIN_SHARE; })
      .sort(function (a, b) { return b.share - a.share || a.m.res - b.m.res; })
      .slice(0, max)
      .sort(function (a, b) { return a.m.res - b.m.res || a.m.order - b.m.order; })
      .map(function (c) { return c.m.id; });
  }

  function hourOf(ms) { return new Date(ms).getUTCHours(); }

  /** The run validMs is read from: the newest one, no newer than the
      latest published, that starts at or before it and reaches it; null
      when none does. */
  function runFor(id, validMs, latestRefMs) {
    var m = byId[id];
    if (!m || validMs == null) return null;
    var r = Math.floor(Math.min(validMs, latestRefMs) / HOUR) * HOUR;
    for (var k = 0; k <= SCAN_H; k++, r -= HOUR) {
      var h = hourOf(r);
      if (h % m.every === 0 && validMs - r <= m.range(h) * HOUR) return r;
    }
    return null;
  }

  /** Whether run runMs has a file for validMs. */
  function hasFile(id, validMs, runMs) {
    var m = byId[id];
    if (!m || validMs == null || runMs == null) return false;
    var lead = validMs - runMs;
    return lead >= 0 && lead % HOUR === 0 && lead <= m.range(hourOf(runMs)) * HOUR && hourOf(runMs) % m.every === 0;
  }

  var DEG = Math.PI / 180;

  /** The variables a model's 10 m wind is read from. */
  function windVars(id) {
    return byId[id].wind === 'sd' ? ['wind_speed_10m', 'wind_direction_10m'] : ['wind_u_component_10m', 'wind_v_component_10m'];
  }

  var turns = {};

  /** Cosine and sine of the angle a grid's north makes with true north at
      each point of a Lambert conformal grid: n times the longitude from
      its central meridian. Worked out once per model. */
  function gridTurn(id, d) {
    if (turns[id]) return turns[id];
    var n = d.nx * d.ny, cos = new Float32Array(n), sin = new Float32Array(n), p = d.proj;
    for (var r = 0; r < d.ny; r++) {
      for (var c = 0; c < d.nx; c++) {
        var lon = Grids.lonLatAt(d, c, r).lon, dl = ((lon - p.lon0 / DEG + 540) % 360) - 180, a = p.n * dl * DEG;
        cos[r * d.nx + c] = Math.cos(a);
        sin[r * d.nx + c] = Math.sin(a);
      }
    }
    return (turns[id] = { cos: cos, sin: sin });
  }

  /** A model's 10 m wind as read (a, b: its two variables, on its full grid
      d) as { u, v } toward the east and the north, in m/s. */
  function toEarthWind(id, a, b, d) {
    var kind = byId[id].wind, n = a.length, u, v, i;
    if (kind === 'uv') return { u: a, v: b };
    u = new Float32Array(n); v = new Float32Array(n);
    if (kind === 'sd') {
      for (i = 0; i < n; i++) {
        var dir = b[i] * DEG;
        u[i] = -a[i] * Math.sin(dir);
        v[i] = -a[i] * Math.cos(dir);
      }
      return { u: u, v: v };
    }
    var t = gridTurn(id, d);
    for (i = 0; i < n; i++) {
      u[i] = a[i] * t.cos[i] + b[i] * t.sin[i];
      v[i] = -a[i] * t.sin[i] + b[i] * t.cos[i];
    }
    return { u: u, v: v };
  }

  return {
    list: list, get: get, runFor: runFor, hasFile: hasFile, coverage: coverage, pickForView: pickForView, labels: labels,
    windVars: windVars, toEarthWind: toEarthWind
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetModels; }
