/**
 * WeatherService.qml — Weather API service layer
 *
 * Usage in main.qml:
 *   WeatherService { id: weatherService; weatherRoot: root }
 */
import QtQuick
import org.kde.plasma.plasmoid

import "js/weather.js" as W

QtObject {
    id: service

    // ── Public interface ──────────────────────────────────────────────────
    /** Reference to the PlasmoidItem root — set from main.qml */
    property var weatherRoot

    // ── Private: API key helpers ─────────────────────────────────────────
    function _owKey() {
        return (Plasmoid.configuration.owApiKey || "").trim();
    }
    function _waKey() {
        return (Plasmoid.configuration.waApiKey || "").trim();
    }

    // ── Public methods ────────────────────────────────────────────────────

    /** Full weather refresh — current + daily forecast */
    function refreshNow() {
        var r = weatherRoot;
        if (!r.hasSelectedTown) {
            r.loading = false;
            r.updateText = "";
            r.temperatureC = NaN;
            r.apparentC = NaN;
            r.windKmh = NaN;
            r.windDirection = NaN;
            r.pressureHpa = NaN;
            r.humidityPercent = NaN;
            r.visibilityKm = NaN;
            r.dewPointC = NaN;
            r.sunriseTimeText = "--";
            r.sunsetTimeText = "--";
            r.weatherCode = -1;
            r.isDay = -1;
            r.dailyData = [];
            r.hourlyData = [];
            return;
        }
        r.loading = true;

        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var chain = (provider === "adaptive") ? ["openMeteo", "openWeather", "weatherApi", "metno"] : [provider];

        _tryProvider(chain, 0);
    }

    /** Hourly data fetch for a specific date string (yyyy-MM-dd) */
    function fetchHourlyForDate(dateStr) {
        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var ap = (provider === "adaptive") ? "openMeteo" : provider;

        if (ap === "openMeteo") {
            _hourlyOpenMeteo(dateStr);
            return;
        }
        if (ap === "openWeather") {
            _hourlyOpenWeather(dateStr);
            return;
        }
        if (ap === "weatherApi") {
            _hourlyWeatherApi(dateStr);
            return;
        }
        if (ap === "metno") {
            _hourlyMetNo(dateStr);
            return;
        }
        weatherRoot.hourlyData = [];
    }

    // ── Private: provider chain ───────────────────────────────────────────

    // _failed tracks which providers were attempted and returned errors.
    // Entries are added by each _current* function before calling _tryProvider(chain, idx+1).
    property var _failed: []

    /**
     * Normalises a WeatherAPI "h:mm AM" / "h:mm PM" string to 24-hour "HH:mm"
     * so internal storage is always 24-hour regardless of API source.
     */
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

    function _providerLabel(p) {
        if (p === "openWeather")
            return "OpenWeather";
        if (p === "weatherApi")
            return "WeatherAPI.com";
        if (p === "metno")
            return "met.no";
        return "Open-Meteo";
    }

    function _tryProvider(chain, idx) {
        if (idx >= chain.length) {
            weatherRoot.loading = false;
            // Show exactly which provider(s) failed instead of a generic message
            var names = chain.map(function (p) {
                return _providerLabel(p);
            });
            weatherRoot.updateText = i18n("Failed: %1", names.join(", "));
            _failed = [];
            return;
        }
        var p = chain[idx];
        if (p === "openWeather") {
            _currentOpenWeather(chain, idx);
            return;
        }
        if (p === "weatherApi") {
            _currentWeatherApi(chain, idx);
            return;
        }
        if (p === "metno") {
            _currentMetNo(chain, idx);
            return;
        }
        _currentOpenMeteo(chain, idx); // default
    }

    // ─── Open-Meteo ───────────────────────────────────────────────────────

    function _currentOpenMeteo(chain, idx) {
        var r = weatherRoot;
        var tz = (Plasmoid.configuration.timezone || "").trim();
        var url = "https://api.open-meteo.com/v1/forecast" + "?latitude=" + Plasmoid.configuration.latitude + "&longitude=" + Plasmoid.configuration.longitude + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto") + "&current=temperature_2m,apparent_temperature,relative_humidity_2m," + "weather_code,wind_speed_10m,wind_direction_10m,surface_pressure," + "dew_point_2m,visibility,is_day" + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset";

        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status !== 200) {
                _tryProvider(chain, idx + 1);
                return;
            }
            var d = JSON.parse(req.responseText);
            if (!d.current) {
                _tryProvider(chain, idx + 1);
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
            r.sunriseTimeText = (d.daily && d.daily.sunrise && d.daily.sunrise.length > 0) ? Qt.formatTime(new Date(d.daily.sunrise[0]), "HH:mm") : "--";
            r.sunsetTimeText = (d.daily && d.daily.sunset && d.daily.sunset.length > 0) ? Qt.formatTime(new Date(d.daily.sunset[0]), "HH:mm") : "--";
            var nd = [];
            if (d.daily && d.daily.time) {
                var maxD = Math.min(Plasmoid.configuration.forecastDays, d.daily.time.length);
                for (var i = 0; i < maxD; ++i)
                    nd.push({
                        day: Qt.formatDate(new Date(d.daily.time[i]), "ddd"),
                        dateStr: d.daily.time[i],
                        maxC: d.daily.temperature_2m_max[i],
                        minC: d.daily.temperature_2m_min[i],
                        code: d.daily.weather_code[i]
                    });
            }
            r.dailyData = nd;
            r.loading = false;
            r.updateText = i18n("Updated %1 (Open-Meteo)", Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat)));
        };
        req.send();
    }

    // ─── OpenWeather ──────────────────────────────────────────────────────

    function _currentOpenWeather(chain, idx) {
        var r = weatherRoot;
        var key = _owKey();
        if (!key) {
            _tryProvider(chain, idx + 1);
            return;
        }
        var baseUrl = "https://api.openweathermap.org/data/2.5/";
        var latlon = "lat=" + Plasmoid.configuration.latitude + "&lon=" + Plasmoid.configuration.longitude + "&units=metric&appid=" + encodeURIComponent(key);

        var req = new XMLHttpRequest();
        req.open("GET", baseUrl + "weather?" + latlon);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status !== 200) {
                _tryProvider(chain, idx + 1);
                return;
            }
            var d = JSON.parse(req.responseText);
            if (!d.main) {
                _tryProvider(chain, idx + 1);
                return;
            }
            r.temperatureC = d.main.temp;
            r.apparentC = d.main.feels_like;
            r.humidityPercent = d.main.humidity;
            r.pressureHpa = d.main.pressure;
            r.windKmh = (d.wind && d.wind.speed !== undefined) ? d.wind.speed * 3.6 : NaN;
            r.windDirection = (d.wind && d.wind.deg !== undefined) ? d.wind.deg : NaN;
            r.dewPointC = NaN;
            r.visibilityKm = (d.visibility !== undefined) ? d.visibility / 1000.0 : NaN;
            r.weatherCode = (d.weather && d.weather.length > 0) ? W.openWeatherCodeToWmo(d.weather[0].id) : 2;
            r.isDay = -1;   // OpenWeather provides no is_day; derive from sunrise/sunset
            r.sunriseTimeText = (d.sys && d.sys.sunrise) ? Qt.formatTime(new Date(d.sys.sunrise * 1000), "HH:mm") : "--";
            r.sunsetTimeText = (d.sys && d.sys.sunset) ? Qt.formatTime(new Date(d.sys.sunset * 1000), "HH:mm") : "--";

            // Fetch forecast separately
            var fcReq = new XMLHttpRequest();
            fcReq.open("GET", baseUrl + "forecast?" + latlon);
            fcReq.onreadystatechange = function () {
                if (fcReq.readyState !== XMLHttpRequest.DONE)
                    return;
                var nd = [];
                if (fcReq.status === 200) {
                    var fc = JSON.parse(fcReq.responseText);
                    var seen = {};
                    if (fc.list)
                        fc.list.forEach(function (e) {
                            var dt = new Date(e.dt * 1000);
                            var dk = Qt.formatDate(dt, "yyyy-MM-dd");
                            var hr = dt.getHours();
                            if (!seen[dk] || Math.abs(hr - 12) < Math.abs(seen[dk].hour - 12))
                                seen[dk] = {
                                    hour: hr,
                                    entry: e,
                                    dk: dk
                                };
                        });
                    Object.keys(seen).sort().forEach(function (k) {
                        if (nd.length >= Plasmoid.configuration.forecastDays)
                            return;
                        var e = seen[k].entry;
                        nd.push({
                            day: Qt.formatDate(new Date(e.dt * 1000), "ddd"),
                            dateStr: k,
                            maxC: e.main.temp_max,
                            minC: e.main.temp_min,
                            code: W.openWeatherCodeToWmo(e.weather[0].id)
                        });
                    });
                }
                r.dailyData = nd;
                r.loading = false;
                r.updateText = i18n("Updated %1 (OpenWeather)", Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat)));
            };
            fcReq.send();
        };
        req.send();
    }

    // ─── WeatherAPI.com ───────────────────────────────────────────────────

    function _currentWeatherApi(chain, idx) {
        var r = weatherRoot;
        var key = _waKey();
        if (!key) {
            _tryProvider(chain, idx + 1);
            return;
        }
        var days = Math.max(3, Plasmoid.configuration.forecastDays);
        var url = "https://api.weatherapi.com/v1/forecast.json?key=" + encodeURIComponent(key) + "&q=" + encodeURIComponent(Plasmoid.configuration.latitude + "," + Plasmoid.configuration.longitude) + "&days=" + days + "&aqi=no&alerts=no";

        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status !== 200) {
                _tryProvider(chain, idx + 1);
                return;
            }
            var d = JSON.parse(req.responseText);
            if (!d.current) {
                _tryProvider(chain, idx + 1);
                return;
            }
            r.temperatureC = d.current.temp_c;
            r.apparentC = d.current.feelslike_c;
            r.humidityPercent = d.current.humidity;
            r.pressureHpa = d.current.pressure_mb;
            r.windKmh = d.current.wind_kph;
            r.windDirection = (d.current.wind_degree !== undefined) ? d.current.wind_degree : NaN;
            r.dewPointC = NaN;
            r.visibilityKm = d.current.vis_km;
            r.weatherCode = d.current.condition ? W.weatherApiCodeToWmo(d.current.condition.code) : 2;
            r.isDay = (d.current.is_day !== undefined) ? d.current.is_day : -1;
            if (d.forecast && d.forecast.forecastday && d.forecast.forecastday.length > 0) {
                var astro = d.forecast.forecastday[0].astro;
                r.sunriseTimeText = astro ? _apiTimeTo24h(astro.sunrise) : "--";
                r.sunsetTimeText = astro ? _apiTimeTo24h(astro.sunset) : "--";
            } else {
                r.sunriseTimeText = "--";
                r.sunsetTimeText = "--";
            }
            var nd = [];
            if (d.forecast && d.forecast.forecastday) {
                var maxD = Math.min(Plasmoid.configuration.forecastDays, d.forecast.forecastday.length);
                for (var i = 0; i < maxD; ++i) {
                    var f = d.forecast.forecastday[i];
                    nd.push({
                        day: Qt.formatDate(new Date(f.date), "ddd"),
                        dateStr: f.date,
                        maxC: f.day.maxtemp_c,
                        minC: f.day.mintemp_c,
                        code: W.weatherApiCodeToWmo(f.day.condition.code)
                    });
                }
            }
            r.dailyData = nd;
            r.loading = false;
            r.updateText = i18n("Updated %1 (WeatherAPI.com)", Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat)));
        };
        req.send();
    }

    // ─── met.no ───────────────────────────────────────────────────────────

    function _currentMetNo(chain, idx) {
        var r = weatherRoot;
        var alt = Plasmoid.configuration.altitude;
        var url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=" + encodeURIComponent(Plasmoid.configuration.latitude) + "&lon=" + encodeURIComponent(Plasmoid.configuration.longitude) + ((!isNaN(alt) && alt !== 0) ? "&altitude=" + Math.round(alt) : "");

        var req = new XMLHttpRequest();
        req.open("GET", url);
        // met.no Terms of Service: User-Agent identifying the app is MANDATORY.
        // Requests without it receive 403 Forbidden.
        req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status !== 200) {
                _tryProvider(chain, idx + 1);
                return;
            }
            var d = JSON.parse(req.responseText);
            if (!d.properties || !d.properties.timeseries || d.properties.timeseries.length === 0) {
                _tryProvider(chain, idx + 1);
                return;
            }
            var ts = d.properties.timeseries[0];
            var det = (ts.data && ts.data.instant) ? ts.data.instant.details : null;
            if (!det) {
                _tryProvider(chain, idx + 1);
                return;
            }

            r.temperatureC = det.air_temperature;
            r.apparentC = det.air_temperature;
            r.humidityPercent = det.relative_humidity;
            r.pressureHpa = det.air_pressure_at_sea_level;
            r.windKmh = (det.wind_speed !== undefined) ? det.wind_speed * 3.6 : NaN;
            r.windDirection = (det.wind_from_direction !== undefined) ? det.wind_from_direction : NaN;
            r.dewPointC = det.dew_point_temperature !== undefined ? det.dew_point_temperature : NaN;
            r.visibilityKm = NaN;
            var sym = (ts.data && ts.data.next_1_hours && ts.data.next_1_hours.summary) ? ts.data.next_1_hours.summary.symbol_code : "";
            r.weatherCode = W.metNoSymbolToWmo(sym);
            r.isDay = -1;   // met.no provides no is_day; derive from sunrise/sunset
            r.sunriseTimeText = "--";
            r.sunsetTimeText = "--";

            // Build daily forecast from timeseries
            var seen = {};
            d.properties.timeseries.forEach(function (t2) {
                var dd = new Date(t2.time);
                var dk = Qt.formatDate(dd, "yyyy-MM-dd");
                var hr = dd.getHours();
                var det2 = (t2.data && t2.data.instant) ? t2.data.instant.details : null;
                if (!det2)
                    return;
                if (!seen[dk] || Math.abs(hr - 12) < Math.abs(seen[dk].hour - 12)) {
                    var s2 = (t2.data && t2.data.next_1_hours && t2.data.next_1_hours.summary) ? t2.data.next_1_hours.summary.symbol_code : "";
                    seen[dk] = {
                        hour: hr,
                        tempC: det2.air_temperature,
                        code: W.metNoSymbolToWmo(s2),
                        dk: dk
                    };
                }
            });
            var nd = [];
            Object.keys(seen).sort().forEach(function (k) {
                if (nd.length >= Plasmoid.configuration.forecastDays)
                    return;
                var s3 = seen[k];
                nd.push({
                    day: Qt.formatDate(new Date(k), "ddd"),
                    dateStr: k,
                    maxC: s3.tempC,
                    minC: s3.tempC,
                    code: s3.code
                });
            });
            r.dailyData = nd;
            r.loading = false;
            r.updateText = i18n("Updated %1 (met.no)", Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat)));
        };
        req.send();
    }

    // ─── Hourly fetchers ──────────────────────────────────────────────────

    function _hourlyOpenMeteo(dateStr) {
        var r = weatherRoot;
        var tz = (Plasmoid.configuration.timezone || "").trim();
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + Plasmoid.configuration.latitude + "&longitude=" + Plasmoid.configuration.longitude + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto") + "&hourly=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,relative_humidity_2m,precipitation_probability" + "&start_date=" + dateStr + "&end_date=" + dateStr;
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
                        precipProb: d.hourly.precipitation_probability ? d.hourly.precipitation_probability[i] : NaN
                    });
            r.hourlyData = arr;
        };
        req.send();
    }

    function _hourlyOpenWeather(dateStr) {
        var r = weatherRoot;
        var key = _owKey();
        if (!key) {
            r.hourlyData = [];
            return;
        }
        var url = "https://api.openweathermap.org/data/2.5/forecast?lat=" + Plasmoid.configuration.latitude + "&lon=" + Plasmoid.configuration.longitude + "&units=metric&appid=" + encodeURIComponent(key);
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
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
                            precipProb: (e.pop !== undefined && e.pop !== null) ? Math.round(e.pop * 100) : NaN
                        });
                });
            r.hourlyData = arr;
        };
        req.send();
    }

    function _hourlyWeatherApi(dateStr) {
        var r = weatherRoot;
        var key = _waKey();
        if (!key) {
            r.hourlyData = [];
            return;
        }
        var url = "https://api.weatherapi.com/v1/forecast.json?key=" + encodeURIComponent(key) + "&q=" + encodeURIComponent(Plasmoid.configuration.latitude + "," + Plasmoid.configuration.longitude) + "&days=7&aqi=no&alerts=no&dt=" + dateStr;
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
                                precipProb: (h.chance_of_rain !== undefined) ? h.chance_of_rain : NaN
                            });
                        });
                });
            r.hourlyData = arr;
        };
        req.send();
    }

    function _hourlyMetNo(dateStr) {
        var r = weatherRoot;
        var alt = Plasmoid.configuration.altitude;
        var url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=" + encodeURIComponent(Plasmoid.configuration.latitude) + "&lon=" + encodeURIComponent(Plasmoid.configuration.longitude) + ((!isNaN(alt) && alt !== 0) ? "&altitude=" + Math.round(alt) : "");
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
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
                        var det = (ts.data && ts.data.instant) ? ts.data.instant.details : null;
                        if (!det)
                            return;
                        var sym = (ts.data && ts.data.next_1_hours && ts.data.next_1_hours.summary) ? ts.data.next_1_hours.summary.symbol_code : "";
                        arr.push({
                            hour: Qt.formatTime(dd, "HH:mm"),
                            tempC: det.air_temperature,
                            code: W.metNoSymbolToWmo(sym),
                            windKmh: det.wind_speed !== undefined ? det.wind_speed * 3.6 : NaN,
                            windDeg: det.wind_from_direction !== undefined ? det.wind_from_direction : NaN,
                            humidity: det.relative_humidity,
                            precipProb: (ts.data && ts.data.next_1_hours && ts.data.next_1_hours.details && ts.data.next_1_hours.details.probability_of_precipitation !== undefined) ? ts.data.next_1_hours.details.probability_of_precipitation : NaN
                        });
                    }
                });
            r.hourlyData = arr;
        };
        req.send();
    }
}
