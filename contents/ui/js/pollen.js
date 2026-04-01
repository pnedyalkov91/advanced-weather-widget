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
 * pollen.js — Universal Pollen Index (UPI) helpers
 *
 * Scale 0–12:
 *   0–2.4   Low       Minimal to no risk
 *   2.5–4.8 Moderate  Mild symptoms in highly sensitive individuals
 *   4.9–7.2 High      Most allergy sufferers will experience discomfort
 *   7.3–12  Very High Serious risk; avoid outdoor activities
 *
 * Supported pollen types (Open-Meteo air-quality API):
 *   alder, birch, grass, mugwort, olive, ragweed
 *
 * Note: pollen type display names are i18n'd in QML (not here) because
 * .pragma library JS cannot call i18n().
 */

.pragma library

// No-op marker so xgettext can extract these strings (translated at runtime in QML).
function I18N_NOOP(s) { return s; }

// ─── Band definitions ─────────────────────────────────────────────────────────

var BANDS = [
    { maxExclusive: 2.5,  label: I18N_NOOP("Low"),       color: "#4CAF50", textColor: "#1B5E20", description: I18N_NOOP("Minimal to no risk.") },
    { maxExclusive: 4.9,  label: I18N_NOOP("Moderate"),  color: "#FFEB3B", textColor: "#5D4800", description: I18N_NOOP("Mild symptoms in highly sensitive individuals.") },
    { maxExclusive: 7.3,  label: I18N_NOOP("High"),      color: "#FF9800", textColor: "#7A3500", description: I18N_NOOP("Most allergy sufferers will experience discomfort.") },
    { maxExclusive: 99,   label: I18N_NOOP("Very High"), color: "#F44336", textColor: "#7F0000", description: I18N_NOOP("Serious risk; avoid outdoor activities.") }
];

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Returns the band object for a UPI value (0–12).
 */
function bandForValue(v) {
    if (isNaN(v) || v === null || v === undefined) return BANDS[0];
    for (var i = 0; i < BANDS.length; i++) {
        if (v < BANDS[i].maxExclusive) return BANDS[i];
    }
    return BANDS[BANDS.length - 1];
}

/**
 * Returns colour hex for a UPI value.
 */
function colorForValue(v) {
    return bandForValue(v).color;
}

/**
 * Returns label string ("Low", "Moderate", etc.) for a UPI value.
 */
function labelForValue(v) {
    return bandForValue(v).label;
}

/**
 * Returns a fill percentage (0–100) for a 0–12 scale bar.
 */
function scalePercent(v) {
    return Math.min(100, Math.max(0, (v / 12) * 100));
}

/**
 * Given a pollenData array [{key, value}], returns the entry with the
 * highest value, or null if empty / all NaN.
 */
function dominant(pollenData) {
    if (!pollenData || pollenData.length === 0) return null;
    var best = null;
    for (var i = 0; i < pollenData.length; i++) {
        var p = pollenData[i];
        if (isNaN(p.value) || p.value === null) continue;
        if (!best || p.value > best.value) best = p;
    }
    return best;
}
