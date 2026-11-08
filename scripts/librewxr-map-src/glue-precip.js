// === PRECIPITATION (glue-precip.js; after glue-airquality.js) ===
// The ECMWF precipitation as a rate in mm/h, each kind in its own colors
// (rain, snow, wet snow, rain and snow, freezing rain, freezing drizzle,
// ice pellets), layer 'precipitation'. A file holds what fell in the step
// before its hour (3 h, 6 past the 6 days): the picture of hour T is what
// fell from T - 1.5 h to T + 1.5 h, worked out from the files that cover
// that window, so the rain is where it was at T. Two bytes a point: the
// rate on a log scale and the kind (the one that brought the most water).
// The shader mixes two pictures, the kind taken from the wetter one, and
// looks the colors up in a table of a row per kind; the kinds not chosen
// are left out (window.precipSetKinds). Mostly see-through, it goes over
// the other colors. It borrows the GL layer of glue-pressure.js.
// window.precipSetOpacity, precipOptions.
var WidgetPrecip = (function () {
  'use strict';
  var HOUR = 3600e3, RUN_H = 6, LONG_RUN_H = 12, SHORT_RANGE_H = 144, HALF = 1.5 * HOUR;
  var MODEL_KEY = 'ecmwf_ifs025~precip';   // its own model in the store: pruneStore would drop its runs
  var FILE_STORE = 'precip-file2';         // what is kept: the files, the pictures are worked out from them
  var MAX = 100;                           // mm/h at byte 254
  var opts = { opacity: 0.8, minRate: 0.05, fullRate: 0.3 };

  // --- the kinds: index in the picture, ECMWF's precipitation_type codes,
  // colors from light to heavy (by mm/h of water) ---
  var RAIN = [[0.1, '#a6d8f7'], [0.5, '#4aa3e8'], [1, '#1f6fd6'], [2, '#18a85a'], [4, '#e8dc3a'], [8, '#f5961f'], [16, '#e0302c'], [32, '#b01f86'], [64, '#5e1f7a']];
  var KINDS = [
    null,
    { id: 'rain', label: 'Rain', stops: RAIN },
    { id: 'snow', label: 'Snow', stops: [[0.1, '#f2f2fb'], [0.5, '#d6d0f4'], [1, '#b6a8ec'], [2, '#9580e0'], [4, '#7458cf'], [8, '#5636ad'], [16, '#3b1f80']] },
    { id: 'wet_snow', label: 'Wet snow', stops: [[0.1, '#e8ecff'], [0.5, '#bcc6f4'], [1, '#8f9ee6'], [2, '#6a78d8'], [4, '#4b55bd'], [8, '#333a96']] },
    { id: 'mix', label: 'Rain and snow', stops: [[0.1, '#d4f4ee'], [0.5, '#9fe2d6'], [1, '#6fd0c0'], [2, '#3fb3a4'], [4, '#1f9a8a'], [8, '#0d5c55']] },
    { id: 'freezing_rain', label: 'Freezing rain', stops: [[0.1, '#ffd6e4'], [0.5, '#ff9cbf'], [1, '#ff6fa0'], [2, '#f04682'], [4, '#e0206a'], [8, '#8a0038']] },
    { id: 'freezing_drizzle', label: 'Freezing drizzle', stops: [[0.1, '#f7dcf2'], [0.3, '#eeb4e4'], [0.6, '#e08ad0'], [1, '#c862b8'], [2, '#b040a0'], [4, '#6a1060']] },
    { id: 'ice_pellets', label: 'Ice pellets', stops: [[0.1, '#ffe8c4'], [0.5, '#ffc77e'], [1, '#ffb050'], [2, '#f7921f'], [4, '#f07a10'], [8, '#b04a00']] }
  ];
  // The names in the widget's language (strings of the page's address).
  KINDS.forEach(function (kd) { if (kd) kd.label = tr('precip_' + kd.id, kd.label); });
  var N_ROWS = 8;
  // precipitation_type: 1 rain, 3 freezing rain, 5 snow, 6 wet snow, 7 rain
  // and snow, 8 ice pellets, 12 freezing drizzle.
  var PTYPE = { 1: 1, 3: 5, 5: 2, 6: 3, 7: 4, 8: 7, 12: 6 };
  var shown = null;             // the kinds shown, { id: true }; null: all
  function isShown(kd) { return !!kd && (!shown || !!shown[kd.id]); }

  // A file holds what fell in the step before its hour: the file of the
  // run's own hour has no precipitation at all, so each hour is read from
  // a run before it. Past the 6 days, steps of 6 h.
  function runOf(t, refMs) {
    var run = Math.min(Math.floor((t - 1) / (RUN_H * HOUR)) * RUN_H * HOUR, refMs);
    if (t - run > SHORT_RANGE_H * HOUR) run = Math.floor(run / (LONG_RUN_H * HOUR)) * LONG_RUN_H * HOUR;
    return run;
  }
  function stepH(lead) { return lead > SHORT_RANGE_H * HOUR ? 6 : 3; }
  function hasFile(t, run) {
    var lead = t - run;
    return lead > 0 && (lead <= SHORT_RANGE_H * HOUR || lead % (6 * HOUR) === 0);
  }
  /** The files whose step overlaps T - 1.5 h .. T + 1.5 h, each with its
      share of those 3 hours: { t, run, w }. Two halves in steps of 3 h; in
      steps of 6 h, one whole file between two hours of files, two halves
      on them. */
  function filesFor(T, refMs) {
    var out = [], lo = T - HALF, hi = T + HALF;
    for (var E = T - 3 * HOUR; E <= T + 6 * HOUR; E += 3 * HOUR) {
      var run = runOf(E, refMs);
      if (!hasFile(E, run)) continue;
      var w = Math.min(hi, E) - Math.max(lo, E - stepH(E - run) * HOUR);
      if (w > 0) out.push({ t: E, run: run, w: w / (2 * HALF) });
    }
    return out;
  }
  /** The run of a file, from its address (…/2026/11/04/0600Z/…). */
  function runOfUrl(url) {
    var m = /\/(\d{4})\/(\d\d)\/(\d\d)\/(\d\d)00Z\//.exec(url);
    return m ? Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4]) : NaN;
  }

  function rateOf(b) { return Math.pow(10, b / 254 * Math.log10(MAX + 1)) - 1; }
  function byteOf(v) { return Math.log10(Math.max(0, v) + 1) / Math.log10(MAX + 1) * 254; }
  var RATES = new Float32Array(256);
  for (var b = 0; b < 256; b++) RATES[b] = rateOf(Math.min(b, 254));

  /** One file as { rate (byte of mm/h), kind }. Where the rain fell but the
      type (of the file's hour) says none, it has stopped: snow if most of
      the water was snow, else rain. */
  function readFile(e, t) {
    var lead = t - runOfUrl(e.url), h = isFinite(lead) ? stepH(lead) : 3;
    var g = WidgetOpenData.toScalarGrid(e.data[0], e.ny, e.nx, t);
    var gt = WidgetOpenData.toScalarGrid(e.data[1], e.ny, e.nx, t).values;
    var gs = WidgetOpenData.toScalarGrid(e.data[2], e.ny, e.nx, t).values;
    var n = g.values.length, rate = new Uint8Array(n), kind = new Uint8Array(n);
    for (var i = 0; i < n; i++) {
      var p = g.values[i];
      if (!(p > 0)) continue;
      rate[i] = Math.min(254, Math.round(byteOf(p / h)));
      kind[i] = PTYPE[gt[i]] || (gs[i] > p / 2 ? 2 : 1);
    }
    return { meta: { lats: g.lats, lons: g.lons, res: g.res }, parts: [rate, kind] };
  }

  /** The picture of the files given with their shares: the rates added up,
      at each point the kind of the file that brought the most. */
  function combine(list) {
    var total = list.reduce(function (s, f) { return s + f.w; }, 0);
    var n = list[0].parts[0].length, rate = new Uint8Array(n), kind = new Uint8Array(n);
    var rs = list.map(function (f) { return f.parts[0]; }), ks = list.map(function (f) { return f.parts[1]; });
    var ws = list.map(function (f) { return f.w / total; }), m = list.length;
    for (var i = 0; i < n; i++) {
      var sum = 0, best = 0, bk = 0;
      for (var k = 0; k < m; k++) {
        var r = rs[k][i];
        if (!r) continue;
        var v = RATES[r] * ws[k];
        sum += v;
        if (v > best) { best = v; bk = ks[k][i]; }
      }
      if (sum > 0) { rate[i] = Math.min(254, Math.round(byteOf(sum))); kind[i] = bk; }
    }
    return [rate, kind];
  }

  var FIELD = {
    id: 'precipitation', precip: true, store: FILE_STORE,
    vars: ['precipitation', 'precipitation_type', 'snowfall_water_equivalent'],
    unpack: function (parts) { return { rate: parts[0], kind: parts[1] }; },
    grid: function (m, a, b, mix, tA, tB, at) {
      if (!b) return { lats: m.lats, lons: m.lons, res: m.res, times: [tA / 1000], values: a.rate, kind: a.kind };
      return { lats: m.lats, lons: m.lons, res: m.res, times: [at / 1000], values: a.rate, kind: a.kind, valuesB: b.rate, kindB: b.kind, mix: mix };
    }
  };
  WidgetAnim.FIELDS.precipitation = FIELD;

  // --- the pictures: the files read (from the store first), each picture
  // made once the files of its window are in; a file is let go once the
  // pictures that need it are made ---
  var Base = WidgetAnim.Frames.prototype.constructor, Before = WidgetAnim.Frames;

  function PrecipFrames(loader, o) {
    var c = {};
    for (var k in o) c[k] = o[k];
    c.pruneH = 0;
    Base.call(this, loader, c);
    this.model = MODEL_KEY;
    this.keepH = o.pruneH || 192;
  }
  PrecipFrames.prototype = Object.create(Base.prototype);
  PrecipFrames.prototype.load = function () {
    var self = this, loader = this.loader;
    return loader.fetch(loader.base + loader.model + '/latest.json', { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('latest.json ' + r.status);
      return r.json();
    }).then(function (latest) {
      var refMs = Date.parse(latest.reference_time);
      if (self.store) prune(self.store, self.now() - (self.keepH + 6) * HOUR);
      self.between = self.times.map(function () { return false; });
      var need = self.times.map(function (t) { return filesFor(t, refMs); });
      var files = {}, queue = [], users = {};
      WidgetAnim.loadOrder(self.times.length, self.nowIndex).forEach(function (i) {
        if (self.packed[i]) return;
        need[i].forEach(function (f) {
          var k = f.run + '|' + f.t;
          if (!users[k]) { users[k] = 0; queue.push(f); }
          users[k]++;
        });
      });
      // The pictures whose files are all in (or failed).
      function make() {
        for (var i = 0; i < self.times.length; i++) {
          if (self.packed[i] || self.failed[i]) continue;
          var list = need[i], done = list.every(function (f) { return files[f.run + '|' + f.t] !== undefined; });
          if (!done) continue;
          var ok = list.filter(function (f) { return files[f.run + '|' + f.t]; }).map(function (f) {
            return { w: f.w, parts: files[f.run + '|' + f.t].parts };
          });
          if (ok.length) self._in(i, self.meta || files[list[0].run + '|' + list[0].t].meta, combine(ok));
          else { self.failed[i] = true; self.onFrame(i); }
          list.forEach(function (f) {
            var k = f.run + '|' + f.t;
            if (--users[k] === 0) files[k] = null;
          });
        }
      }
      function got(f, meta, parts) {
        if (!self.meta) self.meta = meta;
        files[f.run + '|' + f.t] = { meta: meta, parts: parts };
        make();
      }
      function next() {
        if (self.stopped || !queue.length) return Promise.resolve();
        var f = queue.shift(), t = f.t, run = f.run;
        var url = WidgetAnim.frameUrl(t, run, loader.model, loader.base);
        var key = self.store ? WidgetAnim.frameKey(self.model, FILE_STORE, run, t) : null;
        var kept = key ? Promise.resolve().then(function () { return self.store.get(key); }).catch(function () { return null; }) : Promise.resolve(null);
        return kept.then(function (k) {
          if (self.stopped) return;
          if (k && k.parts && k.meta) { self.fromStore++; got(f, k.meta, k.parts); return; }
          var t0 = Date.now();
          var read = function () { return loader._readVars({ url: url, validMs: t }, FIELD.vars); };
          return (self.gate ? self.gate.run(read, self.weight) : read()).then(function (e) {
            if (self.stopped) return;
            var fr = readFile(e, t);
            console.log('[precip] ' + url.split('/').slice(-3).join('/') + ' in ' + (Date.now() - t0) + ' ms');
            got(f, fr.meta, fr.parts);
            if (key) Promise.resolve().then(function () { return self.store.put(key, { meta: fr.meta, parts: fr.parts }); }).catch(function () {});
          }, function (err) {
            console.warn('[precip] ' + url + ': ' + err);
            files[run + '|' + t] = null;
            make();
          });
        }).then(next);
      }
      var workers = [];
      for (var w = 0; w < self.parallel; w++) workers.push(next());
      return Promise.all(workers);
    });
  };
  /** Drop the files of this layer older than oldestMs, and those kept
      another way before. */
  function prune(store, oldestMs) {
    Promise.resolve().then(function () { return store.keys(); }).then(function (keys) {
      var drop = (keys || []).filter(function (k) {
        var p = WidgetAnim.parseKey(k);
        return p && p.model === MODEL_KEY && (p.field !== FILE_STORE || p.validMs < oldestMs);
      });
      if (drop.length) return store.del(drop);
    }).catch(function () {});
  }
  WidgetAnim.Frames = function (loader, o) {
    return o && o.field && o.field.precip ? new PrecipFrames(loader, o) : new Before(loader, o);
  };
  WidgetAnim.Frames.prototype = Base.prototype;

  // --- colors: a row of 256 per kind (row 0, none, see-through); nothing
  // under minRate, faded in up to fullRate ---
  function hex(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }
  function colorAt(v, stops) {
    if (v <= stops[0][0]) return hex(stops[0][1]);
    for (var k = 0; k < stops.length - 1; k++) {
      if (v <= stops[k + 1][0]) {
        var f = (Math.log(v) - Math.log(stops[k][0])) / (Math.log(stops[k + 1][0]) - Math.log(stops[k][0]));
        var a = hex(stops[k][1]), b = hex(stops[k + 1][1]);
        return [0, 1, 2].map(function (i) { return Math.round(a[i] + (b[i] - a[i]) * f); });
      }
    }
    return hex(stops[stops.length - 1][1]);
  }
  function alphaAt(v) {
    var t = Math.max(0, Math.min(1, (v - opts.minRate) / (opts.fullRate - opts.minRate)));
    return t * t * (3 - 2 * t);
  }
  var lut = null;
  function buildLut() {
    var out = new Uint8Array(256 * N_ROWS * 4);
    KINDS.forEach(function (kd, row) {
      if (!kd) return;
      for (var b = 0; b < 256; b++) {
        var v = RATES[b], c = colorAt(v, kd.stops), o = (row * 256 + b) * 4;
        out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2]; out[o + 3] = Math.round(255 * alphaAt(v));
      }
    });
    return out;
  }
  /** 1 for the kinds shown, by row. */
  function showMask() {
    return new Float32Array(KINDS.map(function (kd) { return isShown(kd) ? 1 : 0; }));
  }

  // --- the GL layer ---
  var FS = WidgetPressure.FS_HEAD + [
    'uniform sampler2D u_ra, u_ka, u_rb, u_kb, u_lut;',
    'uniform float u_mix, u_opacity;',
    'uniform float u_show[' + N_ROWS + '];',
    // The kind of one grid point: that of the wetter picture, 0 if dry.
    'int kindAt(ivec2 p) {',
    '  float ra = texelFetch(u_ra, p, 0).r, rb = texelFetch(u_rb, p, 0).r;',
    '  if (ra + rb <= 0.0) return 0;',
    '  return int(round((ra * (1.0 - u_mix) >= rb * u_mix ? texelFetch(u_ka, p, 0).r : texelFetch(u_kb, p, 0).r) * 255.0));',
    '}',
    // The rate read smooth (the textures mix the points around); the
    // colors of the kinds of the four wet points around, each by its
    // share: kinds meet in smooth edges, a kind not shown fades out.
    'void main() {',
    '  float lat; vec2 uv = gridUv(lat);',
    '  float r = mix(texture(u_ra, uv).r, texture(u_rb, uv).r, u_mix) * 255.0;',
    '  vec2 pos = uv * u_size - 0.5, f = fract(pos);',
    '  ivec2 last = ivec2(u_size) - 1, p0 = clamp(ivec2(floor(pos)), ivec2(0), last), p1 = min(p0 + 1, last);',
    '  ivec2 ps[4] = ivec2[4](p0, ivec2(p1.x, p0.y), ivec2(p0.x, p1.y), p1);',
    '  float ws[4] = float[4]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);',
    '  vec4 c = vec4(0.0); float wet = 0.0;',
    '  for (int i = 0; i < 4; i++) {',
    '    int k = kindAt(ps[i]);',
    '    if (k <= 0 || k >= ' + N_ROWS + ') continue;',
    '    wet += ws[i];',
    '    if (u_show[k] < 0.5) continue;',
    '    vec4 lc = texture(u_lut, vec2((r + 0.5) / 256.0, (float(k) + 0.5) / ' + N_ROWS + '.0));',
    '    c += ws[i] * vec4(lc.rgb * lc.a, lc.a);',
    '  }',
    '  if (wet <= 0.0) discard;',
    '  fragColor = c / wet * u_opacity;',
    '}'
  ].join('\n');

  function nearest(gl) {
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  }
  function draw(gl, u, layer) {
    var o = layer.owner, sh = o.shown, g = sh.grid;
    if (!g) return false;
    var rows = g.lats.length, cols = g.lons.length;
    lut = lut || buildLut();
    layer.texture(gl, 0, sh.ra, cols, rows, 'r8'); gl.uniform1i(u.u_ra, 0);
    layer.texture(gl, 1, sh.ka, cols, rows, 'r8'); nearest(gl); gl.uniform1i(u.u_ka, 1);
    layer.texture(gl, 2, sh.rb, cols, rows, 'r8'); gl.uniform1i(u.u_rb, 2);
    layer.texture(gl, 3, sh.kb, cols, rows, 'r8'); nearest(gl); gl.uniform1i(u.u_kb, 3);
    layer.texture(gl, 4, lut, 256, N_ROWS, 'rgba-nearest'); gl.uniform1i(u.u_lut, 4);
    gl.uniform1fv(u.u_show, showMask());
    gl.uniform2f(u.u_size, cols, rows);
    gl.uniform1f(u.u_mix, sh.mix);
    gl.uniform1f(u.u_opacity, opts.opacity * layer.fade);
    layer.drawn = sh.version;
    return true;
  }

  function PrecipLayer() {
    this.map = null;
    this.grid = null;
    this.legend = null;
    this.shown = { grid: null, ra: null, ka: null, rb: null, kb: null, mix: 0, version: 0 };
    this.gl = new WidgetPressure.GLLayer('lv-precip-gl', FS, draw);
    this.gl.owner = this;
  }
  PrecipLayer.prototype = {
    addTo: function (map) {
      var self = this;
      this.map = map;
      map.addLayer(this.gl, WidgetPressure.beforeLines(map));
      _widgetAdapter.setLines('precipitation', true);
      this.showLegend();
      // A colored layer switched on later goes under the lines too, so over
      // this one: it is put back on top of them.
      this.onStyle = function () { self.keepOnTop(); };
      map.on('styledata', this.onStyle);
      return this;
    },
    keepOnTop: function () {
      var map = this.map;
      if (!map || !map.getLayer(this.gl.id)) return;
      var order = map.getLayersOrder(), before = WidgetPressure.beforeLines(map);
      if (before && order[order.indexOf(this.gl.id) + 1] !== before) map.moveLayer(this.gl.id, before);
    },
    remove: function () {
      this.hideLegend();
      if (!this.map) return;
      this.map.off('styledata', this.onStyle);
      if (this.map.getLayer(this.gl.id)) this.map.removeLayer(this.gl.id);
      _widgetAdapter.setLines('precipitation', false);
      this.map = null;
    },
    showFile: function (grid) {
      var sh = this.shown, two = grid.valuesB && grid.mix > 0;
      this.grid = grid;
      sh.grid = grid;
      sh.ra = grid.values; sh.ka = grid.kind;
      sh.rb = two ? grid.valuesB : grid.values; sh.kb = two ? grid.kindB : grid.kind;
      sh.mix = two ? grid.mix : 0;
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
    showLegend: function () { if (this.map) { this.hideLegend(); this.legend = makeLegend(this.map); this.legend.style.opacity = String(this.gl.fade); } },
    hideLegend: function () { if (this.legend) this.legend.remove(); this.legend = null; }
  };

  // --- legend: bottom left (the temperature's is top center, and both can
  // show; the map's buttons are top left), a bar for each kind shown ---
  (function () {
    var css = document.createElement('style');
    css.textContent = [
      '.lv-precip-legend { position: absolute; bottom: 8px; left: 8px; z-index: 5; pointer-events: none;',
      '  display: grid; grid-template-columns: auto 180px auto; column-gap: 6px; row-gap: 1px; padding: 3px 8px 5px; border-radius: 6px;',
      '  font: 11px var(--font-ui, sans-serif); background: rgba(20, 22, 28, 0.72); color: #eee; }',
      'body[data-theme="light"] .lv-precip-legend { background: rgba(255, 255, 255, 0.82); color: #222; }',
      '.lv-precip-legend .lv-temp-ticks { grid-column: 2; grid-row: 1; position: relative; height: 14px; }',
      '.lv-precip-legend .lv-temp-ticks span { position: absolute; transform: translateX(-50%); white-space: nowrap; }',
      '.lv-precip-legend canvas { grid-column: 2; width: 180px; height: 6px; border-radius: 2px; align-self: center; }',
      '.lv-precip-legend .lv-precip-name { grid-column: 1; text-align: right; line-height: 12px; }',
      '.lv-precip-legend .lv-temp-unit { grid-column: 3; grid-row: 1; align-self: end; }',
      '@media (max-width: 480px) { .lv-precip-legend { display: none; } }'
    ].join('\n');
    document.head.appendChild(css);
  })();
  var TICKS = [0.1, 1, 2, 5, 10, 20, 50];
  function makeLegend(map) {
    var W = 180, lo = byteOf(0.1), hi = byteOf(64), table = lut = lut || buildLut();
    var legend = document.createElement('div');
    legend.className = 'lv-precip-legend';
    var ticks = TICKS.map(function (v) {
      return '<span style="left:' + ((byteOf(v) - lo) / (hi - lo) * 100).toFixed(2) + '%">' + localNumber(v, v < 1 ? 1 : 0) + '</span>';
    });
    legend.innerHTML = '<div class="lv-temp-ticks">' + ticks.join('') + '</div><span class="lv-temp-unit">mm/h</span>';
    var line = 2;
    KINDS.forEach(function (kd, row) {
      if (!isShown(kd)) return;
      var label = document.createElement('span');
      label.className = 'lv-precip-name';
      label.style.gridRow = String(line);
      label.textContent = kd.label;
      var bar = document.createElement('canvas'), g = bar.getContext('2d');
      bar.width = W;
      bar.height = 6;
      bar.style.gridRow = String(line++);
      bar.style.opacity = String(opts.opacity);
      for (var x = 0; x < W; x++) {
        var o = (row * 256 + Math.round(lo + (x + 0.5) / W * (hi - lo))) * 4;
        // The faint end drawn opaque: the legend shows the colors, the map the fade.
        g.fillStyle = 'rgb(' + table[o] + ',' + table[o + 1] + ',' + table[o + 2] + ')';
        g.fillRect(x, 0, 1, 6);
      }
      legend.appendChild(label);
      legend.appendChild(bar);
    });
    (document.getElementById('lv-map') || map.getContainer()).appendChild(legend);
    return legend;
  }

  ANIM_LAYERS.precipitation = function (m) { return new PrecipLayer().addTo(m); };

  function track() { return anim && anim.group.track('precipitation'); }
  window.precipSetOpacity = function (percent) {
    opts.opacity = Math.max(0, Math.min(100, percent === "" || percent === null || !isFinite(+percent) ? 80 : +percent)) / 100;
    var t = track();
    if (t) {
      t.layer.redraw();
      if (t.layer.legend) t.layer.legend.querySelectorAll('canvas').forEach(function (c) { c.style.opacity = String(opts.opacity); });
    }
    return opts.opacity;
  };
  /** The kinds shown: ids, several at once, or 'all' (nothing read
      again); none shows nothing. Gives the ids shown. */
  window.precipSetKinds = function (ids) {
    ids = [].concat(ids);
    if (ids.indexOf('all') >= 0) shown = null;
    else {
      shown = {};
      KINDS.forEach(function (kd) { if (kd && ids.indexOf(kd.id) >= 0) shown[kd.id] = true; });
    }
    var t = track();
    if (t) { t.layer.redraw(); t.layer.showLegend(); }
    return KINDS.filter(isShown).map(function (kd) { return kd.id; });
  };
  window.precipFrames = function () { var t = track(); return t && t.frames; };   // for the test scripts
  window.precipKinds = function () {
    return KINDS.filter(Boolean).map(function (kd) { return [kd.id, kd.label]; });
  };
  window.precipOptions = function (o) {
    for (var k in o) opts[k] = o[k];
    lut = null;
    var t = track();
    if (t) { t.layer.gl.textures.clear(); t.layer.redraw(); t.layer.showLegend(); }
    return opts;
  };

  // --- the Ctrl readout: kind and rate ---
  /** The byte at the grid point nearest lat/lon (the kind is not mixed). */
  function nearestByte(g, values, lat, lon) {
    var r = Math.round((90 - lat) / g.res), c = Math.round((lon + 180) / g.res), cols = g.lons.length;
    c = ((c % (cols - 1)) + (cols - 1)) % (cols - 1);
    return values[Math.max(0, Math.min(g.lats.length - 1, r)) * cols + c];
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
    var ra = WidgetTemp.sampleScalar(g, g.values, ll.lat, ll.lng);
    var rb = m ? WidgetTemp.sampleScalar(g, g.valuesB, ll.lat, ll.lng) : ra;
    if (!isFinite(ra) || !isFinite(rb)) return html;
    var k = ra * (1 - m) >= rb * m ? nearestByte(g, g.kind, ll.lat, ll.lng) : nearestByte(g, g.kindB, ll.lat, ll.lng);
    var v = rateOf(ra + (rb - ra) * m), kd = KINDS[k];
    var dry = !kd || v < opts.minRate || !isShown(kd);
    var col = colorAt(Math.max(v, 0.1), kd ? kd.stops : RAIN);
    var drop = '<svg viewBox="0 0 16 16" width="20" height="20"><path d="M8 2 C8 2 3.5 7.6 3.5 10.2 A4.5 4.5 0 0 0 12.5 10.2 C12.5 7.6 8 2 8 2 Z" fill="currentColor" stroke="rgba(255,255,255,0.6)" stroke-width="0.8"/></svg>';
    return html + '<div class="lv-readout-row"><span class="lv-readout-icon" style="color:rgb(' + col.join(',') + ')">' + drop +
      '</span><span>' + (dry ? tr('precipDry', 'Dry') : kd.label + ' ' + localNumber(v, v < 10 ? 1 : 0) + ' mm/h') + '</span></div>';
  };

  return { runOf: runOf, hasFile: hasFile, filesFor: filesFor, combine: combine, rateOf: rateOf, byteOf: byteOf, KINDS: KINDS, opts: opts };
})();
