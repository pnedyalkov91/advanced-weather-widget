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
 * visualCrossing.js — Visual Crossing current + hourly fetcher
 *
 * Non-pragma JS — accesses config via service properties.
 * Visual Crossing Timeline API provides current conditions, daily and hourly forecasts.
 * Uses Dark Sky-compatible icon names.
 * Docs: https://www.visualcrossing.com/resources/documentation/weather-api/
 */

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

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._vcKey();
    if (!key) {
        service._tryProvider(chain, idx + 1);
        return;
    }

    var url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/"
        + service.latitude + "," + service.longitude
        + "?key=" + encodeURIComponent(key)
        + "&unitGroup=metric"
        + "&include=current,days,alerts"
        + "&iconSet=icons2";

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
                    snowCm: (dd.snow !== undefined) ? dd.snow : NaN
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
        r.aqiData = null;
        r.pollenData = [];
        r.loading = false;
        r.updateText = service._formatUpdateText("visualCrossing");

        // Parse alerts if available
        if (d.alerts && d.alerts.length > 0) {
            _parseAlerts(r, d.alerts);
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
        if (a.ends) {
            var exp = new Date(a.ends);
            if (exp < now) continue;
        }

        parsed.push({
            headline: a.headline || a.event || "",
            displayName: a.event || a.headline || "",
            severity: "",
            description: a.description || "",
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
    }
}


function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._vcKey();
    if (!key) {
        r.hourlyData = [];
        return;
    }

    // Request hours for the specific date only
    var url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/"
        + service.latitude + "," + service.longitude
        + "/" + dateStr + "/" + dateStr
        + "?key=" + encodeURIComponent(key)
        + "&unitGroup=metric"
        + "&include=hours"
        + "&iconSet=icons2";

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
        if (d.days && d.days.length > 0 && d.days[0].hours) {
            d.days[0].hours.forEach(function (h) {
                arr.push({
                    hour: h.datetime ? h.datetime.substring(0, 5) : "--",
                    tempC: h.temp,
                    code: _iconToWmo(h.icon),
                    windKmh: (h.windspeed !== undefined) ? h.windspeed : NaN,
                    windDeg: (h.winddir !== undefined) ? h.winddir : NaN,
                    humidity: (h.humidity !== undefined) ? Math.round(h.humidity) : NaN,
                    precipProb: (h.precipprob !== undefined) ? Math.round(h.precipprob) : NaN,
                    precipMm: (h.precip !== undefined) ? h.precip : NaN
                });
            });
        }
        r.hourlyData = arr;
    };
    req.send();
}
