/*
 * Copyright 2026 rcspam
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

'use strict';
// Unit tests for the radar and satellite tiles read ahead (glue-prefetch.js).
// Run: node --test scripts/librewxr-map-src/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const P = require('../glue-prefetch.js');

const key = (t) => t.z + '/' + t.x + '/' + t.y;

test('tilesFor: the tiles over an area, nearest the middle first', () => {
  // Around Lyon at level 6: x 32, y 22 (one tile).
  const box = [4.5, 45.5, 5.0, 46.0];
  assert.deepEqual(P.tilesFor(box, 6, 0).map(key), ['6/32/22']);
  const ring = P.tilesFor(box, 6, 1).map(key);
  assert.equal(ring.length, 9);
  assert.equal(ring[0], '6/32/22');
  assert.ok(ring.includes('6/31/21') && ring.includes('6/33/23'));
});

test('tilesFor: x wraps around the date line, y stays on the map', () => {
  const xs = P.tilesFor([170, -10, -170, 10], 3, 0).map((t) => t.x).sort((a, b) => a - b);
  assert.deepEqual(Array.from(new Set(xs)), [0, 7]);
  const top = P.tilesFor([-10, 80, 10, 85], 2, 1);
  assert.ok(top.every((t) => t.y >= 0 && t.y <= 3));
  // The whole world at level 1: four tiles, none twice.
  assert.equal(P.tilesFor([-180, -85, 180, 85], 1, 1).length, 4);
});

test('urlFor: the host MapLibre picks, (x + y) modulo their number', () => {
  const urls = ['http://localhost:8099/r/{z}/{x}/{y}.webp', 'http://a.localhost:8099/r/{z}/{x}/{y}.webp'];
  assert.equal(P.urlFor(urls, { z: 6, x: 32, y: 22 }), 'http://localhost:8099/r/6/32/22.webp');
  assert.equal(P.urlFor(urls, { z: 6, x: 33, y: 22 }), 'http://a.localhost:8099/r/6/33/22.webp');
});

const tpl = (n) => ['http://h/' + n + '/{z}/{x}/{y}'];

test('plan: the view of the other images, then the ring, the level in, the level out', () => {
  const box = [4.5, 45.5, 5.0, 46.0];
  const frames = [
    { urls: tpl('a'), maxZoom: 9, shown: false },
    { urls: tpl('b'), maxZoom: 9, shown: true },
    { urls: tpl('c'), maxZoom: 9, shown: false }
  ];
  const list = P.plan({ box, z: 6, frames });
  const at = (u) => list.indexOf(u);
  // The shown image's view is MapLibre's own.
  assert.equal(at('http://h/b/6/32/22'), -1);
  assert.ok(at('http://h/a/6/32/22') < at('http://h/c/6/32/22'));
  assert.ok(at('http://h/c/6/32/22') < at('http://h/b/6/31/21'));      // view before ring
  assert.ok(at('http://h/b/6/31/21') < at('http://h/a/6/31/21'));      // shown first in the ring
  assert.ok(at('http://h/a/6/33/23') < at('http://h/b/7/65/45'));      // ring before the level in
  assert.ok(at('http://h/c/7/65/45') < at('http://h/b/5/16/11'));      // level in before level out
  assert.equal(new Set(list).size, list.length);
});

test('plan: no level in past the last level, nothing twice at the cap', () => {
  const box = [4.5, 45.5, 5.0, 46.0];
  const frames = [{ urls: tpl('a'), maxZoom: 9, shown: false }];
  const at9 = P.plan({ box, z: 9, frames });
  assert.ok(at9.every((u) => !/\/10\//.test(u)));
  // Beyond the cap the view takes the level 9 tiles; the level out is 9 too.
  const at11 = P.plan({ box, z: 11, frames });
  assert.ok(at11.every((u) => /\/a\/9\//.test(u)));
  assert.equal(new Set(at11).size, at11.length);
});

test('plan: images the server keeps 5 min only get their view, nothing around', () => {
  const box = [4.5, 45.5, 5.0, 46.0];
  const frames = [{ urls: tpl('n'), maxZoom: 9, shown: false, shortLived: true }];
  assert.deepEqual(P.plan({ box, z: 6, frames }), ['http://h/n/6/32/22']);
});

test('Queue: n at a time, in order, each once, a stop drops the rest', async () => {
  const asked = [];
  let running = 0, most = 0;
  const fetchOne = (u, signal) => new Promise((ok, ko) => {
    asked.push(u); running++; most = Math.max(most, running);
    const t = setTimeout(() => { running--; ok(); }, 5);
    signal.addEventListener('abort', () => { clearTimeout(t); running--; ko(new Error('abort')); });
  });
  const q = new P.Queue(fetchOne, 2);
  await q.run(['u1', 'u2', 'u3', 'u4']);
  assert.deepEqual(asked, ['u1', 'u2', 'u3', 'u4']);
  assert.equal(most, 2);
  // Done once: not asked again.
  await q.run(['u1', 'u5']);
  assert.deepEqual(asked.slice(4), ['u5']);
  // Stopped: what was under way is asked again next time.
  const p = q.run(['u6', 'u7', 'u8']);
  q.stop();
  await p;
  const before = asked.length;
  await q.run(['u6', 'u7', 'u8']);
  assert.deepEqual(asked.slice(before), ['u6', 'u7', 'u8']);
  // forget: everything may be asked again.
  q.forget();
  await q.run(['u1']);
  assert.equal(asked[asked.length - 1], 'u1');
});
