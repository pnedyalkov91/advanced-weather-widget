/*
 * Copyright 2026 Petar Nedyalkov
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
 * along with this program.  If not, see <https://gnu.org>.
 */

/**
 * gaugeAnim.js - tiny shared clock for the animated gauge scenes.
 *
 * ExpandedGauge.qml calls setEnabled() before every paint. When animations are
 * off, T() is always 0, so every scene draws exactly the same static picture
 * as before. When on, T() is the time in seconds and the scenes use it to
 * move their particles, waves and rays.
 */
.pragma library

var _enabled = false;
var _t0 = Date.now();

function setEnabled(on) { _enabled = on === true; }

/**
 * Layer switch. ExpandedGauge draws every gauge twice into two stacked canvases:
 * the moving scene (layer "scene", repainted by the timer) and the static dial
 * with its markers (layer "dial", repainted only when the data changes). Each
 * gauge wraps its scene block in `if (GA.scene())` and its dial block in
 * `if (GA.dial())`; "all" (the default) draws both, like before.
 */
var _layer = "all";
function setLayer(l) { _layer = l; }
function scene() { return _layer !== "dial"; }
function dial() { return _layer !== "scene"; }
function isEnabled() { return _enabled; }

/** Seconds since start while animating, 0 when animations are off. */
function T() { return _enabled ? (Date.now() - _t0) / 1000 : 0; }

/** Wraps v into [0, span). */
function wrap(v, span) {
    if (span <= 0) return 0;
    var m = v % span;
    return m < 0 ? m + span : m;
}

/** Sine wobble of amplitude `amp` (angular speed `w`, phase `ph`); 0 when off. */
function osc(w, ph, amp) {
    return _enabled ? Math.sin(T() * w + ph) * amp : 0;
}

/** Slow sine pulse in 0..1 with the given period in seconds (0.5 when off). */
function pulse(period, shift) {
    if (!_enabled) return 0.5;
    return 0.5 + 0.5 * Math.sin(2 * Math.PI * T() / period + (shift || 0));
}
