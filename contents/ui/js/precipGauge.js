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
 * precipGauge.js - Canvas drawing for the expandable Precipitation (rate) card.
 *
 * 0-50 mm/h dial on a square-root scale: light / moderate / heavy / extreme.
 * Slanted rain streaks fill the dial, more and thicker as the rate climbs;
 * with no precipitation the sky stays clear.
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "gaugeAnim.js" as GA

var MAXMM = 50;

function _t(mm) { return Math.sqrt(GC.clamp01(mm / MAXMM)); }

function _pal(isDark) {
    return isDark
        ? { light: "#6bb8ff", mod: "#5a86ff", heavy: "#a37bff", ext: "#ff5cc8" }
        : { light: "#1a6fcc", mod: "#2f4fd0", heavy: "#6a3fd0", ext: "#b0208c" };
}

function colorAt(mm, isDark) {
    var p = _pal(isDark);
    return GC.colorScale([[0, p.light], [2.5, p.light], [5, p.mod], [7.6, p.mod],
                          [15, p.heavy], [25, p.heavy], [40, p.ext], [50, p.ext]], mm);
}

function bandKey(mm) {
    if (!GC.isNum(mm)) return "";
    if (mm < 0.05) return "none";
    if (mm < 2.5) return "light";
    if (mm < 7.6) return "moderate";
    if (mm < 25) return "heavy";
    return "extreme";
}

function info(mm, isDark) {
    return { key: bandKey(mm), color: GC.isNum(mm) ? colorAt(mm, isDark) : _pal(isDark).light };
}

/** p = { v: mm/h, isDark, text, imperial } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var pal = _pal(p.isDark);
    var has = GC.isNum(p.v);
    var t = has ? _t(p.v) : 0;
    var wet = has && p.v >= 0.05;
    var cur = has ? colorAt(p.v, p.isDark) : pal.light;

    // ── Scene: rain streaks ──────────────────────────────────────────────
    if (GA.scene()) {
        GC.clipDisc(ctx, g, 6);
        if (wet) {
            var tint = ctx.createLinearGradient(0, g.baseY - g.r, 0, g.baseY);
            tint.addColorStop(0, GC.rgba(cur, 0.10 + 0.10 * t));
            tint.addColorStop(1, GC.rgba(cur, 0.02));
            ctx.fillStyle = tint;
            ctx.fillRect(0, 0, cw, ch);
        }
        var rng = GC.makeRng(23);
        var n = wet ? Math.round(5 + 36 * t) : 0;
        ctx.lineCap = "round";
        for (var i = 0; i < 44; i++) {
            var pos = GC.randomInDisc(rng, g, g.r - 8);
            var len = 6 + rng() * 6 + 5 * t;
            var alpha = 0.16 + rng() * 0.20;
            if (i >= n) continue;
            // rain falls; each streak wraps back to the top of the dial
            var fallTop = g.baseY - (g.r - 8), fallSpan = g.r - 8;
            pos.y = fallTop + GA.wrap(pos.y - fallTop + GA.T() * (50 + 40 * t) * (0.7 + (i % 4) * 0.2), fallSpan);
            ctx.beginPath();
            ctx.moveTo(pos.x, pos.y);
            ctx.lineTo(pos.x - len * 0.28, pos.y + len);
            ctx.lineWidth = 1.1 + 1.2 * t;
            ctx.strokeStyle = GC.rgba(cur, alpha);
            ctx.stroke();
        }
        ctx.restore();
    }

    if (GA.dial()) {
        // ── Dial ─────────────────────────────────────────────────────────────
        var mmTicks = [1, 5, 10, 25];
        var ticks = [{ t: 0, label: "0" }];
        for (var k = 0; k < mmTicks.length; k++)
            ticks.push({ t: _t(mmTicks[k]), label: GC.fmt(GC.mmToDisp(mmTicks[k], p.imperial), p.imperial ? 2 : 0) });
        ticks.push({ t: 1, label: GC.fmt(GC.mmToDisp(MAXMM, p.imperial), p.imperial ? 1 : 0) });

        GC.drawDial(ctx, g, {
            bands: [
                { from: 0, to: _t(2.5), color: pal.light },
                { from: _t(2.5), to: _t(7.6), color: pal.mod },
                { from: _t(7.6), to: _t(25), color: pal.heavy },
                { from: _t(25), to: 1, color: pal.ext }
            ],
            t: wet ? t : NaN,
            colorAt: function (tt) { return colorAt(tt * tt * MAXMM, p.isDark); },
            ticks: ticks,
            text: p.text
        });

        if (has) {
            // a dry reading still gets a marker, parked at the start of the dial
            GC.drawDot(ctx, g, wet ? t : 0, cur, p.isDark, 6);
        }
    }
}
