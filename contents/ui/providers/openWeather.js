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
 * openWeather.js — OpenWeather current + hourly fetcher
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

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._owKey();
    if (!key) {
        service._tryProvider(chain, idx + 1);
        return;
    }
    var baseUrl = "https://api.openweathermap.org/data/2.5/";
    var latlon = "lat=" + service.latitude
        + "&lon=" + service.longitude
        + "&units=metric&appid=" + encodeURIComponent(key);

    var req = new XMLHttpRequest();
    req.open("GET", baseUrl + "weather?" + latlon);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        var d = JSON.parse(req.responseText);
        if (!d.main) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        var _cur = {
            temperatureC:    d.main.temp,
            apparentC:       d.main.feels_like,
            humidityPercent: d.main.humidity,
            pressureHpa:     d.main.pressure,
            windKmh:         (d.wind && d.wind.speed !== undefined) ? d.wind.speed * 3.6 : NaN,
            windDirection:   (d.wind && d.wind.deg !== undefined) ? d.wind.deg : NaN,
            dewPointC:       _calcDewPoint(d.main.temp, d.main.humidity),
            visibilityKm:    (d.visibility !== undefined) ? d.visibility / 1000.0 : NaN,
            precipMmh:       (d.rain && d.rain["1h"] !== undefined) ? d.rain["1h"]
                                : (d.rain && d.rain["3h"] !== undefined) ? d.rain["3h"] / 3.0 : 0,
            uvIndex:         NaN,
            snowDepthCm:     NaN,
            weatherCode:     (d.weather && d.weather.length > 0) ? W.openWeatherCodeToWmo(d.weather[0].id) : 2,
            isDay:           -1,
            locationUtcOffsetMins: 0,
            sunriseTimeText: (d.sys && d.sys.sunrise) ? Qt.formatTime(new Date(d.sys.sunrise * 1000), "HH:mm") : "--",
            sunsetTimeText:  (d.sys && d.sys.sunset)  ? Qt.formatTime(new Date(d.sys.sunset  * 1000), "HH:mm") : "--",
            dailyData:       []
        };

        // Fetch forecast separately
        var fcReq = new XMLHttpRequest();
        fcReq.open("GET", baseUrl + "forecast?" + latlon);
        fcReq.onreadystatechange = function () {
            if (fcReq.readyState !== XMLHttpRequest.DONE)
                return;
            if (service._refreshGen !== gen) return;
            var nd = [];
            if (fcReq.status === 200) {
                var fc = JSON.parse(fcReq.responseText);
                var days = {};
                if (fc.list)
                    fc.list.forEach(function (e) {
                        var dt = new Date(e.dt * 1000);
                        var dk = Qt.formatDate(dt, "yyyy-MM-dd");
                        var hr = dt.getHours();
                        if (!days[dk])
                            days[dk] = { maxC: -Infinity, minC: Infinity, bestHr: -1, bestEntry: null, precipMm: 0, snowMm: 0 };
                        var day = days[dk];
                        if (e.main.temp_max > day.maxC)
                            day.maxC = e.main.temp_max;
                        if (e.main.temp_min < day.minC)
                            day.minC = e.main.temp_min;
                        // accumulate precipitation
                        if (e.rain && e.rain["3h"])
                            day.precipMm += e.rain["3h"];
                        if (e.snow && e.snow["3h"])
                            day.snowMm += e.snow["3h"];
                        // pick entry closest to noon for the weather code
                        if (day.bestHr < 0 || Math.abs(hr - 12) < Math.abs(day.bestHr - 12)) {
                            day.bestHr = hr;
                            day.bestEntry = e;
                        }
                    });
                Object.keys(days).sort().forEach(function (k) {
                    if (nd.length >= service.forecastDays)
                        return;
                    var day = days[k];
                    nd.push({
                        day: Qt.formatDate(new Date(day.bestEntry.dt * 1000), "ddd"),
                        dateStr: k,
                        maxC: day.maxC,
                        minC: day.minC,
                        code: W.openWeatherCodeToWmo(day.bestEntry.weather[0].id),
                        precipMm: day.precipMm,
                        snowCm: day.snowMm / 10.0  // mm → cm
                    });
                });
            }
            _cur.dailyData = nd;
            r.weatherDataStaged = _cur;
            r.loading = false;
            r.updateText = service._formatUpdateText("openWeather");

            // No native alerts — fall back to MeteoAlarm / NWS
            service._fetchAlertsIfNeeded();

            _fetchAirQuality(service, W);
        };
        fcReq.send();
    };
    req.send();
}

function _owAqiLabel(aqi) {
    if (aqi === 1) return "Good";
    if (aqi === 2) return "Fair";
    if (aqi === 3) return "Moderate";
    if (aqi === 4) return "Poor";
    if (aqi === 5) return "Very Poor";
    return "";
}

function _fetchAirQuality(service, W) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._owKey();
    if (!key) {
        r.aqiData = null;
        return;
    }
    var url = "https://api.openweathermap.org/data/2.5/air_pollution?lat="
        + service.latitude + "&lon=" + service.longitude
        + "&appid=" + encodeURIComponent(key);
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            r.aqiData = null;
            r.pollenData = [];
            return;
        }
        var d = JSON.parse(req.responseText);
        if (d.list && d.list.length > 0 && d.list[0].main) {
            var aqi = d.list[0].main.aqi;
            r.aqiDataStaged = { index: aqi, label: _owAqiLabel(aqi) };
        } else {
            r.aqiData = null;
        }
        r.pollenData = []; // not available in OpenWeather free tier
    };
    req.send();
}

function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._owKey();
    if (!key) {
        r.hourlyData = [];
        return;
    }
    var url = "https://api.openweathermap.org/data/2.5/forecast?lat="
        + service.latitude
        + "&lon=" + service.longitude
        + "&units=metric&appid=" + encodeURIComponent(key);
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
        var fc = JSON.parse(req.responseText);
        var arr = [];
        if (fc.list)
            fc.list.forEach(function (e) {
                var d = new Date(e.dt * 1000);
                if (Qt.formatDate(d, "yyyy-MM-dd") === dateStr)
                    arr.push({
                        hour: Qt.formatTime(d, "HH:mm"),
                        tempC: e.main.temp,
                        code: W.openWeatherCodeToWmo(e.weather[0].id),
                        windKmh: e.wind ? e.wind.speed * 3.6 : NaN,
                        windDeg: e.wind ? e.wind.deg : NaN,
                        humidity: e.main.humidity,
                        precipProb: (e.pop !== undefined && e.pop !== null)
                            ? Math.round(e.pop * 100) : NaN,
                        precipMm: (e.rain && e.rain["1h"] !== undefined) ? e.rain["1h"]
                            : (e.rain && e.rain["3h"] !== undefined) ? (e.rain["3h"] / 3)
                            : NaN
                    });
            });
        r.hourlyData = arr;
    };
    req.send();
}
