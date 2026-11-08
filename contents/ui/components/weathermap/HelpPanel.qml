import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// How to read the Weather Map's layers, in a panel that slides in over the
// right of the tab. The layers shown now come first and are marked; the
// others follow in the order of the column. A popup of the tab (parent),
// not a drawer: a drawer would cover the whole Plasma popup.
QQC2.Popup {
    id: panel
    property var layers: ({})         // layer id: shown
    property var choices: ({})        // layer id: the [value, text] pairs of its list

    x: parent ? parent.width - width : 0
    y: 0
    width: Math.min(400, parent ? parent.width * 0.85 : 400)
    height: parent ? parent.height : 600
    padding: 0
    modal: false
    closePolicy: QQC2.Popup.CloseOnEscape
    enter: Transition { NumberAnimation { property: "x"; from: panel.parent ? panel.parent.width : 0; to: panel.parent ? panel.parent.width - panel.width : 0; duration: 220; easing.type: Easing.OutCubic } }
    exit: Transition { NumberAnimation { property: "x"; to: panel.parent ? panel.parent.width : 0; duration: 180; easing.type: Easing.InCubic } }

    readonly property string icons: Qt.resolvedUrl("../../../icons/")
    readonly property string sixDays: i18n("Up to 6 days ahead and about 7 days back (Open-Meteo deletes older forecast files).")
    // ids: the page's layer, icon: a file under contents/icons.
    readonly property var sections: [
        { ids: ["radar"], icon: icons + "weathermap/radar.svg", title: i18n("Radar"),
          range: i18n("Every 10 minutes, from about 2 hours back to 1 hour ahead (LibreWXR's nowcast, paler on the time line)."),
          text: i18n("What the weather radars see falling now, from LibreWXR, over the animation in its range: the time line slows down to its 10 minute steps there. The wheel of its line sets its colors, snow, smoothing, lightning, storm cells, wind arrows and alerts. The arrows show how the rain moves now, the same on every picture: they are not the wind of the time shown. A double click on its icon shows the radar alone, on its own range; then a click on the satellite adds it (both, on their joint range). The same double click gives back the layers from before.") },
        { ids: ["satellite"], icon: icons + "weathermap/satellite.svg", mask: true, title: i18n("Satellite"),
          range: i18n("Every hour over the past 12 hours."),
          text: i18n("The infrared picture of the clouds from LibreWXR: the colder the top, the higher and whiter the cloud. A double click on its icon shows the satellite alone, on its own range; then a click on the radar adds it. Ctrl and a double click on either shows both at once.") },
        { ids: ["wind"], icon: icons + "flat-color/22/wi-strong-wind.svg", title: i18n("Wind"), range: sixDays,
          text: i18n("The lines flow with the wind. Their color is the speed, from your wind palette: by default white when calm, green and blue for a breeze, yellow and orange for a strong wind, red and violet for a storm. The options of its line (the wheel) pick the height: 10 m is the wind you feel, shaped by the relief; 700 hPa (about 3000 m) is the flow that carries the clouds and the rain, stronger and smoother. At 700 hPa only the global model is drawn: the regional files hold the 10 m wind only. Watch where the lines bunch up and turn: that is where the weather changes.") },
        { ids: ["temperature"], icon: icons + "flat-color/22/wi-thermometer.svg", title: i18n("Temperature"), range: sixDays,
          text: i18n("Air temperature at 2 m, in the bands of the legend. Play a whole day to see the land warm up in the afternoon and cool down at night, while the sea hardly changes. A sharp edge that moves is a front.") },
        { ids: ["precipitation"], icon: icons + "flat-color/22/wi-rain.svg", title: i18n("Precipitation"), range: sixDays,
          text: i18n("What falls in the three hours around the time shown, in mm per hour. Each kind has its colors: rain from blue to green, yellow, red and magenta as it gets heavier; snow in lilac and violet; the dangerous ones (freezing rain, freezing drizzle, ice pellets) in colors of their own. Pick the kinds in the options of its line (the wheel). Under 0.05 mm/h nothing is drawn.") },
        { ids: ["clouds"], icon: icons + "flat-color/22/wi-cloudy.svg", title: i18n("Clouds"), range: sixDays,
          text: i18n("White is cloud: the whiter, the more of the sky it covers. Low clouds (under about 2 km) make grey days, fog and drizzle. Mid clouds (2 to 6 km) often come before rain. High clouds (above 6 km) are thin veils of ice: the sun still gets through. With all three levels ticked you see the total cover as the model counts it, without counting twice the clouds that sit over each other.") },
        { ids: ["pressure", "isobars"], icon: icons + "flat-color/22/wi-barometer.svg", title: i18n("Pressure and isobars"), range: sixDays,
          text: i18n("Air pressure brought to sea level, in hPa. Blue and purple are lows: clouds, rain and wind. Orange and red are highs: settled weather, fog in winter. The isobars join the points of equal pressure, every 4 hPa. The wind blows almost along them, counterclockwise around a low in the northern hemisphere. The closer the lines, the stronger the wind.") },
        { ids: ["humidity"], icon: icons + "flat-color/22/wi-humidity.svg", title: i18n("Humidity"), range: sixDays,
          text: i18n("Relative humidity at 2 m: how close the air is to being saturated with water. Brown is dry (under 30 %: dry skin, fire risk), sand and green are usual, blue is near 100 % (fog, low clouds, rain). It goes up at night and down in the afternoon even when the air keeps the same water, because warm air can hold more: for the water itself, look at the dew point.") },
        { ids: ["dewpoint"], icon: icons + "flat-color/22/wi-dew-point.svg", title: i18n("Dew point"), range: sixDays,
          text: i18n("The temperature the air would have to cool to for dew to form. It tells how much water the air really holds, and how muggy it feels. Under 10 °C the air feels dry, 13 to 16 °C you notice it, from 18 °C it is muggy, from 21 °C oppressive, and from 24 °C tropical. When the night temperature falls to the dew point, dew or fog forms.") },
        { ids: ["airquality"], icon: icons + "flat-color/22/wi-smoke.svg", title: i18n("Air quality"),
          range: i18n("Up to 5 days ahead only: the CAMS forecast stops there, later pictures stay empty. About 7 days back."),
          text: i18n("The CAMS forecast for the pollutant chosen in the list. The colors follow the bands of the European Air Quality Index: cyan good, green fair, yellow moderate, red poor, dark red very poor, purple extremely poor. Dust shows Saharan dust, AOD how hazy the air is (smoke, dust), UV the UV index of the day. The scale is logarithmic: each band covers a wider range than the one before.") }
    ]
    function isOn(s) { return s.ids.some(function (id) { return !!panel.layers[id]; }); }
    readonly property var ordered: sections.filter(isOn).concat(sections.filter(function (s) { return !isOn(s); }))

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        Rectangle { width: 1; height: parent.height; color: Kirigami.Theme.disabledTextColor; opacity: 0.4 }
    }

    contentItem: ColumnLayout {
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                level: 3
                text: i18n("Reading the Weather Map")
            }
            QQC2.ToolButton {
                icon.name: "window-close"
                focusPolicy: Qt.NoFocus
                onClicked: panel.close()
            }
        }
        QQC2.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            ColumnLayout {
                width: scroll.availableWidth
                spacing: Kirigami.Units.largeSpacing
                Repeater {
                    model: panel.ordered
                    ColumnLayout {
                        required property var modelData
                        readonly property bool on: panel.isOn(modelData)
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing
                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                implicitWidth: 22
                                implicitHeight: 22
                                roundToIconSize: false
                                source: modelData.icon
                                isMask: !!modelData.mask
                                color: modelData.mask ? Kirigami.Theme.textColor : "transparent"
                            }
                            QQC2.Label {
                                text: modelData.title
                                font.bold: true
                            }
                            QQC2.Label {
                                visible: on
                                text: i18nc("@info a layer of the map is shown now", "shown")
                                color: Kirigami.Theme.highlightColor
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            opacity: on ? 1.0 : 0.75
                            text: modelData.text
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            opacity: 0.7
                            font.italic: true
                            text: modelData.range
                        }
                        // The choices of the layer's list, in the order of the list.
                        QQC2.Label {
                            readonly property var list: panel.choices[modelData.ids[0]] || []
                            visible: list.length > 0
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Kirigami.Theme.linkColor
                            font.italic: true
                            text: list.map(function (c) { return c[1]; }).join(", ")
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.bottomMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label { text: i18n("Layers"); font.bold: true }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: i18n("A click on the icon of a line switches the layer on or off; the slider sets its opacity, from 0 to 100 %. The wheel at the end of the line opens its options: what it shows, and its color legend on the map, which can be hidden. The colors share one layer at a time (temperature, pressure, humidity, dew point, air quality); precipitation, clouds, wind, isobars, radar and satellite go over them. The thin button on the left edge of the column folds it to its icons: the opacity is then the bar under each icon, set with the wheel over it. The map stays where it is when the column opens over it.")
                    }
                    QQC2.Label { text: i18n("Time"); font.bold: true }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: i18n("The two clocks under the layers set how far back and how far ahead the animation goes (the wheel over one steps through its choices, a click opens them); a layer stops where its data stops. The triangles beside them set the speed, x1, x2 or x3, one click to the next. The round arrow beside the date goes back to now; the arrow after it lists the days of the range. A green dot is a picture straight from a forecast file, an orange one is worked out between two of them. At the bottom left of the map, small: the pictures loaded out of those of the range, and the pictures per second at most. The loop button at the end of the time bar plays round again from the start, or stops on the last picture. The models line names the global model, then the finer regional ones drawn over it in this view.")
                    }
                    QQC2.Label { text: i18n("Keys"); font.bold: true }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: i18n("Space plays or pauses. The arrows move one hour; the -/+ buttons of the time bar move 3 hours, an hour for the satellite alone or with the radar, 10 minutes for the radar alone. Page Up and Page Down (or Ctrl and an arrow) jump to the previous or next picture from a forecast file. Hold Ctrl over the map to read the wind and the temperature under the pointer. Esc closes this panel.")
                    }
                }
            }
        }
    }
}
