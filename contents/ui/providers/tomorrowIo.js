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
 * tomorrowIo.js - Tomorrow.io current + hourly fetcher
 *
 * Non-pragma JS - accesses config via service properties.
 * Uses the Tomorrow.io Weather API v4 (Realtime + Forecast endpoints).
 * Docs: https://docs.tomorrow.io/reference/welcome
 */

.import "../js/debug.js" as Dbg
.import "../js/sharedGet.js" as Shared
.import "../js/refusals.js" as Refusals

/**
 * Maps a Tomorrow.io weather code to a WMO weather code.
 */
function _codeToWmo(code) {
    if (code === undefined || code === null) return 2;
    switch (code) {
        case 1000: return 0;   // Clear
        case 1100: return 1;   // Mostly Clear
        case 1101: return 2;   // Partly Cloudy
        case 1102: return 3;   // Mostly Cloudy
        case 1001: return 3;   // Cloudy
        case 2000: return 45;  // Fog
        case 2100: return 45;  // Light Fog
        case 4000: return 51;  // Drizzle
        case 4200: return 61;  // Light Rain
        case 4001: return 63;  // Rain
        case 4201: return 65;  // Heavy Rain
        case 5001: return 77;  // Flurries
        case 5100: return 71;  // Light Snow
        case 5000: return 73;  // Snow
        case 5101: return 75;  // Heavy Snow
        case 6000: return 56;  // Freezing Drizzle
        case 6200: return 66;  // Light Freezing Rain
        case 6001: return 66;  // Freezing Rain
        case 6201: return 67;  // Heavy Freezing Rain
        case 7102: return 77;  // Light Ice Pellets
        case 7000: return 77;  // Ice Pellets
        case 7101: return 77;  // Heavy Ice Pellets
        case 8000: return 95;  // Thunderstorm
        default:   return 2;
    }
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
// Tomorrow.io's free plan allows 25 requests an hour and 500 a day, and every endpoint + location
// counts as one call: realtime, forecast hourly and forecast daily used to be three calls per refresh.
// The forecast endpoint takes several timesteps at once, so "1h,1d" is ONE call that answers both the
// daily forecast (current refresh) and the hourly one (Forecast tab), and Shared.xhr hands the same
// answer to every caller for 10 minutes (a manual refresh asks again).
var _FORECAST_REUSE_MS = 10 * 60000;
var _mergedOk = true;        // false once the combined "1h,1d" request was rejected: one request per timestep then
var _keysLogged = {};

function _base(service, endpoint, key, extra) {
    return "https://api.tomorrow.io/v4/weather/" + endpoint
        + "?location=" + service.latitude + "," + service.longitude
        + (extra || "")
        + "&units=metric"
        + "&apikey=" + encodeURIComponent(key);
}

/** Debug only: which value fields an answer really holds (once per kind and session). */
function _logKeys(kind, values) {
    if (!Dbg.enabled() || !values || _keysLogged[kind])
        return;
    _keysLogged[kind] = true;
    Dbg.log("Tomorrow.io", kind + " fields: " + Object.keys(values).sort().join(", "));
}

function _num(v, name) {
    var x = v ? v[name] : undefined;
    return (typeof x === "number" && isFinite(x)) ? x : NaN;
}

/** Precipitation rate in mm/h: the total field when the answer has one, else the sum of the types. */
function _precipRate(v) {
    var t = _num(v, "precipitationIntensity");
    if (!isNaN(t))
        return t;
    var sum = 0, any = false;
    ["rainIntensity", "snowIntensity", "sleetIntensity", "freezingRainIntensity"].forEach(function (n) {
        var x = _num(v, n);
        if (!isNaN(x)) { sum += x; any = true; }
    });
    return any ? sum : NaN;
}

/** Water a day brings, mm: rain + (liquid equivalent of) sleet, snow and ice. NaN when the answer has none of them. */
function _dailyPrecipMm(dv) {
    var sum = 0, any = false;
    ["rainAccumulationSum", "sleetAccumulationLweSum", "snowAccumulationLweSum", "iceAccumulationLweSum"].forEach(function (n) {
        var x = _num(dv, n);
        if (!isNaN(x)) { sum += x; any = true; }
    });
    return any ? sum : NaN;
}

function _first(v, names) {
    for (var i = 0; i < names.length; ++i) {
        var x = _num(v, names[i]);
        if (!isNaN(x))
            return x;
    }
    return NaN;
}

/**
 * One forecast answer. need: "hourly" or "daily". callback(status, parsed): status 200 with the parsed
 * answer, a refusal status (remembered, see refusals.js) or whatever the server said.
 */
function _forecast(service, key, label, need, callback) {
    var refused = Refusals.active("tomorrowIo", key);
    if (refused) {
        Refusals.logSkip("Tomorrow.io", label, refused);
        callback(refused.status, null);
        return;
    }
    var combined = _mergedOk;
    var url = _base(service, "forecast", key, "&timesteps=" + (combined ? "1h,1d" : (need === "hourly" ? "1h" : "1d")));
    var req = Shared.xhr("Tomorrow.io", label, { reuseMs: _FORECAST_REUSE_MS });
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (req.status !== 200) {
            if (Refusals.isRefusal(req.status)) {
                Refusals.note("tomorrowIo", req.status, key);
            } else if (combined && req.status === 400) {
                _mergedOk = false;
                Dbg.log("Tomorrow.io", label + ": the combined 1h,1d request was rejected (HTTP 400) → one request per timestep from now on");
                _forecast(service, key, label, need, callback);
                return;
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
        var tl = d && d.timelines;
        if (combined && !(tl && tl[need] && tl[need].length)) {
            // 200, but the timestep this caller needs is missing: the server ignored the second one
            _mergedOk = false;
            Dbg.log("Tomorrow.io", label + ": the combined 1h,1d answer lacks the " + need + " timeline → one request per timestep from now on");
            _forecast(service, key, label, need, callback);
            return;
        }
        if (tl) {
            _logKeys("hourly", tl.hourly && tl.hourly[0] && tl.hourly[0].values);
            _logKeys("daily", tl.daily && tl.daily[0] && tl.daily[0].values);
        }
        callback(200, d);
    };
    req.send();
}

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._tioKey();
    if (!key) {
        Dbg.log("Tomorrow.io", "no API key set in Settings → provider skipped, trying the next one");
        service._tryProvider(chain, idx + 1);
        return;
    }
    var refused = Refusals.active("tomorrowIo", key);
    if (refused) {
        Refusals.logSkip("Tomorrow.io", "fetchCurrent", refused);
        service._tryProvider(chain, idx + 1);
        return;
    }

    // Step 1: Fetch realtime conditions
    var url = _base(service, "realtime", key);

    var req = Shared.xhr("Tomorrow.io", "fetchCurrent");
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            if (Refusals.isRefusal(req.status))
                Refusals.note("tomorrowIo", req.status, key);
            service._tryProvider(chain, idx + 1);
            return;
        }
        try {
            var d = JSON.parse(req.responseText);
        } catch (e) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        if (!d.data || !d.data.values) {
            service._tryProvider(chain, idx + 1);
            return;
        }

        var c = d.data.values;
        _logKeys("realtime", c);
        // Stage current fields - will be written atomically with dailyData in _fetchForecast
        service._tio_cur = {
            temperatureC:    c.temperature,
            apparentC:       c.temperatureApparent,
            humidityPercent: (c.humidity !== undefined) ? c.humidity : NaN,
            windKmh:         (c.windSpeed !== undefined) ? c.windSpeed * 3.6 : NaN,
            windDirection:   (c.windDirection !== undefined) ? c.windDirection : NaN,
            pressureHpa:     (c.pressureSeaLevel !== undefined) ? c.pressureSeaLevel : ((c.pressureSurfaceLevel !== undefined) ? c.pressureSurfaceLevel : NaN),  // prefer sea-level
            dewPointC:       (c.dewPoint !== undefined) ? c.dewPoint : NaN,
            visibilityKm:    (c.visibility !== undefined) ? c.visibility : NaN,
            precipMmh:       _precipRate(c),
            uvIndex:         (c.uvIndex !== undefined) ? c.uvIndex : NaN,
            snowDepthCm:     NaN,
            weatherCode:     _codeToWmo(c.weatherCode),
            isDay:           -1,
            locationUtcOffsetMins: 0,
            sunriseTimeText: "--",
            sunsetTimeText:  "--",
            dailyData:       []
        };
        // No native air quality or pollen - both are supplied by the shared
        // Open-Meteo fetch started in WeatherService.refreshNow(). Clearing
        // them here would race that fetch and discard its result.
        // Step 2: Fetch daily forecast for dailyData + sun times, then write r.weatherData
        _fetchForecast(service, W, gen, key);
    };
    req.send();
}

/**
 * Fetches the daily forecast from Tomorrow.io.
 * Sets dailyData, sunriseTimeText, sunsetTimeText, and isDay.
 */
function _fetchForecast(service, W, gen, key) {
    var r = service.weatherRoot;

    _forecast(service, key, "_fetchForecast", "daily", function (status, d) {
        if (service._refreshGen !== gen) return;

        var haveSunTimes = false;

        if (status === 200 && d) {
            try {
                var dailyTimeline = d.timelines && d.timelines.daily;
                if (dailyTimeline && dailyTimeline.length > 0) {
                    var day0v = dailyTimeline[0].values;
                    if (day0v.sunriseTime) {
                        service._tio_cur.sunriseTimeText = Qt.formatTime(new Date(day0v.sunriseTime), "HH:mm");
                        haveSunTimes = true;
                    }
                    if (day0v.sunsetTime) {
                        service._tio_cur.sunsetTimeText = Qt.formatTime(new Date(day0v.sunsetTime), "HH:mm");
                    }
                    if (day0v.sunriseTime && day0v.sunsetTime) {
                        var now = new Date();
                        var sr = new Date(day0v.sunriseTime);
                        var ss = new Date(day0v.sunsetTime);
                        service._tio_cur.isDay = (now >= sr && now <= ss) ? 1 : 0;
                    }

                    // Daily forecast
                    var nd = [];
                    var maxD = Math.min(service.forecastDays, dailyTimeline.length);
                    for (var i = 0; i < maxD; i++) {
                        var dd = dailyTimeline[i];
                        var dv = dd.values;
                        var snowMm = _num(dv, "snowAccumulationSum");
                        var prob = _first(dv, ["precipitationProbabilityMax", "precipitationProbabilityAvg"]);
                        var wind = _first(dv, ["windSpeedMax", "windSpeedAvg"]);
                        nd.push({
                            day: Qt.formatDate(new Date(dd.time), "ddd"),
                            dateStr: Qt.formatDate(new Date(dd.time), "yyyy-MM-dd"),
                            maxC: (dv.temperatureMax !== undefined) ? dv.temperatureMax : NaN,
                            minC: (dv.temperatureMin !== undefined) ? dv.temperatureMin : NaN,
                            code: _codeToWmo(dv.weatherCodeMax !== undefined ? dv.weatherCodeMax : dv.weatherCode),
                            precipMm: _dailyPrecipMm(dv),
                            snowCm: isNaN(snowMm) ? NaN : snowMm / 10,
                            precipProb: isNaN(prob) ? NaN : Math.round(prob),
                            windKmh: isNaN(wind) ? NaN : wind * 3.6,
                            windDir: _num(dv, "windDirectionAvg")
                        });
                    }
                    service._tio_cur.dailyData = nd;
                }
            } catch (e) { /* ignore parse errors */ }
        }

        // Always backfill the UTC offset from Open-Meteo: Tomorrow.io's own
        // sunrise/sunset ARE location-local, but with locationUtcOffsetMins
        // left at 0 every sun/moon progress calc silently uses UTC. The patch
        // also refreshes sunrise/sunset (within minutes) as a side effect.
        try { service._fetchSunTimesOpenMeteo(); } catch (e) {}

        r.weatherDataStaged = service._tio_cur;
        service._tio_cur = null;
        r.loading = false;
        r.updateText = service._formatUpdateText("tomorrowIo");

        // No native alerts - fall back to MeteoAlarm / NWS
        service._fetchAlertsIfNeeded();

        // Air quality fetched in parallel from WeatherService.refreshNow()
    });
}


/** The hours of dateStr (plus the closing 00:00 of the next day) out of one parsed answer. */
function _hourlyDay(d, W, dateStr) {
    var arr = [];
    var nextDateStr = _nextDateStr(dateStr);
    var nextEntry = null;
    var hourlyTimeline = d.timelines && d.timelines.hourly;
    if (hourlyTimeline) {
        hourlyTimeline.forEach(function (h) {
            var dt = new Date(h.time);
            var hDateStr = Qt.formatDate(dt, "yyyy-MM-dd");
            var isTarget = hDateStr === dateStr;
            var isClosing = !nextEntry && hDateStr === nextDateStr;
            if (!isTarget && !isClosing) return;

            var v = h.values;
            var entry = {
                hour: Qt.formatTime(dt, "HH:mm"),
                tempC: v.temperature,
                code: _codeToWmo(v.weatherCode),
                windKmh: (v.windSpeed !== undefined) ? v.windSpeed * 3.6 : NaN,
                windDeg: (v.windDirection !== undefined) ? v.windDirection : NaN,
                humidity: (v.humidity !== undefined) ? Math.round(v.humidity) : NaN,
                precipProb: (v.precipitationProbability !== undefined) ? Math.round(v.precipitationProbability) : NaN,
                precipMm: _precipRate(v)
            };
            if (isTarget) {
                arr.push(entry);
            } else {
                // hourlyTimeline is chronological, so the first match
                // for the next date is its earliest (00:00) hour -
                // append it to close the loop at midnight.
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
    var key = service._tioKey();
    if (!key) {
        Dbg.log("Tomorrow.io", "no API key set in Settings → no hourly forecast");
        r.hourlyData = [];
        return;
    }

    _forecast(service, key, "fetchHourly", "hourly", function (status, d) {
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
    var key = service._tioKey();
    if (!key) {
        Dbg.log("Tomorrow.io", "no API key set in Settings → no hourly forecast");
        callback({});
        return;
    }

    _forecast(service, key, "fetchHourlyAll", "hourly", function (status, d) {
        if (status !== 200 || !d) {
            callback({});
            return;
        }
        callback(_hourlyDays(d, W, firstDate, lastDate));
    });
}
