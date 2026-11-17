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
 * precipSumGauge.js - Canvas drawing for the expandable Precipitation Sum card.
 *
 * 0-50 mm dial on a square-root scale. The dial doubles as a rain gauge:
 * the half-disc inside it fills with rippling water up to a level that
 * follows the accumulated amount.
 */
.pragma library
.import "gaugeCommon.js" as GC

var MAXMM = 50;

function _t(mm) { return Math.sqrt(GC.clamp01(mm / MAXMM)); }

function _pal(isDark) {
    return isDark
        ? { light: "#5ec8e8", mod: "#4a9dff", heavy: "#7a78ff", ext: "#c070ff" }
        : { light: "#007f94", mod: "#1a6fcc", heavy: "#4a45d0", ext: "#8a30b8" };
}

function colorAt(mm, isDark) {
    var p = _pal(isDark);
    return GC.colorScale([[0, p.light], [5, p.light], [10, p.mod], [15, p.mod],
                          [25, p.heavy], [30, p.heavy], [42, p.ext], [50, p.ext]], mm);
}

function bandKey(mm) {
    if (!GC.isNum(mm)) return "";
    if (mm < 0.1) return "none";
    if (mm < 5) return "light";
    if (mm < 15) return "moderate";
    if (mm < 30) return "heavy";
    return "extreme";
}

function info(mm, isDark) {
    return { key: bandKey(mm), color: GC.isNum(mm) ? colorAt(mm, isDark) : _pal(isDark).light };
}

/** p = { v: mm, isDark, text, imperial } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var pal = _pal(p.isDark);
    var has = GC.isNum(p.v);
    var t = has ? _t(p.v) : 0;
    var any = has && p.v >= 0.1;
    var cur = has ? colorAt(p.v, p.isDark) : pal.light;

    // ── Scene: water filling the dial ────────────────────────────────────
    if (any) {
        GC.clipDisc(ctx, g, 5);
        var level = g.baseY - (g.r - 10) * t;
        var x0 = g.cx - g.r, x1 = g.cx + g.r;

        // back wave
        ctx.beginPath();
        GC.wavePath(ctx, x0, x1, level - 2, 2.4, 0.050, 1.9, false);
        ctx.lineTo(x1, g.baseY + 4);
        ctx.lineTo(x0, g.baseY + 4);
        ctx.closePath();
        ctx.fillStyle = GC.rgba(cur, 0.14);
        ctx.fill();

        // front wave
        var grad = ctx.createLinearGradient(0, level - 4, 0, g.baseY);
        grad.addColorStop(0, GC.rgba(cur, 0.40));
        grad.addColorStop(1, GC.rgba(cur, 0.12));
        ctx.beginPath();
        GC.wavePath(ctx, x0, x1, level, 2.6, 0.062, 0.3, false);
        ctx.lineTo(x1, g.baseY + 4);
        ctx.lineTo(x0, g.baseY + 4);
        ctx.closePath();
        ctx.fillStyle = grad;
        ctx.fill();

        // surface highlight
        ctx.beginPath();
        GC.wavePath(ctx, x0, x1, level, 2.6, 0.062, 0.3, false);
        ctx.lineWidth = 1.4;
        ctx.lineJoin = "round";
        ctx.strokeStyle = GC.rgba(cur, 0.65);
        ctx.stroke();

        // a few rising bubbles
        var rng = GC.makeRng(5);
        for (var i = 0; i < 9; i++) {
            var bx = x0 + rng() * (x1 - x0);
            var by = level + 6 + rng() * Math.max(1, g.baseY - level - 8);
            var br = 1 + rng() * 2;
            if (by > g.baseY - 3) continue;
            ctx.beginPath();
            ctx.arc(bx, by, br, 0, 2 * GC.PI);
            ctx.lineWidth = 1;
            ctx.strokeStyle = GC.rgba(cur, 0.45);
            ctx.stroke();
        }
        ctx.restore();
    }

    // ── Dial ─────────────────────────────────────────────────────────────
    var mmTicks = [1, 5, 15, 30];
    var ticks = [{ t: 0, label: "0" }];
    for (var k = 0; k < mmTicks.length; k++)
        ticks.push({ t: _t(mmTicks[k]), label: GC.fmt(GC.mmToDisp(mmTicks[k], p.imperial), p.imperial ? 2 : 0) });
    ticks.push({ t: 1, label: GC.fmt(GC.mmToDisp(MAXMM, p.imperial), p.imperial ? 1 : 0) });

    GC.drawDial(ctx, g, {
        bands: [
            { from: 0, to: _t(5), color: pal.light },
            { from: _t(5), to: _t(15), color: pal.mod },
            { from: _t(15), to: _t(30), color: pal.heavy },
            { from: _t(30), to: 1, color: pal.ext }
        ],
        t: any ? t : NaN,
        colorAt: function (tt) { return colorAt(tt * tt * MAXMM, p.isDark); },
        ticks: ticks,
        text: p.text
    });

    if (has)
        GC.drawDot(ctx, g, any ? t : 0, cur, p.isDark, 6);
}
