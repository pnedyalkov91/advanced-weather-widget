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
  var t = anim && anim.group.track('wind');
  if (t) t.layer.setPalette(windPalette);
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
  var t = anim && anim.group.track('temperature');
  if (t) t.layer.setPalette(tempPalette);
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

// The stack of the weather layers, chosen in the widget settings: ids top
// first (radar, satellite, precipitation, clouds, temperature, pressure,
// humidity, dewpoint, airquality); the isobars go over the highest field.
window.setLayerOrder = function (order) {
  if (_widgetAdapter.setLayerOrder) _widgetAdapter.setLayerOrder(order);
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
var animWindOpacity = 1;       // the wind's opacity in the animation (0..1)
// Six file reads at once for all the layers together: as many as the
// temperature alone used to have; twelve ran the reader out of memory.
var animGate = typeof WidgetAnim === 'undefined' ? null : new WidgetAnim.Gate(6);
// The pictures read, kept across page loads; sorted out down to the longest
// range back the bar offers (8 days).
var animStore = typeof WidgetAnim === 'undefined' || typeof indexedDB === 'undefined' ? null : WidgetAnim.frameStore();
var ANIM_KEEP_H = 192;
// The finer regional models drawn over the temperature (WidgetModels ids,
// finest first): those the view picks (WidgetModels.pickForView), or a
// list set by hand (animSetFineModels); animSetFine switches them all.
// Their ground heights for the relief, one loader each. Those out of view
// keep their pictures while they fit in ANIM_FINE_BUDGET with those in view.
var animFine = true;
var animFineAuto = true;
var animFineModels = [];
var ANIM_FINE_BUDGET = 150e6;
var animFineKeep = typeof WidgetAnim === 'undefined' ? null : new WidgetAnim.FineKeep(ANIM_FINE_BUDGET);
var _fineOpen = {}, _fineSurface = {};
function fineSurface(model) {
  if (!_fineOpen[model]) {
    _fineOpen[model] = new WidgetOpenData.Loader({
      base: WIND_FILES_BASE || undefined, model: model, step: WidgetModels.get(model).step,
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
    // The graphics chip draws the files far out; the tiles everything else.
    var Layer = WidgetTemp.TempLayerGL || WidgetTemp.TempLayer;
    var layer = new Layer(_widgetAdapter, anim.api, _windOpen, _tempDem, {
      stops: tempPalette, step: tempStep, unit: tempUnit, opacity: tempOpacity, manual: true, quantum: WidgetAnim.TEMP_QUANTUM
    });
    layer.addTo(m);
    layer.setMovingStep(anim.movingStep);
    return layer;
  },
  wind: function (m) {
    var layer = _widgetAdapter.createWindLayer(anim.api, null, _windDem, {
      fps: windFps, maxFps: windMaxFps, relief: WIND_RELIEF, theme: currentTheme(), level: animWindLevel,
      lineWidth: windLineWidth, palette: windPalette, density: windDensity, manual: true, opacity: animWindOpacity
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
var ANIM_KEYS = { wind: function () { return 'wind:' + animWindLevel; } };
function animKey(id) { return ANIM_KEYS[id] ? ANIM_KEYS[id]() : id; }

// The wind of the animation at 10 m or at 700 hPa (about 3000 m, the flow
// that steers the rain), the two levels the radar's wind offers; each has
// its own pictures, kept apart, so a new level fades in over the old one.
var animWindLevel = WIND_LEVEL;
/** The field the pictures of layer id are read with. */
function animField(id) { return id === 'wind' ? WidgetAnim.windField(animWindLevel) : WidgetAnim.FIELDS[id]; }

/** Another level of the wind ('10m' or '700hPa'): the layer goes off and
    comes back at it. The level now. */
window.animSetWindLevel = function (level) {
  if (WidgetAnim.WIND_LEVELS.indexOf(level) < 0 || level === animWindLevel) return animWindLevel;
  var on = anim && anim.group && anim.group.track('wind');
  if (on) animSetLayer('wind', false);
  animWindLevel = level;
  if (on) animSetLayer('wind', true);
  return animWindLevel;
};

// Looping or not (WidgetAnim.Player.loop), kept across starts.
var animLoop = true;
window.animSetLoop = function (on) {
  animLoop = !!on;
  if (anim) anim.player.loop = animLoop;
  return animLoop;
};

/** Pictures of layer id for the range of the animation, those of `reuse`
    (the same layer's Frames of another range, or kept while it was off)
    taken over; onShow once its first picture is drawn. */
function animTrack(id, layer, reuse, onShow) {
  var frames = WidgetAnim.makeFrames(_windOpen, {
    field: animField(id), now: function () { return anim.nowMs; },
    pastH: anim.pastH, futureH: anim.futureH, times: anim.group.times, nowIndex: anim.group.nowIndex,
    reuse: reuse, parallel: 6, gate: animGate,
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
  frames.fines = fines;   // none unless the layer takes them (a field taken over may hold some)
  if (animFineField(id) && animFine) {
    if (animFineAuto) animFineModels = animPickFines();
    fines = frames.fines = animFineModels.map(function (model) {
      var old = reuse && reuse.fines ? reuse.fines.filter(function (f) { return f.fileModel === model; })[0] : null;
      return animMakeFine(id, model, frames, old || animFineKeep.take(id + '|' + model));
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
  fines.forEach(animLoadFine);
}

/** The regional models for the map's view, finest first. */
function animPickFines() {
  var b = _widgetAdapter.getMap().getBounds();
  return WidgetModels.pickForView({ south: b.getSouth(), west: b.getWest(), north: b.getNorth(), east: b.getEast() });
}

/** The field of the finer models riding along with layer id's pictures;
    null for a layer without (pressure, clouds...), or whose field says it
    takes none (fines: false: the wind at 700 hPa, which the regional
    files do not hold; their 10 m wind would be drawn over it). */
function animFineField(id) {
  if (typeof WidgetModels === 'undefined') return null;
  if (animField(id) && animField(id).fines === false) return null;
  return { temperature: WidgetAnim.FIELDS.temperatureFine, wind: WidgetAnim.FIELDS.windFine }[id] || null;
}

/** The pictures of finer model `model` riding along with layer id's
    frames, those of `reuse` (the same model's, paused or of another
    range) taken over. The temperature brings the model's ground height. */
function animMakeFine(id, model, frames, reuse) {
  var temp = id === 'temperature';
  if (temp) fineSurface(model);
  var fine = WidgetAnim.makeFrames(_windOpen, {
    field: animFineField(id), fileModel: model, now: function () { return anim.nowMs; },
    pastH: anim.pastH, futureH: anim.futureH, times: anim.group.times, nowIndex: anim.group.nowIndex,
    reuse: reuse, parallel: 6, gate: animGate,
    store: animStore, pruneH: ANIM_KEEP_H, surface: temp ? function () { return fineSurface(model); } : null,
    onFrame: function (i) {
      var t = anim && anim.group.track(id), p = anim && anim.player;
      if (!t || t.frames !== frames || (frames.fines || []).indexOf(fine) < 0 || p.index < 0 || p.playing) return;
      if (i === Math.floor(p.index) || i === Math.ceil(p.index)) p.seek(p.index);
    }
  });
  fine.keepKey = id + '|' + model;
  if (reuse) reuse.stop();
  return fine;
}

function animLoadFine(fine) {
  var t1 = Date.now();
  fine.load().then(function () {
    console.log('[anim] ' + fine.field.id + ' ' + fine.fileModel + ': ' + fine.packed.filter(Boolean).length + '/' + fine.times.length + ' pictures in ' +
      (Date.now() - t1) + ' ms, ' + fine.fromStore + ' from the store');
  }, function (err) { console.warn('[anim] ' + fine.field.id + ' ' + fine.fileModel + ': ' + err); });
}

/** The map moved: the models the view picks now, if they changed. Those
    leaving keep their pictures (animFineKeep), those coming take theirs
    back or read them; the picture shown is drawn again with them. */
function animFineMoved() {
  if (!anim || !animFine || !animFineAuto) return;
  var ids = animPickFines();
  if (ids.join() === animFineModels.join()) return;
  animSetFines(ids);
}

function animSetFines(ids) {
  animFineModels = ids;
  if (!anim) return;
  var shown = 0;
  anim.group.tracks.forEach(function (t) {
    if (!animFineField(t.id)) return;
    var frames = t.frames, old = frames.fines || [];
    var fines = ids.map(function (model) {
      var here = old.filter(function (f) { return f.fileModel === model; })[0];
      if (here) return here;
      var fine = animMakeFine(t.id, model, frames, animFineKeep.take(t.id + '|' + model));
      animLoadFine(fine);
      return fine;
    });
    old.forEach(function (f) { if (fines.indexOf(f) < 0) animFineKeep.put(f); });
    frames.fines = fines;
    shown += fines.reduce(function (n, f) { return n + WidgetAnim.heldBytes(f); }, 0);
  });
  animFineKeep.trim(shown);
  console.log('[anim] regional models: ' + (ids.join(', ') || 'none') + '; kept out of view: ' +
    animFineKeep.kept.map(function (f) { return f.keepKey || f.fileModel; }).join(', '));
  var p = anim.player;
  if (p.index >= 0 && !p.playing) p.seek(p.index);
}

/** New pictures for pastH hours before now and futureH after, one every
    stepH hours (WidgetAnim.STEP_H, the files' own; 1 for the radar and
    satellite alone, no layer then), those already read taken over; the
    time shown stays, now moves on with the clock. span { start, end } (ms): from the one to the other
    instead, the ends themselves (the range of the radar or satellite). */
function animLoad(pastH, futureH, stepH, span) {
  // Layers fading out belong to the old range: they go at once.
  anim.switcher.flush();
  var old = anim.group;
  anim.nowMs = Date.now();
  anim.stepH = stepH || WidgetAnim.STEP_H;
  if (span) {
    pastH = Math.max(0, Math.ceil((anim.nowMs - span.start) / 3600e3));
    futureH = Math.max(0, Math.ceil((span.end - anim.nowMs) / 3600e3));
  }
  anim.pastH = pastH;
  anim.futureH = futureH;
  // A range of the radar or satellite stays when a forecast layer comes:
  // then on the files' steps that cover it.
  anim.span = span || null;
  var ft = span ? (anim.stepH >= WidgetAnim.STEP_H ? WidgetAnim.alignedTimes(span.start, span.end, anim.nowMs, anim.stepH)
    : WidgetAnim.spanTimes(span.start, span.end, anim.nowMs, anim.stepH))
    : WidgetAnim.frameTimes(anim.nowMs, pastH, futureH, anim.stepH);
  anim.group = anim.player.frames = anim.player.layer = new WidgetAnim.Group(ft.times, ft.now);
  anim.group.onTime = animOverlayTime;
  // The API's hours count from the present hour, the frames from the
  // nearest 3-hour step: one step more each way covers them.
  anim.api.setHours(pastH + WidgetAnim.STEP_H, futureH + WidgetAnim.STEP_H);
  if (old) old.tracks.forEach(function (t) { animTrack(t.id, t.layer, t.frames); t.layer.reload(); });
  var keep = old ? WidgetAnim.keptIndex(old.times, old.nowIndex, anim.player.index, ft.times, ft.now) : ft.now;
  anim.player.index = -1;
  anim.player.show(keep);
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
    if (anim.stepH !== WidgetAnim.STEP_H) animLoad(anim.pastH, anim.futureH, WidgetAnim.STEP_H, anim.span);
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
  animOverlaysRaise();
}

/** Start with the layers of `layers` ({ temperature: true, wind: false }),
    the temperature alone by default. true once started, false when it
    cannot be, 'wait' while the map's style loads (it takes no layer
    before): the widget asks again. */
window.animStart = function (pastH, futureH, layers) {
  var m = _widgetAdapter.getMap();
  if (!m || !window.animAvailable) return false;
  if (anim) return true;
  if (_widgetAdapter.isReady && !_widgetAdapter.isReady()) return 'wait';
  if (!animRestyleHooked && _widgetAdapter.onRestyle) { _widgetAdapter.onRestyle(animRestyle); animRestyleHooked = true; }
  if (!animMoveHooked) { m.on('moveend', animFineMoved); animMoveHooked = true; }
  if (tempLayer) { tempLayer.remove(); tempLayer = null; }
  if (windLayer) windLayer.setActive(false);
  anim = {
    group: null, player: new WidgetAnim.Player(null, null), movingStep: 1,
    switcher: new WidgetAnim.Switcher({ onGone: function (key) { if (anim && anim.group) anim.group.removeGhost(key); } }),
    // Not stored: a grid of the whole range would not fit in localStorage.
    api: new WidgetWind.WindSource({ storage: null, world: false })
  };
  anim.player.slow = animSlow;
  anim.player.stops = animStops;
  anim.player.loop = animLoop;
  animLoad(pastH == null ? 24 : pastH, futureH == null ? 48 : futureH);
  _widgetAdapter.setFramesHidden(true);
  document.body.classList.add('lv-anim');
  legendGather();
  layers = layers || { temperature: true };
  for (var id in ANIM_LAYERS) if (layers[id]) animSetLayer(id, true);
  creditOpenMeteo();
  animOverlaysStart();
  return true;
};

window.animSetRange = function (pastH, futureH, stepH) { if (anim) animLoad(pastH, futureH, stepH); };
/** From startMs to endMs (the range of the radar or satellite alone), a picture every stepH hours between. */
window.animSetSpan = function (startMs, endMs, stepH) { if (anim) animLoad(0, 0, stepH, { start: startMs, end: endMs }); };
/** The widget's place changed: the map moves there, nothing reloaded. */
window.setHome = function (lat, lon) {
  config.view.lat = lat;
  config.view.lon = lon;
  if (_widgetAdapter.setHome) _widgetAdapter.setHome(lat, lon);
};
window.animSetLayer = function (id, on) { if (anim) animSetLayer(id, !!on); };

var animMoveHooked = false;

window.animStop = function () {
  if (!anim) return;
  if (animFineKeep) animFineKeep.clear();
  anim.player.stop();
  anim.group.tracks.forEach(function (t) { t.frames.stop(); t.layer.remove(); });
  anim.switcher.clear();
  animOverlaysStop();
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
window.animStep = function (dir) { if (anim) anim.player.step(dir, anim.stepH); };
window.animStepFile = function (dir) { if (anim) anim.player.stepFile(dir); };
/** Home (-1) and End (1): the first or the last picture of the range. */
window.animToEnd = function (dir) { if (anim) anim.player.toEnd(dir); };
// Paused steps of h hours (3: one frame).
/** A step of h hours (a fraction for minutes) back (-1) or ahead (1). */
window.animStepHours = function (dir, h) { if (anim) anim.player.step(dir, anim.stepH / h); };
// The step buttons follow the time shown: the radar's 10 min in its range,
// the satellite's hour in its range, where they are on; the files' step
// elsewhere (WidgetAnimRadar.stepTime).
function animStepBaseH() { return anim.stepH < 1 ? 1 / 6 : anim.stepH < 3 ? 1 : 3; }
function animStepSources(baseH) {
  if (!animOverlays || typeof WidgetAnimRadar === 'undefined') return [];
  return ['radar', 'satellite'].map(function (k) { return animOverlays[k]; }).filter(function (o) {
    return o.on && o.range() && o.gapMs < baseH * 3600e3;
  }).map(function (o) {
    var r = o.range();
    return { start: r.start, end: r.end, last: o.lastTime(), gap: o.gapMs };
  });
}
/** The step in hours of the button back (-1) or ahead (1) at the time shown. */
function animButtonStepH(dir) {
  if (!anim || anim.player.index < 0 || typeof WidgetAnimRadar === 'undefined') return anim ? animStepBaseH() : null;
  var baseH = animStepBaseH(), p = anim.player;
  return WidgetAnimRadar.stepHours(anim.group.timeAt(p._base()), dir, baseH, animStepSources(baseH));
}
window.animStepButton = function (dir) {
  if (!anim) return;
  var p = anim.player, g = anim.group, baseH = animStepBaseH(), times = g.times, last = times.length - 1;
  var sources = typeof WidgetAnimRadar === 'undefined' ? [] : animStepSources(baseH);
  if (!sources.length || p._round(dir, function () { return true; }) >= 0) { p.step(dir, anim.stepH / baseH); return; }
  // Where the files' step would land, as Player.step counts it.
  var perFrame = anim.stepH / baseH, base = p._base() * perFrame;
  var k = dir > 0 ? Math.floor(base + 1e-6) + 1 : Math.ceil(base - 1e-6) - 1;
  var t = g.timeAt(p._base()), to = WidgetAnimRadar.stepTime(t, dir, g.timeAt(Math.max(0, Math.min(last, k / perFrame))), sources);
  var pos = last;
  for (var i = 0; i < last; i++) if (to < times[i + 1]) { pos = i + Math.max(0, to - times[i]) / (times[i + 1] - times[i]); break; }
  p.play(false);
  p.seek(Math.max(0, Math.min(last, pos)));
};
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
  if (anim) animLoad(anim.pastH, anim.futureH, anim.stepH);
};

/** The finer models drawn (ids of WidgetModels), put in their order of
    priority, finest first, unknown ids left out; null gives the choice
    back to the view. The list drawn. */
window.animSetFineModels = function (ids) {
  animFineAuto = !ids;
  var list = ids ? WidgetModels.list.map(function (m) { return m.id; }).filter(function (id) { return ids.indexOf(id) >= 0; })
    : anim ? animPickFines() : [];
  if (anim) animSetFines(list); else animFineModels = list;
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
  var kept = {};
  if (animFineKeep) animFineKeep.kept.forEach(function (f) { kept[f.fileModel] = WidgetAnim.heldBytes(f); });
  // How the temperature is drawn: by the chip, the tiles, or the tiles after the chip failed.
  var tt = anim && anim.group.track('temperature'), tl = tt && tt.layer, draw = null;
  if (tl) draw = tl._gl && tl._gl.failed ? 'tiles (no shader)' : tl._gpuOn ? 'chip, ' + (tl._shown.fields.length - 1) + ' finer' : 'tiles';
  return { read: Object.assign({}, WidgetOpenData.traffic), held: held, kept: kept, fine: animFine, models: animFineModels, draw: draw };
};

/** { times (ms), ready, failed, now, index (a position between frames),
    time (ms) of that position, fromFile (a frame as read, not worked out),
    playing, layers ({ id: on }), models (short names of the models
    drawn: the global one, then the finer ones in view) } for the QML bar. */

window.animState = function () {
  if (!anim) return null;
  var g = anim.group, layers = {};
  for (var id in ANIM_LAYERS) layers[id] = !!g.track(id);
  return {
    times: g.times, now: g.nowIndex, index: anim.player.index, playing: anim.player.playing,
    time: anim.player.index >= 0 ? g.timeAt(anim.player.index) : null,
    fromFile: anim.player.index >= 0 && g.isFile(anim.player.index),
    ready: g.times.map(function (_, i) { return g.ready(i); }), failed: g.failed(), layers: layers,
    radar: animOverlayState('radar'), satellite: animOverlayState('satellite'),
    models: WidgetModels.labels(_windOpen ? _windOpen.model : 'ecmwf_ifs025', animFine ? animFineModels : []),
    loop: animLoop, windLevel: animWindLevel,
    stepBack: animButtonStepH(-1), stepAhead: animButtonStepH(1)
  };
};

// === LEGENDS AND THE WIDGET'S LAYER COLUMN ===
// The color legends of the layers (class lv-legend, their layer in
// data-layer), each made by its own layer in the map's box, go into one
// column at the top left while the animation runs (overrides.css). Hidden
// legends stay hidden when their layer makes them again.
var legendHidden = {};
var legendStack = null;
function legendGather() {
  var host = document.getElementById('lv-map');
  if (!host || !document.body.classList.contains('lv-anim')) return;
  if (!legendStack || legendStack.parentNode !== host) {
    legendStack = document.createElement('div');
    legendStack.id = 'lv-legend-stack';
    host.appendChild(legendStack);
  }
  host.querySelectorAll('.lv-legend').forEach(function (el) {
    if (el.parentNode !== legendStack) legendStack.appendChild(el);
    var off = !!legendHidden[el.dataset.layer || ''];
    if (el.classList.contains('lv-legend-off') !== off) el.classList.toggle('lv-legend-off', off);
  });
}
/** Show (on) or hide the color legend of layer id. */
window.animSetLegend = function (id, on) {
  legendHidden[id] = !on;
  legendGather();
};
// A layer puts its legend in the map's box: only its children are watched
// (the whole page changed on every frame of the readout and the markers).
if (typeof MutationObserver !== 'undefined' && document.getElementById('lv-map')) {
  new MutationObserver(legendGather).observe(document.getElementById('lv-map'), { childList: true });
}

/** How much of the map's right the widget's layer column covers (px): the
    map's own buttons there slide left by as much. */
window.animSetRightInset = function (px) {
  document.documentElement.style.setProperty('--aww-inset', Math.max(0, +px || 0) + 'px');
};
/** How far down the legends start (px): under the widget's date when the
    map is too narrow for both side by side. */
window.animSetLegendTop = function (px) {
  document.documentElement.style.setProperty('--aww-legend-top', Math.max(0, +px || 0) + 'px');
};

// === RADAR AND SATELLITE OVER THE ANIMATION (glue-anim-radar.js) ===
// Their images from the LibreWXR catalog, each shown while the time of the
// animation is in its range; the animation slows down through the radar's
// (WidgetAnimRadar.slowFactor). Their tile options mirror the viewer's,
// and changing one here changes the viewer's too.
var animRadarOpts = {
  color: CURRENT_COLOR, smooth: SMOOTH_INIT, snow: SNOW_INIT, format: FORMAT_INIT, tileSize: TILESIZE_INIT,
  arrows: ARROWS_ON, lightning: false, alerts: ALERTS_INIT, cells: CELLS_INIT
};
var animOverlays = null;       // { radar, satellite } (WidgetAnimRadar.Overlay)
var animCatalogData = null;
var animCatalogTimer = null;
var ANIM_CATALOG_MS = 5 * 60e3;

function animTileOpts() {
  var o = animRadarOpts, size = o.tileSize === 'auto' ? (window.devicePixelRatio >= 1.5 ? 512 : 256) : parseInt(o.tileSize, 10) || 256;
  return {
    size: size, color: o.color, smooth: o.smooth, snow: o.snow, format: o.format,
    arrows: o.arrows ? (currentTheme() === 'dark' ? 'light' : 'dark') : '', cells: o.cells || '', lightning: o.lightning ? 'bolts' : ''
  };
}

function animOverlayUrl(kind) {
  var o = animTileOpts();
  return function (frame) { return WidgetAnimRadar.tileUrl(API_BASE, frame, kind, o); };
}

/** The satellite's last image stays on until the end of the radar's
    range: it comes about an hour late, and would be gone at now. */
function animSatUntil() {
  var r = animOverlays && animOverlays.radar.range();
  return r ? r.end : null;
}

function animOverlaysStart() {
  if (typeof WidgetAnimRadar === 'undefined') return;
  if (!animOverlays) {
    animOverlays = {
      radar: new WidgetAnimRadar.Overlay(_widgetAdapter, { kind: 'radar', gapMs: WidgetAnimRadar.RADAR_GAP, opacity: 0.8, fadeMs: 400, url: animOverlayUrl('radar') }),
      satellite: new WidgetAnimRadar.Overlay(_widgetAdapter, { kind: 'satellite', gapMs: WidgetAnimRadar.SAT_GAP, until: animSatUntil, opacity: 0.6, fadeMs: 400, url: animOverlayUrl('satellite') })
    };
  }
  animCatalog();
  if (!animCatalogTimer) animCatalogTimer = setInterval(animCatalog, ANIM_CATALOG_MS);
}

function animOverlaysStop() {
  if (animCatalogTimer) { clearInterval(animCatalogTimer); animCatalogTimer = null; }
  if (animOverlays) { animOverlays.radar.setOn(false); animOverlays.satellite.setOn(false); }
  _widgetAdapter.setLines('satellite', false);
  _widgetAdapter.setLines('radar', false);
}

function animCatalog() {
  return fetch(API_BASE + '/public/weather-maps.json', { cache: 'no-store' }).then(function (r) {
    if (!r.ok) throw new Error('catalog ' + r.status);
    return r.json();
  }).then(function (c) {
    animCatalogData = c;
    if (!animOverlays) return;
    animOverlays.radar.setFrames(WidgetAnimRadar.framesOf(c, 'radar'));
    animOverlays.satellite.setFrames(WidgetAnimRadar.framesOf(c, 'satellite'));
  }).catch(function (err) { console.warn('[anim] radar catalog: ' + err); });
}

/** The time of the picture shown: the radar and satellite follow. */
function animOverlayTime(ms) {
  if (!animOverlays) return;
  animOverlays.satellite.show(ms);
  animOverlays.radar.show(ms);
}

function animOverlaysRaise() {
  if (!animOverlays) return;
  ['satellite', 'radar'].forEach(function (k) { var o = animOverlays[k]; if (o.shown) o._put(o.shown); });
}

/** With no layer drawn between frames (the radar and satellite alone),
    the times their images change: the play goes from one to the next
    without the pictures in between. null while a layer is on or fading. */
function animStops() {
  if (!anim || !animOverlays || anim.group.tracks.length || anim.group.ghosts.length) return null;
  var out = [];
  ['radar', 'satellite'].forEach(function (k) {
    var o = animOverlays[k], r = o.on && o.range();
    if (!r) return;
    o.frames.forEach(function (f) { out.push(f.time * 1000); });
    out.push(r.end);
  });
  return out;
}

/** How many times slower the animation goes at ms (the radar's range, while it is on). */
function animSlow(ms) {
  // Frames already 10 minutes apart (the radar alone): no slowing down.
  if (anim && anim.stepH < 1) return 1;
  var r = animOverlays && animOverlays.radar;
  return r && r.on ? WidgetAnimRadar.slowFactor(ms, r.range()) : 1;
}

function animOverlayState(kind) {
  var o = animOverlays && animOverlays[kind];
  if (!o) return null;
  var r = o.range();
  // Where the radar's nowcast starts: the bar of its range is paler from there.
  var nc = kind === 'radar' && animCatalogData && animCatalogData.radar && animCatalogData.radar.nowcast;
  return {
    on: o.on, start: r ? r.start : null, end: r ? r.end : null, last: o.lastTime(), time: o.shownTime(), opacity: Math.round(o.opacity * 100),
    forecastFrom: nc && nc.length ? nc[0].time * 1000 : null
  };
}

/** The radar over the animation; the coasts and borders come over it. */
window.animSetRadar = function (on) {
  if (!animOverlays) return;
  animOverlays.radar.setOn(on);
  _widgetAdapter.setLines('radar', !!on);
};
/** The satellite over the animation; the coasts and borders come over it. */
window.animSetSatellite = function (on) {
  if (!animOverlays) return;
  animOverlays.satellite.setOn(on);
  _widgetAdapter.setLines('satellite', !!on);
};

/** The color schemes of the radar, [[id, name]], from the catalog. */
window.animRadarSchemes = function () {
  var list = animCatalogData && animCatalogData.radar && animCatalogData.radar.colorSchemes || [];
  return list.map(function (c) { return [c.id, c.name]; });
};

/** A tile option of the radar (color, smooth, snow, lightning, arrows,
    alerts, format, tileSize, cells: the storm cells' theme, 'light',
    'dark' or '' for none), for the animation's images and the viewer's. */
window.animSetRadarOption = function (key, value) {
  if (!(key in animRadarOpts)) return;
  animRadarOpts[key] = value;
  var apply = {
    color: function () { viewer.setColorScheme(value); },
    smooth: function () { viewer.setSmooth(!!value); },
    snow: function () { viewer.setSnow(!!value); },
    lightning: function () { viewer.setLightning(value ? 'bolts' : ''); },
    arrows: function () { window.setArrows(!!value); },
    alerts: function () { viewer.setAlertsEnabled(!!value); },
    format: function () { viewer.setFormat(value); },
    tileSize: function () { viewer.setTileSize(String(value)); },
    cells: function () { window.setCells(value || ''); }
  }[key];
  apply();
  if (!animOverlays || key === 'alerts') return;
  animOverlays.radar.setUrl(animOverlayUrl('radar'));
  if (key === 'format' || key === 'tileSize') animOverlays.satellite.setUrl(animOverlayUrl('satellite'));
};

window.animRadarOptions = function () { return Object.assign({}, animRadarOpts); };

// The opacity setters of the layers by id, in percent: the page's own,
// and those of the spikes injected after it (looked up when called).
var ANIM_OPACITY = {
  temperature: function (p) { window.setTempOpacity(p); },
  wind: function (p) {
    animWindOpacity = p / 100;
    var t = anim && anim.group.track('wind');
    if (t && t.layer.setOpacity) t.layer.setOpacity(animWindOpacity);
  },
  radar: function (p) { if (animOverlays) animOverlays.radar.setOpacity(p / 100); },
  satellite: function (p) { if (animOverlays) animOverlays.satellite.setOpacity(p / 100); },
  pressure: 'presSetOpacity', isobars: 'isoSetOpacity', airquality: 'aqSetOpacity', precipitation: 'precipSetOpacity',
  clouds: 'cloudSetOpacity', humidity: 'humiditySetOpacity', dewpoint: 'dewpointSetOpacity'
};

/** Layer id's opacity, in percent (0 to 100). */
window.animSetOpacity = function (id, pct) {
  var f = ANIM_OPACITY[id], p = Math.max(0, Math.min(100, Math.round(+pct)));
  if (!f || !isFinite(p)) return;
  if (typeof f === 'string') { if (typeof window[f] === 'function') window[f](p); }
  else f(p);
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

/** Where the pointer is on the map ({ lat, lng }), null when it is off the
    map, past the Mercator edge, or off the globe. */
function readoutPoint() {
  var m = _widgetAdapter.getMap();
  if (!m || !readout.known) return null;
  var c = m.getContainer().getBoundingClientRect(), x = readout.x - c.left, y = readout.y - c.top;
  if (x < 0 || y < 0 || x > c.width || y > c.height) return null;
  var ll = m.unproject([x, y]);
  if (!ll || !isFinite(ll.lat) || Math.abs(ll.lat) > 85) return null;
  var back = m.project(ll);
  if (Math.abs(back.x - x) > 1 || Math.abs(back.y - y) > 1) return null;   // off the globe
  return ll;
}
/** One line of the readout: an icon in a color, then its text. */
function readoutRow(icon, color, text) {
  return '<div class="lv-readout-row"><span class="lv-readout-icon" style="color:' + color + '">' + icon + '</span><span>' + text + '</span></div>';
}
/** The lines the other layers add to the readout (addReadout), in turn. */
var readoutLines = [];
/** Adds a line to the readout for layer track() when it shows a picture:
    line(track, latLng) gives its html, '' for none. */
function addReadout(track, line) { readoutLines.push({ track: track, line: line }); }

/** The lines of the box at the pointer, '' where nothing is drawn. */
function readoutHtml() {
  var ll = readoutPoint();
  if (!ll) return '';
  var layers = readoutLayers();
  var hasWind = !!(layers.wind && layers.wind.valueAt), hasTemp = !!(layers.temp && layers.temp.valueAt);
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
  var html = lines.map(function (l) { return '<div class="lv-readout-row">' + l + '</div>'; }).join('');
  readoutLines.forEach(function (r) {
    var t = r.track();
    if (t && t.layer.grid) html += r.line(t, ll) || '';
  });
  return html;
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
// The animation's keys, told to the widget: once the map has the keyboard
// (clicked, or given it when the popup opens), the widget's own shortcuts
// get no key. Before MapLibre (capture), so the arrows step and do not pan.
var ANIM_LAYER_KEYS = { R: 'radar', S: 'satellite', V: 'wind', T: 'temperature', P: 'precipitation',
  N: 'clouds', B: 'pressure', I: 'isobars', H: 'humidity', D: 'dewpoint', A: 'airquality' };
// Ctrl and + or -, from the widget: the map zooms as with its buttons.
window.animZoom = function (d) {
  var m = _widgetAdapter ? _widgetAdapter.getMap() : null;
  if (m) { if (d > 0) m.zoomIn(); else m.zoomOut(); }
};
window.animKeyFor = function (e) {
  if (!anim) return null;   // no animation (the Leaflet page): the map keeps its keys
  var t = e.target, tag = t && t.tagName;
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (t && t.isContentEditable)) return null;
  if (e.altKey || e.metaKey) return null;
  if (e.key === 'F11') return 'fullscreen';
  // 0 and + need Shift on some layouts (AZERTY). Ctrl and + or -: zoom.
  if (e.ctrlKey && (e.key === '+' || e.key === '=' || e.key === '-')) return 'zoom:' + (e.key === '-' ? -1 : 1);
  if (!e.ctrlKey && e.key === '0') return 'now';
  if (!e.ctrlKey && (e.key === '+' || e.key === '-')) return 'speed:' + (e.key === '-' ? -1 : 1);
  if (e.shiftKey) return null;
  if (e.key === ' ' && !e.ctrlKey) return e.repeat ? '' : 'play';
  if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') return (e.ctrlKey ? 'file:' : 'step:') + (e.key === 'ArrowLeft' ? -1 : 1);
  if ((e.key === 'PageUp' || e.key === 'PageDown') && !e.ctrlKey) return 'file:' + (e.key === 'PageUp' ? -1 : 1);
  if ((e.key === 'Home' || e.key === 'End') && !e.ctrlKey) return 'end:' + (e.key === 'Home' ? -1 : 1);
  // One letter per layer (the widget's layerKeys), L for the loop.
  if (!e.ctrlKey && e.key.length === 1) {
    var c = e.key.toUpperCase();
    if (c === 'L') return 'loop';
    var id = ANIM_LAYER_KEYS[c];
    if (id) return 'layer:' + id;
  }
  return null;
};
document.addEventListener('keydown', function (e) {
  var k = window.animKeyFor(e);
  if (k === null) return;
  e.preventDefault();
  e.stopPropagation();
  if (k) console.log('[keys] ' + k);
}, true);
document.addEventListener('keydown', function (e) {
  // Esc in the page is told to the widget (its help panel): the map takes
  // the keys once clicked.
  if (e.key === 'Escape') console.log('[keys] escape');
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
