/*
 * Copyright 2026 Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
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
 * spaceWeatherGauge.js - Canvas drawing for one page of the expandable Space
 * Weather card (G scale, Kp index, solar wind, aurora, Bz, X-ray class).
 *
 * The scales (zones, tick positions, position of the reading, colours) are
 * worked out by DetailsView from spaceWeather.js, so this file only draws:
 * a dial in the shared style over a small scene that fits the metric -
 *   gscale / kp   magnetosphere field arcs that get more distorted with the level
 *   solarwind     particle streaks flowing in from the Sun on the left
 *   aurora        curtains of light whose height follows the probability
 *   bz            field lines of the solar wind pointing north or south
 *   xray          the Sun's limb with flare rays
 */
.pragma library
.import "gaugeCommon.js" as GC

/**
 * p = { kind: "gscale" | "kp" | "solarwind" | "aurora" | "bz" | "xray",
 *       t: 0..1 position of the reading (NaN = no data), bandColor,
 *       zones: [{from, to, color}] (0..1), ticks: [{t, label, major}],
 *       south: bool (bz only: the field points south), isDark, text }
 */

function _stars(ctx, g, rng, text, n) {
    for (var i = 0; i < n; i++) {
        var pt = GC.randomInDisc(rng, g, g.r - 8);
        var r = 0.5 + rng() * 0.9;
        ctx.beginPath(); ctx.arc(pt.x, pt.y, r, 0, 2 * GC.PI);
        ctx.fillStyle = GC.rgba(text, 0.10 + rng() * 0.20);
        ctx.fill();
    }
}

function _fieldArcs(ctx, g, col, dens, rng) {
    // nested field lines around the centre; the higher the level the more they wobble
    ctx.lineWidth = 1.2;
    ctx.lineCap = "round";
    for (var i = 1; i <= 4; i++) {
        var rad = (g.r - 14) * (0.26 + 0.19 * i);
        var amp = (0.4 + 3.6 * dens) * (0.5 + 0.2 * i);
        ctx.beginPath();
        var steps = 48;
        for (var k = 0; k <= steps; k++) {
            var u = k / steps;
            var a = GC.PI + u * GC.PI;
            var rr = rad + Math.sin(u * GC.PI * (6 + i) + i * 1.7) * amp * Math.sin(u * GC.PI);
            var x = g.cx + Math.cos(a) * rr, y = g.baseY + Math.sin(a) * rr;
            if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.strokeStyle = GC.rgba(col, 0.14 + 0.05 * (i % 2));
        ctx.stroke();
    }
    // a few charged particles riding the lines
    var n = Math.round(2 + 8 * dens);
    for (var j = 0; j < 10; j++) {
        var pt = GC.randomInDisc(rng, g, g.r - 18);
        if (j >= n) continue;
        ctx.beginPath(); ctx.arc(pt.x, pt.y, 1 + rng() * 1.3, 0, 2 * GC.PI);
        ctx.fillStyle = GC.rgba(col, 0.40); ctx.fill();
    }
}

function _solarWind(ctx, g, col, dens, rng) {
    // the Sun's glow on the left, particle streaks streaming right
    var sx = g.cx - g.r * 0.98, sy = g.baseY - g.r * 0.30;
    var gl = ctx.createRadialGradient(sx, sy, 0, sx, sy, g.r * 0.7);
    gl.addColorStop(0, GC.rgba("#FFC107", 0.30));
    gl.addColorStop(1, GC.rgba("#FFC107", 0));
    ctx.fillStyle = gl;
    ctx.beginPath(); ctx.arc(sx, sy, g.r * 0.7, 0, 2 * GC.PI); ctx.fill();
    ctx.lineCap = "round";
    var n = Math.round(6 + 22 * dens);
    for (var i = 0; i < 28; i++) {
        var y = g.baseY - 8 - rng() * (g.r - 22);
        var x = g.cx - g.r + 10 + rng() * (g.r * 1.7);
        var len = 8 + rng() * (10 + 26 * dens);
        var al = 0.20 + rng() * 0.30;
        if (i >= n) continue;
        ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + len, y + (rng() - 0.5) * 3);
        ctx.lineWidth = 1 + rng() * 0.8;
        ctx.strokeStyle = GC.rgba(col, al); ctx.stroke();
        ctx.beginPath(); ctx.arc(x + len, y, 1.2, 0, 2 * GC.PI);
        ctx.fillStyle = GC.rgba(col, al + 0.1); ctx.fill();
    }
}

function _aurora(ctx, g, col, dens, rng) {
    // vertical curtains: each a column of fading strokes with a wavy base line
    var n = 64;
    var left = g.cx - g.r * 0.9, span = g.r * 1.8;
    var hmax = (g.r - 18) * (0.22 + 0.62 * dens);
    ctx.lineCap = "round";
    for (var i = 0; i < n; i++) {
        var u = i / (n - 1);
        var x = left + span * u;
        var base = g.baseY - 10 - 6 * Math.sin(u * 9 + 0.6) - 4 * Math.sin(u * 17);
        var h = hmax * (0.35 + 0.65 * Math.sin(u * GC.PI)) * (0.72 + 0.28 * Math.sin(u * 11 + 0.8));
        var grad = ctx.createLinearGradient(x, base, x, base - h);
        grad.addColorStop(0, GC.rgba(col, 0.32));
        grad.addColorStop(1, GC.rgba(col, 0));
        ctx.beginPath(); ctx.moveTo(x, base); ctx.lineTo(x, base - h);
        ctx.lineWidth = span / n + 0.8;
        ctx.strokeStyle = grad; ctx.stroke();
    }
    ctx.beginPath();
    for (var k = 0; k <= 40; k++) {
        var uu = k / 40;
        var xx = left + span * uu;
        var yy = g.baseY - 10 - 6 * Math.sin(uu * 9 + 0.6) - 4 * Math.sin(uu * 17);
        if (k === 0) ctx.moveTo(xx, yy); else ctx.lineTo(xx, yy);
    }
    ctx.lineWidth = 1.2; ctx.strokeStyle = GC.rgba(col, 0.40); ctx.stroke();
}

function _bz(ctx, g, col, south, dens) {
    // vertical field lines with arrow heads (down = southward = geoeffective)
    var n = 7;
    var left = g.cx - g.r * 0.78, span = g.r * 1.56;
    var top = g.baseY - (g.r - 20), bot = g.baseY - 8;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    for (var i = 0; i < n; i++) {
        var x = left + span * (i / (n - 1));
        var wob = Math.sin(i * 1.9) * 3;
        ctx.beginPath(); ctx.moveTo(x, top); ctx.quadraticCurveTo(x + wob * 3, (top + bot) / 2, x, bot);
        ctx.lineWidth = 1.2; ctx.strokeStyle = GC.rgba(col, 0.16 + 0.12 * dens); ctx.stroke();
        var ay = (top + bot) / 2 + (south ? 6 : -6), d = south ? 1 : -1;
        ctx.beginPath();
        ctx.moveTo(x - 3.5, ay - d * 4); ctx.lineTo(x, ay); ctx.lineTo(x + 3.5, ay - d * 4);
        ctx.strokeStyle = GC.rgba(col, 0.34); ctx.stroke();
    }
}

function _xray(ctx, g, col, dens, rng) {
    // the Sun's limb at the top centre, flare rays fanning down
    var sx = g.cx, sy = g.baseY - g.r * 0.98, sr = g.r * 0.30;
    var gl = ctx.createRadialGradient(sx, sy, sr * 0.8, sx, sy, g.r * 0.75);
    gl.addColorStop(0, GC.rgba(col, 0.28));
    gl.addColorStop(1, GC.rgba(col, 0));
    ctx.fillStyle = gl;
    ctx.beginPath(); ctx.arc(sx, sy, g.r * 0.75, 0, 2 * GC.PI); ctx.fill();
    ctx.beginPath(); ctx.arc(sx, sy, sr, 0, 2 * GC.PI);
    ctx.fillStyle = GC.rgba(col, 0.20); ctx.fill();
    ctx.lineCap = "round";
    var n = Math.round(5 + 15 * dens);
    for (var i = 0; i < 20; i++) {
        var a = GC.PI * (0.12 + 0.76 * (i / 19));
        var len = (g.r * 0.18) * (0.5 + rng()) + g.r * 0.34 * dens * rng();
        if (i >= n) continue;
        ctx.beginPath();
        ctx.moveTo(sx + Math.cos(a) * (sr + 3), sy + Math.sin(a) * (sr + 3));
        ctx.lineTo(sx + Math.cos(a) * (sr + 3 + len), sy + Math.sin(a) * (sr + 3 + len));
        ctx.lineWidth = 1.2 + rng() * 1.2;
        ctx.strokeStyle = GC.rgba(col, 0.16 + 0.22 * rng());
        ctx.stroke();
    }
}

function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var has = GC.isNum(p.t);
    var t = has ? GC.clamp01(p.t) : 0;
    var col = (has && p.bandColor) ? p.bandColor : "#8E9BAE";
    var rng = GC.makeRng(91 + (p.kind ? p.kind.length : 0));
    var dens = has ? 0.12 + 0.88 * t : 0;

    // ── Scene ────────────────────────────────────────────────────────────
    GC.clipDisc(ctx, g, 6);
    var glow = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
    glow.addColorStop(0, GC.rgba(col, has ? 0.14 : 0.04));
    glow.addColorStop(1, GC.rgba(col, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, cw, ch);
    _stars(ctx, g, rng, p.text, 26);

    if (p.kind === "solarwind") _solarWind(ctx, g, col, dens, rng);
    else if (p.kind === "aurora") _aurora(ctx, g, col, dens, rng);
    else if (p.kind === "bz") _bz(ctx, g, col, p.south === true, dens);
    else if (p.kind === "xray") _xray(ctx, g, col, dens, rng);
    else _fieldArcs(ctx, g, col, dens, rng);
    ctx.restore();

    // ── Dial ─────────────────────────────────────────────────────────────
    var bands = [];
    var zones = p.zones || [];
    for (var i = 0; i < zones.length; i++)
        bands.push({ from: zones[i].from, to: zones[i].to, color: zones[i].color });
    GC.drawDial(ctx, g, {
        bands: bands,
        bandAlpha: p.isDark ? 0.34 : 0.42,
        t: has ? t : NaN,
        colorAt: function (tt) {
            for (var j = 0; j < zones.length; j++)
                if (tt <= zones[j].to) return zones[j].color;
            return zones.length ? zones[zones.length - 1].color : col;
        },
        ticks: p.ticks || [],
        text: p.text
    });
    if (has) GC.drawDot(ctx, g, t, col, p.isDark, 6.5);
}
