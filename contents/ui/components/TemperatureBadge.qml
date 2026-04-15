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
 * TemperatureBadge.qml — Reusable temperature overlay badge
 *
 * Used by CompactView (compressed mode) and TrayCompactView to show
 * a temperature label overlaid on the weather icon. Eliminates the
 * duplicated badge positioning/color/opacity logic.
 *
 * Usage:
 *   TemperatureBadge {
 *       temperatureText: weatherRoot ? weatherRoot.tempValue(weatherRoot.temperatureC) : "--"
 *       badgePosition: Plasmoid.configuration.compressedBadgePosition || "bottom-right"
 *       badgeSpacing: Plasmoid.configuration.compressedBadgeSpacing || 0
 *       badgeColor: Plasmoid.configuration.compressedBadgeColor || ""
 *       badgeOpacity: Plasmoid.configuration.compressedBadgeOpacity !== undefined
 *                     ? Plasmoid.configuration.compressedBadgeOpacity : 0.85
 *       fontPixelSize: Math.max(7, Math.round(parent.height / 3))
 *   }
 */

import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: badge

    // ── Public properties ─────────────────────────────────────────────────
    /** The formatted temperature string to display */
    property string temperatureText: "--"

    /** Badge position: "bottom-right", "bottom-left", "top-right", "top-left", "bottom-center", "top-center" */
    property string badgePosition: "bottom-right"

    /** Spacing from the edge in pixels */
    property int badgeSpacing: 0

    /** Custom background color (empty string = use theme background) */
    property string badgeColor: ""

    /** Background opacity (0.0–1.0) */
    property real badgeOpacity: 0.85

    /** Font pixel size for the temperature text */
    property int fontPixelSize: 12

    /** Whether the font should be bold */
    property bool fontBold: false

    // ── Positioning ───────────────────────────────────────────────────────
    x: {
        if (badgePosition === "bottom-right" || badgePosition === "top-right")
            return parent.width - width - badgeSpacing;
        if (badgePosition === "bottom-left" || badgePosition === "top-left")
            return badgeSpacing;
        // center
        return (parent.width - width) / 2;
    }
    y: {
        if (badgePosition.indexOf("bottom") === 0)
            return parent.height - height - badgeSpacing;
        // top
        return badgeSpacing;
    }

    // ── Sizing ────────────────────────────────────────────────────────────
    width: badgeLabel.implicitWidth + 6
    height: badgeLabel.implicitHeight + 2
    radius: height / 2

    // ── Background color ──────────────────────────────────────────────────
    color: {
        var op = badge.badgeOpacity;
        if (badge.badgeColor.length > 0) {
            var parsed = Qt.color(badge.badgeColor);
            return Qt.rgba(parsed.r, parsed.g, parsed.b, op);
        }
        return Qt.rgba(Kirigami.Theme.backgroundColor.r,
                       Kirigami.Theme.backgroundColor.g,
                       Kirigami.Theme.backgroundColor.b, op);
    }

    // ── Temperature label ─────────────────────────────────────────────────
    Label {
        id: badgeLabel
        anchors.centerIn: parent
        text: badge.temperatureText
        font.pixelSize: badge.fontPixelSize
        font.bold: badge.fontBold
        color: Kirigami.Theme.textColor
    }
}
