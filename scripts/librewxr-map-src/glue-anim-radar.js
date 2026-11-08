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

  /** { start, end } in ms: from the first image to one gap past the last;
      null without images. */
  function rangeOf(frames, gapMs) {
    if (!frames || !frames.length) return null;
    return { start: frames[0].time * 1000, end: frames[frames.length - 1].time * 1000 + gapMs };
  }

  /** The index of the latest image at or before ms, -1 out of the range. */
  function frameAt(frames, ms, gapMs) {
    var r = rangeOf(frames, gapMs);
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

  /** How many times slower the animation goes at ms: RADAR_SLOW in the
      radar's range, 1 elsewhere. */
  function slowFactor(ms, range) {
    return range && ms >= range.start && ms < range.end ? RADAR_SLOW : 1;
  }

  /* The images of one source over the animation. opts: kind, gapMs,
     opacity (0..1), url(frame) -> its tile address. adapter: the map's
     (createFrameLayer, onLayerReady, setFrameOpacity, destroyFrameLayer). */
  function Overlay(adapter, opts) {
    this.adapter = adapter;
    this.kind = opts.kind;
    this.gapMs = opts.gapMs;
    this.opacity = opts.opacity == null ? 0.8 : opts.opacity;
    this.url = opts.url;
    this.frames = [];
    this.on = false;
    this.layers = {};           // path -> { handle, ready }
    this.wanted = null;         // path of the image of the time asked for
    this.shown = null;          // path of the image on the map
    this.time = null;           // the last time asked for (ms)
    this.stale = null;          // the image shown before new tile options, kept until its new one is in
  }

  Overlay.prototype.range = function () { return rangeOf(this.frames, this.gapMs); };

  /** The time of the image on the map (ms), null when none is. */
  Overlay.prototype.shownTime = function () {
    var path = this.shown || (this.stale ? this.stalePath : null);
    for (var i = 0; i < this.frames.length; i++) if (this.frames[i].path === path) return this.frames[i].time * 1000;
    return null;
  };

  Overlay.prototype._make = function (frame) {
    var self = this, path = frame.path;
    if (this.layers[path]) return;
    var entry = this.layers[path] = { handle: this.adapter.createFrameLayer(this.url(frame), this.kind, { anim: true }), ready: false };
    this.adapter.onLayerReady(entry.handle, function () {
      if (self.layers[path] !== entry) return;
      entry.ready = true;
      if (self.wanted === path) self._put(path);
    });
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
    if (e) {
      this.adapter.setFrameOpacity(e.handle, this.opacity);
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

  /** Other tiles (color, smoothing, arrows, lightning...): every layer
      made again, the image of the time shown first. That image stays on
      the map until its new one is in (no blink), the hidden ones go now. */
  Overlay.prototype.setUrl = function (url) {
    this.url = url;
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
      var i = this.time === null ? -1 : frameAt(this.frames, this.time, this.gapMs);
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
      this.frames.forEach(function (f) { self._make(f); });
      if (this.time !== null) this.show(this.time);
    } else {
      this.wanted = null;
      Object.keys(this.layers).forEach(function (p) { self._drop(p); });
      this._dropStale();
    }
  };

  Overlay.prototype.setOpacity = function (v) {
    this.opacity = v;
    if (this.stale) this.adapter.setFrameOpacity(this.stale, v);
    if (this.shown && this.layers[this.shown]) this.adapter.setFrameOpacity(this.layers[this.shown].handle, v);
  };

  /** The image of time ms, once its tiles are in; none out of the range. */
  Overlay.prototype.show = function (ms) {
    this.time = ms;
    if (!this.on) return;
    var i = frameAt(this.frames, ms, this.gapMs);
    if (i < 0) { this.wanted = null; this._put(null); return; }
    var f = this.frames[i];
    this.wanted = f.path;
    if (this.shown === f.path) return;
    this._make(f);
    if (this.layers[f.path].ready) this._put(f.path);
  };

  return {
    RADAR_GAP: RADAR_GAP, SAT_GAP: SAT_GAP, RADAR_SLOW: RADAR_SLOW,
    framesOf: framesOf, rangeOf: rangeOf, frameAt: frameAt, tileUrl: tileUrl, slowFactor: slowFactor, Overlay: Overlay
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetAnimRadar; }
