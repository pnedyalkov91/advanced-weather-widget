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
 * bbcWeather.js — BBC Weather current + hourly fetcher
 *
 * Non-pragma JS — accesses config via service properties.
 * Qt global is available; Plasmoid/i18n/Locale are NOT (use service instead).
 * W (weather.js) is passed as a parameter by the caller.
 *
 * BBC Weather has no public API key requirement. It is keyed by a numeric
 * location id (not lat/lon), so we first resolve the nearest location id via
 * the BBC locator service, then fetch the aggregated forecast for that id.
 * The resolved id is cached on the service so subsequent refreshes for the
 * same location skip the lookup.
 *
 * Endpoints (same ones the KDE weather ion uses):
 *   Locator:  https://locator-service.api.bbci.co.uk/locations?...&latitude=&longitude=
 *   Forecast: https://weather-broker-cdn.api.bbci.co.uk/en/forecast/aggregated/<id>
 */

var _LOCATOR_KEY = "AGbFAKx58hyjQScCXIYrxuEwJh2W2cmv";

/**
 * BBC visibility is a text band ("Very Poor" … "Excellent"). Map it to an
 * approximate distance in km so the UI's numeric visibility field has a value.
 */
function _visibilityKm(text) {
    switch ((text || "").toLowerCase()) {
        case "very poor": return 1;
        case "poor":      return 4;
        case "moderate":  return 10;
        case "good":      return 20;
        case "very good": return 40;
        case "excellent": return 70;
        default:          return NaN;
    }
}

/** "HH:mm" (BBC local time) for a report's timeslot. */
function _slotTime(rep) {
    return (rep.timeslot && rep.timeslot.length >= 5) ? rep.timeslot.substr(0, 5) : "--";
}

/**
 * BBC gives pressure and visibility only on the hourly reports, not on the
 * day summary. This aggregates a single day's reports (matched by localDate)
 * into a representative { pressureHpa, visibilityKm } for the daily row:
 * pressure is averaged; visibility takes the day's worst (minimum) band, which
 * is the more useful figure for a daily glance.
 */
function _dailyDerived(fcs, dateStr) {
    var pSum = 0, pN = 0, visKm = NaN;
    fcs.forEach(function (fc) {
        var reps = (fc.detailed && fc.detailed.reports) ? fc.detailed.reports : [];
        reps.forEach(function (rep) {
            if (rep.localDate !== dateStr) return;
            if (rep.pressure !== undefined && rep.pressure !== null) {
                pSum += rep.pressure; pN++;
            }
            var v = _visibilityKm(rep.visibility);
            if (!isNaN(v) && (isNaN(visKm) || v < visKm)) visKm = v;
        });
    });
    return {
        pressureHpa: pN > 0 ? Math.round(pSum / pN) : NaN,
        visibilityKm: visKm
    };
}

/**
 * Resolves the nearest BBC location id for the service's lat/lon, then calls
 * cb(id) on success or cb(null) on failure. Caches the result on the service
 * keyed by rounded coordinates so we don't re-resolve on every refresh.
 */
function _resolveLocationId(service, gen, cb) {
    var lat = service.latitude;
    var lon = service.longitude;
    var key = Number(lat).toFixed(3) + "," + Number(lon).toFixed(3);
    if (service._bbcLocKey === key && service._bbcLocId)
        return cb(service._bbcLocId);

    var url = "https://locator-service.api.bbci.co.uk/locations?"
        + "api_key=" + _LOCATOR_KEY
        + "&stack=aws&locale=en&filter=international"
        + "&place-types=settlement%2Cairport%2Cdistrict&order=importance"
        + "&latitude=" + encodeURIComponent(lat)
        + "&longitude=" + encodeURIComponent(lon)
        + "&format=json";
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE) return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) return cb(null);
        try {
            var d = JSON.parse(req.responseText);
            var results = d && d.response && d.response.results
                ? d.response.results.results : null;
            if (!results || results.length === 0) return cb(null);
            var id = results[0].id;
            service._bbcLocKey = key;
            service._bbcLocId = id;
            cb(id);
        } catch (e) {
            cb(null);
        }
    };
    req.send();
}

function _forecastUrl(id) {
    return "https://weather-broker-cdn.api.bbci.co.uk/en/forecast/aggregated/"
        + encodeURIComponent(id);
}

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    _resolveLocationId(service, gen, function (id) {
        if (service._refreshGen !== gen) return;
        if (!id) { service._tryProvider(chain, idx + 1); return; }
        _fetchCurrentForId(service, W, chain, idx, gen, id);
    });
}

function _fetchCurrentForId(service, W, chain, idx, gen, id) {
    var r = service.weatherRoot;
    var req = new XMLHttpRequest();
    req.open("GET", _forecastUrl(id));
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE) return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) { service._tryProvider(chain, idx + 1); return; }
        var d;
        try { d = JSON.parse(req.responseText); }
        catch (e) { service._tryProvider(chain, idx + 1); return; }

        var fcs = d.forecasts;
        if (!fcs || fcs.length === 0) { service._tryProvider(chain, idx + 1); return; }

        // Current conditions = the first hourly report of the first day.
        var today = fcs[0];
        var cur = (today.detailed && today.detailed.reports && today.detailed.reports.length > 0)
            ? today.detailed.reports[0] : null;
        var sum0 = today.summary ? today.summary.report : null;
        if (!cur && sum0) cur = sum0; // fall back to the day summary if no hourly
        if (!cur) { service._tryProvider(chain, idx + 1); return; }

        // Build the daily forecast from each day's summary.report.
        var nd = [];
        var maxD = Math.min(service.forecastDays, fcs.length);
        for (var i = 0; i < maxD; i++) {
            var s = fcs[i].summary ? fcs[i].summary.report : null;
            if (!s) continue;
            // BBC has no pressure/visibility on the day summary — derive them
            // from the day's hourly reports.
            var der = _dailyDerived(fcs, s.localDate);
            nd.push({
                day: Qt.formatDate(new Date(s.localDate), "ddd"),
                dateStr: s.localDate,
                maxC: (s.maxTempC !== undefined && s.maxTempC !== null) ? s.maxTempC : NaN,
                minC: (s.minTempC !== undefined && s.minTempC !== null) ? s.minTempC : NaN,
                code: W.bbcWeatherTypeToWmo(s.weatherType),
                precipMm: W.NOT_SUPPORTED, // BBC exposes only precip probability, not an amount
                snowCm: NaN,
                precipProb: (s.precipitationProbabilityInPercent !== undefined)
                                ? s.precipitationProbabilityInPercent : NaN,
                windKmh: (s.windSpeedKph !== undefined) ? s.windSpeedKph : NaN,
                windDir: W.compassToDegrees ? W.compassToDegrees(s.windDirection) : NaN,
                uvMax: (s.uvIndex !== undefined && s.uvIndex !== null) ? s.uvIndex : NaN,
                pressureHpa: der.pressureHpa,
                visibilityKm: der.visibilityKm
            });
        }

        var _cur = {
            temperatureC:    (cur.temperatureC !== undefined && cur.temperatureC !== null)
                                ? cur.temperatureC : cur.maxTempC,
            apparentC:       (cur.feelsLikeTemperatureC !== undefined && cur.feelsLikeTemperatureC !== null)
                                ? cur.feelsLikeTemperatureC : NaN,
            humidityPercent: (cur.humidity !== undefined) ? cur.humidity : NaN,
            pressureHpa:     (cur.pressure !== undefined) ? cur.pressure : NaN,
            windKmh:         (cur.windSpeedKph !== undefined) ? cur.windSpeedKph : NaN,
            windDirection:   W.compassToDegrees ? W.compassToDegrees(cur.windDirection) : NaN,
            // BBC has no dew point — derive it from temperature + humidity.
            dewPointC:       W.dewPoint(
                                (cur.temperatureC !== undefined && cur.temperatureC !== null)
                                    ? cur.temperatureC : cur.maxTempC,
                                (cur.humidity !== undefined) ? cur.humidity : NaN),
            visibilityKm:    _visibilityKm(cur.visibility),
            precipMmh:       W.NOT_SUPPORTED, // BBC exposes only precip probability, not an amount
            uvIndex:         (sum0 && sum0.uvIndex !== undefined) ? sum0.uvIndex : NaN,
            snowDepthCm:     NaN,
            weatherCode:     W.bbcWeatherTypeToWmo(cur.weatherType),
            isDay:           (d.isNight === true) ? 0 : (d.isNight === false ? 1
                                : W.bbcWeatherTypeIsDay(cur.weatherType)),
            locationUtcOffsetMins: 0,
            sunriseTimeText: (sum0 && sum0.sunrise) ? sum0.sunrise : "--",
            sunsetTimeText:  (sum0 && sum0.sunset)  ? sum0.sunset  : "--",
            dailyData:       nd
        };

        r.weatherDataStaged = _cur;
        r.loading = false;
        r.updateText = service._formatUpdateText("bbc");

        // BBC exposes no CAP alerts — fall back to MeteoAlarm / NWS.
        service._fetchAlertsIfNeeded();
        // Air quality is fetched in parallel from WeatherService.refreshNow().
    };
    req.send();
}

/** Parses the aggregated forecast JSON into an hourly array for `dateStr`. */
function _parseHourly(d, W, dateStr) {
    var arr = [];
    if (d.forecasts)
        d.forecasts.forEach(function (fc) {
            var reps = (fc.detailed && fc.detailed.reports) ? fc.detailed.reports : [];
            reps.forEach(function (rep) {
                if (rep.localDate !== dateStr) return;
                arr.push({
                    hour: _slotTime(rep),
                    tempC: (rep.temperatureC !== undefined) ? rep.temperatureC : NaN,
                    code: W.bbcWeatherTypeToWmo(rep.weatherType),
                    windKmh: (rep.windSpeedKph !== undefined) ? rep.windSpeedKph : NaN,
                    windDeg: W.compassToDegrees ? W.compassToDegrees(rep.windDirection) : NaN,
                    humidity: (rep.humidity !== undefined) ? rep.humidity : NaN,
                    precipProb: (rep.precipitationProbabilityInPercent !== undefined)
                                    ? rep.precipitationProbabilityInPercent : NaN,
                    precipMm: W.NOT_SUPPORTED, // BBC exposes only precip probability, not amount
                    pressureHpa: (rep.pressure !== undefined && rep.pressure !== null)
                                    ? rep.pressure : NaN,
                    visibilityKm: _visibilityKm(rep.visibility),
                    uvIndex: W.NOT_SUPPORTED   // BBC has no per-hour UV index
                });
            });
        });
    return arr;
}

function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    _resolveLocationId(service, gen, function (id) {
        if (service._refreshGen !== gen) return;
        if (!id) { r.hourlyData = []; return; }
        var req = new XMLHttpRequest();
        req.open("GET", _forecastUrl(id));
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            if (service._refreshGen !== gen) return;
            if (req.status !== 200) { r.hourlyData = []; return; }
            try { r.hourlyData = _parseHourly(JSON.parse(req.responseText), W, dateStr); }
            catch (e) { r.hourlyData = []; }
        };
        req.send();
    });
}

/**
 * Parallel-safe hourly fetch (ForecastView expand-all). Resolves the location
 * id, fetches the aggregated forecast, and hands the hourly array to `cb`
 * without touching weatherRoot.hourlyData.
 */
function fetchHourlyDirect(service, W, dateStr, cb) {
    var gen = service._refreshGen;
    _resolveLocationId(service, gen, function (id) {
        if (service._refreshGen !== gen) { cb([]); return; }
        if (!id) { cb([]); return; }
        var req = new XMLHttpRequest();
        req.open("GET", _forecastUrl(id));
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            if (req.status !== 200) { cb([]); return; }
            try { cb(_parseHourly(JSON.parse(req.responseText), W, dateStr)); }
            catch (e) { cb([]); }
        };
        req.send();
    });
}
