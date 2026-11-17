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
 * humidityGauge.js - Canvas drawing for the expandable Humidity card.
 *
 * 0-100 % dial split into comfort zones (dry / comfortable / humid / very
 * humid), a teardrop marker at the current reading and a cloud of faint
 * vapour droplets inside the dial that gets denser as the air gets wetter.
 */
.pragma library
.import "gaugeCommon.js" as GC

function _pal(isDark) {
    return isDark
        ? { dry: "#ffb347", comfy: "#4ed8a0", humid: "#5ea8ff", very: "#8b7bff" }
        : { dry: "#b86000", comfy: "#0f8a5f", humid: "#1a6fcc", very: "#5a45d6" };
}

function colorAt(v, isDark) {
    var p = _pal(isDark);
    return GC.colorScale([[0, p.dry], [22, p.dry], [38, p.comfy], [55, p.comfy],
                          [68, p.humid], [82, p.very], [100, p.very]], v);
}

function bandKey(v) {
    if (!GC.isNum(v)) return "";
    if (v < 30) return "dry";
    if (v < 60) return "comfortable";
    if (v < 75) return "humid";
    return "veryhumid";
}

/** { key, color } - key is translated by DetailsView. */
function info(v, isDark) {
    return { key: bandKey(v), color: GC.isNum(v) ? colorAt(v, isDark) : _pal(isDark).comfy };
}

/** p = { v, v2, isDark, text, imperial, tempUnit } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var pal = _pal(p.isDark);
    var has = GC.isNum(p.v);
    var t = has ? GC.clamp01(p.v / 100) : 0;
    var cur = has ? colorAt(p.v, p.isDark) : pal.comfy;

    // ── Scene: soft tint + vapour droplets ───────────────────────────────
    GC.clipDisc(ctx, g, 6);
    var tint = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
    tint.addColorStop(0, GC.rgba(cur, has ? 0.14 : 0.05));
    tint.addColorStop(1, GC.rgba(cur, 0));
    ctx.fillStyle = tint;
    ctx.fillRect(0, 0, cw, ch);

    var rng = GC.makeRng(11);
    var n = has ? Math.round(5 + 27 * t) : 0;
    for (var i = 0; i < 32; i++) {
        // always consume the same random numbers so droplets stay put as the value changes
        var pos = GC.randomInDisc(rng, g, g.r - 20);
        var size = 2 + rng() * 3.4;
        var alpha = 0.10 + rng() * 0.16;
        if (i >= n) continue;
        ctx.fillStyle = GC.rgba(cur, alpha);
        GC.dropletPath(ctx, pos.x, pos.y, size);
        ctx.fill();
    }
    ctx.restore();

    // ── Dial ─────────────────────────────────────────────────────────────
    GC.drawDial(ctx, g, {
        bands: [
            { from: 0.00, to: 0.30, color: pal.dry },
            { from: 0.30, to: 0.60, color: pal.comfy },
            { from: 0.60, to: 0.75, color: pal.humid },
            { from: 0.75, to: 1.00, color: pal.very }
        ],
        t: has ? t : NaN,
        colorAt: function (tt) { return colorAt(tt * 100, p.isDark); },
        ticks: [
            { t: 0.00, label: "0" },
            { t: 0.30, label: "30" },
            { t: 0.60, label: "60" },
            { t: 0.75 },
            { t: 1.00, label: "100" }
        ],
        text: p.text
    });

    // ── Teardrop marker ──────────────────────────────────────────────────
    if (has) {
        var m = GC.pointAt(g, t, g.r);
        GC.dropletPath(ctx, m.x, m.y - 1, 7.5);
        ctx.fillStyle = cur;
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        ctx.strokeStyle = p.isDark ? "rgba(20,20,20,0.85)" : "rgba(255,255,255,0.95)";
        ctx.stroke();
        // small highlight
        ctx.beginPath();
        ctx.arc(m.x - 2.2, m.y + 0.4, 1.6, 0, 2 * GC.PI);
        ctx.fillStyle = "rgba(255,255,255,0.55)";
        ctx.fill();
    }
}
