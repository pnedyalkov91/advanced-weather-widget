/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * RadarWebEngineViewLibreWXR.qml - Interactive weather radar map using WebEngineView + Leaflet
 *
 * LibreWXR (https://librewxr.net/) variant of the radar view, built on the
 * official LibreWXR Leaflet example (components/librewxr-map.html). The map
 * page is a chrome-less map + replayer: every control lives in this QML side
 * as a native Plasma widget, and each change is written straight into
 * Plasmoid.configuration so the user's choices persist naturally. The page
 * is seeded from URL query parameters and then driven live through these
 * window functions:
 *
 *   window.setLayerMode("radar" | "satellite" | "both")
 *   window.setColorScheme(index)          // 0-12, LibreWXR color scheme id
 *   window.setArrows(true | false)        // boolean; the page derives arrow color from its theme
 *   window.setWind(true | false)          // animated 10 m wind particles (Open-Meteo)
 *   window.setWindActive(true | false)    // pause the wind while the popup is collapsed
 *   window.setWindLevel("10m" | "700hPa") // surface wind or the flow aloft that steers the rain
 *   window.setWindRate(fps, maxFps)       // frame-rate budget from the settings
 *   window.setCells("light" | "dark" | "")   // storm-cell overlay theme; "" = off
 *   window.setAlerts(true | false)        // WMO alerts overlay
 *   window.setSmooth(true | false)        // radar tile edge smoothing
 *   window.setSnow(true | false)          // radar snow/wintry-precip mask
 *   window.setFormat("webp" | "png")      // tile image format
 *   window.setTileSize("auto" | "256" | "512")   // tile pixel size ("auto" = device DPR)
 *   window.setTheme("light" | "dark")     // map + replayer theme
 *   window.setBackground(id)              // base map id, from backgroundChoices
 *   window.fixViewport()                  // post-load Leaflet viewport fix
 *
 * - Layer mode pills, radar color scheme combo, motion-arrows switch, storm
 *   cells switch, alerts switch and the Dark map switch are native
 *   controls owned by this file; the base map is chosen via the in-map
 *   picker on the map page (reports "bg:" picks through document.title),
 *   with the configuration value seeding the initial state
 * - Smoothing, snow mask, tile format and tile size live behind a
 *   collapsible "Options" toggle (native controls, same as the row above);
 *   collapsed state persists via librewxrOptionsExpanded
 * - "auto" base map follows the KDE Plasma light/dark theme; any explicit
 *   choice pins a fixed light/dark style and locks the Dark map switch
 * - The page reports only zoom ("zoom:") and in-map background picks
 *   ("bg:") back through document.title; the "state:" toolbar protocol is
 *   gone because the chrome-less page no longer owns any controls
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtWebEngine
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Item {
    id: radarRoot

    property var weatherRoot

    readonly property double lat: weatherRoot ? (Plasmoid.configuration.latitude || 0) : 0
    readonly property double lon: weatherRoot ? (Plasmoid.configuration.longitude || 0) : 0
    readonly property string activeLayer: Plasmoid.configuration.librewxrLayer || "radar"
    readonly property int initialZoom: Math.min(12, Plasmoid.configuration.radarZoom || 7)
    readonly property int colorScheme: Plasmoid.configuration.librewxrColorScheme !== undefined ? Plasmoid.configuration.librewxrColorScheme : 10
    readonly property bool arrowsOn: Plasmoid.configuration.librewxrArrows === true
    readonly property bool windOn: Plasmoid.configuration.librewxrWind === true
    readonly property string windLevel: Plasmoid.configuration.librewxrWindLevel === "700hPa" ? "700hPa" : "10m"
    // Frame-rate budget from the settings: [base fps, ceiling fps]. The page
    // raises the rate with the wind speed inside that range.
    readonly property var windRate: {
        var q = Plasmoid.configuration.librewxrWindQuality || "balanced";
        if (q === "economy") return [8, 10];
        if (q === "smooth") return [12, 30];
        return [10, 20];
    }
    readonly property string activeCells: Plasmoid.configuration.librewxrCells || ""
    readonly property bool alertsOn: Plasmoid.configuration.librewxrAlerts === true
    readonly property bool smoothOn: Plasmoid.configuration.librewxrSmooth !== false
    readonly property bool snowOn: Plasmoid.configuration.librewxrSnow !== false
    readonly property string tileFormat: Plasmoid.configuration.librewxrFormat || "webp"
    readonly property string tileSizeChoice: Plasmoid.configuration.librewxrTileSize || "auto"
    readonly property bool optionsExpanded: Plasmoid.configuration.librewxrOptionsExpanded === true
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
    readonly property string mapTheme: {
        var t = Plasmoid.configuration.librewxrTheme || "auto";
        if (t === "light" || t === "dark")
            return t;
        return isDark ? "dark" : "light";
    }

    // ── Base map background ──────────────────────────────────────────────
    // "auto" keeps the theme-driven pair this map uses (OSM in light,
    // OpenFreeMap Dark in dark); any other id pins one background
    // regardless of the theme. The page re-resolves "auto" itself on theme
    // switches, so themeHint only seeds the initial load.
    readonly property string mapBackground: Plasmoid.configuration.mapBackground || "auto"
    /** Set while the in-map picker is what changed the background. */
    property bool _backgroundFromMap: false

    readonly property MapBackgroundChoices backgroundChoices: MapBackgroundChoices {
        themeHint: radarRoot.mapTheme
        attributionSuffix: " | <a href=\"https://librewxr.net/\">LibreWXR</a>"
    }

    // Any explicitly chosen base map has a fixed light/dark style of its own,
    // so the map page ignores the theme for tile selection while one is
    // active (see setTheme's "only auto follows the theme" guard in
    // librewxr-map.html). The Dark map switch is locked read-only while one
    // is selected, since toggling it would have no visible effect on the map.
    readonly property bool darkMapLocked: radarRoot.mapBackground !== "auto"

    // A manual "Dark map" toggle only sticks until the Plasma theme itself
    // actually changes - at that point the override is cleared so the map
    // (and the switch) snap back to following Plasma automatically.
    property bool _themeGuardArmed: false

    Timer {
        id: themeGuardTimer
        interval: 400
        repeat: false
        onTriggered: radarRoot._themeGuardArmed = true
    }

    onIsDarkChanged: {
        if (!radarRoot._themeGuardArmed) {
            console.log("[Advanced Weather Widget Radar/LibreWXR] ignoring theme read during startup settle");
            return;
        }
        if ((Plasmoid.configuration.librewxrTheme || "auto") !== "auto") {
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
    // (and back) forces Chromium to produce a fresh frame - the same thing
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
            // The page cannot always tell a collapsed popup from a visible one,
            // so pause and resume the wind particles from here.
            webView.runJavaScript("if (window.setWindActive) window.setWindActive(" + (radarRoot.weatherRoot.expanded ? "true" : "false") + ");");
            if (radarRoot.weatherRoot.expanded && radarRoot.visible)
                repaintNudgeTimer.restart();
        }
    }

    Component.onCompleted: {
        console.log("[Advanced Weather Widget Radar/LibreWXR] component completed; lat=", lat, "lon=", lon, "layer=", activeLayer, "zoom=", initialZoom, "colorScheme=", colorScheme, "arrows=", arrowsOn, "theme=", mapTheme, "server=", serverUrl, "qt=", Qt.version, "platform=", Qt.platform.os);
        themeGuardTimer.restart();
    }

    // -- Wi-font icon loader -------------------------------------------------
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../../fonts/weathericons-regular-webfont.ttf")
    }
    readonly property bool wiFontReady: wiFont.status === FontLoader.Ready
    readonly property string wiFontFamily: wiFontReady ? wiFont.font.family : ""

    // -- Layer modes (matching the LibreWXR example) -------------------------
    readonly property var layers: [
        {
            id: "radar",
            label: i18n("Radar"),
            glyph: "\uF01D"
        },
        {
            id: "satellite",
            label: i18n("Satellite"),
            glyph: "\uF013"
        },
        {
            id: "both",
            label: i18n("Radar + Satellite"),
            glyph: "\uF002"
        }
    ]

    // LibreWXR radar color schemes (ids 0-12, from /public/weather-maps.json)
    readonly property var colorSchemes: [i18n("Black and White"), "Rain Viewer Original", "Universal Blue", "Titan", "The Weather Channel (TWC)", "Meteored", "NEXRAD Level III", "Rainbow @ Selex SI", "Dark Sky", "Datameteo Valerio", "Viper HD", "MRMS CREF", "33/40 Max Storm"]

    // Tile image format and pixel size, per librewxr-map.html's state.format /
    // state.tileSize (webp|png; auto|256|512 - "auto" follows devicePixelRatio)
    readonly property var tileFormats: [
        { id: "webp", label: "WebP" },
        { id: "png", label: "PNG" }
    ]
    readonly property var tileSizes: [
        { id: "auto", label: i18n("Auto (device)") },
        { id: "256", label: i18n("256 px") },
        { id: "512", label: i18n("512 px") }
    ]

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
        return Qt.resolvedUrl("librewxr-map.html") + "?lat=" + radarRoot.lat + "&lon=" + radarRoot.lon + "&zoom=" + radarRoot.initialZoom + "&layer=" + encodeURIComponent(radarRoot.activeLayer) + "&color=" + radarRoot.colorScheme + "&arrows=" + (radarRoot.arrowsOn ? "1" : "0") + "&wind=" + (radarRoot.windOn ? "1" : "0") + "&windlevel=" + radarRoot.windLevel + "&windfps=" + radarRoot.windRate[0] + "&windmaxfps=" + radarRoot.windRate[1] + "&cells=" + encodeURIComponent(radarRoot.activeCells) + "&alerts=" + (radarRoot.alertsOn ? "1" : "0") + "&smooth=" + (radarRoot.smoothOn ? "1" : "0") + "&snow=" + (radarRoot.snowOn ? "1" : "0") + "&format=" + encodeURIComponent(radarRoot.tileFormat) + "&tilesize=" + encodeURIComponent(radarRoot.tileSizeChoice) + "&theme=" + radarRoot.mapTheme + "&server=" + encodeURIComponent(radarRoot.serverUrl) + "&hour12=" + (radarRoot.is24h ? "0" : "1") + "&locale=" + encodeURIComponent(Qt.locale().name.replace("_", "-")) + "&strings=" + encodeURIComponent(JSON.stringify(strings)) + "&bg=" + encodeURIComponent(radarRoot.mapBackground) + "&bglist=" + encodeURIComponent(radarRoot.backgroundChoices.toJson()) + "&font=" + encodeURIComponent(Kirigami.Theme.defaultFont.family || "");
    }

    function _loadPage(reason) {
        var url = _pageUrl();
        console.log("[Advanced Weather Widget Radar/LibreWXR] loading page (" + reason + "); lat=", radarRoot.lat, "lon=", radarRoot.lon, "layer=", radarRoot.activeLayer, "theme=", radarRoot.mapTheme);
        // Assigning an unchanged url is not guaranteed to navigate - force a
        // real reload in that case (e.g. the header Refresh button).
        if (webView.url.toString() === url)
            webView.reload();
        else
            webView.url = url;
    }

    // Coalesce page loads: at creation lat and lon arrive one after the
    // other (0 → lat → lat+lon), which used to trigger three page loads in a
    // row - each one a fresh window for compositing glitches.
    Timer {
        id: pageLoadTimer
        interval: 150
        repeat: false
        onTriggered: radarRoot._loadPage("coalesced")
    }

    // ── Mini switch ──────────────────────────────────────────────────────
    // A small switch built from the Plasma theme's own switch SVG (26 x 14
    // px track, sliding handle) with a small label: same look and colors as
    // a Plasma Switch at half its height, so the option row above the map
    // fits on one line at widget width.
    component OptionChip: Item {
        id: chip
        property string text
        property bool checked: false
        property string tooltip
        signal toggled(bool on)

        height: 22
        implicitWidth: track.width + 5 + chipLabel.implicitWidth + 4
        opacity: enabled ? 1.0 : 0.4

        // Same SVG pieces as Plasma's own SwitchIndicator (widgets/switch:
        // inactive bar, active bar, handle), just drawn smaller, so the
        // colors come from the Plasma theme exactly like the original.
        KSvg.Svg {
            id: switchSvg
            imagePath: "widgets/switch"
            colorSet: chip.Kirigami.Theme.colorSet
        }

        Item {
            id: track
            width: 26
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            KSvg.FrameSvgItem {
                anchors.fill: parent
                imagePath: "widgets/switch"
                prefix: "inactive"
            }
            KSvg.FrameSvgItem {
                visible: chip.checked
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: knob.right
                imagePath: "widgets/switch"
                prefix: "active"
            }
            KSvg.SvgItem {
                id: knob
                width: 14
                height: 14
                anchors.verticalCenter: parent.verticalCenter
                x: chip.checked ? parent.width - width : 0
                svg: switchSvg
                elementId: chipMouse.containsMouse && chip.enabled ? "handle-hover" : (chip.checked && switchSvg.hasElement("handle-active") ? "handle-active" : "handle")
                Behavior on x {
                    NumberAnimation {
                        duration: Kirigami.Units.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }

        Label {
            id: chipLabel
            anchors.left: track.right
            anchors.leftMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            color: Kirigami.Theme.textColor
            opacity: chip.checked ? 1.0 : 0.65
            font: weatherRoot ? weatherRoot.wf(10, false) : Kirigami.Theme.smallFont
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (chip.enabled) chip.toggled(!chip.checked)
        }

        PlasmaComponents.ToolTip.visible: chipMouse.containsMouse && chip.tooltip.length > 0
        PlasmaComponents.ToolTip.text: chip.tooltip
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // ── Main layout ──────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // -- Layer mode selector (pill-tab style matching Details/Forecast/Radar tabs) --
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

        // -- Options: color scheme + mini switches (arrows, wind, cells, alerts, map theme) --
        // Hand-drawn mini switches instead of Plasma ones: half the height, so
        // the row stays one line high above the map at widget width.
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 2

            Label {
                visible: radarRoot.activeLayer !== "satellite"
                height: 22
                verticalAlignment: Text.AlignVCenter
                text: i18n("Palette:")
                color: Kirigami.Theme.textColor
                opacity: 0.72
                font: weatherRoot ? weatherRoot.wf(11, false) : Kirigami.Theme.smallFont
                height: schemeCombo.height
                verticalAlignment: Text.AlignVCenter
            }

            PlasmaComponents.ComboBox {
                id: schemeCombo
                visible: radarRoot.activeLayer !== "satellite"
                implicitHeight: 24
                Layout.maximumWidth: Kirigami.Units.gridUnit * 12
                font: weatherRoot ? weatherRoot.wf(10, false) : Kirigami.Theme.smallFont
                model: radarRoot.colorSchemes
                currentIndex: Math.max(0, Math.min(radarRoot.colorSchemes.length - 1, radarRoot.colorScheme))
                onActivated: {
                    Plasmoid.configuration.librewxrColorScheme = currentIndex;
                    webView.runJavaScript("window.setColorScheme(" + currentIndex + ");");
                }
            }

            OptionChip {
                visible: radarRoot.activeLayer !== "satellite"
                text: i18n("Arrows")
                checked: radarRoot.arrowsOn
                tooltip: i18n("Show motion arrows on the map")
                onToggled: function (on) {
                    Plasmoid.configuration.librewxrArrows = on;
                    webView.runJavaScript("window.setArrows(" + (on ? "true" : "false") + ");");
                }
            }

            OptionChip {
                text: i18n("Wind")
                checked: radarRoot.windOn
                tooltip: i18n("Animate the wind on the map (Open-Meteo)")
                onToggled: function (on) {
                    Plasmoid.configuration.librewxrWind = on;
                    webView.runJavaScript("if (window.setWind) window.setWind(" + (on ? "true" : "false") + ");");
                }
            }

            OptionChip {
                visible: radarRoot.windOn
                text: i18n("Aloft")
                checked: radarRoot.windLevel === "700hPa"
                tooltip: i18n("Show the wind at about 3000 m (700 hPa), the flow that steers the rain, instead of the surface wind at 10 m")
                onToggled: function (on) {
                    var level = on ? "700hPa" : "10m";
                    Plasmoid.configuration.librewxrWindLevel = level;
                    webView.runJavaScript("if (window.setWindLevel) window.setWindLevel(" + JSON.stringify(level) + ");");
                }
            }

            OptionChip {
                text: i18n("Storm cells")
                checked: radarRoot.activeCells !== ""
                tooltip: i18n("Overlay detected storm cells on the map")
                onToggled: function (on) {
                    // The stored value is the storm-cell overlay theme; pick
                    // the opposite of the map theme so the cells stand out.
                    var cells = on ? (radarRoot.mapTheme === "dark" ? "light" : "dark") : "";
                    Plasmoid.configuration.librewxrCells = cells;
                    webView.runJavaScript("if (window.setCells) window.setCells(" + JSON.stringify(cells) + ");");
                }
            }

            OptionChip {
                text: i18n("Alerts")
                checked: radarRoot.alertsOn
                tooltip: i18n("Show WMO alerts on the map")
                onToggled: function (on) {
                    Plasmoid.configuration.librewxrAlerts = on;
                    webView.runJavaScript("if (window.setAlerts) window.setAlerts(" + (on ? "true" : "false") + ");");
                }
            }

            OptionChip {
                text: i18n("Dark map")
                checked: radarRoot.mapTheme === "dark"
                enabled: !radarRoot.darkMapLocked
                tooltip: radarRoot.darkMapLocked ? i18n("Not available: the selected base map already has a fixed light or dark style.") : i18n("Switch between the light and dark map style. Until first toggled, the map follows the Plasma theme.")
                onToggled: function (on) {
                    // Manual choice overrides following the Plasma theme
                    // until the Plasma theme itself changes (see onIsDarkChanged)
                    Plasmoid.configuration.librewxrTheme = on ? "dark" : "light";
                    webView.runJavaScript("window.setTheme(" + JSON.stringify(on ? "dark" : "light") + ");");
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                text: i18n("Options")
                checkable: true
                checked: radarRoot.optionsExpanded
                onToggled: Plasmoid.configuration.librewxrOptionsExpanded = checked

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Show tile options: smoothing, snow mask, format and tile size")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        // -- Options panel: smoothing + snow mask (radar modes) + tile format + tile size --
        // Revealed by the Options toggle above; smoothing/snow only affect radar
        // tiles (see librewxr-map.html's buildTileUrl - the satellite branch
        // never reads state.smooth/state.snow), so those two switches hide for
        // the Satellite layer the same way the color scheme combo does above.
        // Format and tile size apply to both radar and satellite tiles.
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 2
            visible: radarRoot.optionsExpanded

            PlasmaComponents.Switch {
                visible: radarRoot.activeLayer !== "satellite"
                text: i18n("Smoothing")
                checked: radarRoot.smoothOn
                onToggled: {
                    Plasmoid.configuration.librewxrSmooth = checked;
                    webView.runJavaScript("if (window.setSmooth) window.setSmooth(" + (checked ? "true" : "false") + ");");
                }

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Smooth radar tile edges")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents.Switch {
                visible: radarRoot.activeLayer !== "satellite"
                text: i18n("Snow mask")
                checked: radarRoot.snowOn
                onToggled: {
                    Plasmoid.configuration.librewxrSnow = checked;
                    webView.runJavaScript("if (window.setSnow) window.setSnow(" + (checked ? "true" : "false") + ");");
                }

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Highlight snow and wintry precipitation with a distinct color")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            Label {
                text: i18n("Format:")
                color: Kirigami.Theme.textColor
                opacity: 0.72
                font: weatherRoot ? weatherRoot.wf(11, false) : Kirigami.Theme.smallFont
                height: formatCombo.height
                verticalAlignment: Text.AlignVCenter
            }

            PlasmaComponents.ComboBox {
                id: formatCombo
                Layout.maximumWidth: Kirigami.Units.gridUnit * 7
                model: radarRoot.tileFormats
                textRole: "label"
                currentIndex: {
                    for (var i = 0; i < radarRoot.tileFormats.length; i++)
                        if (radarRoot.tileFormats[i].id === radarRoot.tileFormat)
                            return i;
                    return 0;
                }
                onActivated: {
                    var v = radarRoot.tileFormats[currentIndex].id;
                    Plasmoid.configuration.librewxrFormat = v;
                    webView.runJavaScript("if (window.setFormat) window.setFormat(" + JSON.stringify(v) + ");");
                }
            }

            Label {
                text: i18n("Tile size:")
                color: Kirigami.Theme.textColor
                opacity: 0.72
                font: weatherRoot ? weatherRoot.wf(11, false) : Kirigami.Theme.smallFont
                height: tileSizeCombo.height
                verticalAlignment: Text.AlignVCenter
            }

            PlasmaComponents.ComboBox {
                id: tileSizeCombo
                Layout.maximumWidth: Kirigami.Units.gridUnit * 9
                model: radarRoot.tileSizes
                textRole: "label"
                currentIndex: {
                    for (var i = 0; i < radarRoot.tileSizes.length; i++)
                        if (radarRoot.tileSizes[i].id === radarRoot.tileSizeChoice)
                            return i;
                    return 0;
                }
                onActivated: {
                    var v = radarRoot.tileSizes[currentIndex].id;
                    Plasmoid.configuration.librewxrTileSize = v;
                    webView.runJavaScript("if (window.setTileSize) window.setTileSize(" + JSON.stringify(v) + ");");
                }
            }
        }

        // ── WebEngine map ─────────────────────────────────────────────
        WebEngineView {
            id: webView
            // Match the page's --bg so the uninitialized web surface does not flash white
            backgroundColor: radarRoot.isDark ? "#0f1117" : "#f0f2f5"
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
                if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    viewportFixTimer.restart();
                    // mapTheme can still flip while the page is loading: Kirigami
                    // reports a different background color early in startup, and
                    // the component is rebuilt every time the popup reopens. Those
                    // setTheme calls land on a page that does not exist yet and are
                    // lost, leaving the page on the theme frozen into its URL while
                    // the Dark map switch already shows the new one. Re-assert it
                    // here so the switch, the page and the "auto" background agree.
                    // No-op when they already match.
                    webView.runJavaScript("window.setTheme(" + JSON.stringify(radarRoot.mapTheme) + ");");
                }
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
                } else if (title.indexOf("bg:") === 0) {
                    // Picked from the in-map picker: the page already swapped
                    // its tiles, so persist the choice without reloading.
                    var bg = title.substring(3);
                    if (bg.length > 0 && bg !== Plasmoid.configuration.mapBackground) {
                        radarRoot._backgroundFromMap = true;
                        Plasmoid.configuration.mapBackground = bg;
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
                function onWindRateChanged() {
                    webView.runJavaScript("if (window.setWindRate) window.setWindRate(" + radarRoot.windRate[0] + "," + radarRoot.windRate[1] + ");");
                }
                function onMapBackgroundChanged() {
                    if (radarRoot._backgroundFromMap) {
                        // The map itself made the change; swapping tiles again
                        // would throw away the current pan and zoom.
                        radarRoot._backgroundFromMap = false;
                        return;
                    }
                    console.log("[Advanced Weather Widget Radar/LibreWXR] map background changed; background=", radarRoot.mapBackground);
                    webView.runJavaScript("window.setBackground(" + JSON.stringify(radarRoot.mapBackground) + ");");
                }
            }
        }
    }

    function reload() {
        radarRoot._loadPage("reload requested");
    }
}
