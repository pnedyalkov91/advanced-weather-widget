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

function fetchCurrent(service, chain, idx) {
    var r = service.weatherRoot;
    var tz = service.timezone;
    var url = "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + service.latitude
        + "&longitude=" + service.longitude
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,"
        + "weather_code,wind_speed_10m,wind_direction_10m,surface_pressure,"
        + "dew_point_2m,visibility,is_day,precipitation,uv_index,snow_depth"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,"
        + "precipitation_sum,snowfall_sum";

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
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
        r.temperatureC = c.temperature_2m;
        r.apparentC = c.apparent_temperature;
        r.humidityPercent = c.relative_humidity_2m;
        r.windKmh = c.wind_speed_10m;
        r.windDirection = isNaN(c.wind_direction_10m) ? NaN : c.wind_direction_10m;
        r.pressureHpa = c.surface_pressure;
        r.dewPointC = c.dew_point_2m;
        r.visibilityKm = c.visibility / 1000.0;
        r.weatherCode = c.weather_code;
        r.isDay = (c.is_day !== undefined) ? c.is_day : -1;
        r.precipMmh = (c.precipitation !== undefined) ? c.precipitation : NaN;
        r.uvIndex = (c.uv_index !== undefined) ? c.uv_index : NaN;
        r.snowDepthCm = (c.snow_depth !== undefined && c.snow_depth !== null) ? c.snow_depth * 100 : NaN;
        r.locationUtcOffsetMins = (d.utc_offset_seconds !== undefined)
            ? Math.round(d.utc_offset_seconds / 60) : 0;
        r.sunriseTimeText = (d.daily && d.daily.sunrise && d.daily.sunrise.length > 0)
            ? Qt.formatTime(new Date(d.daily.sunrise[0]), "HH:mm") : "--";
        r.sunsetTimeText = (d.daily && d.daily.sunset && d.daily.sunset.length > 0)
            ? Qt.formatTime(new Date(d.daily.sunset[0]), "HH:mm") : "--";
        var nd = [];
        if (d.daily && d.daily.time) {
            var maxD = Math.min(service.forecastDays, d.daily.time.length);
            for (var i = 0; i < maxD; ++i)
                nd.push({
                    day: Qt.formatDate(new Date(d.daily.time[i]), "ddd"),
                    dateStr: d.daily.time[i],
                    maxC: d.daily.temperature_2m_max[i],
                    minC: d.daily.temperature_2m_min[i],
                    code: d.daily.weather_code[i],
                    precipMm: d.daily.precipitation_sum ? d.daily.precipitation_sum[i] : NaN,
                    snowCm: d.daily.snowfall_sum ? d.daily.snowfall_sum[i] : NaN
                });
        }
        r.dailyData = nd;
        r.loading = false;
        r.updateText = service._formatUpdateText("openMeteo");
        // Fetch air quality from separate endpoint
        _fetchAirQuality(service);
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
    var r = service.weatherRoot;
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
        if (req.status !== 200) {
            r.airQualityIndex = NaN;
            r.airQualityLabel = "";
            r.aqiPm10 = NaN;
            r.aqiPm2_5 = NaN;
            r.aqiCo = NaN;
            r.aqiNo2 = NaN;
            r.aqiSo2 = NaN;
            r.aqiO3 = NaN;
            r.pollenData = [];
            return;
        }
        var d = JSON.parse(req.responseText);
        var c = d.current || {};
        if (c.european_aqi !== undefined) {
            r.airQualityIndex = c.european_aqi;
            r.airQualityLabel = _aqiLabel(c.european_aqi);
        } else {
            r.airQualityIndex = NaN;
            r.airQualityLabel = "";
        }
        // Pollutant concentrations (µg/m³ except CO which is µg/m³ → store as mg/m³)
        r.aqiPm10  = (c.pm10               !== undefined) ? c.pm10               : NaN;
        r.aqiPm2_5 = (c.pm2_5              !== undefined) ? c.pm2_5              : NaN;
        r.aqiNo2   = (c.nitrogen_dioxide    !== undefined) ? c.nitrogen_dioxide    : NaN;
        r.aqiSo2   = (c.sulphur_dioxide     !== undefined) ? c.sulphur_dioxide     : NaN;
        r.aqiO3    = (c.ozone               !== undefined) ? c.ozone               : NaN;
        // Open-Meteo returns CO in µg/m³; our breakpoints use mg/m³
        r.aqiCo    = (c.carbon_monoxide     !== undefined) ? c.carbon_monoxide / 1000.0 : NaN;

        // Pollen — Open-Meteo returns grains/m³ mapped to UPI 0–12 scale
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
            pd.push({ key: p.key, value: (v !== undefined && v !== null) ? v : NaN });
        });
        r.pollenData = pd;
    };
    req.send();
}

function fetchHourly(service, dateStr) {
    var r = service.weatherRoot;
    var tz = service.timezone;
    var url = "https://api.open-meteo.com/v1/forecast?latitude="
        + service.latitude
        + "&longitude=" + service.longitude
        + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
        + "&hourly=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,relative_humidity_2m,precipitation_probability,precipitation"
        + "&start_date=" + dateStr + "&end_date=" + dateStr;
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
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
                    precipMm: d.hourly.precipitation ? d.hourly.precipitation[i] : NaN
                });
        r.hourlyData = arr;
    };
    req.send();
}
