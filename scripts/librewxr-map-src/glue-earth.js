// ==========================================================================
// Glue script 2e: the Earth as a whole on the MapLibre map. Where the Sun is
// overhead, the day and the night as Web Mercator tiles the page draws (the
// map lays them over the Earth, flat or globe), and the zoom at which the
// whole Earth fits in the map. Loadable under Node for tests.
// ==========================================================================
var WidgetEarth = (function () {
  'use strict';

  var RAD = Math.PI / 180, DEG = 180 / Math.PI;

  /** Share of the map's smaller side the globe takes at the widest zoom. */
  var GLOBE_FILL = 0.94;

  function wrap180(d) { return ((d + 540) % 360) - 180; }

  /** Where the Sun is overhead at that instant, { lat, lon } in degrees:
      declination from the NOAA solar position formulas, longitude from UTC
      time corrected by the equation of time. Accurate to a fraction of a
      degree. The same computation as the RadioGlobe plasmoid. */
  function subsolarPoint(date) {
    var t = (date.getTime() / 86400000 + 2440587.5 - 2451545) / 36525;
    var meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360;
    var meanAnomaly = (357.52911 + t * (35999.05029 - t * 0.0001537)) % 360;
    var eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    var centre = Math.sin(meanAnomaly * RAD) * (1.914602 - t * (0.004817 + 0.000014 * t))
      + Math.sin(2 * meanAnomaly * RAD) * (0.019993 - 0.000101 * t)
      + Math.sin(3 * meanAnomaly * RAD) * 0.000289;
    var omega = 125.04 - 1934.136 * t;
    var apparentLongitude = meanLongitude + centre - 0.00569 - 0.00478 * Math.sin(omega * RAD);
    var meanObliquity = 23.439291 - t * (0.013004167 + t * (0.00000016667 - t * 0.000000502778));
    var obliquity = meanObliquity + 0.00256 * Math.cos(omega * RAD);
    var declination = Math.asin(Math.sin(obliquity * RAD) * Math.sin(apparentLongitude * RAD)) * DEG;
    var y = Math.pow(Math.tan(obliquity / 2 * RAD), 2);
    var equationOfTime = 4 * DEG * (
      y * Math.sin(2 * meanLongitude * RAD)
      - 2 * eccentricity * Math.sin(meanAnomaly * RAD)
      + 4 * eccentricity * y * Math.sin(meanAnomaly * RAD) * Math.cos(2 * meanLongitude * RAD)
      - 0.5 * y * y * Math.sin(4 * meanLongitude * RAD)
      - 1.25 * eccentricity * eccentricity * Math.sin(2 * meanAnomaly * RAD));   // minutes
    var utcHours = date.getUTCHours() + date.getUTCMinutes() / 60 + date.getUTCSeconds() / 3600;
    // Solar noon is at 12:00 UTC on the Greenwich meridian, minus the
    // equation of time; the Sun moves 15 degrees west per hour after that.
    return { lat: declination, lon: wrap180(-(utcHours - 12 + equationOfTime / 60) * 15) };
  }

  /** Height of the Sun above the horizon at (lat, lon), in degrees. */
  function sunAltitude(sun, lat, lon) {
    var s = Math.sin(lat * RAD) * Math.sin(sun.lat * RAD)
      + Math.cos(lat * RAD) * Math.cos(sun.lat * RAD) * Math.cos((lon - sun.lon) * RAD);
    return Math.asin(Math.max(-1, Math.min(1, s))) * DEG;
  }

  /** Degrees over which the night, and the day veil, fade in. */
  var TWILIGHT = 18;

  /** The day and the night for a Sun position as the RGBA pixels of one Web
      Mercator tile ({ z, x, y }, `size` pixels square), for the map to lay
      over the Earth. Over the night, black, fading in from the horizon to 18
      degrees below, where it is `depth` opaque (0..1); over the day, white,
      fading in the same way over the first 18 degrees above, up to
      `dayVeil`. The opacity grows as veils laid one over the other would:
      1 - (1 - depth)^share. */
  function shadeTile(sun, tile, size, depth, dayVeil) {
    var img = new Uint8ClampedArray(size * size * 4), n = Math.pow(2, tile.z);
    var sinD = Math.sin(sun.lat * RAD), cosD = Math.cos(sun.lat * RAD);
    var lnNight = Math.log(1 - Math.min(depth, 0.999)), lnDay = Math.log(1 - Math.min(dayVeil, 0.999));
    var cosH = new Float64Array(size), c;
    for (c = 0; c < size; c++) cosH[c] = Math.cos(((tile.x + (c + 0.5) / size) / n * 360 - 180 - sun.lon) * RAD);
    for (var r = 0; r < size; r++) {
      var lat = Math.atan(Math.sinh(Math.PI * (1 - 2 * (tile.y + (r + 0.5) / size) / n)));
      var a = Math.sin(lat) * sinD, b = Math.cos(lat) * cosD;
      for (c = 0; c < size; c++) {
        var h = Math.asin(Math.max(-1, Math.min(1, a + b * cosH[c]))) * DEG, k = (r * size + c) * 4;
        if (h < 0) {
          img[k + 3] = 255 * (1 - Math.exp(lnNight * Math.min(1, -h / TWILIGHT)));
        } else if (dayVeil > 0) {
          img[k] = img[k + 1] = img[k + 2] = 255;
          img[k + 3] = 255 * (1 - Math.exp(lnDay * Math.min(1, h / TWILIGHT)));
        }
      }
    }
    return img;
  }

  /** The same day and night for the chip, which draws them in one layer
      over the whole map instead of tiles made again at each move of the
      Sun: what its shader (NIGHT_FS) needs for a Sun position, { sun: [sin
      and cos of the Sun's latitude, its longitude in radians], ln: [ln(1 -
      depth), ln(1 - dayVeil)] } (a veil of 0 gives 0: none drawn). */
  function shadeUniforms(sun, depth, dayVeil) {
    return {
      sun: [Math.sin(sun.lat * RAD), Math.cos(sun.lat * RAD), sun.lon * RAD],
      ln: [Math.log(1 - Math.min(depth, 0.999)), Math.log(1 - Math.min(dayVeil, 0.999))]
    };
  }

  /** The color (premultiplied, 0..1) the chip gives the place at x, y in
      Mercator (0..1) with the uniforms u. Line for line what NIGHT_FS does. */
  function shadeFrom(u, x, y) {
    var lon = ((x - Math.floor(x)) * 2 - 1) * Math.PI;
    var lat = Math.atan(Math.sinh(Math.PI * (1 - 2 * y)));
    var s = Math.max(-1, Math.min(1, Math.sin(lat) * u.sun[0] + Math.cos(lat) * u.sun[1] * Math.cos(lon - u.sun[2])));
    var h = Math.asin(s) * DEG, a;
    if (h < 0) {
      a = 1 - Math.exp(u.ln[0] * Math.min(1, -h / TWILIGHT));
      return [0, 0, 0, a];
    }
    a = 1 - Math.exp(u.ln[1] * Math.min(1, h / TWILIGHT));
    return [a, a, a, a];
  }

  // For the mesh of the chip's layers (v_merc: Mercator 0..1, see
  // WidgetTemp.TempLayerGL.GLLayer).
  var NIGHT_FS = [
    '#version 300 es',
    'precision highp float;',
    'in vec2 v_merc;',
    'out vec4 fragColor;',
    'const float PI = 3.141592653589793;',
    'uniform vec3 u_sun;',
    'uniform vec2 u_ln;',
    'void main() {',
    '  float lon = (fract(v_merc.x) * 2.0 - 1.0) * PI;',
    '  float lat = atan(sinh(PI * (1.0 - 2.0 * v_merc.y)));',
    '  float s = clamp(sin(lat) * u_sun.x + cos(lat) * u_sun.y * cos(lon - u_sun.z), -1.0, 1.0);',
    '  float h = degrees(asin(s));',
    '  if (h < 0.0) {',
    '    fragColor = vec4(0.0, 0.0, 0.0, 1.0 - exp(u_ln.x * min(1.0, -h / ' + TWILIGHT + '.0)));',
    '  } else {',
    '    fragColor = vec4(1.0 - exp(u_ln.y * min(1.0, h / ' + TWILIGHT + '.0)));',
    '  }',
    '}'
  ].join('\n');

  /** The lights of the towns on the night side, as points
      (vendor/night-lights.bin, made by scripts/make_night_lights.py from
      NASA's Black Marble 2016, 3 km, a grid of `cols` columns): off while
      the Sun is above `on` degrees, full once it is below `full` (the sky
      dark), the dusk between; the picture's faint lights brought up
      (`gamma`) above its `floor`. Far out, `boost` times as bright as the
      picture. Gone as the map closes in: all of them while it spans
      fadeKm[1] km or more (a whole country), none from fadeKm[0] (half
      of France). */
  var NIGHT_LIGHTS = { on: -2, full: -10, gamma: 0.55, floor: 0.02, color: [1, 0.96, 0.82], cols: 13500, boost: 2, fadeKm: [500, 1000] };

  /** How bright a light of value v (0..1, the picture's) shows with the
      Sun h degrees above the horizon, 0..1. Line for line what the vertex
      shader (NIGHT_LIGHTS_VS) does. */
  function nightLight(v, h) {
    var L = NIGHT_LIGHTS;
    var t = Math.max(0, Math.min(1, (L.on - h) / (L.on - L.full)));
    var dusk = t * t * (3 - 2 * t);
    return Math.pow(Math.max(v - L.floor, 0) / (1 - L.floor), L.gamma) * dusk;
  }

  /** A number from 0 to 1 for the integer n, the same every time. */
  function hash01(n) {
    n = Math.imul(n ^ (n >>> 16), 0x45d9f3b);
    n = Math.imul(n ^ (n >>> 16), 0x45d9f3b);
    return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
  }

  /** The points of the lights file: { cols, rows, count, lon, lat,
      value }, each point somewhere in its cell of the grid (from 90N and
      180W), spread there the same way every time so no grid shows close
      in. */
  function decodeNightLights(buffer) {
    var b = new Uint8Array(buffer);
    if (b.length < 12 || String.fromCharCode(b[0], b[1], b[2], b[3]) !== 'AWN1') throw new Error('not a night lights file');
    var cols = b[4] | b[5] << 8, rows = b[6] | b[7] << 8, count = (b[8] | b[9] << 8 | b[10] << 16 | b[11] << 24) >>> 0, pos = 12;
    function varint() {
      var v = 0, shift = 1, c;
      do { c = b[pos++]; v += (c & 0x7f) * shift; shift *= 128; } while (c & 0x80);
      return v;
    }
    var lon = new Float32Array(count), lat = new Float32Array(count), value = new Uint8Array(count), r = 0, c = 0;
    for (var i = 0; i < count; i++) {
      var dr = varint();
      if (dr) c = 0;
      r += dr;
      c += varint();
      value[i] = b[pos++];
      lon[i] = (c + hash01(2 * i + 1)) / cols * 360 - 180;
      lat[i] = 90 - (r + hash01(2 * i + 2)) / rows * 180;
    }
    return { cols: cols, rows: rows, count: count, lon: lon, lat: lat, value: value };
  }

  var MERC_LAT = 85.0511;
  /** Mercator x, y (0..1, as MapLibre's) and the brightness (0..1) of each
      point, three floats a point; past 85 degrees on the map's edge. */
  function nightLightsVertices(d) {
    var out = new Float32Array(d.count * 3);
    for (var i = 0; i < d.count; i++) {
      var la = Math.max(-MERC_LAT, Math.min(MERC_LAT, d.lat[i])) * RAD;
      out[3 * i] = (d.lon[i] + 180) / 360;
      out[3 * i + 1] = (1 - Math.log(Math.tan(Math.PI / 4 + la / 2)) / Math.PI) / 2;
      out[3 * i + 2] = d.value[i] / 255;
    }
    return out;
  }

  /** The points at zoom z: their size in CSS px (1.5 far out, a little
      larger than their cell closer in, 4 at most) and how much of their
      light each gives (far out, where many share a pixel, what its cell
      would give, `boost` times; full once they stand apart). */
  function nightLightsLook(z) {
    var cell = 512 * Math.pow(2, z) / NIGHT_LIGHTS.cols;
    var size = Math.max(1.5, Math.min(4, cell * 1.2));
    return { size: size, gain: Math.min(1, NIGHT_LIGHTS.boost * cell * cell / (size * size)) };
  }

  /** The ground across a map widthPx wide at zoom z, its middle at
      latitude lat, in km (MapLibre's 512 px tiles). */
  function viewWidthKm(widthPx, z, lat) {
    return widthPx * 40075.0167 * Math.cos(lat * RAD) / (512 * Math.pow(2, z));
  }

  /** How much of the lights shows on a map viewKm across, 0..1. */
  function nightLightsFade(viewKm) {
    var k = NIGHT_LIGHTS.fadeKm, t = Math.max(0, Math.min(1, (viewKm - k[0]) / (k[1] - k[0])));
    return t * t * (3 - 2 * t);
  }

  /** A number as GLSL reads a float (with its point). */
  function glslFloat(x) { return x.toFixed(4); }

  // The shaders of the lights, drawn as points by the chip: the vertex
  // shader goes after MapLibre's prelude for the projection (flat or
  // globe), a_pos is Mercator x, y and the brightness.
  var NIGHT_LIGHTS_VS = (function () {
    var L = NIGHT_LIGHTS;
    return [
      // MapLibre's prelude has its own PI.
      'const float LV_PI = 3.141592653589793;',
      'in vec3 a_pos;',
      'uniform float u_shift;',
      'uniform vec3 u_sun;',
      'uniform float u_opacity;',
      'uniform float u_size;',
      'uniform float u_gain;',
      'out float v_a;',
      'void main() {',
      '  float lat = atan(sinh(LV_PI * (1.0 - 2.0 * a_pos.y)));',
      '  float lon = (a_pos.x - 0.5) * 2.0 * LV_PI;',
      '  vec3 p = vec3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat));',
      '  float h = degrees(asin(clamp(dot(p, u_sun), -1.0, 1.0)));',
      '  float t = clamp((' + glslFloat(L.on) + ' - h) / (' + glslFloat(L.on) + ' - (' + glslFloat(L.full) + ')), 0.0, 1.0);',
      '  float dusk = t * t * (3.0 - 2.0 * t);',
      '  float b = pow(max(a_pos.z - ' + glslFloat(L.floor) + ', 0.0) / (1.0 - ' + glslFloat(L.floor) + '), ' + glslFloat(L.gamma) + ');',
      '  v_a = b * dusk * u_opacity * u_gain;',
      '  gl_Position = projectTile(vec2(a_pos.x + u_shift, a_pos.y), vec2(0.0));',
      '  gl_PointSize = u_size;',
      // Off: out of the picture, nothing to draw.
      '  if (v_a <= 0.0) gl_Position = vec4(2.0, 2.0, 2.0, 1.0);',
      '}'
    ].join('\n');
  })();
  var NIGHT_LIGHTS_FS = [
    '#version 300 es',
    'precision highp float;',
    'in float v_a;',
    'out vec4 fragColor;',
    'void main() {',
    '  vec2 d = gl_PointCoord * 2.0 - 1.0;',
    '  float r = dot(d, d);',
    '  if (r > 1.0) discard;',
    '  float a = v_a * (1.0 - r * r);',
    '  fragColor = vec4(vec3(' + NIGHT_LIGHTS.color.map(glslFloat).join(', ') + ') * a, a);',
    '}'
  ].join('\n');

  /** MapLibre light position [radial, azimuthal, polar] (anchor 'map') that
      lights the globe's atmosphere from the Sun. MapLibre makes it the
      direction (sin az sin p, -cos az sin p, -cos p) in its globe frame,
      where a place is (sin lon cos lat, sin lat, cos lon cos lat). */
  function sunLightPosition(sun) {
    var x = Math.sin(sun.lon * RAD) * Math.cos(sun.lat * RAD), y = Math.sin(sun.lat * RAD);
    var z = Math.cos(sun.lon * RAD) * Math.cos(sun.lat * RAD);
    return [1, Math.atan2(x, -y) * DEG, Math.acos(Math.max(-1, Math.min(1, -z))) * DEG];
  }

  /** MapLibre's camera stands this many map heights from the point in the
      middle of the map (its 36.87 degree field of view). */
  var CAMERA = 1.5;

  /** Radius in px of the globe as seen on a map `height` px high, at a
      MapLibre globe zoom: the globe's radius is 512 2^zoom / 2 pi, and the
      camera's perspective shows less than half of it. */
  function globeApparentRadius(zoom, height) {
    var R = 512 * Math.pow(2, zoom) / (2 * Math.PI), c = CAMERA * height;
    return c * R / Math.sqrt(c * c + 2 * c * R);
  }

  /** The widest MapLibre zoom (512 px world at zoom 0) that still shows the
      whole Earth: flat, the world fills the height of the map; globe, the
      globe as seen takes GLOBE_FILL of the smaller side. On the globe,
      MapLibre holds its minimum zoom against the globe's size, whatever the
      latitude in view. null while the map has no size. */
  function wholeEarthZoom(projection, width, height) {
    if (!(width > 0 && height > 0)) return null;
    if (projection !== 'globe') return Math.log2(height / 512);
    // globeApparentRadius solved for the globe's radius
    var a = GLOBE_FILL * Math.min(width, height) / 2, c = CAMERA * height;
    var R = (a * a + a * Math.sqrt(a * a + c * c)) / c;
    return Math.log2(2 * Math.PI * R / 512);
  }

  /** The coasts and land borders of vendor/coast-borders.bin (made by
      scripts/make_coast_lines.py) as GeoJSON lines, properties.kind 'coast'
      or 'border'. Points come as zigzag varint deltas in thousandths of a
      degree: 650 KB for what takes 5 MB as GeoJSON. */
  function decodeLines(buffer) {
    var b = new Uint8Array(buffer), pos = 0;
    if (b.length < 5 || String.fromCharCode(b[0], b[1], b[2], b[3]) !== 'AWL1') throw new Error('not a lines file');
    pos = 4;
    function varint() {
      var v = 0, shift = 1, c;
      do { c = b[pos++]; v += (c & 0x7f) * shift; shift *= 128; } while (c & 0x80);
      return v;
    }
    function zigzag() { var v = varint(); return v % 2 ? -(v + 1) / 2 : v / 2; }
    var count = varint(), features = new Array(count);
    for (var i = 0; i < count; i++) {
      var kind = b[pos++] ? 'border' : 'coast';
      var n = varint(), coords = new Array(n), x = 0, y = 0;
      for (var j = 0; j < n; j++) {
        x += zigzag(); y += zigzag();
        coords[j] = [x / 1000, y / 1000];
      }
      features[i] = { type: 'Feature', properties: { kind: kind }, geometry: { type: 'LineString', coordinates: coords } };
    }
    return { type: 'FeatureCollection', features: features };
  }

  // ---- Space around the globe: the stars, the Sun and the Moon ----

  function julianDay(date) { return date.getTime() / 86400000 + 2440587.5; }

  /** Greenwich mean sidereal time at that instant, in degrees (Meeus 12.4):
      how far the sky has turned over Greenwich. */
  function gmst(date) {
    var d = julianDay(date) - 2451545, t = d / 36525;
    var g = 280.46061837 + 360.98564736629 * d + t * t * (0.000387933 - t / 38710000);
    return ((g % 360) + 360) % 360;
  }

  /** Where the Moon is overhead at that instant, { lat, lon } in degrees,
      seen from the Earth's centre: the low precision series of the
      Astronomical Almanac, good to a few tenths of a degree. */
  function sublunarPoint(date) {
    var t = (julianDay(date) - 2451545) / 36525;
    function s(a, b) { return Math.sin((a + b * t) * RAD); }
    var lambda = 218.32 + 481267.881 * t + 6.29 * s(135.0, 477198.87) - 1.27 * s(259.3, -413335.36)
      + 0.66 * s(235.7, 890534.22) + 0.21 * s(269.9, 954397.74) - 0.19 * s(357.5, 35999.05)
      - 0.11 * s(186.5, 966404.03);
    var beta = 5.13 * s(93.3, 483202.02) + 0.28 * s(228.2, 960400.89) - 0.28 * s(318.3, 6003.15)
      - 0.17 * s(217.6, -407332.21);
    var eps = (23.439 - 0.0130 * t) * RAD, l = lambda * RAD, b = beta * RAD;
    var x = Math.cos(b) * Math.cos(l);
    var y = Math.cos(eps) * Math.cos(b) * Math.sin(l) - Math.sin(eps) * Math.sin(b);
    var z = Math.sin(eps) * Math.cos(b) * Math.sin(l) + Math.cos(eps) * Math.sin(b);
    var ra = Math.atan2(y, x) * DEG, dec = Math.asin(Math.max(-1, Math.min(1, z))) * DEG;
    return { lat: dec, lon: wrap180(ra - gmst(date)) };
  }

  /** A place, or a direction from the Earth's centre, in MapLibre's globe
      frame: (sin lon cos lat, sin lat, cos lon cos lat). */
  function placeVector(lat, lon) {
    var c = Math.cos(lat * RAD);
    return [Math.sin(lon * RAD) * c, Math.sin(lat * RAD), Math.cos(lon * RAD) * c];
  }

  function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

  /** Share of the Moon's disc the Sun lights, 0 (new) to 1 (full), from the
      points under each: the phase angle taken as 180 degrees minus their
      separation (the Sun is 400 times further). */
  function moonPhase(sun, moon) {
    return (1 - dot(placeVector(sun.lat, sun.lon), placeVector(moon.lat, moon.lon))) / 2;
  }

  /** The axes of MapLibre's camera over the globe, centred on (lat, lon),
      turned by `bearing` and tilted by `pitch` (degrees): fwd looks into
      the screen, right and up along it. Directions only: the stars, the Sun
      and the Moon are far enough for the camera's place not to matter. */
  function camera(lat, lon, bearing, pitch) {
    var c = placeVector(lat, lon);
    var east = [Math.cos(lon * RAD), 0, -Math.sin(lon * RAD)];
    var north = [-Math.sin(lat * RAD) * Math.sin(lon * RAD), Math.cos(lat * RAD), -Math.sin(lat * RAD) * Math.cos(lon * RAD)];
    var cb = Math.cos(bearing * RAD), sb = Math.sin(bearing * RAD);
    var cp = Math.cos(pitch * RAD), sp = Math.sin(pitch * RAD);
    var up0 = [], right = [], fwd = [], up = [];
    for (var i = 0; i < 3; i++) {
      up0[i] = north[i] * cb + east[i] * sb;
      right[i] = east[i] * cb - north[i] * sb;
      fwd[i] = -c[i] * cp + up0[i] * sp;
      up[i] = up0[i] * cp + c[i] * sp;
    }
    return { fwd: fwd, right: right, up: up };
  }

  /** Screen offset in px from the middle of the map of a direction `v`, for
      a camera of focal length `f` px; null when it is behind the camera. */
  function projectDir(cam, v, f) {
    var z = dot(v, cam.fwd);
    if (z <= 1e-6) return null;
    return { x: f * dot(v, cam.right) / z, y: -f * dot(v, cam.up) / z };
  }

  /** The Earth's radius in px from its edge on screen (`edge` px from the
      middle) for a camera of focal length `f` px standing f past the
      surface point in the middle, as MapLibre's does: edge = f R /
      sqrt(f^2 + 2 f R), solved for R. */
  function earthRadiusPx(edge, f) {
    return (edge * edge + edge * Math.sqrt(edge * edge + f * f)) / f;
  }

  /** Where the camera stands, px from the Earth's centre in the globe
      frame: f back from the surface point in the middle (`centre`, a
      placeVector), along the camera's forward axis. */
  function cameraPosition(cam, centre, earthR, f) {
    return [0, 1, 2].map(function (i) { return centre[i] * earthR - cam.fwd[i] * f; });
  }

  /** A point of space (px from the Earth's centre, globe frame) on screen:
      { x, y } px from the middle of the map, `dist` from the camera, `z`
      its depth; null behind the camera or too close to it. */
  function projectPoint(cam, pos, p, f) {
    var d = [p[0] - pos[0], p[1] - pos[1], p[2] - pos[2]], z = dot(d, cam.fwd);
    if (z <= f * 0.05) return null;
    return { x: f * dot(d, cam.right) / z, y: -f * dot(d, cam.up) / z, z: z, dist: Math.hypot(d[0], d[1], d[2]) };
  }

  /** How the camera (frame `cam`, at `pos`) sees a body at `p` (both px
      from the Earth's centre, globe frame): fwd along the line from the
      camera to it, right and up the screen's, squared to that line. Lit
      along that line by the Sun of the scene, the Moon shows the same
      light as the globe beside it. */
  function moonView(cam, pos, p) {
    var d = [p[0] - pos[0], p[1] - pos[1], p[2] - pos[2]], dl = Math.hypot(d[0], d[1], d[2]);
    var fwd = [d[0] / dl, d[1] / dl, d[2] / dl];
    function square(a, b) {   // a, less its share along fwd and b, as a unit
      var ka = dot(a, fwd), kb = b ? dot(a, b) : 0;
      var r = [0, 1, 2].map(function (i) { return a[i] - ka * fwd[i] - (b ? kb * b[i] : 0); });
      var l = Math.hypot(r[0], r[1], r[2]);
      return [r[0] / l, r[1] / l, r[2] / l];
    }
    var right = square(cam.right, null);
    return { fwd: fwd, right: right, up: square(cam.up, right) };
  }

  /** The Moon as RGBA pixels into `out` (`size` px square, the disc
      `radPx` px across from the middle): its texture `tex` ({ width,
      height, data }, equirectangular, longitude 0 in the middle) on a ball
      seen along cam.fwd, lit by the Sun (direction `sunDir`), its near side
      turned to the Earth (it is at `moonDir` from it) with its north up
      the Earth's axis; `alpha` (0..1) fades it all. The night side keeps a
      little earthshine. */
  function renderMoon(out, size, radPx, cam, moonDir, sunDir, tex, alpha) {
    var xm = [-moonDir[0], -moonDir[1], -moonDir[2]];
    var zm = [-xm[1] * xm[0], 1 - xm[1] * xm[1], -xm[1] * xm[2]];   // the Earth's axis, square to xm
    var zl = Math.hypot(zm[0], zm[1], zm[2]) || 1;
    zm = [zm[0] / zl, zm[1] / zl, zm[2] / zl];
    var ym = [zm[1] * xm[2] - zm[2] * xm[1], zm[2] * xm[0] - zm[0] * xm[2], zm[0] * xm[1] - zm[1] * xm[0]];
    var F = cam.fwd, R = cam.right, U = cam.up, tw = tex.width, th = tex.height, td = tex.data;
    var half = size / 2, n = [0, 0, 0];
    for (var j = 0; j < size; j++) {
      var v = -(j + 0.5 - half) / radPx;
      for (var i = 0; i < size; i++) {
        var u = (i + 0.5 - half) / radPx, q = u * u + v * v, k = (j * size + i) * 4;
        // A pixel wide soft edge.
        var edge = Math.max(0, Math.min(1, (1 - Math.sqrt(q)) * radPx + 0.5));
        if (edge <= 0) { out[k + 3] = 0; continue; }
        var w = Math.sqrt(Math.max(0, 1 - q));
        for (var a = 0; a < 3; a++) n[a] = u * R[a] + v * U[a] - w * F[a];
        var lon = Math.atan2(dot(n, ym), dot(n, xm)), lat = Math.asin(Math.max(-1, Math.min(1, dot(n, zm))));
        var tx = Math.min(tw - 1, Math.floor((lon / (2 * Math.PI) + 0.5) * tw));
        var ty = Math.min(th - 1, Math.floor((0.5 - lat / Math.PI) * th));
        var t = (ty * tw + tx) * 4, light = 0.05 + 1.05 * Math.max(0, dot(n, sunDir));
        out[k] = td[t] * light; out[k + 1] = td[t + 1] * light; out[k + 2] = td[t + 2] * light;
        out[k + 3] = 255 * edge * alpha;
      }
    }
  }

  /** `count` stars spread evenly over the sky, the same for the same seed:
      right ascension and declination in degrees, then a brightness from 0
      to 1, with many more faint stars than bright ones. */
  function starField(count, seed) {
    var a = seed >>> 0;
    function rand() {   // mulberry32
      a = (a + 0x6D2B79F5) >>> 0;
      var r = Math.imul(a ^ (a >>> 15), 1 | a);
      r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
      return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    }
    var out = new Float64Array(count * 3);
    for (var i = 0; i < count; i++) {
      out[i * 3] = rand() * 360;
      out[i * 3 + 1] = Math.asin(2 * rand() - 1) * DEG;
      out[i * 3 + 2] = Math.pow(rand(), 5);
    }
    return out;
  }

  return {
    gmst: gmst, sublunarPoint: sublunarPoint, placeVector: placeVector, moonPhase: moonPhase,
    camera: camera, projectDir: projectDir, earthRadiusPx: earthRadiusPx,
    cameraPosition: cameraPosition, projectPoint: projectPoint, moonView: moonView, renderMoon: renderMoon, dot: dot, starField: starField, CAMERA: CAMERA,
    decodeLines: decodeLines,
    GLOBE_FILL: GLOBE_FILL, subsolarPoint: subsolarPoint, sunAltitude: sunAltitude,
    shadeTile: shadeTile, shadeUniforms: shadeUniforms, shadeFrom: shadeFrom, NIGHT_FS: NIGHT_FS, sunLightPosition: sunLightPosition,
    NIGHT_LIGHTS: NIGHT_LIGHTS, nightLight: nightLight, NIGHT_LIGHTS_VS: NIGHT_LIGHTS_VS, NIGHT_LIGHTS_FS: NIGHT_LIGHTS_FS, glslFloat: glslFloat,
    decodeNightLights: decodeNightLights, nightLightsVertices: nightLightsVertices, nightLightsLook: nightLightsLook,
    viewWidthKm: viewWidthKm, nightLightsFade: nightLightsFade,
    globeApparentRadius: globeApparentRadius, wholeEarthZoom: wholeEarthZoom
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetEarth; }
