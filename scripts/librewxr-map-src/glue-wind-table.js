// ==========================================================================
// Glue script 2d: the wind layer of the MapLibre map, flat or globe.
// Particles live in screen space on a 2D canvas over the map and move through
// a lookup table of the projection, built when the map stops: every CELL px,
// the longitude and latitude under the node and the inverse Jacobian that
// turns degrees per second into screen pixels per second (the method of
// earth.nullschool.net). No projection call per particle and no map redraw
// per frame. The table is built in slices of a few ms, so a slow CPU never
// freezes the map; particles hide while the map moves.
// ==========================================================================
WidgetWind.createTableWindLayer = function (maplibregl) {
  'use strict';
  var WindField = WidgetWind.WindField;
  var DEG = Math.PI / 180;
  var CELL = 12;              // px between table nodes
  var SLICE_MS = 4;           // longest slice of table building per frame
  var REVEAL_MS = 250;        // fade in of the wind after a change of projection
  var FILE_RES = 0.25;        // degrees of the files given in manual mode

  // Nested grids: every zoom of a band samples the same points (the map
  // zooms in fractions), and a finer grid holds the points of a coarser one.
  WindField.pow2Steps = 'round';

  function wrap180(d) { return ((d + 540) % 360) - 180; }

  function TableWindLayer(source, openData, dem, options) {
    this._source = source;
    this._open = openData;
    this._dem = dem;
    this._fade = 1;           // 0..1, the canvas's opacity while the layer fades in or out
    this._opacity = options && options.opacity != null ? Math.max(0, Math.min(1, options.opacity)) : 1;   // set by the user
    this.options = {
      fps: 10, maxFps: 20, stepPx: 2.5, cadenceFraction: 0.98,
      relief: true, reliefMinZoom: 9, sigma: 250,
      fade: 0.90, maxAge: 60, density: 1, lineWidth: 1, palette: null, theme: 'dark',
      speedScale: 3, minPx: 2, maxPx: 60,
      fetchDelayMs: 600, settleMs: 1500, level: '10m',
      manual: false          // the file grid comes from showFile() (the animation); the API as usual
    };
    for (var k in options) if (options[k] !== undefined) this.options[k] = options[k];
    this.options.lineWidth = WindField.lineWidth(this.options.lineWidth);
    this.options.palette = this.options.palette || WindField.DEFAULT_PALETTE;
    this._velOpts = { k: this.options.speedScale, min: this.options.minPx, max: this.options.maxPx };
    this._fps = this.options.fps;
    this._active = true;
    this._running = false;
    this._settled = false;
    this._loop = 0;
    this._job = 0;
    this._resetToken = 0;
    this._entry = null;
    this._n = 0;
    this._mode = null;       // 'file' | 'api': where the drawn grid comes from
    this._fileGrid = {};     // per level, from the open-data files
    this._fileState = {};    // per level: 'loading' | 'ready' | 'failed'
    this.nudging = false;    // set by fixViewport around its repaint nudge
  }

  TableWindLayer.prototype = WidgetWind.withParticles({
    addTo: function (map) {
      var self = this;
      this._map = map;
      this._canvas = document.createElement('canvas');
      this._canvas.className = 'lv-wind-canvas';
      this._canvas.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none;';
      this._canvas.style.opacity = String(this._fade * this._opacity);
      // Right over the map's own canvas: markers and popups stay on top.
      var gl = map.getCanvas();
      gl.parentNode.insertBefore(this._canvas, gl.nextSibling);
      this._ctx = this._canvas.getContext('2d');
      // The widget resizes the map now and then without changing the view
      // (viewport fixes, repaint nudges): only a real move stops the
      // particles, and an end of move on the same view keeps them going.
      this._onMove = function () {
        if (!self.nudging && (self._running || self._building) && self._viewKey() !== self._lastKey) self._stop(true);
      };
      this._onMoveEnd = function () {
        if (self.nudging) return;
        if ((self._running || self._building) && self._viewKey() === self._lastKey) return;
        self._reset();
      };
      this._onVisibility = function () { if (document.hidden) self._stop(false); else self._reset(); };
      map.on('move', this._onMove);
      map.on('moveend', this._onMoveEnd);
      map.on('resize', this._onMoveEnd);
      document.addEventListener('visibilitychange', this._onVisibility);
      // Nothing is drawn before settle(): the page's first viewport fix
      // would land the particles in a provisional frame.
      this._settleTimer = setTimeout(function () { self.settle(); }, this.options.settleMs);
      if (this._open && !this.options.manual) {
        this._loadFile(this.options.level);
        // A newer file now and then; the loader reads latest.json at most every 10 min.
        this._recheck = setInterval(function () { self._loadFile(self.options.level); }, 600000);
      }
      this._reset();
      return this;
    },

    remove: function () {
      this._stop(true);
      if (this._settleTimer) clearTimeout(this._settleTimer);
      if (this._recheck) clearInterval(this._recheck);
      if (!this._map) return;
      this._map.off('move', this._onMove);
      this._map.off('moveend', this._onMoveEnd);
      this._map.off('resize', this._onMoveEnd);
      document.removeEventListener('visibilitychange', this._onVisibility);
      this._canvas.remove();
      this._canvas = this._ctx = this._map = null;
    },

    /** Fade in or out (0..1): the canvas's opacity, the particles go on. */
    setFade: function (f) {
      this._fade = Math.max(0, Math.min(1, f));
      if (this._canvas) this._canvas.style.opacity = String(this._fade * this._opacity);
    },

    /** The opacity chosen for the layer (0..1), under its fade. */
    setOpacity: function (v) {
      this._opacity = Math.max(0, Math.min(1, v));
      if (this._canvas) this._canvas.style.opacity = String(this._fade * this._opacity);
    },

    getOpacity: function () { return this._opacity; },

    /** Pause (popup collapsed) or resume. */
    setActive: function (active) {
      this._active = !!active;
      if (this._active) this._reset();
      else this._stop(true);
    },

    /** Manual mode: the file grid to draw far out, in place of the latest
        file. Its `at` (s) is the time drawn, also on the API grids closer in
        (they hold every hour of the animation). The particles go on across
        the swap. */
    showFile: function (grid) {
      var level = this.options.level, first = this._fileState[level] !== 'ready';
      this._at = grid.at;
      this._fileGrid[level] = grid;
      this._fileState[level] = 'ready';
      if (!this._map) return;
      if (first) { this._reset(); return; }
      if (this._mode === 'file') {
        this._entry = { grid: grid };
        if (!this._running && !this._building) this._start();
      }
    },

    /** Whether the grid given is on screen: false while the table of the
        projection is being built. */
    settled: function () { return !this._building; },

    /** The wind drawn at lat/lon, { speed (m/s), dir (from, degrees) }, or
        null where none is drawn. */
    valueAt: function (lat, lon) {
      var grid = this._grid();
      if (!grid || !this._map) return null;
      var o = this.options, z = this._map.getZoom() + 1, hP = NaN;
      var sigma = o.relief && z >= o.reliefMinZoom && grid.elev && o.level === '10m' ? o.sigma : 0;
      if (sigma > 0) {
        var dz = this._demZoom(), p = WindField.worldPx(lat, lon, dz);
        hP = this._dem.elevationAtWorld(p.x, p.y, dz);
      }
      var uv = WindField.sampleChain(grid, lat, lon, WindField.timeWeights(grid.times, this._time(grid)), hP, sigma, o.level);
      return uv ? WindField.fromUV(uv.u, uv.v) : null;
    },

    /** The color of the particles at speed ms (m/s). */
    colorOf: function (ms) {
      var p = this.options.palette;
      return WindField.bandColor(p, WindField.paletteBand(ms, p), this.options.theme);
    },

    /** The time a grid is drawn at (s): its own (a file of the animation),
        the animation's (manual mode), else now. */
    _time: function (grid) {
      return grid.at != null ? grid.at : this._at != null ? this._at : Date.now() / 1000;
    },

    setDensity: function (density) {
      this.options.density = density > 0 ? density : 1;
      if (this._map) this._reset();
    },

    setLevel: function (level) {
      this.options.level = level === '700hPa' ? '700hPa' : '10m';
      if (this._open && !this._fileState[this.options.level]) this._loadFile(this.options.level);
      if (this._map) this._reset();
    },

    /** The projection changed under the layer: rebuild the table. */
    refresh: function () { if (this._map) this._reset(); },

    /** The projection is changing: the particles of the old one go at once
        (they would stand in the wrong places), the table is built again on
        the first frame of the new one, and the wind fades back in. */
    reproject: function () {
      if (!this._map) return;
      var self = this;
      this._stop(true);
      this._map.once('render', function () {
        requestAnimationFrame(function () {
          if (!self._map) return;
          self._fadeIn = true;
          self._reset();
        });
      });
      this._map.triggerRepaint();
    },

    /** The source's grids changed (other hours): draw again from it. */
    reload: function () { if (this._map) this._reset(); },

    _stop: function (clear) {
      this._running = false;
      this._loop++;
      // A build slice still waiting for its frame sees the new job number
      // and gives up; a restart may begin a new build at once.
      this._job++;
      this._building = false;
      if (this._timer) { clearTimeout(this._timer); this._timer = null; }
      if (this._fetchTimer) { clearTimeout(this._fetchTimer); this._fetchTimer = null; }
      if (this._retryTimer) { clearTimeout(this._retryTimer); this._retryTimer = null; }
      if (clear && this._ctx) this._ctx.clearRect(0, 0, this._canvas.width, this._canvas.height);
    },

    /** The view on the widget's zoom scale (256 px tiles, one above MapLibre's). */
    _view: function () {
      var b = this._map.getBounds();
      return {
        bounds: { west: b.getWest(), south: Math.max(-85, b.getSouth()), east: b.getEast(), north: Math.min(85, b.getNorth()) },
        zoom: this._map.getZoom() + 1
      };
    },

    /** Center, zoom, rotation, tilt and size: what a real move changes. */
    _viewKey: function () {
      var m = this._map, c = m.getCenter(), box = m.getContainer();
      return [c.lng.toFixed(6), c.lat.toFixed(6), m.getZoom().toFixed(4), m.getBearing().toFixed(2),
        m.getPitch().toFixed(2), box.clientWidth, box.clientHeight].join(',');
    },

    _reset: function () {
      if (!this._map || !this._canvas) return;
      this._stop(true);
      this._lastKey = this._viewKey();
      var c = this._map.getContainer();
      this._dpr = Math.min(2, window.devicePixelRatio || 1);
      this._w = c.clientWidth;
      this._h = c.clientHeight;
      this._canvas.width = Math.round(this._w * this._dpr);
      this._canvas.height = Math.round(this._h * this._dpr);
      if (!this._active || document.hidden || !this._settled) return;
      var view = this._view(), self = this, token = ++this._resetToken, level = this.options.level;
      // Far out, the open-data file: the model's own field, no API call. The
      // API only once its grid is finer than the file's; while the file is
      // on its way, wait for it; if it failed, the API at every zoom. In
      // manual mode the file is the one given (showFile).
      var fileRes = this.options.manual ? FILE_RES : this._open && this._open.res;
      if (fileRes && !WindField.wantApi(WindField.gridSpec(view.bounds), fileRes)) {
        if (this.options.manual && this._fileState[level] !== 'ready') { this._setMode('file'); return; }
        if (this._fileState[level] === 'ready') {
          this._setMode('file');
          this._entry = { grid: this._fileGrid[level] };
          this._start();
          return;
        }
        if (this._fileState[level] === 'loading') { this._setMode('file'); return; }
      }
      this._setMode('api');
      // Draw at once with the best grid at hand, then make sure the data
      // cover the view: a run of pans does not fire one request per stop.
      var best = this._source.best(view);
      if (best) this._entry = best;
      this._fetchTimer = setTimeout(function () {
        self._fetchTimer = null;
        self._ensureFor(view, token);
      }, this._entry ? this.options.fetchDelayMs : 0);
      if (this._grid()) this._start();
    },

    /** Get an API grid for the view of reset `token`; when the source holds
        back (rate limit, failure), ask again once it allows. */
    _ensureFor: function (view, token) {
      var self = this;
      this._source.ensure(view).then(function (entry) {
        if (token !== self._resetToken || !self._map) return;
        var now = self._source.now(), ttl = self._source.ttlMs;
        if (WindField.needsFetch(view, entry, now, ttl)) entry = self._source.best(view) || entry;
        var next = WindField.afterEnsure(view, entry, now, ttl);
        if (next.draw) {
          self._entry = entry;
          if (self.options.relief && view.zoom >= self.options.reliefMinZoom) self._dem.ensure(entry.spec, self._demZoom());
          self._start();
        }
        if (next.retry) {
          var wait = Math.max(1000, self._source.blockedUntil - self._source.now() + 200);
          self._retryTimer = setTimeout(function () {
            self._retryTimer = null;
            if (token === self._resetToken && self._map) self._ensureFor(view, token);
          }, wait);
        }
      });
    },

    _grid: function () { return this._entry && this._entry.grid; },

    _setMode: function (mode) {
      if (mode === this._mode) return;
      this._mode = mode;
      console.log('[wind] source: ' + (mode === 'file' ? 'open data' : 'API'));
    },

    /** The kept wind of a level at once, then the latest file when newer. */
    _loadFile: function (level) {
      var self = this, open = this._open;
      if (!this._fileState[level]) this._fileState[level] = 'loading';
      open.kept(level).then(function (grid) {
        if (grid && !self._fileGrid[level]) {
          console.log('[wind] open data: kept wind of ' + level);
          self._fileIn(level, grid, true);
        }
        return open.load(level);
      }).then(function (res) {
        if (res) self._fileIn(level, res.grid, res.changed);
        else if (!self._fileGrid[level]) {
          self._fileState[level] = 'failed';
          if (level === self.options.level && self._mode === 'file') self._reset();
        }
      });
    },

    _fileIn: function (level, grid, changed) {
      var first = this._fileState[level] !== 'ready';
      this._fileGrid[level] = grid;
      this._fileState[level] = 'ready';
      if (level !== this.options.level || !this._map || (!first && !changed)) return;
      if (this._mode === 'file') {
        if (this._running) this._entry = { grid: grid };   // live swap, the particles go on
        else this._reset();
        return;
      }
      // Drawn from the API: switch only when this view belongs to the file.
      if (!WindField.wantApi(WindField.gridSpec(this._view().bounds), this._open.res)) this._reset();
    },

    _demZoom: function () { return Math.min(10, Math.max(9, Math.round(this._map.getZoom() + 1))); },

    /** Build the table and the particles in slices, then run the frames. */
    _start: function () {
      if (this._running || this._building || !this._settled) return;
      var self = this, job = ++this._job, steps = this._build();
      this._building = true;
      this._canvas.style.visibility = 'hidden';
      var slice = function () {
        if (job !== self._job) return;
        var t0 = performance.now(), done = false;
        do { done = steps.next().done; } while (!done && performance.now() - t0 < SLICE_MS);
        if (!done) { requestAnimationFrame(slice); return; }
        self._building = false;
        self._canvas.style.visibility = '';
        if (self._fadeIn) {
          self._fadeIn = false;
          if (self._canvas.animate) self._canvas.animate([{ opacity: 0 }, { opacity: self._fade * self._opacity }], { duration: REVEAL_MS, easing: 'ease-out' });
        }
        self._running = true;
        self._schedule();
      };
      slice();
    },

    _build: function* () {
      yield* this._buildTable();
      var t = this._table;
      this._n = WindField.particleCount(t.area, this.options.density, WindField.maxParticles(this.options.density));
      this._px = new Float32Array(this._n);
      this._py = new Float32Array(this._n);
      this._age = new Uint16Array(this._n);
      this._spd = new Float32Array(this._n);
      for (var i = 0; i < this._n; i++) this._spawn(i, true);
      // The first frames at once, so the first frame shown has full trails.
      var n = WindField.warmUpFrames(this.options.fade);
      this._warming = true;
      for (var f = 0; f < n; f++) { this._frame(); yield; }
      this._warming = false;
    },

    _buildTable: function* () {
      var map = this._map, cols = Math.ceil(this._w / CELL) + 1, rows = Math.ceil(this._h / CELL) + 1, N = cols * rows;
      var t = {
        cols: cols, rows: rows, area: 0,
        lon: new Float64Array(N), lat: new Float64Array(N), ok: new Uint8Array(N), okJ: new Uint8Array(N),
        a11: new Float32Array(N), a12: new Float32Array(N), a21: new Float32Array(N), a22: new Float32Array(N)
      };
      var tr = map._camera && map._camera.transform ? map._camera.transform : map.transform;
      var i, j, k, count = 0;
      // A yield every 8 nodes: on a slow CPU one node costs about 1 ms.
      for (j = 0; j < rows; j++) {
        for (i = 0; i < cols; i++) {
          if (++count % 8 === 0) yield;
          var x = i * CELL, y = j * CELL, ll = map.unproject([x, y]);
          if (!ll || !isFinite(ll.lat) || Math.abs(ll.lat) > 85) continue;
          var p = map.project(ll);
          // Off the globe, unproject lands elsewhere; behind it, it is hidden.
          if (Math.abs(p.x - x) > 0.5 || Math.abs(p.y - y) > 0.5) continue;
          if (tr && tr.isLocationOccluded && tr.isLocationOccluded(ll)) continue;
          k = j * cols + i;
          t.lon[k] = ll.lng;
          t.lat[k] = ll.lat;
          t.ok[k] = 1;
        }
      }
      var valid = 0;
      for (j = 0; j < rows; j++) {
        for (i = 0; i < cols; i++) {
          k = j * cols + i;
          if (!t.ok[k]) continue;
          var iL = i > 0 && t.ok[k - 1] ? i - 1 : i, iR = i < cols - 1 && t.ok[k + 1] ? i + 1 : i;
          var jU = j > 0 && t.ok[k - cols] ? j - 1 : j, jD = j < rows - 1 && t.ok[k + cols] ? j + 1 : j;
          if (iL === iR || jU === jD) continue;
          var kL = j * cols + iL, kR = j * cols + iR, kU = jU * cols + i, kD = jD * cols + i;
          var dx = (iR - iL) * CELL, dy = (jD - jU) * CELL;
          var lx = wrap180(t.lon[kR] - t.lon[kL]) / dx, ax = (t.lat[kR] - t.lat[kL]) / dx;
          var ly = wrap180(t.lon[kD] - t.lon[kU]) / dy, ay = (t.lat[kD] - t.lat[kU]) / dy;
          var det = lx * ay - ly * ax;
          if (!(Math.abs(det) > 1e-14)) continue;
          t.a11[k] = ay / det; t.a12[k] = -ly / det; t.a21[k] = -ax / det; t.a22[k] = lx / det;
          t.okJ[k] = 1;
          valid++;
        }
      }
      t.area = valid * CELL * CELL;
      this._table = t;
    },

    /** Index of the table cell under (x, y) when its four nodes are usable, else -1. */
    _cell: function (x, y) {
      var t = this._table;
      if (!(x >= 0 && y >= 0)) return -1;
      var ci = Math.floor(x / CELL), cj = Math.floor(y / CELL);
      if (ci >= t.cols - 1 || cj >= t.rows - 1) return -1;
      var k = cj * t.cols + ci, ok = t.okJ;
      return ok[k] && ok[k + 1] && ok[k + t.cols] && ok[k + t.cols + 1] ? k : -1;
    },

    _spawn: function (i, randomAge) {
      var t = this._table, W = (t.cols - 1) * CELL, H = (t.rows - 1) * CELL;
      for (var tries = 0; tries < 12; tries++) {
        var x = Math.random() * W, y = Math.random() * H;
        if (this._cell(x, y) < 0) continue;
        this._px[i] = x;
        this._py[i] = y;
        this._age[i] = randomAge ? (Math.random() * this.options.maxAge) | 0 : 0;
        return;
      }
      this._px[i] = NaN;
      this._age[i] = this.options.maxAge;
    },

    _frame: function () {
      var grid = this._grid();
      if (!grid || !this._table) return;
      var t0 = performance.now(), ctx = this._ctx, dpr = this._dpr, o = this.options, t = this._table, cols = t.cols;
      this._fadeTrails(ctx, o.fade);
      var map = this._map, glZoom = map.getZoom(), z = glZoom + 1;
      var pxPerDeg = 512 * Math.pow(2, glZoom) / 360 / Math.cos(map.getCenter().lat * DEG);
      var tw = WindField.timeWeights(grid.times, this._time(grid));
      // Relief weighting near the ground, from the API grid's elevations.
      var sigma = o.relief && z >= o.reliefMinZoom && grid.elev && o.level === '10m' ? o.sigma : 0;
      var dz = this._demZoom(), worldSize = 256 * Math.pow(2, dz);
      var dt = 1 / this._fps, palette = o.palette, spd = this._spd, pxCount = 0, paths = this._paths();
      for (var i = 0; i < this._n; i++) {
        if (++this._age[i] > o.maxAge) { this._spawn(i, false); continue; }
        var x = this._px[i], y = this._py[i], k = this._cell(x, y);
        if (k < 0) { this._spawn(i, false); continue; }
        var fx = x / CELL, fy = y / CELL, tx = fx - Math.floor(fx), ty = fy - Math.floor(fy);
        var w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty, w00 = 1 - w10 - w01 - w11;
        var lon0 = t.lon[k];
        var lon = lon0 + w10 * wrap180(t.lon[k + 1] - lon0) + w01 * wrap180(t.lon[k + cols] - lon0) + w11 * wrap180(t.lon[k + cols + 1] - lon0);
        var lat = w00 * t.lat[k] + w10 * t.lat[k + 1] + w01 * t.lat[k + cols] + w11 * t.lat[k + cols + 1];
        var hP = NaN;
        if (sigma > 0) {
          var wx = (lon + 180) / 360 * worldSize;
          var wy = (1 - Math.log(Math.tan(Math.PI / 4 + lat * DEG / 2)) / Math.PI) / 2 * worldSize;
          hP = this._dem.elevationAtWorld(wx, wy, dz);
        }
        var uv = WindField.sampleChain(grid, lat, lon, tw, hP, sigma, o.level);
        if (!uv) { this._spawn(i, false); continue; }
        var sv = WindField.screenVelocity(uv.u, uv.v, this._velOpts);
        var dlon = sv.dx / (pxPerDeg * Math.max(0.05, Math.cos(lat * DEG))), dlat = -sv.dy / pxPerDeg;
        // The nearest node's matrix: cells are CELL px wide, smooth enough.
        var a = tx < 0.5 ? (ty < 0.5 ? k : k + cols) : (ty < 0.5 ? k + 1 : k + cols + 1);
        var vx = t.a11[a] * dlon + t.a12[a] * dlat, vy = t.a21[a] * dlon + t.a22[a] * dlat;
        var nx = x + vx * dt, ny = y + vy * dt;
        spd[pxCount++] = Math.sqrt(vx * vx + vy * vy);
        var b = WindField.paletteBand(sv.speed, palette);
        paths[b].moveTo(x * dpr, y * dpr);
        paths[b].lineTo(nx * dpr, ny * dpr);
        this._px[i] = nx;
        this._py[i] = ny;
      }
      this._stroke(ctx, paths, dpr, pxCount);
      if (!this._warming) this._stat(performance.now() - t0);
    }
  });

  return TableWindLayer;
};
