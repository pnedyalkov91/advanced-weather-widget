// === FIELDS (glue-fields.js; MapLibre page, after glue-controls.js) ===
// What the animation's layers drawn by the graphics chip share (pressure,
// air quality, precipitation, clouds, humidity, dew point): their place in
// the map's stack, colors from stops, values packed on one byte, the 256
// color table of those bytes, the GL layer of one or two forecast
// pictures, its legend. It lives inside the page's module, where it
// reaches the adapter, anim and the readout.
var WidgetFields = (function () {
  'use strict';
  var GL = WidgetTemp.TempLayerGL;

  // --- the place of a layer: the adapter's stack (addLayer) ---

  /** A GL layer put back after a new base map, at its place. */
  function readdGL(map, gl) {
    if (map && !map.getLayer(gl.id)) _widgetAdapter.addLayer(gl);
  }

  // --- values ---

  /** The value at lat/lon of a grid given to showFile (mixed when it has
      two), its cell found once. */
  var CELL = { k: 0, nx: 0, fr: 0, fc: 0 };
  function sample(g, lat, lon) {
    if (!WidgetTemp.scalarCell(g, lat, lon, CELL)) return NaN;
    var v = WidgetTemp.cellValue(g.values, CELL);
    if (g.valuesB && g.mix > 0) v += (WidgetTemp.cellValue(g.valuesB, CELL) - v) * g.mix;
    return v;
  }
  /** Values on one byte each (0..254) by toByte(value); missing ones 0. */
  function packBytes(values, toByte) {
    var out = new Uint8Array(values.length);
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      out[i] = isFinite(v) ? Math.max(0, Math.min(254, Math.round(toByte(v)))) : 0;
    }
    return out;
  }
  /** A field of the animation kept as bytes the GPU reads as they are.
      props: its id, store, vars...; valuesOf(e, t) the grid of a file
      ({ lats, lons, res, values }), toByte(value) the byte of a value. */
  function byteField(props, valuesOf, toByte) {
    var f = {
      read: function (e, t) {
        var g = valuesOf(e, t);
        return { meta: { lats: g.lats, lons: g.lons, res: g.res }, parts: [packBytes(g.values, toByte)] };
      },
      unpack: function (parts) { return parts[0]; },
      grid: WidgetAnim.latLonGrid
    };
    for (var k in props) f[k] = props[k];
    return f;
  }
  /** An opacity given in percent (anything else: fallback), as 0..1. */
  function percent(p, fallback) {
    return Math.max(0, Math.min(100, p === '' || p === null || !isFinite(+p) ? fallback : +p)) / 100;
  }

  // --- colors ---

  /** '#rrggbb' as [r, g, b]. */
  function hex(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }
  function same(v) { return v; }
  /** The color of v between stops [[value, '#rrggbb'], ...], as [r, g, b],
      the colors spread evenly on scale(value) (Math.log...). */
  function colorAt(stops, v, scale) {
    if (v <= stops[0][0]) return hex(stops[0][1]);
    var k = 0, x = scale || same;
    while (k < stops.length - 2 && v > stops[k + 1][0]) k++;
    var f = Math.max(0, Math.min(1, (x(v) - x(stops[k][0])) / (x(stops[k + 1][0]) - x(stops[k][0]))));
    var a = hex(stops[k][1]), b = hex(stops[k + 1][1]);
    return [Math.round(a[0] + (b[0] - a[0]) * f), Math.round(a[1] + (b[1] - a[1]) * f), Math.round(a[2] + (b[2] - a[2]) * f)];
  }
  function css(rgb) { return 'rgb(' + rgb[0] + ', ' + rgb[1] + ', ' + rgb[2] + ')'; }
  /** 0 to 1 over 0..1, smoothly; clamped. */
  function smoothstep(t) { t = Math.max(0, Math.min(1, t)); return t * t * (3 - 2 * t); }
  /** The table of the 256 bytes as RGBA (255 read as 254): colorOf(value)
      of each byte's valueOf(byte), opaque unless alphaOf(value) 0..1. */
  function byteLut(valueOf, colorOf, alphaOf) {
    var out = new Uint8Array(256 * 4);
    for (var b = 0; b < 256; b++) {
      var v = valueOf(Math.min(b, 254)), c = colorOf(v);
      out[b * 4] = c[0]; out[b * 4 + 1] = c[1]; out[b * 4 + 2] = c[2];
      out[b * 4 + 3] = alphaOf ? Math.round(255 * alphaOf(v)) : 255;
    }
    return out;
  }

  // --- legends: a box at the top of the map (the page's legend column) ---

  /** A legend of class cls for layer id: ticks [[percent, text]] over the
      bars added after, the unit at the end. */
  function legendBox(cls, id, ticks, unit) {
    var el = document.createElement('div');
    el.className = cls;
    el.dataset.layer = id;
    el.innerHTML = '<div class="lv-temp-ticks">' + ticks.map(function (t) {
      return '<span style="left:' + t[0].toFixed(2) + '%">' + t[1] + '</span>';
    }).join('') + '</div><span class="lv-temp-unit">' + unit + '</span>';
    return el;
  }
  /** A color bar w x h px: cssAt(x) the color of column x. */
  function legendBar(w, h, cssAt) {
    var bar = document.createElement('canvas'), g = bar.getContext('2d');
    bar.width = w;
    bar.height = h;
    if (!g) return bar;
    for (var x = 0; x < w; x++) {
      g.fillStyle = cssAt(x);
      g.fillRect(x, 0, 1, h);
    }
    return bar;
  }
  /** The legend of a byte layer as wide as the temperature's: lut its color
      table, bytes lo..hi along the bar, ticks [[byte, text]]; alpha keeps
      the table's alpha in the bar. */
  function lutLegend(id, lut, lo, hi, ticks, unit, alpha) {
    var W = 240, el = legendBox('lv-aq-legend', id, ticks.map(function (t) {
      return [(t[0] - lo) / (hi - lo) * 100, t[1]];
    }), unit);
    var bar = legendBar(W, 10, function (x) {
      var b = Math.round(lo + (x + 0.5) / W * (hi - lo)) * 4;
      return alpha ? 'rgba(' + lut[b] + ',' + lut[b + 1] + ',' + lut[b + 2] + ',' + (lut[b + 3] / 255).toFixed(2) + ')'
        : 'rgb(' + lut[b] + ',' + lut[b + 1] + ',' + lut[b + 2] + ')';
    });
    bar.className = 'lv-temp-bar';
    el.appendChild(bar);
    return el;
  }

  // --- the GL layer of one or two forecast pictures ---

  /** A byte picture looked up in a 256 color table (u_lut). */
  var LUT_FS = GL.FS_HEAD + [
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
  function lutDraw(gl, u, layer) {
    var o = layer.owner, sh = o.shown, g = sh.grid;
    if (!g) return false;
    var rows = g.lats.length, cols = g.lons.length;
    layer.texture(gl, 0, sh.a, cols, rows, 'r8'); gl.uniform1i(u.u_a, 0);
    layer.texture(gl, 1, sh.b, cols, rows, 'r8'); gl.uniform1i(u.u_b, 1);
    layer.texture(gl, 2, o.colors(), 256, 1, 'rgba'); gl.uniform1i(u.u_lut, 2);
    gl.uniform2f(u.u_size, cols, rows);
    gl.uniform1f(u.u_mix, sh.mix);
    gl.uniform1f(u.u_opacity, o.o.opacity() * layer.fade);
    layer.drawn = sh.version;
    return true;
  }

  /** A layer of the animation drawn by the chip from the grids its field
      gives (showFile), at its place in the adapter's stack. o: { id (its
      lines' key), glId, opacity() 0..1, and either lut() (a byte picture
      in a 256 color table) or fs and draw(gl, u, layer) of its own;
      onShow(shown, grid, two) on each picture (more of the grid for draw),
      legend(layer) its legend element }. layer.shown is what draw reads: { grid, a, b (the two
      pictures), mix, version }. */
  function FieldLayer(o) {
    this.o = o;
    this.id = o.id;
    this.map = null;
    this.grid = null;
    this.lut = null;
    this.legend = null;
    this.shown = { grid: null, a: null, b: null, mix: 0, version: 0 };
    this.gl = new GL.GLLayer(o.glId, o.fs || LUT_FS, o.draw || lutDraw);
    this.gl.owner = this;
  }
  FieldLayer.prototype = {
    /** Its color table, made once (lut = null to make it again). */
    colors: function () { return this.lut || (this.lut = this.o.lut()); },
    addTo: function (map) {
      this.map = map;
      _widgetAdapter.addLayer(this.gl);
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
      var sh = this.shown, two = !!(grid.valuesB && grid.mix > 0);
      this.grid = sh.grid = grid;
      sh.a = grid.values;
      sh.b = two ? grid.valuesB : grid.values;
      sh.mix = two ? grid.mix : 0;
      if (this.o.onShow) this.o.onShow(sh, grid, two);
      sh.version++;
      this.redraw();
    },
    setFade: function (f) {
      this.gl.fade = f;
      if (this.legend) this.legend.style.opacity = String(f);
      this.redraw();
    },
    redraw: function () { if (this.map) this.map.triggerRepaint(); },
    /** Its colors changed: the table made again, the legend too. */
    recolor: function () { this.lut = null; this.redraw(); this.showLegend(); },
    restyle: function () { readdGL(this.map, this.gl); },
    settled: function () { return this.gl.drawn === this.shown.version; },
    reload: function () {},
    showLegend: function () {
      if (!this.map || !this.o.legend) return;
      this.hideLegend();
      this.legend = this.o.legend(this);
      this.legend.style.opacity = String(this.gl.fade);
      (document.getElementById('lv-map') || this.map.getContainer()).appendChild(this.legend);
    },
    hideLegend: function () { if (this.legend) this.legend.remove(); this.legend = null; },
    /** The layer's opacity changed: drawn again, its legend's bars as light. */
    setOpacity: function (op) {
      this.redraw();
      if (this.legend) this.legend.querySelectorAll('canvas').forEach(function (c) { c.style.opacity = String(op); });
    }
  };

  /** The track of layer id in the animation, null when off. */
  function track(id) { return anim && anim.group.track(id) || null; }

  return {
    readdGL: readdGL,
    sample: sample, packBytes: packBytes, byteField: byteField, percent: percent,
    hex: hex, colorAt: colorAt, css: css, smoothstep: smoothstep, byteLut: byteLut,
    legendBox: legendBox, legendBar: legendBar, lutLegend: lutLegend,
    FieldLayer: FieldLayer, track: track
  };
})();
