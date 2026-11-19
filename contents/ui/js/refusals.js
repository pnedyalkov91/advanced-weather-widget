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
 * Providers that answer "no" - an API key they reject (HTTP 401/403) or a daily limit that is used
 * up (402/429) - as opposed to a connection that is down.
 *
 * Such an answer proves the Internet works and cannot change in seconds, yet a failed refresh used
 * to be handled like a lost connection: three quick retries (5, 15, 45 s) and then, while the last
 * sync had failed, a connectivity probe every minute that started another refresh every 2 minutes
 * for as long as the provider kept refusing. StormGlass counts the refused requests too (the
 * "requestCount" in its 402 reply), so one exhausted free plan kept the counter growing all night.
 *
 * A refusal is remembered per provider and API key. While it lasts the provider is skipped without
 * any request, WeatherService starts no quick retries and main.qml no connectivity probe. A manual
 * refresh (clear()) or a different key asks again at once.
 */

var _items = {};   // provider -> { status, key, t, until }

var KEY_REFUSED_MS = 60 * 60000;      // 401 / 402 / 403
var RATE_LIMITED_MS = 15 * 60000;     // 429 - often a short-lived limit

function isRefusal(status) {
    return status === 401 || status === 402 || status === 403 || status === 429;
}

function note(provider, status, key) {
    var ms = status === 429 ? RATE_LIMITED_MS : KEY_REFUSED_MS;
    var now = Date.now();
    // one shared request can reach several callers (current + hourly): note its answer only once
    var cur = _items[provider];
    if (cur && cur.status === status && cur.key === key && now < cur.until && now - cur.t < 5000)
        return;
    _items[provider] = { status: status, key: key, t: now, until: now + ms };
    Dbg.log("Refusals", provider + " refused the request (HTTP " + status + ") → not asked again for "
            + Math.round(ms / 60000) + " min; a manual refresh or a different API key asks at once");
}

/** The refusal still in force for the provider (and, when given, this API key), else null. */
function active(provider, key) {
    var r = _items[provider];
    if (!r)
        return null;
    if (Date.now() >= r.until || (key !== undefined && r.key !== key)) {
        delete _items[provider];
        return null;
    }
    return r;
}

/** Debug line for a request that was not sent because of an active refusal. */
function logSkip(component, what, r) {
    Dbg.log(component, what + ": not sent - HTTP " + r.status + " was the answer " + Math.round((Date.now() - r.t) / 60000)
            + " min ago, next try in " + Math.max(1, Math.round((r.until - Date.now()) / 60000)) + " min (manual refresh: at once)");
}

/** The first refusal when EVERY provider of the chain is under one, else null (a single network
 *  failure in the chain still deserves the quick retries). */
function allRefused(chain) {
    if (!chain || chain.length === 0)
        return null;
    var first = null;
    for (var i = 0; i < chain.length; ++i) {
        var r = active(chain[i]);
        if (!r)
            return null;
        if (!first)
            first = r;
    }
    return first;
}

function clear() {
    _items = {};
}
