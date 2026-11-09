import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../js/configUtils.js" as ConfigUtils

// The layer column of the Weather Map, at the right of the map: the help
// and the settings at the top, the layers (radar and satellite, then the
// forecast layers), the range and the speed, the models drawn at the
// bottom. Folded, it keeps the width of an icon; open, it grows to the left
// over the map, which stays where it is. map: the WeatherMapView, which
// talks to the page and keeps the settings.
Rectangle {
    id: panel
    property var map
    readonly property real openWidth: 190
    readonly property real foldedWidth: 56
    readonly property bool folded: map.panelFolded
    readonly property real colW: folded ? 36 : 169
    readonly property alias radarRow: radarRow
    readonly property alias satRow: satRow
    readonly property alias windRow: windRow
    readonly property alias tempRow: tempRow
    readonly property alias precipRow: precipRow
    readonly property alias cloudRow: cloudRow
    readonly property alias presRow: presRow
    readonly property alias aqRow: aqRow
    readonly property alias radarMenu: radarMenu
    readonly property alias settingsMenu: settingsMenu
    readonly property alias orderMenu: orderMenu
    readonly property alias pastPick: pastPick
    readonly property alias futurePick: futurePick

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color dimText: Kirigami.Theme.disabledTextColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    width: folded ? foldedWidth : openWidth
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    clip: true
    color: Kirigami.Theme.backgroundColor
    Rectangle { width: 1; height: parent.height; color: panel.tint(0.10) }
    // The column lies over the map: a wheel that nothing of the column
    // takes (the scrolling, the clocks, an opacity) stops here instead of
    // zooming the map under it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function (wheel) { wheel.accepted = true; }
    }

    // An option with one value among a list that can be long: its name,
    // then the list under it.
    component OptCombo: ColumnLayout {
        id: oc
        property string title
        property var choices: []        // [[value, text]]
        property var current            // the value taken
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 2
        QQC2.Label { text: oc.title; color: panel.dimText }
        QQC2.ComboBox {
            Layout.fillWidth: true
            model: oc.choices.map(function (c) { return c[1]; })
            currentIndex: Math.max(0, oc.choices.map(function (c) { return c[0]; }).indexOf(oc.current))
            onActivated: function (i) { oc.picked(oc.choices[i][0]); }
        }
    }
    // An option with one value among several: its name, then a switch for
    // each, two by two. Switching one on switches the one before off; the
    // one on stays on.
    component OptSwitches: ColumnLayout {
        id: os
        property string title
        property var choices: []        // [[value, text]]
        property var current            // the value taken
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 2
        QQC2.Label { text: os.title; color: panel.dimText }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 6
            rowSpacing: 0
            Repeater {
                model: os.choices
                SmallSwitch {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: modelData[1]
                    checked: os.current === modelData[0]
                    onToggled: {
                        if (checked)
                            os.picked(modelData[0]);
                        checked = Qt.binding(function () { return os.current === modelData[0]; });
                    }
                }
            }
        }
    }
    // A setting with a few values: its name, then the values side by side,
    // the one taken highlighted. When both do not fit in room (the width of
    // the menu), the values go on the line under the name.
    component Segmented: GridLayout {
        id: sg
        property string title
        property var choices: []        // [[value, text]]
        property var current            // the value taken
        property real room: 206         // a layer's options: 230 less the padding
        signal picked(var value)
        readonly property bool wrapped: sgTitle.implicitWidth + columnSpacing + sgBox.implicitWidth > room
        Layout.fillWidth: true
        columns: wrapped ? 1 : 2
        rowSpacing: 2
        QQC2.Label { id: sgTitle; text: sg.title; color: panel.dimText; Layout.fillWidth: true; elide: Text.ElideRight }
        Rectangle {
            id: sgBox
            implicitWidth: sgRow.implicitWidth + 4
            implicitHeight: 26
            radius: 4
            color: panel.tint(0.06)
            border.color: panel.tint(0.12)
            Row {
                id: sgRow
                anchors.centerIn: parent
                Repeater {
                    model: sg.choices
                    Rectangle {
                        required property var modelData
                        readonly property bool taken: sg.current === modelData[0]
                        width: Math.max(34, sgLabel.implicitWidth + 12)
                        height: 22
                        radius: 3
                        color: taken ? panel.accent : "transparent"
                        QQC2.Label {
                            id: sgLabel
                            anchors.centerIn: parent
                            text: parent.modelData[1]
                            font.bold: parent.taken
                            color: parent.taken ? Kirigami.Theme.highlightedTextColor : panel.dimText
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sg.picked(parent.modelData[0])
                        }
                    }
                }
            }
        }
    }
    // The kinds of a layer shown, several at once: a switch for each, two
    // by two, "All" first. Each change is sent at once.
    component OptKinds: ColumnLayout {
        id: ok
        property string title
        property var choices: []        // [[value, text]]
        property var checkedValues: choices.map(function (c) { return c[0]; })
        signal picked(var values)
        Layout.fillWidth: true
        spacing: 2
        function set(values) {
            // In the order of the choices.
            var v = choices.map(function (c) { return c[0]; }).filter(function (x) { return values.indexOf(x) >= 0; });
            picked(v);
        }
        QQC2.Label { text: ok.title; color: panel.dimText }
        SmallSwitch {
            text: i18n("All")
            font.bold: true
            checked: ok.checkedValues.length === ok.choices.length
            onToggled: {
                ok.set(checked ? ok.choices.map(function (c) { return c[0]; }) : []);
                checked = Qt.binding(function () { return ok.checkedValues.length === ok.choices.length; });
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 6
            rowSpacing: 0
            Repeater {
                model: ok.choices
                SmallSwitch {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: modelData[1]
                    checked: ok.checkedValues.indexOf(modelData[0]) >= 0
                    onToggled: {
                        var v = ok.checkedValues.filter(function (x) { return x !== modelData[0]; });
                        if (checked)
                            v.push(modelData[0]);
                        ok.set(v);
                        checked = Qt.binding(function () { return ok.checkedValues.indexOf(modelData[0]) >= 0; });
                    }
                }
            }
        }
    }
    component Caption: QQC2.Label {
        visible: !panel.folded
        color: panel.dimText
        font.pixelSize: 12
        font.bold: true
    }
    component Divider: Item {
        width: panel.colW
        height: 9
        Rectangle { y: 4; width: parent.width; height: 1; color: panel.tint(0.22) }
    }
    // A round button of the head: the help, the settings.
    component HeadButton: Rectangle {
        id: hb
        property string text
        property string iconName
        property string themeIcon      // an icon of the icon theme, drawn as a mask
        property string tip
        property bool on: false
        signal clicked()
        width: 34
        height: 34
        radius: 17
        color: on ? panel.accent : panel.tint(hbArea.containsMouse ? 0.13 : 0.06)
        border.color: panel.tint(0.15)
        QQC2.Label {
            visible: hb.text !== ""
            anchors.centerIn: parent
            text: hb.text
            color: hb.on ? Kirigami.Theme.highlightedTextColor : panel.fg
            font.bold: true
            font.pixelSize: 19
        }
        Kirigami.Icon {
            visible: hb.themeIcon !== ""
            anchors.centerIn: parent
            width: 21
            height: 21
            source: hb.themeIcon
            isMask: true
            color: hb.on ? Kirigami.Theme.highlightedTextColor : panel.fg
        }
        WmIcon {
            visible: hb.text === "" && hb.themeIcon === ""
            anchors.centerIn: parent
            width: 21
            height: 21
            name: hb.iconName
            mask: true
            tint: hb.on ? Kirigami.Theme.highlightedTextColor : panel.fg
        }
        MouseArea {
            id: hbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
        QQC2.ToolTip.text: hb.tip
        QQC2.ToolTip.visible: hbArea.containsMouse
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // The help and the settings, always in sight at the top of the column
    // (the layers scroll under them), as the time is at the bottom.
    Column {
        id: headBox
        x: 9.5
        y: 8
        spacing: 7
        // The help and the settings side by side at the right (one under the
        // other, folded): the row glides to the left as the second glides
        // under the first, in step with the time's below.
        Flow {
            readonly property real rowW: 3 * 34 + 2 * spacing
            x: panel.folded ? 0 : panel.colW - rowW
            width: panel.folded ? panel.colW : rowW
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            spacing: 8
            // Side by side open, one under the other folded: they glide there.
            move: Transition { NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic } }
            HeadButton {
                text: "?"
                tip: i18n("How to read the weather maps")
                on: panel.map.helpOpen
                onClicked: panel.map.toggleHelp()
            }
            // The stack of the layers, as in the settings: a handle drags a
            // layer up or down, a switch takes it out of the column.
            HeadButton {
                themeIcon: "dialog-layers"
                tip: i18n("Order of the layers")
                on: orderMenu.visible
                onClicked: orderMenu.visible ? orderMenu.close() : orderMenu.open()
                QQC2.Popup {
                    id: orderMenu
                    margins: 6
                    x: parent.width - width
                    y: parent.height + 6
                    width: 300
                    padding: 12
                    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent
                    contentItem: ColumnLayout {
                        spacing: 6
                        QQC2.Label { text: i18n("Order of the layers"); font.bold: true }
                        LayerStackList {
                            Layout.fillWidth: true
                            saved: JSON.stringify(panel.map.layerOrder)
                            disabled: panel.map.disabledLayers
                            labels: ({
                                wind: i18n("Wind"), radar: i18n("Radar"), satellite: i18n("Satellite"),
                                precipitation: i18n("Precipitation"), clouds: i18n("Cloud cover"), temperature: i18n("Temperature"),
                                pressure: i18n("Pressure"), humidity: i18n("Relative humidity"), dewpoint: i18n("Dew point"), airquality: i18n("Air quality")
                            })
                            onOrderPicked: function (json) { panel.map.setLayerOrder(json); }
                            onLayerToggled: function (id, on) { panel.map.setLayerEnabled(id, on); }
                        }
                        QQC2.Button {
                            text: i18n("Default order")
                            icon.name: "edit-undo"
                            enabled: JSON.stringify(panel.map.layerOrder) !== JSON.stringify(ConfigUtils.WEATHER_STACK)
                            onClicked: panel.map.setLayerOrder("[]")
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 276
                            wrapMode: Text.WordWrap
                            color: panel.dimText
                            text: i18n("The wind is drawn over the map, so over every layer wherever it is in this list: its place here orders the column of the tab only.")
                        }
                    }
                }
            }
            // Set once: pictures per second at most, the resolution
            // while playing, coasts and borders, the dark map.
            HeadButton {
                id: settingsButton
                iconName: "gear"
                tip: i18n("Settings: pictures per second, resolution while playing,<br>coasts and borders, dark map")
                on: settingsMenu.visible
                onClicked: settingsMenu.visible ? settingsMenu.close() : settingsMenu.open()
                QQC2.Popup {
                    id: settingsMenu
                    margins: 6
                    x: parent.width - width
                    y: parent.height + 6
                    width: 350
                    padding: 12
                    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent
                    contentItem: ColumnLayout {
                        spacing: 8
                        QQC2.Label { text: i18n("Settings"); font.bold: true }
                        Segmented {
                            title: i18n("Pictures per second")
                            room: 326
                            choices: [[4, "4"], [8, "8"], [15, "15"]]
                            current: panel.map.maxFps
                            onPicked: function (v) { panel.map.setMaxFps(v); }
                        }
                        Segmented {
                            title: i18n("Resolution while playing")
                            room: 326
                            choices: [[1, i18n("Full")], [2, i18n("Half")], [4, i18n("Quarter")]]
                            current: panel.map.resolution
                            onPicked: function (v) { panel.map.setResolution(v); }
                        }
                        SmallSwitch {
                            text: i18n("Coasts and borders")
                            checked: panel.map.mapLinesOn
                            onToggled: {
                                panel.map.setMapLines(checked);
                                checked = Qt.binding(function () { return panel.map.mapLinesOn; });
                            }
                        }
                        SmallSwitch {
                            text: i18n("Dark map")
                            enabled: !panel.map.darkMapLocked
                            checked: panel.map.mapTheme === "dark"
                            onToggled: {
                                panel.map.setDarkMap(checked);
                                checked = Qt.binding(function () { return panel.map.mapTheme === "dark"; });
                            }
                            QQC2.ToolTip.text: panel.map.darkMapLocked ? i18n("Not available: the selected base map already has a fixed light or dark style.") : i18n("Switch between the light and dark map style. Until first toggled, the map follows the Plasma theme.")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }
            }
        }
        Divider {}
    }

    // The rows in the order of the stack (map.layerOrder, top first; the
    // wind's place orders the column only, it is drawn over the map). Each
    // row hung again on the column, in turn, goes after those before it.
    function arrangeRows() {
        var rowOf = { radar: radarRow, satellite: satRow, wind: windRow, precipitation: precipRow, clouds: cloudRow, temperature: tempRow,
            pressure: presRow, humidity: humRow, dewpoint: dewRow, airquality: aqRow };
        var rows = [layersCaption].concat(map.layerOrder.filter(function (id) { return !!rowOf[id]; })
            .map(function (id) { return rowOf[id]; }));
        rows.forEach(function (r) {
            r.parent = null;
            r.parent = layerColumn;
        });
    }
    Component.onCompleted: arrangeRows()
    /** The titles of the column's rows, in their order (the test hook "rows"). */
    function rowTitles() {
        return layerColumn.children.filter(function (r) { return r.title !== undefined && r.visible; })
            .map(function (r) { return r.title; });
    }
    Connections {
        target: panel.map
        function onLayerOrderChanged() { panel.arrangeRows(); }
    }

    // The whole column scrolls when the popup is too short for it.
    Flickable {
        id: layerScroll
        anchors.fill: parent
        anchors.leftMargin: 1
        anchors.topMargin: headBox.y + headBox.height
        // In step with the buttons gliding one under the other.
        Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        anchors.bottomMargin: timeBox.height + 12
        clip: true
        contentWidth: width
        contentHeight: layerColumn.y + layerColumn.height + 12
        boundsBehavior: Flickable.StopAtBounds
        // A thin bar at the very edge, out of the way of the wheels.
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            policy: QQC2.ScrollBar.AsNeeded
            width: 5
            padding: 1
            background: null
            contentItem: Rectangle {
                implicitWidth: 3
                radius: 1.5
                color: panel.tint(parent.pressed ? 0.55 : parent.hovered ? 0.4 : 0.25)
            }
        }

        Column {
            id: layerColumn
            x: 9.5
            y: 4
            spacing: 7

            Caption { id: layersCaption; text: i18n("Layers") }

            // Radar and satellite; the radar's wheel opens their tile options.
            LayerRow {
                id: radarRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Radar")
                key: panel.map.layerKeys.radar
                iconName: "radar"
                checked: panel.map.layerOn("radar")
                visible: panel.map.layerEnabled("radar")
                opacityValue: panel.map.opacities.radar
                customGear: true
                soloable: true
                soloed: panel.map.solo === "radar" || panel.map.solo === "both"
                soloTip: i18n("Double-click: radar range")
                onSoloRequested: function (withCtrl) { panel.map.soloSource(withCtrl ? "both" : "radar"); }
                onToggled: function (on) { panel.map.clickSource("radar", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("radar", p); }
                onGearClicked: {
                    if (radarMenu.visible) {
                        radarMenu.close();
                        return;
                    }
                    panel.map.readRadar();
                    radarMenu.open();
                }
            }
            RadarMenu {
                id: radarMenu
                parent: radarRow.gearItem
                x: parent.width - width
                y: parent.height + 6
                schemes: panel.map.radarSchemes
                options: panel.map.radarOptions
                onOptionPicked: function (key, value) { panel.map.setRadarOption(key, value); }
            }
            LayerRow {
                id: satRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Satellite")
                key: panel.map.layerKeys.satellite
                iconName: "satellite"
                checked: panel.map.layerOn("satellite")
                visible: panel.map.layerEnabled("satellite")
                opacityValue: panel.map.opacities.satellite
                hasOptions: false
                soloable: true
                soloed: panel.map.solo === "satellite" || panel.map.solo === "both"
                soloTip: i18n("Double-click: satellite range")
                onSoloRequested: function (withCtrl) { panel.map.soloSource(withCtrl ? "both" : "satellite"); }
                onToggled: function (on) { panel.map.clickSource("satellite", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("satellite", p); }
            }

            LayerRow {
                id: windRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Wind")
                key: panel.map.layerKeys.wind
                iconName: "vent-glyph"
                checked: panel.map.layerOn("wind")
                visible: panel.map.layerEnabled("wind")
                opacityValue: panel.map.opacities.wind
                onToggled: function (on) { panel.map.setLayer("wind", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("wind", p); }
                Segmented {
                    title: i18n("Height")
                    choices: panel.map.windLevelChoices
                    current: panel.map.windLevel
                    onPicked: function (v) { panel.map.setWindLevel(v); }
                }
                OptCombo {
                    title: i18n("Colors")
                    choices: panel.map.windPaletteChoices
                    current: panel.map.windPaletteId
                    onPicked: function (v) { panel.map.setWindPaletteId(v); }
                }
            }
            LayerRow {
                id: tempRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Temperature")
                key: panel.map.layerKeys.temperature
                iconName: "temperature-glyph"
                checked: panel.map.layerOn("temperature")
                visible: panel.map.layerEnabled("temperature")
                opacityValue: panel.map.opacities.temperature
                onToggled: function (on) { panel.map.setLayer("temperature", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("temperature", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["temperature"]
                onLegendToggled: function (on) { panel.map.setLegend("temperature", on); }
                Segmented {
                    title: i18n("Width of the bands")
                    choices: panel.map.tempStepChoices
                    current: panel.map.tempStep
                    onPicked: function (v) { panel.map.setTempStep(v); }
                }
                OptCombo {
                    title: i18n("Colors")
                    choices: panel.map.tempPaletteChoices
                    current: panel.map.tempPaletteId
                    onPicked: function (v) { panel.map.setTempPaletteId(v); }
                }
            }
            LayerRow {
                id: precipRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Precipitation (rain, snow)")
                key: panel.map.layerKeys.precipitation
                iconName: "precipitations-glyph"
                checked: panel.map.layerOn("precipitation")
                visible: panel.map.layerEnabled("precipitation")
                opacityValue: panel.map.opacities.precipitation
                onToggled: function (on) { panel.map.setLayer("precipitation", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("precipitation", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["precipitation"]
                onLegendToggled: function (on) { panel.map.setLegend("precipitation", on); }
                OptKinds {
                    title: i18n("Kinds shown")
                    choices: panel.map.precipChoices
                    checkedValues: panel.map.precipKinds
                    onPicked: function (values) { panel.map.setPrecipKinds(values); }
                }
            }
            LayerRow {
                id: cloudRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Cloud cover")
                key: panel.map.layerKeys.clouds
                iconName: "nuages-glyph"
                iconMask: true
                checked: panel.map.layerOn("clouds")
                visible: panel.map.layerEnabled("clouds")
                opacityValue: panel.map.opacities.clouds
                onToggled: function (on) { panel.map.setLayer("clouds", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("clouds", p); }
                OptKinds {
                    title: i18n("Levels shown")
                    choices: panel.map.cloudChoices
                    checkedValues: panel.map.cloudLevels
                    onPicked: function (values) { panel.map.setCloudLevels(values); }
                }
            }
            LayerRow {
                id: presRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Sea level pressure")
                key: panel.map.layerKeys.pressure
                iconName: "pression-glyph"
                checked: panel.map.layerOn("pressure")
                visible: panel.map.layerEnabled("pressure")
                opacityValue: panel.map.opacities.pressure
                onToggled: function (on) { panel.map.setLayer("pressure", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("pressure", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["pressure"]
                onLegendToggled: function (on) { panel.map.setLegend("pressure", on); }
            }
            LayerRow {
                id: humRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Relative humidity")
                key: panel.map.layerKeys.humidity
                iconName: "humidite-glyph"
                checked: panel.map.layerOn("humidity")
                visible: panel.map.layerEnabled("humidity")
                opacityValue: panel.map.opacities.humidity
                onToggled: function (on) { panel.map.setLayer("humidity", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("humidity", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["humidity"]
                onLegendToggled: function (on) { panel.map.setLegend("humidity", on); }
            }
            LayerRow {
                id: dewRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Dew point")
                key: panel.map.layerKeys.dewpoint
                iconName: "rosee-glyph"
                checked: panel.map.layerOn("dewpoint")
                visible: panel.map.layerEnabled("dewpoint")
                opacityValue: panel.map.opacities.dewpoint
                onToggled: function (on) { panel.map.setLayer("dewpoint", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("dewpoint", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["dewpoint"]
                onLegendToggled: function (on) { panel.map.setLegend("dewpoint", on); }
            }
            LayerRow {
                id: aqRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Air quality (CAMS)")
                key: panel.map.layerKeys.airquality
                iconName: "qualite-air-glyph"
                iconMask: true
                checked: panel.map.layerOn("airquality")
                visible: panel.map.layerEnabled("airquality")
                opacityValue: panel.map.opacities.airquality
                onToggled: function (on) { panel.map.setLayer("airquality", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("airquality", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["airquality"]
                onLegendToggled: function (on) { panel.map.setLegend("airquality", on); }
                OptSwitches {
                    title: i18n("Pollutant")
                    choices: panel.map.aqChoices
                    current: panel.map.pollutant
                    onPicked: function (v) { panel.map.setPollutant(v); }
                }
            }
        }
    }

    // The time, always in sight at the bottom of the column (the column
    // scrolls above it): how far back, how far ahead, the speed.
    Column {
        id: timeBox
        x: 9.5
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        spacing: 7
        Divider {}
        Caption { text: i18n("Time") }
        // How far back, how far ahead (the wheel steps them), the speed.
        Flow {
            width: panel.colW
            spacing: panel.folded ? 4 : 10
            // Side by side open, one under the other folded: they glide there.
            move: Transition { NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic } }
            RangeIcon {
                id: pastPick
                prefix: "−"
                // A source's range shows its name on both clocks, its hours in the bubble.
                override: panel.map.solo ? "−" + panel.map.hoursText(panel.map.pastH) : ""
                detail: panel.map.rangeKind && !panel.map.solo ? "−" + panel.map.hoursText(panel.map.pastH) : ""
                choices: panel.map.pastChoices
                current: Math.max(0, panel.map.pastChoices.map(function (c) { return c[0]; }).indexOf(panel.map.rangeKind || panel.map.savedPastH))
                tip: i18n("How far back")
                onPicked: function (h) { panel.map.pickRange(h, panel.map.rangeKind ? panel.map.savedFutureH : panel.map.futureH); }
            }
            RangeIcon {
                id: futurePick
                prefix: "+"
                // A source's range shows its name on both clocks, its hours in the bubble.
                override: panel.map.solo ? "+" + panel.map.hoursText(panel.map.futureH) : ""
                detail: panel.map.rangeKind && !panel.map.solo ? "+" + panel.map.hoursText(panel.map.futureH) : ""
                mirror: true
                choices: panel.map.futureChoices
                current: Math.max(0, panel.map.futureChoices.map(function (c) { return c[0]; }).indexOf(panel.map.rangeKind || panel.map.savedFutureH))
                tip: i18n("How far ahead")
                onPicked: function (h) { panel.map.pickRange(panel.map.rangeKind ? panel.map.savedPastH : panel.map.pastH, h); }
            }
            // x1, x2, x3 in turn, one a click: 3 hours of weather in 1.5 s, 0.75 s, 0.5 s.
            Item {
                id: speedIcon
                readonly property int speed: panel.map.speed
                implicitWidth: 36
                implicitHeight: 40
                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: panel.tint(speedArea.containsMouse ? 0.10 : 0)
                }
                // One triangle a step of speed.
                Canvas {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 5
                    width: 26
                    height: 16
                    property int n: speedIcon.speed
                    property color fill: panel.fg
                    onNChanged: requestPaint()
                    onFillChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"), w = 8, gap = 1, total = n * w + (n - 1) * gap, x0 = (width - total) / 2;
                        c.reset();
                        c.fillStyle = fill;
                        for (var i = 0; i < n; i++) {
                            var x = x0 + i * (w + gap);
                            c.beginPath();
                            c.moveTo(x, 2);
                            c.lineTo(x + w, 8);
                            c.lineTo(x, 14);
                            c.closePath();
                            c.fill();
                        }
                    }
                }
                QQC2.Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 25
                    text: "x" + speedIcon.speed
                    color: panel.fg
                    font.pixelSize: 11
                    font.bold: true
                }
                MouseArea {
                    id: speedArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.map.setSpeed(speedIcon.speed % 3 + 1)
                }
                QQC2.ToolTip.text: "<b>" + i18n("Speed x%1", speedIcon.speed) + "</b> (+ −)"
                QQC2.ToolTip.visible: speedArea.containsMouse
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    // Folds the column to its icons, or opens it.
    Rectangle {
        x: 1
        anchors.verticalCenter: parent.verticalCenter
        width: 8
        height: 56
        radius: 4
        color: panel.tint(foldArea.containsMouse ? 0.18 : 0.07)
        QQC2.Label {
            anchors.centerIn: parent
            text: panel.folded ? "‹" : "›"
            color: panel.dimText
            font.pixelSize: 12
            font.bold: true
        }
        MouseArea {
            id: foldArea
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.map.setFolded(!panel.folded)
        }
        QQC2.ToolTip.text: panel.folded ? i18n("Open the layer column") : i18n("Fold the layer column")
        QQC2.ToolTip.visible: foldArea.containsMouse
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
