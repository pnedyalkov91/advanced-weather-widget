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
 * mapProviders.js - Shared base map (background tile) definitions
 *
 * Single source of truth for the tile layers offered by the "Map background"
 * setting. Consumed by two different map engines:
 *
 *   - Leaflet (RadarWebEngineView.qml) uses tileUrlTemplate, which keeps the
 *     {s} subdomain placeholder for round-robin tile fetching.
 *   - QtLocation (ConfigMapSubPage.qml) uses singleHost, since its "osm"
 *     plugin takes one fixed host and appends {z}/{x}/{y}.png itself.
 *
 * Backgrounds come in two shapes. Raster ones carry tileUrlTemplate and go into
 * an L.tileLayer. Vector ones carry styleUrl with vector: true and go into an
 * L.maplibreGL layer instead - MapLibre renders them on a WebGL canvas that
 * Leaflet keeps in sync, so the radar overlays above them are untouched.
 *
 * All providers are free and require no API key. Attribution strings are HTML
 * because both consumers render rich text.
 *
 * Non-pragma JS - plain globals, imported with "as MapProvidersJS".
 */

var _OSM_LINK = "© <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a> contributors";

var MAP_BACKGROUNDS = {
    "osm-standard": {
        tileUrlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
        singleHost: "https://tile.openstreetmap.org/",
        maxZoom: 19,
        attribution: _OSM_LINK
    },
    "osm-humanitarian": {
        tileUrlTemplate: "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
        singleHost: "https://a.tile.openstreetmap.fr/hot/",
        maxZoom: 20,
        attribution: _OSM_LINK + " | Tiles style by <a href='https://www.hotosm.org/'>HOT</a>"
    },
    "cyclosm": {
        tileUrlTemplate: "https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
        singleHost: "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/",
        maxZoom: 20,
        attribution: _OSM_LINK + " | Tiles style by <a href='https://www.cyclosm.org/'>CyclOSM</a>"
    },
    "opentopomap": {
        tileUrlTemplate: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
        singleHost: "https://a.tile.opentopomap.org/",
        maxZoom: 17,
        attribution: _OSM_LINK + ", SRTM | © <a href='https://opentopomap.org/'>OpenTopoMap</a> (CC-BY-SA)"
    },
    /*
     * The dark basemap LibreWXR itself moved to when CARTO closed its keyless
     * tiles: plain OSM raster recoloured in CSS. `invert` tells the consumer
     * to put the filter class on the base layer's own container, never on the
     * tile pane, which radar and overlays share in RainViewer.
     *
     * It is the only dark background that needs no WebGL. The OpenFreeMap
     * dark styles are vector, so a machine without a GL context falls back to
     * raster and loses every dark option without this one.
     */
    "osm-dark": {
        tileUrlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
        singleHost: "https://tile.openstreetmap.org/",
        maxZoom: 19,
        invert: true,
        attribution: _OSM_LINK
    },
    "openfreemap-positron": {
        styleUrl: "https://tiles.openfreemap.org/styles/positron",
        vector: true,
        maxZoom: 20,
        attribution: _OSM_LINK + " | Tiles by <a href='https://openfreemap.org/'>OpenFreeMap</a>"
    },
    "openfreemap-liberty": {
        styleUrl: "https://tiles.openfreemap.org/styles/liberty",
        vector: true,
        maxZoom: 20,
        attribution: _OSM_LINK + " | Tiles by <a href='https://openfreemap.org/'>OpenFreeMap</a>"
    },
    "openfreemap-fiord": {
        styleUrl: "https://tiles.openfreemap.org/styles/fiord",
        vector: true,
        maxZoom: 20,
        attribution: _OSM_LINK + " | Tiles by <a href='https://openfreemap.org/'>OpenFreeMap</a>"
    },
    "openfreemap-dark": {
        styleUrl: "https://tiles.openfreemap.org/styles/dark",
        vector: true,
        maxZoom: 20,
        attribution: _OSM_LINK + " | Tiles by <a href='https://openfreemap.org/'>OpenFreeMap</a>"
    }
};

var DEFAULT_MAP_BACKGROUND = "osm-standard";

/**
 * "auto" is the shipped default: the widget picks the background instead of
 * the user. Maps that have a light/dark theme of their own (LibreWXR) resolve
 * it against that theme, which reproduces exactly what they did before this
 * setting existed; maps that have no theme (RainViewer) get the standard OSM
 * tiles they always used.
 */
var AUTO_MAP_BACKGROUND = "auto";

/** Ids offered by the "Map background" picker, in display order. */
var MAP_BACKGROUND_ORDER = ["auto", "osm-standard", "osm-dark", "osm-humanitarian", "cyclosm", "opentopomap", "openfreemap-positron", "openfreemap-liberty", "openfreemap-fiord", "openfreemap-dark"];

/**
 * Resolve a background id to its definition.
 *
 * @param id         one of MAP_BACKGROUND_ORDER; anything unknown falls back
 *                   to the default background
 * @param themeHint  "dark" or "light", only consulted for "auto"; omit it on
 *                   maps that have no theme of their own
 */
function resolveMapBackground(id, themeHint) {
    if (id === AUTO_MAP_BACKGROUND)
        return MAP_BACKGROUNDS[themeHint === "dark" ? "openfreemap-dark" : DEFAULT_MAP_BACKGROUND];
    return MAP_BACKGROUNDS[id] || MAP_BACKGROUNDS[DEFAULT_MAP_BACKGROUND];
}

/** True for backgrounds that need MapLibre GL rather than a raster tile layer. */
function isVectorBackground(p) {
    return !!(p && p.vector && p.styleUrl);
}
