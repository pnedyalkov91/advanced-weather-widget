// === AIR QUALITY (glue-airquality.js; after glue-pressure.js) ===
// One pollutant of CAMS global (0.4 degree, runs of 00 and 12 UTC, 5 days
// ahead, hourly files) as a colored field in the animation, layer
// 'airquality'. The values are kept on one byte on a log scale and go to
// the GPU as they are: the shader mixes the two forecast pictures and
// looks the byte up in a 256 color table. Each pollutant has its own
// layer, colors, legend and pictures (kept under 'airquality:<id>' while
// off), so a new pollutant fades in over the old one. It borrows the GL
// layer of glue-pressure.js. window.aqSetPollutant(id), aqSetOpacity.
var WidgetAirQuality = (function () {
  'use strict';
  var HOUR = 3600e3, RUN_H = 12, RANGE_H = 120;
  var opts = { opacity: 0.6, floorAlpha: 0.35 };

  // The bands of the European air quality index (µg/m³) for the pollutants
  // that have one; the others on scales of their own. log: the byte is
  // log10(v + 1) / log10(max + 1) * 254, else v / step.
  // floorAlpha: how much of the first color shows at 0 (opts.floorAlpha
  // when not given). The particles (dust, PM2.5, PM10) show none of it:
  // clean air leaves the map as it is.
  var EAQI = ['#50f0e6', '#50ccaa', '#f0e641', '#ff5050', '#960032', '#7d2181'];
  var POLL = {
    pm2_5: { label: 'PM2.5', unit: 'µg/m³', max: 2000, log: true, floorAlpha: 0, edges: [0, 10, 20, 25, 50, 75, 250], colors: EAQI.concat('#3d0a40') },
    pm10: { label: 'PM10', unit: 'µg/m³', max: 5000, log: true, floorAlpha: 0, edges: [0, 20, 40, 50, 100, 150, 600], colors: EAQI.concat('#3d0a40') },
    ozone: { label: 'O₃', unit: 'µg/m³', max: 1000, log: true, edges: [0, 50, 100, 130, 240, 380], colors: EAQI },
    nitrogen_dioxide: { label: 'NO₂', unit: 'µg/m³', max: 1000, log: true, edges: [0, 40, 90, 120, 230, 340], colors: EAQI },
    sulphur_dioxide: { label: 'SO₂', unit: 'µg/m³', max: 3000, log: true, edges: [0, 100, 200, 350, 500, 750], colors: EAQI },
    dust: { label: tr('aqDust', 'Dust'), unit: 'µg/m³', max: 10000, log: true, floorAlpha: 0, edges: [0, 20, 50, 100, 250, 500, 1000, 3000], colors: ['#f6efe0', '#ead9a8', '#ddb86a', '#c98f3c', '#a8622a', '#7e3d1e', '#55220f', '#2e1007'] },
    aerosol_optical_depth: { label: 'AOD', unit: '', max: 10, log: true, edges: [0, 0.1, 0.2, 0.4, 0.7, 1, 2], colors: ['#50f0e6', '#50ccaa', '#f0e641', '#ffaa40', '#ff5050', '#960032', '#7d2181'] },
    uv_index: { label: 'UV', unit: '', step: 0.1, log: false, edges: [0, 3, 6, 8, 11, 14], colors: ['#4eb400', '#f7e400', '#f85900', '#d8001d', '#6b49c8', '#3b2075'] }
  };
  var current = 'pm2_5';

  function spec() { return POLL[current]; }

  /** Value of a byte (fractional bytes too, from the readout). */
  function valueOf(b, s) {
    s = s || spec();
    if (!s.log) return b * s.step;
    return Math.pow(10, b / 254 * Math.log10(s.max + 1)) - 1;
  }
  /** Byte of a value (fractional). */
  function byteOf(v, s) {
    s = s || spec();
    if (!s.log) return v / s.step;
    return Math.log10(Math.max(0, v) + 1) / Math.log10(s.max + 1) * 254;
  }
  function pack(values, s) {
    var out = new Uint8Array(values.length);
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      out[i] = isFinite(v) ? Math.max(0, Math.min(254, Math.round(byteOf(v, s)))) : 0;
    }
    return out;
  }

  // --- colors: the table of the 256 bytes, the colors of the bands from
  // edge to edge, faded under the first band (clean air lets the map show) ---
  function hex(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }
  function colorAt(v, s) {
    var e = s.edges, c = s.colors, k = 0;
    while (k < e.length - 2 && v > e[k + 1]) k++;
    var x0 = s.log ? Math.log10(e[k] + 1) : e[k], x1 = s.log ? Math.log10(e[k + 1] + 1) : e[k + 1], x = s.log ? Math.log10(v + 1) : v;
    var f = Math.max(0, Math.min(1, (x - x0) / (x1 - x0)));
    var a = hex(c[k]), b = hex(c[Math.min(k + 1, c.length - 1)]);
    return [0, 1, 2].map(function (i) { return Math.round(a[i] + (b[i] - a[i]) * f); });
  }
  function buildLut(s) {
    var out = new Uint8Array(256 * 4), first = s.edges[1];
    for (var b = 0; b < 256; b++) {
      var v = valueOf(Math.min(b, 254), s), c = colorAt(v, s);
      var t = Math.max(0, Math.min(1, v / first)), floor = s.floorAlpha !== undefined ? s.floorAlpha : opts.floorAlpha, fade = floor + (1 - floor) * t * t * (3 - 2 * t);
      out[b * 4] = c[0]; out[b * 4 + 1] = c[1]; out[b * 4 + 2] = c[2]; out[b * 4 + 3] = Math.round(255 * fade);
    }
    return out;
  }

  // --- the field of a pollutant: one variable of the file, its own store
  // key; the Frames made while it is chosen keep it ---
  var fields = {};
  function fieldOf(p) {
    if (fields[p]) return fields[p];
    var s = POLL[p];
    return (fields[p] = {
      id: 'airquality', cams: true, pollutant: p,
      store: 'aq-' + p, vars: [p],
      read: function (e, t) {
        var g = WidgetOpenData.toScalarGrid(e.data[0], e.ny, e.nx, t);
        return { meta: { lats: g.lats, lons: g.lons, res: g.res }, parts: [pack(g.values, s)] };
      },
      // The bytes themselves: the GPU and the readout read them as they are.
      unpack: function (parts) { return parts[0]; },
      grid: function (m, a, b, mix, tA, tB, at) {
        if (!b) return { lats: m.lats, lons: m.lons, res: m.res, times: [tA / 1000], values: a };
        return { lats: m.lats, lons: m.lons, res: m.res, times: [at / 1000], values: a, valuesB: b, mix: mix };
      }
    });
  }
  WidgetAnim.FIELDS.airquality = fieldOf(current);
  ANIM_KEYS.airquality = function () { return 'airquality:' + current; };

  // --- the pictures: CAMS has its own runs, and its files are elsewhere ---
  var cams = new WidgetOpenData.Loader({
    model: 'cams_global', base: _windOpen.base, importReader: _windOpen.importReader, fetchFn: _windOpen.fetch
  });
  var PlainFrames = WidgetAnim.Frames;

  /** Frames of a CAMS layer: each hour from the run of 00 or 12 UTC at or
      before it (never newer than the latest published, nor than the hours
      latest.json lists for a run still coming in); none past its 5 days.
      The store is not pruned: pruneStore knows the ECMWF runs only. */
  function AqFrames(opts) {
    var o = {};
    for (var k in opts) o[k] = opts[k];
    o.pruneH = 0;
    PlainFrames.call(this, cams, o);
    this.model = 'cams_global';
  }
  AqFrames.prototype = Object.create(PlainFrames.prototype);
  AqFrames.prototype.load = function () {
    var self = this, loader = this.loader;
    return loader.fetch(loader.base + loader.model + '/latest.json', { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('latest.json ' + r.status);
      return r.json();
    }).then(function (latest) {
      var refMs = Date.parse(latest.reference_time), listed = {};
      (latest.valid_times || []).forEach(function (s) { listed[Date.parse(s)] = true; });
      function runOf(t) {
        var run = Math.min(Math.floor(t / (RUN_H * HOUR)) * RUN_H * HOUR, refMs);
        if (run === refMs && !listed[t]) run -= RUN_H * HOUR;
        return run;
      }
      self.between = self.times.map(function () { return false; });
      var queue = WidgetAnim.loadOrder(self.times.length, self.nowIndex).filter(function (i) { return !self.packed[i]; });
      function next() {
        if (self.stopped || !queue.length) return Promise.resolve();
        var i = queue.shift(), t = self.times[i], run = runOf(t);
        if (t - run > RANGE_H * HOUR) { self.failed[i] = true; self.onFrame(i); return next(); }
        var url = WidgetAnim.frameUrl(t, run, loader.model, loader.base);
        var key = self.store ? WidgetAnim.frameKey(self.model, self.field.store, run, t) : null;
        var kept = key ? Promise.resolve().then(function () { return self.store.get(key); }).catch(function () { return null; }) : Promise.resolve(null);
        return kept.then(function (k) {
          if (self.stopped) return;
          if (k && k.parts && k.meta) { self.fromStore++; self._in(i, k.meta, k.parts); return; }
          var t0 = Date.now(), field = self.field;
          var read = function () { return loader._readVars({ url: url, validMs: t }, field.vars); };
          return (self.gate ? self.gate.run(read, self.weight) : read()).then(function (e) {
            if (self.stopped) return;
            var fr = field.read(e, t);
            console.log('[aq] ' + url.split('/').slice(-3).join('/') + ' ' + field.vars[0] + ' in ' + (Date.now() - t0) + ' ms');
            self._in(i, fr.meta, fr.parts);
            if (key) Promise.resolve().then(function () { return self.store.put(key, { meta: fr.meta, parts: fr.parts }); }).catch(function () {});
          }, function (err) {
            self.failed[i] = true;
            console.warn('[aq] ' + url + ': ' + err);
            self.onFrame(i);
          });
        }).then(next);
      }
      var workers = [];
      for (var w = 0; w < self.parallel; w++) workers.push(next());
      return Promise.all(workers);
    });
  };
  WidgetAnim.Frames = function (loader, o) {
    return o && o.field && o.field.cams ? new AqFrames(o) : new PlainFrames(loader, o);
  };
  WidgetAnim.Frames.prototype = PlainFrames.prototype;

  // --- the GL layer ---
  var AQ_FS = WidgetPressure.FS_HEAD + [
    'uniform sampler2D u_a, u_b, u_lut;',
    'uniform float u_mix, u_opacity;',
    'void main() {',
    '  float lat; vec2 uv = gridUv(lat);',
    '  float b = mix(texture(u_a, uv).r, texture(u_b, uv).r, u_mix) * 255.0;',
    '  vec4 c = texture(u_lut, vec2((b + 0.5) / 256.0, 0.5));',
    '  float a = c.a * u_opacity;',
    '  fragColor = vec4(c.rgb * a, a);',
    '}'
  ].join('\n');

  /** Draws the picture its layer was last given, in its colors. */
  function aqDraw(gl, u, layer) {
    var o = layer.owner, sh = o.shown, g = sh.grid;
    if (!g) return false;
    var rows = g.lats.length, cols = g.lons.length;
    o.lut = o.lut || buildLut(o.spec);
    layer.texture(gl, 0, sh.a, cols, rows, 'r8'); gl.uniform1i(u.u_a, 0);
    layer.texture(gl, 1, sh.b, cols, rows, 'r8'); gl.uniform1i(u.u_b, 1);
    layer.texture(gl, 2, o.lut, 256, 1, 'rgba'); gl.uniform1i(u.u_lut, 2);
    gl.uniform2f(u.u_size, cols, rows);
    gl.uniform1f(u.u_mix, sh.mix);
    gl.uniform1f(u.u_opacity, opts.opacity * layer.fade);
    layer.drawn = sh.version;
    return true;
  }

  /** The layer of pollutant p: its GL layer, colors and legend. Two show
      at once while one fades into the other. */
  function AqLayer(p) {
    this.p = p;
    this.spec = POLL[p];
    this.map = null;
    this.grid = null;
    this.lut = null;
    this.legend = null;
    this.shown = { grid: null, a: null, b: null, mix: 0, version: 0 };
    this.gl = new WidgetPressure.GLLayer('lv-aq-gl-' + p, AQ_FS, aqDraw);
    this.gl.owner = this;
  }
  AqLayer.prototype = {
    addTo: function (map) {
      this.map = map;
      map.addLayer(this.gl, WidgetPressure.beforeLines(map));
      _widgetAdapter.setLines('airquality:' + this.p, true);
      this.showLegend();
      return this;
    },
    remove: function () {
      this.hideLegend();
      if (!this.map) return;
      if (this.map.getLayer(this.gl.id)) this.map.removeLayer(this.gl.id);
      _widgetAdapter.setLines('airquality:' + this.p, false);
      this.map = null;
    },
    showFile: function (grid) {
      var sh = this.shown;
      this.grid = grid;
      sh.grid = grid;
      sh.a = grid.values;
      sh.b = grid.valuesB && grid.mix > 0 ? grid.valuesB : grid.values;
      sh.mix = grid.valuesB ? grid.mix || 0 : 0;
      sh.version++;
      if (this.map) this.map.triggerRepaint();
    },
    setFade: function (f) {
      this.gl.fade = f;
      if (this.legend) this.legend.style.opacity = String(f);
      if (this.map) this.map.triggerRepaint();
    },
    redraw: function () { if (this.map) this.map.triggerRepaint(); },
    restyle: function () { WidgetPressure.readdGL(this.map, this.gl, true); },
    settled: function () { return this.gl.drawn === this.shown.version; },
    reload: function () {},
    showLegend: function () { if (this.map) { this.hideLegend(); this.legend = makeLegend(this.map, this.spec, this.lut = this.lut || buildLut(this.spec)); this.legend.style.opacity = String(this.gl.fade); } },
    hideLegend: function () { if (this.legend) this.legend.remove(); this.legend = null; }
  };

  // --- legend, as the pressure's (the colored layers never show together) ---
  var legend = null;
  (function () {
    var css = document.createElement('style');
    css.textContent = [
      '.lv-aq-legend { position: absolute; top: 8px; left: 50%; transform: translateX(-50%); z-index: 5; pointer-events: none;',
      '  display: grid; grid-template-columns: 240px auto; column-gap: 6px; padding: 3px 8px 5px; border-radius: 6px;',
      '  font: 11px var(--font-ui, sans-serif); background: rgba(20, 22, 28, 0.72); color: #eee; }',
      'body[data-theme="light"] .lv-aq-legend { background: rgba(255, 255, 255, 0.82); color: #222; }',
      '.lv-aq-legend .lv-temp-ticks { grid-column: 1; grid-row: 1; position: relative; height: 14px; }',
      '.lv-aq-legend .lv-temp-ticks span { position: absolute; transform: translateX(-50%); white-space: nowrap; }',
      '.lv-aq-legend .lv-temp-bar { grid-column: 1; grid-row: 2; width: 240px; height: 8px; border-radius: 2px; }',
      '.lv-aq-legend .lv-temp-unit { grid-column: 2; grid-row: 2; align-self: center; }',
      '@media (max-width: 320px) { .lv-aq-legend { display: none; } }'
    ].join('\n');
    document.head.appendChild(css);
  })();
  /** The legend of pollutant spec s, in the colors of lut. */
  function makeLegend(map, s, lut) {
    var e = s.edges, lo = byteOf(0, s), hi = byteOf(e[e.length - 1], s), W = 240;
    var legend = document.createElement('div');
    legend.className = 'lv-aq-legend';
    legend.dataset.layer = 'airquality';
    // A tick too close to the one before (20 and 25 of PM2.5) is left out.
    var ticks = [], lastX = -100;
    e.slice(1).forEach(function (v) {
      var x = (byteOf(v, s) - lo) / (hi - lo) * 100;
      if (x - lastX < 9) return;
      lastX = x;
      ticks.push('<span style="left:' + x.toFixed(2) + '%">' + localNumber(v, v < 1 ? 1 : 0) + '</span>');
    });
    legend.innerHTML = '<div class="lv-temp-ticks">' + ticks.join('') + '</div><span class="lv-temp-unit">' + s.label + (s.unit ? ' ' + s.unit : '') + '</span>';
    var bar = document.createElement('canvas'), g = bar.getContext('2d');
    bar.width = W;
    bar.height = 10;
    bar.className = 'lv-temp-bar';
    bar.style.opacity = String(opts.opacity);
    for (var x = 0; x < W; x++) {
      var b = Math.round(lo + (x + 0.5) / W * (hi - lo)) * 4;
      g.fillStyle = 'rgba(' + lut[b] + ',' + lut[b + 1] + ',' + lut[b + 2] + ',' + (lut[b + 3] / 255).toFixed(2) + ')';
      g.fillRect(x, 0, 1, 10);
    }
    legend.appendChild(bar);
    (document.getElementById('lv-map') || map.getContainer()).appendChild(legend);
    return legend;
  }

  ANIM_LAYERS.airquality = function (m) { return new AqLayer(current).addTo(m); };

  // The page's own switch (the colored layers take turns in glue-humidity.js).
  var plainSetLayer = window.animSetLayer;

  /** Another pollutant: shown, it fades in over the old one as soon as its
      first picture is in (its pictures kept from before, else from the
      store or the files); the old one's pictures are kept. */
  window.aqSetPollutant = function (id) {
    if (!POLL[id] || id === current) return current;
    var on = anim && anim.group.track('airquality');
    if (on) plainSetLayer('airquality', false);
    current = id;
    WidgetAnim.FIELDS.airquality = fieldOf(id);
    if (on) plainSetLayer('airquality', true);
    return current;
  };
  window.aqPollutants = function () {
    return Object.keys(POLL).map(function (k) { return [k, POLL[k].label]; });
  };
  window.aqSetOpacity = function (percent) {
    opts.opacity = Math.max(0, Math.min(100, percent === "" || percent === null || !isFinite(+percent) ? 60 : +percent)) / 100;
    var t = anim && anim.group.track('airquality');
    if (t) {
      t.layer.redraw();
      if (t.layer.legend) t.layer.legend.querySelector('canvas').style.opacity = String(opts.opacity);
    }
    return opts.opacity;
  };
  window.aqOptions = function (o) {
    for (var k in o) opts[k] = o[k];
    var t = anim && anim.group.track('airquality');
    if (t) { t.layer.lut = null; t.layer.redraw(); t.layer.showLegend(); }
    return opts;
  };

  // --- the Ctrl readout: the value under the pointer, a dot of its color ---
  function colorCss(v, s) {
    var c = colorAt(v, s);
    return 'rgb(' + c[0] + ', ' + c[1] + ', ' + c[2] + ')';
  }
  var plainReadout = readoutHtml;
  readoutHtml = function () {
    var html = plainReadout(), map = _widgetAdapter.getMap();
    var t = anim && anim.group.track('airquality');
    if (!t || !t.layer.grid || !map || !readout.known) return html;
    var c = map.getContainer().getBoundingClientRect(), x = readout.x - c.left, y = readout.y - c.top;
    if (x < 0 || y < 0 || x > c.width || y > c.height) return html;
    var ll = map.unproject([x, y]);
    if (!ll || !isFinite(ll.lat) || Math.abs(ll.lat) > 85) return html;
    var back = map.project(ll);
    if (Math.abs(back.x - x) > 1 || Math.abs(back.y - y) > 1) return html;
    var b = WidgetPressure.sample(t.layer.grid, ll.lat, ll.lng);
    if (!isFinite(b)) return html;
    var s = t.layer.spec, v = valueOf(b, s);
    var dot = '<svg viewBox="0 0 16 16" width="20" height="20"><circle cx="8" cy="8" r="6" fill="currentColor" stroke="rgba(255,255,255,0.6)" stroke-width="0.8"/></svg>';
    return html + '<div class="lv-readout-row"><span class="lv-readout-icon" style="color:' + colorCss(v, s) + '">' + dot +
      '</span><span>' + s.label + ' ' + localNumber(v, v < 10 ? 1 : 0) + (s.unit ? ' ' + s.unit : '') + '</span></div>';
  };

  return { POLL: POLL, valueOf: valueOf, byteOf: byteOf, buildLut: buildLut, opts: opts };
})();
