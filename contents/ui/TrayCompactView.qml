/*
 * Copyright 2026  Petar Nedyalkov
 */

import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W
import "components"

Item {
    id: trayRoot

    property var weatherRoot

    readonly property string _trayTemp: weatherRoot ? weatherRoot.tempValue(weatherRoot.temperatureC) : "--"
    readonly property bool _hasTemp: weatherRoot
        && weatherRoot.hasSelectedTown
        && !isNaN(weatherRoot.temperatureC)

    // Weather icon
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

    // Temperature badge — uses shared TemperatureBadge component
    TemperatureBadge {
        visible: trayRoot._hasTemp
        temperatureText: trayRoot._trayTemp
        badgePosition: Plasmoid.configuration.compressedBadgePosition || "bottom-right"
        badgeSpacing: Plasmoid.configuration.compressedBadgeSpacing || 0
        badgeColor: Plasmoid.configuration.compressedBadgeColor || ""
        badgeOpacity: Plasmoid.configuration.compressedBadgeOpacity !== undefined
            ? Plasmoid.configuration.compressedBadgeOpacity : 0.85
        fontPixelSize: Math.max(7, Math.round(trayRoot.height / 3))
    }
}
