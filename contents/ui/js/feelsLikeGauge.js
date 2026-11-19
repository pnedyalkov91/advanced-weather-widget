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
 * feelsLikeGauge.js - Canvas drawing for the expandable Feels Like card.
 *
 * -25..45 degC thermometer dial with a full cold-to-hot colour sweep. The
 * "feels like" temperature is the filled dot, the real air temperature a
 * hollow ring; the bracket between them shows how much wind chill / humidity
 * shifts the perceived value. Concentric rings and a temperature-coloured
 * glow give it a radar-dial look; the freezing point is marked on the scale.
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "gaugeAnim.js" as GA

var MIN = -25;
var MAX = 45;

function _t(c) { return GC.clamp01((c - MIN) / (MAX - MIN)); }

function _stops(isDark) {
    return isDark
        ? [[-25, "#8f7bff"], [-12, "#5ea8ff"], [0, "#5ed0f0"], [10, "#4ed8a0"],
           [20, "#b8e05a"], [27, "#ffd04d"], [34, "#ff9a3c"], [45, "#ff4d3d"]]
        : [[-25, "#5a45d6"], [-12, "#1a6fcc"], [0, "#0b87a8"], [10, "#0f8a5f"],
           [20, "#6b8e00"], [27, "#a88400"], [34, "#c05a00"], [45, "#b82618"]];
}

function colorAt(c, isDark) {
    return GC.colorScale(_stops(isDark), c);
}

function bandKey(c) {
    if (!GC.isNum(c)) return "";
    if (c < 0) return "freezing";
    if (c < 10) return "cold";
    if (c < 18) return "cool";
    if (c < 26) return "comfortable";
    if (c < 32) return "warm";
    if (c < 40) return "hot";
    return "extremeheat";
}

function info(c, isDark) {
    return { key: bandKey(c), color: GC.isNum(c) ? colorAt(c, isDark) : colorAt(15, isDark) };
}

/** p = { v: feels-like degC, v2: air temperature degC, isDark, text, tempUnit } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var has = GC.isNum(p.v);
    var hasAir = GC.isNum(p.v2);
    var t = has ? _t(p.v) : 0;
    var cur = has ? colorAt(p.v, p.isDark) : colorAt(15, p.isDark);

    // ── Scene: temperature glow + concentric rings ───────────────────────
    if (GA.scene()) {
        GC.clipDisc(ctx, g, 6);
        var glow = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
        glow.addColorStop(0, GC.rgba(cur, has ? 0.14 + 0.12 * GA.pulse(4) : 0.05));   // pulsing glow
        glow.addColorStop(0.7, GC.rgba(cur, has ? 0.06 : 0.02));
        glow.addColorStop(1, GC.rgba(cur, 0));
        ctx.fillStyle = glow;
        ctx.fillRect(0, 0, cw, ch);

        ctx.lineWidth = 1;
        for (var i = 1; i <= 3; i++) {
            var rr = g.r - 18 - i * 22;
            if (rr < 10) break;
            ctx.beginPath();
            ctx.arc(g.cx, g.baseY, rr, GC.PI, 2 * GC.PI, false);
            ctx.strokeStyle = GC.rgba(p.text, 0.07);
            ctx.stroke();
        }
        ctx.restore();
    }

    if (GA.dial()) {
        // ── Dial ─────────────────────────────────────────────────────────────
        var vals = [-20, -10, 0, 10, 20, 30, 40];
        var ticks = [];
        for (var k = 0; k < vals.length; k++)
            ticks.push({ t: _t(vals[k]), label: GC.fmt(GC.cToDisp(vals[k], p.tempUnit), 0), major: vals[k] === 0 });

        // the scale is one continuous cold-to-hot sweep (dimmed), the progress arc brightens it up to the reading
        GC.drawDial(ctx, g, {
            ghostAt: function (tt) { return colorAt(MIN + tt * (MAX - MIN), p.isDark); },
            bandAlpha: 0.32,
            t: has ? t : NaN,
            colorAt: function (tt) { return colorAt(MIN + tt * (MAX - MIN), p.isDark); },
            ticks: ticks,
            text: p.text
        });

        // ── Real vs. perceived ───────────────────────────────────────────────
        if (has && hasAir) {
            var tAir = _t(p.v2);
            GC.drawBracket(ctx, g, t, tAir, cur, 0.65);
            GC.drawRing(ctx, g, tAir, p.text, p.isDark, 5);
        }
        if (has)
            GC.drawDot(ctx, g, t, cur, p.isDark, 6.5);
    }
}
