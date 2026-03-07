/**
 * TooltipContent.qml — Tooltip popup content
 *
 * Renders the rich tooltip with configurable icon themes + data values.
 * Receives weatherRoot to access live weather data and helper functions.
 * Supports the same icon themes as the Panel: wi-font, symbolic, flat-color,
 * 3d-oxygen, kde, and custom (user-picked KDE icons per item).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/moonphase.js" as Moon
import "js/weather.js" as W

ColumnLayout {
    id: ttRoot

    // ── Interface ─────────────────────────────────────────────────────────
    /** Reference to the PlasmoidItem root (set by CompactView) */
    property var weatherRoot

    // Respect the global tooltipEnabled setting: collapse to nothing when off.
    // (CompactView also sets active:false on the ToolTipArea, so the popup
    //  never opens at all.  This guard is a belt-and-suspenders fallback.)
    visible: Plasmoid.configuration.tooltipEnabled !== false
    spacing: 5
    implicitWidth: (Plasmoid.configuration.tooltipEnabled !== false) ? Math.max(280, ttContentCol.implicitWidth + 24) : 0

    // ── Wi-font loaded inside tooltip popup ───────────────────────────────
    FontLoader {
        id: wiFontTT
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    // ── Tooltip icon/font config helpers ─────────────────────────────────
    readonly property string ttIconTheme: Plasmoid.configuration.tooltipIconTheme || "wi-font"
    readonly property int ttIconSize: Plasmoid.configuration.tooltipIconSize || 22
    readonly property bool ttUseIcons: Plasmoid.configuration.tooltipUseIcons !== false
    readonly property string ttSunTimesMode: Plasmoid.configuration.tooltipSunTimesMode || "both"

    // FIX: Qt.resolvedUrl MUST be evaluated at component load time (here, as a property),
    // NOT inside a JS function. When TooltipContent is used as a Plasma tooltip mainItem
    // it runs in a detached window context where Qt.resolvedUrl("../...") inside a function
    // resolves relative to the window root (wrong path → file not found → blank icons).
    // A property-level Qt.resolvedUrl always resolves relative to this QML file (correct).
    readonly property url iconsBaseDir: Qt.resolvedUrl("../icons/")

    // Resolved icon font to use in tooltip rows
    readonly property font ttFont: {
        if (!Plasmoid.configuration.tooltipUseSystemFont && (Plasmoid.configuration.tooltipFontFamily || "").length > 0) {
            return Qt.font({
                family: Plasmoid.configuration.tooltipFontFamily,
                bold: Plasmoid.configuration.tooltipFontBold || false,
                pixelSize: Kirigami.Theme.defaultFont.pixelSize
            });
        }
        return Kirigami.Theme.defaultFont;
    }

    // Custom icon map helper
    function getTooltipCustomIcon(itemId) {
        var raw = Plasmoid.configuration.tooltipCustomIcons || "";
        if (raw.length === 0)
            return "";
        var m = {};
        raw.split(";").forEach(function (pair) {
            var kv = pair.split("=");
            if (kv.length === 2 && kv[0].trim().length > 0)
                m[kv[0].trim()] = kv[1].trim();
        });
        return (itemId in m) ? m[itemId] : "";
    }

    // Returns { type, source, kdeFallback } for a given token + ttIconTheme
    function ttItemIconInfo(tok) {
        var theme = ttIconTheme;

        if (theme === "wi-font") {
            // Return the same wi-font codepoints used historically
            var glyphs = {
                temperature: "\uF055",
                feelslike: "\uF053",
                condition: "\uF013",
                wind: "\uF050",
                humidity: "\uF07A",
                pressure: "\uF079",
                dewpoint: "\uF078",
                visibility: "\uF0B6",
                moonphase: Moon.moonPhaseFontIcon(),
                "suntimes-sunrise": "\uF051",
                "suntimes-sunset": "\uF052"
            };
            return {
                type: "wi",
                source: glyphs[tok] || "",
                kdeFallback: ""
            };
        }

        if (theme === "custom") {
            var defaults = {
                temperature: "thermometer",
                feelslike: "thermometer",
                condition: W.weatherCodeToIcon(weatherRoot ? weatherRoot.weatherCode : -1, weatherRoot ? weatherRoot.isNightTime() : false),
                wind: "weather-windy",
                humidity: "weather-showers",
                pressure: "weather-overcast",
                dewpoint: "raindrop",
                visibility: "weather-fog",
                moonphase: "weather-clear-night",
                "suntimes-sunrise": "weather-sunrise",
                "suntimes-sunset": "weather-sunset"
            };
            var saved = getTooltipCustomIcon(tok);
            return {
                type: "kde",
                source: saved.length > 0 ? saved : (defaults[tok] || ""),
                kdeFallback: ""
            };
        }

        if (theme === "kde") {
            var kdeMap = {
                temperature: "thermometer",
                feelslike: "thermometer",
                wind: "weather-wind-beaufort-0",
                humidity: "weather-humidity",
                pressure: "weather-pressure",
                dewpoint: "raindrop",
                visibility: "weather-fog",
                moonphase: "weather-clear-night",
                "suntimes-sunrise": "weather-sunrise",
                "suntimes-sunset": "weather-sunset"
            };
            if (tok === "condition")
                return {
                    type: "kde",
                    source: weatherRoot ? W.weatherCodeToIcon(weatherRoot.weatherCode, weatherRoot.isNightTime()) : "weather-none-available",
                    kdeFallback: ""
                };
            return {
                type: "kde",
                source: kdeMap[tok] || "",
                kdeFallback: ""
            };
        }

        // ── SVG themes ────────────────────────────────────────────────────
        // Use iconsBaseDir (resolved at load time) — do NOT call Qt.resolvedUrl() here;
        // inside a JS function in a detached tooltip context the base path is wrong.
        var base = ttRoot.iconsBaseDir + theme + "/" + ttIconSize + "/wi-";

        var svgMap = {
            temperature: "thermometer",
            feelslike: "thermometer",
            humidity: "humidity",
            pressure: "barometer",
            wind: "strong-wind",
            dewpoint: "raindrop",
            visibility: "thermometer",
            moonphase: Moon.moonPhaseSvgStem(),
            "suntimes-sunrise": "sunrise",
            "suntimes-sunset": "sunset"
        };
        if (tok === "condition") {
            if (!weatherRoot)
                return {
                    type: "svg",
                    source: "",
                    kdeFallback: ""
                };
            var code = weatherRoot.weatherCode, night = weatherRoot.isNightTime(), stem;
            if (code === 0)
                stem = night ? "night-clear" : "day-sunny";
            else if (code <= 2)
                stem = night ? "night-alt-partly-cloudy" : "day-cloudy";
            else if (code === 3)
                stem = "cloudy";
            else if (code <= 48)
                stem = night ? "night-fog" : "day-fog";
            else if (code <= 65)
                stem = night ? "night-alt-rain" : "day-rain";
            else if (code <= 75)
                stem = night ? "night-alt-snow" : "day-snow";
            else
                stem = night ? "night-alt-thunderstorm" : "day-thunderstorm";
            return {
                type: "svg",
                source: base + stem + ".svg",
                kdeFallback: ""
            };
        }
        var s = svgMap[tok];
        // wi-sunrise.svg and wi-sunset.svg exist in all SVG theme packs — no kdeFallback needed
        return {
            type: "svg",
            source: s ? base + s + ".svg" : "",
            kdeFallback: ""
        };
    }

    // ── Header: location name ─────────────────────────────────────────────
    Label {
        Layout.fillWidth: true
        text: weatherRoot && weatherRoot.hasSelectedTown ? Plasmoid.configuration.locationName : i18n("Weather Widget")
        font.bold: true
        font.pixelSize: ttRoot.ttFont.pixelSize + 2
        font.family: ttRoot.ttFont.family
        color: Kirigami.Theme.textColor
        wrapMode: Text.NoWrap
    }

    // ── Update timestamp ─────────────────────────────────────────────────
    Label {
        Layout.fillWidth: true
        visible: weatherRoot && weatherRoot.hasSelectedTown && weatherRoot.updateText.length > 0
        text: weatherRoot ? weatherRoot.updateText : ""
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        color: Kirigami.Theme.disabledTextColor
    }

    // ── No-location hint ─────────────────────────────────────────────────
    Label {
        Layout.fillWidth: true
        visible: !weatherRoot || !weatherRoot.hasSelectedTown
        text: i18n("Click to configure a location")
        color: Kirigami.Theme.disabledTextColor
    }

    // ── Separator ────────────────────────────────────────────────────────
    Rectangle {
        visible: weatherRoot && weatherRoot.hasSelectedTown
        Layout.fillWidth: true
        height: 1
        color: Kirigami.Theme.separatorColor
        Layout.topMargin: 1
        Layout.bottomMargin: 2
    }

    // ── Data rows — ICONS MODE: 3-per-row grid ────────────────────────────
    GridLayout {
        id: ttContentCol
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 10
        rowSpacing: 6
        visible: weatherRoot && weatherRoot.hasSelectedTown && ttUseIcons

        Repeater {
            model: {
                if (!weatherRoot || !ttUseIcons)
                    return [];
                var _ = weatherRoot.temperatureC + weatherRoot.windKmh + weatherRoot.windDirection + weatherRoot.humidityPercent + weatherRoot.pressureHpa + weatherRoot.weatherCode + weatherRoot.sunriseTimeText.length + weatherRoot.sunsetTimeText.length + ttIconTheme + ttIconSize + ttSunTimesMode;
                return _buildTooltipItems();
            }

            delegate: RowLayout {
                required property var modelData
                // Fill the grid cell so all 3 columns are equal width
                Layout.fillWidth: true
                spacing: 5

                // ── wi-font glyph ─────────────────────────────────────────
                Text {
                    visible: modelData.showIcon && modelData.glyphType === "wi" && (modelData.glyph || "").length > 0
                    text: modelData.glyph || ""
                    font.family: wiFontTT.status === FontLoader.Ready ? wiFontTT.font.family : ""
                    font.pixelSize: ttRoot.ttFont.pixelSize + 2
                    color: Kirigami.Theme.textColor
                    verticalAlignment: Text.AlignVCenter
                }

                // ── KDE icon ──────────────────────────────────────────────
                Kirigami.Icon {
                    visible: modelData.showIcon && modelData.glyphType === "kde" && (modelData.glyph || "").length > 0
                    source: modelData.glyph || ""
                    implicitWidth: ttRoot.ttIconSize
                    implicitHeight: ttRoot.ttIconSize
                    Layout.alignment: Qt.AlignVCenter
                }

                // ── SVG icon ──────────────────────────────────────────────
                Item {
                    visible: modelData.showIcon && modelData.glyphType === "svg" && (modelData.glyph || "").length > 0
                    implicitWidth: ttRoot.ttIconSize
                    implicitHeight: ttRoot.ttIconSize
                    Layout.alignment: Qt.AlignVCenter
                    Kirigami.Icon {
                        anchors.fill: parent
                        source: modelData.glyphKdeFallback || ""
                        visible: (modelData.glyphKdeFallback || "").length > 0
                    }
                    Kirigami.Icon {
                        anchors.fill: parent
                        source: modelData.glyph || ""
                        isMask: ttRoot.ttIconTheme === "symbolic"
                        color: Kirigami.Theme.textColor
                    }
                }

                // ── Value text ────────────────────────────────────────────
                Label {
                    Layout.fillWidth: true
                    text: modelData.text || ""
                    color: Kirigami.Theme.textColor
                    font: ttRoot.ttFont
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ── Data rows — TEXT MODE: one labelled row per item ──────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        visible: weatherRoot && weatherRoot.hasSelectedTown && !ttUseIcons

        Repeater {
            model: {
                if (!weatherRoot || ttUseIcons)
                    return [];
                var _ = weatherRoot.temperatureC + weatherRoot.windKmh + weatherRoot.windDirection + weatherRoot.humidityPercent + weatherRoot.pressureHpa + weatherRoot.weatherCode + weatherRoot.sunriseTimeText.length + weatherRoot.sunsetTimeText.length + ttSunTimesMode;
                return _buildTooltipItems();
            }

            delegate: Label {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.text || ""
                color: Kirigami.Theme.textColor
                font: ttRoot.ttFont
                wrapMode: Text.NoWrap
            }
        }
    }

    // ── Private: build tooltip rows ───────────────────────────────────────
    function _buildTooltipItems() {
        if (!weatherRoot || !weatherRoot.hasSelectedTown)
            return [];
        var iconMap = {};
        var raw = Plasmoid.configuration.tooltipItemIcons || "";
        if (raw.length > 0) {
            raw.split(";").forEach(function (pair) {
                var kv = pair.split("=");
                if (kv.length === 2)
                    iconMap[kv[0].trim()] = (kv[1].trim() === "1");
            });
        }
        var order = (Plasmoid.configuration.tooltipItemOrder || "temperature;wind;humidity;pressure;suntimes").split(";").filter(function (t) {
            return t.trim().length > 0;
        });
        var rows = [];
        order.forEach(function (tok) {
            _tooltipItemsFor(tok.trim(), iconMap).forEach(function (row) {
                rows.push(row);
            });
        });
        return rows;
    }

    /**
     * Returns 1–2 row objects for a given token.
     * Icons mode: { glyph, glyphType, glyphKdeFallback, showIcon, text }
     * Text mode:  { glyph: "", glyphType: "", glyphKdeFallback: "", showIcon: false, text: "Label: value" }
     */
    function _tooltipItemsFor(tok, iconMap) {
        var r = weatherRoot;
        var showIcon = ttUseIcons && ((tok in iconMap) ? iconMap[tok] : true);
        var textMode = !ttUseIcons;

        function iconRow(iconTok, txt) {
            var info = ttItemIconInfo(iconTok);
            return {
                glyph: info.source,
                glyphType: info.type,
                glyphKdeFallback: info.kdeFallback,
                showIcon: showIcon,
                text: txt
            };
        }
        function textRow(txt) {
            return {
                glyph: "",
                glyphType: "",
                glyphKdeFallback: "",
                showIcon: false,
                text: txt
            };
        }
        function row(iconTok, iconText, labelText) {
            return textMode ? textRow(labelText) : iconRow(iconTok, iconText);
        }

        if (tok === "temperature")
            return [row("temperature", r.tempValue(r.temperatureC), i18n("Temperature:") + " " + r.tempValue(r.temperatureC))];

        if (tok === "feelslike")
            return [row("feelslike", r.tempValue(r.apparentC), i18n("Feels like:") + " " + r.tempValue(r.apparentC))];

        if (tok === "condition")
            return [row("condition", r.weatherCodeToText(r.weatherCode, r.isNightTime()), i18n("Condition:") + " " + r.weatherCodeToText(r.weatherCode, r.isNightTime()))];

        if (tok === "wind") {
            var windTxt = r.windValue(r.windKmh);
            if (textMode)
                return [textRow(i18n("Wind:") + " " + windTxt)];
            // Icons mode: use wind-direction glyph for wi-font
            var glyph, type, kdf;
            if (ttIconTheme === "wi-font") {
                glyph = isNaN(r.windDirection) ? "\uF050" : W.windDirectionGlyph(r.windDirection);
                type = "wi";
                kdf = "";
            } else {
                var info = ttItemIconInfo("wind");
                glyph = info.source;
                type = info.type;
                kdf = info.kdeFallback;
            }
            return [
                {
                    glyph: glyph,
                    glyphType: type,
                    glyphKdeFallback: kdf,
                    showIcon: showIcon,
                    text: windTxt
                }
            ];
        }

        if (tok === "humidity")
            return [row("humidity", isNaN(r.humidityPercent) ? "--" : r.humidityPercent.toFixed(1) + "%", i18n("Humidity:") + " " + (isNaN(r.humidityPercent) ? "--" : r.humidityPercent.toFixed(1) + "%"))];

        if (tok === "pressure")
            return [row("pressure", r.pressureValue(r.pressureHpa), i18n("Pressure:") + " " + r.pressureValue(r.pressureHpa))];

        if (tok === "dewpoint")
            return [row("dewpoint", r.tempValue(r.dewPointC), i18n("Dew point:") + " " + r.tempValue(r.dewPointC))];

        if (tok === "visibility") {
            var visTxt = isNaN(r.visibilityKm) ? "--" : r.visibilityKm.toFixed(1) + " km";
            return [row("visibility", visTxt, i18n("Visibility:") + " " + visTxt)];
        }

        if (tok === "moonphase")
            return [row("moonphase", i18n(Moon.moonPhaseNameKey()), i18n("Moon:") + " " + i18n(Moon.moonPhaseNameKey()))];

        if (tok === "suntimes") {
            var mode = ttSunTimesMode;
            var infoRise = ttItemIconInfo("suntimes-sunrise");
            var infoSet = ttItemIconInfo("suntimes-sunset");
            var riseTime = r.formatTimeForDisplay(r.sunriseTimeText);
            var setTime = r.formatTimeForDisplay(r.sunsetTimeText);

            // Helper: parse "HH:MM" → total minutes for upcoming logic
            function parseMins(s) {
                if (!s || s.indexOf(":") < 0)
                    return -1;
                var parts = s.split(":");
                return parseInt(parts[0]) * 60 + parseInt(parts[1]);
            }

            if (mode === "sunrise") {
                return textMode ? [textRow(i18n("Sunrise:") + " " + riseTime)] : [
                    {
                        glyph: infoRise.source,
                        glyphType: infoRise.type,
                        glyphKdeFallback: infoRise.kdeFallback,
                        showIcon: showIcon,
                        text: riseTime
                    }
                ];
            }
            if (mode === "sunset") {
                return textMode ? [textRow(i18n("Sunset:") + " " + setTime)] : [
                    {
                        glyph: infoSet.source,
                        glyphType: infoSet.type,
                        glyphKdeFallback: infoSet.kdeFallback,
                        showIcon: showIcon,
                        text: setTime
                    }
                ];
            }
            if (mode === "upcoming") {
                var nowM = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                var riseM = parseMins(r.sunriseTimeText);
                var setM = parseMins(r.sunsetTimeText);
                var useSet = riseM >= 0 && nowM >= riseM && (setM < 0 || nowM < setM);
                if (useSet)
                    return textMode ? [textRow(i18n("Sunset:") + " " + setTime)] : [
                        {
                            glyph: infoSet.source,
                            glyphType: infoSet.type,
                            glyphKdeFallback: infoSet.kdeFallback,
                            showIcon: showIcon,
                            text: setTime
                        }
                    ];
                else
                    return textMode ? [textRow(i18n("Sunrise:") + " " + riseTime)] : [
                        {
                            glyph: infoRise.source,
                            glyphType: infoRise.type,
                            glyphKdeFallback: infoRise.kdeFallback,
                            showIcon: showIcon,
                            text: riseTime
                        }
                    ];
            }
            // "both" (default)
            if (textMode) {
                return [textRow(i18n("Sunrise:") + " " + riseTime), textRow(i18n("Sunset:") + " " + setTime)];
            }
            return [
                {
                    glyph: infoRise.source,
                    glyphType: infoRise.type,
                    glyphKdeFallback: infoRise.kdeFallback,
                    showIcon: showIcon,
                    text: riseTime
                },
                {
                    glyph: infoSet.source,
                    glyphType: infoSet.type,
                    glyphKdeFallback: infoSet.kdeFallback,
                    showIcon: showIcon,
                    text: setTime
                }
            ];
        }
        return [];
    }
}
