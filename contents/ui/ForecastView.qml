/**
 * ForecastView.qml — "Forecast" tab of the main widget popup
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W

Item {
    id: forecastRoot
    property var weatherRoot
    property int expandedIndex: -1

    // Set implicit height based on content
    implicitHeight: (weatherRoot && weatherRoot.dailyData.length > 0) ? forecastColumn.height : (emptyLabel.implicitHeight + 40) // extra space for centering

    // Font for weather icons (wind direction glyph)
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    // Resolved at load time so the path is correct in all rendering contexts
    readonly property url iconsBaseDir: Qt.resolvedUrl("../icons/")

    // Widget icon theme — needed to build correct SVG icon paths
    readonly property string widgetIconTheme: Plasmoid.configuration.widgetIconTheme || "symbolic"
    readonly property int iconSz: Plasmoid.configuration.widgetIconSize || 16
    readonly property string iconTheme: widgetIconTheme

    // ── empty state ───────────────────────────────────────────────────────
    Label {
        id: emptyLabel
        anchors.centerIn: parent
        visible: !weatherRoot || weatherRoot.dailyData.length === 0
        text: (weatherRoot && weatherRoot.loading) ? i18n("Loading forecast…") : i18n("No forecast data")
        color: Kirigami.Theme.textColor
        opacity: 0.4
        font: weatherRoot ? weatherRoot.wf(12, false) : Qt.font({})
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        visible: weatherRoot && weatherRoot.dailyData.length > 0

        Column {
            id: forecastColumn
            width: parent.width
            spacing: 0

            Repeater {
                model: weatherRoot && weatherRoot.dailyData.length > 0 ? Math.min(Plasmoid.configuration.forecastDays, weatherRoot.dailyData.length) : 0

                delegate: Column {
                    required property int index
                    width: parent.width
                    spacing: 0

                    // ── day row ─────────────────────────────────────────
                    Rectangle {
                        id: dayRow
                        width: parent.width
                        height: Math.max(52, rowLayoutInner.implicitHeight + 12)
                        color: (rowMouse.containsMouse || forecastRoot.expandedIndex === index) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        RowLayout {
                            id: rowLayoutInner
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 14
                            }
                            spacing: 0

                            Kirigami.Icon {
                                source: forecastRoot.expandedIndex === index ? "arrow-down" : "arrow-right"
                                width: 14
                                height: 14
                                opacity: 0.45
                                Layout.alignment: Qt.AlignVCenter
                                Layout.rightMargin: 6
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 110
                                Layout.minimumWidth: 110
                                Layout.maximumWidth: 110
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1
                                Label {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: {
                                        if (index === 0)
                                            return i18n("Today");
                                        var ds = weatherRoot.dailyData[index].dateStr;
                                        if (!ds)
                                            return "";
                                        var parts = ds.split("-");
                                        if (parts.length !== 3)
                                            return "";
                                        var d = new Date(parts[0], parts[1] - 1, parts[2]);
                                        return Qt.locale().dayName(d.getDay(), Locale.LongFormat);
                                    }
                                    color: Kirigami.Theme.textColor
                                    font: weatherRoot.wf(12, true)
                                }
                                Label {
                                    text: {
                                        var ds = weatherRoot.dailyData[index].dateStr || "";
                                        if (!ds)
                                            return "";
                                        var d = new Date(ds);
                                        var fmt = Qt.locale().dateFormat(Locale.ShortFormat);
                                        return Qt.formatDate(d, fmt);
                                    }
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.42
                                    font: weatherRoot.wf(9, false)
                                }
                            }

                            Kirigami.Icon {
                                source: W.weatherCodeToIcon(weatherRoot.dailyData[index].code)
                                width: 28
                                height: 28
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.rightMargin: 4
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: weatherRoot.weatherCodeToText(weatherRoot.dailyData[index].code)
                                color: Kirigami.Theme.textColor
                                opacity: 0.48
                                font: weatherRoot.wf(11, false)
                                wrapMode: Text.WordWrap
                            }

                            Item {
                                Layout.preferredWidth: 8
                            }

                            RowLayout {
                                spacing: 2
                                Layout.alignment: Qt.AlignRight
                                Label {
                                    text: weatherRoot.tempValue(weatherRoot.dailyData[index].minC)
                                    color: "#42a5f5"
                                    opacity: 0.48
                                    font: weatherRoot.wf(12, false)
                                }
                                Label {
                                    text: "/"
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.22
                                    font: weatherRoot.wf(12, false)
                                }
                                Label {
                                    text: weatherRoot.tempValue(weatherRoot.dailyData[index].maxC)
                                    color: "#ff6e40"
                                    font: weatherRoot.wf(12, true)
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (forecastRoot.expandedIndex === index) {
                                    forecastRoot.expandedIndex = -1;
                                } else {
                                    forecastRoot.expandedIndex = index;
                                    if (weatherRoot) {
                                        weatherRoot.hourlyData = [];
                                        weatherRoot.fetchHourlyForDate(weatherRoot.dailyData[index].dateStr || "");
                                    }
                                }
                            }
                        }
                    }

                    // ── inline hourly panel ─────────────────────────────
                    Rectangle {
                        width: parent.width
                        height: forecastRoot.expandedIndex === index ? 240 : 0
                        visible: height > 0
                        clip: true
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        Behavior on height {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.InOutQuad
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: !weatherRoot || weatherRoot.hourlyData.length === 0
                            text: i18n("Loading hourly data…")
                            color: Kirigami.Theme.textColor
                            opacity: 0.32
                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                        }

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: weatherRoot && weatherRoot.hourlyData.length > 0
                            clip: true
                            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                            ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                            Row {
                                spacing: 6
                                height: parent.height

                                Repeater {
                                    model: weatherRoot ? weatherRoot.hourlyData : []

                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 100
                                        height: 200
                                        radius: 8
                                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                                        border.width: 1

                                        ColumnLayout {
                                            anchors {
                                                fill: parent
                                                margins: 6
                                            }
                                            spacing: 4

                                            // Fix bug with time formatting – formatted according to system locale (12h/24h)
                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: {
                                                    if (!modelData.hour || modelData.hour === "--")
                                                        return "--";
                                                    var parts = modelData.hour.split(":");
                                                    if (parts.length < 2)
                                                        return modelData.hour;
                                                    var h = parseInt(parts[0], 10);
                                                    var m = parseInt(parts[1], 10);
                                                    if (isNaN(h) || isNaN(m))
                                                        return modelData.hour;
                                                    var d = new Date();
                                                    d.setHours(h, m, 0, 0);
                                                    return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
                                                }
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.52
                                                font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                            }

                                            Kirigami.Icon {
                                                Layout.alignment: Qt.AlignHCenter
                                                source: {
                                                    // Derive night flag from the hour vs sunrise/sunset
                                                    var isNight = false;
                                                    if (modelData.hour && modelData.hour !== "--") {
                                                        var parts = modelData.hour.split(":");
                                                        if (parts.length >= 2) {
                                                            var hMins = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                                                            function parseSunMins(t) {
                                                                if (!t || t === "--") return -1;
                                                                var p = t.split(":");
                                                                return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                                            }
                                                            var rise = parseSunMins(weatherRoot ? weatherRoot.sunriseTimeText : "--");
                                                            var set_ = parseSunMins(weatherRoot ? weatherRoot.sunsetTimeText : "--");
                                                            if (rise >= 0 && set_ >= 0)
                                                                isNight = hMins < rise || hMins >= set_;
                                                        }
                                                    }
                                                    return W.weatherCodeToIcon(modelData.code || 0, isNight);
                                                }
                                                Layout.preferredWidth: 48
                                                Layout.preferredHeight: 48
                                            }

                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: weatherRoot ? weatherRoot.tempValue(modelData.tempC) : "--"
                                                color: Kirigami.Theme.textColor
                                                font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({
                                                    bold: true
                                                })
                                            }

                                            // Wind speed + direction (using font glyph for direction)
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 4
                                                Label {
                                                    text: weatherRoot && modelData.windKmh !== undefined ? weatherRoot.windValue(modelData.windKmh) : "--"
                                                    color: Kirigami.Theme.textColor
                                                    opacity: 0.55
                                                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                }
                                                Text {
                                                    visible: weatherRoot && !isNaN(modelData.windDeg)
                                                    text: W.windDirectionGlyph(modelData.windDeg)
                                                    font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                    font.pixelSize: 20  // adjust to match visual size
                                                    color: Kirigami.Theme.textColor
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }

                                            // Precipitation probability
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 3
                                                Kirigami.Icon {
                                                    source: {
                                                        var th = forecastRoot.widgetIconTheme;
                                                        if (th === "kde" || th === "wi-font")
                                                            th = "symbolic";
                                                        return forecastRoot.iconsBaseDir + th + "/32/wi-umbrella.svg";
                                                    }
                                                    isMask: true
                                                    color: "#5ea8ff"
                                                    Layout.preferredWidth: 32
                                                    Layout.preferredHeight: 32
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Label {
                                                    text: {
                                                        var pp = modelData.precipProb;
                                                        if (pp !== undefined && pp !== null && !isNaN(pp))
                                                            return Math.round(pp) + "%";
                                                        var h = modelData.humidity;
                                                        return (!isNaN(h) && h !== undefined) ? Math.round(h) + "%" : "--";
                                                    }
                                                    color: "#5ea8ff"
                                                    font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                    }
                }
            }
        }
    }
}
