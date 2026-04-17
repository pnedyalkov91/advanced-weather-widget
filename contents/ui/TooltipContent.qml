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
import "js/suncalc.js" as SC
import "js/weather.js" as W
import "js/iconResolver.js" as IconResolver
import "js/configUtils.js" as ConfigUtils
import "components"

Item {
    id: ttRoot

    // ── Interface ─────────────────────────────────────────────────────────
    /** Reference to the PlasmoidItem root (set by CompactView) */
    property var weatherRoot

    // Respect the global tooltipEnabled setting: collapse to nothing when off.
    // (CompactView also sets active:false on the ToolTipArea, so the popup
    //  never opens at all.  This guard is a belt-and-suspenders fallback.)
    visible: Plasmoid.configuration.tooltipEnabled !== false

    // When truncating, cap tooltip width so the Label elide actually fires.
    // When wrapping, still cap at a reasonable max so very long names wrap
    // rather than making the tooltip absurdly wide.
    // ── Size config helpers ───────────────────────────────────────────
    readonly property bool ttWidthAuto: (Plasmoid.configuration.tooltipWidthMode || "auto") === "auto"
    readonly property bool ttHeightAuto: (Plasmoid.configuration.tooltipHeightMode || "auto") === "auto"
    readonly property int ttWidthManual: Plasmoid.configuration.tooltipWidthManual || 320
    readonly property int ttHeightManual: Plasmoid.configuration.tooltipHeightManual || 300
    // Auto width: fit content, min 280, max 480
    readonly property int ttMaxWidth: ttWidthAuto ? 480 : Math.max(200, ttWidthManual)

    // Track tooltip item count for auto-width sizing
    readonly property int _ttItemCount: ttIconRepeater.count
    // Estimate width from actual column count and icon size
    readonly property int _ttAutoWidth: {
        if (!ttUseIcons || _ttItemCount === 0)
            return 280;
        var effectiveCols = Math.min(3, _ttItemCount);
        // Each column: icon + 5px spacing + ~100px text + 10px col spacing
        var colW = ttIconSize + 5 + 100 + 10;
        return Math.max(280, effectiveCols * colW + 48);
    }

    // Using an Item root (not ColumnLayout) ensures implicitWidth/Height
    // are NOT overridden by the layout engine, so manual tooltip sizing works.
    implicitWidth: (Plasmoid.configuration.tooltipEnabled !== false)
        ? (ttWidthAuto
            ? Math.min(ttMaxWidth, _ttAutoWidth)
            : ttWidthManual)
        : 0
    implicitHeight: (Plasmoid.configuration.tooltipEnabled !== false)
        ? (ttHeightAuto
            ? Math.max(40, ttDataCol.implicitHeight + _headerHeight + 32)
            : ttHeightManual)
        : 0

    // Sum of header labels + separator — used in manual-height calculation
    readonly property int _headerHeight: _ttHeaderLabel.implicitHeight
        + ((_ttTimestamp.visible ? _ttTimestamp.implicitHeight : 0))
        + ((_ttNoLocHint.visible ? _ttNoLocHint.implicitHeight : 0))
        + 6 /* separator + margins */

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
    readonly property string ttMoonPhaseMode: Plasmoid.configuration.tooltipMoonPhaseMode || "full"

    readonly property string iconsBaseDir: Qt.resolvedUrl("../icons/")

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

    // Custom icon map helper — delegates to ConfigUtils.parseConfigMap()
    function getTooltipCustomIcon(itemId) {
        var m = ConfigUtils.parseConfigMap(Plasmoid.configuration.tooltipCustomIcons || "");
        return (itemId in m) ? m[itemId] : "";
    }

    // Returns { type, source, svgFallback, isMask } for a given token + ttIconTheme
    function ttItemIconInfo(tok) {
        var theme = ttIconTheme;

        if (theme === "wi-font") {
            var glyphs = {
                temperature: "\uF055",
                feelslike: "\uF053",
                condition: weatherRoot ? weatherRoot.panelItemGlyph("condition") : "\uF013",
                wind: "\uF050",
                humidity: "\uF07A",
                pressure: "\uF079",
                dewpoint: "\uF078",
                visibility: "\uF0B6",
                moonphase: Moon.moonPhaseFontIcon(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase)),
                "moonphase-moonrise": "\uF0C9",
                "moonphase-moonset": "\uF0CA",
                "suntimes-sunrise": "\uF051",
                "suntimes-sunset": "\uF052",
                preciprate: "\uF04E",
                precipsum: "\uF07C",
                uvindex: "\uF072",
                airquality: "\uF074",
                pollen:     "\uF082",
                spaceweather: "\uF06E",
                alerts: "\uF0CE",
                snowcover: "\uF076"
            };
            return { type: "wi", source: glyphs[tok] || "", svgFallback: "", isMask: false };
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
                "moonphase-moonrise": "weather-clear-night",
                "moonphase-moonset": "weather-clear-night",
                "suntimes-sunrise": "weather-sunrise",
                "suntimes-sunset": "weather-sunset",
                preciprate: "weather-showers",
                precipsum: "flood",
                uvindex: "weather-clear",
                airquality: "weather-many-clouds",
                pollen: "sandstorm",
                spaceweather: "solar-eclipse",
                alerts: "weather-storm",
                snowcover: "weather-snow-scattered"
            };
            // Moon phase token: use bundled SVG (shows actual phase) rather than custom icon
            if (tok === "moonphase") {
                var moonStemC = Moon.moonPhaseSvgStem(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
                return IconResolver.resolveMoonPhase(moonStemC, ttIconSize, ttRoot.iconsBaseDir, "flat-color");
            }
            var saved = getTooltipCustomIcon(tok);
            return { type: "kde", source: saved.length > 0 ? saved : (defaults[tok] || ""), svgFallback: "", isMask: false };
        }

        // KDE / SVG themes — unified via IconResolver
        // Pass theme directly; "kde" is handled by IconResolver internally.
        var svgTheme = theme;

        if (tok === "condition") {
            if (!weatherRoot)
                return { type: "kde", source: "weather-none-available", svgFallback: "", isMask: false };
            return IconResolver.resolveCondition(weatherRoot.weatherCode, weatherRoot.isNightTime(), ttIconSize, ttRoot.iconsBaseDir, svgTheme);
        }
        if (tok === "moonphase") {
            var moonStem = Moon.moonPhaseSvgStem(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
            return IconResolver.resolveMoonPhase(moonStem, ttIconSize, ttRoot.iconsBaseDir, svgTheme);
        }
        if (tok === "moonphase-moonrise")
            return IconResolver.resolve("moonrise", ttIconSize, ttRoot.iconsBaseDir, svgTheme);
        if (tok === "moonphase-moonset")
            return IconResolver.resolve("moonset", ttIconSize, ttRoot.iconsBaseDir, svgTheme);

        return IconResolver.resolve(tok, ttIconSize, ttRoot.iconsBaseDir, svgTheme);
    }

    // ── Inner layout — anchored to root Item for proper sizing ───────────
    ColumnLayout {
        id: ttLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 5

    // ── Header: location name ─────────────────────────────────────────────
    Label {
        id: _ttHeaderLabel
        Layout.fillWidth: true
        Layout.maximumWidth: ttRoot.ttMaxWidth - 24
        text: ttRoot.weatherRoot && ttRoot.weatherRoot.hasSelectedTown ? Plasmoid.configuration.locationName : i18n("Weather Widget")
        font.bold: true
        font.pixelSize: ttRoot.ttFont.pixelSize + 2
        font.family: ttRoot.ttFont.family
        color: Kirigami.Theme.textColor
        wrapMode: (Plasmoid.configuration.tooltipLocationWrap || "truncate") === "wrap" ? Text.WordWrap : Text.NoWrap
        elide: (Plasmoid.configuration.tooltipLocationWrap || "truncate") === "truncate" ? Text.ElideRight : Text.ElideNone
    }

    // ── Update timestamp ─────────────────────────────────────────────────
    Label {
        id: _ttTimestamp
        Layout.fillWidth: true
        visible: ttRoot.weatherRoot && ttRoot.weatherRoot.hasSelectedTown && ttRoot.weatherRoot.updateText.length > 0
        text: ttRoot.weatherRoot ? ttRoot.weatherRoot.updateText : ""
        textFormat: Text.RichText
        onLinkActivated: function(link) { Qt.openUrlExternally(link) }
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        color: Kirigami.Theme.disabledTextColor
        HoverHandler {
            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    // ── No-location hint ─────────────────────────────────────────────────
    Label {
        id: _ttNoLocHint
        Layout.fillWidth: true
        visible: !ttRoot.weatherRoot || !ttRoot.weatherRoot.hasSelectedTown
        text: i18n("Click to configure a location")
        color: Kirigami.Theme.disabledTextColor
    }

    // ── Separator ────────────────────────────────────────────────────────
    Rectangle {
        visible: ttRoot.weatherRoot && ttRoot.weatherRoot.hasSelectedTown
        Layout.fillWidth: true
        height: 1
        color: Kirigami.Theme.neutralTextColor
        Layout.topMargin: 1
        Layout.bottomMargin: 2
    }

    // ── Scrollable data area — height capped when Manual ──────────────
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: !ttRoot.ttHeightAuto
        // Auto: natural height. Manual: fill remaining space within the capped tooltip.
        implicitHeight: ttRoot.ttHeightAuto
            ? ttDataCol.implicitHeight
            : Math.min(Math.max(40, ttRoot.ttHeightManual - ttRoot._headerHeight - 16), ttDataCol.implicitHeight)
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ttRoot.ttHeightAuto
            ? ScrollBar.AlwaysOff
            : (ttDataCol.implicitHeight > (ttRoot.ttHeightManual - ttRoot._headerHeight - 16) ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff)

        ColumnLayout {
            id: ttDataCol
            width: parent.width
            spacing: 0

            // ── Data rows — ICONS MODE: 3-per-row grid ────────────────────────────
            GridLayout {
                id: ttContentCol
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 10
                rowSpacing: 6
                visible: ttRoot.weatherRoot && ttRoot.weatherRoot.hasSelectedTown && ttRoot.ttUseIcons

                Repeater {
                    id: ttIconRepeater
                    model: {
                        if (!ttRoot.weatherRoot || !ttRoot.ttUseIcons)
                            return [];
                        var _ = ttRoot.weatherRoot.weatherData + ttRoot.weatherRoot.moonriseTimeText.length + ttRoot.weatherRoot.moonsetTimeText.length + ttRoot.ttIconTheme + ttRoot.ttIconSize + ttRoot.ttSunTimesMode + ttRoot.ttMoonPhaseMode;
                        return ttRoot._buildTooltipItems();
                    }

                    delegate: RowLayout {
                        id: ttIconDelegate
                        required property var modelData
                        // Fill the grid cell so all 3 columns are equal width
                        Layout.fillWidth: true
                        spacing: 5

                        WeatherIcon {
                            visible: modelData.showIcon
                            iconInfo: modelData.iconInfo
                            iconSize: ttRoot.ttIconSize
                            wiFontFamily: wiFontTT.status === FontLoader.Ready ? wiFontTT.font.family : ""
                            wiFontReady: wiFontTT.status === FontLoader.Ready
                            Layout.alignment: Qt.AlignVCenter
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
                visible: ttRoot.weatherRoot && ttRoot.weatherRoot.hasSelectedTown && !ttRoot.ttUseIcons

                Repeater {
                    model: {
                        if (!ttRoot.weatherRoot || ttRoot.ttUseIcons)
                            return [];
                        var _ = ttRoot.weatherRoot.weatherData + ttRoot.weatherRoot.moonriseTimeText.length + ttRoot.weatherRoot.moonsetTimeText.length + ttRoot.ttSunTimesMode + ttRoot.ttMoonPhaseMode;
                        return ttRoot._buildTooltipItems();
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
        } // ttDataCol
    } // ScrollView

    } // ColumnLayout (ttLayout)

    // ── Private: build tooltip rows ───────────────────────────────────────
    function _buildTooltipItems() {
        if (!weatherRoot || !weatherRoot.hasSelectedTown)
            return [];
        var iconMap = ConfigUtils.parseBoolMap(Plasmoid.configuration.tooltipItemIcons || "");
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
     * Icons mode: { iconInfo, showIcon, text }
     * Text mode:  { iconInfo: null, showIcon: false, text: "Label: value" }
     */
    function _tooltipItemsFor(tok, iconMap) {
        var r = weatherRoot;
        var showIcon = ttUseIcons && ((tok in iconMap) ? iconMap[tok] : true);
        var textMode = !ttUseIcons;
        var emptyInfo = { type: "", source: "", svgFallback: "", isMask: false };

        function iconRow(iconTok, txt) {
            return { iconInfo: ttItemIconInfo(iconTok), showIcon: showIcon, text: txt };
        }
        function textRow(txt) {
            return { iconInfo: emptyInfo, showIcon: false, text: txt };
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
            var windInfo;
            if (ttIconTheme === "wi-font") {
                var g = isNaN(r.windDirection) ? "\uF050" : W.windDirectionGlyph(r.windDirection);
                windInfo = { type: "wi", source: g, svgFallback: "", isMask: false };
            } else {
                windInfo = ttItemIconInfo("wind");
            }
            return [{ iconInfo: windInfo, showIcon: showIcon, text: windTxt }];
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

        if (tok === "preciprate") {
            var pTxt = r.precipValue(r.precipMmh);
            return [row("preciprate", pTxt, i18n("Precipitation:") + " " + pTxt)];
        }

        if (tok === "precipsum") {
            var psTxt = r.precipSumText(r.precipSumMm);
            return [row("precipsum", psTxt, i18n("Precip. Sum:") + " " + psTxt)];
        }

        if (tok === "uvindex") {
            var uvTxt = r.uvIndexText(r.uvIndex);
            return [row("uvindex", uvTxt, i18n("UV Index:") + " " + uvTxt)];
        }

        if (tok === "airquality") {
            var aqTxt = r.airQualityText();
            return [row("airquality", aqTxt, i18n("Air Quality:") + " " + aqTxt)];
        }

        if (tok === "pollen") {
            var polTxt = r.pollenText();
            return [row("pollen", polTxt, i18n("Pollen:") + " " + polTxt)];
        }

        if (tok === "spaceweather") {
            var swTxt = r.spaceWeatherText();
            return [row("spaceweather", swTxt, i18n("Space Weather:") + " " + swTxt)];
        }

        if (tok === "alerts") {
            var alTxt = r.alertsText();
            return [row("alerts", alTxt, i18n("Alerts:") + " " + alTxt)];
        }

        if (tok === "snowcover") {
            var snTxt = r.snowDepthText(r.snowDepthCm);
            return [row("snowcover", snTxt, i18n("Snow Cover:") + " " + snTxt)];
        }

        if (tok === "moonphase") {
            var _age = Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase);
            var phaseName = i18n(Moon.moonPhaseNameKey(_age));
            var moonMode = ttMoonPhaseMode;
            var riseTime = r.formatTimeForDisplay(r.moonriseTimeText);
            var setTime = r.formatTimeForDisplay(r.moonsetTimeText);

            if (moonMode === "phase")
                return [row("moonphase", phaseName, i18n("Moon:") + " " + phaseName)];

            if (moonMode === "moonrise")
                return textMode ? [textRow(i18n("Moonrise:") + " " + riseTime)]
                    : [iconRow("moonphase-moonrise", riseTime)];

            if (moonMode === "moonset")
                return textMode ? [textRow(i18n("Moonset:") + " " + setTime)]
                    : [iconRow("moonphase-moonset", setTime)];

            if (moonMode === "upcoming-times") {
                // Show next moonrise or moonset
                function parseMoonMins(s) {
                    if (!s || s.indexOf(":") < 0) return -1;
                    var pts = s.split(":");
                    return parseInt(pts[0]) * 60 + parseInt(pts[1]);
                }
                var nowMM = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                var riseMM = parseMoonMins(r.moonriseTimeText);
                var setMM = parseMoonMins(r.moonsetTimeText);
                var useSetM = riseMM >= 0 && nowMM >= riseMM && (setMM < 0 || nowMM < setMM);
                if (useSetM)
                    return textMode ? [textRow(i18n("Moonset:") + " " + setTime)]
                        : [iconRow("moonphase-moonset", setTime)];
                else
                    return textMode ? [textRow(i18n("Moonrise:") + " " + riseTime)]
                        : [iconRow("moonphase-moonrise", riseTime)];
            }

            if (moonMode === "times") {
                // Moonrise + moonset only
                if (textMode) {
                    return [textRow(i18n("Moonrise:") + " " + riseTime), textRow(i18n("Moonset:") + " " + setTime)];
                }
                return [
                    { iconInfo: ttItemIconInfo("moonphase-moonrise"), showIcon: showIcon, text: riseTime },
                    { iconInfo: ttItemIconInfo("moonphase-moonset"), showIcon: showIcon, text: setTime }
                ];
            }

            if (moonMode === "upcoming") {
                // Phase + upcoming rise/set
                var rows2 = [row("moonphase", phaseName, i18n("Moon:") + " " + phaseName)];
                function parseMoonMins2(s) {
                    if (!s || s.indexOf(":") < 0) return -1;
                    var pts = s.split(":");
                    return parseInt(pts[0]) * 60 + parseInt(pts[1]);
                }
                var nowMM2 = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                var riseMM2 = parseMoonMins2(r.moonriseTimeText);
                var setMM2 = parseMoonMins2(r.moonsetTimeText);
                var useSetM2 = riseMM2 >= 0 && nowMM2 >= riseMM2 && (setMM2 < 0 || nowMM2 < setMM2);
                if (useSetM2)
                    rows2.push(textMode ? textRow(i18n("Moonset:") + " " + setTime)
                        : { iconInfo: ttItemIconInfo("moonphase-moonset"), showIcon: showIcon, text: setTime });
                else
                    rows2.push(textMode ? textRow(i18n("Moonrise:") + " " + riseTime)
                        : { iconInfo: ttItemIconInfo("moonphase-moonrise"), showIcon: showIcon, text: riseTime });
                return rows2;
            }

            // "full" (default): phase + moonrise + moonset
            if (textMode) {
                return [
                    textRow(i18n("Moon:") + " " + phaseName),
                    textRow(i18n("Moonrise:") + " " + riseTime),
                    textRow(i18n("Moonset:") + " " + setTime)
                ];
            }
            return [
                { iconInfo: ttItemIconInfo("moonphase"), showIcon: showIcon, text: phaseName },
                { iconInfo: ttItemIconInfo("moonphase-moonrise"), showIcon: showIcon, text: riseTime },
                { iconInfo: ttItemIconInfo("moonphase-moonset"), showIcon: showIcon, text: setTime }
            ];
        }

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
                return textMode ? [textRow(i18n("Sunrise:") + " " + riseTime)]
                    : [{ iconInfo: infoRise, showIcon: showIcon, text: riseTime }];
            }
            if (mode === "sunset") {
                return textMode ? [textRow(i18n("Sunset:") + " " + setTime)]
                    : [{ iconInfo: infoSet, showIcon: showIcon, text: setTime }];
            }
            if (mode === "upcoming") {
                var nowM = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                var riseM = parseMins(r.sunriseTimeText);
                var setM = parseMins(r.sunsetTimeText);
                var useSet = riseM >= 0 && nowM >= riseM && (setM < 0 || nowM < setM);
                if (useSet)
                    return textMode ? [textRow(i18n("Sunset:") + " " + setTime)]
                        : [{ iconInfo: infoSet, showIcon: showIcon, text: setTime }];
                else
                    return textMode ? [textRow(i18n("Sunrise:") + " " + riseTime)]
                        : [{ iconInfo: infoRise, showIcon: showIcon, text: riseTime }];
            }
            // "both" (default)
            if (textMode) {
                return [textRow(i18n("Sunrise:") + " " + riseTime), textRow(i18n("Sunset:") + " " + setTime)];
            }
            return [
                { iconInfo: infoRise, showIcon: showIcon, text: riseTime },
                { iconInfo: infoSet, showIcon: showIcon, text: setTime }
            ];
        }
        return [];
    }
}
