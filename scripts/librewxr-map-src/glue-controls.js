// ==========================================================================
// Glue script 3: create the viewer and expose the QML-facing window.* API.
// ==========================================================================
var _widgetAdapter = new WidgetLeafletAdapter();

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
  m.invalidateSize(false);
  m.panBy([1, 0], { animate: false });
  m.panBy([-1, 0], { animate: false });
  // Timeout rearm: the engine's moveend restarts a quiet background preload,
  // which the cancelling 1px nudge (never a real view change) safely ignores.
  setTimeout(function () { m.invalidateSize(false); }, 400);
};

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
