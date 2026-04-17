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
 * weatherbit.js — Weatherbit current + hourly fetcher
 *
 * Non-pragma JS — accesses config via service properties.
 * Weatherbit provides current conditions, daily and hourly forecasts.
 * Docs: https://www.weatherbit.io/api
 */

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

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._wbKey();
    if (!key) {
        service._tryProvider(chain, idx + 1);
        return;
    }

    var url = "https://api.weatherbit.io/v2.0/current"
        + "?lat=" + service.latitude
        + "&lon=" + service.longitude
        + "&key=" + encodeURIComponent(key)
        + "&units=M";

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
            pressureHpa:     (c.pres !== undefined) ? c.pres : NaN,
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
        r.aqiData = null;
        r.pollenData = [];
        _fetchDailyForecast(service, W, gen);
    };
    req.send();
}

/**
 * Fetches the daily forecast from Weatherbit.
 * Sets dailyData, then marks loading complete.
 */
function _fetchDailyForecast(service, W, gen) {
    var r = service.weatherRoot;
    var key = service._wbKey();

    var url = "https://api.weatherbit.io/v2.0/forecast/daily"
        + "?lat=" + service.latitude
        + "&lon=" + service.longitude
        + "&key=" + encodeURIComponent(key)
        + "&units=M"
        + "&days=" + Math.min(service.forecastDays, 16);

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;

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
                            snowCm: (dd.snow !== undefined) ? dd.snow / 10 : NaN // mm to cm
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

        // No native alerts — fall back to MeteoAlarm / NWS
        service._fetchAlertsIfNeeded();

        // Air quality fetched in parallel from WeatherService.refreshNow()
    };
    req.send();
}


function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._wbKey();
    if (!key) {
        r.hourlyData = [];
        return;
    }

    var url = "https://api.weatherbit.io/v2.0/forecast/hourly"
        + "?lat=" + service.latitude
        + "&lon=" + service.longitude
        + "&key=" + encodeURIComponent(key)
        + "&units=M"
        + "&hours=48";

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
        if (d.data) {
            d.data.forEach(function (h) {
                // timestamp_local is "yyyy-MM-ddTHH:mm:ss"
                var dtStr = h.timestamp_local || h.datetime || "";
                var datePart = dtStr.substring(0, 10);
                if (datePart !== dateStr) return;

                var dt = new Date(dtStr);
                var wCode = (h.weather && h.weather.code !== undefined) ? h.weather.code : undefined;

                arr.push({
                    hour: Qt.formatTime(dt, "HH:mm"),
                    tempC: h.temp,
                    code: _codeToWmo(wCode),
                    windKmh: (h.wind_spd !== undefined) ? h.wind_spd * 3.6 : NaN,
                    windDeg: (h.wind_dir !== undefined) ? h.wind_dir : NaN,
                    humidity: (h.rh !== undefined) ? Math.round(h.rh) : NaN,
                    precipProb: (h.pop !== undefined) ? Math.round(h.pop) : NaN,
                    precipMm: (h.precip !== undefined) ? h.precip : NaN
                });
            });
        }
        r.hourlyData = arr;
    };
    req.send();
}
