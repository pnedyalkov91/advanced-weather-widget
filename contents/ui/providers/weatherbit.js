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
 * weatherbit.js - Weatherbit current + hourly fetcher
 *
 * Non-pragma JS - accesses config via service properties.
 * Weatherbit provides current conditions, daily and hourly forecasts.
 * Docs: https://www.weatherbit.io/api
 */

.import "../js/debug.js" as Dbg
.import "../js/sharedGet.js" as Shared
.import "../js/refusals.js" as Refusals

/**
 * Maps a Weatherbit weather code to a WMO weather code.
 */
function _codeToWmo(code) {
    if (code === undefined || code === null) return 2;
    // Thunderstorm (200-233)
    if (code >= 200 && code <= 233) return 95;
    // Drizzle (300-302)
    if (code >= 300 && code <= 302) return 51;
    // Rain
    if (code === 500) return 61;  // Light Rain
    if (code === 501) return 63;  // Moderate Rain
    if (code === 502) return 65;  // Heavy Rain
    if (code === 511) return 66;  // Freezing Rain
    if (code >= 520 && code <= 522) return 80; // Rain showers
    // Snow
    if (code === 600) return 71;  // Light Snow
    if (code === 601) return 73;  // Snow
    if (code === 602) return 75;  // Heavy Snow
    if (code === 610) return 66;  // Mix snow/rain
    if (code === 611 || code === 612) return 66; // Sleet
    if (code === 621) return 85;  // Snow Shower
    if (code === 622) return 86;  // Heavy Snow Shower
    if (code === 623) return 77;  // Flurries
    // Fog / Mist / Haze (700-751)
    if (code >= 700 && code <= 751) return 45;
    // Clear / Clouds
    if (code === 800) return 0;   // Clear
    if (code === 801) return 1;   // Few clouds
    if (code === 802) return 2;   // Scattered clouds
    if (code === 803) return 3;   // Broken clouds
    if (code === 804) return 3;   // Overcast
    // Unknown precipitation
    if (code === 900) return 63;
    return 2;
}

/** The calendar date (YYYY-MM-DD) immediately after dateStr, in the widget's
 *  own local time - used to append the closing 00:00 entry so the hourly
 *  forecast reads 00:00..00:00 instead of stopping at 23:00. */
function _nextDateStr(dateStr) {
    var d = new Date(dateStr + "T00:00:00");
    d.setDate(d.getDate() + 1);
    return Qt.formatDate(d, "yyyy-MM-dd");
}


// ── Requests ─────────────────────────────────────────────────────────────────
// Weatherbit's free plan is tiny: about 50 calls a day (the x-ratelimit headers say 55) and NO hourly
// forecast - /forecast/hourly answers HTTP 403 "Your API key does not allow access to this endpoint"
// while /current and /forecast/daily work. So:
//  - the daily forecast (it changes a few times a day) is reused for 3 h, the hourly one for 10 min;
//  - the hourly 403 is remembered as its own "provider" (weatherbitHourly): it says nothing about the
//    key, so current + daily keep working, but the hourly request is not repeated for every day the
//    Forecast tab opens (that was 7+ refused requests in a row);
//  - 401/402/429 (bad key, daily limit used up) are remembered for the whole provider, see refusals.js.
var _DAILY_REUSE_MS = 3 * 3600 * 1000;
var _HOURLY_REUSE_MS = 10 * 60000;

function _hourlyUrl(service, key) {
    return "https://api.weatherbit.io/v2.0/forecast/hourly"
        + "?lat=" + service.latitude
        + "&lon=" + service.longitude
        + "&key=" + encodeURIComponent(key)
        + "&units=M"
        + "&hours=48";
}

/** The refusal (whole provider, or the hourly endpoint alone) that rules out a request now, else null. */
function _hourlyRefused(key) {
    return Refusals.active("weatherbit", key) || Refusals.active("weatherbitHourly", key);
}

/** One hourly answer: callback(status, parsed) - status 200 with the parsed answer, else what the server said. */
function _hourly(service, key, label, callback) {
    var refused = _hourlyRefused(key);
    if (refused) {
        Refusals.logSkip("Weatherbit", label, refused);
        callback(refused.status, null);
        return;
    }
    var req = Shared.xhr("Weatherbit", label, { reuseMs: _HOURLY_REUSE_MS });
    req.open("GET", _hourlyUrl(service, key));
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (req.status !== 200) {
            if (req.status === 403) {
                // this plan has no hourly forecast: not a verdict on the key
                Dbg.log("Weatherbit", label + ": the hourly forecast is not part of this API key's plan (HTTP 403: "
                        + Dbg.snippet(req.responseText, 100) + ") → no hourly hours for this provider");
                Refusals.note("weatherbitHourly", 403, key);
            } else if (Refusals.isRefusal(req.status)) {
                Refusals.note("weatherbit", req.status, key);
            }
            callback(req.status, null);
            return;
        }
        var d;
        try {
            d = JSON.parse(req.responseText);
        } catch (e) {
            callback(200, null);
            return;
        }
        callback(200, d);
    };
    req.send();
}

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._wbKey();
    if (!key) {
        Dbg.log("Weatherbit", "no API key set in Settings → provider skipped, trying the next one");
        service._tryProvider(chain, idx + 1);
        return;
    }
    var refused = Refusals.active("weatherbit", key);
    if (refused) {
        Refusals.logSkip("Weatherbit", "fetchCurrent", refused);
        service._tryProvider(chain, idx + 1);
        return;
    }

    var url = "https://api.weatherbit.io/v2.0/current"
        + "?lat=" + service.latitude
        + "&lon=" + service.longitude
        + "&key=" + encodeURIComponent(key)
        + "&units=M";

    var req = Shared.xhr("Weatherbit", "fetchCurrent");
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            if (Refusals.isRefusal(req.status))
                Refusals.note("weatherbit", req.status, key);
            service._tryProvider(chain, idx + 1);
            return;
        }
        try {
            var d = JSON.parse(req.responseText);
        } catch (e) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        if (!d.data || d.data.length === 0) {
            service._tryProvider(chain, idx + 1);
            return;
        }

        var c = d.data[0];

        var wCode = (c.weather && c.weather.code !== undefined) ? c.weather.code : undefined;
        service._wb_cur = {
            temperatureC:    c.temp,
            apparentC:       c.app_temp,
            humidityPercent: (c.rh !== undefined) ? c.rh : NaN,
            windKmh:         (c.wind_spd !== undefined) ? c.wind_spd * 3.6 : NaN,
            windDirection:   (c.wind_dir !== undefined) ? c.wind_dir : NaN,
            pressureHpa:     (c.slp !== undefined) ? c.slp : ((c.pres !== undefined) ? c.pres : NaN),  // prefer sea-level (slp) over surface (pres)
            dewPointC:       (c.dewpt !== undefined) ? c.dewpt : NaN,
            visibilityKm:    (c.vis !== undefined) ? c.vis : NaN,
            precipMmh:       (c.precip !== undefined) ? c.precip : NaN,
            uvIndex:         (c.uv !== undefined) ? c.uv : NaN,
            snowDepthCm:     NaN,
            weatherCode:     _codeToWmo(wCode),
            isDay:           (c.pod === "d") ? 1 : (c.pod === "n") ? 0 : -1,
            locationUtcOffsetMins: 0,
            sunriseTimeText: c.sunrise || "--",
            sunsetTimeText:  c.sunset  || "--",
            dailyData:       []
        };
        // No native air quality or pollen - both are supplied by the shared
        // Open-Meteo fetch started in WeatherService.refreshNow(). Clearing
        // them here would race that fetch and discard its result.
        _fetchDailyForecast(service, W, gen, key);
    };
    req.send();
}

/**
 * Fetches the daily forecast from Weatherbit.
 * Sets dailyData, then marks loading complete.
 */
function _fetchDailyForecast(service, W, gen, key) {
    var r = service.weatherRoot;

    var url = "https://api.weatherbit.io/v2.0/forecast/daily"
        + "?lat=" + service.latitude
        + "&lon=" + service.longitude
        + "&key=" + encodeURIComponent(key)
        + "&units=M"
        + "&days=" + Math.min(service.forecastDays, 16);

    var req = Shared.xhr("Weatherbit", "_fetchDailyForecast", { reuseMs: _DAILY_REUSE_MS });
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;

        if (req.status !== 200 && Refusals.isRefusal(req.status))
            Refusals.note("weatherbit", req.status, key);
        if (req.status === 200) {
            try {
                var d = JSON.parse(req.responseText);
                if (d.data && d.data.length > 0) {
                    var nd = [];
                    var maxD = Math.min(service.forecastDays, d.data.length);
                    for (var i = 0; i < maxD; i++) {
                        var dd = d.data[i];
                        var wCode = (dd.weather && dd.weather.code !== undefined) ? dd.weather.code : undefined;
                        nd.push({
                            day: Qt.formatDate(new Date(dd.datetime + "T12:00:00"), "ddd"),
                            dateStr: dd.datetime,
                            maxC: (dd.max_temp !== undefined) ? dd.max_temp : NaN,
                            minC: (dd.min_temp !== undefined) ? dd.min_temp : NaN,
                            code: _codeToWmo(wCode),
                            precipMm: (dd.precip !== undefined) ? dd.precip : NaN,
                            snowCm: (dd.snow !== undefined) ? dd.snow / 10 : NaN, // mm to cm
                            precipProb: (dd.pop !== undefined) ? dd.pop : NaN,
                            windKmh: (dd.wind_spd !== undefined) ? dd.wind_spd * 3.6 : NaN,
                            windDir: (dd.wind_dir !== undefined) ? dd.wind_dir : NaN
                        });
                    }
                    service._wb_cur.dailyData = nd;
                }
            } catch (e) { /* ignore parse errors */ }
        }

        r.weatherDataStaged = service._wb_cur;
        service._wb_cur = null;
        r.loading = false;
        r.updateText = service._formatUpdateText("weatherbit");

        // No native alerts - fall back to MeteoAlarm / NWS
        service._fetchAlertsIfNeeded();

        // Weatherbit sunrise/sunset ARE location-local, but the payload gives
        // no numeric UTC offset, so sun/moon progress would silently use UTC
        // for any non-UTC location. Same Open-Meteo backfill as BBC/met.no.
        try { service._fetchSunTimesOpenMeteo(); } catch (e) {}

        // Air quality fetched in parallel from WeatherService.refreshNow()
    };
    req.send();
}


/** The hours of dateStr (plus the closing 00:00 of the next day) out of one parsed answer. */
function _hourlyDay(d, W, dateStr) {
    var arr = [];
    var nextDateStr = _nextDateStr(dateStr);
    var nextEntry = null;
    if (d.data) {
        d.data.forEach(function (h) {
            // timestamp_local is "yyyy-MM-ddTHH:mm:ss"
            var dtStr = h.timestamp_local || h.datetime || "";
            var datePart = dtStr.substring(0, 10);
            var isTarget = datePart === dateStr;
            var isClosing = !nextEntry && datePart === nextDateStr;
            if (!isTarget && !isClosing) return;

            var dt = new Date(dtStr);
            var wCode = (h.weather && h.weather.code !== undefined) ? h.weather.code : undefined;

            var entry = {
                hour: Qt.formatTime(dt, "HH:mm"),
                tempC: h.temp,
                code: _codeToWmo(wCode),
                windKmh: (h.wind_spd !== undefined) ? h.wind_spd * 3.6 : NaN,
                windDeg: (h.wind_dir !== undefined) ? h.wind_dir : NaN,
                humidity: (h.rh !== undefined) ? Math.round(h.rh) : NaN,
                precipProb: (h.pop !== undefined) ? Math.round(h.pop) : NaN,
                precipMm: (h.precip !== undefined) ? h.precip : NaN
            };
            if (isTarget) {
                arr.push(entry);
            } else {
                // d.data is chronological, so the first match for the
                // next date is its earliest hour - append it to close
                // the loop at midnight. Only present when the fixed
                // 48h window above happens to reach that far.
                entry.isNextDay = true;
                nextEntry = entry;
            }
        });
    }
    if (nextEntry) arr.push(nextEntry);
    
    return arr;
}

/** Hours of every day firstDate..lastDate out of ONE already-parsed answer: { "yyyy-MM-dd": [hours] }
 *  (days the answer does not cover are left out). Same per-day result fetchHourly gives. */
function _hourlyDays(d, W, firstDate, lastDate) {
    var map = {};
    var ds = firstDate;
    for (var guard = 0; guard < 40 && ds <= lastDate; ++guard) {
        var a = _hourlyDay(d, W, ds);
        if (a && a.length)
            map[ds] = a;
        ds = _nextDateStr(ds);
    }
    return map;
}

function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._wbKey();
    if (!key) {
        Dbg.log("Weatherbit", "no API key set in Settings → no hourly forecast");
        r.hourlyData = [];
        return;
    }

    _hourly(service, key, "fetchHourly", function (status, d) {
        if (service._refreshGen !== gen) return;
        if (status !== 200 || !d) {
            r.hourlyData = [];
            return;
        }
        r.setHourlyResult(dateStr, _hourlyDay(d, W, dateStr));
    });
}

/** Hours of every day firstDate..lastDate from ONE request: callback({ dateStr: [hours] }), {} on any failure. */
function fetchHourlyAll(service, W, firstDate, lastDate, callback) {
    var key = service._wbKey();
    if (!key) {
        Dbg.log("Weatherbit", "no API key set in Settings → no hourly forecast");
        callback({});
        return;
    }

    _hourly(service, key, "fetchHourlyAll", function (status, d) {
        if (status !== 200 || !d) {
            callback({});
            return;
        }
        callback(_hourlyDays(d, W, firstDate, lastDate));
    });
}
