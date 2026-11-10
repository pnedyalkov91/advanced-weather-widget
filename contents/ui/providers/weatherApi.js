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
 * weatherApi.js - WeatherAPI.com current + hourly fetcher
 *
 * Non-pragma JS - accesses config via service properties.
 * Qt global is available; Plasmoid/i18n/Locale are NOT (use service instead).
 * W (weather.js) is passed as a parameter by the caller.
 */

.import "../js/debug.js" as Dbg
.import "../js/sharedGet.js" as Shared

/**
 * Magnus-formula dew-point approximation.
 * T in °C, rh in % → dew point in °C (rounded to 1 decimal).
 */
function _calcDewPoint(T, rh) {
    if (isNaN(T) || isNaN(rh) || rh <= 0)
        return NaN;
    var b = 17.67, c = 243.5;
    var gamma = Math.log(rh / 100.0) + (b * T) / (c + T);
    return Math.round((c * gamma) / (b - gamma) * 10) / 10;
}

/** The calendar date (YYYY-MM-DD) immediately after dateStr, in the widget's
 *  own local time - used to append the closing 00:00 entry so the hourly
 *  forecast reads 00:00..00:00 instead of stopping at 23:00. */
function _nextDateStr(dateStr) {
    var d = new Date(dateStr + "T00:00:00");
    d.setDate(d.getDate() + 1);
    return Qt.formatDate(d, "yyyy-MM-dd");
}

function _apiTimeTo24h(s) {
    if (!s || s === "--")
        return "--";
    var parts = s.trim().split(/\s+/);
    if (parts.length < 2)
        return s;  // already "HH:mm" - pass through
    var hm = parts[0].split(":");
    if (hm.length < 2)
        return s;
    var h = parseInt(hm[0], 10);
    var min = hm[1];
    var ap = parts[1].toUpperCase();
    if (ap === "AM") {
        if (h === 12)
            h = 0;
    } else {
        if (h !== 12)
            h += 12;
    }
    return (h < 10 ? "0" + h : "" + h) + ":" + min;
}

/**
 * The ONE forecast URL every WeatherAPI call uses: current conditions + daily list + native
 * alerts (fetchCurrent) and the hours of every day (fetchHourly / fetchHourlyAll) all come out
 * of the same answer. Keeping the URL identical lets the shared GET helper join / reuse it,
 * so a refresh downloads it once instead of once per caller.
 * `days` is one more than the configured forecast days (the closing 00:00 of the last day
 * lives in the next one), capped at the 14 days the API serves; plans that allow fewer days
 * (the free plan: 3) simply answer with fewer.
 */
function _forecastUrl(service, key) {
    var days = Math.min(14, Math.max(3, service.forecastDays) + 1);
    return "https://api.weatherapi.com/v1/forecast.json?key="
        + encodeURIComponent(key)
        + "&q=" + encodeURIComponent(service.latitude + "," + service.longitude)
        + "&days=" + days + "&alerts=yes";
}

/**
 * The place's UTC offset in minutes, worked out from the answer itself: location.localtime is the
 * wall-clock time there and location.localtime_epoch the same instant in UTC seconds. (Qt's JS
 * cannot resolve the IANA tz_id on its own, which is why the offset used to be fetched from Open-Meteo.)
 * The wall time is cut to whole minutes, so the difference is rounded to a quarter hour - every
 * real UTC offset is a multiple of that. NaN when the answer lacks the two fields.
 */
function _utcOffsetMins(loc) {
    if (!loc || !loc.localtime || loc.localtime_epoch === undefined)
        return NaN;
    var m = /^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2})/.exec(String(loc.localtime));
    if (!m)
        return NaN;
    var wallMs = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
    var off = Math.round((wallMs - Number(loc.localtime_epoch) * 1000) / 60000 / 15) * 15;
    return (off >= -720 && off <= 840) ? off : NaN;
}

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._waKey();
    if (!key) {
        Dbg.log("WeatherAPI", "no API key set in Settings → provider skipped, trying the next one");
        service._tryProvider(chain, idx + 1);
        return;
    }
    var url = _forecastUrl(service, key);

    var req = Shared.xhr("WeatherAPI", "fetchCurrent");
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
        // Air quality: WeatherAPI's current.air_quality["us-epa-index"] is a
        // 1-6 category (Good/Moderate/.../Hazardous - see the removed
        // _waAqiLabel() that used to map it), not the 0-500 numeric US AQI
        // that usAqi/bandForUsAqi() expect elsewhere, so it can't be merged
        // in directly without misreading a category number as if it were an
        // AQI value. The &aqi=yes request param has been dropped along with
        // it. Providers.qml has no "weatherApi" case in its
        // fetchAirQuality() switch, so WeatherService.refreshNow() already
        // falls through to the shared Open-Meteo air-quality fetch
        // unconditionally for this provider - that's the sole source of
        // pollutants and all three index values here, same as for most
        // other providers.
        var astro = (d.forecast && d.forecast.forecastday && d.forecast.forecastday.length > 0)
            ? d.forecast.forecastday[0].astro : null;
        var nd = [];
        if (d.forecast && d.forecast.forecastday) {
            var maxD = Math.min(service.forecastDays, d.forecast.forecastday.length);
            for (var i = 0; i < maxD; ++i) {
                var f = d.forecast.forecastday[i];
                nd.push({
                    day: Qt.formatDate(new Date(f.date), "ddd"),
                    dateStr: f.date,
                    maxC: f.day.maxtemp_c,
                    minC: f.day.mintemp_c,
                    code: W.weatherApiCodeToWmo(f.day.condition.code),
                    precipMm: (f.day.totalprecip_mm !== undefined) ? f.day.totalprecip_mm : NaN,
                    snowCm: (f.day.totalsnow_cm !== undefined) ? f.day.totalsnow_cm : NaN,
                    precipProb: (f.day.daily_chance_of_rain !== undefined) ? f.day.daily_chance_of_rain : NaN,
                    windKmh: (f.day.maxwind_kph !== undefined) ? f.day.maxwind_kph : NaN,
                    windDir: NaN
                });
            }
        }
        var utcOffMins = _utcOffsetMins(d.location);
        var sunriseText = astro ? _apiTimeTo24h(astro.sunrise) : "--";
        var sunsetText  = astro ? _apiTimeTo24h(astro.sunset)  : "--";
        r.weatherDataStaged = {
            temperatureC:    d.current.temp_c,
            apparentC:       d.current.feelslike_c,
            humidityPercent: d.current.humidity,
            pressureHpa:     d.current.pressure_mb,
            windKmh:         d.current.wind_kph,
            windDirection:   (d.current.wind_degree !== undefined) ? d.current.wind_degree : NaN,
            dewPointC:       (d.current.dewpoint_c !== undefined && d.current.dewpoint_c !== null)
                                ? d.current.dewpoint_c
                                : _calcDewPoint(d.current.temp_c, d.current.humidity),
            visibilityKm:    d.current.vis_km,
            precipMmh:       (d.current.precip_mm !== undefined) ? d.current.precip_mm : NaN,
            uvIndex:         (d.current.uv !== undefined) ? d.current.uv : NaN,
            snowDepthCm:     NaN,
            weatherCode:     d.current.condition ? W.weatherApiCodeToWmo(d.current.condition.code) : 2,
            isDay:           (d.current.is_day !== undefined) ? d.current.is_day : -1,
            locationUtcOffsetMins: isNaN(utcOffMins) ? 0 : utcOffMins,
            sunriseTimeText: sunriseText,
            sunsetTimeText:  sunsetText,
            dailyData:       nd
        };
        r.loading = false;
        r.updateText = service._formatUpdateText("weatherApi");

        // WeatherAPI's astro sunrise/sunset are location-local and the UTC offset comes from
        // location.localtime / localtime_epoch (see _utcOffsetMins), so nothing else is needed.
        // Only when the answer lacks one of them does the Open-Meteo backfill still fill the gap.
        var timeRe = /^\d{1,2}:\d{2}$/;
        if (isNaN(utcOffMins) || !timeRe.test(sunriseText) || !timeRe.test(sunsetText)) {
            try { service._fetchSunTimesOpenMeteo(); } catch (e) {}
        }

        // Parse native alerts if available
        if (d.alerts && d.alerts.alert && d.alerts.alert.length > 0) {
            if (_parseAlerts(r, d.alerts.alert))
                service._nativeAlertsSetThisGen = true;
        }

        // Fall back to MeteoAlarm / NWS if no native alerts
        service._fetchAlertsIfNeeded();
    };
    req.send();
}

function _parseAlerts(r, alerts) {
    var parsed = [];
    var now = new Date();
    for (var i = 0; i < alerts.length; i++) {
        var a = alerts[i];
        // Skip expired
        if (a.expires) {
            var exp = new Date(a.expires);
            if (exp < now) continue;
        }

        // Map severity to MeteoAlarm-compatible color
        var color = "";
        var severity = (a.severity || "").toLowerCase();
        if (severity === "extreme") color = "red";
        else if (severity === "severe") color = "red";
        else if (severity === "moderate") color = "orange";
        else if (severity === "minor") color = "yellow";

        parsed.push({
            headline: a.headline || a.event || "",
            displayName: a.event || a.headline || "",
            severity: a.severity || "",
            description: a.desc || "",
            event: a.event || "",
            area: a.areas || "",
            color: color,
            awarenessType: 0,
            onset: a.effective || "",
            effective: a.effective || "",
            expires: a.expires || "",
            instruction: a.instruction || "",
            web: "",
            source: "WeatherAPI",
            action: a.msgtype || "",
            senderName: a.note || ""
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
            hour: Qt.formatTime(new Date(h.time_epoch * 1000), "HH:mm"),
            tempC: h.temp_c,
            code: W.weatherApiCodeToWmo(h.condition.code),
            windKmh: h.wind_kph,
            windDeg: h.wind_degree,
            humidity: h.humidity,
            precipProb: (h.chance_of_rain !== undefined)
                ? h.chance_of_rain : NaN,
            precipMm: (h.precip_mm !== undefined) ? h.precip_mm : NaN
        };
    }
    var nextDateStr = _nextDateStr(dateStr);
    var arr = [];
    if (d.forecast && d.forecast.forecastday) {
        d.forecast.forecastday.forEach(function (day) {
            if (day.date === dateStr && day.hour)
                day.hour.forEach(function (h) { arr.push(buildEntry(h)); });
        });
        var tomorrow = d.forecast.forecastday.filter(function (day) {
            return day.date === nextDateStr;
        })[0];
        if (tomorrow && tomorrow.hour && tomorrow.hour.length > 0) {
            var closing = buildEntry(tomorrow.hour[0]);
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
    var key = service._waKey();
    if (!key) {
        Dbg.log("WeatherAPI", "no API key set in Settings → no hourly forecast");
        r.hourlyData = [];
        return;
    }
    var nextDateStr = _nextDateStr(dateStr);
    // WeatherAPI's `dt` parameter "restricts date output" to that single day
    // only, which left no way to reach the next day's 00:00 (the entry that
    // closes the hourly forecast's loop at midnight) without a second
    // request. Requesting the same multi-day window fetchCurrent already
    // uses instead - wide enough to cover dateStr's following day even when
    // dateStr is the last configured forecast day - keeps this to one
    // request and lets both dates be picked out of the same response.
    var url = _forecastUrl(service, key);
    var req = Shared.xhr("WeatherAPI", "fetchHourly");
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


        r.setHourlyResult(dateStr, _hourlyDay(d, W, dateStr));
    };
    req.send();
}

/** Hours of every day firstDate..lastDate from ONE request: callback({ dateStr: [hours] }), {} on any failure. */
function fetchHourlyAll(service, W, firstDate, lastDate, callback) {
    var dateStr = firstDate;
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._waKey();
    if (!key) {
        Dbg.log("WeatherAPI", "no API key set in Settings → no hourly forecast");
        callback({});
        return;
    }
    var nextDateStr = _nextDateStr(dateStr);
    // WeatherAPI's `dt` parameter "restricts date output" to that single day
    // only, which left no way to reach the next day's 00:00 (the entry that
    // closes the hourly forecast's loop at midnight) without a second
    // request. Requesting the same multi-day window fetchCurrent already
    // uses instead - wide enough to cover dateStr's following day even when
    // dateStr is the last configured forecast day - keeps this to one
    // request and lets both dates be picked out of the same response.
    var url = _forecastUrl(service, key);
    var req = Shared.xhr("WeatherAPI", "fetchHourlyAll");
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (req.status !== 200) {
            callback({});
            return;
        }
        var d;
        try {
            d = JSON.parse(req.responseText);
        } catch (e) {
            callback({});
            return;
        }


        callback(_hourlyDays(d, W, firstDate, lastDate));
    };
    req.send();
}
