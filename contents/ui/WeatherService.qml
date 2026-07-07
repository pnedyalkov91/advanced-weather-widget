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
// NOTE: the 12 provider .js modules are intentionally NOT imported here.
// They live in Providers.qml, which is created lazily on the first fetch
// (see _providers()) so ~3.7k lines of provider JS stay off the shell-startup
// critical path. W stays imported because fetchHourlyForDateDirect uses it inline.

QtObject {
    id: service

    // ── Public interface ──────────────────────────────────────────────────
    /** Real PlasmoidItem root — set from main.qml. */
    property var rootRef

    /** Provider-facing mutable sink. Direct-hourly fetch may override this. */
    property var weatherRoot: rootRef

    // Provider modules are imported JS files. Mutating nested fields on
    // `service.weatherRoot` does not reliably notify QML here, so providers
    // write to these pass-through properties on `service` instead.
    property bool loading: false
    onLoadingChanged: if (rootRef) rootRef.loading = loading

    property string updateText: ""
    onUpdateTextChanged: if (rootRef) rootRef.updateText = updateText

    property var weatherDataStaged: null
    onWeatherDataStagedChanged: if (rootRef) rootRef.weatherDataStaged = weatherDataStaged

    property var aqiDataStaged: null
    onAqiDataStagedChanged: if (rootRef) rootRef.aqiDataStaged = aqiDataStaged

    property var pollenDataStaged: []
    onPollenDataStagedChanged: if (rootRef) rootRef.pollenDataStaged = pollenDataStaged || []

    property var weatherAlerts: []
    onWeatherAlertsChanged: if (rootRef) rootRef.weatherAlerts = weatherAlerts || []

    property var hourlyData: []
    onHourlyDataChanged: if (weatherRoot) weatherRoot.hourlyData = hourlyData || []

    property var spaceWeather: null
    onSpaceWeatherChanged: if (rootRef) rootRef.spaceWeather = spaceWeather

    property var spaceWeatherDailyForecast: ({})
    onSpaceWeatherDailyForecastChanged: if (rootRef) rootRef.spaceWeatherDailyForecast = spaceWeatherDailyForecast || ({})

    property var spaceWeatherForecastPeriods: []
    onSpaceWeatherForecastPeriodsChanged: if (rootRef) rootRef.spaceWeatherForecastPeriods = spaceWeatherForecastPeriods || []

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
    // never syncs it — the JSON would stay stale after KCM Apply.
    readonly property real latitude:       Plasmoid.configuration.latitude
    readonly property real longitude:      Plasmoid.configuration.longitude
    readonly property string timezone:     (Plasmoid.configuration.timezone || "").trim()
    readonly property int forecastDays:    Plasmoid.configuration.forecastDays
    readonly property real altitude:       Plasmoid.configuration.altitude
    readonly property string countryCode:  (Plasmoid.configuration.countryCode || "").toUpperCase()
    // Open-Meteo model selection ("auto" = official national high-res model by
    // country; "default" = global best_match; otherwise a literal models= id).
    readonly property string openMeteoModel: Plasmoid.configuration.openMeteoModel || "auto"
    readonly property string locationName: Plasmoid.configuration.locationName || ""
    // Alerts source: "native" (provider alerts + MeteoAlarm/NWS fallback),
    // "librewxr" (LibreWXR worldwide CAP alerts API), or "foss" (KDE FOSS
    // Public Alert Server — worldwide CAP alerts).
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

    // ── Request lifecycle — generation guard ────────────────────────────
    // _refreshGen increments on each refreshNow().  Callbacks captured at
    // send time compare their gen to the live value; a mismatch means a
    // newer refresh has started and the callback should silently bail out.
    // We intentionally do NOT call abort() on old XHRs — Qt QML's
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
    // refresh generation — lets _fetchAlertsIfNeeded() decide whether to
    // fall back to AlertsJS without having to blank weatherRoot.weatherAlerts
    // up front (which would hide a still-valid alert for the fetch duration).
    property bool _nativeAlertsSetThisGen: false

    // Safety timer — if loading stays true for 20 s, force-reset state
    // so the widget never gets stuck in "Loading…" forever.
    property Timer _safetyTimer: Timer {
        interval: 20000
        repeat: false
        onTriggered: {
            if (service.loading) {
                console.warn("[WeatherService] Safety timeout — forcing loading=false");
                service.loading = false;
                service._clearUpdateMetadata();
                service.updateText = i18n("Update timed out. Tap to retry.");
            }
        }
    }

    property Timer _relativeUpdateTimer: Timer {
        interval: 60000
        running: service._updateTimestampMs > 0 && (service._updateProvider || "").length > 0
        repeat: true
        onTriggered: service._refreshRelativeUpdateText()
    }

    function _hasConfiguredLocation() {
        var name = (locationName || "").trim();
        if (name.length > 0)
            return true;
        return !isNaN(latitude) && !isNaN(longitude) && (latitude !== 0 || longitude !== 0);
    }

    // ── Public methods ────────────────────────────────────────────────────

    /** Full weather refresh — current + daily forecast.
     *  force=true bypasses the space weather fetch throttle (manual refresh). */
    function refreshNow(force) {
        _refreshGen++;
        _safetyTimer.stop();

        var r = service;
        if (!_hasConfiguredLocation()) {
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
        // Don't blank r.weatherAlerts here — that would hide the still-valid
        // alert from the UI for the whole duration of the fetch. The provider
        // (or the AlertsJS fallback) replaces it once new data is actually in.
        _nativeAlertsSetThisGen = false;

        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var chain = (provider === "adaptive") ? ["openMeteo", "bbc", "metno", "pirateWeather", "visualCrossing", "tomorrowIo", "stormGlass", "weatherbit", "qWeather", "openWeather", "weatherApi"] : [provider];
        chain._gen = _refreshGen;

        _tryProvider(chain, 0);
        // Fetch air quality + pollen in parallel with the main weather request
        // (independent of provider — always uses Open-Meteo air-quality API)
        _fetchAirQualityOpenMeteo();
        // Fetch NOAA space weather independently (location-independent)
        // Skip if data was fetched recently (< 10 min) since it doesn't change
        // with location — unless this is a forced (manual) refresh
        var now = Date.now();
        if (force === true || !_lastSpaceWeatherFetch || (now - _lastSpaceWeatherFetch) > 600000) {
            _lastSpaceWeatherFetch = now;
            var _pSW = _providers();
            if (_pSW) _pSW.fetchSpaceWeather(service);
        }
    }

    /** Hourly data fetch for a specific date string (yyyy-MM-dd) */
    function fetchHourlyForDate(dateStr) {
        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var ap = (provider === "adaptive") ? "openMeteo" : provider;

        var _p = _providers();
        if (!_p || !_p.fetchHourly(ap, service, dateStr))
            service.hourlyData = [];
    }

    /**
     * Non-mutating hourly fetch used by ForecastView prefetch/expand-all and
     * notification helpers. Reuses the same per-provider parsing path as the
     * normal sequential fetch, but captures the result into a temporary sink so
     * shared weatherRoot.hourlyData is never overwritten by concurrent calls.
     */
    function fetchHourlyForDateDirect(dateStr, callback) {
        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var ap = (provider === "adaptive") ? "openMeteo" : provider;
        if (typeof callback !== "function")
            return;
        var _p = _providers();
        if (!_p) {
            callback([]);
            return;
        }

        // BBC resolves its location id inside the provider module, so reuse
        // its direct path instead of proxying through the shared hourly sink.
        if (ap === "bbc") {
            if (!_p.fetchHourlyDirect(ap, service, dateStr, callback))
                callback([]);
            return;
        }

        var delivered = false;
        var sink = {
            _rows: [],
            get hourlyData() {
                return this._rows;
            },
            set hourlyData(rows) {
                this._rows = rows || [];
                if (delivered)
                    return;
                delivered = true;
                callback(this._rows);
            }
        };

        var proxyService = Object.create(service);
        proxyService.weatherRoot = sink;
        proxyService._refreshGen = service._refreshGen;
        Object.defineProperty(proxyService, "hourlyData", {
            configurable: true,
            get: function () { return sink.hourlyData; },
            set: function (rows) { sink.hourlyData = rows; }
        });

        try {
            if (!_p.fetchHourly(ap, proxyService, dateStr)) {
                delivered = true;
                callback([]);
            }
        } catch (e) {
            if (!delivered) {
                delivered = true;
                callback([]);
            }
        }
    }


    // ── Private: provider chain ───────────────────────────────────────────

    property var _failed: []

    /**
     * Called by each provider after setting r.loading = false.
     * With the LibreWXR alerts provider selected, alerts always come from
     * LibreWXR (overwriting any provider-native alerts on success).
     * Otherwise (native mode): if the provider already populated
     * weatherAlerts (native alerts), this is a no-op — else it falls
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
            service.loading = false;
            _safetyTimer.stop();
            var names = chain.map(function (p) {
                return _providerLabel(p);
            });
            service._clearUpdateMetadata();
            service.updateText = i18n("Failed: %1", names.join(", "));
            _failed = [];
            // Still fetch alerts even if all weather providers failed
            _fetchAlertsIfNeeded();
            return;
        }
        var p = chain[idx];
        var _p = _providers();
        if (!_p) {
            // Providers.qml failed to load — fail this refresh gracefully.
            service.loading = false;
            _safetyTimer.stop();
            service._clearUpdateMetadata();
            service.updateText = i18n("Failed to load weather providers");
            return;
        }
        _p.fetchCurrent(p, service, chain, idx);
    }

    // ─── Shared Open-Meteo air-quality + pollen fallback ────────────────────

    /**
     * Fetches AQI, pollutant concentrations, and pollen from the Open-Meteo
     * air-quality API and writes them through WeatherService pass-through state.
     * Called by providers that don't supply this data natively.
     */
    function _fetchAirQualityOpenMeteo() {
        var gen = _refreshGen;
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
            if (req.readyState !== XMLHttpRequest.DONE) return;
            if (_refreshGen !== gen) return;
            if (req.status !== 200) {
                r.aqiDataStaged = null;
                r.pollenDataStaged = [];
                return;
            }
            try {
                var d = JSON.parse(req.responseText);
                var c = d.current || {};
                var aqi = c.european_aqi;
                var hasAqi = aqi !== undefined && aqi !== null && !isNaN(aqi);
                var label = "";
                if (hasAqi) {
                    if      (aqi <= 20)  label = "Good";
                    else if (aqi <= 40)  label = "Fair";
                    else if (aqi <= 60)  label = "Moderate";
                    else if (aqi <= 80)  label = "Poor";
                    else if (aqi <= 100) label = "Very Poor";
                    else                 label = "Hazardous";
                }
                r.aqiDataStaged = {
                    index: hasAqi ? aqi : NaN,
                    label: label,
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
            } catch (e) {
                r.aqiDataStaged = null;
                r.pollenDataStaged = [];
            }
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
        var r = service;
        var tz = service.timezone;
        var url = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + service.latitude
            + "&longitude=" + service.longitude
            + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto")
            + "&forecast_days=1"
            + "&daily=sunrise,sunset";
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
                var currentData = service.weatherDataStaged
                    || (rootRef ? (rootRef.weatherDataStaged || rootRef.weatherData) : null);
                if (currentData && (
                    (d.daily && d.daily.sunrise && d.daily.sunrise.length > 0) ||
                    (d.daily && d.daily.sunset  && d.daily.sunset.length  > 0))) {
                    var patched = Object.assign({}, currentData);
                    if (d.daily.sunrise && d.daily.sunrise.length > 0)
                        patched.sunriseTimeText = Qt.formatTime(new Date(d.daily.sunrise[0]), "HH:mm");
                    if (d.daily.sunset && d.daily.sunset.length > 0)
                        patched.sunsetTimeText = Qt.formatTime(new Date(d.daily.sunset[0]), "HH:mm");
                    if (d.utc_offset_seconds !== undefined)
                        patched.locationUtcOffsetMins = Math.round(d.utc_offset_seconds / 60);
                    if (d.timezone_abbreviation !== undefined && d.timezone_abbreviation !== null)
                        patched.locationTimezoneAbbrev = "" + d.timezone_abbreviation;
                    r.weatherDataStaged = patched;
                }
            } catch (e) {}
        };
        req.send();
    }
}
