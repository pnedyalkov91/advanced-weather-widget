// ==========================================================================
// Glue script 2: MapLibre adapter (adapted from examples/src/maplibre.html.js).
// Implements the viewer-core.js adapter contract with MapLibre GL JS 6,
// wired to the widget's base-map list, plus what glue-controls.js needs of a
// map whatever its library: resize, repaint nudge, tile state, wind layer.
// ==========================================================================
var WidgetMapLibreAdapter = function (maplibregl) {
  var map = null;
  var styleReady = false;      // set at the first 'load', stays set
  var maxZoom = 12;
  var frameSeq = 0;
  var frameRegistry = [];      // runtime frame entries, creation order
  var pendingReady = {};       // source id -> finishers of onLayerReady still waiting
  var alertsEntry = null;      // { geojson } while the alerts overlay is on
  var popupHandler = null;
  var alertClickCb = null;
  var appliedKey = null;       // base map now drawn
  var desired = null;          // { key, style } wanted
  var swapInProgress = false;
  var projection = PROJECTION_INIT;   // 'flat' | 'globe'
  var skyTheme = PARAMS.get('theme') === 'light' ? 'light' : 'dark';

  // The widget counts zoom levels on 256 px tiles, as Leaflet does; MapLibre
  // counts them on 512 px tiles, one level lower for the same scale.
  function toGl(z) { return z - 1; }
  function fromGl(z) { return z + 1; }

  // MapLibre has no {s} subdomain placeholder: list the hosts instead.
  function tileUrls(url) {
    if (url.indexOf('{s}') < 0) return [url];
    return ['a', 'b', 'c'].map(function (s) { return url.replace('{s}', s); });
  }

  // A base-map entry of the widget's list as a MapLibre style: vector
  // entries by their style URL, raster ones as a one-layer style. Inverted
  // entries get the look of the Leaflet page's CSS filter (invert, hue
  // turned back, a little darker and duller). The swapped brightness bounds
  // invert each channel, which turns parks purple and roads blue: the hue
  // rotation brings them back to green and orange.
  function baseFor(theme) {
    var entry = resolveBg(BG_CURRENT, theme);
    if (entry.vector && entry.styleUrl) return { key: entry.styleUrl, style: entry.styleUrl };
    var url = entry.url || FALLBACK_BG[theme].url;
    var paint = entry.invert ? {
      'raster-hue-rotate': 180,
      'raster-brightness-min': 0.9, 'raster-brightness-max': 0,
      'raster-contrast': -0.1, 'raster-saturation': -0.2
    } : {};
    return {
      key: url + (entry.invert ? '#inverted' : ''),
      style: {
        version: 8,
        sources: { 'lv-base': { type: 'raster', tiles: tileUrls(url), tileSize: 256, maxzoom: entry.maxZoom || 19, attribution: entry.attribution || '' } },
        layers: [{ id: 'lv-base', type: 'raster', source: 'lv-base', paint: paint }]
      }
    };
  }

  function firstRadarFrameLayerId() {
    var layers = map.getStyle().layers;
    for (var i = 0; i < layers.length; i++) {
      if (layers[i].id.indexOf('lv-layer-radar-') === 0) return layers[i].id;
    }
    return undefined;
  }

  // First layer the page added over the base map and its day and night:
  // satellite frames go right below it.
  function firstRuntimeLayerId() {
    var layers = map.getStyle().layers;
    for (var i = 0; i < layers.length; i++) {
      var id = layers[i].id;
      if (id.indexOf('lv-') === 0 && id !== 'lv-base' && id !== 'lv-night') return id;
    }
    return undefined;
  }

  // A percentage from the widget, held within 0..100; null if unreadable.
  function percent(v) {
    var n = parseFloat(v);
    return isNaN(n) ? null : Math.max(0, Math.min(100, n));
  }

  // Day and night (glue-earth.js): raster tiles the page draws itself, from
  // the Sun and the setting, through a tile protocol of its own. Black over
  // the night, fading in over the 18 degrees of twilight down to the
  // widget's darkness (percent of black, 40 by default); on a dark map, a
  // light veil over the day, fading in the same way. One layer for the GPU
  // where nested areas made the night side 19 translucent layers deep (38
  // with the day), and tiles, which the globe extends to the poles as it
  // does the base map's: an image source stops at 85 degrees there. At most
  // 16 tiles of 128 px (zoom 2, smooth enough for a fade over 18 degrees),
  // drawn again once a minute. Right over the base map, under the
  // satellite, the alerts and the radar. The map's light stands at the Sun,
  // so the atmosphere glows over the day side; with day and night off it
  // comes from the viewer and the globe glows evenly.
  var SHADE_TILE = 128, SHADE_MAXZOOM = 2, DAY_VEIL = 0.07;
  var EVEN_LIGHT = { anchor: 'viewport', position: [1, 0, 0] };
  var nightDepth = percent(NIGHTDEPTH_INIT);
  if (nightDepth === null) nightDepth = 40;
  var dayNight = DAYNIGHT_INIT;
  var sunTimer = null;
  var shade = { sun: WidgetEarth.subsolarPoint(new Date()), version: 0 };
  maplibregl.addProtocol('lvshade', function (params) {
    var m = /^lvshade:\/\/\d+\/(\d+)\/(\d+)\/(\d+)/.exec(params.url);
    var img = WidgetEarth.shadeTile(shade.sun, { z: +m[1], x: +m[2], y: +m[3] }, SHADE_TILE,
      nightDepth / 100, skyTheme === 'dark' ? DAY_VEIL : 0);
    return createImageBitmap(new ImageData(img, SHADE_TILE, SHADE_TILE)).then(function (bitmap) {
      return { data: bitmap };
    });
  });
  function shadeTiles() { return ['lvshade://' + shade.version + '/{z}/{x}/{y}']; }
  // New tiles for the Sun now, the darkness and the theme; the shown ones
  // stay until they arrive.
  function drawShade(sun) {
    shade.sun = sun;
    shade.version++;
    var src = map.getSource('lv-night');
    if (src) src.setTiles(shadeTiles());
  }
  // The shade the setting asks for; after a style swap too.
  function addSunLayers() {
    if (!dayNight) {
      if (map.getLayer('lv-night')) map.removeLayer('lv-night');
      if (map.getSource('lv-night')) map.removeSource('lv-night');
      return;
    }
    if (!map.getSource('lv-night')) {
      map.addSource('lv-night', { type: 'raster', tiles: shadeTiles(), tileSize: 256, maxzoom: SHADE_MAXZOOM });
    }
    if (!map.getLayer('lv-night')) {
      map.addLayer({ id: 'lv-night', type: 'raster', source: 'lv-night', paint: { 'raster-fade-duration': 0 } },
        firstRuntimeLayerId());
    }
  }
  function moveSun() {
    var sun = WidgetEarth.subsolarPoint(new Date());
    map.setLight(dayNight ? { anchor: 'map', position: WidgetEarth.sunLightPosition(sun) } : EVEN_LIGHT);
    drawShade(sun);
  }
  function applyDayNight() {
    addSunLayers();
    moveSun();
    // Not while the map moves: the tiles wait for the next minute.
    if (!sunTimer) sunTimer = setInterval(function () { if (!document.hidden && !swapInProgress && !moving) moveSun(); }, 60000);
  }

  // The widest zoom shows the whole Earth (glue-earth.js): the world fills
  // the map's height when flat, the globe its smaller side. It depends on
  // the map's size only; MapLibre takes no minimum below -2.
  function fitMinZoom() {
    var c = map.getContainer();
    var z = WidgetEarth.wholeEarthZoom(projection, c.clientWidth, c.clientHeight);
    if (z === null) return;
    z = Math.max(-2, Math.min(z, map.getMaxZoom()));
    if (Math.abs(z - map.getMinZoom()) > 0.001) map.setMinZoom(z);
  }

  // Alerts sit right below the radar frames, above satellite frames.
  function assertAlertsPosition() {
    if (!map.getLayer('lv-alerts-fill') || !map.getLayer('lv-alerts-line')) return;
    var radar = firstRadarFrameLayerId();
    map.moveLayer('lv-alerts-fill', radar);
    map.moveLayer('lv-alerts-line', radar);
  }

  function addFrameEntry(entry) {
    if (!map.getSource(entry.sourceId)) {
      map.addSource(entry.sourceId, { type: 'raster', tiles: [entry.url], tileSize: 256, maxzoom: entry.maxZoom });
    }
    if (map.getLayer(entry.layerId)) return;
    map.addLayer({
      id: entry.layerId,
      type: 'raster',
      source: entry.sourceId,
      layout: { visibility: entry.held ? 'none' : 'visible' },
      paint: {
        'raster-opacity': entry.opacity,
        'raster-opacity-transition': { duration: 0, delay: 0 },
        'raster-fade-duration': 0
      }
    }, entry.kind === 'satellite' ? firstRuntimeLayerId() : undefined);
    if (entry.kind !== 'satellite') assertAlertsPosition();
  }

  // Severity colors come from the engine's style function, computed once per
  // feature into its properties, as the Leaflet page styles each path.
  function addAlertsLayers() {
    if (map.getLayer('lv-alerts-fill')) return;
    if (!map.getSource('lv-alerts')) map.addSource('lv-alerts', { type: 'geojson', data: alertsEntry.geojson });
    var before = firstRadarFrameLayerId();
    map.addLayer({
      id: 'lv-alerts-fill', type: 'fill', source: 'lv-alerts',
      paint: { 'fill-color': ['get', '__fillColor'], 'fill-opacity': ['get', '__fillOpacity'] }
    }, before);
    map.addLayer({
      id: 'lv-alerts-line', type: 'line', source: 'lv-alerts',
      paint: { 'line-color': ['get', '__color'], 'line-width': ['get', '__weight'] }
    }, before);
  }

  function registerAlertsPopup() {
    if (popupHandler) return;
    popupHandler = function (e) {
      var hits = map.queryRenderedFeatures(e.point, { layers: ['lv-alerts-fill'] });
      var f = hits && hits[0];
      if (!f || !f.properties || !f.properties.__popup) return;
      new maplibregl.Popup({ closeButton: true, maxWidth: '300px' })
        .setLngLat(e.lngLat).setHTML(f.properties.__popup).addTo(map);
      if (alertClickCb) alertClickCb(f.properties.uri || f.properties.title);
    };
    map.on('click', popupHandler);
  }

  // While the map moves, frames preloading out of sight (opacity 0) fetch
  // no tiles: on a small CPU, decoding theirs is what slowed a zoom down,
  // more than the wind. When it stops they come back two at a time, in the
  // order the viewer made them (nearest the shown time first), each pair
  // once the map is idle, the first too: a zoom by the wheel goes on by
  // steps, and all 17 at once made it stutter (9 to 13 frames over 33 ms
  // per zoom on one core, 1 with the shown frame only).
  // A new move cuts that short; a frame the viewer shows or waits for
  // comes back at once.
  var REVEAL_BATCH = 2;
  var moving = false, revealJob = 0;
  function holdFrame(e, held) {
    e.held = held;
    if (map.getLayer(e.layerId)) map.setLayoutProperty(e.layerId, 'visibility', held ? 'none' : 'visible');
  }
  function entryOf(handle) {
    for (var i = 0; i < frameRegistry.length; i++) if (frameRegistry[i].layerId === handle.layerId) return frameRegistry[i];
    return null;
  }
  function holdHiddenFrames(hold) {
    moving = hold;
    var job = ++revealJob, i;
    if (hold) {
      for (i = 0; i < frameRegistry.length; i++) if (!(frameRegistry[i].opacity > 0)) holdFrame(frameRegistry[i], true);
      return;
    }
    var next = function () {
      if (job !== revealJob) return;
      var n = 0;
      for (i = 0; i < frameRegistry.length && n < REVEAL_BATCH; i++) {
        if (frameRegistry[i].held) { holdFrame(frameRegistry[i], false); n++; }
      }
      if (n) map.once('idle', next);
    };
    map.once('idle', next);
  }

  // Kept loaded behind a closed popup, the page prepares what the popup
  // will open on (glue-prepare.js gives it frames meanwhile): the base map
  // and the image shown, or every image for the whole animation. The
  // preparation ends there, so the wind does not run on in a hidden page.
  // Hidden, map moves do not reach the viewer, whose answer to one is to
  // preload every image; a new image starts another preparation.
  var prepare = typeof widgetPrepare !== 'undefined' ? widgetPrepare : null;
  var prepareMode = typeof PREPARE_MODE !== 'undefined' ? PREPARE_MODE : 'none';
  var viewportCb = null, preloadAsked = false;
  function pageHidden() { return document.visibilityState === 'hidden'; }
  function framesSettled() {
    for (var id in pendingReady) if (pendingReady[id].length) return false;
    for (var i = 0; i < frameRegistry.length; i++) {
      var e = frameRegistry[i];
      if (map.getSource(e.sourceId) && !map.isSourceLoaded(e.sourceId)) return false;
    }
    return true;
  }
  function checkPrepared() {
    if (!prepare || !prepare.preparing() || adapter.tilesBusy()) return;
    if (!frameRegistry.some(function (e) { return e.opacity > 0; })) return;
    if (prepareMode === 'all') {
      if (!preloadAsked) { preloadAsked = true; if (viewportCb) viewportCb(); return; }
      if (!framesSettled()) return;
    }
    prepare.end();
    console.log('[librewxr] radar prepared in the hidden page (' + prepareMode + ')');
  }
  function prepareNewFrame() {
    if (!prepare || prepareMode === 'none' || !pageHidden() || prepare.preparing()) return;
    preloadAsked = false;
    prepare.begin();
  }

  // Around the globe, space in the page's colors and an atmosphere lit by
  // the Sun (moveSun), which fades out as the map zooms in (gone at
  // MapLibre zoom 7).
  var SKY = {
    dark: { 'sky-color': '#05070b', 'horizon-color': '#1d3557', 'fog-color': '#05070b' },
    light: { 'sky-color': '#e8eef5', 'horizon-color': '#9fb6d0', 'fog-color': '#e8eef5' }
  };
  // The glow of the atmosphere, in percent of its full strength (blend 0.5
  // with the whole Earth in view): full, it washes the day side out. Set
  // from the widget's slider; 30 by default.
  var glow = percent(GLOW_INIT);
  if (glow === null) glow = 30;
  function applyProjection() {
    map.setProjection({ type: projection === 'globe' ? 'globe' : 'mercator' });
    var sky = {}, base = SKY[skyTheme] || SKY.dark, g = glow / 100;
    for (var k in base) sky[k] = base[k];
    sky['atmosphere-blend'] = ['interpolate', ['linear'], ['zoom'], 0, 0.5 * g, 4, 0.35 * g, 7, 0];
    map.setSky(sky);
  }

  // A new style drops every source and layer the page added: put them back
  // once it has loaded. It comes with the projection: a style without one is
  // a flat map, where MapLibre holds the globe's minimum zoom as a flat one,
  // and the globe came back bigger than it was.
  function swapToStyle(next) {
    swapInProgress = true;
    map.once('style.load', function () { restoreRuntimeStyle(next.key); });
    map.setStyle(next.style, {
      diff: false,
      transformStyle: function (previous, style) {
        var s = {};
        for (var k in style) s[k] = style[k];
        s.projection = { type: projection === 'globe' ? 'globe' : 'mercator' };
        return s;
      }
    });
  }

  function restoreRuntimeStyle(key) {
    appliedKey = key;
    var i;
    addSunLayers();
    for (i = 0; i < frameRegistry.length; i++) if (frameRegistry[i].kind === 'satellite') addFrameEntry(frameRegistry[i]);
    if (alertsEntry) { addAlertsLayers(); registerAlertsPopup(); }
    for (i = 0; i < frameRegistry.length; i++) if (frameRegistry[i].kind !== 'satellite') addFrameEntry(frameRegistry[i]);
    assertAlertsPosition();
    applyProjection();
    moveSun();
    swapInProgress = false;
    if (desired && desired.key !== appliedKey) swapToStyle(desired);
  }

  var adapter = {
    // MapLibre takes no sources or layers before its style has loaded.
    onMapReady: function (cb) {
      if (styleReady) { cb(); return; }
      map.once('load', function () { styleReady = true; cb(); });
    },

    createMap: function (containerId, view) {
      maxZoom = view.maxZoom;
      var first = baseFor(PARAMS.get('theme') === 'light' ? 'light' : 'dark');
      appliedKey = first.key;
      map = new maplibregl.Map({
        container: containerId,
        style: first.style,
        center: [view.lon, view.lat],
        zoom: toGl(view.zoom),
        maxZoom: toGl(view.maxZoom),
        attributionControl: { compact: true },
        // Tile fetches from a file:// page (CORS with a null origin)
        transformRequest: function (url) { return { url: url, credentials: 'omit' }; }
      });
      // Zoom buttons and compass, where the Leaflet page has them.
      map.addControl(new maplibregl.NavigationControl({ visualizePitch: false }), 'top-left');
      new maplibregl.Marker().setLngLat([view.lon, view.lat]).addTo(map);
      map.once('load', function () { styleReady = true; applyProjection(); applyDayNight(); fitMinZoom(); });
      map.on('movestart', function () { holdHiddenFrames(true); });
      map.on('moveend', function () { holdHiddenFrames(false); });
      map.on('resize', fitMinZoom);
      map.on('render', checkPrepared);
      return map;
    },

    setBasemap: function (theme) {
      skyTheme = theme;
      desired = baseFor(theme);
      if (!styleReady) { map.once('load', function () { adapter.setBasemap(theme); }); return; }
      if (swapInProgress) return;
      if (desired.key !== appliedKey) { swapToStyle(desired); return; }
      // Same base map, other theme: the space around the globe and the day veil follow.
      applyProjection();
      addSunLayers();
      drawShade(WidgetEarth.subsolarPoint(new Date()));
    },

    createFrameLayer: function (url, kind) {
      var id = 'lv-frame-' + (frameSeq++);
      var entry = {
        sourceId: 'lv-src-' + id,
        layerId: (kind === 'satellite' ? 'lv-layer-sat-' : 'lv-layer-radar-') + id,
        kind: kind, url: url, maxZoom: maxZoom, opacity: 0
      };
      frameRegistry.push(entry);
      prepareNewFrame();
      // The handle is due now; only the map change waits for the style.
      if (!styleReady) map.once('load', function () { addFrameEntry(entry); });
      else if (!swapInProgress) addFrameEntry(entry);
      return { sourceId: entry.sourceId, layerId: entry.layerId };
    },

    onLayerReady: function (handle, cb) {
      var done = false, waiter = null;
      function finish() {
        if (done) return;
        done = true;
        map.off('sourcedata', onData);
        map.off('error', onError);
        clearTimeout(waiter);
        var list = pendingReady[handle.sourceId];
        if (list) list.splice(list.indexOf(finish), 1);
        cb();
      }
      function onData(e) {
        if (e.sourceId === handle.sourceId && map.isSourceLoaded(handle.sourceId)) finish();
      }
      // A dead tile host settles the layer too, so the animation never hangs.
      function onError(e) {
        if (e.sourceId === handle.sourceId || (e.error && e.error.sourceId === handle.sourceId)) {
          console.warn('[librewxr] map tile/source error:', e.error ? (e.error.message || e.error) : e);
          finish();
        }
      }
      map.on('sourcedata', onData);
      map.on('error', onError);
      var e = entryOf(handle);
      if (e && e.held && !moving) holdFrame(e, false);
      (pendingReady[handle.sourceId] = pendingReady[handle.sourceId] || []).push(finish);
      waiter = setTimeout(function () {
        console.warn('[librewxr] frame layer not settled after 25 s: ' + handle.sourceId);
        finish();
      }, 25000);
      if (map.getSource(handle.sourceId) && map.isSourceLoaded(handle.sourceId)) finish();
    },

    setFrameOpacity: function (handle, v) {
      var e = entryOf(handle);
      if (e) e.opacity = v;
      if (map.getLayer(handle.layerId)) map.setPaintProperty(handle.layerId, 'raster-opacity', v);
      if (e && v > 0 && e.held) holdFrame(e, false);
      else if (e && moving && !(v > 0)) holdFrame(e, true);
    },

    destroyFrameLayer: function (handle) {
      if (!handle) return;
      // A layer destroyed while loading gets no more source events: settle
      // its waiters now. Left to their 25 s timeout, the viewer's late
      // callback found the frame rebuilt under the same path and faded the
      // shown radar out for this dead layer. A tick later, once the viewer
      // has finished clearing its cache, before any new layer can be ready.
      var waiting = pendingReady[handle.sourceId];
      delete pendingReady[handle.sourceId];
      if (waiting && waiting.length) setTimeout(function () { waiting.slice().forEach(function (f) { f(); }); }, 0);
      for (var i = 0; i < frameRegistry.length; i++) {
        if (frameRegistry[i].layerId === handle.layerId) { frameRegistry.splice(i, 1); break; }
      }
      if (map.getLayer(handle.layerId)) map.removeLayer(handle.layerId);
      if (map.getSource(handle.sourceId)) map.removeSource(handle.sourceId);
    },

    onAlertClick: function (cb) { alertClickCb = cb; },

    // Open popups are map overlays: they stay open when the overlay is
    // refreshed, so reopenId has nothing left to do here.
    setAlertsOverlay: function (geojsonOrNull, styleFn) {
      if (!styleReady) {
        map.once('load', function () { adapter.setAlertsOverlay(geojsonOrNull, styleFn); });
        return;
      }
      if (map.getLayer('lv-alerts-fill')) map.removeLayer('lv-alerts-fill');
      if (map.getLayer('lv-alerts-line')) map.removeLayer('lv-alerts-line');
      if (map.getSource('lv-alerts')) map.removeSource('lv-alerts');
      if (popupHandler) { map.off('click', popupHandler); popupHandler = null; }
      if (!geojsonOrNull) { alertsEntry = null; return; }
      var features = [], list = geojsonOrNull.features || [];
      for (var i = 0; i < list.length; i++) {
        var f = list[i];
        if (!f.geometry) continue;
        var s = (styleFn && styleFn(f)) || {}, props = {};
        for (var k in f.properties) props[k] = f.properties[k];
        props.__color = s.color || '#546e7a';
        props.__fillColor = s.fillColor || props.__color;
        props.__fillOpacity = s.fillOpacity == null ? 0.18 : s.fillOpacity;
        props.__weight = s.weight == null ? 2 : s.weight;
        features.push({ type: 'Feature', geometry: f.geometry, properties: props });
      }
      alertsEntry = { geojson: { type: 'FeatureCollection', features: features } };
      if (swapInProgress) return;   // restoreRuntimeStyle() adds it afterwards
      addAlertsLayers();
      assertAlertsPosition();
      registerAlertsPopup();
    },

    flyTo: function (lat, lon, zoom) {
      map.flyTo({ center: [lon, lat], zoom: zoom == null ? map.getZoom() : toGl(zoom) });
    },

    onViewportChange: function (cb) {
      viewportCb = cb;
      map.on('moveend', function () {
        if (cb && !(prepare && pageHidden())) cb();
        // Report the zoom to QML via the page title, on the widget's scale.
        document.title = 'zoom:' + Math.round(fromGl(map.getZoom()));
      });
    },

    getBounds: function () {
      var b = map.getBounds();
      return { west: b.getWest(), south: b.getSouth(), east: b.getEast(), north: b.getNorth() };
    },

    getMap: function () { return map; },

    /* What glue-controls.js asks of any map. */
    resize: function () { if (map) map.resize(); },

    // Chromium in the plasmoid can leave the canvas damaged: one more frame.
    nudge: function () { if (map) { map.resize(); map.triggerRepaint(); } },

    sizeKey: function () {
      var c = map ? map.getContainer() : null;
      return c ? c.clientWidth + 'x' + c.clientHeight : '0x0';
    },

    // Tiles still loading in the sources on screen; hidden radar frames
    // (preloaded at opacity 0) do not count.
    tilesBusy: function () {
      if (!map || !styleReady) return true;
      var hidden = {};
      for (var i = 0; i < frameRegistry.length; i++) if (!(frameRegistry[i].opacity > 0)) hidden[frameRegistry[i].sourceId] = true;
      var sources = map.getStyle().sources;
      for (var id in sources) if (!hidden[id] && map.getSource(id) && !map.isSourceLoaded(id)) return true;
      return false;
    },

    setProjection: function (p) {
      projection = p === 'globe' ? 'globe' : 'flat';
      if (styleReady && !swapInProgress) applyProjection();
      if (styleReady) fitMinZoom();
    },

    getProjection: function () { return projection; },

    setDayNight: function (on) {
      dayNight = !!on;
      if (styleReady && !swapInProgress) applyDayNight();
    },

    getDayNight: function () { return dayNight; },

    setGlow: function (value) {
      var g = percent(value);
      if (g === null) return;
      glow = g;
      if (styleReady && !swapInProgress) applyProjection();
    },

    getGlow: function () { return glow; },

    setNightDepth: function (value) {
      var d = percent(value);
      if (d === null) return;
      nightDepth = d;
      if (styleReady && map.getLayer('lv-night')) drawShade(WidgetEarth.subsolarPoint(new Date()));
    },

    getNightDepth: function () { return nightDepth; },

    // The table-based wind layer (glue-wind-table.js), when the page has it.
    createWindLayer: function (source, openData, dem, options) {
      if (!WidgetWind.createTableWindLayer) return null;
      var Layer = WidgetWind.createTableWindLayer(maplibregl);
      return new Layer(source, openData, dem, options);
    }
  };
  return adapter;
};
