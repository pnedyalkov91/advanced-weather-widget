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
 * pollenGauge.js - Canvas drawing for one pollen type page of the expandable
 * Pollen card.
 *
 * Like aqiGauge.js, the scale comes from pollen.js through DetailsView: the
 * position of the reading, the colour zones and the tick positions arrive in
 * the parameters. The scene is a cloud of pollen grains over a bit of
 * vegetation that fits the type - grass blades, tree leaves or weed spikes.
 */
.pragma library
.import "gaugeCommon.js" as GC

var TREES = ["alder", "birch", "olive", "hazel", "oak", "cypress", "plane", "pine", "poplar", "elm"];

/** "grass" | "tree" | "weed" */
function kindOf(key) {
    if (key === "grass") return "grass";
    for (var i = 0; i < TREES.length; i++)
        if (TREES[i] === key) return "tree";
    return "weed";
}

function _zoneColor(zones, tt, fallback) {
    if (!zones || zones.length === 0) return fallback;
    for (var i = 0; i < zones.length; i++)
        if (tt <= zones[i].to) return zones[i].color;
    return zones[zones.length - 1].color;
}

function _grain(ctx, x, y, r, col, al) {
    ctx.fillStyle = GC.rgba(col, al);
    ctx.beginPath(); ctx.arc(x, y, r, 0, 2 * GC.PI); ctx.fill();
    // spikes of the grain
    ctx.fillStyle = GC.rgba(col, al * 0.8);
    for (var i = 0; i < 6; i++) {
        var a = i * GC.PI / 3 + 0.4;
        ctx.beginPath();
        ctx.arc(x + Math.cos(a) * (r + 1.8), y + Math.sin(a) * (r + 1.8), 0.9, 0, 2 * GC.PI);
        ctx.fill();
    }
}

function _leaf(ctx, x, y, s, rot, col, al) {
    var c = Math.cos(rot), d = Math.sin(rot);
    function pt(u, v) { return [x + u * c - v * d, y + u * d + v * c]; }
    var a = pt(-s, 0), b = pt(s, 0), c1 = pt(0, -s * 0.7), c2 = pt(0, s * 0.7);
    ctx.beginPath();
    ctx.moveTo(a[0], a[1]);
    ctx.quadraticCurveTo(c1[0], c1[1], b[0], b[1]);
    ctx.quadraticCurveTo(c2[0], c2[1], a[0], a[1]);
    ctx.closePath();
    ctx.fillStyle = GC.rgba(col, al);
    ctx.fill();
}

/**
 * p = { t: 0..1 position of the reading (NaN = no data), bandColor,
 *       zones: [{from, to, color}] (0..1), key: "grass" | "birch" | ...,
 *       ticks: [{t, label}], isDark, text }
 */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var has = GC.isNum(p.t);
    var t = has ? GC.clamp01(p.t) : 0;
    var col = (has && p.bandColor) ? p.bandColor : "#8BC34A";
    var kind = kindOf(p.key);
    var rng = GC.makeRng(kind === "grass" ? 61 : (kind === "tree" ? 67 : 71));
    var dens = has ? 0.12 + 0.88 * t : 0;

    // ── Scene ────────────────────────────────────────────────────────────
    GC.clipDisc(ctx, g, 6);
    var glow = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
    glow.addColorStop(0, GC.rgba(col, has ? 0.16 : 0.04));
    glow.addColorStop(1, GC.rgba(col, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, cw, ch);

    var i, pt, k;
    // vegetation along the baseline
    var base = g.baseY;
    var left = g.cx - g.r, span = 2 * g.r;
    ctx.lineCap = "round";
    if (kind === "grass") {
        ctx.lineWidth = 1.4;
        for (i = 0; i < 34; i++) {
            var bx = left + 6 + (span - 12) * (i / 33) + (rng() - 0.5) * 4;
            var bh = 7 + rng() * 11 + 10 * dens;
            var sw = (rng() - 0.5) * 10;
            ctx.beginPath(); ctx.moveTo(bx, base + 2);
            ctx.quadraticCurveTo(bx + sw * 0.3, base - bh * 0.5, bx + sw, base - bh);
            ctx.strokeStyle = GC.rgba(col, 0.20 + rng() * 0.18); ctx.stroke();
        }
    } else if (kind === "tree") {
        for (i = 0; i < 16; i++) {
            pt = { x: left + 10 + (span - 20) * rng(), y: base - 3 - rng() * (10 + 14 * dens) };
            _leaf(ctx, pt.x, pt.y, 4 + rng() * 3, (rng() - 0.5) * 2.4, col, 0.16 + rng() * 0.16);
        }
    } else {
        ctx.lineWidth = 1.2;
        for (i = 0; i < 12; i++) {
            var wx = left + 12 + (span - 24) * rng();
            var wh = 8 + rng() * 10 + 8 * dens;
            ctx.beginPath(); ctx.moveTo(wx, base + 2); ctx.lineTo(wx, base - wh);
            ctx.strokeStyle = GC.rgba(col, 0.20 + rng() * 0.14); ctx.stroke();
            for (k = 0; k < 3; k++) {
                var sy = base - wh * (0.45 + 0.25 * k);
                ctx.beginPath();
                ctx.moveTo(wx, sy); ctx.lineTo(wx - 3, sy - 3);
                ctx.moveTo(wx, sy); ctx.lineTo(wx + 3, sy - 3);
                ctx.stroke();
            }
        }
    }
    // pollen cloud
    var n = Math.round(3 + 15 * dens);
    for (i = 0; i < 18; i++) {
        pt = GC.randomInDisc(rng, g, g.r - 16);
        var gr = 1.6 + rng() * 1.8;
        var al = 0.30 + rng() * 0.28;
        if (i >= n) continue;
        // keep grains above the vegetation
        if (pt.y > base - 20) pt.y = base - 20 - rng() * 20;
        _grain(ctx, pt.x, pt.y, gr, col, al);
    }
    ctx.restore();

    // ── Dial ─────────────────────────────────────────────────────────────
    var bands = [];
    if (p.zones && p.zones.length > 0) {
        for (i = 0; i < p.zones.length; i++)
            bands.push({ from: p.zones[i].from, to: p.zones[i].to, color: p.zones[i].color });
    }
    GC.drawDial(ctx, g, {
        bands: bands,
        bandAlpha: p.isDark ? 0.34 : 0.42,
        t: has ? t : NaN,
        colorAt: function (tt) { return _zoneColor(p.zones, tt, col); },
        ticks: p.ticks || [],
        text: p.text
    });
    if (has) GC.drawDot(ctx, g, t, col, p.isDark, 6.5);
}
