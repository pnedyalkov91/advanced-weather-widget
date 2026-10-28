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
 * js/spaceWeather.js - NOAA SWPC data fetcher
 *
 * Fetches 5 endpoints in parallel (no API key required) and assembles
 * a single spaceWeather object on weatherRoot.
 *
 * All helper logic lives in js/spaceWeather.js (.pragma library);
 * this file is non-pragma so it can use Qt / XMLHttpRequest.
 */

// Helper copied inline (cannot import .pragma from non-pragma)
// Thresholds at n − 1/3 to match NOAA's thirds rounding (see js/spaceWeather.js).
function _kpToGScale(kp) {
    if (isNaN(kp) || kp === null) return "G0";
    if (kp >= 9)    return "G5";
    if (kp >= 7.67) return "G4";
    if (kp >= 6.67) return "G3";
    if (kp >= 5.67) return "G2";
    if (kp >= 4.67) return "G1";
    return "G0";
}

function _getXrayClass(flux) {
    if (isNaN(flux) || flux === null || flux <= 0) return "--";
    if (flux < 1e-8) return "A";
    if (flux < 1e-7) return "B";
    if (flux < 1e-6) return "C";
    if (flux < 1e-5) return "M";
    return "X";
}

function _getXrayClassFull(flux) {
    if (isNaN(flux) || flux === null || flux <= 0) return "--";
    var cls, base;
    if (flux < 1e-8)      { cls = "A"; base = 1e-9; }
    else if (flux < 1e-7) { cls = "B"; base = 1e-8; }
    else if (flux < 1e-6) { cls = "C"; base = 1e-7; }
    else if (flux < 1e-5) { cls = "M"; base = 1e-6; }
    else                  { cls = "X"; base = 1e-5; }
    return cls + (flux / base).toFixed(1);
}

function _formatSummary(data) {
    if (!data) return "--";
    var parts = [];
    if (!isNaN(data.kp))        parts.push("Kp " + data.kp.toFixed(1));
    if (data.gScale)            parts.push(data.gScale);
    if (!isNaN(data.solarWind)) parts.push(Math.round(data.solarWind) + " km/s");
    if (!isNaN(data.bz))        parts.push("Bz " + (data.bz >= 0 ? "+" : "") + data.bz.toFixed(1) + " nT");
    if (data.xrayClassFull && data.xrayClassFull !== "--") parts.push(data.xrayClassFull);
    return parts.join(" · ");
}

// Kept in sync with auroraVisibilityPercent() in js/spaceWeather.js - this
// file is not a .pragma library (it needs XMLHttpRequest), and a plain
// script importing a .pragma library is fine, but that hasn't been wired up
// here yet, so the logic is duplicated for now. See spaceWeather.js for the
// full rationale (darkness gate + the Kp→boundary-latitude table).
function _auroraVisibilityPercent(kp, latitude, isDark) {
    if (isNaN(kp) || isNaN(latitude)) return 0;
    if (!isDark) return 0; // not dark → not visible, regardless of Kp

    var absLat = Math.abs(latitude);
    var boundary = [66.5, 64.5, 62.4, 60.4, 58.3, 56.3, 54.2, 52.2, 50.1, 48.1];
    var kpClamped = Math.max(0, Math.min(9, kp));
    var lo = Math.floor(kpClamped);
    var hi = Math.min(9, lo + 1);
    var frac = kpClamped - lo;
    var boundaryLat = boundary[lo] + (boundary[hi] - boundary[lo]) * frac;

    var distance = absLat - boundaryLat;
    var visibility;
    if (distance >= 0) {
        visibility = 70 + Math.min(25, distance * 5);
    } else {
        visibility = 70 * Math.exp(distance / 4);
    }
    return Math.round(Math.max(0, Math.min(95, visibility)));
}

/**
 * Fetches all NOAA SWPC endpoints and stores results on weatherRoot.spaceWeather.
 * Called from WeatherService after the main weather fetch completes.
 */
function fetchSpaceWeather(service) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;

    // Collector - wait for all 5 fetches to complete before assembling
    var state = {
        kp:        undefined,
        solarWind: undefined,
        bz:        undefined,
        flux:      undefined,
        done:      0
    };

    function _tryAssemble() {
        state.done++;
        if (state.done < 4) return; // wait for all 4 fast endpoints
        if (service._refreshGen !== gen) return; // superseded by a newer refresh

        var kp        = (state.kp        !== undefined) ? state.kp        : NaN;
        var solarWind = (state.solarWind !== undefined) ? state.solarWind : NaN;
        var bz        = (state.bz        !== undefined) ? state.bz        : NaN;
        var flux      = (state.flux      !== undefined) ? state.flux      : NaN;

        var gScale        = _kpToGScale(kp);
        var xrayClass     = _getXrayClass(flux);
        var xrayClassFull = _getXrayClassFull(flux);
        var isDark        = (r && typeof r.isNightTime === "function") ? r.isNightTime() : false;
        var auroraProb    = _auroraVisibilityPercent(kp, service.latitude, isDark);

        var data = {
            kp:           kp,
            gScale:       gScale,
            solarWind:    solarWind,
            bz:           bz,
            xrayClass:    xrayClass,
            xrayClassFull: xrayClassFull,
            auroraPercent: auroraProb,
            summary:      ""
        };
        data.summary = _formatSummary(data);
        r.spaceWeather = data;

        // Only mark the 10-min throttle window as "fresh" once at least one
        // endpoint actually came back with real data. If every request
        // failed (e.g. no network yet at Plasma startup), leave the
        // timestamp untouched so the next automatic refresh (periodic
        // timer, resume-from-suspend, config change, etc.) tries again
        // right away instead of silently sitting on empty/NaN data for up
        // to 10 minutes. See _lastSpaceWeatherFetch in WeatherService.qml.
        var gotData = !isNaN(kp) || !isNaN(solarWind) || !isNaN(bz) || !isNaN(flux);
        if (gotData) service._lastSpaceWeatherFetch = Date.now();
    }

    // ── 1) Kp index - 1-minute real-time nowcast. The finalized 3-hourly
    // feed lags up to 3 h behind (a storm onset wouldn't show until the
    // period closes), so it is only used as a fallback. ──────────────────
    function _fetchKp3hFallback() {
        _get("https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json",
            function(text) {
                try {
                    var arr = JSON.parse(text);
                    // Array of objects {time_tag, Kp, ...}; take the last valid entry
                    var kp = NaN;
                    for (var i = arr.length - 1; i >= 0; i--) {
                        var v = parseFloat(arr[i].Kp);
                        if (!isNaN(v)) { kp = v; break; }
                    }
                    state.kp = kp;
                } catch(e) { state.kp = NaN; }
                _tryAssemble();
            },
            function() { state.kp = NaN; _tryAssemble(); }
        );
    }
    _get("https://services.swpc.noaa.gov/json/planetary_k_index_1m.json",
        function(text) {
            var kp = NaN;
            try {
                var arr = JSON.parse(text);
                // Array of objects {time_tag, estimated_kp, ...}; take the last valid entry
                for (var i = arr.length - 1; i >= 0; i--) {
                    var v = parseFloat(arr[i].estimated_kp);
                    if (!isNaN(v)) { kp = v; break; }
                }
            } catch(e) { kp = NaN; }
            if (isNaN(kp)) { _fetchKp3hFallback(); return; }
            state.kp = kp;
            _tryAssemble();
        },
        _fetchKp3hFallback
    );

    // ── 2) Solar wind speed ───────────────────────────────────────────────
    _get("https://services.swpc.noaa.gov/products/summary/solar-wind-speed.json",
        function(text) {
            try {
                var d = JSON.parse(text);
                // Response is an array; take the first (latest) entry
                var entry = Array.isArray(d) ? d[0] : d;
                state.solarWind = parseFloat(entry.proton_speed);
            } catch(e) { state.solarWind = NaN; }
            _tryAssemble();
        },
        function() { state.solarWind = NaN; _tryAssemble(); }
    );

    // ── 3) Magnetic field Bz ─────────────────────────────────────────────
    _get("https://services.swpc.noaa.gov/products/summary/solar-wind-mag-field.json",
        function(text) {
            try {
                var d = JSON.parse(text);
                // Response is an array; take the first (latest) entry
                var entry = Array.isArray(d) ? d[0] : d;
                state.bz = parseFloat(entry.bz_gsm);
            } catch(e) { state.bz = NaN; }
            _tryAssemble();
        },
        function() { state.bz = NaN; _tryAssemble(); }
    );

    // ── 4) X-ray flux (GOES primary, 1-day, latest entry) ────────────────
    _get("https://services.swpc.noaa.gov/json/goes/primary/xrays-1-day.json",
        function(text) {
            try {
                var arr = JSON.parse(text);
                // Filter for long channel (0.1-0.8 nm) and take last entry
                var flux = NaN;
                for (var i = arr.length - 1; i >= 0; i--) {
                    var e = arr[i];
                    // energy field identifies the channel; long = "0.1-0.8nm"
                    if (e.energy && e.energy.indexOf("0.1") >= 0 && e.flux !== undefined) {
                        flux = parseFloat(e.flux);
                        break;
                    }
                }
                // Fallback: just take the last element's flux
                if (isNaN(flux) && arr.length > 0) {
                    flux = parseFloat(arr[arr.length - 1].flux);
                }
                state.flux = flux;
            } catch(e) { state.flux = NaN; }
            _tryAssemble();
        },
        function() { state.flux = NaN; _tryAssemble(); }
    );

    // ── 5) Kp/G forecast (3-hourly, ~3 days ahead) - independent of the
    // main assembly above; powers the optional daily-forecast Kp/G stat. ──
    _get("https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json",
        function(text) {
            if (service._refreshGen !== gen) return;
            var byDate = {};
            var periods = [];
            try {
                var arr = JSON.parse(text);
                for (var i = 0; i < arr.length; i++) {
                    var entry = arr[i];
                    var tag = entry.time_tag;
                    var kp = parseFloat(entry.kp);
                    if (!tag || isNaN(kp)) continue;
                    var gScale = entry.noaa_scale || _kpToGScale(kp);
                    var dateStr = tag.substring(0, 10);
                    if (!byDate[dateStr] || kp > byDate[dateStr].kp)
                        byDate[dateStr] = { kp: kp, gScale: gScale };
                    // time_tag is UTC without a zone suffix
                    var startMs = Date.parse(tag.indexOf("Z") >= 0 ? tag : tag + "Z");
                    if (!isNaN(startMs))
                        periods.push({ startMs: startMs, kp: kp, gScale: gScale });
                }
                periods.sort(function(a, b) { return a.startMs - b.startMs; });
            } catch(e) { byDate = {}; periods = []; }
            r.spaceWeatherDailyForecast = byDate;
            r.spaceWeatherForecastPeriods = periods;
        },
        function() {}
    );
}

/**
 * Recomputes just the aurora-visibility percentage in weatherRoot.spaceWeather
 * for the current latitude/darkness, without touching the network.
 *
 * Kp/solar wind/Bz/X-ray are genuinely location-independent, so refreshNow()
 * correctly skips re-fetching them on a location change while the 10-min
 * throttle is still active. But auroraPercent - bundled into that same
 * object - depends on the observer's latitude and on isNightTime()
 * (sunrise/sunset), both of which change with location. Without this, a
 * location switch left the aurora number stuck showing the previous city's
 * value until the throttle window happened to expire or a manual refresh
 * forced a full re-fetch.
 *
 * No-ops if we don't have a cached Kp yet (nothing to recompute from).
 */
function recomputeAuroraForLocation(service) {
    var r = service.weatherRoot;
    if (!r || !r.spaceWeather) return;
    var kp = r.spaceWeather.kp;
    if (isNaN(kp)) return;

    var isDark = (typeof r.isNightTime === "function") ? r.isNightTime() : false;
    var auroraProb = _auroraVisibilityPercent(kp, service.latitude, isDark);
    if (auroraProb === r.spaceWeather.auroraPercent) return; // unchanged - skip the reassignment

    // QML's `property var` only notifies on a new object reference, so
    // patch a copy rather than mutating r.spaceWeather in place (same
    // pattern used by _mergeAqiData / _fetchSunTimesOpenMeteo above).
    var patched = {};
    for (var k in r.spaceWeather) patched[k] = r.spaceWeather[k];
    patched.auroraPercent = auroraProb;
    patched.summary = _formatSummary(patched);
    r.spaceWeather = patched;
}

// ── Internal HTTP helper ──────────────────────────────────────────────────────

function _get(url, onSuccess, onError) {
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
    req.onreadystatechange = function() {
        if (req.readyState !== XMLHttpRequest.DONE) return;
        if (req.status === 200) {
            onSuccess(req.responseText);
        } else {
            onError();
        }
    };
    req.send();
}
