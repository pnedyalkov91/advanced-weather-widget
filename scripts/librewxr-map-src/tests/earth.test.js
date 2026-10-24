'use strict';
// Unit tests for glue-earth.js: the Sun's position, the night and twilight
// areas, and the zoom at which the whole Earth fits in the map.
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const E = require('../glue-earth.js');

function near(actual, expected, tol, what) {
  assert.ok(Math.abs(actual - expected) <= tol, what + ': ' + actual + ' not within ' + tol + ' of ' + expected);
}

test('subsolarPoint: declination and longitude at known instants', () => {
  // June solstice 2026 (21 June 08:24 UTC): the Sun over the Tropic of Cancer.
  near(E.subsolarPoint(new Date('2026-06-21T08:24:00Z')).lat, 23.44, 0.05, 'solstice declination');
  // March equinox 2026 (20 March 14:46 UTC): the Sun over the equator.
  near(E.subsolarPoint(new Date('2026-03-20T14:46:00Z')).lat, 0, 0.05, 'equinox declination');
  // 12:00 UTC on 3 November: equation of time +16.4 min, so solar noon came
  // 16 min early at Greenwich and the Sun is already 4.1 degrees west.
  near(E.subsolarPoint(new Date('2026-11-03T12:00:00Z')).lon, -4.1, 0.2, 'November longitude');
  // 18:00 UTC: a quarter turn later, 90 degrees further west.
  near(E.subsolarPoint(new Date('2026-11-03T18:00:00Z')).lon, -4.1 - 90, 0.2, 'evening longitude');
});

test('sunAltitude: overhead at the subsolar point, under the far side', () => {
  const sun = { lat: 10, lon: 40 };
  near(E.sunAltitude(sun, 10, 40), 90, 1e-5, 'subsolar point');
  near(E.sunAltitude(sun, -10, -140), -90, 1e-5, 'antisolar point');
  near(E.sunAltitude(sun, 0, 130), -E.sunAltitude(sun, 0, -50), 1e-9, 'symmetry');
});

/** Whether (lat, lon) lies in a ring of [lon, lat] whose longitudes may run past +-180. */
function inRing(ring, lat, lon) {
  for (const shift of [-360, 0, 360]) {
    const x = lon + shift;
    let inside = false;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const [xi, yi] = ring[i], [xj, yj] = ring[j];
      if ((yi > lat) !== (yj > lat) && x < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
    }
    if (inside) return true;
  }
  return false;
}

test('nightGeoJSON: nested areas every degree, from the horizon to 18 degrees below', () => {
  const suns = [
    { lat: 23.4, lon: -60 },     // June solstice: the north pole in daylight
    { lat: -23.4, lon: 120 },    // December solstice
    { lat: 0.2, lon: 10 },       // near an equinox: the deep night reaches no pole
    { lat: -8, lon: 178 },       // night across the antimeridian
  ];
  for (const sun of suns) {
    const fc = E.nightGeoJSON(sun);
    assert.equal(fc.type, 'FeatureCollection');
    assert.deepEqual(fc.features.map((f) => f.properties.altitude), [0, -1, -2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12, -13, -14, -15, -16, -17, -18]);
    fc.features.forEach((f) => {
      const ring = f.geometry.coordinates[0];
      assert.deepEqual(ring[0], ring[ring.length - 1], 'closed ring');
      for (let lat = -84; lat <= 84; lat += 6) {
        for (let lon = -180; lon < 180; lon += 6) {
          const alt = E.sunAltitude(sun, lat, lon), h = f.properties.altitude;
          if (Math.abs(alt - h) < 1.5) continue;   // too close to the edge to judge
          assert.equal(inRing(ring, lat, lon), alt < h,
            `sun ${sun.lat},${sun.lon} altitude ${h}: point ${lat},${lon} (sun at ${alt.toFixed(1)})`);
        }
      }
    });
  }
});

test('wholeEarthZoom: flat, the world fills the height of the map', () => {
  // MapLibre zoom: 512 px for the whole world at zoom 0.
  near(E.wholeEarthZoom('flat', 800, 330), Math.log2(330 / 512), 1e-9, 'flat');
  near(E.wholeEarthZoom('flat', 800, 1024), 1, 1e-9, 'flat, tall map');
});

test('wholeEarthZoom: globe, the globe as seen fills GLOBE_FILL of the smaller side', () => {
  // MapLibre's camera (36.87 degree field of view) stands 1.5 map heights
  // from the point in the middle: a globe of radius R shows as a disc of
  // radius c R / sqrt(c^2 + 2 c R), c = 1.5 h. Its minimum zoom holds the
  // globe's radius, 512 2^z / 2 pi, whatever the latitude in view. The
  // model matches the radius measured on the page (157, 200.8 and 315.6 px
  // at zoom 1.5, 2 and 3 on a 266 px high map).
  for (const [w, h] of [[800, 266], [800, 330], [400, 600]]) {
    const z = E.wholeEarthZoom('globe', w, h);
    const R = 512 * Math.pow(2, z) / (2 * Math.PI), c = 1.5 * h;
    near(c * R / Math.sqrt(c * c + 2 * c * R), Math.min(w, h) * E.GLOBE_FILL / 2, 1e-6, `globe ${w}x${h}`);
  }
  near(E.globeApparentRadius(Math.log2(1.5 * 2 * Math.PI * 230.5 / 512 / 1.5), 266), 157, 0.5, 'measured');
});

test('wholeEarthZoom: no size, no zoom', () => {
  assert.equal(E.wholeEarthZoom('globe', 0, 300), null);
  assert.equal(E.wholeEarthZoom('flat', 800, 0), null);
});

test('dayGeoJSON: nested areas every degree, from the horizon to 18 degrees above', () => {
  for (const sun of [{ lat: 23.4, lon: -60 }, { lat: -11.5, lon: -150 }, { lat: 0.2, lon: 179 }]) {
    const fc = E.dayGeoJSON(sun);
    assert.deepEqual(fc.features.map((f) => f.properties.altitude), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]);
    fc.features.forEach((f) => {
      const ring = f.geometry.coordinates[0], h = f.properties.altitude;
      assert.deepEqual(ring[0], ring[ring.length - 1], 'closed ring');
      for (let lat = -84; lat <= 84; lat += 6) {
        for (let lon = -180; lon < 180; lon += 6) {
          const alt = E.sunAltitude(sun, lat, lon);
          if (Math.abs(alt - h) < 1.5) continue;
          assert.equal(inRing(ring, lat, lon), alt > h, `sun ${sun.lat},${sun.lon} altitude ${h}: point ${lat},${lon} (sun at ${alt.toFixed(1)})`);
        }
      }
    });
  }
});

test('sunLightPosition: MapLibre light (anchor map) pointing from the Sun', () => {
  // MapLibre turns the light position [r, azimuthal, polar] into the
  // direction (sin az sin p, -cos az sin p, -cos p) in its globe frame, where
  // a place is (sin lon cos lat, sin lat, cos lon cos lat). Checked on the
  // page: the lit rim of the atmosphere sits over the day side.
  const R = Math.PI / 180;
  for (const sun of [{ lat: 23.4, lon: -60 }, { lat: -11.6, lon: -132.7 }, { lat: 0, lon: 0 }, { lat: 5, lon: 179 }]) {
    const [r, az, p] = E.sunLightPosition(sun);
    assert.equal(r, 1);
    assert.ok(p >= 0 && p <= 180, 'polar within 0..180');
    const dir = [Math.sin(az * R) * Math.sin(p * R), -Math.cos(az * R) * Math.sin(p * R), -Math.cos(p * R)];
    const want = [Math.sin(sun.lon * R) * Math.cos(sun.lat * R), Math.sin(sun.lat * R), Math.cos(sun.lon * R) * Math.cos(sun.lat * R)];
    dir.forEach((v, i) => near(v, want[i], 1e-9, `sun ${sun.lat},${sun.lon} axis ${i}`));
  }
});
