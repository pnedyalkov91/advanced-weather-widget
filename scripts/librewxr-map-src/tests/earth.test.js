'use strict';
// Unit tests for glue-earth.js: the Sun's position, the day and night
// image, and the zoom at which the whole Earth fits in the map.
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

/** The whole world as one Web Mercator tile. */
const WORLD = { z: 0, x: 0, y: 0 };

/** Latitude and longitude of the centre of pixel (col, row) of a square Web Mercator world. */
function pixelLatLon(col, row, size) {
  const lon = (col + 0.5) / size * 360 - 180;
  const lat = Math.atan(Math.sinh(Math.PI * (1 - 2 * (row + 0.5) / size))) * 180 / Math.PI;
  return { lat, lon };
}

test('shadeTile: black over the night, as deep as asked, fading in over 18 degrees', () => {
  const sun = { lat: -11.6, lon: 30 }, size = 64, depth = 0.4;
  const img = E.shadeTile(sun, WORLD, size, depth, 0);
  assert.equal(img.length, size * size * 4);
  let night = 0, twilight = 0, day = 0;
  for (let row = 0; row < size; row++) {
    for (let col = 0; col < size; col++) {
      const { lat, lon } = pixelLatLon(col, row, size), h = E.sunAltitude(sun, lat, lon);
      const k = (row * size + col) * 4, a = img[k + 3] / 255;
      const want = h < 0 ? 1 - Math.pow(1 - depth, Math.min(1, -h / 18)) : 0;
      assert.ok(Math.abs(a - want) <= 1.5 / 255, `pixel ${col},${row} at ${h.toFixed(1)} degrees: alpha ${a} for ${want}`);
      if (h < 0) assert.deepEqual([img[k], img[k + 1], img[k + 2]], [0, 0, 0], 'black');
      if (h < -18) night++; else if (h < 0) twilight++; else day++;
    }
  }
  assert.ok(night > 100 && twilight > 100 && day > 100, `${night} ${twilight} ${day}`);
});

test('shadeTile: a light veil over the day, fading in over its first 18 degrees', () => {
  const sun = { lat: 20, lon: -100 }, size = 64, veil = 0.07;
  const img = E.shadeTile(sun, WORLD, size, 0.4, veil);
  for (let row = 0; row < size; row += 3) {
    for (let col = 0; col < size; col += 3) {
      const { lat, lon } = pixelLatLon(col, row, size), h = E.sunAltitude(sun, lat, lon);
      if (h <= 0) continue;
      const k = (row * size + col) * 4, a = img[k + 3] / 255;
      const want = 1 - Math.pow(1 - veil, Math.min(1, h / 18));
      assert.ok(Math.abs(a - want) <= 1.5 / 255, `pixel ${col},${row} at ${h.toFixed(1)} degrees`);
      if (img[k + 3] > 0) assert.deepEqual([img[k], img[k + 1], img[k + 2]], [255, 255, 255], 'white');
    }
  }
});

test('shadeTile: the middle rows of the world tile lie on the equator, the top one near 85 degrees north', () => {
  // Sun over the equator at 0: the antisolar point (equator, 180) is the deepest night.
  const sun = { lat: 0, lon: 0 }, size = 64;
  const img = E.shadeTile(sun, WORLD, size, 0.5, 0);
  const at = (col, row) => img[(row * size + col) * 4 + 3];
  assert.ok(Math.abs(at(size - 1, size / 2) - 0.5 * 255) <= 1, 'deep night at the equator, far east');
  assert.equal(at(size / 2, size / 2), 0, 'noon at the equator');
  assert.ok(pixelLatLon(0, 0, size).lat > 84, 'top row');
});

test('shadeTile: a tile of zoom 1 is a quarter of the world at twice the detail', () => {
  const sun = { lat: 8, lon: -40 }, world = E.shadeTile(sun, WORLD, 64, 0.4, 0.07);
  for (const [x, y] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
    const tile = E.shadeTile(sun, { z: 1, x, y }, 32, 0.4, 0.07);
    for (let r = 0; r < 32; r += 5) {
      for (let c = 0; c < 32; c += 5) {
        const k = (r * 32 + c) * 4, w = ((y * 32 + r) * 64 + x * 32 + c) * 4;
        assert.deepEqual([...tile.slice(k, k + 4)], [...world.slice(w, w + 4)], `tile ${x},${y} pixel ${c},${r}`);
      }
    }
  }
});
