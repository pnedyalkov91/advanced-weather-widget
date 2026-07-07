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
 * Providers.qml — lazily-loaded weather-provider dispatcher.
 *
 * All provider .js modules are imported here instead of in WeatherService.qml
 * so they are NOT parsed/compiled during shell startup. WeatherService creates
 * this object on demand (first weather fetch, ~600 ms after the widget loads)
 * via Qt.createComponent, keeping ~3.7k lines of provider JS off the critical
 * startup path. The dispatch logic mirrors what previously lived inline in
 * WeatherService (_tryProvider / fetchHourlyForDate / _fetchAlertsIfNeeded).
 */
import QtQuick

import "js/weather.js" as W
import "providers/openMeteo.js" as OpenMeteoJS
import "providers/openWeather.js" as OpenWeatherJS
import "providers/weatherApi.js" as WeatherApiJS
import "providers/metNo.js" as MetNoJS
import "providers/bbcWeather.js" as BbcWeatherJS
import "providers/pirateWeather.js" as PirateWeatherJS
import "providers/visualCrossing.js" as VisualCrossingJS
import "providers/tomorrowIo.js" as TomorrowIoJS
import "providers/stormGlass.js" as StormGlassJS
import "providers/weatherbit.js" as WeatherbitJS
import "providers/qWeather.js" as QWeatherJS
import "providers/alerts.js" as AlertsJS
import "providers/librewxrAlerts.js" as LibreWxrAlertsJS
import "providers/fossAlerts.js" as FossAlertsJS
import "providers/spaceWeather_provider.js" as SpaceWeatherJS

QtObject {
    /** Current-weather fetch for provider `p` (mirrors the old _tryProvider tail). */
    function fetchCurrent(p, service, chain, idx) {
        switch (p) {
        case "pirateWeather":  PirateWeatherJS.fetchCurrent(service, W, chain, idx); return;
        case "visualCrossing": VisualCrossingJS.fetchCurrent(service, W, chain, idx); return;
        case "tomorrowIo":     TomorrowIoJS.fetchCurrent(service, W, chain, idx); return;
        case "stormGlass":     StormGlassJS.fetchCurrent(service, W, chain, idx); return;
        case "weatherbit":     WeatherbitJS.fetchCurrent(service, W, chain, idx); return;
        case "qWeather":       QWeatherJS.fetchCurrent(service, W, chain, idx); return;
        case "openWeather":    OpenWeatherJS.fetchCurrent(service, W, chain, idx); return;
        case "weatherApi":     WeatherApiJS.fetchCurrent(service, W, chain, idx); return;
        case "metno":          MetNoJS.fetchCurrent(service, W, chain, idx); return;
        case "bbc":            BbcWeatherJS.fetchCurrent(service, W, chain, idx); return;
        default:               OpenMeteoJS.fetchCurrent(service, chain, idx); return; // default = Open-Meteo
        }
    }

    /** Sequential hourly fetch for provider `ap`. Returns true if handled. */
    function fetchHourly(ap, service, dateStr) {
        switch (ap) {
        case "openMeteo":      OpenMeteoJS.fetchHourly(service, dateStr); return true;
        case "pirateWeather":  PirateWeatherJS.fetchHourly(service, W, dateStr); return true;
        case "openWeather":    OpenWeatherJS.fetchHourly(service, W, dateStr); return true;
        case "weatherApi":     WeatherApiJS.fetchHourly(service, W, dateStr); return true;
        case "metno":          MetNoJS.fetchHourly(service, W, dateStr); return true;
        case "bbc":            BbcWeatherJS.fetchHourly(service, W, dateStr); return true;
        case "visualCrossing": VisualCrossingJS.fetchHourly(service, W, dateStr); return true;
        case "tomorrowIo":     TomorrowIoJS.fetchHourly(service, W, dateStr); return true;
        case "stormGlass":     StormGlassJS.fetchHourly(service, W, dateStr); return true;
        case "weatherbit":     WeatherbitJS.fetchHourly(service, W, dateStr); return true;
        case "qWeather":       QWeatherJS.fetchHourly(service, W, dateStr); return true;
        default:               return false;
        }
    }

    /** Parallel-safe hourly fetch for providers that support it. Returns true
     *  if handled (result delivered via callback), false to let the caller use
     *  its inline path. Only BBC needs this (its id resolution lives in-module). */
    function fetchHourlyDirect(ap, service, dateStr, callback) {
        if (ap === "bbc") { BbcWeatherJS.fetchHourlyDirect(service, W, dateStr, callback); return true; }
        return false;
    }

    function fetchAlerts(service)         { AlertsJS.fetchAlerts(service); }
    function fetchAlertsLibreWxr(service) { LibreWxrAlertsJS.fetchAlerts(service); }
    function fetchAlertsFoss(service)      { FossAlertsJS.fetchAlerts(service); }
    function fetchSpaceWeather(service) { SpaceWeatherJS.fetchSpaceWeather(service); }
}
