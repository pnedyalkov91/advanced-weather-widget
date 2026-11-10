// === HUMIDITY AND DEW POINT (glue-humidity.js; after glue-clouds.js) ===
// Two colored layers of the animation from the ECMWF files: 'humidity'
// (relative_humidity_2m, one byte a percent) and 'dewpoint' (not in the
// files: worked out from temperature_2m and relative_humidity_2m with the
// Magnus formula, as the API does, on one byte a half degree from -80 °C).
// Full 0.25 degree, one byte a point: a picture weighs 1 MB. The bytes go to
// the GPU as they are and are looked up in a 256 color table. They take
// turns with the other colored layers (temperature, pressure, air quality).
// A FieldLayer of glue-fields.js.
// window.humiditySetOpacity, dewpointSetOpacity (each its own), humidityOptions.
var WidgetHumidity = (function () {
  'use strict';
  var F = WidgetFields, track = F.track;
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

  Object.keys(SPECS).forEach(function (id) {
    var s = SPECS[id];
    s.lut = function () { return F.byteLut(s.value, function (v) { return F.colorAt(s.stops, v); }); };
    WidgetAnim.FIELDS[id] = F.byteField({ id: id, store: s.store, vars: s.vars }, s.grid, s.toByte);
  });

  /** The legend of layer id, in its colors. */
  function legend(layer) {
    var id = layer.id, s = SPECS[id], el = F.lutLegend(id, layer.colors(), s.toByte(s.lo), s.toByte(s.hi), s.ticks.map(function (v) {
      return [s.toByte(v), localNumber(id === 'dewpoint' ? cToUnit(v) : v, 0)];
    }), s.label + ' ' + s.unit());
    el.querySelector('canvas').style.opacity = String(opacity[id]);
    return el;
  }
  function makeLayer(id) {
    var l = new F.FieldLayer({ id: id, glId: 'lv-' + id + '-gl', lut: SPECS[id].lut, legend: legend, opacity: function () { return opacity[id]; } });
    l.spec = SPECS[id];
    return l;
  }
  ANIM_LAYERS.humidity = function (m) { return makeLayer('humidity').addTo(m); };
  ANIM_LAYERS.dewpoint = function (m) { return makeLayer('dewpoint').addTo(m); };

  // The colored layers take turns: switching one on switches the others off.
  var plainSetLayer = window.animSetLayer;
  var COLORED = ['humidity', 'dewpoint', 'airquality', 'temperature', 'pressure'];
  window.animSetLayer = function (id, on) {
    if (on && COLORED.indexOf(id) >= 0) COLORED.forEach(function (o) { if (o !== id) plainSetLayer(o, false); });
    plainSetLayer(id, on);
  };

  function setOpacity(id, percent) {
    opacity[id] = F.percent(percent, 60);
    var t = track(id);
    if (t) t.layer.setOpacity(opacity[id]);
    return opacity[id];
  }
  window.humiditySetOpacity = function (percent) { return setOpacity('humidity', percent); };
  window.dewpointSetOpacity = function (percent) { return setOpacity('dewpoint', percent); };
  window.humidityOptions = function (o) {
    for (var k in o) opts[k] = o[k];
    ['humidity', 'dewpoint'].forEach(function (id) {
      var t = track(id);
      if (t) t.layer.recolor();
    });
    return opts;
  };
  window.humidityFrames = function (id) { var t = track(id || 'humidity'); return t && t.frames; };   // for the test scripts
  /** The value shown at lat/lon (°C for the dew point), and its hour. */
  window.humidityAt = function (lat, lon) {
    var t = track('humidity') || track('dewpoint'), g = t && t.layer.grid;
    if (!g) return null;
    return { layer: t.layer.id, at: new Date(g.times[0] * 1000).toISOString(), value: t.layer.spec.value(F.sample(g, lat, lon)) };
  };

  // --- the Ctrl readout: the value under the pointer, a drop of its color ---
  var DROP = '<svg viewBox="0 0 16 16" width="20" height="20"><path d="M8 1.5 C8 1.5 3 7.5 3 10.5 A5 5 0 0 0 13 10.5 C13 7.5 8 1.5 8 1.5 Z" fill="currentColor" stroke="rgba(255,255,255,0.6)" stroke-width="0.8"/></svg>';
  addReadout(function () { return track('humidity') || track('dewpoint'); }, function (t, ll) {
    var b = F.sample(t.layer.grid, ll.lat, ll.lng);
    if (!isFinite(b)) return '';
    var s = t.layer.spec, v = s.value(b);
    return readoutRow(DROP, F.css(F.colorAt(s.stops, v)), s.label + ' ' + s.text(v));
  });

  return { SPECS: SPECS, dewPoint: dewPoint, opts: opts };
})();
