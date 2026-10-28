/*
 * Copyright 2026 Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of
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
 * spaceWeather.js - NOAA Space Weather Prediction Center helpers
 *
 * All logic is pure JS (no Qt / i18n) because this is a .pragma library.
 * Display strings for UI labels must be i18n'd in QML.
 *
 * Data sources (no API key required):
 *   Kp index  : https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json
 *   NOAA scales: https://services.swpc.noaa.gov/products/noaa-scales.json
 *   Solar wind: https://services.swpc.noaa.gov/products/summary/solar-wind-speed.json
 *   Bz        : https://services.swpc.noaa.gov/products/summary/solar-wind-mag-field.json
 *   X-ray flux: https://services.swpc.noaa.gov/json/goes/primary/xrays-1-day.json
 */

.pragma library

// No-op marker so xgettext can extract these strings (translated at runtime in QML).
function I18N_NOOP(s) { return s; }

// ─── Kp → Geomagnetic storm scale ────────────────────────────────────────────

/**
 * Converts a Kp index (0-9) to a NOAA G-scale string.
 *   Kp 5 → G1, 6 → G2, 7 → G3, 8 → G4, 9 → G5
 *   Below 5 → "G0" (no storm)
 * Kp is reported in thirds (5− = 4.67, 5o = 5.0, 5+ = 5.33), and NOAA counts
 * the "−" third toward the higher category (5.67 = 6− → G2), so thresholds
 * sit at n − 1/3. This matches the noaa_scale values in SWPC feeds.
 * Exception: G5 needs a full Kp 9 - a 9− (8.67) is still G4.
 */
function kpToGScale(kp) {
    if (isNaN(kp) || kp === null) return "G0";
    if (kp >= 9)    return "G5";
    if (kp >= 7.67) return "G4";
    if (kp >= 6.67) return "G3";
    if (kp >= 5.67) return "G2";
    if (kp >= 4.67) return "G1";
    return "G0";
}

/**
 * Returns a color for the G-scale level.
 */
function gScaleColor(gScale) {
    switch (gScale) {
        case "G5": return "#7B1FA2"; // deep purple
        case "G4": return "#D32F2F"; // dark red
        case "G3": return "#F44336"; // red
        case "G2": return "#FF9800"; // orange
        case "G1": return "#FFEB3B"; // yellow
        default:   return "#4CAF50"; // green - no storm
    }
}

/**
 * Returns a darker text-safe color for the G-scale level (light themes).
 */
function gScaleTextColor(gScale) {
    switch (gScale) {
        case "G5": return "#4A0072";
        case "G4": return "#7F0000";
        case "G3": return "#B71C1C";
        case "G2": return "#7A3500";
        case "G1": return "#5D4800";
        default:   return "#1B5E20";
    }
}

/**
 * Returns a description for the G-scale level.
 */
function gScaleDescription(gScale) {
    switch (gScale) {
        case "G5": return I18N_NOOP("Extreme geomagnetic storm.");
        case "G4": return I18N_NOOP("Severe geomagnetic storm.");
        case "G3": return I18N_NOOP("Strong geomagnetic storm.");
        case "G2": return I18N_NOOP("Moderate geomagnetic storm.");
        case "G1": return I18N_NOOP("Minor geomagnetic storm.");
        default:   return I18N_NOOP("No geomagnetic storm activity.");
    }
}

// ─── X-ray flux → Solar flare class ──────────────────────────────────────────

/**
 * Converts a GOES X-ray flux value (W/m²) to a flare class string.
 *   < 1e-8   → "A"
 *   < 1e-7   → "B"
 *   < 1e-6   → "C"
 *   < 1e-5   → "M"
 *   >= 1e-5  → "X"
 */
function getXrayClass(flux) {
    if (isNaN(flux) || flux === null || flux <= 0) return "--";
    if (flux < 1e-8) return "A";
    if (flux < 1e-7) return "B";
    if (flux < 1e-6) return "C";
    if (flux < 1e-5) return "M";
    return "X";
}

/**
 * Returns a full formatted class string with sub-index, e.g. "M2.3".
 */
function getXrayClassFull(flux) {
    if (isNaN(flux) || flux === null || flux <= 0) return "--";
    var cls, base;
    if (flux < 1e-8)      { cls = "A"; base = 1e-9; }
    else if (flux < 1e-7) { cls = "B"; base = 1e-8; }
    else if (flux < 1e-6) { cls = "C"; base = 1e-7; }
    else if (flux < 1e-5) { cls = "M"; base = 1e-6; }
    else                  { cls = "X"; base = 1e-5; }
    var sub = (flux / base);
    return cls + sub.toFixed(1);
}

/**
 * Returns a color for the X-ray class.
 */
function xrayClassColor(cls) {
    if (!cls || cls === "--") return "#4CAF50";
    var c = cls.charAt(0).toUpperCase();
    switch (c) {
        case "X": return "#D32F2F";
        case "M": return "#FF9800";
        case "C": return "#FFEB3B";
        case "B": return "#4CAF50";
        default:  return "#4CAF50";
    }
}

/**
 * Returns a darker text-safe color for the X-ray class (light themes).
 */
function xrayClassTextColor(cls) {
    if (!cls || cls === "--") return "#1B5E20";
    var c = cls.charAt(0).toUpperCase();
    switch (c) {
        case "X": return "#7F0000";
        case "M": return "#7A3500";
        case "C": return "#5D4800";
        case "B": return "#1B5E20";
        default:  return "#1B5E20";
    }
}

// ─── Text level descriptions (for UI labels) ──────────────────────────────────

/**
 * Returns a text level description for Kp index.
 * Levels: Quiet, Unsettled, Active, Minor Storm, Major Storm, Severe Storm
 */
function kpTextLevel(kp) {
    if (isNaN(kp)) return I18N_NOOP("--");
    if (kp >= 9)  return I18N_NOOP("Extreme");
    if (kp >= 7)  return I18N_NOOP("Strong");
    if (kp >= 5)  return I18N_NOOP("Storm");
    if (kp >= 4)  return I18N_NOOP("Active");
    if (kp >= 2)  return I18N_NOOP("Unsettled");
    return I18N_NOOP("Quiet");
}

/**
 * Returns a text level description for solar wind speed.
 * Levels: Low, Moderate, High, Extreme
 */
function solarWindTextLevel(speed) {
    if (isNaN(speed)) return I18N_NOOP("--");
    if (speed >= 800) return I18N_NOOP("Extreme");
    if (speed >= 600) return I18N_NOOP("High");
    if (speed >= 400) return I18N_NOOP("Moderate");
    return I18N_NOOP("Low");
}

/**
 * Returns a text level description for aurora visibility percent.
 * Levels: None, Low, Moderate, High, Excellent
 */
function auroraTextLevel(percent) {
    if (isNaN(percent)) return I18N_NOOP("--");
    if (percent >= 80) return I18N_NOOP("Excellent");
    if (percent >= 60) return I18N_NOOP("High");
    if (percent >= 30) return I18N_NOOP("Moderate");
    if (percent >= 10) return I18N_NOOP("Low");
    return I18N_NOOP("None");
}

// ─── Activity flags ───────────────────────────────────────────────────────────

/**
 * Returns an object with boolean activity flags for the current conditions.
 */
function activityFlags(data) {
    return {
        storm:           data.kp >= 5,
        activeBz:        data.bz < 0,
        elevatedWind:    data.solarWind > 500,
        flareWarning:    data.xrayClass === "M" || data.xrayClass === "X"
    };
}

// ─── Aurora probability ───────────────────────────────────────────────────────

/**
 * Calculates aurora visibility probability (0-100%) based on latitude, Kp,
 * and whether the sky is actually dark right now.
 *
 * Two things the old formula got wrong:
 *
 *   1. It had no darkness gate at all, so it happily reported "60% High"
 *      in broad daylight (it only looked at Kp + latitude). Aurora simply
 *      cannot be seen while the sun is up, during bright twilight, or
 *      during a high-latitude summer where the sky never gets properly
 *      dark ("night twilight" / white nights, e.g. northern Germany and
 *      further north). The caller MUST now pass `isDark` - ideally based
 *      on nautical/astronomical twilight (ex: suncalc's getTimes(), using
 *      the `night`/`nightEnd` fields, which come back invalid/NaN exactly
 *      when the sky never reaches real darkness that night) rather than
 *      plain sunrise/sunset, since simple civil sunset still leaves the
 *      sky too bright for aurora at those latitudes in summer. Falling
 *      back to the widget's existing isNightTime() is acceptable and
 *      already fixes the everyday case (e.g. reporting a % before local
 *      sunset), but will still be overly generous during high-latitude
 *      summer white nights.
 *
 *   2. Even ignoring darkness, the probability curve was far too
 *      generous: a flat "distance * 2.5" falloff let mid-latitudes (e.g.
 *      ~43-49°N) show 40-60% visibility at quiet, non-stormy Kp values,
 *      when realistically that requires a severe/extreme storm (Kp 7-9,
 *      G3+) and even then it's a rare, faint, horizon-hugging glow.
 *
 * The table below is the commonly used approximation for where the
 * auroral oval's equatorward edge sits (in geomagnetic latitude) at each
 * Kp step - much closer to reality than the old flat falloff, though
 * still a simplification of the real (and constantly shifting) OVATION
 * oval. Visibility is scaled steeply once you're equatorward of that
 * line, and only levels off once you're a few degrees poleward of it
 * (i.e. the oval is essentially overhead).
 *
 * Caveat: this widget only knows the observer's *geographic* latitude,
 * not geomagnetic latitude, so results are still an estimate - most
 * notably, geomagnetic latitude runs a few degrees below geographic
 * latitude across most of Europe. Good enough to stop reporting "high
 * chance of aurora" over Sofia on a quiet, sunlit summer evening, but
 * not a substitute for a real oval model.
 */
function auroraVisibilityPercent(kp, latitude, isDark) {
    if (isNaN(kp) || isNaN(latitude)) return 0;
    if (!isDark) return 0; // not dark (or never gets properly dark tonight) → not visible, full stop

    var absLat = Math.abs(latitude);

    // Equatorward boundary of the auroral oval (geomagnetic latitude),
    // indexed by integer Kp 0..9.
    var boundary = [66.5, 64.5, 62.4, 60.4, 58.3, 56.3, 54.2, 52.2, 50.1, 48.1];
    var kpClamped = Math.max(0, Math.min(9, kp));
    var lo = Math.floor(kpClamped);
    var hi = Math.min(9, lo + 1);
    var frac = kpClamped - lo;
    var boundaryLat = boundary[lo] + (boundary[hi] - boundary[lo]) * frac;

    // Positive = observer is poleward of the line (oval likely overhead);
    // negative = equatorward of it (oval is off on the horizon, or not
    // visible at all).
    var distance = absLat - boundaryLat;

    var visibility;
    if (distance >= 0) {
        visibility = 70 + Math.min(25, distance * 5);
    } else {
        // Steep falloff once equatorward of the line - a faint glow is
        // possible a few degrees out on an exceptionally clear night, but
        // realistically gone within ~10-15°.
        visibility = 70 * Math.exp(distance / 4);
    }

    return Math.round(Math.max(0, Math.min(95, visibility)));
}

// ─── Summary formatter ────────────────────────────────────────────────────────

/**
 * Builds a short one-line summary string (no i18n - done in QML).
 * Format: "Kp 3.3 · G0 · 420 km/s · Bz −4 nT · C2.1"
 */
function formatSpaceWeatherSummary(data) {
    if (!data) return "--";
    var parts = [];
    if (!isNaN(data.kp))         parts.push("Kp " + data.kp.toFixed(1));
    if (data.gScale)             parts.push(data.gScale);
    if (!isNaN(data.solarWind))  parts.push(Math.round(data.solarWind) + " km/s");
    if (!isNaN(data.bz))         parts.push("Bz " + (data.bz >= 0 ? "+" : "") + data.bz.toFixed(1) + " nT");
    if (data.xrayClassFull && data.xrayClassFull !== "--") parts.push(data.xrayClassFull);
    return parts.join(" · ");
}

/**
 * Returns the full structured space weather data object shape (defaults).
 * Providers populate this and store it on weatherRoot.spaceWeather.
 */
function emptyData() {
    return {
        kp:           NaN,
        gScale:       "G0",
        solarWind:    NaN,
        bz:           NaN,
        xrayClass:    "--",
        xrayClassFull: "--",
        summary:      "--"
    };
}
