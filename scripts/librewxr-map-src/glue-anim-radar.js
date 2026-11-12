// ==========================================================================
// Glue script 2h: the radar and satellite images of LibreWXR over the
// animation. The catalog lists them: radar every 10 min from about 2 h back
// to 1 h ahead (the nowcast), satellite every hour over the past 12 h. When
// the time of the animation falls in a source's range, its image of that
// time shows over the other layers; out of it, nothing. Each source has its
// own layers, made through the map adapter as the viewer makes its own
// (preloaded hidden, shown once their tiles are in), but kept visible while
// the viewer's are hidden for the animation. Loadable under Node for tests.
// ==========================================================================
var WidgetAnimRadar = (function () {
  'use strict';
  // The linear fade of the other layers (glue-anim.js): a global in the page, required under Node.
  var Fade = (typeof WidgetAnim !== 'undefined' ? WidgetAnim : require('./glue-anim.js')).Fade;

  var MIN = 60e3;
  var RADAR_GAP = 10 * MIN;     // radar images every 10 min
  var SAT_GAP = 60 * MIN;       // satellite every hour
  // In the radar's range the animation goes this many times slower: each
  // radar image of 10 min gets a third of the time of a step of 3 h (half
  // a second at 1x, as the radar plays them on its own).
  var RADAR_SLOW = 6;

  /** The images of kind ('radar' or 'satellite') in a catalog
      (weather-maps.json): the past radar then its nowcast, or the infrared
      satellite. */
  function framesOf(catalog, kind) {
    if (!catalog) return [];
    if (kind === 'satellite') return (catalog.satellite && catalog.satellite.infrared || []).slice();
    var r = catalog.radar || {};
    return (r.past || []).concat(r.nowcast || []);
  }

  /** { start, end } in ms: from the first image to one gap past the last,
      or to untilMs when later; null without images. */
  function rangeOf(frames, gapMs, untilMs) {
    if (!frames || !frames.length) return null;
    return { start: frames[0].time * 1000, end: Math.max(frames[frames.length - 1].time * 1000 + gapMs, untilMs || 0) };
  }

  /** The index of the latest image at or before ms, -1 out of the range. */
  function frameAt(frames, ms, gapMs, untilMs) {
    var r = rangeOf(frames, gapMs, untilMs);
    if (!r || ms < r.start || ms >= r.end) return -1;
    for (var i = frames.length - 1; i >= 0; i--) if (frames[i].time * 1000 <= ms) return i;
    return -1;
  }

  /** The tile address of an image, as the viewer builds it: o holds size,
      color, smooth, snow, format, arrows, cells and lightning. */
  function tileUrl(base, frame, kind, o) {
    if (kind === 'satellite') return base + frame.path + '/' + o.size + '/{z}/{x}/{y}/0/0_0.' + o.format;
    var url = base + frame.path + '/' + o.size + '/{z}/{x}/{y}/' + o.color + '/' + (o.smooth ? 1 : 0) + '_' + (o.snow ? 1 : 0) + '.' + o.format;
    var q = [];
    if (o.arrows) q.push('arrows=' + o.arrows);
    if (o.cells) q.push('cells=' + o.cells);
    if (o.lightning) q.push('lightning=' + o.lightning);
    return q.length ? url + '?' + q.join('&') : url;
  }

  /** The tiles for the size chosen ('auto', '256' or '512') at device
      pixel ratio dpr: size, the files' pixels, and grid, the size MapLibre
      lays them on. Files of 512 on a 512 grid take a quarter of the
      requests of 256 ones, for the same pixels on screen; on HiDPI (1.5
      and more) 'auto' and '512' keep files of 512 on a 256 grid, sharper. */
  function tileSizes(choice, dpr) {
    var size = choice === 'auto' ? 512 : parseInt(choice, 10) === 512 ? 512 : 256;
    return { size: size, grid: size === 512 && dpr < 1.5 ? 512 : 256 };
  }

  /** How many times slower the animation goes at ms: RADAR_SLOW in the
      radar's range, 1 elsewhere. */
  function slowFactor(ms, range) {
    return range && ms >= range.start && ms < range.end ? RADAR_SLOW : 1;
  }

  /* The step buttons over a forecast animation. sources: { start, end,
     last, gap } in ms of the radar and the satellite switched on, finer
     than the files' step. Where the time is in one (just before it going
     back), the button steps on its images; elsewhere it keeps the files'
     step but stops on the first or the last image of a source on the way. */
  function _inside(src, t, dir) {
    var x = dir > 0 ? t : t - 1;
    return x >= src.start && x < src.end;
  }
  function _finest(t, dir, sources) {
    var best = null;
    (sources || []).forEach(function (src) {
      if (_inside(src, t, dir) && (!best || src.gap < best.gap)) best = src;
    });
    return best;
  }
  /** The step in hours of the button going dir at time t (baseH elsewhere). */
  function stepHours(t, dir, baseH, sources) {
    var src = _finest(t, dir, sources);
    return src && src.gap < baseH * 3600e3 ? src.gap / 3600e3 : baseH;
  }
  /** The time the button going dir from t lands on; baseTarget: the files' step. */
  function stepTime(t, dir, baseTarget, sources) {
    var src = _finest(t, dir, sources), eps = 1e-9, to = baseTarget;
    if (src) {
      var k = (t - src.start) / src.gap;
      k = dir > 0 ? Math.floor(k + eps) + 1 : Math.ceil(k - eps) - 1;
      to = Math.min(src.start + k * src.gap, src.end);
    }
    // A finer source on the way: stop on its first (or last) image.
    (sources || []).forEach(function (s) {
      if (src && s.gap >= src.gap) return;
      if (dir > 0 && s.start > t && s.start < to) to = s.start;
      if (dir < 0 && s.last !== null && s.last < t && s.last > to) to = s.last;
    });
    return to;
  }

  /* The images of one source over the animation. opts: kind, gapMs,
     opacity (0..1), url(frame) -> its tile address, fadeMs: switched on,
     its first image fades in, switched off it fades out before its layers
     go, as the other layers do (0: at once; now and raf for tests). adapter: the map's
     (createFrameLayer, onLayerReady, setFrameOpacity, destroyFrameLayer). */
  function Overlay(adapter, opts) {
    this.adapter = adapter;
    this.kind = opts.kind;
    this.gapMs = opts.gapMs;
    // () -> ms the last image stays on until, when later than one gap past
    // it (the satellite's, an hour late, until the end of the radar).
    this.until = opts.until || null;
    this.opacity = opts.opacity == null ? 0.8 : opts.opacity;
    this.url = opts.url;
    this.tileSize = opts.tileSize || 256;   // the grid of its tiles (tileSizes)
    this.frames = [];
    this.on = false;
    this.layers = {};           // path -> { handle, ready }
    this.wanted = null;         // path of the image of the time asked for
    this.shown = null;          // path of the image on the map
    this.time = null;           // the last time asked for (ms)
    this.stale = null;          // the image shown before new tile options, kept until its new one is in
    this.fadeMs = opts.fadeMs || 0;
    this.level = 1;             // the fade, 0..1, times the opacity
    this._fadeIn = false;       // the next image put fades in (just switched on)
    this._leaving = false;      // fading out, its layers go at the end
    var self = this;
    this._fade = new Fade(function (v) { self._setLevel(v); }, { ms: this.fadeMs, now: opts.now, raf: opts.raf, from: 1 });
  }

  /** The opacity of the image shown, the fade counted. */
  Overlay.prototype._op = function () { return this.opacity * this.level; };

  Overlay.prototype._setLevel = function (v) {
    this.level = v;
    if (this.stale) this.adapter.setFrameOpacity(this.stale, this._op());
    if (this.shown && this.layers[this.shown]) this.adapter.setFrameOpacity(this.layers[this.shown].handle, this._op());
  };

  /** The fade from where it is to target in fadeMs (linear), then done(). */
  Overlay.prototype._fadeTo = function (target, done) { this._fade.to(target, done); };

  /** The fade at v at once, nothing drawn yet. */
  Overlay.prototype._jump = function (v) {
    this._fade.value = v;
    this.level = v;
  };

  /** The time of the last image (ms), null without images. */
  Overlay.prototype.lastTime = function () {
    return this.frames.length ? this.frames[this.frames.length - 1].time * 1000 : null;
  };
  Overlay.prototype._until = function () { return this.until ? this.until() : null; };
  Overlay.prototype.range = function () { return rangeOf(this.frames, this.gapMs, this._until()); };

  /** The time of the image on the map (ms), null when none is. */
  Overlay.prototype.shownTime = function () {
    var path = this.shown || (this.stale ? this.stalePath : null);
    for (var i = 0; i < this.frames.length; i++) if (this.frames[i].path === path) return this.frames[i].time * 1000;
    return null;
  };

  Overlay.prototype._make = function (frame) {
    var path = frame.path;
    if (this.layers[path]) return;
    this.layers[path] = { handle: this.adapter.createFrameLayer(this.url(frame), this.kind, { anim: true, tileSize: this.tileSize }), ready: false, waiting: false };
    this._await(path);
  };

  /** Wait for the tiles of image path (once at a time), then show it if
      it is still the one asked for. */
  Overlay.prototype._await = function (path) {
    var self = this, entry = this.layers[path];
    if (!entry || entry.waiting) return;
    entry.waiting = true;
    this.adapter.onLayerReady(entry.handle, function () {
      if (self.layers[path] !== entry) return;
      entry.waiting = false;
      entry.ready = true;
      if (self.wanted === path) self._put(path);
    });
  };

  /** Whether image path has its tiles for the map as it is now: one
      settled before a zoom has none at the new scale yet. */
  Overlay.prototype._loaded = function (path) {
    var e = this.layers[path];
    if (!e || !e.ready || e.waiting) return false;
    return !this.adapter.frameLoaded || this.adapter.frameLoaded(e.handle);
  };

  /** Whether the image of time ms can show at once (true off or out of
      the range); when not, its tiles are asked for. The play waits on it. */
  Overlay.prototype.loadedAt = function (ms) {
    if (!this.on) return true;
    var i = frameAt(this.frames, ms, this.gapMs, this._until());
    if (i < 0) return true;
    var path = this.frames[i].path;
    if (this._loaded(path)) return true;
    this._make(this.frames[i]);
    this._await(path);
    return false;
  };

  Overlay.prototype._drop = function (path) {
    var e = this.layers[path];
    if (!e) return;
    delete this.layers[path];
    this.adapter.destroyFrameLayer(e.handle);
    if (this.shown === path) this.shown = null;
  };

  Overlay.prototype._dropStale = function () {
    if (this.stale) this.adapter.destroyFrameLayer(this.stale);
    this.stale = null;
  };

  /** Image path on the map, the one before off. */
  Overlay.prototype._put = function (path) {
    var e = path ? this.layers[path] : null;
    if (this.shown && this.shown !== path && this.layers[this.shown]) this.adapter.setFrameOpacity(this.layers[this.shown].handle, 0);
    this.shown = e ? path : null;
    if (e && this._fadeIn) {
      // The first image since switched on: from nothing.
      this._fadeIn = false;
      this._jump(0);
      this._fadeTo(1);
    }
    if (e) {
      this.adapter.setFrameOpacity(e.handle, this._op());
      if (this.adapter.raise) this.adapter.raise(e.handle);
    }
    this._dropStale();
  };

  /** New images (a new catalog): the layers of those still listed stay. */
  Overlay.prototype.setFrames = function (frames) {
    var keep = {}, self = this;
    this.frames = (frames || []).slice();
    this.frames.forEach(function (f) { keep[f.path] = true; });
    Object.keys(this.layers).forEach(function (p) { if (!keep[p]) self._drop(p); });
    if (this.on) this.frames.forEach(function (f) { self._make(f); });
    if (this.time !== null) this.show(this.time);
  };

  /** Other tiles (color, smoothing, arrows, lightning, size...): every
      layer made again, on grid tileSize when given, the image of the time
      shown first. That image stays on the map until its new one is in (no
      blink), the hidden ones go now. */
  Overlay.prototype.setUrl = function (url, tileSize) {
    this.url = url;
    if (tileSize) this.tileSize = tileSize;
    var self = this, kept = this.shown && this.layers[this.shown];
    if (kept) {
      this._dropStale();
      this.stale = kept.handle;
      this.stalePath = this.shown;
      delete this.layers[this.shown];
      this.shown = null;
    }
    Object.keys(this.layers).forEach(function (p) { self._drop(p); });
    if (this.on) {
      var i = this.time === null ? -1 : frameAt(this.frames, this.time, this.gapMs, this._until());
      if (i >= 0) this._make(this.frames[i]);
      this.frames.forEach(function (f) { self._make(f); });
    }
    if (this.time !== null) this.show(this.time);
  };

  /** On: every image preloaded hidden, that of the time shown once in.
      Off: every layer goes. */
  Overlay.prototype.setOn = function (on) {
    on = !!on;
    if (on === this.on) return;
    this.on = on;
    var self = this;
    if (on) {
      if (this._leaving) {
        // Back while fading out: from where it is, its layers kept.
        this._leaving = false;
        this._fadeTo(1);
      } else if (this.fadeMs > 0) {
        this._fadeIn = true;
      }
      this.frames.forEach(function (f) { self._make(f); });
      if (this.time !== null) this.show(this.time);
    } else {
      this.wanted = null;
      this._fadeIn = false;
      var drop = function () {
        self._leaving = false;
        if (self.on) return;
        Object.keys(self.layers).forEach(function (p) { self._drop(p); });
        self._dropStale();
        self._jump(1);
      };
      if (this.fadeMs > 0 && (this.shown || this.stale)) {
        this._leaving = true;
        this._fadeTo(0, drop);
      } else {
        drop();
      }
    }
  };

  Overlay.prototype.setOpacity = function (v) {
    this.opacity = v;
    this._setLevel(this.level);
  };

  /** The image of time ms, once its tiles are in; none out of the range. */
  Overlay.prototype.show = function (ms) {
    this.time = ms;
    if (!this.on) return;
    var i = frameAt(this.frames, ms, this.gapMs, this._until());
    // Out of the range: the image that comes in later just shows, as in a play.
    if (i < 0) { this._fadeIn = false; this.wanted = null; this._put(null); return; }
    var f = this.frames[i];
    this.wanted = f.path;
    if (this.shown === f.path) return;
    this._make(f);
    // Not in for the map as it is (a zoom): the image before stays meanwhile.
    if (this._loaded(f.path)) this._put(f.path);
    else this._await(f.path);
  };

  return {
    RADAR_GAP: RADAR_GAP, SAT_GAP: SAT_GAP, RADAR_SLOW: RADAR_SLOW,
    framesOf: framesOf, rangeOf: rangeOf, frameAt: frameAt, tileUrl: tileUrl, tileSizes: tileSizes, slowFactor: slowFactor,
    stepHours: stepHours, stepTime: stepTime, Overlay: Overlay
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetAnimRadar; }
