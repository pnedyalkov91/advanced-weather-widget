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
 * alertGauge.js - Canvas drawing for one alert page of the expandable Alerts
 * card.
 *
 * A three-zone severity dial (yellow / orange / red warning level) with the
 * marker in the zone of the alert, over a small scene for the hazard type
 * (MeteoAlarm awareness_type numbers, as in DetailsView.alertTypeGlyph):
 *   1 wind, 2 snow / ice, 3 thunderstorm, 4 fog, 5 high temperature,
 *   6 low temperature, 7 coastal, 8 forest fire, 9 avalanche, 10 rain,
 *   11 flooding, 12 rain-flood. Anything else gets a warning triangle.
 */
.pragma library
.import "gaugeCommon.js" as GC

var YELLOW = "#ffc107";
var ORANGE = "#ff8c00";
var RED = "#dc3545";
var NEUTRAL = "#999999";
var GREEN = "#4CAF50";

/** 1 = yellow, 2 = orange, 3 = red, 0 = unknown colour. */
function levelOf(color) {
    var c = String(color || "").toLowerCase();
    if (c === "yellow") return 1;
    if (c === "orange") return 2;
    if (c === "red") return 3;
    return 0;
}

function levelKey(level) {
    return level === 1 ? "yellow" : (level === 2 ? "orange" : (level === 3 ? "red" : ""));
}

function colorOf(level) {
    return level === 1 ? YELLOW : (level === 2 ? ORANGE : (level === 3 ? RED : NEUTRAL));
}

function info(color) {
    var l = levelOf(color);
    return { key: levelKey(l), color: colorOf(l) };
}

function _flame(ctx, x, y, s, col, al) {
    GC.dropletPath(ctx, x, y, s);
    ctx.fillStyle = GC.rgba(col, al);
    ctx.fill();
}

function _scene(ctx, g, type, col, text) {
    var rng = GC.makeRng(80 + type);
    var left = g.cx - g.r, right = g.cx + g.r, span = 2 * g.r;
    var top = g.baseY - (g.r - 14);
    var i, k, pt, x, y, len, al;

    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    if (type === 1) {
        // wind: gusting lines
        ctx.lineWidth = 1.6;
        for (i = 0; i < 8; i++) {
            y = g.baseY - (g.r - 16) * (0.12 + 0.11 * i);
            x = left + rng() * span * 0.4;
            len = 50 + rng() * 70;
            ctx.beginPath();
            GC.wavePath(ctx, x, Math.min(right, x + len), y, 2.4, 0.07, rng() * 6, false);
            ctx.strokeStyle = GC.rgba(col, 0.20 + rng() * 0.22);
            ctx.stroke();
        }
    } else if (type === 2 || type === 6 || type === 9) {
        // snow, ice, avalanche: flakes (+ frost rings / slope)
        if (type === 6) {
            for (i = 1; i <= 3; i++) {
                ctx.beginPath();
                ctx.arc(g.cx, g.baseY, (g.r - 14) * (0.30 + 0.22 * i), GC.PI, 2 * GC.PI, false);
                ctx.lineWidth = 1; ctx.strokeStyle = GC.rgba(col, 0.12); ctx.stroke();
            }
        }
        if (type === 9) {
            ctx.beginPath();
            ctx.moveTo(g.cx - g.r * 0.9, g.baseY + 2);
            ctx.lineTo(g.cx - g.r * 0.20, g.baseY - g.r * 0.62);
            ctx.lineTo(g.cx + g.r * 0.12, g.baseY - g.r * 0.30);
            ctx.lineTo(g.cx + g.r * 0.40, g.baseY - g.r * 0.50);
            ctx.lineTo(g.cx + g.r * 0.95, g.baseY + 2);
            ctx.closePath();
            ctx.fillStyle = GC.rgba(col, 0.10); ctx.fill();
            ctx.lineWidth = 1.3; ctx.strokeStyle = GC.rgba(col, 0.30); ctx.stroke();
        }
        var n = type === 6 ? 9 : 15;
        for (i = 0; i < 15; i++) {
            pt = GC.randomInDisc(rng, g, g.r - 14);
            var fs = 2.4 + rng() * 2.6;
            al = 0.30 + rng() * 0.30;
            if (i >= n) continue;
            GC.snowflakePath(ctx, pt.x, pt.y, fs);
            ctx.lineWidth = 1; ctx.strokeStyle = GC.rgba(col, al); ctx.stroke();
        }
    } else if (type === 3) {
        // thunderstorm: a bolt + a few sparks
        var P = [[0.12, -0.82], [-0.16, -0.40], [0.00, -0.40], [-0.14, -0.06], [0.20, -0.52], [0.04, -0.52], [0.20, -0.82]];
        ctx.beginPath();
        for (i = 0; i < P.length; i++) {
            var bx = g.cx + P[i][0] * g.r, by = g.baseY + P[i][1] * g.r;
            if (i === 0) ctx.moveTo(bx, by); else ctx.lineTo(bx, by);
        }
        ctx.closePath();
        ctx.fillStyle = GC.rgba(col, 0.26); ctx.fill();
        ctx.lineWidth = 1.2; ctx.strokeStyle = GC.rgba(col, 0.50); ctx.stroke();
        for (i = 0; i < 6; i++) {
            pt = GC.randomInDisc(rng, g, g.r - 16);
            ctx.beginPath(); ctx.arc(pt.x, pt.y, 1.2 + rng() * 1.2, 0, 2 * GC.PI);
            ctx.fillStyle = GC.rgba(col, 0.35); ctx.fill();
        }
    } else if (type === 4) {
        // fog: stacked haze bands
        for (i = 0; i < 5; i++) {
            y = g.baseY - (g.r - 16) * (0.15 + 0.17 * i);
            ctx.beginPath();
            GC.wavePath(ctx, left, right, y, 2.2, 0.024 + 0.003 * i, i * 1.3, false);
            ctx.lineWidth = 6 + (i % 2) * 3;
            ctx.strokeStyle = GC.rgba(col, 0.10 + 0.04 * (i % 2));
            ctx.stroke();
        }
    } else if (type === 5) {
        // high temperature: sun with rays
        var sx = g.cx, sy = g.baseY - g.r * 0.50;
        var gl = ctx.createRadialGradient(sx, sy, 0, sx, sy, g.r * 0.55);
        gl.addColorStop(0, GC.rgba(col, 0.34));
        gl.addColorStop(1, GC.rgba(col, 0));
        ctx.fillStyle = gl;
        ctx.beginPath(); ctx.arc(sx, sy, g.r * 0.55, 0, 2 * GC.PI); ctx.fill();
        ctx.beginPath(); ctx.arc(sx, sy, g.r * 0.15, 0, 2 * GC.PI);
        ctx.fillStyle = GC.rgba(col, 0.40); ctx.fill();
        ctx.lineWidth = 1.6;
        for (i = 0; i < 16; i++) {
            var a = i * GC.PI / 8;
            ctx.beginPath();
            ctx.moveTo(sx + Math.cos(a) * g.r * 0.22, sy + Math.sin(a) * g.r * 0.22);
            ctx.lineTo(sx + Math.cos(a) * g.r * (i % 2 ? 0.34 : 0.42), sy + Math.sin(a) * g.r * (i % 2 ? 0.34 : 0.42));
            ctx.strokeStyle = GC.rgba(col, 0.30); ctx.stroke();
        }
    } else if (type === 7 || type === 11 || type === 12) {
        // coastal, flooding: water layers (flood level rises from the baseline)
        for (i = 0; i < 4; i++) {
            y = g.baseY - (g.r - 16) * (type === 7 ? 0.14 + 0.13 * i : 0.10 + 0.07 * i);
            ctx.beginPath();
            GC.wavePath(ctx, left, right, y, 3.5 + i, 0.030 + 0.004 * i, i * 1.4, false);
            ctx.lineTo(right, g.baseY + 4); ctx.lineTo(left, g.baseY + 4); ctx.closePath();
            ctx.fillStyle = GC.rgba(col, 0.07 + 0.015 * i); ctx.fill();
            ctx.beginPath();
            GC.wavePath(ctx, left, right, y, 3.5 + i, 0.030 + 0.004 * i, i * 1.4, false);
            ctx.lineWidth = 1.2; ctx.strokeStyle = GC.rgba(col, 0.28); ctx.stroke();
        }
    } else if (type === 8) {
        // forest fire: flames
        for (i = 0; i < 9; i++) {
            x = left + 14 + (span - 28) * (i / 8) + (rng() - 0.5) * 8;
            var fh = 6 + rng() * 8 + (i % 3 === 1 ? 6 : 0);
            _flame(ctx, x, g.baseY - 6 - fh * 1.2, fh * 0.7, col, 0.22 + rng() * 0.16);
            _flame(ctx, x, g.baseY - 4 - fh * 0.8, fh * 0.38, col, 0.20);
        }
        for (i = 0; i < 7; i++) {
            pt = GC.randomInDisc(rng, g, g.r - 16);
            ctx.beginPath(); ctx.arc(pt.x, pt.y, 0.9 + rng() * 1.1, 0, 2 * GC.PI);
            ctx.fillStyle = GC.rgba(col, 0.40); ctx.fill();
        }
    }

    if (type === 10 || type === 12) {
        // rain streaks
        ctx.lineWidth = 1.2;
        for (i = 0; i < 18; i++) {
            pt = GC.randomInDisc(rng, g, g.r - 14);
            len = 7 + rng() * 8;
            ctx.beginPath(); ctx.moveTo(pt.x, pt.y); ctx.lineTo(pt.x - len * 0.35, pt.y + len);
            ctx.strokeStyle = GC.rgba(col, 0.28 + rng() * 0.22); ctx.stroke();
        }
    }

    if (type < 1 || type > 12) {
        // unknown type: warning triangle
        var ty = g.baseY - g.r * 0.50, ts = g.r * 0.42;
        ctx.beginPath();
        ctx.moveTo(g.cx, ty - ts);
        ctx.lineTo(g.cx + ts * 0.95, ty + ts * 0.7);
        ctx.lineTo(g.cx - ts * 0.95, ty + ts * 0.7);
        ctx.closePath();
        ctx.lineWidth = 2; ctx.strokeStyle = GC.rgba(col, 0.26); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(g.cx, ty - ts * 0.35); ctx.lineTo(g.cx, ty + ts * 0.20);
        ctx.stroke();
        ctx.beginPath(); ctx.arc(g.cx, ty + ts * 0.42, 1.6, 0, 2 * GC.PI);
        ctx.fillStyle = GC.rgba(col, 0.30); ctx.fill();
    }
}

// ── "All clear" (no alerts at all): a shield with a check mark under a calm sky ──
function _sparkle(ctx, x, y, s, col, al) {
    ctx.beginPath();
    ctx.moveTo(x, y - s); ctx.quadraticCurveTo(x, y, x + s, y);
    ctx.quadraticCurveTo(x, y, x, y + s); ctx.quadraticCurveTo(x, y, x - s, y);
    ctx.quadraticCurveTo(x, y, x, y - s);
    ctx.closePath();
    ctx.fillStyle = GC.rgba(col, al);
    ctx.fill();
}

function _clearScene(ctx, g, col, text) {
    var rng = GC.makeRng(131);
    var cx = g.cx, cy = g.baseY - g.r * 0.50, s = g.r * 0.40;
    var i, pt;

    // soft rays
    ctx.lineCap = "round";
    ctx.lineWidth = 1.4;
    for (i = 0; i < 18; i++) {
        var a = GC.PI * (1.04 + 0.92 * (i / 17));
        var r0 = s * 1.35, r1 = s * (i % 2 ? 1.65 : 1.95);
        ctx.beginPath();
        ctx.moveTo(cx + Math.cos(a) * r0, g.baseY + (cy - g.baseY) + Math.sin(a) * r0 * 0.9);
        ctx.lineTo(cx + Math.cos(a) * r1, g.baseY + (cy - g.baseY) + Math.sin(a) * r1 * 0.9);
        ctx.strokeStyle = GC.rgba(col, 0.14);
        ctx.stroke();
    }
    // sparkles
    for (i = 0; i < 9; i++) {
        pt = GC.randomInDisc(rng, g, g.r - 14);
        _sparkle(ctx, pt.x, pt.y, 2.2 + rng() * 3.2, col, 0.18 + rng() * 0.26);
    }
    // shield
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(cx, cy - s);
    ctx.bezierCurveTo(cx + s * 0.35, cy - s * 0.78, cx + s * 0.72, cy - s * 0.70, cx + s * 0.92, cy - s * 0.66);
    ctx.lineTo(cx + s * 0.92, cy + s * 0.02);
    ctx.bezierCurveTo(cx + s * 0.92, cy + s * 0.55, cx + s * 0.42, cy + s * 0.92, cx, cy + s * 1.08);
    ctx.bezierCurveTo(cx - s * 0.42, cy + s * 0.92, cx - s * 0.92, cy + s * 0.55, cx - s * 0.92, cy + s * 0.02);
    ctx.lineTo(cx - s * 0.92, cy - s * 0.66);
    ctx.bezierCurveTo(cx - s * 0.72, cy - s * 0.70, cx - s * 0.35, cy - s * 0.78, cx, cy - s);
    ctx.closePath();
    ctx.fillStyle = GC.rgba(col, 0.10);
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = GC.rgba(col, 0.30);
    ctx.stroke();
    // check mark
    ctx.beginPath();
    ctx.moveTo(cx - s * 0.42, cy + s * 0.04);
    ctx.lineTo(cx - s * 0.10, cy + s * 0.38);
    ctx.lineTo(cx + s * 0.46, cy - s * 0.30);
    ctx.lineWidth = 3;
    ctx.strokeStyle = GC.rgba(col, 0.34);
    ctx.stroke();
}

function _drawClear(ctx, cw, ch, p, g) {
    GC.clipDisc(ctx, g, 6);
    var glow = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
    glow.addColorStop(0, GC.rgba(GREEN, 0.16));
    glow.addColorStop(1, GC.rgba(GREEN, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, cw, ch);
    _clearScene(ctx, g, GREEN, p.text);
    ctx.restore();

    // dial: a green "no warning" zone in front of the three warning levels, marker in it
    var lb = p.labels || [];
    GC.drawDial(ctx, g, {
        bands: [
            { from: 0, to: 0.25, color: GREEN },
            { from: 0.25, to: 0.5, color: YELLOW },
            { from: 0.5, to: 0.75, color: ORANGE },
            { from: 0.75, to: 1, color: RED }
        ],
        bandAlpha: p.isDark ? 0.30 : 0.36,
        t: 0.125,
        colorAt: function () { return GREEN; },
        ticks: [
            { t: 0.125, label: p.okLabel || "", major: false },
            { t: 0.375, label: lb[0] || "", major: false },
            { t: 0.625, label: lb[1] || "", major: false },
            { t: 0.875, label: lb[2] || "", major: false }
        ],
        text: p.text
    });
    GC.drawDot(ctx, g, 0.125, GREEN, p.isDark, 6.5);
}

/**
 * p = { color: "yellow" | "orange" | "red" | other, type: awareness type 0..12,
 *       labels: optional [yellow, orange, red] strings for the zones,
 *       clear: true = no alerts at all (shield + check mark scene, green zone;
 *              `okLabel` names that zone),
 *       isDark, text }
 */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;
    if (p.clear === true) { _drawClear(ctx, cw, ch, p, g); return; }

    var level = levelOf(p.color);
    var col = colorOf(level);
    var has = level > 0;
    var t = has ? (level - 0.5) / 3 : NaN;

    // ── Scene ────────────────────────────────────────────────────────────
    GC.clipDisc(ctx, g, 6);
    var glow = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
    glow.addColorStop(0, GC.rgba(col, has ? 0.16 : 0.05));
    glow.addColorStop(1, GC.rgba(col, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, cw, ch);
    _scene(ctx, g, p.type || 0, col, p.text);
    ctx.restore();

    // ── Dial: three warning levels ───────────────────────────────────────
    var lb = p.labels || [];
    var ticks = [
        { t: 1 / 6, label: lb[0] || "", major: false },
        { t: 1 / 3, label: "", major: true },
        { t: 0.5, label: lb[1] || "", major: false },
        { t: 2 / 3, label: "", major: true },
        { t: 5 / 6, label: lb[2] || "", major: false }
    ];
    GC.drawDial(ctx, g, {
        bands: [
            { from: 0, to: 1 / 3, color: YELLOW },
            { from: 1 / 3, to: 2 / 3, color: ORANGE },
            { from: 2 / 3, to: 1, color: RED }
        ],
        bandAlpha: p.isDark ? 0.34 : 0.42,
        t: t,
        colorAt: function (tt) { return GC.colorScale([[0, YELLOW], [0.5, ORANGE], [1, RED]], tt); },
        ticks: ticks,
        text: p.text
    });
    if (has) GC.drawDot(ctx, g, t, col, p.isDark, 6.5);
}
