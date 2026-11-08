// === CLOUDS (glue-clouds.js; after glue-precip.js) ===
// The ECMWF cloud cover in the animation, layer 'clouds': high, mid and
// low, any of them together, in white; all three show the model's total
// cover (its own overlap of the levels). All four are read from each file and
// kept in one RGBA picture (one byte of percent each, at 0.5 degree: one
// point out of two, so a picture weighs what a temperature one does), so
// other levels show without reading anything again
// (window.cloudSetLevels). Mostly see-through, it goes over the colored
// layers and under the precipitation. It borrows the GL layer of
// glue-pressure.js. window.cloudSetOpacity, cloudOptions.
var WidgetClouds = (function () {
  'use strict';
  var opts = { opacity: 0.7, minCover: 0.1, color: '#f4f6f8' };

  // ch: the channel of each level in the picture.
  var LEVELS = [
    { id: 'total', label: 'Total', v: 'cloud_cover', ch: 3 },
    { id: 'high', label: 'High', v: 'cloud_cover_high', ch: 2 },
    { id: 'mid', label: 'Mid', v: 'cloud_cover_mid', ch: 1 },
    { id: 'low', label: 'Low', v: 'cloud_cover_low', ch: 0 }
  ];
  LEVELS.forEach(function (l) { l.label = tr('cloud_' + l.id, l.label); });
  var TOTAL = LEVELS[0], PARTS = LEVELS.slice(1);
  var shown = { high: true, mid: true, low: true };
  /** The channels drawn: the total for all three levels, else each shown. */
  function drawn() {
    var on = PARTS.filter(function (l) { return shown[l.id]; });
    return on.length === PARTS.length ? [TOTAL] : on;
  }

  /** One file as RGBA bytes (low, mid, high, total, percent * 2.55), one
      point out of two. */
  function readFile(e, t) {
    var g = null, chans = [];
    // e.data in the order of FIELD.vars, that of LEVELS.
    LEVELS.forEach(function (l, i) {
      var s = WidgetOpenData.toScalarGrid(e.data[i], e.ny, e.nx, t);
      g = g || s;
      chans[l.ch] = s.values;
    });
    var R = g.lats.length, C = g.lons.length, r2 = (R + 1) >> 1, c2 = (C + 1) >> 1;
    var out = new Uint8Array(r2 * c2 * 4);
    for (var r = 0; r < r2; r++) {
      for (var c = 0; c < c2; c++) {
        var src = (r * 2) * C + c * 2, dst = (r * c2 + c) * 4;
        for (var k = 0; k < 4; k++) {
          var v = chans[k][src];
          out[dst + k] = isFinite(v) ? Math.max(0, Math.min(255, Math.round(v * 2.55))) : 0;
        }
      }
    }
    var lats = g.lats.filter(function (x, i) { return i % 2 === 0; });
    var lons = g.lons.filter(function (x, i) { return i % 2 === 0; });
    return { meta: { lats: lats, lons: lons, res: g.res * 2 }, parts: [out] };
  }

  var FIELD = {
    id: 'clouds', store: 'clouds-0.5', vars: LEVELS.map(function (l) { return l.v; }),
    read: readFile,
    unpack: function (parts) { return parts[0]; },
    grid: function (m, a, b, mix, tA, tB, at) {
      if (!b) return { lats: m.lats, lons: m.lons, res: m.res, times: [tA / 1000], values: a };
      return { lats: m.lats, lons: m.lons, res: m.res, times: [at / 1000], values: a, valuesB: b, mix: mix };
    }
  };
  WidgetAnim.FIELDS.clouds = FIELD;

  // Four variables a file: six reads at once run the file reader out of
  // memory (OOM), two do not.
  var Before = WidgetAnim.Frames, CLOUD_PARALLEL = 2;
  WidgetAnim.Frames = function (loader, o) {
    if (o && o.field === FIELD) {
      var c = {};
      for (var k in o) c[k] = o[k];
      c.parallel = Math.min(c.parallel || CLOUD_PARALLEL, CLOUD_PARALLEL);
      o = c;
    }
    return new Before(loader, o);
  };
  WidgetAnim.Frames.prototype = Before.prototype;

  // --- the GL layer: the levels drawn, in white, each over the others ---
  var FS = WidgetPressure.FS_HEAD + [
    'uniform sampler2D u_a, u_b;',
    'uniform float u_mix, u_opacity, u_min;',
    'uniform vec4 u_pick;',               // 1 on the channels drawn
    'uniform vec3 u_col;',
    'void main() {',
    '  float lat; vec2 uv = gridUv(lat);',
    '  vec4 c = mix(texture(u_a, uv), texture(u_b, uv), u_mix);',
    // One over the other: what shows through all of them is left clear.
    '  vec4 clear = 1.0 - smoothstep(u_min, 1.0, c) * u_pick;',
    '  float a = (1.0 - clear.r * clear.g * clear.b * clear.a) * u_opacity;',
    '  if (a <= 0.0) discard;',
    '  fragColor = vec4(u_col * a, a);',
    '}'
  ].join('\n');

  function hex(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }

  function draw(gl, u, layer) {
    var o = layer.owner, sh = o.shown, g = sh.grid;
    if (!g) return false;
    var rows = g.lats.length, cols = g.lons.length, c = hex(opts.color);
    layer.texture(gl, 0, sh.a, cols, rows, 'rgba'); gl.uniform1i(u.u_a, 0);
    layer.texture(gl, 1, sh.b, cols, rows, 'rgba'); gl.uniform1i(u.u_b, 1);
    var pick = [0, 0, 0, 0];
    drawn().forEach(function (l) { pick[l.ch] = 1; });
    gl.uniform4f(u.u_pick, pick[0], pick[1], pick[2], pick[3]);
    gl.uniform3f(u.u_col, c[0] / 255, c[1] / 255, c[2] / 255);
    gl.uniform2f(u.u_size, cols, rows);
    gl.uniform1f(u.u_mix, sh.mix);
    gl.uniform1f(u.u_min, opts.minCover);
    gl.uniform1f(u.u_opacity, opts.opacity * layer.fade);
    layer.drawn = sh.version;
    return true;
  }

  var PRECIP_ID = 'lv-precip-gl';
  function CloudLayer() {
    this.map = null;
    this.grid = null;
    this.shown = { grid: null, a: null, b: null, mix: 0, version: 0 };
    this.gl = new WidgetPressure.GLLayer('lv-clouds-gl', FS, draw);
    this.gl.owner = this;
  }
  /** What the clouds go just under: the precipitation, else the lines. */
  function target(map) { return map.getLayer(PRECIP_ID) ? PRECIP_ID : WidgetPressure.beforeIsobars(map); }
  CloudLayer.prototype = {
    addTo: function (map) {
      var self = this;
      this.map = map;
      map.addLayer(this.gl, target(map));
      _widgetAdapter.setLines('clouds', true);
      // A colored layer switched on later goes under the lines, so over
      // this one: it is put back on top of them (under the precipitation).
      this.onStyle = function () { self.keepOnTop(); };
      map.on('styledata', this.onStyle);
      return this;
    },
    keepOnTop: function () {
      var map = this.map;
      if (!map || !map.getLayer(this.gl.id)) return;
      var order = map.getLayersOrder(), before = target(map);
      if (before && order[order.indexOf(this.gl.id) + 1] !== before) map.moveLayer(this.gl.id, before);
    },
    remove: function () {
      if (!this.map) return;
      this.map.off('styledata', this.onStyle);
      if (this.map.getLayer(this.gl.id)) this.map.removeLayer(this.gl.id);
      _widgetAdapter.setLines('clouds', false);
      this.map = null;
    },
    showFile: function (grid) {
      var sh = this.shown, two = grid.valuesB && grid.mix > 0;
      this.grid = grid;
      sh.grid = grid;
      sh.a = grid.values;
      sh.b = two ? grid.valuesB : grid.values;
      sh.mix = two ? grid.mix : 0;
      sh.version++;
      if (this.map) this.map.triggerRepaint();
    },
    setFade: function (f) {
      this.gl.fade = f;
      if (this.map) this.map.triggerRepaint();
    },
    redraw: function () { if (this.map) this.map.triggerRepaint(); },
    restyle: function () {
      if (this.map && !this.map.getLayer(this.gl.id)) this.map.addLayer(this.gl, target(this.map));
    },
    settled: function () { return this.gl.drawn === this.shown.version; },
    reload: function () {}
  };

  ANIM_LAYERS.clouds = function (m) { return new CloudLayer().addTo(m); };

  function track() { return anim && anim.group.track('clouds'); }
  window.cloudSetOpacity = function (percent) {
    opts.opacity = Math.max(0, Math.min(100, percent === "" || percent === null || !isFinite(+percent) ? 70 : +percent)) / 100;
    var t = track();
    if (t) t.layer.redraw();
    return opts.opacity;
  };
  /** The levels shown: ids ('high', 'mid', 'low'), several at once, or
      'all'; none shows nothing; nothing read again. Gives the ids shown. */
  window.cloudSetLevels = function (ids) {
    ids = [].concat(ids);
    shown = {};
    PARTS.forEach(function (l) { if (ids.indexOf('all') >= 0 || ids.indexOf(l.id) >= 0) shown[l.id] = true; });
    var t = track();
    if (t) t.layer.redraw();
    return PARTS.filter(function (l) { return shown[l.id]; }).map(function (l) { return l.id; });
  };
  window.cloudLevels = function () { return PARTS.map(function (l) { return [l.id, l.label]; }); };
  window.cloudFrames = function () { var t = track(); return t && t.frames; };   // for the test scripts
  window.cloudOptions = function (o) {
    for (var k in o) opts[k] = o[k];
    var t = track();
    if (t) t.layer.redraw();
    return opts;
  };

  // --- the Ctrl readout: the cover of each level drawn ---
  /** Channel ch of an RGBA grid at lat/lon, bilinear, in percent. */
  function sampleCh(g, data, ch, lat, lon) {
    var rows = g.lats.length, cols = g.lons.length;
    var r = (90 - lat) / g.res, c = (((lon + 180) % 360) + 360) % 360 / g.res;
    var i0 = Math.max(0, Math.min(rows - 2, Math.floor(r))), j0 = Math.max(0, Math.min(cols - 2, Math.floor(c)));
    var fr = Math.max(0, Math.min(1, r - i0)), fc = Math.max(0, Math.min(1, c - j0)), k = (i0 * cols + j0) * 4 + ch;
    var top = data[k] * (1 - fc) + data[k + 4] * fc;
    var bottom = data[k + cols * 4] * (1 - fc) + data[k + cols * 4 + 4] * fc;
    return (top * (1 - fr) + bottom * fr) / 2.55;
  }
  var plainReadout = readoutHtml;
  readoutHtml = function () {
    var html = plainReadout(), map = _widgetAdapter.getMap(), t = track();
    if (!t || !t.layer.grid || !map || !readout.known) return html;
    var c = map.getContainer().getBoundingClientRect(), x = readout.x - c.left, y = readout.y - c.top;
    if (x < 0 || y < 0 || x > c.width || y > c.height) return html;
    var ll = map.unproject([x, y]);
    if (!ll || !isFinite(ll.lat) || Math.abs(ll.lat) > 85) return html;
    var back = map.project(ll);
    if (Math.abs(back.x - x) > 1 || Math.abs(back.y - y) > 1) return html;
    var g = t.layer.grid, m = g.valuesB && g.mix > 0 ? g.mix : 0;
    var parts = drawn().map(function (l) {
      var v = sampleCh(g, g.values, l.ch, ll.lat, ll.lng);
      if (m) v += (sampleCh(g, g.valuesB, l.ch, ll.lat, ll.lng) - v) * m;
      return l.label.toLowerCase() + ' ' + Math.round(v) + ' %';
    });
    if (!parts.length) return html;
    var cloud = '<svg viewBox="0 0 16 16" width="20" height="20"><path d="M4.5 12.5 A3 3 0 0 1 4.2 6.6 A3.8 3.8 0 0 1 11.4 5.8 A3.4 3.4 0 0 1 11.8 12.5 Z" fill="currentColor" stroke="rgba(0,0,0,0.35)" stroke-width="0.8"/></svg>';
    return html + '<div class="lv-readout-row"><span class="lv-readout-icon" style="color:' + opts.color + '">' + cloud +
      '</span><span>Clouds: ' + parts.join(', ') + '</span></div>';
  };

  return { LEVELS: LEVELS, readFile: readFile, opts: opts };
})();
