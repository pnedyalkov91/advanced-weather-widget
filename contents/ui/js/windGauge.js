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
 * windGauge.js - Canvas drawing for the expandable Wind card.
 *
 * A full compass on the left (the card's text overlay sits to its right, see
 * ExpandedGauge layoutMode "side"): ring with ticks and N/E/S/W, a glow and
 * streaks that flow in the direction the wind is blowing TO, a navigation
 * arrow, and a dot + wedge on the ring at the bearing the wind comes FROM.
 * Colour and streak density follow the Beaufort scale.
 *
 * Direction convention is the one from windCompass.js: dir = meteorological
 * "from" bearing in degrees (0 = N); the arrow points 180 degrees away.
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "windCompass.js" as WC

var BF_KMH = [1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118];
var BF_KEYS = ["calm", "lightair", "lightbreeze", "gentlebreeze", "moderatebreeze",
               "freshbreeze", "strongbreeze", "neargale", "gale", "stronggale",
               "storm", "violentstorm", "hurricane"];

/** Beaufort number 0..12 for a speed in km/h, -1 for no data. */
function beaufort(kmh) {
    if (!GC.isNum(kmh)) return -1;
    for (var i = 0; i < BF_KMH.length; i++)
        if (kmh < BF_KMH[i]) return i;
    return 12;
}

function bandKey(kmh) {
    var b = beaufort(kmh);
    return b < 0 ? "" : BF_KEYS[b];
}

function _pal(isDark) {
    return isDark
        ? { blue: "#4db6f0", teal: "#3ecf8e", amber: "#f0a830", red: "#f0533e", violet: "#c76bf0" }
        : { blue: "#1a7fc0", teal: "#0f9a62", amber: "#b87000", red: "#c8321e", violet: "#8a2a9a" };
}

function colorAt(kmh, isDark) {
    var p = _pal(isDark);
    return GC.colorScale([[0, p.blue], [10, p.blue], [20, p.teal], [30, p.teal],
                          [45, p.amber], [55, p.red], [90, p.red], [120, p.violet]], kmh);
}

function info(kmh, isDark) {
    return { key: bandKey(kmh), color: GC.isNum(kmh) ? colorAt(kmh, isDark) : _pal(isDark).blue };
}

function cardinal(deg) { return WC.cardinal(deg); }

/** Compass placement: left part of the card, vertically centred. */
function geometry(cw, ch) {
    var R = Math.min(ch / 2 - 16, cw * 0.27);
    return { cx: cw * 0.30, cy: ch / 2 + 2, R: R, ok: cw > 0 && ch > 0 && R > 24 };
}

/** p = { v: wind km/h, dir: bearing it blows FROM (deg), isDark, text } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = geometry(cw, ch);
    if (!g.ok) return;

    var PI = Math.PI;
    var has = GC.isNum(p.v);
    var hasDir = GC.isNum(p.dir);
    var col = has ? colorAt(p.v, p.isDark) : _pal(p.isDark).blue;
    var t = has ? GC.clamp01(p.v / 90) : 0;
    var halo = p.isDark ? "rgba(20,20,20,0.85)" : "rgba(255,255,255,0.95)";

    // ── Glow + inner rings ───────────────────────────────────────────────
    var glow = ctx.createRadialGradient(g.cx, g.cy, 0, g.cx, g.cy, g.R);
    glow.addColorStop(0, GC.rgba(col, has ? 0.22 : 0.06));
    glow.addColorStop(0.7, GC.rgba(col, has ? 0.07 : 0.02));
    glow.addColorStop(1, GC.rgba(col, 0));
    ctx.fillStyle = glow;
    ctx.beginPath(); ctx.arc(g.cx, g.cy, g.R, 0, 2 * PI); ctx.fill();

    ctx.lineWidth = 1;
    ctx.strokeStyle = GC.rgba(p.text, 0.07);
    var ringsAt = [0.62, 0.30];
    for (var i = 0; i < ringsAt.length; i++) {
        ctx.beginPath(); ctx.arc(g.cx, g.cy, g.R * ringsAt[i], 0, 2 * PI); ctx.stroke();
    }
    // cross hairs
    ctx.beginPath();
    ctx.moveTo(g.cx - g.R + 24, g.cy); ctx.lineTo(g.cx + g.R - 24, g.cy);
    ctx.moveTo(g.cx, g.cy - g.R + 24); ctx.lineTo(g.cx, g.cy + g.R - 24);
    ctx.stroke();

    // ── Streaks flowing in the direction the wind blows TO ───────────────
    var dx = 0, dy = 0;
    if (has && hasDir) {
        var to = (p.dir + 180) * PI / 180;
        dx = Math.sin(to);
        dy = -Math.cos(to);
        if (p.v >= 1) {
            ctx.save();
            ctx.beginPath(); ctx.arc(g.cx, g.cy, g.R - 24, 0, 2 * PI); ctx.clip();
            var rng = GC.makeRng(57);
            var n = Math.round(4 + 14 * t);
            var len = 14 + 34 * t;
            ctx.lineCap = "round";
            for (var k = 0; k < 18; k++) {
                var rr = (g.R - 28) * Math.sqrt(rng());
                var aa = rng() * 2 * PI;
                var lw = 1.1 + rng() * 1.2;
                var al = 0.30 + rng() * 0.30;
                if (k >= n) continue;
                var x0 = g.cx + Math.cos(aa) * rr, y0 = g.cy + Math.sin(aa) * rr;
                var xa = x0 - dx * len / 2, ya = y0 - dy * len / 2;
                var xb = x0 + dx * len / 2, yb = y0 + dy * len / 2;
                var sg = ctx.createLinearGradient(xa, ya, xb, yb);
                sg.addColorStop(0, GC.rgba(col, 0));
                sg.addColorStop(1, GC.rgba(col, al));
                ctx.beginPath(); ctx.moveTo(xa, ya); ctx.lineTo(xb, yb);
                ctx.lineWidth = lw; ctx.strokeStyle = sg; ctx.stroke();
            }
            ctx.restore();
        }
    }

    // ── Ring, ticks, cardinal letters ────────────────────────────────────
    ctx.beginPath(); ctx.arc(g.cx, g.cy, g.R, 0, 2 * PI);
    ctx.lineWidth = 6; ctx.strokeStyle = GC.rgba(p.text, 0.13); ctx.stroke();

    ctx.lineCap = "butt";
    for (var q = 0; q < 36; q++) {
        var ta = (q * 10 - 90) * PI / 180;
        var major = (q % 9 === 0);
        var r0 = g.R - 6, r1 = g.R - (major ? 14 : 10);
        ctx.beginPath();
        ctx.moveTo(g.cx + Math.cos(ta) * r0, g.cy + Math.sin(ta) * r0);
        ctx.lineTo(g.cx + Math.cos(ta) * r1, g.cy + Math.sin(ta) * r1);
        ctx.lineWidth = major ? 1.4 : 1;
        ctx.strokeStyle = GC.rgba(p.text, major ? 0.55 : 0.28);
        ctx.stroke();
    }
    var cards = [["N", 0], ["E", 90], ["S", 180], ["W", 270]];
    for (var c = 0; c < cards.length; c++) {
        var ca = (cards[c][1] - 90) * PI / 180;
        GC.label(ctx, cards[c][0], g.cx + Math.cos(ca) * (g.R - 24), g.cy + Math.sin(ca) * (g.R - 24),
                 10, p.text, cards[c][0] === "N" ? 1.0 : 0.55, cards[c][0] === "N", "center", "middle");
    }

    if (!(has && hasDir)) return;

    // ── Origin: wedge + dot on the ring at the "from" bearing ────────────
    var af = (p.dir - 90) * PI / 180;
    ctx.beginPath(); ctx.arc(g.cx, g.cy, g.R, af - 0.30, af + 0.30, false);
    ctx.lineWidth = 6; ctx.lineCap = "round"; ctx.strokeStyle = GC.rgba(col, 0.5); ctx.stroke();
    var ox = g.cx + Math.cos(af) * g.R, oy = g.cy + Math.sin(af) * g.R;
    ctx.beginPath(); ctx.arc(ox, oy, 6, 0, 2 * PI); ctx.fillStyle = col; ctx.fill();
    ctx.beginPath(); ctx.arc(ox, oy, 6, 0, 2 * PI); ctx.lineWidth = 2; ctx.strokeStyle = halo; ctx.stroke();

    // ── Arrow (kite) pointing to where the wind blows ────────────────────
    var ang = Math.atan2(dy, dx);
    var L = g.R - 30;
    var ca2 = Math.cos(ang), sa2 = Math.sin(ang);
    function pt(u, v) { return [g.cx + u * ca2 - v * sa2, g.cy + u * sa2 + v * ca2]; }
    var tip = pt(L, 0), wr = pt(-L * 0.45, L * 0.30), nt = pt(-L * 0.22, 0), wl = pt(-L * 0.45, -L * 0.30);
    ctx.save();
    ctx.globalAlpha = p.v < 1 ? 0.4 : 1;
    ctx.beginPath();
    ctx.moveTo(tip[0], tip[1]); ctx.lineTo(wr[0], wr[1]); ctx.lineTo(nt[0], nt[1]); ctx.lineTo(wl[0], wl[1]);
    ctx.closePath();
    ctx.fillStyle = GC.rgba(col, 0.92); ctx.fill();
    ctx.lineJoin = "round"; ctx.lineWidth = 1.5; ctx.strokeStyle = halo; ctx.stroke();
    ctx.restore();
    ctx.beginPath(); ctx.arc(g.cx, g.cy, 3, 0, 2 * PI); ctx.fillStyle = halo; ctx.fill();
}
