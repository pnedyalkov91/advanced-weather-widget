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
 * dewPointGauge.js - Canvas drawing for the expandable Dew Point card.
 *
 * -10..26 degC dial in comfort zones (dry / comfortable / humid / oppressive).
 * The dew point is the filled dot, the real air temperature a hollow ring;
 * the bracket between them is the "spread". The smaller the spread, the more
 * the mist layers in the dial thicken (saturated air = fog / dew).
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "gaugeAnim.js" as GA

var MIN = -10;
var MAX = 26;

function _t(v) { return GC.clamp01((v - MIN) / (MAX - MIN)); }

function _pal(isDark) {
    return isDark
        ? { dry: "#5ea8ff", comfy: "#4ed8a0", humid: "#ffb347", opp: "#ff6b5a" }
        : { dry: "#1a6fcc", comfy: "#0f8a5f", humid: "#b86000", opp: "#c0301f" };
}

function colorAt(v, isDark) {
    var p = _pal(isDark);
    return GC.colorScale([[-10, p.dry], [8, p.dry], [12, p.comfy], [15, p.comfy],
                          [18, p.humid], [20, p.humid], [23, p.opp], [26, p.opp]], v);
}

function bandKey(v) {
    if (!GC.isNum(v)) return "";
    if (v < 10) return "dry";
    if (v < 16) return "comfortable";
    if (v < 21) return "humid";
    return "oppressive";
}

function info(v, isDark) {
    return { key: bandKey(v), color: GC.isNum(v) ? colorAt(v, isDark) : _pal(isDark).comfy };
}

/** p = { v: dew point degC, v2: air temperature degC, isDark, text, imperial, tempUnit } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var pal = _pal(p.isDark);
    var has = GC.isNum(p.v);
    var hasAir = GC.isNum(p.v2);
    var t = has ? _t(p.v) : 0;
    var cur = has ? colorAt(p.v, p.isDark) : pal.comfy;

    // How close the air is to saturation (0 = far from it, 1 = at the dew point)
    var sat = (has && hasAir) ? GC.clamp01(1 - (p.v2 - p.v) / 8) : 0;

    // ── Scene: layers of mist, thicker as the spread shrinks ─────────────
    if (GA.scene()) {
        GC.clipDisc(ctx, g, 6);
        var haze = ctx.createLinearGradient(0, g.baseY - g.r, 0, g.baseY);
        haze.addColorStop(0, GC.rgba(cur, 0));
        haze.addColorStop(1, GC.rgba(cur, 0.06 + 0.20 * sat));
        ctx.fillStyle = haze;
        ctx.fillRect(0, 0, cw, ch);

        var mistCol = p.isDark ? "#dfe9f5" : "#6b7f99";
        for (var i = 0; i < 5; i++) {
            var y = g.baseY - 12 - i * (g.r - 30) / 5;
            ctx.beginPath();
            GC.wavePath(ctx, g.cx - g.r, g.cx + g.r, y, 2.6, 0.045 + i * 0.011, i * 1.7 + GA.T() * (0.6 + 0.15 * i), false);
            ctx.lineWidth = 3 + (i % 2);
            ctx.lineCap = "round";
            ctx.strokeStyle = GC.rgba(mistCol, (0.05 + 0.15 * sat) * (1 - i * 0.14));
            ctx.stroke();
        }
        ctx.restore();
    }

    if (GA.dial()) {
        // ── Dial ─────────────────────────────────────────────────────────────
        var ticks = [];
        var vals = [-10, 0, 10, 20, 26];
        for (var k = 0; k < vals.length; k++)
            ticks.push({ t: _t(vals[k]), label: GC.fmt(GC.cToDisp(vals[k], p.tempUnit), 0) });
        ticks[0].t = 0;
        ticks[4].t = 1;

        GC.drawDial(ctx, g, {
            bands: [
                { from: 0, to: _t(10), color: pal.dry },
                { from: _t(10), to: _t(16), color: pal.comfy },
                { from: _t(16), to: _t(21), color: pal.humid },
                { from: _t(21), to: 1, color: pal.opp }
            ],
            t: has ? t : NaN,
            colorAt: function (tt) { return colorAt(MIN + tt * (MAX - MIN), p.isDark); },
            ticks: ticks,
            text: p.text
        });

        // ── Spread bracket + markers ─────────────────────────────────────────
        if (has && hasAir) {
            var tAir = _t(p.v2);
            GC.drawBracket(ctx, g, t, tAir, cur, 0.65);
            GC.drawRing(ctx, g, tAir, p.text, p.isDark, 5);
        }
        if (has)
            GC.drawDot(ctx, g, t, cur, p.isDark, 6.5);
    }
}
