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
 * qWeather.js — QWeather (和风天气) current + daily + hourly fetcher
 *
 * Non-pragma JS — accesses config via service properties.
 * Qt global is available; Plasmoid/i18n/Locale are NOT (use service instead).
 * W (weather.js) is passed as a parameter by the caller.
 *
 * QWeather API docs: https://dev.qweather.com/en/docs/api/weather/
 * Authentication: API KEY via `X-QW-Api-Key` request header.
 * Location format: longitude,latitude (up to 2 decimal places).
 *
 * API host is user-configurable (service._qwHost()) because QWeather
 * assigns a project-specific host to each developer account.
 * Falls back to devapi.qweather.com when no host is configured.
 */

/**
 * Map a QWeather icon code to WMO weather code.
 *
 * QWeather icon codes:
 *   100 Sunny (day), 150 Clear (night)
 *   101-103 Cloudy variants (day), 151-153 (night)
 *   104 Overcast
 *   300-301 Shower rain (day), 350-351 (night)
 *   302-303 Thunderstorm
 *   304 Hail
 *   305-318 Rain variants
 *   399 Rain (generic)
 *   400-410 Snow variants
 *   499 Snow (generic)
 *   500-515 Fog/haze/mist/dust
 *   900 Hot, 901 Cold
 */
function _qwCodeToWmo(code) {
    var code = parseInt(code, 10);
    if (isNaN(code)) return 2;
    // Clear / Sunny
    if (code === 100 || code === 150) return 0;
    // Few clouds / partly cloudy
    if (code === 101 || code === 102 || code === 151 || code === 152) return 2;
    // Cloudy / overcast
    if (code === 103 || code === 104 || code === 153) return 3;
    // Thunderstorm
    if (code === 302 || code === 303) return 95;
    // Hail
    if (code === 304) return 99;
    // Shower rain (day/night)
    if (code === 300 || code === 301 || code === 350 || code === 351) return 80;
    // Rain variants
    if (code === 305 || code === 309 || code === 314) return 61;  // light rain
    if (code === 306 || code === 315) return 63;  // moderate rain
    if (code >= 307 && code <= 318) return 65;    // heavy rain
    if (code === 399) return 63;               // generic rain
    // Freezing rain
    if (code === 313) return 66;
    // Snow
    if (code === 400 || code === 408) return 71;  // light snow
    if (code === 401 || code === 409) return 73;  // moderate snow
    if (code === 402 || code === 403 || code === 410) return 75; // heavy snow / snowstorm
    if (code === 404 || code === 405) return 66;  // sleet / rain and snow
    if (code === 406 || code === 407 || code === 456 || code === 457) return 77; // snow flurry
    if (code === 499) return 73;               // generic snow
    // Fog / mist / haze / dust
    if (code >= 500 && code <= 515) return 45;
    // Hot / Cold
    if (code === 900 || code === 901) return 0;
    return 2; // fallback
}

/**
 * Determine isDay from QWeather icon code.
 * Night icons: 150-153, 350-351, 456-457.
 */
function _isDay(iconCode) {
    var code = parseInt(iconCode, 10);
    if ((code >= 150 && code <= 153) || code === 350 || code === 351 || code === 456 || code === 457)
        return 0;
    return 1;
}

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
    var key = service._qwKey();
    if (!key) {
        service._tryProvider(chain, idx + 1);
        return;
    }
    var base = service._qwHost();
    // QWeather location format: longitude,latitude (up to 2 decimals)
    var loc = service.longitude.toFixed(2) + "," + service.latitude.toFixed(2);
    var url = base + "/v7/weather/now?location=" + encodeURIComponent(loc)
        + "&unit=m";

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("X-QW-Api-Key", key);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE) return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        var d;
        try { d = JSON.parse(req.responseText); } catch (e) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        if (d.code !== "200" || !d.now) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        var n = d.now;
        service._qw_cur = {
            temperatureC:    parseFloat(n.temp),
            apparentC:       parseFloat(n.feelsLike),
            humidityPercent: parseFloat(n.humidity),
            pressureHpa:     parseFloat(n.pressure),
            windKmh:         parseFloat(n.windSpeed),
            windDirection:   parseFloat(n.wind360),
            dewPointC:       (n.dew !== undefined && n.dew !== null)
                                ? parseFloat(n.dew)
                                : _calcDewPoint(parseFloat(n.temp), parseFloat(n.humidity)),
            visibilityKm:    parseFloat(n.vis),
            precipMmh:       parseFloat(n.precip) || 0,
            uvIndex:         NaN,
            snowDepthCm:     NaN,
            weatherCode:     _qwCodeToWmo(n.icon),
            isDay:           _isDay(n.icon),
            locationUtcOffsetMins: 0,
            sunriseTimeText: "--",
            sunsetTimeText:  "--",
            dailyData:       []
        };
        _fetchDaily(service, W, key, loc, gen, base);
    };
    req.send();
}

function _fetchDaily(service, W, key, loc, gen, base) {
    var r = service.weatherRoot;
    var days = Math.min(service.forecastDays, 7);
    var url = base + "/v7/weather/" + days + "d?location=" + encodeURIComponent(loc)
        + "&unit=m";

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("X-QW-Api-Key", key);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE) return;
        if (service._refreshGen !== gen) return;
        var nd = [];
        if (req.status === 200) {
            var d;
            try { d = JSON.parse(req.responseText); } catch (e) { /* ignore */ }
            if (d && d.code === "200" && d.daily) {
                for (var i = 0; i < d.daily.length && i < service.forecastDays; i++) {
                    var day = d.daily[i];
                    nd.push({
                        day: Qt.formatDate(new Date(day.fxDate), "ddd"),
                        dateStr: day.fxDate,
                        maxC: parseFloat(day.tempMax),
                        minC: parseFloat(day.tempMin),
                        code: _qwCodeToWmo(day.iconDay),
                        precipMm: parseFloat(day.precip) || 0,
                        snowCm: 0, // not separated in QWeather daily
                        precipProb: (day.pop !== undefined) ? parseFloat(day.pop) : NaN,
                        windKmh: (day.windSpeed !== undefined) ? parseFloat(day.windSpeed) : NaN,
                        windDir: (day.wind360 !== undefined) ? parseFloat(day.wind360) : NaN
                    });
                }
                if (d.daily.length > 0) {
                    if (d.daily[0].sunrise)
                        service._qw_cur.sunriseTimeText = d.daily[0].sunrise;
                    if (d.daily[0].sunset)
                        service._qw_cur.sunsetTimeText = d.daily[0].sunset;
                }
            }
        }
        service._qw_cur.dailyData = nd;
        var r = service.weatherRoot;
        r.weatherDataStaged = service._qw_cur;
        service._qw_cur = null;
        r.loading = false;
        r.updateText = service._formatUpdateText("qWeather");

        service._fetchAlertsIfNeeded();
        _fetchAirQuality(service, W, key, loc, gen, base);
    };
    req.send();
}

function _qwAqiLabel(category) {
    // Category 1–6 from QWeather
    if (category === 1) return "Good";
    if (category === 2) return "Moderate";
    if (category === 3) return "Unhealthy (Sensitive)";
    if (category === 4) return "Unhealthy";
    if (category === 5) return "Very Unhealthy";
    if (category === 6) return "Hazardous";
    return "";
}

function _fetchAirQuality(service, W, key, loc, gen, base) {
    var r = service.weatherRoot;
    var url = base + "/airquality/v1/current?location=" + encodeURIComponent(loc);

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("X-QW-Api-Key", key);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE) return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            r.aqiData = null;
            r.pollenData = [];
            return;
        }
        var d;
        try { d = JSON.parse(req.responseText); } catch (e) {
            r.aqiData = null;
            r.pollenData = [];
            return;
        }
        if (d.code === "200" && d.indexes && d.indexes.length > 0) {
            var idx = d.indexes[0];
            var aqi = parseFloat(idx.aqiDisplay) || NaN;
            r.aqiDataStaged = { index: aqi, label: _qwAqiLabel(parseInt(idx.category, 10)) };
        } else {
            r.aqiData = null;
        }
        r.pollenData = [];
    };
    req.send();
}

function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._qwKey();
    if (!key) {
        r.hourlyData = [];
        return;
    }
    var base = service._qwHost();
    var loc = service.longitude.toFixed(2) + "," + service.latitude.toFixed(2);
    var url = base + "/v7/weather/24h?location=" + encodeURIComponent(loc)
        + "&unit=m";

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("X-QW-Api-Key", key);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE) return;
        if (service._refreshGen !== gen) return;
        var hours = [];
        if (req.status === 200) {
            var d;
            try { d = JSON.parse(req.responseText); } catch (e) { /* ignore */ }
            if (d && d.code === "200" && d.hourly) {
                for (var i = 0; i < d.hourly.length; i++) {
                    var h = d.hourly[i];
                    var fxTime = new Date(h.fxTime);
                    var fxDateStr = Qt.formatDate(fxTime, "yyyy-MM-dd");
                    if (fxDateStr !== dateStr) continue;
                    hours.push({
                        hour: Qt.formatTime(fxTime, "HH:mm"),
                        tempC: parseFloat(h.temp),
                        code: _qwCodeToWmo(h.icon),
                        windKmh: parseFloat(h.windSpeed),
                        windDir: parseFloat(h.wind360),
                        humidityPercent: parseFloat(h.humidity),
                        pressureHpa: parseFloat(h.pressure),
                        precipMmh: parseFloat(h.precip) || 0,
                        pop: (h.pop !== undefined && h.pop !== null) ? parseFloat(h.pop) : NaN,
                        dewPointC: (h.dew !== undefined && h.dew !== null)
                            ? parseFloat(h.dew)
                            : _calcDewPoint(parseFloat(h.temp), parseFloat(h.humidity))
                    });
                }
            }
        }
        r.hourlyData = hours;
    };
    req.send();
}
