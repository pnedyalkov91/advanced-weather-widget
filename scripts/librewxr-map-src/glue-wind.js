// ==========================================================================
// Glue script 2b: animated 10 m wind layer.
// WindField holds the pure math (grid, interpolation, projection) and is
// loadable under Node for tests; WindSource fetches the Open-Meteo grid and
// caches it; DemTiles reads Terrarium elevation tiles; createWindLayer(L)
// builds the Leaflet layer that animates the particles on a canvas.
// ==========================================================================
var WidgetWind = (function () {
  'use strict';

  var DEG = Math.PI / 180;
  var KM_PER_DEG = 111.32;

  var MAX_LAT = 85.0511;   // Web Mercator's (and Leaflet's) last latitude

  function round4(x) { return Math.round(x * 1e4) / 1e4; }

  /** Web Mercator y (radians) of a latitude. */
  function mercatorY(lat) { return Math.log(Math.tan(Math.PI / 4 + lat * DEG / 2)); }

  function bilinearWeights(fr, fc) {
    return [(1 - fr) * (1 - fc), (1 - fr) * fc, fr * (1 - fc), fr * fc];
  }

  /* Wind levels fetched together: 10 m is what people feel and what the relief
     shapes; 700 hPa (about 3000 m) is the flow that steers the rain, so it
     matches the radar motion arrows. Keys are the level ids used everywhere. */
  var LEVELS = {
    '10m': ['wind_speed_10m', 'wind_direction_10m'],
    '700hPa': ['wind_speed_700hPa', 'wind_direction_700hPa']
  };
  var DEFAULT_LEVEL = '10m';

  /* === WindField: pure math, no DOM === */
  var WindField = {
    LEVELS: LEVELS,
    DEFAULT_LEVEL: DEFAULT_LEVEL,
    /** The whole Earth as Leaflet bounds, for the world grid. */
    WORLD: { west: -180, south: -MAX_LAT, east: 180, north: MAX_LAT },

    /** Meteorological direction (where the wind comes FROM) to east/north components (m/s). */
    toUV: function (speed, dirDeg) {
      var a = dirDeg * DEG;
      return { u: -speed * Math.sin(a), v: -speed * Math.cos(a) };
    },

    /** Grid spec for a viewport: the bounds widened by `margin` on each side,
        covered by grid points on a lattice fixed to the Earth. Meridians sit
        on multiples of a step that divides 360 and parallels on multiples of
        a step that divides 90, so two pans of the same view sample the wind
        at the same points, whichever copy of the world they show. Both steps
        come from the view's size alone (its longitude span and its Mercator
        height), which a pan does not change. About `targetKm` apart, with
        minN - 1 to maxN points per side. lats run north to south, lons west
        to east. */
    gridSpec: function (bounds, opts) {
      opts = opts || {};
      var margin = opts.margin == null ? 0.3 : opts.margin;
      var targetKm = opts.targetKm || 3;
      var minN = opts.minN || 6, maxN = opts.maxN || 12;
      var w = bounds.east - bounds.west, h = bounds.north - bounds.south;
      var clampLat = function (x) { return Math.max(-MAX_LAT, Math.min(MAX_LAT, x)); };
      var mercH = (mercatorY(clampLat(bounds.north)) - mercatorY(clampLat(bounds.south))) / DEG;
      var lonSpan = w * (1 + 2 * margin);
      var latSpan = Math.min(180, mercH * (1 + 2 * margin));   // the most a latitude span gets
      // n points over the span, then the next coarser lattice step: snapping
      // the box outward adds at most one point on each side.
      var stepFor = function (span, period) {
        var n = Math.max(minN, Math.min(maxN, Math.round(span * KM_PER_DEG / targetKm)));
        var div = Math.max(1, Math.floor(period / (span / (n - 2))));
        // Optional power-of-two steps: every zoom of a band then shares the
        // same points, and a finer band holds all the points of a coarser
        // one. 'round' snaps to the nearest power: never more than 1.4 times
        // coarser than the free step, up to about 17 points per side.
        if (WindField.pow2Steps) div = Math.pow(2, (WindField.pow2Steps === 'round' ? Math.round : Math.floor)(Math.log2(div)));
        return period / div;
      };
      // Past a full turn (zoomed out on several copies of the world), one
      // turn is enough: sample() finds every longitude on it.
      var fullTurn = lonSpan >= 360;
      var lonStep = stepFor(Math.min(lonSpan, 360), 360), latStep = stepFor(latSpan, 90);
      var iw = Math.floor((bounds.west - w * margin) / lonStep);
      var ie = fullTurn ? iw + Math.round(360 / lonStep)
        : Math.max(iw + 1, Math.ceil((bounds.east + w * margin) / lonStep));
      // Up to the parallel at or past Leaflet's last latitude, never past a pole.
      var jn = Math.ceil(clampLat(bounds.north + h * margin) / latStep);
      var js = Math.min(jn - 1, Math.floor(clampLat(bounds.south - h * margin) / latStep));
      var lats = [], lons = [], i;
      for (i = jn; i >= js; i--) lats.push(round4(i * latStep));
      for (i = iw; i <= ie; i++) lons.push(round4(i * lonStep));
      return {
        west: lons[0], south: lats[lats.length - 1], east: lons[lons.length - 1], north: lats[0],
        lats: lats, lons: lons, lonStep: lonStep, latStep: latStep
      };
    },

    /** Comma-separated coordinate lists for Open-Meteo, row-major (lat rows,
        lon columns). Zoomed out on the whole world the box runs past +-180,
        which Open-Meteo rejects (HTTP 400): it gets the same meridian inside
        -180..180, while the grid keeps its unwrapped geometry. */
    pointLists: function (spec) {
      var la = [], lo = [];
      for (var i = 0; i < spec.lats.length; i++) {
        for (var j = 0; j < spec.lons.length; j++) {
          la.push(spec.lats[i]);
          lo.push(round4(((spec.lons[j] + 180) % 360 + 360) % 360 - 180));
        }
      }
      return { latitude: la.join(','), longitude: lo.join(',') };
    },

    /** True when the cached grid cannot serve the view: none, expired, laid
        out before the fixed lattice, zoom moved by a level or more, or the
        view left the fetched box. The world grid covers everything, so it
        serves the views laid on its own lattice, those of the whole world. */
    needsFetch: function (view, cached, nowMs, ttlMs) {
      if (!cached || !cached.spec || !cached.grid) return true;
      if (!cached.spec.lonStep) return true;
      if (nowMs - cached.fetchedAt > ttlMs) return true;
      if (cached.world) return !WindField.sameLattice(WindField.gridSpec(view.bounds), cached.spec);
      if (WindField.pow2Steps) {
        // Nested lattices: the question is whether the grid is fine enough
        // for this view, whatever the zoom it came from. A map that zooms
        // in fractions would otherwise keep a grid up to a whole level too coarse.
        var want = WindField.gridSpec(view.bounds), eps = 1e-9;
        if (want.lonStep < cached.spec.lonStep - eps || want.latStep < cached.spec.latStep - eps) return true;
      } else if (Math.abs(view.zoom - cached.zoom) >= 1) return true;
      var b = view.bounds, s = cached.spec;
      if (b.south < s.south || b.north > s.north) return true;
      if (s.east - s.west >= 360) return false;   // a full turn: every longitude has a copy inside
      var k = WindField.lonShift(b, s);
      return b.west + k < s.west || b.east + k > s.east;
    },

    /** Whether two grid specs put their points on the same lattice. */
    sameLattice: function (a, b) {
      return a.lonStep === b.lonStep && a.latStep === b.latStep;
    },

    /** Whole turns (a multiple of 360) that bring a view's longitudes toward
        a grid box. Leaflet keeps counting past +-180 when the map is panned
        around the world, while the lattice repeats every 360 degrees. */
    lonShift: function (bounds, spec) {
      return 360 * Math.round(((spec.west + spec.east) - (bounds.west + bounds.east)) / 720);
    },

    /** After WindSource.ensure(): draw the entry when it covers most of the
        view, and ask again later while it does not fully serve the view (an
        older grid handed back during the rate limit or after a failure). */
    afterEnsure: function (view, entry, nowMs, ttlMs) {
      var draw = !!(entry && entry.grid) && WindField.coverage(view.bounds, entry.spec) >= 0.5;
      return { draw: draw, retry: !draw || WindField.needsFetch(view, entry, nowMs, ttlMs) };
    },

    /** Fraction (0..1) of the view area that a grid spec covers. */
    coverage: function (bounds, spec) {
      if (!spec) return 0;
      var k = WindField.lonShift(bounds, spec);
      var w = spec.east - spec.west >= 360 ? bounds.east - bounds.west
        : Math.min(bounds.east + k, spec.east) - Math.max(bounds.west + k, spec.west);
      var h = Math.min(bounds.north, spec.north) - Math.max(bounds.south, spec.south);
      if (w <= 0 || h <= 0) return 0;
      var area = (bounds.east - bounds.west) * (bounds.north - bounds.south);
      return area > 0 ? Math.min(1, (w * h) / area) : 0;
    },

    /** Open-Meteo multi-location response -> typed u/v grids per hour. */
    buildGrid: function (spec, points) {
      var count = spec.lats.length * spec.lons.length;
      if (!points || points.length !== count) {
        throw new Error('wind: expected ' + count + ' points, got ' + (points ? points.length : 0));
      }
      var times = points[0].hourly.time.slice();
      var hours = times.length;
      var elev = new Float32Array(count);
      var levels = {};
      for (var p = 0; p < count; p++) {
        var pt = points[p];
        elev[p] = (pt.elevation != null && isFinite(pt.elevation)) ? pt.elevation : NaN;
      }
      for (var name in LEVELS) {
        var vars = LEVELS[name];
        if (!points[0].hourly[vars[0]] || !points[0].hourly[vars[1]]) continue;   // level absent (older cache)
        var u = [], v = [];
        for (var h = 0; h < hours; h++) { u.push(new Float32Array(count)); v.push(new Float32Array(count)); }
        for (var q = 0; q < count; q++) {
          var sp = points[q].hourly[vars[0]] || [], di = points[q].hourly[vars[1]] || [];
          for (var k = 0; k < hours; k++) {
            if (sp[k] == null || di[k] == null) { u[k][q] = NaN; v[k][q] = NaN; continue; }
            var uv = WindField.toUV(sp[k], di[k]);
            u[k][q] = uv.u; v[k][q] = uv.v;
          }
        }
        levels[name] = { u: u, v: v };
      }
      var base = levels[DEFAULT_LEVEL] || { u: [], v: [] };
      return { lats: spec.lats, lons: spec.lons, elev: elev, times: times, u: base.u, v: base.v, levels: levels };
    },

    /** Hour index containing nowSec and the fraction toward the next hour. */
    timeWeights: function (times, nowSec) {
      var last = times.length - 1;
      if (nowSec <= times[0]) return { i: 0, frac: 0 };
      if (nowSec >= times[last]) return { i: last, frac: 0 };
      var i = 0;
      while (i < last - 1 && times[i + 1] <= nowSec) i++;
      var span = times[i + 1] - times[i];
      return { i: i, frac: span > 0 ? (nowSec - times[i]) / span : 0 };
    },

    /** Wind (u, v m/s) at lat/lon: bilinear on the grid, blended in time, and
        when sigma > 0 and hP is a number, weighted by elevation similarity so a
        valley particle follows valley grid points. null outside the grid
        (on every copy of the world).
        `level` picks a wind level id (see LEVELS); unknown or absent levels
        fall back to the grid's default (10 m) arrays. */
    sample: function (grid, lat, lon, tw, hP, sigma, level) {
      var lats = grid.lats, lons = grid.lons, rows = lats.length, cols = lons.length;
      var lv = (level && grid.levels && grid.levels[level]) || grid;
      var north = lats[0], south = lats[rows - 1], west = lons[0], east = lons[cols - 1];
      // The same meridian on another copy of the world (see lonShift).
      if (lon < west) lon += 360 * Math.ceil((west - lon) / 360);
      else if (lon > east) lon -= 360 * Math.ceil((lon - east) / 360);
      if (lat > north || lat < south || lon < west || lon > east) return null;
      var r = (north - lat) / (north - south) * (rows - 1);
      var c = (lon - west) / (east - west) * (cols - 1);
      var i0 = Math.min(rows - 2, Math.floor(r)), j0 = Math.min(cols - 2, Math.floor(c));
      var fr = r - i0, fc = c - j0;
      var idx = [i0 * cols + j0, i0 * cols + j0 + 1, (i0 + 1) * cols + j0, (i0 + 1) * cols + j0 + 1];
      var w = bilinearWeights(fr, fc), k;
      if (sigma > 0 && typeof hP === 'number' && isFinite(hP)) {
        var sum = 0;
        for (k = 0; k < 4; k++) {
          var hk = grid.elev[idx[k]];
          if (isFinite(hk)) { var d = (hP - hk) / sigma; w[k] *= Math.exp(-d * d); }
          sum += w[k];
        }
        if (sum >= 1e-3) { for (k = 0; k < 4; k++) w[k] /= sum; }
        else w = bilinearWeights(fr, fc);
      }
      var u0 = lv.u[tw.i], v0 = lv.v[tw.i];
      if (!u0 || !v0) return null;
      var blend = tw.frac > 0 && tw.i + 1 < lv.u.length;
      var u1 = blend ? lv.u[tw.i + 1] : null, v1 = blend ? lv.v[tw.i + 1] : null;
      var u = 0, v = 0, wsum = 0;
      for (k = 0; k < 4; k++) {
        var a = u0[idx[k]], b = v0[idx[k]];
        if (blend) { a = a * (1 - tw.frac) + u1[idx[k]] * tw.frac; b = b * (1 - tw.frac) + v1[idx[k]] * tw.frac; }
        if (!isFinite(a) || !isFinite(b)) continue;
        u += w[k] * a; v += w[k] * b; wsum += w[k];
      }
      if (wsum <= 0) return null;
      return { u: u / wsum, v: v / wsum };
    },

    /** Screen velocity (px/s): k px/s per m/s, clamped so calm air still
        drifts and storms stay readable. Screen y points down. */
    screenVelocity: function (u, v, opts) {
      var k = opts.k, vmin = opts.min, vmax = opts.max;
      var s = Math.sqrt(u * u + v * v);
      if (s < 0.05) return { dx: 0, dy: 0, speed: 0 };
      var px = Math.max(vmin, Math.min(vmax, k * s));
      return { dx: u / s * px, dy: -v / s * px, speed: s };
    },

    /** Particle speed (px/s) the frame rate is tuned on: the speed that
        `fraction` of the first `count` particles do not exceed (nearest
        rank). Reorders those values in place. */
    cadenceSpeed: function (speeds, count, fraction) {
      if (!count) return 0;
      var s = speeds.subarray(0, count);
      s.sort();
      return s[Math.max(0, Math.ceil(fraction * count) - 1)];
    },

    /** Frame rate that moves a particle at pxPerSec by about stepPx per
        frame, kept within [fps, maxFps]. */
    targetFps: function (pxPerSec, fps, maxFps, stepPx) {
      return Math.max(fps, Math.min(maxFps, pxPerSec / stepPx));
    },

    /** Particle stroke width (CSS px) from the settings, kept within the
        range the settings slider offers; 1 px when unset or invalid. */
    lineWidth: function (w) {
      if (!(w > 0)) return 1;
      return Math.max(0.5, Math.min(2, w));
    },

    /** false (steps from the view size alone), true (power of two, rounded
        down) or 'round' (nearest power of two). Set by the page. */
    pow2Steps: false,

    /** The default wind palette: the Beaufort scale grouped in 8 bands,
        upper bounds in m/s (km/h / 3.6, to 3 decimals like the URL form),
        the last one open. */
    DEFAULT_PALETTE: [[5, '#ffffff'], [12, '#2ecc40'], [20, '#7fdbff'], [38, '#1e64ff'],
      [50, '#ffdc00'], [75, '#ff851b'], [118, '#ff2020'], [Infinity, '#8a5cff']]
      .map(function (b) { return { max: b[0] === Infinity ? Infinity : +(b[0] / 3.6).toFixed(3), color: b[1] }; }),

    /** Opacity of each band: calm winds faint, strong winds solid. */
    BAND_ALPHA: [0.5, 0.85, 0.9, 0.95, 0.95, 1, 1, 1],

    /** A palette from its URL form, 8 "max:rrggbb" pairs separated by
        commas, max in m/s and "inf" for the last band. null when the count,
        the order of the thresholds or a color is wrong. */
    parsePalette: function (s) {
      var parts = String(s == null ? '' : s).split(',');
      if (parts.length !== 8) return null;
      var out = [], prev = -1;
      for (var i = 0; i < parts.length; i++) {
        var m = /^\s*(inf|\d+(?:\.\d+)?):#?([0-9a-fA-F]{6})\s*$/.exec(parts[i]);
        if (!m) return null;
        var max = m[1] === 'inf' ? Infinity : parseFloat(m[1]);
        if (!(max > prev) || (max === Infinity) !== (i === parts.length - 1)) return null;
        out.push({ max: max, color: '#' + m[2].toLowerCase() });
        prev = max;
      }
      return out;
    },

    /** The URL form of a palette (see parsePalette), thresholds to 3 decimals. */
    formatPalette: function (p) {
      return p.map(function (b) {
        return (b.max === Infinity ? 'inf' : String(+b.max.toFixed(3))) + ':' + b.color.replace('#', '');
      }).join(',');
    },

    /** Band of a wind speed (m/s): the first whose upper bound it does not exceed. */
    paletteBand: function (speed, p) {
      for (var i = 0; i < p.length - 1; i++) if (speed <= p[i].max) return i;
      return p.length - 1;
    },

    /** Stroke color of a band. White would vanish on a light map: there it
        takes the map's dark ink instead. */
    bandColor: function (p, band, theme) {
      var c = p[band].color;
      return theme === 'light' && c === '#ffffff' ? '#1a237e' : c;
    },

    /** Particles for a canvas area (CSS px^2): one per 300 px^2 at density
        1, within 200..maxP. */
    particleCount: function (area, density, maxP) {
      return Math.max(200, Math.min(maxP, Math.round(area * density / 300)));
    },

    /** Whether the API grid for a view is finer than a file of resolution
        fileRes (degrees): only then does the API add detail. */
    wantApi: function (spec, fileRes) {
      return spec.lonStep < fileRes - 1e-9;
    },

    /** Frames to draw at once when the particles start over, so their trails
        already reach 95% of their steady length: each frame keeps `fade` of
        the previous one. Capped so a slow fade never stalls the page. */
    warmUpFrames: function (fade) {
      if (!(fade > 0 && fade < 1)) return 0;
      return Math.min(60, Math.ceil(Math.log(0.05) / Math.log(fade)));
    },

    /** Web Mercator world pixel at zoom z (256 px tiles), same convention as Leaflet's EPSG3857. */
    worldPx: function (lat, lon, z) {
      var scale = 256 * Math.pow(2, z);
      var s = Math.sin(lat * DEG);
      return { x: (lon + 180) / 360 * scale, y: (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * scale };
    },

    /** Inverse of worldPx. */
    worldToLatLng: function (x, y, z) {
      var scale = 256 * Math.pow(2, z);
      var m = Math.PI - 2 * Math.PI * y / scale;
      return { lat: Math.atan(0.5 * (Math.exp(m) - Math.exp(-m))) / DEG, lon: x / scale * 360 - 180 };
    },

    /** Affine frame mapping screen (container) pixels to world pixels, from
        the world positions of the container's origin, of (1, 0) and of
        (0, 1). Built from Leaflet's own conversions so a rotated map
        (leaflet-rotate) needs no knowledge of the plugin's conventions. */
    viewFrame: function (o, px, py) {
      return { ox: o.x, oy: o.y, axx: px.x - o.x, axy: px.y - o.y, ayx: py.x - o.x, ayy: py.y - o.y };
    },

    /** Whether two layer views {zoom, w, h, frame} are the same within tol
        px: same zoom and rotation, size and screen origin barely moved. */
    sameView: function (a, b, tol) {
      if (!a || !b || a.zoom !== b.zoom) return false;
      if (Math.abs(a.w - b.w) > tol || Math.abs(a.h - b.h) > tol) return false;
      var fa = a.frame, fb = b.frame, eps = 1e-6;
      return Math.abs(fa.ox - fb.ox) <= tol && Math.abs(fa.oy - fb.oy) <= tol &&
        Math.abs(fa.axx - fb.axx) < eps && Math.abs(fa.axy - fb.axy) < eps &&
        Math.abs(fa.ayx - fb.ayx) < eps && Math.abs(fa.ayy - fb.ayy) < eps;
    },

    screenToWorld: function (f, x, y) {
      return { x: f.ox + x * f.axx + y * f.ayx, y: f.oy + x * f.axy + y * f.ayy };
    },

    /** World displacement to screen displacement: the frame is a rotation
        (orthonormal), so its inverse is its transpose. */
    worldToScreenVector: function (f, dx, dy) {
      return { dx: dx * f.axx + dy * f.axy, dy: dx * f.ayx + dy * f.ayy };
    },

    /** Terrarium PNG encoding to meters. */
    terrariumMeters: function (r, g, b) { return r * 256 + g + b / 256 - 32768; }
  };

  /* === WindSource: Open-Meteo grid fetch, localStorage cache, backoff === */
  function safeStorage() {
    try {
      if (typeof window === 'undefined' || !window.localStorage) return null;
      window.localStorage.getItem(WindSource.STORAGE_KEY);
      return window.localStorage;
    } catch (e) { return null; }
  }

  function WindSource(opts) {
    opts = opts || {};
    this.fetch = opts.fetch || (typeof fetch === 'function' ? function (u) { return fetch(u); } : null);
    this.storage = opts.storage === undefined ? safeStorage() : opts.storage;
    this.now = opts.now || function () { return Date.now(); };
    this.apiBase = opts.apiBase || 'https://api.open-meteo.com/v1/forecast';
    this.ttlMs = opts.ttlMs || 60 * 60 * 1000;
    // Retry delay after a failure: backoffMs, doubled at each further failure
    // up to maxBackoffMs, reset by the next success. A 429 (quota) or a
    // network blip must not freeze the layer on a stale box for long.
    this.backoffMs = opts.backoffMs || 20 * 1000;
    this.maxBackoffMs = opts.maxBackoffMs || 10 * 60 * 1000;
    // Open-Meteo counts every grid point as one call against its 600/min
    // allowance, so a 12 x 12 grid at most every 15 s keeps a pan-happy user
    // well under it. The layer retries by itself once the interval is over.
    this.minIntervalMs = opts.minIntervalMs == null ? 15 * 1000 : opts.minIntervalMs;
    // A request that never answers (seen when Open-Meteo stalls) would stay
    // in flight forever, and every later ensure() would wait on it: the wind
    // then never comes back until the page reloads, which a radar kept
    // loaded in the background may not do for hours. Count it as a failure.
    this.timeoutMs = opts.timeoutMs || 20 * 1000;
    this.failures = 0;
    // Grids kept besides the world one, most recently used first: zooming
    // back to a level already seen draws at once and asks nothing. keepMs is
    // the age past which a grid is no longer drawn while a fresh one is on
    // its way (the hourly data run 4 h ahead of the fetch).
    this.maxEntries = opts.maxEntries || 6;
    this.keepMs = opts.keepMs || 3 * 60 * 60 * 1000;
    this.entries = [];        // { spec, zoom, fetchedAt, points, grid }
    // The whole Earth on the coarsest lattice: it draws any view at once,
    // coarse, until the view's own grid comes.
    this.world = null;        // same shape, with world: true
    this.worldFailures = 0;
    this.worldRetryAt = 0;
    this.worldInflight = null;
    this.restored = false;
    this.blockedUntil = 0;
    this.inflight = null;
  }
  WindSource.STORAGE_KEY = 'awwWind:grids';
  WindSource.OLD_STORAGE_KEY = 'awwWind:last';   // a single grid, before the lattice

  WindSource.prototype.url = function (spec) {
    var pl = WindField.pointLists(spec);
    var vars = [];
    for (var name in LEVELS) vars = vars.concat(LEVELS[name]);
    return this.apiBase + '?latitude=' + pl.latitude + '&longitude=' + pl.longitude +
      '&hourly=' + vars.join(',') + '&wind_speed_unit=ms&timeformat=unixtime' +
      '&past_hours=2&forecast_hours=4';
  };

  /** Bring the grids back from storage once per page, dropping those past
      keepMs. */
  WindSource.prototype.restore = function () {
    if (this.restored || !this.storage) return;
    this.restored = true;
    var self = this, now = this.now();
    var revive = function (e) {
      if (!e || !e.spec || !e.points || !(now - e.fetchedAt <= self.keepMs)) return null;
      e.grid = WindField.buildGrid(e.spec, e.points);
      return e;
    };
    try {
      if (this.storage.removeItem) this.storage.removeItem(WindSource.OLD_STORAGE_KEY);
      var raw = this.storage.getItem(WindSource.STORAGE_KEY);
      if (!raw) return;
      var saved = JSON.parse(raw);
      this.world = revive(saved.world);
      this.entries = (saved.grids || []).map(revive).filter(Boolean).slice(0, this.maxEntries);
    } catch (err) { this.world = null; this.entries = []; }
  };

  WindSource.prototype.persist = function () {
    if (!this.storage) return;
    var pack = function (e) {
      return e && { spec: e.spec, zoom: e.zoom, fetchedAt: e.fetchedAt, world: e.world, points: e.points };
    };
    try {
      this.storage.setItem(WindSource.STORAGE_KEY, JSON.stringify({ world: pack(this.world), grids: this.entries.map(pack) }));
    } catch (err) { /* quota or disabled storage: the in-memory copies still work */ }
  };

  WindSource.prototype._all = function () {
    return this.world ? [this.world].concat(this.entries) : this.entries;
  };

  /** The grid to draw a view with right now: the finest one covering all of
      it (the world grid always does), else the one covering most of it, at
      least half. null when there is none. */
  WindSource.prototype.best = function (view) {
    this.restore();
    var now = this.now(), all = this._all(), full = null, part = null, partCov = 0.5;
    for (var i = 0; i < all.length; i++) {
      var e = all[i];
      if (!e.grid || !(now - e.fetchedAt <= this.keepMs)) continue;
      var cov = WindField.coverage(view.bounds, e.spec);
      if (cov >= 0.999) { if (!full || e.spec.lonStep < full.spec.lonStep) full = e; }
      else if (cov >= partCov) { part = e; partCov = cov; }
    }
    return full || part;
  };

  /** One request for a spec; resolves with a new entry, keeping only what
      buildGrid() reads of each point. Fails after timeoutMs without an
      answer (see the constructor). */
  WindSource.prototype._get = function (spec) {
    var self = this, timer = null;
    var timeout = new Promise(function (resolve, reject) {
      timer = setTimeout(function () { reject(new Error('no answer after ' + Math.round(self.timeoutMs / 1000) + ' s')); }, self.timeoutMs);
    });
    var request = this.fetch(this.url(spec)).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    });
    return Promise.race([request, timeout]).then(function (points) {
      clearTimeout(timer);
      points = points.map(function (p) { return { elevation: p.elevation, hourly: p.hourly }; });
      return { spec: spec, fetchedAt: self.now(), points: points, grid: WindField.buildGrid(spec, points) };
    }, function (err) {
      clearTimeout(timer);
      throw err;
    });
  };

  /** Keep the world grid at most ttlMs old. An hourly request of 121
      points, not held back by minIntervalMs; its failures back off on their
      own. Resolves with the world grid, or null. */
  WindSource.prototype.ensureWorld = function () {
    var self = this;
    this.restore();
    var now = this.now();
    if (this.world && now - this.world.fetchedAt <= this.ttlMs) return Promise.resolve(this.world);
    if (this.worldInflight) return this.worldInflight;
    if (now < this.worldRetryAt) return Promise.resolve(this.world);
    this.worldInflight = this._get(WindField.gridSpec(WindField.WORLD)).then(function (entry) {
      entry.world = true;
      entry.zoom = null;
      self.world = entry;
      self.worldInflight = null;
      self.worldFailures = 0;
      self.persist();
      return entry;
    }).catch(function (err) {
      self.worldInflight = null;
      self.worldFailures++;
      self.worldRetryAt = self.now() + Math.min(self.maxBackoffMs, self.backoffMs * Math.pow(2, self.worldFailures - 1));
      if (typeof console !== 'undefined') console.warn('[wind] world grid failed: ' + err);
      return self.world;
    });
    return this.worldInflight;
  };

  /** Resolve with an entry for view {bounds, zoom}: a kept one that serves
      it, else a fresh fetch. While fetching is held back (minIntervalMs, or
      backoffMs after a failure) and on failure, the best grid at hand is
      returned instead (see best()), or null. */
  WindSource.prototype.ensure = function (view) {
    var self = this;
    this.restore();
    var now = this.now(), all = this._all();
    for (var i = 0; i < all.length; i++) {
      if (WindField.needsFetch(view, all[i], now, this.ttlMs)) continue;
      var hit = all[i], at = this.entries.indexOf(hit);
      if (at > 0) { this.entries.splice(at, 1); this.entries.unshift(hit); }
      this.ensureWorld();
      return Promise.resolve(hit);
    }
    var spec = WindField.gridSpec(view.bounds);
    if (WindField.sameLattice(spec, WindField.gridSpec(WindField.WORLD))) {
      return this.ensureWorld().then(function (w) { return w || self.best(view); });
    }
    this.ensureWorld();
    if (now < this.blockedUntil) return Promise.resolve(this.best(view));
    if (this.inflight) return this.inflight;
    var t0 = now;
    this.inflight = this._get(spec).then(function (entry) {
      entry.zoom = view.zoom;
      self.entries.unshift(entry);
      if (self.entries.length > self.maxEntries) self.entries.length = self.maxEntries;
      self.persist();
      self.inflight = null;
      self.failures = 0;
      self.blockedUntil = self.now() + self.minIntervalMs;
      if (typeof console !== 'undefined') console.log('[wind] grid ' + spec.lats.length + 'x' + spec.lons.length + ' fetched in ' + (self.now() - t0) + ' ms');
      return entry;
    }).catch(function (err) {
      self.inflight = null;
      self.failures++;
      var delay = Math.min(self.maxBackoffMs, self.backoffMs * Math.pow(2, self.failures - 1));
      self.blockedUntil = self.now() + delay;
      if (typeof console !== 'undefined') console.warn('[wind] fetch failed, retry in ' + Math.round(delay / 1000) + ' s: ' + err);
      return self.best(view);
    });
    return this.inflight;
  };

  /* === DemTiles: Terrarium elevation tiles, decoded once per tile === */
  function defaultLoadTile(url) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = function () {
        try {
          var c = document.createElement('canvas');
          c.width = 256; c.height = 256;
          var ctx = c.getContext('2d');
          ctx.drawImage(img, 0, 0);
          var d = ctx.getImageData(0, 0, 256, 256).data;
          var out = new Float32Array(65536);
          for (var i = 0, p = 0; i < 65536; i++, p += 4) out[i] = WindField.terrariumMeters(d[p], d[p + 1], d[p + 2]);
          resolve(out);
        } catch (e) { reject(e); }
      };
      img.onerror = function () { reject(new Error('tile load failed: ' + url)); };
      img.src = url;
    });
  }

  function DemTiles(opts) {
    opts = opts || {};
    this.template = opts.template || 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';
    this.loadTile = opts.loadTile || defaultLoadTile;
    this.maxTiles = opts.maxTiles || 16;
    this.tiles = {};     // 'z/x/y' -> Float32Array(65536)
    this.pending = {};   // 'z/x/y' -> Promise
  }

  /** Tile index range covering a spec at zoom z. Latitudes are kept inside
      Web Mercator: a grid reaching a pole (the world grid) has no finite y. */
  DemTiles.prototype._range = function (spec, z) {
    var clamp = function (lat) { return Math.max(-MAX_LAT, Math.min(MAX_LAT, lat)); };
    var a = WindField.worldPx(clamp(spec.north), spec.west, z), b = WindField.worldPx(clamp(spec.south), spec.east, z);
    return { x0: Math.floor(a.x / 256), x1: Math.floor(b.x / 256), y0: Math.floor(a.y / 256), y1: Math.floor(b.y / 256) };
  };

  DemTiles.prototype.tileKeysFor = function (spec, z) {
    var r = this._range(spec, z), keys = [];
    for (var ty = r.y0; ty <= r.y1; ty++) {
      for (var tx = r.x0; tx <= r.x1; tx++) keys.push(z + '/' + tx + '/' + ty);
    }
    return keys;
  };

  /** Load every tile covering the spec at zoom z (skipped when that means more than maxTiles). */
  DemTiles.prototype.ensure = function (spec, z) {
    var self = this;
    var r = this._range(spec, z);
    if ((r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1) > this.maxTiles) return Promise.resolve();
    var keys = this.tileKeysFor(spec, z);
    var waits = [];
    keys.forEach(function (key) {
      if (self.tiles[key]) return;
      if (!self.pending[key]) {
        var parts = key.split('/');
        var url = self.template.replace('{z}', parts[0]).replace('{x}', parts[1]).replace('{y}', parts[2]);
        self.pending[key] = self.loadTile(url).then(function (data) {
          self.tiles[key] = data;
          delete self.pending[key];
        }).catch(function (err) {
          delete self.pending[key];
          if (typeof console !== 'undefined') console.warn('[wind] ' + err);
        });
      }
      waits.push(self.pending[key]);
    });
    return Promise.all(waits);
  };

  /** Elevation (m) at a world pixel of zoom z, NaN while the tile is missing. */
  DemTiles.prototype.elevationAtWorld = function (x, y, z) {
    var tx = Math.floor(x / 256), ty = Math.floor(y / 256);
    var t = this.tiles[z + '/' + tx + '/' + ty];
    if (!t) return NaN;
    var px = Math.floor(x - tx * 256), py = Math.floor(y - ty * 256);
    return t[py * 256 + px];
  };

  /* === Leaflet layer: canvas particles driven by the grid === */
  function createWindLayer(L) {
    return L.Layer.extend({
      options: {
        pane: 'lv-wind-pane',
        fps: 10,             // base cadence; raised up to maxFps when particles move fast
        maxFps: 20,
        stepPx: 2.5,         // target displacement per frame of the fast particles (CSS px)
        cadenceFraction: 0.98, // the cadence follows the fastest 2% of the particles
        relief: true,
        reliefMinZoom: 9,
        sigma: 250,          // m: elevation similarity scale for the weighting
        fade: 0.90,          // alpha kept per frame (trail length)
        maxAge: 60,          // frames before a particle respawns
        density: 1,          // from the settings: 1 = one particle per 300 CSS px^2
        maxParticles: 800,
        lineWidth: 1,        // CSS px, set from the widget settings
        palette: null,       // wind palette (WindField.parsePalette); null = the default
        theme: 'dark',       // map theme: white bands turn dark on a light map
        speedScale: 3,       // px/s per m/s
        minPx: 2,
        maxPx: 60,
        fetchDelayMs: 600,   // settle time after a move before asking for data
        settleMs: 1500,      // longest wait for the page's first viewport fix
        level: DEFAULT_LEVEL // '10m' | '700hPa' (see LEVELS)
      },

      initialize: function (source, dem, options) {
        L.setOptions(this, options);
        this.options.lineWidth = WindField.lineWidth(this.options.lineWidth);
        this.options.palette = this.options.palette || WindField.DEFAULT_PALETTE;
        this._source = source;
        this._dem = dem;
        this._active = true;
        this._running = false;
        this._timer = null;
        this._entry = null;
        this._resetToken = 0;
        this._fps = this.options.fps;
        this._loop = 0;
        this._velOpts = { k: this.options.speedScale, min: this.options.minPx, max: this.options.maxPx };
      },

      getAttribution: function () {
        return 'Wind: <a href="https://open-meteo.com/">Open-Meteo</a>';
      },

      onAdd: function (map) {
        this._map = map;
        // leaflet-zoom-hide: Leaflet hides the canvas during zoom animations.
        this._canvas = L.DomUtil.create('canvas', 'lv-wind-canvas leaflet-zoom-hide');
        this.getPane().appendChild(this._canvas);
        this._ctx = this._canvas.getContext('2d');
        map.on('movestart zoomstart', this._onMoveStart, this);
        // 'rotate' comes from leaflet-rotate (map.setBearing); the canvas
        // stays upright, only the screen/world frame changes.
        map.on('moveend zoomend resize rotate', this._onMoveEnd, this);
        this._onVisibility = L.bind(this._onVisibilityChange, this);
        document.addEventListener('visibilitychange', this._onVisibility);
        // Nothing is drawn before settle(): see there.
        this._settled = false;
        var self = this;
        this._settleTimer = setTimeout(function () { self.settle(); }, this.options.settleMs);
        this._reset();
      },

      onRemove: function (map) {
        this._stop(true);
        if (this._settleTimer) { clearTimeout(this._settleTimer); this._settleTimer = null; }
        map.off('movestart zoomstart', this._onMoveStart, this);
        map.off('moveend zoomend resize rotate', this._onMoveEnd, this);
        document.removeEventListener('visibilitychange', this._onVisibility);
        L.DomUtil.remove(this._canvas);
        this._canvas = null;
        this._ctx = null;
        this._map = null;
      },

      /** Pause (popup collapsed) or resume; paused layers draw nothing. */
      setActive: function (active) {
        this._active = !!active;
        if (this._active) this._reset();
        else this._stop(true);
      },

      /** Map theme ('dark' | 'light'); the next frame draws with it. */
      setTheme: function (theme) { this.options.theme = theme; },

      /** Wind palette from the settings (null: the default); the next frame uses it. */
      setPalette: function (palette) { this.options.palette = palette || WindField.DEFAULT_PALETTE; },

      /** Particle density from the settings: the particles start over with the new count. */
      setDensity: function (density) {
        this.options.density = density > 0 ? density : 1;
        if (this._px) this._spawnAll();
      },

      /** The map has its final size: start drawing. Right after a page
          load the widget recalibrates the viewport (window.fixViewport);
          particles drawn before that land in a provisional frame and start
          over a moment later, which looks like a scramble. Called by
          fixViewport, or after settleMs when nothing calls it. */
      settle: function () {
        if (this._settleTimer) { clearTimeout(this._settleTimer); this._settleTimer = null; }
        if (this._settled) return;
        this._settled = true;
        this._reset();
      },

      /** Whether particles are on screen, for the widget's fade-in. */
      isDrawing: function () { return !!this._running; },

      /** Frame-rate budget: base cadence and the ceiling the adaptive rate may reach. */
      setRate: function (fps, maxFps) {
        this.options.fps = Math.max(4, Math.min(30, fps || 10));
        this.options.maxFps = Math.max(this.options.fps, Math.min(30, maxFps || this.options.fps));
        this._fps = this.options.fps;
      },

      /** Particle width from the settings; the next frame draws with it. */
      setLineWidth: function (w) {
        this.options.lineWidth = WindField.lineWidth(w);
      },

      /** Switch the wind level; the grid already holds every level, so this
          only respawns the particles. */
      setLevel: function (level) {
        this.options.level = LEVELS[level] ? level : DEFAULT_LEVEL;
        if (this._map) this._reset();
      },

      // `nudging` is set by fixViewport around its 1 px pan-and-back, which
      // is no view change: restarting the particles for it would only show.
      _onMoveStart: function () { if (!this.nudging) this._stop(true); },
      // The widget also nudges the view by 1 px to make Chromium repaint,
      // which resizes the map: a running layer keeps its particles when the
      // view did not really change, instead of visibly starting over.
      _onMoveEnd: function () {
        if (this.nudging) return;
        // Nor does it delay a grid request already on its way for this view:
        // the popup settles its size by 1 px steps right after opening.
        if ((this._running || this._fetchTimer) && WindField.sameView(this._lastView, this._viewNow(), 2)) return;
        this._reset();
      },

      /** Zoom, size and screen -> world frame of the map right now. */
      _viewNow: function () {
        var map = this._map, size = map.getSize(), origin = map.getPixelOrigin();
        var wp = function (x, y) { return map.containerPointToLayerPoint([x, y]).add(origin); };
        return { zoom: map.getZoom(), w: size.x, h: size.y, frame: WindField.viewFrame(wp(0, 0), wp(1, 0), wp(0, 1)) };
      },
      _onVisibilityChange: function () {
        if (document.hidden) this._stop(false);
        else this._reset();
      },

      _stop: function (clear) {
        this._running = false;
        // Invalidate the chain: a rAF already requested by the old timer
        // must neither draw nor reschedule once we restart (rotate/moveend
        // can stop and start again before it runs).
        this._loop = (this._loop || 0) + 1;
        if (this._timer) { clearTimeout(this._timer); this._timer = null; }
        if (this._fetchTimer) { clearTimeout(this._fetchTimer); this._fetchTimer = null; }
        if (this._retryTimer) { clearTimeout(this._retryTimer); this._retryTimer = null; }
        if (clear && this._ctx) this._ctx.clearRect(0, 0, this._canvas.width, this._canvas.height);
      },

      /** Re-anchor the canvas to the viewport, size it, make sure the data
          covers the view, respawn the particles and start the loop. */
      _reset: function () {
        if (!this._map || !this._canvas) return;
        var map = this._map, size = map.getSize();
        // Layer points are in the rotated pane's frame; our pane sits in
        // _mapPane (upright), which leaflet-rotate maps back with
        // rotatedPointToMapPanePoint (identity without the plugin).
        var topLeft = map.containerPointToLayerPoint([0, 0]);
        if (map.rotatedPointToMapPanePoint) topLeft = map.rotatedPointToMapPanePoint(topLeft);
        L.DomUtil.setPosition(this._canvas, topLeft);
        var dpr = Math.min(2, window.devicePixelRatio || 1);
        this._dpr = dpr;
        this._w = size.x;
        this._h = size.y;
        this._canvas.width = Math.round(size.x * dpr);
        this._canvas.height = Math.round(size.y * dpr);
        this._canvas.style.width = size.x + 'px';
        this._canvas.style.height = size.y + 'px';
        // Screen -> world frame (handles map rotation, see WindField.viewFrame).
        this._lastView = this._viewNow();
        var zoom = this._lastView.zoom;
        this._zoom = zoom;
        this._view = this._lastView.frame;
        this._demZoom = Math.min(10, Math.max(9, Math.round(zoom)));
        this._demScale = Math.pow(2, this._demZoom - zoom);
        this._stop(true);
        this._spawnAll();
        if (!this._active || document.hidden) return;
        var b = map.getBounds();
        var view = { bounds: { west: b.getWest(), south: b.getSouth(), east: b.getEast(), north: b.getNorth() }, zoom: zoom };
        // Draw right away with the best grid at hand (see WindSource.best):
        // one kept in storage when the page was just recreated (the popup
        // reopened), the one of a zoom level already seen, or the world grid,
        // coarse but covering everything. The data settle a moment later, so
        // a run of pans does not fire one Open-Meteo request per stop.
        var best = this._source.best(view);
        if (best) { this._entry = best; this._start(); }
        var self = this, token = ++this._resetToken;
        if (this._fetchTimer) clearTimeout(this._fetchTimer);
        // Without any grid yet (a page just built, nothing in storage) there
        // is no run of pans to wait for: ask at once.
        var hasGrid = !!(this._entry && this._entry.grid);
        this._fetchTimer = setTimeout(function () {
          self._fetchTimer = null;
          self._ensureFor(view, zoom, token);
        }, hasGrid ? this.options.fetchDelayMs : 0);
      },

      /** Get a grid for the view of reset `token` and draw with it. While the
          source only has grids that do not serve the view (rate limit, failed
          fetch), draw with the best of them (see WindSource.best) and ask again
          by ourselves once the source allows it, since the user may not move
          the map again. The particles keep running across the swap. */
      _ensureFor: function (view, zoom, token) {
        var self = this;
        this._source.ensure(view).then(function (entry) {
          if (token !== self._resetToken || !self._map) return;   // superseded by a later reset
          var now = self._source.now(), ttl = self._source.ttlMs;
          // A request already on its way for another view hands back that
          // view's grid: draw this one with the best grid at hand instead.
          if (WindField.needsFetch(view, entry, now, ttl)) entry = self._source.best(view) || entry;
          var next = WindField.afterEnsure(view, entry, now, ttl);
          if (next.draw) {
            self._entry = entry;
            if (self.options.relief && zoom >= self.options.reliefMinZoom) self._dem.ensure(entry.spec, self._demZoom);
            self._start();
          }
          if (next.retry) {
            var wait = Math.max(1000, self._source.blockedUntil - self._source.now() + 200);
            self._retryTimer = setTimeout(function () {
              self._retryTimer = null;
              if (token === self._resetToken && self._map) self._ensureFor(view, zoom, token);
            }, wait);
          }
        });
      },

      _spawnAll: function () {
        var count = WindField.particleCount(this._w * this._h, this.options.density, this.options.maxParticles);
        this._n = count;
        this._px = new Float32Array(count);
        this._py = new Float32Array(count);
        this._age = new Uint16Array(count);
        this._spd = new Float32Array(count);   // per-frame screen speeds, for the cadence
        for (var i = 0; i < count; i++) this._spawn(i, true);
        this._fresh = true;   // trails to rebuild: _start() warms them up
      },

      _spawn: function (i, randomAge) {
        this._px[i] = Math.random() * this._w;
        this._py[i] = Math.random() * this._h;
        this._age[i] = randomAge ? (Math.random() * this.options.maxAge) | 0 : 0;
      },

      _start: function () {
        if (this._running || !this._settled) return;
        this._running = true;
        if (this._fresh) this._warmUp();
        this._schedule();
      },

      // Freshly spawned particles have no trail and took a second or two to
      // look like wind, every time the popup reopened or the map moved. Draw
      // the first frames at once, off the timer, so the first frame shown
      // already has full trails.
      _warmUp: function () {
        this._fresh = false;
        var n = WindField.warmUpFrames(this.options.fade);
        this._warming = true;
        for (var i = 0; i < n; i++) this._frame();
        this._warming = false;
      },

      // One frame every 1000/fps ms: a timer, then a single rAF to draw. Never
      // a free-running rAF loop (it alone costs ~9 % of a core in QtWebEngine).
      _schedule: function () {
        var self = this, loop = this._loop || 0;
        this._timer = setTimeout(function () {
          self._timer = null;
          if (!self._running || self._loop !== loop) return;
          requestAnimationFrame(function () {
            if (!self._running || self._loop !== loop) return;
            self._frame();
            self._schedule();
          });
        }, 1000 / this._fps);
      },

      // Adaptive cadence: strong winds would jump several px per frame at
      // 10 fps, so raise the rate until the fast particles step about stepPx,
      // never above maxFps. Tuned on the fast ones (cadenceFraction) rather
      // than the mean: zoomed out, calm air fills most of the view and kept
      // the base rate while the storms jumped. Smoothed so the rate does not
      // flicker.
      _adaptFps: function (pxPerSec) {
        var want = WindField.targetFps(pxPerSec, this.options.fps, this.options.maxFps, this.options.stepPx);
        this._fps = this._fps * 0.8 + want * 0.2;
      },

      // Frame statistics (frames drawn, JS ms per frame) logged every 10 s so
      // the real cadence and cost can be read from the console.
      _stat: function (jsMs) {
        var now = Date.now();
        if (!this._statT0) { this._statT0 = now; this._statFrames = 0; this._statMs = 0; }
        this._statFrames++;
        this._statMs += jsMs;
        if (now - this._statT0 >= 10000) {
          var secs = (now - this._statT0) / 1000;
          console.log('[wind] ' + (this._statFrames / secs).toFixed(1) + ' fps, ' +
            (this._statMs / this._statFrames).toFixed(2) + ' ms JS per frame, ' + this._n + ' particles');
          this._statT0 = now; this._statFrames = 0; this._statMs = 0;
        }
      },

      _frame: function () {
        var entry = this._entry;
        if (!entry || !entry.grid || !this._ctx) return;
        var t0 = performance.now();
        var grid = entry.grid, ctx = this._ctx, dpr = this._dpr;
        var W = this._canvas.width, H = this._canvas.height;
        var tw = WindField.timeWeights(grid.times, Date.now() / 1000);
        var dt = 1 / this._fps;
        // Keep the trail the same length in seconds whatever the cadence.
        var fade = Math.pow(this.options.fade, this.options.fps / this._fps);
        var spd = this._spd, pxCount = 0;
        // Elevation weighting only makes sense for the surface wind.
        var level = this.options.level;
        var sigma = (this.options.relief && level === DEFAULT_LEVEL && this._zoom >= this.options.reliefMinZoom) ? this.options.sigma : 0;
        var frame = this._view, z = this._zoom, ds = this._demScale, dz = this._demZoom;
        var maxAge = this.options.maxAge, w = this._w, h = this._h;

        ctx.globalCompositeOperation = 'destination-in';
        ctx.fillStyle = 'rgba(0,0,0,' + fade + ')';
        ctx.fillRect(0, 0, W, H);
        ctx.globalCompositeOperation = 'source-over';

        var palette = this.options.palette, paths = palette.map(function () { return new Path2D(); });
        for (var i = 0; i < this._n; i++) {
          if (++this._age[i] > maxAge) { this._spawn(i, false); continue; }
          var x = this._px[i], y = this._py[i];
          var wpt = WindField.screenToWorld(frame, x, y), wx = wpt.x, wy = wpt.y;
          var ll = WindField.worldToLatLng(wx, wy, z);
          var hP = sigma > 0 ? this._dem.elevationAtWorld(wx * ds, wy * ds, dz) : NaN;
          var uv = WindField.sample(grid, ll.lat, ll.lon, tw, hP, sigma, level);
          if (!uv) { this._spawn(i, false); continue; }
          var sv = WindField.screenVelocity(uv.u, uv.v, this._velOpts);
          var vel = WindField.worldToScreenVector(frame, sv.dx, sv.dy);
          spd[pxCount++] = Math.sqrt(vel.dx * vel.dx + vel.dy * vel.dy);
          var nx = x + vel.dx * dt, ny = y + vel.dy * dt;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) { this._spawn(i, false); continue; }
          var k = WindField.paletteBand(sv.speed, palette);
          paths[k].moveTo(x * dpr, y * dpr);
          paths[k].lineTo(nx * dpr, ny * dpr);
          this._px[i] = nx;
          this._py[i] = ny;
        }
        ctx.lineWidth = this.options.lineWidth * dpr;
        ctx.lineCap = 'round';
        for (var b = 0; b < paths.length; b++) {
          ctx.strokeStyle = WindField.bandColor(palette, b, this.options.theme);
          ctx.globalAlpha = WindField.BAND_ALPHA[b];
          ctx.stroke(paths[b]);
        }
        ctx.globalAlpha = 1;
        if (pxCount) this._adaptFps(WindField.cadenceSpeed(spd, pxCount, this.options.cadenceFraction));
        if (!this._warming) this._stat(performance.now() - t0);
      }
    });
  }

  return { WindField: WindField, WindSource: WindSource, DemTiles: DemTiles, createWindLayer: createWindLayer };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetWind; }
