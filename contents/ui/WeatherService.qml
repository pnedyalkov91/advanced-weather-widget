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
        r.weatherAlerts = [];  // reset before parallel fetch

        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var chain = (provider === "adaptive") ? ["openMeteo", "openWeather", "weatherApi", "metno"] : [provider];

        _tryProvider(chain, 0);

        // Fetch alerts independently (MeteoAlarm → met.no fallback)
        AlertsJS.fetchAlerts(service);
        // Fetch NOAA space weather independently (no location needed)
        SpaceWeatherJS.fetchSpaceWeather(service);
    }

    /** Hourly data fetch for a specific date string (yyyy-MM-dd) */
    function fetchHourlyForDate(dateStr) {
        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        var ap = (provider === "adaptive") ? "openMeteo" : provider;

        if (ap === "openMeteo") {
            OpenMeteoJS.fetchHourly(service, dateStr);
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
        weatherRoot.hourlyData = [];
    }

    // ── Private: provider chain ───────────────────────────────────────────

    property var _failed: []

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
        return "Open-Meteo";
    }

    function _tryProvider(chain, idx) {
        if (idx >= chain.length) {
            weatherRoot.loading = false;
            var names = chain.map(function (p) {
                return _providerLabel(p);
            });
            weatherRoot.updateText = i18n("Failed: %1", names.join(", "));
            _failed = [];
            return;
        }
        var p = chain[idx];
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
        var r = weatherRoot;
        var tz = (Plasmoid.configuration.timezone || "").trim();
        var today = Qt.formatDate(new Date(), "yyyy-MM-dd");
        var url = "https://api.open-meteo.com/v1/forecast" + "?latitude=" + Plasmoid.configuration.latitude + "&longitude=" + Plasmoid.configuration.longitude + "&timezone=" + encodeURIComponent(tz.length > 0 ? tz : "auto") + "&daily=sunrise,sunset" + "&start_date=" + today + "&end_date=" + today;
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
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
