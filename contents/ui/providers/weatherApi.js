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
 * weatherApi.js — WeatherAPI.com current + hourly fetcher
 *
 * Non-pragma JS — accesses config via service properties.
 * Qt global is available; Plasmoid/i18n/Locale are NOT (use service instead).
 * W (weather.js) is passed as a parameter by the caller.
 */

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

function _waAqiLabel(epa) {
    if (epa === 1) return "Good";
    if (epa === 2) return "Moderate";
    if (epa === 3) return "Unhealthy for Sensitive";
    if (epa === 4) return "Unhealthy";
    if (epa === 5) return "Very Unhealthy";
    if (epa === 6) return "Hazardous";
    return "";
}

function _apiTimeTo24h(s) {
    if (!s || s === "--")
        return "--";
    var parts = s.trim().split(/\s+/);
    if (parts.length < 2)
        return s;  // already "HH:mm" — pass through
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

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._waKey();
    if (!key) {
        service._tryProvider(chain, idx + 1);
        return;
    }
    var days = Math.max(3, service.forecastDays);
    var url = "https://api.weatherapi.com/v1/forecast.json?key="
        + encodeURIComponent(key)
        + "&q=" + encodeURIComponent(
            service.latitude + "," + service.longitude)
        + "&days=" + days + "&aqi=yes&alerts=yes";

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
        var aq = d.current.air_quality;
        var epa = aq ? aq["us-epa-index"] : undefined;
        if (aq) {
            r.aqiDataStaged = { index: (epa !== undefined) ? epa : NaN, label: _waAqiLabel(epa) };
        } else {
            r.aqiData = null;
        }
        r.pollenData = [];
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
                    snowCm: (f.day.totalsnow_cm !== undefined) ? f.day.totalsnow_cm : NaN
                });
            }
        }
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
            locationUtcOffsetMins: 0,
            sunriseTimeText: astro ? _apiTimeTo24h(astro.sunrise) : "--",
            sunsetTimeText:  astro ? _apiTimeTo24h(astro.sunset)  : "--",
            dailyData:       nd
        };
        r.loading = false;
        r.updateText = service._formatUpdateText("weatherApi");

        // Parse native alerts if available
        if (d.alerts && d.alerts.alert && d.alerts.alert.length > 0) {
            _parseAlerts(r, d.alerts.alert);
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
    }
}

function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._waKey();
    if (!key) {
        r.hourlyData = [];
        return;
    }
    var url = "https://api.weatherapi.com/v1/forecast.json?key="
        + encodeURIComponent(key)
        + "&q=" + encodeURIComponent(
            service.latitude + "," + service.longitude)
        + "&days=7&aqi=no&alerts=no&dt=" + dateStr;
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
        var arr = [];
        if (d.forecast && d.forecast.forecastday)
            d.forecast.forecastday.forEach(function (day) {
                if (day.date === dateStr && day.hour)
                    day.hour.forEach(function (h) {
                        arr.push({
                            hour: Qt.formatTime(new Date(h.time_epoch * 1000), "HH:mm"),
                            tempC: h.temp_c,
                            code: W.weatherApiCodeToWmo(h.condition.code),
                            windKmh: h.wind_kph,
                            windDeg: h.wind_degree,
                            humidity: h.humidity,
                            precipProb: (h.chance_of_rain !== undefined)
                                ? h.chance_of_rain : NaN,
                            precipMm: (h.precip_mm !== undefined) ? h.precip_mm : NaN
                        });
                    });
            });
        r.hourlyData = arr;
    };
    req.send();
}
