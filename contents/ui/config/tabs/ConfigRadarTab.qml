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
 * ConfigRadarTab.qml - Radar tab content
 *
 * Extracted from configGeneral.qml for readability.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.plasmoid
import "../../js/weather.js" as W

GridLayout {
    id: radarTab

    Layout.fillWidth: true
    // children with a maximum width would otherwise cap the grid itself and make
    // it flip between one and two columns
    Layout.maximumWidth: Number.POSITIVE_INFINITY
    Layout.alignment: Qt.AlignTop
    // Label and control on one line when there is room (like the wide mode of
    // Kirigami.FormLayout); the label goes above its control in a narrow window.
    columns: width >= Kirigami.Units.gridUnit * 30 ? 2 : 1
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: columns === 1 ? Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing * 2

    /** Reference to the root KCM (configGeneral) for cfg_* properties, functions and state */
    required property var configRoot

    /** The default wind palette (the Beaufort scale grouped), upper bounds in
        m/s as the map page has them; the last level is open. */
    readonly property var defaultWindPalette: [[5, "#ffffff"], [12, "#2ecc40"], [20, "#7fdbff"], [38, "#1e64ff"], [50, "#ffdc00"], [75, "#ff851b"], [118, "#ff2020"], [0, "#8a5cff"]].map(function (b, i) {
        return {
            max: i === 7 ? 0 : Math.round(b[0] / 3.6 * 1000) / 1000,
            color: b[1]
        };
    })
    /** The wind palettes made here: [{ name, levels: [{ max, color }] x 8 }]. */
    readonly property var windPalettes: {
        try {
            var list = JSON.parse(radarTab.configRoot.cfg_librewxrWindPalettes || "[]");
            return Array.isArray(list) ? list : [];
        } catch (e) {
            return [];
        }
    }
    readonly property string windUnit: Plasmoid.configuration.windSpeedUnit || "kmh"

    /** A wind speed in m/s, in the wind unit of the settings; and back. */
    function windToUnit(ms) {
        return Number(W.formatWindValue(ms * 3.6, radarTab.windUnit));
    }
    function windFromUnit(value) {
        var perKmh = radarTab.windUnit === "mph" ? 0.621371 : (radarTab.windUnit === "ms" ? 1 / 3.6 : (radarTab.windUnit === "kn" ? 0.539957 : 1));
        return value / perKmh / 3.6;
    }
    function saveWindPalettes(list, selected) {
        radarTab.configRoot.cfg_librewxrWindPalettes = JSON.stringify(list);
        radarTab.configRoot.cfg_librewxrWindPalette = selected;
    }

    // Section title with a thin rule, same look as the Notifications page.
    component SectionHeader: RowLayout {
        required property string title
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: parent.title
            font.bold: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.5
        }
    }

    // A Switch whose label wraps onto several lines instead of forcing the
    // whole page wider than the (resizable) settings window. A plain Switch
    // keeps its full single-line text width and cannot shrink, so a long
    // label gets clipped when the window is narrow.
    component WrappingSwitch: Switch {
        id: wrappingSwitch
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        contentItem: Label {
            text: wrappingSwitch.text
            font: wrappingSwitch.font
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            leftPadding: wrappingSwitch.indicator && !wrappingSwitch.mirrored ? wrappingSwitch.indicator.width + wrappingSwitch.spacing : 0
            rightPadding: wrappingSwitch.indicator && wrappingSwitch.mirrored ? wrappingSwitch.indicator.width + wrappingSwitch.spacing : 0
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // SECTION: Radar
    // ═══════════════════════════════════════════════════════════════
    SectionHeader {
        title: i18n("Radar Settings")
        Layout.columnSpan: radarTab.columns
    }

    Item {
        // empty label cell: keeps the control in the second column
        visible: radarTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Item {
        Layout.preferredHeight: Kirigami.Units.smallSpacing
    }

    WrappingSwitch {
        Layout.columnSpan: radarTab.columns
        text: i18n("Show Radar tab in widget")
        checked: radarTab.configRoot.cfg_radarEnabled
        onToggled: radarTab.configRoot.cfg_radarEnabled = checked
    }

    Item {
        // empty label cell: keeps the control in the second column
        visible: radarTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Item {
        Layout.preferredHeight: Kirigami.Units.smallSpacing
    }

    ColumnLayout {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: radarTab.configRoot.cfg_radarEnabled

        WrappingSwitch {
            text: i18n("Keep the radar loaded in the background")
            checked: radarTab.configRoot.cfg_radarKeepLoaded
            onToggled: radarTab.configRoot.cfg_radarKeepLoaded = checked
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("The radar map is prepared in the background after login and stays ready while the popup is closed, so the Radar tab opens at once. It uses more memory and starts QtWebEngine with Plasma.")
        }
    }

    Item {
        // empty label cell: keeps the control in the second column
        visible: radarTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Item {
        Layout.preferredHeight: Kirigami.Units.smallSpacing
    }

    WrappingSwitch {
        Layout.columnSpan: radarTab.columns
        visible: radarTab.configRoot.cfg_radarEnabled
        text: i18n("Workaround radar map crashes on hybrid-GPU systems (EXPERIMENTAL)")
        checked: radarTab.configRoot.cfg_radarGpuWorkaround
        onToggled: {
            radarTab.configRoot.cfg_radarGpuWorkaround = checked;
            radarTab.configRoot.radarGpuWorkaroundExec.apply(checked);
            // Re-check either way: turning it on shows whether it needs a
            // logout to become active, turning it off shows whether it's
            // still live for the rest of this session (see the "Off -"
            // message below) rather than just disappearing silently.
            radarTab.configRoot.radarGpuWorkaroundExec.checkStatus();
        }
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarGpuWorkaround
        showCloseButton: false
        type: Kirigami.MessageType.Warning
        text: i18n("<b>Hybrid-GPU / NVIDIA PRIME + Wayland crash workaround</b><br/><br/>" + "On some hybrid-GPU laptops running Wayland, the Radar tab's embedded browser view can crash the whole Plasma shell the moment it first paints, due to a driver-level conflict between the two GPUs. This option disables GPU-accelerated compositing inside that browser view to avoid it.<br/><br/>" + "Only enable this if you're actually experiencing that crash - it costs some rendering performance on the radar map.<br/><br/>" + `<b>This needs a log out and back in to take effect</b>, since it has to be set before Plasma starts. It also applies to the whole session, so any other app that embeds a Chromium-based browser view will pick up the same setting. Turning it back off later needs the same log out/in to fully clear it too.
        <br/><br/>` + "If you enable this option, the following file will be created in: ~/.config/plasma-workspace/env/advanced-weather-widget-radar-gpu-workaround.sh")
        actions: [
            Kirigami.Action {
                text: i18n("Log Out Now…")
                icon.name: "system-log-out"
                onTriggered: radarTab.configRoot.radarGpuWorkaroundExec.logout()
            }
        ]
    }

    Item {
        // empty label cell: keeps the control in the second column
        visible: radarTab.columns === 2 && (radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarGpuWorkaround)
        implicitWidth: 0
        implicitHeight: 0
    }
    RowLayout {
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarGpuWorkaround
        Layout.fillWidth: true

        Button {
            text: radarTab.configRoot.radarGpuTestState === 1 ? i18n("Checking…") : i18n("Check Status")
            icon.name: "view-refresh"
            enabled: radarTab.configRoot.radarGpuTestState !== 1
            onClicked: radarTab.configRoot.radarGpuWorkaroundExec.checkStatus()
        }
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.radarGpuTestState === 2
        type: Kirigami.MessageType.Positive
        text: radarTab.configRoot.radarGpuTestMessage
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.radarGpuTestState === 3
        type: Kirigami.MessageType.Warning
        text: radarTab.configRoot.radarGpuTestMessage
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.radarGpuTestState === 4
        type: Kirigami.MessageType.Error
        text: radarTab.configRoot.radarGpuTestMessage
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.radarGpuTestState === 5
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: radarTab.configRoot.radarGpuTestMessage
        actions: [
            Kirigami.Action {
                text: i18n("Log Out Now…")
                icon.name: "system-log-out"
                onTriggered: radarTab.configRoot.radarGpuWorkaroundExec.logout()
            }
        ]
    }

    Item {
        // empty label cell: keeps the control in the second column
        visible: radarTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Item {
        Layout.preferredHeight: Kirigami.Units.smallSpacing
    }

    Label {
        text: i18n("Radar provider:")
        visible: radarTab.configRoot.cfg_radarEnabled
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: radarTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: radarProviderCombo
        Layout.preferredWidth: 280
        visible: radarTab.configRoot.cfg_radarEnabled
        model: [
            {
                text: i18n("Rain Viewer"),
                value: "rainviewer"
            },
            {
                text: i18n("LibreWXR"),
                value: "librewxr"
            }
        ]
        textRole: "text"
        currentIndex: radarTab.configRoot.cfg_radarProvider === "librewxr" ? 1 : 0
        onActivated: radarTab.configRoot.cfg_radarProvider = model[currentIndex].value
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider !== "librewxr"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Radar provider: <a href='https://www.rainviewer.com/'>Rain Viewer</a><br/><br/>" + "The widget uses the free RainViewer API, which provides the past 2 hours of weather radar data in 10-minute intervals. Radar forecast is not supported.<br/><br/>" + "Rain Viewer does not guarantee the availability of radar data. " + "They do not conclude contracts with owners of this data. " + "The reason is that the owners can ask them to remove their data from Rain Viewer, " + "change the format, or stop sharing the data. " + "They are trying to keep radar data for as long as possible, " + "but sometimes the owners just stop providing the images.")
        onLinkActivated: link => Qt.openUrlExternally(link)
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Radar provider: <a href='https://librewxr.net/'>LibreWXR</a><br/><br/>" + "LibreWXR is a free, open-source weather radar API. It combines real radar composites from NOAA, Canadian, and European sources with a global model fallback, and provides the past 2 hours of radar data plus a short nowcast. It also offers a free satellite (infrared) layer.<br/><br/>" + "Layer mode, radar color scheme, and motion arrows are selected directly in the Radar tab. The map follows your Plasma light/dark theme automatically.")
        onLinkActivated: link => Qt.openUrlExternally(link)
    }

    // LibreWXR is self-hostable, so let the user point the radar and the
    // alerts provider at their own instance instead of the public API.
    Label {
        text: i18n("LibreWXR server:")
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        Layout.topMargin: radarTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"

        TextField {
            id: librewxrUrlField
            Layout.fillWidth: true
            placeholderText: "https://api.librewxr.net"
            text: radarTab.configRoot.cfg_librewxrUrl
            selectByMouse: true
            onTextEdited: radarTab.configRoot.cfg_librewxrUrl = text
            onEditingFinished: radarTab.configRoot.cfg_librewxrUrl = text.trim()
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Leave this empty to use the public server. Set it to your own address if you run a self-hosted LibreWXR instance.")
        }
    }

    // The animated wind layer of the LibreWXR map. Its data comes from
    // Open-Meteo, not from the LibreWXR server. It redraws the map at
    // every frame, so the frame-rate budget is what the CPU cost
    // depends on; the rate rises with the wind speed inside the range.
    Label {
        text: i18n("Wind animation:")
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        Layout.topMargin: radarTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"

        ComboBox {
            id: windQualityCombo
            Layout.preferredWidth: 280
            model: [
                {
                    text: i18n("Economy (8 to 10 fps)"),
                    value: "economy"
                },
                {
                    text: i18n("Balanced (10 to 20 fps)"),
                    value: "balanced"
                },
                {
                    text: i18n("Smooth (20 to 30 fps)"),
                    value: "smooth"
                }
            ]
            textRole: "text"
            currentIndex: radarTab.configRoot.cfg_librewxrWindQuality === "economy" ? 0 : (radarTab.configRoot.cfg_librewxrWindQuality === "smooth" ? 2 : 1)
            onActivated: radarTab.configRoot.cfg_librewxrWindQuality = model[currentIndex].value
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("The Radar tab can animate the wind as moving particles (switch it on there). The wind data comes from <a href='https://open-meteo.com/'>Open-Meteo</a>, independently of the LibreWXR server. This sets the frame rate: lower it on a slow computer, raise it if strong winds look jerky.")
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }

    Label {
        text: i18n("Particle width:")
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"

        Slider {
            Layout.preferredWidth: 220
            from: 0.5
            to: 2
            stepSize: 0.1
            value: radarTab.configRoot.cfg_librewxrWindLineWidth
            onMoved: radarTab.configRoot.cfg_librewxrWindLineWidth = Math.round(value * 10) / 10
        }
        Label {
            text: i18n("%1 px", Number(radarTab.configRoot.cfg_librewxrWindLineWidth).toLocaleString(Qt.locale(), "f", 1))
        }
    }

    // Wind palettes: the default one, and the ones made here, kept by name.
    Label {
        text: i18n("Wind palette:")
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider === "librewxr"

        ComboBox {
            id: windPaletteCombo
            Layout.preferredWidth: 200
            model: [i18n("Default")].concat(radarTab.windPalettes.map(function (p) {
                return p.name;
            }))
            currentIndex: {
                var name = radarTab.configRoot.cfg_librewxrWindPalette;
                for (var i = 0; i < radarTab.windPalettes.length; i++) {
                    if (radarTab.windPalettes[i].name === name)
                        return i + 1;
                }
                return 0;
            }
            onActivated: radarTab.configRoot.cfg_librewxrWindPalette = currentIndex === 0 ? "" : radarTab.windPalettes[currentIndex - 1].name
        }
        Button {
            icon.name: "list-add"
            text: i18n("New…")
            onClicked: windPaletteDialog.openFor(-1)
        }
        Button {
            icon.name: "document-edit"
            text: i18n("Edit…")
            enabled: windPaletteCombo.currentIndex > 0
            onClicked: windPaletteDialog.openFor(windPaletteCombo.currentIndex - 1)
        }
        Button {
            icon.name: "edit-delete"
            text: i18n("Delete")
            enabled: windPaletteCombo.currentIndex > 0
            onClicked: {
                var list = radarTab.windPalettes.slice();
                list.splice(windPaletteCombo.currentIndex - 1, 1);
                radarTab.saveWindPalettes(list, "");
            }
        }
    }

    // Editor of one palette: its name, then 8 levels, each a color and the
    // speed it goes up to (the last one has no limit).
    Dialog {
        id: windPaletteDialog

        property int index: -1       // palette edited; -1 for a new one
        property var levels: []
        readonly property string unitLabel: i18n(W.windUnitLabel(radarTab.windUnit))

        function openFor(i) {
            index = i;
            var from = i >= 0 ? radarTab.windPalettes[i].levels : (windPaletteCombo.currentIndex > 0 ? radarTab.windPalettes[windPaletteCombo.currentIndex - 1].levels : radarTab.defaultWindPalette);
            levels = from.map(function (l) {
                return {
                    max: Number(l.max),
                    color: String(l.color)
                };
            });
            nameField.text = i >= 0 ? radarTab.windPalettes[i].name : "";
            check();
            open();
        }
        function setLevel(i, key, value) {
            var list = levels.slice(), level = {
                max: list[i].max,
                color: list[i].color
            };
            level[key] = value;
            list[i] = level;
            levels = list;
            check();
        }
        // The OK button waits for a free name and limits that go up.
        function check() {
            var name = nameField.text.trim(), problem = "";
            if (!name)
                problem = i18n("Give the palette a name.");
            for (var k = 0; k < radarTab.windPalettes.length && !problem; k++) {
                if (k !== index && radarTab.windPalettes[k].name === name)
                    problem = i18n("Another palette has this name.");
            }
            for (var j = 0; j < 7 && !problem; j++) {
                if (!(levels[j].max > (j > 0 ? levels[j - 1].max : 0)))
                    problem = i18n("Each level must go higher than the one before.");
            }
            errorLabel.text = problem;
            var ok = standardButton(Dialog.Ok);
            if (ok)
                ok.enabled = problem === "";
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        title: index < 0 ? i18n("New wind palette") : i18n("Edit wind palette")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            var entry = {
                name: nameField.text.trim(),
                levels: levels.map(function (l, i) {
                    return {
                        max: i === 7 ? 0 : Math.round(l.max * 1000) / 1000,
                        color: l.color
                    };
                })
            };
            var list = radarTab.windPalettes.slice();
            if (index >= 0)
                list[index] = entry;
            else
                list.push(entry);
            radarTab.saveWindPalettes(list, entry.name);
        }

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: i18n("Palette name")
                onTextChanged: windPaletteDialog.check()
            }
            Repeater {
                model: 8
                delegate: RowLayout {
                    id: levelRow
                    required property int index
                    spacing: Kirigami.Units.smallSpacing

                    KQuickControls.ColorButton {
                        showAlphaChannel: false
                        dialogTitle: i18n("Wind color")
                        color: windPaletteDialog.levels.length ? windPaletteDialog.levels[levelRow.index].color : "white"
                        onAccepted: picked => windPaletteDialog.setLevel(levelRow.index, "color", picked.toString())
                    }
                    Label {
                        text: levelRow.index < 7 ? i18n("up to") : (windPaletteDialog.levels.length ? i18n("above %1 %2", radarTab.windToUnit(windPaletteDialog.levels[6].max), windPaletteDialog.unitLabel) : "")
                    }
                    TextField {
                        visible: levelRow.index < 7
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        text: windPaletteDialog.levels.length && levelRow.index < 7 ? String(radarTab.windToUnit(windPaletteDialog.levels[levelRow.index].max)) : ""
                        validator: DoubleValidator {
                            bottom: 0
                            decimals: 1
                            notation: DoubleValidator.StandardNotation
                        }
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        onEditingFinished: windPaletteDialog.setLevel(levelRow.index, "max", radarTab.windFromUnit(Number(text.replace(",", "."))))
                    }
                    Label {
                        visible: levelRow.index < 7
                        text: windPaletteDialog.unitLabel
                    }
                }
            }
            Button {
                icon.name: "edit-reset"
                text: i18n("Default colors and limits")
                onClicked: {
                    windPaletteDialog.levels = radarTab.defaultWindPalette.map(function (l) {
                        return {
                            max: l.max,
                            color: l.color
                        };
                    });
                    windPaletteDialog.check();
                }
            }
            Label {
                id: errorLabel
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.negativeTextColor
                visible: text !== ""
            }
        }
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        showCloseButton: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider !== "librewxr" && radarTab.configRoot.cfg_radarEnabled && (radarTab.configRoot.cfg_owApiKey || "").trim() === ""
        type: Kirigami.MessageType.Information
        text: i18n("To unlock additional map layers (Rain, Clouds, Temperature, Wind, Pressure): " + "disable Adaptive mode from the 'Provider' tab, select OpenWeatherMap as your weather provider, and enter your API key above. When you are ready, you can enable Adaptive mode again.")
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: radarTab.columns
        Layout.fillWidth: true
        showCloseButton: true
        visible: radarTab.configRoot.cfg_radarEnabled && radarTab.configRoot.cfg_radarProvider !== "librewxr" && radarTab.configRoot.cfg_radarEnabled && (radarTab.configRoot.cfg_owApiKey || "").trim() !== ""
        type: Kirigami.MessageType.Warning
        text: i18n("<b>Why OWM layers may not match RainViewer radar</b><br/><br/>" + "OWM precipitation/cloud layers are <b>static model tiles</b> - they show a smoothed NWP (Numerical Weather Prediction) output, not actual radar returns. " + "They represent where the model <i>thinks</i> it is raining based on interpolation between weather stations and model runs.<br/><br/>" + "RainViewer uses <b>real weather radar composites</b> from radar stations - actual measured reflectivity updated every 2-10 minutes. " + "This discrepancy is expected and known.")
    }

    // Invisible filler row: it lets the second column take ALL spare width, so the
    // label column keeps its width when rows are shown or hidden.
    Item {
        visible: radarTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Item {
        visible: radarTab.columns === 2
        Layout.fillWidth: true
        implicitWidth: 0
        implicitHeight: 0
    }
}
