// ==========================================================================
// Glue script 2c': the grids of the regional models, whatever their
// projection: plain latitude/longitude, rotated latitude/longitude, Lambert
// conformal conic, Lambert azimuthal equal-area. A grid is a descriptor
// { id, kind, nx, ny, x0, y0, dx, dy, proj, res }: point (col, row) of a
// file sits at x0 + col * dx, y0 + row * dy in the projection's own
// coordinates (degrees, or metres), row 0 the southern one, as the files
// hold them. The parameters are those Open-Meteo gives its grids; the
// projections are the usual spherical ones (radius 6371229 m).
// WidgetGrids is loadable under Node for tests.
// ==========================================================================
var WidgetGrids = (function () {
  'use strict';

  var DEG = Math.PI / 180, R = 6371229;

  function wrap180(lon) { return ((lon + 180) % 360 + 360) % 360 - 180; }

  /* --- projections: forward(lat, lon) -> { x, y }, inverse(x, y) -> { lat, lon } --- */

  /** Rotated latitude/longitude, the south pole of the grid at
      (lat, lon) as Open-Meteo writes it: the sphere turned by
      90 + lat degrees about y, lon degrees about z. */
  function rotated(lat, lon) {
    var t = (90 + lat) * DEG, p = lon * DEG;
    return { kind: 'rotated', ct: Math.cos(t), st: Math.sin(t), cp: Math.cos(p), sp: Math.sin(p) };
  }

  /** Lambert conformal conic on the sphere: meridian lon0, latitude of
      origin lat0, standard parallels lat1 and lat2 (equal: a tangent cone). */
  function lcc(lon0, lat0, lat1, lat2) {
    var f1 = lat1 * DEG, f2 = lat2 * DEG, t = function (f) { return Math.tan(Math.PI / 4 + f / 2); };
    var n = Math.abs(lat1 - lat2) < 1e-9 ? Math.sin(f1) : Math.log(Math.cos(f1) / Math.cos(f2)) / Math.log(t(f2) / t(f1));
    var F = Math.cos(f1) * Math.pow(t(f1), n) / n;
    return { kind: 'lcc', lon0: lon0 * DEG, n: n, F: F, rho0: F / Math.pow(t(lat0 * DEG), n) };
  }

  /** Lambert azimuthal equal-area on the sphere, centered on (lat1, lon0). */
  function laea(lon0, lat1) {
    var f = lat1 * DEG;
    return { kind: 'laea', lon0: lon0 * DEG, s1: Math.sin(f), c1: Math.cos(f) };
  }

  function forward(proj, lat, lon) {
    var f = lat * DEG, l = lon * DEG;
    if (proj.kind === 'rotated') {
      var x = Math.cos(l) * Math.cos(f), y = Math.sin(l) * Math.cos(f), z = Math.sin(f);
      var x2 = proj.ct * proj.cp * x + proj.ct * proj.sp * y + proj.st * z;
      var y2 = -proj.sp * x + proj.cp * y;
      var z2 = -proj.st * proj.cp * x - proj.st * proj.sp * y + proj.ct * z;
      return { x: -Math.atan2(y2, x2) / DEG, y: -Math.asin(Math.max(-1, Math.min(1, z2))) / DEG };
    }
    var dl = wrap180(lon - proj.lon0 / DEG) * DEG;
    if (proj.kind === 'lcc') {
      var rho = proj.F / Math.pow(Math.tan(Math.PI / 4 + f / 2), proj.n), th = proj.n * dl;
      return { x: R * rho * Math.sin(th), y: R * (proj.rho0 - rho * Math.cos(th)) };
    }
    var cf = Math.cos(f), sf = Math.sin(f), cd = Math.cos(dl);
    var k = Math.sqrt(2 / (1 + proj.s1 * sf + proj.c1 * cf * cd));
    return { x: R * k * cf * Math.sin(dl), y: R * k * (proj.c1 * sf - proj.s1 * cf * cd) };
  }

  function inverse(proj, x, y) {
    if (proj.kind === 'rotated') {
      // The rotation undone: the grid's point on the turned sphere, turned back.
      var lr = -x * DEG, fr = -y * DEG;
      var x2 = Math.cos(fr) * Math.cos(lr), y2 = Math.cos(fr) * Math.sin(lr), z2 = Math.sin(fr);
      var gx = proj.ct * proj.cp * x2 - proj.sp * y2 - proj.st * proj.cp * z2;
      var gy = proj.ct * proj.sp * x2 + proj.cp * y2 - proj.st * proj.sp * z2;
      var gz = proj.st * x2 + proj.ct * z2;
      return { lat: Math.asin(Math.max(-1, Math.min(1, gz))) / DEG, lon: wrap180(Math.atan2(gy, gx) / DEG) };
    }
    if (proj.kind === 'lcc') {
      var xs = x / R, ys = proj.rho0 - y / R, s = proj.n < 0 ? -1 : 1;
      var rho = s * Math.sqrt(xs * xs + ys * ys), th = Math.atan2(s * xs, s * ys);
      return { lat: (2 * Math.atan(Math.pow(proj.F / rho, 1 / proj.n)) - Math.PI / 2) / DEG, lon: wrap180((proj.lon0 + th / proj.n) / DEG) };
    }
    var p = Math.sqrt(x * x + y * y);
    if (p < 1e-9) return { lat: Math.asin(proj.s1) / DEG, lon: wrap180(proj.lon0 / DEG) };
    var c = 2 * Math.asin(Math.min(1, p / (2 * R))), sc = Math.sin(c), cc = Math.cos(c);
    return {
      lat: Math.asin(cc * proj.s1 + y * sc * proj.c1 / p) / DEG,
      lon: wrap180((proj.lon0 + Math.atan2(x * sc, p * proj.c1 * cc - y * proj.s1 * sc)) / DEG)
    };
  }

  /* --- grids --- */

  var KM_PER_DEG = R * DEG;   // metres along a degree of a great circle

  /** A plain latitude/longitude grid from its south-west point. */
  function latlon(o) {
    return { id: o.id || null, kind: 'latlon', nx: o.nx, ny: o.ny, x0: o.west, y0: o.south, dx: o.dLon, dy: o.dLat, proj: null, res: (o.dLon + o.dLat) / 2 };
  }

  /** A projected grid from its first point (x0, y0) and steps, in the
      projection's coordinates; or, with sw and ne ([lat, lon] of its first
      and last points), from those. */
  function projected(o) {
    var x0 = o.x0, y0 = o.y0, dx = o.dx, dy = o.dy;
    if (o.sw) {
      var a = forward(o.proj, o.sw[0], o.sw[1]), b = forward(o.proj, o.ne[0], o.ne[1]);
      x0 = a.x; y0 = a.y; dx = (b.x - a.x) / (o.nx - 1); dy = (b.y - a.y) / (o.ny - 1);
    }
    var step = (Math.abs(dx) + Math.abs(dy)) / 2;
    return { id: o.id || null, kind: o.proj.kind, nx: o.nx, ny: o.ny, x0: x0, y0: y0, dx: dx, dy: dy, proj: o.proj, res: o.proj.kind === 'rotated' ? step : step / KM_PER_DEG };
  }

  /** Where lat/lon falls in grid d: { col, row }, fractional; NaN for both
      outside it. */
  function index(d, lat, lon) {
    var x, y;
    if (d.kind === 'latlon') {
      x = lon;
      y = lat;
    } else {
      var p = forward(d.proj, lat, lon);
      x = p.x; y = p.y;
    }
    // Longitudes (plain or rotated) on the copy of the world the grid is
    // on; their steps can go west (dx < 0).
    if (d.kind === 'latlon' || d.kind === 'rotated') {
      var mid = d.x0 + (d.nx - 1) * d.dx / 2;
      x = mid + wrap180(x - mid);
    }
    var col = (x - d.x0) / d.dx, row = (y - d.y0) / d.dy, e = 1e-9;
    if (!(col >= -e && col <= d.nx - 1 + e && row >= -e && row <= d.ny - 1 + e)) return { col: NaN, row: NaN };
    return { col: Math.max(0, Math.min(d.nx - 1, col)), row: Math.max(0, Math.min(d.ny - 1, row)) };
  }

  /** Latitude and longitude of point (col, row) of grid d. */
  function lonLatAt(d, col, row) {
    var x = d.x0 + col * d.dx, y = d.y0 + row * d.dy;
    if (d.kind === 'latlon') return { lat: y, lon: x };
    return inverse(d.proj, x, y);
  }

  /** The latitudes and longitudes grid d spans, from its edges. */
  function bounds(d) {
    var b = { south: 90, west: 180, north: -90, east: -180 };
    function add(c, r) {
      var p = lonLatAt(d, c, r);
      b.south = Math.min(b.south, p.lat); b.north = Math.max(b.north, p.lat);
      b.west = Math.min(b.west, p.lon); b.east = Math.max(b.east, p.lon);
    }
    var sx = Math.max(1, Math.floor((d.nx - 1) / 400)), sy = Math.max(1, Math.floor((d.ny - 1) / 400)), i;
    for (i = 0; i < d.nx; i += sx) { add(i, 0); add(i, d.ny - 1); }
    for (i = 0; i < d.ny; i += sy) { add(0, i); add(d.nx - 1, i); }
    add(d.nx - 1, 0); add(d.nx - 1, d.ny - 1); add(0, d.ny - 1);
    return b;
  }

  /** Value of a field of grid d (values row by row, south row first) at
      lat/lon: bilinear; NaN outside the grid or next to a missing value. */
  function sample(d, values, lat, lon) {
    var c = cell(d, lat, lon);
    return c ? valueAt(values, c) : NaN;
  }

  /** The cell of grid d lat/lon falls in, { k (its south-west point), nx,
      fr, fc }, for valueAt(); null outside the grid. Found once, it serves
      every field of the grid at that point. */
  function cell(d, lat, lon) {
    var p = index(d, lat, lon);
    if (!(p.col >= 0)) return null;
    var nx = d.nx, i0 = Math.min(d.ny - 2, Math.floor(p.row)), j0 = Math.min(nx - 2, Math.floor(p.col));
    return { k: i0 * nx + j0, nx: nx, fr: p.row - i0, fc: p.col - j0 };
  }

  /** Bilinear value of a field in cell c; NaN next to a missing value. */
  function valueAt(values, c) {
    var k = c.k, nx = c.nx, fc = c.fc;
    var bottom = values[k] * (1 - fc) + values[k + 1] * fc;
    var top = values[k + nx] * (1 - fc) + values[k + nx + 1] * fc;
    return bottom * (1 - c.fr) + top * c.fr;
  }

  // The regional models, as Open-Meteo sets their grids (checked against
  // the bounding boxes of their latest.json on 2026-11-07).
  var MODELS = {
    meteofrance_arome_france0025: function () { return latlon({ nx: 1121, ny: 717, south: 37.5, west: -12, dLon: 0.025, dLat: 0.025 }); },
    dwd_icon_d2: function () { return latlon({ nx: 1215, ny: 746, south: 43.18, west: -3.94, dLon: 0.02, dLat: 0.02 }); },
    italia_meteo_arpae_icon_2i: function () { return latlon({ nx: 761, ny: 761, south: 33.7, west: 3, dLon: 0.025, dLat: 0.02 }); },
    jma_msm: function () { return latlon({ nx: 481, ny: 505, south: 22.4, west: 120, dLon: 0.0625, dLat: 0.05 }); },
    meteoswiss_icon_ch1: function () {
      return projected({ nx: 1089, ny: 705, proj: rotated(43, 190), x0: -6.46, y0: -4.06, dx: 0.01, dy: 0.01 });
    },
    cmc_gem_hrdps: function () {
      return projected({ nx: 2540, ny: 1290, proj: rotated(-36.0885, 245.305), sw: [39.626034, -133.62952], ne: [47.876457, -40.708557] });
    },
    ncep_hrrr_conus: function () {
      return projected({ nx: 1799, ny: 1059, proj: lcc(-97.5, 0, 38.5, 38.5), sw: [21.138, -122.72], ne: [47.8424, -60.918] });
    },
    ukmo_uk_deterministic_2km: function () {
      return projected({ nx: 1042, ny: 970, proj: laea(-2.5, 54.9), x0: -1158000, y0: -1036000, dx: 2000, dy: 2000 });
    },
    metno_nordic_pp: function () {
      return projected({ nx: 1796, ny: 2321, proj: lcc(15, 63, 63, 63), sw: [52.30272, 1.9184653], ne: [72.18527, 41.764282] });
    }
  };
  var made = {};

  /** The grid of model id (one object per model), null for a model not
      listed (a global one); with a file's ny and nx, an error when they
      are not the grid's. */
  function of(id, ny, nx) {
    if (!MODELS[id]) return null;
    var d = made[id];
    if (!d) { d = made[id] = MODELS[id](); d.id = id; }
    if (ny != null && (d.ny !== ny || d.nx !== nx)) throw new Error(id + ' is ' + d.ny + ' x ' + d.nx + ', the file ' + ny + ' x ' + nx);
    return d;
  }

  var thinned = {};

  /** Grid d read one point in f each way (from its first point): the same
      places, f times fewer each way. d itself for f = 1. */
  function thin(d, f) {
    if (!f || f === 1) return d;
    var key = d.id + '/' + f;
    if (d.id && thinned[key]) return thinned[key];
    var t = {
      id: d.id, kind: d.kind, nx: Math.floor((d.nx - 1) / f) + 1, ny: Math.floor((d.ny - 1) / f) + 1,
      x0: d.x0, y0: d.y0, dx: d.dx * f, dy: d.dy * f, proj: d.proj, res: d.res * f, step: f, full: d
    };
    if (d.id) thinned[key] = t;
    return t;
  }

  /** The values of a field of grid d at the points of thin(d, f). */
  function thinValues(values, d, f) {
    if (!f || f === 1) return values;
    var t = thin(d, f), out = new Float32Array(t.nx * t.ny);
    for (var r = 0; r < t.ny; r++) {
      for (var c = 0; c < t.nx; c++) out[r * t.nx + c] = values[r * f * d.nx + c * f];
    }
    return out;
  }

  return {
    R: R, thin: thin, thinValues: thinValues, rotated: rotated, lcc: lcc, laea: laea, forward: forward, inverse: inverse,
    latlon: latlon, projected: projected, index: index, lonLatAt: lonLatAt, bounds: bounds, sample: sample, cell: cell, valueAt: valueAt,
    MODELS: Object.keys(MODELS), of: of
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetGrids; }
