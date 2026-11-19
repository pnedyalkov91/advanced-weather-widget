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
 * visibilityGauge.js - Canvas drawing for the expandable Visibility card.
 *
 * 0-30 km dial on a square-root scale (so the interesting low end gets room):
 * fog / poor / moderate / good / excellent. Inside the dial a range of hills
 * fades into a haze veil that thickens as visibility drops.
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "gaugeAnim.js" as GA

var MAXKM = 30;

function _t(km) { return Math.sqrt(GC.clamp01(km / MAXKM)); }

function _pal(isDark) {
    return isDark
        ? { fog: "#ff6b8b", poor: "#ffb347", mod: "#e8d44d", good: "#4ed8a0", exc: "#4dd0e1" }
        : { fog: "#c0304f", poor: "#b86000", mod: "#8a7500", good: "#0f8a5f", exc: "#007f94" };
}

function colorAt(km, isDark) {
    var p = _pal(isDark);
    return GC.colorScale([[0, p.fog], [1, p.fog], [2.5, p.poor], [4, p.poor], [7, p.mod],
                          [10, p.mod], [15, p.good], [20, p.good], [30, p.exc]], km);
}

function bandKey(km) {
    if (!GC.isNum(km)) return "";
    if (km < 1) return "fog";
    if (km < 4) return "poor";
    if (km < 10) return "moderate";
    if (km < 20) return "good";
    return "excellent";
}

function info(km, isDark) {
    return { key: bandKey(km), color: GC.isNum(km) ? colorAt(km, isDark) : _pal(isDark).good };
}

function _ridge(ctx, g, baseFrac, amp, k, ph, fill) {
    var yb = g.baseY - g.r * baseFrac;
    ctx.beginPath();
    ctx.moveTo(g.cx - g.r, g.baseY + 2);
    GC.wavePath(ctx, g.cx - g.r, g.cx + g.r, yb, amp, k, ph, true);
    ctx.lineTo(g.cx + g.r, g.baseY + 2);
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
}

/** p = { v: visibility km, isDark, text, imperial } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var pal = _pal(p.isDark);
    var has = GC.isNum(p.v);
    var t = has ? _t(p.v) : 0;
    var cur = has ? colorAt(p.v, p.isDark) : pal.good;
    // 0 = crystal clear, 1 = thick fog
    var haze = has ? GC.clamp01(1 - Math.sqrt(GC.clamp01(p.v / 12))) : 0.2;

    // ── Scene: hills fading into haze ────────────────────────────────────
    if (GA.scene()) {
        GC.clipDisc(ctx, g, 6);
        var hillCol = p.isDark ? "#9fb6d4" : "#4a6283";
        var fade = 1 - 0.75 * haze;
        _ridge(ctx, g, 0.52, 7, 0.030, 0.4, GC.rgba(hillCol, 0.07 * fade));
        _ridge(ctx, g, 0.36, 9, 0.024, 2.1, GC.rgba(hillCol, 0.11 * fade));
        _ridge(ctx, g, 0.20, 8, 0.036, 4.3, GC.rgba(hillCol, 0.17 * fade));

        var veilCol = p.isDark ? "#c9d3e0" : "#8896aa";
        var veil = ctx.createLinearGradient(0, g.baseY - g.r, 0, g.baseY);
        var hz = GC.clamp01(haze + (GA.pulse(7) - 0.5) * 0.14);   // the haze slowly breathes
        veil.addColorStop(0, GC.rgba(veilCol, 0.04 + 0.10 * hz));
        veil.addColorStop(1, GC.rgba(veilCol, 0.08 + 0.34 * hz));
        ctx.fillStyle = veil;
        ctx.fillRect(0, 0, cw, ch);
        ctx.restore();
    }

    if (GA.dial()) {
        // ── Dial ─────────────────────────────────────────────────────────────
        var kmTicks = [1, 5, 10, 20];
        var ticks = [{ t: 0, label: "0" }];
        for (var i = 0; i < kmTicks.length; i++)
            ticks.push({ t: _t(kmTicks[i]), label: GC.fmt(GC.kmToDisp(kmTicks[i], p.imperial), 0) });
        ticks.push({ t: 1, label: GC.fmt(GC.kmToDisp(MAXKM, p.imperial), 0) });

        GC.drawDial(ctx, g, {
            bands: [
                { from: 0, to: _t(1), color: pal.fog },
                { from: _t(1), to: _t(4), color: pal.poor },
                { from: _t(4), to: _t(10), color: pal.mod },
                { from: _t(10), to: _t(20), color: pal.good },
                { from: _t(20), to: 1, color: pal.exc }
            ],
            t: has ? t : NaN,
            colorAt: function (tt) { return colorAt(tt * tt * MAXKM, p.isDark); },
            ticks: ticks,
            text: p.text
        });

        if (has)
            GC.drawDot(ctx, g, t, cur, p.isDark, 6);
    }
}
