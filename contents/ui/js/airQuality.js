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
 * airQuality.js - Air-quality index helpers for all three standards the
 * widget can display: European CAQI, US EPA AQI, and Canadian AQHI.
 *
 * ── European CAQI / Open-Meteo european_aqi scale ─────────────────────────
 * Official EEA thresholds, using the bands revised in 2024:
 * https://airindex.eea.europa.eu/AQI/index.html
 *   0-20   Good
 *   20-40  Fair
 *   40-60  Moderate
 *   60-80  Poor
 *   80-100 Very Poor
 *   >100   Extremely Poor (open-ended - the EEA scale has no fixed ceiling)
 *
 * Per-pollutant sub-index breakpoints follow the same 2024-revised EEA
 * specification (hourly concentrations, µg/m³) → sub-index 0-100:
 *   PM2.5: 5 / 15 / 50 / 90 / 140
 *   PM10:  15 / 45 / 120 / 195 / 270
 *   NO2:   10 / 25 / 60 / 100 / 150
 *   O3:    60 / 100 / 120 / 160 / 180
 *   SO2:   20 / 40 / 125 / 190 / 275
 * CO has no entry: it is not one of the EEA's five index pollutants, so
 * there is no official EU sub-index to interpolate - its concentration is
 * still shown, just without a fabricated color band.
 *
 * ── US EPA Air Quality Index (0-500) ───────────────────────────────────────
 * https://document.airnow.gov/technical-assistance-document-for-the-reporting-of-daily-air-quailty.pdf
 * Open-Meteo computes this for us (its own NowCast/rolling-average math per
 * pollutant), so this file only needs the six headline bands for labeling.
 *
 * ── Canadian Air Quality Health Index (1-10+) ─────────────────────────────
 * Health Canada's published formula, computed from 3-hour moving averages
 * of NO2, O3 (ppb) and PM2.5 (µg/m³) - see aqhiFromPollutants() below.
 * https://www.canada.ca/en/environment-climate-change/services/air-quality-health-index/about.html
 */

.pragma library

// No-op marker so xgettext can extract these strings (translated at runtime in QML).
function I18N_NOOP(s) { return s; }

// ─── Region → standard resolution ────────────────────────────────────────
// Official EEA European Air Quality Index coverage: EU-27 + EEA (Iceland,
// Liechtenstein, Norway) + United Kingdom + Switzerland.
var EEA_COUNTRIES = [
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR",
    "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
    "SI", "ES", "SE", "IS", "LI", "NO", "GB", "CH"
];

/**
 * Resolves which air-quality standard to display for a location.
 *   countryCode: ISO 3166-1 alpha-2, e.g. "US", "CA", "DE" (from
 *                Plasmoid.configuration.countryCode)
 *   override:    "auto" | "us" | "eu" | "ca" (from
 *                Plasmoid.configuration.aqiStandard)
 * Returns "us" | "eu" | "ca". The global default - used for the USA, South
 * America, Africa, Asia, and anywhere else not covered by the two regional
 * standards below (including an unresolved/empty country code) - is US AQI.
 */
function resolveStandard(countryCode, override) {
    if (override === "us" || override === "eu" || override === "ca")
        return override;
    var cc = (countryCode || "").trim().toUpperCase();
    if (cc === "CA") return "ca";
    if (EEA_COUNTRIES.indexOf(cc) >= 0) return "eu";
    return "us";
}

// ─── European CAQI band definitions ──────────────────────────────────────

var BANDS = [
    { max: 20,  label: I18N_NOOP("Good"),           shortLabel: I18N_NOOP("Good"),     color: "#4CAF50", textColor: "#1B5E20", emoji: "\u{1F7E2}", description: I18N_NOOP("Air quality is satisfactory.") },
    { max: 40,  label: I18N_NOOP("Fair"),           shortLabel: I18N_NOOP("Fair"),     color: "#CDDC39", textColor: "#4E6B00", emoji: "\u{1F7E1}", description: I18N_NOOP("Air quality is acceptable.") },
    { max: 60,  label: I18N_NOOP("Moderate"),       shortLabel: I18N_NOOP("Moderate"), color: "#FF9800", textColor: "#7A3500", emoji: "\u{1F7E0}", description: I18N_NOOP("Air quality is fair.") },
    { max: 80,  label: I18N_NOOP("Poor"),           shortLabel: I18N_NOOP("Poor"),     color: "#F44336", textColor: "#7F0000", emoji: "\u{1F534}", description: I18N_NOOP("Air quality is poor.") },
    { max: 100, label: I18N_NOOP("Very Poor"),      shortLabel: I18N_NOOP("V.Poor"),   color: "#9C27B0", textColor: "#4A0072", emoji: "\u{1F7E3}", description: I18N_NOOP("Air quality is very poor.") },
    { max: 9999,label: I18N_NOOP("Extremely Poor"), shortLabel: I18N_NOOP("Extreme"),  color: "#7B1FA2", textColor: "#1A002A", emoji: "\u{1F7E4}", description: I18N_NOOP("Air quality is extremely poor.") }
];

// ─── US EPA AQI band definitions (0-500) ─────────────────────────────────
// Official colors from the EPA's published AQI scale.

var US_BANDS = [
    { max: 50,  label: I18N_NOOP("Good"),                           shortLabel: I18N_NOOP("Good"),        color: "#00E400", textColor: "#0B4D00", emoji: "\u{1F7E2}", description: I18N_NOOP("Air quality is satisfactory, and air pollution poses little or no risk.") },
    { max: 100, label: I18N_NOOP("Moderate"),                       shortLabel: I18N_NOOP("Moderate"),    color: "#FFFF00", textColor: "#6B6B00", emoji: "\u{1F7E1}", description: I18N_NOOP("Air quality is acceptable; there may be a risk for people unusually sensitive to air pollution.") },
    { max: 150, label: I18N_NOOP("Unhealthy for Sensitive Groups"), shortLabel: I18N_NOOP("USG"),         color: "#FF7E00", textColor: "#7A3D00", emoji: "\u{1F7E0}", description: I18N_NOOP("Members of sensitive groups may experience health effects; the general public is less likely to be affected.") },
    { max: 200, label: I18N_NOOP("Unhealthy"),                      shortLabel: I18N_NOOP("Unhealthy"),   color: "#FF0000", textColor: "#7F0000", emoji: "\u{1F534}", description: I18N_NOOP("Everyone may begin to experience health effects; sensitive groups may experience more serious effects.") },
    { max: 300, label: I18N_NOOP("Very Unhealthy"),                 shortLabel: I18N_NOOP("V.Unhealthy"), color: "#8F3F97", textColor: "#3D1A40", emoji: "\u{1F7E3}", description: I18N_NOOP("Health alert: everyone may experience more serious health effects.") },
    { max: 9999,label: I18N_NOOP("Hazardous"),                      shortLabel: I18N_NOOP("Hazardous"),   color: "#7E0023", textColor: "#2A000B", emoji: "\u{1F7E4}", description: I18N_NOOP("Health warning of emergency conditions: everyone is more likely to be affected.") }
];

function bandForUsAqi(aqi) {
    if (isNaN(aqi) || aqi === null) return US_BANDS[0];
    for (var i = 0; i < US_BANDS.length; i++)
        if (aqi <= US_BANDS[i].max) return US_BANDS[i];
    return US_BANDS[US_BANDS.length - 1];
}

// ─── Canadian AQHI (1-10+) ────────────────────────────────────────────────

var AQHI_BANDS = [
    { max: 3,    label: I18N_NOOP("Low Risk"),       shortLabel: I18N_NOOP("Low"),      color: "#00CCFF", textColor: "#004D66", emoji: "\u{1F535}", description: I18N_NOOP("Ideal air quality for outdoor activities.") },
    { max: 6,    label: I18N_NOOP("Moderate Risk"),  shortLabel: I18N_NOOP("Moderate"), color: "#FFCC00", textColor: "#665200", emoji: "\u{1F7E1}", description: I18N_NOOP("Consider reducing or rescheduling strenuous outdoor activities if you experience symptoms such as coughing or throat irritation.") },
    { max: 10,   label: I18N_NOOP("High Risk"),      shortLabel: I18N_NOOP("High"),     color: "#FF6600", textColor: "#662900", emoji: "\u{1F7E0}", description: I18N_NOOP("Reduce or reschedule strenuous outdoor activities, especially if you experience symptoms.") },
    { max: 9999, label: I18N_NOOP("Very High Risk"), shortLabel: I18N_NOOP("V.High"),   color: "#CC0033", textColor: "#4D0013", emoji: "\u{1F534}", description: I18N_NOOP("Avoid strenuous outdoor activities.") }
];

function bandForAqhi(aqhi) {
    if (isNaN(aqhi) || aqhi === null) return AQHI_BANDS[0];
    for (var i = 0; i < AQHI_BANDS.length; i++)
        if (aqhi <= AQHI_BANDS[i].max) return AQHI_BANDS[i];
    return AQHI_BANDS[AQHI_BANDS.length - 1];
}

// Molar masses (g/mol) for the two AQHI gases that need µg/m³ → ppb conversion.
var _AQHI_MOLAR_MASS = { no2: 46.01, o3: 48.00 };

/**
 * Converts a µg/m³ concentration to ppb for "no2" or "o3", using the
 * standard conversion at 25°C / 1 atm: ppb = µg/m³ × 24.45 / molar mass.
 */
function ugm3ToPpb(ugm3, pollutant) {
    var m = _AQHI_MOLAR_MASS[pollutant];
    if (!m || ugm3 === null || ugm3 === undefined || isNaN(ugm3)) return NaN;
    return ugm3 * 24.45 / m;
}

/**
 * Computes the genuine Health Canada AQHI from 3-hour moving averages:
 *   AQHI = (10/10.4) × 100 × [(e^(0.000871·NO2) − 1) + (e^(0.000537·O3) − 1) + (e^(0.000487·PM2.5) − 1)]
 * NO2 and O3 must be in ppb; PM2.5 in µg/m³. Reported values are never
 * below 1. Returns NaN if any input is missing - round the result for
 * display.
 */
function aqhiFromPollutants(no2Ppb, o3Ppb, pm25) {
    if (isNaN(no2Ppb) || isNaN(o3Ppb) || isNaN(pm25)) return NaN;
    var risk = (Math.exp(0.000871 * no2Ppb) - 1)
             + (Math.exp(0.000537 * o3Ppb)  - 1)
             + (Math.exp(0.000487 * pm25)   - 1);
    return Math.max(1, (10 / 10.4) * 100 * risk);
}

/**
 * Returns { value, band, standardLabel } for the active standard, given the
 * raw values stored on aqiData. `value` is unrounded - round for display.
 * `standardLabel` is I18N_NOOP-wrapped like the band labels; wrap it in
 * i18n() at the call site.
 */
function standardDisplay(standard, europeanAqi, usAqi, aqhi) {
    if (standard === "us")
        return { value: usAqi, band: bandForUsAqi(usAqi), standardLabel: I18N_NOOP("AQI") };
    if (standard === "ca")
        return { value: aqhi, band: bandForAqhi(aqhi), standardLabel: I18N_NOOP("AQHI") };
    return { value: europeanAqi, band: bandForIndex(europeanAqi), standardLabel: I18N_NOOP("CAQI") };
}

// ─── Per-pollutant breakpoints (European CAQI sub-index bars) ───────────────
// Each entry: [c1, c2, c3, c4, c5] concentrations mapping to sub-index
// 0→0, c1→20, c2→40, c3→60, c4→80, c5→100, beyond c5→ open-ended (see
// subIndex() below - the EEA scale itself has no fixed ceiling past 100).

var POLLUTANT_BREAKS = {
    pm2_5: [5,   15,   50,   90,  140],
    pm10:  [15,  45,  120,  195,  270],
    no2:   [10,  25,   60,  100,  150],
    o3:    [60, 100,  120,  160,  180],
    so2:   [20,  40,  125,  190,  275]
    // co intentionally omitted - see file header.
};

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Returns the band object for a given European AQI value (0-100+).
 */
function bandForIndex(aqi) {
    if (isNaN(aqi) || aqi === null) return BANDS[0];
    for (var i = 0; i < BANDS.length; i++) {
        if (aqi < BANDS[i].max) return BANDS[i];
    }
    return BANDS[BANDS.length - 1];
}

/**
 * Returns { label, color, textColor, description } for a given AQI.
 */
function infoForIndex(aqi) {
    return bandForIndex(aqi);
}

/**
 * Returns the EU AQI color hex string for an index value.
 */
function colorForIndex(aqi) {
    return bandForIndex(aqi).color;
}

/**
 * Returns the label string ("Good", "Fair", etc.) for an index value.
 */
function labelForIndex(aqi) {
    return bandForIndex(aqi).label;
}

/**
 * Computes a 0-100+ sub-index for a pollutant concentration, on the same
 * scale as the consolidated European AQI (BANDS above).
 *
 * @param {string} pollutant  Key in POLLUTANT_BREAKS: "pm2_5", "pm10", "no2", "o3", "so2"
 * @param {number} value      Concentration in µg/m³
 * @returns {number}          Sub-index >= 0, or NaN if input is NaN or the
 *                             pollutant has no EEA breakpoint table (co)
 */
function subIndex(pollutant, value) {
    if (isNaN(value) || value === null || value === undefined) return NaN;
    var breaks = POLLUTANT_BREAKS[pollutant];
    if (!breaks) return NaN;

    // Linear interpolation between band boundaries
    // Band 0: 0  → 20  (concentration 0 → breaks[0])
    // Band 1: 20 → 40  (breaks[0] → breaks[1])
    // Band 2: 40 → 60  (breaks[1] → breaks[2])
    // Band 3: 60 → 80  (breaks[2] → breaks[3])
    // Band 4: 80 → 100 (breaks[3] → breaks[4])
    // Band 5: >breaks[4] → open-ended; extrapolated at the same slope as
    //         the 80→100 segment rather than an arbitrary cap, since the
    //         EEA scale itself has no fixed ceiling here (the display bar
    //         still clamps visually at 100% via scalePercent()).

    var cLo, cHi, iLo, iHi;
    if (value <= 0)           return 0;
    if (value <= breaks[0]) { cLo = 0;          cHi = breaks[0]; iLo = 0;  iHi = 20; }
    else if (value <= breaks[1]) { cLo = breaks[0]; cHi = breaks[1]; iLo = 20; iHi = 40; }
    else if (value <= breaks[2]) { cLo = breaks[1]; cHi = breaks[2]; iLo = 40; iHi = 60; }
    else if (value <= breaks[3]) { cLo = breaks[2]; cHi = breaks[3]; iLo = 60; iHi = 80; }
    else if (value <= breaks[4]) { cLo = breaks[3]; cHi = breaks[4]; iLo = 80; iHi = 100; }
    else {
        var slope = 20 / (breaks[4] - breaks[3]);
        return 100 + (value - breaks[4]) * slope;
    }

    return iLo + (value - cLo) / (cHi - cLo) * (iHi - iLo);
}

/**
 * Returns the band for a pollutant sub-index value.
 */
function bandForSubIndex(si) {
    return bandForIndex(si);
}

/**
 * Returns a percentage (0-100) for positioning on a scale bar.
 */
function scalePercent(value, maxScale) {
    var scale = maxScale || 100;
    return Math.min(100, Math.max(0, value / scale * 100));
}

/**
 * Returns the English unit-label key for a pollutant key; wrap in i18n() before display.
 */
function unitFor(pollutant) {
    if (pollutant === "co") return I18N_NOOP("mg/m³");
    return I18N_NOOP("µg/m³");
}
