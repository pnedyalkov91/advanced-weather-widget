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
 * aemet.js - AEMET OpenData (Agencia Estatal de Meteorología, Spain)
 * current + hourly fetcher.
 *
 * Non-pragma JS - accesses config via service properties.
 * Qt global is available; Plasmoid/i18n/Locale are NOT (use service instead).
 * W (weather.js) is passed as a parameter by the caller.
 *
 * SPAIN ONLY: AEMET has zero coverage outside Spain. Every entry point below
 * re-checks service._isSpainLocation() itself (via _resolveMunicipio) rather
 * than trusting the caller, since this module can be reached either through
 * the "adaptive" chain (already gated to Spain by WeatherService.refreshNow)
 * or by the user explicitly picking "aemet" as weatherProvider for a
 * non-Spain location - the latter has no upstream gate.
 *
 * Requires a free API key from
 * https://opendata.aemet.es/centrodedescargas/altaUsuario - stored as
 * Plasmoid.configuration.aemetApiKey and read via service._aemetKey().
 *
 * TWO QUIRKS THAT ARE EASY TO GET WRONG AND HAVE NO IN-BAND DOCUMENTATION:
 *
 * 1. The prediccion/especifica/* endpoints are "self-discovery" pointers,
 *    not the payload itself: the first GET returns
 *    {"estado":200,"datos":"<url>","metadatos":"<url>"} and the real JSON
 *    lives at the "datos" URL, which must be fetched with a second,
 *    separate GET. That URL is short-lived/single-use - it is never cached
 *    or reused across refreshes; _fetchAemetJson() below redoes both hops
 *    every single call.
 *    The /api/maestro/* family does NOT work this way: municipios (and
 *    municipio/{id}) return the payload directly in the first response.
 *    _fetchAemetJson() therefore branches on whether "datos" is actually
 *    present rather than assuming it always is.
 *
 * 2. The payload at the "datos" URL is encoded ISO-8859-15, per a captured
 *    real response's declared Content-Type - close enough to plain
 *    ISO-8859-1/Latin-1 that it makes no visible difference for Spanish
 *    text specifically (none of á/é/í/ó/ú/ñ/¿/¡ fall in the handful of
 *    symbol slots the two encodings disagree on) - not UTF-8, and every one
 *    of those characters in sky-condition descriptions and place names
 *    comes back mangled without correcting for this. overrideMimeType() is
 *    used to force the correct decoding; it requires Qt 6.6+ (Plasma 6's
 *    XMLHttpRequest gained it "since 6.6"), so the call is wrapped in
 *    try/catch and degrades to (slightly garbled) UTF-8 on older Qt rather
 *    than failing the request outright. The charset actually requested is
 *    ISO-8859-1, not -15, because Qt 6 only recognises the former - see
 *    AEMET_CHARSET below for why that makes no difference here.
 *
 * MUNICIPALITY RESOLUTION: forecasts are requested by 5-digit INE municipio
 * code, not lat/lon. There is no reverse-geocoding endpoint on AEMET's side,
 * so the ~8,100-entry /api/maestro/municipios master list is fetched once
 * per session (cached on service._aemetMunicipios - see the "Provider-side
 * staging buffers" properties in WeatherService.qml) and the nearest entry
 * to the configured coordinates is picked via Haversine distance. The
 * master list's own "id" field is prefixed ("id28079") and must have that
 * prefix stripped before use in a forecast URL (confirmed against AEMET's
 * own municipio page URLs, e.g. .../municipios/madrid-id28079).
 *
 * FIELD NAMES VERIFIED AGAINST: AEMET's own schema-description ("sh/...")
 * documents - fetched directly (they need no API key, unlike the actual data
 * endpoints): https://opendata.aemet.es/opendata/sh/dfd88b22 (daily) and
 * https://opendata.aemet.es/opendata/sh/93a7c63d (hourly) - which is how an
 * earlier inference-based mistake here got caught: wind was originally
 * modelled as one combined "vientoAndRachaMax" entry (a name that turned out
 * to be a downstream R package's tidied *column* name, not an AEMET JSON
 * key). AEMET actually keeps them separate on both endpoints - "viento"
 * ({periodo, direccion, velocidad}, hour-keyed on the hourly endpoint,
 * 6-hour-block-keyed on daily) and "rachaMax" ({periodo, value}, always
 * 6-hour-block-keyed, gust only, not currently surfaced by this module).
 * Also caught by the same documents: "uvMax" is a single-entry array
 * ([{value}]), not a bare scalar, and the hourly endpoint's
 * "probPrecipitacion" is keyed by 6-hour blocks in "HHHH" form (e.g. "0107"
 * = 01:00-07:00), not by hour - see _rangeContainsHour(). Secondary,
 * non-authoritative cross-checks: the Go client github.com/rubiojr/aemet-go,
 * the Python client github.com/pablo-moreno/python-aemet, and
 * PranshulGG/WeatherMaster#1030 (a Kotlin implementation tested against real
 * endpoints with a real key, and also where the ISO-8859-15 charset above
 * comes from).
 */

// ── Geometry helpers ─────────────────────────────────────────────────────

function _haversineKm(lat1, lon1, lat2, lon2) {
    var R = 6371;
    var dLat = (lat2 - lat1) * Math.PI / 180;
    var dLon = (lon2 - lon1) * Math.PI / 180;
    var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Parses an AEMET-style compact sexagesimal coordinate string ("394924N",
 * "025309E") into decimal degrees. Only used as a fallback when a municipio
 * entry's latitud_dec/longitud_dec fields (see _muniLat/_muniLon) are
 * missing - the master list normally provides decimal degrees directly.
 */
function _dmsToDecimal(coord) {
    if (!coord) return NaN;
    var s = String(coord).trim();
    if (s.length < 7) return NaN;
    var dir = s.charAt(s.length - 1).toUpperCase();
    var digits = s.substring(0, s.length - 1);
    var deg = parseInt(digits.substring(0, 2), 10);
    var min = parseInt(digits.substring(2, 4), 10);
    var sec = parseInt(digits.substring(4, 6), 10);
    if (isNaN(deg) || isNaN(min) || isNaN(sec)) return NaN;
    var dec = deg + min / 60 + sec / 3600;
    return (dir === "S" || dir === "W") ? -dec : dec;
}

function _muniLat(entry) {
    var v = parseFloat(entry.latitud_dec);
    return isNaN(v) ? _dmsToDecimal(entry.latitud) : v;
}
function _muniLon(entry) {
    var v = parseFloat(entry.longitud_dec);
    return isNaN(v) ? _dmsToDecimal(entry.longitud) : v;
}

function _nearestMunicipio(list, lat, lon) {
    var best = null, bestDist = Infinity;
    for (var i = 0; i < list.length; i++) {
        var e = list[i];
        var mLat = _muniLat(e), mLon = _muniLon(e);
        if (isNaN(mLat) || isNaN(mLon)) continue;
        var d = _haversineKm(lat, lon, mLat, mLon);
        if (d < bestDist) { bestDist = d; best = e; }
    }
    return best;
}

function _roundKey(lat, lon) {
    return Number(lat).toFixed(2) + "," + Number(lon).toFixed(2);
}

// ── Location-local time ──────────────────────────────────────────────────

/**
 * AEMET's hourly "periodo" values are in the forecast location's own wall
 * clock, not UTC and not the machine running this widget's clock - using
 * (new Date()).getHours() directly picks the WRONG hour's reading whenever
 * the widget's system timezone differs from the configured location's (e.g.
 * checking Madrid from a machine set to Sofia time is a real, easy-to-hit
 * one-hour-plus offset, and grows far larger for e.g. Canary Islands
 * locations at UTC+0/+1 checked from central Europe). service.timezone is
 * the IANA zone name already resolved for the active location (see
 * WeatherService.qml's `timezone` property, filled in by the same location
 * search that resolves countryCode) - Intl.DateTimeFormat with that zone
 * gives the correct local hour directly and handles DST automatically.
 * Falls back to the system clock if timezone is unset or Intl throws.
 */
function _locationHourString(service) {
    var tz = service.timezone;
    if (tz) {
        try {
            var fmt = new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", hourCycle: "h23" });
            var hn = parseInt(fmt.format(new Date()), 10);
            if (!isNaN(hn))
                return ("0" + (hn % 24)).slice(-2);
        } catch (e) {
            // Unknown/unsupported IANA zone, or Intl unavailable - fall through.
        }
    }
    return ("0" + (new Date()).getHours()).slice(-2);
}

/**
 * Current UTC offset in whole hours for the forecast location, derived by
 * comparing its local hour (above) against the UTC hour right now - this
 * naturally accounts for DST without separately tracking it. Needed because
 * AEMET's own documentation (aemet.es/en/eltiempo/prediccion/municipios/
 * ayuda) states plainly that "six-hourly intervals or greater correspond to
 * UTC times" - only the hour-by-hour "01".."23" timeline is already local.
 * That means the 6-hour-block period keys (daily's estadoCielo/viento/
 * rachaMax, hourly's probPrecipitacion/probTormenta/probNieve/rachaMax) need
 * shifting by this offset before comparing against a local hour; the
 * hour-keyed fields (temperatura, humedadRelativa, hourly's viento/
 * estadoCielo/precipitacion) do not and are untouched by this.
 */
function _locationUtcOffsetHours(service) {
    var localH = parseInt(_locationHourString(service), 10);
    var utcH = (new Date()).getUTCHours();
    var diff = localH - utcH;
    if (diff > 12) diff -= 24;
    if (diff < -12) diff += 24;
    return diff;
}

/** Today's date, as YYYY-MM-DD, in the forecast location's own timezone -
 *  same fallback behavior as _locationHourString. */
/** Today's date, as YYYY-MM-DD, in the forecast location's own timezone -
 *  same fallback behavior as _locationHourString. Built from formatToParts()
 *  rather than trusting en-CA's default separator/ordering to stay
 *  "YYYY-MM-DD" on every ICU build - a locale-format mismatch here would
 *  make _alignDaysToToday's string comparison silently wrong, potentially
 *  filtering out every entry (including today) and turning into a hard
 *  "Failed: AEMET" for a reason that has nothing to do with AEMET itself. */
function _locationDateString(service) {
    var tz = service.timezone;
    if (tz) {
        try {
            var parts = new Intl.DateTimeFormat("en-US", {
                timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit"
            }).formatToParts(new Date());
            var y, m, dd;
            parts.forEach(function (p) {
                if (p.type === "year") y = p.value;
                else if (p.type === "month") m = p.value;
                else if (p.type === "day") dd = p.value;
            });
            if (y && m && dd) return y + "-" + m + "-" + dd;
        } catch (e) {
            // Unknown/unsupported IANA zone, formatToParts unavailable, or Intl unavailable - fall through.
        }
    }
    var d = new Date();
    return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2);
}

/**
 * Drops any leading entries in a "dia" array that are dated before today in
 * the forecast location's timezone, so index 0 is reliably today rather
 * than whatever AEMET's own elaboration schedule happens to have as its
 * first entry. This is what was behind "today's forecast is broken" /
 * "Today" showing yesterday's date and yesterday's evening hours: AEMET's
 * product doesn't roll its own dia[0] over onto the new calendar day
 * exactly at local midnight, so for a window after midnight (length
 * unconfirmed - could be anywhere from minutes to a few hours depending on
 * their elaboration schedule) dia[0] can still legitimately be yesterday.
 * Every other place in this file already keys off dateStr/fecha rather than
 * a bare array index, so this one alignment step is enough to fix it
 * everywhere index 0 is used as "today" (current-conditions, UV backfill,
 * sunrise/sunset, and the daily array itself all flow through here).
 */
function _alignDaysToToday(dias, service) {
    if (!dias || dias.length === 0) return dias;
    var todayStr = _locationDateString(service);
    for (var i = 0; i < dias.length; i++) {
        if ((dias[i].fecha || "").substr(0, 10) >= todayStr)
            return dias.slice(i);
    }
    return dias; // nothing matched today-or-later - return as-is rather than empty
}

// ── Numeric helpers ──────────────────────────────────────────────────────

// AEMET represents "no data" as either a missing key or a bare null,
// depending on the field - route every field access through this so a null
// doesn't silently become 0 on a QML "real" property (see the identical
// concern/fix documented in openMeteo.js's _num()).
function _num(v) {
    return (v === null || v === undefined || (typeof v === "number" && isNaN(v))) ? NaN : v;
}

function _aemetDirToDegrees(dir, W) {
    if (!dir) return NaN;
    var d = String(dir).toUpperCase().trim();
    if (d === "C") return NaN; // "Calma" (calm) - no defined direction
    return W.compassToDegrees(d);
}

/** The calendar date (YYYY-MM-DD) immediately after dateStr, in the widget's
 *  own local time - used to append the closing 00:00 entry so the hourly
 *  forecast reads 00:00..00:00 instead of stopping at 23:00. */
function _nextDateStr(dateStr) {
    var d = new Date(dateStr + "T00:00:00");
    d.setDate(d.getDate() + 1);
    return Qt.formatDate(d, "yyyy-MM-dd");
}

// ── Two-step "self-discovery" fetch shared by every AEMET endpoint ───────

/**
 * ISO-8859-1, not the ISO-8859-15 AEMET actually declares. Qt 6 replaced
 * QTextCodec with QStringConverter, which only knows UTF-8/16/32, Latin-1
 * and System - and an unrecognised charset name is NOT an error there:
 * QQmlXMLHttpRequest::findTextDecoder() silently falls through to
 * QStringDecoder(Utf8). So asking for "ISO-8859-15" got UTF-8 decoding of
 * Latin-1 bytes (mojibake in place names) rather than the graceful
 * degradation the try/catch was meant to provide. The two encodings differ
 * only in a handful of symbol slots - none of á/é/í/ó/ú/ñ/¿/¡ - so
 * Latin-1 is exactly right for Spanish text and is a name Qt recognises.
 */
var AEMET_CHARSET = "text/plain; charset=ISO-8859-1";

/**
 * `service` is threaded through purely so a 429 on either hop can be
 * recorded (service._aemetRateLimited) - AEMET returns this when its
 * documented ~50 req/min-per-key limit is hit, and without flagging it
 * specifically, a rate-limited refresh looked identical to any other
 * failure ("Failed: AEMET"), with no way for the person to tell "wait a
 * moment" apart from "something is actually broken".
 */
function _fetchAemetJson(url, service, cb) {
    var meta = new XMLHttpRequest();
    meta.open("GET", url);
    try { meta.overrideMimeType(AEMET_CHARSET); } catch (e) {}
    meta.onreadystatechange = function () {
        if (meta.readyState !== XMLHttpRequest.DONE) return;
        if (meta.status === 429) { service._aemetRateLimited = true; service.weatherRoot.aemetRateLimited = true; cb(null); return; }
        if (meta.status !== 200) { cb(null); return; }
        var ptr;
        try { ptr = JSON.parse(meta.responseText); } catch (e) { cb(null); return; }

        // NOT every endpoint is a two-step pointer, despite what the header
        // comment above used to claim unconditionally: the /api/maestro/*
        // family (municipios, municipio/{id}) answers with the payload
        // itself in this first response. Demanding {estado, datos} here made
        // the municipio master-list fetch fail 100% of the time, which - via
        // the empty-list cache in _withMunicipiosList - failed every AEMET
        // refresh for the rest of the session. So: follow "datos" only when
        // it is actually there, otherwise treat this body AS the payload.
        if (!ptr || typeof ptr.datos !== "string") {
            // An error body ({"estado":404,"descripcion":"..."}) is not a
            // payload - only a missing/200 estado means "this is the data".
            if (ptr && ptr.estado !== undefined && ptr.estado !== 200) { cb(null); return; }
            cb(ptr);
            return;
        }

        // The "datos" pointer is short-lived and single-use - always fetch
        // it fresh, right now, never cache/reuse it across refreshes.
        var data = new XMLHttpRequest();
        data.open("GET", ptr.datos);
        try { data.overrideMimeType(AEMET_CHARSET); } catch (e) {}
        data.onreadystatechange = function () {
            if (data.readyState !== XMLHttpRequest.DONE) return;
            if (data.status === 429) { service._aemetRateLimited = true; service.weatherRoot.aemetRateLimited = true; cb(null); return; }
            if (data.status !== 200) { cb(null); return; }
            try { cb(JSON.parse(data.responseText)); }
            catch (e) { cb(null); }
        };
        data.send();
    };
    meta.send();
}

/**
 * Wraps _fetchAemetJson with a single immediate retry on failure - except
 * when the failure was a 429, where retrying straight back into the same
 * rate limit would just waste another request. AEMET's OpenData API is
 * rate-limited (documented ~50 req/min per key) and a full AEMET refresh
 * needs several two-hop requests in the same short window (municipio list,
 * daily, hourly), so an occasional transient failure (dropped connection,
 * brief server hiccup) is a real, recurring possibility here specifically,
 * not just a hard error. This is what was behind "sometimes the hourly
 * forecast isn't loaded" / "sometimes I get different data on refresh" - a
 * soft hourly failure was silently falling back to the coarser
 * daily-derived baseline (see _currentFromDailyDay), which reads
 * differently on purpose. One retry, not a loop: a genuinely bad key or a
 * real outage still fails and lets the provider chain move on normally.
 */
function _fetchAemetJsonR(url, service, cb) {
    _fetchAemetJson(url, service, function (result) {
        if (result !== null) { cb(result); return; }
        if (service._aemetRateLimited) { cb(null); return; }
        _fetchAemetJson(url, service, cb);
    });
}

// ── Municipality resolution (cached on `service`, see WeatherService.qml
//    "Provider-side staging buffers") ─────────────────────────────────────

/**
 * Ensures service._aemetMunicipios holds the ~8,100-entry master list, then
 * calls cb(list) - fetching it at most once per session. ForecastView's
 * "expand all days" mode can trigger several resolutions back-to-back
 * before the first lands, and AEMET's API is rate-limited, so concurrent
 * callers queue behind a single in-flight fetch (service._aemetMuniListPending)
 * instead of each firing their own ~1 MB two-step request.
 */
function _withMunicipiosList(service, key, cb) {
    if (service._aemetMunicipios) { cb(service._aemetMunicipios); return; }
    if (service._aemetMuniListPending) {
        service._aemetMuniListPending.push(cb);
        return;
    }
    service._aemetMuniListPending = [cb];
    var url = "https://opendata.aemet.es/opendata/api/maestro/municipios/?api_key=" + encodeURIComponent(key);
    _fetchAemetJsonR(url, service, function (list) {
        var waiters = service._aemetMuniListPending || [];
        service._aemetMuniListPending = null;
        var arr = Array.isArray(list) ? list : [];
        // Cache ONLY a real list. [] is truthy, so caching a failed fetch
        // made the `if (service._aemetMunicipios)` short-circuit at the top
        // of this function hit forever after: every later refresh - the
        // _aemetAutoRetryTimer's included - resolved instantly to an empty
        // list without touching the network, and AEMET stayed broken until
        // Plasma itself was restarted.
        if (arr.length > 0) service._aemetMunicipios = arr;
        waiters.forEach(function (w) { w(arr); });
    });
}

// AEMET regenerates these products only "cuatro veces al día" (4x/day) per
// its own schema docs, aside from temperature which "pueden actualizarse
// más a menudo" - refetching every 10-15 minutes (a typical widget refresh
// interval) is mostly re-requesting data that hasn't changed at all. A
// generation-scoped cache alone (below) only dedupes calls within one
// refresh; this time-based one also skips the network entirely on refreshes
// that land within the window, which is the single biggest lever on
// request volume for a personal widget's normal (non-testing) usage.
var AEMET_CACHE_TTL_MS = 20 * 60 * 1000; // 20 minutes

/**
 * Ensures the daily product for `muniId` has been fetched within the last
 * AEMET_CACHE_TTL_MS, then calls cb(rawResponseOrNull). Time-based (not
 * generation-based) so it also serves refreshes that land within the
 * window, not just concurrent calls within one.
 */
function _withDailyData(service, key, muniId, cb) {
    var cache = service._aemetDailyCache;
    if (cache && cache.muniId === muniId && (Date.now() - cache.ts) < AEMET_CACHE_TTL_MS) {
        cb(cache.data);
        return;
    }
    var pending = service._aemetDailyPending;
    if (pending && pending.muniId === muniId) {
        pending.callbacks.push(cb);
        return;
    }
    service._aemetDailyPending = { muniId: muniId, callbacks: [cb] };
    _fetchAemetJsonR(_forecastBaseUrl("diaria", muniId, key), service, function (d) {
        var p = service._aemetDailyPending;
        service._aemetDailyPending = null;
        // Successes only. Caching a null alongside a fresh timestamp meant a
        // single transient failure bought AEMET_CACHE_TTL_MS of guaranteed
        // "Failed: AEMET" - served straight from the cache, with no network
        // attempt at all - which is what made this look intermittent
        // ("works, then just stops for a while") rather than broken.
        if (d) service._aemetDailyCache = { muniId: muniId, ts: Date.now(), data: d };
        var waiters = (p && p.muniId === muniId) ? p.callbacks : [cb];
        waiters.forEach(function (w) { w(d); });
    });
}

/**
 * Same as _withDailyData, for the hourly product - shared by fetchCurrent
 * (current-conditions refinement), fetchHourly (a single expanded day) and
 * fetchHourlyDirect ("expand all days"). Before this, each of those fired
 * its own independent two-hop request for the exact same ~48h product -
 * expanding all 7 days meant 7 redundant fetches (5 of which could only
 * ever come back empty, since AEMET's hourly product only covers
 * today+tomorrow) against an API rate-limited to ~50 req/min. Now every
 * caller shares one fetch (or queues behind one already in flight, or
 * reuses one from the last AEMET_CACHE_TTL_MS), so "expand all" costs at
 * most the one hourly request fetchCurrent already needed, not seven more.
 */
function _withHourlyData(service, key, muniId, cb) {
    var cache = service._aemetHourlyCache;
    if (cache && cache.muniId === muniId && (Date.now() - cache.ts) < AEMET_CACHE_TTL_MS) {
        cb(cache.data);
        return;
    }
    var pending = service._aemetHourlyPending;
    if (pending && pending.muniId === muniId) {
        pending.callbacks.push(cb);
        return;
    }
    service._aemetHourlyPending = { muniId: muniId, callbacks: [cb] };
    _fetchAemetJsonR(_forecastBaseUrl("horaria", muniId, key), service, function (hd) {
        var p = service._aemetHourlyPending;
        service._aemetHourlyPending = null;
        if (hd) service._aemetHourlyCache = { muniId: muniId, ts: Date.now(), data: hd }; // successes only - see _withDailyData
        var waiters = (p && p.muniId === muniId) ? p.callbacks : [cb];
        waiters.forEach(function (w) { w(hd); });
    });
}

/** Resolves the nearest municipio's plain (no "id" prefix) INE code for the
 *  service's current lat/lon, then calls cb(id) or cb(null) on failure/
 *  non-Spain location. Result is cached keyed by rounded coordinates, like
 *  BBC's _bbcLocId/_bbcLocKey pattern, so repeat refreshes for the same
 *  location skip both the list fetch and the nearest-match scan - and, via
 *  service._persistAemetMunicipio(), is written through to
 *  Plasmoid.configuration so it also survives a Plasma restart. That last
 *  part is what takes the ~1 MB master-list download from once-per-session
 *  to once-per-location-ever, leaving a steady-state refresh at just the
 *  daily + hourly products.
 *
 *  `gen` is accepted for call-site symmetry but deliberately NOT used as a
 *  bail-out condition. It used to be, and that contradicted fetchHourly's
 *  own documented "don't abandon on a stale generation" behaviour: the
 *  check `return`ed without ever invoking cb, so a background refresh tick
 *  landing mid-resolution left an expanded Forecast day spinning forever.
 *  Nothing here is generation-sensitive anyway - the municipio is derived
 *  from the live coordinates on every call, so a late resolution is still
 *  the right answer for the still-configured location. */
function _resolveMunicipio(service, gen, key, cb) {
    if (!service._isSpainLocation()) { cb(null); return; }

    var rk = _roundKey(service.latitude, service.longitude);
    if (service._aemetMuniKey === rk && service._aemetMuniId) {
        cb(service._aemetMuniId);
        return;
    }

    _withMunicipiosList(service, key, function (list) {
        if (!list || list.length === 0) { cb(null); return; }
        var nearest = _nearestMunicipio(list, service.latitude, service.longitude);
        if (!nearest) { cb(null); return; }
        var id = String(nearest.id || "").replace(/^id/, "");
        if (!id) { cb(null); return; }
        service._aemetMuniKey = rk;
        service._aemetMuniId = id;
        if (typeof service._persistAemetMunicipio === "function")
            service._persistAemetMunicipio(rk, id);
        cb(id);
    });
}

// ── Field extraction shared by the daily/hourly parsers ─────────────────

function _findByPeriod(arr, key) {
    if (!arr) return null;
    for (var i = 0; i < arr.length; i++) {
        // Some AEMET fields key their per-slot entries "periodo", others
        // "hora" - climaemet's own (live-API-tested) parser checks both
        // names rather than assuming one, so this does too.
        var p = (arr[i].periodo !== undefined) ? arr[i].periodo : arr[i].hora;
        if (String(p) === String(key)) return arr[i];
    }
    return null;
}

/** Like _findByPeriod, but when there's no exact match for `hourStr` it
 *  falls back to the entry for the nearest earlier hour (wrapping past
 *  midnight), and failing that, the last entry in the array - used to pick
 *  a "right now" reading from a hh-keyed array that may not literally
 *  contain the current hour (e.g. right after the day rolls over, before
 *  AEMET's next elaboration lands). */
function _nearestHourEntry(arr, hourStr) {
    if (!arr || arr.length === 0) return null;
    var exact = _findByPeriod(arr, hourStr);
    if (exact) return exact;
    var wanted = parseInt(hourStr, 10);
    var best = null, bestDiff = Infinity;
    arr.forEach(function (e) {
        var p = (e.periodo !== undefined) ? e.periodo : e.hora;
        var h = parseInt(p, 10);
        if (isNaN(h)) return;
        var diff = wanted - h;
        if (diff < 0) diff += 24; // wrap - prefer the most recent past hour
        if (diff < bestDiff) { bestDiff = diff; best = e; }
    });
    return best || arr[arr.length - 1];
}

/**
 * Picks a single representative entry out of a day's period-block array
 * (estadoCielo/viento/rachaMax on the daily product). Days 3-7 use one
 * "00-24" block covering the whole day; days 1-2 are split into finer
 * 6-hour blocks instead ("00-06", "06-12", "12-18", "18-24", ...) with no
 * "00-24" entry at all - for those, midday ("12-18"/"12-24") is preferred
 * over just taking the first block, which would otherwise silently pick an
 * overnight ("00-06") reading (and icon) to represent the whole day.
 */
function _pickDayPeriodEntry(arr) {
    if (!arr || arr.length === 0) return null;
    return _findByPeriod(arr, "00-24") || _findByPeriod(arr, "12-18")
        || _findByPeriod(arr, "12-24") || arr[0];
}

function _maxValue(arr) {
    if (!arr || arr.length === 0) return NaN;
    var m = NaN;
    for (var i = 0; i < arr.length; i++) {
        var v = _num(arr[i].value);
        if (!isNaN(v) && (isNaN(m) || v > m)) m = v;
    }
    return m;
}

/** True when `hour` (0-23, local) falls inside a 6-hour-block period key in
 *  compact "HHHH" form (e.g. "0107" = 01:00-07:00, "1901" = 19:00-01:00
 *  wrapping past midnight). Per AEMET's own documentation, these blocks are
 *  in UTC, so utcOffsetHours (see _locationUtcOffsetHours) shifts them to
 *  local before comparing - distinct from the hour-by-hour "01".."23" keys
 *  most other hourly fields use, which are already local. */
function _rangeContainsHour(rangeKey, hour, utcOffsetHours) {
    if (!rangeKey || rangeKey.length !== 4) return false;
    var start = parseInt(rangeKey.substring(0, 2), 10);
    var end = parseInt(rangeKey.substring(2, 4), 10);
    if (isNaN(start) || isNaN(end)) return false;
    start = (start + utcOffsetHours + 24) % 24;
    end = (end + utcOffsetHours + 24) % 24;
    if (start <= end) return hour >= start && hour < end;
    return hour >= start || hour < end; // wraps past midnight
}

function _precipProbForHour(arr, hourStr, utcOffsetHours) {
    if (!arr) return null;
    var h = parseInt(hourStr, 10);
    for (var i = 0; i < arr.length; i++) {
        if (_rangeContainsHour(String(arr[i].periodo || ""), h, utcOffsetHours))
            return arr[i];
    }
    return null;
}

/** AEMET's uvMax is oddly a single-entry array ([{value}]) rather than a
 *  bare scalar, unlike every sibling field in the same "dia" object. */
function _uvMaxValue(day) {
    return (day.uvMax && day.uvMax[0]) ? _num(day.uvMax[0].value) : NaN;
}

// ── Daily ("diaria", 7-day) parsing ──────────────────────────────────────

function _buildDailyArray(dias, forecastDays, W) {
    var nd = [];
    var maxD = Math.min(forecastDays, dias.length);
    for (var i = 0; i < maxD; i++) {
        var day = dias[i];
        var temp = day.temperatura || {};
        var skyEntry = _pickDayPeriodEntry(day.estadoCielo);
        var windEntry = _pickDayPeriodEntry(day.viento);
        nd.push({
            day: Qt.formatDate(new Date(day.fecha), "ddd"),
            dateStr: (day.fecha || "").substr(0, 10),
            maxC: _num(temp.maxima),
            minC: _num(temp.minima),
            code: W.aemetSkyToWmo(skyEntry ? skyEntry.value : ""),
            precipMm: W.NOT_SUPPORTED, // daily product gives a rain probability, not an accumulated mm figure
            snowCm: W.NOT_SUPPORTED,   // AEMET's only snow-related daily field is snow-line elevation, not accumulation
            precipProb: _maxValue(day.probPrecipitacion),
            windKmh: windEntry ? _num(windEntry.velocidad) : NaN,
            windDir: windEntry ? _aemetDirToDegrees(windEntry.direccion, W) : NaN,
            uvMax: _uvMaxValue(day),
            pressureHpa: W.NOT_SUPPORTED, // not in any AEMET municipio forecast product
            visibilityKm: W.NOT_SUPPORTED // not in any AEMET municipio forecast product
        });
    }
    return nd;
}

/**
 * Degraded "current conditions" derived ONLY from the daily product's
 * today entry - used solely as a last-resort baseline if the separate
 * hourly request (see _currentFromHourlyDay) fails outright, which should
 * be rare (same key, same municipio, same API). Daily has no true
 * instantaneous reading, so this picks today's max or min depending on
 * whether it's currently day or night (in the forecast location's own
 * timezone - see _locationHourString) as a rough stand-in rather than
 * leaving the "current" fields blank.
 */
function _currentFromDailyDay(day, W, service) {
    var temp = day.temperatura || {};
    var sens = day.sensTermica || {};
    var hum = day.humedadRelativa || {};
    var hourNow = parseInt(_locationHourString(service), 10);
    var isDaytime = hourNow >= 8 && hourNow < 21;
    var skyEntry = _pickDayPeriodEntry(day.estadoCielo);
    var windEntry = _pickDayPeriodEntry(day.viento);
    var t = isDaytime ? _num(temp.maxima) : _num(temp.minima);
    var h = isDaytime ? _num(hum.minima) : _num(hum.maxima); // humidity runs roughly inverse to temperature through the day
    return {
        temperatureC: t,
        apparentC: isDaytime ? _num(sens.maxima) : _num(sens.minima),
        humidityPercent: h,
        pressureHpa: W.NOT_SUPPORTED, // not in any AEMET municipio forecast product
        windKmh: windEntry ? _num(windEntry.velocidad) : NaN,
        windDirection: windEntry ? _aemetDirToDegrees(windEntry.direccion, W) : NaN,
        dewPointC: W.dewPoint(t, h),
        visibilityKm: W.NOT_SUPPORTED, // not in any AEMET municipio forecast product
        precipMmh: W.NOT_SUPPORTED,    // daily-only fallback has no per-hour precip amount, only a daily rain probability
        uvIndex: _uvMaxValue(day),
        snowDepthCm: W.NOT_SUPPORTED,  // AEMET's only snow-related field is snow-line elevation, not accumulation/cover
        weatherCode: W.aemetSkyToWmo(skyEntry ? skyEntry.value : ""),
        isDay: isDaytime ? 1 : 0,
        locationUtcOffsetMins: 0,
        sunriseTimeText: "--",
        sunsetTimeText: "--",
        dailyData: []
    };
}

// ── Hourly ("horaria", ~48h) parsing ─────────────────────────────────────

/** Primary "current conditions" source: the hourly product's entry nearest
 *  the current local hour (in the forecast location's own timezone - see
 *  _locationHourString). Returns null (letting the caller keep the daily
 *  baseline) if neither temperature nor sky data is available at all. */
function _currentFromHourlyDay(today, W, service) {
    var hourStr = _locationHourString(service);
    var sky  = _nearestHourEntry(today.estadoCielo, hourStr);
    var temp = _nearestHourEntry(today.temperatura, hourStr);
    var sens = _nearestHourEntry(today.sensTermica, hourStr);
    var hum  = _nearestHourEntry(today.humedadRelativa, hourStr);
    var wind = _nearestHourEntry(today.viento, hourStr);
    var precip = _nearestHourEntry(today.precipitacion, hourStr);

    if (!temp && !sky) return null;

    var t = temp ? _num(temp.value) : NaN;
    var h = hum ? _num(hum.value) : NaN;
    return {
        temperatureC: t,
        apparentC: sens ? _num(sens.value) : NaN,
        humidityPercent: h,
        pressureHpa: W.NOT_SUPPORTED, // not in any AEMET municipio forecast product
        windKmh: wind ? _num(wind.velocidad) : NaN,
        windDirection: wind ? _aemetDirToDegrees(wind.direccion, W) : NaN,
        dewPointC: W.dewPoint(t, h),
        visibilityKm: W.NOT_SUPPORTED, // not in any AEMET municipio forecast product
        precipMmh: precip ? _num(precip.value) : 0,
        uvIndex: NaN, // not exposed hourly - left as NaN (not NOT_SUPPORTED) so fetchCurrent's
                       // combine() step backfills it from today's daily uvMax; NOT_SUPPORTED
                       // would defeat that isNaN() check, since -9999 isn't NaN
        snowDepthCm: W.NOT_SUPPORTED, // AEMET's only snow-related field is snow-line elevation, not accumulation/cover
        weatherCode: W.aemetSkyToWmo(sky ? sky.value : ""),
        isDay: W.aemetSkyIsDay(sky ? sky.value : ""),
        locationUtcOffsetMins: 0,
        sunriseTimeText: "--",
        sunsetTimeText: "--",
        dailyData: []
    };
}

function _buildHourlyArray(day, W, service) {
    var arr = [];
    var hours = {};
    var utcOffsetHours = _locationUtcOffsetHours(service);
    // Only hour-keyed fields ("01".."23") feed the hour index -
    // probPrecipitacion uses 6-hour "HHHH" blocks instead (see
    // _rangeContainsHour) and is looked up per-hour separately below, not
    // unioned in here (its block keys aren't valid hours).
    ["estadoCielo", "temperatura", "viento", "humedadRelativa",
     "precipitacion"].forEach(function (field) {
        var a = day[field];
        if (!a) return;
        a.forEach(function (e) {
            var p = (e.periodo !== undefined) ? e.periodo : e.hora;
            if (p !== undefined) hours[p] = true;
        });
    });
    Object.keys(hours).sort().forEach(function (h) {
        var sky   = _findByPeriod(day.estadoCielo, h);
        var temp  = _findByPeriod(day.temperatura, h);
        var wind  = _findByPeriod(day.viento, h);
        var hum   = _findByPeriod(day.humedadRelativa, h);
        var pMm   = _findByPeriod(day.precipitacion, h);
        var pProb = _precipProbForHour(day.probPrecipitacion, h, utcOffsetHours);
        arr.push({
            hour: (h.length === 2) ? (h + ":00") : h,
            tempC: temp ? _num(temp.value) : NaN,
            code: W.aemetSkyToWmo(sky ? sky.value : ""),
            windKmh: wind ? _num(wind.velocidad) : NaN,
            windDeg: wind ? _aemetDirToDegrees(wind.direccion, W) : NaN,
            humidity: hum ? _num(hum.value) : NaN,
            precipProb: pProb ? _num(pProb.value) : NaN,
            precipMm: pMm ? _num(pMm.value) : NaN
        });
    });
    return arr;
}

function _forecastBaseUrl(kind, muniId, key) {
    return "https://opendata.aemet.es/opendata/api/prediccion/especifica/municipio/"
        + kind + "/" + encodeURIComponent(muniId) + "?api_key=" + encodeURIComponent(key);
}

// ── Public entry points (dispatched from Providers.qml) ─────────────────

function fetchCurrent(service, W, chain, idx) {
    var gen = service._refreshGen;
    var key = service._aemetKey();
    if (!key) { service._tryProvider(chain, idx + 1); return; }
    service._aemetRateLimited = false; // fresh attempt - don't judge it by a previous one's rate limit
    service.weatherRoot.aemetRateLimited = false;

    _resolveMunicipio(service, gen, key, function (muniId) {
        if (service._refreshGen !== gen) return;
        if (!muniId) { service._tryProvider(chain, idx + 1); return; }

        // Daily and hourly are independent AEMET products, each its own
        // two-hop request - fetched in parallel rather than daily-then-
        // hourly so a slow hop on one doesn't add its full latency on top
        // of the other's (this alone was often enough to make a provider
        // switch or manual refresh look "stuck" until a second tap).
        // undefined = still pending, null = failed, object = parsed body.
        var dailyResult, hourlyResult;

        function combine() {
            if (dailyResult === undefined || hourlyResult === undefined) return;
            if (service._refreshGen !== gen) return;
            // The two products are independent requests against the same API -
            // there is no reason a daily failure should throw away a hourly
            // response that arrived perfectly well (and the hourly one is the
            // better source for current conditions anyway). Only give up on
            // the provider when BOTH came back empty.
            if (!dailyResult && !hourlyResult) { service._tryProvider(chain, idx + 1); return; }

            var dias = [];
            if (dailyResult) {
                var root = Array.isArray(dailyResult) ? dailyResult[0] : dailyResult;
                var rawDias = (root && root.prediccion && root.prediccion.dia) ? root.prediccion.dia : [];
                dias = _alignDaysToToday(rawDias, service);
            }

            var nd = dias.length > 0 ? _buildDailyArray(dias, service.forecastDays, W) : [];
            var finalCur = dias.length > 0 ? _currentFromDailyDay(dias[0], W, service) : null;
            var sun = null;

            if (hourlyResult) {
                var hroot = Array.isArray(hourlyResult) ? hourlyResult[0] : hourlyResult;
                var hdias = (hroot && hroot.prediccion && hroot.prediccion.dia) ? hroot.prediccion.dia : [];
                hdias = _alignDaysToToday(hdias, service);
                if (hdias.length > 0) {
                    var refined = _currentFromHourlyDay(hdias[0], W, service);
                    if (refined) finalCur = refined;
                    sun = { orto: hdias[0].orto, ocaso: hdias[0].ocaso };
                }
            }

            // Neither product yielded a usable "today" - nothing to show.
            if (!finalCur) { service._tryProvider(chain, idx + 1); return; }

            // UV is only on the daily product, never the hourly one - so
            // whenever the hourly-refined reading is what's showing (the
            // normal/successful case), backfill it from today's daily
            // figure instead of leaving it blank for no real reason.
            // _fetchWindUvOpenMeteo() below covers the daily-missing case.
            if (isNaN(finalCur.uvIndex) && dias.length > 0)
                finalCur.uvIndex = _uvMaxValue(dias[0]);

            finalCur.dailyData = nd;
            if (sun) {
                if (sun.orto)  finalCur.sunriseTimeText = sun.orto;
                if (sun.ocaso) finalCur.sunsetTimeText  = sun.ocaso;
            }

            service.weatherRoot.weatherDataStaged = finalCur;
            service.weatherRoot.loading = false;
            service.weatherRoot.updateText = service._formatUpdateText("aemet");

            // AEMET's orto/ocaso (and the daily-fallback "--") are local
            // wall-clock strings with no numeric UTC offset attached -
            // same limitation as met.no/BBC/Tomorrow.io/StormGlass - so
            // patch locationUtcOffsetMins (and sunrise/sunset if still
            // "--") from Open-Meteo the same way those providers do.
            service._fetchSunTimesOpenMeteo();

            // Backfill wind/UV gaps (fetch failures, hours/days AEMET's own
            // response didn't have data for) from Open-Meteo - fills in,
            // never overrides a genuine AEMET value.
            service._fetchWindUvOpenMeteo();

            // No native CAP alerts in this product - fall back to
            // MeteoAlarm (already covers Spain) / NWS.
            service._fetchAlertsIfNeeded();
        }

        _withDailyData(service, key, muniId, function (d) {
            if (service._refreshGen !== gen) return;
            dailyResult = d || null;
            combine();
        });
        _withHourlyData(service, key, muniId, function (hd) {
            if (service._refreshGen !== gen) return;
            hourlyResult = hd || null;
            combine();
        });
    });
}

/**
 * Note: unlike fetchCurrent, this does NOT bail out if service._refreshGen
 * has moved on by the time the async chain resolves. It used to, and that
 * was a real bug: a background refresh tick landing while the person had a
 * day expanded in the Forecast tab would silently abandon the in-flight
 * request, leaving that day stuck on its loading state forever, since
 * nothing else re-triggers fetchHourly for it. Nothing here is actually
 * generation-sensitive the way "current conditions" is - _resolveMunicipio
 * already re-derives the right municipio from the live coordinates on every
 * call regardless of gen, so finishing a request from a now-superseded
 * generation is still correct data for the still-configured location.
 */
function fetchHourly(service, W, dateStr) {
    var gen = service._refreshGen;
    var r = service.weatherRoot;
    var key = service._aemetKey();
    if (!key) { r.hourlyData = []; return; }
    r.aemetRateLimited = false; // reflect only this attempt's outcome, not a previous one's

    _resolveMunicipio(service, gen, key, function (muniId) {
        if (!muniId) { r.hourlyData = []; return; }
        _withHourlyData(service, key, muniId, function (hd) {
            r.hourlyData = _dayHourlyForDate(hd, dateStr, W, service);
        });
    });
}

/**
 * Parallel-safe hourly fetch for ForecastView's "expand all days" mode -
 * mirrors bbcWeather.js's fetchHourlyDirect (the only other provider that
 * also needs an async id-resolution step before the real request). Hands
 * the hourly array to `cb` without touching weatherRoot.hourlyData, so
 * several in-flight requests for different dates don't clobber each other.
 */
function fetchHourlyDirect(service, W, dateStr, cb) {
    var gen = service._refreshGen;
    var key = service._aemetKey();
    if (!key) { cb([]); return; }
    service.weatherRoot.aemetRateLimited = false;

    _resolveMunicipio(service, gen, key, function (muniId) {
        if (!muniId) { cb([]); return; }
        _withHourlyData(service, key, muniId, function (hd) {
            cb(_dayHourlyForDate(hd, dateStr, W, service));
        });
    });
}

/** Shared by fetchHourly/fetchHourlyDirect: picks the day matching dateStr
 *  out of an hourly response and builds its per-hour array, then closes the
 *  loop with the following day's earliest hour (marked isNextDay) so it
 *  reads 00:00..00:00 instead of stopping at 23:00 - same as every other
 *  provider. AEMET's hourly product only covers today+tomorrow, so the
 *  closing entry is simply omitted when dateStr is the last day it has
 *  data for (dates further out already resolve to an empty array). */
function _dayHourlyForDate(hd, dateStr, W, service) {
    if (!hd) return [];
    var root = Array.isArray(hd) ? hd[0] : hd;
    var dias = (root && root.prediccion && root.prediccion.dia) ? root.prediccion.dia : [];
    var arr = null;
    for (var i = 0; i < dias.length; i++) {
        if ((dias[i].fecha || "").substr(0, 10) === dateStr) {
            arr = _buildHourlyArray(dias[i], W, service);
            break;
        }
    }
    if (!arr) return [];

    var nextDateStr = _nextDateStr(dateStr);
    for (var j = 0; j < dias.length; j++) {
        if ((dias[j].fecha || "").substr(0, 10) === nextDateStr) {
            var nextArr = _buildHourlyArray(dias[j], W, service);
            if (nextArr.length > 0) {
                var closing = nextArr[0];
                closing.isNextDay = true;
                arr.push(closing);
            }
            break;
        }
    }
    return arr;
}
