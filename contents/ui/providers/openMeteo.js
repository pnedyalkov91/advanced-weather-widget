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
 * openMeteo.js — Open-Meteo current + hourly fetcher
 *
 * Non-pragma JS — accesses config via service properties.
 * Qt global is available; Plasmoid/i18n/Locale are NOT (use service instead).
 */

.import "../js/weather.js" as W

function fetchCurrent(service, chain, idx) {
    var gen = service._refreshGen;
    var r = service;
    var tz = service.timezone;
    var url = "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + service.latitude
        + "&longitude=" + service.longitude
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
        + "&forecast_days=" + Math.min(service.forecastDays, 16)
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
        var nd = [];
        if (d.daily && d.daily.time) {
            var maxD = Math.min(service.forecastDays, d.daily.time.length);
            for (var i = 0; i < maxD; ++i) {
                var parts = (d.daily.time[i] || "").split("-");
                var dayDate = (parts.length === 3)
                    ? new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10), 12, 0, 0, 0)
                    : new Date();
                nd.push({
                    day: Qt.formatDate(dayDate, "ddd"),
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
                    visibilityKm: d.daily.visibility_mean ? d.daily.visibility_mean[i] / 1000.0 : NaN,
                    sunriseTimeText: (d.daily.sunrise && d.daily.sunrise[i]) ? Qt.formatTime(new Date(d.daily.sunrise[i]), "HH:mm") : "--",
                    sunsetTimeText: (d.daily.sunset && d.daily.sunset[i]) ? Qt.formatTime(new Date(d.daily.sunset[i]), "HH:mm") : "--"
                });
            }
        }
        r.weatherDataStaged = {
            temperatureC:        c.temperature_2m,
            apparentC:           c.apparent_temperature,
            humidityPercent:     c.relative_humidity_2m,
            windKmh:             c.wind_speed_10m,
            windDirection:       isNaN(c.wind_direction_10m) ? NaN : c.wind_direction_10m,
            pressureHpa:         c.pressure_msl,   // sea-level pressure (matches Foreca et al.)
            dewPointC:           c.dew_point_2m,
            visibilityKm:        c.visibility / 1000.0,
            weatherCode:         c.weather_code,
            isDay:               (c.is_day !== undefined) ? c.is_day : -1,
            precipMmh:           (c.precipitation !== undefined) ? c.precipitation : NaN,
            uvIndex:             (c.uv_index !== undefined) ? c.uv_index : NaN,
            snowDepthCm:         (c.snow_depth !== undefined && c.snow_depth !== null) ? c.snow_depth * 100 : NaN,
            locationUtcOffsetMins: (d.utc_offset_seconds !== undefined) ? Math.round(d.utc_offset_seconds / 60) : 0,
            locationTimezoneAbbrev: (d.timezone_abbreviation !== undefined && d.timezone_abbreviation !== null) ? ("" + d.timezone_abbreviation) : "",
            sunriseTimeText:     (d.daily && d.daily.sunrise && d.daily.sunrise.length > 0) ? Qt.formatTime(new Date(d.daily.sunrise[0]), "HH:mm") : "--",
            sunsetTimeText:      (d.daily && d.daily.sunset  && d.daily.sunset.length  > 0) ? Qt.formatTime(new Date(d.daily.sunset[0]),  "HH:mm") : "--",
            dailyData:           nd
        };
        r.loading = false;
        r.updateText = service._formatUpdateText("openMeteo");

        // No native alerts — fall back to MeteoAlarm / NWS
        service._fetchAlertsIfNeeded();
    };
    req.send();
}

function _aqiLabel(aqi) {
    if (aqi <= 20) return "Good";
    if (aqi <= 40) return "Fair";
    if (aqi <= 60) return "Moderate";
    if (aqi <= 80) return "Poor";
    if (aqi <= 100) return "Very Poor";
    return "Hazardous";
}

function _fetchAirQuality(service) {
    var gen = service._refreshGen;
    var r = service;
    var tz = service.timezone;
    var url = "https://air-quality-api.open-meteo.com/v1/air-quality"
        + "?latitude=" + service.latitude
        + "&longitude=" + service.longitude
        + "&current=european_aqi,pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone"
        + ",alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto");
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            r.aqiDataStaged = null;
            r.pollenDataStaged = [];
            return;
        }
        var d = JSON.parse(req.responseText);
        var c = d.current || {};
        var aqi = c.european_aqi;
        var hasAqi = aqi !== undefined && aqi !== null && !isNaN(aqi);
        r.aqiDataStaged = {
            index: hasAqi ? aqi : NaN,
            label: hasAqi ? _aqiLabel(aqi) : "",
            pm10:  (c.pm10             !== undefined && c.pm10             !== null && !isNaN(c.pm10))             ? c.pm10 : NaN,
            pm2_5: (c.pm2_5            !== undefined && c.pm2_5            !== null && !isNaN(c.pm2_5))            ? c.pm2_5 : NaN,
            no2:   (c.nitrogen_dioxide !== undefined && c.nitrogen_dioxide !== null && !isNaN(c.nitrogen_dioxide)) ? c.nitrogen_dioxide : NaN,
            so2:   (c.sulphur_dioxide  !== undefined && c.sulphur_dioxide  !== null && !isNaN(c.sulphur_dioxide))  ? c.sulphur_dioxide : NaN,
            o3:    (c.ozone            !== undefined && c.ozone            !== null && !isNaN(c.ozone))            ? c.ozone : NaN,
            co:    (c.carbon_monoxide  !== undefined && c.carbon_monoxide  !== null && !isNaN(c.carbon_monoxide))  ? c.carbon_monoxide / 1000.0 : NaN
        };
        var pollenKeys = [
            { key: "alder",   field: "alder_pollen"   },
            { key: "birch",   field: "birch_pollen"   },
            { key: "grass",   field: "grass_pollen"   },
            { key: "mugwort", field: "mugwort_pollen" },
            { key: "olive",   field: "olive_pollen"   },
            { key: "ragweed", field: "ragweed_pollen" }
        ];
        var pd = [];
        pollenKeys.forEach(function (p) {
            var v = c[p.field];
            if (v !== undefined && v !== null && !isNaN(v))
                pd.push({ key: p.key, value: v });
        });
        r.pollenDataStaged = pd;
    };
    req.send();
}

function fetchHourly(service, dateStr) {
    var gen = service._refreshGen;
    var r = service;
    var tz = service.timezone;
    var url = "https://api.open-meteo.com/v1/forecast?latitude="
        + service.latitude
        + "&longitude=" + service.longitude
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
        + "&hourly=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,relative_humidity_2m,precipitation_probability,precipitation,pressure_msl,visibility,uv_index"
        + "&start_date=" + dateStr + "&end_date=" + dateStr
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
        var arr = [];
        if (d.hourly && d.hourly.time)
            for (var i = 0; i < d.hourly.time.length; ++i)
                arr.push({
                    hour: Qt.formatTime(new Date(d.hourly.time[i]), "HH:mm"),
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
                });
        r.hourlyData = arr;
    };
    req.send();
}
