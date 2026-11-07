// ==========================================================================
// Glue script 2g: the weather over time, from the past day to two days
// ahead, one picture every 3 hours, for each layer switched on (temperature,
// wind; more to come): each has its own pictures, a Group moves them on
// together. Each hour comes from the open-data file
// of the latest run that covers it: for the past, the run of that morning or
// evening (Open-Meteo keeps them about a week), for the future, the latest
// run, or the latest of 00 or 12 UTC past the 6 days the others hold. The
// pictures are read a few at a time, nearest to now first, and kept on one
// byte per point and field (the temperature by half degrees, 1 MB each
// instead of 4; the wind by half m/s, 2 MB, at the file's 0.25 degree as
// the radar draws it). They
// are also kept in IndexedDB (frameStore): a file never changes, so what was
// read once comes back from there, even after the page or Plasma restarts. WidgetAnim is loadable
// under Node for tests; the page drives it through window.anim*.
// ==========================================================================
var WidgetAnim = (function () {
  'use strict';

  var HOUR = 3600e3;
  var STEP_H = 3;               // the files hold one hour in three
  var RUN_H = 6;                // runs start at 00, 06, 12 and 18 UTC
  var LONG_RUN_H = 12;          // those of 00 and 12 UTC go 15 days ahead
  var SHORT_RANGE_H = 144;      // those of 06 and 18 UTC, 6 days
  var PACK_MIN = -80, PACK_NAN = 255;   // byte b is PACK_MIN + b / 2 °C (TEMP_QUANTUM)
  var WIND_MIN = -63.5;         // byte b is WIND_MIN + b / 2 m/s
  var EDGE_JITTER = 2;          // degrees: how far in a finer model may start to blend (see edgeJitter)

  /** The hours shown, every stepH hours from pastH before the step nearest
      to nowMs to futureH after it: { times: [ms], now: index of that step }. */
  function frameTimes(nowMs, pastH, futureH, stepH) {
    var step = (stepH || STEP_H) * HOUR, mid = Math.round(nowMs / step) * step, times = [];
    for (var t = mid - pastH * HOUR; t <= mid + futureH * HOUR; t += step) times.push(t);
    return { times: times, now: pastH * HOUR / step };
  }

  /** The run a valid hour is read from: the one that started at or before
      it, but never newer than the latest published run; past the 6 days of
      a run of 06 or 18 UTC, the latest of 00 or 12 UTC. */
  function runFor(validMs, latestRefMs) {
    var floor = Math.floor(validMs / (RUN_H * HOUR)) * RUN_H * HOUR;
    var run = Math.min(floor, latestRefMs);
    if (validMs - run > SHORT_RANGE_H * HOUR) run = Math.floor(run / (LONG_RUN_H * HOUR)) * LONG_RUN_H * HOUR;
    return run;
  }

  /** Whether run runMs has a file for validMs: every 3 h for 6 days, then
      every 6 h. */
  function hasFile(validMs, runMs) {
    var lead = validMs - runMs;
    return lead >= 0 && (lead <= SHORT_RANGE_H * HOUR || lead % (2 * STEP_H * HOUR) === 0);
  }

  /* When each model's runs start and how far they go: runFor(validMs,
     latestRefMs) and hasFile(validMs, runMs). The regional models' come
     from WidgetModels, ECMWF's are those above. */
  /** One point in how many each way a regional model is read with. */
  function stepOf(model) {
    var m = typeof WidgetModels !== 'undefined' && WidgetModels.get(model);
    return m ? m.step : 1;
  }

  function scheduleOf(model) {
    if (typeof WidgetModels === 'undefined' || !WidgetModels.get(model)) return { runFor: runFor, hasFile: hasFile };
    return {
      runFor: function (validMs, latestRefMs) { return WidgetModels.runFor(model, validMs, latestRefMs); },
      hasFile: function (validMs, runMs) { return WidgetModels.hasFile(model, validMs, runMs); }
    };
  }

  /** The picture halfway between two packed ones, field by field; NaN
      where either is. */
  function midPacked(a, b) {
    return a.map(function (pa, k) {
      var pb = b[k], out = new Uint8Array(pa.length);
      for (var i = 0; i < pa.length; i++) out[i] = pa[i] === PACK_NAN || pb[i] === PACK_NAN ? PACK_NAN : (pa[i] + pb[i] + 1) >> 1;
      return out;
    });
  }

  function p2(n) { return (n < 10 ? '0' : '') + n; }

  /** Address of the file of run runMs valid at validMs. */
  function frameUrl(validMs, runMs, model, base) {
    var r = new Date(runMs), v = new Date(validMs);
    return base + model + '/' + r.getUTCFullYear() + '/' + p2(r.getUTCMonth() + 1) + '/' + p2(r.getUTCDate()) + '/' +
      p2(r.getUTCHours()) + '00Z/' + v.getUTCFullYear() + '-' + p2(v.getUTCMonth() + 1) + '-' + p2(v.getUTCDate()) +
      'T' + p2(v.getUTCHours()) + '00.om';
  }

  /** Values by halves on one byte from min (127 units up); NaN kept apart. */
  function packFrom(values, min) {
    var out = new Uint8Array(values.length);
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      out[i] = isFinite(v) ? Math.max(0, Math.min(254, Math.round((v - min) * 2))) : PACK_NAN;
    }
    return out;
  }

  // The 256 values a byte can stand for, by min: unpacking a picture is
  // then one lookup a point (a million points: a few ms instead of 20 to 40).
  var unpackTables = {};

  function unpackFrom(packed, min) {
    var table = unpackTables[min];
    if (!table) {
      table = unpackTables[min] = new Float32Array(256);
      for (var b = 0; b < 256; b++) table[b] = b === PACK_NAN ? NaN : min + b / 2;
    }
    var out = new Float32Array(packed.length);
    for (var i = 0; i < packed.length; i++) out[i] = table[packed[i]];
    return out;
  }

  /** Temperatures by half degrees on one byte, -80 to +47 °C (the bands
      are 2 °C at the finest). */
  function pack(values) { return packFrom(values, PACK_MIN); }
  function unpack(packed) { return unpackFrom(packed, PACK_MIN); }

  /** One point in f each way of a rows x cols field; (rows - 1) and
      (cols - 1) are multiples of f, so both ends stay. Unused since the wind
      keeps every point, kept for a lighter layer to come. */
  function decimate(d, rows, cols, f) {
    var r2 = Math.floor((rows - 1) / f) + 1, c2 = Math.floor((cols - 1) / f) + 1, out = new Float32Array(r2 * c2);
    for (var r = 0; r < r2; r++) {
      for (var c = 0; c < c2; c++) out[r * c2 + c] = d[r * f * cols + c * f];
    }
    return out;
  }

  /* What each layer reads from a file and how it keeps it. store: its name
     in the store's keys, changed whenever the way it is kept changes, so
     pictures kept the old way are never read back. read(e, t): the
     fields of file reading e as { meta (lats, lons, res), parts (packed) };
     unpack(parts): the values in full; grid(meta, a, b, mix, tA, tB, at):
     what the layer is given, frame a alone (b null) or a and b with the
     share of b. */
  var FIELDS = {
    temperature: {
      id: 'temperature',
      store: 'temperature',
      vars: ['temperature_2m'],
      read: function (e, t) {
        var g = WidgetOpenData.toScalarGrid(e.data[0], e.ny, e.nx, t);
        return { meta: { lats: g.lats, lons: g.lons, res: g.res }, parts: [pack(g.values)] };
      },
      unpack: function (parts) { return unpack(parts[0]); },
      // The layer mixes the two where it reads them, a few thousand points
      // a picture instead of the whole world.
      grid: function (m, a, b, mix, tA, tB, at) {
        if (!b) return { lats: m.lats, lons: m.lons, res: m.res, times: [tA / 1000], values: a };
        return { lats: m.lats, lons: m.lons, res: m.res, times: [at / 1000], values: a, valuesB: b, mix: mix };
      }
    },
    // The 2 m temperature of the finer model, on its own regional grid;
    // weights (see WidgetTemp.edgeWeights) blend it into the coarse one
    // over feather degrees inside its border (0.5 left a line along it
    // over the sea, where the two models differ by 1 to 2 degrees).
    temperatureFine: {
      id: 'temperature',
      // Kept as the file holds it (south row first), under its own name:
      // the pictures of the first trial were kept flipped.
      store: 'temperature-file',
      vars: ['temperature_2m'],
      feather: 2,
      read: function (e, t, model) {
        var step = stepOf(model), g = WidgetOpenData.toModelGrid(e.data[0], e.ny, e.nx, t, model, step);
        return { meta: { model: model, step: step }, parts: [pack(g.values)] };
      },
      // A picture kept with another step is read again.
      accepts: function (meta, model) { return (meta.step || 1) === stepOf(model); },
      unpack: function (parts) { return unpack(parts[0]); },
      grid: function (m, a, b, mix, tA, tB, at) {
        var desc = WidgetOpenData.gridOf(m.model, m.step);
        if (!b) return { desc: desc, times: [tA / 1000], values: a };
        return { desc: desc, times: [at / 1000], values: a, valuesB: b, mix: mix };
      }
    },
    // The 10 m wind of a regional model, on its own grid like the
    // temperature's: read as each model gives it, kept as u and v toward
    // the east and the north (see WidgetModels.toEarthWind), by half m/s.
    windFine: {
      id: 'wind',
      store: 'wind-file',
      vars: function (model) { return WidgetModels.windVars(model); },
      feather: 2,
      read: function (e, t, model) {
        var step = stepOf(model), full = WidgetOpenData.gridOf(model, 1);
        var w = WidgetModels.toEarthWind(model, e.data[0], e.data[1], full);
        var gu = WidgetOpenData.toModelGrid(w.u, e.ny, e.nx, t, model, step), gv = WidgetOpenData.toModelGrid(w.v, e.ny, e.nx, t, model, step);
        return { meta: { model: model, step: step }, parts: [packFrom(gu.values, WIND_MIN), packFrom(gv.values, WIND_MIN)] };
      },
      accepts: function (meta, model) { return (meta.step || 1) === stepOf(model); },
      unpack: function (parts) { return { u: unpackFrom(parts[0], WIND_MIN), v: unpackFrom(parts[1], WIND_MIN) }; },
      grid: function (m, a, b, mix, tA, tB, at) {
        return {
          desc: WidgetOpenData.gridOf(m.model, m.step), times: [(b ? at : tA) / 1000],
          u: a.u, v: a.v, uB: b ? b.u : null, vB: b ? b.v : null, mix: b ? mix : 0
        };
      }
    },
    // The 10 m wind, every point of the file as the radar reads it; the
    // wind layer mixes two hours by itself (times and at).
    wind: {
      id: 'wind',
      store: 'wind-0.25',
      vars: ['wind_u_component_10m', 'wind_v_component_10m'],
      packPart: function (values) { return packFrom(values, WIND_MIN); },
      unpackPart: function (packed) { return unpackFrom(packed, WIND_MIN); },
      read: function (e, t) {
        var g = WidgetOpenData.toGrid(e.data[0], e.data[1], e.ny, e.nx, t, '10m');
        return { meta: { lats: g.lats, lons: g.lons, res: g.res }, parts: [g.u[0], g.v[0]].map(FIELDS.wind.packPart) };
      },
      unpack: function (parts) { return { u: FIELDS.wind.unpackPart(parts[0]), v: FIELDS.wind.unpackPart(parts[1]) }; },
      grid: function (m, a, b, mix, tA, tB, at) {
        var g = { lats: m.lats, lons: m.lons, res: m.res, elev: null, times: [tA / 1000], u: [a.u], v: [a.v], at: (b ? at : tA) / 1000 };
        if (b) { g.times.push(tB / 1000); g.u.push(b.u); g.v.push(b.v); }
        return g;
      }
    }
  };

  /** Indexes of the frames ordered by distance to frame `now`, the future
      first on a tie: the pictures around now come in first. */
  function loadOrder(count, now) {
    var out = [];
    for (var i = 0; i < count; i++) out.push(i);
    return out.sort(function (a, b) { return Math.abs(a - now) - Math.abs(b - now) || b - a; });
  }

  /** Key of a picture kept in the store: model, layer, run and valid hour,
      so the store can be sorted out from its keys alone. */
  function frameKey(model, field, runMs, validMs) { return [model, field, runMs, validMs].join('|'); }

  function parseKey(key) {
    var p = String(key).split('|');
    if (p.length !== 4 || !(+p[2] >= 0) || !(+p[3] >= 0)) return null;
    return { model: p[0], field: p[1], runMs: +p[2], validMs: +p[3] };
  }

  /** The pictures read, in IndexedDB: get, put, keys, del. Storage can be
      missing or refused (a private profile): every call then gives null and
      the pictures come from the files each time. */
  function frameStore(dbName) {
    var opening = null;
    function open() {
      if (!opening) {
        opening = new Promise(function (resolve, reject) {
          var r = indexedDB.open(dbName || 'awwAnim', 1);
          r.onupgradeneeded = function () { r.result.createObjectStore('frames'); };
          r.onsuccess = function () { resolve(r.result); };
          r.onerror = function () { reject(r.error); };
        });
      }
      return opening;
    }
    function run(mode, op) {
      return Promise.resolve().then(open).then(function (db) {
        return new Promise(function (resolve, reject) {
          var tx = db.transaction('frames', mode), req = op(tx.objectStore('frames'));
          tx.oncomplete = function () { resolve(req && req.result !== undefined ? req.result : null); };
          tx.onerror = function () { reject(tx.error); };
          tx.onabort = function () { reject(tx.error); };
        });
      }).catch(function () { return null; });
    }
    return {
      get: function (key) { return run('readonly', function (s) { return s.get(key); }); },
      put: function (key, value) { return run('readwrite', function (s) { return s.put(value, key); }); },
      keys: function () { return run('readonly', function (s) { return s.getAllKeys(); }).then(function (k) { return k || []; }); },
      del: function (keys) {
        return run('readwrite', function (s) { keys.forEach(function (k) { s.delete(k); }); return null; });
      }
    };
  }

  /** Drop from the store the pictures of model older than maxPastH (the
      longest range back, plus a step), those whose hour is now read from
      another run (the future of a run since replaced) and those of a layer
      kept another way before (see FIELDS.store). */
  function pruneStore(store, model, latestRefMs, nowMs, maxPastH) {
    var runOf = scheduleOf(model).runFor;
    return Promise.resolve().then(function () { return store.keys(); }).then(function (keys) {
      var oldest = nowMs - (maxPastH + STEP_H) * HOUR, known = {};
      for (var id in FIELDS) known[FIELDS[id].store] = true;
      var drop = (keys || []).filter(function (k) {
        var p = parseKey(k);
        return p && p.model === model && (!known[p.field] || p.validMs < oldest || p.runMs !== runOf(p.validMs, latestRefMs));
      });
      if (drop.length) {
        console.log('[anim] store: ' + drop.length + ' pictures dropped');
        return store.del(drop);
      }
    }).catch(function () {});
  }

  /* At most n jobs at once, the others wait their turn: the layers of an
     animation share one, since the file reader runs out of memory past a
     few reads at a time. */
  function Gate(n) {
    this.n = n;
    this.free = n;
    this.waiting = [];          // { weight, go }, in turn
  }

  /** fn() once weight places are free (1 by default; at most n, for a
      large grid whose read needs that much of the reader's memory); its
      promise. */
  Gate.prototype.run = function (fn, weight) {
    var self = this, w = Math.max(1, Math.min(this.n, weight || 1));
    return new Promise(function (resolve) {
      if (!self.waiting.length && self.free >= w) { self.free -= w; resolve(); } else self.waiting.push({ weight: w, go: resolve });
    }).then(fn).then(function (v) { self._done(w); return v; }, function (err) { self._done(w); throw err; });
  };

  /** Weight places back; the next in turn go while they fit. */
  Gate.prototype._done = function (w) {
    this.free += w;
    while (this.waiting.length && this.free >= this.waiting[0].weight) {
      var next = this.waiting.shift();
      this.free -= next.weight;
      next.go();
    }
  };

  /* The pictures of one layer of an animation (opts.field, one of FIELDS;
     the temperature by default). loader is a WidgetOpenData.Loader: its
     base and model give the addresses, its reader reads the files, through
     opts.gate when the reads are shared with other layers. Each picture is
     looked for in opts.store first (see frameStore), and put there once
     read; with opts.pruneH, the store is sorted out on each load (see
     pruneStore). The pictures of opts.reuse (the Frames of another range) are taken over. */
  function Frames(loader, opts) {
    opts = opts || {};
    this.loader = loader;
    this.field = opts.field || FIELDS.temperature;
    this.now = opts.now || function () { return Date.now(); };
    this.pastH = opts.pastH == null ? 24 : opts.pastH;
    this.futureH = opts.futureH == null ? 48 : opts.futureH;
    this.parallel = opts.parallel || 4;
    this.gate = opts.gate || null;
    this.store = opts.store || null;
    // The model the files come from (loader's by default), and the one
    // the store keys name.
    this.fileModel = opts.fileModel || loader.model;
    this.model = opts.model || this.fileModel;
    this.schedule = scheduleOf(this.fileModel);
    // A read takes a place of the gate per million points of the file.
    var rm = typeof WidgetModels !== 'undefined' && WidgetModels.get(this.fileModel);
    this.names = typeof this.field.vars === 'function' ? this.field.vars(this.fileModel) : this.field.vars;
    this.weight = rm ? Math.max(1, Math.round(rm.grid.nx * rm.grid.ny * this.names.length / 1e6)) : 1;
    this.fines = opts.fines || null;   // Frames of finer models, finest first, given along (see gridAt)
    this.surface = opts.surface || null;   // () -> the model's ground heights, once known
    this.pruneH = opts.pruneH || 0;
    this.fromStore = 0;
    this.onFrame = opts.onFrame || function () {};
    var ft = frameTimes(this.now(), this.pastH, this.futureH, STEP_H);
    this.times = ft.times;
    this.nowIndex = ft.now;
    this.packed = this.times.map(function () { return null; });
    this.failed = this.times.map(function () { return false; });
    this.between = this.times.map(function () { return false; });   // no file: halfway between its neighbors
    this.meta = null;            // { lats, lons, res } shared by every picture
    this.stopped = false;
    this.done = false;           // every read is over: a picture missing now stays so
    var old = opts.reuse;
    if (old && old.meta) {
      this.meta = old.meta;
      for (var i = 0; i < this.times.length; i++) {
        var k = old.times.indexOf(this.times[i]);
        if (k >= 0 && old.packed[k]) {
          this.packed[i] = old.packed[k];
          this.between[i] = old.between[k];
        }
      }
    }
  }

  /** Read every picture; resolves once all are in or failed. */
  Frames.prototype.load = function () {
    var self = this, loader = this.loader, sched = this.schedule;
    return loader.fetch(loader.base + this.fileModel + '/latest.json', { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('latest.json ' + r.status);
      return r.json();
    }).then(function (latest) {
      var refMs = new Date(latest.reference_time).getTime();
      if (self.store && self.pruneH) pruneStore(self.store, self.model, refMs, self.now(), self.pruneH);
      self.between = self.times.map(function (t) { return !sched.hasFile(t, sched.runFor(t, refMs)); });
      var queue = loadOrder(self.times.length, self.nowIndex).filter(function (i) { return !self.packed[i] && !self.between[i]; });
      function next() {
        if (self.stopped || !queue.length) return Promise.resolve();
        var i = queue.shift(), t = self.times[i], run = sched.runFor(t, refMs);
        var url = frameUrl(t, run, self.fileModel, loader.base);
        var key = self.store ? frameKey(self.model, self.field.store, run, t) : null;
        var kept = key ? Promise.resolve().then(function () { return self.store.get(key); }).catch(function () { return null; }) : Promise.resolve(null);
        return kept.then(function (k) {
          if (self.stopped) return;
          if (k && k.parts && k.meta && (!self.field.accepts || self.field.accepts(k.meta, self.fileModel))) {
            self.fromStore++;
            self._in(i, k.meta, k.parts);
            return;
          }
          var t0 = Date.now();
          var read = function () { return loader._readVars({ url: url, validMs: t }, self.names); };
          return (self.gate ? self.gate.run(read, self.weight) : read()).then(function (e) {
            if (self.stopped) return;
            var fr = self.field.read(e, t, self.fileModel);
            console.log('[anim] ' + url.split('/').slice(-3).join('/') + ' ' + self.field.id + ' in ' + (Date.now() - t0) + ' ms');
            self._in(i, fr.meta, fr.parts);
            if (key) Promise.resolve().then(function () { return self.store.put(key, { meta: fr.meta, parts: fr.parts }); }).catch(function () {});
          }, function (err) {
            self.failed[i] = true;
            console.warn('[anim] ' + url + ': ' + err);
            self.onFrame(i);
          });
        }).then(next);
      }
      var workers = [];
      for (var k = 0; k < self.parallel; k++) workers.push(next());
      return Promise.all(workers).then(function () { self.done = true; });
    });
  };

  /** Picture i is in, from the file or the store. */
  Frames.prototype._in = function (i, meta, parts) {
    var self = this;
    if (!this.meta) this.meta = meta;
    this.packed[i] = parts;
    this.onFrame(i);
    [i - 1, i + 1].forEach(function (j) { self._fill(j); });
  };

  /** A picture without file, once both its neighbors are in. */
  Frames.prototype._fill = function (i) {
    if (!this.between[i] || this.packed[i]) return;
    var a = this.packed[i - 1], b = this.packed[i + 1];
    if (!a || !b) return;
    this.packed[i] = midPacked(a, b);
    this.onFrame(i);
  };

  Frames.prototype.ready = function (i) { return !!this.packed[i]; };

  var UNPACKED_KEPT = 3;        // frames kept in full: the two being mixed, and the one before

  /** Frame i in full (4 bytes a point and field), unpacked once and kept while it is
      among the last few used. */
  Frames.prototype._values = function (i) {
    var kept = this.unpacked || (this.unpacked = []);
    for (var k = 0; k < kept.length; k++) {
      if (kept[k].i === i) {
        var hit = kept.splice(k, 1)[0];
        kept.push(hit);
        return hit.values;
      }
    }
    var values = this.field.unpack(this.packed[i]);
    kept.push({ i: i, values: values });
    if (kept.length > UNPACKED_KEPT) kept.shift();
    return values;
  };

  // When the page has a moment: the browser's idle time, or the next turn.
  var whenIdle = typeof requestIdleCallback === 'function'
    ? function (cb) { requestIdleCallback(cb, { timeout: 500 }); }
    : function (cb) { setTimeout(cb, 0); };

  /** Unpack frame i while the page is idle, so that reaching it does not
      hold the picture back (40 ms for the wind's two fields). */
  Frames.prototype._warm = function (i) {
    var packed = this.packed[i], kept = this.unpacked || [];
    if (!packed || this._warming === i) return;
    for (var k = 0; k < kept.length; k++) if (kept[k].i === i) return;
    var self = this;
    this._warming = i;
    (this.idle || whenIdle)(function () {
      if (self._warming === i) self._warming = null;
      if (self.packed[i] === packed) self._values(i);
    });
  };

  /** Picture i as a grid of the layer, null until it is in. */
  Frames.prototype.grid = function (i) {
    var p = this.packed[i], m = this.meta;
    if (!p || !m) return null;
    return this._dress(this.field.grid(m, this._values(i), null, 0, this.times[i]), i);
  };

  /** A grid with what goes along: the edge weights of a finer model, the
      finer model's grid at the same position (pos) for the coarse one. */
  Frames.prototype._dress = function (g, pos) {
    if (this.field.feather) g.weights = this.weights();
    var z = this.surface && this.surface();
    if (z && z.length === g.values.length) g.elev = z;
    if (this.fines) {
      g.fines = [];
      for (var k = 0; k < this.fines.length; k++) {
        var f = this.fines[k].fineAt(pos);
        if (f) g.fines.push(f);
      }
    }
    return g;
  };

  /** How far in (points) the blend of a finer model on grid d starts at
      each of its points: up to EDGE_JITTER degrees, by WidgetTemp.edgeNoise. */
  function edgeJitter(d) {
    var j = new Float32Array(d.nx * d.ny), s = EDGE_JITTER / d.res;
    for (var r = 0; r < d.ny; r++) {
      for (var c = 0; c < d.nx; c++) {
        var p = WidgetGrids.lonLatAt(d, c, r);
        j[r * d.nx + c] = s * WidgetTemp.edgeNoise(p.lat, p.lon);
      }
    }
    return j;
  }

  /** The edge weights of this model's grid, worked out once from the first
      picture in (every picture has its values at the same points). */
  Frames.prototype.weights = function () {
    if (this._weights) return this._weights;
    var m = this.meta;
    for (var i = 0; i < this.packed.length && m; i++) {
      if (!this.packed[i] || this.between[i]) continue;
      var vals = this._values(i), d = this.field.grid(m, vals, null, 0, this.times[i]).desc;
      var rows = d ? d.ny : m.lats.length, cols = d ? d.nx : m.lons.length, res = d ? d.res : m.res;
      this._weights = WidgetTemp.edgeWeights(vals.u || vals, rows, cols, this.field.feather / res, d ? edgeJitter(d) : null);
      return this._weights;
    }
    return null;
  };

  /** The layer's grid at position pos (frame i plus a fraction toward
      i + 1): frames i and i + 1 and the share of the second, mixed by the
      layer (see FIELDS). Frame i alone when i + 1 is not read. null until
      frame i is in. */
  Frames.prototype.gridAt = function (pos) {
    var i = Math.floor(pos), f = pos - i, m = this.meta;
    if (!this.packed[i] || !m) return null;
    this._warm(i + 2);
    if (!this.packed[i + 1] || f < 1e-3) return this.grid(i);
    return this._dress(this.field.grid(m, this._values(i), this._values(i + 1), f, this.times[i], this.times[i + 1], this.timeAt(pos)), pos);
  };

  /** Whether picture j will never be in: out of the range, or missing
      once every read is over (past the finer model's hours, a file not
      found). */
  Frames.prototype.gone = function (j) {
    return j < 0 || j >= this.times.length || !this.packed[j] && (this.failed[j] || this.done);
  };

  /** This Frames as the finer model of another: its grid at position pos
      with a fade (1 in full, 0 not at all), so that where it lacks a
      picture for good it fades out over the step before (in over the step
      after, at the start) instead of stopping at once. A picture still
      loading is waited for, the one before held at full weight. */
  Frames.prototype.fineAt = function (pos) {
    var i = Math.floor(pos), f = pos - i, a = this.packed[i], b = this.packed[i + 1], g = null;
    if (a && (b || f < 1e-3)) {
      g = this.gridAt(pos);
      if (g) g.fade = 1;
    } else if (a) {
      g = this.grid(i);
      g.fade = this.gone(i + 1) ? 1 - f : 1;
    } else if (b && this.gone(i)) {
      g = this.grid(i + 1);
      g.fade = f;
    }
    return g;
  };

  /** Whether position pos shows a frame as read from its file, rather than
      one worked out between two. */
  Frames.prototype.isFile = function (pos) {
    var i = Math.floor(pos);
    return pos - i < 1e-3 && !!this.packed[i] && !this.between[i];
  };

  /** The time at position pos, in ms. */
  Frames.prototype.timeAt = function (pos) {
    var i = Math.floor(pos), t = this.times;
    return i + 1 < t.length ? t[i] + (pos - i) * (t[i + 1] - t[i]) : t[i];
  };

  Frames.prototype.stop = function () {
    if (this.fines) this.fines.forEach(function (f) { f.stop(); });
    this.stopped = true;
    this.packed = this.packed.map(function () { return null; });
    this.unpacked = [];
  };

  /** No more reading, the pictures read kept (packed) for a Frames that
      takes them over later (opts.reuse). */
  Frames.prototype.pause = function () {
    if (this.fines) this.fines.forEach(function (f) { f.pause(); });
    this.stopped = true;
    this.unpacked = [];
  };

  /* The pictures of finer models out of view, kept paused (packed) so that
     coming back over them costs nothing, while they fit in budget bytes
     with those in view; past it the least recently kept are let go (their
     pictures stay in the store). */
  function FineKeep(budget) {
    this.budget = budget;
    this.kept = [];             // Frames, oldest first
  }

  function heldBytes(f) {
    return f.packed.reduce(function (n, p) { return n + (p ? p.reduce(function (m, a) { return m + a.byteLength; }, 0) : 0); }, 0);
  }

  function keepKey(f) { return f.keepKey || f.fileModel; }

  FineKeep.prototype.put = function (frames) {
    this.kept = this.kept.filter(function (f) { return keepKey(f) !== keepKey(frames); });
    frames.pause();
    this.kept.push(frames);
    this.trim(0);
  };

  /** The kept Frames under key (keepKey, else its model), taken out of the
      keep; null if none. */
  FineKeep.prototype.take = function (key) {
    for (var i = 0; i < this.kept.length; i++) {
      if (keepKey(this.kept[i]) === key) return this.kept.splice(i, 1)[0];
    }
    return null;
  };

  FineKeep.prototype.bytes = function () {
    return this.kept.reduce(function (n, f) { return n + heldBytes(f); }, 0);
  };

  /** Let the oldest go until the kept and inView bytes fit the budget. */
  FineKeep.prototype.trim = function (inView) {
    while (this.kept.length && this.bytes() + (inView || 0) > this.budget) this.kept.shift().stop();
  };

  FineKeep.prototype.clear = function () {
    this.kept.forEach(function (f) { f.stop(); });
    this.kept = [];
  };

  /* The layers switched on, as one set of frames and one layer for the
     Player: a position is ready once every layer has it, and shows on all
     of them at once. times and now are those of every Frames of the set
     (same range); with no layer, nothing is ever ready. A layer still
     loading (optional) holds no one: it gets the pictures it has, and the
     others play on; while every layer loads, all count. Layers leaving
     (ghosts) get the pictures too while they fade out, and count for
     nothing. */
  function Group(times, nowIndex) {
    this.times = times;
    this.nowIndex = nowIndex;
    this.tracks = [];           // { id, frames, layer, onShow, optional }
    this.ghosts = [];           // { id, frames, layer }
  }

  /** opts.onShow: called once, after the layer's first picture;
      opts.optional: the layer is still loading (see setOptional). */
  Group.prototype.add = function (id, frames, layer, opts) {
    this.remove(id);
    opts = opts || {};
    this.tracks.push({ id: id, frames: frames, layer: layer, onShow: opts.onShow || null, optional: !!opts.optional });
  };

  /** Layer id loaded (false): the others wait for it again where it misses a picture. */
  Group.prototype.setOptional = function (id, on) {
    var t = this.track(id);
    if (t) t.optional = !!on;
  };

  Group.prototype.addGhost = function (id, frames, layer) {
    this.removeGhost(id);
    this.ghosts.push({ id: id, frames: frames, layer: layer });
  };

  Group.prototype.removeGhost = function (id) {
    this.ghosts = this.ghosts.filter(function (t) { return t.id !== id; });
  };

  /** The layers that count: those loaded, or all while none is. */
  Group.prototype._counted = function () {
    var hard = this.tracks.filter(function (t) { return !t.optional; });
    return hard.length ? hard : this.tracks;
  };

  Group.prototype.remove = function (id) {
    this.tracks = this.tracks.filter(function (t) { return t.id !== id; });
  };

  Group.prototype.track = function (id) {
    for (var k = 0; k < this.tracks.length; k++) if (this.tracks[k].id === id) return this.tracks[k];
    return null;
  };

  Group.prototype._every = function (fn) { var c = this._counted(); return c.length > 0 && c.every(fn); };

  Group.prototype.ready = function (i) { return this._every(function (t) { return t.frames.ready(i); }); };
  Group.prototype.isFile = function (pos) { return this._every(function (t) { return t.frames.isFile(pos); }); };
  Group.prototype.timeAt = function (pos) { return Frames.prototype.timeAt.call(this, pos); };

  /** Frames that failed in any layer. */
  Group.prototype.failed = function () {
    var tracks = this._counted();
    return this.times.map(function (_, i) { return tracks.some(function (t) { return !!t.frames.failed[i]; }); });
  };

  /** One grid per layer, in the order of tracks (null for a layer still
      loading that misses it), and the position (pos); null while a layer
      that counts misses it. */
  Group.prototype.gridAt = function (pos) {
    if (!this.tracks.length) return null;
    var counted = this._counted(), grids = [];
    for (var k = 0; k < this.tracks.length; k++) {
      var t = this.tracks[k], g = t.frames.gridAt(pos);
      if (!g && counted.indexOf(t) >= 0) return null;
      grids.push(g);
    }
    grids.pos = pos;
    return grids;
  };

  Group.prototype.showFile = function (grids) {
    this.tracks.forEach(function (t, k) {
      if (!grids[k]) return;
      t.layer.showFile(grids[k]);
      if (t.onShow) { var f = t.onShow; t.onShow = null; f(); }
    });
    this.ghosts.forEach(function (t) {
      var g = grids.pos == null ? null : t.frames.gridAt(grids.pos);
      if (g) t.layer.showFile(g);
    });
  };

  var raf = typeof requestAnimationFrame === 'function' ? function (f) { requestAnimationFrame(f); } : function (f) { setTimeout(f, 16); };
  function nowMs() { return typeof performance !== 'undefined' ? performance.now() : Date.now(); }

  /* A value going from where it is to a target in opts.ms (linear, so two
     layers crossing keep the same sum), set(value) on each frame of the
     page. A new target takes over at once: the end of the old one never
     comes. */
  function Fade(set, opts) {
    opts = opts || {};
    this.set = set;
    this.ms = opts.ms == null ? 400 : opts.ms;
    this.now = opts.now || nowMs;
    this.raf = opts.raf || raf;
    this.value = opts.from == null ? 1 : opts.from;
    this._token = 0;
  }

  Fade.prototype.to = function (target, done) {
    var self = this, token = ++this._token, from = this.value, start = this.now();
    if (this.ms <= 0 || from === target) {
      this.value = target;
      this.set(target);
      if (done) done();
      return;
    }
    function frame() {
      if (token !== self._token) return;
      var p = Math.min(1, (self.now() - start) / self.ms);
      self.value = from + (target - from) * p;
      self.set(self.value);
      if (p < 1) self.raf(frame);
      else if (done) done();
    }
    this.raf(frame);
  };

  /* Layers of the animation switched on and off. A layer switched off
     fades out, then goes; its pictures are kept (at most opts.keep sets,
     the oldest dropped first) for when it comes back, read again from
     nothing. One color for another: the old layer stays until the new one
     shows its first picture (opts.waitMs at most), then the two cross. A
     layer switched on again while it fades out comes back as it is.
     Layers need remove(), and setFade(0..1) to fade. */
  function Switcher(opts) {
    opts = opts || {};
    this.ms = opts.ms == null ? 400 : opts.ms;
    this.waitMs = opts.waitMs == null ? 1500 : opts.waitMs;
    // The colored layers of the animation (temperature, pressure, air
    // quality, a few of its pollutants): up to 1 MB a picture, 25 to 113
    // pictures each.
    this.keep = opts.keep == null ? 6 : opts.keep;
    this.now = opts.now || nowMs;
    this.raf = opts.raf || raf;
    this.defer = opts.defer || function (f) { setTimeout(f, 0); };
    this.onGone = opts.onGone || function () {};
    this._parked = [];          // { id, frames }, oldest first
    this._leaving = {};         // id -> { layer, fade, waiting, since }
    this._pending = {};         // id -> { fade, since }: on, first picture not shown yet
    this._fades = [];           // [layer, Fade]
    this._polling = false;
  }

  Switcher.prototype._fade = function (layer, from) {
    for (var k = 0; k < this._fades.length; k++) if (this._fades[k][0] === layer) return this._fades[k][1];
    var f = new Fade(function (v) { if (layer.setFade) layer.setFade(v); }, { ms: this.ms, now: this.now, raf: this.raf, from: from });
    this._fades.push([layer, f]);
    return f;
  };

  Switcher.prototype._forget = function (layer) {
    this._fades = this._fades.filter(function (e) { return e[0] !== layer; });
  };

  /** Layer id goes off: its pictures kept, the layer faded out then removed. */
  Switcher.prototype.leave = function (id, layer, frames) {
    var self = this;
    if (frames) {
      frames.pause();
      this._parked = this._parked.filter(function (p) { return p.id !== id; });
      this._parked.push({ id: id, frames: frames });
      while (this._parked.length > this.keep) this._parked.shift();
    }
    delete this._pending[id];
    this._leaving[id] = { layer: layer, fade: this._fade(layer, 1), waiting: true, since: this.now() };
    // A color switched on right after (in the same call) is waited for.
    this.defer(function () { self._poll(); });
  };

  /** Layer id goes on: { layer: the one fading out to take back, or null
      for a new one; reuse: its kept pictures, or null }. */
  Switcher.prototype.enter = function (id) {
    var reuse = null, layer = null;
    for (var k = 0; k < this._parked.length; k++) {
      if (this._parked[k].id === id) { reuse = this._parked[k].frames; this._parked.splice(k, 1); break; }
    }
    var l = this._leaving[id];
    if (l) { layer = l.layer; delete this._leaving[id]; }
    return { layer: layer, reuse: reuse };
  };

  /** The layer of id is on the map: invisible until its first picture. */
  Switcher.prototype.entered = function (id, layer) {
    var f = this._fade(layer, 0);
    if (f.value === 0 && layer.setFade) layer.setFade(0);
    this._pending[id] = { fade: f, since: this.now() };
    this._poll();
  };

  /** The first picture of id is drawn: it fades in. */
  Switcher.prototype.shown = function (id) {
    var p = this._pending[id];
    if (!p) return;
    delete this._pending[id];
    p.fade.to(1);
  };

  Switcher.prototype._out = function (id, l) {
    var self = this;
    l.waiting = false;
    l.fade.to(0, function () {
      if (self._leaving[id] !== l) return;
      delete self._leaving[id];
      self._forget(l.layer);
      l.layer.remove();
      self.onGone(id, l.layer);
    });
  };

  /** Layers leaving go once nothing waits for a first picture; a picture
      that never comes is not waited for past waitMs. */
  Switcher.prototype._poll = function () {
    var self = this, t = this.now(), id, busy = false;
    for (id in this._pending) {
      if (t - this._pending[id].since >= this.waitMs) this.shown(id);
      else busy = true;
    }
    var again = false;
    for (id in this._leaving) {
      var l = this._leaving[id];
      if (!l.waiting) continue;
      if (!busy || t - l.since >= this.waitMs) this._out(id, l);
      else again = true;
    }
    if ((again || busy) && !this._polling) {
      this._polling = true;
      this.raf(function () { self._polling = false; self._poll(); });
    }
  };

  /** The pictures kept for id go: its data changed. */
  Switcher.prototype.drop = function (id) {
    this._parked = this._parked.filter(function (p) { return p.id !== id; });
  };

  /** The layers fading out go at once (a new base map); pictures kept. */
  Switcher.prototype.flush = function () {
    for (var id in this._leaving) {
      var l = this._leaving[id];
      l.fade.to(l.fade.value);           // cancels its end
      this._forget(l.layer);
      l.layer.remove();
      this.onGone(id, l.layer);
    }
    this._leaving = {};
  };

  /** Everything off at once (end of the animation): nothing kept. */
  Switcher.prototype.clear = function () {
    this.flush();
    this._pending = {};
    this._parked = [];
    this._fades = [];
  };

  Group.prototype.settled = function () {
    return this._counted().every(function (t) { return !t.layer.settled || t.layer.settled(); });
  };

  Group.prototype.setMoving = function (on) {
    this.tracks.forEach(function (t) { if (t.layer.setMoving) t.layer.setMoving(on); });
  };

  /* Plays the frames on a layer in manual mode (a Group for several), in continuous
     time: going from one frame to the next takes stepMs, and each time the
     map has drawn a picture, the next one is the temperature at the time
     reached, mixed from the two frames around it. The map's drawing speed
     sets how many pictures come between two frames. The last frame stays
     endPauseMs before going back to the first; frames not read yet are
     jumped over. Pictures come minFrameMs apart at the most: each costs
     a whole new set of tiles. index is the position: frame number plus a
     fraction. A seek is kept until the map has drawn the picture before:
     a slider dragged fast asks for many more than the map can draw, and
     only the last one counts. */
  function Player(frames, layer, opts) {
    opts = opts || {};
    this.frames = frames;
    this.layer = layer;
    this.stepMs = opts.stepMs == null ? 800 : opts.stepMs;
    this.endPauseMs = opts.endPauseMs == null ? 1500 : opts.endPauseMs;
    this.minFrameMs = opts.minFrameMs == null ? 125 : opts.minFrameMs;
    this.now = opts.now || function () { return Date.now(); };
    this.index = -1;
    this.target = null;         // position of the last seek, not shown yet
    this.playing = false;
    this.shownAt = 0;
    this.dueAt = 0;             // when the next picture may come
    this.timer = null;
  }

  var DRAWN_MS = 1500;          // a picture taking longer counts as drawn

  /** Whether the map has drawn the picture shown, or given up on it. */
  Player.prototype._drawn = function () {
    return this.index < 0 || this.layer.settled() || this.now() - this.shownAt > DRAWN_MS;
  };

  /** The timer runs while playing or while a seek waits. */
  Player.prototype._ensureTimer = function () {
    var self = this, need = this.playing || this.target !== null;
    if (need && !this.timer) this.timer = setInterval(function () { self._tick(); }, 16);
    else if (!need && this.timer) { clearInterval(this.timer); this.timer = null; }
  };

  /** Go to position pos once the map is free. */
  Player.prototype.seek = function (pos) {
    this.target = pos;
    this._ensureTimer();
    this._tick();
  };

  /** Show position pos; false when its frame is not read yet. */
  Player.prototype.show = function (pos) {
    var g = this.frames.gridAt(pos);
    if (!g) return false;
    var now = this.now();
    this.index = pos;
    this.shownAt = now;
    // Due minFrameMs after the last one was due, not after the timer step
    // that showed it, so the cap holds on average (15 a second gave 12.5);
    // once behind (the map was slow), counted from now again.
    var base = now >= this.dueAt && now - this.dueAt < this.minFrameMs ? this.dueAt : now;
    this.dueAt = base + this.minFrameMs;
    this.layer.showFile(g);
    return true;
  };

  /** The next frame read after `from`, going round; -1 when none. */
  Player.prototype.nextReady = function (from) {
    var n = this.frames.times.length;
    for (var k = 1; k <= n; k++) {
      var i = (Math.floor(from) + k) % n;
      if (this.frames.ready(i)) return i;
    }
    return -1;
  };

  /** Where a step starts from: the seek on its way, else what is shown. */
  Player.prototype._base = function () {
    if (this.target !== null) return this.target;
    return this.index >= 0 ? this.index : this.frames.nowIndex;
  };

  /** Pause and move one 1/perFrame of a frame (perFrame 3: one hour)
      forward (dir 1) or back (-1), on that grid. */
  Player.prototype.step = function (dir, perFrame) {
    var base = this._base() * perFrame, last = this.frames.times.length - 1;
    var k = dir > 0 ? Math.floor(base + 1e-6) + 1 : Math.ceil(base - 1e-6) - 1;
    this.play(false);
    this.seek(Math.max(0, Math.min(last, k / perFrame)));
  };

  /** Pause and move to the next frame read from its file, forward (dir 1)
      or back (-1); nothing when there is none that way. */
  Player.prototype.stepFile = function (dir) {
    var base = this._base(), n = this.frames.times.length;
    var i = dir > 0 ? Math.floor(base + 1e-6) + 1 : Math.ceil(base - 1e-6) - 1;
    for (; i >= 0 && i < n; i += dir) {
      if (!this.frames.isFile(i)) continue;
      this.play(false);
      this.seek(i);
      return;
    }
  };

  Player.prototype.play = function (on) {
    this.playing = !!on;
    if (this.layer.setMoving) this.layer.setMoving(this.playing);
    if (this.playing) this.shownAt = this.now();
    this._ensureTimer();
  };

  Player.prototype._tick = function () {
    if (!this._drawn()) return;
    if (this.target !== null) {
      var to = this.target;
      this.target = null;
      this.show(to);
      this._ensureTimer();
      return;
    }
    if (!this.playing || this.index < 0) return;
    var now = this.now(), i = Math.floor(this.index), j = this.nextReady(this.index);
    if (j < 0) return;
    if (j <= i) {
      // Round the end: the last frame stays a while, then the first.
      if (now - this.shownAt >= this.endPauseMs) this.show(j);
    } else if (j > i + 1 || this.index === i && !this.frames.ready(i)) {
      // A frame missing on the way: straight to the next one read.
      if (now - this.shownAt >= this.stepMs) this.show(j);
    } else if (now >= this.dueAt) {
      this.show(Math.min(j, this.index + (now - this.shownAt) / this.stepMs));
    }
  };

  Player.prototype.stop = function () { this.play(false); };

  return {
    STEP_H: STEP_H, TEMP_QUANTUM: 0.5, frameTimes: frameTimes, runFor: runFor, hasFile: hasFile, scheduleOf: scheduleOf, frameUrl: frameUrl, pack: pack, unpack: unpack,
    decimate: decimate, FIELDS: FIELDS, Gate: Gate, frameKey: frameKey, parseKey: parseKey, frameStore: frameStore, pruneStore: pruneStore, loadOrder: loadOrder, Frames: Frames, FineKeep: FineKeep, heldBytes: heldBytes, Group: Group, Player: Player,
    Fade: Fade, Switcher: Switcher
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetAnim; }
