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
 * along with this program; if not, see <https://www.gnu.org/licenses/>.
 */
.pragma library
.import "debug.js" as Dbg

/*
 * A drop-in replacement for Dbg.xhr() for GET requests whose answer is shared.
 *
 * Some providers answer "current weather" and "hourly forecast" from the very same URL
 * (met.no's locationforecast, StormGlass' point endpoint). Sending it twice a few hundred
 * milliseconds apart only wastes quota (StormGlass' free plan is 10 requests a day) and
 * bandwidth, so an identical GET that is already in flight is joined, and one that was
 * answered a moment ago is answered again from memory. Only successful answers are kept,
 * and only briefly: this is not a long-lived cache, the callers' own caches are.
 *
 * With { revalidate: true } the answer is also kept past that short window together with its
 * Last-Modified / Expires headers, the way met.no's terms of service ask clients to behave:
 *   - before the Expires time nothing is requested again (the data cannot have changed);
 *   - after it the request carries If-Modified-Since, and a "304 Not Modified" reply
 *     (no body, nearly free for the server) is turned into the previous answer.
 *
 * The returned object mimics the parts of XMLHttpRequest the providers use:
 * open(), setRequestHeader(), send(), onreadystatechange, readyState, status, responseText.
 */

var REUSE_MS = 120000;       // how long an answer may be reused
var MAX_ENTRIES = 6;
var _entries = {};           // key -> { t, done, status, text, waiters: [] }
var _validators = {};        // key -> { t, text, lastModified, expiresMs } (revalidate: true only)
var MAX_VALIDATORS = 4;

function _header(req, name) {
    try {
        return req.getResponseHeader(name) || "";
    } catch (e) {
        return "";
    }
}
function _clock(ms) {
    return new Date(ms).toTimeString().substring(0, 8);
}
function _remember(key, req, text) {
    var lm = _header(req, "Last-Modified");
    var ex = Date.parse(_header(req, "Expires"));
    if (!lm && isNaN(ex))
        return;
    _validators[key] = { t: Date.now(), text: text, lastModified: lm, expiresMs: isNaN(ex) ? 0 : ex };
    var keys = Object.keys(_validators);
    if (keys.length > MAX_VALIDATORS) {
        keys.sort(function (a, b) { return _validators[a].t - _validators[b].t; });
        for (var i = 0; i < keys.length - MAX_VALIDATORS; ++i)
            delete _validators[keys[i]];
    }
}

function _prune() {
    var keys = Object.keys(_entries);
    for (var i = 0; i < keys.length; ++i) {
        var e = _entries[keys[i]];
        if (e.done && Date.now() - e.t >= REUSE_MS)
            delete _entries[keys[i]];
    }
    keys = Object.keys(_entries);
    if (keys.length > MAX_ENTRIES) {
        keys.sort(function (a, b) { return _entries[a].t - _entries[b].t; });
        for (var j = 0; j < keys.length - MAX_ENTRIES; ++j)
            if (_entries[keys[j]].done)
                delete _entries[keys[j]];
    }
}

function xhr(component, label, opts) {
    var revalidate = !!(opts && opts.revalidate);
    var facade = {
        readyState: 0,
        status: 0,
        responseText: "",
        onreadystatechange: null,
        _url: "",
        _headers: [],
        open: function (method, url) {
            facade._url = url;
        },
        setRequestHeader: function (name, value) {
            facade._headers.push([name, value]);
        },
        abort: function () {
            facade.onreadystatechange = null;
        },
        send: function () {
            var key = facade._url + "\n" + facade._headers.map(function (h) { return h[0] + ":" + h[1]; }).join("\n");
            _prune();
            var e = _entries[key];
            if (e && e.done) {
                Dbg.log(component, label + ": an identical request was answered " + (Date.now() - e.t)
                        + " ms ago → reusing that answer, request skipped");
                Qt.callLater(function () { _finish(e.status, e.text); });
                return;
            }
            if (e) {
                Dbg.log(component, label + ": an identical request is already in flight → waiting for it, no second request");
                e.waiters.push(_finish);
                return;
            }
            var v = revalidate ? _validators[key] : null;
            if (v && v.expiresMs > Date.now()) {
                Dbg.log(component, label + ": the server says this answer is valid until " + _clock(v.expiresMs)
                        + " (Expires header) → reusing it, request skipped");
                Qt.callLater(function () { _finish(200, v.text); });
                return;
            }
            e = { t: Date.now(), done: false, status: 0, text: "", waiters: [_finish] };
            _entries[key] = e;
            var real = Dbg.xhr(component, label);
            real.open("GET", facade._url);
            facade._headers.forEach(function (h) { real.setRequestHeader(h[0], h[1]); });
            if (v && v.lastModified)
                real.setRequestHeader("If-Modified-Since", v.lastModified);
            real.onreadystatechange = function () {
                if (real.readyState !== XMLHttpRequest.DONE)
                    return;
                e.done = true;
                e.t = Date.now();
                e.status = real.status;
                e.text = real.responseText;
                if (revalidate) {
                    if (real.status === 304 && v) {
                        // nothing changed: the previous answer is still the current one, and the new
                        // Expires header says how long
                        var ex = Date.parse(_header(real, "Expires"));
                        if (!isNaN(ex))
                            v.expiresMs = ex;
                        v.t = Date.now();
                        Dbg.log(component, label + ": 304 Not Modified → using the previous answer");
                        e.status = 200;
                        e.text = v.text;
                    } else if (real.status === 200) {
                        _remember(key, real, e.text);
                    }
                }
                if (real.status !== 200)
                    delete _entries[key];        // failures are never reused
                var w = e.waiters;
                e.waiters = [];
                w.forEach(function (f) { f(e.status, e.text); });
            };
            real.send();
        }
    };
    function _finish(status, text) {
        if (!facade.onreadystatechange)
            return;
        facade.readyState = 4;
        facade.status = status;
        facade.responseText = text;
        facade.onreadystatechange();
    }
    return facade;
}
