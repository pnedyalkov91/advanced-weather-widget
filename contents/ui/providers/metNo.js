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
 * metNo.js — met.no current + hourly fetcher
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
    var alt = service.altitude;
    var url = "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat="
        + encodeURIComponent(service.latitude)
        + "&lon=" + encodeURIComponent(service.longitude)
        + ((!isNaN(alt) && alt !== 0) ? "&altitude=" + Math.round(alt) : "");

    var req = new XMLHttpRequest();
    req.open("GET", url);
    // met.no Terms of Service: User-Agent identifying the app is MANDATORY.
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        var d = JSON.parse(req.responseText);
        if (!d.properties || !d.properties.timeseries
                || d.properties.timeseries.length === 0) {
            service._tryProvider(chain, idx + 1);
            return;
        }
        var ts = d.properties.timeseries[0];
        var det = (ts.data && ts.data.instant) ? ts.data.instant.details : null;
        if (!det) {
            service._tryProvider(chain, idx + 1);
            return;
        }

        var precipDet = (ts.data && ts.data.next_1_hours && ts.data.next_1_hours.details)
            ? ts.data.next_1_hours.details : null;
        var sym = (ts.data && ts.data.next_1_hours && ts.data.next_1_hours.summary)
            ? ts.data.next_1_hours.summary.symbol_code : "";
        var _cur = {
            temperatureC:    det.air_temperature,
            apparentC:       det.air_temperature,
            humidityPercent: det.relative_humidity,
            pressureHpa:     det.air_pressure_at_sea_level,
            windKmh:         (det.wind_speed !== undefined) ? det.wind_speed * 3.6 : NaN,
            windDirection:   (det.wind_from_direction !== undefined) ? det.wind_from_direction : NaN,
            dewPointC:       det.dew_point_temperature !== undefined
                                ? det.dew_point_temperature
                                : _calcDewPoint(det.air_temperature, det.relative_humidity),
            visibilityKm:    NaN,
            precipMmh:       (precipDet && precipDet.precipitation_amount !== undefined)
                                ? precipDet.precipitation_amount : 0,
            uvIndex:         (det.ultraviolet_index_clear_sky !== undefined)
                                ? det.ultraviolet_index_clear_sky : NaN,
            snowDepthCm:     NaN,
            weatherCode:     W.metNoSymbolToWmo(sym),
            isDay:           -1,
            locationUtcOffsetMins: 0,
            sunriseTimeText: "--",
            sunsetTimeText:  "--",
            dailyData:       []   // filled below
        };
        // met.no does not provide sunrise/sunset — fetch from Open-Meteo as fallback.
        service._fetchSunTimesOpenMeteo();

        // Build daily forecast from timeseries
        var days = {};
        d.properties.timeseries.forEach(function (t2) {
            var dd = new Date(t2.time);
            var dk = Qt.formatDate(dd, "yyyy-MM-dd");
            var hr = dd.getHours();
            var det2 = (t2.data && t2.data.instant) ? t2.data.instant.details : null;
            if (!det2)
                return;
            if (!days[dk])
                days[dk] = { maxC: -Infinity, minC: Infinity, bestHr: -1, bestCode: 0, precipMm: 0 };
            var day = days[dk];
            if (det2.air_temperature > day.maxC)
                day.maxC = det2.air_temperature;
            if (det2.air_temperature < day.minC)
                day.minC = det2.air_temperature;
            // accumulate precipitation
            var p1h = (t2.data && t2.data.next_1_hours && t2.data.next_1_hours.details)
                ? t2.data.next_1_hours.details : null;
            if (p1h && p1h.precipitation_amount !== undefined)
                day.precipMm += p1h.precipitation_amount;
            // pick entry closest to noon for the weather code
            if (day.bestHr < 0 || Math.abs(hr - 12) < Math.abs(day.bestHr - 12)) {
                var s2 = (t2.data && t2.data.next_1_hours
                    && t2.data.next_1_hours.summary)
                    ? t2.data.next_1_hours.summary.symbol_code : "";
                day.bestHr = hr;
                day.bestCode = W.metNoSymbolToWmo(s2);
            }
        });
        var nd = [];
        Object.keys(days).sort().forEach(function (k) {
            if (nd.length >= service.forecastDays)
                return;
            var day = days[k];
            nd.push({
                day: Qt.formatDate(new Date(k), "ddd"),
                dateStr: k,
                maxC: day.maxC,
                minC: day.minC,
                code: day.bestCode,
                precipMm: day.precipMm,
                snowCm: NaN
            });
        });
        _cur.dailyData = nd;
        r.weatherDataStaged = _cur;
        r.loading = false;
        r.updateText = service._formatUpdateText("metno");

        // No native alerts — fall back to MeteoAlarm / NWS
        service._fetchAlertsIfNeeded();
    };
    req.send();
}

function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var alt = service.altitude;
    var url = "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat="
        + encodeURIComponent(service.latitude)
        + "&lon=" + encodeURIComponent(service.longitude)
        + ((!isNaN(alt) && alt !== 0) ? "&altitude=" + Math.round(alt) : "");
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
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
        if (d.properties && d.properties.timeseries)
            d.properties.timeseries.forEach(function (ts) {
                var dd = new Date(ts.time);
                if (Qt.formatDate(dd, "yyyy-MM-dd") === dateStr) {
                    var det = (ts.data && ts.data.instant)
                        ? ts.data.instant.details : null;
                    if (!det)
                        return;
                    var sym = (ts.data && ts.data.next_1_hours
                        && ts.data.next_1_hours.summary)
                        ? ts.data.next_1_hours.summary.symbol_code : "";
                    arr.push({
                        hour: Qt.formatTime(dd, "HH:mm"),
                        tempC: det.air_temperature,
                        code: W.metNoSymbolToWmo(sym),
                        windKmh: det.wind_speed !== undefined
                            ? det.wind_speed * 3.6 : NaN,
                        windDeg: det.wind_from_direction !== undefined
                            ? det.wind_from_direction : NaN,
                        humidity: det.relative_humidity,
                        precipProb: (ts.data && ts.data.next_1_hours
                            && ts.data.next_1_hours.details
                            && ts.data.next_1_hours.details.probability_of_precipitation !== undefined)
                            ? ts.data.next_1_hours.details.probability_of_precipitation : NaN,
                        precipMm: (ts.data && ts.data.next_1_hours
                            && ts.data.next_1_hours.details
                            && ts.data.next_1_hours.details.precipitation_amount !== undefined)
                            ? ts.data.next_1_hours.details.precipitation_amount : NaN
                    });
                }
            });
        r.hourlyData = arr;
    };
    req.send();
}
