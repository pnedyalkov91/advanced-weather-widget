/**
 * DetailsView.qml — Dynamic "Details" tab content for the popup
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W
import "js/moonphase.js" as Moon

Item {
    id: root
    property var weatherRoot

    // Helper: true if weatherRoot exists and has a valid (non-NaN) temperature
    readonly property bool hasData: weatherRoot && !isNaN(weatherRoot.temperatureC)

    // Implicit height based on content (ScrollView's contentHeight) or empty label
    implicitHeight: Math.max(hasData ? detailsScroll.contentHeight : (emptyLabel.implicitHeight + 40), 50)

    // Font for weather icons
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    // ── Icon size from configuration ──────────────────────────────────────
    readonly property int iconSize: Plasmoid.configuration.widgetIconSize || 16

    // ── Theme helper — true when KDE is using a dark colour scheme ────────
    readonly property bool isDark: Kirigami.Theme.textColor.r > 0.5

    // ── Colour palette — adapts to dark / light theme ─────────────────────
    readonly property color cardBg: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
    readonly property color cardBorder: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)
    readonly property color valueColor: Kirigami.Theme.textColor

    // Accent colours — shift toward darker hues on light themes for contrast
    readonly property color accentBlue: isDark ? "#5ea8ff" : "#1a6fcc"
    readonly property color accentWarm: isDark ? "#ffb347" : "#b86000"
    readonly property color accentTeal: isDark ? "#4ecdc4" : "#007070"
    readonly property color accentGold: isDark ? "#ffcf63" : "#9c7400"
    readonly property color accentOrange: isDark ? "#ff8c52" : "#c04000"
    readonly property color accentViolet: isDark ? "#c4b4ff" : "#5030a0"

    // ── icon theme ────────────────────────────────────────────────────────
    readonly property string iconTheme: Plasmoid.configuration.widgetIconTheme || "kde"
    readonly property int iconSz: iconSize
    readonly property bool isList: (Plasmoid.configuration.widgetDetailsLayout || "cards2") === "list"

    // Resolved SVG URL for non-kde/wi-font themes
    function svgIconUrl(filename) {
        if (iconTheme === "kde" || iconTheme === "wi-font")
            return "";
        return Qt.resolvedUrl("../icons/" + iconTheme + "/" + iconSize + "/" + filename);
    }

    // ── Lookup tables ─────────────────────────────────────────────────────
    function wiGlyph(id) {
        return ({
                feelslike: "\uF055",
                humidity: "\uF07A",
                pressure: "\uF079",
                wind: "\uF050",
                suntimes: "\uF051",
                dewpoint: "\uF078",
                visibility: "\uF0B6",
                moonphase: "\uF0D0",
                condition: "\uF013"
            })[id] || "\uF00D";
    }
    function wiFile(id) {
        return ({
                feelslike: "wi-thermometer.svg",
                humidity: "wi-humidity.svg",
                pressure: "wi-barometer.svg",
                wind: "wi-strong-wind.svg",
                suntimes: "wi-sunrise.svg",
                dewpoint: "wi-raindrop.svg",
                visibility: "wi-fog.svg",
                moonphase: "wi-wi-moon-alt-full.svg",
                condition: "wi-day-sunny.svg"
            })[id] || "wi-na.svg";
    }
    function kdeIcon(id) {
        return ({
                feelslike: "thermometer",
                humidity: "weather-humidity",
                pressure: "weather-pressure",
                wind: "weather-windy",
                suntimes: "weather-sunrise",
                dewpoint: "weather-dew-point",
                visibility: "weather-fog",
                moonphase: "weather-clear-night",
                condition: "weather-few-clouds"
            })[id] || "weather-none-available";
    }
    function accentFor(id) {
        return ({
                feelslike: root.accentWarm,
                humidity: root.accentBlue,
                pressure: root.accentTeal,
                wind: root.accentBlue,
                suntimes: root.accentGold,
                dewpoint: root.accentTeal,
                visibility: Kirigami.Theme.textColor,
                moonphase: root.accentViolet,
                condition: Kirigami.Theme.textColor
            })[id] || root.accentBlue;
    }
    function labelFor(id) {
        return ({
                feelslike: i18n("Feels Like"),
                humidity: i18n("Humidity"),
                pressure: i18n("Pressure"),
                wind: i18n("Wind"),
                suntimes: i18n("Sunrise/Sunset"),
                dewpoint: i18n("Dew Point"),
                visibility: i18n("Visibility"),
                moonphase: i18n("Moon Phase"),
                condition: i18n("Condition")
            })[id] || id;
    }
    function dataValue(id) {
        if (!weatherRoot)
            return "--";
        switch (id) {
        case "feelslike":
            return weatherRoot.tempValue(weatherRoot.apparentC);
        case "humidity":
            return isNaN(weatherRoot.humidityPercent) ? "--" : Math.round(weatherRoot.humidityPercent) + "%";
        case "pressure":
            return weatherRoot.pressureValue(weatherRoot.pressureHpa);
        case "dewpoint":
            return weatherRoot.tempValue(weatherRoot.dewPointC);
        case "visibility":
            return isNaN(weatherRoot.visibilityKm) ? "--" : weatherRoot.visibilityKm.toFixed(1) + " km";
        case "condition":
            return weatherRoot.weatherCodeToText(weatherRoot.weatherCode, weatherRoot.isNightTime());
        case "wind":
            // Wind is handled specially in the card
            return "";
        case "suntimes":
            // Handled in expanded card
            return "";
        case "moonphase":
            // Handled in expanded card
            return "";
        default:
            return "";
        }
    }

    // List of detail IDs in configured order
    property var detailIds: (Plasmoid.configuration.widgetDetailsOrder || "feelslike;humidity;pressure;wind;suntimes;dewpoint;visibility;moonphase").split(";").map(s => s.trim()).filter(s => s.length > 0)

    // Build rows: each row is an array of 1 or 2 IDs
    function buildRows() {
        var order = (Plasmoid.configuration.widgetDetailsOrder || "feelslike;humidity;pressure;wind;suntimes;dewpoint;visibility;moonphase").split(";").map(function (s) {
            return s.trim();
        }).filter(function (s) {
            return s.length > 0;
        });
        var rows = [];
        var i = 0;
        if (root.isList) {
            while (i < detailIds.length) {
                rows.push([detailIds[i]]);
                i++;
            }
        } else {
            while (i < detailIds.length) {
                if (i + 1 < detailIds.length) {
                    rows.push([detailIds[i], detailIds[i + 1]]);
                    i += 2;
                } else {
                    rows.push([detailIds[i]]);
                    i++;
                }
            }
        }
        return rows;
    }

    // ── empty state ───────────────────────────────────────────────────────
    Label {
        id: emptyLabel
        anchors.centerIn: parent
        visible: !root.hasData
        text: (weatherRoot && weatherRoot.loading) ? i18n("Loading details…") : i18n("No details data")
        color: Kirigami.Theme.textColor
        opacity: 0.4
        font: weatherRoot ? weatherRoot.wf(12, false) : Qt.font({})
    }

    // ── UI when data exists ───────────────────────────────────────────────
    ScrollView {
        id: detailsScroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        visible: root.hasData

        Column {
            id: detailsColumn
            width: parent.width
            spacing: 8
            bottomPadding: 4

            Repeater {
                model: root.buildRows()

                delegate: RowLayout {
                    id: rowItem
                    required property var modelData   // array of 1 or 2 IDs
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: rowItem.modelData

                        delegate: Rectangle {
                            id: card
                            required property string modelData   // the detail ID

                            // Card height
                            readonly property bool isExpandedCard: card.modelData === "suntimes" || card.modelData === "moonphase"
                            readonly property int autoHeight: isExpandedCard ? 80 : 52
                            Layout.fillWidth: true
                            Layout.preferredHeight: Plasmoid.configuration.widgetCardsHeightAuto ? autoHeight : Plasmoid.configuration.widgetCardsHeight
                            radius: root.isList ? 6 : 10
                            color: root.cardBg
                            border.color: root.cardBorder
                            border.width: 1

                            // Standard item: single row
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8
                                visible: !card.isExpandedCard && card.modelData !== "wind"

                                // Icon
                                Text {
                                    visible: root.iconTheme === "wi-font" && wiFont.status === FontLoader.Ready
                                    text: root.wiGlyph(card.modelData)
                                    font.family: wiFont.font.family
                                    font.pixelSize: root.iconSize
                                    color: root.accentFor(card.modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Kirigami.Icon {
                                    visible: root.iconTheme === "kde"
                                    source: root.kdeIcon(card.modelData)
                                    implicitWidth: root.iconSize
                                    implicitHeight: root.iconSize
                                    color: root.accentFor(card.modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Kirigami.Icon {
                                    visible: root.iconTheme !== "kde" && root.iconTheme !== "wi-font"
                                    source: root.svgIconUrl(root.wiFile(card.modelData))
                                    isMask: root.iconTheme === "symbolic"
                                    color: root.iconTheme === "symbolic" ? Kirigami.Theme.textColor : "transparent"
                                    implicitWidth: root.iconSize
                                    implicitHeight: root.iconSize
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                // label (dim)
                                Label {
                                    text: root.labelFor(card.modelData) + ":"
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.55
                                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                // scalar value
                                Label {
                                    visible: card.modelData !== "wind"
                                    text: root.dataValue(card.modelData)
                                    color: root.valueColor
                                    font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                        bold: true
                                    })
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            // Wind special (icon + speed + arrow)
                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8
                                visible: card.modelData === "wind"

                                // Icon (same as above)
                                Text {
                                    visible: root.iconTheme === "wi-font" && wiFont.status === FontLoader.Ready
                                    text: root.wiGlyph("wind")
                                    font.family: wiFont.font.family
                                    font.pixelSize: root.iconSize
                                    color: root.accentFor("wind")
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Kirigami.Icon {
                                    visible: root.iconTheme === "kde"
                                    source: root.kdeIcon("wind")
                                    implicitWidth: root.iconSize
                                    implicitHeight: root.iconSize
                                    color: root.accentFor("wind")
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Kirigami.Icon {
                                    visible: root.iconTheme !== "kde" && root.iconTheme !== "wi-font"
                                    source: root.svgIconUrl(root.wiFile("wind"))
                                    isMask: root.iconTheme === "symbolic"
                                    color: root.iconTheme === "symbolic" ? Kirigami.Theme.textColor : "transparent"
                                    implicitWidth: root.iconSize
                                    implicitHeight: root.iconSize
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Label {
                                    text: root.labelFor("wind") + ":"
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.55
                                    font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                // Speed and arrow
                                RowLayout {
                                    visible: card.modelData === "wind"
                                    spacing: 6
                                    Label {
                                        text: weatherRoot ? weatherRoot.windValue(weatherRoot.windKmh) : "--"
                                        color: root.valueColor
                                        font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                            bold: true
                                        })
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Text {
                                        visible: weatherRoot && !isNaN(weatherRoot.windDirection)
                                        text: W.windDirectionGlyph(weatherRoot.windDirection)
                                        font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                        font.pixelSize: root.iconSize
                                        color: Kirigami.Theme.textColor
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            } // RowLayout (standard)

                            // ═══════════════════════════════════════════════════
                            // Suntimes: [icon  Sunrise/Sunset] / [↑ time  |  ↓ time]
                            // ═══════════════════════════════════════════════════
                            Item {
                                anchors.fill: parent
                                visible: card.modelData === "suntimes"
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 20
                                    spacing: 4  // reduced from 4 to bring rows closer

                                    // Row 1: prefix icon + dim label
                                    RowLayout {
                                        width: parent.width
                                        spacing: 5

                                        Text {
                                            visible: root.iconTheme === "wi-font" && wiFont.status === FontLoader.Ready
                                            text: "\uF051"
                                            font.family: wiFont.font.family
                                            font.pixelSize: root.iconSize
                                            color: root.accentGold
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Kirigami.Icon {
                                            visible: root.iconTheme !== "wi-font"
                                            source: root.iconTheme === "kde" ? "weather-sunrise" : root.svgIconUrl("wi-sunrise.svg")
                                            isMask: root.iconTheme === "symbolic"
                                            color: root.iconTheme === "symbolic" ? Kirigami.Theme.textColor : "transparent"
                                            implicitWidth: root.iconSize
                                            implicitHeight: root.iconSize
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Label {
                                            text: root.labelFor("suntimes")
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }

                                    // Row 2: sunrise  |  sunset
                                    RowLayout {
                                        width: parent.width
                                        spacing: 10   // small gap between items (adjust as desired)

                                        // Sunrise icon (wi‑font)
                                        Text {
                                            visible: wiFont.status === FontLoader.Ready
                                            text: "\uF051"
                                            font.family: wiFont.font.family
                                            font.pixelSize: Math.round(root.iconSize * 0.7)
                                            color: root.accentGold
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 2   // tiny left margin from card edge
                                        }
                                        // Fallback sunrise icon (SVG) – scaled
                                        Kirigami.Icon {
                                            visible: wiFont.status !== FontLoader.Ready
                                            source: root.iconTheme === "kde" ? "weather-sunrise" : root.svgIconUrl("wi-sunrise.svg")
                                            isMask: root.iconTheme === "symbolic"
                                            color: root.iconTheme === "symbolic" ? Kirigami.Theme.textColor : "transparent"
                                            implicitWidth: Math.round(root.iconSize * 0.7)   // ✅ match scaled size
                                            implicitHeight: Math.round(root.iconSize * 0.7)
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 2
                                        }

                                        // Sunrise time
                                        Label {
                                            text: weatherRoot ? weatherRoot.formatTimeForDisplay(weatherRoot.sunriseTimeText) : "--"
                                            color: root.accentGold
                                            font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                                bold: true
                                            })
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        // Separator between sunrise and sunset
                                        Rectangle {
                                            width: 1
                                            height: root.iconSize
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.25
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 10
                                            Layout.rightMargin: 10
                                        }

                                        // Sunset icon (wi‑font)
                                        Text {
                                            visible: wiFont.status === FontLoader.Ready
                                            text: "\uF052"
                                            font.family: wiFont.font.family
                                            font.pixelSize: Math.round(root.iconSize * 0.7)
                                            color: root.accentOrange
                                            Layout.alignment: Qt.AlignVCenter          // ✅ added
                                        }
                                        // Fallback sunset icon (SVG) – scaled
                                        Kirigami.Icon {
                                            visible: wiFont.status !== FontLoader.Ready
                                            source: root.iconTheme === "kde" ? "weather-sunset" : root.svgIconUrl("wi-sunset.svg")
                                            isMask: root.iconTheme === "symbolic"
                                            color: root.iconTheme === "symbolic" ? Kirigami.Theme.textColor : "transparent"
                                            implicitWidth: Math.round(root.iconSize * 0.7)   // ✅ match scaled size
                                            implicitHeight: Math.round(root.iconSize * 0.7)
                                            Layout.alignment: Qt.AlignVCenter          // ✅ added
                                        }

                                        // Sunset time
                                        Label {
                                            text: weatherRoot ? weatherRoot.formatTimeForDisplay(weatherRoot.sunsetTimeText) : "--"
                                            color: root.accentOrange
                                            font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                                bold: true
                                            })
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        // Absorb leftover space so items stay packed left
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            } // Item (suntimes)

                            // ═══════════════════════════════════════════════════
                            // Moon Phase: [icon  Moon Phase] / [glyph  phase name]
                            // ═══════════════════════════════════════════════════
                            Item {
                                anchors.fill: parent
                                visible: card.modelData === "moonphase"
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 20          // consistent 10px padding on each side
                                    spacing: 2                        // small gap between the two rows

                                    // Row 1: prefix icon + dim label
                                    RowLayout {
                                        width: parent.width
                                        spacing: 5

                                        Text {
                                            visible: root.iconTheme === "wi-font" && wiFont.status === FontLoader.Ready
                                            text: "\uF0D0"            // moon phase glyph (header)
                                            font.family: wiFont.font.family
                                            font.pixelSize: root.iconSize
                                            color: root.accentViolet
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 7
                                        }
                                        Kirigami.Icon {
                                            visible: root.iconTheme !== "wi-font"
                                            source: root.iconTheme === "kde" ? "weather-clear-night" : root.svgIconUrl("wi-moon-alt-waxing-gibbous-2.svg")
                                            isMask: root.iconTheme === "symbolic"
                                            color: root.iconTheme === "symbolic" ? Kirigami.Theme.textColor : "transparent"
                                            implicitWidth: Math.round(root.iconSize * 0.7)
                                            implicitHeight: Math.round(root.iconSize * 0.7)
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 7
                                        }
                                        Label {
                                            text: root.labelFor("moonphase")
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.55
                                            font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 7
                                        }
                                    }

                                    // Row 2: moon phase icon + phase name (like sunrise/sunset row)
                                    RowLayout {
                                        width: parent.width
                                        spacing: 4

                                        // Moon phase icon – smaller (70% of base icon size)
                                        Text {
                                            visible: wiFont.status === FontLoader.Ready
                                            text: Moon.moonPhaseFontIcon()
                                            font.family: wiFont.font.family
                                            font.pixelSize: Math.round(root.iconSize * 0.7)
                                            color: root.accentViolet
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 10  // left margin from card edge
                                            Layout.topMargin: 5
                                        }
                                        // Fallback SVG icon (when font not ready)
                                        Kirigami.Icon {
                                            visible: wiFont.status !== FontLoader.Ready
                                            source: weatherRoot ? weatherRoot.moonPhaseSvgUrl() : "weather-clear-night"
                                            isMask: true
                                            color: root.accentViolet
                                            implicitWidth: Math.round(root.iconSize * 0.7)
                                            implicitHeight: Math.round(root.iconSize * 0.7)
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 10
                                            Layout.topMargin: 5
                                        }

                                        // Moon phase name label (takes remaining width)
                                        Label {
                                            text: weatherRoot ? weatherRoot.moonPhaseLabel() : "--"
                                            color: root.accentViolet
                                            font: weatherRoot ? weatherRoot.wf(13, true) : Qt.font({
                                                bold: true
                                            })
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.leftMargin: 10    // optional left margin
                                            Layout.topMargin: 5
                                        }
                                    }
                                }
                            } // Item (moonphase)

                        } // Rectangle (card)
                    } // Repeater (items)

                    // spacer for odd rows
                    Item {
                        Layout.fillWidth: true
                        visible: rowItem.modelData.length === 1
                    }
                } // RowLayout (row)
            } // Repeater (rows)
        } // Column
    } // ScrollView
}
