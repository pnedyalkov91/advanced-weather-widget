/*
 * Copyright 2026  Petar Nedyalkov
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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/**
 * pressureGauge.js — Canvas drawing for the expandable Pressure card.
 *
 * Draws a semicircular dial over the sea-level pressure range (970–1040 hPa)
 * with a coloured progress arc and a marker dot at the current reading.
 */
.pragma library

var LO = 970;
var HI = 1040;

/** Normalised 0..1 position of an hPa value on the gauge. */
function progress(hpa) {
    if (hpa === undefined || hpa === null || isNaN(hpa)) return 0.5;
    return Math.max(0, Math.min(1, (hpa - LO) / (HI - LO)));
}

/** Qualitative band key for an hPa value: "low" | "normal" | "high". */
function band(hpa) {
    if (hpa === undefined || hpa === null || isNaN(hpa)) return "normal";
    if (hpa < 1000) return "low";
    if (hpa > 1025) return "high";
    return "normal";
}

/** Pads a 0-255 channel value to a 2-digit hex string. */
function _hx(n) {
    var s = Math.max(0, Math.min(255, Math.round(n))).toString(16);
    return s.length < 2 ? "0" + s : s;
}

/**
 * Theme-aware colour for an hPa value across the LO..HI gauge range —
 * low pressure (storm-ish) → blue/violet, normal → teal/green, high
 * (fair-weather) → warm amber. Mirrors the same multi-stop interpolation
 * pattern used by the hourly-forecast temperature trend line. Returns a
 * "#rrggbb" string usable both as a Canvas fill/strokeStyle and as a QML
 * `color` binding.
 */
function pressureColor(hpa, isDark) {
    if (hpa === undefined || hpa === null || isNaN(hpa))
        return isDark ? "#4ecdc4" : "#007070";
    var stops = isDark ? [
        { t: 970,  r: 120, g: 130, b: 255 },
        { t: 1000, r:  80, g: 190, b: 230 },
        { t: 1013, r:  78, g: 205, b: 196 },
        { t: 1025, r: 120, g: 220, b: 140 },
        { t: 1040, r: 255, g: 190, b:  90 }
    ] : [
        { t: 970,  r:  70, g:  70, b: 210 },
        { t: 1000, r:   0, g: 120, b: 190 },
        { t: 1013, r:   0, g: 112, b: 112 },
        { t: 1025, r:  40, g: 140, b:  60 },
        { t: 1040, r: 200, g: 120, b:   0 }
    ];
    var t = Math.max(LO, Math.min(HI, hpa));
    if (t <= stops[0].t) { var s0 = stops[0]; return "#" + _hx(s0.r) + _hx(s0.g) + _hx(s0.b); }
    if (t >= stops[stops.length - 1].t) { var sN = stops[stops.length - 1]; return "#" + _hx(sN.r) + _hx(sN.g) + _hx(sN.b); }
    for (var i = 1; i < stops.length; i++) {
        if (t <= stops[i].t) {
            var frac = (t - stops[i - 1].t) / (stops[i].t - stops[i - 1].t);
            var r = stops[i - 1].r + frac * (stops[i].r - stops[i - 1].r);
            var g = stops[i - 1].g + frac * (stops[i].g - stops[i - 1].g);
            var b = stops[i - 1].b + frac * (stops[i].b - stops[i - 1].b);
            return "#" + _hx(r) + _hx(g) + _hx(b);
        }
    }
    return isDark ? "#4ecdc4" : "#007070";
}

/**
 * @param ctx        2D canvas context
 * @param cw, ch     canvas size
 * @param hpa        pressure in hPa, may be NaN
 * @param isDark     dark theme flag
 * @param accentCss  accent colour (CSS string) — when given, overrides the
 *                    min/max-based colour scale with a single fixed colour
 *                    for the traveled arc + marker. Pass null to use the
 *                    LO..HI colour scale (low→blue, normal→teal, high→amber).
 */
function drawPressureGauge(ctx, cw, ch, hpa, isDark, accentCss) {
    ctx.clearRect(0, 0, cw, ch);
    if (cw <= 0 || ch <= 0) return;

    var cx = cw / 2;
    var baseY = ch - 20;
    var r = Math.min(cx - 24, baseY - 6);
    if (r <= 4) return;

    var trackCol = isDark ? "rgba(255,255,255,0.13)" : "rgba(0,0,0,0.11)";

    // Track (semicircle, left → right over the top)
    ctx.beginPath();
    ctx.arc(cx, baseY, r, Math.PI, 2 * Math.PI, false);
    ctx.lineWidth = 6;
    ctx.lineCap = "round";
    ctx.strokeStyle = trackCol;
    ctx.stroke();

    // Traveled arc up to the current value — swept through the LO..HI colour
    // scale (or a single fixed accentCss, if given) segment-by-segment, the
    // same per-segment-gradient technique used by the hourly temperature
    // trend line elsewhere in this widget.
    var t = progress(hpa);
    var ang = Math.PI * (1 + t);
    if (t > 0) {
        var steps = Math.max(1, Math.ceil(t * 60));
        for (var i = 0; i < steps; i++) {
            var a0 = Math.PI + (ang - Math.PI) * (i / steps);
            var a1 = Math.PI + (ang - Math.PI) * ((i + 1) / steps);
            var midHpa = LO + (HI - LO) * (((i + 0.5) / steps) * t);
            ctx.beginPath();
            ctx.arc(cx, baseY, r, a0, a1, false);
            ctx.lineWidth = 6;
            ctx.lineCap = "round";
            ctx.strokeStyle = accentCss || pressureColor(midHpa, isDark);
            ctx.stroke();
        }
    }

    var accent = accentCss || pressureColor(hpa, isDark);

    // Marker dot
    var dx = cx + Math.cos(ang) * r;
    var dy = baseY + Math.sin(ang) * r;
    ctx.beginPath();
    ctx.arc(dx, dy, 6, 0, 2 * Math.PI);
    ctx.fillStyle = accent;
    ctx.fill();
    ctx.beginPath();
    ctx.arc(dx, dy, 6, 0, 2 * Math.PI);
    ctx.lineWidth = 2;
    ctx.strokeStyle = isDark ? "rgba(20,20,20,0.85)" : "rgba(255,255,255,0.95)";
    ctx.stroke();

    // End-scale labels
    ctx.font = "10px sans-serif";
    ctx.fillStyle = isDark ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.5)";
    ctx.textBaseline = "top";
    ctx.textAlign = "center";
    ctx.fillText("" + LO, cx - r, baseY + 5);
    ctx.fillText("" + HI, cx + r, baseY + 5);
}
