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
 * pirateWeather.js - Pirate Weather current + hourly fetcher
 *
 * Non-pragma JS - accesses config via service properties.
 * Qt global is available; Plasmoid/i18n/Locale are NOT (use service instead).
 * W (weather.js) is passed as a parameter by the caller.
 *
 * Pirate Weather is a Dark Sky API-compatible service.
 * Docs: https://docs.pirateweather.net/en/latest/API/
 */

/**
 * Maps a Pirate Weather / Dark Sky icon string to a WMO weather code.
 */
function _iconToWmo(icon) {
    if (!icon) return 2;
    switch (icon) {
        case "clear-day":
        case "clear-night":
            return 0;
        case "partly-cloudy-day":
        case "partly-cloudy-night":
        case "mostly-clear-day":
        case "mostly-clear-night":
            return 2;
        case "cloudy":
        case "mostly-cloudy-day":
        case "mostly-cloudy-night":
            return 3;
        case "rain":
        case "light-rain":
        case "heavy-rain":
        case "drizzle":
        case "possible-rain-day":
        case "possible-rain-night":
            return 63;
        case "snow":
        case "light-snow":
        case "heavy-snow":
        case "flurries":
        case "possible-snow-day":
        case "possible-snow-night":
            return 73;
        case "sleet":
        case "light-sleet":
        case "heavy-sleet":
        case "very-light-sleet":
        case "possible-sleet-day":
        case "possible-sleet-night":
            return 66;
        case "wind":
        case "breezy":
        case "dangerous-wind":
            return 2;
        case "fog":
        case "mist":
        case "haze":
            return 45;
        case "thunderstorm":
        case "possible-thunderstorm-day":
        case "possible-thunderstorm-night":
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
    var key = service._pwKey();
    if (!key) {
        service._tryProvider(chain, idx + 1);
        return;
    }

    // Use ca units: Celsius temps, km/h wind, hPa pressure, km visibility
    var url = "https://api.pirateweather.net/forecast/"
        + encodeURIComponent(key) + "/"
        + service.latitude + "," + service.longitude
        + "?units=ca&exclude=minutely&version=2";

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
        try {
            var d = JSON.parse(req.responseText);
        } catch (e) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        if (!d.currently) {
            service._tryProvider(chain, idx + 1);
            return;
        }

        var c = d.currently;
        var day0 = (d.daily && d.daily.data && d.daily.data.length > 0) ? d.daily.data[0] : null;
        var nd = [];
        if (d.daily && d.daily.data) {
            var maxD = Math.min(service.forecastDays, d.daily.data.length);
            for (var i = 0; i < maxD; i++) {
                var dd = d.daily.data[i];
                nd.push({
                    day: Qt.formatDate(new Date(dd.time * 1000), "ddd"),
                    dateStr: Qt.formatDate(new Date(dd.time * 1000), "yyyy-MM-dd"),
                    maxC: (dd.temperatureMax !== undefined) ? dd.temperatureMax : dd.temperatureHigh,
                    minC: (dd.temperatureMin !== undefined) ? dd.temperatureMin : dd.temperatureLow,
                    code: _iconToWmo(dd.icon),
                    precipMm: (dd.precipAccumulation !== undefined) ? dd.precipAccumulation * 10 : NaN,
                    snowCm: (dd.snowAccumulation !== undefined) ? dd.snowAccumulation : NaN,
                    precipProb: (dd.precipProbability !== undefined) ? Math.round(dd.precipProbability * 100) : NaN,
                    windKmh: (dd.windSpeed !== undefined) ? dd.windSpeed : NaN,
                    windDir: (dd.windBearing !== undefined) ? dd.windBearing : NaN
                });
            }
        }
        r.weatherDataStaged = {
            temperatureC:    c.temperature,
            apparentC:       c.apparentTemperature,
            humidityPercent: (c.humidity !== undefined) ? c.humidity * 100 : NaN,
            windKmh:         (c.windSpeed !== undefined) ? c.windSpeed : NaN,
            windDirection:   (c.windBearing !== undefined) ? c.windBearing : NaN,
            pressureHpa:     (c.pressure !== undefined) ? c.pressure : NaN,
            dewPointC:       (c.dewPoint !== undefined) ? c.dewPoint : NaN,
            visibilityKm:    (c.visibility !== undefined) ? c.visibility : NaN,
            precipMmh:       (c.precipIntensity !== undefined) ? c.precipIntensity : NaN,
            uvIndex:         (c.uvIndex !== undefined) ? c.uvIndex : NaN,
            snowDepthCm:     NaN,
            weatherCode:     _iconToWmo(c.icon),
            isDay:           _iconIsDay(c.icon),
            locationUtcOffsetMins: (d.offset !== undefined) ? Math.round(d.offset * 60) : 0,
            sunriseTimeText: day0 && day0.sunriseTime ? Qt.formatTime(new Date(day0.sunriseTime * 1000), "HH:mm") : "--",
            sunsetTimeText:  day0 && day0.sunsetTime  ? Qt.formatTime(new Date(day0.sunsetTime  * 1000), "HH:mm") : "--",
            dailyData:       nd
        };
        // No native air quality or pollen - both are supplied by the shared
        // Open-Meteo fetch started in WeatherService.refreshNow(). Clearing
        // them here would race that fetch and discard its result.
        r.loading = false;
        r.updateText = service._formatUpdateText("pirateWeather");

        // Pirate Weather provides its own alerts - parse them
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

function _parseAlerts(r, alerts) {
    var parsed = [];
    var now = new Date();
    for (var i = 0; i < alerts.length; i++) {
        var a = alerts[i];
        // Skip expired
        if (a.expires && a.expires > 0) {
            var exp = new Date(a.expires * 1000);
            if (exp < now) continue;
        }

        // Map severity to MeteoAlarm-compatible color
        var color = "";
        var severity = (a.severity || "").toLowerCase();
        if (severity === "extreme") color = "red";
        else if (severity === "severe") color = "red";
        else if (severity === "moderate") color = "orange";
        else if (severity === "minor") color = "yellow";

        var regions = (a.regions && a.regions.length > 0) ? a.regions.join(", ") : "";

        parsed.push({
            headline: a.title || "",
            displayName: a.title || "",
            severity: a.severity || "",
            description: a.description || "",
            event: a.title || "",
            area: regions,
            color: color,
            awarenessType: 0,
            onset: a.time ? new Date(a.time * 1000).toISOString() : "",
            effective: a.time ? new Date(a.time * 1000).toISOString() : "",
            expires: a.expires ? new Date(a.expires * 1000).toISOString() : "",
            instruction: "",
            web: a.uri || "",
            source: "PirateWeather",
            action: "",
            senderName: ""
        });
    }

    // Only update if we actually got alerts from PW
    if (parsed.length > 0) {
        r.weatherAlerts = parsed;
        return true;
    }
    return false;
}


function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._pwKey();
    if (!key) {
        r.hourlyData = [];
        return;
    }

    // Pirate Weather returns 48h of hourly data by default, 168h with extend=hourly
    var url = "https://api.pirateweather.net/forecast/"
        + encodeURIComponent(key) + "/"
        + service.latitude + "," + service.longitude
        + "?units=ca&exclude=minutely,daily,alerts&extend=hourly";

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
        try {
            var d = JSON.parse(req.responseText);
        } catch (e) {
            r.hourlyData = [];
            return;
        }

        var arr = [];
        var nextDateStr = _nextDateStr(dateStr);
        var nextEntry = null;
        if (d.hourly && d.hourly.data) {
            d.hourly.data.forEach(function (h) {
                var dt = new Date(h.time * 1000);
                var hDateStr = Qt.formatDate(dt, "yyyy-MM-dd");
                var isTarget = hDateStr === dateStr;
                var isClosing = !nextEntry && hDateStr === nextDateStr;
                if (!isTarget && !isClosing) return;

                var entry = {
                    hour: Qt.formatTime(dt, "HH:mm"),
                    tempC: h.temperature,
                    code: _iconToWmo(h.icon),
                    windKmh: (h.windSpeed !== undefined) ? h.windSpeed : NaN,
                    windDeg: (h.windBearing !== undefined) ? h.windBearing : NaN,
                    humidity: (h.humidity !== undefined) ? Math.round(h.humidity * 100) : NaN,
                    precipProb: (h.precipProbability !== undefined) ? Math.round(h.precipProbability * 100) : NaN,
                    precipMm: (h.precipIntensity !== undefined) ? h.precipIntensity : NaN
                };
                if (isTarget) {
                    arr.push(entry);
                } else {
                    // Data is chronological, so the first match for the next
                    // date is its earliest (00:00) hour - append it to close
                    // the hourly forecast's loop at midnight.
                    entry.isNextDay = true;
                    nextEntry = entry;
                }
            });
        }
        if (nextEntry) arr.push(nextEntry);
        r.hourlyData = arr;
    };
    req.send();
}

/**
 * Converts a gas concentration from parts-per-billion to micrograms per
 * cubic metre at 25°C / 1 atm (the conversion EPA/WHO use), so that
 * o3/no2/so2/co line up with pm10/pm2_5, which PW already reports in µg/m³.
 *   µg/m³ = ppb * molarMass / 24.45
 */
function _ppbToUgm3(ppb, molarMass) {
    if (ppb === undefined || ppb === null || isNaN(ppb)) return NaN;
    return ppb * molarMass / 24.45;
}

var _MOLAR_MASS = { o3: 48.00, no2: 46.01, so2: 64.07, co: 28.01 };

/**
 * fetchAirQuality - native Pirate Weather air quality.
 *
 * IMPORTANT UNITS CAVEAT:
 * The main fetchCurrent() request uses units=ca, but PW ties the AQI
 * *scale* to the units param: ca -> ECCC AQHI (1-10ish), us/default ->
 * US EPA AQI (0-500), si/uk -> EU CAQI (0-100+). This function only ever
 * contributes the CAQI figure (see below), so reusing fetchCurrent's
 * ca-units response would hand the widget a badly-mismatched number.
 *
 * Rather than reimplement PW's CAQI breakpoint math locally (risking a
 * different number than PW's own service would report), this issues one
 * extra, deliberately small request with units=si to get PW's own
 * authoritative EU CAQI value straight from the source. Pollutant
 * concentrations (pm25/pm10 in µg/m³, the rest in ppb) don't change with
 * units, so this request is intentionally scoped to `currently` only.
 *
 * Gas concentrations are converted ppb -> µg/m³ to match pm10/pm2_5, which
 * is what airQuality.js's per-pollutant bands expect for o3/no2/so2. CO is
 * the exception: its band table is in mg/m³, so it takes a further /1000.
 *
 * This function only ever contributes europeanAqi (via _mergeAqiData and
 * _nativeAqiSetThisGen) - PW has no US AQI or AQHI calculation of its own.
 * That means its result is only actually *displayed* when the resolved
 * standard for the user's location is CAQI; everywhere else it's still
 * merged in (harmless - that field just isn't read at render time). US AQI,
 * Canadian AQHI, and pollen always come from the shared Open-Meteo fetch, so
 * every code path below - including the early-return failure cases - calls
 * service._fetchAqi() before returning, the same way fetchCurrent() always
 * calls _fetchAlertsIfNeeded(). That fetch is unconditional now (it no
 * longer skips itself when _nativeAqiSetThisGen is set), so pollen and the
 * non-CAQI standards resolve correctly even when this native request
 * succeeds.
 */
function fetchAirQuality(service, W) {
    var gen = service._refreshGen;
    var key = service._pwKey();
    if (!key) {
        service._fetchAqi();
        return;
    }

    var url = "https://api.pirateweather.net/forecast/"
        + encodeURIComponent(key) + "/"
        + service.latitude + "," + service.longitude
        + "?units=si&exclude=minutely,hourly,daily,alerts,summary"
        + "&include=airqualitydetails&version=2";

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            service._fetchAqi();
            return;
        }
        try {
            var d = JSON.parse(req.responseText);
        } catch (e) {
            service._fetchAqi();
            return;
        }

        var c = d.currently;
        // -999 is PW's sentinel for "not available at this location/time"
        if (!c || c.airQualityIndex === undefined || c.airQualityIndex === -999) {
            service._fetchAqi();
            return;
        }

        var co = _ppbToUgm3(c.coConcentration, _MOLAR_MASS.co);
        service._mergeAqiData({
            europeanAqi: c.airQualityIndex,
            pm10:  (c.pm10 !== undefined) ? c.pm10 : NaN,
            pm2_5: (c.pm25 !== undefined) ? c.pm25 : NaN,
            o3:    _ppbToUgm3(c.ozoneConcentration, _MOLAR_MASS.o3),
            no2:   _ppbToUgm3(c.no2Concentration, _MOLAR_MASS.no2),
            so2:   _ppbToUgm3(c.so2Concentration, _MOLAR_MASS.so2),
            co:    isNaN(co) ? NaN : co / 1000.0   // airQuality.js bands CO in mg/m³
        });
        service._nativeAqiSetThisGen = true;
        service._fetchAqi();
    };
    req.send();
}
