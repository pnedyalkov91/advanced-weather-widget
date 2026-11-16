/*
 * Copyright 2026 Petar Nedyalkov
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
 * along with this program.  If not, see <https://gnu.org>.
 */


/**
 * bbcLocator.js - the one place that knows how to call the BBC locator service.
 *
 * The BBC Weather provider needs a numeric BBC location id, which the locator
 * service resolves from latitude/longitude. The locator wants an `api_key`
 * query parameter. This is the key that the BBC's own weather website sends
 * with the same request; it is not a personal secret and users do not enter
 * one. It is an undocumented endpoint, not an official BBC API, so it can
 * change or be withdrawn by the BBC at any time.
 *
 * It used to be copied into four files; every caller now goes through
 * locatorUrl() so that a change (or removal) is made here only.
 *
 * `.pragma library` - stateless, safe to import from the applet and from the
 * separate settings-dialog QML engine alike.
 */
.pragma library

var _LOCATOR_KEY = "AGbFAKx58hyjQScCXIYrxuEwJh2W2cmv";

/** Full locator URL for the place nearest to (lat, lon). */
function locatorUrl(lat, lon) {
    return "https://locator-service.api.bbci.co.uk/locations?"
        + "api_key=" + _LOCATOR_KEY
        + "&stack=aws&locale=en&filter=international"
        + "&place-types=settlement%2Cairport%2Cdistrict&order=importance"
        + "&latitude=" + encodeURIComponent(lat)
        + "&longitude=" + encodeURIComponent(lon)
        + "&format=json";
}
