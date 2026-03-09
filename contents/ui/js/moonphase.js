/**
 * moonphase.js — Moon phase calculation utilities
 *
 * .pragma library: pure JS math only, no Qt APIs, no i18n.
 * Import via: import "js/moonphase.js" as Moon
 */
.pragma library

/**
 * Returns the current moon age in days.
 * 0.0 = new moon,  ~7.38 = first quarter,
 * ~14.77 = full moon, ~22.15 = third quarter
 */
function getMoonAge() {
    var refNewMoon  = new Date(Date.UTC(2000, 0, 6, 18, 14, 0));
    var lunarCycle  = 29.530588853;
    var diffDays    = (Date.now() - refNewMoon.getTime()) / 86400000;
    return ((diffDays % lunarCycle) + lunarCycle) % lunarCycle;
}

/**
 * Returns a wi-font Unicode glyph (PUA F0D0+) for the given moon age.
 * If age is omitted the current age is computed automatically.
 */
function moonPhaseGlyph(age) {
    var a = (age !== undefined) ? age : getMoonAge();
    var offsets = [0x00, 0x02, 0x05, 0x08, 0x0C, 0x10, 0x14, 0x17];
    var idx = Math.round((a / 29.53) * 7) % 8;
    return String.fromCodePoint(0xF0D0 + offsets[idx]);
}

/**
 * Returns the wi-* SVG icon name stem (e.g. "wi-moon-alt-full") for the given moon age.
 * Full URL: Qt.resolvedUrl("../icons/wi-" + Moon.moonPhaseSvgStem(age) + ".svg")
 */
function moonPhaseSvgStem(age) {
    var a = (age !== undefined) ? age : getMoonAge();
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

function moonPhaseFontIcon(age) {
    var a = (age !== undefined) ? age : getMoonAge();
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
 * Returns the English phase name key — the caller is responsible for i18n().
 * e.g.: i18n(Moon.moonPhaseNameKey())
 */
function moonPhaseNameKey(age) {
    var a = (age !== undefined) ? age : getMoonAge();
    if (a < 1.85)  return "New Moon";
    if (a < 7.38)  return "Waxing Crescent";
    if (a < 9.23)  return "First Quarter";
    if (a < 14.77) return "Waxing Gibbous";
    if (a < 16.62) return "Full Moon";
    if (a < 22.15) return "Waning Gibbous";
    if (a < 24.0)  return "Last Quarter";
    return "Waning Crescent";
}
