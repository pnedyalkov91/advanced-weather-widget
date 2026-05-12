/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * RadarView.qml - dependency-safe wrapper for the optional QtWebEngine radar.
 *
 * Keep this file free of QtWebEngine imports. Plasma loads this type together
 * with FullView, even when the Radar tab is not selected.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: radarRoot

    property var weatherRoot
    readonly property bool radarReady: radarLoader.status === Loader.Ready && radarLoader.item !== null
    property bool loadEmbeddedRadar: false

    readonly property double lat: Plasmoid.configuration.latitude || 0
    readonly property double lon: Plasmoid.configuration.longitude || 0
    readonly property string externalRadarUrl: {
        if (!lat || !lon)
            return "https://www.rainviewer.com/map.html";
        return "https://www.rainviewer.com/map.html?loc=" + lat + "," + lon + "," + (Plasmoid.configuration.radarZoom || 9);
    }

    implicitHeight: 380

    onWeatherRootChanged: _syncLoadedItem()
    onVisibleChanged: {
        console.log("[Advanced Weather Widget Radar] wrapper visible changed:", visible,
                    "loadEmbeddedRadar=", loadEmbeddedRadar,
                    "loaderStatus=", _loaderStatusText(radarLoader.status));
        if (visible && !loadEmbeddedRadar)
            deferredLoadTimer.restart();
    }

    Timer {
        id: deferredLoadTimer
        interval: 250
        repeat: false
        onTriggered: {
            console.log("[Advanced Weather Widget Radar] deferred WebEngine activation tick; visible=", radarRoot.visible,
                        "lat=", radarRoot.lat, "lon=", radarRoot.lon,
                        "layer=", Plasmoid.configuration.radarLayer || "rainviewer",
                        "zoom=", Plasmoid.configuration.radarZoom || 9,
                        "qt=", Qt.version, "platform=", Qt.platform.os);
            if (radarRoot.visible)
                radarRoot.loadEmbeddedRadar = true;
        }
    }

    Loader {
        id: radarLoader
        anchors.fill: parent
        active: radarRoot.visible && radarRoot.loadEmbeddedRadar
        source: Qt.resolvedUrl("components/RadarWebEngineView.qml")
        asynchronous: false

        onStatusChanged: {
            console.log("[Advanced Weather Widget Radar] loader status:", radarRoot._loaderStatusText(status),
                        "active=", active, "visible=", radarRoot.visible,
                        "loadEmbeddedRadar=", radarRoot.loadEmbeddedRadar);
            if (status === Loader.Error)
                console.warn("[Advanced Weather Widget Radar] failed to load RadarWebEngineView:", radarLoader.source);
        }

        onLoaded: {
            console.log("[Advanced Weather Widget Radar] RadarWebEngineView loaded; syncing weatherRoot");
            radarRoot._syncLoadedItem();
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Kirigami.Units.largeSpacing
        }
        spacing: Kirigami.Units.smallSpacing
        visible: radarLoader.status === Loader.Null

        Item {
            Layout.fillHeight: true
        }

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: visible
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: i18n("Loading radar…")
            color: Kirigami.Theme.textColor
            opacity: 0.72
            font: Kirigami.Theme.defaultFont
        }

        Item {
            Layout.fillHeight: true
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Kirigami.Units.largeSpacing
        }
        spacing: Kirigami.Units.smallSpacing
        visible: radarLoader.status === Loader.Error

        Item {
            Layout.fillHeight: true
        }

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            source: "globe"
            color: Kirigami.Theme.textColor
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            level: 3
            text: i18n("QtWebEngine is not installed")
            wrapMode: Text.WordWrap
        }

        TextEdit {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: Kirigami.Theme.textColor
            text: i18n("The Radar tab requires the QtWebEngine package, which is not installed on this system.")
            readOnly: true
            selectByMouse: true
            wrapMode: Text.WordWrap
            selectedTextColor: Kirigami.Theme.highlightedTextColor
            selectionColor: Kirigami.Theme.highlightColor
            font: Kirigami.Theme.defaultFont
        }

        TextEdit {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: Kirigami.Theme.textColor
            text: i18n("Install it for your distribution:\n- Fedora / RHEL: qt6-qtwebengine\n- openSUSE / Arch: qt6-webengine\n- Debian / Kubuntu / KDE Neon: qml6-module-qtwebengine")
            readOnly: true
            selectByMouse: true
            wrapMode: Text.WordWrap
            selectedTextColor: Kirigami.Theme.highlightedTextColor
            selectionColor: Kirigami.Theme.highlightColor
            font: Kirigami.Theme.defaultFont
        }

        Item {
            Layout.preferredHeight: Kirigami.Units.smallSpacing
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: i18n("Open install guide")
            icon.name: "help-about"
            onClicked: Qt.openUrlExternally("https://github.com/pnedyalkov91/advanced-weather-widget#%EF%B8%8F-prerequisites--dependencies")
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: i18n("Open radar in browser")
            icon.name: "internet-web-browser"
            onClicked: Qt.openUrlExternally(radarRoot.externalRadarUrl)
        }

        Item {
            Layout.fillHeight: true
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: radarLoader.status === Loader.Loading
        visible: running
    }

    function reload() {
        if (radarReady) {
            console.log("[Advanced Weather Widget Radar] reload requested");
            radarLoader.item.reload();
        } else {
            console.log("[Advanced Weather Widget Radar] reload requested before radarReady; status=", _loaderStatusText(radarLoader.status));
        }
    }

    function _syncLoadedItem() {
        if (radarReady) {
            console.log("[Advanced Weather Widget Radar] sync weatherRoot into RadarWebEngineView");
            radarLoader.item.weatherRoot = radarRoot.weatherRoot;
        }
    }

    function _loaderStatusText(status) {
        if (status === Loader.Null) return "Null";
        if (status === Loader.Ready) return "Ready";
        if (status === Loader.Loading) return "Loading";
        if (status === Loader.Error) return "Error";
        return "Unknown(" + status + ")";
    }
}
