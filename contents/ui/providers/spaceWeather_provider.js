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
 * js/spaceWeather.js — NOAA SWPC data fetcher
 *
 * Fetches 5 endpoints in parallel (no API key required) and assembles
 * a single spaceWeather object on weatherRoot.
 *
 * All helper logic lives in js/spaceWeather.js (.pragma library);
 * this file is non-pragma so it can use Qt / XMLHttpRequest.
 */

// Helper copied inline (cannot import .pragma from non-pragma)
function _kpToGScale(kp) {
    if (isNaN(kp) || kp === null) return "G0";
    if (kp >= 9) return "G5";
    if (kp >= 8) return "G4";
    if (kp >= 7) return "G3";
    if (kp >= 6) return "G2";
    if (kp >= 5) return "G1";
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

function _auroraVisibilityPercent(kp, latitude) {
    if (isNaN(kp) || isNaN(latitude)) return 0;
    var absLat = Math.abs(latitude);
    var aurovalLat = 65 - (kp / 2);  // Higher Kp shifts aurora south
    if (kp >= 9) aurovalLat = 30;    // Extreme storms reach equator
    var distance = Math.abs(absLat - aurovalLat);
    var visibility = Math.max(0, 100 - (distance * 2.5));
    if (kp >= 7 && absLat >= 40) visibility = Math.max(visibility, 50);
    if (kp >= 8 && absLat >= 35) visibility = Math.max(visibility, 60);
    if (kp >= 9 && absLat >= 30) visibility = Math.max(visibility, 70);
    return Math.round(visibility);
}

/**
 * Fetches all NOAA SWPC endpoints and stores results on weatherRoot.spaceWeather.
 * Called from WeatherService after the main weather fetch completes.
 */
function fetchSpaceWeather(service) {
    var r = service.weatherRoot;

    // Collector — wait for all 5 fetches to complete before assembling
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

        var kp        = (state.kp        !== undefined) ? state.kp        : NaN;
        var solarWind = (state.solarWind !== undefined) ? state.solarWind : NaN;
        var bz        = (state.bz        !== undefined) ? state.bz        : NaN;
        var flux      = (state.flux      !== undefined) ? state.flux      : NaN;

        var gScale        = _kpToGScale(kp);
        var xrayClass     = _getXrayClass(flux);
        var xrayClassFull = _getXrayClassFull(flux);
        var auroraProb    = _auroraVisibilityPercent(kp, service.latitude);

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
    }

    // ── 1) Kp index ───────────────────────────────────────────────────────
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
                // Filter for long channel (0.1–0.8 nm) and take last entry
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
