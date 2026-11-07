// ==========================================================================
// Glue script 2f: the temperature layer of the MapLibre map.
// The 2 m temperature comes the way the wind does: far out, the open-data
// file (the model's own field, no API call); closer, the API grids that the
// wind fetches too, in the same request, the file filling what they do not
// cover. Each pixel is brought from the height the data are valid at (the
// model's ground, or the API point's) to its own, read in the Terrarium
// tiles, at 6.5 °C per km. The map asks for the layer tile by tile, as for
// the night: it shows the tiles it has while new ones come, and keeps them
// for a zoom back. A tile is drawn a few rows per frame once its elevation
// tile is in; new data, or new colors, make a new set of tiles.
// ==========================================================================
WidgetTemp.TempLayer = (function () {
  'use strict';
  var WindField = WidgetWind.WindField;
  var DEG = Math.PI / 180;
  var TILE = 256;
  var SLICE_MS = 6;           // longest slice of drawing per frame
  var LATTICE = 8;            // the data are read every 8 px, and blended between
  var DEM_MAX_ZOOM = 12;      // past it, a tile reads the elevation tile it lies in
  var RECHECK_MS = 600000;    // a newer file now and then; latest.json at most every 10 min anyway
  var LEGEND_PX = 240;
  var RELIEF_KEPT = 48;       // tiles whose relief offsets are kept (256 KB each)

  /** 1 (full resolution), 2 (half) or 4 (quarter). */
  function normMovingStep(n) { n = +n; return n === 2 || n === 4 ? n : 1; }

  function latOfMercY(y) { return (2 * Math.atan(Math.exp(y)) - Math.PI / 2) / DEG; }

  /** Latitude of a row of world pixels at zoom z (row may be fractional). */
  function latOfRow(row, z) {
    return latOfMercY(Math.PI * (1 - 2 * row / (TILE * Math.pow(2, z))));
  }

  /** The temperature and the height it is valid at, at lat/lon: from the
      first field that has it. A field between two times (the animation)
      has a second set of values and the share of it (mix). A field with
      weights (a finer model over part of the map) is blended into the
      fields after it by its weight there, temperature and height alike:
      the height correction being linear, that is the blend of the
      corrected temperatures, so its border leaves no step. Without the
      height when noZ. */
  function readFields(fields, lat, lon, out, noZ, from) {
    for (var i = from || 0; i < fields.length; i++) {
      var f = fields[i], t = WidgetTemp.sampleScalar(f.grid, f.values, lat, lon);
      if (f.valuesB && f.mix > 0) t += (WidgetTemp.sampleScalar(f.grid, f.valuesB, lat, lon) - t) * f.mix;
      if (!isFinite(t)) continue;
      var z = f.elev && !noZ ? WidgetTemp.sampleScalar(f.grid, f.elev, lat, lon) : NaN;
      if (f.weights) {
        var w = WidgetTemp.sampleScalar(f.grid, f.weights, lat, lon) * (f.fade == null ? 1 : f.fade);
        if (!(w > 0)) continue;
        if (w < 1) {
          readFields(fields, lat, lon, out, noZ, i + 1);
          if (isFinite(out.t)) {
            out.t += (t - out.t) * w;
            out.z = isFinite(out.z) && isFinite(z) ? out.z + (z - out.z) * w : (isFinite(z) ? z : out.z);
            return;
          }
        }
      }
      out.t = t;
      out.z = z;
      return;
    }
    out.t = NaN;
    out.z = NaN;
  }

  /** What the relief adds to each pixel of a tile job, in °C: the
      correction is linear in the temperature, so it does not change from
      one picture to the next. */
  function reliefOffsets(job, lt) {
    var out = new Float32Array(TILE * TILE), n = TILE / LATTICE + 1, dem = job.demData, s = job.demShift;
    for (var row = 0; row < TILE; row++) {
      var li = Math.floor(row / LATTICE), fr = (row - li * LATTICE) / LATTICE;
      var demRow = ((job.demOffY + row) >> s) * TILE;
      for (var col = 0; col < TILE; col++) {
        var lj = Math.floor(col / LATTICE), fc = (col - lj * LATTICE) / LATTICE, k = li * n + lj;
        var zs = (lt.z[k] * (1 - fc) + lt.z[k + 1] * fc) * (1 - fr) + (lt.z[k + n] * (1 - fc) + lt.z[k + n + 1] * fc) * fr;
        out[row * TILE + col] = WidgetTemp.correct(0, zs, dem[demRow + ((job.demOffX + col) >> s)]);
      }
    }
    return out;
  }

  /** Rows r0 to r1 of a tile job into its pixels (RGBA): the fields
      blended between the lattice nodes, plus the relief offset of each
      pixel when there is elevation. A job of a lower resolution (step 2 or
      4: 128 or 64 px a side) reads every step-th pixel of the full tile. */
  function drawRows(job, r0, r1) {
    var px = job.px, lut = job.lut, lt = job.lattice, n = TILE / LATTICE + 1, off = job.offsets;
    var step = job.step || 1, size = TILE / step, half = step >> 1;
    for (var r = r0; r < r1; r++) {
      var row = r * step + half, li = Math.floor(row / LATTICE), fr = (row - li * LATTICE) / LATTICE;
      for (var c = 0; c < size; c++) {
        var col = c * step + half, lj = Math.floor(col / LATTICE), fc = (col - lj * LATTICE) / LATTICE;
        var k = li * n + lj, o = (r * size + c) * 4;
        var t00 = lt.t[k], t01 = lt.t[k + 1], t10 = lt.t[k + n], t11 = lt.t[k + n + 1];
        var t = (t00 * (1 - fc) + t01 * fc) * (1 - fr) + (t10 * (1 - fc) + t11 * fc) * fr;
        if (!isFinite(t)) { px[o + 3] = 0; continue; }
        if (off) t += off[row * TILE + col];
        var i = WidgetTemp.lutIndex(t) * 3;
        px[o] = lut[i]; px[o + 1] = lut[i + 1]; px[o + 2] = lut[i + 2]; px[o + 3] = 255;
      }
    }
  }

  /** The fields at every lattice node of tile z/x/y; without the heights
      when noZ. */
  function makeLattice(fields, z, x, y, noZ) {
    var n = TILE / LATTICE + 1, t = new Float32Array(n * n), zz = new Float32Array(n * n), out = {};
    var world = TILE * Math.pow(2, z);
    for (var i = 0; i < n; i++) {
      var lat = latOfRow(y * TILE + i * LATTICE + 0.5, z);
      for (var j = 0; j < n; j++) {
        var lon = (x * TILE + j * LATTICE + 0.5) / world * 360 - 180;
        readFields(fields, lat, lon, out, noZ);
        t[i * n + j] = out.t;
        zz[i * n + j] = out.z;
      }
    }
    return { t: t, z: zz };
  }

  function TempLayer(adapter, source, openData, dem, options) {
    options = options || {};
    this._adapter = adapter;
    this._source = source;
    this._open = openData || null;
    this._dem = dem || null;
    this.options = {
      stops: options.stops || WidgetTemp.DEFAULT_STOPS,
      step: WidgetTemp.normStep(options.step),
      unit: WidgetTemp.normUnit(options.unit),
      opacity: WidgetTemp.normOpacity(options.opacity),
      fetchDelayMs: options.fetchDelayMs == null ? 600 : options.fetchDelayMs,
      retryMinMs: options.retryMinMs == null ? 1000 : options.retryMinMs
    };
    this._now = options.now || function () { return Date.now(); };
    this._map = null;
    this._token = 0;          // view of the last reset
    this._drawn = false;
    this._mode = null;        // 'file' | 'api'
    this._fileGrid = null;
    this._fileState = this._open ? 'loading' : 'failed';
    this._surface = null;
    this._lut = null;
    this._legend = null;
    this._bar = null;         // the legend's colors
    this._shown = null;       // what the tiles on the map are drawn from: { fields, lut }
    this._version = 0;        // of those tiles
    this._api = null;         // the API field last made: { grid, field }
    this._jobs = [];          // tiles waiting for their rows to be drawn
    this._frame = false;      // a frame asked for those
    this._manual = !!options.manual;   // the file grid comes from showFile() (the animation); the API as usual
    this._at = null;          // manual mode: the time of the picture given (s), for the API grids
    this._drawnApi = null;    // the API entry on the map
    this._inflight = 0;       // tiles asked for and not drawn yet
    this._served = null;      // the data the last tile asked for was drawn from
    this._relief = new Map(); // tile -> { key, offsets }, oldest first
    this._moving = false;     // the animation plays: tiles at movingStep
    this._fade = 1;           // 0..1 over the opacity, while the layer fades in or out
    this.options.movingStep = normMovingStep(options.movingStep);
    var self = this;
    this._provider = function (z, x, y, signal) { return self.tile(z, x, y, signal); };
  }

  TempLayer.prototype = {
    addTo: function (map) {
      var self = this;
      this._map = map;
      this._lut = WidgetTemp.buildLut(this.options.stops, this.options.step, this.options.unit);
      this._legend = document.createElement('div');
      this._legend.id = 'lv-temp-legend';
      (document.getElementById('lv-map') || map.getContainer()).appendChild(this._legend);
      this._renderLegend();
      this._legend.style.opacity = String(this._fade);
      this._onMoveEnd = function () { self._reset(); };
      map.on('moveend', this._onMoveEnd);
      if (this._open && !this._manual) {
        var open = this._open;
        open.keptTemp().then(function (grid) {
          if (grid && !self._fileGrid) self._fileIn(grid, true);
          return open.loadTemp();
        }).then(function (res) {
          if (res) self._fileIn(res.grid, res.changed);
          else if (!self._fileGrid) {
            self._fileState = 'failed';
            self._reset();
          }
        });
        this._recheck = setInterval(function () {
          open.loadTemp().then(function (res) { if (res && res.changed) self._fileIn(res.grid, true); });
        }, RECHECK_MS);
        // Under Node (tests) the timer must not keep the process alive.
        if (this._recheck && this._recheck.unref) this._recheck.unref();
      }
      if (this._open) {
        this._open.loadSurface().then(function (surface) {
          if (!self._map || !surface) return;
          self._surface = surface;
          self._reset();
        });
      }
      this._reset();
      return this;
    },

    remove: function () {
      this._token++;
      if (this._fetchTimer) { clearTimeout(this._fetchTimer); this._fetchTimer = null; }
      if (this._recheck) { clearInterval(this._recheck); this._recheck = null; }
      if (!this._map) return;
      this._map.off('moveend', this._onMoveEnd);
      this._adapter.clearTemp();
      if (this._legend) this._legend.remove();
      this._legend = null;
      this._bar = null;
      this._map = null;
      this._shown = null;
      this._relief.clear();
    },

    /** True once a tile is drawn. */
    isDrawing: function () { return this._drawn; },

    /** Manual mode: the file grid to draw far out, and the time (its
        times[0]) to read the API grids at closer in. Zoomed in, the next
        picture only reads the grid on the map at the new time. */
    showFile: function (grid) {
      this._at = grid.times ? grid.times[0] : null;
      if (this._map && this._mode === 'api' && this._drawnApi) {
        this._fileGrid = grid;
        this._fileState = 'ready';
        this._show(this._apiFields(this._drawnApi.grid, this._fileFields()));
        return;
      }
      this._fileIn(grid, true);
    },

    /** The animation plays (on) or stops: while it plays, tiles are drawn
        at the moving resolution; once it stops, the picture shown is drawn
        again at full resolution. */
    setMoving: function (on) {
      on = !!on;
      if (on === this._moving) return;
      this._moving = on;
      if (!on && this._shown && this._shown.step !== 1) this._show(this._shown.fields, true);
    },

    /** Resolution of the tiles while the animation plays: 1, 2 or 4 (full,
        half, quarter). */
    setMovingStep: function (n) { this.options.movingStep = normMovingStep(n); },

    /** True once the map has asked for the tiles of the data shown and got
        them all. */
    settled: function () { return !!this._shown && this._served === this._shown && this._inflight === 0; },

    /** Opacity in percent: only the layer and the legend's colors change,
        nothing is redrawn. */
    setOpacity: function (percent) {
      this.options.opacity = WidgetTemp.normOpacity(percent);
      if (this._map) this._adapter.setTempOpacity(this.options.opacity / 100 * this._fade);
      if (this._bar) this._bar.style.opacity = String(this.options.opacity / 100);
    },

    /** Fade in or out (0..1) over the opacity, the legend with it: nothing
        is redrawn. */
    setFade: function (f) {
      this._fade = Math.max(0, Math.min(1, f));
      if (this._map) this._adapter.setTempOpacity(this.options.opacity / 100 * this._fade);
      if (this._legend) this._legend.style.opacity = String(this._fade);
    },

    setPalette: function (stops) { this.options.stops = stops || WidgetTemp.DEFAULT_STOPS; this._recolor(); },
    setStep: function (step) { this.options.step = WidgetTemp.normStep(step); this._recolor(); },
    setUnit: function (unit) { this.options.unit = WidgetTemp.normUnit(unit); this._recolor(); },

    /** The projection changed: the map draws its tiles again by itself. */
    refresh: function () {},

    /** The source's grids changed (other hours): draw again from it. */
    reload: function () { this._reset(); },

    /** The pixels of tile z/x/y (256 x 256 RGBA), drawn from the data on the
        map: once its elevation tile is in, a few rows per frame. Empty when
        the layer is gone or the map no longer wants the tile (signal). */
    tile: function (z, x, y, signal) {
      var self = this, shown = this._shown, step = shown ? shown.step : 1;
      var px = new Uint8ClampedArray((TILE / step) * (TILE / step) * 4);
      if (!this._map || !shown) return Promise.resolve(px);
      this._served = shown;
      this._inflight++;
      var dz = Math.min(z, DEM_MAX_ZOOM), s = z - dz;
      var dx = x >> s, dy = y >> s;
      var wantsDem = !!this._dem && shown.fields.some(function (f) { return !!f.elev; });
      var demReady = wantsDem ? this._dem.ensureTile(dz, dx, dy) : Promise.resolve();
      return demReady.then(function () {
        return new Promise(function (resolve) {
          var job = {
            px: px, lut: shown.lut, signal: signal, resolve: resolve, row: 0, step: step,
            demData: wantsDem ? self._dem.tileData(dz, dx, dy) : null,
            demShift: s, demOffX: (x - (dx << s)) * TILE, demOffY: (y - (dy << s)) * TILE
          };
          var kept = job.demData ? self._keptRelief(z, x, y, shown.fields, job.demData) : null;
          job.lattice = makeLattice(shown.fields, z, x, y, !!kept);
          if (job.demData) job.offsets = kept || self._keepRelief(z, x, y, shown.fields, job.demData, reliefOffsets(job, job.lattice));
          self._jobs.push(job);
          self._pump();
        });
      }).then(function (out) {
        self._inflight--;
        return out;
      }, function (err) {
        self._inflight--;
        throw err;
      });
    },

    /* The relief offsets of a tile hold while the heights the data are
       valid at and the elevation tile stay the same: the same fields (the
       file, and a finer model over it, as in the animation), each with the
       same grid, heights and edge weights, the same elevation. Only the
       files: the API grids change with the view, so they are not kept. */
    _reliefKey: function (fields, demData) {
      var parts = [];
      for (var i = 0; i < fields.length; i++) {
        var f = fields[i];
        // A finer model fading in or out blends the heights by its fade.
        if (!f.elev || f.grid.temp || f.fade != null && f.fade !== 1) return null;
        parts.push(f.grid.lats, f.elev, f.weights || null);
      }
      return parts.length ? { parts: parts, dem: demData } : null;
    },

    _keptRelief: function (z, x, y, fields, demData) {
      var key = this._reliefKey(fields, demData), id = z + '/' + x + '/' + y, e = this._relief.get(id);
      if (!key || !e || e.key.dem !== key.dem || e.key.parts.length !== key.parts.length) return null;
      for (var i = 0; i < key.parts.length; i++) if (e.key.parts[i] !== key.parts[i]) return null;
      this._relief.delete(id);
      this._relief.set(id, e);
      return e.offsets;
    },

    _keepRelief: function (z, x, y, fields, demData, offsets) {
      var key = this._reliefKey(fields, demData);
      if (!key) return offsets;
      this._relief.set(z + '/' + x + '/' + y, { key: key, offsets: offsets });
      if (this._relief.size > RELIEF_KEPT) this._relief.delete(this._relief.keys().next().value);
      return offsets;
    },

    /** Draw the waiting tiles, a few ms per frame, oldest first. */
    _pump: function () {
      if (this._frame) return;
      this._frame = true;
      var self = this;
      requestAnimationFrame(function () {
        self._frame = false;
        var t0 = performance.now();
        while (self._jobs.length && performance.now() - t0 < SLICE_MS) {
          var job = self._jobs[0];
          if (!self._map || (job.signal && job.signal.aborted)) {
            self._jobs.shift();
            job.px.fill(0);
            job.resolve(job.px);
            continue;
          }
          drawRows(job, job.row, Math.min(job.row + LATTICE, TILE / job.step));
          job.row += LATTICE;
          if (job.row < TILE / job.step) continue;
          self._jobs.shift();
          self._drawn = true;
          job.resolve(job.px);
        }
        if (self._jobs.length) self._pump();
      });
    },

    _recolor: function () {
      if (!this._map) return;
      this._lut = WidgetTemp.buildLut(this.options.stops, this.options.step, this.options.unit);
      this._renderLegend();
      if (this._shown) this._show(this._shown.fields);
    },

    _renderLegend: function () {
      var o = this.options, ticks = WidgetTemp.legendTicks(o.stops, o.unit);
      this._legend.innerHTML = '<div class="lv-temp-ticks">' + ticks.map(function (k) {
        return '<span style="left:' + (k.pos * 100).toFixed(2) + '%">' + k.label + '</span>';
      }).join('') + '</div><span class="lv-temp-unit">°' + o.unit + '</span>';
      var bar = document.createElement('canvas'), g = bar.getContext('2d'), lut = this._lut;
      var lo = o.stops[0].t, hi = o.stops[o.stops.length - 1].t;
      bar.width = LEGEND_PX;
      bar.height = 10;
      bar.className = 'lv-temp-bar';
      bar.style.opacity = String(o.opacity / 100);   // as light as the layer
      for (var x = 0; x < LEGEND_PX; x++) {
        var i = WidgetTemp.lutIndex(lo + (x + 0.5) / LEGEND_PX * (hi - lo)) * 3;
        g.fillStyle = 'rgb(' + lut[i] + ',' + lut[i + 1] + ',' + lut[i + 2] + ')';
        g.fillRect(x, 0, 1, 10);
      }
      this._legend.appendChild(bar);
      this._bar = bar;
    },

    _view: function () {
      var b = this._adapter.getBounds();
      return {
        bounds: { west: b.west, south: Math.max(-85, b.south), east: b.east, north: Math.min(85, b.north) },
        zoom: this._map.getZoom() + 1   // the wind's grids count zoom levels of 256 px tiles
      };
    },

    _setMode: function (mode) {
      if (mode === this._mode) return;
      this._mode = mode;
      console.log('[temp] source: ' + (mode === 'file' ? 'open data' : 'API'));
    },

    _fileIn: function (grid, changed) {
      var first = this._fileState !== 'ready';
      this._fileGrid = grid;
      this._fileState = 'ready';
      if (!this._map || (!first && !changed)) return;
      this._reset();
    },

    /** Far out the file; closer, or when the file failed, the API grids. */
    _reset: function () {
      if (!this._map) return;
      var self = this, token = ++this._token, view = this._view();
      if (this._fetchTimer) { clearTimeout(this._fetchTimer); this._fetchTimer = null; }
      var file = this._fileState === 'ready' && this._fileGrid ? this._fileFields() : null;
      if (this._open && this._fileState !== 'failed' && !WindField.wantApi(WindField.gridSpec(view.bounds), this._open.res)) {
        this._setMode('file');
        // Still on its way: _fileIn() shows it.
        if (file) this._show(file);
        return;
      }
      this._setMode('api');
      // Show at once the best grid at hand, then make sure the data cover
      // the view: one request serves the wind and the temperature.
      var best = this._source.best(view);
      var drawn = best && best.grid && best.grid.temp ? best : null;
      this._drawnApi = drawn;
      if (drawn) this._show(this._apiFields(drawn.grid, file));
      // Nothing from the API yet: the picture given meanwhile.
      else if (this._manual && file) this._show(file);
      this._fetchTimer = setTimeout(function () {
        self._fetchTimer = null;
        self._ensureFor(view, token, drawn);
      }, drawn ? this.options.fetchDelayMs : 0);
    },

    /** Get an API grid for the view of reset `token` and show it unless it
        is the one on the map; when the source holds back (the interval
        between requests, a failure), ask again once it allows, as the wind
        does. */
    _ensureFor: function (view, token, drawn) {
      var self = this;
      this._source.ensure(view).then(function (entry) {
        if (token !== self._token || !self._map) return;
        var now = self._source.now(), next = WindField.afterEnsure(view, entry, now, self._source.ttlMs);
        if (next.draw && entry !== drawn && entry.grid.temp) {
          drawn = self._drawnApi = entry;
          self._show(self._apiFields(entry.grid, self._fileState === 'ready' ? self._fileFields() : null));
        }
        if (!next.retry) return;
        var wait = Math.max(self.options.retryMinMs, (self._source.blockedUntil || 0) - now + 200);
        self._fetchTimer = setTimeout(function () {
          self._fetchTimer = null;
          if (token === self._token && self._map) self._ensureFor(view, token, drawn);
        }, wait);
      });
    },

    /** New tiles from these fields, unless the map shows them already
        (again anyway when force). */
    _show: function (fields, force) {
      var shown = this._shown, lut = this._lut, step = this._moving ? this.options.movingStep : 1;
      if (!force && shown && shown.lut === lut && shown.step === step && shown.fields.length === fields.length && shown.fields.every(function (f, i) {
        return f.values === fields[i].values && f.elev === fields[i].elev &&
          f.valuesB === fields[i].valuesB && f.mix === fields[i].mix && f.fade === fields[i].fade;
      })) return;
      this._shown = { fields: fields, lut: lut, step: step };
      this._adapter.setTempTiles(this._provider, ++this._version, this.options.opacity / 100 * this._fade);
    },

    /** The file's temperature, with the model's ground height when it
        matches; before it, the finer model's when the grid brings one
        (fine, with its own heights and edge weights). */
    _fileFields: function () {
      var g = this._fileGrid, s = this._surface, out = [];
      var f = g.fine;
      if (f && f.weights) {
        out.push({
          grid: f, values: f.values, valuesB: f.valuesB || null, mix: f.mix || 0, elev: f.elev || null,
          weights: f.weights, fade: f.fade == null ? 1 : f.fade
        });
      }
      out.push({
        grid: g, values: g.values, valuesB: g.valuesB || null, mix: g.mix || 0,
        elev: s && s.values.length === g.values.length ? s.values : null
      });
      return out;
    },

    /** An API grid, then the file where the grid ends. */
    _apiFields: function (grid, file) {
      // Live, the field made once per grid (a move then keeps the tiles); in
      // manual mode, once per time of the animation.
      var at = this._timeSec(), key = this._manual ? at : null;
      if (!this._api || this._api.grid !== grid || this._api.key !== key) this._api = { grid: grid, key: key, field: this._apiField(grid, at) };
      return file ? [this._api.field].concat(file) : [this._api.field];
    },

    /** The temperature drawn at lat/lon (°C), corrected to the height there
        once its elevation tile is in; null where nothing is drawn. */
    valueAt: function (lat, lon) {
      var shown = this._shown, out = {};
      if (!this._map || !shown) return null;
      readFields(shown.fields, lat, lon, out);
      if (!isFinite(out.t)) return null;
      var zPix = NaN;
      if (this._dem && isFinite(out.z)) {
        // The elevation tiles are those of the temperature tiles on screen.
        var z = this._map.getZoom() + 1, zooms = [Math.round(z), Math.floor(z)];
        for (var k = 0; k < zooms.length && !isFinite(zPix); k++) {
          var dz = Math.max(0, Math.min(zooms[k], DEM_MAX_ZOOM)), p = WindField.worldPx(lat, lon, dz);
          zPix = this._dem.elevationAtWorld(p.x, p.y, dz);
        }
      }
      return WidgetTemp.correct(out.t, out.z, zPix);
    },

    /** The color of the band temperature tC (°C) is drawn in, as on the map. */
    colorOf: function (tC) {
      var lut = this._lut || WidgetTemp.buildLut(this.options.stops, this.options.step, this.options.unit);
      var i = WidgetTemp.lutIndex(tC) * 3;
      return 'rgb(' + lut[i] + ', ' + lut[i + 1] + ', ' + lut[i + 2] + ')';
    },

    /** The time drawn (s): the animation's in manual mode, else now. */
    _timeSec: function () { return this._manual && this._at != null ? this._at : this._now() / 1000; },

    /** An API grid's temperature at time `at` (s), with its points' heights. */
    _apiField: function (grid, at) {
      var tw = WindField.timeWeights(grid.times, at);
      var a = grid.temp[tw.i], b = grid.temp[Math.min(tw.i + 1, grid.temp.length - 1)];
      var values = new Float32Array(a.length);
      for (var k = 0; k < a.length; k++) values[k] = a[k] + (b[k] - a[k]) * tw.frac;
      return { grid: grid, values: values, elev: grid.elev };
    }
  };

  TempLayer.readFields = readFields;
  return TempLayer;
})();
