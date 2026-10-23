// ==========================================================================
// Glue script 2e: the Earth as a whole on the MapLibre map. Where the Sun is
// overhead, the night and its three twilights as areas in longitude and
// latitude (the map projects them itself, flat or globe), and the zoom at
// which the whole Earth fits in the map. Loadable under Node for tests.
// ==========================================================================
var WidgetEarth = (function () {
  'use strict';

  var RAD = Math.PI / 180, DEG = 180 / Math.PI;

  /** Sun altitudes (degrees) bounding the areas: night, then civil,
      nautical and astronomical twilight ending. */
  var BANDS = [0, -6, -12, -18];

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

  /* Where the Sun is lower than h degrees: a cap of angular radius 90 + h
     around the antisolar point, as one ring of [lon, lat]. */
  function capRing(sun, h, step) {
    var cLat = -sun.lat, cLon = wrap180(sun.lon + 180), r = (90 + h) * RAD;
    // Exactly at an equinox the night touches both poles: nudge it.
    if (Math.abs(cLat) < 1e-6) cLat = 1e-6;
    var pole = cLat > 0 ? 90 : -90, ring = [], i;
    if (90 - Math.abs(cLat) < 90 + h) {
      // The cap holds a pole: every meridian crosses its edge once. The
      // edge for each longitude, then along the pole back to the start.
      var a = Math.sin(cLat * RAD), cr = Math.cos(r);
      for (var lon = -180; lon <= 180; lon += step) {
        // a sin(lat) + b cos(lat) = cos r, solved as A cos(lat - lat0) = cos r
        var b = Math.cos(cLat * RAD) * Math.cos((lon - cLon) * RAD);
        var A = Math.sqrt(a * a + b * b), lat0 = Math.atan2(a, b);
        var d = Math.acos(Math.max(-1, Math.min(1, cr / A)));
        var lat = wrap180((lat0 + d) * DEG);
        if (Math.abs(lat) > 90) lat = wrap180((lat0 - d) * DEG);
        ring.push([lon, Math.max(-90, Math.min(90, lat))]);
      }
      ring.push([180, pole], [-180, pole], ring[0]);
      return ring;
    }
    // A cap clear of the poles: its edge point by point around the centre,
    // longitudes kept continuous (past +-180 when it crosses the antimeridian).
    var sinC = Math.sin(cLat * RAD), cosC = Math.cos(cLat * RAD), prev = null;
    for (i = 0; i <= 360; i += step) {
      var th = i * RAD;
      var sinLat = sinC * Math.cos(r) + cosC * Math.sin(r) * Math.cos(th);
      var pLat = Math.asin(sinLat);
      var pLon = cLon + Math.atan2(Math.sin(th) * Math.sin(r) * cosC, Math.cos(r) - sinC * sinLat) * DEG;
      if (prev !== null) pLon = prev + wrap180(pLon - prev);
      prev = pLon;
      ring.push([pLon, pLat * DEG]);
    }
    ring[ring.length - 1] = ring[0];
    return ring;
  }

  /** The night and its twilights for a Sun position: one polygon per
      altitude of BANDS, each holding the next, deepest last. Drawn one over
      the other with the same light veil, they darken step by step. */
  function nightGeoJSON(sun, step) {
    return {
      type: 'FeatureCollection',
      features: BANDS.map(function (h) {
        return {
          type: 'Feature',
          properties: { altitude: h },
          geometry: { type: 'Polygon', coordinates: [capRing(sun, h, step || 1)] }
        };
      })
    };
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
    BANDS: BANDS, GLOBE_FILL: GLOBE_FILL, subsolarPoint: subsolarPoint, sunAltitude: sunAltitude,
    nightGeoJSON: nightGeoJSON, globeApparentRadius: globeApparentRadius, wholeEarthZoom: wholeEarthZoom
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetEarth; }
