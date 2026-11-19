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

test('shadeFrom: what the chip draws for the night is what the tiles held, night and day veil', () => {
  const sun = { lat: -11.6, lon: 30 }, size = 64, depth = 0.4, veil = 0.07;
  const img = E.shadeTile(sun, WORLD, size, depth, veil), u = E.shadeUniforms(sun, depth, veil);
  assert.equal(u.sun.length, 3);
  assert.equal(u.ln.length, 2);
  for (let row = 0; row < size; row += 2) {
    for (let col = 0; col < size; col += 2) {
      const { lat, lon } = pixelLatLon(col, row, size), k = (row * size + col) * 4;
      // Mercator 0..1, as the chip's shader gets the place.
      const c = E.shadeFrom(u, (lon + 180) / 360, (row + 0.5) / size);
      assert.ok(Math.abs(c[3] - img[k + 3] / 255) <= 1.5 / 255, `alpha at ${lat.toFixed(1)}, ${lon.toFixed(1)}`);
      // Premultiplied: black over the night, white as strong as its alpha over the day.
      const white = img[k] === 255;
      assert.ok(Math.abs(c[0] - (white ? c[3] : 0)) < 1e-9, 'color');
    }
  }
});

test('shadeUniforms: no day veil asked, none drawn', () => {
  const u = E.shadeUniforms({ lat: 0, lon: 0 }, 0.4, 0);
  assert.deepEqual([...E.shadeFrom(u, 0.5, 0.5)], [0, 0, 0, 0], 'noon at the equator');
  assert.ok(Math.abs(E.shadeFrom(u, 0, 0.5)[3] - 0.4) < 1e-6, 'midnight on the other side');
});

test('NIGHT_FS: the shader of the night reads the same uniforms', () => {
  assert.match(E.NIGHT_FS, /uniform vec3 u_sun;/);
  assert.match(E.NIGHT_FS, /uniform vec2 u_ln;/);
  assert.match(E.NIGHT_FS, /in vec2 v_merc;/);
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

// === Coasts and borders (vendor/coast-borders.bin) ===
test('decodeLines reads the packed lines as GeoJSON, coasts and borders apart', () => {
  // "AWL1", 2 lines; coast (1,2) (1.5,2.25); border (-0.001,0) (0,0.001) (0.002,0.001)
  const bytes = Uint8Array.from([0x41, 0x57, 0x4c, 0x31, 2,
    0, 2, 0xd0, 0x0f, 0xa0, 0x1f, 0xe8, 0x07, 0xf4, 0x03,
    1, 3, 1, 0, 2, 2, 4, 0]);
  const fc = E.decodeLines(bytes.buffer);
  assert.equal(fc.type, 'FeatureCollection');
  assert.deepEqual(JSON.parse(JSON.stringify(fc.features.map((f) => [f.properties.kind, f.geometry.coordinates]))), [
    ['coast', [[1, 2], [1.5, 2.25]]],
    ['border', [[-0.001, 0], [0, 0.001], [0.002, 0.001]]]
  ]);
});

test('decodeLines refuses what is not a lines file', () => {
  assert.throws(() => E.decodeLines(Uint8Array.from([1, 2, 3, 4, 0]).buffer));
});

test('the widget file holds the coasts and borders of the whole Earth', () => {
  const buf = require('node:fs').readFileSync(require('node:path').join(__dirname, '../../../contents/ui/components/vendor/coast-borders.bin'));
  const fc = E.decodeLines(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length));
  const kinds = { coast: 0, border: 0 };
  let minLat = 90, maxLat = -90, out = 0;
  for (const f of fc.features) {
    kinds[f.properties.kind]++;
    for (const [lon, lat] of f.geometry.coordinates) {
      if (lon < -180 || lon > 180) out++;
      minLat = Math.min(minLat, lat); maxLat = Math.max(maxLat, lat);
    }
  }
  assert.ok(kinds.coast > 1000 && kinds.border > 100, JSON.stringify(kinds));
  assert.equal(out, 0);
  assert.ok(minLat < -80 && maxLat > 80, minLat + ' ' + maxLat);
});

// ---- Space around the globe: sidereal time, the Moon, the camera ----

test('gmst: Greenwich mean sidereal time (Meeus example 12.a)', () => {
  // 1987 April 10, 0h UT: 13h10m46.3668s = 197.693195 degrees.
  near(E.gmst(new Date('1987-04-10T00:00:00Z')), 197.693195, 1e-4, 'GMST');
});

test('sublunarPoint: the Moon of Meeus example 47.a', () => {
  // 1992 April 12, 0h TD: right ascension 134.688470, declination 13.768368.
  const date = new Date('1992-04-12T00:00:00Z');
  const m = E.sublunarPoint(date);
  near(m.lat, 13.768, 0.4, 'declination');
  const lon = ((134.688470 - E.gmst(date) + 540) % 360) - 180;
  near(m.lon, lon, 0.5, 'longitude');
});

test('moonPhase: lit share of the Moon (Meeus example 48.a)', () => {
  const date = new Date('1992-04-12T00:00:00Z');
  near(E.moonPhase(E.subsolarPoint(date), E.sublunarPoint(date)), 0.6786, 0.02, 'illuminated fraction');
  // Same direction: new Moon; opposite: full.
  near(E.moonPhase({ lat: 0, lon: 0 }, { lat: 0, lon: 0 }), 0, 1e-9, 'new');
  near(E.moonPhase({ lat: 0, lon: 0 }, { lat: 0, lon: 180 }), 1, 1e-9, 'full');
});

test('camera: the point in the middle of the map faces the viewer', () => {
  const cam = E.camera(45, 10, 0, 0);
  const p = E.placeVector(45, 10);
  // Looking at the Earth: forward points from the camera to its centre.
  near(cam.fwd[0], -p[0], 1e-12, 'fwd x'); near(cam.fwd[1], -p[1], 1e-12, 'fwd y'); near(cam.fwd[2], -p[2], 1e-12, 'fwd z');
  // A direction straight away from the viewer projects to the middle.
  const mid = E.projectDir(cam, cam.fwd, 100);
  near(mid.x, 0, 1e-9, 'x'); near(mid.y, 0, 1e-9, 'y');
  // Towards the viewer: behind the camera, not drawn.
  assert.equal(E.projectDir(cam, p, 100), null);
});

test('camera: north up, east right, then turned by the bearing', () => {
  // Over the equator at 0, looking at the Earth along -z: a direction
  // past it and north is up the screen, one past it and east to the right.
  const cam = E.camera(0, 0, 0, 0);
  const north = E.projectDir(cam, [0, 1, -1], 100), east = E.projectDir(cam, [1, 0, -1], 100);
  assert.ok(north.y < 0 && Math.abs(north.x) < 1e-9, 'north up: ' + JSON.stringify(north));
  assert.ok(east.x > 0 && Math.abs(east.y) < 1e-9, 'east right: ' + JSON.stringify(east));
  // Bearing 90: east is up.
  const turned = E.camera(0, 0, 90, 0);
  const e2 = E.projectDir(turned, [1, 0, -1], 100);
  assert.ok(e2.y < 0 && Math.abs(e2.x) < 1e-9, 'east up at bearing 90: ' + JSON.stringify(e2));
});

test('starField: same stars for the same seed, spread over the sky', () => {
  const a = E.starField(2000, 7), b = E.starField(2000, 7);
  assert.deepEqual(a, b);
  let north = 0;
  for (let i = 0; i < 2000; i++) if (a[i * 3 + 1] > 0) north++;
  near(north / 2000, 0.5, 0.05, 'half in the northern sky');
});

test('earthRadiusPx: the globe radius that shows a given edge on screen', () => {
  // A sphere of radius R seen from f past its surface, focal length f:
  // edge = f R / sqrt(f^2 + 2 f R).
  const f = 700, R = 300, edge = f * R / Math.sqrt(f * f + 2 * f * R);
  near(E.earthRadiusPx(edge, f), R, 1e-6, 'radius');
});

test('projectPoint: the Earth seen by the camera, a Moon in front and behind', () => {
  const f = 700, R = 300, cam = E.camera(0, 0, 0, 0);
  const pos = E.cameraPosition(cam, E.placeVector(0, 0), R, f);
  // The camera stands f past the surface point in the middle.
  near(pos[2], R + f, 1e-9, 'camera distance');
  const centre = E.projectPoint(cam, pos, [0, 0, 0], f);
  near(centre.x, 0, 1e-9, 'centre x'); near(centre.y, 0, 1e-9, 'centre y');
  near(centre.dist, R + f, 1e-9, 'centre distance');
  // A Moon at 2.4 radii towards the viewer, then away from it.
  const front = E.projectPoint(cam, pos, [0, 0, 2.4 * R], f);
  const back = E.projectPoint(cam, pos, [0, 0, -2.4 * R], f);
  assert.ok(front.dist < centre.dist && back.dist > centre.dist);
  // East of the middle, on the Earth's side plane: right of the globe.
  const east = E.projectPoint(cam, pos, [2.4 * R, 0, 0], f);
  assert.ok(east.x > 0 && Math.abs(east.y) < 1e-9);
  // Behind the camera: null.
  assert.equal(E.projectPoint(cam, pos, [0, 0, 2 * (R + f)], f), null);
});

// A 4 x 2 texture: longitude -180..-90 red, -90..0 green, 0..90 blue,
// 90..180 white; both rows the same.
function stripes() {
  const cols = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]], data = new Uint8ClampedArray(4 * 2 * 4);
  for (let y = 0; y < 2; y++) for (let x = 0; x < 4; x++) data.set([...cols[x], 255], (y * 4 + x) * 4);
  return { width: 4, height: 2, data };
}
function px(out, size, x, y) { const k = (y * size + x) * 4; return Array.from(out.slice(k, k + 4)); }

test('renderMoon: seen from the Earth, lit from behind the viewer: full, its near side in the middle', () => {
  // Camera looking along -z at a Moon on +z... the Moon at direction (0,0,-1)
  // from the Earth, the camera between them looking at it.
  const cam = { fwd: [0, 0, -1], right: [1, 0, 0], up: [0, 1, 0] };
  const size = 21, out = new Uint8ClampedArray(size * size * 4);
  E.renderMoon(out, size, 10, cam, [0, 0, -1], [0, 0, 1], stripes(), 1);
  const mid = px(out, size, 10, 10);
  // The near side (longitude 0, blue/green border): just right of it east, blue.
  assert.ok(mid[3] === 255, 'opaque middle');
  const east = px(out, size, 14, 10), west = px(out, size, 6, 10);
  assert.ok(east[2] > 150 && east[0] < 50, 'east of the near side blue: ' + east);
  assert.ok(west[1] > 150 && west[0] < 50, 'west of it green: ' + west);
  // Outside the disc: transparent.
  assert.equal(px(out, size, 0, 0)[3], 0);
});

test('renderMoon: the Sun behind the Moon leaves its face dark, faded by `alpha`', () => {
  const cam = { fwd: [0, 0, -1], right: [1, 0, 0], up: [0, 1, 0] };
  const size = 21, out = new Uint8ClampedArray(size * size * 4);
  E.renderMoon(out, size, 10, cam, [0, 0, -1], [0, 0, -1], stripes(), 0.5);
  const mid = px(out, size, 10, 10);
  assert.ok(mid[0] + mid[1] + mid[2] < 60, 'dark: ' + mid);
  assert.ok(Math.abs(mid[3] - 128) <= 1, 'half faded: ' + mid[3]);
  // Lit from the right (east): the right half bright, the left dark.
  E.renderMoon(out, size, 10, cam, [0, 0, -1], [1, 0, 0], stripes(), 1);
  const r = px(out, size, 17, 10), l = px(out, size, 3, 10);
  assert.ok(r[0] + r[1] + r[2] > l[0] + l[1] + l[2] + 100, 'lit right: ' + r + ' vs ' + l);
});

function brightness(p) { return p[0] + p[1] + p[2]; }
function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }

test('moonView: straight ahead, the camera itself', () => {
  const f = 700, R = 300, cam = E.camera(0, 0, 0, 0);
  const pos = E.cameraPosition(cam, E.placeVector(0, 0), R, f);
  const v = E.moonView(cam, pos, [0, 0, -1.45 * R]);
  for (const k of ['fwd', 'right', 'up']) for (let i = 0; i < 3; i++) near(v[k][i], cam[k][i], 1e-9, k + i);
});

test('moonView: off to the side, looks along the line from the camera to the Moon', () => {
  const f = 700, R = 300, cam = E.camera(20, 30, 40, 10);
  const pos = E.cameraPosition(cam, E.placeVector(20, 30), R, f);
  const X = E.placeVector(-10, 120).map(c => c * 1.45 * R);
  const v = E.moonView(cam, pos, X);
  const d = [X[0] - pos[0], X[1] - pos[1], X[2] - pos[2]], dl = Math.hypot(...d);
  for (let i = 0; i < 3; i++) near(v.fwd[i], d[i] / dl, 1e-9, 'fwd' + i);
  near(E.dot(v.fwd, v.right), 0, 1e-9, 'right square'); near(E.dot(v.fwd, v.up), 0, 1e-9, 'up square');
  near(E.dot(v.right, v.up), 0, 1e-9, 'right/up square'); near(Math.hypot(...v.right), 1, 1e-9, 'right unit');
  assert.ok(E.dot(v.right, cam.right) > 0.5 && E.dot(v.up, cam.up) > 0.5, 'still the screen right and up');
  // Same hand as the camera: up x right along the same way as its fwd.
  assert.ok(E.dot(cross(v.up, v.right), v.fwd) * E.dot(cross(cam.up, cam.right), cam.fwd) > 0, 'same hand');
});

test('moonView: the Moon lit by the Sun of the scene, as the camera sees it', () => {
  const f = 700, R = 300, cam = E.camera(0, 0, 0, 0);
  const pos = E.cameraPosition(cam, E.placeVector(0, 0), R, f);
  const size = 21, out = new Uint8ClampedArray(size * size * 4), tex = stripes();
  const front = [0, 0, 1.45 * R], back = [0.6 * R, 0, -1.45 * R], mvFront = [0, 0, 1], mvBack = E.placeVector(0, 180 - 22.5);
  // Noon under the camera, the Sun behind it: the face of the Earth in view
  // is lit, and so is the face of the Moon passing in front of it.
  E.renderMoon(out, size, 10, E.moonView(cam, pos, front), mvFront, [0, 0, 1], tex, 1);
  assert.ok(brightness(px(out, size, 10, 10)) > 150, 'full in front: ' + px(out, size, 10, 10));
  // The Sun behind the globe: the Moon in front shows its night side.
  E.renderMoon(out, size, 10, E.moonView(cam, pos, front), mvFront, [0, 0, -1], tex, 1);
  assert.ok(brightness(px(out, size, 10, 10)) < 60, 'dark in front: ' + px(out, size, 10, 10));
  // The Sun off to the right of the screen: the right side of the Moon is
  // the lit one, in front of the globe and behind it.
  for (const [X, mv] of [[front, mvFront], [back, mvBack]]) {
    E.renderMoon(out, size, 10, E.moonView(cam, pos, X), mv, cam.right, tex, 1);
    const r = px(out, size, 17, 10), l = px(out, size, 3, 10);
    assert.ok(brightness(r) > brightness(l) + 100, 'lit right: ' + r + ' vs ' + l);
  }
});

test('nightLight: off by day and as the Sun sets, full once the sky is dark, fading in through the dusk', () => {
  const L = E.NIGHT_LIGHTS;
  assert.equal(E.nightLight(1, 10), 0, 'day');
  assert.equal(E.nightLight(1, L.on), 0, 'the Sun just set');
  near(E.nightLight(1, L.full), 1, 1e-9, 'dark sky');
  near(E.nightLight(1, -60), 1, 1e-9, 'deep night');
  let last = 0;
  for (let h = L.on; h >= L.full; h -= 0.5) {
    const k = E.nightLight(1, h);
    assert.ok(k >= last, 'brighter as the Sun goes down, at ' + h);
    last = k;
  }
  const mid = E.nightLight(1, (L.on + L.full) / 2);
  assert.ok(mid > 0.3 && mid < 0.7, 'halfway: ' + mid);
});

test('nightLight: unlit land stays dark, the faint lights come up', () => {
  const L = E.NIGHT_LIGHTS;
  assert.equal(E.nightLight(0, -30), 0);
  assert.equal(E.nightLight(L.floor, -30), 0, 'at the floor: the noise of the picture');
  const faint = E.nightLight(0.1, -30);
  assert.ok(faint > 0.15 && faint < 0.5, 'a faint town brought up: ' + faint);
  assert.ok(E.nightLight(0.5, -30) < E.nightLight(0.8, -30), 'brighter towns brighter');
});

test('night lights: the shader works the Sun out as placeVector does, with the numbers of nightLight', () => {
  // sin(altitude) = place . Sun, both as placeVector (the shader's frame).
  for (let i = 0; i < 200; i++) {
    const lat = Math.random() * 170 - 85, lon = Math.random() * 360 - 180;
    const sun = { lat: Math.random() * 47 - 23.5, lon: Math.random() * 360 - 180 };
    const s = E.dot(E.placeVector(lat, lon), E.placeVector(sun.lat, sun.lon));
    near(Math.asin(s) * 180 / Math.PI, E.sunAltitude(sun, lat, lon), 1e-9, 'altitude at ' + lat + ',' + lon);
  }
  const L = E.NIGHT_LIGHTS, vs = E.NIGHT_LIGHTS_VS;
  for (const k of ['on', 'full', 'gamma', 'floor']) assert.ok(vs.includes(E.glslFloat(L[k])), k + ' in the shader');
  assert.ok(vs.includes('vec3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat))'), 'the place as placeVector');
  assert.ok(vs.includes('projectTile('), 'placed by MapLibre\'s projection');
});

// The lights file as make_night_lights.py packs it.
function packLights(w, h, pts, floorV = 10, power = 1.2) {
  const out = [...Buffer.from('AWN2')], u16 = (n) => out.push(n & 255, n >> 8);
  u16(w); u16(h); out.push(pts.length & 255, (pts.length >> 8) & 255, (pts.length >> 16) & 255, pts.length >>> 24);
  out.push(floorV, Math.round(power * 100));
  const vi = (n) => { while (n >= 128) { out.push((n & 127) | 128); n = Math.floor(n / 128); } out.push(n); };
  let lr = 0, lc = 0;
  for (const [r, c, v] of pts) { if (r !== lr) lc = 0; vi(r - lr); vi(c - lc); out.push(v); lr = r; lc = c; }
  return new Uint8Array(out).buffer;
}

/** Longitude and latitude of the point at k of the vertices v. */
function lonLat(v, k) {
  const lon = v[3 * k] * 360 - 180;
  const lat = Math.atan(Math.sinh(Math.PI * (1 - 2 * v[3 * k + 1]))) * 180 / Math.PI;
  return [lon, lat];
}

test('decodeNightLights: the lit cells of the file and the points a brightness gets', () => {
  // A 360 x 180 grid: one degree a cell from 90N and 180W.
  const cells = [[0, 5, 30], [0, 300, 255], [90, 180, 120], [179, 359, 11]];
  const d = E.decodeNightLights(packLights(360, 180, cells));
  assert.equal(d.count, 4);
  cells.forEach(([r, c, v], i) => {
    assert.equal(d.row[i], r); assert.equal(d.col[i], c); assert.equal(d.value[i], v);
  });
  assert.equal(d.chance[255], 1, 'full light: one point at density 1');
  assert.equal(d.chance[10], 0, 'the floor: none');
  near(d.chance[132], Math.pow(122 / 245, 1.2), 1e-6);
  assert.throws(() => E.decodeNightLights(new Uint8Array([65, 87, 78, 49, 0, 0]).buffer), /not a night lights file/);
});

test('nightLightsVertices: Mercator x, y and the brightness of points spread in their cells, as many as the density says', () => {
  // Full light: density points a cell, all in it.
  const d = E.decodeNightLights(packLights(360, 180, [[0, 5, 255], [90, 180, 255], [179, 359, 255]]));
  const v = E.nightLightsVertices(d, 4);
  assert.equal(v.length, 3 * 12);
  for (let k = 0; k < 12; k++) {
    const [lon, lat] = lonLat(v, k), cell = [[0, 5], [90, 180], [179, 359]][Math.floor(k / 4)];
    assert.ok(lon >= cell[1] - 180 && lon <= cell[1] - 179, 'lon of ' + k + ': ' + lon);
    if (cell[0] === 90) assert.ok(lat <= 0 && lat >= -1, 'lat of ' + k + ': ' + lat);
    else assert.ok(Math.abs(lat) <= 85.0512, 'kept on the map near the pole: ' + lat);
    near(v[3 * k + 2], 1, 1e-6, 'full');
  }
  assert.notEqual(v[0], v[3], 'not all in one place');
  assert.deepEqual(Array.from(E.nightLightsVertices(d, 4)), Array.from(v), 'the same every time');
  // A dim cell: a point now and then, more with more density; more density keeps those of less.
  const dim = [];
  for (let c = 0; c < 360; c++) dim.push([60, c, 60]);
  const dd = E.decodeNightLights(packLights(360, 180, dim)), expect = 360 * dd.chance[60];
  const lo = E.nightLightsVertices(dd, 1), hi = E.nightLightsVertices(dd, 3);
  assert.ok(Math.abs(lo.length / 3 - expect) < 0.3 * expect + 3, 'density 1: ' + lo.length / 3 + ' for ' + expect);
  assert.ok(Math.abs(hi.length / 3 - 3 * expect) < 0.3 * 3 * expect + 3, 'density 3: ' + hi.length / 3 + ' for ' + 3 * expect);
  const his = new Set();
  for (let k = 0; k < hi.length; k += 3) his.add(hi[k] + ',' + hi[k + 1]);
  for (let k = 0; k < lo.length; k += 3) assert.ok(his.has(lo[k] + ',' + lo[k + 1]), 'point ' + k / 3 + ' of density 1 kept');
});

test('nightLightsLook: small points far out, a little larger closer in, never past 4 px; as bright in all as the picture', () => {
  for (const D of [1, 3, 6]) {
    let last = { size: 0, gain: 0, keep: 0 };
    for (let z = 0; z <= 10; z += 0.5) {
      const k = E.nightLightsLook(z, D);
      assert.ok(k.size >= last.size && k.gain >= last.gain - 1e-12 && k.keep >= last.keep, 'grows with the zoom at ' + z);
      assert.ok(k.size >= 1.5 && k.size <= 4, 'size at ' + z + ': ' + k.size);
      assert.ok(k.gain >= E.NIGHT_LIGHTS.minGain - 1e-12 && k.gain <= 1, 'gain at ' + z + ': ' + k.gain);
      assert.ok(k.keep > 0 && k.keep <= 1, 'keep at ' + z + ': ' + k.keep);
      last = k;
    }
    // Far out, many points share a pixel: all of a cell give what it would.
    for (const z of [0, 1.3, 2, 4]) {
      const cell = 512 * Math.pow(2, z) / E.NIGHT_LIGHTS.cols, k = E.nightLightsLook(z, D);
      near(D * k.keep * k.size * k.size * k.gain, E.NIGHT_LIGHTS.boost * cell * cell, 1e-9, 'the light of a cell at zoom ' + z + ', density ' + D);
    }
  }
  // The whole globe: fewer points, none too faint for the screen.
  const far = E.nightLightsLook(1.3, 3);
  assert.ok(far.keep < 0.2 && far.gain * 255 * 0.7 > 10, JSON.stringify(far));
  assert.equal(E.nightLightsLook(9, 3).keep, 1, 'close in: all of them');
  // The globe turned north: MapLibre lowers the zoom, the globe keeps its
  // size on screen, and so do the lights.
  const z45 = 1.45, z75 = z45 + Math.log2(Math.cos(75 * Math.PI / 180) / Math.cos(45 * Math.PI / 180));
  const a = E.nightLightsLook(z45, 3, 45), b = E.nightLightsLook(z75, 3, 75);
  near(a.size, b.size, 1e-9); near(a.gain * a.keep, b.gain * b.keep, 1e-9, 'the same light');
  assert.deepEqual(E.nightLightsLook(2, 3, null), E.nightLightsLook(2, 3), 'the flat map as before');
  near(E.nightLightsLook(2, 3, 0).keep, E.nightLightsLook(2, 3).keep, 1e-12, 'a globe on the equator as the flat map');
  assert.equal(E.nightLightsLook(9, 3).gain, 1, 'close in: each point at full light');
  assert.equal(E.nightLightsLook(2).gain, E.nightLightsLook(2, E.NIGHT_LIGHTS.density[2]).gain, 'the default density');
});

test('the widget file holds the lights of the towns of the whole Earth', () => {
  const fs = require('node:fs'), zlib = require('node:zlib');
  const buf = zlib.gunzipSync(fs.readFileSync(require('node:path').join(__dirname, '../../../contents/ui/components/vendor/night-lights.bin.gz')));
  const d = E.decodeNightLights(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length));
  assert.ok(d.count > 600000 && d.count < 1200000, 'cells: ' + d.count);
  const v = E.nightLightsVertices(d, 1);
  assert.ok(v.length / 3 > 150000 && v.length / 3 < 400000, 'points at density 1: ' + v.length / 3);
  let paris = 0, atlantic = 0;
  for (let k = 0; k < v.length / 3; k++) {
    const [lon, lat] = lonLat(v, k);
    if (Math.abs(lat - 48.86) < 0.15 && Math.abs(lon - 2.35) < 0.2) paris++;
    if (lat > 25 && lat < 35 && lon > -45 && lon < -35) atlantic++;
  }
  assert.ok(paris > 30, 'Paris: ' + paris);
  assert.ok(atlantic < 5, 'mid-Atlantic: ' + atlantic);
  const [lo, hi] = E.NIGHT_LIGHTS.density;
  assert.ok(lo >= 1 && hi <= 15 && E.NIGHT_LIGHTS.density[2] >= lo && E.NIGHT_LIGHTS.density[2] <= hi);
});

test('viewWidthKm: the ground across the map, from its width in px, the zoom and the latitude', () => {
  near(E.viewWidthKm(512, 0, 0), 40075.0167, 1e-3, 'the equator at zoom 0');
  near(E.viewWidthKm(512, 1, 0), 40075.0167 / 2, 1e-3, 'half at zoom 1');
  near(E.viewWidthKm(512, 0, 60), 40075.0167 / 2, 1e-3, 'half as much ground at 60 degrees');
  // The globe turned to a pole: MapLibre sizes it as at 85 degrees.
  near(E.viewWidthKm(512, -1.585, 90), E.viewWidthKm(512, -1.585, 85.0511), 1e-9, 'at the north pole');
  near(E.viewWidthKm(512, -1.585, -89.9), E.viewWidthKm(512, -1.585, 85.0511), 1e-9, 'near the south pole');
  near(E.nightLightsLook(-1.585, 3, 90).keep, E.nightLightsLook(-1.585, 3, 85.0511).keep, 1e-12, 'the lights too');
});

test('nightLightsFade: all the lights over a whole country, none once half of France fills the map', () => {
  const [gone, full] = E.NIGHT_LIGHTS.fadeKm;
  assert.equal(gone, 500); assert.equal(full, 1000);
  assert.equal(E.nightLightsFade(20000), 1, 'the whole Earth');
  assert.equal(E.nightLightsFade(full), 1);
  assert.equal(E.nightLightsFade(gone), 0);
  assert.equal(E.nightLightsFade(100), 0);
  near(E.nightLightsFade((gone + full) / 2), 0.5, 1e-9, 'halfway');
  let last = 0;
  for (let km = gone; km <= full; km += 25) {
    const f = E.nightLightsFade(km);
    assert.ok(f >= last, 'more as the view widens, at ' + km);
    last = f;
  }
});

test('night lights: white with a touch of yellow, as the shader draws them', () => {
  const [r, g, b] = E.NIGHT_LIGHTS.color;
  assert.equal(r, 1);
  assert.ok(g >= 0.92 && g < 1, 'nearly white: ' + g);
  assert.ok(b >= 0.75 && b < g - 0.05, 'a touch of yellow: ' + b);
  assert.ok(E.NIGHT_LIGHTS_FS.includes('vec3(' + E.NIGHT_LIGHTS.color.map(E.glslFloat).join(', ') + ')'), 'in the shader');
});

test('shadeFrom: on the globe\'s polar caps (pole), the Sun seen from the real latitude', () => {
  const merc = (lat) => (1 - Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360)) / Math.PI) / 2;
  const edge = merc(85.0511), u = E.shadeUniforms({ lat: -3, lon: 0 }, 0.6, 0);
  // At the north pole the Sun is 3 degrees down, whatever the longitude.
  const atPole = E.shadeFrom(u, 0.1, edge, -1);
  E.shadeFrom(u, 0.6, edge, -1).forEach((c, k) => assert.ok(Math.abs(c - atPole[k]) < 1e-12, 'one color at the pole'));
  assert.ok(Math.abs(atPole[3] - (1 - Math.exp(u.ln[0] * Math.min(1, 3 / 18)))) < 1e-9, 'night 3 degrees deep');
  // Without the flag, the edge's colors as before.
  assert.notDeepEqual([...E.shadeFrom(u, 0.1, edge)], [...atPole]);
  assert.deepEqual([...E.shadeFrom(u, 0.1, edge, 0)], [...E.shadeFrom(u, 0.1, edge)]);
});

test('NIGHT_FS: the night reads the latitude of the caps', () => {
  assert.match(E.NIGHT_FS, /in float v_pole;/);
  assert.match(E.NIGHT_FS, /abs\(v_pole\)/);
});
