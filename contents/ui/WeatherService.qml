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
 * WeatherService.qml - Weather API service layer
 *
 * Usage in main.qml:
 *   WeatherService { id: weatherService; weatherRoot: root }
 *
 * Providers are split into separate files under providers/.
 */
import QtQuick
import org.kde.plasma.plasmoid

import "js/weather.js" as W
import "js/airQuality.js" as AQI
// NOTE: the 12 provider .js modules are intentionally NOT imported here.
// They live in Providers.qml, which is created lazily on the first fetch
// (see _providers()) so ~3.7k lines of provider JS stay off the shell-startup
// critical path. W stays imported because fetchHourlyForDateDirect uses it inline.

QtObject {
    id: service

    // ── Public interface ──────────────────────────────────────────────────
    /** Reference to the PlasmoidItem root - set from main.qml */
    property var weatherRoot

    property string _updateProvider: ""
    property real _updateTimestampMs: 0

    // ── Lazy provider dispatcher ─────────────────────────────────────────
    // Providers.qml (which imports all 12 provider modules) is loaded on first
    // use instead of at widget construction, keeping provider JS off the shell-
    // startup path. createComponent is synchronous for local files, so the
    // object is ready immediately after the first call.
    property var _providersComponent: null
    property var _providersObj: null
    function _providers() {
        if (_providersObj) return _providersObj;
        if (!_providersComponent)
            _providersComponent = Qt.createComponent(Qt.resolvedUrl("Providers.qml"));
        if (_providersComponent.status === Component.Ready) {
            _providersObj = _providersComponent.createObject(service);
        } else if (_providersComponent.status === Component.Error) {
            console.warn("[WeatherService] Failed to load Providers.qml:",
                         _providersComponent.errorString());
        }
        return _providersObj;
    }

    // ── Config mirrors (accessible from non-pragma JS providers) ──────────
    // Read directly from individual Plasmoid.configuration entries.
    // KCM Apply syncs cfg_* → Plasmoid.configuration.* for these keys.
    // The popup's _applyPendingLocFields() also writes them directly.
    // NOTE: We intentionally do NOT read from activeLocation here because
    // the KCM framework has no cfg_activeLocation property and therefore
    // never syncs it - the JSON would stay stale after KCM Apply.
    readonly property real latitude:       Plasmoid.configuration.latitude
    readonly property real longitude:      Plasmoid.configuration.longitude
    readonly property string timezone:     (Plasmoid.configuration.timezone || "").trim()
    readonly property int forecastDays:    Plasmoid.configuration.forecastDays
    readonly property real altitude:       Plasmoid.configuration.altitude
    readonly property string countryCode:  (Plasmoid.configuration.countryCode || "").toUpperCase()
    // Air-quality standard: "auto" resolves US AQI/European CAQI/Canadian
    // AQHI from countryCode; otherwise an explicit "us"/"eu"/"ca" override.
    readonly property string aqiStandardOverride: Plasmoid.configuration.aqiStandard || "auto"
    // Open-Meteo model selection ("auto" = official national high-res model by
    // country; "default" = global best_match; otherwise a literal models= id).
    readonly property string openMeteoModel: Plasmoid.configuration.openMeteoModel || "auto"
    readonly property string locationName: Plasmoid.configuration.locationName || ""
    // Alerts source: "native" (provider alerts + MeteoAlarm/NWS fallback),
    // "librewxr" (LibreWXR worldwide CAP alerts API), or "foss" (KDE FOSS
    // Public Alert Server - worldwide CAP alerts).
    readonly property string alertsProvider: Plasmoid.configuration.alertsProvider || "native"
    // Base URL shared with the LibreWXR radar view (librewxrUrl config entry)
    readonly property string librewxrBaseUrl: {
        var u = (Plasmoid.configuration.librewxrUrl || "https://api.librewxr.net").trim();
        u = u.replace(/\/+$/, "");
        return u || "https://api.librewxr.net";
    }
    // Base URL for the FOSS Public Alert Server (self-hostable; default is
    // KDE's public instance at https://alerts.kde.org).
    readonly property string fossBaseUrl: {
        var u = (Plasmoid.configuration.fossAlertUrl || "https://alerts.kde.org").trim();
        u = u.replace(/\/+$/, "");
        return u || "https://alerts.kde.org";
    }

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

    // ── Request lifecycle - generation guard ────────────────────────────
    // _refreshGen increments on each refreshNow().  Callbacks captured at
    // send time compare their gen to the live value; a mismatch means a
    // newer refresh has started and the callback should silently bail out.
    // We intentionally do NOT call abort() on old XHRs - Qt QML's
    // XMLHttpRequest.abort() can block the JS thread on some platforms.
    property int _refreshGen: 0
    // Provider-side staging buffers used across multi-request fetch flows.
    // These must exist as declared QML properties because JS providers cannot
    // assign arbitrary new properties onto the WeatherService object.
    property var _tio_cur: null
    property var _wb_cur: null
    property var _qw_cur: null
    // BBC Weather is keyed by a numeric location id (not lat/lon). We cache the
    // id resolved from the locator service, keyed by rounded coordinates, so
    // repeat refreshes for the same location skip the extra lookup request.
    property string _bbcLocId: ""
    property string _bbcLocKey: ""
    // True once the current provider has written native alerts for this
    // refresh generation - lets _fetchAlertsIfNeeded() decide whether to
    // fall back to AlertsJS without having to blank weatherRoot.weatherAlerts
    // up front (which would hide a still-valid alert for the fetch duration).
    property bool _nativeAlertsSetThisGen: false
    // True once the selected provider has written a native air-quality index
    // for this refresh generation. The shared Open-Meteo air-quality fetch
    // always runs alongside it, and uses this flag to contribute only the
    // pollutant concentrations rather than overwriting the provider's index.
    property bool _nativeAqiSetThisGen: false
    // Per-generation accumulator behind _mergeAqiData(), which merges the
    // provider's index with the shared Open-Meteo fetch's pollutants instead
    // of letting the later response overwrite the earlier one.
    property var _aqiAccum: null
    property int _aqiAccumGen: -1

    // Safety timer - if loading stays true for 20 s, force-reset state
    // so the widget never gets stuck in "Loading…" forever.
    property Timer _safetyTimer: Timer {
        interval: 20000
        repeat: false
        onTriggered: {
            if (weatherRoot && weatherRoot.loading) {
                console.warn("[WeatherService] Safety timeout - forcing loading=false");
                weatherRoot.loading = false;
                service._clearUpdateMetadata();
                weatherRoot.updateText = i18n("Update timed out. Tap to retry.");
            }
        }
    }

    property Timer _relativeUpdateTimer: Timer {
        interval: 60000
        running: service._updateTimestampMs > 0 && (service._updateProvider || "").length > 0
        repeat: true
        onTriggered: service._refreshRelativeUpdateText()
    }

    // ── Auto-retry after a total provider-chain failure ─────────────────
    // Waking the laptop fires the resume-detection refresh (see main.qml's
    // heartbeat timer) before NetworkManager has actually reassociated with
    // Wi-Fi and DNS is working again - every provider in the chain fails
    // near-instantly (a connection/DNS error, not a slow per-request
    // timeout), exhausting all 11 within a fraction of a second, well
    // before the network is back. The widget was then stuck on
    // "Failed: ..." until the next scheduled auto-refresh
    // (refreshIntervalMinutes, commonly 15 min) or a manual tap. A short,
    // bounded, backed-off retry covers this - and any other transient
    // network blip - without hammering providers when genuinely offline
    // for a long stretch (e.g. on a plane). The count is reset by any
    // "real" refreshNow() call (manual, periodic, resume, config change)
    // and only preserved across the timer's own auto-retry call, so it
    // can't reset itself back to attempt 1 forever.
    property int _totalFailureRetryCount: 0
    readonly property var _totalFailureRetryDelaysMs: [5000, 15000, 45000]
    property Timer _totalFailureRetryTimer: Timer {
        interval: 5000
        repeat: false
        onTriggered: service.refreshNow(false, true)
    }

    // ── Public methods ────────────────────────────────────────────────────

    /** Full weather refresh - current + daily forecast.
     *  force=true bypasses the space weather fetch throttle (manual refresh).
     *  isAutoRetry=true marks a call made by _totalFailureRetryTimer itself -
     *  it preserves _totalFailureRetryCount instead of resetting it, so the
     *  timer's own retries don't reset their own backoff. */
    function refreshNow(force, isAutoRetry) {
        _refreshGen++;
        _safetyTimer.stop();
        _totalFailureRetryTimer.stop();
        if (isAutoRetry !== true) _totalFailureRetryCount = 0;

        var r = weatherRoot;
        if (!r.hasSelectedTown) {
            r.loading = false;
            service._clearUpdateMetadata();
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
        // Don't blank r.weatherAlerts here - that would hide the still-valid
        // alert from the UI for the whole duration of the fetch. The provider
        // (or the AlertsJS fallback) replaces it once new data is actually in.
        _nativeAlertsSetThisGen = false;
        _nativeAqiSetThisGen = false;

        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var chain = (provider === "adaptive") ? ["openMeteo", "bbc", "metno", "pirateWeather", "visualCrossing", "tomorrowIo", "stormGlass", "weatherbit", "qWeather", "openWeather", "weatherApi"] : [provider];
        chain._gen = _refreshGen;

        _tryProvider(chain, 0);
        // Fetch air quality + pollen in parallel with the main weather request.
        // Pirate Weather supplies AQI natively; other providers (and pollen,
        // which has no PW equivalent) fall back to Open-Meteo.
        var ap = (provider === "adaptive") ? "openMeteo" : provider;
        var _pAQ = _providers();
        if (!_pAQ || !_pAQ.fetchAirQuality(ap, service)) {
            _fetchAqi();
        }
        // When ap === "pirateWeather", the branch above dispatched PW's own
        // native fetch instead - PW's own completion handler calls _fetchAqi()
        // itself once it settles (see pirateWeather.js), so pollen and the
        // non-CAQI standards still resolve even though PW only ever supplies
        // the European figure natively.
        // Fetch NOAA space weather independently (location-independent)
        // Skip if data was fetched recently (< 10 min) since it doesn't change
        // with location - unless this is a forced (manual) refresh.
        // NOTE: _lastSpaceWeatherFetch is stamped by the provider itself, only
        // once it actually has data back (see spaceWeather_provider.js) - not
        // eagerly here at request time. Stamping it here unconditionally used
        // to mean that if the fetch failed outright (e.g. no network yet at
        // Plasma startup), the throttle still treated it as "fresh" and
        // silently blocked every automatic retry for the next 10 minutes,
        // leaving space weather empty until someone hit the manual refresh
        // button (which passes force=true and bypasses the throttle).
        var now = Date.now();
        if (force === true || !_lastSpaceWeatherFetch || (now - _lastSpaceWeatherFetch) > 600000) {
            var _pSW = _providers();
            if (_pSW) _pSW.fetchSpaceWeather(service);
        } else {
            // Kp/solar wind/Bz/X-ray really don't change with location, so
            // skipping the NOAA re-fetch above is correct. But the derived
            // aurora-visibility percentage bundled into the same object DOES
            // depend on the observer's latitude and local darkness - both of
            // which may have just changed if this refresh was triggered by a
            // location switch. Recompute just that value from the still-fresh
            // cached Kp instead of leaving it stuck showing the old city's
            // number.
            var _pSW2 = _providers();
            if (_pSW2) _pSW2.recomputeAuroraForLocation(service);
        }
    }

    /** Recomputes only the aurora-visibility percentage in weatherRoot.spaceWeather
     *  for the current latitude/darkness, without hitting the network. Used when
     *  the location changes but the NOAA data itself is still within its 10-min
     *  throttle window (see refreshNow). Safe to call at any time. */
    function recomputeAuroraForLocation() {
        var _p = _providers();
        if (_p) _p.recomputeAuroraForLocation(service);
    }

    /** Hourly data fetch for a specific date string (yyyy-MM-dd) */
    function fetchHourlyForDate(dateStr) {
        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var ap = (provider === "adaptive") ? "openMeteo" : provider;

        var _p = _providers();
        if (!_p || !_p.fetchHourly(ap, service, dateStr))
            weatherRoot.hourlyData = [];
    }

    /**
     * Parallel variant used by ForecastView's expand-all mode.
     * Fires a real XHR for the given dateStr and calls callback(hourlyArray)
     * when done - never touches weatherRoot.hourlyData, so multiple in-flight
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

        // ── BBC Weather ───────────────────────────────────────────────────────
        // BBC's id resolution lives in its provider module, so delegate the
        // whole parallel fetch there instead of inlining it here.
        if (ap === "bbc") {
            var _pB = _providers();
            if (!_pB || !_pB.fetchHourlyDirect(ap, service, dateStr, callback))
                callback([]);
            return;
        }

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
                + "&wind_speed_unit=kmh"
                + W.openMeteoModelParam(service.openMeteoModel, service.countryCode);
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
            function _qwHourlySpanHours(ds) {
                if (!ds)
                    return 168;
                var parts = ds.split("-");
                if (parts.length < 3)
                    return 168;
                var year = parseInt(parts[0], 10);
                var month = parseInt(parts[1], 10) - 1;
                var day = parseInt(parts[2], 10);
                if (isNaN(year) || isNaN(month) || isNaN(day))
                    return 168;
                var targetEnd = new Date(year, month, day, 23, 59, 59, 999);
                var diffHours = Math.ceil((targetEnd.getTime() - (new Date()).getTime()) / 3600000);
                if (diffHours <= 24)
                    return 24;
                if (diffHours <= 72)
                    return 72;
                return 168;
            }
            var url  = base + "/v7/weather/" + _qwHourlySpanHours(dateStr) + "h?location=" + encodeURIComponent(loc) + "&unit=m";
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
                            precipMm:   h.precip !== undefined && h.precip !== null ? parseFloat(h.precip) : NaN
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
     * With the LibreWXR alerts provider selected, alerts always come from
     * LibreWXR (overwriting any provider-native alerts on success).
     * Otherwise (native mode): if the provider already populated
     * weatherAlerts (native alerts), this is a no-op - else it falls
     * back to MeteoAlarm / NWS.
     */
    function _fetchAlertsIfNeeded() {
        var r = weatherRoot;
        if (alertsProvider === "librewxr") {
            console.log("[WeatherService] Alerts provider = LibreWXR → fetching " + librewxrBaseUrl);
            var _pL = _providers();
            if (_pL) _pL.fetchAlertsLibreWxr(service);
            return;
        }
        if (alertsProvider === "foss") {
            console.log("[WeatherService] Alerts provider = FOSS Public Alert Server → fetching " + fossBaseUrl);
            var _pF = _providers();
            if (_pF) _pF.fetchAlertsFoss(service);
            return;
        }
        if (!_nativeAlertsSetThisGen) {
            console.log("[WeatherService] No native alerts → fetching via AlertsJS (countryCode=" + countryCode + ")");
            var _pA = _providers();
            if (_pA) _pA.fetchAlerts(service);
        } else {
            console.log("[WeatherService] Provider set", (r.weatherAlerts || []).length, "native alert(s) → skipping AlertsJS");
        }
    }

    /**
     * Fetches the shared Open-Meteo air-quality/pollen data. Named _fetchAqi()
     * rather than "...IfNeeded" deliberately: it now always runs, regardless
     * of whether a provider (Pirate Weather) supplied a native AQI reading -
     * pollen has no provider equivalent, and US AQI / Canadian AQHI (and the
     * extra hourly pollutant history AQHI needs) only ever come from here.
     * _nativeAqiSetThisGen still matters *inside* _fetchAirQualityOpenMeteo():
     * it only gates that one function's europeanAqi contribution, so a
     * provider's native CAQI reading isn't overwritten by this call.
     */
    function _fetchAqi() {
        _fetchAirQualityOpenMeteo();
    }

    function _formatUpdateText(p) {
        service._updateTimestampMs = Date.now();
        service._updateProvider = p || "";
        return service._buildRelativeUpdateText(service._updateProvider);
    }

    function _clearUpdateMetadata() {
        service._updateTimestampMs = 0;
        service._updateProvider = "";
    }

    function _relativeUpdateAgeText() {
        var stamp = service._updateTimestampMs;
        if (!(stamp > 0))
            return "";
        var elapsedMinutes = Math.floor(Math.max(0, Date.now() - stamp) / 60000);
        if (elapsedMinutes < 1)
            return i18n("Updated just now");
        if (elapsedMinutes < 60)
            return i18np("Updated %1 minute ago", "Updated %1 minutes ago", elapsedMinutes);
        var elapsedHours = Math.floor(elapsedMinutes / 60);
        if (elapsedHours < 24)
            return i18np("Updated %1 hour ago", "Updated %1 hours ago", elapsedHours);
        var elapsedDays = Math.floor(elapsedHours / 24);
        return i18np("Updated %1 day ago", "Updated %1 days ago", elapsedDays);
    }

    function _providerUrl(p) {
        if (p === "openWeather")
            return "https://openweathermap.org";
        if (p === "weatherApi")
            return "https://www.weatherapi.com";
        if (p === "metno")
            return "https://www.met.no";
        if (p === "bbc")
            return "https://www.bbc.com/weather";
        if (p === "pirateWeather")
            return "https://pirateweather.net";
        if (p === "visualCrossing")
            return "https://www.visualcrossing.com";
        if (p === "tomorrowIo")
            return "https://www.tomorrow.io";
        if (p === "stormGlass")
            return "https://stormglass.io";
        if (p === "weatherbit")
            return "https://www.weatherbit.io";
        if (p === "qWeather")
            return "https://www.qweather.com";
        return "https://open-meteo.com";
    }

    function _providerLinkLabel(p) {
        if (p === "openWeather")
            return "OpenWeather";
        if (p === "weatherApi")
            return "WeatherAPI.com";
        if (p === "metno")
            return "MET Norway";
        if (p === "bbc")
            return "BBC Weather";
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

    function _buildRelativeUpdateText(p) {
        var provider = p || service._updateProvider;
        if ((provider || "").length === 0)
            return "";
        var providerLink = "<a href='" + service._providerUrl(provider) + "'>" + service._providerLinkLabel(provider) + "</a>";
        if (provider !== "openWeather" && provider !== "weatherApi" && provider !== "metno" && provider !== "bbc"
            && provider !== "pirateWeather" && provider !== "visualCrossing" && provider !== "tomorrowIo"
            && provider !== "stormGlass" && provider !== "weatherbit" && provider !== "qWeather") {
            var mi = W.openMeteoModelInfo(openMeteoModel, countryCode);
            if (mi)
                providerLink += " (<a href='" + mi.url + "'>" + mi.name + "</a>)";
        }
        return service._relativeUpdateAgeText() + " \u00B7 " + i18n("Weather provider:") + " " + providerLink;
    }

    function _refreshRelativeUpdateText() {
        if (!weatherRoot || weatherRoot.loading)
            return;
        var next = service._buildRelativeUpdateText(service._updateProvider);
        if (next.length > 0)
            weatherRoot.updateText = next;
    }

    function _providerLabel(p) {
        if (p === "openWeather")
            return "OpenWeather";
        if (p === "weatherApi")
            return "WeatherAPI.com";
        if (p === "metno")
            return "met.no";
        if (p === "bbc")
            return "BBC Weather";
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
            service._clearUpdateMetadata();
            if (_totalFailureRetryCount < _totalFailureRetryDelaysMs.length) {
                _totalFailureRetryTimer.interval = _totalFailureRetryDelaysMs[_totalFailureRetryCount];
                _totalFailureRetryCount++;
                _totalFailureRetryTimer.restart();
                weatherRoot.updateText = i18n("Failed: %1 — retrying…", names.join(", "));
            } else {
                weatherRoot.updateText = i18n("Failed: %1", names.join(", "));
            }
            _failed = [];
            // Still fetch alerts even if all weather providers failed
            _fetchAlertsIfNeeded();
            return;
        }
        var p = chain[idx];
        var _p = _providers();
        if (!_p) {
            // Providers.qml failed to load - fail this refresh gracefully.
            weatherRoot.loading = false;
            _safetyTimer.stop();
            service._clearUpdateMetadata();
            weatherRoot.updateText = i18n("Failed to load weather providers");
            return;
        }
        _p.fetchCurrent(p, service, chain, idx);
    }

    // ─── Shared Open-Meteo air-quality + pollen fallback ────────────────────

    /**
     * Merges a partial air-quality patch into weatherRoot.aqiDataStaged.
     *
     * Two independent sources write air-quality data on every refresh: the
     * selected provider (Pirate Weather, natively CAQI-only) and the shared
     * Open-Meteo fetch below (all six pollutant concentrations, us_aqi, and
     * - only when the resolved standard is Canadian - aqhi). They race, so a
     * plain assignment lets whichever response lands second discard the
     * other's fields - which is what used to leave PM2.5 and the rest of the
     * pollutant rows showing "--" under OpenWeather / WeatherAPI / QWeather.
     *
     * Ownership is therefore split per field: a provider may claim
     * europeanAqi and set _nativeAqiSetThisGen; the shared fetch always
     * contributes the pollutants, usAqi, and (when relevant) aqhi, and only
     * fills in europeanAqi itself when no provider already claimed it.
     * Neither clobbers the other regardless of arrival order. Which of
     * europeanAqi/usAqi/aqhi is actually shown is decided at render time by
     * airQuality.js's resolveStandard() + standardDisplay() - see
     * weatherRoot.airQualityText() in main.qml.
     *
     * At the start of each refresh generation the accumulator is seeded from
     * the data already on screen rather than from an empty object, so the
     * card doesn't flash "--" between the first and second response of the
     * new generation (same reasoning as weatherAlerts in refreshNow()). A
     * successful shared fetch rewrites all its own keys, so a stale reading
     * only survives a fetch that failed outright.
     */
    function _mergeAqiData(patch) {
        if (!patch)
            return;
        if (_aqiAccumGen !== _refreshGen) {
            _aqiAccum = weatherRoot.aqiData || {};
            _aqiAccumGen = _refreshGen;
        }
        var merged = {};
        var k;
        for (k in _aqiAccum)
            merged[k] = _aqiAccum[k];
        for (k in patch) {
            if (patch[k] === undefined)
                continue;
            merged[k] = patch[k];
        }
        _aqiAccum = merged;
        // Hand the staging property a fresh object - QML compares by
        // reference, so mutating the accumulator in place would not notify.
        var out = {};
        for (k in merged)
            out[k] = merged[k];
        weatherRoot.aqiDataStaged = out;
    }

    /**
     * Fetches pollutant concentrations, pollen, and the raw index values for
     * all three air-quality standards from the Open-Meteo air-quality API,
     * and writes them into weatherRoot. Always runs on every refresh (see
     * _fetchAqi() above) since pollen has no provider equivalent, and US AQI
     * / Canadian AQHI have no provider equivalent either.
     *
     * european_aqi and us_aqi are both requested in the same "current" call
     * regardless of which standard is actually resolved for this location -
     * that costs nothing extra (same request, a couple more numbers in the
     * response) and means switching the Misc-tab override between "auto" /
     * "US AQI" / "European CAQI" is instant, with no refetch needed.
     *
     * AQHI is different: it's defined over 3-hour moving averages, which the
     * "current" snapshot can't give us. Only when Canadian AQHI is actually
     * needed - the resolved standard is Canadian, or the Misc-tab "show
     * standards" switches have the AQHI one on - does this add an
     * &hourly=...&past_hours=2 request for the three pollutants the ECCC
     * formula needs, scoped deliberately small and only fetched when it'll
     * actually be used.
     *
     * forecast_hours is set to 1, not 0, to actually include the current
     * hour: Open-Meteo's own time-range builder (forecastTimeRange2 in
     * ForecastapiQuery.swift) computes the window as a half-open range
     * [currentHour - past_hours, currentHour + forecast_hours) - the end is
     * exclusive, so forecast_hours=0 collapses that to end === currentHour
     * and excludes it, returning only the 2 *preceding* hours. forecast_hours=1
     * pushes the exclusive end one hour past "now", which is what actually
     * makes the current hour the last of the 3 included points.
     */
    function _fetchAirQualityOpenMeteo() {
        var gen = _refreshGen;
        var r = weatherRoot;
        var tz = (Plasmoid.configuration.timezone || "").trim();
        var standard = AQI.resolveStandard(Plasmoid.configuration.countryCode, Plasmoid.configuration.aqiStandard || "auto");
        // The three "show standards" switches (Misc tab) can request AQHI
        // even when it isn't the single resolved standard above - whenever
        // any of the three is on, they take over from the single-standard
        // selector, so the resolved standard on its own is not enough to
        // decide whether the AQHI hourly block is needed.
        var multiMode = (Plasmoid.configuration.aqiShowUs === true)
            || (Plasmoid.configuration.aqiShowEu === true)
            || (Plasmoid.configuration.aqiShowCa === true);
        var needsAqhi = multiMode ? (Plasmoid.configuration.aqiShowCa === true) : (standard === "ca");
        var url = "https://air-quality-api.open-meteo.com/v1/air-quality"
            + "?latitude=" + Plasmoid.configuration.latitude
            + "&longitude=" + Plasmoid.configuration.longitude
            + "&current=european_aqi,us_aqi,pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone"
            + ",alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
            + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto");
        if (needsAqhi)
            url += "&hourly=pm2_5,nitrogen_dioxide,ozone&past_hours=2&forecast_hours=1";
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            if (_refreshGen !== gen) return;
            if (req.status !== 200) return;
            try {
                var d = JSON.parse(req.responseText);
                var c = d.current || {};

                // Pollutants and us_aqi always come from here - they are the
                // only source the UI has for them. europeanAqi is
                // contributed only when no provider already claimed it
                // natively this generation (see pirateWeather.js).
                var patch = {
                    pm10:  (c.pm10             !== undefined) ? c.pm10             : NaN,
                    pm2_5: (c.pm2_5            !== undefined) ? c.pm2_5            : NaN,
                    no2:   (c.nitrogen_dioxide !== undefined) ? c.nitrogen_dioxide : NaN,
                    so2:   (c.sulphur_dioxide  !== undefined) ? c.sulphur_dioxide  : NaN,
                    o3:    (c.ozone            !== undefined) ? c.ozone            : NaN,
                    co:    (c.carbon_monoxide  !== undefined) ? c.carbon_monoxide / 1000.0 : NaN,
                    usAqi: (c.us_aqi           !== undefined) ? c.us_aqi           : NaN
                };
                if (!_nativeAqiSetThisGen)
                    patch.europeanAqi = (c.european_aqi !== undefined) ? c.european_aqi : NaN;

                // aqhi is only ever populated on a generation that actually
                // requested the hourly block above (needsAqhi) - explicitly
                // NaN otherwise, so a stale reading from a previous
                // Canadian location (or from AQHI being switched off) can't
                // linger unused in the accumulator and be mistaken for
                // fresh data.
                //
                // The average is taken over whatever trailing hours are
                // actually present (up to 3) rather than requiring exactly
                // 3, so a request-boundary edge case degrades to a shorter
                // average instead of an empty result - the forecast_hours=1
                // fix above should always yield exactly 3, but this doesn't
                // depend on that holding precisely.
                if (needsAqhi) {
                    var aqhi = NaN;
                    var h = d.hourly;
                    if (h && h.pm2_5 && h.nitrogen_dioxide && h.ozone && h.pm2_5.length >= 1) {
                        var n = h.pm2_5.length;
                        var take = Math.min(3, n);
                        var avgLast = function (arr) {
                            var sum = 0, count = 0;
                            for (var k = n - take; k < n; k++) {
                                var v = arr[k];
                                if (v === null || v === undefined || isNaN(v)) continue;
                                sum += v;
                                count++;
                            }
                            return count > 0 ? sum / count : NaN;
                        };
                        var pm25_3h   = avgLast(h.pm2_5);
                        var no2Ppb_3h = AQI.ugm3ToPpb(avgLast(h.nitrogen_dioxide), "no2");
                        var o3Ppb_3h  = AQI.ugm3ToPpb(avgLast(h.ozone), "o3");
                        aqhi = AQI.aqhiFromPollutants(no2Ppb_3h, o3Ppb_3h, pm25_3h);
                    }
                    patch.aqhi = aqhi;
                } else {
                    patch.aqhi = NaN;
                }

                _mergeAqiData(patch);
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
                return;  // leave "--" in place - better than crashing
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
