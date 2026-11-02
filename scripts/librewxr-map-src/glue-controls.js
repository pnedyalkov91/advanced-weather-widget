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

/** Pictures of layer id for the range of the animation, those of `reuse`
    (the same layer's Frames of another range) taken over. */
function animTrack(id, layer, reuse) {
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
  if (reuse) reuse.stop();
  anim.group.add(id, frames, layer);
  var t0 = Date.now();
  frames.load().then(function () {
    console.log('[anim] ' + id + ': ' + frames.packed.filter(Boolean).length + '/' + frames.times.length + ' pictures in ' +
      (Date.now() - t0) + ' ms, ' + frames.fromStore + ' from the store');
  }, function (err) { console.warn('[anim] ' + id + ': ' + err); });
}

/** New pictures for pastH hours before now and futureH after, those
    already read taken over; the time shown stays. */
function animLoad(pastH, futureH) {
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

/** Switch layer id of the animation on or off. */
function animSetLayer(id, on) {
  var t = anim.group.track(id);
  if (!on && t) {
    t.frames.stop();
    t.layer.remove();
    anim.group.remove(id);
  } else if (on && !t && ANIM_LAYERS[id]) {
    var layer = ANIM_LAYERS[id](_widgetAdapter.getMap());
    if (!layer) return;
    if (layer.setMoving) layer.setMoving(anim.player.playing);
    animTrack(id, layer, null);
    if (anim.player.index >= 0) anim.player.seek(anim.player.index);
  }
}

/** Start with the layers of `layers` ({ temperature: true, wind: false }),
    the temperature alone by default. */
window.animStart = function (pastH, futureH, layers) {
  var m = _widgetAdapter.getMap();
  if (!m || !window.animAvailable) return false;
  if (anim) return true;
  if (tempLayer) { tempLayer.remove(); tempLayer = null; }
  if (windLayer) windLayer.setActive(false);
  anim = {
    group: null, player: new WidgetAnim.Player(null, null), movingStep: 1,
    // Not stored: a grid of the whole range would not fit in localStorage.
    api: new WidgetWind.WindSource({ storage: null, world: false })
  };
  animLoad(pastH || 24, futureH || 48);
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
  anim.group.tracks.slice().forEach(function (t) { animSetLayer(t.id, false); });
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
  // The new projection is in place on the next frames: rebuild the wind table then.
  if (windLayer && windLayer.refresh) setTimeout(function () { if (windLayer) windLayer.refresh(); }, 300);
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
