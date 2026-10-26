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

  return {
    GLOBE_FILL: GLOBE_FILL, subsolarPoint: subsolarPoint, sunAltitude: sunAltitude,
    shadeTile: shadeTile, sunLightPosition: sunLightPosition,
    globeApparentRadius: globeApparentRadius, wholeEarthZoom: wholeEarthZoom
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetEarth; }
