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
  var frameById = new Map();   // their layer id -> entry
  var framesHidden = false;    // the radar and satellite frames off (the animations)
  var pendingReady = {};       // source id -> finishers of onLayerReady still waiting
  var pendingCheck = {};       // source id -> checks of onLayerReady (finish if loaded now)
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

  // A browser opens at most 6 connections to a host over HTTP/1.1, as a
  // local server is: the frames' tiles go to it under other names too, all
  // on the same machine (the browser sends any *.localhost there).
  var LOOPBACK = /^(https?:\/\/)(localhost|127\.0\.0\.1|[a-z0-9-]+\.localhost)(:\d+)?(\/.*)$/i;
  function frameTiles(url) {
    var m = LOOPBACK.exec(url);
    if (!m) return [url];
    return [url].concat(['a', 'b', 'c'].map(function (s) { return m[1] + s + '.localhost' + (m[3] || '') + m[4]; }));
  }

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
  // The light goes to its new place at once. MapLibre would take 300 ms
  // over it, drawing the whole map at every frame of the screen meanwhile:
  // with the Sun moved at each picture of the animation, it never stopped.
  var AT_ONCE = { duration: 0, delay: 0 };
  function lightAt(light) {
    return { anchor: light.anchor, position: light.position, 'position-transition': AT_ONCE, 'color-transition': AT_ONCE, 'intensity-transition': AT_ONCE };
  }
  var nightDepth = percent(NIGHTDEPTH_INIT);
  if (nightDepth === null) nightDepth = 40;
  var dayNight = DAYNIGHT_INIT;
  var sunTimer = null;
  var shade = { sun: WidgetEarth.subsolarPoint(new Date()), version: 0 };
  // 16 by default: the animation preloads a few hundred tiles at once,
  // and a server over HTTP/2 takes more in parallel.
  if (maplibregl.setMaxParallelImageRequests) maplibregl.setMaxParallelImageRequests(32);
  maplibregl.addProtocol('lvshade', function (params) {
    var m = /^lvshade:\/\/\d+\/(\d+)\/(\d+)\/(\d+)/.exec(params.url);
    var img = WidgetEarth.shadeTile(shade.sun, { z: +m[1], x: +m[2], y: +m[3] }, SHADE_TILE,
      nightDepth / 100, dayVeil());
    return createImageBitmap(new ImageData(img, SHADE_TILE, SHADE_TILE)).then(function (bitmap) {
      return { data: bitmap };
    });
  });
  function shadeTiles() { return ['lvshade://' + shade.version + '/{z}/{x}/{y}']; }
  function dayVeil() { return skyTheme === 'dark' ? DAY_VEIL : 0; }
  // Where the chip's layers are in the page (glue-temp-gl.js), the night
  // is one of them: the Sun, the darkness and the veil go to its shader
  // (WidgetEarth.NIGHT_FS) and moving the Sun costs one drawing of the map.
  // The tiles took the page's time at each picture of the animation (16
  // tiles worked out, sent to the chip, the map drawn twice). They stay for
  // a page without those layers, or a chip that does not build the shader.
  var night = { layer: null, failed: false };
  function nightClass() {
    return !night.failed && typeof WidgetTemp !== 'undefined' && WidgetTemp.TempLayerGL && WidgetTemp.TempLayerGL.GLLayer || null;
  }
  function nightLayer(GLLayer) {
    if (night.layer) return night.layer;
    night.layer = new GLLayer('lv-night', WidgetEarth.NIGHT_FS, function (gl, u) {
      var v = WidgetEarth.shadeUniforms(shade.sun, nightDepth / 100, dayVeil());
      gl.uniform3f(u.u_sun, v.sun[0], v.sun[1], v.sun[2]);
      gl.uniform2f(u.u_ln, v.ln[0], v.ln[1]);
      return true;
    });
    // Called while the map draws: the tiles take over right after.
    night.layer.onFail = function () {
      night.failed = true;
      night.layer = null;
      setTimeout(function () {
        if (!map || !styleReady || swapInProgress) return;
        if (map.getLayer('lv-night')) map.removeLayer('lv-night');
        addSunLayers();
      }, 0);
    };
    return night.layer;
  }
  // The night for the Sun now, the darkness and the theme: drawn again by
  // the chip, or new tiles, the shown ones staying until they arrive.
  function drawShade(sun) {
    shade.sun = sun;
    shade.version++;
    var src = map.getSource('lv-night');
    if (src) src.setTiles(shadeTiles());
    else if (map.getLayer('lv-night') && map.triggerRepaint) map.triggerRepaint();
  }
  // The globe's polar caps kept clear of the raster layers (MapLibre
  // stretches the row of pixels at 85 degrees of each up to the pole: rain
  // on it came out as a wedge pointing at the pole). A layer of the chip
  // right over the base map writes the nearest depth there; the rasters
  // over it fail their depth test in the caps (WidgetTemp.TempLayerGL.CAPS_FS).
  var caps = { layer: null, failed: false };
  function addCapsLayer() {
    if (caps.failed || map.getLayer('lv-caps')) return;
    var GLLayer = nightClass();
    if (!GLLayer) return;
    if (!caps.layer) {
      caps.layer = new GLLayer('lv-caps', WidgetTemp.TempLayerGL.CAPS_FS, function () { return true; });
      caps.layer.depthOnly = true;
      // Called while the map draws: the caps go back to MapLibre's way.
      caps.layer.onFail = function () {
        caps.failed = true;
        caps.layer = null;
        setTimeout(function () {
          if (map && map.getLayer('lv-caps')) map.removeLayer('lv-caps');
        }, 0);
      };
    }
    addLayer(caps.layer);
  }
  // The shade the setting asks for; after a style swap too.
  function addSunLayers() {
    addCapsLayer();
    if (!dayNight) {
      if (map.getLayer('lv-night')) map.removeLayer('lv-night');
      if (map.getSource('lv-night')) map.removeSource('lv-night');
      applyLights();
      return;
    }
    var GLLayer = nightClass();
    if (GLLayer) {
      if (!map.getLayer('lv-night')) addLayer(nightLayer(GLLayer));
      applyLights();
      return;
    }
    if (!map.getSource('lv-night')) {
      map.addSource('lv-night', { type: 'raster', tiles: shadeTiles(), tileSize: 256, maxzoom: SHADE_MAXZOOM });
    }
    if (!map.getLayer('lv-night')) addLayer({ id: 'lv-night', type: 'raster', source: 'lv-night', paint: { 'raster-fade-duration': 0 } });
    applyLights();
  }

  // The lights of the towns on the night side: points drawn from the lit
  // cells of NASA's Black Marble (vendor/night-lights.bin.gz, WidgetEarth),
  // some 240 000 for each step of the widget's density, each lit by the
  // chip as the Sun goes down where it stands, sharp at every zoom.
  // A layer of MapLibre's own (type custom) right over the night, for the
  // day and night only, as bright as the widget's slider says (percent, 0
  // for none).
  var LIGHTS_URL = 'vendor/night-lights.bin.gz';
  var nightLights = percent(typeof LIGHTS_INIT === 'undefined' ? null : LIGHTS_INIT);
  if (nightLights === null) nightLights = 70;
  var lightsDensity = lightsDensityOf(typeof LIGHTS_DENSITY_INIT === 'undefined' ? null : LIGHTS_DENSITY_INIT);
  if (lightsDensity === null) lightsDensity = WidgetEarth.NIGHT_LIGHTS.density[2];
  var lights = { layer: null, cells: null, vertices: null, loading: false, rebuild: 0, sun: [0, 0, 1] };
  // The points a cell of full light gets, within the bounds, or null.
  function lightsDensityOf(value) {
    var d = parseFloat(value), b = WidgetEarth.NIGHT_LIGHTS.density;
    return isFinite(d) ? Math.max(b[0], Math.min(b[1], d)) : null;
  }
  // The points again for the density, once a frame at most while the
  // slider moves.
  function rebuildLights() {
    if (!lights.cells || lights.rebuild) return;
    lights.rebuild = requestAnimationFrame(function () {
      lights.rebuild = 0;
      lights.vertices = WidgetEarth.nightLightsVertices(lights.cells, lightsDensity);
      if (map && map.triggerRepaint) map.triggerRepaint();
    });
  }
  function applyLights() {
    if (!dayNight || !(nightLights > 0)) {
      if (map.getLayer('lv-lights')) map.removeLayer('lv-lights');
      return;
    }
    if (!lights.layer) lights.layer = makeLightsLayer();
    if (!map.getLayer('lv-lights')) addLayer(lights.layer);
    loadLights();
    if (map.triggerRepaint) map.triggerRepaint();
  }
  function makeLightsLayer() {
    return {
      id: 'lv-lights',
      type: 'custom',
      renderingMode: '2d',
      programs: {},
      vbo: null,
      uploaded: null,
      count: 0,
      failed: false,
      onAdd: function () {},
      onRemove: function (m, gl) {
        var self = this;
        Object.keys(this.programs).forEach(function (k) {
          var pr = self.programs[k];
          if (pr) { gl.deleteProgram(pr.p); gl.deleteVertexArray(pr.vao); }
        });
        this.programs = {};
        if (this.vbo) gl.deleteBuffer(this.vbo);
        this.vbo = null;
        this.uploaded = null;
      },
      // The program for MapLibre's projection variant (flat or globe), made once.
      program: function (gl, sd) {
        if (sd.variantName in this.programs) return this.programs[sd.variantName];
        var ok = true;
        function sh(type, src) {
          var x = gl.createShader(type);
          gl.shaderSource(x, src);
          gl.compileShader(x);
          if (!gl.getShaderParameter(x, gl.COMPILE_STATUS)) { ok = false; console.warn('[gl] lv-lights shader: ' + gl.getShaderInfoLog(x)); }
          return x;
        }
        var pr = gl.createProgram();
        var v = sh(gl.VERTEX_SHADER, '#version 300 es\n' + sd.vertexShaderPrelude + '\n' + sd.define + '\n' + WidgetEarth.NIGHT_LIGHTS_VS);
        var f = sh(gl.FRAGMENT_SHADER, WidgetEarth.NIGHT_LIGHTS_FS);
        gl.attachShader(pr, v);
        gl.attachShader(pr, f);
        gl.linkProgram(pr);
        gl.deleteShader(v);
        gl.deleteShader(f);
        if (!ok || !gl.getProgramParameter(pr, gl.LINK_STATUS)) {
          console.warn('[gl] lv-lights link: ' + gl.getProgramInfoLog(pr));
          gl.deleteProgram(pr);
          return (this.programs[sd.variantName] = null);
        }
        var loc = {}, n = gl.getProgramParameter(pr, gl.ACTIVE_UNIFORMS);
        for (var i = 0; i < n; i++) {
          var name = gl.getActiveUniform(pr, i).name.replace(/\[0\]$/, '');
          loc[name] = gl.getUniformLocation(pr, name);
        }
        var vao = gl.createVertexArray();
        gl.bindVertexArray(vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
        var ap = gl.getAttribLocation(pr, 'a_pos');
        gl.enableVertexAttribArray(ap);
        gl.vertexAttribPointer(ap, 3, gl.FLOAT, false, 0, 0);
        gl.bindVertexArray(null);
        return (this.programs[sd.variantName] = { p: pr, loc: loc, vao: vao });
      },
      render: function (gl, args) {
        var fade = lightsFade();
        if (this.failed || !lights.vertices || !(nightLights > 0) || !(fade > 0)) return;
        if (!this.vbo) this.vbo = gl.createBuffer();
        // New points (first time, or a new density): to the chip again.
        if (this.uploaded !== lights.vertices) {
          gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
          gl.bufferData(gl.ARRAY_BUFFER, lights.vertices, gl.STATIC_DRAW);
          this.uploaded = lights.vertices;
          this.count = lights.vertices.length / 3;
        }
        var sd = args.shaderData, d = args.defaultProjectionData, pr = this.program(gl, sd);
        if (!pr) { this.failed = true; return; }
        var u = pr.loc, look = WidgetEarth.nightLightsLook(map.getZoom(), lightsDensity, sd.variantName === 'globe' ? map.getCenter().lat : null), dpr = window.devicePixelRatio || 1;
        gl.useProgram(pr.p);
        gl.uniformMatrix4fv(u.u_projection_matrix, false, d.mainMatrix);
        if (u.u_projection_fallback_matrix) gl.uniformMatrix4fv(u.u_projection_fallback_matrix, false, d.fallbackMatrix);
        if (u.u_projection_tile_mercator_coords) gl.uniform4fv(u.u_projection_tile_mercator_coords, d.tileMercatorCoords);
        if (u.u_projection_clipping_plane) gl.uniform4fv(u.u_projection_clipping_plane, d.clippingPlane);
        if (u.u_projection_transition) gl.uniform1f(u.u_projection_transition, d.projectionTransition);
        gl.uniform3fv(u.u_sun, lights.sun);
        gl.uniform1f(u.u_opacity, nightLights / 100);
        gl.uniform1f(u.u_size, look.size * dpr);
        gl.uniform1f(u.u_gain, look.gain * fade);
        gl.uniform1f(u.u_keep, look.keep);
        // Added to what is under them: lights glow, and many in one place glow more.
        gl.enable(gl.BLEND);
        gl.blendFuncSeparate(gl.ONE, gl.ONE, gl.ZERO, gl.ONE);
        gl.disable(gl.DEPTH_TEST);
        gl.disable(gl.STENCIL_TEST);
        gl.disable(gl.CULL_FACE);
        gl.bindVertexArray(pr.vao);
        // Flat, the copies of the world on either side; on the globe one is all.
        var shifts = sd.variantName === 'globe' ? [0] : [-1, 0, 1];
        for (var k = 0; k < shifts.length; k++) {
          gl.uniform1f(u.u_shift, shifts[k]);
          gl.drawArrays(gl.POINTS, 0, this.count);
        }
        gl.bindVertexArray(null);
      }
    };
  }
  // How much of the lights shows: all of them over a country, fading out
  // as the map closes in on half of France (WidgetEarth.nightLightsFade).
  function lightsFade() {
    return WidgetEarth.nightLightsFade(WidgetEarth.viewWidthKm(map.getContainer().clientWidth, map.getZoom(), map.getCenter().lat));
  }
  // Read once, the first time the lights are on; the file is gzipped.
  function loadLights() {
    if (lights.cells || lights.loading || typeof fetch !== 'function') return;
    lights.loading = true;
    fetch(LIGHTS_URL).then(function (r) { return r.arrayBuffer(); }).then(gunzip).then(function (buf) {
      lights.cells = WidgetEarth.decodeNightLights(buf);
      lights.vertices = WidgetEarth.nightLightsVertices(lights.cells, lightsDensity);
      if (map && map.triggerRepaint) map.triggerRepaint();
    }).catch(function (e) { lights.loading = false; console.warn('night lights: ' + e); });
  }
  // The bytes of a gzip file, undone (left as they are if not gzipped).
  function gunzip(buf) {
    var b = new Uint8Array(buf, 0, 2);
    if (b[0] !== 0x1f || b[1] !== 0x8b) return buf;
    return new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
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
      addLayer({
        id: TEMP_LAYER, type: 'raster', source: TEMP_SOURCE,
        paint: { 'raster-opacity': tempEntry.opacity, 'raster-fade-duration': 0, 'raster-resampling': 'linear' }
      });
    }
    setLines('temperature', true);
  }

  // The color layers hide the base map: the coasts and land borders drawn
  // again over them, from the widget's own file (vendor/coast-borders.bin,
  // Natural Earth, about 500 m), the same on every base map and offline.
  // On top of the weather layers (see the stack below). Shown while a layer
  // wants them (setLines) and the widget's setting lets them
  // (setLinesShown), the file read once. Hidden, never removed: from one
  // color layer to another they stay as they are, tiles and all.
  var homeMarker = null;      // the widget's place
  var LINES_LAYER = 'lv-lines', LINES_SOURCE = 'lv-lines-src', LINES_URL = 'vendor/coast-borders.bin';
  // Under the dark lines, a light edge: they still show where the map is
  // dark, the night side above all, now that the night turns with the
  // time bar.
  var LINES_HALO = 'lv-lines-halo';
  var LINES_WIDTH = [0, 1.7, 2, 1.3, 4, 1.0, 6, 1.2, 10, 1.8];
  function linesWidth(extra) {
    var e = ['interpolate', ['linear'], ['zoom']];
    for (var i = 0; i < LINES_WIDTH.length; i += 2) e.push(LINES_WIDTH[i], LINES_WIDTH[i + 1] + extra);
    return e;
  }
  var linesOwners = {}, linesData = null, linesLoading = false;
  var linesShown = typeof LINES_INIT === 'undefined' || LINES_INIT !== false;
  function linesWanted() {
    if (!linesShown) return false;
    for (var k in linesOwners) return true;
    return false;
  }
  // Called by restoreRuntimeStyle() while the swap ends, so not held by it.
  function applyLines() {
    if (!styleReady) return;
    if (!linesWanted()) {
      [LINES_HALO, LINES_LAYER].forEach(function (id) {
        if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', 'none');
      });
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
    if (!map.getLayer(LINES_HALO)) {
      addLayer({
        id: LINES_HALO, type: 'line', source: LINES_SOURCE,
        layout: { 'line-join': 'round', visibility: 'visible' },
        paint: { 'line-color': 'rgba(235, 235, 235, 0.3)', 'line-width': linesWidth(1.6), 'line-blur': 1 }
      });
    } else map.setLayoutProperty(LINES_HALO, 'visibility', 'visible');
    if (map.getLayer(LINES_LAYER)) {
      map.setLayoutProperty(LINES_LAYER, 'visibility', 'visible');
      return;
    }
    addLayer({
      id: LINES_LAYER, type: 'line', source: LINES_SOURCE,
      layout: { 'line-join': 'round', visibility: 'visible' },
      paint: {
        'line-color': 'rgba(20, 20, 20, 0.6)',
        // Thicker far out: on the whole globe (zoom ~1) a hairline is lost
        // in the colors. Thinnest around zoom 4, then wider again close in.
        'line-width': linesWidth(0)
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
    closeCredits();
    watchCredits(attribution._container);
  }
  // The credits are an aside: folded at every start (MapLibre opens them
  // until the first move), and whenever the widget is hidden.
  function closeCredits() {
    var el = attribution && attribution._container;
    if (!el) return;
    el.removeAttribute('open');
    el.classList.remove('maplibregl-compact-show');
  }
  if (typeof window !== 'undefined') window.closeCredits = closeCredits;
  // The credits opened or closed (the (i) button, or MapLibre folding them
  // on the first move), and where they stand while open: the widget hides
  // what it draws over them meanwhile, only what they cover.
  // "[credits] 1 left top right bottom" (view pixels) or "[credits] 0".
  var creditsObserver = null, creditsResize = null, creditsSent = null;
  function watchCredits(el) {
    if (creditsObserver) creditsObserver.disconnect();
    if (creditsResize) creditsResize.disconnect();
    creditsObserver = creditsResize = null;
    if (!el || typeof MutationObserver === 'undefined') return;
    var report = function () {
      var open = el.hasAttribute('open') || el.classList.contains('maplibregl-compact-show');
      var msg = '0';
      if (open) {
        var b = el.getBoundingClientRect();
        msg = '1 ' + [b.left, b.top, b.right, b.bottom].map(Math.round).join(' ');
      }
      if (msg === creditsSent) return;
      creditsSent = msg;
      console.log('[credits] ' + msg);
    };
    creditsObserver = new MutationObserver(report);
    creditsObserver.observe(el, { attributes: true, attributeFilter: ['open', 'class'] });
    // Its lines wrap again as the widget is resized.
    if (typeof ResizeObserver !== 'undefined') {
      creditsResize = new ResizeObserver(report);
      creditsResize.observe(el);
      creditsResize.observe(document.body);
    }
    creditsSent = null;
    report();
  }
  // The Sun of the picture shown while the animation runs (setSkyTime),
  // now otherwise: the night, the glow and the sky around the globe turn
  // with the time bar.
  function skyDate() { return new Date(skyTime == null ? Date.now() : skyTime); }
  function moveSun() {
    var sun = WidgetEarth.subsolarPoint(skyDate());
    map.setLight(lightAt(dayNight ? { anchor: 'map', position: WidgetEarth.sunLightPosition(sun) } : EVEN_LIGHT));
    drawShade(sun);
    lights.sun = WidgetEarth.placeVector(sun.lat, sun.lon);
    if (map.getLayer('lv-lights') && map.triggerRepaint) map.triggerRepaint();
    drawSpaceSoon();
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

  function addFrameEntry(entry) {
    entry.shownAt = renderSeq;
    if (!map.getSource(entry.sourceId)) {
      map.addSource(entry.sourceId, { type: 'raster', tiles: frameTiles(entry.url), tileSize: entry.tileSize, maxzoom: entry.maxZoom });
    }
    if (map.getLayer(entry.layerId)) return;
    addLayer({
      id: entry.layerId,
      type: 'raster',
      source: entry.sourceId,
      layout: { visibility: frameVisibility(entry) },
      paint: {
        'raster-opacity': entry.opacity,
        'raster-opacity-transition': { duration: 0, delay: 0 },
        'raster-fade-duration': 0
      }
    });
  }

  // Severity colors come from the engine's style function, computed once per
  // feature into its properties, as the Leaflet page styles each path. Right
  // under the radar's images (see the stack), the line over the fill.
  function addAlertsLayers() {
    if (map.getLayer('lv-alerts-fill')) return;
    if (!map.getSource('lv-alerts')) map.addSource('lv-alerts', { type: 'geojson', data: alertsEntry.geojson });
    addLayer({
      id: 'lv-alerts-fill', type: 'fill', source: 'lv-alerts',
      paint: { 'fill-color': ['get', '__fillColor'], 'fill-opacity': ['get', '__fillOpacity'] }
    });
    addLayer({
      id: 'lv-alerts-line', type: 'line', source: 'lv-alerts',
      paint: { 'line-color': ['get', '__color'], 'line-width': ['get', '__weight'] }
    });
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
    if (!held && e.held) e.shownAt = renderSeq;
    e.held = held;
    if (map.getLayer(e.layerId)) map.setLayoutProperty(e.layerId, 'visibility', frameVisibility(e));
    // Drawn again with every tile already cached, no source data may
    // come: its waiters look once the map has drawn it.
    if (!held && pendingCheck[e.sourceId] && pendingCheck[e.sourceId].length) {
      map.once('render', function () { (pendingCheck[e.sourceId] || []).slice().forEach(function (c) { c(); }); });
    }
  }
  function entryOf(handle) { return frameById.get(handle.layerId) || null; }
  // Frames drawn since: a frame added or shown again has no tile asked for
  // until the map draws it, and MapLibre calls such a source loaded.
  var renderSeq = 0;
  /** The view as the loading bar keys it for frame e: the zoom of its
      tiles (a 256 grid takes those of the map's zoom + 1; past the last
      zoom the same tiles serve) and the area. */
  function viewNow(e) {
    var b = map.getBounds ? map.getBounds() : null;
    var z = Math.round(map.getZoom()) + (e.tileSize === 256 ? 1 : 0);
    return {
      z: e.maxZoom != null ? Math.min(z, e.maxZoom) : z,
      box: b ? [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()] : null
    };
  }
  var SEEN_PER_ZOOM = 4;       // areas kept per zoom and frame
  /** A frame in at the view now: noted (frameCounted). */
  function noteSeen(e) {
    var v = viewNow(e), seen = e.seen = e.seen || {}, list = seen[v.z] = seen[v.z] || [];
    if (list.some(function (b) { return covers(b, v.box); })) return;
    list.push(v.box);
    if (list.length > SEEN_PER_ZOOM) list.shift();
  }
  /** Whether the frame was in at this zoom over the area now. */
  function seenHere(e) {
    var v = viewNow(e), list = e.seen && e.seen[v.z];
    return !!list && list.some(function (b) { return covers(b, v.box); });
  }
  function covers(b, box) {
    if (!b || !box) return !b && !box;
    var eps = 1e-6;
    return box[0] >= b[0] - eps && box[1] >= b[1] - eps && box[2] <= b[2] + eps && box[3] <= b[3] + eps;
  }
  /** Whether a frame has its tiles for the map as it is: a held one's
      loaded state is from before the move, its tiles at the new scale are not asked for. */
  function frameReadyNow(handle) {
    var e = entryOf(handle);
    return !!map.getSource(handle.sourceId) && !(e && e.held) && map.isSourceLoaded(handle.sourceId);
  }
  function holdHiddenFrames(hold) {
    moving = hold;
    var job = ++revealJob, i;
    if (hold) {
      for (i = 0; i < frameRegistry.length; i++) if (!(frameRegistry[i].opacity > 0)) holdFrame(frameRegistry[i], true);
      return;
    }
    // A frame waited for comes back at once.
    for (i = 0; i < frameRegistry.length; i++) {
      var w = frameRegistry[i];
      if (w.held && pendingCheck[w.sourceId] && pendingCheck[w.sourceId].length) holdFrame(w, false);
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
    // Space on the globe is the page's own canvas under the map (drawSpace).
    if (projection === 'globe') sky['sky-color'] = sky['fog-color'] = 'rgba(0,0,0,0)';
    sky['atmosphere-blend'] = ['interpolate', ['linear'], ['zoom'], 0, 0.5 * g, 4, 0.35 * g, 7, 0];
    map.setSky(sky);
    drawSpaceSoon();
  }

  // Around the globe, a small model of the sky seen by MapLibre's camera,
  // at the time of the picture shown (setSkyTime) or now: black space and
  // the stars where they are (they turn with the globe), the Sun in its
  // true direction, far away, and the Moon on its true orbit, brought in
  // to MOON_ORBIT Earth radii, MOON_SIZE across. The Moon passes behind the
  // globe (on the canvas under the map's) and in front of it (on a canvas
  // over it), lit by the Sun: its phase is the one seen from the camera.
  var STARS = 9000, SPACE = '#02040a', MOON_ORBIT = 1.45, MOON_SIZE = 0.2;
  // The colors round the Sun, from 1.5 to 3.6 of its radius: [place, color].
  var SUN_RINGS = [[0, 'rgba(255,120,90,0)'], [0.18, 'rgba(255,120,90,0.10)'], [0.36, 'rgba(255,214,96,0.09)'],
    [0.54, 'rgba(120,230,150,0.07)'], [0.72, 'rgba(110,170,255,0.08)'], [0.88, 'rgba(180,130,255,0.05)'], [1, 'rgba(180,130,255,0)']];
  var space = null, spaceFrame = 0, skyTime = null;
  // How bright the Sun's light at the globe's edge (rimGlow), percent: set
  // from the widget's slider; 60 by default, the strength it was drawn for.
  var RIM_FULL = 60, rimPercent = percent(typeof RIM_INIT === 'undefined' ? null : RIM_INIT);
  if (rimPercent === null) rimPercent = RIM_FULL;
  // The stars, the Sun and the Moon come and go together (one setting).
  var skyShown = typeof SKY_INIT === 'undefined' || SKY_INIT !== false;
  function makeSpace() {
    var canvas = document.createElement('canvas');
    canvas.id = 'lv-space';
    canvas.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none;display:none';
    var front = document.createElement('canvas');
    front.id = 'lv-space-front';
    front.style.cssText = canvas.style.cssText;
    var under = map.getCanvasContainer();
    map.getContainer().insertBefore(canvas, under);
    map.getContainer().insertBefore(front, under.nextSibling);
    var raw = WidgetEarth.starField(STARS, 20261114), n = STARS;
    // Each star as sin ra cos dec, sin dec, cos ra cos dec (the sky as it is
    // at sidereal time 0), its size and its alpha.
    var stars = new Float32Array(n * 5);
    for (var i = 0; i < n; i++) {
      var ra = raw[i * 3] * Math.PI / 180, dec = raw[i * 3 + 1] * Math.PI / 180, b = raw[i * 3 + 2];
      stars[i * 5] = Math.sin(ra) * Math.cos(dec);
      stars[i * 5 + 1] = Math.sin(dec);
      stars[i * 5 + 2] = Math.cos(ra) * Math.cos(dec);
      stars[i * 5 + 3] = 0.7 + 1.6 * b;
      stars[i * 5 + 4] = 0.25 + 0.75 * b;
    }
    space = { canvas: canvas, ctx: canvas.getContext('2d'), front: front, fctx: front.getContext('2d'), stars: stars };
  }
  // The globe's radius on screen, px: the farthest a point on the meridian
  // through the middle of the map projects from it (towards the equator,
  // never past a pole). globeApparentRadius() comes out a few percent short.
  function globeEdge(c, mid) {
    var dir = c.lat >= 0 ? -1 : 1, lo = 0, hi = 90;
    function dist(a) { var p = map.project([c.lng, c.lat + dir * a]); return Math.hypot(p.x - mid.x, p.y - mid.y); }
    for (var i = 0; i < 24; i++) {   // ternary search: the distance rises to the edge, then falls
      var m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
      if (dist(m1) < dist(m2)) lo = m1; else hi = m2;
    }
    return dist((lo + hi) / 2);
  }
  function drawSpaceSoon() {
    // (No animation frames in the unit tests' stand-in page.)
    if (!map || spaceFrame || typeof requestAnimationFrame !== 'function') return;
    spaceFrame = requestAnimationFrame(function () { spaceFrame = 0; drawSpace(); });
  }
  function drawSpace() {
    if (!map || !styleReady) return;
    if (!space) makeSpace();
    var canvas = space.canvas, show = projection === 'globe';
    canvas.style.display = space.front.style.display = show ? '' : 'none';
    if (!show) return;
    var box = map.getContainer(), w = box.clientWidth, h = box.clientHeight, dpr = window.devicePixelRatio || 1;
    if (!(w > 0 && h > 0)) return;
    [canvas, space.front].forEach(function (cv) {
      if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) {
        cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
      }
    });
    var ctx = space.ctx, fctx = space.fctx;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    fctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    fctx.clearRect(0, 0, w, h);
    ctx.fillStyle = SPACE;
    ctx.fillRect(0, 0, w, h);
    var c = map.getCenter(), mid = map.project(c), f = WidgetEarth.CAMERA * h;
    var r = globeEdge(c, mid);
    if (r > Math.hypot(w, h)) return;   // the globe covers it all
    var cam = WidgetEarth.camera(c.lat, c.lng, map.getBearing(), map.getPitch());
    var now = skyDate(), g = WidgetEarth.gmst(now) * Math.PI / 180, cg = Math.cos(g), sg = Math.sin(g);
    var F = cam.fwd, R = cam.right, U = cam.up, st = space.stars, v = [0, 0, 0];
    ctx.fillStyle = '#fff';
    for (var i = 0; skyShown && i < st.length; i += 5) {
      // The sky turned by the sidereal time: longitude = right ascension - GMST.
      v[0] = st[i] * cg - st[i + 2] * sg; v[1] = st[i + 1]; v[2] = st[i + 2] * cg + st[i] * sg;
      var z = v[0] * F[0] + v[1] * F[1] + v[2] * F[2];
      if (z <= 0) continue;
      var x = mid.x + f * (v[0] * R[0] + v[1] * R[1] + v[2] * R[2]) / z;
      var y = mid.y - f * (v[0] * U[0] + v[1] * U[1] + v[2] * U[2]) / z;
      if (x < 0 || y < 0 || x > w || y > h) continue;
      var s = st[i + 3];
      ctx.globalAlpha = st[i + 4];
      ctx.fillRect(x - s / 2, y - s / 2, s, s);
    }
    ctx.globalAlpha = 1;
    var sun = WidgetEarth.subsolarPoint(now), moon = WidgetEarth.sublunarPoint(now);
    var sv = WidgetEarth.placeVector(sun.lat, sun.lon), mv = WidgetEarth.placeVector(moon.lat, moon.lon);
    var earthR = WidgetEarth.earthRadiusPx(r, f);
    var pos = WidgetEarth.cameraPosition(cam, WidgetEarth.placeVector(c.lat, c.lng), earthR, f);
    var earthDist = Math.hypot(pos[0], pos[1], pos[2]);

    // The Sun, at infinity: where its direction meets the screen, hidden
    // by the globe when it is behind it. As it comes near the globe's edge,
    // its light through the air at the Earth's rim says where it is: a thin
    // bright line right at the edge, in a blue glow that fades out into
    // space (rimGlow), like the atmosphere of the day side.
    var sp = skyShown ? WidgetEarth.projectDir(cam, sv, f) : null, sunR = 0.024 * Math.min(w, h);
    if (sp) {
      sp = { x: mid.x + sp.x, y: mid.y + sp.y };
      var off = Math.hypot(sp.x - mid.x, sp.y - mid.y);
      var near = Math.max(0, Math.min(1, 1 - (off - r) / (r * 0.6))) * rimPercent / RIM_FULL;
      if (near > 0) {
        // Brightest towards the Sun, gone 50 degrees either side (all
        // round the edge when the Sun is straight behind the globe).
        var phi = Math.atan2(sp.y - mid.y, sp.x - mid.x);
        var spread = Math.min(0.5, 0.14 + 0.36 * Math.max(0, 1 - off / r));
        // Straight behind the globe, the light comes round the whole edge.
        var round = Math.max(0, 1 - off / (r * 0.7));
        rimGlow(phi, spread, round, 0.16, '110,170,255', 0.5 * near);
        rimGlow(phi, spread * 0.8, round, 0.07, '150,205,255', 0.55 * near);
        rimGlow(phi, spread * 0.5, round, 0.025, '255,240,214', 0.8 * near);
      }
      // A yellow disc, paler at its heart, in a warm glow; round it, faint
      // rings of color (SUN_RINGS): the iridescence of a light seen through
      // a lens, red inside to blue outside, added to what is under them.
      var glowR = sunR * 2.4, halo = ctx.createRadialGradient(sp.x, sp.y, sunR * 0.6, sp.x, sp.y, glowR);
      halo.addColorStop(0, 'rgba(255,222,130,0.42)');
      halo.addColorStop(0.4, 'rgba(255,198,100,0.11)');
      halo.addColorStop(1, 'rgba(255,186,90,0)');
      ctx.fillStyle = halo;
      ctx.beginPath(); ctx.arc(sp.x, sp.y, glowR, 0, 2 * Math.PI); ctx.fill();
      var ringR = sunR * 3.6, rings = ctx.createRadialGradient(sp.x, sp.y, sunR * 1.5, sp.x, sp.y, ringR);
      SUN_RINGS.forEach(function (s) { rings.addColorStop(s[0], s[1]); });
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = rings;
      ctx.beginPath(); ctx.arc(sp.x, sp.y, ringR, 0, 2 * Math.PI); ctx.fill();
      ctx.restore();
      var disc = ctx.createRadialGradient(sp.x, sp.y, 0, sp.x, sp.y, sunR);
      disc.addColorStop(0, '#fffbe8');
      disc.addColorStop(0.55, '#fff1b8');
      disc.addColorStop(1, '#ffe07a');
      ctx.fillStyle = disc;
      ctx.beginPath(); ctx.arc(sp.x, sp.y, sunR, 0, 2 * Math.PI); ctx.fill();
    }

    // A glow round the globe's edge, added to the sky: `rgb` at `alpha`
    // right at the edge, fading out over `reach` globe radii; brightest at
    // the angle phi, down to `round` of it `spread` turns either side and
    // beyond (0: gone there). Drawn on a canvas of
    // its own, so cutting it to its arc leaves the stars alone.
    function rimGlow(phi, spread, round, reach, rgb, alpha) {
      var gc = space.glow || (space.glow = document.createElement('canvas')), g = gc.getContext('2d');
      if (gc.width !== canvas.width || gc.height !== canvas.height) { gc.width = canvas.width; gc.height = canvas.height; }
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.globalCompositeOperation = 'source-over';
      g.clearRect(0, 0, w, h);
      var r0 = r * 0.985, r1 = r * (1 + reach), edge = (r - r0) / (r1 - r0);
      var ring = g.createRadialGradient(mid.x, mid.y, r0, mid.x, mid.y, r1);
      var col = function (a) { return 'rgba(' + rgb + ',' + Math.min(1, alpha * a).toFixed(3) + ')'; };
      ring.addColorStop(0, col(0));
      ring.addColorStop(edge, col(1));
      // Thinning air: half as bright every eighth of the way out.
      for (var k = 1; k <= 8; k++) ring.addColorStop(edge + (1 - edge) * k / 8, col(k === 8 ? 0 : Math.pow(0.5, k)));
      g.fillStyle = ring;
      g.beginPath(); g.arc(mid.x, mid.y, r1, 0, 2 * Math.PI); g.fill();
      var arc = g.createConicGradient(phi + Math.PI, mid.x, mid.y);
      var part = function (a) { return 'rgba(0,0,0,' + (round + (1 - round) * a).toFixed(3) + ')'; };
      arc.addColorStop(0, part(0));
      [[1, 0], [0.7, 0.2], [0.4, 0.65], [0, 1]].forEach(function (st) {
        arc.addColorStop(Math.max(0, 0.5 - spread * st[0]), part(st[1]));
      });
      [[0.4, 0.65], [0.7, 0.2], [1, 0]].forEach(function (st) {
        arc.addColorStop(Math.min(1, 0.5 + spread * st[0]), part(st[1]));
      });
      arc.addColorStop(1, part(0));
      g.globalCompositeOperation = 'destination-in';
      g.fillStyle = arc;
      g.fillRect(0, 0, w, h);
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.drawImage(gc, 0, 0, w, h);
      ctx.restore();
    }

    // The Moon, a ball in space: under the map when farther than the
    // Earth's centre (the globe hides it), over it when nearer. Only with
    // the whole Earth in view: it fades out over the first zoom step.
    var moonAlpha = skyShown ? Math.max(0, Math.min(1, 1 - (map.getZoom() - map.getMinZoom() - 0.1) / 0.5)) : 0;
    var X = [mv[0] * MOON_ORBIT * earthR, mv[1] * MOON_ORBIT * earthR, mv[2] * MOON_ORBIT * earthR];
    var mp = moonAlpha > 0 ? WidgetEarth.projectPoint(cam, pos, X, f) : null;
    if (mp) {
      var mx = mid.x + mp.x, my = mid.y + mp.y, mrad = f * MOON_SIZE / 2 * earthR / mp.z;
      var inFront = mp.dist < earthDist;
      if (mx > -mrad && my > -mrad && mx < w + mrad && my < h + mrad) drawMoon(inFront ? fctx : ctx, mx, my, mrad);
      mp = { x: mx, y: my, r: mrad, front: inFront, alpha: moonAlpha, textured: !!space.moonTex };
    }
    space.last = { sun: sp, moon: mp, edge: r, time: now.getTime() };   // for the test bench

    // Its texture on the ball, drawn through a small canvas, as the camera
    // sees it (WidgetEarth.moonView): lit by the same Sun as the globe, its
    // bright side always turns the same way as the Earth's day side. Its
    // near side faces the Earth, so on the small orbit the camera sees the
    // far side whenever the Moon passes in front of the globe.
    function drawMoon(cx, x, y, rad) {
      var tex = space.moonTex;
      if (!tex) { loadMoonTexture(); return; }
      var size = Math.max(2, Math.ceil(2 * rad * dpr) + 2), mc = space.moonCanvas;
      if (!mc) mc = space.moonCanvas = document.createElement('canvas');
      if (mc.width !== size) { mc.width = mc.height = size; space.moonPixels = mc.getContext('2d').createImageData(size, size); }
      var img = space.moonPixels;
      WidgetEarth.renderMoon(img.data, size, rad * dpr, WidgetEarth.moonView(cam, pos, X), mv, sv, tex, moonAlpha);
      mc.getContext('2d').putImageData(img, 0, 0);
      cx.drawImage(mc, x - size / dpr / 2, y - size / dpr / 2, size / dpr, size / dpr);
    }
  }

  // The Moon's colors (vendor/moon.jpg), read once into pixels: fetched as
  // a blob so the canvas that reads them is not tainted by the file:// page.
  var MOON_URL = 'vendor/moon.jpg', moonLoading = false;
  function loadMoonTexture() {
    if (moonLoading || !space) return;
    moonLoading = true;
    fetch(MOON_URL).then(function (r) { return r.blob(); }).then(function (b) { return createImageBitmap(b); }).then(function (bmp) {
      var c = document.createElement('canvas');
      c.width = bmp.width; c.height = bmp.height;
      var g = c.getContext('2d');
      g.drawImage(bmp, 0, 0);
      space.moonTex = g.getImageData(0, 0, c.width, c.height);
      drawSpaceSoon();
    }).catch(function (e) { console.warn('moon texture: ' + e); });
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
  // the bottom, the coasts and borders on top, the whole stack over the
  // base map. A layer is added right at its place (addLayer, beforeFor);
  // restack() puts every layer back at its place, with as few moves as it
  // can, after a new order and on each 'styledata' (a layer added some
  // other way).
  var STACK_DEFAULT = ['radar', 'satellite', 'isobars', 'precipitation', 'clouds',
    'temperature', 'pressure', 'humidity', 'dewpoint', 'airquality'];
  var stackOrder = STACK_DEFAULT.slice(), restacking = false;
  /** The ids of order known, once each; a missing one right after its
      neighbour above it in the default (an order saved before it). */
  function normStackOrder(order) {
    var out = [];
    (order || []).forEach(function (g) {
      if (STACK_DEFAULT.indexOf(g) >= 0 && out.indexOf(g) < 0) out.push(g);
    });
    STACK_DEFAULT.forEach(function (g, i) {
      if (out.indexOf(g) >= 0) return;
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        var k = out.indexOf(STACK_DEFAULT[j]);
        if (k >= 0) { at = k + 1; break; }
      }
      out.splice(at, 0, g);
    });
    return out;
  }
  /** [group, rank inside the group] of a layer id; null for one not stacked. */
  function stackGroup(id) {
    if (id === 'lv-caps') return ['night', -1];
    if (id === 'lv-night') return ['night', 0];
    if (id === 'lv-lights') return ['night', 1];
    if (id === LINES_HALO) return ['lines', 0];
    if (id === LINES_LAYER) return ['lines', 1];
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
  /** The place of a layer id in the stack, bottom first: its group's level
      times 2 plus its rank inside the group; null for one not stacked. */
  function rankOf(id) {
    var g = stackGroup(id);
    if (!g) return null;
    var n = stackOrder.length, level = g[0] === 'night' ? -1 : g[0] === 'lines' ? n : n - 1 - stackOrder.indexOf(g[0]);
    return level * 2 + g[1];
  }
  function layersOrder() {
    return map.getLayersOrder ? map.getLayersOrder() : map.getStyle().layers.map(function (l) { return l.id; });
  }
  /** The layer a new layer id goes right under: the lowest of the stack
      above its place, undefined (on top) when none is, or for a layer not
      stacked. */
  function beforeFor(id) {
    var r = rankOf(id);
    if (r === null || !map) return undefined;
    var ids = layersOrder();
    for (var i = 0; i < ids.length; i++) {
      var q = rankOf(ids[i]);
      if (q !== null && q > r) return ids[i];
    }
    return undefined;
  }
  /** A layer (a style layer, or a custom one) added at its place. */
  function addLayer(layer) { map.addLayer(layer, beforeFor(layer.id)); }
  function restack() {
    if (!map || restacking || swapInProgress) return;
    var ids = layersOrder(), known = [];
    ids.forEach(function (id, pos) {
      var r = rankOf(id);
      if (r !== null) known.push({ id: id, rank: r, pos: pos });
    });
    var want = known.slice().sort(function (a, b) { return a.rank - b.rank || a.pos - b.pos; });
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
    /** Whether the map takes layers now (its first style has loaded). */
    isReady: function () { return styleReady; },

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
      map.on('move', drawSpaceSoon);
      map.on('resize', drawSpaceSoon);
      map.on('render', checkPrepared);
      map.on('render', function () { renderSeq++; });
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
      drawShade(WidgetEarth.subsolarPoint(skyDate()));
    },

    /** opts.anim: an image of the animation (glue-anim-radar.js), shown
        while the viewer's are hidden, over the animation's layers;
        opts.tileSize: the grid of its tiles, 256 or 512 (256 by default). */
    createFrameLayer: function (url, kind, opts) {
      var id = 'lv-frame-' + (frameSeq++), anim = !!(opts && opts.anim);
      var entry = {
        sourceId: 'lv-src-' + id,
        layerId: (anim ? 'lv-anim-' : '') + (kind === 'satellite' ? 'lv-layer-sat-' : 'lv-layer-radar-') + id,
        // Past the data's own resolution the map stretches the last level.
        kind: kind, url: url, opacity: 0, anim: anim,
        maxZoom: typeof WidgetAnimRadar !== 'undefined' ? WidgetAnimRadar.nativeZoom(url, maxZoom) : maxZoom,
        tileSize: opts && opts.tileSize === 512 ? 512 : 256
      };
      frameRegistry.push(entry);
      frameById.set(entry.layerId, entry);
      prepareNewFrame();
      // The handle is due now; only the map change waits for the style.
      if (!styleReady) map.once('load', function () { addFrameEntry(entry); });
      else if (!swapInProgress) addFrameEntry(entry);
      return { sourceId: entry.sourceId, layerId: entry.layerId };
    },

    onLayerReady: function (handle, cb) {
      var done = false, waiter = null;
      // ok false: settled on a tile error. The time out is not one: a slow
      // server may still bring the tiles, made again they would start over.
      function finish(ok) {
        if (done) return;
        done = true;
        map.off('sourcedata', onData);
        map.off('error', onError);
        clearTimeout(waiter);
        var list = pendingReady[handle.sourceId];
        if (list) list.splice(list.indexOf(finish), 1);
        var checks = pendingCheck[handle.sourceId];
        if (checks) checks.splice(checks.indexOf(check), 1);
        cb(ok !== false);
      }
      function check() { if (frameReadyNow(handle)) finish(true); }
      function onData(e) {
        if (e.sourceId === handle.sourceId) check();
      }
      // A dead tile host settles the layer too, so the animation never hangs.
      function onError(e) {
        if (e.sourceId === handle.sourceId || (e.error && e.error.sourceId === handle.sourceId)) {
          console.warn('[librewxr] map tile/source error:', e.error ? (e.error.message || e.error) : e);
          finish(false);
        }
      }
      map.on('sourcedata', onData);
      map.on('error', onError);
      var e = entryOf(handle);
      if (e && e.held && !moving) holdFrame(e, false);
      (pendingReady[handle.sourceId] = pendingReady[handle.sourceId] || []).push(finish);
      (pendingCheck[handle.sourceId] = pendingCheck[handle.sourceId] || []).push(check);
      waiter = setTimeout(function () {
        console.warn('[librewxr] frame layer not settled after 25 s: ' + handle.sourceId);
        finish(true);
      }, 25000);
      check();
    },

    /** Whether a frame has its tiles for the map as it is (not after a
        zoom that came while it was held back). */
    frameLoaded: function (handle) {
      return !!map && !!map.getLayer(handle.layerId) && frameReadyNow(handle);
    },

    /** Whether a frame counts as in for the loading bar: in now, or seen
        in before at this zoom over this area, its tiles then in the map's
        cache. Counted by frameLoaded, the bar fell at every move (the
        hidden frames held back) and went up and down while they came back
        two at a time, as if all were read again; now it goes down only for
        tiles that have to come (a zoom or an area not seen), then up. */
    frameCounted: function (handle) {
      var e = entryOf(handle);
      if (!e) return false;
      if (!e.held && renderSeq > e.shownAt && this.frameLoaded(handle)) {
        noteSeen(e);
        return true;
      }
      return seenHere(e);
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
      delete pendingCheck[handle.sourceId];
      if (waiting && waiting.length) setTimeout(function () { waiting.slice().forEach(function (f) { f(); }); }, 0);
      var e = frameById.get(handle.layerId);
      if (e) {
        frameById.delete(handle.layerId);
        frameRegistry.splice(frameRegistry.indexOf(e), 1);
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

    /** The stars, the Sun and the Moon around the globe, on or off. */
    setSkyShown: function (on) {
      skyShown = !!on;
      drawSpaceSoon();
    },

    /** The time (ms) of the Sun, the night and the sky around the globe:
        the picture's while the animation runs; null for now. */
    setSkyTime: function (ms) {
      var t = ms == null || !isFinite(ms) ? null : +ms;
      if (t === skyTime) return;
      skyTime = t;
      if (map && styleReady && !swapInProgress) moveSun();
      else drawSpaceSoon();
    },

    /** Where the space canvas last put the Sun and the Moon (test bench). */
    spaceState: function () { return space && space.last; },

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
      if (styleReady && map.getLayer('lv-night')) drawShade(WidgetEarth.subsolarPoint(skyDate()));
    },

    getNightDepth: function () { return nightDepth; },

    /** How bright the Sun's light at the globe's edge, percent; 0 for none. */
    setRimGlow: function (value) {
      var d = percent(value);
      if (d === null) return;
      rimPercent = d;
      drawSpaceSoon();
    },

    /** How bright the lights of the towns at night, percent; 0 for none. */
    setNightLights: function (value) {
      var d = percent(value);
      if (d === null) return;
      nightLights = d;
      if (styleReady && !swapInProgress) applyLights();
    },

    /** How many points the lights get: those of a cell of full light. */
    setNightLightsDensity: function (value) {
      var d = lightsDensityOf(value);
      if (d === null || d === lightsDensity) return;
      lightsDensity = d;
      rebuildLights();
    },

    /** The lights' setting and Sun (test bench). */
    nightLightsState: function () {
      return { percent: nightLights, density: lightsDensity, sun: lights.sun.slice(), shown: !!(map && map.getLayer('lv-lights')), loaded: !!lights.vertices, points: lights.vertices ? lights.vertices.length / 3 : 0, fade: map ? lightsFade() : 1 };
    },

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
        wants them. */
    setLines: setLines,
    setLinesShown: function (on) {
      linesShown = !!on;
      if (!swapInProgress) applyLines();
    },
    getLinesShown: function () { return linesShown; },
    /** The layer a weather layer of id goes right under, to be at its
        place in the stack (map.addLayer(layer, beforeFor(layer.id))). */
    beforeFor: beforeFor,
    /** A weather layer of the page's other scripts added at its place. */
    addLayer: function (layer) { addLayer(layer); },

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
