// ==========================================================================
// Glue script 2g: the temperature over time, from the past day to two days
// ahead, one picture every 3 hours. Each hour comes from the open-data file
// of the latest run that covers it: for the past, the run of that morning or
// evening (Open-Meteo keeps them about a week), for the future, the latest
// run, or the latest of 00 or 12 UTC past the 6 days the others hold. The
// pictures are read a few at a time, nearest to now first, and kept on one
// byte per point, by half degrees (1 MB each instead of 4). WidgetAnim is loadable
// under Node for tests; the page drives it through window.anim*.
// ==========================================================================
var WidgetAnim = (function () {
  'use strict';

  var HOUR = 3600e3;
  var STEP_H = 3;               // the files hold one hour in three
  var RUN_H = 6;                // runs start at 00, 06, 12 and 18 UTC
  var LONG_RUN_H = 12;          // those of 00 and 12 UTC go 15 days ahead
  var SHORT_RANGE_H = 144;      // those of 06 and 18 UTC, 6 days
  var PACK_MIN = -80, PACK_NAN = 255;   // byte b is PACK_MIN + b / 2 °C

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

  /** The picture halfway between two packed ones; NaN where either is. */
  function midPacked(a, b) {
    var out = new Uint8Array(a.length);
    for (var i = 0; i < a.length; i++) out[i] = a[i] === PACK_NAN || b[i] === PACK_NAN ? PACK_NAN : (a[i] + b[i] + 1) >> 1;
    return out;
  }

  function p2(n) { return (n < 10 ? '0' : '') + n; }

  /** Address of the file of run runMs valid at validMs. */
  function frameUrl(validMs, runMs, model, base) {
    var r = new Date(runMs), v = new Date(validMs);
    return base + model + '/' + r.getUTCFullYear() + '/' + p2(r.getUTCMonth() + 1) + '/' + p2(r.getUTCDate()) + '/' +
      p2(r.getUTCHours()) + '00Z/' + v.getUTCFullYear() + '-' + p2(v.getUTCMonth() + 1) + '-' + p2(v.getUTCDate()) +
      'T' + p2(v.getUTCHours()) + '00.om';
  }

  /** Temperatures by half degrees on one byte, -80 to +47 °C (the bands
      are 2 °C at the finest); NaN kept apart. */
  function pack(values) {
    var out = new Uint8Array(values.length);
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      out[i] = isFinite(v) ? Math.max(0, Math.min(254, Math.round((v - PACK_MIN) * 2))) : PACK_NAN;
    }
    return out;
  }

  function unpack(packed) {
    var out = new Float32Array(packed.length);
    for (var i = 0; i < packed.length; i++) out[i] = packed[i] === PACK_NAN ? NaN : PACK_MIN + packed[i] / 2;
    return out;
  }

  /** Indexes of the frames ordered by distance to frame `now`, the future
      first on a tie: the pictures around now come in first. */
  function loadOrder(count, now) {
    var out = [];
    for (var i = 0; i < count; i++) out.push(i);
    return out.sort(function (a, b) { return Math.abs(a - now) - Math.abs(b - now) || b - a; });
  }

  /* The pictures of one animation. loader is a WidgetOpenData.Loader: its
     base and model give the addresses, its reader reads the files. The
     pictures of opts.reuse (the Frames of another range) are taken over. */
  function Frames(loader, opts) {
    opts = opts || {};
    this.loader = loader;
    this.now = opts.now || function () { return Date.now(); };
    this.pastH = opts.pastH == null ? 24 : opts.pastH;
    this.futureH = opts.futureH == null ? 48 : opts.futureH;
    this.parallel = opts.parallel || 4;
    this.onFrame = opts.onFrame || function () {};
    var ft = frameTimes(this.now(), this.pastH, this.futureH, STEP_H);
    this.times = ft.times;
    this.nowIndex = ft.now;
    this.packed = this.times.map(function () { return null; });
    this.failed = this.times.map(function () { return false; });
    this.between = this.times.map(function () { return false; });   // no file: halfway between its neighbors
    this.meta = null;            // { lats, lons, res } shared by every picture
    this.stopped = false;
    var old = opts.reuse;
    if (old && old.meta) {
      this.meta = old.meta;
      for (var i = 0; i < this.times.length; i++) {
        var k = old.times.indexOf(this.times[i]);
        if (k >= 0 && old.packed[k]) this.packed[i] = old.packed[k];
      }
    }
  }

  /** Read every picture; resolves once all are in or failed. */
  Frames.prototype.load = function () {
    var self = this, loader = this.loader;
    return loader.fetch(loader.base + loader.model + '/latest.json', { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('latest.json ' + r.status);
      return r.json();
    }).then(function (latest) {
      var refMs = new Date(latest.reference_time).getTime();
      self.between = self.times.map(function (t) { return !hasFile(t, runFor(t, refMs)); });
      var queue = loadOrder(self.times.length, self.nowIndex).filter(function (i) { return !self.packed[i] && !self.between[i]; });
      function next() {
        if (self.stopped || !queue.length) return Promise.resolve();
        var i = queue.shift(), t = self.times[i];
        var url = frameUrl(t, runFor(t, refMs), loader.model, loader.base);
        var t0 = Date.now();
        return loader._readVars({ url: url, validMs: t }, ['temperature_2m']).then(function (e) {
          if (self.stopped) return;
          var grid = WidgetOpenData.toScalarGrid(e.data[0], e.ny, e.nx, t);
          if (!self.meta) self.meta = { lats: grid.lats, lons: grid.lons, res: grid.res };
          self.packed[i] = pack(grid.values);
          console.log('[anim] ' + url.split('/').slice(-3).join('/') + ' in ' + (Date.now() - t0) + ' ms');
          self.onFrame(i);
          [i - 1, i + 1].forEach(function (j) { self._fill(j); });
        }, function (err) {
          self.failed[i] = true;
          console.warn('[anim] ' + url + ': ' + err);
          self.onFrame(i);
        }).then(next);
      }
      var workers = [];
      for (var k = 0; k < self.parallel; k++) workers.push(next());
      return Promise.all(workers);
    });
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

  /** Frame i in full (4 bytes a point), unpacked once and kept while it is
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
    var values = unpack(this.packed[i]);
    kept.push({ i: i, values: values });
    if (kept.length > UNPACKED_KEPT) kept.shift();
    return values;
  };

  /** Picture i as a grid of the temperature layer, null until it is in. */
  Frames.prototype.grid = function (i) {
    var p = this.packed[i], m = this.meta;
    if (!p || !m) return null;
    return { lats: m.lats, lons: m.lons, res: m.res, times: [this.times[i] / 1000], values: this._values(i) };
  };

  /** The temperature at position pos (frame i plus a fraction toward i + 1):
      frame i, frame i + 1 and the share of the second (mix). The layer mixes
      the two where it reads them, a few thousand points a picture instead
      of the whole world. Frame i alone when i + 1 is not read. null until
      frame i is in. */
  Frames.prototype.gridAt = function (pos) {
    var i = Math.floor(pos), f = pos - i, m = this.meta;
    if (!this.packed[i] || !m) return null;
    if (!this.packed[i + 1] || f < 1e-3) return this.grid(i);
    return {
      lats: m.lats, lons: m.lons, res: m.res, times: [this.timeAt(pos) / 1000],
      values: this._values(i), valuesB: this._values(i + 1), mix: f
    };
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
    this.stopped = true;
    this.packed = this.packed.map(function () { return null; });
    this.unpacked = [];
  };

  /* Plays the frames on a temperature layer in manual mode, in continuous
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
    this.index = pos;
    this.shownAt = this.now();
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
    } else if (now - this.shownAt >= this.minFrameMs) {
      this.show(Math.min(j, this.index + (now - this.shownAt) / this.stepMs));
    }
  };

  Player.prototype.stop = function () { this.play(false); };

  return {
    STEP_H: STEP_H, frameTimes: frameTimes, runFor: runFor, hasFile: hasFile, frameUrl: frameUrl, pack: pack, unpack: unpack,
    loadOrder: loadOrder, Frames: Frames, Player: Player
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetAnim; }
