// ==========================================================================
// Glue script 3: create the viewer and expose the QML-facing window.* API.
// ==========================================================================
var config = {
  apiFixed: API_BASE,
  strings: STRINGS,
  view: { lat: LAT, lon: LON, zoom: INIT_ZOOM, maxZoom: 12 },
  layerMode: ACTIVE_LAYER,                      // 'radar' | 'satellite' | 'both'
  colorScheme: CURRENT_COLOR,                   // clamped 0..12
  cells: CELLS_INIT,                            // 'light' | 'dark' | '' (URL)
  arrows: (ARROWS_ON ? (ACTIVE_THEME === 'dark' ? 'light' : 'dark') : ''),
  alerts: ALERTS_INIT,                          // fetch + overlay alerts at boot
  smooth: SMOOTH_INIT,
  snow: SNOW_INIT,
  format: FORMAT_INIT,
  tileSize: TILESIZE_INIT,
  theme: ACTIVE_THEME,                          // 'dark' | 'light'
  locateMode: 'view',
  nowMarker: true,
  nowMarkerLabel: true,
  locale: SYS_LOCALE,
  hour12: HOUR12,
  onThemeChange: function (theme) {
    // The QML chrome only knows arrows on/off; the page derives the arrow
    // color from the map theme, so re-derive it whenever the theme moves.
    if (arrowsOn) viewer.setArrows(theme === 'dark' ? 'light' : 'dark');
    if (windLayer) windLayer.setTheme(theme);
  }
};

// Whether motion arrows are currently on. Initialized from the same derivation
// used for config.arrows above (ARROWS_ON), so onThemeChange stays correct.
var arrowsOn = ARROWS_ON;

// Capture the viewer API: every window.* setter drives the engine directly.
var viewer = window.LibreWXR.createViewer(config, _widgetAdapter);

// === QML-FACING WINDOW API ===
window.setLayerMode = function (mode) { viewer.setLayerMode(mode); };

window.setColorScheme = function (n) { viewer.setColorScheme(n); };

window.setArrows = function (on) {
    arrowsOn = !!on;
    viewer.setArrows(arrowsOn ? (currentTheme() === 'dark' ? 'light' : 'dark') : '');
};

window.setCells = function (mode) { viewer.setCells(mode); };

window.setAlerts = function (on) { viewer.setAlertsEnabled(!!on); };

window.setTheme = function (theme) { viewer.setTheme(theme); };

// WIDGET PATCH: live tile-options bridge for the Options panel (Smoothing /
// Snow mask / Format / Tile size). The engine already exposes these on
// `viewer` (see the createViewer return statement above) - only the
// window.* facade for the QML side was missing the last four.
window.setSmooth = function (on) { viewer.setSmooth(!!on); };

window.setSnow = function (on) { viewer.setSnow(!!on); };

window.setFormat = function (fmt) { viewer.setFormat(fmt); };

window.setTileSize = function (size) { viewer.setTileSize(size); };
// /WIDGET PATCH

window.setBackground = function (id) {
  if (id !== 'auto') {
    var found = false;
    for (var i = 0; i < BG_LIST.length; i++) {
      if (BG_LIST[i].id === id) { found = true; break; }
    }
    if (!found) return; // invalid id
  }
  BG_CURRENT = id;
  var theme = currentTheme();
  if (_widgetAdapter && typeof _widgetAdapter.setBasemap === 'function') {
    _widgetAdapter.setBasemap(theme);
  }
  renderBgMenu(); // keep the picker's active mark in sync with config-driven changes
};

window.fixViewport = function () {
  var m = _widgetAdapter ? _widgetAdapter.getMap() : null;
  if (!m) return;
  // Reproduce the old cure for the plasmoid's WebEngineView: recalculate the
  // container size and do an invisible 1px pan-and-back, which forces Leaflet
  // to reset its view and Chromium to repaint the damaged surface.
  _widgetAdapter.resize();
  if (windLayer) windLayer.nudging = true;
  _widgetAdapter.nudge();
  if (windLayer) windLayer.nudging = false;
  // The view is final now: the wind may start drawing.
  viewportSettled = true;
  if (windLayer) windLayer.settle();
  document.body.classList.add('lv-ready');   // fade the whole view in (overrides.css)
  // Timeout rearm: the engine's moveend restarts a quiet background preload,
  // which the cancelling 1px nudge (never a real view change) safely ignores.
  setTimeout(function () { _widgetAdapter.resize(); }, 400);
};

// Called by the widget when a page kept loaded comes back into view: answer
// with document.title 'ready:<token>' once the map has its real size and the
// layers on screen have their tiles, so the view fades in on a full map.
// Built hidden, the page had a 0 px map and has loaded nothing yet, and the
// popup goes through a smaller layout before its final one: wait for a size
// that holds still for 200 ms, then for its tiles. A tile
// that fails counts as done (a server down does not hold the fade), and the
// answer comes after 1.5 s at the latest, so a wind request that fails
// (Open-Meteo down, rate limit) does not hold the fade either. Hidden layers
// (radar frames preloaded at opacity 0) are not waited for.
window.signalWhenLoaded = function (token) {
  var m = _widgetAdapter ? _widgetAdapter.getMap() : null;
  var start = Date.now(), lastSize = '', still = 0;
  var answer = function () { document.title = 'ready:' + token; };
  if (!m) { answer(); return; }
  var busy = function () {
    var loading = _widgetAdapter.tilesBusy();
    // The wind draws once its grid is in, from memory or from Open-Meteo.
    if (windLayer && !windLayer.isDrawing()) loading = true;
    // The temperature once its first picture is on the map.
    if (tempLayer && !tempLayer.isDrawing()) loading = true;
    return loading;
  };
  var check = function () {
    if (Date.now() - start > 1500) { answer(); return; }
    // Leaflet requests the tiles of a new size a moment after it gets it.
    var key = _widgetAdapter.sizeKey();
    still = key.indexOf('0x') !== 0 && key === lastSize ? still + 1 : 0;
    lastSize = key;
    if (still >= 4 && !busy()) { answer(); return; }
    setTimeout(check, 50);
  };
  setTimeout(check, 50);
};

// === WIND LAYER (Open-Meteo particles, glue-wind.js) ===
var _windSource = new WidgetWind.WindSource(WIND_API_BASE ? { apiBase: WIND_API_BASE } : {});
// The open-data wind (glue-wind-open.js), on the pages that have it.
var _windOpen = typeof WidgetOpenData === 'undefined' ? null : new WidgetOpenData.Loader({
  base: WIND_FILES_BASE || undefined,
  importReader: function () { return import('./vendor/index.browser.js'); }
});
var _windDem = new WidgetWind.DemTiles({});
var windLayer = null;
var windLevel = WIND_LEVEL;   // '10m' | '700hPa'
var windFps = WIND_FPS, windMaxFps = WIND_MAX_FPS;
var windLineWidth = WIND_LINE_WIDTH;
var windDensity = WIND_DENSITY;
// A palette that does not parse (a broken settings entry) gives the default one.
var windPalette = WidgetWind.WindField.parsePalette(WIND_PALETTE_PARAM);
var viewportSettled = false;   // set by the first window.fixViewport()

window.setWind = function (on) {
  var m = _widgetAdapter.getMap();
  if (!m) return;
  if (on && !windLayer) {
    windLayer = _widgetAdapter.createWindLayer(_windSource, _windOpen, _windDem, {
      fps: windFps, maxFps: windMaxFps, relief: WIND_RELIEF, theme: currentTheme(), level: windLevel,
      lineWidth: windLineWidth, palette: windPalette, density: windDensity
    });
    if (!windLayer) return;
    windLayer.addTo(m);
    // Switched on after the page settled: nothing left to wait for.
    if (viewportSettled) windLayer.settle();
  } else if (!on && windLayer) {
    windLayer.remove();
    windLayer = null;
  }
  creditOpenMeteo();
};

// Frame-rate budget chosen in the widget settings (economy / balanced / smooth).
window.setWindRate = function (fps, maxFps) {
  windFps = fps; windMaxFps = maxFps;
  if (windLayer) windLayer.setRate(fps, maxFps);
};

// Particle width chosen in the widget settings (CSS px).
window.setWindWidth = function (w) {
  windLineWidth = w;
  if (windLayer) windLayer.setLineWidth(w);
};

// Particle density chosen in the widget settings (1 = one particle per 300 px2).
window.setWindDensity = function (d) {
  windDensity = d;
  if (windLayer) windLayer.setDensity(d);
};

// Wind palette chosen in the widget settings, in the "max:rrggbb" x 8 form.
window.setWindPalette = function (s) {
  windPalette = WidgetWind.WindField.parsePalette(s);
  if (windLayer) windLayer.setPalette(windPalette);
};

// '10m' (surface, relief-aware) or '700hPa' (the flow that steers the rain).
window.setWindLevel = function (level) {
  windLevel = level === '700hPa' ? '700hPa' : '10m';
  if (windLayer) windLayer.setLevel(windLevel);
};

// Popup collapsed/expanded: the page may not see a visibility change, so QML says it.
window.setWindActive = function (active) {
  if (windLayer) windLayer.setActive(!!active);
};

if (WIND_ON) window.setWind(true);

// === TEMPERATURE LAYER (glue-temp.js, glue-temp-layer.js; MapLibre page) ===
// It reads the wind's API grids and open-data files (one request serves
// both) and its own elevation tiles, kept apart from the wind's: it asks
// for tiles at every zoom.
window.tempAvailable = typeof WidgetTemp !== 'undefined' && !!WidgetTemp.TempLayer &&
  typeof _widgetAdapter.setTempTiles === 'function';
var tempLayer = null;
var _tempDem = window.tempAvailable ? new WidgetWind.DemTiles({ maxKept: 96 }) : null;
var tempPalette = window.tempAvailable ? WidgetTemp.paletteFromParam(TEMP_PALETTE_PARAM) : null;
var tempOpacity = window.tempAvailable ? WidgetTemp.normOpacity(TEMP_OPACITY) : 45;
var tempStep = window.tempAvailable ? WidgetTemp.normStep(TEMP_STEP) : 5;
var tempUnit = TEMP_UNIT;

// Open-Meteo credited while its data show.
function creditOpenMeteo() {
  if (_widgetAdapter.setDataAttribution) _widgetAdapter.setDataAttribution(!!(windLayer || tempLayer || anim));
}

window.setTemp = function (on) {
  var m = _widgetAdapter.getMap();
  if (!m || !window.tempAvailable) return;
  if (on && !tempLayer) {
    tempLayer = new WidgetTemp.TempLayer(_widgetAdapter, _windSource, _windOpen, _tempDem, {
      stops: tempPalette, step: tempStep, unit: tempUnit, opacity: tempOpacity
    });
    tempLayer.addTo(m);
  } else if (!on && tempLayer) {
    tempLayer.remove();
    tempLayer = null;
  }
  creditOpenMeteo();
};

// Palette chosen in the widget settings, "t:rrggbb,..." with t in °C.
window.setTempPalette = function (s) {
  if (!window.tempAvailable) return;
  tempPalette = WidgetTemp.paletteFromParam(s);
  if (tempLayer) tempLayer.setPalette(tempPalette);
};

// Opacity of the layer in percent, from the widget settings.
window.setTempOpacity = function (n) {
  if (!window.tempAvailable) return;
  tempOpacity = WidgetTemp.normOpacity(n);
  if (tempLayer) tempLayer.setOpacity(tempOpacity);
  var t = anim && anim.group.track('temperature');
  if (t) t.layer.setOpacity(tempOpacity);
};

// Width of the bands (0: smooth gradient), in the unit below.
window.setTempStep = function (n) {
  if (!window.tempAvailable) return;
  tempStep = WidgetTemp.normStep(n);
  if (tempLayer) tempLayer.setStep(tempStep);
  var t = anim && anim.group.track('temperature');
  if (t) t.layer.setStep(tempStep);
};

// The widget's temperature unit, 'C' or 'F': the bands and the legend follow it.
window.setTempUnit = function (u) {
  if (!window.tempAvailable) return;
  tempUnit = WidgetTemp.normUnit(u);
  if (tempLayer) tempLayer.setUnit(tempUnit);
  var t = anim && anim.group.track('temperature');
  if (t) t.layer.setUnit(tempUnit);
};

// Coasts and borders over the color layers, from the widget's setting.
window.setMapLines = function (on) {
  if (_widgetAdapter.setLinesShown) _widgetAdapter.setLinesShown(!!on);
};

if (TEMP_ON) window.setTemp(true);

// === ANIMATIONS (glue-anim.js; MapLibre page) ===
// The weather from days before to days ahead, each layer switched on
// (temperature, wind) with pictures of its own, moved on together; the
// radar, its bar and the live wind hide meanwhile. QML drives it and reads
// window.animState() for its own time bar.
var anim = null;
// Six file reads at once for all the layers together: as many as the
// temperature alone used to have; twelve ran the reader out of memory.
var animGate = typeof WidgetAnim === 'undefined' ? null : new WidgetAnim.Gate(6);
// The pictures read, kept across page loads; sorted out down to the longest
// range back the bar offers (8 days).
var animStore = typeof WidgetAnim === 'undefined' || typeof indexedDB === 'undefined' ? null : WidgetAnim.frameStore();
var ANIM_KEEP_H = 192;
// The finer regional models drawn over the temperature (WidgetModels ids,
// finest first; animSetFine switches them all), and their ground heights
// for the relief, one loader each.
var animFine = true;
var animFineModels = ['meteofrance_arome_france0025'];
var _fineOpen = {}, _fineSurface = {};
function fineSurface(model) {
  if (!_fineOpen[model]) {
    _fineOpen[model] = new WidgetOpenData.Loader({
      base: WIND_FILES_BASE || undefined, model: model,
      importReader: function () { return import('./vendor/index.browser.js'); }
    });
    _fineOpen[model].loadSurface().then(function (g) { if (g) _fineSurface[model] = g.values; });
  }
  return _fineSurface[model] || null;
}
window.animAvailable = window.tempAvailable && typeof WidgetAnim !== 'undefined' && !!_windOpen;

// The layers an animation can show, by id (a WidgetAnim.FIELDS key): each
// makes its layer in manual mode and puts it on the map. As on the radar,
// far out they draw the files, closer in the API grids (anim.api: one
// request per view for both, holding every hour of the range).
var ANIM_LAYERS = {
  temperature: function (m) {
    var layer = new WidgetTemp.TempLayer(_widgetAdapter, anim.api, _windOpen, _tempDem, {
      stops: tempPalette, step: tempStep, unit: tempUnit, opacity: tempOpacity, manual: true
    });
    layer.addTo(m);
    layer.setMovingStep(anim.movingStep);
    return layer;
  },
  wind: function (m) {
    var layer = _widgetAdapter.createWindLayer(anim.api, null, _windDem, {
      fps: windFps, maxFps: windMaxFps, relief: WIND_RELIEF, theme: currentTheme(), level: '10m',
      lineWidth: windLineWidth, palette: windPalette, density: windDensity, manual: true
    });
    if (!layer) return null;
    layer.addTo(m);
    layer.settle();
    return layer;
  }
};

// The name the pictures of a layer are kept under while it is off, for
// layers whose pictures depend on a choice within them (by id: a function
// giving that name); the layer's id otherwise.
var ANIM_KEYS = {};
function animKey(id) { return ANIM_KEYS[id] ? ANIM_KEYS[id]() : id; }

/** Pictures of layer id for the range of the animation, those of `reuse`
    (the same layer's Frames of another range, or kept while it was off)
    taken over; onShow once its first picture is drawn. */
function animTrack(id, layer, reuse, onShow) {
  var frames = new WidgetAnim.Frames(_windOpen, {
    field: WidgetAnim.FIELDS[id], now: function () { return anim.nowMs; },
    pastH: anim.pastH, futureH: anim.futureH, reuse: reuse, parallel: 6, gate: animGate,
    store: animStore, pruneH: ANIM_KEEP_H,
    onFrame: function (i) {
      var t = anim && anim.group.track(id);
      if (!t || t.frames !== frames) return;
      var p = anim.player;
      // The picture of now goes up as soon as every layer has it; a layer
      // switched on while paused joins the others once its picture is in.
      if (p.index < 0) { if (i === anim.group.nowIndex && anim.group.ready(i)) p.show(i); }
      else if (!p.playing && (i === Math.floor(p.index) || i === Math.ceil(p.index))) p.seek(p.index);
    }
  });
  var fines = [];
  if (id === 'temperature' && animFine && typeof WidgetModels !== 'undefined') {
    fines = frames.fines = animFineModels.map(function (model) {
      var old = reuse && reuse.fines ? reuse.fines.filter(function (f) { return f.fileModel === model; })[0] : null;
      fineSurface(model);
      return new WidgetAnim.Frames(_windOpen, {
        field: WidgetAnim.FIELDS.temperatureFine, fileModel: model, now: function () { return anim.nowMs; },
        pastH: anim.pastH, futureH: anim.futureH, reuse: old, parallel: 6, gate: animGate,
        store: animStore, pruneH: ANIM_KEEP_H, surface: function () { return fineSurface(model); },
        onFrame: function (i) {
          var t = anim && anim.group.track(id), p = anim && anim.player;
          if (!t || t.frames !== frames || p.index < 0 || p.playing) return;
          if (i === Math.floor(p.index) || i === Math.ceil(p.index)) p.seek(p.index);
        }
      });
    });
  }
  if (reuse) reuse.stop();
  // Loading, it holds no other layer: they play on, it joins them picture
  // by picture; once loaded, they wait for it again where it misses one.
  anim.group.add(id, frames, layer, { onShow: onShow, optional: true });
  var t0 = Date.now();
  frames.load().then(function () {
    var t = anim && anim.group.track(id);
    if (t && t.frames === frames) anim.group.setOptional(id, false);
    console.log('[anim] ' + id + ': ' + frames.packed.filter(Boolean).length + '/' + frames.times.length + ' pictures in ' +
      (Date.now() - t0) + ' ms, ' + frames.fromStore + ' from the store');
  }, function (err) { console.warn('[anim] ' + id + ': ' + err); });
  fines.forEach(function (fine) {
    var t1 = Date.now();
    fine.load().then(function () {
      console.log('[anim] ' + id + ' ' + fine.fileModel + ': ' + fine.packed.filter(Boolean).length + '/' + fine.times.length + ' pictures in ' +
        (Date.now() - t1) + ' ms, ' + fine.fromStore + ' from the store');
    }, function (err) { console.warn('[anim] ' + id + ' ' + fine.fileModel + ': ' + err); });
  });
}

/** New pictures for pastH hours before now and futureH after, those
    already read taken over; the time shown stays. */
function animLoad(pastH, futureH) {
  // Layers fading out belong to the old range: they go at once.
  anim.switcher.flush();
  var old = anim.group, shownMs = old && anim.player.index >= 0 ? old.times[Math.round(anim.player.index)] : null;
  anim.nowMs = Date.now();
  anim.pastH = pastH;
  anim.futureH = futureH;
  var ft = WidgetAnim.frameTimes(anim.nowMs, pastH, futureH, WidgetAnim.STEP_H);
  anim.group = anim.player.frames = anim.player.layer = new WidgetAnim.Group(ft.times, ft.now);
  // The API's hours count from the present hour, the frames from the
  // nearest 3-hour step: one step more each way covers them.
  anim.api.setHours(pastH + WidgetAnim.STEP_H, futureH + WidgetAnim.STEP_H);
  if (old) old.tracks.forEach(function (t) { animTrack(t.id, t.layer, t.frames); t.layer.reload(); });
  var keep = shownMs === null ? -1 : ft.times.indexOf(shownMs);
  anim.player.index = -1;
  anim.player.show(keep >= 0 ? keep : ft.now);
}

/** Switch layer id of the animation on or off. Off, it fades out and its
    pictures are kept; on, it takes them back (nothing read again) and
    fades in with its first picture, while a color it replaces waits for
    it (WidgetAnim.Switcher). */
function animSetLayer(id, on) {
  var t = anim.group.track(id);
  var key = animKey(id);
  if (!on && t) {
    anim.group.remove(id);
    // Fading out, it plays on with the others.
    anim.group.addGhost(key, t.frames, t.layer);
    anim.switcher.leave(key, t.layer, t.frames);
  } else if (on && !t && ANIM_LAYERS[id]) {
    var back = anim.switcher.enter(key);
    if (back.layer) anim.group.removeGhost(key);
    var layer = back.layer || ANIM_LAYERS[id](_widgetAdapter.getMap());
    if (!layer) return;
    if (layer.setMoving) layer.setMoving(anim.player.playing);
    anim.switcher.entered(key, layer);
    animTrack(id, layer, back.reuse, function () { if (anim) anim.switcher.shown(key); });
    if (anim.player.index >= 0) anim.player.seek(anim.player.index);
  }
}

/** A new base map drops the layers the animation put on the map: each puts
    its own back (restyle, for those that add any; the temperature tiles
    come back with the adapter's), then the picture shown is drawn again. */
var animRestyleHooked = false;
function animRestyle() {
  if (!anim) return;
  var m = _widgetAdapter.getMap();
  anim.switcher.flush();
  anim.group.tracks.forEach(function (t) { if (t.layer.restyle) t.layer.restyle(m); });
  if (anim.player.index >= 0) anim.player.show(anim.player.index);
}

/** Start with the layers of `layers` ({ temperature: true, wind: false }),
    the temperature alone by default. */
window.animStart = function (pastH, futureH, layers) {
  var m = _widgetAdapter.getMap();
  if (!m || !window.animAvailable) return false;
  if (anim) return true;
  if (!animRestyleHooked && _widgetAdapter.onRestyle) { _widgetAdapter.onRestyle(animRestyle); animRestyleHooked = true; }
  if (tempLayer) { tempLayer.remove(); tempLayer = null; }
  if (windLayer) windLayer.setActive(false);
  anim = {
    group: null, player: new WidgetAnim.Player(null, null), movingStep: 1,
    switcher: new WidgetAnim.Switcher({ onGone: function (key) { if (anim && anim.group) anim.group.removeGhost(key); } }),
    // Not stored: a grid of the whole range would not fit in localStorage.
    api: new WidgetWind.WindSource({ storage: null, world: false })
  };
  animLoad(pastH == null ? 24 : pastH, futureH == null ? 48 : futureH);
  _widgetAdapter.setFramesHidden(true);
  document.body.classList.add('lv-anim');
  layers = layers || { temperature: true };
  for (var id in ANIM_LAYERS) if (layers[id]) animSetLayer(id, true);
  creditOpenMeteo();
  return true;
};

window.animSetRange = function (pastH, futureH) { if (anim) animLoad(pastH, futureH); };
window.animSetLayer = function (id, on) { if (anim) animSetLayer(id, !!on); };

window.animStop = function () {
  if (!anim) return;
  anim.player.stop();
  anim.group.tracks.forEach(function (t) { t.frames.stop(); t.layer.remove(); });
  anim.switcher.clear();
  anim = null;
  if (windLayer) windLayer.setActive(true);
  _widgetAdapter.setFramesHidden(false);
  document.body.classList.remove('lv-anim');
  creditOpenMeteo();
};

window.animPlay = function (on) { if (anim) anim.player.play(on); };
/** Play or pause; the new state, so QML need not trust its last reading. */
window.animToggle = function () {
  if (!anim) return false;
  anim.player.play(!anim.player.playing);
  return anim.player.playing;
};
window.animShow = function (i) { if (anim) anim.player.seek(i); };
// Paused steps: one hour (dir 1 or -1), or to the next frame from its file.
window.animStep = function (dir) { if (anim) anim.player.step(dir, WidgetAnim.STEP_H); };
window.animStepFile = function (dir) { if (anim) anim.player.stepFile(dir); };
window.animSetStep = function (ms) { if (anim) anim.player.stepMs = ms; };
window.animSetMaxFps = function (fps) { if (anim) anim.player.minFrameMs = 1000 / fps; };
// Resolution of the temperature while it plays: 1 full, 2 half, 4 quarter; full again on pause.
window.animSetResolution = function (n) {
  if (!anim) return;
  anim.movingStep = n;
  var t = anim.group.track('temperature');
  if (t) t.layer.setMovingStep(n);
};

/** The finer models on or off (spike, to compare). */
window.animSetFine = function (on) {
  animFine = !!on;
  if (anim) animLoad(anim.pastH, anim.futureH);
};

/** The finer models drawn (ids of WidgetModels), put in their order of
    priority, finest first; unknown ids left out. Until the view picks
    them (spike). */
window.animSetFineModels = function (ids) {
  animFineModels = WidgetModels.list.map(function (m) { return m.id; }).filter(function (id) { return ids.indexOf(id) >= 0; });
  if (anim) animLoad(anim.pastH, anim.futureH);
  return animFineModels;
};

/** What the animation holds and has read (spike measures): bytes read by
    model, bytes of the packed pictures by layer and model. */
window.animMeasure = function () {
  var held = {};
  function add(name, f) {
    if (!f) return;
    held[name] = f.packed.reduce(function (n, p) { return n + (p ? p.reduce(function (m, a) { return m + a.byteLength; }, 0) : 0); }, 0);
    held[name + ' pictures'] = f.packed.filter(Boolean).length;
  }
  if (anim) {
    anim.group.tracks.forEach(function (t) {
      add(t.id, t.frames);
      (t.frames.fines || []).forEach(function (f) { add(t.id + ' ' + f.fileModel, f); });
    });
  }
  return { read: Object.assign({}, WidgetOpenData.traffic), held: held, fine: animFine, models: animFineModels };
};

/** { times (ms), ready, failed, now, index (a position between frames),
    time (ms) of that position, fromFile (a frame as read, not worked out),
    playing, layers ({ id: on }) } for the QML bar. */

window.animState = function () {
  if (!anim) return null;
  var g = anim.group, layers = {};
  for (var id in ANIM_LAYERS) layers[id] = !!g.track(id);
  return {
    times: g.times, now: g.nowIndex, index: anim.player.index, playing: anim.player.playing,
    time: anim.player.index >= 0 ? g.timeAt(anim.player.index) : null,
    fromFile: anim.player.index >= 0 && g.isFile(anim.player.index),
    ready: g.times.map(function (_, i) { return g.ready(i); }), failed: g.failed(), layers: layers
  };
};

// === READOUT UNDER THE POINTER (Ctrl) ===
// While Ctrl is held, a small box follows the mouse with the wind and the
// temperature drawn there, at the time shown: the animation's layers while
// it runs, else the live ones. Ctrl is read from the mouse events too: in
// the Plasma popup the page does not always get the keys.
var windUnit = WIND_UNIT;
var windUnitLabel = tr('windUnitLabel', { kmh: 'km/h', ms: 'm/s', kn: 'kn', mph: 'mph' }[WIND_UNIT]);
var COMPASS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'].map(function (d) { return tr('dir' + d, d); });
var readout = { el: null, x: 0, y: 0, known: false, shown: false, timer: null, keyDown: false };

/** The wind unit chosen in the widget and its translated label. */
window.setWindUnit = function (u, label) {
  windUnit = u;
  windUnitLabel = label || windUnitLabel;
  if (readout.shown) readoutDraw();
};

function readoutLayers() {
  if (anim) {
    var w = anim.group.track('wind'), t = anim.group.track('temperature');
    return { wind: w && w.layer, temp: t && t.layer };
  }
  return { wind: windLayer, temp: tempLayer };
}

/** A number the local way, with `dec` decimals. */
function localNumber(n, dec) {
  return n.toLocaleString(SYS_LOCALE, { minimumFractionDigits: dec, maximumFractionDigits: dec });
}

// A filled arrow pointing down (south), turned to where the wind goes; it
// takes the color of its span.
var READOUT_ARROW = '<svg viewBox="0 0 16 16" width="20" height="20"><path d="M8 15.5 3.6 9.3H6.9V.5h2.2v8.8h3.3Z" fill="currentColor"/></svg>';

// A thermometer drawn here (a file's image could not take a color), filled
// with the color of its span, a thin outline so dark colors still show.
var READOUT_THERMO = '<svg viewBox="0 0 16 16" width="20" height="20"><path d="M6.2 2.2a1.8 1.8 0 0 1 3.6 0v6.7a3.6 3.6 0 1 1-3.6 0Z" ' +
  'fill="currentColor" stroke="rgba(255,255,255,0.6)" stroke-width="0.8"/></svg>';

/** The lines of the box at the pointer, '' where nothing is drawn. */
function readoutHtml() {
  var m = _widgetAdapter.getMap(), layers = readoutLayers();
  var hasWind = !!(layers.wind && layers.wind.valueAt), hasTemp = !!(layers.temp && layers.temp.valueAt);
  if (!m || !(hasWind || hasTemp)) return '';
  var c = m.getContainer().getBoundingClientRect(), x = readout.x - c.left, y = readout.y - c.top;
  if (x < 0 || y < 0 || x > c.width || y > c.height) return '';
  var ll = m.unproject([x, y]);
  if (!ll || !isFinite(ll.lat) || Math.abs(ll.lat) > 85) return '';
  var back = m.project(ll);
  if (Math.abs(back.x - x) > 1 || Math.abs(back.y - y) > 1) return '';   // off the globe
  var lines = [];
  var w = hasWind ? layers.wind.valueAt(ll.lat, ll.lng) : null;
  if (w) {
    var s = WidgetWind.WindField.speedText(w.speed, windUnit);
    // The arrow points where the wind goes.
    // The arrow in the color of the particles at that speed.
    var wc = layers.wind.colorOf ? ';color:' + layers.wind.colorOf(w.speed) : '';
    lines.push('<span class="lv-readout-arrow" style="transform:rotate(' + Math.round(w.dir) + 'deg)' + wc + '">' + READOUT_ARROW + '</span>' +
      '<span>' + localNumber(Number(s), s.indexOf('.') >= 0 ? 1 : 0) + ' ' + windUnitLabel + ' ' + COMPASS[WidgetWind.WindField.compassIndex(w.dir)] + '</span>');
  }
  var t = hasTemp ? layers.temp.valueAt(ll.lat, ll.lng) : null;
  if (t !== null && isFinite(t)) {
    // The thermometer in the color of the band on the map.
    var tc = layers.temp.colorOf ? ' style="color:' + layers.temp.colorOf(t) + '"' : '';
    lines.push('<span class="lv-readout-icon"' + tc + '>' + READOUT_THERMO + '</span>' +
      '<span>' + localNumber(tempUnit === 'F' ? t * 9 / 5 + 32 : t, 1) + ' \u00b0' + tempUnit + '</span>');
  }
  return lines.map(function (l) { return '<div class="lv-readout-row">' + l + '</div>'; }).join('');
}

function readoutDraw() {
  // Nothing before the pointer has been over the page: its place is unknown.
  var html = readout.known ? readoutHtml() : '', el = readout.el;
  if (!html) { el.style.display = 'none'; return; }
  el.innerHTML = html;
  el.style.display = 'block';
  // Below right of the pointer, kept inside the window.
  var left = readout.x + 14, top = readout.y + 14;
  if (left + el.offsetWidth > window.innerWidth - 4) left = readout.x - 14 - el.offsetWidth;
  if (top + el.offsetHeight > window.innerHeight - 4) top = readout.y - 14 - el.offsetHeight;
  el.style.left = Math.max(4, left) + 'px';
  el.style.top = Math.max(4, top) + 'px';
}

function readoutShow(on) {
  if (on === readout.shown) { if (on) readoutDraw(); return; }
  readout.shown = on;
  document.body.classList.toggle('lv-readout-on', on);   // the pointer becomes a cross
  // Told to the window through the console: it sets the cross at once
  // (Chromium changes its own only at the next mouse move).
  console.log('[readout] ctrl:' + (on ? 1 : 0));
  if (!readout.el) {
    readout.el = document.createElement('div');
    readout.el.id = 'lv-readout';
    document.body.appendChild(readout.el);
  }
  if (on) {
    readoutDraw();
    // The values change while the animation plays or the wind comes in.
    readout.timer = setInterval(readoutDraw, 250);
  } else {
    clearInterval(readout.timer);
    readout.el.style.display = 'none';
  }
}

document.addEventListener('mousemove', function (e) {
  readout.x = e.clientX;
  readout.y = e.clientY;
  readout.known = true;
  // A move without Ctrl only ends it when no key holds it: Qt sends moves
  // of its own, without the modifiers, when the window changes the cursor.
  readoutShow(e.ctrlKey || readout.keyDown);
});
document.addEventListener('keydown', function (e) {
  if (e.key !== 'Control' || e.repeat) return;
  readout.keyDown = true;
  readoutShow(true);
});
// Ctrl seen by QML while the keyboard is on its side (the page then gets no
// key at all): the box shows at once at the last pointer position.
// The pointer as the window sees it (x, y in the page's pixels): while it
// sets the cross, the moves no longer reach the page.
window.readoutAt = function (x, y) {
  readout.x = x;
  readout.y = y;
  readout.known = true;
  if (readout.shown) readoutDraw();
};
window.setReadout = function (on) {
  readout.keyDown = !!on;
  readoutShow(!!on);
};
document.addEventListener('keyup', function (e) {
  if (e.key !== 'Control') return;
  readout.keyDown = false;
  readoutShow(false);
});
// Not while a key holds it: setting the cross, Qt tells the page the pointer
// left, though the moves keep coming.
document.addEventListener('mouseleave', function () { if (!readout.keyDown) readoutShow(false); });
window.addEventListener('blur', function () { readout.keyDown = false; readoutShow(false); });

// Fade-in fallback when nothing calls fixViewport (the page opened on its own).
setTimeout(function () { document.body.classList.add('lv-ready'); }, 1500);

// === PROJECTION (MapLibre page: flat map or globe) ===
// The globe button sits under the base-map picker and is lit while the globe
// shows. A switch is reported to QML through the title ("proj:"), which keeps
// it in the settings; QML can also set it through window.setProjection().
var projBtn = document.getElementById('lv-proj');
function renderProjBtn() {
  if (projBtn) projBtn.classList.toggle('active', _widgetAdapter.getProjection() === 'globe');
}
window.setProjection = function (p) {
  p = p === 'globe' ? 'globe' : 'flat';
  if (p === _widgetAdapter.getProjection()) return;
  _widgetAdapter.setProjection(p);
  renderProjBtn();
  // The wind layers, the animation's too (and those fading out), build their
  // table again on the first frame of the new projection (reproject); the
  // old one put a flat map's wind in the globe's disc.
  var winds = [windLayer];
  if (anim && anim.group) anim.group.tracks.concat(anim.group.ghosts).forEach(function (t) { winds.push(t.layer); });
  winds.forEach(function (l) {
    if (l && l.reproject) l.reproject();
    else if (l && l.refresh) setTimeout(function () { l.refresh(); }, 300);
  });
  if (tempLayer) setTimeout(function () { if (tempLayer) tempLayer.refresh(); }, 300);
};
if (projBtn) {
  projBtn.title = tr('globe', 'Globe');
  projBtn.addEventListener('click', function () {
    window.setProjection(_widgetAdapter.getProjection() === 'globe' ? 'flat' : 'globe');
    document.title = 'proj:' + _widgetAdapter.getProjection();
  });
  renderProjBtn();
}

// === DAY AND NIGHT (MapLibre page: the night fading in on the map) ===
// Same pattern as the globe button: lit while on, reported to QML through
// the title ("night:1" or "night:0"), set by QML through window.setDayNight().
var nightBtn = document.getElementById('lv-night');
function renderNightBtn() {
  if (nightBtn) nightBtn.classList.toggle('active', _widgetAdapter.getDayNight());
}
window.setDayNight = function (on) {
  _widgetAdapter.setDayNight(!!on);
  renderNightBtn();
};
if (nightBtn) {
  nightBtn.title = tr('dayNight', 'Day and night');
  nightBtn.addEventListener('click', function () {
    window.setDayNight(!_widgetAdapter.getDayNight());
    document.title = 'night:' + (_widgetAdapter.getDayNight() ? '1' : '0');
  });
  renderNightBtn();
}

// Glow of the globe's atmosphere, from the widget's slider (percent).
window.setGlow = function (percent) { _widgetAdapter.setGlow(percent); };
// Darkness of the deep night, from the widget's settings (percent of black).
window.setNightDepth = function (percent) { _widgetAdapter.setNightDepth(percent); };

// === BASE MAP PICKER (in-map, 1.7.2 style) ===
var bgMenu = document.getElementById('bgMenu');
var bgBtn = document.getElementById('bgBtn');
function currentTheme() {
  return document.body.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
}
function renderBgMenu() {
    if (!bgMenu) return;
    bgMenu.innerHTML = '';
    if (!BG_LIST.length) {
        var picker = document.getElementById('bgPicker');
        if (picker) picker.style.display = 'none';
        return;
    }
    for (var i = 0; i < BG_LIST.length; i++) {
        (function (entry) {
            var row = document.createElement('div');
            row.textContent = entry.label;
            if (entry.id === BG_CURRENT) row.className = 'active';
            row.addEventListener('click', function () {
                if (entry.id === BG_CURRENT) { closeBgMenu(); return; }
                BG_CURRENT = entry.id;
                _widgetAdapter.setBasemap(currentTheme());
                // Persist the pick on the QML side via the title channel
                document.title = 'bg:' + entry.id;
                closeBgMenu();
                renderBgMenu();
            });
            bgMenu.appendChild(row);
        })(BG_LIST[i]);
    }
}
function closeBgMenu() {
    if (bgMenu) bgMenu.classList.remove('open');
}
if (bgBtn) {
    bgBtn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        if (bgMenu) {
            var isOpen = bgMenu.classList.contains('open');
            if (isOpen) { closeBgMenu(); }
            else { renderBgMenu(); bgMenu.classList.add('open'); }
        }
    });
}
document.addEventListener('click', function (ev) {
    if (bgMenu && bgMenu.classList.contains('open') && ev.target && !(ev.target.closest && (ev.target.closest('#bgPicker')))) closeBgMenu();
});
renderBgMenu();

// === VIEWPORT FIX WIRING (map lifecycle in the ~380px embedded webview) ===
if (typeof ResizeObserver !== 'undefined') {
  var _roTimer = null;
  new ResizeObserver(function () {
    if (_roTimer) clearTimeout(_roTimer);
    _roTimer = setTimeout(window.fixViewport, 120);
  }).observe(document.getElementById('lv-map'));
}
window.addEventListener('load', function () {
  setTimeout(window.fixViewport, 250);
  setTimeout(window.fixViewport, 1200);
});

// === BUILD PROVENANCE ===
// Assembled by the advanced-weather-widget's scripts/build_librewxr_map.py.
