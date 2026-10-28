/*
 * Copyright 2026 Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://gnu.org>.
 */


/**
 * arcUtils.js - Utilities shared by sunpath.js and moonpath.js
 *
 * .pragma library - pure JS math, no Qt APIs.
 *
 * Import via:
 *   import "js/arcUtils.js" as ArcUtils
 */
.pragma library

/**
 * Parses a "HH:mm" string to minutes since midnight.
 * Returns -1 for missing / invalid input.
 */
function parseMins(t) {
    if (!t || t === "--") return -1;
    var p = t.split(":");
    if (p.length < 2) return -1;
    var h = parseInt(p[0], 10), m = parseInt(p[1], 10);
    return (isNaN(h) || isNaN(m)) ? -1 : h * 60 + m;
}

/**
 * Returns current local time at the weather location in minutes since midnight.
 * Uses UTC + utcOffsetMins - the only reliable approach in Qt V4 (no Intl/timeZone).
 */
function nowMinsAt(utcOffsetMins) {
    var d = new Date();
    return ((d.getUTCHours() * 60 + d.getUTCMinutes()) + (utcOffsetMins || 0) + 1440) % 1440;
}

/**
 * Formats a duration given in total minutes to "Xh Ym" or "Ym".
 */
function formatDuration(totalMins) {
    if (isNaN(totalMins) || totalMins < 0) return "--";
    var h = Math.floor(totalMins / 60);
    var m = Math.round(totalMins % 60);
    if (h > 0 && m > 0) return h + "h " + m + "m";
    if (h > 0)          return h + "h";
    return m + "m";
}

/**
 * Draws a starfield in the upper portion of an arc canvas.
 * Used by both sun-arc (night mode) and moon-arc drawings.
 */
function drawStars(ctx, cw, ch, hY, count, isDark) {
    var alpha = isDark ? 0.55 : 0.28;
    ctx.fillStyle = isDark ? "rgba(255,255,255," + alpha + ")" : "rgba(100,100,150," + alpha + ")";
    var seed = 42;
    function rand() {
        seed = (seed * 16807 + 0) % 2147483647;
        return (seed - 1) / 2147483646;
    }
    for (var i = 0; i < count; i++) {
        var x = rand() * cw;
        var y = rand() * hY * 0.85;
        var r = 0.5 + rand() * 1.0;
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
    }
}
