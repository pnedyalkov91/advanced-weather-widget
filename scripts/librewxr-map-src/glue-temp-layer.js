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

  function latOfMercY(y) { return (2 * Math.atan(Math.exp(y)) - Math.PI / 2) / DEG; }

  /** Latitude of a row of world pixels at zoom z (row may be fractional). */
  function latOfRow(row, z) {
    return latOfMercY(Math.PI * (1 - 2 * row / (TILE * Math.pow(2, z))));
  }

  /** The temperature and the height it is valid at, at lat/lon: from the
      first field that has it. */
  function readFields(fields, lat, lon, out) {
    for (var i = 0; i < fields.length; i++) {
      var f = fields[i], t = WidgetTemp.sampleScalar(f.grid, f.values, lat, lon);
      if (!isFinite(t)) continue;
      out.t = t;
      out.z = f.elev ? WidgetTemp.sampleScalar(f.grid, f.elev, lat, lon) : NaN;
      return;
    }
    out.t = NaN;
    out.z = NaN;
  }

  /** Rows r0 to r1 of a tile job into its pixels (RGBA): the fields
      blended between the lattice nodes, the elevation pixel by pixel. */
  function drawRows(job, r0, r1) {
    var px = job.px, lut = job.lut, lt = job.lattice, n = TILE / LATTICE + 1, dem = job.demData, s = job.demShift;
    for (var row = r0; row < r1; row++) {
      var li = Math.floor(row / LATTICE), fr = (row - li * LATTICE) / LATTICE;
      var demRow = dem ? ((job.demOffY + row) >> s) * TILE : 0;
      for (var col = 0; col < TILE; col++) {
        var lj = Math.floor(col / LATTICE), fc = (col - lj * LATTICE) / LATTICE;
        var k = li * n + lj, o = (row * TILE + col) * 4;
        var t00 = lt.t[k], t01 = lt.t[k + 1], t10 = lt.t[k + n], t11 = lt.t[k + n + 1];
        var t = (t00 * (1 - fc) + t01 * fc) * (1 - fr) + (t10 * (1 - fc) + t11 * fc) * fr;
        if (!isFinite(t)) { px[o + 3] = 0; continue; }
        if (dem) {
          var zs = (lt.z[k] * (1 - fc) + lt.z[k + 1] * fc) * (1 - fr) + (lt.z[k + n] * (1 - fc) + lt.z[k + n + 1] * fc) * fr;
          t = WidgetTemp.correct(t, zs, dem[demRow + ((job.demOffX + col) >> s)]);
        }
        var i = WidgetTemp.lutIndex(t) * 3;
        px[o] = lut[i]; px[o + 1] = lut[i + 1]; px[o + 2] = lut[i + 2]; px[o + 3] = 255;
      }
    }
  }

  /** The fields at every lattice node of tile z/x/y. */
  function makeLattice(fields, z, x, y) {
    var n = TILE / LATTICE + 1, t = new Float32Array(n * n), zz = new Float32Array(n * n), out = {};
    var world = TILE * Math.pow(2, z);
    for (var i = 0; i < n; i++) {
      var lat = latOfRow(y * TILE + i * LATTICE + 0.5, z);
      for (var j = 0; j < n; j++) {
        var lon = (x * TILE + j * LATTICE + 0.5) / world * 360 - 180;
        readFields(fields, lat, lon, out);
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
    this._shown = null;       // what the tiles on the map are drawn from: { fields, lut }
    this._version = 0;        // of those tiles
    this._api = null;         // the API field last made: { grid, field }
    this._jobs = [];          // tiles waiting for their rows to be drawn
    this._frame = false;      // a frame asked for those
    this._manual = !!options.manual;   // the file grid comes from showFile() only (the animation)
    this._inflight = 0;       // tiles asked for and not drawn yet
    this._served = null;      // the data the last tile asked for was drawn from
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
      this._map = null;
      this._shown = null;
    },

    /** True once a tile is drawn. */
    isDrawing: function () { return this._drawn; },

    /** Manual mode: show this file grid at every zoom. */
    showFile: function (grid) { this._fileIn(grid, true); },

    /** True once the map has asked for the tiles of the data shown and got
        them all. */
    settled: function () { return !!this._shown && this._served === this._shown && this._inflight === 0; },

    /** Opacity in percent: only the layer changes, nothing is redrawn. */
    setOpacity: function (percent) {
      this.options.opacity = WidgetTemp.normOpacity(percent);
      if (this._map) this._adapter.setTempOpacity(this.options.opacity / 100);
    },

    setPalette: function (stops) { this.options.stops = stops || WidgetTemp.DEFAULT_STOPS; this._recolor(); },
    setStep: function (step) { this.options.step = WidgetTemp.normStep(step); this._recolor(); },
    setUnit: function (unit) { this.options.unit = WidgetTemp.normUnit(unit); this._recolor(); },

    /** The projection changed: the map draws its tiles again by itself. */
    refresh: function () {},

    /** The pixels of tile z/x/y (256 x 256 RGBA), drawn from the data on the
        map: once its elevation tile is in, a few rows per frame. Empty when
        the layer is gone or the map no longer wants the tile (signal). */
    tile: function (z, x, y, signal) {
      var self = this, shown = this._shown, px = new Uint8ClampedArray(TILE * TILE * 4);
      if (!this._map || !shown) return Promise.resolve(px);
      this._served = shown;
      this._inflight++;
      var dz = Math.min(z, DEM_MAX_ZOOM), s = z - dz;
      var dx = x >> s, dy = y >> s;
      var wantsDem = !!this._dem && shown.fields.some(function (f) { return !!f.elev; });
      var demReady = wantsDem ? this._dem.ensureTile(dz, dx, dy) : Promise.resolve();
      return demReady.then(function () {
        return new Promise(function (resolve) {
          self._jobs.push({
            px: px, lut: shown.lut, signal: signal, resolve: resolve, row: 0,
            lattice: makeLattice(shown.fields, z, x, y),
            demData: wantsDem ? self._dem.tileData(dz, dx, dy) : null,
            demShift: s, demOffX: (x - (dx << s)) * TILE, demOffY: (y - (dy << s)) * TILE
          });
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
          drawRows(job, job.row, job.row + LATTICE);
          job.row += LATTICE;
          if (job.row < TILE) continue;
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
      for (var x = 0; x < LEGEND_PX; x++) {
        var i = WidgetTemp.lutIndex(lo + (x + 0.5) / LEGEND_PX * (hi - lo)) * 3;
        g.fillStyle = 'rgb(' + lut[i] + ',' + lut[i + 1] + ',' + lut[i + 2] + ')';
        g.fillRect(x, 0, 1, 10);
      }
      this._legend.appendChild(bar);
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
      var file = this._open && this._fileState === 'ready' ? this._fileField() : null;
      if (this._manual) {
        this._setMode('file');
        if (file) this._show([file]);
        return;
      }
      if (this._open && this._fileState !== 'failed' && !WindField.wantApi(WindField.gridSpec(view.bounds), this._open.res)) {
        this._setMode('file');
        // Still on its way: _fileIn() shows it.
        if (file) this._show([file]);
        return;
      }
      this._setMode('api');
      // Show at once the best grid at hand, then make sure the data cover
      // the view: one request serves the wind and the temperature.
      var best = this._source.best(view);
      var drawn = best && best.grid && best.grid.temp ? best : null;
      if (drawn) this._show(this._apiFields(drawn.grid, file));
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
          drawn = entry;
          self._show(self._apiFields(entry.grid, self._fileState === 'ready' ? self._fileField() : null));
        }
        if (!next.retry) return;
        var wait = Math.max(self.options.retryMinMs, (self._source.blockedUntil || 0) - now + 200);
        self._fetchTimer = setTimeout(function () {
          self._fetchTimer = null;
          if (token === self._token && self._map) self._ensureFor(view, token, drawn);
        }, wait);
      });
    },

    /** New tiles from these fields, unless the map shows them already. */
    _show: function (fields) {
      var shown = this._shown, lut = this._lut;
      if (shown && shown.lut === lut && shown.fields.length === fields.length && shown.fields.every(function (f, i) {
        return f.values === fields[i].values && f.elev === fields[i].elev;
      })) return;
      this._shown = { fields: fields, lut: lut };
      this._adapter.setTempTiles(this._provider, ++this._version, this.options.opacity / 100);
    },

    /** The file's temperature, with the model's ground height when it matches. */
    _fileField: function () {
      var g = this._fileGrid, s = this._surface;
      return { grid: g, values: g.values, elev: s && s.values.length === g.values.length ? s.values : null };
    },

    /** An API grid, then the file where the grid ends. */
    _apiFields: function (grid, file) {
      if (!this._api || this._api.grid !== grid) this._api = { grid: grid, field: this._apiField(grid) };
      return file ? [this._api.field, file] : [this._api.field];
    },

    /** An API grid's temperature at the present time, with its points' heights. */
    _apiField: function (grid) {
      var tw = WindField.timeWeights(grid.times, this._now() / 1000);
      var a = grid.temp[tw.i], b = grid.temp[Math.min(tw.i + 1, grid.temp.length - 1)];
      var values = new Float32Array(a.length);
      for (var k = 0; k < a.length; k++) values[k] = a[k] + (b[k] - a[k]) * tw.frac;
      return { grid: grid, values: values, elev: grid.elev };
    }
  };

  return TempLayer;
})();
