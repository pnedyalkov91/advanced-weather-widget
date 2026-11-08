import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

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

    // An option of a layer with one value: its name, then a list under it.
    component OptCombo: ColumnLayout {
        id: oc
        property string title
        property var choices: []        // [[value, text]]
        property int current: 0
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 2
        QQC2.Label { text: oc.title; color: panel.dimText }
        QQC2.ComboBox {
            Layout.fillWidth: true
            model: oc.choices.map(function (c) { return c[1]; })
            currentIndex: oc.current
            onActivated: function (i) { oc.current = i; oc.picked(oc.choices[i][0]); }
        }
    }
    // The kinds of a layer shown, several at once: a list that opens on a
    // switch for each, "All" first. Each change is sent at once.
    component OptKinds: ColumnLayout {
        id: ok
        property string title
        property var choices: []        // [[value, text]]
        property var checkedValues: choices.map(function (c) { return c[0]; })
        signal picked(var values)
        Layout.fillWidth: true
        spacing: 2
        readonly property var _labels: choices.filter(function (c) { return checkedValues.indexOf(c[0]) >= 0; }).map(function (c) { return c[1]; })
        readonly property string label: _labels.length === choices.length ? i18n("All")
            : _labels.length === 0 ? i18n("None")
            : _labels.length <= 2 ? _labels.join(" + ")
            : i18np("%1 kind", "%1 kinds", _labels.length)
        function set(values) {
            // In the order of the choices.
            var v = choices.map(function (c) { return c[0]; }).filter(function (x) { return values.indexOf(x) >= 0; });
            picked(v);
        }
        QQC2.Label { text: ok.title; color: panel.dimText }
        QQC2.ComboBox {
            id: kindsCombo
            Layout.fillWidth: true
            model: []
            displayText: ok.label
            popup: QQC2.Popup {
                y: kindsCombo.height + 2
                width: kindsCombo.width
                padding: 6
                margins: 6
                closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent
                contentItem: ColumnLayout {
                    spacing: 0
                    QQC2.Switch {
                        text: i18n("All")
                        font.bold: true
                        checked: ok.checkedValues.length === ok.choices.length
                        onToggled: {
                            ok.set(checked ? ok.choices.map(function (c) { return c[0]; }) : []);
                            checked = Qt.binding(function () { return ok.checkedValues.length === ok.choices.length; });
                        }
                    }
                    Repeater {
                        model: ok.choices
                        delegate: QQC2.Switch {
                            required property var modelData
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
        WmIcon {
            visible: hb.text === ""
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

    // The whole column scrolls when the popup is too short for it.
    Flickable {
        id: layerScroll
        anchors.fill: parent
        anchors.leftMargin: 1
        anchors.bottomMargin: modelsBox.visible ? modelsBox.height + 18 : 0
        clip: true
        contentWidth: width
        contentHeight: layerColumn.y + layerColumn.height + 12
        boundsBehavior: Flickable.StopAtBounds
        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

        Column {
            id: layerColumn
            x: 9.5
            y: 8
            spacing: 7

            // The help and the settings, top right of the column (one under the other, folded).
            Flow {
                width: panel.colW
                layoutDirection: Qt.RightToLeft
                spacing: 8
                HeadButton {
                    text: "?"
                    tip: i18n("How to read the Weather Map")
                    on: panel.map.helpOpen
                    onClicked: panel.map.toggleHelp()
                }
                // Set once: pictures per second at most, the resolution
                // while playing, coasts and borders, the dark map.
                HeadButton {
                    id: settingsButton
                    iconName: "gear"
                    tip: i18n("Settings: pictures per second,<br>resolution while playing, coasts and borders, dark map")
                    on: settingsMenu.visible
                    onClicked: settingsMenu.visible ? settingsMenu.close() : settingsMenu.open()
                    QQC2.Popup {
                        id: settingsMenu
                        margins: 6
                        x: parent.width - width
                        y: parent.height + 6
                        width: 290
                        padding: 12
                        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent
                        contentItem: ColumnLayout {
                            spacing: 8
                            QQC2.Label { text: i18n("Settings"); font.bold: true }
                            // Pictures per second at most: three side by side, the one taken highlighted.
                            RowLayout {
                                Layout.fillWidth: true
                                QQC2.Label { text: i18n("Pictures per second"); color: panel.dimText; Layout.fillWidth: true }
                                Rectangle {
                                    implicitWidth: fpsRow.implicitWidth + 4
                                    implicitHeight: 26
                                    radius: 4
                                    color: panel.tint(0.06)
                                    border.color: panel.tint(0.12)
                                    Row {
                                        id: fpsRow
                                        anchors.centerIn: parent
                                        Repeater {
                                            model: [4, 8, 15]
                                            Rectangle {
                                                required property int modelData
                                                readonly property bool taken: panel.map.maxFps === modelData
                                                width: 34
                                                height: 22
                                                radius: 3
                                                color: taken ? panel.accent : "transparent"
                                                QQC2.Label {
                                                    anchors.centerIn: parent
                                                    text: parent.modelData
                                                    font.bold: parent.taken
                                                    color: parent.taken ? Kirigami.Theme.highlightedTextColor : panel.dimText
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: panel.map.setMaxFps(parent.modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            OptCombo {
                                title: i18n("Resolution while playing")
                                choices: [[1, i18n("Full")], [2, i18n("Half")], [4, i18n("Quarter")]]
                                current: [1, 2, 4].indexOf(panel.map.resolution)
                                onPicked: function (v) { panel.map.setResolution(v); }
                            }
                            QQC2.Switch {
                                text: i18n("Coasts and borders")
                                checked: panel.map.mapLinesOn
                                onToggled: {
                                    panel.map.setMapLines(checked);
                                    checked = Qt.binding(function () { return panel.map.mapLinesOn; });
                                }
                            }
                            QQC2.Switch {
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

            Caption { text: i18n("Layers") }

            // Radar and satellite; the radar's wheel opens their tile options.
            LayerRow {
                id: radarRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Radar")
                iconName: "radar"
                checked: panel.map.layerOn("radar")
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
                iconName: "satellite"
                iconMask: true
                checked: panel.map.layerOn("satellite")
                opacityValue: panel.map.opacities.satellite
                hasOptions: false
                soloable: true
                soloed: panel.map.solo === "satellite" || panel.map.solo === "both"
                soloTip: i18n("Double-click: satellite range")
                onSoloRequested: function (withCtrl) { panel.map.soloSource(withCtrl ? "both" : "satellite"); }
                onToggled: function (on) { panel.map.clickSource("satellite", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("satellite", p); }
            }
            Divider {}

            LayerRow {
                id: windRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Wind")
                iconName: "vent-glyph"
                checked: panel.map.layerOn("wind")
                opacityValue: panel.map.opacities.wind
                onToggled: function (on) { panel.map.setLayer("wind", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("wind", p); }
                OptCombo {
                    title: i18n("Height")
                    choices: panel.map.windLevelChoices
                    current: panel.map.windLevelChoices.map(function (c) { return c[0]; }).indexOf(panel.map.windLevel)
                    onPicked: function (v) { panel.map.setWindLevel(v); }
                }
            }
            LayerRow {
                id: tempRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Temperature")
                iconName: "temperature-glyph"
                checked: panel.map.layerOn("temperature")
                opacityValue: panel.map.opacities.temperature
                onToggled: function (on) { panel.map.setLayer("temperature", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("temperature", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["temperature"]
                onLegendToggled: function (on) { panel.map.setLegend("temperature", on); }
                OptCombo {
                    title: i18n("Width of the bands")
                    choices: panel.map.tempStepChoices
                    current: panel.map.tempStepChoices.map(function (c) { return c[0]; }).indexOf(panel.map.tempStep)
                    onPicked: function (v) { panel.map.setTempStep(v); }
                }
            }
            LayerRow {
                id: precipRow
                width: panel.colW
                compact: panel.folded
                title: i18n("Precipitation (rain, snow)")
                iconName: "precipitations-glyph"
                checked: panel.map.layerOn("precipitation")
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
                iconName: "nuages-glyph"
                iconMask: true
                checked: panel.map.layerOn("clouds")
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
                iconName: "pression-glyph"
                checked: panel.map.layerOn("pressure")
                active: checked || panel.map.layerOn("isobars")
                opacityValue: panel.map.opacities.pressure
                onToggled: function (on) { panel.map.setLayer("pressure", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("pressure", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["pressure"]
                onLegendToggled: function (on) { panel.map.setLegend("pressure", on); }
                QQC2.Switch {
                    text: i18n("Isobars")
                    checked: panel.map.layerOn("isobars")
                    onToggled: {
                        panel.map.setLayer("isobars", checked);
                        checked = Qt.binding(function () { return panel.map.layerOn("isobars"); });
                    }
                }
            }
            LayerRow {
                width: panel.colW
                compact: panel.folded
                title: i18n("Relative humidity")
                iconName: "humidite-glyph"
                checked: panel.map.layerOn("humidity")
                opacityValue: panel.map.opacities.humidity
                onToggled: function (on) { panel.map.setLayer("humidity", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("humidity", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["humidity"]
                onLegendToggled: function (on) { panel.map.setLegend("humidity", on); }
            }
            LayerRow {
                width: panel.colW
                compact: panel.folded
                title: i18n("Dew point")
                iconName: "rosee-glyph"
                checked: panel.map.layerOn("dewpoint")
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
                iconName: "qualite-air-glyph"
                iconMask: true
                checked: panel.map.layerOn("airquality")
                opacityValue: panel.map.opacities.airquality
                onToggled: function (on) { panel.map.setLayer("airquality", on); }
                onOpacityPicked: function (p) { panel.map.setOpacity("airquality", p); }
                hasLegend: true
                legendOn: !panel.map.legendsHidden["airquality"]
                onLegendToggled: function (on) { panel.map.setLegend("airquality", on); }
                OptCombo {
                    title: i18n("Pollutant")
                    choices: panel.map.aqChoices
                    current: Math.max(0, panel.map.aqChoices.map(function (c) { return c[0]; }).indexOf(panel.map.pollutant))
                    onPicked: function (v) { panel.map.setPollutant(v); }
                }
            }
            Divider {}
            Caption { text: i18n("Time") }
            // How far back, how far ahead (the wheel steps them), the speed.
            Flow {
                width: panel.colW
                spacing: panel.folded ? 4 : 10
                RangeIcon {
                    id: pastPick
                    prefix: "−"
                    override: panel.map.solo ? "−" + panel.map.hoursText(panel.map.pastH) : ""
                    choices: panel.map.pastChoices
                    current: Math.max(0, panel.map.pastChoices.map(function (c) { return c[0]; }).indexOf(panel.map.savedPastH))
                    tip: i18n("How far back")
                    onPicked: function (h) { panel.map.pickRange(h, panel.map.futureH); }
                }
                RangeIcon {
                    id: futurePick
                    prefix: "+"
                    override: panel.map.solo ? "+" + panel.map.hoursText(panel.map.futureH) : ""
                    mirror: true
                    choices: panel.map.futureChoices
                    current: Math.max(0, panel.map.futureChoices.map(function (c) { return c[0]; }).indexOf(panel.map.savedFutureH))
                    tip: i18n("How far ahead")
                    onPicked: function (h) { panel.map.pickRange(panel.map.pastH, h); }
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
                    QQC2.ToolTip.text: i18n("Speed x%1: 3 hours in %2 s", speedIcon.speed, Number(1.5 / speedIcon.speed).toLocaleString(Qt.locale(), "f", 2).replace(/0$/, "")) + "<br><i>" + i18n("Click for the next speed") + "</i>"
                    QQC2.ToolTip.visible: speedArea.containsMouse
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }
    }

    // The models drawn, at the bottom of the open column: the global one,
    // then the finer ones over this view.
    Column {
        id: modelsBox
        visible: !panel.folded
        x: 10.5
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        spacing: 2
        QQC2.Label {
            text: i18n("Models")
            color: panel.dimText
            font.pixelSize: 12
            font.bold: true
        }
        QQC2.Label {
            width: 165
            wrapMode: Text.Wrap
            color: panel.fg
            font.pixelSize: 13
            text: panel.map.animState && panel.map.animState.models ? panel.map.animState.models.join(", ") : "…"
            HoverHandler { id: modelsHover }
            QQC2.ToolTip.text: i18n("The global model, then the finer regional<br>ones drawn over it in this view")
            QQC2.ToolTip.visible: modelsHover.hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
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
