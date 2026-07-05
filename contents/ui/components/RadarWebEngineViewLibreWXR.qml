/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * RadarWebEngineViewLibreWXR.qml — Interactive weather radar map using WebEngineView + Leaflet
 *
 * LibreWXR (https://librewxr.net/) variant of the radar view, built on the
 * official LibreWXR Leaflet example (components/librewxr-map.html). The page
 * is configured through URL query parameters and driven live through
 * window.setLayerMode / setColorScheme / setArrows / setTheme.
 *
 * - Three layer modes: Radar, Satellite (infrared), Radar + Satellite
 * - Radar color scheme and motion-arrows toggle, in-widget (not in settings)
 * - Base map follows the KDE Plasma light/dark theme automatically; arrow
 *   color follows the map theme
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtWebEngine
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Item {
    id: radarRoot

    property var weatherRoot

    readonly property double lat: weatherRoot ? (Plasmoid.configuration.latitude || 0) : 0
    readonly property double lon: weatherRoot ? (Plasmoid.configuration.longitude || 0) : 0
    readonly property string activeLayer: Plasmoid.configuration.librewxrLayer || "radar"
    readonly property int initialZoom: Math.min(12, Plasmoid.configuration.radarZoom || 7)
    readonly property int colorScheme: Plasmoid.configuration.librewxrColorScheme !== undefined ? Plasmoid.configuration.librewxrColorScheme : 2
    readonly property bool arrowsOn: Plasmoid.configuration.librewxrArrows === true
    readonly property string serverUrl: {
        var u = (Plasmoid.configuration.librewxrUrl || "https://api.librewxr.net").trim();
        while (u.length > 1 && u.charAt(u.length - 1) === "/")
            u = u.substring(0, u.length - 1);
        return u || "https://api.librewxr.net";
    }

    // Follow the Plasma theme: perceptual luminance of the theme background
    readonly property bool isDark: {
        var c = Kirigami.Theme.backgroundColor;
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) < 0.5;
    }
    // "auto" follows the Plasma theme; the in-widget switch stores an override
    readonly property string themeOverride: Plasmoid.configuration.librewxrTheme || "auto"
    readonly property string mapTheme: {
        if (themeOverride === "light" || themeOverride === "dark")
            return themeOverride;
        return isDark ? "dark" : "light";
    }

    // A manual "Dark map" toggle only sticks until the Plasma theme itself
    // actually changes — at that point the override is cleared so the map
    // (and the switch) snap back to following Plasma automatically.
    onIsDarkChanged: {
        if (radarRoot.themeOverride !== "auto") {
            console.log("[Advanced Weather Widget Radar/LibreWXR] Plasma theme changed; clearing manual dark-map override");
            Plasmoid.configuration.librewxrTheme = "auto";
        }
    }

    readonly property bool is24h: {
        var f = Qt.locale().timeFormat(Locale.ShortFormat);
        return f.indexOf('H') !== -1 || f.indexOf('k') !== -1;
    }

    implicitHeight: 380

    // ── Blank-view workaround ────────────────────────────────────────────
    // When the plasmoid popup is closed and reopened, the Chromium surface
    // behind WebEngineView is not always recomposited, leaving a blank map
    // until the user resizes the widget. Nudging the view's size by 1 px
    // (and back) forces Chromium to produce a fresh frame — the same thing
    // a manual resize does.
    property int _repaintNudge: 0

    Timer {
        id: repaintNudgeTimer
        interval: 150
        repeat: false
        onTriggered: {
            console.log("[Advanced Weather Widget Radar/LibreWXR] repaint nudge");
            radarRoot._repaintNudge = 1;
            repaintRestoreTimer.restart();
        }
    }
    Timer {
        id: repaintRestoreTimer
        interval: 60
        repeat: false
        onTriggered: radarRoot._repaintNudge = 0
    }

    onVisibleChanged: {
        if (visible)
            repaintNudgeTimer.restart();
    }

    Connections {
        target: radarRoot.weatherRoot ? radarRoot.weatherRoot : null
        ignoreUnknownSignals: true
        function onExpandedChanged() {
            if (radarRoot.weatherRoot.expanded && radarRoot.visible)
                repaintNudgeTimer.restart();
        }
    }

    Component.onCompleted: {
        console.log("[Advanced Weather Widget Radar/LibreWXR] component completed; lat=", lat, "lon=", lon, "layer=", activeLayer, "zoom=", initialZoom, "colorScheme=", colorScheme, "arrows=", arrowsOn, "theme=", mapTheme, "server=", serverUrl, "qt=", Qt.version, "platform=", Qt.platform.os);
    }

    // ── Wi-font icon loader ───────────────────────────────────────────────
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../../fonts/weathericons-regular-webfont.ttf")
    }
    readonly property bool wiFontReady: wiFont.status === FontLoader.Ready
    readonly property string wiFontFamily: wiFontReady ? wiFont.font.family : ""

    // ── Layer modes (matching the LibreWXR example) ──────────────────────
    readonly property var layers: [
        {
            id: "radar",
            label: i18n("Radar"),
            glyph: ""
        },
        {
            id: "satellite",
            label: i18n("Satellite"),
            glyph: ""
        },
        {
            id: "both",
            label: i18n("Radar + Satellite"),
            glyph: ""
        }
    ]

    // LibreWXR radar color schemes (ids 0-12, from /public/weather-maps.json)
    readonly property var colorSchemes: [i18n("Black and White"), "Rain Viewer Original", "Universal Blue", "Titan", "The Weather Channel (TWC)", "Meteored", "NEXRAD Level III", "Rainbow @ Selex SI", "Dark Sky", "Datameteo Valerio", "Viper HD", "MRMS CREF", "33/40 Max Storm"]

    // ── Page URL ─────────────────────────────────────────────────────────
    function _pageUrl() {
        var strings = {
            "forecast": i18n("Forecast"),
            "loading": i18n("Loading…"),
            "loadingFrame": i18n("Loading frame…"),
            "loadingFrames": i18n("Loading frames"),
            "noData": i18n("No data"),
            "noRadarData": i18n("No radar data"),
            "noSatData": i18n("No satellite data"),
            "apiError": i18n("API error"),
            "connFailed": i18n("Connection failed")
        };
        return Qt.resolvedUrl("librewxr-map.html") + "?lat=" + radarRoot.lat + "&lon=" + radarRoot.lon + "&zoom=" + radarRoot.initialZoom + "&layer=" + encodeURIComponent(radarRoot.activeLayer) + "&color=" + radarRoot.colorScheme + "&arrows=" + (radarRoot.arrowsOn ? "1" : "0") + "&theme=" + radarRoot.mapTheme + "&server=" + encodeURIComponent(radarRoot.serverUrl) + "&hour12=" + (radarRoot.is24h ? "0" : "1") + "&locale=" + encodeURIComponent(Qt.locale().name.replace("_", "-")) + "&strings=" + encodeURIComponent(JSON.stringify(strings));
    }

    function _loadPage(reason) {
        var url = _pageUrl();
        console.log("[Advanced Weather Widget Radar/LibreWXR] loading page (" + reason + "); lat=", radarRoot.lat, "lon=", radarRoot.lon, "layer=", radarRoot.activeLayer, "theme=", radarRoot.mapTheme);
        // Assigning an unchanged url is not guaranteed to navigate — force a
        // real reload in that case (e.g. the header Refresh button).
        if (webView.url.toString() === url)
            webView.reload();
        else
            webView.url = url;
    }

    // Coalesce page loads: at creation lat and lon arrive one after the
    // other (0 → lat → lat+lon), which used to trigger three page loads in a
    // row — each one a fresh window for compositing glitches.
    Timer {
        id: pageLoadTimer
        interval: 150
        repeat: false
        onTriggered: radarRoot._loadPage("coalesced")
    }

    // ── Main layout ──────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // ── Layer mode selector (pill-tab style matching Details/Forecast/Radar tabs) ─
        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 17
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)

            RowLayout {
                anchors {
                    fill: parent
                    margins: 3
                }
                spacing: 0

                Repeater {
                    model: radarRoot.layers
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isActive: radarRoot.activeLayer === modelData.id
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        color: isActive ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.17) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                visible: radarRoot.wiFontReady
                                text: modelData.glyph
                                font.family: radarRoot.wiFontFamily
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                                color: Kirigami.Theme.textColor
                                opacity: parent.parent.isActive ? 1.0 : 0.42
                                verticalAlignment: Text.AlignVCenter
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 140
                                    }
                                }
                            }
                            Label {
                                text: modelData.label
                                color: Kirigami.Theme.textColor
                                opacity: parent.parent.isActive ? 1.0 : 0.42
                                font: weatherRoot ? weatherRoot.wf(11, parent.parent.isActive) : Qt.font({
                                    bold: parent.parent.isActive
                                })
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 140
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Plasmoid.configuration.librewxrLayer = modelData.id;
                                webView.runJavaScript("window.setLayerMode(" + JSON.stringify(modelData.id) + ");");
                            }
                        }
                    }
                }
            }
        }

        // ── Options: color scheme + motion arrows (radar modes) + map theme ─
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Label {
                visible: radarRoot.activeLayer !== "satellite"
                text: i18n("Radar color scheme:")
                color: Kirigami.Theme.textColor
                opacity: 0.72
                font: weatherRoot ? weatherRoot.wf(11, false) : Kirigami.Theme.smallFont
            }

            PlasmaComponents.ComboBox {
                id: schemeCombo
                visible: radarRoot.activeLayer !== "satellite"
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                model: radarRoot.colorSchemes
                currentIndex: Math.max(0, Math.min(radarRoot.colorSchemes.length - 1, radarRoot.colorScheme))
                onActivated: {
                    Plasmoid.configuration.librewxrColorScheme = currentIndex;
                    webView.runJavaScript("window.setColorScheme(" + currentIndex + ");");
                }
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents.Switch {
                visible: radarRoot.activeLayer !== "satellite"
                text: i18n("Arrows")
                checked: radarRoot.arrowsOn
                onToggled: {
                    Plasmoid.configuration.librewxrArrows = checked;
                    webView.runJavaScript("window.setArrows(" + (checked ? "true" : "false") + ");");
                }

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Show precipitation motion arrows")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents.Switch {
                text: i18n("Dark map")
                checked: radarRoot.mapTheme === "dark"
                onToggled: {
                    // Manual choice overrides following the Plasma theme
                    // until the Plasma theme itself changes (see onIsDarkChanged)
                    Plasmoid.configuration.librewxrTheme = checked ? "dark" : "light";
                    webView.runJavaScript("window.setTheme(" + JSON.stringify(checked ? "dark" : "light") + ");");
                }

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Switch between the light and dark map style. Until first toggled, the map follows the Plasma theme.")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        // ── WebEngine map ─────────────────────────────────────────────
        WebEngineView {
            id: webView
            Layout.fillWidth: true
            Layout.fillHeight: true
            // 1 px nudge to force Chromium recompositing after popup reopen
            Layout.bottomMargin: radarRoot._repaintNudge
            // Chromium resizes the page asynchronously; while it catches up
            // it composites the stale old-size texture, which would otherwise
            // paint past the view's bounds (ghost scrubber below the footer).
            clip: true

            settings.javascriptEnabled: true
            settings.localContentCanAccessRemoteUrls: true
            settings.localContentCanAccessFileUrls: true

            // Prevent popups / navigation away from our page
            onNewWindowRequested: function (req) {
                Qt.openUrlExternally(req.requestedUrl);
            }

            // Disable the native Chromium context menu (Back/Forward/Reload/Save page/View source).
            // Radar reload is handled by the header Refresh button instead, for a consistent UI.
            onContextMenuRequested: function (request) {
                request.accepted = true;
            }

            Component.onCompleted: pageLoadTimer.restart()

            onLoadingChanged: function (loadRequest) {
                console.log("[Advanced Weather Widget Radar/LibreWXR] loading changed:", "status=", loadRequest.status, "url=", loadRequest.url, "errorCode=", loadRequest.errorCode, "error=", loadRequest.errorString);
                if (loadRequest.status === WebEngineView.LoadSucceededStatus)
                    viewportFixTimer.restart();
            }

            // After a (re)load, Leaflet may size itself against a stale
            // viewport, glitching the map until it is panned. Recalculate
            // once the page has settled, and nudge the Chromium surface.
            Timer {
                id: viewportFixTimer
                interval: 300
                repeat: false
                onTriggered: {
                    console.log("[Advanced Weather Widget Radar/LibreWXR] post-load viewport fix");
                    webView.runJavaScript("if (window.fixViewport) window.fixViewport();");
                    repaintNudgeTimer.restart();
                    viewportFixLateTimer.restart();
                }
            }
            // Second pass: radar/base tiles can finish loading well after
            // LoadSucceeded, re-exposing the compositing artifact.
            Timer {
                id: viewportFixLateTimer
                interval: 1500
                repeat: false
                onTriggered: {
                    webView.runJavaScript("if (window.fixViewport) window.fixViewport();");
                    repaintNudgeTimer.restart();
                }
            }

            onRenderProcessTerminated: function (terminationStatus, exitCode) {
                console.warn("[Advanced Weather Widget Radar/LibreWXR] render process terminated:", "status=", terminationStatus, "exitCode=", exitCode);
            }

            onTitleChanged: {
                if (title.indexOf("zoom:") === 0) {
                    var z = parseInt(title.substring(5));
                    if (!isNaN(z) && z !== Plasmoid.configuration.radarZoom) {
                        Plasmoid.configuration.radarZoom = z;
                    }
                }
            }

            // Reload on location/server change (coalesced); theme switches
            // live without reload
            Connections {
                target: radarRoot
                function onLatChanged() {
                    pageLoadTimer.restart();
                }
                function onLonChanged() {
                    pageLoadTimer.restart();
                }
                function onServerUrlChanged() {
                    pageLoadTimer.restart();
                }
                function onMapThemeChanged() {
                    console.log("[Advanced Weather Widget Radar/LibreWXR] Plasma theme changed; mapTheme=", radarRoot.mapTheme);
                    webView.runJavaScript("window.setTheme(" + JSON.stringify(radarRoot.mapTheme) + ");");
                }
            }
        }
    }

    function reload() {
        radarRoot._loadPage("reload requested");
    }
}
