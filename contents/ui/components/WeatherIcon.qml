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

pragma ComponentBehavior: Bound

/**
 * WeatherIcon.qml — Unified weather icon renderer
 *
 * Renders a weather icon with automatic fallback:
 *   1. KDE system icon (if type === "kde")
 *   2. Bundled SVG fallback (if svgFallback is set and KDE icon missing)
 *   3. Wi-font glyph (if type === "wi", for compact panel display)
 *
 * Usage (new simplified API):
 *   WeatherIcon {
 *       iconType: "kde"              // "kde" | "svg" | "wi"
 *       iconSource: "thermometer"    // KDE icon name, SVG URL, or wi-font glyph
 *       svgFallback: "file:///..."   // optional bundled SVG fallback URL
 *       iconSize: 22
 *       isMask: false                // true for monochrome symbolic SVGs
 *   }
 *
 * Or with iconResolver.js:
 *   WeatherIcon {
 *       iconInfo: IconResolver.resolve("humidity", 22, iconsBaseDir, "symbolic")
 *       iconSize: 22
 *   }
 */

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: weatherIcon

    // ── Shorthand: set from iconResolver.js result object ─────────────────
    /** Pass the result of IconResolver.resolve() directly */
    property var iconInfo: null

    // ── Derived properties — reactively track iconInfo ─────────────────
    // These are always in sync with iconInfo via QML bindings (no
    // imperative onChanged handler needed).  When iconInfo is null the
    // defaults produce an empty/invisible state.
    readonly property string _infoType:     iconInfo ? String(iconInfo.type     || "") : ""
    readonly property string _infoSource:   iconInfo ? String(iconInfo.source   || "") : ""
    readonly property string _infoFallback: iconInfo ? String(iconInfo.svgFallback || "") : ""
    readonly property bool   _infoMask:     iconInfo ? (iconInfo.isMask === true) : false

    // ── Individual properties (can also be set directly) ──────────────────
    /** Icon type: "kde" (system icon), "svg" (file URL), "wi" (wi-font glyph) */
    property string iconType: _infoType

    /** The icon source: KDE icon name, SVG file URL, or wi-font glyph char */
    property string iconSource: _infoSource

    /** Pixel size for the icon */
    property int iconSize: 22

    /** Bundled SVG fallback URL — used when KDE icon is not found */
    property string svgFallback: _infoFallback

    /** Whether to render the SVG as a monochrome mask (symbolic theme) */
    property bool isMask: _infoMask

    /** Optional icon colour override (defaults to theme text colour) */
    property color iconColor: Kirigami.Theme.textColor

    // ── Wi-font specific (only needed for "wi" type) ──────────────────────
    /** The loaded wi-font family name (from FontLoader.font.family) */
    property string wiFontFamily: ""

    /** Whether the wi-font FontLoader is ready */
    property bool wiFontReady: false

    // ── Size ──────────────────────────────────────────────────────────────
    implicitWidth: iconSize
    implicitHeight: iconSize
    width: iconSize
    height: iconSize
    clip: iconType !== "wi"

    visible: iconSource.length > 0

    // ── Single loaded branch ──────────────────────────────────────────────
    // Exactly one element is instantiated per icon (wi-font Text, or one
    // Kirigami.Icon).  Every Kirigami.Icon carries a PlasmaTheme object that
    // re-syncs on each window expose, and pays icon-theme lookups on polish —
    // with hundreds of icons in the forecast/details delegates, keeping five
    // dormant Icon siblings per WeatherIcon froze the GUI thread on popup
    // open.  The bundled-SVG fallback is only created when the KDE theme
    // lookup actually misses.
    Loader {
        anchors.fill: parent
        sourceComponent: {
            if (weatherIcon.iconType === "wi")
                return weatherIcon.wiFontReady ? wiComp : null;
            if ((weatherIcon.iconType === "kde" || weatherIcon.iconType === "svg")
                    && weatherIcon.iconSource.length > 0)
                return iconComp;
            return null;
        }
    }

    // ── Wi-font glyph ─────────────────────────────────────────────────────
    Component {
        id: wiComp
        Text {
            text: weatherIcon.iconSource
            font.family: weatherIcon.wiFontFamily
            font.pixelSize: Math.round(weatherIcon.iconSize * 0.88)
            color: weatherIcon.iconColor
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── KDE system icon or SVG file icon ──────────────────────────────────
    Component {
        id: iconComp
        Kirigami.Icon {
            id: primaryIcon
            source: weatherIcon.iconSource
            isMask: weatherIcon.isMask
            color: weatherIcon.isMask ? weatherIcon.iconColor : "transparent"
            fallback: weatherIcon.iconType === "kde"
                ? (weatherIcon.svgFallback.length > 0 ? ""
                   : (weatherIcon.isMask ? "dialog-question-symbolic" : "dialog-question"))
                : "unknown"

            // Bundled SVG fallback — only exists when the KDE icon is missing.
            // Gate on status === Error, not !valid: a failed theme lookup still
            // reports valid=true (placeholder machinery), and Error is only set
            // after the lookup finishes, so no transient fallback gets built
            // while the primary icon is still loading.
            Loader {
                anchors.fill: parent
                active: weatherIcon.iconType === "kde"
                        && weatherIcon.svgFallback.length > 0
                        && primaryIcon.status === Kirigami.Icon.Error
                sourceComponent: Kirigami.Icon {
                    source: weatherIcon.svgFallback
                    isMask: weatherIcon.isMask
                    color: weatherIcon.isMask ? weatherIcon.iconColor : "transparent"
                }
            }
        }
    }
}
