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
 * aqiGauge.js - Canvas drawing for one pollutant page of the expandable Air
 * Quality card.
 *
 * The scale itself comes from airQuality.js through DetailsView (position of
 * the reading, the band colour, the tick positions), so this file never has
 * to know the index definition. The colours reproduce the old slider bar:
 * the dimmed track is the green -> lime -> orange -> red -> purple scale by
 * position, the swept arc runs through the same colours up to the reading
 * and ends in the band colour.
 *
 * The scene depends on the pollutant: drifting particles (PM2.5 / PM10),
 * layered haze with small molecules (NO2 / SO2 / CO), shimmering ozone
 * triplets (O3).
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "gaugeAnim.js" as GA

var TRACK = [[0, "#4CAF50"], [0.167, "#CDDC39"], [0.333, "#FF9800"],
             [0.5, "#F44336"], [0.75, "#9C27B0"], [1, "#7B1FA2"]];
var FILL = [[0, "#4CAF50"], [25, "#CDDC39"], [50, "#FF9800"], [75, "#F44336"], [100, "#9C27B0"]];

/** Scene family for a pollutant key. */
function kindOf(key) {
    if (key === "pm2_5") return "pm25";
    if (key === "pm10") return "pm10";
    if (key === "o3") return "ozone";
    return "gas";
}

/** Colour of the swept arc at fraction `frac` (0..1) of the filled part. */
function fillColor(frac, si, bandColor) {
    if (!GC.isNum(si) || si <= 0) return bandColor;
    var stops = [];
    for (var i = 0; i < FILL.length; i++)
        if (FILL[i][0] < si) stops.push(FILL[i]);
    stops.push([si, bandColor]);
    return GC.colorScale(stops, frac * si);
}

function _molecule(ctx, x, y, s, n, col, al) {
    // n = 2 -> a pair of atoms, n = 3 -> an O3 triangle
    var pts = n === 3
        ? [[0, -s * 0.9], [-s, s * 0.6], [s, s * 0.6]]
        : [[-s * 0.7, 0], [s * 0.7, 0]];
    ctx.strokeStyle = GC.rgba(col, al * 0.8);
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (var i = 0; i < pts.length; i++) {
        var q = pts[(i + 1) % pts.length];
        if (n === 2 && i === 1) break;
        ctx.moveTo(x + pts[i][0], y + pts[i][1]);
        ctx.lineTo(x + q[0], y + q[1]);
    }
    ctx.stroke();
    ctx.fillStyle = GC.rgba(col, al);
    for (var j = 0; j < pts.length; j++) {
        ctx.beginPath();
        ctx.arc(x + pts[j][0], y + pts[j][1], s * 0.42, 0, 2 * GC.PI);
        ctx.fill();
    }
}

/**
 * p = { t: 0..1 position of the reading (NaN = no data), si: sub-index,
 *       bandColor, key: "pm2_5" | "pm10" | "no2" | "o3" | "so2" | "co",
 *       ticks: [{t, label}], isDark, text }
 */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var has = GC.isNum(p.t);
    var t = has ? GC.clamp01(p.t) : 0;
    var col = (has && p.bandColor) ? p.bandColor : "#4CAF50";
    var kind = kindOf(p.key);
    var rng = GC.makeRng(kind === "pm25" ? 41 : (kind === "pm10" ? 43 : (kind === "ozone" ? 47 : 53)));

    // ── Scene ────────────────────────────────────────────────────────────
    if (GA.scene()) {
        GC.clipDisc(ctx, g, 6);
        var glow = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
        glow.addColorStop(0, GC.rgba(col, has ? 0.16 : 0.04));
        glow.addColorStop(1, GC.rgba(col, 0));
        ctx.fillStyle = glow;
        ctx.fillRect(0, 0, cw, ch);

        var dens = has ? 0.12 + 0.88 * t : 0;
        var i, pt, rad, al;
        if (kind === "pm25" || kind === "pm10") {
            var n = Math.round(8 + 34 * dens);
            var big = kind === "pm10";
            for (i = 0; i < 42; i++) {
                pt = GC.randomInDisc(rng, g, g.r - 12);
                rad = (big ? 1.4 : 0.8) + rng() * (big ? 2.2 : 1.4);
                al = 0.25 + rng() * 0.30;
                if (i >= n) continue;
                pt.x += GA.osc(0.8, i * 2.1, 5); pt.y += GA.osc(0.6, i * 1.3, 5);
                ctx.beginPath(); ctx.arc(pt.x, pt.y, rad, 0, 2 * GC.PI);
                ctx.fillStyle = GC.rgba(col, al); ctx.fill();
                if (big && rad > 2.2) {
                    ctx.beginPath(); ctx.arc(pt.x, pt.y, rad + 2.4, 0, 2 * GC.PI);
                    ctx.lineWidth = 0.8; ctx.strokeStyle = GC.rgba(col, al * 0.6); ctx.stroke();
                }
            }
        } else if (kind === "gas") {
            var x0 = g.cx - g.r, x1 = g.cx + g.r;
            for (i = 0; i < 3; i++) {
                var yy = g.baseY - (g.r - 14) * (0.22 + 0.22 * i);
                ctx.beginPath();
                GC.wavePath(ctx, x0, x1, yy, 3 + 2.2 * i, 0.028 + 0.004 * i, 1.1 * i + 0.4 + GA.T() * 0.7, false);
                ctx.lineTo(x1, g.baseY + 4); ctx.lineTo(x0, g.baseY + 4); ctx.closePath();
                ctx.fillStyle = GC.rgba(col, (0.03 + 0.05 * dens) * (1 + 0.2 * i));
                ctx.fill();
                ctx.beginPath();
                GC.wavePath(ctx, x0, x1, yy, 3 + 2.2 * i, 0.028 + 0.004 * i, 1.1 * i + 0.4 + GA.T() * 0.7, false);
                ctx.lineWidth = 1; ctx.strokeStyle = GC.rgba(col, 0.20 + 0.15 * dens); ctx.stroke();
            }
            var mn = Math.round(2 + 8 * dens);
            for (i = 0; i < 10; i++) {
                pt = GC.randomInDisc(rng, g, g.r - 18);
                al = 0.30 + rng() * 0.25;
                if (i >= mn) continue;
                pt.x += GA.osc(0.7, i * 1.9, 4); pt.y += GA.osc(0.5, i * 1.1, 4);
                _molecule(ctx, pt.x, pt.y, 2.6 + rng() * 1.4, 2, col, al);
            }
        } else {
            for (i = 1; i <= 3; i++) {
                ctx.beginPath();
                ctx.arc(g.cx, g.baseY, (g.r - 14) * (0.30 + 0.24 * i), GC.PI, 2 * GC.PI, false);
                ctx.lineWidth = 1; ctx.strokeStyle = GC.rgba(col, 0.10 + 0.08 * dens); ctx.stroke();
            }
            var on = Math.round(2 + 7 * dens);
            for (i = 0; i < 9; i++) {
                pt = GC.randomInDisc(rng, g, g.r - 20);
                al = 0.32 + rng() * 0.25;
                if (i >= on) continue;
                pt.x += GA.osc(0.7, i * 1.9, 4); pt.y += GA.osc(0.5, i * 1.1, 4);
                _molecule(ctx, pt.x, pt.y, 3 + rng() * 1.6, 3, col, al);
            }
        }
        ctx.restore();
    }

    if (GA.dial()) {
        // ── Dial ─────────────────────────────────────────────────────────────
        GC.drawDial(ctx, g, {
            ghostAt: function (tt) { return GC.colorScale(TRACK, tt); },
            bandAlpha: p.isDark ? 0.35 : 0.42,
            t: has ? t : NaN,
            colorAt: function (tt) { return fillColor(t > 0 ? tt / t : 0, p.si, col); },
            ticks: p.ticks || [],
            text: p.text
        });
        if (has) GC.drawDot(ctx, g, t, col, p.isDark, 6.5);
    }
}
