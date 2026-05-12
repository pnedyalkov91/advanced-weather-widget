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
 * WeatherService.qml — Weather API service layer
 *
 * Usage in main.qml:
 *   WeatherService { id: weatherService; weatherRoot: root }
 *
 * Providers are split into separate files under providers/.
 */
import QtQuick
import org.kde.plasma.plasmoid

import "js/weather.js" as W
import "providers/openMeteo.js" as OpenMeteoJS
import "providers/openWeather.js" as OpenWeatherJS
import "providers/weatherApi.js" as WeatherApiJS
import "providers/metNo.js" as MetNoJS
import "providers/pirateWeather.js" as PirateWeatherJS
import "providers/visualCrossing.js" as VisualCrossingJS
import "providers/tomorrowIo.js" as TomorrowIoJS
import "providers/stormGlass.js" as StormGlassJS
import "providers/weatherbit.js" as WeatherbitJS
import "providers/qWeather.js" as QWeatherJS
import "providers/alerts.js" as AlertsJS
import "providers/spaceWeather_provider.js" as SpaceWeatherJS

QtObject {
    id: service

    // ── Public interface ──────────────────────────────────────────────────
    /** Reference to the PlasmoidItem root — set from main.qml */
    property var weatherRoot

    // ── Config mirrors (accessible from non-pragma JS providers) ──────────
    // Read directly from individual Plasmoid.configuration entries.
    // KCM Apply syncs cfg_* → Plasmoid.configuration.* for these keys.
    // The popup's _applyPendingLocFields() also writes them directly.
    // NOTE: We intentionally do NOT read from activeLocation here because
    // the KCM framework has no cfg_activeLocation property and therefore
    // never syncs it — the JSON would stay stale after KCM Apply.
    readonly property real latitude:       Plasmoid.configuration.latitude
    readonly property real longitude:      Plasmoid.configuration.longitude
    readonly property string timezone:     (Plasmoid.configuration.timezone || "").trim()
    readonly property int forecastDays:    Plasmoid.configuration.forecastDays
    readonly property real altitude:       Plasmoid.configuration.altitude
    readonly property string countryCode:  (Plasmoid.configuration.countryCode || "").toUpperCase()
    readonly property string locationName: Plasmoid.configuration.locationName || ""

    // ── Private: API key helpers ─────────────────────────────────────────
    function _owKey() {
        return (Plasmoid.configuration.owApiKey || "").trim();
    }
    function _waKey() {
        return (Plasmoid.configuration.waApiKey || "").trim();
    }
    function _pwKey() {
        return (Plasmoid.configuration.pwApiKey || "").trim();
    }
    function _vcKey() {
        return (Plasmoid.configuration.vcApiKey || "").trim();
    }
    function _tioKey() {
        return (Plasmoid.configuration.tioApiKey || "").trim();
    }
    function _sgKey() {
        return (Plasmoid.configuration.sgApiKey || "").trim();
    }
    function _wbKey() {
        return (Plasmoid.configuration.wbApiKey || "").trim();
    }
    function _qwKey() {
        return (Plasmoid.configuration.qwApiKey || "").trim();
    }
    function _qwHost() {
        var h = (Plasmoid.configuration.qwApiHost || "").trim();
        if (!h) return "https://devapi.qweather.com";
        // Strip trailing slash
        return h.replace(/\/+$/, "");
    }

    // ── Private: space weather cache timestamp ──────────────────────────
    property real _lastSpaceWeatherFetch: 0

    // ── Request lifecycle — generation guard ────────────────────────────
    // _refreshGen increments on each refreshNow().  Callbacks captured at
    // send time compare their gen to the live value; a mismatch means a
    // newer refresh has started and the callback should silently bail out.
    // We intentionally do NOT call abort() on old XHRs — Qt QML's
    // XMLHttpRequest.abort() can block the JS thread on some platforms.
    property int _refreshGen: 0

    // Safety timer — if loading stays true for 20 s, force-reset state
    // so the widget never gets stuck in "Loading…" forever.
    property Timer _safetyTimer: Timer {
        interval: 20000
        repeat: false
        onTriggered: {
            if (weatherRoot && weatherRoot.loading) {
                console.warn("[WeatherService] Safety timeout — forcing loading=false");
                weatherRoot.loading = false;
                weatherRoot.updateText = i18n("Update timed out. Tap to retry.");
            }
        }
    }

    // ── Public methods ────────────────────────────────────────────────────

    /** Full weather refresh — current + daily forecast */
    function refreshNow() {
        _refreshGen++;
        _safetyTimer.stop();

        var r = weatherRoot;
        if (!r.hasSelectedTown) {
            r.loading = false;
            r.updateText = "";
            r.weatherDataStaged = null;
            r.aqiDataStaged = null;
            r.pollenDataStaged = [];
            r.spaceWeather = null;
            r.weatherAlerts = [];
            r.hourlyData = [];
            return;
        }
        r.loading = true;
        _safetyTimer.restart();
        r.weatherAlerts = [];  // reset before parallel fetch

        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var chain = (provider === "adaptive") ? ["openMeteo", "metno", "pirateWeather", "visualCrossing", "tomorrowIo", "stormGlass", "weatherbit", "qWeather", "openWeather", "weatherApi"] : [provider];
        chain._gen = _refreshGen;

        _tryProvider(chain, 0);
        // Fetch air quality + pollen in parallel with the main weather request
        // (independent of provider — always uses Open-Meteo air-quality API)
        _fetchAirQualityOpenMeteo();
        // Fetch NOAA space weather independently (location-independent)
        // Skip if data was fetched recently (< 10 min) since it doesn't change with location
        var now = Date.now();
        if (!_lastSpaceWeatherFetch || (now - _lastSpaceWeatherFetch) > 600000) {
            _lastSpaceWeatherFetch = now;
            SpaceWeatherJS.fetchSpaceWeather(service);
        }
    }

    /** Hourly data fetch for a specific date string (yyyy-MM-dd) */
    function fetchHourlyForDate(dateStr) {
        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var ap = (provider === "adaptive") ? "openMeteo" : provider;

        if (ap === "openMeteo") {
            OpenMeteoJS.fetchHourly(service, dateStr);
            return;
        }
        if (ap === "pirateWeather") {
            PirateWeatherJS.fetchHourly(service, W, dateStr);
            return;
        }
        if (ap === "openWeather") {
            OpenWeatherJS.fetchHourly(service, W, dateStr);
            return;
        }
        if (ap === "weatherApi") {
            WeatherApiJS.fetchHourly(service, W, dateStr);
            return;
        }
        if (ap === "metno") {
            MetNoJS.fetchHourly(service, W, dateStr);
            return;
        }
        if (ap === "visualCrossing") {
            VisualCrossingJS.fetchHourly(service, W, dateStr);
            return;
        }
        if (ap === "tomorrowIo") {
            TomorrowIoJS.fetchHourly(service, W, dateStr);
            return;
        }
        if (ap === "stormGlass") {
            StormGlassJS.fetchHourly(service, W, dateStr);
            return;
        }
        if (ap === "weatherbit") {
            WeatherbitJS.fetchHourly(service, W, dateStr);
            return;
        }
        if (ap === "qWeather") {
            QWeatherJS.fetchHourly(service, W, dateStr);
            return;
        }
        weatherRoot.hourlyData = [];
    }

    /**
     * Parallel variant used by ForecastView's expand-all mode.
     * Fires a real XHR for the given dateStr and calls callback(hourlyArray)
     * when done — never touches weatherRoot.hourlyData, so multiple in-flight
     * requests don't clobber each other.
     *
     * Falls back to fetchHourlyForDate (sequential) for providers that don't
     * expose a direct fetch yet.
     */
    function fetchHourlyForDateDirect(dateStr, callback) {
        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var ap = (provider === "adaptive") ? "openMeteo" : provider;
        var lat = service.latitude;
        var lon = service.longitude;
        var tz  = service.timezone || "auto";

        // ── Open-Meteo ────────────────────────────────────────────────────────
        if (ap === "openMeteo") {
            var url = "https://api.open-meteo.com/v1/forecast"
                + "?latitude="  + encodeURIComponent(lat)
                + "&longitude=" + encodeURIComponent(lon)
                + "&timezone="  + encodeURIComponent(tz)
                + "&hourly=temperature_2m,weather_code,wind_speed_10m,"
                + "wind_direction_10m,relative_humidity_2m,"
                + "precipitation_probability,precipitation"
                + "&start_date=" + encodeURIComponent(dateStr)
                + "&end_date="   + encodeURIComponent(dateStr)
                + "&wind_speed_unit=kmh";
            var xhr = new XMLHttpRequest();
            xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText);
                    var h = d.hourly || {}; var times = h.time || []; var arr = [];
                    for (var i = 0; i < times.length; i++) {
                        var t = times[i];
                        arr.push({
                            hour:       t.length >= 16 ? t.substr(11, 5) : "--",
                            tempC:      h.temperature_2m            ? h.temperature_2m[i]            : NaN,
                            code:       h.weather_code              ? h.weather_code[i]              : 0,
                            windKmh:    h.wind_speed_10m            ? h.wind_speed_10m[i]            : NaN,
                            windDeg:    h.wind_direction_10m        ? h.wind_direction_10m[i]        : NaN,
                            humidity:   h.relative_humidity_2m      ? h.relative_humidity_2m[i]      : NaN,
                            precipProb: h.precipitation_probability ? h.precipitation_probability[i] : NaN,
                            precipMm:   h.precipitation             ? h.precipitation[i]             : NaN
                        });
                    }
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── met.no ────────────────────────────────────────────────────────────
        if (ap === "metno") {
            var alt = service.altitude;
            var url = "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat="
                + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon)
                + ((!isNaN(alt) && alt !== 0) ? "&altitude=" + Math.round(alt) : "");
            var xhr = new XMLHttpRequest();
            xhr.open("GET", url);
            xhr.setRequestHeader("User-Agent",
                "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText); var arr = [];
                    if (d.properties && d.properties.timeseries)
                        d.properties.timeseries.forEach(function(ts) {
                            var dd = new Date(ts.time);
                            if (Qt.formatDate(dd, "yyyy-MM-dd") !== dateStr) return;
                            var det = ts.data && ts.data.instant ? ts.data.instant.details : null;
                            if (!det) return;
                            var sym = ts.data && ts.data.next_1_hours && ts.data.next_1_hours.summary
                                ? ts.data.next_1_hours.summary.symbol_code : "";
                            var p1h = ts.data && ts.data.next_1_hours && ts.data.next_1_hours.details
                                ? ts.data.next_1_hours.details : null;
                            arr.push({
                                hour:       Qt.formatTime(dd, "HH:mm"),
                                tempC:      det.air_temperature,
                                code:       W.metNoSymbolToWmo(sym),
                                windKmh:    det.wind_speed !== undefined ? det.wind_speed * 3.6 : NaN,
                                windDeg:    det.wind_from_direction !== undefined ? det.wind_from_direction : NaN,
                                humidity:   det.relative_humidity,
                                precipProb: p1h && p1h.probability_of_precipitation !== undefined
                                                ? p1h.probability_of_precipitation : NaN,
                                precipMm:   p1h && p1h.precipitation_amount !== undefined
                                                ? p1h.precipitation_amount : NaN
                            });
                        });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── OpenWeather ───────────────────────────────────────────────────────
        if (ap === "openWeather") {
            var key = service._owKey(); if (!key) { callback([]); return; }
            var url = "https://api.openweathermap.org/data/2.5/forecast?lat=" + lat
                + "&lon=" + lon + "&units=metric&appid=" + encodeURIComponent(key);
            var xhr = new XMLHttpRequest(); xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var fc = JSON.parse(xhr.responseText); var arr = [];
                    if (fc.list) fc.list.forEach(function(e) {
                        var d = new Date(e.dt * 1000);
                        if (Qt.formatDate(d, "yyyy-MM-dd") !== dateStr) return;
                        arr.push({
                            hour:       Qt.formatTime(d, "HH:mm"),
                            tempC:      e.main.temp,
                            code:       W.openWeatherCodeToWmo(e.weather[0].id),
                            windKmh:    e.wind ? e.wind.speed * 3.6 : NaN,
                            windDeg:    e.wind ? e.wind.deg : NaN,
                            humidity:   e.main.humidity,
                            precipProb: e.pop !== undefined ? Math.round(e.pop * 100) : NaN,
                            precipMm:   e.rain && e.rain["1h"] !== undefined ? e.rain["1h"]
                                        : e.rain && e.rain["3h"] !== undefined ? e.rain["3h"] / 3 : NaN
                        });
                    });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── Pirate Weather ────────────────────────────────────────────────────
        if (ap === "pirateWeather") {
            var key = service._pwKey(); if (!key) { callback([]); return; }
            var url = "https://api.pirateweather.net/forecast/"
                + encodeURIComponent(key) + "/" + lat + "," + lon
                + "?units=ca&exclude=minutely,daily,alerts&extend=hourly";
            var xhr = new XMLHttpRequest(); xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText); var arr = [];
                    function _pwIcon(icon) {
                        if (!icon) return 2;
                        if (icon.indexOf("clear") >= 0) return 0;
                        if (icon.indexOf("partly-cloudy") >= 0) return 2;
                        if (icon === "cloudy") return 3;
                        if (icon.indexOf("rain") >= 0) return 63;
                        if (icon.indexOf("snow") >= 0) return 73;
                        if (icon.indexOf("sleet") >= 0) return 66;
                        if (icon === "fog" || icon === "mist" || icon === "haze") return 45;
                        if (icon.indexOf("thunder") >= 0) return 95;
                        return 2;
                    }
                    if (d.hourly && d.hourly.data) d.hourly.data.forEach(function(h) {
                        var dt = new Date(h.time * 1000);
                        if (Qt.formatDate(dt, "yyyy-MM-dd") !== dateStr) return;
                        arr.push({
                            hour:       Qt.formatTime(dt, "HH:mm"),
                            tempC:      h.temperature,
                            code:       _pwIcon(h.icon),
                            windKmh:    h.windSpeed !== undefined ? h.windSpeed : NaN,
                            windDeg:    h.windBearing !== undefined ? h.windBearing : NaN,
                            humidity:   h.humidity !== undefined ? Math.round(h.humidity * 100) : NaN,
                            precipProb: h.precipProbability !== undefined ? Math.round(h.precipProbability * 100) : NaN,
                            precipMm:   h.precipIntensity !== undefined ? h.precipIntensity : NaN
                        });
                    });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── WeatherAPI ────────────────────────────────────────────────────────
        if (ap === "weatherApi") {
            var key = service._waKey(); if (!key) { callback([]); return; }
            var url = "https://api.weatherapi.com/v1/forecast.json?key="
                + encodeURIComponent(key)
                + "&q=" + encodeURIComponent(lat + "," + lon)
                + "&days=7&aqi=no&alerts=no&dt=" + dateStr;
            var xhr = new XMLHttpRequest(); xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText); var arr = [];
                    if (d.forecast && d.forecast.forecastday)
                        d.forecast.forecastday.forEach(function(day) {
                            if (day.date !== dateStr) return;
                            if (day.hour) day.hour.forEach(function(h) {
                                arr.push({
                                    hour:       Qt.formatTime(new Date(h.time_epoch * 1000), "HH:mm"),
                                    tempC:      h.temp_c,
                                    code:       W.weatherApiCodeToWmo(h.condition.code),
                                    windKmh:    h.wind_kph,
                                    windDeg:    h.wind_degree,
                                    humidity:   h.humidity,
                                    precipProb: h.chance_of_rain !== undefined ? h.chance_of_rain : NaN,
                                    precipMm:   h.precip_mm !== undefined ? h.precip_mm : NaN
                                });
                            });
                        });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── Visual Crossing ───────────────────────────────────────────────────
        if (ap === "visualCrossing") {
            var key = service._vcKey(); if (!key) { callback([]); return; }
            var url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/"
                + lat + "," + lon + "/" + dateStr + "/" + dateStr
                + "?key=" + encodeURIComponent(key)
                + "&unitGroup=metric&include=hours&iconSet=icons2";
            var xhr = new XMLHttpRequest(); xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText); var arr = [];
                    function _vcIcon(icon) {
                        if (!icon) return 2;
                        if (icon.indexOf("clear") >= 0) return 0;
                        if (icon.indexOf("partly-cloudy") >= 0) return 2;
                        if (icon === "cloudy") return 3;
                        if (icon.indexOf("thunder") >= 0) return 95;
                        if (icon.indexOf("snow") >= 0) return 73;
                        if (icon === "sleet") return 66;
                        if (icon.indexOf("rain") >= 0 || icon.indexOf("shower") >= 0) return 63;
                        if (icon === "fog") return 45;
                        return 2;
                    }
                    if (d.days && d.days.length > 0 && d.days[0].hours)
                        d.days[0].hours.forEach(function(h) {
                            arr.push({
                                hour:       h.datetime ? h.datetime.substring(0, 5) : "--",
                                tempC:      h.temp,
                                code:       _vcIcon(h.icon),
                                windKmh:    h.windspeed  !== undefined ? h.windspeed  : NaN,
                                windDeg:    h.winddir    !== undefined ? h.winddir    : NaN,
                                humidity:   h.humidity   !== undefined ? Math.round(h.humidity) : NaN,
                                precipProb: h.precipprob !== undefined ? Math.round(h.precipprob) : NaN,
                                precipMm:   h.precip     !== undefined ? h.precip : NaN
                            });
                        });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── Tomorrow.io ───────────────────────────────────────────────────────
        if (ap === "tomorrowIo") {
            var key = service._tioKey(); if (!key) { callback([]); return; }
            var url = "https://api.tomorrow.io/v4/weather/forecast"
                + "?location=" + lat + "," + lon
                + "&timesteps=1h&units=metric&apikey=" + encodeURIComponent(key);
            var xhr = new XMLHttpRequest(); xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText); var arr = [];
                    var m = {1000:0,1100:1,1101:2,1102:3,1001:3,2000:45,2100:45,4000:51,
                             4200:61,4001:63,4201:65,5001:77,5100:71,5000:73,5101:75,
                             6000:56,6200:66,6001:66,6201:67,7102:77,7000:77,7101:77,8000:95};
                    function _tioWmo(code) { return m[code] !== undefined ? m[code] : 2; }
                    var ht = d.timelines && d.timelines.hourly;
                    if (ht) ht.forEach(function(h) {
                        var dt = new Date(h.time);
                        if (Qt.formatDate(dt, "yyyy-MM-dd") !== dateStr) return;
                        var v = h.values;
                        arr.push({
                            hour:       Qt.formatTime(dt, "HH:mm"),
                            tempC:      v.temperature,
                            code:       _tioWmo(v.weatherCode),
                            windKmh:    v.windSpeed !== undefined ? v.windSpeed * 3.6 : NaN,
                            windDeg:    v.windDirection !== undefined ? v.windDirection : NaN,
                            humidity:   v.humidity !== undefined ? Math.round(v.humidity) : NaN,
                            precipProb: v.precipitationProbability !== undefined ? Math.round(v.precipitationProbability) : NaN,
                            precipMm:   v.precipitationIntensity !== undefined ? v.precipitationIntensity : NaN
                        });
                    });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── StormGlass ────────────────────────────────────────────────────────
        if (ap === "stormGlass") {
            var key = service._sgKey(); if (!key) { callback([]); return; }
            var url = "https://api.stormglass.io/v2/weather/point"
                + "?lat=" + lat + "&lng=" + lon
                + "&params=airTemperature,humidity,windSpeed,windDirection,precipitation,cloudCover";
            var xhr = new XMLHttpRequest(); xhr.open("GET", url);
            xhr.setRequestHeader("Authorization", key);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText); var arr = [];
                    function _sgV(obj) {
                        if (obj === undefined || obj === null) return NaN;
                        if (typeof obj === "number") return obj;
                        if (obj.sg !== undefined) return obj.sg;
                        var k = Object.keys(obj); return k.length > 0 ? obj[k[0]] : NaN;
                    }
                    function _sgWmo(cc, pr, t) {
                        cc = isNaN(cc)?0:cc; pr = isNaN(pr)?0:pr; t = isNaN(t)?10:t;
                        if (pr > 0.1) { if (t<=0) return pr>2?75:pr>0.5?73:71; return pr>7.5?65:pr>2.5?63:61; }
                        return cc>80?3:cc>50?2:cc>20?1:0;
                    }
                    if (d.hours) d.hours.forEach(function(h) {
                        var dt = new Date(h.time);
                        if (Qt.formatDate(dt, "yyyy-MM-dd") !== dateStr) return;
                        var t=_sgV(h.airTemperature), cc=_sgV(h.cloudCover), pr=_sgV(h.precipitation), ws=_sgV(h.windSpeed);
                        arr.push({
                            hour:       Qt.formatTime(dt, "HH:mm"),
                            tempC:      t, code: _sgWmo(cc, pr, t),
                            windKmh:    !isNaN(ws) ? ws * 3.6 : NaN,
                            windDeg:    _sgV(h.windDirection),
                            humidity:   (function(){ var v=_sgV(h.humidity); return !isNaN(v)?Math.round(v):NaN; })(),
                            precipProb: NaN, precipMm: pr
                        });
                    });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── Weatherbit ────────────────────────────────────────────────────────
        if (ap === "weatherbit") {
            var key = service._wbKey(); if (!key) { callback([]); return; }
            var url = "https://api.weatherbit.io/v2.0/forecast/hourly"
                + "?lat=" + lat + "&lon=" + lon
                + "&key=" + encodeURIComponent(key) + "&units=M&hours=48";
            var xhr = new XMLHttpRequest(); xhr.open("GET", url);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText); var arr = [];
                    function _wbWmo(code) {
                        if (!code) return 2;
                        if (code>=200&&code<=233) return 95; if (code>=300&&code<=302) return 51;
                        if (code===500) return 61; if (code===501) return 63; if (code===502) return 65;
                        if (code===511) return 66; if (code>=520&&code<=522) return 80;
                        if (code===600) return 71; if (code===601) return 73; if (code===602) return 75;
                        if (code===610||code===611||code===612) return 66;
                        if (code===621) return 85; if (code===622) return 86; if (code===623) return 77;
                        if (code>=700&&code<=751) return 45;
                        if (code===800) return 0; if (code===801) return 1; if (code===802) return 2; if (code>=803) return 3;
                        return 2;
                    }
                    if (d.data) d.data.forEach(function(h) {
                        var s = (h.timestamp_local || h.datetime || "");
                        if (s.substring(0, 10) !== dateStr) return;
                        var dt = new Date(s);
                        arr.push({
                            hour:       Qt.formatTime(dt, "HH:mm"),
                            tempC:      h.temp,
                            code:       _wbWmo(h.weather ? h.weather.code : undefined),
                            windKmh:    h.wind_spd !== undefined ? h.wind_spd * 3.6 : NaN,
                            windDeg:    h.wind_dir !== undefined ? h.wind_dir : NaN,
                            humidity:   h.rh !== undefined ? Math.round(h.rh) : NaN,
                            precipProb: h.pop !== undefined ? Math.round(h.pop) : NaN,
                            precipMm:   h.precip !== undefined ? h.precip : NaN
                        });
                    });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        // ── QWeather ──────────────────────────────────────────────────────────
        if (ap === "qWeather") {
            var key = service._qwKey(); if (!key) { callback([]); return; }
            var base = service._qwHost();
            var loc  = lon.toFixed(2) + "," + lat.toFixed(2);
            var url  = base + "/v7/weather/24h?location=" + encodeURIComponent(loc) + "&unit=m";
            var xhr = new XMLHttpRequest(); xhr.open("GET", url);
            xhr.setRequestHeader("X-QW-Api-Key", key);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) { callback([]); return; }
                try {
                    var d = JSON.parse(xhr.responseText); var arr = [];
                    function _qwWmo(code) {
                        code = parseInt(code, 10); if (isNaN(code)) return 2;
                        if (code===100||code===150) return 0;
                        if (code===101||code===102||code===151||code===152) return 2;
                        if (code===103||code===104||code===153) return 3;
                        if (code===302||code===303) return 95; if (code===304) return 99;
                        if (code===300||code===301||code===350||code===351) return 80;
                        if (code===305||code===309||code===314) return 61;
                        if (code===306||code===315) return 63;
                        if (code>=307&&code<=318) return 65; if (code===399) return 63;
                        if (code===313) return 66;
                        if (code===400||code===408) return 71; if (code===401||code===409) return 73;
                        if (code===402||code===403||code===410) return 75;
                        if (code===404||code===405) return 66;
                        if (code===406||code===407||code===456||code===457) return 77; if (code===499) return 73;
                        if (code>=500&&code<=515) return 45; return 2;
                    }
                    if (d.code === "200" && d.hourly) d.hourly.forEach(function(h) {
                        var dt = new Date(h.fxTime);
                        if (Qt.formatDate(dt, "yyyy-MM-dd") !== dateStr) return;
                        arr.push({
                            hour:       Qt.formatTime(dt, "HH:mm"),
                            tempC:      parseFloat(h.temp),
                            code:       _qwWmo(h.icon),
                            windKmh:    parseFloat(h.windSpeed),
                            windDeg:    parseFloat(h.wind360),
                            humidity:   parseFloat(h.humidity),
                            precipProb: h.pop !== undefined && h.pop !== null ? parseFloat(h.pop) : NaN,
                            precipMm:   parseFloat(h.precip) || NaN
                        });
                    });
                    callback(arr);
                } catch(e) { callback([]); }
            };
            xhr.send(); return;
        }

        callback([]);
    }


    // ── Private: provider chain ───────────────────────────────────────────

    property var _failed: []

    /**
     * Called by each provider after setting r.loading = false.
     * If the provider already populated weatherAlerts (native alerts),
     * this is a no-op.  Otherwise it falls back to MeteoAlarm / NWS.
     */
    function _fetchAlertsIfNeeded() {
        var r = weatherRoot;
        if (!r.weatherAlerts || r.weatherAlerts.length === 0) {
            console.log("[WeatherService] No native alerts → fetching via AlertsJS (countryCode=" + countryCode + ")");
            AlertsJS.fetchAlerts(service);
        } else {
            console.log("[WeatherService] Provider set", r.weatherAlerts.length, "native alert(s) → skipping AlertsJS");
        }
    }

    function _formatUpdateText(p) {
        var t = Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat));
        var name, url;
        if (p === "openWeather") {
            name = "OpenWeather";
            url = "https://openweathermap.org";
        } else if (p === "weatherApi") {
            name = "WeatherAPI.com";
            url = "https://www.weatherapi.com";
        } else if (p === "metno") {
            name = "MET Norway";
            url = "https://www.met.no";
        } else if (p === "pirateWeather") {
            name = "Pirate Weather";
            url = "https://pirateweather.net";
        } else if (p === "visualCrossing") {
            name = "Visual Crossing";
            url = "https://www.visualcrossing.com";
        } else if (p === "tomorrowIo") {
            name = "Tomorrow.io";
            url = "https://www.tomorrow.io";
        } else if (p === "stormGlass") {
            name = "StormGlass";
            url = "https://stormglass.io";
        } else if (p === "weatherbit") {
            name = "Weatherbit";
            url = "https://www.weatherbit.io";
        } else if (p === "qWeather") {
            name = "QWeather";
            url = "https://www.qweather.com";
        } else {
            name = "Open-Meteo";
            url = "https://open-meteo.com";
        }
        return i18n("Updated %1", t) + " \u00B7 " + i18n("Weather provider:") + " <a href='" + url + "'>" + name + "</a>";
    }

    function _providerLabel(p) {
        if (p === "openWeather")
            return "OpenWeather";
        if (p === "weatherApi")
            return "WeatherAPI.com";
        if (p === "metno")
            return "met.no";
        if (p === "pirateWeather")
            return "Pirate Weather";
        if (p === "visualCrossing")
            return "Visual Crossing";
        if (p === "tomorrowIo")
            return "Tomorrow.io";
        if (p === "stormGlass")
            return "StormGlass";
        if (p === "weatherbit")
            return "Weatherbit";
        if (p === "qWeather")
            return "QWeather";
        return "Open-Meteo";
    }

    function _tryProvider(chain, idx) {
        // If a newer refresh has started, stop advancing this chain
        if (idx > 0 && _refreshGen !== chain._gen) return;

        if (idx >= chain.length) {
            weatherRoot.loading = false;
            _safetyTimer.stop();
            var names = chain.map(function (p) {
                return _providerLabel(p);
            });
            weatherRoot.updateText = i18n("Failed: %1", names.join(", "));
            _failed = [];
            // Still fetch alerts even if all weather providers failed
            _fetchAlertsIfNeeded();
            return;
        }
        var p = chain[idx];
        if (p === "pirateWeather") {
            PirateWeatherJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        if (p === "visualCrossing") {
            VisualCrossingJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        if (p === "tomorrowIo") {
            TomorrowIoJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        if (p === "stormGlass") {
            StormGlassJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        if (p === "weatherbit") {
            WeatherbitJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        if (p === "qWeather") {
            QWeatherJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        if (p === "openWeather") {
            OpenWeatherJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        if (p === "weatherApi") {
            WeatherApiJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        if (p === "metno") {
            MetNoJS.fetchCurrent(service, W, chain, idx);
            return;
        }
        OpenMeteoJS.fetchCurrent(service, chain, idx); // default
    }

    // ─── Shared Open-Meteo air-quality + pollen fallback ────────────────────

    /**
     * Fetches AQI, pollutant concentrations, and pollen from the Open-Meteo
     * air-quality API and writes them into weatherRoot.
     * Called by providers that don't supply this data natively.
     */
    function _fetchAirQualityOpenMeteo() {
        var gen = _refreshGen;
        var r = weatherRoot;
        var tz = (Plasmoid.configuration.timezone || "").trim();
        var url = "https://air-quality-api.open-meteo.com/v1/air-quality"
            + "?latitude=" + Plasmoid.configuration.latitude
            + "&longitude=" + Plasmoid.configuration.longitude
            + "&current=european_aqi,pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone"
            + ",alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
            + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto");
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            if (_refreshGen !== gen) return;
            if (req.status !== 200) return;
            try {
                var d = JSON.parse(req.responseText);
                var c = d.current || {};
                var aqi = c.european_aqi;
                var label = "";
                if (aqi !== undefined) {
                    if      (aqi <= 20)  label = "Good";
                    else if (aqi <= 40)  label = "Fair";
                    else if (aqi <= 60)  label = "Moderate";
                    else if (aqi <= 80)  label = "Poor";
                    else if (aqi <= 100) label = "Very Poor";
                    else                 label = "Hazardous";
                }
                r.aqiDataStaged = {
                    index: (aqi !== undefined) ? aqi : NaN,
                    label: label,
                    pm10:  (c.pm10            !== undefined) ? c.pm10            : NaN,
                    pm2_5: (c.pm2_5           !== undefined) ? c.pm2_5           : NaN,
                    no2:   (c.nitrogen_dioxide !== undefined) ? c.nitrogen_dioxide : NaN,
                    so2:   (c.sulphur_dioxide  !== undefined) ? c.sulphur_dioxide  : NaN,
                    o3:    (c.ozone            !== undefined) ? c.ozone            : NaN,
                    co:    (c.carbon_monoxide  !== undefined) ? c.carbon_monoxide / 1000.0 : NaN
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
                    pd.push({ key: p.key, value: (v !== undefined && v !== null) ? v : NaN });
                });
                r.pollenDataStaged = pd;
            } catch (e) {}
        };
        req.send();
    }

    // ─── Sunrise/sunset fallback for providers that don't supply it ─────────

    /**
     * Fetches today's sunrise and sunset from Open-Meteo and writes them
     * into weatherRoot.  Called after met.no succeeds so night-icon logic
     * and isNightTime() work correctly even without a primary API for these.
     */
    function _fetchSunTimesOpenMeteo() {
        var gen = _refreshGen;
        var r = weatherRoot;
        var tz = (Plasmoid.configuration.timezone || "").trim();
        var today = Qt.formatDate(new Date(), "yyyy-MM-dd");
        var url = "https://api.open-meteo.com/v1/forecast" + "?latitude=" + Plasmoid.configuration.latitude + "&longitude=" + Plasmoid.configuration.longitude + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto") + "&daily=sunrise,sunset" + "&start_date=" + today + "&end_date=" + today;
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (_refreshGen !== gen) return;
            if (req.status !== 200)
                return;  // leave "--" in place — better than crashing
            try {
                var d = JSON.parse(req.responseText);
                if (r.weatherData && (
                    (d.daily && d.daily.sunrise && d.daily.sunrise.length > 0) ||
                    (d.daily && d.daily.sunset  && d.daily.sunset.length  > 0))) {
                    var patched = Object.assign({}, r.weatherData);
                    if (d.daily.sunrise && d.daily.sunrise.length > 0)
                        patched.sunriseTimeText = Qt.formatTime(new Date(d.daily.sunrise[0]), "HH:mm");
                    if (d.daily.sunset && d.daily.sunset.length > 0)
                        patched.sunsetTimeText = Qt.formatTime(new Date(d.daily.sunset[0]), "HH:mm");
                    if (d.utc_offset_seconds !== undefined)
                        patched.locationUtcOffsetMins = Math.round(d.utc_offset_seconds / 60);
                    r.weatherDataStaged = patched;
                }
            } catch (e) {}
        };
        req.send();
    }
}
