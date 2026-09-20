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
 * openMeteo.js - Open-Meteo current + hourly fetcher
 *
 * Non-pragma JS - accesses config via service properties.
 * Qt global is available; Plasmoid/i18n/Locale are NOT (use service instead).
 */

.import "../js/weather.js" as W

// Open-Meteo represents "this model doesn't report this field" as a bare
// null, NOT a missing key - undefined-only checks (`x !== undefined`) let
// null straight through. That's harmless for a `var`-held value, but once
// it lands on a QML `real`/`int` property (e.g. weatherRoot.uvIndex),
// null gets silently coerced to 0 - while undefined correctly becomes NaN.
// A "real" 0 UV index then displays as "0 (Low)" instead of "--". Always
// route field values through these helpers rather than checking
// `!== undefined` alone.
function _num(v) {
    return (v === null || v === undefined || (typeof v === "number" && isNaN(v))) ? NaN : v;
}
function _numOr(v, fallback) {
    var n = _num(v);
    return isNaN(n) ? fallback : n;
}
// Picks entry[key] when it's a usable value; otherwise falls back to
// backupEntry[key] and marks flag.used so callers know backup was needed.
// Used by the current/daily/hourly mergers so a day/hour/reading is never
// wholesale replaced by the best-match blend just because ONE field (most
// often UV) was null - every field the primary model DID report is kept.
function _pickField(entry, backupEntry, key, flag) {
    var v = entry ? entry[key] : undefined;
    if (v !== null && v !== undefined && !(typeof v === "number" && isNaN(v)))
        return v;
    flag.used = true;
    return backupEntry ? backupEntry[key] : v;
}

/** The calendar date (YYYY-MM-DD) immediately after dateStr, in the widget's
 *  own local time - used to append the closing 00:00 entry so the hourly
 *  forecast reads 00:00..00:00 instead of stopping at 23:00. */
function _nextDateStr(dateStr) {
    var d = new Date(dateStr + "T00:00:00");
    d.setDate(d.getDate() + 1);
    return Qt.formatDate(d, "yyyy-MM-dd");
}

function fetchCurrent(service, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var tz = service.timezone;
    var requestedDays = Math.min(service.forecastDays, 16);
    var url = "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + service.latitude
        + "&longitude=" + service.longitude
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
        + "&forecast_days=" + requestedDays
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,"
        + "weather_code,wind_speed_10m,wind_direction_10m,pressure_msl,"
        + "dew_point_2m,visibility,is_day,precipitation,uv_index,snow_depth"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,"
        + "precipitation_sum,snowfall_sum,precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,"
        + "uv_index_max,pressure_msl_mean,visibility_mean"
        + W.openMeteoModelParam(service.openMeteoModel, service.countryCode);

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        var d = JSON.parse(req.responseText);
        if (!d.current) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        var c = d.current;
        var nd = _parseDailyArray(d, requestedDays);

        // National high-res models (ICON-D2 for Germany, AROME for France,
        // UKMO for the UK, etc.) each cover a different number of days, and
        // several of them omit some "current" fields entirely (UV index
        // most commonly, but precipitation/visibility too) - Open-Meteo
        // represents both cases as null rather than erroring. Detect both
        // here rather than trusting a hardcoded per-country day/field list,
        // since coverage changes over time.
        var currentNeedsBackfill = _isCurrentIncomplete(c);
        var dailyNeedsBackfill = nd.length < requestedDays || nd.some(_isDailyIncomplete);

        function finalize(finalCurrent, finalDaily) {
            if (service._refreshGen !== gen) return;
            r.weatherDataStaged = {
                temperatureC:        _num(finalCurrent.temperature_2m),
                apparentC:           _num(finalCurrent.apparent_temperature),
                humidityPercent:     _num(finalCurrent.relative_humidity_2m),
                windKmh:             _num(finalCurrent.wind_speed_10m),
                windDirection:       _num(finalCurrent.wind_direction_10m),
                pressureHpa:         _num(finalCurrent.pressure_msl),   // sea-level pressure (matches Foreca et al.)
                dewPointC:           _num(finalCurrent.dew_point_2m),
                visibilityKm:        isNaN(_num(finalCurrent.visibility)) ? NaN : finalCurrent.visibility / 1000.0,
                weatherCode:         _numOr(finalCurrent.weather_code, -1),
                isDay:               _numOr(finalCurrent.is_day, -1),
                precipMmh:           _num(finalCurrent.precipitation),
                uvIndex:             _num(finalCurrent.uv_index),
                snowDepthCm:         isNaN(_num(finalCurrent.snow_depth)) ? NaN : finalCurrent.snow_depth * 100,
                locationUtcOffsetMins: (d.utc_offset_seconds !== undefined) ? Math.round(d.utc_offset_seconds / 60) : 0,
                sunriseTimeText:     (d.daily && d.daily.sunrise && d.daily.sunrise.length > 0) ? Qt.formatTime(new Date(d.daily.sunrise[0]), "HH:mm") : "--",
                sunsetTimeText:      (d.daily && d.daily.sunset  && d.daily.sunset.length  > 0) ? Qt.formatTime(new Date(d.daily.sunset[0]),  "HH:mm") : "--",
                dailyData:           finalDaily
            };
            r.loading = false;
            r.updateText = service._formatUpdateText("openMeteo");

            // No native alerts - fall back to MeteoAlarm / NWS
            service._fetchAlertsIfNeeded();
        }

        if (!currentNeedsBackfill && !dailyNeedsBackfill) {
            finalize(c, nd);
            return;
        }

        // Fetch the same range from Open-Meteo's global best-match blend and
        // use it to fill in just the current-fields/days the high-res model
        // didn't cover. _mergeCurrent/_mergeDailyArrays are no-ops for any
        // field the primary model DID report, so it's safe to call this even
        // when only one of the two actually needs backfilling.
        _fetchBackup(service, gen, requestedDays, function (backupCurrent, backupNd) {
            finalize(_mergeCurrent(c, backupCurrent), _mergeDailyArrays(nd, backupNd, requestedDays));
        });
    };
    req.send();
}

// A "current" reading is incomplete when the primary (often national
// high-res) model doesn't report a field for it. temperature/weather_code
// are must-have; uv_index/precipitation/visibility are the fields most
// commonly missing from high-res models' current block - this is the exact
// condition behind the "UV index shows 0" reports: a bare null used to sail
// through untouched and get coerced to 0 by QML's real-property binding.
function _isCurrentIncomplete(c) {
    if (!c) return true;
    if (isNaN(_num(c.temperature_2m))) return true;
    if (isNaN(_num(c.weather_code))) return true;
    if (isNaN(_num(c.uv_index))) return true;
    if (isNaN(_num(c.precipitation))) return true;
    if (isNaN(_num(c.visibility))) return true;
    return false;
}

// Fills in only the current fields the primary model left null, keeping
// every field it DID report (never a wholesale swap to the coarser blend).
function _mergeCurrent(primary, backup) {
    var fields = ["temperature_2m", "apparent_temperature", "relative_humidity_2m",
        "weather_code", "wind_speed_10m", "wind_direction_10m", "pressure_msl",
        "dew_point_2m", "visibility", "is_day", "precipitation", "uv_index", "snow_depth"];
    var flag = { used: false };
    var merged = {};
    for (var i = 0; i < fields.length; ++i)
        merged[fields[i]] = _pickField(primary, backup, fields[i], flag);
    if (flag.used) merged.isBackupModel = true;
    return merged;
}

// Parses the "daily" block of an Open-Meteo /v1/forecast response into the
// widget's internal per-day shape. Shared by the primary (model-specific)
// fetch and the best-match backup fetch used to fill gaps beyond a national
// high-res model's forecast horizon.
function _parseDailyArray(d, requestedDays) {
    var nd = [];
    if (d.daily && d.daily.time) {
        var maxD = Math.min(requestedDays, d.daily.time.length);
        for (var i = 0; i < maxD; ++i)
            nd.push({
                day: Qt.formatDate(new Date(d.daily.time[i]), "ddd"),
                dateStr: d.daily.time[i],
                maxC: d.daily.temperature_2m_max[i],
                minC: d.daily.temperature_2m_min[i],
                code: d.daily.weather_code[i],
                precipMm: d.daily.precipitation_sum ? d.daily.precipitation_sum[i] : NaN,
                snowCm: d.daily.snowfall_sum ? d.daily.snowfall_sum[i] : NaN,
                precipProb: d.daily.precipitation_probability_max ? d.daily.precipitation_probability_max[i] : NaN,
                windKmh: d.daily.wind_speed_10m_max ? d.daily.wind_speed_10m_max[i] : NaN,
                windDir: d.daily.wind_direction_10m_dominant ? d.daily.wind_direction_10m_dominant[i] : NaN,
                uvMax: d.daily.uv_index_max ? d.daily.uv_index_max[i] : NaN,
                pressureHpa: d.daily.pressure_msl_mean ? d.daily.pressure_msl_mean[i] : NaN,
                visibilityKm: d.daily.visibility_mean ? d.daily.visibility_mean[i] / 1000.0 : NaN
            });
    }
    return nd;
}

// A day is "incomplete" when the national high-res model has no forecast
// for it, OR when it covers the day but leaves one field null - Open-Meteo
// represents both cases as null rather than omitting the day or erroring,
// so length alone isn't a reliable signal. UV is the field most commonly
// missing (ICON-D2, AROME, UKMO, etc. cover temp/code but not
// uv_index_max), but precip probability, wind, pressure and visibility can
// be missing too; all are checked so the per-field merge below can fill in
// just the missing value(s) without touching fields the model DID report.
function _isDailyIncomplete(entry) {
    if (!entry) return true;
    if (isNaN(_num(entry.maxC))) return true;
    if (isNaN(_num(entry.minC))) return true;
    if (isNaN(_num(entry.code))) return true;
    if (isNaN(_num(entry.uvMax))) return true;
    if (isNaN(_num(entry.precipMm))) return true;
    if (isNaN(_num(entry.precipProb))) return true;
    if (isNaN(_num(entry.windKmh))) return true;
    if (isNaN(_num(entry.pressureHpa))) return true;
    if (isNaN(_num(entry.visibilityKm))) return true;
    return false;
}

// Fetches the same current + daily range from Open-Meteo's global best-match
// blend, used to fill in whichever current fields and/or days the primary
// (often national high-res) model didn't cover. Deliberately omits &models=
// so Open-Meteo picks its own default, which has full worldwide coverage.
function _fetchBackup(service, gen, requestedDays, callback) {
    var tz = service.timezone;
    var url = "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + service.latitude
        + "&longitude=" + service.longitude
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
        + "&forecast_days=" + requestedDays
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,"
        + "weather_code,wind_speed_10m,wind_direction_10m,pressure_msl,"
        + "dew_point_2m,visibility,is_day,precipitation,uv_index,snow_depth"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,"
        + "precipitation_sum,snowfall_sum,precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,"
        + "uv_index_max,pressure_msl_mean,visibility_mean";

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen || req.status !== 200) {
            callback(null, []);
            return;
        }
        try {
            var d = JSON.parse(req.responseText);
            callback(d.current || null, _parseDailyArray(d, requestedDays));
        } catch (e) {
            callback(null, []);
        }
    };
    req.send();
}

// Merges the model-specific daily array with the best-match backup on a
// PER-FIELD basis, matched by dateStr so timezone/date-boundary differences
// between the two requests can't misalign the days (positional fallback for
// a day the primary fetch didn't return at all). A day flagged incomplete
// only has the specific field(s) that were actually null replaced - e.g. a
// day missing just uvMax keeps its high-res maxC/minC/windKmh/etc. rather
// than being swapped wholesale for the coarser blend's numbers.
function _mergeDailyArrays(primary, backup, requestedDays) {
    var backupByDate = {};
    for (var i = 0; i < backup.length; ++i)
        backupByDate[backup[i].dateStr] = backup[i];

    var fields = ["day", "dateStr", "maxC", "minC", "code", "precipMm", "snowCm",
        "precipProb", "windKmh", "windDir", "uvMax", "pressureHpa", "visibilityKm"];
    var merged = [];
    var len = Math.max(primary.length, requestedDays);
    for (var j = 0; j < len; ++j) {
        var entry = primary[j];
        if (!_isDailyIncomplete(entry)) {
            merged.push(entry);
            continue;
        }
        var backupEntry = (entry && backupByDate[entry.dateStr]) ? backupByDate[entry.dateStr] : backup[j];
        if (!entry && !backupEntry) continue; // nothing for this slot from either source

        var flag = { used: false };
        var mergedEntry = {};
        for (var k = 0; k < fields.length; ++k)
            mergedEntry[fields[k]] = _pickField(entry, backupEntry, fields[k], flag);
        // Only flagged when a field actually came from the blend - a day
        // can trip _isDailyIncomplete and still have every field filled by
        // the primary model except the one that triggered the check.
        if (flag.used) mergedEntry.isBackupModel = true;
        merged.push(mergedEntry);
    }
    return merged;
}

// Air-quality fetching for the default (Open-Meteo) provider path lives in
// WeatherService.qml's _fetchAirQualityOpenMeteo() - the shared fetch every
// provider falls back to - not here. A duplicate, unused _fetchAirQuality()
// used to live in this file (never dispatched from Providers.qml, which has
// no "openMeteo" case in its fetchAirQuality() switch) and had gone stale:
// its result object assigned `index`/`label` twice in the same literal, so
// the european_aqi values it computed were always silently discarded in
// favor of us_aqi. Removed rather than fixed, since WeatherService.qml's
// version is the actual live path and now handles both figures (plus
// Canadian AQHI) correctly - see airQuality.js for the current index math.


function fetchHourly(service, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var tz = service.timezone;
    // end_date is one day past dateStr (not dateStr itself) so the response
    // also carries the following day's 00:00 hour - the entry that closes
    // the hourly forecast's loop at midnight - in the same single request.
    var nextDateStr = _nextDateStr(dateStr);
    var url = "https://api.open-meteo.com/v1/forecast?latitude="
        + service.latitude
        + "&longitude=" + service.longitude
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
        + "&hourly=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,relative_humidity_2m,precipitation_probability,precipitation,pressure_msl,visibility,uv_index"
        + "&start_date=" + dateStr + "&end_date=" + nextDateStr
        + W.openMeteoModelParam(service.openMeteoModel, service.countryCode);
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            r.hourlyData = [];
            return;
        }
        var d = JSON.parse(req.responseText);
        var arr = _parseHourlyArray(d, dateStr, nextDateStr);

        // Same national-model horizon issue as the daily forecast: if
        // dateStr falls outside the high-res model's coverage, Open-Meteo
        // returns either an empty hourly.time array or null-filled hours
        // for it. Backfill from the global best-match blend when needed.
        var needsBackfill = arr.length === 0 || arr.some(_isHourlyIncomplete);
        if (!needsBackfill) {
            r.hourlyData = arr;
            return;
        }

        _fetchHourlyBackup(service, gen, dateStr, nextDateStr, function (backupArr) {
            if (service._refreshGen !== gen) return;
            r.hourlyData = _mergeHourlyArrays(arr, backupArr);
        });
    };
    req.send();
}

// Parses the "hourly" block of an Open-Meteo /v1/forecast response into the
// widget's internal per-hour shape. Shared by the primary (model-specific)
// fetch and the best-match backup fetch. When dateStr/nextDateStr are given,
// keeps only dateStr's own hours plus nextDateStr's exact 00:00 entry
// (flagged isNextDay) - the response covers both dates (see fetchHourly),
// so this is what actually closes the hourly forecast's loop at midnight.
function _parseHourlyArray(d, dateStr, nextDateStr) {
    var arr = [];
    if (d.hourly && d.hourly.time)
        for (var i = 0; i < d.hourly.time.length; ++i) {
            var t = d.hourly.time[i];
            var isTarget = !dateStr || t.substring(0, 10) === dateStr;
            var isClosing = !isTarget && nextDateStr && t === (nextDateStr + "T00:00");
            if (dateStr && !isTarget && !isClosing) continue;
            var entry = {
                timeIso: t,
                hour: Qt.formatTime(new Date(t), "HH:mm"),
                tempC: d.hourly.temperature_2m[i],
                code: d.hourly.weather_code[i],
                windKmh: d.hourly.wind_speed_10m[i],
                windDeg: d.hourly.wind_direction_10m ? d.hourly.wind_direction_10m[i] : NaN,
                humidity: d.hourly.relative_humidity_2m[i],
                precipProb: d.hourly.precipitation_probability ? d.hourly.precipitation_probability[i] : NaN,
                precipMm: d.hourly.precipitation ? d.hourly.precipitation[i] : NaN,
                pressureHpa: d.hourly.pressure_msl ? d.hourly.pressure_msl[i] : NaN,
                visibilityKm: d.hourly.visibility ? d.hourly.visibility[i] / 1000.0 : NaN,
                uvIndex: d.hourly.uv_index ? d.hourly.uv_index[i] : NaN
            };
            if (isClosing) entry.isNextDay = true;
            arr.push(entry);
        }
    return arr;
}

// An hour is "incomplete" when the national high-res model has no data for
// it, OR reports some fields but leaves others null. Mirrors
// _isDailyIncomplete: UV is checked here too now - previously it wasn't,
// so an hourly-only null UV silently passed through as "0 (Low)" even
// after the equivalent daily bug was fixed.
function _isHourlyIncomplete(entry) {
    if (!entry) return true;
    if (isNaN(_num(entry.tempC))) return true;
    if (isNaN(_num(entry.code))) return true;
    if (isNaN(_num(entry.uvIndex))) return true;
    if (isNaN(_num(entry.windKmh))) return true;
    if (isNaN(_num(entry.humidity))) return true;
    if (isNaN(_num(entry.pressureHpa))) return true;
    if (isNaN(_num(entry.visibilityKm))) return true;
    return false;
}

// Fetches the same day (plus the following day, for the midnight-closing
// entry) from Open-Meteo's global best-match blend to use as backfill.
// Deliberately omits &models= so Open-Meteo picks its own default, which has
// full worldwide coverage.
function _fetchHourlyBackup(service, gen, dateStr, nextDateStr, callback) {
    var tz = service.timezone;
    var url = "https://api.open-meteo.com/v1/forecast?latitude="
        + service.latitude
        + "&longitude=" + service.longitude
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
        + "&hourly=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,relative_humidity_2m,precipitation_probability,precipitation,pressure_msl,visibility,uv_index"
        + "&start_date=" + dateStr + "&end_date=" + nextDateStr;
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen || req.status !== 200) {
            callback([]);
            return;
        }
        try {
            var d = JSON.parse(req.responseText);
            callback(_parseHourlyArray(d, dateStr, nextDateStr));
        } catch (e) {
            callback([]);
        }
    };
    req.send();
}

// Merges the model-specific hourly array with the best-match backup on a
// PER-FIELD basis, matched by timeIso (positional fallback for hours the
// primary fetch didn't return at all) - same rationale as _mergeDailyArrays:
// an hour missing just uvIndex keeps its high-res tempC/windKmh/etc.
// instead of being swapped wholesale for the coarser blend's numbers.
function _mergeHourlyArrays(primary, backup) {
    var backupByTime = {};
    for (var i = 0; i < backup.length; ++i)
        backupByTime[backup[i].timeIso] = backup[i];

    var fields = ["timeIso", "hour", "tempC", "code", "windKmh", "windDeg", "humidity",
        "precipProb", "precipMm", "pressureHpa", "visibilityKm", "uvIndex"];
    var len = Math.max(primary.length, backup.length);
    var merged = [];
    for (var j = 0; j < len; ++j) {
        var entry = primary[j];
        if (!_isHourlyIncomplete(entry)) {
            merged.push(entry);
            continue;
        }
        var backupEntry = (entry && backupByTime[entry.timeIso]) ? backupByTime[entry.timeIso] : backup[j];
        if (!entry && !backupEntry) continue;

        var flag = { used: false };
        var mergedEntry = {};
        for (var k = 0; k < fields.length; ++k)
            mergedEntry[fields[k]] = _pickField(entry, backupEntry, fields[k], flag);
        if (flag.used) mergedEntry.isBackupModel = true;
        // Neither field is in `fields` (nothing to backfill per-field) -
        // carry the flag itself across the merge so the closing midnight
        // entry stays marked whichever side it came from.
        if ((entry && entry.isNextDay) || (backupEntry && backupEntry.isNextDay))
            mergedEntry.isNextDay = true;
        merged.push(mergedEntry);
    }
    return merged;
}
