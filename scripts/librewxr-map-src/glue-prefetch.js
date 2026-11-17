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

// ==========================================================================
// RADAR AND SATELLITE TILES READ AHEAD
// Only the image on the map is a layer that loads (glue-adapter-maplibre.js
// holds the others back). The tiles of the other images of the animation,
// of a ring around the view and of the levels in and out are read ahead
// into the browser's cache, a few at a time: a play, a move or a zoom then
// finds them there and asks the server for nothing. WidgetPrefetch is
// loadable under Node for tests.
// ==========================================================================
var WidgetPrefetch = (function () {
  'use strict';

  function lonToX(lon, z) { return (lon + 180) / 360 * Math.pow(2, z); }
  function latToY(lat, z) {
    var l = Math.max(-85.0511, Math.min(85.0511, lat)) * Math.PI / 180;
    return (1 - Math.log(Math.tan(l) + 1 / Math.cos(l)) / Math.PI) / 2 * Math.pow(2, z);
  }

  /** The tiles { z, x, y } at level z over box [west, south, east, north]
      and ring tiles around it, nearest the middle first; x wraps around
      the date line, y stays on the map, none twice. */
  function tilesFor(box, z, ring) {
    var n = Math.pow(2, z), r = ring || 0;
    var east = box[2] < box[0] ? box[2] + 360 : box[2];
    var x0 = Math.floor(lonToX(box[0], z)) - r, x1 = Math.floor(lonToX(east, z)) + r;
    var y0 = Math.max(0, Math.floor(latToY(box[3], z)) - r);
    var y1 = Math.min(n - 1, Math.floor(latToY(box[1], z)) + r);
    if (x1 - x0 + 1 > n) { x0 = 0; x1 = n - 1; }
    var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, seen = {}, out = [];
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        var wx = ((x % n) + n) % n, k = wx + '/' + y;
        if (seen[k]) continue;
        seen[k] = true;
        out.push({ z: z, x: wx, y: y, d: Math.abs(x - cx) + Math.abs(y - cy) });
      }
    }
    out.sort(function (a, b) { return a.d - b.d; });
    return out.map(function (t) { return { z: t.z, x: t.x, y: t.y }; });
  }

  /** The address of tile t among urls, on the host MapLibre takes for it
      (maplibre-gl CanonicalTileID.url): the browser's cache keys on it. */
  function urlFor(urls, t) {
    return urls[(t.x + t.y) % urls.length]
      .replace('{z}', t.z).replace('{x}', t.x).replace('{y}', t.y);
  }

  /** The addresses to read ahead, in order, for the view o.box at tile
      level o.z, o.frames: [{ urls, maxZoom, shown, shortLived }] (shown:
      the image on the map, whose view MapLibre loads itself; shortLived:
      the last observed image and the nowcast, kept 5 min by the server,
      read for the view only).
        1. the view, the other images;
        2. a ring of one tile around it, the shown image first;
        3. the level in, over the view (past an image's maxZoom the map
           stretches its tiles: nothing to read);
        4. the level out, over the view and its ring. */
  function plan(o) {
    var out = [], seen = {};
    function add(f, tiles) {
      tiles.forEach(function (t) {
        var u = urlFor(f.urls, t);
        if (seen[u]) return;
        seen[u] = true;
        out.push(u);
      });
    }
    var shownFirst = o.frames.filter(function (f) { return f.shown; })
      .concat(o.frames.filter(function (f) { return !f.shown; }));
    var lasting = shownFirst.filter(function (f) { return !f.shortLived; });
    function levelOf(f, z) { return Math.max(0, Math.min(z, f.maxZoom)); }
    // The shown image's own view counts as read: the map asks for it.
    o.frames.forEach(function (f) {
      if (f.shown) tilesFor(o.box, levelOf(f, o.z), 0).forEach(function (t) { seen[urlFor(f.urls, t)] = true; });
    });
    o.frames.forEach(function (f) { if (!f.shown) add(f, tilesFor(o.box, levelOf(f, o.z), 0)); });
    lasting.forEach(function (f) { add(f, tilesFor(o.box, levelOf(f, o.z), 1)); });
    lasting.forEach(function (f) {
      if (o.z + 1 <= f.maxZoom) add(f, tilesFor(o.box, o.z + 1, 0));
    });
    lasting.forEach(function (f) {
      var zo = levelOf(f, o.z - 1);
      if (zo !== levelOf(f, o.z)) add(f, tilesFor(o.box, zo, 1));
    });
    return out;
  }

  /** Reads addresses at most n at a time with fetchOne(url, signal), in
      order. Each read once: run() skips those done. stop() aborts what is
      under way and drops the rest (they may come again in the next run);
      forget() lets every address be read again (a new catalog). */
  function Queue(fetchOne, n) {
    this.fetchOne = fetchOne;
    this.n = n || 3;
    this.done = {};
    this.job = 0;
    this.live = [];
  }
  Queue.prototype.run = function (urls) {
    this.stop();
    var self = this, job = this.job, i = 0;
    var list = urls.filter(function (u) { return !self.done[u]; });
    return new Promise(function (resolve) {
      var active = 0;
      function next() {
        if (job !== self.job) { if (!active) resolve(); return; }
        if (i >= list.length) { if (!active) resolve(); return; }
        var u = list[i++], ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
        active++;
        if (ctl) self.live.push(ctl);
        Promise.resolve().then(function () { return self.fetchOne(u, ctl ? ctl.signal : null); }).then(function () {
          if (job === self.job) self.done[u] = true;
        }, function () { /* aborted or failed: may be read next time */ }).then(function () {
          active--;
          if (ctl) self.live.splice(self.live.indexOf(ctl), 1);
          next();
        });
      }
      for (var k = 0; k < self.n; k++) next();
      if (!list.length) resolve();
    });
  };
  Queue.prototype.stop = function () {
    this.job++;
    this.live.slice().forEach(function (c) { c.abort(); });
  };
  Queue.prototype.forget = function () { this.done = {}; };

  return { tilesFor: tilesFor, urlFor: urlFor, plan: plan, Queue: Queue };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetPrefetch; }
