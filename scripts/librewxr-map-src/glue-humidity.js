// === HUMIDITY AND DEW POINT (glue-humidity.js; after glue-clouds.js) ===
// Two colored layers of the animation from the ECMWF files: 'humidity'
// (relative_humidity_2m, one byte a percent) and 'dewpoint' (not in the
// files: worked out from temperature_2m and relative_humidity_2m with the
// Magnus formula, as the API does, on one byte a half degree from -80 °C).
// Full 0.25 degree, one byte a point: a picture weighs 1 MB. The bytes go to
// the GPU as they are and are looked up in a 256 color table. They take
// turns with the other colored layers (temperature, pressure, air quality).
// It borrows the GL layer of glue-pressure.js.
// window.humiditySetOpacity, dewpointSetOpacity (each its own), humidityOptions.
var WidgetHumidity = (function () {
  'use strict';
  var opts = {};
  // Each its own opacity, as the other colored layers.
  var opacity = { humidity: 0.6, dewpoint: 0.6 };

  function cToUnit(c) { return tempUnit === 'F' ? c * 9 / 5 + 32 : c; }

  // Magnus, the constants of Alduchov and Eskridge (1996).
  var MA = 17.625, MB = 243.04;
  function dewPoint(t, rh) {
    var g = Math.log(Math.max(1, rh) / 100) + MA * t / (MB + t);
    return MB * g / (MA - g);
  }

  var SPECS = {
    humidity: {
      label: tr('humidity', 'Humidity'), vars: ['relative_humidity_2m'], store: 'humidity',
      toByte: function (rh) { return rh; },
      value: function (b) { return b; },
      text: function (v) { return localNumber(v, 0) + ' %'; },
      unit: function () { return '%'; },
      ticks: [0, 20, 40, 60, 80, 100], lo: 0, hi: 100,
      stops: [[0, '#7a3e12'], [20, '#c47f2c'], [40, '#e8cf8a'], [60, '#b8e0c8'], [75, '#5cb8b2'],
        [85, '#2f8fc8'], [95, '#2b4fa8'], [100, '#3a2a8a']],
      // e.data in the order of vars.
      grid: function (e, t) { return WidgetOpenData.toScalarGrid(e.data[0], e.ny, e.nx, t); }
    },
    dewpoint: {
      label: tr('dewpoint', 'Dew point'), vars: ['temperature_2m', 'relative_humidity_2m'], store: 'dewpoint',
      toByte: function (c) { return (c + 80) * 2; },
      value: function (b) { return b / 2 - 80; },
      text: function (v) { return localNumber(cToUnit(v), 1) + ' °' + tempUnit; },
      unit: function () { return '°' + tempUnit; },
      ticks: [-30, -20, -10, 0, 10, 15, 20, 25], lo: -40, hi: 30,
      stops: [[-40, '#e8e0f0'], [-20, '#9b8fc8'], [-10, '#5a78c0'], [0, '#4aa8d8'], [5, '#6cc4a0'],
        [10, '#a8d860'], [13, '#e8e050'], [16, '#f0b040'], [18, '#e87830'], [21, '#d04040'],
        [24, '#a01850'], [27, '#600a40']],
      grid: function (e, t) {
        var tg = WidgetOpenData.toScalarGrid(e.data[0], e.ny, e.nx, t);
        var rh = WidgetOpenData.toScalarGrid(e.data[1], e.ny, e.nx, t).values;
        var v = new Float32Array(tg.values.length);
        for (var i = 0; i < v.length; i++) v[i] = dewPoint(tg.values[i], rh[i]);
        return { lats: tg.lats, lons: tg.lons, res: tg.res, values: v };
      }
    }
  };

  function pack(values, s) {
    var out = new Uint8Array(values.length);
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      out[i] = isFinite(v) ? Math.max(0, Math.min(254, Math.round(s.toByte(v)))) : 0;
    }
    return out;
  }

  function hex(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }
  function colorAt(v, s) {
    var st = s.stops, k = 0;
    if (v <= st[0][0]) return hex(st[0][1]);
    while (k < st.length - 2 && v > st[k + 1][0]) k++;
    var f = Math.max(0, Math.min(1, (v - st[k][0]) / (st[k + 1][0] - st[k][0])));
    var a = hex(st[k][1]), b = hex(st[k + 1][1]);
    return [0, 1, 2].map(function (i) { return Math.round(a[i] + (b[i] - a[i]) * f); });
  }
  function buildLut(s) {
    var out = new Uint8Array(256 * 4);
    for (var b = 0; b < 256; b++) {
      var c = colorAt(s.value(Math.min(b, 254)), s);
      out[b * 4] = c[0]; out[b * 4 + 1] = c[1]; out[b * 4 + 2] = c[2]; out[b * 4 + 3] = 255;
    }
    return out;
  }

  Object.keys(SPECS).forEach(function (id) {
    var s = SPECS[id];
    WidgetAnim.FIELDS[id] = {
      id: id, store: s.store, vars: s.vars,
      read: function (e, t) {
        var g = s.grid(e, t);
        return { meta: { lats: g.lats, lons: g.lons, res: g.res }, parts: [pack(g.values, s)] };
      },
      unpack: function (parts) { return parts[0]; },
      grid: function (m, a, b, mix, tA, tB, at) {
        if (!b) return { lats: m.lats, lons: m.lons, res: m.res, times: [tA / 1000], values: a };
        return { lats: m.lats, lons: m.lons, res: m.res, times: [at / 1000], values: a, valuesB: b, mix: mix };
      }
    };
  });

  // --- the GL layer, that of the air quality ---
  var FS = WidgetPressure.FS_HEAD + [
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

  function draw(gl, u, layer) {
    var o = layer.owner, sh = o.shown, g = sh.grid;
    if (!g) return false;
    var rows = g.lats.length, cols = g.lons.length;
    o.lut = o.lut || buildLut(o.spec);
    layer.texture(gl, 0, sh.a, cols, rows, 'r8'); gl.uniform1i(u.u_a, 0);
    layer.texture(gl, 1, sh.b, cols, rows, 'r8'); gl.uniform1i(u.u_b, 1);
    layer.texture(gl, 2, o.lut, 256, 1, 'rgba'); gl.uniform1i(u.u_lut, 2);
    gl.uniform2f(u.u_size, cols, rows);
    gl.uniform1f(u.u_mix, sh.mix);
    gl.uniform1f(u.u_opacity, opacity[o.id] * layer.fade);
    layer.drawn = sh.version;
    return true;
  }

  function MoistLayer(id) {
    this.id = id;
    this.spec = SPECS[id];
    this.map = null;
    this.grid = null;
    this.lut = null;
    this.legend = null;
    this.shown = { grid: null, a: null, b: null, mix: 0, version: 0 };
    this.gl = new WidgetPressure.GLLayer('lv-' + id + '-gl', FS, draw);
    this.gl.owner = this;
  }
  MoistLayer.prototype = {
    addTo: function (map) {
      this.map = map;
      map.addLayer(this.gl, WidgetPressure.beforeLines(map));
      _widgetAdapter.setLines(this.id, true);
      this.showLegend();
      return this;
    },
    remove: function () {
      this.hideLegend();
      if (!this.map) return;
      if (this.map.getLayer(this.gl.id)) this.map.removeLayer(this.gl.id);
      _widgetAdapter.setLines(this.id, false);
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
    showLegend: function () {
      if (!this.map) return;
      this.hideLegend();
      this.legend = makeLegend(this.map, this.spec, this.lut = this.lut || buildLut(this.spec));
      this.legend.style.opacity = String(this.gl.fade);
    },
    hideLegend: function () { if (this.legend) this.legend.remove(); this.legend = null; }
  };

  /** The legend of spec s, in the styles of the air quality one. */
  function makeLegend(map, s, lut) {
    var W = 240, lo = s.toByte(s.lo), hi = s.toByte(s.hi);
    var legend = document.createElement('div');
    legend.className = 'lv-aq-legend';
    legend.dataset.layer = s === SPECS.dewpoint ? 'dewpoint' : 'humidity';
    var ticks = s.ticks.map(function (v) {
      var x = (s.toByte(v) - lo) / (hi - lo) * 100;
      return '<span style="left:' + x.toFixed(2) + '%">' + localNumber(s === SPECS.dewpoint ? cToUnit(v) : v, 0) + '</span>';
    });
    legend.innerHTML = '<div class="lv-temp-ticks">' + ticks.join('') + '</div><span class="lv-temp-unit">' + s.label + ' ' + s.unit() + '</span>';
    var bar = document.createElement('canvas'), g = bar.getContext('2d');
    bar.width = W;
    bar.height = 10;
    bar.className = 'lv-temp-bar';
    bar.style.opacity = String(opacity[s === SPECS.dewpoint ? 'dewpoint' : 'humidity']);
    for (var x = 0; x < W; x++) {
      var b = Math.round(lo + (x + 0.5) / W * (hi - lo)) * 4;
      g.fillStyle = 'rgb(' + lut[b] + ',' + lut[b + 1] + ',' + lut[b + 2] + ')';
      g.fillRect(x, 0, 1, 10);
    }
    legend.appendChild(bar);
    (document.getElementById('lv-map') || map.getContainer()).appendChild(legend);
    return legend;
  }

  ANIM_LAYERS.humidity = function (m) { return new MoistLayer('humidity').addTo(m); };
  ANIM_LAYERS.dewpoint = function (m) { return new MoistLayer('dewpoint').addTo(m); };

  // The colored layers take turns: switching one on switches the others off.
  var plainSetLayer = window.animSetLayer;
  var COLORED = ['humidity', 'dewpoint', 'airquality', 'temperature', 'pressure'];
  window.animSetLayer = function (id, on) {
    if (on && COLORED.indexOf(id) >= 0) COLORED.forEach(function (o) { if (o !== id) plainSetLayer(o, false); });
    plainSetLayer(id, on);
  };

  function track(id) { return anim && anim.group.track(id); }
  function setOpacity(id, percent) {
    opacity[id] = Math.max(0, Math.min(100, percent === "" || percent === null || !isFinite(+percent) ? 60 : +percent)) / 100;
    var t = track(id);
    if (t) {
      t.layer.redraw();
      if (t.layer.legend) t.layer.legend.querySelector('canvas').style.opacity = String(opacity[id]);
    }
    return opacity[id];
  }
  window.humiditySetOpacity = function (percent) { return setOpacity('humidity', percent); };
  window.dewpointSetOpacity = function (percent) { return setOpacity('dewpoint', percent); };
  window.humidityOptions = function (o) {
    for (var k in o) opts[k] = o[k];
    ['humidity', 'dewpoint'].forEach(function (id) {
      var t = track(id);
      if (t) { t.layer.lut = null; t.layer.redraw(); t.layer.showLegend(); }
    });
    return opts;
  };
  window.humidityFrames = function (id) { var t = track(id || 'humidity'); return t && t.frames; };   // for the test scripts
  /** The value shown at lat/lon (°C for the dew point), and its hour. */
  window.humidityAt = function (lat, lon) {
    var t = track('humidity') || track('dewpoint'), g = t && t.layer.grid;
    if (!g) return null;
    return { layer: t.layer.id, at: new Date(g.times[0] * 1000).toISOString(), value: t.layer.spec.value(WidgetPressure.sample(g, lat, lon)) };
  };

  // --- the Ctrl readout: the value under the pointer, a drop of its color ---
  var plainReadout = readoutHtml;
  readoutHtml = function () {
    var html = plainReadout(), map = _widgetAdapter.getMap();
    var t = track('humidity') || track('dewpoint');
    if (!t || !t.layer.grid || !map || !readout.known) return html;
    var c = map.getContainer().getBoundingClientRect(), x = readout.x - c.left, y = readout.y - c.top;
    if (x < 0 || y < 0 || x > c.width || y > c.height) return html;
    var ll = map.unproject([x, y]);
    if (!ll || !isFinite(ll.lat) || Math.abs(ll.lat) > 85) return html;
    var back = map.project(ll);
    if (Math.abs(back.x - x) > 1 || Math.abs(back.y - y) > 1) return html;
    var b = WidgetPressure.sample(t.layer.grid, ll.lat, ll.lng);
    if (!isFinite(b)) return html;
    var s = t.layer.spec, v = s.value(b), col = colorAt(v, s);
    var drop = '<svg viewBox="0 0 16 16" width="20" height="20"><path d="M8 1.5 C8 1.5 3 7.5 3 10.5 A5 5 0 0 0 13 10.5 C13 7.5 8 1.5 8 1.5 Z" fill="currentColor" stroke="rgba(255,255,255,0.6)" stroke-width="0.8"/></svg>';
    return html + '<div class="lv-readout-row"><span class="lv-readout-icon" style="color:rgb(' + col.join(', ') + ')">' + drop +
      '</span><span>' + s.label + ' ' + s.text(v) + '</span></div>';
  };

  return { SPECS: SPECS, dewPoint: dewPoint, opts: opts };
})();
