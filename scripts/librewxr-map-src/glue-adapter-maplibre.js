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
  var framesHidden = false;    // the radar and satellite frames off (the animations)
  var pendingReady = {};       // source id -> finishers of onLayerReady still waiting
  var alertsEntry = null;      // { geojson } while the alerts overlay is on
  var tempEntry = null;        // { provider, version, opacity } while the temperature shows
  var restyleCbs = [];         // the page's own layers to put back after a new style (onRestyle)
  var attribution = null;      // the attribution control, remade when its lines change
  var dataAttribution = false; // Open-Meteo credited (wind or temperature on)
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
      if (id.indexOf('lv-') === 0 && id !== 'lv-base' && id !== 'lv-night' && id !== TEMP_LAYER && id !== LINES_LAYER) return id;
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
        map.getLayer(TEMP_LAYER) ? TEMP_LAYER : map.getLayer(LINES_LAYER) ? LINES_LAYER : firstRuntimeLayerId());
    }
  }

  // The temperature (glue-temp-layer.js): raster tiles the layer draws,
  // through a tile protocol of its own as the night, right over the base
  // map and its night, under every frame and overlay. Each new set of tiles
  // (new data, new colors) has its own address; the shown ones stay until
  // the new ones arrive. A tile of 256 px is shown on 512, as a vector
  // map's: the data are coarse, and the elevation keeps 2 screen px; a
  // quarter of the tiles to draw and of the elevation tiles to fetch. Past
  // zoom 12 the map stretches the tiles.
  var TEMP_LAYER = 'lv-temp', TEMP_SOURCE = 'lv-temp-src', TEMP_TILE = 256, TEMP_MAXZOOM = 12;
  maplibregl.addProtocol('lvtemp', function (params, abortController) {
    var m = /^lvtemp:\/\/\d+\/(\d+)\/(\d+)\/(\d+)/.exec(params.url);
    var signal = abortController && abortController.signal;
    var drawn = tempEntry ? tempEntry.provider(+m[1], +m[2], +m[3], signal)
      : Promise.resolve(new Uint8ClampedArray(TEMP_TILE * TEMP_TILE * 4));
    return drawn.then(function (px) {
      // 256 px, or fewer while the animation plays (the map stretches them).
      var size = Math.round(Math.sqrt(px.length / 4));
      return createImageBitmap(new ImageData(px, size, size));
    }).then(function (bitmap) {
      return { data: bitmap };
    });
  });
  function tempTiles() { return ['lvtemp://' + tempEntry.version + '/{z}/{x}/{y}']; }
  function addTempLayer() {
    if (!tempEntry) return;
    if (!map.getSource(TEMP_SOURCE)) {
      map.addSource(TEMP_SOURCE, { type: 'raster', tiles: tempTiles(), tileSize: 2 * TEMP_TILE, maxzoom: TEMP_MAXZOOM });
    }
    if (!map.getLayer(TEMP_LAYER)) {
      map.addLayer({
        id: TEMP_LAYER, type: 'raster', source: TEMP_SOURCE,
        paint: { 'raster-opacity': tempEntry.opacity, 'raster-fade-duration': 0, 'raster-resampling': 'linear' }
      }, map.getLayer(LINES_LAYER) ? LINES_LAYER : firstRuntimeLayerId());
    }
    setLines('temperature', true);
  }

  // The color layers hide the base map: the coasts and land borders drawn
  // again over them, from the widget's own file (vendor/coast-borders.bin,
  // Natural Earth, about 500 m), the same on every base map and offline.
  // Right under the frames and the alerts; color layers of other scripts
  // go under them through linesBefore(). Shown while a layer wants them
  // (setLines) and the widget's setting lets them (setLinesShown), the
  // file read once. Hidden, never removed: from one color layer to another
  // they stay as they are, tiles and all.
  var homeMarker = null;      // the widget's place
  var LINES_LAYER = 'lv-lines', LINES_SOURCE = 'lv-lines-src', LINES_URL = 'vendor/coast-borders.bin';
  var linesOwners = {}, linesData = null, linesLoading = false;
  var linesShown = typeof LINES_INIT === 'undefined' || LINES_INIT !== false;
  function linesWanted() {
    if (!linesShown) return false;
    for (var k in linesOwners) return true;
    return false;
  }
  function firstOverlayLayerId() {
    var layers = map.getStyle().layers;
    for (var i = 0; i < layers.length; i++) {
      var id = layers[i].id;
      if (id.indexOf('lv-layer-') === 0 || id.indexOf('lv-alerts') === 0) return id;
    }
    return undefined;
  }
  // Called by restoreRuntimeStyle() while the swap ends, so not held by it.
  function applyLines() {
    if (!styleReady) return;
    if (!linesWanted()) {
      if (map.getLayer(LINES_LAYER)) map.setLayoutProperty(LINES_LAYER, 'visibility', 'none');
      return;
    }
    if (!linesData) {
      if (linesLoading || typeof fetch !== 'function') return;
      linesLoading = true;
      fetch(LINES_URL).then(function (r) { return r.arrayBuffer(); }).then(function (buf) {
        linesData = WidgetEarth.decodeLines(buf);
        if (!swapInProgress) applyLines();
      }).catch(function (e) {
        linesLoading = false;
        console.warn('coast and border lines: ' + e);
      });
      return;
    }
    if (!map.getSource(LINES_SOURCE)) map.addSource(LINES_SOURCE, { type: 'geojson', data: linesData });
    if (map.getLayer(LINES_LAYER)) {
      map.setLayoutProperty(LINES_LAYER, 'visibility', 'visible');
      return;
    }
    map.addLayer({
      id: LINES_LAYER, type: 'line', source: LINES_SOURCE,
      layout: { 'line-join': 'round', visibility: 'visible' },
      paint: {
        'line-color': 'rgba(20, 20, 20, 0.6)',
        // Thicker far out: on the whole globe (zoom ~1) a hairline is lost
        // in the colors. Thinnest around zoom 4, then wider again close in.
        'line-width': ['interpolate', ['linear'], ['zoom'], 0, 1.7, 2, 1.3, 4, 1.0, 6, 1.2, 10, 1.8]
      }
    }, firstOverlayLayerId());
    // The animation's images made before them go under them, the
    // satellite's under the radar's.
    ['satellite', 'radar'].forEach(function (kind) {
      for (var i = 0; i < frameRegistry.length; i++) {
        var e = frameRegistry[i];
        if (e.anim && (e.kind === 'satellite') === (kind === 'satellite') && map.getLayer(e.layerId)) map.moveLayer(e.layerId, LINES_LAYER);
      }
    });
  }
  function setLines(owner, on) {
    if (on) linesOwners[owner] = true; else delete linesOwners[owner];
    if (!swapInProgress) applyLines();
  }

  var OPEN_METEO = 'Weather data: <a href="https://open-meteo.com/">Open-Meteo</a>';
  function makeAttribution() {
    if (attribution) map.removeControl(attribution);
    attribution = new maplibregl.AttributionControl(dataAttribution ? { compact: true, customAttribution: OPEN_METEO } : { compact: true });
    map.addControl(attribution);
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
      layout: { visibility: frameVisibility(entry) },
      paint: {
        'raster-opacity': entry.opacity,
        'raster-opacity-transition': { duration: 0, delay: 0 },
        'raster-fade-duration': 0
      }
    }, entry.anim ? animFrameBefore(entry) : entry.kind === 'satellite' ? firstRuntimeLayerId() : undefined);
    if (entry.kind !== 'satellite' && !entry.anim) assertAlertsPosition();
  }

  // The animation's images go over every layer of the map and under the
  // coasts and borders, so these show over the clouds and the rain; its
  // satellite under its radar.
  function firstAnimRadarId() {
    var layers = map.getStyle().layers;
    for (var i = 0; i < layers.length; i++) {
      var e = entryOf({ layerId: layers[i].id });
      if (e && e.anim && e.kind !== 'satellite') return layers[i].id;
    }
    return undefined;
  }
  /** The lowest image of the animation on the map (a satellite one first). */
  function firstAnimFrameId() {
    var order = map.getLayersOrder ? map.getLayersOrder() : map.getStyle().layers.map(function (l) { return l.id; });
    for (var i = 0; i < order.length; i++) {
      var e = entryOf({ layerId: order[i] });
      if (e && e.anim) return order[i];
    }
    return undefined;
  }
  function animFrameBefore(entry) {
    var lines = map.getLayer(LINES_LAYER) ? LINES_LAYER : undefined;
    if (entry.kind !== 'satellite') return lines;
    return firstAnimRadarId() || lines;
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
  // The animation's own radar and satellite images (anim) stay out of setFramesHidden.
  function frameVisibility(e) { return e.held || (framesHidden && !e.anim) ? 'none' : 'visible'; }
  function holdFrame(e, held) {
    e.held = held;
    if (map.getLayer(e.layerId)) map.setLayoutProperty(e.layerId, 'visibility', frameVisibility(e));
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

  // The stack of the weather layers, set by the widget: its ids top first
  // (the wind, a canvas over the map, is not in it). The night stays at
  // the bottom, the coasts and borders on top, the isobars right over the
  // highest of the fields (the other ids but the radar and the satellite),
  // so the lines read over the colors. restack() puts every layer of the
  // map at its place, with as few moves as it can; a layer added anywhere
  // goes back to its place on the next 'styledata'.
  var STACK_DEFAULT = ['radar', 'satellite', 'precipitation', 'clouds',
    'temperature', 'pressure', 'humidity', 'dewpoint', 'airquality'];
  var stackOrder = STACK_DEFAULT.slice(), restacking = false;
  function normStackOrder(order) {
    var out = [];
    (order || []).concat(STACK_DEFAULT).forEach(function (g) {
      if (STACK_DEFAULT.indexOf(g) >= 0 && out.indexOf(g) < 0) out.push(g);
    });
    return out;
  }
  /** [group, rank inside the group] of a layer id; null for one not stacked. */
  function stackGroup(id) {
    if (id === 'lv-night') return ['night', 0];
    if (id === LINES_LAYER) return ['lines', 0];
    if (id.indexOf('lv-alerts') === 0) return ['radar', 0];
    if (id.indexOf('lv-layer-sat-') >= 0) return ['satellite', 1];
    if (id.indexOf('lv-layer-radar-') >= 0) return ['radar', 1];
    if (id === 'lv-iso' || id === 'lv-iso-gl') return ['isobars', 0];
    if (id === 'lv-iso-label') return ['isobars', 1];
    if (id === 'lv-precip-gl') return ['precipitation', 0];
    if (id === 'lv-clouds-gl') return ['clouds', 0];
    if (id === 'lv-temp-gl' || id === TEMP_LAYER) return ['temperature', 0];
    if (id === 'lv-pres-gl' || id === 'lv-pres') return ['pressure', 0];
    if (id === 'lv-humidity-gl') return ['humidity', 0];
    if (id === 'lv-dewpoint-gl') return ['dewpoint', 0];
    if (id.indexOf('lv-aq-gl-') === 0) return ['airquality', 0];
    return null;
  }
  function layersOrder() {
    return map.getLayersOrder ? map.getLayersOrder() : map.getStyle().layers.map(function (l) { return l.id; });
  }
  function restack() {
    if (!map || restacking || swapInProgress) return;
    var n = stackOrder.length, ids = layersOrder(), known = [], fieldTop = -1;
    stackOrder.forEach(function (g, i) {
      if (g !== 'radar' && g !== 'satellite') fieldTop = Math.max(fieldTop, n - 1 - i);
    });
    ids.forEach(function (id, pos) {
      var g = stackGroup(id);
      if (!g) return;
      var level = g[0] === 'night' ? -1 : g[0] === 'lines' ? n : g[0] === 'isobars' ? fieldTop + 0.5 : n - 1 - stackOrder.indexOf(g[0]);
      known.push({ id: id, level: level, sub: g[1], pos: pos });
    });
    var want = known.slice().sort(function (a, b) { return a.level - b.level || a.sub - b.sub || a.pos - b.pos; });
    if (want.every(function (k, i) { return k === known[i]; })) return;
    restacking = true;
    try {
      // Each one right under the one above it, from the top one down.
      for (var i = want.length - 2; i >= 0; i--) {
        ids = layersOrder();
        if (ids[ids.indexOf(want[i].id) + 1] !== want[i + 1].id) map.moveLayer(want[i].id, want[i + 1].id);
      }
    } finally {
      restacking = false;
    }
  }

  function restoreRuntimeStyle(key) {
    appliedKey = key;
    var i;
    addSunLayers();
    addTempLayer();
    applyLines();
    for (i = 0; i < frameRegistry.length; i++) if (frameRegistry[i].kind === 'satellite') addFrameEntry(frameRegistry[i]);
    if (alertsEntry) { addAlertsLayers(); registerAlertsPopup(); }
    for (i = 0; i < frameRegistry.length; i++) if (frameRegistry[i].kind !== 'satellite') addFrameEntry(frameRegistry[i]);
    assertAlertsPosition();
    applyProjection();
    moveSun();
    swapInProgress = false;
    for (i = 0; i < restyleCbs.length; i++) restyleCbs[i]();
    restack();
    if (desired && desired.key !== appliedKey) swapToStyle(desired);
  }

  var adapter = {
    /** The stack of the weather layers, ids top first (see restack()). */
    setLayerOrder: function (order) {
      stackOrder = normStackOrder(order);
      restack();
    },
    restack: restack,

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
        // Made by makeAttribution(), which adds a line for Open-Meteo's data.
        attributionControl: false,
        // The zoom buttons' tips, in the widget's language, with their keys.
        // (tr: the page's, absent in the unit tests).
        locale: { 'NavigationControl.ZoomIn': (typeof tr === 'function' ? tr('zoomIn', 'Zoom in') : 'Zoom in') + ' (Ctrl +)',
                  'NavigationControl.ZoomOut': (typeof tr === 'function' ? tr('zoomOut', 'Zoom out') : 'Zoom out') + ' (Ctrl -)' },
        // Tile fetches from a file:// page (CORS with a null origin)
        transformRequest: function (url) { return { url: url, credentials: 'omit' }; }
      });
      // Zoom buttons and compass, where the Leaflet page has them.
      map.addControl(new maplibregl.NavigationControl({ visualizePitch: false }), 'top-left');
      makeAttribution();
      homeMarker = new maplibregl.Marker().setLngLat([view.lon, view.lat]).addTo(map);
      // The default marker without its shadow (a black group of ellipses
      // at its foot in MapLibre's SVG).
      var markerShadow = homeMarker.getElement && homeMarker.getElement().querySelector('g[fill="#000000"]');
      if (markerShadow) markerShadow.remove();
      // applyLines(): the layers that asked for the lines before the style
      // loaded (the radar, switched on as soon as the page is up) get them now.
      map.once('load', function () { styleReady = true; applyProjection(); applyDayNight(); addTempLayer(); applyLines(); fitMinZoom(); });
      map.on('movestart', function () { holdHiddenFrames(true); });
      map.on('moveend', function () { holdHiddenFrames(false); });
      map.on('resize', fitMinZoom);
      map.on('render', checkPrepared);
      map.on('styledata', restack);
      return map;
    },

    /** cb() after each base map change, once the adapter has put its own
        layers back: the layers the page added itself (those of the
        animation) go back then. */
    onRestyle: function (cb) { restyleCbs.push(cb); },

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

    /** opts.anim: an image of the animation (glue-anim-radar.js), shown
        while the viewer's are hidden, over the animation's layers. */
    createFrameLayer: function (url, kind, opts) {
      var id = 'lv-frame-' + (frameSeq++), anim = !!(opts && opts.anim);
      var entry = {
        sourceId: 'lv-src-' + id,
        layerId: (anim ? 'lv-anim-' : '') + (kind === 'satellite' ? 'lv-layer-sat-' : 'lv-layer-radar-') + id,
        kind: kind, url: url, maxZoom: maxZoom, opacity: 0, anim: anim
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

    /** An image of the animation back to its place in the stack. */
    raise: function (handle) {
      var e = entryOf(handle);
      if (!e || !e.anim || !map.getLayer(e.layerId)) return;
      restack();
    },

    /** Hide every radar and satellite frame, those to come too. */
    setFramesHidden: function (on) {
      framesHidden = !!on;
      for (var i = 0; i < frameRegistry.length; i++) {
        var e = frameRegistry[i];
        if (map && map.getLayer(e.layerId)) map.setLayoutProperty(e.layerId, 'visibility', frameVisibility(e));
      }
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

    /** A new place for the widget: its marker there, the map on it at once. */
    setHome: function (lat, lon) {
      if (homeMarker) homeMarker.setLngLat([lon, lat]);
      if (map) map.jumpTo({ center: [lon, lat] });
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

    /** Show the temperature tiles drawn by provider(z, x, y, signal) ->
        Promise of 256 x 256 RGBA pixels, at opacity 0..1; again with a new
        version when the data or the colors change. */
    setTempTiles: function (provider, version, opacity) {
      var same = tempEntry && tempEntry.version === version;
      tempEntry = { provider: provider, version: version, opacity: opacity };
      if (!styleReady || swapInProgress) return;   // restoreRuntimeStyle() adds it afterwards
      var src = map.getSource(TEMP_SOURCE);
      if (!src || !map.getLayer(TEMP_LAYER)) { addTempLayer(); return; }
      if (!same) src.setTiles(tempTiles());
      map.setPaintProperty(TEMP_LAYER, 'raster-opacity', opacity);
    },

    setTempOpacity: function (opacity) {
      if (!tempEntry) return;
      tempEntry.opacity = opacity;
      if (map.getLayer(TEMP_LAYER)) map.setPaintProperty(TEMP_LAYER, 'raster-opacity', opacity);
    },

    clearTemp: function () {
      tempEntry = null;
      setLines('temperature', false);
      if (map.getLayer(TEMP_LAYER)) map.removeLayer(TEMP_LAYER);
      if (map.getSource(TEMP_SOURCE)) map.removeSource(TEMP_SOURCE);
    },

    /** Coasts and borders over the color layers while at least one owner
        wants them; the layer to put a color layer before, to stay under. */
    setLines: setLines,
    setLinesShown: function (on) {
      linesShown = !!on;
      if (!swapInProgress) applyLines();
    },
    getLinesShown: function () { return linesShown; },
    /** Where a weather layer goes: under the animation's satellite and
        radar images when there are any (the radar over all), else under
        the coasts and borders. */
    linesBefore: function () {
      if (!map) return undefined;
      return firstAnimFrameId() || (map.getLayer(LINES_LAYER) ? LINES_LAYER : undefined);
    },

    /** Credit Open-Meteo while the wind or the temperature shows. */
    setDataAttribution: function (on) {
      on = !!on;
      if (on === dataAttribution) return;
      dataAttribution = on;
      makeAttribution();
    },

    // The table-based wind layer (glue-wind-table.js), when the page has it.
    createWindLayer: function (source, openData, dem, options) {
      if (!WidgetWind.createTableWindLayer) return null;
      var Layer = WidgetWind.createTableWindLayer(maplibregl);
      return new Layer(source, openData, dem, options);
    }
  };
  return adapter;
};
