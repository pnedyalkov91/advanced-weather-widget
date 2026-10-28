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
 * openMeteoHistory.js - Open-Meteo Historical Weather (archive) client
 *
 * Pragma library: no access to Plasmoid/i18n/Qt. Everything it needs comes in
 * through arguments, everything it produces goes out through a callback, so
 * HistoryView.qml owns all config and presentation.
 *
 * Endpoint: https://archive-api.open-meteo.com/v1/archive  (daily aggregates)
 * Values are always requested in metric units (°C, km/h, mm, cm, hPa); the
 * view converts them with weatherRoot.tempValue()/windValue()/... so the
 * user's unit settings are honoured exactly like everywhere else.
 */
.pragma library

var ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive";

/** ERA5 starts in 1940. */
var EARLIEST_DATE = "1940-01-01";

/** Longest range the view will request (keeps the list/chart responsive). */
var MAX_RANGE_DAYS = 366;

/** A day counts as "wet" from this much precipitation (mm), the usual
 *  climatological threshold. */
var WET_DAY_MM = 1.0;

// Core variables - the request falls back to just these if the API rejects
// the wider set for any reason.
var DAILY_CORE = [
    "weather_code",
    "temperature_2m_max", "temperature_2m_min", "temperature_2m_mean",
    "apparent_temperature_max", "apparent_temperature_min",
    "precipitation_sum", "rain_sum", "snowfall_sum", "precipitation_hours",
    "wind_speed_10m_max", "wind_gusts_10m_max", "wind_direction_10m_dominant",
    "sunrise", "sunset", "sunshine_duration", "shortwave_radiation_sum"
];
var DAILY_EXTRA = [
    "relative_humidity_2m_mean", "pressure_msl_mean", "cloud_cover_mean"
];

// ── Date helpers (ISO "YYYY-MM-DD" strings compare correctly as strings) ───
function _pad(n) {
    return (n < 10 ? "0" : "") + n;
}
function toIso(d) {
    return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate());
}
/** Parses "YYYY-MM-DD" to a local-midnight Date (never via Date.parse, which
 *  treats date-only strings as UTC and shifts the day in western timezones). */
function parseIso(s) {
    var p = String(s).split("-");
    return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10));
}
function isIso(s) {
    if (typeof s !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(s))
        return false;
    return toIso(parseIso(s)) === s;
}
function addDays(iso, n) {
    var d = parseIso(iso);
    d.setDate(d.getDate() + n);
    return toIso(d);
}
function daysBetween(a, b) {
    return Math.round((parseIso(b).getTime() - parseIso(a).getTime()) / 86400000);
}
function todayIso() {
    return toIso(new Date());
}
/** The newest day requested by default. Today is skipped on purpose: it is
 *  incomplete, and the Forecast/Details tabs already cover it. */
function latestAvailable() {
    return addDays(todayIso(), -1);
}
function clampIso(iso, lo, hi) {
    if (iso < lo) return lo;
    if (iso > hi) return hi;
    return iso;
}

/**
 * Turns a period preset into a concrete { start, end, clamped } range.
 * preset: yesterday | last7 | last30 | last90 | thisMonth | lastMonth |
 *         thisYear | single | custom
 * startIso/endIso are only used by "single" (start) and "custom".
 * latestIso is the newest selectable day (see latestAvailable()).
 * offset (optional, default 0) pages a preset back in time, one step per unit:
 *   yesterday          1 day per step        (yesterday, 2 days ago, 3 days ago …)
 *   last7/30/90        one whole window      (the 7/30/90 days before the last window)
 *   thisMonth          one calendar month    (a full month once offset > 0)
 *   lastMonth          one calendar month
 *   thisYear           one calendar year     (a full year once offset > 0)
 * "single" and "custom" ignore it - those are stepped with shiftRange().
 */
function resolvePeriod(preset, startIso, endIso, latestIso, offset) {
    var latest = latestIso || latestAvailable();
    var off = (typeof offset === "number" && offset > 0) ? Math.floor(offset) : 0;
    var start = latest;
    var end = latest;
    var now = parseIso(latest);
    var y = now.getFullYear();
    var m = now.getMonth();

    switch (preset) {
    case "yesterday":
        end = addDays(latest, -off);
        start = end;
        break;
    case "last7":
        end = addDays(latest, -7 * off);
        start = addDays(end, -6);
        break;
    case "last90":
        end = addDays(latest, -90 * off);
        start = addDays(end, -89);
        break;
    case "thisMonth":
        start = toIso(new Date(y, m - off, 1));
        if (off > 0)
            end = toIso(new Date(y, m - off + 1, 0));
        break;
    case "lastMonth":
        start = toIso(new Date(y, m - 1 - off, 1));
        end = toIso(new Date(y, m - off, 0));
        break;
    case "thisYear":
        start = toIso(new Date(y - off, 0, 1));
        if (off > 0)
            end = toIso(new Date(y - off, 11, 31));
        break;
    case "single":
        start = isIso(startIso) ? startIso : latest;
        end = start;
        break;
    case "custom":
        start = isIso(startIso) ? startIso : addDays(latest, -6);
        end = isIso(endIso) ? endIso : latest;
        break;
    case "last30":
    default:
        end = addDays(latest, -30 * off);
        start = addDays(end, -29);
        break;
    }

    start = clampIso(start, EARLIEST_DATE, latest);
    end = clampIso(end, EARLIEST_DATE, latest);
    if (start > end)
        start = end;

    var clamped = false;
    if (daysBetween(start, end) + 1 > MAX_RANGE_DAYS) {
        end = addDays(start, MAX_RANGE_DAYS - 1);
        clamped = true;
    }
    return { start: start, end: end, clamped: clamped };
}

/**
 * Moves a picked date range (the "single" / "custom" presets) one range-length
 * older (dir < 0) or newer (dir > 0), keeping its length, and never past
 * [EARLIEST_DATE, latestIso]. A single day therefore steps one day at a time.
 * Returns { start, end }.
 */
function shiftRange(startIso, endIso, dir, latestIso) {
    var latest = latestIso || latestAvailable();
    var start = isIso(startIso) ? startIso : latest;
    var end = isIso(endIso) ? endIso : start;
    if (start > end) {
        var t = start;
        start = end;
        end = t;
    }
    var span = daysBetween(start, end) + 1;
    var step = dir < 0 ? -span : span;
    start = addDays(start, step);
    end = addDays(end, step);
    if (end > latest) {
        end = latest;
        start = addDays(end, -(span - 1));
    }
    if (start < EARLIEST_DATE) {
        start = EARLIEST_DATE;
        end = addDays(start, span - 1);
    }
    return { start: start, end: end };
}

// ── Value helpers ─────────────────────────────────────────────────────────
// Open-Meteo reports "no data for this field/day" as a bare null (the most
// recent days often are, until ERA5 catches up). Treat null/undefined/NaN
// uniformly as NaN so nothing downstream mistakes a gap for a real 0.
function _num(v) {
    return (v === null || v === undefined || (typeof v === "number" && isNaN(v))) ? NaN : v;
}
function _at(arr, i) {
    return arr ? _num(arr[i]) : NaN;
}
function _str(arr, i) {
    var v = arr ? arr[i] : "";
    return (v === null || v === undefined) ? "" : String(v);
}
function _isNum(v) {
    return typeof v === "number" && isFinite(v);
}

// ── Response parsing ─────────────────────────────────────────────────────
function parseDaily(d) {
    var days = [];
    var t = d && d.daily ? d.daily.time : null;
    if (!t)
        return days;
    var q = d.daily;
    for (var i = 0; i < t.length; ++i) {
        var maxC = _at(q.temperature_2m_max, i);
        var minC = _at(q.temperature_2m_min, i);
        var meanC = _at(q.temperature_2m_mean, i);
        if (!_isNum(meanC) && _isNum(maxC) && _isNum(minC))
            meanC = (maxC + minC) / 2;
        days.push({
            dateStr: t[i],
            hasData: _isNum(maxC) || _isNum(minC) || _isNum(meanC),
            code: _at(q.weather_code, i),
            maxC: maxC,
            minC: minC,
            meanC: meanC,
            apparentMaxC: _at(q.apparent_temperature_max, i),
            apparentMinC: _at(q.apparent_temperature_min, i),
            precipMm: _at(q.precipitation_sum, i),
            rainMm: _at(q.rain_sum, i),
            snowCm: _at(q.snowfall_sum, i),
            precipHours: _at(q.precipitation_hours, i),
            windKmh: _at(q.wind_speed_10m_max, i),
            gustKmh: _at(q.wind_gusts_10m_max, i),
            windDir: _at(q.wind_direction_10m_dominant, i),
            sunshineSec: _at(q.sunshine_duration, i),
            radiationMj: _at(q.shortwave_radiation_sum, i),
            humidity: _at(q.relative_humidity_2m_mean, i),
            pressureHpa: _at(q.pressure_msl_mean, i),
            cloudPercent: _at(q.cloud_cover_mean, i),
            sunrise: _str(q.sunrise, i),
            sunset: _str(q.sunset, i)
        });
    }
    return days;
}

function _mean(days, key) {
    var sum = 0, n = 0;
    for (var i = 0; i < days.length; ++i) {
        var v = days[i][key];
        if (_isNum(v)) { sum += v; n++; }
    }
    return n > 0 ? sum / n : NaN;
}
function _sum(days, key) {
    var sum = 0, n = 0;
    for (var i = 0; i < days.length; ++i) {
        var v = days[i][key];
        if (_isNum(v)) { sum += v; n++; }
    }
    return n > 0 ? sum : NaN;
}
/** The day holding the largest (dir=1) or smallest (dir=-1) value of `key`,
 *  as { v, date }, or null when no day has one. */
function _extreme(days, key, dir) {
    var best = null;
    for (var i = 0; i < days.length; ++i) {
        var v = days[i][key];
        if (!_isNum(v))
            continue;
        if (best === null || (dir > 0 ? v > best.v : v < best.v))
            best = { v: v, date: days[i].dateStr };
    }
    return best;
}
function _countWhere(days, key, min) {
    var c = 0;
    for (var i = 0; i < days.length; ++i)
        if (_isNum(days[i][key]) && days[i][key] >= min)
            c++;
    return c;
}

/** Aggregates the days that actually have data. */
function summarize(allDays) {
    var days = [];
    for (var i = 0; i < allDays.length; ++i)
        if (allDays[i].hasData)
            days.push(allDays[i]);

    var sunSec = _sum(days, "sunshineSec");
    return {
        count: days.length,
        avgMeanC: _mean(days, "meanC"),
        avgMaxC: _mean(days, "maxC"),
        avgMinC: _mean(days, "minC"),
        hottest: _extreme(days, "maxC", 1),
        coldest: _extreme(days, "minC", -1),
        totalPrecipMm: _sum(days, "precipMm"),
        wetDays: _countWhere(days, "precipMm", WET_DAY_MM),
        wettest: _extreme(days, "precipMm", 1),
        totalSnowCm: _sum(days, "snowCm"),
        snowDays: _countWhere(days, "snowCm", 0.1),
        maxWind: _extreme(days, "windKmh", 1),
        maxGust: _extreme(days, "gustKmh", 1),
        avgHumidity: _mean(days, "humidity"),
        avgPressureHpa: _mean(days, "pressureHpa"),
        avgCloudPercent: _mean(days, "cloudPercent"),
        totalSunshineHours: _isNum(sunSec) ? sunSec / 3600 : NaN
    };
}

// ── Request ──────────────────────────────────────────────────────────────
function _buildUrl(opts, vars) {
    var tz = (opts.timezone && opts.timezone.length > 0) ? opts.timezone : "auto";
    return ARCHIVE_URL
        + "?latitude=" + Number(opts.latitude).toFixed(4)
        + "&longitude=" + Number(opts.longitude).toFixed(4)
        + "&start_date=" + opts.start
        + "&end_date=" + opts.end
        + "&timezone=" + encodeURIComponent(tz)
        + "&daily=" + vars.join(",");
}

function _errorFrom(req) {
    var reason = "";
    try {
        var j = JSON.parse(req.responseText);
        if (j && j.reason)
            reason = String(j.reason);
    } catch (e) {}
    return { status: req.status, message: reason };
}

// ── Small result cache (module state persists across view instances) ─────
var CACHE_TTL_MS = 15 * 60 * 1000;
var CACHE_MAX = 8;
var _cache = {};
function _remember(key, result) {
    _cache[key] = { t: Date.now(), result: result };
    var keys = Object.keys(_cache);
    if (keys.length > CACHE_MAX) {
        keys.sort(function (a, b) { return _cache[a].t - _cache[b].t; });
        for (var i = 0; i < keys.length - CACHE_MAX; ++i)
            delete _cache[keys[i]];
    }
}

/**
 * Fetches daily history for opts = { latitude, longitude, timezone, start, end[, force] }.
 * callback(err, result):
 *   err    null, or { status, message } (status 0 = network failure/aborted)
 *   result { days: [...], summary: {...}, missingDays, elevation, utcOffsetSeconds }
 * Returns a handle with abort(); an aborted request still invokes the callback
 * (status 0), so callers should guard with their own generation counter.
 */
function fetchHistory(opts, callback) {
    // Reuse a recent identical answer (the popup recreates the tab on every
    // open, and this module-level cache outlives the view). opts.force skips it.
    var cacheKey = _buildUrl(opts, DAILY_CORE.concat(DAILY_EXTRA));
    if (!opts.force) {
        var hit = _cache[cacheKey];
        if (hit && Date.now() - hit.t < CACHE_TTL_MS) {
            callback(null, hit.result);
            return { aborted: false, abort: function () {} };
        }
    }

    var handle = {
        aborted: false,
        _req: null,
        abort: function () {
            this.aborted = true;
            if (this._req)
                this._req.abort();
        }
    };

    function attempt(vars, canFallBack) {
        var req = new XMLHttpRequest();
        handle._req = req;
        req.open("GET", _buildUrl(opts, vars));
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status === 200) {
                try {
                    var d = JSON.parse(req.responseText);
                    var days = parseDaily(d);
                    var missing = 0;
                    for (var i = 0; i < days.length; ++i)
                        if (!days[i].hasData)
                            missing++;
                    var result = {
                        days: days,
                        summary: summarize(days),
                        missingDays: missing,
                        elevation: _num(d.elevation),
                        utcOffsetSeconds: d.utc_offset_seconds !== undefined ? d.utc_offset_seconds : 0
                    };
                    _remember(cacheKey, result);
                    callback(null, result);
                } catch (e) {
                    callback({ status: 200, message: "Unreadable response" }, null);
                }
                return;
            }
            // The wider variable set was rejected - retry once with the core
            // set so the tab still works (humidity/pressure/cloud just read "--").
            if (req.status === 400 && canFallBack && !handle.aborted) {
                attempt(DAILY_CORE, false);
                return;
            }
            callback(_errorFrom(req), null);
        };
        req.send();
    }

    attempt(DAILY_CORE.concat(DAILY_EXTRA), true);
    return handle;
}

// ── Time of the extremes ─────────────────────────────────────────────────
// The daily endpoint only says how warm / windy a day got, not when. Open-Meteo
// computes its daily maxima and minima from the hourly values, so the hour of
// an extreme can be read from the hourly series of that one day. This is done
// for the few days the summary tiles point at (warmest, coldest, strongest
// wind, strongest gust): up to four tiny requests, made after the daily data
// has arrived. If any of them fails, the tile just has no time.
var HOURLY_VARS = ["temperature_2m", "wind_speed_10m", "wind_gusts_10m"];
var _hourlyCache = {};

function _hourlyUrl(opts, date) {
    var tz = (opts.timezone && opts.timezone.length > 0) ? opts.timezone : "auto";
    return ARCHIVE_URL
        + "?latitude=" + Number(opts.latitude).toFixed(4)
        + "&longitude=" + Number(opts.longitude).toFixed(4)
        + "&start_date=" + date
        + "&end_date=" + date
        + "&timezone=" + encodeURIComponent(tz)
        + "&hourly=" + HOURLY_VARS.join(",");
}

/** First hour holding the largest (dir=1) / smallest (dir=-1) value, as { v, t }, or null. */
function _peak(times, vals, dir) {
    var best = null;
    if (!times || !vals)
        return null;
    for (var i = 0; i < times.length; ++i) {
        var v = _num(vals[i]);
        if (!_isNum(v))
            continue;
        if (best === null || (dir > 0 ? v > best.v : v < best.v))
            best = { v: v, t: String(times[i]) };
    }
    return best;
}

function parseHourlyPeaks(d) {
    var h = d && d.hourly ? d.hourly : null;
    if (!h || !h.time)
        return null;
    return {
        maxT: _peak(h.time, h.temperature_2m, 1),
        minT: _peak(h.time, h.temperature_2m, -1),
        wind: _peak(h.time, h.wind_speed_10m, 1),
        gust: _peak(h.time, h.wind_gusts_10m, 1)
    };
}

/** A copy of `summary` whose hottest / coldest / maxWind / maxGust entries
 *  carry `time` ("YYYY-MM-DDTHH:MM", local to the place) where the hourly data
 *  confirms the daily value. peaks: { "<date>": parseHourlyPeaks(...) }. */
function withTimes(summary, peaks) {
    var out = {};
    for (var k in summary)
        out[k] = summary[k];
    function stamp(entry, field) {
        var p = entry ? peaks[entry.date] : null;
        var hit = p ? p[field] : null;
        // The hourly extreme must be the daily value (rounding aside);
        // otherwise the hour would belong to something else.
        if (!hit || Math.abs(hit.v - entry.v) > 0.25)
            return entry;
        return { v: entry.v, date: entry.date, time: hit.t };
    }
    out.hottest = stamp(summary.hottest, "maxT");
    out.coldest = stamp(summary.coldest, "minT");
    out.maxWind = stamp(summary.maxWind, "wind");
    out.maxGust = stamp(summary.maxGust, "gust");
    return out;
}

/**
 * Looks up the hour of the summary's extremes.
 * callback(summaryWithTimes) is called once, only if at least one time was
 * found; returns a handle with abort() (an aborted lookup never calls back).
 */
function fetchExtremeTimes(opts, summary, callback) {
    var dates = [];
    var entries = [summary.hottest, summary.coldest, summary.maxWind, summary.maxGust];
    for (var i = 0; i < entries.length; ++i)
        if (entries[i] && dates.indexOf(entries[i].date) < 0)
            dates.push(entries[i].date);

    var handle = {
        aborted: false,
        _reqs: [],
        abort: function () {
            this.aborted = true;
            for (var r = 0; r < this._reqs.length; ++r)
                this._reqs[r].abort();
        }
    };
    var peaks = {};
    var pending = dates.length;
    if (pending === 0)
        return handle;

    function oneDone() {
        if (--pending > 0 || handle.aborted)
            return;
        var s = withTimes(summary, peaks);
        if (s.hottest !== summary.hottest || s.coldest !== summary.coldest
                || s.maxWind !== summary.maxWind || s.maxGust !== summary.maxGust)
            callback(s);
    }

    dates.forEach(function (date) {
        var url = _hourlyUrl(opts, date);
        var hit = _hourlyCache[url];
        if (hit && Date.now() - hit.t < CACHE_TTL_MS) {
            peaks[date] = hit.peaks;
            oneDone();
            return;
        }
        var req = new XMLHttpRequest();
        handle._reqs.push(req);
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status === 200) {
                try {
                    var p = parseHourlyPeaks(JSON.parse(req.responseText));
                    if (p) {
                        peaks[date] = p;
                        _hourlyCache[url] = { t: Date.now(), peaks: p };
                    }
                } catch (e) {}
            }
            oneDone();
        };
        req.send();
    });
    return handle;
}
