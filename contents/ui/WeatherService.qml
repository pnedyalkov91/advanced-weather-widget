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
    readonly property real latitude: Plasmoid.configuration.latitude
    readonly property real longitude: Plasmoid.configuration.longitude
    readonly property string timezone: (Plasmoid.configuration.timezone || "").trim()
    readonly property int forecastDays: Plasmoid.configuration.forecastDays
    readonly property real altitude: Plasmoid.configuration.altitude
    readonly property string countryCode: (Plasmoid.configuration.countryCode || "").toUpperCase()
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
            r.temperatureC = NaN;
            r.apparentC = NaN;
            r.windKmh = NaN;
            r.windDirection = NaN;
            r.pressureHpa = NaN;
            r.humidityPercent = NaN;
            r.visibilityKm = NaN;
            r.dewPointC = NaN;
            r.precipMmh = NaN;
            r.uvIndex = NaN;
            r.airQualityIndex = NaN;
            r.airQualityLabel = "";
            r.aqiPm10 = NaN;
            r.aqiPm2_5 = NaN;
            r.aqiCo = NaN;
            r.aqiNo2 = NaN;
            r.aqiSo2 = NaN;
            r.aqiO3 = NaN;
            r.pollenData = [];
            r.spaceWeather = null;
            r.weatherAlerts = [];
            r.snowDepthCm = NaN;
            r.sunriseTimeText = "--";
            r.sunsetTimeText = "--";
            r.weatherCode = -1;
            r.isDay = -1;
            r.dailyData = [];
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
                if (d.daily && d.daily.sunrise && d.daily.sunrise.length > 0)
                    r.sunriseTimeText = Qt.formatTime(new Date(d.daily.sunrise[0]), "HH:mm");
                if (d.daily && d.daily.sunset && d.daily.sunset.length > 0)
                    r.sunsetTimeText = Qt.formatTime(new Date(d.daily.sunset[0]), "HH:mm");
            } catch (e) {}
        };
        req.send();
    }
}
