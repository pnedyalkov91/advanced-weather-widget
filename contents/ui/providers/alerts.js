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
 * alerts.js — Centralized weather alerts fetcher
 *
 * Strategy:
 *   1. MeteoAlarm Atom feeds (38 European countries, no auth)
 *   2. Fallback → MET Norway MetAlerts (lat/lon based, Norway only)
 *
 * Non-pragma JS — accesses config via service properties.
 */

// ISO 3166-1 alpha-2 → MeteoAlarm feed slug
var _isoToSlug = {
    "AD": "andorra",
    "AT": "austria",
    "BA": "bosnia-herzegovina",
    "BE": "belgium",
    "BG": "bulgaria",
    "CH": "switzerland",
    "CY": "cyprus",
    "CZ": "czechia",
    "DE": "germany",
    "DK": "denmark",
    "EE": "estonia",
    "ES": "spain",
    "FI": "finland",
    "FR": "france",
    "GB": "united-kingdom",
    "GR": "greece",
    "HR": "croatia",
    "HU": "hungary",
    "IE": "ireland",
    "IL": "israel",
    "IS": "iceland",
    "IT": "italy",
    "LT": "lithuania",
    "LU": "luxembourg",
    "LV": "latvia",
    "MD": "moldova",
    "ME": "montenegro",
    "MK": "republic-of-north-macedonia",
    "MT": "malta",
    "NL": "netherlands",
    "NO": "norway",
    "PL": "poland",
    "PT": "portugal",
    "RO": "romania",
    "RS": "serbia",
    "SE": "sweden",
    "SI": "slovenia",
    "SK": "slovakia",
    "UA": "ukraine"
};

/**
 * Main entry point — called from WeatherService.refreshNow().
 * Tries NWS for US, MeteoAlarm for Europe, falls back to met.no MetAlerts.
 */
function fetchAlerts(service) {
    var r = service.weatherRoot;
    var isoCode = (service.countryCode || "").toUpperCase();

    // US locations: use NWS alerts API
    if (isoCode === "US") {
        console.log("[Alerts] countryCode=US → fetching NWS alerts");
        _fetchNws(service);
        return;
    }

    // If countryCode is not set, try a quick bounding-box check for the US
    // (CONUS + Alaska + Hawaii) to avoid the Nominatim round-trip.
    if (isoCode.length === 0 && _looksLikeUS(service.latitude, service.longitude)) {
        console.log("[Alerts] no countryCode but coordinates look like US → fetching NWS alerts");
        _fetchNws(service);
        return;
    }

    var slug = _isoToSlug[isoCode];

    if (slug) {
        console.log("[Alerts] countryCode=" + isoCode + " → fetching MeteoAlarm (" + slug + ")");
        _fetchMeteoAlarm(service, slug, function (ok) {
            if (!ok) {
                _fetchMetNo(service);
            }
        });
    } else if (isoCode.length > 0) {
        console.log("[Alerts] countryCode=" + isoCode + " → not supported by MeteoAlarm or NWS");
    } else {
        // Country code not set — try reverse-geocoding to determine it
        console.log("[Alerts] no countryCode → reverse-geocoding via Nominatim");
        _resolveCountryThenFetch(service);
    }
}

/**
 * Quick bounding-box check: does lat/lon fall inside CONUS, Alaska, or Hawaii?
 * Used as a fast fallback when countryCode is not configured.
 */
function _looksLikeUS(lat, lon) {
    lat = parseFloat(lat);  lon = parseFloat(lon);
    if (isNaN(lat) || isNaN(lon)) return false;
    // CONUS: lat 24–50, lon –125 to –66
    if (lat >= 24 && lat <= 50 && lon >= -125 && lon <= -66) return true;
    // Alaska: lat 51–72, lon –180 to –129
    if (lat >= 51 && lat <= 72 && lon >= -180 && lon <= -129) return true;
    // Hawaii: lat 18–23, lon –161 to –154
    if (lat >= 18 && lat <= 23 && lon >= -161 && lon <= -154) return true;
    return false;
}

// ── Reverse-geocode fallback for missing countryCode ──────────────────

function _resolveCountryThenFetch(service) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;  // FIX: r was undefined here, causing silent failure
    var lat = service.latitude;
    var lon = service.longitude;
    if (!lat || !lon) return;

    // Use zoom=10 so we also get county/state — avoids a second Nominatim
    // call (and possible rate-limit) inside _fetchMeteoAlarm.
    // Use accept-language=en for Latin-script admin names.
    var req = new XMLHttpRequest();
    req.open("GET",
        "https://nominatim.openstreetmap.org/reverse?lat="
        + encodeURIComponent(lat)
        + "&lon=" + encodeURIComponent(lon)
        + "&format=json&zoom=10&addressdetails=1"
        + "&accept-language=en");
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        var isoCode = "";
        var adminTerms = [];
        if (req.status === 200) {
            try {
                var data = JSON.parse(req.responseText);
                if (data.address) {
                    if (data.address.country_code)
                        isoCode = data.address.country_code.toUpperCase();
                    // Extract admin terms right here so we can reuse them
                    var keys = ["city", "town", "village", "municipality",
                                "county", "state", "state_district",
                                "province", "region"];
                    keys.forEach(function (k) {
                        if (data.address[k])
                            adminTerms.push(data.address[k].toLowerCase());
                    });
                }
            } catch (e) { /* ignore */ }
        }
        var slug = _isoToSlug[isoCode];
        if (isoCode === "US") {
            console.log("[Alerts] Nominatim resolved US → fetching NWS alerts");
            _fetchNws(service);
        } else if (slug) {
            console.log("[Alerts] Nominatim resolved " + isoCode + " → fetching MeteoAlarm (" + slug + ")");
            _fetchMeteoAlarm(service, slug, function (ok) {
                if (!ok)
                    _fetchMetNo(service);
            }, adminTerms);
        } else if (isoCode.length > 0) {
            console.log("[Alerts] Nominatim resolved " + isoCode + " → not supported");
        } else {
            console.warn("[Alerts] Nominatim reverse-geocode failed or returned no country");
        }
    };
    req.send();
}

// ── MeteoAlarm Atom feeds ─────────────────────────────────────────────

function _fetchMeteoAlarm(service, slug, callback, prefetchedTerms) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var feedUrl = "https://feeds.meteoalarm.org/api/v1/warnings/feeds-" + slug;

    // Run feed fetch and local-name lookup in parallel
    var state = { feedData: undefined, localTerms: undefined };

    function _tryComplete() {
        if (state.feedData === undefined || state.localTerms === undefined)
            return;
        // Stale generation — a newer refresh superseded us
        if (service._refreshGen !== gen) return;
        if (state.feedData === false) {
            callback(false);
            return;
        }
        try {
            var alerts = _parseMeteoAlarmAlerts(
                state.feedData, service.locationName, state.localTerms,
                service.latitude, service.longitude);
            r.weatherAlerts = alerts;
            callback(true);
        } catch (e) {
            callback(false);
        }
    }

    // 1) Fetch MeteoAlarm feed
    var req = new XMLHttpRequest();
    req.open("GET", feedUrl);
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            state.feedData = false;
        } else {
            try {
                state.feedData = JSON.parse(req.responseText);
            } catch (e) {
                state.feedData = false;
            }
        }
        _tryComplete();
    };
    req.send();

    // 2) Use pre-fetched admin terms if available (from _resolveCountryThenFetch),
    //    otherwise fetch via Nominatim.
    if (prefetchedTerms && prefetchedTerms.length > 0) {
        state.localTerms = prefetchedTerms;
        _tryComplete();
    } else {
        _getLocalAdminTerms(service, gen, service.latitude, service.longitude, function (terms) {
            state.localTerms = terms;
            _tryComplete();
        });
    }
}

function _getLocalAdminTerms(service, gen, lat, lon, callback) {
    if (!lat || !lon) { callback([]); return; }
    var req = new XMLHttpRequest();
    // Use accept-language=en so we always get Latin-script names.
    // This is essential for countries like Greece (Cyrillic/Greek script)
    // where Nominatim defaults would return non-Latin names that can't
    // match MeteoAlarm's English area descriptions.
    req.open("GET",
        "https://nominatim.openstreetmap.org/reverse?lat="
        + encodeURIComponent(lat)
        + "&lon=" + encodeURIComponent(lon)
        + "&format=json&zoom=10&addressdetails=1"
        + "&accept-language=en");
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE) return;
        if (service._refreshGen !== gen) return;
        var terms = [];
        if (req.status === 200) {
            try {
                var data = JSON.parse(req.responseText);
                if (data.address) {
                    var keys = ["city", "town", "village", "municipality",
                                "county", "state", "state_district",
                                "province", "region"];
                    keys.forEach(function (k) {
                        if (data.address[k])
                            terms.push(data.address[k].toLowerCase());
                    });
                }
            } catch (e) { /* ignore */ }
        }
        callback(terms);
    };
    req.send();
}

function _parseMeteoAlarmAlerts(data, locationName, localTerms, lat, lon) {
    var now = new Date();
    var alerts = [];
    var userLat = parseFloat(lat);
    var userLon = parseFloat(lon);
    var hasCoords = !isNaN(userLat) && !isNaN(userLon);
    // API returns { warnings: [...] }, not a plain array
    var entries = (data && Array.isArray(data.warnings)) ? data.warnings
                : Array.isArray(data) ? data : [];
    if (!entries.length)
        return alerts;

    // Build search terms from locationName + Nominatim local admin names
    var searchTerms = [];
    var locParts = (locationName || "").split(",");
    locParts.forEach(function (p) {
        var t = p.trim().toLowerCase();
        if (t.length > 2) searchTerms.push(t);
    });
    if (localTerms && localTerms.length > 0) {
        localTerms.forEach(function (t) {
            if (t.length > 2 && searchTerms.indexOf(t) < 0)
                searchTerms.push(t);
        });
    }

    entries.forEach(function (entry) {
        if (!entry.alert || !entry.alert.info)
            return;
        // Only "Actual" alerts — skip "Test", "Exercise", etc.
        if (entry.alert.status && entry.alert.status !== "Actual")
            return;
        var infos = entry.alert.info;
        // Pick local-language info block for display text
        var localInfo = _pickLocalInfo(infos);
        if (!localInfo)
            return;

        // For filtering & metadata, merge data from ALL info blocks
        // (area polygons, parameters, responseType, expires may only
        //  exist in certain language variants of the same alert)
        var allAreas = [];
        var rtypes = [];
        var expires = "";
        var levelName = "", color = "", eventType = "", levelNum = 0;
        var awarenessTypeNum = 0;

        infos.forEach(function (inf) {
            // Collect areas from every info block
            if (inf.area) {
                inf.area.forEach(function (a) { allAreas.push(a); });
            }
            // Merge responseType
            var rt = Array.isArray(inf.responseType)
                ? inf.responseType
                : (inf.responseType ? [inf.responseType] : []);
            rt.forEach(function (r) {
                if (rtypes.indexOf(r) < 0) rtypes.push(r);
            });
            // Keep latest expires
            if (inf.expires && (!expires || inf.expires > expires))
                expires = inf.expires;
            // Extract awareness_level and awareness_type from parameters
            if (inf.parameter) {
                inf.parameter.forEach(function (p) {
                    if (p.valueName === "awareness_level" && p.value && !color) {
                        var parts = p.value.split(";");
                        if (parts.length >= 1) levelNum = parseInt(parts[0].trim(), 10) || 0;
                        if (parts.length >= 3) levelName = parts[2].trim();
                        if (parts.length >= 2) color = parts[1].trim().toLowerCase();
                    }
                    if (p.valueName === "awareness_type" && p.value && !eventType) {
                        var tp = p.value.split(";");
                        if (tp.length >= 1) awarenessTypeNum = parseInt(tp[0].trim(), 10) || 0;
                        if (tp.length >= 2) eventType = tp[1].trim();
                    }
                });
            }
        });

        // Skip "AllClear" cancellation notices
        if (rtypes.indexOf("AllClear") >= 0)
            return;

        // Use localInfo expires if available, otherwise merged expires
        var alertExpires = localInfo.expires || expires;

        // Skip expired alerts
        if (alertExpires) {
            var exp = new Date(alertExpires);
            if (exp < now)
                return;
        }

        // Skip green/Minor (level 1) — these are "No Special Awareness Required"
        if (levelNum <= 1 && color === "green")
            return;

        // Area filtering — use merged areas from ALL info blocks
        var matchedAreas = [];
        var canFilter = hasCoords || searchTerms.length > 0;

        if (canFilter && allAreas.length > 0) {
            var _seenArea = {};
            allAreas.forEach(function (a) {
                var ad = a.areaDesc || "";
                if (_seenArea[ad]) return;  // deduplicate across info blocks
                // 1) Coordinate-based match (polygon / circle)
                if (hasCoords && _areaContainsPoint(a, userLat, userLon)) {
                    _seenArea[ad] = true;
                    matchedAreas.push(ad);
                    return;
                }
                // 2) Fallback — fuzzy text match on areaDesc
                if (ad && searchTerms.length > 0) {
                    var desc = ad.toLowerCase();
                    for (var i = 0; i < searchTerms.length; i++) {
                        if (_textMatch(desc, searchTerms[i])) {
                            _seenArea[ad] = true;
                            matchedAreas.push(ad);
                            return;
                        }
                    }
                }
            });
            if (matchedAreas.length === 0)
                return;  // no area match — skip this alert
        }

        // Use the local-language event name as display text
        var displayName = localInfo.event || eventType || localInfo.headline || "";

        // FIX 1: Use normalized rtypes array (safe to call .filter on)
        var action = rtypes
            .filter(function (r) { return r !== "AllClear"; })
            .join(", ");

        alerts.push({
            headline: localInfo.headline || localInfo.event || "",
            displayName: displayName,
            severity: localInfo.severity || "",
            description: localInfo.description || "",
            event: localInfo.event || eventType || "",
            area: matchedAreas.join(", "),
            color: color,
            awarenessType: awarenessTypeNum,
            onset: localInfo.onset || localInfo.effective || "",
            effective: localInfo.effective || localInfo.onset || "",
            expires: alertExpires || "",
            instruction: localInfo.instruction || "",
            web: localInfo.web || "",
            source: "MeteoAlarm",
            action: action,
            senderName: localInfo.senderName || ""
        });
    });

    // Deduplicate by displayName + onset — same alert type at different time windows
    // must be kept as separate entries (e.g. two "Moderate for Wind" on different days)
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

/**
 * Pick the local-language info block (non-English) from the CAP alert.
 * Falls back to the first info block if no local language is found.
 */
function _pickLocalInfo(infos) {
    var local = null;
    var english = null;
    for (var i = 0; i < infos.length; ++i) {
        var lang = (infos[i].language || "").toLowerCase();
        if (lang === "en-gb" || lang === "en" || lang.indexOf("en") === 0) {
            if (!english) english = infos[i];
        } else if (lang.length > 0) {
            if (!local) local = infos[i];
        }
    }
    // Prefer local language; fall back to English; finally first info
    return local || english || (infos.length > 0 ? infos[0] : null);
}

/**
 * Strip combining diacritical marks so accented characters compare equal
 * to their plain-ASCII equivalents (e.g. "Isère" → "isere").
 */
function _stripDiacritics(s) {
    return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

/**
 * Fuzzy text match — handles English ↔ local name variants.
 * Returns true if:
 *   1. needle is a substring of haystack (or vice-versa), OR
 *   2. any word pair shares a common prefix ≥ 4 chars
 *      (e.g. "Attiki" ↔ "Attica", "Makedonia" ↔ "Macedonia")
 * All comparisons are accent-insensitive.
 */
function _textMatch(haystack, needle) {
    // Normalise: strip accents so "isère" matches "isere"
    var h = _stripDiacritics(haystack);
    var n = _stripDiacritics(needle);
    if (h.indexOf(n) >= 0 || n.indexOf(h) >= 0)
        return true;
    if (n.length < 4) return false;
    // Word-by-word comparison — handles multi-word names like
    // "Central Macedonia" vs "Central Makedonia" and
    // transliteration differences like "Attiki" vs "Attica".
    var hWords = h.split(/[\s,&]+/);
    var nWords = n.split(/[\s,&]+/);
    for (var i = 0; i < hWords.length; i++) {
        var hw = hWords[i];
        if (hw.length < 4) continue;
        for (var j = 0; j < nWords.length; j++) {
            var nw = nWords[j];
            var minLen = Math.min(hw.length, nw.length);
            if (minLen < 4) continue;
            var p = 0;
            while (p < minLen && hw.charAt(p) === nw.charAt(p)) p++;
            if (p >= 4) return true;
        }
    }
    return false;
}

// ── Coordinate-based area matching (CAP polygon / circle) ─────────────

/**
 * Check whether the user's lat/lon falls inside any polygon or circle
 * defined in a CAP area element.
 */
function _areaContainsPoint(area, lat, lon) {
    // Check polygon(s)
    if (area.polygon) {
        var polys = Array.isArray(area.polygon) ? area.polygon : [area.polygon];
        for (var i = 0; i < polys.length; i++) {
            var pts = _parseCapPolygon(polys[i]);
            if (pts.length >= 3 && _pointInPolygon(lat, lon, pts))
                return true;
        }
    }
    // Check circle(s)  — CAP format: "lat,lon radius_km"
    if (area.circle) {
        var circles = Array.isArray(area.circle) ? area.circle : [area.circle];
        for (var j = 0; j < circles.length; j++) {
            if (_pointInCircle(lat, lon, circles[j]))
                return true;
        }
    }
    return false;
}

/**
 * Parse a CAP polygon string "lat,lon lat,lon ..." into [[lat,lon], ...].
 */
function _parseCapPolygon(polyStr) {
    var points = [];
    var pairs = polyStr.trim().split(/\s+/);
    for (var i = 0; i < pairs.length; i++) {
        var parts = pairs[i].split(",");
        if (parts.length >= 2) {
            var lat = parseFloat(parts[0]);
            var lon = parseFloat(parts[1]);
            if (!isNaN(lat) && !isNaN(lon))
                points.push([lat, lon]);
        }
    }
    return points;
}

/**
 * Ray-casting point-in-polygon test.
 */
function _pointInPolygon(lat, lon, polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        var yi = polygon[i][0], xi = polygon[i][1];
        var yj = polygon[j][0], xj = polygon[j][1];
        if (((yi > lat) !== (yj > lat)) &&
            (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
            inside = !inside;
        }
    }
    return inside;
}

/**
 * Check whether a point is inside a CAP circle ("lat,lon radius_km").
 */
function _pointInCircle(lat, lon, circleStr) {
    var parts = circleStr.trim().split(/\s+/);
    if (parts.length < 2) return false;
    var center = parts[0].split(",");
    if (center.length < 2) return false;
    var cLat = parseFloat(center[0]);
    var cLon = parseFloat(center[1]);
    var radius = parseFloat(parts[1]);
    if (isNaN(cLat) || isNaN(cLon) || isNaN(radius)) return false;
    return _haversineKm(lat, lon, cLat, cLon) <= radius;
}

/**
 * Haversine distance in km between two lat/lon points.
 */
function _haversineKm(lat1, lon1, lat2, lon2) {
    var R = 6371;
    var dLat = (lat2 - lat1) * Math.PI / 180;
    var dLon = (lon2 - lon1) * Math.PI / 180;
    var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ── MET Norway MetAlerts ──────────────────────────────────────────────

function _fetchMetNo(service) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var url = "https://api.met.no/weatherapi/metalerts/2.0/current.json"
        + "?lat=" + service.latitude
        + "&lon=" + service.longitude
        + "&lang=en";
    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            // Both sources failed — leave alerts as-is (already [])
            return;
        }
        try {
            var data = JSON.parse(req.responseText);
            var alerts = _parseMetNoAlerts(data);
            r.weatherAlerts = alerts;
        } catch (e) {
            // Parse error — leave alerts empty
        }
    };
    req.send();
}

function _parseMetNoAlerts(data) {
    var now = new Date();
    var alerts = [];
    if (!data.features || !Array.isArray(data.features))
        return alerts;

    data.features.forEach(function (f) {
        var p = f.properties;
        if (!p)
            return;

        // Only show "Actual" status alerts (skip "Test")
        if (p.status && p.status !== "Actual")
            return;

        // Skip expired alerts
        if (f.when && f.when.interval && f.when.interval.length >= 2) {
            var end = new Date(f.when.interval[1]);
            if (end < now)
                return;
        }

        var color = "";
        var levelName = "";
        if (p.riskMatrixColor)
            color = p.riskMatrixColor.toLowerCase();
        if (p.awareness_level) {
            var parts = p.awareness_level.split(";");
            if (parts.length >= 2 && !color)
                color = parts[1].trim().toLowerCase();
            if (parts.length >= 3)
                levelName = parts[2].trim();
        }

        var displayName = "";
        if (levelName && p.event)
            displayName = levelName + " for " + p.event;
        else
            displayName = p.title || p.eventAwarenessName || "";

        alerts.push({
            headline: p.title || p.eventAwarenessName || "",
            displayName: displayName,
            severity: p.severity || "",
            description: p.description || "",
            event: p.event || "",
            area: p.area || "",
            color: color,
            onset: (f.when && f.when.interval) ? f.when.interval[0] : "",
            effective: (f.when && f.when.interval) ? f.when.interval[0] : "",
            expires: (f.when && f.when.interval && f.when.interval.length >= 2)
                ? f.when.interval[1] : "",
            instruction: p.instruction || "",
            web: p.web || "",
            source: "MET Norway",
            action: p.instruction || "",
            senderName: "MET Norway"
        });
    });

    return alerts;
}

// ── NWS (National Weather Service) — US alerts ───────────────────────

/**
 * Fetches weather alerts from the NWS API (api.weather.gov) for US locations.
 * Uses the /alerts/active endpoint with lat/lon point query.
 * Docs: https://www.weather.gov/documentation/services-web-api
 */
function _fetchNws(service) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var lat = parseFloat(service.latitude);
    var lon = parseFloat(service.longitude);
    if (isNaN(lat) || isNaN(lon)) {
        console.warn("[Alerts/NWS] invalid coordinates:", service.latitude, service.longitude);
        return;
    }

    // Round to 4 decimal places (NWS best practice)
    var latStr = lat.toFixed(4);
    var lonStr = lon.toFixed(4);

    // NWS alerts API — active alerts for a geographic point
    var url = "https://api.weather.gov/alerts/active?point="
        + latStr + "," + lonStr
        + "&status=actual&message_type=alert,update";

    console.log("[Alerts/NWS] fetching:", url);

    var req = new XMLHttpRequest();
    req.open("GET", url);
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
    req.setRequestHeader("Accept", "application/geo+json");
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            console.warn("[Alerts/NWS] HTTP", req.status, "for", url);
            return;
        }
        try {
            var data = JSON.parse(req.responseText);
            var alerts = _parseNwsAlerts(data);
            console.log("[Alerts/NWS] parsed", alerts.length, "active alerts");
            if (alerts.length > 0) {
                r.weatherAlerts = alerts;
            }
        } catch (e) {
            console.warn("[Alerts/NWS] parse error:", e);
        }
    };
    req.send();
}

function _parseNwsAlerts(data) {
    var now = new Date();
    var alerts = [];
    if (!data.features || !Array.isArray(data.features))
        return alerts;

    data.features.forEach(function (f) {
        var p = f.properties;
        if (!p) return;

        // Skip expired
        if (p.expires) {
            var exp = new Date(p.expires);
            if (exp < now) return;
        }

        // Map NWS severity to a MeteoAlarm-compatible color
        var color = "";
        var severity = (p.severity || "").toLowerCase();
        if (severity === "extreme")  color = "red";
        else if (severity === "severe") color = "red";
        else if (severity === "moderate") color = "orange";
        else if (severity === "minor") color = "yellow";

        // Map NWS certainty/urgency for awareness type
        var awarenessType = 0;
        var event = (p.event || "").toLowerCase();
        if (event.indexOf("tornado") >= 0) awarenessType = 1;
        else if (event.indexOf("wind") >= 0) awarenessType = 1;
        else if (event.indexOf("snow") >= 0 || event.indexOf("ice") >= 0 || event.indexOf("blizzard") >= 0) awarenessType = 2;
        else if (event.indexOf("thunder") >= 0) awarenessType = 3;
        else if (event.indexOf("fog") >= 0) awarenessType = 4;
        else if (event.indexOf("heat") >= 0) awarenessType = 5;
        else if (event.indexOf("cold") >= 0 || event.indexOf("freeze") >= 0 || event.indexOf("frost") >= 0 || event.indexOf("chill") >= 0) awarenessType = 6;
        else if (event.indexOf("coastal") >= 0 || event.indexOf("tsunami") >= 0 || event.indexOf("storm surge") >= 0) awarenessType = 7;
        else if (event.indexOf("fire") >= 0) awarenessType = 8;
        else if (event.indexOf("avalanche") >= 0) awarenessType = 9;
        else if (event.indexOf("rain") >= 0) awarenessType = 10;
        else if (event.indexOf("flood") >= 0) awarenessType = 11;

        var areas = "";
        if (p.areaDesc) areas = p.areaDesc;

        alerts.push({
            headline: p.headline || p.event || "",
            displayName: p.event || p.headline || "",
            severity: p.severity || "",
            description: p.description || "",
            event: p.event || "",
            area: areas,
            color: color,
            awarenessType: awarenessType,
            onset: p.onset || p.effective || "",
            effective: p.effective || "",
            expires: p.expires || "",
            instruction: p.instruction || "",
            web: (p.id && p.id.indexOf("http") === 0) ? p.id : "",
            source: "NWS",
            action: p.response || "",
            senderName: p.senderName || "National Weather Service"
        });
    });

    // Deduplicate by event + onset
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