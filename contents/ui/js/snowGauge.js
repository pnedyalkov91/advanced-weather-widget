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
 * snowGauge.js - Canvas drawing for the expandable Snow Cover card.
 *
 * 0-100 cm dial on a square-root scale (light / moderate / deep / very deep).
 * Snow crystals drift above a rolling drift of snow whose height follows the
 * depth; with no snow on the ground the dial stays bare.
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "gaugeAnim.js" as GA

var MAXCM = 100;

function _t(cm) { return Math.sqrt(GC.clamp01(cm / MAXCM)); }

function _pal(isDark) {
    return isDark
        ? { light: "#a5e1ff", mod: "#6cc0ff", deep: "#8b9bff", very: "#c39bff" }
        : { light: "#2a86b8", mod: "#1a6fcc", deep: "#4a55c8", very: "#7a3fc0" };
}

function colorAt(cm, isDark) {
    var p = _pal(isDark);
    return GC.colorScale([[0, p.light], [5, p.light], [12, p.mod], [20, p.mod],
                          [35, p.deep], [50, p.deep], [75, p.very], [100, p.very]], cm);
}

function bandKey(cm) {
    if (!GC.isNum(cm)) return "";
    if (cm < 0.1) return "none";
    if (cm < 5) return "light";
    if (cm < 20) return "moderate";
    if (cm < 50) return "deep";
    return "verydeep";
}

function info(cm, isDark) {
    return { key: bandKey(cm), color: GC.isNum(cm) ? colorAt(cm, isDark) : _pal(isDark).light };
}

/** p = { v: snow depth cm, isDark, text, imperial } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var pal = _pal(p.isDark);
    var has = GC.isNum(p.v);
    var any = has && p.v >= 0.1;
    var t = has ? _t(p.v) : 0;
    var cur = has ? colorAt(p.v, p.isDark) : pal.light;
    var snowCol = p.isDark ? "#ffffff" : "#5a8fc8";

    // ── Scene: drifting flakes + snow on the ground ──────────────────────
    if (GA.scene()) {
        GC.clipDisc(ctx, g, 6);
        var groundTop = g.baseY - (g.r - 12) * (any ? 0.04 + 0.28 * t : 0);

        var rng = GC.makeRng(31);
        var n = any ? Math.round(5 + 19 * t) : 0;
        var top = g.baseY - (g.r - 14);
        ctx.lineCap = "round";
        for (var i = 0; i < 24; i++) {
            var fx = g.cx - g.r + rng() * 2 * g.r + GA.osc(1.1, i, 4);
            var fh = Math.max(6, groundTop - 8 - top);
            var fy = top + GA.wrap(rng() * fh + GA.T() * (12 + (i % 5) * 4), fh);   // flakes fall
            var fs = 2.2 + rng() * 2.6;
            var fa = 0.35 + rng() * 0.30;
            if (i >= n) continue;
            // keep flakes inside the dial
            var dx = fx - g.cx, dy = fy - g.baseY;
            if (dx * dx + dy * dy > (g.r - 14) * (g.r - 14)) continue;
            snowflakePath(ctx, fx, fy, fs);
            ctx.lineWidth = 1;
            ctx.strokeStyle = GC.rgba(snowCol, fa);
            ctx.stroke();
        }

        if (any) {
            var x0 = g.cx - g.r, x1 = g.cx + g.r;
            var grad = ctx.createLinearGradient(0, groundTop - 6, 0, g.baseY);
            grad.addColorStop(0, p.isDark ? "rgba(255,255,255,0.30)" : "rgba(90,143,200,0.40)");
            grad.addColorStop(1, p.isDark ? "rgba(255,255,255,0.08)" : "rgba(90,143,200,0.12)");
            ctx.beginPath();
            GC.wavePath(ctx, x0, x1, groundTop, 3.2, 0.030, 0.8 + GA.T() * 0.9, false);
            ctx.lineTo(x1, g.baseY + 4);
            ctx.lineTo(x0, g.baseY + 4);
            ctx.closePath();
            ctx.fillStyle = grad;
            ctx.fill();

            ctx.beginPath();
            GC.wavePath(ctx, x0, x1, groundTop, 3.2, 0.030, 0.8 + GA.T() * 0.9, false);
            ctx.lineWidth = 1.4;
            ctx.lineJoin = "round";
            ctx.strokeStyle = p.isDark ? "rgba(255,255,255,0.55)" : "rgba(60,110,175,0.60)";
            ctx.stroke();
        }
        ctx.restore();
    }

    if (GA.dial()) {
        // ── Dial ─────────────────────────────────────────────────────────────
        var cmTicks = [5, 20, 50];
        var ticks = [{ t: 0, label: "0" }];
        for (var k = 0; k < cmTicks.length; k++)
            ticks.push({ t: _t(cmTicks[k]), label: GC.fmt(GC.cmToDisp(cmTicks[k], p.imperial), 0) });
        ticks.push({ t: 1, label: GC.fmt(GC.cmToDisp(MAXCM, p.imperial), 0) });

        GC.drawDial(ctx, g, {
            bands: [
                { from: 0, to: _t(5), color: pal.light },
                { from: _t(5), to: _t(20), color: pal.mod },
                { from: _t(20), to: _t(50), color: pal.deep },
                { from: _t(50), to: 1, color: pal.very }
            ],
            t: any ? t : NaN,
            colorAt: function (tt) { return colorAt(tt * tt * MAXCM, p.isDark); },
            ticks: ticks,
            text: p.text
        });

        if (has) {
            var m = GC.pointAt(g, any ? t : 0, g.r);
            GC.drawDot(ctx, g, any ? t : 0, cur, p.isDark, 6);
            // tiny crystal on the marker
            snowflakePath(ctx, m.x, m.y, 3);
            ctx.lineWidth = 1;
            ctx.strokeStyle = p.isDark ? "rgba(20,20,20,0.8)" : "rgba(255,255,255,0.95)";
            ctx.stroke();
        }
    }
}

// local alias so the scene code above reads naturally
function snowflakePath(ctx, x, y, s) { GC.snowflakePath(ctx, x, y, s); }
