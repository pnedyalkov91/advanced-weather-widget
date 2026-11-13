import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as QtDialogs
import org.kde.kirigami as Kirigami
import "../../js/configUtils.js" as ConfigUtils

// Editor of one temperature palette of the radar map: its name, then 2 to 12
// points, each a temperature and a color, with a gradient between them.
// Temperatures show and are typed in the widget's unit, and are kept in °C.
Dialog {
    id: tempPaletteDialog

    property int index: -1          // palette edited; -1 for a new one
    property var takenNames: []     // names the palette may not take
    property string unit: "C"       // "C" or "F"
    property var stops: []          // [{ t (°C), color }]
    readonly property string unitLabel: "°" + unit

    /** The palette, saved: { name, stops }. */
    signal saved(var palette)

    function openFor(i, name, fromStops) {
        index = i;
        stops = fromStops.map(function (s) {
            return {
                t: Number(s.t),
                color: String(s.color)
            };
        });
        nameField.text = name || "";
        check();
        open();
    }
    function setStop(i, key, value) {
        var list = stops.slice(), stop = {
            t: list[i].t,
            color: list[i].color
        };
        stop[key] = value;
        list[i] = stop;
        stops = list;
        check();
    }
    function removeStop(i) {
        var list = stops.slice();
        list.splice(i, 1);
        stops = list;
        check();
    }

    // Colors go through the clipboard as "#rrggbb" text, as in the wind
    // palette editor, by way of a hidden text field (clipboardText below).
    property string clipboardColor: ""
    function readClipboardColor() {
        clipboardText.text = "";
        clipboardText.paste();
        clipboardColor = ConfigUtils.colorFromText(clipboardText.text);
        return clipboardColor;
    }
    function copyColor(i) {
        clipboardText.text = stops[i].color;
        clipboardText.selectAll();
        clipboardText.copy();
    }
    function pasteColor(i) {
        var c = readClipboardColor();
        if (c)
            setStop(i, "color", c);
    }

    // The OK button waits for a free name and temperatures that go up.
    function check() {
        var problem = ConfigUtils.tempPaletteProblem(nameField.text, stops, takenNames);
        errorLabel.text = problem === "name" ? i18n("Give the palette a name.") : problem === "taken" ? i18n("Another palette has this name.") : problem === "order" ? i18n("Each temperature must be higher than the one before.") : problem === "count" ? i18n("A palette has 2 to 12 colors.") : "";
        var ok = standardButton(Dialog.Ok);
        if (ok)
            ok.enabled = problem === "";
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    title: index < 0 ? i18n("New temperature palette") : i18n("Edit temperature palette")
    standardButtons: Dialog.Ok | Dialog.Cancel
    // The rows are made when the editor opens: the popup follows the
    // column's size only when told to.
    contentWidth: editorColumn.implicitWidth
    contentHeight: editorColumn.implicitHeight
    onAccepted: saved({
        name: nameField.text.trim(),
        stops: stops
    })

    ColumnLayout {
        id: editorColumn
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        TextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: i18n("Palette name")
            onTextChanged: tempPaletteDialog.check()
        }
        TextEdit {
            id: clipboardText
            visible: false
        }
        // Up to 12 rows: past a few, they scroll.
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(rowsColumn.implicitHeight, Kirigami.Units.gridUnit * 16)
            contentWidth: rowsColumn.implicitWidth
            contentHeight: rowsColumn.implicitHeight
            // Room for the vertical bar, so no row is cut.
            implicitWidth: rowsColumn.implicitWidth + effectiveScrollBarWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                id: rowsColumn
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: tempPaletteDialog.stops.length
                    delegate: RowLayout {
                        id: stopRow
                        required property int index
                        readonly property var stop: tempPaletteDialog.stops[stopRow.index] || {
                            t: 0,
                            color: "#ffffff"
                        }
                        spacing: Kirigami.Units.smallSpacing

                        // A click opens the color window; right-click, Ctrl+C and
                        // Ctrl+V copy or paste the color.
                        Button {
                            id: stopColorButton
                            implicitWidth: 48
                            Accessible.name: i18n("Temperature color")

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                color: stopRow.stop.color
                            }
                            QtDialogs.ColorDialog {
                                id: stopColorDialog
                                title: i18n("Temperature color")
                                parentWindow: stopColorButton.Window.window
                                onAccepted: tempPaletteDialog.setStop(stopRow.index, "color", ConfigUtils.colorFromText(selectedColor.toString()) || stopRow.stop.color)
                            }
                            onClicked: {
                                stopColorDialog.selectedColor = stopRow.stop.color;
                                stopColorDialog.open();
                            }

                            ToolTip.visible: hovered && !stopColorMenu.visible
                            ToolTip.text: i18n("%1. Right-click to copy or paste it.", stopRow.stop.color)
                            ToolTip.delay: Kirigami.Units.toolTipDelay

                            Keys.onPressed: event => {
                                if (event.matches(StandardKey.Copy)) {
                                    tempPaletteDialog.copyColor(stopRow.index);
                                    event.accepted = true;
                                } else if (event.matches(StandardKey.Paste)) {
                                    tempPaletteDialog.pasteColor(stopRow.index);
                                    event.accepted = true;
                                }
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: stopColorMenu.popup()
                            }
                            Menu {
                                id: stopColorMenu
                                onAboutToShow: tempPaletteDialog.readClipboardColor()
                                MenuItem {
                                    icon.name: "edit-copy"
                                    text: i18n("Copy color")
                                    onTriggered: tempPaletteDialog.copyColor(stopRow.index)
                                }
                                MenuItem {
                                    icon.name: "edit-paste"
                                    text: i18n("Paste color")
                                    enabled: tempPaletteDialog.clipboardColor !== ""
                                    onTriggered: tempPaletteDialog.pasteColor(stopRow.index)
                                }
                            }
                        }
                        Label {
                            text: i18n("at")
                        }
                        TextField {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                            text: String(ConfigUtils.tempToUnit(stopRow.stop.t, tempPaletteDialog.unit))
                            validator: DoubleValidator {
                                decimals: 1
                                notation: DoubleValidator.StandardNotation
                            }
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            onEditingFinished: tempPaletteDialog.setStop(stopRow.index, "t", ConfigUtils.tempFromUnit(Number(text.replace(",", ".")), tempPaletteDialog.unit))
                        }
                        Label {
                            text: tempPaletteDialog.unitLabel
                        }
                        ToolButton {
                            icon.name: "list-remove"
                            text: i18n("Remove")
                            display: AbstractButton.IconOnly
                            enabled: tempPaletteDialog.stops.length > 2
                            onClicked: tempPaletteDialog.removeStop(stopRow.index)
                            ToolTip.visible: hovered
                            ToolTip.text: text
                            ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }
            }
        }
        Button {
            icon.name: "list-add"
            text: i18n("Add a color")
            enabled: tempPaletteDialog.stops.length > 0 && tempPaletteDialog.stops.length < 12
            onClicked: {
                tempPaletteDialog.stops = ConfigUtils.tempAddStop(tempPaletteDialog.stops, tempPaletteDialog.unit);
                tempPaletteDialog.check();
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
