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
import org.kde.plasma.core as PlasmaCore

Item {
    id: radarRoot

    property var weatherRoot
    readonly property bool radarReady: radarLoader.status === Loader.Ready && radarLoader.item !== null
    property bool loadEmbeddedRadar: false
    // Set by FullView when "Keep the radar loaded" is on: build the map even
    // while the tab or the popup is hidden, and keep it across hide/show.
    property bool keepLoaded: false
    // Whether the map can be seen right now. A closed popup does not hide
    // its items, so the expanded state is checked too (the desktop has no
    // popup and is always shown).
    readonly property bool shown: visible && (Plasmoid.formFactor === PlasmaCore.Types.Planar
        || !weatherRoot || weatherRoot.expanded === true)
    // When the current page was (re)loaded, for reloadIfStale().
    property double _loadedAt: 0

    readonly property double lat: Plasmoid.configuration.latitude || 0
    readonly property double lon: Plasmoid.configuration.longitude || 0
    readonly property string radarProvider: Plasmoid.configuration.radarProvider || "rainviewer"
    readonly property string externalRadarUrl: {
        if (radarProvider === "librewxr")
            return "https://librewxr.net/examples/";
        if (!lat || !lon)
            return "https://www.rainviewer.com/map.html";
        return "https://www.rainviewer.com/map.html?loc=" + lat + "," + lon + "," + (Plasmoid.configuration.radarZoom || 9);
    }

    implicitHeight: 380

    onWeatherRootChanged: _syncLoadedItem()
    onVisibleChanged: _maybeDeferLoad()
    // Built in the background by FullView: load the map even though the
    // tab is not shown.
    onKeepLoadedChanged: _maybeDeferLoad()

    // A map kept loaded is already built when it comes back into view, and
    // Chromium first shows the frame it had when it was hidden, before the
    // wind restarts: fade it in rather than letting it jump. It stays
    // transparent for at least 150 ms, so the fade does not reveal the old
    // frame, and until the page says its map is loaded: built hidden, it has
    // loaded nothing before its first showing. The page answers even when a
    // server is down, after 1.5 s at the latest; the 2 s here only covers a
    // page that does not answer at all.
    onShownChanged: {
        if (shown && keepLoaded && radarReady) {
            console.log("[Advanced Weather Widget Radar] fading the kept radar in");
            _fadeIn();
        }
    }

    property bool _fadePending: false
    property bool _fadeReady: false

    function _fadeIn() {
        radarFadeAnim.stop();
        radarLoader.opacity = 0;
        _fadePending = true;
        _fadeReady = false;
        fadeHoldTimer.restart();
        fadeCapTimer.restart();
        var view = radarLoader.item;
        if (view && view.awaitReady) {
            view.awaitReady(function () {
                radarRoot._fadeReady = true;
                radarRoot._fadeMaybeStart();
            });
        } else {
            _fadeReady = true;
        }
    }

    function _fadeMaybeStart() {
        if (_fadePending && _fadeReady && !fadeHoldTimer.running)
            _fadeStart();
    }

    function _fadeStart() {
        if (!_fadePending)
            return;
        _fadePending = false;
        fadeCapTimer.stop();
        radarFadeAnim.restart();
    }

    Timer {
        id: fadeHoldTimer
        interval: 150
        onTriggered: radarRoot._fadeMaybeStart()
    }

    Timer {
        id: fadeCapTimer
        interval: 2000
        onTriggered: {
            console.log("[Advanced Weather Widget Radar] no answer from the page after 2 s, fading in anyway");
            radarRoot._fadeStart();
        }
    }

    NumberAnimation {
        id: radarFadeAnim
        target: radarLoader
        property: "opacity"
        to: 1
        duration: 400
        easing.type: Easing.OutCubic
    }

    // Created already-visible when the parent tab Loader builds us on first
    // visit, so onVisibleChanged may never fire - kick the deferred load here
    // too. Harmless if onVisibleChanged also fires (the timer just restarts).
    Component.onCompleted: _maybeDeferLoad()

    function _maybeDeferLoad() {
        console.log("[Advanced Weather Widget Radar] wrapper maybeDeferLoad; visible=", visible,
                    "loadEmbeddedRadar=", loadEmbeddedRadar,
                    "loaderStatus=", _loaderStatusText(radarLoader.status));
        if ((visible || keepLoaded) && !loadEmbeddedRadar)
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
            if (radarRoot.visible || radarRoot.keepLoaded)
                radarRoot.loadEmbeddedRadar = true;
        }
    }

    Loader {
        id: radarLoader
        anchors.fill: parent
        active: (radarRoot.visible || radarRoot.keepLoaded) && radarRoot.loadEmbeddedRadar
        source: radarRoot.radarProvider === "librewxr"
            ? Qt.resolvedUrl("components/RadarWebEngineViewLibreWXR.qml")
            : Qt.resolvedUrl("components/RadarWebEngineView.qml")
        // Load synchronously: QtWebEngine has GUI-thread requirements during
        // init and is historically fragile when created via an async Loader,
        // so for this crash-sensitive component we prefer the conventional
        // synchronous path. Responsiveness is already handled by the 250 ms
        // deferredLoadTimer above (the tab switches instantly; Chromium is
        // only instantiated once the tab has settled).
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
            radarRoot._loadedAt = Date.now();
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
            _loadedAt = Date.now();
            radarLoader.item.reload();
        } else {
            console.log("[Advanced Weather Widget Radar] reload requested before radarReady; status=", _loaderStatusText(radarLoader.status));
        }
    }

    /**
     * Reload only a page older than ten minutes. Called when the Radar tab
     * comes back into view: a page built a moment ago for this very showing
     * is not loaded a second time. A page kept loaded is never reloaded
     * here: it catches up by itself when it is shown again (the radar
     * catalog once older than its 5 min refresh, the wind grids once older
     * than an hour), and reloading it would rebuild the map in front of the
     * user.
     */
    function reloadIfStale() {
        if (!radarReady)
            return;
        if (keepLoaded) {
            console.log("[Advanced Weather Widget Radar] kept radar shown again, no reload");
            return;
        }
        var age = Date.now() - _loadedAt;
        if (age < 10 * 60 * 1000) {
            console.log("[Advanced Weather Widget Radar] page is recent, no reload; ageMs=", age);
            return;
        }
        reload();
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
