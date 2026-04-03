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
 * spaceWeather.js — NOAA Space Weather Prediction Center helpers
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
 * Converts a Kp index (0–9) to a NOAA G-scale string.
 *   Kp 5 → G1, 6 → G2, 7 → G3, 8 → G4, 9 → G5
 *   Below 5 → "G0" (no storm)
 */
function kpToGScale(kp) {
    if (isNaN(kp) || kp === null) return "G0";
    if (kp >= 9) return "G5";
    if (kp >= 8) return "G4";
    if (kp >= 7) return "G3";
    if (kp >= 6) return "G2";
    if (kp >= 5) return "G1";
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
        default:   return "#4CAF50"; // green — no storm
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
 * Calculates aurora visibility probability (0–100%) based on latitude and Kp.
 * 
 * Aurora is more likely to be visible at higher latitudes.
 * Aurora oval at different Kp levels:
 *   Kp 0–2: ~67°+ (Arctic Circle)
 *   Kp 3–4: ~60–70°
 *   Kp 5–6: ~50–65°
 *   Kp 7–8: ~40–55°
 *   Kp 9:   ~30–50° (extreme storms)
 *
 * Formula: considers both latitude proximity and Kp magnitude.
 */
function auroraVisibilityPercent(kp, latitude) {
    if (isNaN(kp) || isNaN(latitude)) return 0;
    var absLat = Math.abs(latitude);
    
    // Kp determines the latitude threshold for aurora visibility
    var aurovalLat = 65 - (kp / 2);  // Higher Kp shifts aurora south
    if (kp >= 9) aurovalLat = 30;    // Extreme storms reach equator
    
    // Probability increases when observer is within ~20° of the auroral oval
    var distance = Math.abs(absLat - aurovalLat);
    var visibility = Math.max(0, 100 - (distance * 2.5));
    
    // Ensure minimum visibility if Kp is high enough
    if (kp >= 7 && absLat >= 40) visibility = Math.max(visibility, 50);
    if (kp >= 8 && absLat >= 35) visibility = Math.max(visibility, 60);
    if (kp >= 9 && absLat >= 30) visibility = Math.max(visibility, 70);
    
    return Math.round(visibility);
}

// ─── Summary formatter ────────────────────────────────────────────────────────

/**
 * Builds a short one-line summary string (no i18n — done in QML).
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
