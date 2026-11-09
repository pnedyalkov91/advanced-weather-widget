import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// How far back or ahead, as an icon with its value under it: the wheel
// over it steps through the choices (one a notch, the choice sent once the
// wheel has been still for settleMs), a click opens their list. choices:
// [value, text] pairs.
Item {
    id: ri
    property var choices: []
    property int current: 0
    property string prefix
    property bool mirror: false        // the icon turned left to right (ahead)
    property string tip
    property int settleMs: 350
    property real _wheel: 0
    property bool _turning: false      // the wheel just moved: the bubble shows the value
    signal picked(var value)
    readonly property alias menu: riMenu
    property string override           // shown instead of the choice (a solo's range)
    property string detail             // added to the bubble (the hours of a source's range)
    // The choice on its way (wheel turned, not sent yet), -1 for none:
    // current itself stays bound to what the view has, so both clocks
    // keep showing the range really chosen.
    property int _pick: -1
    readonly property int shown: _pick >= 0 ? _pick : current
    // A choice named by a word (a source's range) takes no sign.
    function textOf(c) { return typeof c[0] === "string" ? c[1] : prefix + c[1]; }
    readonly property string label: override !== "" ? override : choices.length ? textOf(choices[Math.min(shown, choices.length - 1)]) : ""
    readonly property color fg: Kirigami.Theme.textColor

    implicitWidth: 36
    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: Qt.rgba(ri.fg.r, ri.fg.g, ri.fg.b, riArea.containsMouse || riMenu.visible ? 0.10 : 0)
    }
    // A clock whose rim ends in an arrow: turning back, or ahead (mirror).
    Canvas {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: 2
        width: 22
        height: 22
        transform: Scale { origin.x: 11; xScale: ri.mirror ? -1 : 1 }
        property color stroke: ri.fg
        onStrokeChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"), cx = 11.5, cy = 11.5, r = 7.5;
            c.reset();
            c.strokeStyle = stroke;
            c.fillStyle = stroke;
            c.lineWidth = 1.6;
            c.lineCap = "round";
            // The rim, open at the top left.
            c.beginPath();
            c.arc(cx, cy, r, -Math.PI * 0.62, Math.PI * 1.15, false);
            c.stroke();
            // The arrow at its end, pointing back (counterclockwise).
            var ex = cx + r * Math.cos(Math.PI * 1.15), ey = cy + r * Math.sin(Math.PI * 1.15);
            c.beginPath();
            c.moveTo(ex - 3.6, ey - 1.6);
            c.lineTo(ex + 1.6, ey - 3.4);
            c.lineTo(ex + 0.6, ey + 2.4);
            c.closePath();
            c.fill();
            // The hands.
            c.beginPath();
            c.moveTo(cx, cy - 4.2);
            c.lineTo(cx, cy);
            c.lineTo(cx + 3, cy + 1.8);
            c.stroke();
        }
    }
    QQC2.Label {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 25
        text: ri.label
        color: ri.fg
        font.pixelSize: 11
        font.bold: true
    }
    MouseArea {
        id: riArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: riMenu.visible ? riMenu.close() : riMenu.open()
    }
    // Just the value (a source's range: its name, its hours under it).
    QQC2.ToolTip.text: "<b>" + ri.label + "</b>" + (ri.detail ? "<br>" + ri.detail : "")
    QQC2.ToolTip.visible: riArea.containsMouse && !ri._turning && !riMenu.visible
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    // While the wheel turns: a tip of its own that follows the value (the
    // shared one may already be shown, or timed out, for the hover).
    QQC2.ToolTip {
        visible: ri._turning && !riMenu.visible
        delay: 0
        timeout: -1
        text: "<b>" + ri.label + "</b>"
    }
    Timer { id: turnEnd; interval: 1200; onTriggered: ri._turning = false }

    Timer {
        id: settle
        interval: ri.settleMs
        onTriggered: {
            var v = ri.choices[ri._pick][0];
            ri._pick = -1;
            ri.picked(v);
        }
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
            // A notch is 120; toward you (negative) goes further out.
            ri._wheel -= event.angleDelta.y;
            var notches = Math.trunc(ri._wheel / 120);
            if (notches === 0)
                return;
            ri._wheel -= notches * 120;
            var next = Math.max(0, Math.min(ri.choices.length - 1, ri.shown + notches));
            ri._turning = true;
            turnEnd.restart();
            if (next === ri.shown)
                return;
            ri._pick = next;
            settle.restart();
        }
    }

    QQC2.Menu {
        id: riMenu
        margins: 6
        y: ri.height
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent
        Instantiator {
            model: ri.choices
            delegate: QQC2.MenuItem {
                required property var modelData
                required property int index
                text: ri.textOf(modelData)
                checkable: true
                checked: index === ri.current
                onTriggered: {
                    settle.stop();
                    ri._pick = -1;
                    checked = Qt.binding(function () { return index === ri.current; });
                    ri.picked(modelData[0]);
                }
            }
            onObjectAdded: function (i, o) { riMenu.insertItem(i, o); }
            onObjectRemoved: function (i, o) { riMenu.removeItem(o); }
        }
    }
}
