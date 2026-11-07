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
     UTC hour h holds. */
  var TABLE = [
    { id: 'meteofrance_arome_france0025', label: 'AROME', every: 3, range: function () { return 51; } },
    { id: 'dwd_icon_d2', label: 'ICON-D2', every: 3, range: function () { return 48; } },
    { id: 'italia_meteo_arpae_icon_2i', label: 'ICON-2I', every: 12, range: function () { return 72; } },
    { id: 'jma_msm', label: 'MSM', every: 3, range: function (h) { return h % 12 === 0 ? 78 : 39; } },
    { id: 'meteoswiss_icon_ch1', label: 'ICON-CH1', every: 3, range: function () { return 33; } },
    { id: 'cmc_gem_hrdps', label: 'HRDPS', every: 6, range: function () { return 48; } },
    { id: 'ncep_hrrr_conus', label: 'HRRR', every: 1, range: function (h) { return h % 6 === 0 ? 48 : 18; } },
    { id: 'ukmo_uk_deterministic_2km', label: 'UKV', every: 1, range: function (h) { return h % 3 === 0 ? 54 : 12; } },
    // 56 to 58 hours depending on the run: the shortest.
    { id: 'metno_nordic_pp', label: 'MEPS', every: 1, range: function () { return 56; } }
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
      id: t.id, label: t.label, every: t.every, range: t.range, grid: g, res: g.res, order: k,
      step: g.nx * g.ny > MAX_POINTS ? 2 : 1,
      // The latitudes and longitudes it covers, worked out once.
      bounds: function () { return box || (box = Grids.bounds(g)); }
    };
    byId[t.id] = m;
    return m;
  }).sort(function (a, b) { return a.res - b.res || a.order - b.order; });

  function get(id) { return byId[id] || null; }

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

  return { list: list, get: get, runFor: runFor, hasFile: hasFile, coverage: coverage, pickForView: pickForView };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetModels; }
