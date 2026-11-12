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
 * visualCrossing.js - Visual Crossing current + hourly fetcher
 *
 * Non-pragma JS - accesses config via service properties.
 * Visual Crossing Timeline API provides current conditions, daily and hourly forecasts.
 * Uses Dark Sky-compatible icon names.
 * Docs: https://www.visualcrossing.com/resources/documentation/weather-api/
 */

.import "../js/debug.js" as Dbg
.import "../js/sharedGet.js" as Shared
.import "../js/refusals.js" as Refusals

/**
 * Maps a Visual Crossing icon string to a WMO weather code.
 * VC uses an extended Dark Sky-compatible icon set (icons2).
 */
function _iconToWmo(icon) {
    if (!icon) return 2;
    switch (icon) {
        case "clear-day":
        case "clear-night":
            return 0;
        case "partly-cloudy-day":
        case "partly-cloudy-night":
            return 2;
        case "cloudy":
            return 3;
        case "rain":
            return 63;
        case "showers-day":
        case "showers-night":
            return 80;
        case "snow":
            return 73;
        case "snow-showers-day":
        case "snow-showers-night":
            return 85;
        case "sleet":
            return 66;
        case "wind":
            return 2;
        case "fog":
            return 45;
        case "thunder-rain":
        case "thunder-showers-day":
        case "thunder-showers-night":
            return 95;
        case "hail":
            return 99;
        default:
            return 2;
    }
}

/**
 * Determine isDay from the icon string.
 * Returns 1 for day, 0 for night, -1 for unknown.
 */
function _iconIsDay(icon) {
    if (!icon) return -1;
    if (icon.indexOf("-night") >= 0) return 0;
    if (icon.indexOf("-day") >= 0) return 1;
    return -1;
}

/** The calendar date (YYYY-MM-DD) immediately after dateStr, in the widget's
 *  own local time - used to append the closing 00:00 entry so the hourly
 *  forecast reads 00:00..00:00 instead of stopping at 23:00. */
function _nextDateStr(dateStr) {
    var d = new Date(dateStr + "T00:00:00");
    d.setDate(d.getDate() + 1);
    return Qt.formatDate(d, "yyyy-MM-dd");
}

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._vcKey();
    if (!key) {
        Dbg.log("Visual Crossing", "no API key set in Settings → provider skipped, trying the next one");
        service._tryProvider(chain, idx + 1);
        return;
    }
    var refused = Refusals.active("visualCrossing", key);
    if (refused) {
        Refusals.logSkip("Visual Crossing", "fetchCurrent", refused);
        service._tryProvider(chain, idx + 1);
        return;
    }

    var url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/"
        + service.latitude + "," + service.longitude
        + "?key=" + encodeURIComponent(key)
        + "&unitGroup=metric"
        + "&include=current,days,alerts"
        + "&iconSet=icons2";

    var req = Shared.xhr("Visual Crossing", "fetchCurrent");
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            if (Refusals.isRefusal(req.status))
                Refusals.note("visualCrossing", req.status, key);
            service._tryProvider(chain, idx + 1);
            return;
        }
        try {
            var d = JSON.parse(req.responseText);
        } catch (e) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        if (!d.currentConditions) {
            service._tryProvider(chain, idx + 1);
            return;
        }

        var c = d.currentConditions;
        var nd = [];
        if (d.days) {
            var maxD = Math.min(service.forecastDays, d.days.length);
            for (var i = 0; i < maxD; i++) {
                var dd = d.days[i];
                nd.push({
                    day: Qt.formatDate(new Date(dd.datetime + "T12:00:00"), "ddd"),
                    dateStr: dd.datetime,
                    maxC: (dd.tempmax !== undefined) ? dd.tempmax : NaN,
                    minC: (dd.tempmin !== undefined) ? dd.tempmin : NaN,
                    code: _iconToWmo(dd.icon),
                    precipMm: (dd.precip !== undefined) ? dd.precip : NaN,
                    snowCm: (dd.snow !== undefined) ? dd.snow : NaN,
                    precipProb: (dd.precipprob !== undefined) ? dd.precipprob : NaN,
                    windKmh: (dd.windspeed !== undefined) ? dd.windspeed : NaN,
                    windDir: (dd.winddir !== undefined) ? dd.winddir : NaN
                });
            }
        }
        r.weatherDataStaged = {
            temperatureC:    c.temp,
            apparentC:       c.feelslike,
            humidityPercent: (c.humidity !== undefined) ? c.humidity : NaN,
            windKmh:         (c.windspeed !== undefined) ? c.windspeed : NaN,
            windDirection:   (c.winddir !== undefined) ? c.winddir : NaN,
            pressureHpa:     (c.pressure !== undefined) ? c.pressure : NaN,
            dewPointC:       (c.dew !== undefined) ? c.dew : NaN,
            visibilityKm:    (c.visibility !== undefined) ? c.visibility : NaN,
            precipMmh:       (c.precip !== undefined) ? c.precip : NaN,
            uvIndex:         (c.uvindex !== undefined) ? c.uvindex : NaN,
            snowDepthCm:     (c.snowdepth !== undefined) ? c.snowdepth : NaN,
            weatherCode:     _iconToWmo(c.icon),
            isDay:           _iconIsDay(c.icon),
            locationUtcOffsetMins: (d.tzoffset !== undefined) ? Math.round(d.tzoffset * 60) : 0,
            sunriseTimeText: c.sunrise ? c.sunrise.substring(0, 5) : "--",
            sunsetTimeText:  c.sunset  ? c.sunset.substring(0, 5)  : "--",
            dailyData:       nd
        };
        // No native air quality or pollen - both are supplied by the shared
        // Open-Meteo fetch started in WeatherService.refreshNow(). Clearing
        // them here would race that fetch and discard its result.
        r.loading = false;
        r.updateText = service._formatUpdateText("visualCrossing");

        // Parse alerts if available
        if (d.alerts && d.alerts.length > 0) {
            if (_parseAlerts(r, d.alerts))
                service._nativeAlertsSetThisGen = true;
        }

        // Fall back to MeteoAlarm / NWS if no native alerts
        service._fetchAlertsIfNeeded();

        // Air quality fetched in parallel from WeatherService.refreshNow()
    };
    req.send();
}

// Titles that only say "there is nothing to warn about" (Bulgarian, English)
var _NO_DANGER_RE = /^(няма опасност|no danger|no warnings?|no alerts?|no special awareness required|no awareness (needed|required))[.!\s]*$/i;

function _parseAlerts(r, alerts) {
    var parsed = [];
    var now = new Date();
    for (var i = 0; i < alerts.length; i++) {
        var a = alerts[i];
        // Debug only: Visual Crossing sends no severity, so show what each alert really carries
        Dbg.log("Visual Crossing", "native alert #" + i + ": fields=[" + Object.keys(a).join(",") + "] event=\"" + (a.event || "")
            + "\" headline=\"" + (a.headline || "") + "\" onset=" + (a.onset || "-") + " ends=" + (a.ends || "-")
            + " description=" + String(a.description || "").length + " chars: \"" + String(a.description || "").substring(0, 120)
            + "\" id=" + String(a.id || "-").substring(0, 60) + " link=" + String(a.link || "-").substring(0, 100)
            + " language=" + (a.language || "-"));
        // Skip expired
        if (a.ends) {
            var exp = new Date(a.ends);
            if (exp < now) continue;
        }

        // Some national feeds (e.g. weather.bg for Bulgaria) pass their "no danger" level through
        // as an ordinary alert ("Няма опасност"). Visual Crossing gives no severity to tell it
        // apart, so only an explicit "nothing to report" title is dropped.
        if (_NO_DANGER_RE.test(String(a.event || a.headline || "").trim()))
            continue;
        // Placeholder descriptions such as "---" carry no information
        var desc = /^[\s\-–—.]*$/.test(String(a.description || "")) ? "" : String(a.description);

        parsed.push({
            headline: a.headline || a.event || "",
            displayName: a.event || a.headline || "",
            severity: "",
            description: desc,
            event: a.event || "",
            area: "",
            color: "orange",
            awarenessType: 0,
            onset: a.onset || "",
            effective: a.onset || "",
            expires: a.ends || "",
            instruction: "",
            web: a.link || "",
            source: "VisualCrossing",
            action: "",
            senderName: ""
        });
    }

    if (parsed.length > 0) {
        r.weatherAlerts = parsed;
        return true;
    }
    return false;
}


/** The hours of dateStr (plus the closing 00:00 of the next day) out of one parsed answer. */
function _hourlyDay(d, W, dateStr) {
    function buildEntry(h) {
        return {
            hour: h.datetime ? h.datetime.substring(0, 5) : "--",
            tempC: h.temp,
            code: _iconToWmo(h.icon),
            windKmh: (h.windspeed !== undefined) ? h.windspeed : NaN,
            windDeg: (h.winddir !== undefined) ? h.winddir : NaN,
            humidity: (h.humidity !== undefined) ? Math.round(h.humidity) : NaN,
            precipProb: (h.precipprob !== undefined) ? Math.round(h.precipprob) : NaN,
            precipMm: (h.precip !== undefined) ? h.precip : NaN
        };
    }
    var nextDateStr = _nextDateStr(dateStr);
    var arr = [];
    if (d.days) {
        var today = d.days.filter(function (day) { return day.datetime === dateStr; })[0];
        if (today && today.hours)
            today.hours.forEach(function (h) { arr.push(buildEntry(h)); });

        var tomorrow = d.days.filter(function (day) { return day.datetime === nextDateStr; })[0];
        if (tomorrow && tomorrow.hours && tomorrow.hours.length > 0) {
            var closing = buildEntry(tomorrow.hours[0]);
            closing.isNextDay = true;
            arr.push(closing);
        }
    }
    
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
    var key = service._vcKey();
    if (!key) {
        Dbg.log("Visual Crossing", "no API key set in Settings → no hourly forecast");
        r.hourlyData = [];
        return;
    }
    var refused = Refusals.active("visualCrossing", key);
    if (refused) {
        Refusals.logSkip("Visual Crossing", "fetchHourly", refused);
        r.hourlyData = [];
        return;
    }

    // Request dateStr through the following day (not dateStr alone), so the
    // one response also carries the next day's 00:00 hour needed to close
    // the forecast's loop at midnight.
    var nextDateStr = _nextDateStr(dateStr);
    var url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/"
        + service.latitude + "," + service.longitude
        + "/" + dateStr + "/" + nextDateStr
        + "?key=" + encodeURIComponent(key)
        + "&unitGroup=metric"
        + "&include=hours"
        + "&iconSet=icons2";

    var req = Shared.xhr("Visual Crossing", "fetchHourly");
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            if (Refusals.isRefusal(req.status))
                Refusals.note("visualCrossing", req.status, key);
            r.hourlyData = [];
            return;
        }
        try {
            var d = JSON.parse(req.responseText);
        } catch (e) {
            r.hourlyData = [];
            return;
        }


        r.setHourlyResult(dateStr, _hourlyDay(d, W, dateStr));
    };
    req.send();
}

/** Hours of every day firstDate..lastDate from ONE request: callback({ dateStr: [hours] }), {} on any failure. */
function fetchHourlyAll(service, W, firstDate, lastDate, callback) {
    var dateStr = firstDate;
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._vcKey();
    if (!key) {
        Dbg.log("Visual Crossing", "no API key set in Settings → no hourly forecast");
        callback({});
        return;
    }
    var refused = Refusals.active("visualCrossing", key);
    if (refused) {
        Refusals.logSkip("Visual Crossing", "fetchHourlyAll", refused);
        callback({});
        return;
    }

    // Request dateStr through the following day (not dateStr alone), so the
    // one response also carries the next day's 00:00 hour needed to close
    // the forecast's loop at midnight.
    var nextDateStr = _nextDateStr(dateStr);
    var url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/"
        + service.latitude + "," + service.longitude
        + "/" + firstDate + "/" + _nextDateStr(lastDate)
        + "?key=" + encodeURIComponent(key)
        + "&unitGroup=metric"
        + "&include=hours"
        + "&iconSet=icons2";

    var req = Shared.xhr("Visual Crossing", "fetchHourlyAll");
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (req.status !== 200) {
            if (Refusals.isRefusal(req.status))
                Refusals.note("visualCrossing", req.status, key);
            callback({});
            return;
        }
        try {
            var d = JSON.parse(req.responseText);
        } catch (e) {
            callback({});
            return;
        }


        callback(_hourlyDays(d, W, firstDate, lastDate));
    };
    req.send();
}
