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
 * TrayCompactView.qml — System tray icon (visual only)
 *
 * Shows a weather icon that fits the standard tray icon slot.
 * When a location is set, a compressed-mode temperature badge is overlaid.
 * No mouse handling — the MouseArea lives in CompactRepresentationInTray.
 */
import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W

Item {
    id: trayRoot

    property var weatherRoot

    readonly property bool _hasTemp: weatherRoot
        && weatherRoot.hasSelectedTown
        && !isNaN(weatherRoot.temperatureC)

    // ── Weather icon ──────────────────────────────────────────────────
    Kirigami.Icon {
        id: trayIcon
        anchors.fill: parent
        source: {
            if (!weatherRoot || weatherRoot.weatherCode < 0)
                return "weather-none-available";
            var style = Plasmoid.configuration.panelSimpleIconStyle || "symbolic";
            var isNight = weatherRoot.isNightTime();
            if (style === "symbolic")
                return W.weatherCodeToIcon(weatherRoot.weatherCode, isNight, true);
            return W.weatherCodeToIcon(weatherRoot.weatherCode, isNight, false);
        }
    }

    // ── Temperature badge (compressed mode) ───────────────────────────
    Rectangle {
        id: badgeRect
        visible: trayRoot._hasTemp

        readonly property string _pos: Plasmoid.configuration.compressedBadgePosition || "bottom-right"
        readonly property int _spacing: Plasmoid.configuration.compressedBadgeSpacing || 0

        x: {
            if (_pos === "bottom-right" || _pos === "top-right")
                return parent.width - width - _spacing;
            if (_pos === "bottom-left" || _pos === "top-left")
                return _spacing;
            return (parent.width - width) / 2;
        }
        y: {
            if (_pos.indexOf("bottom") === 0)
                return parent.height - height - _spacing;
            return _spacing;
        }

        width: badgeLabel.implicitWidth + 6
        height: badgeLabel.implicitHeight + 2
        radius: height / 2
        color: {
            var cc = Plasmoid.configuration.compressedBadgeColor || "";
            var op = Plasmoid.configuration.compressedBadgeOpacity !== undefined
                ? Plasmoid.configuration.compressedBadgeOpacity : 0.85;
            if (cc.length > 0) {
                var parsed = Qt.color(cc);
                return Qt.rgba(parsed.r, parsed.g, parsed.b, op);
            }
            return Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, op);
        }

        Label {
            id: badgeLabel
            anchors.centerIn: parent
            text: trayRoot.weatherRoot
                ? trayRoot.weatherRoot.tempValue(trayRoot.weatherRoot.temperatureC)
                : "--"
            font.pixelSize: Math.max(7, Math.round(trayRoot.height / 3))
            font.bold: false
            color: Kirigami.Theme.textColor
        }
    }
}
