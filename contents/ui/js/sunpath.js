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
 * sunpath.js — Sun/Moon arc geometry, progress and daylight helpers
 *
 * Canvas coordinate convention (y-axis points DOWN):
 *
 *   DAY arc  — sun travels CLOCKWISE from left horizon to right:
 *     angle π  (left)  →  3π/2 (top, noon)  →  2π (right)
 *     sunX = cx + r·cos(π(1+p))
 *     sunY = hY + r·sin(π(1+p))   sin(3π/2)=-1 ⟹ above hY ✓
 *
 *   NIGHT arc — moon travels from right horizon over top to left:
 *     moonX = cx + r·cos(m·π)        m=0: right ✓  m=0.5: centre ✓  m=1: left ✓
 *     moonY = hY - r·sin(m·π)        sin(π/2)=1 ⟹ above hY ✓
 *     Equivalent canvas angle = 2π - m·π  (clockwise arc from 2π down to π)
 */

.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// Core helpers
// ─────────────────────────────────────────────────────────────────────────────

function parseMins(t) {
    if (!t || t === "--") return -1;
    var p = t.split(":");
    if (p.length < 2) return -1;
    var h = parseInt(p[0], 10), m = parseInt(p[1], 10);
    if (isNaN(h) || isNaN(m)) return -1;
    return h * 60 + m;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sun / day progress
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 0.0 = sunrise  0.5 = solar noon  1.0 = sunset
 * < 0  before sunrise              > 1  after sunset
 */
/**
 * Get current minutes-since-midnight at the weather location.
 *
 * Uses UTC + the location's UTC offset (in minutes) from the API response.
 * This is the ONLY approach that works reliably in Qt's V4 JS engine —
 * toLocaleTimeString/Intl.DateTimeFormat with a timeZone option are NOT
 * supported by Qt's V4 and always fall back to machine local time.
 *
 * utcOffsetMins: location's UTC offset in minutes (e.g. -420 for UTC-7).
 *   Pass 0 / undefined to fall back to machine local time.
 */
function nowMinsAt(utcOffsetMins) {
    var d = new Date();
    if (utcOffsetMins === undefined || utcOffsetMins === null || isNaN(utcOffsetMins)) {
        return d.getHours() * 60 + d.getMinutes();
    }
    var utcMins = d.getUTCHours() * 60 + d.getUTCMinutes();
    return ((utcMins + utcOffsetMins) % 1440 + 1440) % 1440;  // always positive
}

function sunProgress(riseText, setText, tz) {
    var rise = parseMins(riseText);
    var set  = parseMins(setText);
    if (rise < 0 || set < 0 || set <= rise) return 0.5;
    var now = nowMinsAt(tz);
    return (now - rise) / (set - rise);
}

// ─────────────────────────────────────────────────────────────────────────────
// Moon / night progress
// ─────────────────────────────────────────────────────────────────────────────

function nightLengthMins(riseText, setText) {
    var rise = parseMins(riseText);
    var set  = parseMins(setText);
    if (rise < 0 || set < 0) return 720;
    var total = rise + (1440 - set);
    return total > 0 ? total : 720;
}

/**
 * 0.0 = sunset (right)  0.5 = lunar midnight (top)  1.0 = next sunrise (left)
 */
function moonProgress(riseText, setText, tz) {
    var rise = parseMins(riseText);
    var set  = parseMins(setText);
    if (rise < 0 || set < 0) return 0.5;
    var now      = nowMinsAt(tz);
    var nightLen = nightLengthMins(riseText, setText);
    var minsIn   = (now >= set) ? (now - set) : (1440 - set + now);
    return Math.max(0, Math.min(1, minsIn / nightLen));
}

function minsUntilSunrise(riseText, setText, tz) {
    var rise = parseMins(riseText);
    if (rise < 0) return 0;
    var now = nowMinsAt(tz);
    if (now < rise) return rise - now;
    var set = parseMins(setText);
    if (set < 0 || now < set) return 0;
    return (1440 - now) + rise;
}

// ─────────────────────────────────────────────────────────────────────────────
// Daylight durations
// ─────────────────────────────────────────────────────────────────────────────

function dayLengthMins(riseText, setText) {
    var rise = parseMins(riseText);
    var set  = parseMins(setText);
    if (rise < 0 || set < 0 || set <= rise) return 0;
    return set - rise;
}

function remainingMins(riseText, setText, tz) {
    var set = parseMins(setText);
    if (set < 0) return 0;
    var now = nowMinsAt(tz);
    return Math.max(0, set - now);
}

function formatDuration(totalMins) {
    if (totalMins <= 0) return "0m";
    var h = Math.floor(totalMins / 60);
    var m = totalMins % 60;
    if (h === 0) return m + "m";
    if (m === 0) return h + "h";
    return h + "h " + m + "m";
}

/**
 * Return a phase label for the current point in the night.
 *   mProg: moonProgress() value 0..1
 *   minsUntil: minutes until sunrise
 */
function nightPhaseLabel(mProg, minsUntil) {
    if (minsUntil <= 0)   return "dawn";        // shouldn't happen but safe
    if (minsUntil <= 30)  return "approaching";  // < 30 min to sunrise
    if (mProg < 0.30)     return "evening";      // first ~30% of night
    if (mProg < 0.55)     return "midnight";     // around midnight
    return "late";                               // second half, not yet near dawn
}

// ─────────────────────────────────────────────────────────────────────────────
// Canvas drawing helpers
// ─────────────────────────────────────────────────────────────────────────────

function _drawMoon(ctx, mx, my, OR, isDark) {
    var IR     = OR * 0.70;
    var offset = OR * 0.55;

    // Outer disc
    ctx.save();
    ctx.beginPath();
    ctx.arc(mx, my, OR, 0, 2 * Math.PI);
    ctx.fillStyle = isDark ? "#f0c0dc" : "#c06090";
    ctx.fill();

    // Crescent cutout
    ctx.globalCompositeOperation = "destination-out";
    ctx.beginPath();
    ctx.arc(mx + offset, my, IR, 0, 2 * Math.PI);
    ctx.fill();
    ctx.restore();

    // Bright rim
    ctx.save();
    ctx.beginPath();
    ctx.arc(mx, my, OR, Math.PI * 0.35, Math.PI * 1.65, false);
    ctx.strokeStyle = isDark ? "rgba(255,230,240,0.65)" : "rgba(220,150,190,0.65)";
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.restore();
}

function _drawStars(ctx, cw, ch, hY, count, isDark) {
    var seed = 42;
    function rand() {
        seed = ((seed * 1664525) + 1013904223) & 0xffffffff;
        return (seed >>> 0) / 4294967296;
    }
    ctx.save();
    for (var i = 0; i < count; i++) {
        var sx  = rand() * cw;
        var sy  = rand() * (hY - 14);
        var sr  = rand() * 1.1 + 0.45;
        var sal = rand() * 0.50 + 0.22;
        ctx.beginPath();
        ctx.arc(sx, sy, sr, 0, 2 * Math.PI);
        ctx.fillStyle = isDark
            ? "rgba(255,215,235," + sal + ")"
            : "rgba(160,50,100," + sal + ")";
        ctx.fill();
    }
    ctx.restore();
}

// ─────────────────────────────────────────────────────────────────────────────
// Main draw entry-point
// ─────────────────────────────────────────────────────────────────────────────

/**
 * drawSunArc(ctx, cw, ch, prog, isDark, glowPulse, riseText, setText)
 *
 *   ctx       — canvas 2D context
 *   cw, ch    — canvas width / height
 *   prog      — raw sunProgress() value (< 0 or > 1 means night)
 *   isDark    — true for dark KDE theme
 *   glowPulse — animated 0→1→0 value for glow breathing (pass 0 if unused)
 *   riseText  — "HH:mm" sunrise string
 *   setText   — "HH:mm" sunset string
 */
/**
 * isNight — explicit flag from the API's is_day field (via weatherRoot.isNightTime()).
 *           Overrides the prog-based calculation so day/night is always correct
 *           regardless of machine timezone vs location timezone.
 */
function drawSunArc(ctx, cw, ch, prog, isDark, glowPulse, riseText, setText, tz, isNight) {
    ctx.clearRect(0, 0, cw, ch);

    // Guard: canvas not yet laid out — nothing useful to draw
    if (cw <= 0 || ch <= 0) return;

    var padH  = 28;
    var cx    = cw / 2;
    var hY    = ch - 14;
    var r     = Math.min(cx - padH, hY - 12);

    // Guard: canvas too narrow/short for a valid arc radius
    if (r <= 0) return;

    // isNight comes from the API's is_day flag — authoritative for this location.
    // prog is clamped independently: at night it drives moon arc position.
    var isDay    = (isNight !== undefined && isNight !== null) ? !isNight : (prog >= 0 && prog <= 1);
    var clampDay = Math.max(0, Math.min(1, prog));
    var mProg    = isDay ? 0 : moonProgress(riseText, setText, tz);

    // Active body position
    var bodyX, bodyY;
    if (isDay) {
        var a = Math.PI * (1 + clampDay);
        bodyX = cx + r * Math.cos(a);
        bodyY = hY + r * Math.sin(a);           // sin(3π/2) = -1 ⟹ above hY
    } else {
        bodyX = cx + r * Math.cos(mProg * Math.PI);
        bodyY = hY - r * Math.sin(mProg * Math.PI);
    }

    // ── 1. Sky tint ────────────────────────────────────────────────────────
    var tintGrad = ctx.createLinearGradient(cx, hY - r, cx, hY);
    if (isDay) {
        tintGrad.addColorStop(0,   isDark ? "rgba(255,175,50,0.16)" : "rgba(255,140,0,0.11)");
        tintGrad.addColorStop(0.7, isDark ? "rgba(255,150,30,0.05)" : "rgba(255,130,0,0.03)");
        tintGrad.addColorStop(1,   "rgba(0,0,0,0)");
    } else {
        tintGrad.addColorStop(0,   isDark ? "rgba(60,20,110,0.40)" : "rgba(40,10,80,0.24)");
        tintGrad.addColorStop(0.6, isDark ? "rgba(50,15,100,0.14)" : "rgba(35,8,70,0.09)");
        tintGrad.addColorStop(1,   "rgba(0,0,0,0)");
        _drawStars(ctx, cw, ch, hY, 30, isDark);
    }
    ctx.fillStyle = tintGrad;
    ctx.beginPath();
    ctx.arc(cx, hY, r, Math.PI, 2 * Math.PI, false);
    ctx.closePath();
    ctx.fill();

    // ── 2. Arc track ──────────────────────────────────────────────────────
    if (isDay) {
        // Future (dashed gold)
        if (clampDay < 1) {
            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, hY, r, Math.PI * (1 + clampDay), 2 * Math.PI, false);
            ctx.strokeStyle = isDark ? "rgba(255,185,60,0.22)" : "rgba(195,118,0,0.22)";
            ctx.lineWidth = 2;
            ctx.setLineDash([4, 7]);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.restore();
        }
        // Traveled (solid gold)
        if (clampDay > 0) {
            ctx.beginPath();
            ctx.arc(cx, hY, r, Math.PI, Math.PI * (1 + clampDay), false);
            ctx.strokeStyle = isDark ? "rgba(255,205,72,0.92)" : "rgba(218,138,0,0.92)";
            ctx.lineWidth = 2.5;
            ctx.stroke();
        } else {
            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, hY, r, Math.PI, 2 * Math.PI, false);
            ctx.strokeStyle = isDark ? "rgba(255,185,60,0.13)" : "rgba(195,118,0,0.13)";
            ctx.lineWidth = 1.5;
            ctx.setLineDash([4, 7]);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.restore();
        }
    } else {
        // Night — moon travels from canvas angle 2π (right) down to π (left)
        // Traveled: from 2π - mProg*π to 2π  (clockwise)
        if (mProg > 0) {
            ctx.beginPath();
            ctx.arc(cx, hY, r, 2 * Math.PI - mProg * Math.PI, 2 * Math.PI, false);
            ctx.strokeStyle = isDark ? "rgba(255,160,210,0.90)" : "rgba(185,50,110,0.90)";
            ctx.lineWidth = 2.5;
            ctx.stroke();
        }
        // Remaining: from π to 2π - mProg*π  (clockwise)
        if (mProg < 1) {
            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, hY, r, Math.PI, 2 * Math.PI - mProg * Math.PI, false);
            ctx.strokeStyle = isDark ? "rgba(255,160,210,0.22)" : "rgba(185,50,110,0.22)";
            ctx.lineWidth = 2;
            ctx.setLineDash([4, 7]);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.restore();
        }
        if (mProg === 0) {
            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, hY, r, Math.PI, 2 * Math.PI, false);
            ctx.strokeStyle = isDark ? "rgba(255,160,210,0.13)" : "rgba(185,50,110,0.13)";
            ctx.lineWidth = 1.5;
            ctx.setLineDash([4, 7]);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.restore();
        }
    }

    // ── 3. Horizon ────────────────────────────────────────────────────────
    var hCol = isDay
        ? (isDark ? "rgba(255,195,65,0.30)" : "rgba(195,118,0,0.30)")
        : (isDark ? "rgba(125,158,255,0.30)" : "rgba(55,85,205,0.30)");
    ctx.beginPath();
    ctx.moveTo(cx - r - 10, hY);
    ctx.lineTo(cx + r + 10, hY);
    ctx.strokeStyle = hCol;
    ctx.lineWidth = 1.5;
    ctx.stroke();

    var capCol = isDay
        ? (isDark ? "rgba(255,195,65,0.52)" : "rgba(195,118,0,0.52)")
        : (isDark ? "rgba(125,158,255,0.52)" : "rgba(55,85,205,0.52)");
    [cx - r, cx + r].forEach(function(ex) {
        ctx.beginPath();
        ctx.arc(ex, hY, 3.5, 0, 2 * Math.PI);
        ctx.fillStyle = capCol;
        ctx.fill();
    });

    // Noon/midnight tick
    ctx.beginPath();
    ctx.arc(cx, hY - r, 2.5, 0, 2 * Math.PI);
    ctx.fillStyle = isDay
        ? (isDark ? "rgba(255,215,80,0.28)" : "rgba(210,138,0,0.28)")
        : (isDark ? "rgba(155,185,255,0.28)" : "rgba(55,85,205,0.28)");
    ctx.fill();

    // ── 4. Glow (breathing via glowPulse) ────────────────────────────────
    var pulse  = (glowPulse !== undefined) ? glowPulse : 0;
    var baseG  = isDay ? 20 : 17;
    var glowR  = baseG + pulse * 6;

    var glow = ctx.createRadialGradient(bodyX, bodyY, 0, bodyX, bodyY, glowR);
    if (isDay) {
        glow.addColorStop(0,    "rgba(255,242,135,0.90)");
        glow.addColorStop(0.30, "rgba(255,198,62,0.50)");
        glow.addColorStop(0.65, "rgba(255,158,22,0.18)");
        glow.addColorStop(1,    "rgba(0,0,0,0)");
    } else {
        glow.addColorStop(0,    isDark ? "rgba(255,170,220,0.72)" : "rgba(210,90,150,0.72)");
        glow.addColorStop(0.40, isDark ? "rgba(220,130,200,0.28)" : "rgba(175,60,120,0.28)");
        glow.addColorStop(1,    "rgba(0,0,0,0)");
    }
    ctx.fillStyle = glow;
    ctx.beginPath();
    ctx.arc(bodyX, bodyY, glowR, 0, 2 * Math.PI);
    ctx.fill();

    // ── 5. Sun or Moon body ───────────────────────────────────────────────
    if (isDay) {
        ctx.beginPath();
        ctx.arc(bodyX, bodyY, 8, 0, 2 * Math.PI);
        ctx.fillStyle = isDark ? "#ffe07a" : "#ffcb1a";
        ctx.fill();
        ctx.beginPath();
        ctx.arc(bodyX, bodyY, 5, 0, 2 * Math.PI);
        ctx.fillStyle = "#ffffff";
        ctx.fill();
    } else {
        _drawMoon(ctx, bodyX, bodyY, 8, isDark);
    }
}
