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
 * MapBackgroundChoices.qml - Translated labels for the map background picker
 *
 * The tile definitions live in providers/mapProviders.js; the labels live here
 * because that is what the gettext extraction and the two radar views share.
 * Both RadarWebEngineView and RadarWebEngineViewLibreWXR instantiate this and
 * hand the resulting list to their Leaflet page.
 */
import QtQuick
import "../providers/mapProviders.js" as MapProvidersJS

QtObject {
    id: choices

    /**
     * "dark" or "light": used to resolve the "auto" entry. Maps without a
     * theme of their own leave this empty and get the standard OSM tiles.
     */
    property string themeHint: ""

    /** Extra attribution appended to every entry, e.g. the map data provider. */
    property string attributionSuffix: ""

    readonly property var labels: ({
            "auto": i18n("Automatic"),
            "osm-standard": i18n("OpenStreetMap (standard)"),
            "osm-dark": i18n("OpenStreetMap (dark)"),
            "osm-humanitarian": i18n("Humanitarian (HOT)"),
            "cyclosm": i18n("CyclOSM (cycling)"),
            "opentopomap": i18n("OpenTopoMap (topographic)"),
            "openfreemap-positron": i18n("OpenFreeMap Positron (light)"),
            "openfreemap-liberty": i18n("OpenFreeMap Liberty (light)"),
            "openfreemap-fiord": i18n("OpenFreeMap Fiord (dark)"),
            "openfreemap-dark": i18n("OpenFreeMap Dark")
        })

    /** Choices plus their resolved tile data, ready to inject into a page. */
    readonly property var list: {
        var out = [];
        var order = MapProvidersJS.MAP_BACKGROUND_ORDER;
        for (var i = 0; i < order.length; ++i) {
            var id = order[i];
            var p = MapProvidersJS.resolveMapBackground(id, choices.themeHint);
            out.push({
                id: id,
                label: choices.labels[id] || id,
                url: p.tileUrlTemplate || "",
                styleUrl: p.styleUrl || "",
                vector: MapProvidersJS.isVectorBackground(p),
                invert: !!p.invert,
                attribution: p.attribution + choices.attributionSuffix,
                maxZoom: p.maxZoom
            });
        }
        return out;
    }

    function toJson() {
        return JSON.stringify(choices.list);
    }
}
