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
 * windCompass.js — shared Canvas drawing for wind-compass roses, used by
 * the expandable Wind card (DetailsView), the Simple layout, and the
 * Simple layout's per-day forecast mini-compasses.
 *
 * dirDeg (0 = N) is the meteorological convention — the direction the wind
 * is blowing FROM (matching weather.js windDirectionGlyph()/
 * windDirectionSvgStem() and the provider data). The arrow is drawn pointing
 * 180° from dirDeg (the flow/TO direction), verified against the bundled
 * weathericons-regular-webfont.ttf glyphs: e.g. its "N" glyph (chosen when
 * dirDeg=0) renders as a triangle pointing DOWN, i.e. toward the flow
 * direction, not up at the FROM bearing.
 */
.pragma library

/** 16-point cardinal abbreviation for a bearing in degrees. */
function cardinal(deg) {
    if (deg === undefined || deg === null || isNaN(deg)) return "";
    var names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                 "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
    var idx = Math.floor(((deg + 11.25) % 360) / 22.5) % 16;
    return names[idx];
}

/**
 * Beaufort-like colour band for a wind speed in km/h — used to tint the
 * compass arrow/glow so "how windy is it" reads at a glance.
 *   < 12 km/h  calm/light breeze   → blue
 *   12-29 km/h moderate breeze     → teal/green
 *   29-50 km/h strong breeze/gale  → amber
 *   >= 50 km/h storm-force         → red
 */
function speedColor(kmh) {
    if (kmh === undefined || kmh === null || isNaN(kmh)) return "#4db6f0";
    if (kmh < 12) return "#4db6f0";
    if (kmh < 29) return "#3ecf8e";
    if (kmh < 50) return "#f0a830";
    return "#f0533e";
}

/**
 * @param ctx        2D canvas context
 * @param cw, ch     canvas size
 * @param dirDeg     wind bearing in degrees (0 = N), may be NaN
 * @param textCss    theme text colour (CSS string), used for the ring/labels
 * @param arrowCss   arrow colour (CSS string)
 * @param speedText  formatted wind speed (e.g. "12 km/h"), drawn outside the
 *                    ring at the arrow tip. Pass "" / null to omit.
 * @param isDark     dark-theme flag — tunes the glow opacity (optional, default false)
 * @param windKmh    wind speed in km/h — tints the arrow/glow by Beaufort-like
 *                    band (calm→blue, breezy→teal, strong→amber, storm→red).
 *                    Pass NaN/undefined to keep the fixed default blue.
 * @param boldNearestCardinal  when true, bolds/brightens whichever N/E/S/W
 *                    label is closest to dirDeg instead of always bolding N
 *                    (used by the Simple layout's per-day mini compasses).
 */
function drawWindCompass(ctx, cw, ch, dirDeg, textCss, arrowCss, speedText, isDark, windKmh, boldNearestCardinal) {
    ctx.clearRect(0, 0, cw, ch);
    if (cw <= 0 || ch <= 0) return;

    var cx = cw / 2;
    var cy = ch / 2;
    // Reserve an outer margin for the speed label, which sits just outside the ring.
    var r = Math.min(cx, cy) - (speedText ? 16 : 2);
    if (r <= 4) return;

    var textCol  = textCss || "#ffffff";
    var arrowCol = arrowCss || speedColor(windKmh);

    // ── Background glow ───────────────────────────────────────────────────
    // Soft radial tint behind the ring, matching the sun/moon arc cards'
    // "sky tint" treatment so the wind card doesn't look bare by comparison.
    // The gradient's outer radius is capped at the canvas's own half-size
    // (not r * some factor > 1) so it fully fades to transparent BEFORE
    // reaching the canvas edge — otherwise the canvas's square pixel bounds
    // hard-clip the still-visible gradient, producing a "squared" glow.
    var glowOuter = Math.min(cx, cy) - 1;
    var glow = ctx.createRadialGradient(cx, cy, 0, cx, cy, glowOuter);
    var glowPeak = isDark ? 0.22 : 0.14;
    glow.addColorStop(0,   _withAlpha(arrowCol, glowPeak));
    glow.addColorStop(0.55, _withAlpha(arrowCol, glowPeak * 0.35));
    glow.addColorStop(1,   "rgba(0,0,0,0)");
    ctx.fillStyle = glow;
    ctx.beginPath();
    ctx.arc(cx, cy, glowOuter, 0, Math.PI * 2);
    ctx.fill();

    // Outer ring
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.strokeStyle = _withAlpha(textCol, 0.25);
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // Cardinal labels — by default N is always emphasised; when
    // boldNearestCardinal is set, whichever cardinal is closest to dirDeg
    // is emphasised instead (Simple layout's per-day mini compasses).
    var cardinals = [["N", 0], ["E", 90], ["S", 180], ["W", 270]];
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    for (var i = 0; i < cardinals.length; i++) {
        var lbl = cardinals[i][0];
        var ang = (cardinals[i][1] - 90) * Math.PI / 180;
        var lx = cx + (r - 7) * Math.cos(ang);
        var ly = cy + (r - 7) * Math.sin(ang);
        var isEmph;
        if (boldNearestCardinal) {
            var diff = Math.abs(((cardinals[i][1] - dirDeg) + 540) % 360 - 180);
            isEmph = !isNaN(dirDeg) && diff <= 45;
        } else {
            isEmph = (lbl === "N");
        }
        ctx.font = isEmph ? "bold 9px sans-serif" : "9px sans-serif";
        ctx.fillStyle = _withAlpha(textCol, isEmph ? 1.0 : 0.55);
        ctx.fillText(lbl, lx, ly);
    }

    // Directional arrow — tip points in the direction the wind is blowing
    // TO (dirDeg + 180°). dirDeg itself is the meteorological "from" bearing
    // (e.g. provider wind_direction_10m). This matches the collapsed-row
    // wi-font glyph (W.windDirectionGlyph) verified against the bundled
    // weathericons-regular-webfont.ttf: its "N" glyph (chosen when dirDeg=0,
    // i.e. wind FROM the north) renders as a triangle pointing DOWN — i.e.
    // toward the flow/TO direction, not up at the FROM bearing.
    if (dirDeg !== undefined && dirDeg !== null && !isNaN(dirDeg)) {
        var arrowAng = (dirDeg + 90) * Math.PI / 180;
        var arrowLen = r - 16;
        var ax = cx + arrowLen * Math.cos(arrowAng);
        var ay = cy + arrowLen * Math.sin(arrowAng);
        var tailX = cx - (arrowLen * 0.5) * Math.cos(arrowAng);
        var tailY = cy - (arrowLen * 0.5) * Math.sin(arrowAng);

        ctx.beginPath();
        ctx.moveTo(tailX, tailY);
        ctx.lineTo(ax, ay);
        ctx.strokeStyle = arrowCol;
        ctx.lineWidth = 2.5;
        ctx.lineCap = "round";
        ctx.stroke();

        var headLen = 7, headAng = 0.45;
        ctx.beginPath();
        ctx.moveTo(ax, ay);
        ctx.lineTo(ax - headLen * Math.cos(arrowAng - headAng),
                   ay - headLen * Math.sin(arrowAng - headAng));
        ctx.moveTo(ax, ay);
        ctx.lineTo(ax - headLen * Math.cos(arrowAng + headAng),
                   ay - headLen * Math.sin(arrowAng + headAng));
        ctx.strokeStyle = arrowCol;
        ctx.lineWidth = 2.5;
        ctx.lineCap = "round";
        ctx.stroke();

        ctx.beginPath();
        ctx.arc(cx, cy, 2.5, 0, Math.PI * 2);
        ctx.fillStyle = arrowCol;
        ctx.fill();

        // Speed label just outside the ring, at the arrow's bearing
        if (speedText) {
            var lx2 = cx + (r + 12) * Math.cos(arrowAng);
            var ly2 = cy + (r + 12) * Math.sin(arrowAng);
            ctx.font = "bold 11px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillStyle = arrowCol;
            ctx.fillText(speedText, lx2, ly2);
        }
    }
}

/** Applies an alpha to a CSS color string (hex "#rrggbb" or already rgb/rgba()). */
function _withAlpha(css, alpha) {
    if (!css) return "rgba(255,255,255," + alpha + ")";
    if (css.charAt(0) === "#" && css.length === 7) {
        var r = parseInt(css.substr(1, 2), 16);
        var g = parseInt(css.substr(3, 2), 16);
        var b = parseInt(css.substr(5, 2), 16);
        return "rgba(" + r + "," + g + "," + b + "," + alpha + ")";
    }
    var m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(css);
    if (m) return "rgba(" + m[1] + "," + m[2] + "," + m[3] + "," + alpha + ")";
    return css;
}
