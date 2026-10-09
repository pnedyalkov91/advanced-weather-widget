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

  function round4(x) { return Math.round(x * 1e4) / 1e4; }

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

    /** Meteorological direction (where the wind comes FROM) to east/north components (m/s). */
    toUV: function (speed, dirDeg) {
      var a = dirDeg * DEG;
      return { u: -speed * Math.sin(a), v: -speed * Math.cos(a) };
    },

    /** Grid spec for a viewport: bounds widened by `margin` on each side and an
        N x N grid whose spacing is about `targetKm` (N clamped to minN..maxN).
        lats run north to south, lons west to east. */
    gridSpec: function (bounds, opts) {
      opts = opts || {};
      var margin = opts.margin == null ? 0.3 : opts.margin;
      var targetKm = opts.targetKm || 3;
      var minN = opts.minN || 6, maxN = opts.maxN || 12;
      var w = bounds.east - bounds.west, h = bounds.north - bounds.south;
      var west = bounds.west - w * margin, east = bounds.east + w * margin;
      var south = Math.max(-85, bounds.south - h * margin);
      var north = Math.min(85, bounds.north + h * margin);
      var widthKm = (east - west) * KM_PER_DEG * Math.cos((north + south) / 2 * DEG);
      var n = Math.max(minN, Math.min(maxN, Math.round(widthKm / targetKm)));
      var lats = [], lons = [];
      for (var i = 0; i < n; i++) {
        lats.push(round4(north - (north - south) * i / (n - 1)));
        lons.push(round4(west + (east - west) * i / (n - 1)));
      }
      return { west: west, south: south, east: east, north: north, n: n, lats: lats, lons: lons, widthKm: widthKm };
    },

    /** Comma-separated coordinate lists for Open-Meteo, row-major (lat rows, lon columns). */
    pointLists: function (spec) {
      var la = [], lo = [];
      for (var i = 0; i < spec.n; i++) {
        for (var j = 0; j < spec.n; j++) { la.push(spec.lats[i]); lo.push(spec.lons[j]); }
      }
      return { latitude: la.join(','), longitude: lo.join(',') };
    },

    /** True when the cached grid cannot serve the view: none, expired, zoom
        moved by a level or more, or the view left the fetched box. */
    needsFetch: function (view, cached, nowMs, ttlMs) {
      if (!cached || !cached.spec || !cached.grid) return true;
      if (nowMs - cached.fetchedAt > ttlMs) return true;
      if (Math.abs(view.zoom - cached.zoom) >= 1) return true;
      var b = view.bounds, s = cached.spec;
      return b.west < s.west || b.east > s.east || b.south < s.south || b.north > s.north;
    },

    /** Fraction (0..1) of the view area that a grid spec covers. */
    coverage: function (bounds, spec) {
      if (!spec) return 0;
      var w = Math.min(bounds.east, spec.east) - Math.max(bounds.west, spec.west);
      var h = Math.min(bounds.north, spec.north) - Math.max(bounds.south, spec.south);
      if (w <= 0 || h <= 0) return 0;
      var area = (bounds.east - bounds.west) * (bounds.north - bounds.south);
      return area > 0 ? Math.min(1, (w * h) / area) : 0;
    },

    /** Open-Meteo multi-location response -> typed u/v grids per hour. */
    buildGrid: function (spec, points) {
      var n = spec.n, count = n * n;
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
      return { n: n, lats: spec.lats, lons: spec.lons, elev: elev, times: times, u: base.u, v: base.v, levels: levels };
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
        valley particle follows valley grid points. null outside the grid.
        `level` picks a wind level id (see LEVELS); unknown or absent levels
        fall back to the grid's default (10 m) arrays. */
    sample: function (grid, lat, lon, tw, hP, sigma, level) {
      var n = grid.n, lats = grid.lats, lons = grid.lons;
      var lv = (level && grid.levels && grid.levels[level]) || grid;
      var north = lats[0], south = lats[n - 1], west = lons[0], east = lons[n - 1];
      if (lat > north || lat < south || lon < west || lon > east) return null;
      var r = (north - lat) / (north - south) * (n - 1);
      var c = (lon - west) / (east - west) * (n - 1);
      var i0 = Math.min(n - 2, Math.floor(r)), j0 = Math.min(n - 2, Math.floor(c));
      var fr = r - i0, fc = c - j0;
      var idx = [i0 * n + j0, i0 * n + j0 + 1, (i0 + 1) * n + j0, (i0 + 1) * n + j0 + 1];
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
    this.failures = 0;
    this.cached = null;       // { spec, zoom, fetchedAt, points, grid }
    this.restored = false;
    this.blockedUntil = 0;
    this.inflight = null;
  }
  WindSource.STORAGE_KEY = 'awwWind:last';

  WindSource.prototype.url = function (spec) {
    var pl = WindField.pointLists(spec);
    var vars = [];
    for (var name in LEVELS) vars = vars.concat(LEVELS[name]);
    return this.apiBase + '?latitude=' + pl.latitude + '&longitude=' + pl.longitude +
      '&hourly=' + vars.join(',') + '&wind_speed_unit=ms&timeformat=unixtime' +
      '&past_hours=2&forecast_hours=4';
  };

  /** Rebuild the last grid from storage once per page; null when absent or unreadable. */
  WindSource.prototype.restore = function () {
    if (this.cached || this.restored || !this.storage) return this.cached;
    this.restored = true;
    try {
      var raw = this.storage.getItem(WindSource.STORAGE_KEY);
      if (!raw) return null;
      var e = JSON.parse(raw);
      if (!e || !e.spec || !e.points) return null;
      e.grid = WindField.buildGrid(e.spec, e.points);
      this.cached = e;
    } catch (err) { this.cached = null; }
    return this.cached;
  };

  WindSource.prototype.persist = function (entry) {
    if (!this.storage) return;
    try {
      this.storage.setItem(WindSource.STORAGE_KEY, JSON.stringify({
        spec: entry.spec, zoom: entry.zoom, fetchedAt: entry.fetchedAt, points: entry.points
      }));
    } catch (err) { /* quota or disabled storage: the in-memory copy still works */ }
  };

  /** Resolve with an entry covering view {bounds, zoom}: the cached one when it
      still serves, else a fresh fetch. On failure the previous entry (or null)
      is returned and fetching pauses for backoffMs. */
  WindSource.prototype.ensure = function (view) {
    var self = this;
    this.restore();
    var now = this.now();
    if (!WindField.needsFetch(view, this.cached, now, this.ttlMs)) return Promise.resolve(this.cached);
    if (now < this.blockedUntil) return Promise.resolve(this.cached);
    if (this.inflight) return this.inflight;
    var spec = WindField.gridSpec(view.bounds);
    var url = this.url(spec);
    var t0 = now;
    this.inflight = this.fetch(url).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    }).then(function (points) {
      var entry = { spec: spec, zoom: view.zoom, fetchedAt: self.now(), points: points };
      entry.grid = WindField.buildGrid(spec, points);
      self.cached = entry;
      self.persist(entry);
      self.inflight = null;
      self.failures = 0;
      self.blockedUntil = self.now() + self.minIntervalMs;
      if (typeof console !== 'undefined') console.log('[wind] grid ' + spec.n + 'x' + spec.n + ' fetched in ' + (self.now() - t0) + ' ms');
      return entry;
    }).catch(function (err) {
      self.inflight = null;
      self.failures++;
      var delay = Math.min(self.maxBackoffMs, self.backoffMs * Math.pow(2, self.failures - 1));
      self.blockedUntil = self.now() + delay;
      if (typeof console !== 'undefined') console.warn('[wind] fetch failed, retry in ' + Math.round(delay / 1000) + ' s: ' + err);
      return self.cached;
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

  DemTiles.prototype.tileKeysFor = function (spec, z) {
    var a = WindField.worldPx(spec.north, spec.west, z), b = WindField.worldPx(spec.south, spec.east, z);
    var keys = [];
    for (var ty = Math.floor(a.y / 256); ty <= Math.floor(b.y / 256); ty++) {
      for (var tx = Math.floor(a.x / 256); tx <= Math.floor(b.x / 256); tx++) keys.push(z + '/' + tx + '/' + ty);
    }
    return keys;
  };

  /** Load every tile covering the spec at zoom z (skipped when that means more than maxTiles). */
  DemTiles.prototype.ensure = function (spec, z) {
    var self = this;
    var keys = this.tileKeysFor(spec, z);
    if (keys.length > this.maxTiles) return Promise.resolve();
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
        density: 300,        // CSS px^2 per particle
        minParticles: 200,
        maxParticles: 800,
        lineWidth: 1,        // CSS px, set from the widget settings
        color: '#ffffff',
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

      setColor: function (color) { this.options.color = color; },

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
        if (this._running && WindField.sameView(this._lastView, this._viewNow(), 2)) return;
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
        // A page that was just recreated (the popup reopened) has the last
        // grid in storage: use it at once when it is still fresh and covers
        // the view, instead of waiting fetchDelayMs for ensure() to say so.
        if (!this._entry) {
          var stored = this._source.restore();
          if (stored && stored.grid && !WindField.needsFetch(view, stored, this._source.now(), this._source.ttlMs))
            this._entry = stored;
        }
        // Draw right away with the grid we have when it still covers most of
        // the view (a patch in a corner after a zoom-out looks broken), and
        // settle the data a moment later so a run of pans does not fire one
        // Open-Meteo request per stop.
        if (this._entry && this._entry.grid && WindField.coverage(view.bounds, this._entry.spec) >= 0.5) this._start();
        var self = this, token = ++this._resetToken;
        if (this._fetchTimer) clearTimeout(this._fetchTimer);
        this._fetchTimer = setTimeout(function () {
          self._fetchTimer = null;
          self._source.ensure(view).then(function (entry) {
            if (token !== self._resetToken || !self._map) return;   // superseded by a later reset
            if (!entry || !entry.grid || WindField.coverage(view.bounds, entry.spec) < 0.5) {
              // No usable grid (fetch failed or the source is backing off):
              // try again by ourselves once the backoff is over, since the
              // user may not move the map again.
              var wait = Math.max(1000, self._source.blockedUntil - self._source.now() + 200);
              self._retryTimer = setTimeout(function () {
                self._retryTimer = null;
                if (token === self._resetToken && self._map) self._reset();
              }, wait);
              return;
            }
            self._entry = entry;
            if (self.options.relief && zoom >= self.options.reliefMinZoom) self._dem.ensure(entry.spec, self._demZoom);
            self._start();
          });
        }, this.options.fetchDelayMs);
      },

      _spawnAll: function () {
        var count = Math.round(this._w * this._h / this.options.density);
        count = Math.max(this.options.minParticles, Math.min(this.options.maxParticles, count));
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

        var paths = [new Path2D(), new Path2D(), new Path2D()];   // calm, moderate, strong
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
          var k = sv.speed < 2 ? 0 : (sv.speed < 6 ? 1 : 2);
          paths[k].moveTo(x * dpr, y * dpr);
          paths[k].lineTo(nx * dpr, ny * dpr);
          this._px[i] = nx;
          this._py[i] = ny;
        }
        ctx.strokeStyle = this.options.color;
        ctx.lineWidth = this.options.lineWidth * dpr;
        ctx.lineCap = 'round';
        var alphas = [0.35, 0.6, 0.9];
        for (var b = 0; b < 3; b++) { ctx.globalAlpha = alphas[b]; ctx.stroke(paths[b]); }
        ctx.globalAlpha = 1;
        if (pxCount) this._adaptFps(WindField.cadenceSpeed(spd, pxCount, this.options.cadenceFraction));
        if (!this._warming) this._stat(performance.now() - t0);
      }
    });
  }

  return { WindField: WindField, WindSource: WindSource, DemTiles: DemTiles, createWindLayer: createWindLayer };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetWind; }
