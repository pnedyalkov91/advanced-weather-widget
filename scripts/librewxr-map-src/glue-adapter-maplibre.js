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
  // turned back, a little darker and duller).
  function baseFor(theme) {
    var entry = resolveBg(BG_CURRENT, theme);
    if (entry.vector && entry.styleUrl) return { key: entry.styleUrl, style: entry.styleUrl };
    var url = entry.url || FALLBACK_BG[theme].url;
    var paint = entry.invert ? {
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

  // First layer the page added: satellite frames go right below it, on top
  // of the base map.
  function firstRuntimeLayerId() {
    var layers = map.getStyle().layers;
    for (var i = 0; i < layers.length; i++) {
      if (layers[i].id.indexOf('lv-') === 0 && layers[i].id !== 'lv-base') return layers[i].id;
    }
    return undefined;
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
  // more than the wind. They go on when the map stops.
  var moving = false;
  function holdHiddenFrames(hold) {
    moving = hold;
    for (var i = 0; i < frameRegistry.length; i++) {
      var e = frameRegistry[i];
      if (map.getLayer(e.layerId)) map.setLayoutProperty(e.layerId, 'visibility', hold && !(e.opacity > 0) ? 'none' : 'visible');
    }
  }

  // Around the globe, space in the page's colors and an atmosphere at the
  // rim that fades out as the map zooms in (gone at MapLibre zoom 7).
  var SKY = {
    dark: { 'sky-color': '#05070b', 'horizon-color': '#1d3557', 'fog-color': '#05070b' },
    light: { 'sky-color': '#e8eef5', 'horizon-color': '#9fb6d0', 'fog-color': '#e8eef5' }
  };
  function applyProjection() {
    map.setProjection({ type: projection === 'globe' ? 'globe' : 'mercator' });
    var sky = {}, base = SKY[skyTheme] || SKY.dark;
    for (var k in base) sky[k] = base[k];
    sky['atmosphere-blend'] = ['interpolate', ['linear'], ['zoom'], 0, 0.9, 4, 0.6, 7, 0];
    map.setSky(sky);
  }

  // A new style drops every source and layer the page added, and the
  // projection: put them back once it has loaded.
  function swapToStyle(next) {
    swapInProgress = true;
    map.once('style.load', function () { restoreRuntimeStyle(next.key); });
    map.setStyle(next.style, { diff: false });
  }

  function restoreRuntimeStyle(key) {
    appliedKey = key;
    var i;
    for (i = 0; i < frameRegistry.length; i++) if (frameRegistry[i].kind === 'satellite') addFrameEntry(frameRegistry[i]);
    if (alertsEntry) { addAlertsLayers(); registerAlertsPopup(); }
    for (i = 0; i < frameRegistry.length; i++) if (frameRegistry[i].kind !== 'satellite') addFrameEntry(frameRegistry[i]);
    assertAlertsPosition();
    applyProjection();
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
      map.once('load', function () { styleReady = true; applyProjection(); });
      map.on('movestart', function () { holdHiddenFrames(true); });
      map.on('moveend', function () { holdHiddenFrames(false); });
      return map;
    },

    setBasemap: function (theme) {
      skyTheme = theme;
      desired = baseFor(theme);
      if (!styleReady) { map.once('load', function () { adapter.setBasemap(theme); }); return; }
      if (swapInProgress || desired.key === appliedKey) return;
      swapToStyle(desired);
    },

    createFrameLayer: function (url, kind) {
      var id = 'lv-frame-' + (frameSeq++);
      var entry = {
        sourceId: 'lv-src-' + id,
        layerId: (kind === 'satellite' ? 'lv-layer-sat-' : 'lv-layer-radar-') + id,
        kind: kind, url: url, maxZoom: maxZoom, opacity: 0
      };
      frameRegistry.push(entry);
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
      waiter = setTimeout(finish, 25000);
      if (map.getSource(handle.sourceId) && map.isSourceLoaded(handle.sourceId)) finish();
    },

    setFrameOpacity: function (handle, v) {
      for (var i = 0; i < frameRegistry.length; i++) {
        if (frameRegistry[i].layerId === handle.layerId) frameRegistry[i].opacity = v;
      }
      if (map.getLayer(handle.layerId)) {
        map.setPaintProperty(handle.layerId, 'raster-opacity', v);
        if (moving) map.setLayoutProperty(handle.layerId, 'visibility', v > 0 ? 'visible' : 'none');
      }
    },

    destroyFrameLayer: function (handle) {
      if (!handle) return;
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
      map.on('moveend', function () {
        if (cb) cb();
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
    },

    getProjection: function () { return projection; },

    // The table-based wind layer (glue-wind-table.js), when the page has it.
    createWindLayer: function (source, openData, dem, options) {
      if (!WidgetWind.createTableWindLayer) return null;
      var Layer = WidgetWind.createTableWindLayer(maplibregl);
      return new Layer(source, openData, dem, options);
    }
  };
  return adapter;
};
