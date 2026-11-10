// === AIR QUALITY (glue-airquality.js; after glue-pressure.js) ===
// One pollutant of CAMS global (0.4 degree, runs of 00 and 12 UTC, 5 days
// ahead, hourly files) as a colored field in the animation, layer
// 'airquality'. The values are kept on one byte on a log scale and go to
// the GPU as they are: the shader mixes the two forecast pictures and
// looks the byte up in a 256 color table. Each pollutant has its own
// layer, colors, legend and pictures (kept under 'airquality:<id>' while
// off), so a new pollutant fades in over the old one. A FieldLayer of
// glue-fields.js. window.aqSetPollutant(id), aqSetOpacity.
var WidgetAirQuality = (function () {
  'use strict';
  var F = WidgetFields;
  var HOUR = 3600e3, RUN_H = 12, RANGE_H = 120;
  var opts = { opacity: 0.6, floorAlpha: 0 };

  // The bands of the European air quality index (µg/m³) for the pollutants
  // that have one; the others on scales of their own. log: the byte is
  // log10(v + 1) / log10(max + 1) * 254, else v / step.
  var EAQI = ['#50f0e6', '#50ccaa', '#f0e641', '#ff5050', '#960032', '#7d2181'];
  var POLL = {
    pm2_5: { label: 'PM2.5', unit: 'µg/m³', max: 2000, log: true, edges: [0, 10, 20, 25, 50, 75, 250], colors: EAQI.concat('#3d0a40') },
    pm10: { label: 'PM10', unit: 'µg/m³', max: 5000, log: true, edges: [0, 20, 40, 50, 100, 150, 600], colors: EAQI.concat('#3d0a40') },
    ozone: { label: 'O₃', unit: 'µg/m³', max: 1000, log: true, edges: [0, 50, 100, 130, 240, 380], colors: EAQI },
    nitrogen_dioxide: { label: 'NO₂', unit: 'µg/m³', max: 1000, log: true, edges: [0, 40, 90, 120, 230, 340], colors: EAQI },
    sulphur_dioxide: { label: 'SO₂', unit: 'µg/m³', max: 3000, log: true, edges: [0, 100, 200, 350, 500, 750], colors: EAQI },
    dust: { label: tr('aqDust', 'Dust'), unit: 'µg/m³', max: 10000, log: true, edges: [0, 20, 50, 100, 250, 500, 1000, 3000], colors: ['#f6efe0', '#ead9a8', '#ddb86a', '#c98f3c', '#a8622a', '#7e3d1e', '#55220f', '#2e1007'] },
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
  // --- colors: the table of the 256 bytes, the colors of the bands from
  // edge to edge, faded under the first band (clean air lets the map show) ---
  /** The bands of spec s as color stops, and the scale they are spread on. */
  function stopsOf(s) { return s.stops || (s.stops = s.edges.map(function (e, i) { return [e, s.colors[Math.min(i, s.colors.length - 1)]]; })); }
  function log1(v) { return Math.log10(v + 1); }
  function scaleOf(s) { return s.log ? log1 : null; }
  function colorAt(v, s) { return F.colorAt(stopsOf(s), v, scaleOf(s)); }
  function buildLut(s) {
    var first = s.edges[1];
    return F.byteLut(function (b) { return valueOf(b, s); }, function (v) { return colorAt(v, s); }, function (v) {
      return opts.floorAlpha + (1 - opts.floorAlpha) * F.smoothstep(v / first);
    });
  }

  // --- the field of a pollutant: one variable of the file, its own store
  // key; the Frames made while it is chosen keep it ---
  var fields = {};
  function fieldOf(p) {
    if (fields[p]) return fields[p];
    var s = POLL[p];
    return (fields[p] = F.byteField({ id: 'airquality', cams: true, pollutant: p, store: 'aq-' + p, vars: [p] }, function (e, t) {
      return WidgetOpenData.toScalarGrid(e.data[0], e.ny, e.nx, t);
    }, function (v) { return byteOf(v, s); }));
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

  // --- the GL layer: one per pollutant, two show at once while one fades
  // into the other ---
  /** The legend of pollutant spec s; a tick too close to the one before
      (20 and 25 of PM2.5) is left out. */
  function legend(layer) {
    var s = layer.spec, e = s.edges, ticks = [], lastX = -100;
    var lo = byteOf(0, s), hi = byteOf(e[e.length - 1], s);
    e.slice(1).forEach(function (v) {
      var b = byteOf(v, s), x = (b - lo) / (hi - lo) * 100;
      if (x - lastX < 9) return;
      lastX = x;
      ticks.push([b, localNumber(v, v < 1 ? 1 : 0)]);
    });
    var el = F.lutLegend('airquality', layer.colors(), lo, hi, ticks, s.label + (s.unit ? ' ' + s.unit : ''), true);
    el.querySelector('canvas').style.opacity = String(opts.opacity);
    return el;
  }
  function AqLayer(p) {
    var l = new F.FieldLayer({
      id: 'airquality:' + p, glId: 'lv-aq-gl-' + p, legend: legend,
      lut: function () { return buildLut(POLL[p]); }, opacity: function () { return opts.opacity; }
    });
    l.p = p;
    l.spec = POLL[p];
    return l;
  }

  ANIM_LAYERS.airquality = function (m) { return AqLayer(current).addTo(m); };

  // The page's own switch (the colored layers take turns in glue-humidity.js).
  var plainSetLayer = window.animSetLayer;

  /** Another pollutant: shown, it fades in over the old one as soon as its
      first picture is in (its pictures kept from before, else from the
      store or the files); the old one's pictures are kept. */
  window.aqSetPollutant = function (id) {
    if (!POLL[id] || id === current) return current;
    var on = F.track('airquality');
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
    opts.opacity = F.percent(percent, 60);
    var t = F.track('airquality');
    if (t) t.layer.setOpacity(opts.opacity);
    return opts.opacity;
  };
  window.aqOptions = function (o) {
    for (var k in o) opts[k] = o[k];
    var t = F.track('airquality');
    if (t) t.layer.recolor();
    return opts;
  };

  // --- the Ctrl readout: the value under the pointer, a dot of its color ---
  var DOT = '<svg viewBox="0 0 16 16" width="20" height="20"><circle cx="8" cy="8" r="6" fill="currentColor" stroke="rgba(255,255,255,0.6)" stroke-width="0.8"/></svg>';
  addReadout(function () { return F.track('airquality'); }, function (t, ll) {
    var b = F.sample(t.layer.grid, ll.lat, ll.lng);
    if (!isFinite(b)) return '';
    var s = t.layer.spec, v = valueOf(b, s);
    return readoutRow(DOT, F.css(colorAt(v, s)), s.label + ' ' + localNumber(v, v < 10 ? 1 : 0) + (s.unit ? ' ' + s.unit : ''));
  });

  return { POLL: POLL, valueOf: valueOf, byteOf: byteOf, buildLut: buildLut, stopsOf: stopsOf, scaleOf: scaleOf, opts: opts };
})();
