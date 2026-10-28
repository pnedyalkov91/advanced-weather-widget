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
 * moonphase.js - Moon phase calculation utilities
 *
 * .pragma library: pure JS math only, no Qt APIs, no i18n.
 * Import via: import "js/moonphase.js" as Moon
 *
 * Moon age must now be supplied by the caller via SunCalc:
 *   import "js/suncalc.js" as SC
 *   var age = Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase)
 */
.pragma library

/**
 * Converts a SunCalc phase value (0..1) to moon age in days (0..29.53).
 * Call as: Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase)
 *
 * The old getMoonAge() self-contained calculation has been removed in favour
 * of SunCalc for accuracy and maintainability.
 */
function moonAgeFromPhase(phase) {
    return phase * 29.530588853;
}

/**
 * Returns a wi-font Unicode glyph for the given moon age.
 * This is the single canonical glyph function.
 * (moonPhaseGlyph was identical and has been removed.)
 */
function moonPhaseFontIcon(age) {
    var a = (age !== undefined) ? age : 0;
    if (a < 1.85)  return "\uF0EB";  // moon-alt-new
    if (a < 5.0)   return "\uF0D2";  // moon-alt-waxing-crescent-2
    if (a < 7.38)  return "\uF0D5";  // moon-alt-waxing-crescent-5
    if (a < 9.23)  return "\uF0D6";  // moon-alt-first-quarter
    if (a < 12.0)  return "\uF0DA";  // moon-alt-waxing-gibbous-3
    if (a < 14.77) return "\uF0DC";  // moon-alt-waxing-gibbous-6
    if (a < 16.62) return "\uF0DD";  // moon-alt-full
    if (a < 19.0)  return "\uF0E1";  // moon-alt-waning-gibbous-3
    if (a < 22.15) return "\uF0E3";  // moon-alt-waning-gibbous-6
    if (a < 24.0)  return "\uF0E4";  // moon-alt-third-quarter
    if (a < 26.5)  return "\uF0E6";  // moon-alt-waning-crescent-3
    return "\uF0E9";                 // moon-alt-waning-crescent-6
}

/**
 * Returns the wi-* SVG icon filename stem for the given moon age.
 * e.g. "moon-alt-full" → use as: base + "wi-" + stem + ".svg"
 */
function moonPhaseSvgStem(age) {
    var a = (age !== undefined) ? age : 0;
    if (a < 1.85)  return "moon-alt-new";
    if (a < 5.0)   return "moon-alt-waxing-crescent-2";
    if (a < 7.38)  return "moon-alt-waxing-crescent-5";
    if (a < 9.23)  return "moon-alt-first-quarter";
    if (a < 12.0)  return "moon-alt-waxing-gibbous-3";
    if (a < 14.77) return "moon-alt-waxing-gibbous-6";
    if (a < 16.62) return "moon-alt-full";
    if (a < 19.0)  return "moon-alt-waning-gibbous-3";
    if (a < 22.15) return "moon-alt-waning-gibbous-6";
    if (a < 24.0)  return "moon-alt-third-quarter";
    if (a < 26.5)  return "moon-alt-waning-crescent-3";
    return "moon-alt-waning-crescent-6";
}

/**
 * Returns the English phase name key - the caller is responsible for i18n().
 * e.g.: i18n(Moon.moonPhaseNameKey())
 */
function moonPhaseNameKey(age) {
    var a = (age !== undefined) ? age : 0; // age must be supplied by caller via SC.getMoonIllumination()
    if (a < 1.85)  return "New Moon";
    if (a < 7.38)  return "Waxing Crescent";
    if (a < 9.23)  return "First Quarter";
    if (a < 14.77) return "Waxing Gibbous";
    if (a < 16.62) return "Full Moon";
    if (a < 22.15) return "Waning Gibbous";
    if (a < 24.0)  return "Last Quarter";
    return "Waning Crescent";
}
