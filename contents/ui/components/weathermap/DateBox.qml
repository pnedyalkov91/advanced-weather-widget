import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// The time shown, over the map at the top right: the dot green on a
// picture from a forecast file, orange on one worked out; how far from
// now; a round arrow back to now; the arrow that lists the days. The wheel
// over it goes to the start of the next or previous day. A bar along its
// bottom says how far into the range the picture is. map: the WeatherMapView.
Rectangle {
    id: box
    property var map
    readonly property alias daysMenu: daysMenu

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color dimText: Kirigami.Theme.disabledTextColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    // The day and the hour, as the widget writes its hours.
    function dayText(t) { return new Date(t).toLocaleString(Qt.locale(), "ddd d MMM"); }
    function timeText() {
        return box.map.shownTime !== null ? dayText(box.map.shownTime) + ", " + box.map.formatTime(new Date(box.map.shownTime)) : "…";
    }
    function fromNowText() {
        if (box.map.shownTime === null || box.map.shownNow === null)
            return "";
        var h = Math.round((box.map.shownTime - box.map.shownNow) / 3600000);
        return h === 0 ? i18nc("@label the time shown is now", "now") : (h > 0 ? i18n("+%1 h", h) : i18n("%1 h", h));
    }
    // One width for the whole range: that of its longest date, and of its
    // widest distance from now in whole hours.
    FontMetrics { id: timeMetrics; font.pixelSize: 15; font.bold: true }
    FontMetrics { id: fromNowMetrics; font.pixelSize: 13 }
    readonly property real timeWidth: Math.ceil(Math.max.apply(null, [0].concat(box.map.frameTimes.map(function (t) {
        return timeMetrics.advanceWidth(dayText(t) + ", " + box.map.formatTime(new Date(t)));
    })))) + 2
    readonly property real fromNowWidth: Math.ceil(Math.max(fromNowMetrics.advanceWidth(i18nc("@label the time shown is now", "now")),
        fromNowMetrics.advanceWidth(i18n("%1 h", -Math.ceil(box.map.pastH))), fromNowMetrics.advanceWidth(i18n("+%1 h", Math.ceil(box.map.futureH))))) + 2

    visible: box.map.shownTime !== null
    width: dateRow.implicitWidth + 24
    height: 36
    radius: 8
    color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)

    RowLayout {
        id: dateRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        spacing: 8
        Rectangle {
            width: 10
            height: 10
            radius: 5
            color: box.map.animState && box.map.animState.fromFile ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
        }
        QQC2.Label {
            Layout.preferredWidth: box.timeWidth
            text: box.timeText()
            color: box.fg
            font.pixelSize: 15
            font.bold: true
        }
        Rectangle {
            implicitWidth: box.fromNowWidth + 12
            implicitHeight: 22
            radius: 11
            color: box.tint(0.08)
            QQC2.Label {
                anchors.centerIn: parent
                text: box.fromNowText()
                color: box.dimText
                font.pixelSize: 13
            }
        }
        // Back to now: a round arrow turning counterclockwise.
        Item {
            implicitWidth: 22
            implicitHeight: 24
            Rectangle {
                anchors.centerIn: parent
                width: 24
                height: 24
                radius: 12
                color: box.tint(nowArea.containsMouse ? 0.12 : 0)
            }
            Canvas {
                anchors.centerIn: parent
                width: 18
                height: 18
                property color stroke: box.fg
                onStrokeChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d"), cx = 9, cy = 9.5, r = 6, a0 = -Math.PI / 4;
                    c.reset();
                    c.strokeStyle = stroke;
                    c.fillStyle = stroke;
                    c.lineWidth = 1.7;
                    c.lineCap = "round";
                    // Most of a circle, open at the top: from the top right
                    // round by the bottom to the top left.
                    c.beginPath();
                    c.arc(cx, cy, r, a0, Math.PI * 1.45, false);
                    c.stroke();
                    // At the top right end, the head going on counterclockwise (up and left).
                    var px = cx + r * Math.cos(a0), py = cy + r * Math.sin(a0);
                    var tx = Math.sin(a0), ty = -Math.cos(a0);
                    var nx = -ty, ny = tx;
                    c.beginPath();
                    c.moveTo(px + tx * 3.6, py + ty * 3.6);
                    c.lineTo(px + nx * 2.8, py + ny * 2.8);
                    c.lineTo(px - nx * 2.8, py - ny * 2.8);
                    c.closePath();
                    c.fill();
                }
            }
            MouseArea {
                id: nowArea
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: box.map.count > 0
                onClicked: box.map.showIndex(box.map.animState.now)
            }
            QQC2.ToolTip.text: i18n("Back to now")
            QQC2.ToolTip.visible: nowArea.containsMouse
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        Item {
            implicitWidth: 18
            implicitHeight: 24
            Chevron { anchors.centerIn: parent; stroke: box.fg }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: daysMenu.visible ? daysMenu.close() : daysMenu.open()
            }
        }
    }
    // The wheel over the date: the start of the next day (away from you)
    // or of the previous one.
    WheelHandler {
        property real acc: 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
            acc -= event.angleDelta.y;
            var notches = Math.trunc(acc / 120);
            var days = box.map.days;
            if (notches === 0 || !days.length || box.map.shownTime === null)
                return;
            acc -= notches * 120;
            var today = new Date(box.map.shownTime).toDateString(), k = 0;
            for (var i = 0; i < days.length; i++)
                if (new Date(box.map.frameTimes[days[i][0]]).toDateString() === today)
                    k = i;
            var n = Math.max(0, Math.min(days.length - 1, k + (notches > 0 ? 1 : -1)));
            box.map.showIndex(days[n][0]);
        }
    }
    // How far into the range the picture shown is.
    Rectangle {
        readonly property real done: box.map.count > 1 && box.map.animState.index >= 0 ? Math.min(1, box.map.animState.index / (box.map.count - 1)) : 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        x: 10
        width: (parent.width - 20) * done
        height: 3
        radius: 1.5
        color: Kirigami.Theme.highlightColor
    }
    // The days of the range: a click goes to the first picture of that day.
    QQC2.Menu {
        id: daysMenu
        margins: 6
        x: parent.width - width
        y: parent.height + 4
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent
        Instantiator {
            model: box.map.days
            delegate: QQC2.MenuItem {
                required property var modelData
                text: modelData[1]
                checkable: true
                checked: box.map.animState && box.map.animState.time !== null && new Date(box.map.animState.time).toDateString() === new Date(box.map.frameTimes[modelData[0]]).toDateString()
                onTriggered: box.map.showIndex(modelData[0])
            }
            onObjectAdded: function (i, o) { daysMenu.insertItem(i, o); }
            onObjectRemoved: function (i, o) { daysMenu.removeItem(o); }
        }
    }
}
