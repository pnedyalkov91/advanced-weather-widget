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
 * fossAlerts.js — FOSS Public Alert Server weather-alerts fetcher
 *
 * Fetches worldwide severe-weather warnings from KDE's FOSS Public Alert
 * Server (https://alerts.kde.org, self-hostable):
 *
 *   1. GET {base}/alert/area?min_lat=..&max_lat=..&min_lon=..&max_lon=..
 *        → JSON array of alert UUID strings whose area intersects the bbox.
 *   2. GET {base}/alert/{UUID}
 *        → a single CAP 1.2 XML document (301-redirects to a static .xml
 *          file; XMLHttpRequest follows the redirect transparently).
 *
 * The server does point-in-bbox filtering only, so we still run a
 * client-side point-in-polygon / point-in-circle test on each CAP <area>
 * to keep only alerts that actually contain the user's coordinates —
 * falling back to "keep it" when an alert carries no geometry.
 *
 * The CAP payload is the same MeteoAlarm-style dialect that alerts.js
 * already parses (multiple <info> blocks, awareness_type / awareness_level
 * parameters, <polygon> / <circle> areas), so the produced alert objects
 * match the exact shape the rest of the widget expects:
 *   { headline, displayName, severity, description, event, area, color,
 *     awarenessType, onset, effective, expires, instruction, web,
 *     source, action, senderName }
 *
 * Non-pragma JS — accesses config via service properties.
 */

// Small bounding box (± ~0.05° ≈ 5.5 km) around the point so the area query
// reliably catches alerts whose polygons contain the location without pulling
// in a whole country's worth of unrelated warnings.
var _BBOX_PAD_DEG = 0.05;

/**
 * Main entry point — called from WeatherService._fetchAlertsIfNeeded()
 * when the alerts provider is set to "foss".
 */
function fetchAlerts(service) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var lat = parseFloat(service.latitude);
    var lon = parseFloat(service.longitude);
    if (isNaN(lat) || isNaN(lon)) {
        console.warn("[Alerts/FOSS] invalid coordinates:", service.latitude, service.longitude);
        return;
    }

    var base = service.fossBaseUrl;
    var minLat = (lat - _BBOX_PAD_DEG).toFixed(4);
    var maxLat = (lat + _BBOX_PAD_DEG).toFixed(4);
    var minLon = (lon - _BBOX_PAD_DEG).toFixed(4);
    var maxLon = (lon + _BBOX_PAD_DEG).toFixed(4);

    var areaUrl = base + "/alert/area?min_lat=" + minLat + "&max_lat=" + maxLat
        + "&min_lon=" + minLon + "&max_lon=" + maxLon;

    console.log("[Alerts/FOSS] fetching area:", areaUrl);

    var req = new XMLHttpRequest();
    req.open("GET", areaUrl);
    req.setRequestHeader("User-Agent",
        "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
    req.setRequestHeader("Accept", "application/json");
    req.onreadystatechange = function () {
        if (req.readyState !== XMLHttpRequest.DONE)
            return;
        if (service._refreshGen !== gen) return;
        if (req.status !== 200) {
            console.warn("[Alerts/FOSS] HTTP", req.status, "for", areaUrl);
            return;
        }
        var ids;
        try {
            ids = JSON.parse(req.responseText);
        } catch (e) {
            console.warn("[Alerts/FOSS] area parse error:", e);
            return;
        }
        if (!Array.isArray(ids)) {
            console.warn("[Alerts/FOSS] area response is not an array");
            return;
        }
        if (ids.length === 0) {
            // No alerts intersect the bbox → genuinely nothing here.
            // Clear any previously shown alert (server already filtered).
            console.log("[Alerts/FOSS] no alerts in area");
            r.weatherAlerts = [];
            return;
        }
        _fetchAlertsByIds(service, gen, base, ids);
    };
    req.send();
}

/**
 * Fetches each CAP alert document by UUID in parallel, parses it, filters
 * by point containment, then assigns the aggregated result to weatherAlerts
 * once every request has settled.
 */
function _fetchAlertsByIds(service, gen, base, ids) {
    var r = service.weatherRoot;
    var lat = parseFloat(service.latitude);
    var lon = parseFloat(service.longitude);

    // Cap the number of individual fetches to avoid hammering the server for
    // a location that happens to sit in a very busy bbox.
    var MAX = 25;
    if (ids.length > MAX)
        ids = ids.slice(0, MAX);

    var pending = ids.length;
    var collected = [];

    function _settle() {
        pending--;
        if (pending > 0) return;
        if (service._refreshGen !== gen) return;

        // Deduplicate by displayName + onset (same convention as alerts.js)
        var seen = {};
        var unique = [];
        collected.forEach(function (a) {
            var key = (a.displayName || a.headline) + "|" + (a.onset || a.effective || "");
            if (!seen[key]) {
                seen[key] = true;
                unique.push(a);
            }
        });
        console.log("[Alerts/FOSS] parsed", unique.length, "active alert(s)");
        r.weatherAlerts = unique;
    }

    ids.forEach(function (id) {
        if (typeof id !== "string" || id.length === 0) { _settle(); return; }
        var url = base + "/alert/" + encodeURIComponent(id);
        var req = new XMLHttpRequest();
        req.open("GET", url);
        req.setRequestHeader("User-Agent",
            "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (service._refreshGen !== gen) return;
            if (req.status === 200) {
                try {
                    var doc = req.responseXML;
                    var parsed = doc
                        ? _parseCapDocument(doc, lat, lon)
                        : _parseCapText(req.responseText, lat, lon);
                    parsed.forEach(function (a) { collected.push(a); });
                } catch (e) {
                    console.warn("[Alerts/FOSS] alert parse error for", id, ":", e);
                }
            } else {
                console.warn("[Alerts/FOSS] HTTP", req.status, "for", url);
            }
            _settle();
        };
        req.send();
    });
}

// ── CAP XML parsing ───────────────────────────────────────────────────

/**
 * Parse a CAP <alert> DOM document into zero or more alert objects.
 * Returns [] when the alert is expired, test/exercise, or does not contain
 * the user's coordinates.
 */
function _parseCapDocument(doc, userLat, userLon) {
    var now = new Date();
    var root = doc && doc.documentElement ? doc.documentElement : null;
    if (!root) return [];

    var status = _capText(root, "status");
    // Only "Actual" alerts — skip Test / Exercise / System / Draft.
    if (status && status !== "Actual") return [];

    var infos = _capChildren(root, "info");
    if (infos.length === 0) return [];

    // Merge geometry + parameters across all <info> blocks (language variants
    // of the same alert may each carry different area / parameter data), and
    // pick a local-language block for display text.
    var localInfo = _pickLocalInfoNode(infos);
    if (!localInfo) return [];

    var color = "", levelName = "", levelNum = 0;
    var awarenessTypeNum = 0, eventType = "";
    var expires = "";
    var eventEndingTime = "";   // NWS puts the real event end here, not in <expires>
    var allAreaNodes = [];
    var rtypes = [];

    infos.forEach(function (inf) {
        _capChildren(inf, "area").forEach(function (a) { allAreaNodes.push(a); });

        _capChildrenText(inf, "responseType").forEach(function (rt) {
            if (rtypes.indexOf(rt) < 0) rtypes.push(rt);
        });

        var infExpires = _capText(inf, "expires");
        if (infExpires && (!expires || infExpires > expires))
            expires = infExpires;

        _capChildren(inf, "parameter").forEach(function (p) {
            var name = _capText(p, "valueName");
            var value = _capText(p, "value");
            if (!name || !value) return;
            if (name === "awareness_level" && !color) {
                var parts = value.split(";");
                if (parts.length >= 1) levelNum = parseInt(parts[0].trim(), 10) || 0;
                if (parts.length >= 2) color = parts[1].trim().toLowerCase();
                if (parts.length >= 3) levelName = parts[2].trim();
            }
            if (name === "awareness_type" && !eventType) {
                var tp = value.split(";");
                if (tp.length >= 1) awarenessTypeNum = parseInt(tp[0].trim(), 10) || 0;
                if (tp.length >= 2) eventType = tp[1].trim();
            }
            // NWS-style CAP: the message <expires> is a refresh timestamp, not
            // the event's end. The true end is in the eventEndingTime parameter.
            if (name === "eventEndingTime" && value && (!eventEndingTime || value > eventEndingTime))
                eventEndingTime = value;
        });
    });

    // Skip cancellation notices
    if (rtypes.indexOf("AllClear") >= 0) return [];

    // Effective expiry: prefer the real event end (eventEndingTime, used by
    // NWS) over the CAP <expires> refresh timestamp, so alerts whose <expires>
    // is a stale message-refresh time aren't wrongly treated as ended.
    var alertExpires = eventEndingTime
        || _capText(localInfo, "expires") || expires;
    if (alertExpires) {
        var exp = new Date(alertExpires);
        if (exp < now) return [];
    }

    // Skip green / level-1 "no special awareness required"
    if (levelNum <= 1 && color === "green") return [];

    // ── Fallbacks for feeds without MeteoAlarm awareness_* parameters ──
    // NWS (US) CAP has no awareness_level/awareness_type; derive both from
    // the standard CAP <severity> and the event text, matching the mapping
    // used by the native NWS/LibreWXR parsers so colors, notification gating,
    // and per-type icons keep working.
    var sevText = _capText(localInfo, "severity").toLowerCase();
    if (!color) {
        if (sevText === "extreme" || sevText === "severe") color = "red";
        else if (sevText === "moderate") color = "orange";
        else if (sevText === "minor") color = "yellow";
    }
    if (awarenessTypeNum === 0) {
        // Classify from the event name first (most authoritative — e.g. a
        // "Red Flag Warning" whose body also mentions "thunderstorms" is a
        // fire alert), then fall back to headline, then the full description.
        awarenessTypeNum = _awarenessFromText(_capText(localInfo, "event").toLowerCase())
            || _awarenessFromText(_capText(localInfo, "headline").toLowerCase())
            || _awarenessFromText(_capText(localInfo, "description").toLowerCase());
    }

    // ── Point-in-area filtering ───────────────────────────────────────
    // The server filters by bbox intersection, not point containment, so
    // verify the coordinates actually fall inside one of the alert's areas.
    // If the alert carries no usable geometry we keep it (bbox was tight).
    var hasCoords = !isNaN(userLat) && !isNaN(userLon);
    var matchedAreas = [];
    var sawGeometry = false;

    allAreaNodes.forEach(function (a) {
        var ad = _capText(a, "areaDesc");
        var polys = _capChildrenText(a, "polygon");
        var circles = _capChildrenText(a, "circle");
        if (polys.length > 0 || circles.length > 0) sawGeometry = true;
        if (!hasCoords) return;
        if (_areaNodeContainsPoint(polys, circles, userLat, userLon)) {
            if (matchedAreas.indexOf(ad) < 0) matchedAreas.push(ad);
        }
    });

    if (hasCoords && sawGeometry && matchedAreas.length === 0)
        return [];  // geometry present but point is outside → not our alert

    if (matchedAreas.length === 0) {
        // No geometry (or no coords) — fall back to listing every areaDesc.
        allAreaNodes.forEach(function (a) {
            var ad = _capText(a, "areaDesc");
            if (ad && matchedAreas.indexOf(ad) < 0) matchedAreas.push(ad);
        });
    }

    var displayName = _capText(localInfo, "event") || eventType
        || _capText(localInfo, "headline") || "";
    var action = rtypes
        .filter(function (rt) { return rt !== "AllClear"; })
        .join(", ");

    var capOnset = _capText(localInfo, "onset");
    var capEffective = _capText(localInfo, "effective");
    // Notification gating treats an alert as "active" only within
    // [onset, expires]. For NWS-style CAP, <onset> is often the future peak
    // of the hazard while <effective> is when the warning was issued and is
    // already in force — so use the earlier of the two as the effective
    // onset. That way an already-issued Red Flag / Heat warning notifies
    // immediately instead of staying silent until its peak hour.
    var effOnset = _earlierIso(capOnset, capEffective) || capEffective || capOnset || "";

    return [{
        headline:      _capText(localInfo, "headline") || _capText(localInfo, "event") || "",
        displayName:   displayName,
        severity:      _capText(localInfo, "severity") || "",
        description:   _capText(localInfo, "description") || "",
        event:         _capText(localInfo, "event") || eventType || "",
        area:          matchedAreas.join(", "),
        color:         color,
        awarenessType: awarenessTypeNum,
        onset:         effOnset,
        effective:     capEffective || capOnset || "",
        expires:       alertExpires || "",
        instruction:   _capText(localInfo, "instruction") || "",
        web:           _capText(localInfo, "web") || "",
        source:        "FOSS Public Alert Server",
        action:        action,
        senderName:    _capText(localInfo, "senderName") || ""
    }];
}

/**
 * Fallback text parser for environments where responseXML is unavailable.
 * Reconstructs a DOM via Qt's XmlListModel-free path is not possible in plain
 * JS, so we do a light regex extraction of the first <info> block. This is a
 * best-effort safety net; the DOM path (responseXML) is the normal route.
 */
function _parseCapText(text, userLat, userLon) {
    if (!text) return [];
    function _tag(scope, name) {
        // \\b after the name so "<value>" does not also match "<valueName>".
        var m = new RegExp("<" + name + "(?:\\s[^>]*)?>([\\s\\S]*?)<\\/" + name + ">").exec(scope);
        return m ? _decodeEntities(m[1].trim()) : "";
    }
    var status = _tag(text, "status");
    if (status && status !== "Actual") return [];
    var infoMatch = /<info\b[^>]*>([\s\S]*?)<\/info>/.exec(text);
    if (!infoMatch) return [];
    var info = infoMatch[1];

    var color = "", awarenessTypeNum = 0, eventType = "", levelNum = 0;
    var eventEndingTime = "";
    var paramRe = /<parameter\b[^>]*>([\s\S]*?)<\/parameter>/g, pm;
    while ((pm = paramRe.exec(info)) !== null) {
        var pv = pm[1];
        var vn = _tag(pv, "valueName");
        var val = _tag(pv, "value");
        if (vn === "awareness_level" && !color) {
            var parts = val.split(";");
            if (parts.length >= 1) levelNum = parseInt(parts[0].trim(), 10) || 0;
            if (parts.length >= 2) color = parts[1].trim().toLowerCase();
        }
        if (vn === "awareness_type" && !eventType) {
            var tp = val.split(";");
            if (tp.length >= 1) awarenessTypeNum = parseInt(tp[0].trim(), 10) || 0;
            if (tp.length >= 2) eventType = tp[1].trim();
        }
        if (vn === "eventEndingTime" && val && (!eventEndingTime || val > eventEndingTime))
            eventEndingTime = val;
    }
    var expires = eventEndingTime || _tag(info, "expires");
    if (expires && new Date(expires) < new Date()) return [];
    if (levelNum <= 1 && color === "green") return [];

    var sevText = _tag(info, "severity").toLowerCase();
    if (!color) {
        if (sevText === "extreme" || sevText === "severe") color = "red";
        else if (sevText === "moderate") color = "orange";
        else if (sevText === "minor") color = "yellow";
    }
    if (awarenessTypeNum === 0) {
        awarenessTypeNum = _awarenessFromText(_tag(info, "event").toLowerCase())
            || _awarenessFromText(_tag(info, "headline").toLowerCase())
            || _awarenessFromText(_tag(info, "description").toLowerCase());
    }

    var displayName = _tag(info, "event") || eventType || _tag(info, "headline") || "";
    var capOnset = _tag(info, "onset");
    var capEffective = _tag(info, "effective");
    var effOnset = _earlierIso(capOnset, capEffective) || capEffective || capOnset || "";
    return [{
        headline:      _tag(info, "headline") || _tag(info, "event") || "",
        displayName:   displayName,
        severity:      _tag(info, "severity") || "",
        description:   _tag(info, "description") || "",
        event:         _tag(info, "event") || eventType || "",
        area:          _tag(info, "areaDesc") || "",
        color:         color,
        awarenessType: awarenessTypeNum,
        onset:         effOnset,
        effective:     capEffective || capOnset || "",
        expires:       expires || "",
        instruction:   _tag(info, "instruction") || "",
        web:           _tag(info, "web") || "",
        source:        "FOSS Public Alert Server",
        action:        "",
        senderName:    _tag(info, "senderName") || ""
    }];
}

/**
 * Return the earlier of two ISO-8601 timestamps (either may be empty).
 * Falls back to whichever is present. "" when both are empty/invalid.
 */
function _earlierIso(a, b) {
    var ta = a ? new Date(a).getTime() : NaN;
    var tb = b ? new Date(b).getTime() : NaN;
    if (isNaN(ta)) return isNaN(tb) ? "" : b;
    if (isNaN(tb)) return a;
    return ta <= tb ? a : b;
}

/**
 * Derive a MeteoAlarm-style awareness-type number from free alert text.
 * Ordered specific → generic; mirrors the keyword mapping in alerts.js
 * (NWS parser) and librewxrAlerts.js so per-type notification settings and
 * icons work for feeds that lack the awareness_type CAP parameter.
 */
function _awarenessFromText(text) {
    if (!text) return 0;
    if (text.indexOf("tornado") >= 0) return 1;
    if (text.indexOf("thunder") >= 0) return 3;
    if (text.indexOf("blizzard") >= 0 || text.indexOf("snow") >= 0 || text.indexOf("ice") >= 0) return 2;
    if (text.indexOf("avalanche") >= 0) return 9;
    if (text.indexOf("coastal") >= 0 || text.indexOf("tsunami") >= 0 || text.indexOf("storm surge") >= 0) return 7;
    if (text.indexOf("fire") >= 0 || text.indexOf("red flag") >= 0) return 8;
    if (text.indexOf("fog") >= 0) return 4;
    if (text.indexOf("heat") >= 0) return 5;
    if (text.indexOf("cold") >= 0 || text.indexOf("freeze") >= 0 || text.indexOf("frost") >= 0 || text.indexOf("chill") >= 0) return 6;
    if (text.indexOf("flood") >= 0) return 11;
    if (text.indexOf("rain") >= 0) return 10;
    if (text.indexOf("wind") >= 0) return 1;
    return 0;
}

// ── DOM helpers ───────────────────────────────────────────────────────

/** Direct child elements of `node` with the given (namespace-agnostic) tag. */
function _capChildren(node, tag) {
    var out = [];
    if (!node || !node.childNodes) return out;
    var kids = node.childNodes;
    for (var i = 0; i < kids.length; i++) {
        var c = kids[i];
        if (c.nodeType === 1 && _localName(c) === tag)
            out.push(c);
    }
    return out;
}

/** Trimmed text content of the first direct child element named `tag`. */
function _capText(node, tag) {
    var kids = _capChildren(node, tag);
    if (kids.length === 0) return "";
    return _nodeText(kids[0]).trim();
}

/** Text of every direct child element named `tag`. */
function _capChildrenText(node, tag) {
    return _capChildren(node, tag).map(function (c) {
        return _nodeText(c).trim();
    }).filter(function (s) { return s.length > 0; });
}

function _nodeText(node) {
    if (!node) return "";
    if (node.textContent !== undefined && node.textContent !== null)
        return node.textContent;
    var s = "";
    if (node.childNodes) {
        for (var i = 0; i < node.childNodes.length; i++) {
            var c = node.childNodes[i];
            if (c.nodeType === 3 || c.nodeType === 4) // text / CDATA
                s += c.nodeValue || "";
            else if (c.nodeType === 1)
                s += _nodeText(c);
        }
    }
    return s;
}

/** Local (namespace-stripped) element name. */
function _localName(node) {
    if (node.localName) return node.localName;
    var n = node.nodeName || node.tagName || "";
    var idx = n.indexOf(":");
    return idx >= 0 ? n.substring(idx + 1) : n;
}

/**
 * Pick a local-language <info> node for display, preferring a non-English
 * language, then English, then the first block — mirrors alerts.js.
 */
function _pickLocalInfoNode(infos) {
    var local = null, english = null;
    for (var i = 0; i < infos.length; i++) {
        var lang = _capText(infos[i], "language").toLowerCase();
        if (lang === "en-gb" || lang === "en" || lang.indexOf("en") === 0) {
            if (!english) english = infos[i];
        } else if (lang.length > 0) {
            if (!local) local = infos[i];
        }
    }
    return local || english || infos[0] || null;
}

// ── Point-in-area geometry (mirrors alerts.js) ────────────────────────

function _areaNodeContainsPoint(polygons, circles, lat, lon) {
    for (var i = 0; i < polygons.length; i++) {
        var pts = _parseCapPolygon(polygons[i]);
        if (pts.length >= 3 && _pointInPolygon(lat, lon, pts))
            return true;
    }
    for (var j = 0; j < circles.length; j++) {
        if (_pointInCircle(lat, lon, circles[j]))
            return true;
    }
    return false;
}

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

function _haversineKm(lat1, lon1, lat2, lon2) {
    var R = 6371;
    var dLat = (lat2 - lat1) * Math.PI / 180;
    var dLon = (lon2 - lon1) * Math.PI / 180;
    var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function _decodeEntities(s) {
    return s.replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
            .replace(/&amp;/g, "&");
}
