// ==========================================================================
// Glue script 2: Leaflet adapter (adapted from examples/src/leaflet.html.js).
// Implements the viewer-core.js adapter contract with Leaflet 1.x primitives,
// wired to the widget's query-param basemap selection.
// ==========================================================================
var WidgetLeafletAdapter = function () {
  var map = null;
  var maxZoom = 12;
  var currentBaseMap = null;
  var alertLayers = [];
  var alertClickCb = null;

  // Pane z-values come from the CSS design tokens so theming stays in one place.
  function paneZ(name, fallback) {
    var val = parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name));
    return isNaN(val) ? fallback : val;
  }

  // WIDGET PATCH: vector basemap support (OpenFreeMap).
  //
  // MapLibre needs a WebGL context. Where there is none - blacklisted GPU, a
  // VM, software rendering off - creating the layer throws, and the throw
  // lands after the old base layer was removed, leaving the map with no
  // background at all. Check first and stay on raster tiles instead.
  var webglOk = null;
  function hasWebGL() {
    if (webglOk !== null) return webglOk;
    try {
      var c = document.createElement('canvas');
      webglOk = !!(c.getContext('webgl2') || c.getContext('webgl'));
    } catch (e) {
      webglOk = false;
    }
    return webglOk;
  }

  // Fetched only when a vector background is actually selected: it is an
  // 800 kB script and every raster background works without it. A vector
  // entry picked before it lands shows its raster fallback, and setBasemap
  // runs again once it loads.
  var maplibreState = 'idle'; // idle | loading | ready | failed
  function loadMapLibre(onReady) {
    if (maplibreState === 'ready') return onReady();
    if (maplibreState !== 'idle') return;
    maplibreState = 'loading';
    var css = document.createElement('link');
    css.rel = 'stylesheet';
    css.href = 'https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css';
    document.head.appendChild(css);
    var gl = document.createElement('script');
    gl.src = 'https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js';
    gl.onerror = function () { maplibreState = 'failed'; };
    gl.onload = function () {
      var bridge = document.createElement('script');
      bridge.src = 'https://unpkg.com/@maplibre/maplibre-gl-leaflet@0.0.22/leaflet-maplibre-gl.js';
      bridge.onerror = function () { maplibreState = 'failed'; };
      bridge.onload = function () { maplibreState = 'ready'; onReady(); };
      document.head.appendChild(bridge);
    };
    document.head.appendChild(gl);
  }
  // /WIDGET PATCH

  return {
    // Leaflet maps are usable synchronously - no deferred boot needed.
    onMapReady: function (cb) { cb(); },

    createMap: function (containerId, view) {
      maxZoom = view.maxZoom;
      map = L.map(containerId, {
        maxZoom: view.maxZoom,
        zoomControl: true,
        // WIDGET PATCH: map rotation (leaflet-rotate plugin, loaded in
        // shell.html). rotateControl defaults to the 'topleft' corner, same
        // as zoomControl above, so Leaflet stacks it directly below with no
        // extra positioning needed. closeOnZeroBearing: false keeps the
        // compass visible at all times, matching the always-on compass in
        // the LibreWXR MapLibre example / Mapbox GL NavigationControl this
        // was modeled on, rather than only appearing once rotated off
        // north. Drag the compass icon, or hold Shift and drag the map
        // (shiftKeyRotate, on by default once rotate: true), to rotate.
        rotate: true,
        rotateControl: { position: 'topleft', closeOnZeroBearing: false }
      }).setView([view.lat, view.lon], view.zoom);

      // Widget location pin: marker for the location configured in the widget.
      L.marker([view.lat, view.lon], { interactive: false }).addTo(map);

      // Custom panes give deterministic z-ordering: satellite under alerts
      // under radar. Values mirror the --leaflet-z-* CSS tokens.
      //
      // WIDGET PATCH: leaflet-rotate splits _mapPane into two children -
      // _rotatePane (holds the stock tilePane/overlayPane, and gets the CSS
      // rotate transform) and _norotatePane (markerPane/popupPane/etc, stay
      // upright on purpose - a rotated marker icon or popup bubble would
      // look wrong). Its own createPane() override that would default new
      // panes into _rotatePane automatically is commented out upstream, so
      // an unadorned map.createPane(name) falls through to stock Leaflet
      // and attaches to _mapPane directly - a sibling of _rotatePane, which
      // never receives the rotation transform. That was the whole bug:
      // radar/satellite/alerts silently staying north-up while the base
      // map (tilePane, correctly inside _rotatePane already) rotated under
      // them. Passing map._rotatePane explicitly puts these three panes
      // where the rotation transform actually applies; map._rotatePane
      // falls back to undefined (Leaflet's own default: attach to
      // _mapPane) if a future plugin version ever renames or drops it.
      map.createPane('lv-satellite-pane', map._rotatePane);
      map.getPane('lv-satellite-pane').style.zIndex = paneZ('--leaflet-z-satellite', 350);
      map.createPane('lv-alerts-pane', map._rotatePane);
      map.getPane('lv-alerts-pane').style.zIndex = paneZ('--leaflet-z-alerts', 400);
      map.createPane('lv-radar-pane', map._rotatePane);
      map.getPane('lv-radar-pane').style.zIndex = paneZ('--leaflet-z-radar', 450);
      return map;
    },

    setBasemap: function setBasemapImpl(theme) {
      // WIDGET PATCH: resolve via the widget's BG_LIST / FALLBACK_BG instead of
      // a fixed per-theme tile layer, so QML-picked backgrounds are honored.
      // Vector entries (OpenFreeMap) go through MapLibre; raster ones keep the
      // plain tile layer.
      var entry = resolveBg(BG_CURRENT, theme);
      var wantsVector = !!(entry.vector && entry.styleUrl && hasWebGL());

      if (wantsVector && maplibreState !== 'ready') {
        loadMapLibre(function () { setBasemapImpl(theme); });
      }

      if (currentBaseMap) map.removeLayer(currentBaseMap);
      currentBaseMap = null;

      if (wantsVector && maplibreState === 'ready') {
        // MapLibre draws the style on its own WebGL canvas and Leaflet keeps it
        // aligned, so the satellite, alerts and radar panes above are untouched.
        try {
          currentBaseMap = L.maplibreGL({
            style: entry.styleUrl,
            attribution: entry.attribution
          });
        } catch (err) {
          // A context can still be refused past the check; never leave the map
          // bare - fall through to the raster branch below.
          webglOk = false;
        }
      }
      if (!currentBaseMap) {
        currentBaseMap = L.tileLayer(entry.url || FALLBACK_BG[theme].url, {
          attribution: entry.attribution,
          maxNativeZoom: entry.maxZoom || 19,
          maxZoom: 19,
          // Dark OSM is that same raster recoloured; see .base-inverted.
          className: entry.invert ? 'base-inverted' : ''
        });
      }
      currentBaseMap.addTo(map);
      // L.maplibreGL extends L.Layer, which has no bringToBack; it sits in
      // tilePane anyway, below the satellite, alerts and radar panes.
      if (currentBaseMap.bringToBack) currentBaseMap.bringToBack();
      // /WIDGET PATCH
    },

    createFrameLayer: function (url, kind) {
      var pane = kind === 'satellite' ? 'lv-satellite-pane' : 'lv-radar-pane';
      var layer = new L.TileLayer(url, {
        tileSize: 256,
        opacity: 0, // created hidden; the engine fades in on ready
        maxZoom: maxZoom,
        pane: pane
      });
      layer.createTile = function (coords, done) {
        var tile = document.createElement('img');
        tile.className = kind === 'satellite' ? 'satellite-tile' : 'radar-tile';
        tile.alt = '';
        var key = coords.x + ':' + coords.y + ':' + coords.z;
        var aborted = false;
        var onLoad = function () {
          tile.removeEventListener('load', onLoad);
          tile.removeEventListener('error', onError);
          if (aborted) return;
          tile.style.width = '256px';
          tile.style.height = '256px';
          if (!layer._tiles || !layer._tiles[key]) return;
          if (done) done(null, tile);
          layer.off('remove', abortTile);
        };
        var onError = function () {
          tile.removeEventListener('load', onLoad);
          tile.removeEventListener('error', onError);
          if (aborted) return;
          console.warn('[librewxr] tile load failed:', url);
          if (!layer._tiles || !layer._tiles[key]) return;
          if (done) done(new Error('Tile load failed'), tile);
          layer.off('remove', abortTile);
        };
        var abortTile = function () {
          aborted = true;
          layer.off('remove', abortTile);
          tile.removeAttribute('src');
          tile.removeEventListener('load', onLoad);
          tile.removeEventListener('error', onError);
        };
        layer.on('remove', abortTile);
        tile.addEventListener('load', onLoad);
        tile.addEventListener('error', onError);
        var url = this.getTileUrl(coords);
        tile.src = url;
        return tile;
      };
      layer.addTo(map);
      return layer;
    },

    onLayerReady: function (handle, cb) {
      var settled = false;
      var waiter = setTimeout(finish, 25000);
      function finish() {
        if (settled) return;
        settled = true;
        clearTimeout(waiter);
        handle.off('load', finish);
        handle.off('tileerror', finish);
        setTimeout(cb, 0);
      }
      handle.on('load', finish);
      handle.on('tileerror', finish);
      handle.on('tileerror', function (e) {
        var failedUrl = (e && e.tile && e.tile.src) ? e.tile.src : handle._url;
        console.warn('[librewxr] tile load failed:', failedUrl);
      });
    },

    setFrameOpacity: function (handle, v) {
      handle.setOpacity(v);
    },

    destroyFrameLayer: function (handle) {
      if (handle && map && map.hasLayer(handle)) map.removeLayer(handle);
    },

    onAlertClick: function (cb) { alertClickCb = cb; },

    setAlertsOverlay: function (geojsonOrNull, styleFn, reopenId) {
      if (alertLayers && alertLayers.length) {
        for (var i = 0; i < alertLayers.length; i++) map.removeLayer(alertLayers[i]);
        alertLayers = [];
      }
      if (!geojsonOrNull || !geojsonOrNull.features) return;

      var features = geojsonOrNull.features.slice();
      var sevOrder = { emergency: 5, extreme: 4, severe: 3, moderate: 2, minor: 1 };
      features.sort(function (a, b) {
        var sa = sevOrder[(a.properties && a.properties.severity || '').toLowerCase()] || 0;
        var sb = sevOrder[(b.properties && b.properties.severity || '').toLowerCase()] || 0;
        return sa - sb;
      });

      var pathsByUri = {};
      for (var i = 0; i < features.length; i++) {
        var feature = features[i];
        if (!feature.geometry) continue;
        var sev = (feature.properties && feature.properties.severity || 'unknown').toLowerCase();
        var zIdx = sevOrder[sev] ? sevOrder[sev] * 200 + 200 : 300;
        var fc = { type: 'FeatureCollection', features: [feature] };
        var layer = L.geoJSON(fc, {
          pane: 'lv-alerts-pane',
          style: function (f) { return styleFn(f); },
          onEachFeature: function (f, lyr) {
            if (f.properties && f.properties.__popup) {
              lyr.bindPopup(f.properties.__popup, {
                maxWidth: 320,
                autoPan: true,
                autoPanPadding: [20, 20],
                closeOnClick: true
              });
            }
            lyr.on('click', function (e) {
              L.DomEvent.stopPropagation(e);
              if (alertClickCb) {
                alertClickCb(f.properties && (f.properties.uri || f.properties.title));
              }
            });
            if (f.properties && f.properties.uri) {
              pathsByUri[f.properties.uri] = lyr;
            }
          }
        });
        layer.setZIndex(zIdx);
        layer.addTo(map);
        alertLayers.push(layer);
      }

      if (reopenId && pathsByUri[reopenId]) {
        var reopenPath = pathsByUri[reopenId];
        setTimeout(function () {
          try {
            if (reopenPath._map) reopenPath.openPopup();
          } catch (e) { /* map or layer gone - fine */ }
        }, 0);
      }
    },

    flyTo: function (lat, lon, zoom) {
      map.flyTo([lat, lon], (zoom == null) ? map.getZoom() : zoom);
    },

    onViewportChange: function (cb) {
      map.on('moveend', function () {
        // Keep the engine callback (alerts refilter + background preload).
        if (cb) cb();
        // WIDGET PATCH: report the viewport zoom to QML via the page title.
        // (In-map base-map picks report "bg:" titles; see glue-controls.)
        document.title = 'zoom:' + map.getZoom();
        // /WIDGET PATCH
      });
    },

    getBounds: function () {
      var b = map.getBounds();
      return { west: b.getWest(), south: b.getSouth(), east: b.getEast(), north: b.getNorth() };
    },

    // WIDGET PATCH: expose the Leaflet map for fixViewport().
    getMap: function () { return map; }
    // /WIDGET PATCH
  };
};
