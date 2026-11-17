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
 * gaugeCommon.js - shared helpers for the expanded Details-card gauges
 * (humidity, dew point, visibility, precipitation, precipitation sum,
 * UV index, snow cover, feels like).
 *
 * Every gauge uses the same semicircular dial geometry as pressureGauge.js
 * (left -> right over the top, baseline 20 px above the canvas bottom), so
 * the DetailsView overlay (icon + value + band label) sits in the same spot
 * on all of them.
 *
 * .pragma library - pure JS math/drawing, no Qt APIs.
 *
 * Import via:
 *   .import "gaugeCommon.js" as GC
 */
.pragma library

var PI = Math.PI;

// ═════════════════════════════════════════════════════════════════════════
// Numbers
// ═════════════════════════════════════════════════════════════════════════

function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
function clamp01(t) { return t < 0 ? 0 : (t > 1 ? 1 : t); }
function isNum(v) { return typeof v === "number" && isFinite(v); }

/** Rounds to `dec` decimals and drops trailing zeros ("0.20" -> "0.2"). */
function fmt(v, dec) {
    var k = Math.pow(10, dec || 0);
    return (Math.round(v * k) / k).toString();
}

// Unit conversions - gauges always receive metric values; labels are converted here.
function cToDisp(c, unit)   { return unit === "F" ? c * 9 / 5 + 32 : c; }
function kmToDisp(km, imp)  { return imp ? km * 0.621371 : km; }
function mmToDisp(mm, imp)  { return imp ? mm / 25.4 : mm; }
function cmToDisp(cm, imp)  { return imp ? cm / 2.54 : cm; }

// ═════════════════════════════════════════════════════════════════════════
// Colours
// ═════════════════════════════════════════════════════════════════════════

/** Parses "#rgb", "#rrggbb", Qt's "#aarrggbb" and "rgb(a)(...)" into {r,g,b,a}. */
function parseColor(css) {
    var out = { r: 255, g: 255, b: 255, a: 1 };
    if (!css) return out;
    var s = String(css).replace(/^\s+|\s+$/g, "");
    if (s.charAt(0) === "#") {
        var h = s.substring(1);
        if (h.length === 3) {
            out.r = parseInt(h.charAt(0) + h.charAt(0), 16);
            out.g = parseInt(h.charAt(1) + h.charAt(1), 16);
            out.b = parseInt(h.charAt(2) + h.charAt(2), 16);
        } else if (h.length === 6) {
            out.r = parseInt(h.substr(0, 2), 16);
            out.g = parseInt(h.substr(2, 2), 16);
            out.b = parseInt(h.substr(4, 2), 16);
        } else if (h.length === 8) {
            out.a = parseInt(h.substr(0, 2), 16) / 255;
            out.r = parseInt(h.substr(2, 2), 16);
            out.g = parseInt(h.substr(4, 2), 16);
            out.b = parseInt(h.substr(6, 2), 16);
        }
        return out;
    }
    var m = /rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?/.exec(s);
    if (m) {
        out.r = parseInt(m[1], 10);
        out.g = parseInt(m[2], 10);
        out.b = parseInt(m[3], 10);
        out.a = (m[4] !== undefined) ? parseFloat(m[4]) : 1;
    }
    return out;
}

/** CSS colour with the given alpha (multiplied with the colour's own alpha). */
function rgba(css, alpha) {
    var c = parseColor(css);
    return "rgba(" + c.r + "," + c.g + "," + c.b + "," + (alpha * c.a).toFixed(3) + ")";
}

function _hx(n) {
    var s = Math.max(0, Math.min(255, Math.round(n))).toString(16);
    return s.length < 2 ? "0" + s : s;
}

/** Linear blend of two colours, f = 0 -> a, f = 1 -> b. Returns "#rrggbb". */
function mix(a, b, f) {
    var ca = parseColor(a), cb = parseColor(b);
    return "#" + _hx(ca.r + (cb.r - ca.r) * f)
               + _hx(ca.g + (cb.g - ca.g) * f)
               + _hx(ca.b + (cb.b - ca.b) * f);
}

/**
 * Multi-stop colour scale: stops = [[value, "#rrggbb"], ...] in ascending
 * value order; values outside the range take the first/last colour.
 */
function colorScale(stops, v) {
    if (!isNum(v)) return stops[0][1];
    if (v <= stops[0][0]) return stops[0][1];
    var last = stops[stops.length - 1];
    if (v >= last[0]) return last[1];
    for (var i = 1; i < stops.length; i++) {
        if (v <= stops[i][0]) {
            var span = stops[i][0] - stops[i - 1][0];
            var f = span > 0 ? (v - stops[i - 1][0]) / span : 0;
            return mix(stops[i - 1][1], stops[i][1], f);
        }
    }
    return last[1];
}

// ═════════════════════════════════════════════════════════════════════════
// Dial geometry (identical to pressureGauge.js)
// ═════════════════════════════════════════════════════════════════════════

function geometry(cw, ch) {
    var cx = cw / 2;
    var baseY = ch - 20;
    var r = Math.min(cx - 24, baseY - 6);
    return { cx: cx, baseY: baseY, r: r, w: cw, h: ch, ok: cw > 0 && ch > 0 && r > 24 };
}

/** Canvas angle for a 0..1 position on the dial (0 = far left, 1 = far right). */
function angleAt(t) { return PI * (1 + clamp01(t)); }

function pointAt(g, t, rad) {
    var a = angleAt(t);
    return { x: g.cx + Math.cos(a) * rad, y: g.baseY + Math.sin(a) * rad };
}

/** Starts a clip to the dial's inner half-disc; the caller must ctx.restore(). */
function clipDisc(ctx, g, inset) {
    ctx.save();
    ctx.beginPath();
    ctx.arc(g.cx, g.baseY, g.r - (inset || 0), PI, 2 * PI, false);
    ctx.closePath();
    ctx.clip();
}

/** Small deterministic random generator so decorations don't jump around between repaints. */
function makeRng(seed) {
    var s = seed > 0 ? seed : 1;
    return function () {
        s = (s * 16807) % 2147483647;
        return (s - 1) / 2147483646;
    };
}

/** Random point inside the dial's half-disc, at most rMax from the centre. */
function randomInDisc(rng, g, rMax) {
    var a = PI + rng() * PI;
    var rad = rMax * Math.sqrt(rng());
    return { x: g.cx + Math.cos(a) * rad, y: g.baseY + Math.sin(a) * rad };
}

// ═════════════════════════════════════════════════════════════════════════
// Dial drawing
// ═════════════════════════════════════════════════════════════════════════

/**
 * Draws the dial itself.
 *   o.bands     [{from, to, color}] zones in 0..1, drawn dimmed as the "scale"
 *   o.bandAlpha alpha of the dimmed zones (default 0.30)
 *   o.t         current position 0..1 (NaN/undefined -> no progress arc)
 *   o.colorAt   function(t) -> css colour of the progress arc at position t
 *   o.width     arc thickness (default 8)
 *   o.ticks     [{t, label, major}] - labels at t <= 0 / t >= 1 go under the baseline
 *   o.text      theme text colour (css)
 */
function drawDial(ctx, g, o) {
    var width = o.width || 8;
    var bandAlpha = (o.bandAlpha === undefined) ? 0.30 : o.bandAlpha;
    var gap = 0.014;

    if (o.ghostAt) {
        // continuous dimmed scale (instead of discrete zones)
        var gs = 90;
        for (var q = 0; q < gs; q++) {
            ctx.beginPath();
            ctx.arc(g.cx, g.baseY, g.r, angleAt(q / gs), angleAt((q + 1) / gs), false);
            ctx.lineWidth = width;
            ctx.lineCap = "butt";
            ctx.strokeStyle = rgba(o.ghostAt((q + 0.5) / gs), bandAlpha);
            ctx.stroke();
        }
        var gS = pointAt(g, 0, g.r), gE = pointAt(g, 1, g.r);
        ctx.fillStyle = rgba(o.ghostAt(0), bandAlpha);
        ctx.beginPath(); ctx.arc(gS.x, gS.y, width / 2, 0, 2 * PI); ctx.fill();
        ctx.fillStyle = rgba(o.ghostAt(1), bandAlpha);
        ctx.beginPath(); ctx.arc(gE.x, gE.y, width / 2, 0, 2 * PI); ctx.fill();
    } else if (o.bands && o.bands.length > 0) {
        for (var i = 0; i < o.bands.length; i++) {
            var b = o.bands[i];
            var a0 = angleAt(b.from) + (b.from > 0.0001 ? gap : 0);
            var a1 = angleAt(b.to) - (b.to < 0.9999 ? gap : 0);
            if (a1 <= a0) continue;
            ctx.beginPath();
            ctx.arc(g.cx, g.baseY, g.r, a0, a1, false);
            ctx.lineWidth = width;
            ctx.lineCap = "butt";
            ctx.strokeStyle = rgba(b.color, bandAlpha);
            ctx.stroke();
        }
        // rounded ends of the scale
        var pS = pointAt(g, 0, g.r), pE = pointAt(g, 1, g.r);
        ctx.fillStyle = rgba(o.bands[0].color, bandAlpha);
        ctx.beginPath(); ctx.arc(pS.x, pS.y, width / 2, 0, 2 * PI); ctx.fill();
        ctx.fillStyle = rgba(o.bands[o.bands.length - 1].color, bandAlpha);
        ctx.beginPath(); ctx.arc(pE.x, pE.y, width / 2, 0, 2 * PI); ctx.fill();
    } else {
        ctx.beginPath();
        ctx.arc(g.cx, g.baseY, g.r, PI, 2 * PI, false);
        ctx.lineWidth = width;
        ctx.lineCap = "round";
        ctx.strokeStyle = rgba(o.text, 0.13);
        ctx.stroke();
    }

    // progress arc - swept segment by segment through the colour scale
    var t = o.t;
    if (isNum(t) && t > 0 && o.colorAt) {
        t = clamp01(t);
        var steps = Math.max(2, Math.ceil(t * 90));
        for (var k = 0; k < steps; k++) {
            var ta = t * k / steps;
            var tb = t * (k + 1) / steps;
            ctx.beginPath();
            ctx.arc(g.cx, g.baseY, g.r, angleAt(ta) - (k > 0 ? 0.006 : 0), angleAt(tb), false);
            ctx.lineWidth = width;
            ctx.lineCap = "butt";
            ctx.strokeStyle = o.colorAt((ta + tb) / 2);
            ctx.stroke();
        }
        var ps = pointAt(g, 0, g.r);
        ctx.fillStyle = o.colorAt(0);
        ctx.beginPath(); ctx.arc(ps.x, ps.y, width / 2, 0, 2 * PI); ctx.fill();
    }

    if (o.ticks) drawTicks(ctx, g, o.ticks, o.text);
}

/** Tick marks + numeric labels just inside the dial. */
function drawTicks(ctx, g, ticks, textCss) {
    for (var i = 0; i < ticks.length; i++) {
        var tk = ticks[i];
        var end = (tk.t <= 0.001 || tk.t >= 0.999);
        if (!end) {
            var p0 = pointAt(g, tk.t, g.r - 7);
            var p1 = pointAt(g, tk.t, g.r - (tk.major ? 14 : 11));
            ctx.beginPath();
            ctx.moveTo(p0.x, p0.y);
            ctx.lineTo(p1.x, p1.y);
            ctx.lineWidth = 1.2;
            ctx.lineCap = "butt";
            ctx.strokeStyle = rgba(textCss, tk.major ? 0.55 : 0.35);
            ctx.stroke();
        }
        if (!tk.label) continue;
        if (end) {
            label(ctx, tk.label, g.cx + (tk.t < 0.5 ? -g.r : g.r), g.baseY + 6, 10, textCss, 0.5, false, "center", "top");
        } else {
            var lp = pointAt(g, tk.t, g.r - 23);
            label(ctx, tk.label, lp.x, lp.y, 9, textCss, 0.55, false, "center", "middle");
        }
    }
}

function label(ctx, txt, x, y, px, css, alpha, bold, align, baseline) {
    ctx.font = (bold ? "bold " : "") + px + "px sans-serif";
    ctx.textAlign = align || "center";
    ctx.textBaseline = baseline || "middle";
    ctx.fillStyle = rgba(css, alpha);
    ctx.fillText(txt, x, y);
}

// ═════════════════════════════════════════════════════════════════════════
// Markers
// ═════════════════════════════════════════════════════════════════════════

function _halo(isDark) { return isDark ? "rgba(20,20,20,0.85)" : "rgba(255,255,255,0.95)"; }

/** Filled round marker on the dial (same look as the pressure gauge's). */
function drawDot(ctx, g, t, color, isDark, rad) {
    var p = pointAt(g, t, g.r);
    var r = rad || 6;
    ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 2 * PI);
    ctx.fillStyle = color; ctx.fill();
    ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 2 * PI);
    ctx.lineWidth = 2; ctx.strokeStyle = _halo(isDark); ctx.stroke();
}

/** Hollow ring marker, used for a reference value (e.g. the real air temperature). */
function drawRing(ctx, g, t, color, isDark, rad) {
    var p = pointAt(g, t, g.r);
    var r = rad || 5.5;
    ctx.beginPath(); ctx.arc(p.x, p.y, r + 1.5, 0, 2 * PI);
    ctx.lineWidth = 2; ctx.strokeStyle = _halo(isDark); ctx.stroke();
    ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 2 * PI);
    ctx.fillStyle = _halo(isDark); ctx.fill();
    ctx.lineWidth = 2.4; ctx.strokeStyle = color; ctx.stroke();
}

/** Thin arc just inside the dial joining two positions (the gap between two readings). */
function drawBracket(ctx, g, t0, t1, color, alpha) {
    var lo = Math.min(t0, t1), hi = Math.max(t0, t1);
    if (hi - lo < 0.004) return;
    ctx.beginPath();
    ctx.arc(g.cx, g.baseY, g.r - 12, angleAt(lo), angleAt(hi), false);
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    ctx.strokeStyle = rgba(color, alpha === undefined ? 0.6 : alpha);
    ctx.stroke();
}

// ═════════════════════════════════════════════════════════════════════════
// Small shapes (path only - the caller fills / strokes)
// ═════════════════════════════════════════════════════════════════════════

/** Teardrop centred on (x, y), tip pointing up; s ~ radius of the round part. */
function dropletPath(ctx, x, y, s) {
    ctx.beginPath();
    ctx.moveTo(x, y - s * 1.45);
    ctx.bezierCurveTo(x + s * 0.30, y - s * 0.85, x + s * 0.98, y - s * 0.30, x + s * 0.98, y + s * 0.30);
    ctx.arc(x, y + s * 0.30, s * 0.98, 0, PI, false);
    ctx.bezierCurveTo(x - s * 0.98, y - s * 0.30, x - s * 0.30, y - s * 0.85, x, y - s * 1.45);
    ctx.closePath();
}

/** Six-armed snow crystal. */
function snowflakePath(ctx, x, y, s) {
    ctx.beginPath();
    for (var i = 0; i < 3; i++) {
        var a = i * PI / 3 + PI / 6;
        ctx.moveTo(x - Math.cos(a) * s, y - Math.sin(a) * s);
        ctx.lineTo(x + Math.cos(a) * s, y + Math.sin(a) * s);
    }
    if (s >= 3.2) {
        for (var j = 0; j < 6; j++) {
            var b = j * PI / 3 + PI / 6;
            var bx = x + Math.cos(b) * s * 0.62, by = y + Math.sin(b) * s * 0.62;
            ctx.moveTo(bx, by);
            ctx.lineTo(bx + Math.cos(b + 0.9) * s * 0.34, by + Math.sin(b + 0.9) * s * 0.34);
            ctx.moveTo(bx, by);
            ctx.lineTo(bx + Math.cos(b - 0.9) * s * 0.34, by + Math.sin(b - 0.9) * s * 0.34);
        }
    }
}

/** Adds a sine-sum wave line from x0 to x1 to the current path (no moveTo for the first point if `cont`). */
function wavePath(ctx, x0, x1, y, amp, k, ph, cont) {
    for (var x = x0; x <= x1; x += 3) {
        var yy = y + amp * Math.sin(k * x + ph) + amp * 0.45 * Math.sin(k * 2.3 * x + ph * 1.7);
        if (x === x0 && !cont) ctx.moveTo(x, yy); else ctx.lineTo(x, yy);
    }
}
