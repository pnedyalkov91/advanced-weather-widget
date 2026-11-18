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
 * barometerGauge.js - Canvas drawing for the expandable Pressure card.
 *
 * Same 970-1040 hPa range, bands (low < 1000, normal, high > 1025) and colour
 * scale as pressureGauge.js (it is reused for the colours), drawn in the
 * shared dial style: a weather-map scene of isobar lines that churn at low
 * pressure and flatten at high pressure, faint "L" / "H" pressure-centre
 * letters, and a continuous dimmed scale with the swept progress arc.
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "pressureGauge.js" as PG

var LO = 970;
var HI = 1040;
var TICKS = [970, 985, 1000, 1013, 1025, 1040];

function _t(h) { return GC.clamp01((h - LO) / (HI - LO)); }

function colorAt(h, isDark) { return PG.pressureColor(h, isDark); }

/** "low" | "normal" | "high" (same thresholds as pressureGauge.band), "" for no data. */
function bandKey(h) {
    if (!GC.isNum(h)) return "";
    return PG.band(h);
}

function info(h, isDark) {
    return { key: bandKey(h), color: GC.isNum(h) ? colorAt(h, isDark) : colorAt(1013, isDark) };
}

/**
 * Barometric tendency from the change over the last 3 hours (hPa per 3 h),
 * graded like the Met Office does: steady < 0.5, slowly < 1.6, (plain) < 3.6,
 * quickly < 6, rapidly above.
 * -> { key: "steady" | "rising" | "falling" | "rising_slowly" | ..., dir: -1 | 0 | 1 }
 */
function tendency(d3) {
    if (!GC.isNum(d3)) return { key: "", dir: 0 };
    var a = Math.abs(d3);
    if (a < 0.5) return { key: "steady", dir: 0 };
    var dir = d3 > 0 ? 1 : -1;
    var grade = a < 1.6 ? "_slowly" : (a < 3.6 ? "" : (a < 6 ? "_quickly" : "_rapidly"));
    return { key: (dir > 0 ? "rising" : "falling") + grade, dir: dir };
}

/** Colour of the tendency marker: cool for rising, warm for falling. */
function tendencyColor(dir, isDark) {
    if (dir > 0) return isDark ? "#4FC3F7" : "#0277BD";
    if (dir < 0) return isDark ? "#FFB74D" : "#E65100";
    return isDark ? "#B0BEC5" : "#546E7A";
}

// Bracket on the scale from where the pressure was 3 h ago to where it is now,
// an open ring at the old value and an arrow head at the new one.
function _drawTendency(ctx, g, p, tNow) {
    var t0 = _t(p.prev);
    var dir = p.trendDir || 0;
    var col = tendencyColor(dir, p.isDark);
    GC.drawRing(ctx, g, t0, col, p.isDark, 4.5);
    if (Math.abs(tNow - t0) < 0.012) return;
    GC.drawBracket(ctx, g, t0, tNow, col, 0.85);
    var sgn = tNow > t0 ? 1 : -1;
    var a = GC.angleAt(tNow), rr = g.r - 12;
    var px = g.cx + Math.cos(a) * rr, py = g.baseY + Math.sin(a) * rr;
    var tx = -Math.sin(a) * sgn, ty = Math.cos(a) * sgn;     // direction of travel
    var nx = Math.cos(a), ny = Math.sin(a);                   // radial
    ctx.beginPath();
    ctx.moveTo(px + tx * 6, py + ty * 6);
    ctx.lineTo(px - tx * 2 + nx * 4, py - ty * 2 + ny * 4);
    ctx.lineTo(px - tx * 2 - nx * 4, py - ty * 2 - ny * 4);
    ctx.closePath();
    ctx.fillStyle = GC.rgba(col, 0.9);
    ctx.fill();
}

/**
 * p = { v: hPa, isDark, text,
 *       labels: optional 6 strings for the ticks 970/985/1000/1013/1025/1040
 *               (already converted to the display unit),
 *       prev: optional hPa value 3 hours ago, trendDir: -1 | 0 | 1 (see tendency()) }
 */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var has = GC.isNum(p.v);
    var t = has ? _t(p.v) : 0.5;
    var cur = colorAt(has ? p.v : 1013, p.isDark);

    // ── Scene: glow, isobars, L / H ──────────────────────────────────────
    GC.clipDisc(ctx, g, 6);
    var glow = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
    glow.addColorStop(0, GC.rgba(cur, has ? 0.18 : 0.05));
    glow.addColorStop(0.75, GC.rgba(cur, has ? 0.05 : 0.02));
    glow.addColorStop(1, GC.rgba(cur, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, cw, ch);

    // calm (high) -> nearly straight lines; stormy (low) -> choppy ones
    var calm = GC.clamp01((t - 0.15) / 0.7);
    var amp = 4.6 - 4.0 * calm;
    var x0 = g.cx - g.r, x1 = g.cx + g.r;
    ctx.lineWidth = 1.2;
    ctx.lineCap = "round";
    for (var i = 0; i < 5; i++) {
        var yy = g.baseY - (g.r - 14) * (0.17 + 0.165 * i);
        ctx.beginPath();
        GC.wavePath(ctx, x0, x1, yy, amp, 0.030 + 0.004 * i, 1.3 * i, false);
        ctx.strokeStyle = GC.rgba(cur, 0.12 + 0.05 * (i % 2));
        ctx.stroke();
    }
    var lPos = GC.pointAt(g, 0.15, g.r - 40), hPos = GC.pointAt(g, 0.85, g.r - 40);
    var lowA = has && p.v < 1000 ? 0.26 : 0.10, highA = has && p.v > 1025 ? 0.26 : 0.10;
    GC.label(ctx, "L", lPos.x, lPos.y, 24, p.text, lowA, true, "center", "middle");
    GC.label(ctx, "H", hPos.x, hPos.y, 24, p.text, highA, true, "center", "middle");
    ctx.restore();

    // ── Dial ─────────────────────────────────────────────────────────────
    var ticks = [];
    for (var k = 0; k < TICKS.length; k++) {
        var lbl = (p.labels && p.labels[k] !== undefined) ? p.labels[k] : String(TICKS[k]);
        ticks.push({ t: _t(TICKS[k]), label: lbl, major: TICKS[k] === 1013 });
    }
    GC.drawDial(ctx, g, {
        ghostAt: function (tt) { return colorAt(LO + tt * (HI - LO), p.isDark); },
        bandAlpha: 0.32,
        t: has ? t : NaN,
        colorAt: function (tt) { return colorAt(LO + tt * (HI - LO), p.isDark); },
        ticks: ticks,
        text: p.text
    });
    if (has && GC.isNum(p.prev)) _drawTendency(ctx, g, p, t);
    if (has) GC.drawDot(ctx, g, t, cur, p.isDark, 6.5);
}
