import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// How to read the Weather Map, in a panel that slides in over the right of
// the tab. The layers shown now come first and are marked; the others
// follow in the order of the column; then the column, the time, the time
// line, the date and the keys. Each part: a title, lines ("label: text",
// some under a heading), then a note in italics. A popup of the tab
// (parent), not a drawer: a drawer would cover the whole Plasma popup.
QQC2.Popup {
    id: panel
    property var layers: ({})         // layer id: shown
    property var shownIds: []         // the layers in the column (the others are left out)
    property var keys: ({})           // layer id: its keyboard letter

    x: parent ? parent.width - width : 0
    y: 0
    width: Math.min(400, parent ? parent.width * 0.85 : 400)
    height: parent ? parent.height : 600
    padding: 0
    modal: false
    closePolicy: QQC2.Popup.CloseOnEscape
    enter: Transition { NumberAnimation { property: "x"; from: panel.parent ? panel.parent.width : 0; to: panel.parent ? panel.parent.width - panel.width : 0; duration: 220; easing.type: Easing.OutCubic } }
    exit: Transition { NumberAnimation { property: "x"; to: panel.parent ? panel.parent.width : 0; duration: 180; easing.type: Easing.InCubic } }

    readonly property string sixDays: i18n("about 7 days back to 6 days ahead.")
    readonly property string switchText: i18n("switches the layer on or off.")
    function letter(id) { return panel.keys[id] || ""; }

    // A layer: its range, its options, its shortcuts (the letter last), as lines.
    function layerRows(s) {
        var rows = [{ label: i18n("Range"), text: s.range }];
        if (s.options && s.options.length) {
            rows.push({ head: i18n("Options") });
            s.options.forEach(function (o) { rows.push({ label: o[0], text: o[1], indent: true }); });
        }
        rows.push({ head: i18n("Shortcuts") });
        (s.shortcuts || []).forEach(function (o) { rows.push({ label: o[0], text: o[1], indent: true }); });
        s.ids.forEach(function (id) {
            if (panel.letter(id))
                rows.push({ label: panel.letter(id), text: id === "isobars" ? i18n("switches the isobars on or off.") : panel.switchText, indent: true });
        });
        return rows;
    }

    // ids: the page's layers; icon: a drawing of contents/icons/weathermap
    // (mask: white, tinted with the text).
    readonly property var layerSections: [
        { ids: ["radar"], icon: "radar", title: i18n("Radar"),
          range: i18n("2 hours back to 1 hour ahead, every 10 minutes. It stays so when a longer range is set."),
          options: [[i18n("Colors"), i18n("the palette of the radar.")],
                    [i18n("Snow"), i18n("snow in colors of its own.")],
                    [i18n("Smoothing"), i18n("softens the edges of the rain.")],
                    [i18n("Lightning"), i18n("the recent strikes.")],
                    [i18n("Storm cells"), i18n("the storms tracked.")],
                    [i18n("Wind arrows"), i18n("how the rain moves now. They are the same on every picture: they are not the wind of the time shown.")],
                    [i18n("Alerts"), i18n("the warnings in force.")],
                    [i18n("Format and Tiles"), i18n("WebP or PNG, 256 or 512 px. The satellite follows them too.")]],
          shortcuts: [[i18n("Double click on the icon"), i18n("the radar alone, on its range. A click on the satellite then adds it. The same double click gives back the layers from before.")]],
          note: i18n("What the weather radars see falling, from LibreWXR. After now it is LibreWXR's nowcast, paler on the time line. In its range the time line slows down to its 10 minute steps.") },
        { ids: ["satellite"], icon: "satellite", title: i18n("Satellite"),
          range: i18n("12 hours back to now, every hour."),
          shortcuts: [[i18n("Double click on the icon"), i18n("the satellite alone, on its range. A click on the radar then adds it.")],
                      [i18n("Ctrl + double click"), i18n("on the radar or the satellite: both at once.")]],
          note: i18n("The infrared picture of the clouds, from LibreWXR: the colder the top, the higher and whiter the cloud.") },
        { ids: ["wind"], icon: "vent-glyph", title: i18n("Wind"), range: sixDays,
          options: [[i18n("10 m"), i18n("the wind you feel, shaped by the relief.")],
                    [i18n("700 hPa"), i18n("about 3000 m: the flow that carries the clouds and the rain, stronger and smoother. Only the global model is drawn: the regional models hold the 10 m wind only.")],
                    [i18n("Colors"), i18n("the palettes of the widget settings, where they can be made and changed.")]],
          note: i18n("The lines flow with the wind, their color is the speed (the wind palette of the settings). By default: white when calm, green and blue for a breeze, yellow and orange for a strong wind, red and violet for a storm. Where the lines bunch up and turn, the weather changes.") },
        { ids: ["temperature"], icon: "temperature-glyph", title: i18n("Temperature"), range: sixDays,
          options: [[i18n("Width of the bands"), i18n("how many degrees each color band covers.")],
                    [i18n("Colors"), i18n("the palettes of the widget settings, where they can be made and changed.")]],
          note: i18n("Air temperature at 2 m. Play a whole day: the land warms up in the afternoon and cools down at night, the sea hardly changes. A sharp edge that moves is a front.") },
        { ids: ["precipitation"], icon: "precipitations-glyph", title: i18n("Precipitation"), range: sixDays,
          options: [[i18n("Kinds shown"), i18n("rain, snow, wet snow, rain and snow, freezing rain, freezing drizzle, ice pellets.")]],
          note: i18n("What falls in the three hours around the time shown, in mm/h. Rain goes from blue to green, yellow, red and magenta as it gets heavier; snow is lilac and violet; the dangerous kinds (ice) have colors of their own. Under 0.05 mm/h nothing is drawn.") },
        { ids: ["clouds"], icon: "nuages-glyph", mask: true, title: i18n("Clouds"), range: sixDays,
          options: [[i18nc("@item cloud level", "Low"), i18n("under about 2 km: grey days, fog, drizzle.")],
                    [i18nc("@item cloud level", "Mid"), i18n("2 to 6 km: they often come before rain.")],
                    [i18nc("@item cloud level", "High"), i18n("above 6 km: thin veils of ice, the sun still gets through.")]],
          note: i18n("The whiter, the more of the sky is covered. With the three levels ticked you see the model's total cover, without counting twice the clouds over each other.") },
        { ids: ["pressure", "isobars"], icon: "pression-glyph", title: i18n("Pressure"), range: sixDays,
          shortcuts: [[i18n("Isobars button on the map"), i18n("shows or hides the isobars.")]],
          note: i18n("Air pressure brought to sea level, in hPa. Blue and purple: lows (clouds, rain, wind). Orange and red: highs (settled weather, fog in winter). The isobars join the points of equal pressure, every 4 hPa. The wind blows almost along them, counterclockwise around a low in the northern hemisphere. The closer they are, the stronger the wind.") },
        { ids: ["humidity"], icon: "humidite-glyph", title: i18n("Humidity"), range: sixDays,
          note: i18n("Relative humidity at 2 m: how close the air is to being saturated. Brown: dry (under 30 %, fire risk). Sand and green: usual. Blue: near 100 % (fog, low clouds, rain). It goes up at night and down in the afternoon even when the air keeps the same water. For the water itself, see the dew point.") },
        { ids: ["dewpoint"], icon: "rosee-glyph", title: i18n("Dew point"), range: sixDays,
          note: i18n("The temperature at which dew forms. It tells how much water the air really holds. Under 10 °C the air feels dry, at 13 to 16 °C you notice it, from 18 °C it is muggy, from 21 °C oppressive, from 24 °C tropical. When the night cools down to the dew point, dew or fog forms.") },
        { ids: ["airquality"], icon: "qualite-air-glyph", mask: true, title: i18n("Air quality"),
          range: i18n("about 7 days back to 5 days ahead. Further on the CAMS forecast stops and the pictures stay empty."),
          options: [["PM2.5, PM10, O₃, NO₂, SO₂", i18n("the pollutants.")],
                    [i18n("Dust"), i18n("the Saharan dust.")],
                    [i18n("AOD"), i18n("how hazy the air is (smoke, dust).")],
                    [i18n("UV"), i18n("the UV index of the day.")]],
          note: i18n("The CAMS forecast. The colors follow the European Air Quality Index: cyan good, green fair, yellow moderate, red poor, dark red very poor, purple extremely poor. The scale is logarithmic: each band covers a wider range than the one before.") }
    ]
    function isOn(s) { return s.ids.some(function (id) { return !!panel.layers[id]; }); }
    function inColumn(s) { return s.ids.some(function (id) { return panel.shownIds.indexOf(id) >= 0; }); }
    readonly property var kept: layerSections.filter(inColumn)
    readonly property var orderedLayers: kept.filter(isOn).concat(kept.filter(function (s) { return !isOn(s); }))

    // The rest of the tab. A line: label (bold) and text, an icon of the
    // map (icon) or a few characters (sym) before it.
    readonly property var otherSections: [
        { title: i18n("The layer column"),
          intro: i18n("The thin button on its left edge opens or folds it. The map stays where it is when the column opens over it."),
          rows: [{ head: i18n("Open") },
                 { label: i18n("Click on the icon"), text: panel.switchText, indent: true },
                 { label: i18n("Slider"), text: i18n("the opacity of the layer, from 0 to 100 %."), indent: true },
                 { icon: "gear", mask: true, label: i18n("Wheel"), text: i18n("its options and its color legend, which can be hidden."), indent: true },
                 { head: i18n("Folded") },
                 { label: i18n("Click on the icon"), text: panel.switchText, indent: true },
                 { label: i18n("Shift + mouse wheel on the icon"), text: i18n("the opacity, shown in a bubble while it changes and drawn as the bar under the icon."), indent: true },
                 { label: i18n("Mouse wheel"), text: i18n("scrolls the column."), indent: true }],
          note: i18n("The colored layers share the map, one at a time: temperature, pressure, humidity, dew point, air quality. The column lists the layers as they are stacked on the map, the top one first; the order is set in the widget settings. The wind always goes over the others.") },
        { title: i18n("Time"),
          rows: [{ head: i18n("The two clocks: how far back and how far ahead") },
                 { label: i18n("Click"), text: i18n("opens the list of choices. It also gives the range of the radar or of the satellite, which stays when another layer is switched on."), indent: true },
                 { label: i18n("Mouse wheel"), text: i18n("the next or previous choice, shown in a bubble while it changes."), indent: true },
                 { head: i18n("Speed") },
                 { label: i18n("Click"), text: i18n("the next speed: x1, x2, x3, then x1 again."), indent: true },
                 { label: "+ / −", text: i18n("the next or previous speed, from the keyboard or the keypad."), indent: true }],
          note: i18n("A layer stops where its data stops.") },
        { title: i18n("Time line"),
          rows: [{ icon: "debut-glyph", mask: true, label: i18n("First picture"), text: i18nc("@info keyboard key", "Home") },
                 { sym: "‹ −", label: i18n("One step back (←)"), text: i18n("3 hours. In the range of the satellite one hour, in that of the radar 10 minutes, while they are on: the button shows it. It stops on their first and last image.") },
                 { sym: "▶", label: i18n("Play or pause"), text: i18n("Space") },
                 { sym: "+ ›", label: i18n("One step ahead (→)"), text: i18n("the same steps.") },
                 { icon: "fin-glyph", mask: true, label: i18n("Last picture"), text: i18nc("@info keyboard key", "End") },
                 { icon: "boucle-glyph", mask: true, label: i18n("Loop (L)"), text: i18n("on, the animation plays round again from the start; off, it stops on the last picture.") },
                 { label: i18n("The line"), text: i18n("a click or a drag shows the picture under the pointer, and pauses.") },
                 { label: i18n("Magenta band"), text: i18n("the range of the radar, paler for its nowcast.") },
                 { label: i18n("Grey-blue band"), text: i18n("the range of the satellite.") },
                 { label: i18n("Marks under the line"), text: i18n("one per picture, colored once loaded, red when it failed.") }] },
        { title: i18n("Date"),
          rows: [{ label: i18n("Green dot"), text: i18n("a picture straight from a forecast file.") },
                 { label: i18n("Orange dot"), text: i18n("a picture worked out between two files.") },
                 { sym: "↺", label: i18n("Back to now"), text: "0" },
                 { sym: "▾", label: i18n("Days"), text: i18n("lists the days of the range. The mouse wheel over the date goes to the next or previous day.") }],
          note: i18n("At the bottom left of the map, small: the pictures loaded out of those of the range, and the pictures per second at most. Under them, the models: the global one, then the finer regional ones drawn over it in this view.") },
        { title: i18n("Keys"),
          rows: [{ label: i18n("Space"), text: i18n("play or pause.") },
                 { label: "← / →", text: i18n("one step back or ahead, as the buttons of the time bar.") },
                 { label: i18n("Page Up / Page Down (or Ctrl + arrow)"), text: i18n("the previous or next picture from a forecast file.") },
                 { label: i18n("Home / End"), text: i18n("the first or last picture.") },
                 { label: "0", text: i18n("back to now.") },
                 { label: "+ / −", text: i18n("the next or previous speed.") },
                 { label: i18n("Ctrl + / Ctrl −"), text: i18n("zoom in or out.") },
                 { label: "L", text: i18n("the loop on or off.") },
                 { label: Object.keys(panel.keys).map(function (id) { return panel.keys[id]; }).join(", "),
                   text: i18n("switch radar, satellite, wind, temperature, precipitation, clouds, pressure, isobars, humidity, dew point, air quality on or off.") },
                 { label: i18n("Ctrl held over the map"), text: i18n("the wind and the temperature under the pointer.") },
                 { label: i18n("Esc"), text: i18n("closes this panel.") }],
          note: i18n("The same keys in every language. They work while the Weather Map tab is shown.") }
    ]

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        Rectangle { width: 1; height: parent.height; color: Kirigami.Theme.disabledTextColor; opacity: 0.4 }
    }

    // One part: title (icon, letter, "shown" for a layer on), an intro in
    // italics, the lines, a note in italics.
    component Part: ColumnLayout {
        id: part
        property var section
        property bool on: false
        property bool dim: false
        property var rows: []
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            WmIcon {
                visible: !!part.section.icon
                implicitWidth: 22
                implicitHeight: 22
                name: part.section.icon || ""
                mask: !!part.section.mask
            }
            QQC2.Label {
                text: part.section.title + (part.section.ids && panel.letter(part.section.ids[0]) ? " (" + panel.letter(part.section.ids[0]) + ")" : "")
                font.bold: true
            }
            QQC2.Label {
                visible: part.on
                text: i18nc("@info a layer of the map is shown now", "shown")
                color: Kirigami.Theme.highlightColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
        QQC2.Label {
            visible: !!part.section.intro
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.italic: true
            opacity: 0.8
            text: part.section.intro || ""
        }
        Repeater {
            model: part.rows
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: modelData.indent ? Kirigami.Units.largeSpacing : 0
                spacing: Kirigami.Units.smallSpacing
                opacity: part.dim ? 0.75 : 1.0
                WmIcon {
                    visible: !!modelData.icon
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 16
                    implicitHeight: 16
                    name: modelData.icon || ""
                    mask: !!modelData.mask
                }
                QQC2.Label {
                    visible: !!modelData.sym
                    Layout.alignment: Qt.AlignTop
                    text: modelData.sym || ""
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    textFormat: Text.StyledText
                    text: modelData.head ? "<b>" + modelData.head + "</b>"
                        : "<b>" + modelData.label + "</b>" + (modelData.text ? i18nc("@info label: text", ": ") + modelData.text : "")
                }
            }
        }
        QQC2.Label {
            visible: !!part.section.note
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.italic: true
            opacity: 0.8
            text: part.section.note || ""
        }
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
                text: i18n("Weather maps")
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
                    model: panel.orderedLayers
                    Part {
                        required property var modelData
                        section: modelData
                        on: panel.isOn(modelData)
                        dim: !on
                        rows: panel.layerRows(modelData)
                    }
                }
                Repeater {
                    model: panel.otherSections
                    Part {
                        required property var modelData
                        section: modelData
                        rows: modelData.rows
                    }
                }
                Item { implicitHeight: Kirigami.Units.smallSpacing }
            }
        }
    }
}
