/*
 * Copyright 2026 Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://gnu.org>.
 */

/**
 * debug.js - central debug / diagnostics helper for the widget.
 *
 * Turned on with Settings -> Misc -> Debug -> "Debug mode"
 * (config key `debugMode`). When it is OFF every call here is a cheap no-op
 * (log/mark/cycle…) or returns a plain XMLHttpRequest (xhr), so normal use
 * pays nothing. Warnings and errors (warn/error) are always printed.
 *
 * Every line carries the same tag so the output can be grepped:
 *
 *     [Advanced Weather Widget - <Component>] (+1234 ms) message
 *
 * e.g.   journalctl --user -f | grep "Advanced Weather Widget"
 *        plasmashell --replace 2>&1 | grep "Advanced Weather Widget"
 *        plasmoidviewer -a <path-to-plasmoid> 2>&1 | grep "Advanced Weather Widget"
 *
 * "(+N ms)" is the time since this module was first loaded, which is the
 * moment the widget started building itself - so every line doubles as a
 * "how long did it take to get here" reading.
 *
 * Usage (QML):     import "js/debug.js" as Dbg          // components/: "../js/debug.js"
 * Usage (JS):      .import "../js/debug.js" as Dbg      // providers/
 *
 *   Dbg.log("WeatherService", "message", value, ...)    // debug only
 *   Dbg.warn("AEMET", "something odd", ...)             // always
 *   Dbg.mark("Startup", "first weather data on screen") // timeline milestone
 *   var sw = Dbg.stopwatch(); ...; Dbg.log("X", "took", sw.ms(), "ms")
 *   var req = Dbg.xhr("Open-Meteo", "current");         // instead of new XMLHttpRequest()
 *
 * NOTE: this is a .pragma library, so it has no access to Plasmoid. Each QML
 * engine (the applet, and the separate settings dialog) must call
 * Dbg.setEnabled(Plasmoid.configuration.debugMode === true) itself - see
 * main.qml and the config pages.
 */
.pragma library

var TAG = "Advanced Weather Widget";

// ── State ───────────────────────────────────────────────────────────────────
var _enabled = false;
var _t0 = Date.now();           // module load ≈ widget start-up
var _marks = [];                // timeline milestones (recorded even while disabled)
var _lastMarkMs = 0;
var _reqSeq = 0;
var _pending = {};              // id -> request record, while in flight
var _cycle = null;              // the refresh cycle currently being measured
var _cycleSeq = 0;
var _startupReported = false;
var _settleQueued = false;
var _MAX_MARKS = 200;

// ── Basics ──────────────────────────────────────────────────────────────────

function setEnabled(on, source) {
    on = (on === true);
    if (on === _enabled)
        return;
    if (!on) {
        log("Debug", "Debug mode DISABLED (warnings and errors are still printed)");
        _enabled = false;
        return;
    }
    _enabled = true;
    log("Debug", "Debug mode ENABLED" + (source ? " (" + source + ")" : "")
        + " - widget has been running for " + now() + " ms. Lines look like: ["
        + TAG + " - <Component>] (+ms since widget start) message");
    // Milestones that happened before debug was switched on are not lost
    if (_marks.length > 0) {
        log("Debug", "Timeline so far (" + _marks.length + " milestone(s) recorded before debug mode was on):");
        for (var i = 0; i < _marks.length; i++) {
            var m = _marks[i];
            log(m.component, "⏱ " + m.name + " - at +" + m.atMs + " ms (Δ " + m.deltaMs + " ms)"
                + (m.detail ? " - " + m.detail : ""));
        }
    }
}

function enabled() {
    return _enabled;
}

/** Milliseconds since this module loaded (≈ since the widget started). */
function now() {
    return Date.now() - _t0;
}

function prefix(component) {
    return "[" + TAG + (component ? " - " + component : "") + "] (+" + now() + " ms)";
}

function _args(a, from) {
    return Array.prototype.slice.call(a, from);
}

// The last few debug lines (time + start of the text), so a stall report can say what the widget
// was doing right before the GUI thread went quiet.
var _ring = [];
var _RING_MAX = 40;
function _remember(component, firstPart) {
    _ring.push({ at: now(), text: "[" + component + "] " + String(firstPart === undefined ? "" : firstPart).substring(0, 100) });
    if (_ring.length > _RING_MAX)
        _ring.shift();
}
/** The last debug line logged at or before `atMs` (ms since widget start), as text; "" if none. */
function lastLineBefore(atMs) {
    for (var i = _ring.length - 1; i >= 0; i--)
        if (_ring[i].at <= atMs)
            return _ring[i].text + " (+" + _ring[i].at + " ms)";
    return "";
}
/** How many debug lines were logged strictly between the two moments (ms since widget start). */
function linesBetween(fromMs, toMs) {
    var n = 0;
    for (var i = 0; i < _ring.length; i++)
        if (_ring[i].at > fromMs && _ring[i].at < toMs)
            n++;
    return n;
}
/** The first debug line logged after `atMs`, as text; "" if none yet. */
function firstLineAfter(atMs) {
    for (var i = 0; i < _ring.length; i++)
        if (_ring[i].at > atMs)
            return _ring[i].text + " (+" + _ring[i].at + " ms)";
    return "";
}

/** Debug-only message. log(component, ...parts) */
function log(component) {
    if (!_enabled)
        return;
    var a = _args(arguments, 1);
    _remember(component, a[0]);
    a.unshift(prefix(component));
    console.log.apply(console, a);
}

/** Always-on warning. warn(component, ...parts) */
function warn(component) {
    var a = _args(arguments, 1);
    a.unshift(prefix(component));
    console.warn.apply(console, a);
}

/** Always-on error. error(component, ...parts) */
function error(component) {
    var a = _args(arguments, 1);
    a.unshift(prefix(component));
    console.error.apply(console, a);
}

/** Simple stopwatch: var sw = Dbg.stopwatch(); ... sw.ms() */
function stopwatch() {
    var t0 = Date.now();
    return {
        ms: function () {
            return Date.now() - t0;
        }
    };
}

// ── Formatting helpers ──────────────────────────────────────────────────────

function bytesText(n) {
    if (n === undefined || n === null || isNaN(n))
        return "? B";
    if (n < 1024)
        return n + " B";
    if (n < 1024 * 1024)
        return (n / 1024).toFixed(1) + " KB";
    return (n / 1024 / 1024).toFixed(2) + " MB";
}

function snippet(text, max) {
    var s = String(text === undefined || text === null ? "" : text).replace(/\s+/g, " ").trim();
    max = max || 300;
    return s.length > max ? s.substring(0, max) + "… (+" + (s.length - max) + " chars)" : s;
}

/** Compact JSON for log lines (never throws). */
function json(o, max) {
    try {
        return snippet(JSON.stringify(o), max || 400);
    } catch (e) {
        return String(o);
    }
}

/** URL for log lines: scheme/host/path plus the query *parameter names* only when it is long (the radar page URL carries ~6 KB of query string). */
function shortUrl(url) {
    var s = redact(url);
    if (s.length <= 200)
        return s;
    var q = s.indexOf("?");
    if (q < 0)
        return s.substring(0, 200) + "… (+" + (s.length - 200) + " chars)";
    var names = s.substring(q + 1).split("&").map(function (kv) {
        return kv.split("=")[0];
    });
    return s.substring(0, q) + "?… (" + (s.length - q - 1) + " chars of query: " + names.slice(0, 12).join(",") + (names.length > 12 ? ",…" : "") + ")";
}

function hostOf(url) {
    var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)/i.exec(String(url));
    return m ? m[1] : String(url);
}

/**
 * Removes credentials from a URL before it is logged. Covers the query
 * parameters the supported providers use (key / api_key / appid / token …)
 * and Pirate Weather's key-in-the-path form (/forecast/<key>/lat,lon).
 * Debug output is meant to be pasted into bug reports, so nothing secret
 * may reach it.
 */
function redact(url) {
    var s = String(url === undefined || url === null ? "" : url);
    s = s.replace(/([?&](?:api[-_]?key|key|appid|app_id|token|access[-_]?token|apikey|auth|authorization|secret|signature|sig)=)[^&#]*/gi, "$1<redacted>");
    s = s.replace(/(\/forecast\/)[^\/?#]+(\/-?\d)/i, "$1<redacted>$2");
    return s;
}

function _isSecretName(name) {
    return /key|token|secret|password|passwd|auth|credential/i.test(String(name));
}

function statusHint(status) {
    if (status === 0)
        return "no HTTP answer (offline, DNS/TLS failure, blocked, timeout or aborted)";
    if (status >= 200 && status < 300)
        return "OK";
    if (status === 301 || status === 302 || status === 307 || status === 308)
        return "redirect";
    if (status === 304)
        return "not modified";
    if (status === 400)
        return "bad request (the API rejected the parameters)";
    if (status === 401)
        return "unauthorized (API key missing, wrong or expired)";
    if (status === 403)
        return "forbidden (key not allowed for this endpoint, plan limit, or blocked)";
    if (status === 404)
        return "not found (wrong URL/id, or no data for this location)";
    if (status === 408)
        return "request timeout";
    if (status === 429)
        return "rate limited (too many requests - wait before retrying)";
    if (status >= 500 && status < 600)
        return "server error on the provider's side";
    return "unexpected status";
}

/** Short structural summary of a parsed JSON value: key names + array/object sizes. */
function shape(o, max) {
    try {
        if (o === null || o === undefined)
            return String(o);
        if (Array.isArray(o))
            return "array[" + o.length + "]" + (o.length > 0 && typeof o[0] === "object" && o[0] !== null ? " of {" + Object.keys(o[0]).slice(0, 12).join(",") + "}" : "");
        if (typeof o !== "object")
            return typeof o;
        var parts = [];
        var keys = Object.keys(o);
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i];
            var v = o[k];
            if (Array.isArray(v))
                parts.push(k + "[" + v.length + "]");
            else if (v !== null && typeof v === "object")
                parts.push(k + "{" + Object.keys(v).length + "}");
            else if (typeof v === "string")
                parts.push(k + "=\"" + (v.length > 24 ? v.substring(0, 24) + "…" : v) + "\"");
            else
                parts.push(k + "=" + v);
        }
        return snippet(parts.join(", "), max || 420);
    } catch (e) {
        return "(unprintable)";
    }
}

// ── Timeline / milestones ───────────────────────────────────────────────────

/**
 * Records a milestone ("weather data applied", "Providers.qml loaded", …).
 * Milestones are kept even while debug mode is off, so switching it on later
 * still shows how the start-up went.
 */
function mark(component, name, detail) {
    var at = now();
    var rec = {
        component: component,
        name: name,
        detail: detail || "",
        atMs: at,
        deltaMs: at - _lastMarkMs
    };
    _lastMarkMs = at;
    _marks.push(rec);
    if (_marks.length > _MAX_MARKS)
        _marks.shift();
    log(component, "⏱ " + name + " - at +" + at + " ms (Δ " + rec.deltaMs + " ms)" + (detail ? " - " + detail : ""));
}

/** Prints the milestone table so far. */
function timeline(component) {
    if (!_enabled)
        return;
    log(component || "Startup", "──── Timeline (" + _marks.length + " milestones) ────");
    for (var i = 0; i < _marks.length; i++) {
        var m = _marks[i];
        log(component || "Startup", "  +" + _pad(m.atMs, 6) + " ms  (Δ " + _pad(m.deltaMs, 5) + " ms)  [" + m.component + "] " + m.name + (m.detail ? " - " + m.detail : ""));
    }
}

function _pad(n, w) {
    var s = String(n);
    while (s.length < w)
        s = " " + s;
    return s;
}

// ── Environment + configuration dump ────────────────────────────────────────

/** Qt / platform info. Pass extra = { "key": value, … } for widget-side facts. */
function environment(component, extra) {
    if (!_enabled)
        return;
    var parts = [];
    try {
        parts.push("platform=" + Qt.platform.os);
    } catch (e) {}
    try {
        parts.push("locale=" + Qt.locale().name);
    } catch (e) {}
    try {
        parts.push("appName=" + Qt.application.name);
    } catch (e) {}
    if (extra)
        for (var k in extra)
            parts.push(k + "=" + extra[k]);
    log(component, "Environment: " + parts.join(", "));
}

/**
 * Prints the given configuration keys. Anything whose name looks like a
 * secret (…Key, token, password) is reported only as "set (N chars)" /
 * "not set" - never its value.
 */
function dumpConfig(component, cfg, keys) {
    if (!_enabled || !cfg)
        return;
    var out = [];
    for (var i = 0; i < keys.length; i++) {
        var k = keys[i];
        var v;
        try {
            v = cfg[k];
        } catch (e) {
            v = undefined;
        }
        if (_isSecretName(k)) {
            var s = (v === undefined || v === null) ? "" : String(v).trim();
            out.push(k + "=" + (s.length > 0 ? "set (" + s.length + " chars)" : "not set"));
        } else if (v === undefined) {
            out.push(k + "=(undefined)");
        } else {
            out.push(k + "=" + (typeof v === "string" ? "\"" + snippet(v, 60) + "\"" : v));
        }
    }
    log(component, "Configuration: " + out.join(", "));
}

// ── HTTP request tracing ────────────────────────────────────────────────────

/**
 * Drop-in replacement for `new XMLHttpRequest()`:
 *
 *     var req = Dbg.xhr("Open-Meteo", "current");
 *     req.open("GET", url); req.onreadystatechange = ...; req.send();
 *
 * With debug mode off this IS a plain XMLHttpRequest. With it on, open() /
 * setRequestHeader() / send() / abort() are wrapped on this one instance so
 * that the request line, the response status, timing, size, interesting
 * headers and a shape summary of the JSON body get logged - the provider code
 * itself is untouched. If instrumenting ever fails, the plain request is
 * returned and the widget carries on normally.
 */
function xhr(component, label) {
    var x = new XMLHttpRequest();
    if (!_enabled)
        return x;
    try {
        _instrument(x, component, label || "");
    } catch (e) {
        console.warn(prefix("Debug"), "could not instrument a request (" + component + "/" + label + "):", e);
    }
    return x;
}

var _INTERESTING_HEADERS = ["content-type", "content-length", "content-encoding", "retry-after", "x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset", "x-rate-limit-remaining", "ratelimit-remaining", "ratelimit-reset", "x-forecast-api-calls", "cache-control", "expires", "last-modified", "age", "server", "location"];

function _instrument(x, component, label) {
    var rec = {
        id: ++_reqSeq,
        component: component,
        label: label,
        method: "GET",
        url: "",
        host: "",
        headerNames: [],
        t0: 0,
        done: false,
        cycle: _cycle
    };
    var origOpen = x.open;
    var origSend = x.send;
    var origSetHeader = x.setRequestHeader;
    var origAbort = x.abort;

    // QML's XMLHttpRequest keeps open/send/... as read-only prototype
    // properties, so a plain `x.send = fn` is silently ignored (sloppy mode).
    // Object.defineProperty on the instance is what actually shadows them.
    function wrap(name, fn) {
        Object.defineProperty(x, name, {
            value: fn,
            writable: true,
            configurable: true,
            enumerable: false
        });
    }

    wrap("open", function (method, url) {
        rec.method = method || "GET";
        rec.url = redact(url);
        rec.host = hostOf(url);
        return origOpen.apply(x, arguments);
    });

    wrap("setRequestHeader", function (name, value) {
        rec.headerNames.push(_isSecretName(name) || /^authorization$/i.test(name) ? name + ": <redacted>" : name + ": " + snippet(value, 80));
        return origSetHeader.apply(x, arguments);
    });

    wrap("send", function (body) {
        rec.t0 = Date.now();
        _pending[rec.id] = rec;
        if (rec.cycle)
            rec.cycle.requests++;
        // Wrap whatever handler the caller installed, so the response is
        // logged before the caller's own code runs.
        var userHandler = x.onreadystatechange;
        x.onreadystatechange = function () {
            if (x.readyState === 4)
                _finish(x, rec);
            if (userHandler)
                return userHandler.apply(x, arguments);
        };
        var n = _pendingCount();
        log(component, "→ #" + rec.id + " " + rec.method + " " + rec.host + " [" + label + "] " + rec.url + (body ? "  (body " + bytesText(String(body).length) + ")" : "")
            + (rec.headerNames.length > 0 ? "  headers: {" + rec.headerNames.join("; ") + "}" : "")
            + "  (in flight: " + n + ")");
        return origSend.apply(x, arguments);
    });

    wrap("abort", function () {
        if (!rec.done) {
            rec.done = true;
            delete _pending[rec.id];
            log(component, "✖ #" + rec.id + " " + rec.host + " [" + label + "] aborted after " + (Date.now() - rec.t0) + " ms");
            _queueSettleCheck();
        }
        return origAbort.apply(x, arguments);
    });
}

function _finish(x, rec) {
    if (rec.done)
        return;
    rec.done = true;
    delete _pending[rec.id];
    var ms = Date.now() - rec.t0;
    var status = 0, statusText = "", text = "", ctype = "";
    try {
        status = x.status;
    } catch (e) {}
    try {
        statusText = x.statusText || "";
    } catch (e) {}
    try {
        text = x.responseText || "";
    } catch (e) {}
    try {
        ctype = x.getResponseHeader("content-type") || "";
    } catch (e) {}

    // 304 Not Modified is the normal answer to a conditional request (If-Modified-Since), not a failure
    var ok = (status >= 200 && status < 300) || status === 304;
    var cyc = rec.cycle;
    if (cyc) {
        cyc.done++;
        cyc.bytes += text.length;
        if (!ok)
            cyc.failed++;
        var h = cyc.hosts[rec.host] || (cyc.hosts[rec.host] = {
                count: 0,
                ms: 0
            });
        h.count++;
        h.ms += ms;
        if (!cyc.slowest || ms > cyc.slowest.ms)
            cyc.slowest = {
                ms: ms,
                what: rec.host + " [" + rec.label + "]"
            };
    }

    var line = (ok ? "← #" : "✖ #") + rec.id + " " + rec.host + " [" + rec.label + "] HTTP " + status + (statusText ? " " + statusText : "") + " in " + ms + " ms, " + bytesText(text.length) + (ctype ? ", " + ctype.split(";")[0] : "");
    if (ok) {
        log(rec.component, line);
    } else {
        // A failing request is worth seeing even without debug mode's other output,
        // but only requests created while debug mode was on get here at all.
        warn(rec.component, line + " - " + statusHint(status));
        if (text.length > 0)
            warn(rec.component, "  #" + rec.id + " response body: " + snippet(text, 400));
    }

    if (_enabled) {
        // Headers that matter when diagnosing limits / caching / redirects
        try {
            var hv = [];
            for (var i = 0; i < _INTERESTING_HEADERS.length; i++) {
                var n = _INTERESTING_HEADERS[i];
                if (n === "content-type" || n === "content-length")
                    continue;
                var v = x.getResponseHeader(n);
                if (v)
                    hv.push(n + ": " + snippet(v, 80));
            }
            if (hv.length > 0)
                log(rec.component, "  #" + rec.id + " response headers: " + hv.join("; "));
        } catch (e) {}
        // What came back, structurally (JSON only, bounded size, after timing was taken)
        if (ok && text.length > 0 && text.length < 1500000 && (/json/i.test(ctype) || /^\s*[\[{]/.test(text))) {
            try {
                log(rec.component, "  #" + rec.id + " JSON: " + shape(JSON.parse(text)));
            } catch (e) {
                log(rec.component, "  #" + rec.id + " body is not valid JSON: " + snippet(text, 160));
            }
        } else if (ok && text.length > 0 && !/json/i.test(ctype)) {
            log(rec.component, "  #" + rec.id + " body starts: " + snippet(text, 160));
        }
    }
    _queueSettleCheck();
}

function _pendingCount() {
    var n = 0;
    for (var k in _pending)
        n++;
    return n;
}

/** Lists requests that were sent but never answered (useful when something hangs). */
function logPending(component) {
    if (!_enabled)
        return;
    var n = 0;
    for (var k in _pending) {
        var r = _pending[k];
        n++;
        log(component, "  still waiting: #" + r.id + " " + r.method + " " + r.host + " [" + r.component + "/" + r.label + "] for " + (Date.now() - r.t0) + " ms");
    }
    if (n === 0)
        log(component, "  no requests in flight");
}

// ── Refresh cycles: "how long until everything is loaded" ───────────────────

/**
 * Called when a full refresh starts. Every request sent from now on is
 * counted towards this cycle; once the last one has been answered the cycle
 * is reported (wall time, requests, failures, slowest request, per host).
 */
function cycleBegin(component, reason, info) {
    if (!_enabled)
        return;
    if (_cycle && !_cycle.reported)
        log(component, "Refresh cycle #" + _cycle.id + " superseded by a new one after " + (Date.now() - _cycle.t0) + " ms (" + _cycle.done + "/" + _cycle.requests + " requests had answered)");
    // forget requests that never answered in a previous cycle
    var cutoff = Date.now() - 120000;
    for (var k in _pending)
        if (_pending[k].t0 < cutoff)
            delete _pending[k];
    _cycle = {
        id: ++_cycleSeq,
        t0: Date.now(),
        requests: 0,
        done: 0,
        failed: 0,
        bytes: 0,
        hosts: {},
        slowest: null,
        reported: false,
        reason: reason || ""
    };
    log(component, "━━ Refresh cycle #" + _cycle.id + " started" + (reason ? " (" + reason + ")" : "") + (info ? " - " + info : ""));
}

function _queueSettleCheck() {
    // Deferred, because a provider's response handler typically starts the next
    // request (fallback provider, backfill…) right after we logged this one.
    if (_settleQueued)
        return;
    _settleQueued = true;
    try {
        Qt.callLater(_settleCheck);
    } catch (e) {
        _settleQueued = false;
        _settleCheck();
    }
}

function _settleCheck() {
    _settleQueued = false;
    if (!_enabled || !_cycle || _cycle.reported)
        return;
    if (_pendingCount() > 0 || _cycle.requests === 0)
        return;
    var c = _cycle;
    c.reported = true;
    var ms = Date.now() - c.t0;
    log("Refresh", "━━ Refresh cycle #" + c.id + " settled in " + ms + " ms: " + c.requests + " request(s), " + (c.done - c.failed) + " ok, " + c.failed + " failed, " + bytesText(c.bytes) + " received" + (c.slowest ? "; slowest: " + c.slowest.what + " " + c.slowest.ms + " ms" : ""));
    var hostLines = [];
    for (var h in c.hosts)
        hostLines.push(h + " ×" + c.hosts[h].count + " (avg " + Math.round(c.hosts[h].ms / c.hosts[h].count) + " ms)");
    if (hostLines.length > 0)
        log("Refresh", "   per host: " + hostLines.join(", "));
    if (!_startupReported) {
        _startupReported = true;
        mark("Startup", "first refresh cycle fully settled", "all data requests answered " + now() + " ms after the widget started");
        log("Startup", "★ WIDGET READY: first complete load took " + now() + " ms from widget start (the refresh itself: " + ms + " ms)");
        timeline("Startup");
    }
}

// ── Data summaries ──────────────────────────────────────────────────────────

/** One-line description of a staged weatherData object. */
function weatherSummary(d) {
    if (!d)
        return "(none)";
    function n(v, digits) {
        return (v === undefined || v === null || isNaN(v)) ? "--" : (digits !== undefined ? Number(v).toFixed(digits) : v);
    }
    return "temp=" + n(d.temperatureC, 1) + "°C feels=" + n(d.apparentC, 1) + "°C code=" + n(d.weatherCode) + " wind=" + n(d.windKmh, 1) + "km/h@" + n(d.windDirection) + "° hum=" + n(d.humidityPercent) + "% press=" + n(d.pressureHpa, 0) + "hPa uv=" + n(d.uvIndex, 1) + " vis=" + n(d.visibilityKm, 1) + "km precip=" + n(d.precipMmh, 1) + "mm/h sunrise=" + (d.sunriseTimeText || "--") + " sunset=" + (d.sunsetTimeText || "--") + " daily=" + (d.dailyData ? d.dailyData.length : 0) + " day(s)";
}

/** Lists which numeric fields of weatherData are missing (NaN/undefined). */
function missingFields(d) {
    if (!d)
        return "";
    var keys = ["temperatureC", "apparentC", "humidityPercent", "windKmh", "windDirection", "pressureHpa", "dewPointC", "visibilityKm", "precipMmh", "uvIndex", "snowDepthCm"];
    var miss = [];
    for (var i = 0; i < keys.length; i++) {
        var v = d[keys[i]];
        if (v === undefined || v === null || (typeof v === "number" && isNaN(v)))
            miss.push(keys[i]);
    }
    return miss.join(", ");
}
