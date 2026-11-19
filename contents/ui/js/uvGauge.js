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
 * uvGauge.js - Canvas drawing for the expandable UV Index card.
 *
 * 0-12 dial in the WHO colour zones (low / moderate / high / very high /
 * extreme). A glowing sun marks the current index, a short tick across the
 * dial marks today's expected peak, and a faint sunburst fans out behind it.
 */
.pragma library
.import "gaugeCommon.js" as GC
.import "gaugeAnim.js" as GA

var MAXUV = 12;

function _t(uv) { return GC.clamp01(uv / MAXUV); }

function _pal(isDark) {
    return isDark
        ? { low: "#4caf50", mod: "#fdd835", high: "#ff9800", very: "#f44336", ext: "#ba68c8" }
        : { low: "#2e7d32", mod: "#8a7000", high: "#c06000", very: "#c62828", ext: "#7b1fa2" };
}

function _vivid() {
    return { low: "#4caf50", mod: "#fdd835", high: "#ff9800", very: "#f44336", ext: "#ab47bc" };
}

/** Colour used for the dial (vivid) - the text colour uses _pal(). */
function _dialColorAt(uv, vivid) {
    return GC.colorScale([[0, vivid.low], [2, vivid.low], [3, vivid.mod], [5, vivid.mod],
                          [6, vivid.high], [7, vivid.high], [8, vivid.very], [10, vivid.very],
                          [11, vivid.ext], [12, vivid.ext]], uv);
}

function colorAt(uv, isDark) {
    var p = _pal(isDark);
    return GC.colorScale([[0, p.low], [2, p.low], [3, p.mod], [5, p.mod],
                          [6, p.high], [7, p.high], [8, p.very], [10, p.very],
                          [11, p.ext], [12, p.ext]], uv);
}

// Same thresholds as the collapsed row's uvIndexText() in main.qml
function bandKey(uv) {
    if (!GC.isNum(uv)) return "";
    var v = Math.round(uv * 10) / 10;
    if (v <= 2) return "low";
    if (v <= 5) return "moderate";
    if (v <= 7) return "high";
    if (v <= 10) return "veryhigh";
    return "extreme";
}

function info(uv, isDark) {
    return { key: bandKey(uv), color: GC.isNum(uv) ? colorAt(uv, isDark) : _pal(isDark).low };
}

function _sun(ctx, x, y, color, isDark) {
    // glow
    var gl = ctx.createRadialGradient(x, y, 0, x, y, 26);
    gl.addColorStop(0, GC.rgba(color, 0.55));
    gl.addColorStop(0.5, GC.rgba(color, 0.16));
    gl.addColorStop(1, GC.rgba(color, 0));
    ctx.fillStyle = gl;
    ctx.beginPath();
    ctx.arc(x, y, 26, 0, 2 * GC.PI);
    ctx.fill();
    // rays
    ctx.lineCap = "round";
    ctx.lineWidth = 1.8;
    ctx.strokeStyle = color;
    for (var i = 0; i < 8; i++) {
        var a = i * GC.PI / 4;
        ctx.beginPath();
        ctx.moveTo(x + Math.cos(a) * 9, y + Math.sin(a) * 9);
        ctx.lineTo(x + Math.cos(a) * 13, y + Math.sin(a) * 13);
        ctx.stroke();
    }
    // disc
    ctx.beginPath();
    ctx.arc(x, y, 6, 0, 2 * GC.PI);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = isDark ? "rgba(20,20,20,0.85)" : "rgba(255,255,255,0.95)";
    ctx.stroke();
}

/** p = { v: UV index, v2: today's peak UV index, isDark, text } */
function draw(ctx, cw, ch, p) {
    ctx.clearRect(0, 0, cw, ch);
    var g = GC.geometry(cw, ch);
    if (!g.ok) return;

    var vivid = _vivid();
    var has = GC.isNum(p.v);
    var t = has ? _t(p.v) : 0;
    var cur = has ? _dialColorAt(p.v, vivid) : vivid.low;

    // ── Scene: sunburst fanning out from the dial centre ─────────────────
    if (GA.scene()) {
        GC.clipDisc(ctx, g, 6);
        var tint = ctx.createRadialGradient(g.cx, g.baseY, 0, g.cx, g.baseY, g.r);
        tint.addColorStop(0, GC.rgba(cur, has ? 0.13 : 0.04));
        tint.addColorStop(1, GC.rgba(cur, 0));
        ctx.fillStyle = tint;
        ctx.fillRect(0, 0, cw, ch);

        var rays = 17;
        var intensity = (has ? 0.04 + 0.07 * t : 0.03) * (0.7 + 0.6 * GA.pulse(3.5));
        for (var i = 0; i < rays; i++) {
            var a = GC.PI + (i + 0.5) * GC.PI / rays + GA.osc(0.7, 0, 0.04);
            var half = 0.045;
            ctx.beginPath();
            ctx.moveTo(g.cx, g.baseY);
            ctx.lineTo(g.cx + Math.cos(a - half) * g.r, g.baseY + Math.sin(a - half) * g.r);
            ctx.lineTo(g.cx + Math.cos(a + half) * g.r, g.baseY + Math.sin(a + half) * g.r);
            ctx.closePath();
            ctx.fillStyle = GC.rgba(cur, (i % 2 === 0) ? intensity * 1.4 : intensity * 0.7);
            ctx.fill();
        }
        ctx.restore();
    }

    if (GA.dial()) {
        // ── Dial ─────────────────────────────────────────────────────────────
        var ticks = [
            { t: 0, label: "0" },
            { t: _t(2), label: "2" },
            { t: _t(5), label: "5" },
            { t: _t(7), label: "7" },
            { t: _t(10), label: "10" },
            { t: 1, label: "12" }
        ];
        GC.drawDial(ctx, g, {
            bands: [
                { from: 0, to: _t(2), color: vivid.low },
                { from: _t(2), to: _t(5), color: vivid.mod },
                { from: _t(5), to: _t(7), color: vivid.high },
                { from: _t(7), to: _t(10), color: vivid.very },
                { from: _t(10), to: 1, color: vivid.ext }
            ],
            t: has ? t : NaN,
            colorAt: function (tt) { return _dialColorAt(tt * MAXUV, vivid); },
            ticks: ticks,
            text: p.text
        });

        // ── Today's peak ─────────────────────────────────────────────────────
        if (GC.isNum(p.v2) && p.v2 > 0 && (!has || Math.abs(p.v2 - p.v) >= 0.3)) {
            var tp = _t(p.v2);
            var a0 = GC.pointAt(g, tp, g.r - 9);
            var a1 = GC.pointAt(g, tp, g.r + 9);
            ctx.beginPath();
            ctx.moveTo(a0.x, a0.y);
            ctx.lineTo(a1.x, a1.y);
            ctx.lineWidth = 3.2;
            ctx.lineCap = "round";
            ctx.strokeStyle = p.isDark ? "rgba(20,20,20,0.85)" : "rgba(255,255,255,0.95)";
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(a0.x, a0.y);
            ctx.lineTo(a1.x, a1.y);
            ctx.lineWidth = 1.6;
            ctx.strokeStyle = GC.rgba(p.text, 0.9);
            ctx.stroke();
        }

        if (has) {
            var m = GC.pointAt(g, t, g.r);
            _sun(ctx, m.x, m.y, cur, p.isDark);
        }
    }
}
