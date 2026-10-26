// ==========================================================================
// Glue script 2c: the wind of the whole planet from Open-Meteo's open-data
// files (one .om file per model run and hour on S3), read in parts by
// Open-Meteo's WebAssembly reader vendored under vendor/. No API call, so no
// quota: far out, the map shows the model's own 0.25-degree field instead of
// a dozen API points per side. WidgetOpenData holds the file choice, the
// network backend and the grid layout, and is loadable under Node for tests.
// ==========================================================================
var WidgetOpenData = (function () {
  'use strict';

  var BASE = 'https://openmeteo.s3.amazonaws.com/data_spatial/';
  var MERGE_GAP = 65536;   // bytes between two reads that still share one request
  var BATCH_MS = 5;        // reads asked for within this delay are merged

  function p2(n) { return (n < 10 ? '0' : '') + n; }

  /** The file of the latest run (latest.json) whose valid hour is nearest
      to nowMs: { url, validMs }. base defaults to Open-Meteo's bucket. */
  function fileUrl(latest, model, nowMs, base) {
    var ref = new Date(latest.reference_time);
    // valid_times come as "2026-10-23T15:00Z", which not every engine parses
    var valid = latest.valid_times
      .map(function (t) { return new Date(String(t).replace(/T(\d\d):(\d\d)Z$/, 'T$1:$2:00Z')); })
      .reduce(function (a, b) { return Math.abs(b - nowMs) < Math.abs(a - nowMs) ? b : a; });
    var day = function (d) { return d.getUTCFullYear() + '/' + p2(d.getUTCMonth() + 1) + '/' + p2(d.getUTCDate()); };
    var stamp = function (d) {
      return d.getUTCFullYear() + '-' + p2(d.getUTCMonth() + 1) + '-' + p2(d.getUTCDate()) + 'T' + p2(d.getUTCHours()) + '00';
    };
    return {
      url: (base || BASE) + model + '/' + day(ref) + '/' + p2(ref.getUTCHours()) + '00Z/' + stamp(valid) + '.om',
      validMs: valid.getTime()
    };
  }

  /** Names of the u and v components of a wind level in the files. */
  function varNames(level) {
    var l = level === '700hPa' ? '700hPa' : '10m';
    return ['wind_u_component_' + l, 'wind_v_component_' + l];
  }

  /** Byte ranges {offset, size} sorted and merged when at most gap bytes
      apart: [{ start, end, members }], members being the original ranges. */
  function mergeRanges(reqs, gap) {
    var sorted = reqs.slice().sort(function (a, b) { return a.offset - b.offset; });
    var out = [];
    for (var i = 0; i < sorted.length; i++) {
      var r = sorted[i], last = out[out.length - 1];
      if (last && r.offset <= last.end + gap) {
        last.end = Math.max(last.end, r.offset + r.size);
        last.members.push(r);
      } else {
        out.push({ start: r.offset, end: r.offset + r.size, members: [r] });
      }
    }
    return out;
  }

  /* Backend for Open-Meteo's OmFileReader (count / getBytes). Every request
     to S3 costs a transatlantic round trip (0.3 to 0.9 s), so it makes as few
     as it can: a HEAD for the size; one read of the file's last tailBytes,
     where the headers of all variables and their chunk indexes are (the last
     190 KB for ECMWF), so finding the wind among 126 variables costs nothing;
     then the reads asked for within BATCH_MS merged into one request. Plain
     "bytes=a-b" ranges need no CORS preflight; OmHttpBackend adds If-Match
     and If-Unmodified-Since, which cost one for every new file. */
  function TailBackend(url, tailBytes, fetchFn) {
    this.url = url;
    this.tailBytes = tailBytes;
    this.fetch = fetchFn || function (u, init) { return fetch(u, init); };
    this.size = null;
    this.tail = null;
    this.tailStart = 0;
    this.opening = null;
    this.queue = [];
    this.timer = null;
    this.requests = 0;
    this.bytes = 0;
    this.misses = 0;
  }

  TailBackend.prototype.open = function () {
    var self = this;
    if (!this.opening) {
      this.opening = this.fetch(this.url, { method: 'HEAD' }).then(function (r) {
        if (!r.ok) throw new Error('HEAD ' + r.status + ' ' + self.url);
        self.requests++;
        self.size = +r.headers.get('content-length');
        self.tailStart = Math.max(0, self.size - self.tailBytes);
        return self.fetchRange(self.tailStart, self.size - self.tailStart);
      }).then(function (tail) { self.tail = tail; });
    }
    return this.opening;
  };

  TailBackend.prototype.count = function () {
    var self = this;
    return this.open().then(function () { return self.size; });
  };

  TailBackend.prototype.fetchRange = function (offset, size) {
    var self = this;
    return this.fetch(this.url, { headers: { Range: 'bytes=' + offset + '-' + (offset + size - 1) } }).then(function (r) {
      if (r.status !== 206 && !(r.status === 200 && offset === 0)) throw new Error('range ' + r.status + ' ' + self.url);
      return r.arrayBuffer();
    }).then(function (buf) {
      var b = new Uint8Array(buf);
      if (b.length !== size) throw new Error('got ' + b.length + ' bytes, wanted ' + size);
      self.requests++;
      self.bytes += size;
      return b;
    });
  };

  TailBackend.prototype.getBytes = function (offset, size) {
    var self = this;
    offset = Number(offset);
    size = Number(size);
    return this.open().then(function () {
      if (offset >= self.tailStart) return self.tail.subarray(offset - self.tailStart, offset - self.tailStart + size);
      self.misses++;
      return new Promise(function (resolve, reject) {
        self.queue.push({ offset: offset, size: size, resolve: resolve, reject: reject });
        if (!self.timer) self.timer = setTimeout(function () { self.flush(); }, BATCH_MS);
      });
    });
  };

  TailBackend.prototype.flush = function () {
    var self = this, groups = mergeRanges(this.queue, MERGE_GAP);
    this.queue = [];
    this.timer = null;
    groups.forEach(function (g) {
      self.fetchRange(g.start, g.end - g.start).then(function (b) {
        g.members.forEach(function (m) { m.resolve(b.subarray(m.offset - g.start, m.offset - g.start + m.size)); });
      }, function (err) {
        g.members.forEach(function (m) { m.reject(err); });
      });
    });
  };

  /** A grid for WindField.sample() from the u and v fields of a file, which
      run south to north from -180: rows flipped north to south, and one more
      column at +180 so the antimeridian has wind. */
  function toGrid(du, dv, ny, nx, validMs, level) {
    var cols = nx + 1, res = 180 / (ny - 1);
    var U = new Float32Array(ny * cols), V = new Float32Array(ny * cols);
    for (var r = 0; r < ny; r++) {
      var src = (ny - 1 - r) * nx, dst = r * cols;
      U.set(du.subarray(src, src + nx), dst);
      V.set(dv.subarray(src, src + nx), dst);
      U[dst + nx] = du[src];
      V[dst + nx] = dv[src];
    }
    var lats = [], lons = [], c;
    for (r = 0; r < ny; r++) lats.push(90 - r * res);
    for (c = 0; c < cols; c++) lons.push(-180 + c * res);
    var lv = { u: [U], v: [V] }, levels = {};
    levels[level] = lv;
    return { lats: lats, lons: lons, elev: null, times: [validMs / 1000], u: lv.u, v: lv.v, levels: levels, res: res };
  }

  var TAIL_BYTES = 262144;    // the file's end read at once (headers and chunk indexes)
  var KEEP_HOURS = 3;          // a kept wind further from now than this is not shown

  /** Key of a kept wind: one per model and level. */
  function cacheKey(model, level) { return model + ':' + level; }

  /** Whether a kept wind is close enough to now to be shown. */
  function usableKept(entry, nowMs, maxHours) {
    if (!entry || !(entry.validMs >= 0)) return false;
    return Math.abs(nowMs - entry.validMs) <= (maxHours || KEEP_HOURS) * 3600e3;
  }

  /** The browser's IndexedDB as a small key/value store. Storage can be
      missing or refused (a private profile): every call then gives null and
      the wind is read from the file each time. */
  function idbStore(dbName) {
    var opening = null;
    function open() {
      if (!opening) {
        opening = new Promise(function (resolve, reject) {
          var r = indexedDB.open(dbName || 'awwOpenData', 1);
          r.onupgradeneeded = function () { r.result.createObjectStore('wind'); };
          r.onsuccess = function () { resolve(r.result); };
          r.onerror = function () { reject(r.error); };
        });
      }
      return opening;
    }
    function run(mode, op) {
      return Promise.resolve().then(open).then(function (db) {
        return new Promise(function (resolve, reject) {
          var tx = db.transaction('wind', mode), req = op(tx.objectStore('wind'));
          tx.oncomplete = function () { resolve(req.result === undefined ? null : req.result); };
          tx.onerror = function () { reject(tx.error); };
        });
      }).catch(function () { return null; });
    }
    return {
      get: function (key) { return run('readonly', function (s) { return s.get(key); }); },
      put: function (key, value) { return run('readwrite', function (s) { return s.put(value, key); }); }
    };
  }

  /* The open-data wind of one model, per level: the kept wind straight away
     (kept), then the latest file when it is newer (load). latest.json is read
     at most every recheckMs. Every failure gives null, and the map then keeps
     the API grids at every zoom, as before. */
  function Loader(opts) {
    opts = opts || {};
    this.model = opts.model || 'ecmwf_ifs025';
    this.base = opts.base || BASE;
    this.store = opts.store || idbStore();
    this.fetch = opts.fetchFn || function (u, init) { return fetch(u, init); };
    this.importReader = opts.importReader;
    this.recheckMs = opts.recheckMs == null ? 600000 : opts.recheckMs;
    this.now = opts.now || function () { return Date.now(); };
    this.res = 0.25;             // degrees; read from the file once one is in
    this.grids = {};
    this.urls = {};
    this.checkedAt = {};
    this.loading = {};
  }

  Loader.prototype._use = function (level, entry) {
    var grid = toGrid(entry.du, entry.dv, entry.ny, entry.nx, entry.validMs, level);
    this.res = grid.res;
    this.grids[level] = grid;
    this.urls[level] = entry.url;
    return grid;
  };

  /** The kept wind of a level when recent enough, else null. */
  Loader.prototype.kept = function (level) {
    var self = this;
    return Promise.resolve(this.store.get(cacheKey(this.model, level))).then(function (entry) {
      return usableKept(entry, self.now()) ? self._use(level, entry) : null;
    }).catch(function () { return null; });
  };

  /** { grid, changed } with the latest file's wind, changed when it was
      read now; null on failure. */
  Loader.prototype.load = function (level) {
    var self = this, now = this.now();
    if (this.loading[level]) return this.loading[level];
    if (this.grids[level] && now - this.checkedAt[level] < this.recheckMs) {
      return Promise.resolve({ grid: this.grids[level], changed: false });
    }
    var t0 = now;
    this.loading[level] = this.fetch(this.base + this.model + '/latest.json', { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('latest.json ' + r.status);
      return r.json();
    }).then(function (latest) {
      self.checkedAt[level] = now;
      var f = fileUrl(latest, self.model, now, self.base);
      if (f.url === self.urls[level] && self.grids[level]) return { grid: self.grids[level], changed: false };
      return self._read(f, level).then(function (entry) {
        entry.ref = latest.reference_time;
        self.store.put(cacheKey(self.model, level), entry);
        var grid = self._use(level, entry);
        console.log('[wind] open data: ' + f.url.split('/').slice(-3).join('/') + ' ' + level + ' read in ' + (self.now() - t0) + ' ms');
        return { grid: grid, changed: true };
      });
    }).catch(function (err) {
      console.warn('[wind] open data: ' + err);
      return null;
    }).then(function (res) {
      self.loading[level] = null;
      return res;
    });
    return this.loading[level];
  };

  /** The u and v fields of a level in one file: { url, validMs, ny, nx, du, dv }. */
  Loader.prototype._read = function (f, level) {
    var self = this, lib = null, names = varNames(level);
    return this.importReader().then(function (m) {
      lib = m;
      return lib.OmFileReader.create(new TailBackend(f.url, TAIL_BYTES, self.fetch));
    }).then(function (root) {
      var kids = [];
      for (var i = 0; i < root.numberOfChildren(); i++) kids.push(root.getChild(i));
      return Promise.all(kids);
    }).then(function (kids) {
      var find = function (n) { return kids.filter(function (k) { return k && k.getName() === n; })[0]; };
      var u = find(names[0]), v = find(names[1]);
      if (!u || !v) throw new Error('no ' + names[0] + ' in ' + f.url);
      var dims = u.getDimensions(), ny = Number(dims[0]), nx = Number(dims[1]);
      var args = {
        type: lib.OmDataType.FloatArray,
        ranges: [{ start: 0, end: ny }, { start: 0, end: nx }],
        ioSizeMax: BigInt(1048576),
        ioSizeMerge: BigInt(65536)
      };
      return Promise.all([u.read(args), v.read(args)]).then(function (d) {
        return { url: f.url, validMs: f.validMs, ny: ny, nx: nx, du: d[0], dv: d[1] };
      });
    });
  };

  return {
    BASE: BASE, fileUrl: fileUrl, varNames: varNames, mergeRanges: mergeRanges, TailBackend: TailBackend,
    toGrid: toGrid, cacheKey: cacheKey, usableKept: usableKept, idbStore: idbStore, Loader: Loader
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetOpenData; }
