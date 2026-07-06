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
 * librewxrAlerts.js — LibreWXR weather alerts fetcher
 *
 * Fetches worldwide weather alerts from the LibreWXR API:
 *   GET {librewxrUrl}/v2/alerts?lat=..&lon=..
 * Returns a GeoJSON FeatureCollection of CAP alerts aggregated from
 * official feeds (WMO Severe Weather Information Centre, NOAA NWS, …).
 * Point containment is resolved server-side, so no client-side area
 * filtering is needed — every returned feature applies to the location.
 *
 * Feature properties: title, severity (CAP: Extreme/Severe/Moderate/
 * Minor/Unknown), time + expires (unix seconds), description,
 * regions (string array), uri.
 *
 * Non-pragma JS — accesses config via service properties.
 */

/**
 * Main entry point — called from WeatherService._fetchAlertsIfNeeded()
 * when the alerts provider is set to "librewxr".
 */
function fetchAlerts(service) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var lat = parseFloat(service.latitude);
    var lon = parseFloat(service.longitude);
    if (isNaN(lat) || isNaN(lon)) {
        console.warn("[Alerts/LibreWXR] invalid coordinates:", service.latitude, service.longitude);
        return;
    }

    var url = service.librewxrBaseUrl + "/v2/alerts?lat="
        + lat.toFixed(4) + "&lon=" + lon.toFixed(4);

    console.log("[Alerts/LibreWXR] fetching:", url);

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            console.warn("[Alerts/LibreWXR] HTTP", req.status, "for", url);
            return;
        }
        try {
            var data = JSON.parse(req.responseText);
            var alerts = _parseLibreWxrAlerts(data);
            console.log("[Alerts/LibreWXR] parsed", alerts.length, "active alerts");
            // Assign even when empty — the server already filtered by point,
            // so an empty result genuinely means "no active alerts here" and
            // must clear any previously shown alert.
            r.weatherAlerts = alerts;
        } catch (e) {
            console.warn("[Alerts/LibreWXR] parse error:", e);
        }
    };
    req.send();
}

function _parseLibreWxrAlerts(data) {
    var now = new Date();
    var alerts = [];
    if (!data || !data.features || !Array.isArray(data.features))
        return alerts;

    data.features.forEach(function (f) {
        var p = f.properties;
        if (!p || !p.title) return;

        var onset = _isoFromUnix(p.time);
        var expires = _isoFromUnix(p.expires);

        // Skip expired alerts
        if (expires && new Date(expires) < now)
            return;

        // Map CAP severity to a MeteoAlarm-compatible color
        var color = "";
        var severity = (p.severity || "").toLowerCase();
        if (severity === "extreme")  color = "red";
        else if (severity === "severe") color = "red";
        else if (severity === "moderate") color = "orange";
        else if (severity === "minor") color = "yellow";

        // Derive a MeteoAlarm-style awareness type from the alert text so
        // per-type notification settings and icons keep working (keyword
        // mapping like the NWS parser, but ordered specific → generic:
        // unlike NWS event names, this text includes the full description,
        // where a thunderstorm alert also mentions "wind gusts" and a flood
        // alert mentions "rain". Non-English feeds fall back to 0 = generic,
        // which is always allowed).
        var awarenessType = 0;
        var text = ((p.title || "") + " " + (p.description || "")).toLowerCase();
        if (text.indexOf("tornado") >= 0) awarenessType = 1;
        else if (text.indexOf("thunder") >= 0) awarenessType = 3;
        else if (text.indexOf("blizzard") >= 0 || text.indexOf("snow") >= 0 || text.indexOf("ice") >= 0) awarenessType = 2;
        else if (text.indexOf("avalanche") >= 0) awarenessType = 9;
        else if (text.indexOf("coastal") >= 0 || text.indexOf("tsunami") >= 0 || text.indexOf("storm surge") >= 0) awarenessType = 7;
        else if (text.indexOf("fire") >= 0) awarenessType = 8;
        else if (text.indexOf("fog") >= 0) awarenessType = 4;
        else if (text.indexOf("heat") >= 0) awarenessType = 5;
        else if (text.indexOf("cold") >= 0 || text.indexOf("freeze") >= 0 || text.indexOf("frost") >= 0 || text.indexOf("chill") >= 0) awarenessType = 6;
        else if (text.indexOf("flood") >= 0) awarenessType = 11;
        else if (text.indexOf("rain") >= 0) awarenessType = 10;
        else if (text.indexOf("wind") >= 0) awarenessType = 1;

        var area = Array.isArray(p.regions) ? p.regions.join(", ") : "";

        alerts.push({
            headline: p.title,
            displayName: p.title,
            severity: p.severity || "",
            description: p.description || "",
            event: p.title,
            area: area,
            color: color,
            awarenessType: awarenessType,
            onset: onset,
            effective: onset,
            expires: expires,
            instruction: "",
            web: p.uri || "",
            source: "LibreWXR",
            action: "",
            senderName: "LibreWXR"
        });
    });

    // Deduplicate by title + onset (same convention as the other parsers)
    var seen = {};
    var unique = [];
    alerts.forEach(function (a) {
        var key = (a.displayName || a.headline) + "|" + (a.onset || a.effective || "");
        if (!seen[key]) {
            seen[key] = true;
            unique.push(a);
        }
    });
    return unique;
}

/** Converts a unix-seconds timestamp to an ISO 8601 string ("" if unset). */
function _isoFromUnix(t) {
    var n = parseInt(t, 10);
    if (isNaN(n) || n <= 0) return "";
    return new Date(n * 1000).toISOString();
}
