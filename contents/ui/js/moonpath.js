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
 * moonpath.js — Moon arc geometry, progress, rise/set calculation and canvas drawing
 *
 * MOONRISE / MOONSET — delegated to suncalc.js (getMoonTimes).
 * This file retains only canvas drawing helpers and arc-progress functions.
 *
 * The moon arc mirrors the sun arc from sunpath.js:
 *   Clockwise: left (moonrise) → top (transit) → right (moonset)
 *   moonX = cx + r·cos(π(1+p))
 *   moonY = hY + r·sin(π(1+p))   sin(3π/2)=-1 → above hY ✓
 *
 * Time arithmetic uses UTC + utcOffsetMins (Qt V4 does not support Intl).
 */

.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// Basic helpers
// ─────────────────────────────────────────────────────────────────────────────

function _deg(r) { return r * 180 / Math.PI; }
function _rad(d) { return d * Math.PI / 180; }
function _frac(x) { return x - Math.floor(x); }
function _rev(x)  { return x - Math.floor(x / 360) * 360; } // mod 360

// NOTE: parseMins(), nowMinsAt() and formatDuration() below are intentional
// local copies of the same functions in sunpath.js.  .pragma library files
// cannot import each other in Qt/QML, so deduplication at the JS level is
// not possible — they must be self-contained.
function parseMins(t) {
    if (!t || t === "--") return -1;
    var p = t.split(":");
    if (p.length < 2) return -1;
    var h = parseInt(p[0], 10), m = parseInt(p[1], 10);
    if (isNaN(h) || isNaN(m)) return -1;
    return h * 60 + m;
}

function _minsToHHMM(mins) {
    if (mins < 0) return "--";
    var h = Math.floor(mins / 60) % 24;
    var m = Math.round(mins % 60);
    if (m === 60) { h = (h + 1) % 24; m = 0; }
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
}

/** Current minutes-since-midnight at the weather location (UTC + offset). */
function nowMinsAt(utcOffsetMins) {
    var d = new Date();
    if (utcOffsetMins === undefined || utcOffsetMins === null || isNaN(utcOffsetMins)) {
        return d.getHours() * 60 + d.getMinutes();
    }
    var utcMins = d.getUTCHours() * 60 + d.getUTCMinutes();
    return ((utcMins + utcOffsetMins) % 1440 + 1440) % 1440;
}

// ─────────────────────────────────────────────────────────────────────────────
// Low-precision moon position (Meeus Ch.47 simplified)
// Returns { ra, dec } in degrees for a given Julian Day
// ─────────────────────────────────────────────────────────────────────────────

function _moonPos(jd) {
    var T  = (jd - 2451545.0) / 36525.0;

    // Moon's mean longitude (deg)
    var L0 = _rev(218.3164477 + 481267.88123421 * T);
    // Mean elongation
    var D  = _rev(297.8501921 + 445267.1114034  * T);
    // Sun's mean anomaly
    var M  = _rev(357.5291092 +  35999.0502909  * T);
    // Moon's mean anomaly
    var Mp = _rev(134.9633964 + 477198.8675055  * T);
    // Moon's argument of latitude
    var F  = _rev(93.2720950  + 483202.0175233  * T);

    // Convert to radians for trig
    var Dr = _rad(D), Mr = _rad(M), Mpr = _rad(Mp), Fr = _rad(F);

    // Longitude correction (main terms only, deg)
    var dL = 6.289 * Math.sin(Mpr)
           + 1.274 * Math.sin(2*Dr - Mpr)
           + 0.658 * Math.sin(2*Dr)
           - 0.186 * Math.sin(Mr)
           - 0.059 * Math.sin(2*Dr - 2*Mpr)
           - 0.057 * Math.sin(2*Dr - Mr - Mpr)
           + 0.053 * Math.sin(2*Dr + Mpr)
           + 0.046 * Math.sin(2*Dr - Mr)
           + 0.041 * Math.sin(Mpr - Mr)
           - 0.035 * Math.sin(Dr)
           - 0.031 * Math.sin(Mpr + Mr)
           - 0.015 * Math.sin(2*Fr - 2*Dr)
           + 0.011 * Math.sin(2*Mpr - 2*Dr);

    // Latitude correction (main terms, deg)
    var dB = 5.128 * Math.sin(Fr)
           + 0.280 * Math.sin(Mpr + Fr)
           + 0.277 * Math.sin(Mpr - Fr)
           + 0.173 * Math.sin(2*Dr - Fr)
           + 0.055 * Math.sin(2*Dr - Mpr + Fr)
           + 0.046 * Math.sin(2*Dr - Mpr - Fr)
           - 0.046 * Math.sin(2*Fr)
           + 0.033 * Math.sin(2*Dr + Fr);

    var lon = _rev(L0 + dL);   // ecliptic longitude (deg)
    var lat = dB;               // ecliptic latitude  (deg)

    // Obliquity of ecliptic (degrees, approximate)
    var eps = 23.4393 - 0.0000004 * T;
    var epsr = _rad(eps);
    var lonr = _rad(lon), latr = _rad(lat);

    // Ecliptic → Equatorial
    var sinDec = Math.sin(latr) * Math.cos(epsr)
               + Math.cos(latr) * Math.sin(epsr) * Math.sin(lonr);
    var dec = _deg(Math.asin(sinDec));

    var y   = Math.sin(lonr) * Math.cos(epsr) - Math.tan(latr) * Math.sin(epsr);
    var x   = Math.cos(lonr);
    var ra  = _rev(_deg(Math.atan2(y, x)));   // right ascension in degrees (0–360)

    return { ra: ra, dec: dec };
}

// ─────────────────────────────────────────────────────────────────────────────
// Moon arc progress
// ─────────────────────────────────────────────────────────────────────────────

function moonArcProgress(riseText, setText, utcOffsetMins) {
    var rise = parseMins(riseText);
    var set  = parseMins(setText);
    if (rise < 0 || set < 0) return 0.5;
    var now = nowMinsAt(utcOffsetMins);
    var adjSet = set < rise ? set + 1440 : set;
    var adjNow = (now < rise && set < rise) ? now + 1440 : now;
    return (adjNow - rise) / (adjSet - rise);
}

function moonVisibleMins(riseText, setText) {
    var rise = parseMins(riseText);
    var set  = parseMins(setText);
    if (rise < 0 || set < 0) return 0;
    return set > rise ? set - rise : (1440 - rise) + set;
}

function formatDuration(totalMins) {
    if (totalMins <= 0) return "0m";
    var h = Math.floor(totalMins / 60);
    var m = totalMins % 60;
    if (h === 0) return m + "m";
    if (m === 0) return h + "h";
    return h + "h " + m + "m";
}

// ─────────────────────────────────────────────────────────────────────────────
// Moon illumination / age (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Canvas drawing (all unchanged from previous version)
// ─────────────────────────────────────────────────────────────────────────────

function _drawMoonCrescent(ctx, mx, my, OR, age, isDark) {
    var IR     = OR * 0.68;
    var waxing = (age < 14.77);
    var offset = OR * 0.52 * (waxing ? 1 : -1);
    ctx.save();
    ctx.beginPath();
    ctx.arc(mx, my, OR, 0, 2 * Math.PI);
    ctx.fillStyle = isDark ? "#e8d8ff" : "#9070c8";
    ctx.fill();
    ctx.globalCompositeOperation = "destination-out";
    ctx.beginPath();
    ctx.arc(mx + offset, my, IR, 0, 2 * Math.PI);
    ctx.fill();
    ctx.restore();
    ctx.save();
    var rimStart = waxing ? Math.PI * 0.35 : Math.PI * 1.35;
    var rimEnd   = waxing ? Math.PI * 1.65 : Math.PI * 2.65;
    ctx.beginPath();
    ctx.arc(mx, my, OR, rimStart, rimEnd, false);
    ctx.strokeStyle = isDark ? "rgba(240,225,255,0.70)" : "rgba(200,175,255,0.70)";
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.restore();
}

function _drawFullMoon(ctx, mx, my, OR, isDark) {
    ctx.beginPath();
    ctx.arc(mx, my, OR, 0, 2 * Math.PI);
    ctx.fillStyle = isDark ? "#e8d8ff" : "#9070c8";
    ctx.fill();
    ctx.beginPath();
    ctx.arc(mx, my, OR * 0.65, 0, 2 * Math.PI);
    ctx.fillStyle = isDark ? "rgba(255,248,255,0.55)" : "rgba(210,190,255,0.55)";
    ctx.fill();
    ctx.save();
    ctx.beginPath();
    ctx.arc(mx, my, OR, 0, 2 * Math.PI);
    ctx.strokeStyle = isDark ? "rgba(240,225,255,0.70)" : "rgba(200,175,255,0.70)";
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.restore();
}

function _drawNewMoon(ctx, mx, my, OR, isDark) {
    ctx.beginPath();
    ctx.arc(mx, my, OR, 0, 2 * Math.PI);
    ctx.fillStyle = isDark ? "rgba(60,40,90,0.75)" : "rgba(30,20,60,0.75)";
    ctx.fill();
    ctx.beginPath();
    ctx.arc(mx, my, OR, 0, 2 * Math.PI);
    ctx.strokeStyle = isDark ? "rgba(160,130,220,0.55)" : "rgba(100,75,170,0.55)";
    ctx.lineWidth = 1.2;
    ctx.stroke();
}

function _drawMoonBody(ctx, mx, my, OR, age, isDark) {
    if (age < 1.5 || age > 28.0) _drawNewMoon(ctx, mx, my, OR, isDark);
    else if (age >= 13.5 && age <= 16.0) _drawFullMoon(ctx, mx, my, OR, isDark);
    else _drawMoonCrescent(ctx, mx, my, OR, age, isDark);
}

function _drawStars(ctx, cw, ch, hY, count, isDark) {
    var seed = 137;
    function rand() {
        seed = ((seed * 1664525) + 1013904223) & 0xffffffff;
        return (seed >>> 0) / 4294967296;
    }
    ctx.save();
    for (var i = 0; i < count; i++) {
        var sx = rand() * cw, sy = rand() * (hY - 14);
        var sr = rand() * 1.1 + 0.4, sal = rand() * 0.50 + 0.20;
        ctx.beginPath();
        ctx.arc(sx, sy, sr, 0, 2 * Math.PI);
        ctx.fillStyle = isDark ? "rgba(225,215,255," + sal + ")" : "rgba(100,75,180," + sal + ")";
        ctx.fill();
    }
    ctx.restore();
}

function drawMoonArc(ctx, cw, ch, prog, isDark, glowPulse, age) {
    ctx.clearRect(0, 0, cw, ch);

    // Guard: canvas not yet laid out — nothing useful to draw
    if (cw <= 0 || ch <= 0) return;

    var padH = 28, cx = cw / 2, hY = ch - 14;
    var r = Math.min(cx - padH, hY - 12);

    // Guard: canvas too narrow/short for a valid arc radius
    if (r <= 0) return;
    var isAbove = (prog >= 0 && prog <= 1);
    var clampP  = Math.max(0, Math.min(1, prog));
    var a = Math.PI * (1 + clampP);
    var bodyX = cx + r * Math.cos(a), bodyY = hY + r * Math.sin(a);

    // Sky
    var skyGrad = ctx.createLinearGradient(cx, hY - r, cx, hY);
    skyGrad.addColorStop(0,   isDark ? "rgba(25,15,55,0.42)" : "rgba(15,8,45,0.26)");
    skyGrad.addColorStop(0.6, isDark ? "rgba(20,12,48,0.15)" : "rgba(12,6,38,0.10)");
    skyGrad.addColorStop(1,   "rgba(0,0,0,0)");
    ctx.fillStyle = skyGrad;
    ctx.beginPath(); ctx.arc(cx, hY, r, Math.PI, 2 * Math.PI, false); ctx.closePath(); ctx.fill();
    _drawStars(ctx, cw, ch, hY, 28, isDark);

    // Illumination sky glow
    if (isAbove) {
        var illum = (1 - Math.cos((age / 29.53) * 2 * Math.PI)) / 2;
        var gAlpha = illum * (isDark ? 0.08 : 0.05);
        if (gAlpha > 0.01) {
            var sg = ctx.createRadialGradient(bodyX, bodyY, 0, bodyX, bodyY, r * 0.6);
            sg.addColorStop(0,   "rgba(180,150,255," + (gAlpha * 3).toFixed(3) + ")");
            sg.addColorStop(0.4, "rgba(150,120,230," + gAlpha.toFixed(3) + ")");
            sg.addColorStop(1,   "rgba(0,0,0,0)");
            ctx.fillStyle = sg;
            ctx.beginPath(); ctx.arc(cx, hY, r, Math.PI, 2 * Math.PI, false); ctx.closePath(); ctx.fill();
        }
    }

    // Arc
    if (isAbove) {
        if (clampP < 1) {
            ctx.save(); ctx.beginPath();
            ctx.arc(cx, hY, r, Math.PI * (1 + clampP), 2 * Math.PI, false);
            ctx.strokeStyle = isDark ? "rgba(190,155,255,0.22)" : "rgba(110,70,200,0.22)";
            ctx.lineWidth = 2; ctx.setLineDash([4, 7]); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
        }
        if (clampP > 0) {
            ctx.beginPath(); ctx.arc(cx, hY, r, Math.PI, Math.PI * (1 + clampP), false);
            ctx.strokeStyle = isDark ? "rgba(200,165,255,0.90)" : "rgba(120,80,215,0.90)";
            ctx.lineWidth = 2.5; ctx.stroke();
        }
    } else {
        ctx.save(); ctx.beginPath(); ctx.arc(cx, hY, r, Math.PI, 2 * Math.PI, false);
        ctx.strokeStyle = isDark ? "rgba(190,155,255,0.13)" : "rgba(110,70,200,0.13)";
        ctx.lineWidth = 1.5; ctx.setLineDash([4, 7]); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    }

    // Horizon
    ctx.beginPath(); ctx.moveTo(cx - r - 10, hY); ctx.lineTo(cx + r + 10, hY);
    ctx.strokeStyle = isDark ? "rgba(175,145,255,0.30)" : "rgba(100,65,195,0.30)";
    ctx.lineWidth = 1.5; ctx.stroke();
    [cx - r, cx + r].forEach(function(ex) {
        ctx.beginPath(); ctx.arc(ex, hY, 3.5, 0, 2 * Math.PI);
        ctx.fillStyle = isDark ? "rgba(175,145,255,0.50)" : "rgba(100,65,195,0.50)"; ctx.fill();
    });
    ctx.beginPath(); ctx.arc(cx, hY - r, 2.5, 0, 2 * Math.PI);
    ctx.fillStyle = isDark ? "rgba(200,170,255,0.28)" : "rgba(120,85,210,0.28)"; ctx.fill();

    // Glow
    var pulse = (glowPulse !== undefined) ? glowPulse : 0;
    var illumF = isAbove ? (1 - Math.cos((age / 29.53) * 2 * Math.PI)) / 2 : 0.3;
    var glowR  = 14 + illumF * 8 + pulse * 5;
    var glow = ctx.createRadialGradient(bodyX, bodyY, 0, bodyX, bodyY, glowR);
    glow.addColorStop(0,    isDark ? "rgba(220,200,255,0.80)" : "rgba(160,120,255,0.80)");
    glow.addColorStop(0.35, isDark ? "rgba(185,155,255,0.38)" : "rgba(120,80,220,0.38)");
    glow.addColorStop(0.70, isDark ? "rgba(155,120,245,0.14)" : "rgba(90,55,190,0.14)");
    glow.addColorStop(1,    "rgba(0,0,0,0)");
    ctx.fillStyle = glow; ctx.beginPath(); ctx.arc(bodyX, bodyY, glowR, 0, 2 * Math.PI); ctx.fill();

    // Moon body
    _drawMoonBody(ctx, bodyX, bodyY, 8, age, isDark);
}
