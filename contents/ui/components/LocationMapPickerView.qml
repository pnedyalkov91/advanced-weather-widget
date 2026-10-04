/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * LocationMapPickerView.qml - Leaflet location picker (location-map-picker.html) in a WebEngineView
 *
 * Used by ConfigMapSubPage.qml through a Loader, so a missing QtWebEngine only disables
 * the map (Loader error) instead of the whole page. Same approach as the radar views:
 * the base map follows Plasmoid.configuration.mapBackground, resolved through
 * MapBackgroundChoices (the same list the radar views use).
 *
 *   start(lat, lon, zoom)          creates the page (call once)
 *   setMarker(lat, lon, minZoom)   moves the pin; minZoom > 0 also zooms in to at least that level
 *   mapClicked(lat, lon)           signal: the user clicked the map
 *   loadFailed()                   signal: the page or Leaflet could not be loaded
 */
import QtQuick
import QtWebEngine
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: pickerRoot

    signal mapClicked(real lat, real lon)
    signal loadFailed

    // Follow the Plasma theme, as the radar views do
    readonly property bool isDark: {
        var c = Kirigami.Theme.backgroundColor;
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) < 0.5;
    }
    readonly property string theme: isDark ? "dark" : "light"

    property bool _pageReady: false
    property var _queued: []

    // Same base map list as the radar views (MapBackgroundChoices.qml, registered in this folder's qmldir)
    readonly property MapBackgroundChoices backgroundChoices: MapBackgroundChoices {
        themeHint: pickerRoot.theme
    }

    onThemeChanged: _run("window.setTheme(" + JSON.stringify(theme) + ");")

    function start(lat, lon, zoom) {
        var bg = Plasmoid.configuration.mapBackground || "auto";
        var list = backgroundChoices.toJson();
        webView.url = Qt.resolvedUrl("location-map-picker.html") + "?lat=" + lat + "&lon=" + lon + "&zoom=" + zoom + "&theme=" + theme + "&bg=" + encodeURIComponent(bg) + "&bglist=" + encodeURIComponent(list) + "&font=" + encodeURIComponent(Kirigami.Theme.defaultFont.family || "") + "&zin=" + encodeURIComponent(i18n("Zoom in")) + "&zout=" + encodeURIComponent(i18n("Zoom out"));
    }

    function setMarker(lat, lon, minZoom) {
        _run("window.setMarker(" + Number(lat) + "," + Number(lon) + "," + (minZoom || 0) + ");");
    }

    // Calls made before the page has loaded are kept and replayed in order.
    function _run(js) {
        if (!_pageReady) {
            _queued.push(js);
            return;
        }
        webView.runJavaScript(js);
    }

    WebEngineView {
        id: webView
        anchors.fill: parent
        backgroundColor: Kirigami.Theme.backgroundColor
        clip: true

        settings.javascriptEnabled: true
        settings.localContentCanAccessRemoteUrls: true
        settings.localContentCanAccessFileUrls: true

        // Attribution links: open in the system browser, never inside the picker
        onNewWindowRequested: function (req) {
            Qt.openUrlExternally(req.requestedUrl);
        }
        onContextMenuRequested: function (request) {
            request.accepted = true;
        }

        onLoadingChanged: function (req) {
            if (req.status === WebEngineView.LoadSucceededStatus) {
                pickerRoot._pageReady = true;
                var q = pickerRoot._queued;
                pickerRoot._queued = [];
                for (var i = 0; i < q.length; ++i)
                    webView.runJavaScript(q[i]);
                viewportFixTimer.restart();
            } else if (req.status === WebEngineView.LoadFailedStatus) {
                console.warn("[MapSubPage] map page failed to load:", req.errorString);
                pickerRoot.loadFailed();
            }
        }

        // Leaflet may size itself against a stale viewport right after load
        Timer {
            id: viewportFixTimer
            interval: 300
            repeat: false
            onTriggered: webView.runJavaScript("if (window.fixViewport) window.fixViewport();")
        }

        onRenderProcessTerminated: function (terminationStatus, exitCode) {
            console.warn("[MapSubPage] render process terminated:", terminationStatus, exitCode);
        }

        onTitleChanged: {
            if (title.indexOf("click:") === 0) {
                var p = title.substring(6).split(",");
                var la = parseFloat(p[0]);
                var lo = parseFloat(p[1]);
                if (!isNaN(la) && !isNaN(lo))
                    pickerRoot.mapClicked(la, lo);
            } else if (title.indexOf("error:") === 0) {
                console.warn("[MapSubPage] map page reported", title);
                pickerRoot.loadFailed();
            }
        }
    }
}
