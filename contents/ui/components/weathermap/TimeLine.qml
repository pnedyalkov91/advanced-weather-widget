import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// The time line of the bar: a track, colored up to the handle; under it
// one mark per picture (colored once read, red when it failed) and the
// hours, now in bold; above it the days, each from a line at its midnight,
// and the ranges of the satellite and the radar (the radar's nowcast
// paler). Pressing pauses, dragging shows the picture under the hand.
// anim: window.animState().
Item {
    id: line
    property var anim: null
    // The time of a Date as the widget writes it (its date and time settings).
    property var formatTime: function (d) { return d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat); }
    readonly property int count: anim ? anim.times.length : 0
    signal pressedOn()
    signal showIndex(int i)

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color dimText: Kirigami.Theme.disabledTextColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    implicitHeight: 62
    readonly property real trackY: 28
    readonly property real t0: count ? anim.times[0] : 0
    readonly property real t1: count ? anim.times[count - 1] : 1
    // The span drawn: it follows t0 and t1, gliding when the range changes,
    // so the line stretches or shrinks instead of jumping. The marks out of
    // it hide while it glides.
    property real v0: 0
    property real v1: 1
    property bool _glide: false
    Behavior on v0 { enabled: line._glide; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    Behavior on v1 { enabled: line._glide; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    function _follow() {
        if (count < 2)
            return;
        v0 = t0;
        v1 = t1;
        _glide = true;
    }
    onT0Changed: _follow()
    onT1Changed: _follow()
    // A new range picked: glide to it at once, before the page, busy
    // reading its pictures, gives its new times.
    function glideTo(a, b) {
        if (count < 2)
            return;
        v0 = a;
        v1 = b;
    }
    function xOfTime(t) { return v1 > v0 ? (t - v0) / (v1 - v0) * width : 0; }
    // The time of a position between two pictures.
    function timeOfIndex(i) {
        if (!count)
            return 0;
        var k = Math.max(0, Math.min(count - 1, Math.floor(i))), f = i - k;
        return k + 1 < count ? anim.times[k] + (anim.times[k + 1] - anim.times[k]) * f : anim.times[k];
    }
    function xOfIndex(i) { return count > 1 ? xOfTime(timeOfIndex(i)) : 0; }
    function inView(x) { return x >= -0.5 && x <= width + 0.5; }

    // The hours written under the line: every labelEvery pictures counted
    // from now, the fewest leaving labelGap pixels between two (a round
    // number of minutes: 10, 20, 30 min, 1, 2, 3, 6, 12 h, a day...); now
    // always, in bold, the others kept clear of it.
    readonly property real labelGap: 46
    readonly property int labelMin: {
        if (count < 2 || v1 <= v0)
            return 180;
        var perMin = width / ((v1 - v0) / 60000), stepMin = (anim.times[1] - anim.times[0]) / 60000;
        var steps = [10, 20, 30, 60, 120, 180, 360, 720, 1440, 2880, 10080];
        for (var k = 0; k < steps.length; k++)
            if (steps[k] >= stepMin - 0.5 && steps[k] * perMin >= labelGap)
                return steps[k];
        return steps[steps.length - 1];
    }
    readonly property int labelEvery: count < 2 ? 2 : Math.max(1, Math.round(labelMin / ((anim.times[1] - anim.times[0]) / 60000)))
    function labelShown(i) {
        if (i === anim.now)
            return true;
        return (i - anim.now) % labelEvery === 0 && Math.abs(xOfIndex(i) - xOfIndex(anim.now)) >= labelGap;
    }
    readonly property real handleIndex: area.pressed ? area.dragIndex
        : anim && anim.index >= 0 ? anim.index : anim ? anim.now : 0

    // The local midnights inside the range.
    readonly property var midnights: {
        var out = [];
        if (count < 2)
            return out;
        var d = new Date(t0);
        d.setHours(24, 0, 0, 0);
        for (; d.getTime() <= t1; d.setDate(d.getDate() + 1))
            out.push(d.getTime());
        return out;
    }

    // A source's range above the line: [start, end) clipped to the line,
    // paler from forecastFrom; its name beside it.
    component Band: Item {
        id: band
        property var src: null         // anim.radar or anim.satellite
        property color color
        property string title
        property bool nameAfter: true
        readonly property bool known: !!src && src.start !== null && line.count > 1 && src.end > line.v0 && src.start < line.v1
        readonly property real x0: known ? Math.max(0, line.xOfTime(src.start)) : 0
        readonly property real x1: known ? Math.min(line.width, line.xOfTime(src.end)) : 0
        readonly property real xf: known && src.forecastFrom ? Math.max(x0, Math.min(x1, line.xOfTime(src.forecastFrom))) : x1
        visible: known
        opacity: src && src.on ? 1 : 0.35
        height: 5
        width: line.width
        Rectangle { x: band.x0; width: Math.max(2, band.xf - band.x0); height: 5; radius: 2.5; color: band.color }
        Rectangle { visible: band.x1 > band.xf; x: band.xf; width: band.x1 - band.xf; height: 5; radius: 2.5; color: band.color; opacity: 0.45 }
        QQC2.Label {
            text: band.title
            color: band.color
            font.bold: true
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
            x: band.nameAfter ? band.x1 + 5 : band.x0 - 6 - width
        }
    }

    // The satellite in the grey of the theme's text, the radar in magenta.
    Band { y: 4; src: line.anim ? line.anim.satellite : null; color: Qt.tint(line.dimText, "#3080a0d0"); title: i18n("Satellite"); nameAfter: false }
    Band { y: 12; src: line.anim ? line.anim.radar : null; color: "#c93fc2"; title: i18n("Radar") }

    // The days: a line at each midnight, the day's name after it (the first one at the start).
    QQC2.Label {
        x: Math.max(0, line.xOfTime(line.t0))
        y: 13
        text: line.count ? new Date(line.t0).toLocaleString(Qt.locale(), "ddd d") : ""
        color: line.dimText
        font.pixelSize: 11
        visible: line.midnights.length === 0 || line.xOfTime(line.midnights[0]) > width + 12
        opacity: line.inView(line.xOfTime(line.t0)) ? 1 : 0
    }
    Repeater {
        model: line.midnights
        Item {
            required property var modelData
            x: line.xOfTime(modelData)
            visible: line.inView(x)
            Rectangle { y: 10; width: 1; height: 50; color: line.tint(0.25) }
            QQC2.Label {
                x: 4
                y: 13
                text: new Date(modelData).toLocaleString(Qt.locale(), "ddd d")
                color: line.dimText
                font.pixelSize: 11
            }
        }
    }

    // The track, colored up to the handle.
    Rectangle {
        y: line.trackY
        width: line.width
        height: 6
        radius: 3
        color: line.tint(0.18)
    }
    Rectangle {
        y: line.trackY
        width: Math.max(0, Math.min(line.width, line.xOfIndex(line.handleIndex)))
        height: 6
        radius: 3
        color: line.accent
    }

    // The marks, then the hours.
    Repeater {
        model: line.count
        Item {
            required property int index
            x: line.xOfIndex(index)
            visible: line.inView(x)
            Rectangle {
                x: -0.75
                y: line.trackY + 10
                width: 1.5
                height: 5
                color: line.anim.failed[index] ? Kirigami.Theme.negativeTextColor
                     : line.anim.ready[index] ? line.accent : line.dimText
            }
            QQC2.Label {
                visible: line.labelShown(index)
                x: -width / 2
                y: line.trackY + 17
                text: line.formatTime(new Date(line.anim.times[index]))
                font.pixelSize: 11
                font.bold: index === line.anim.now
                color: index === line.anim.now ? line.fg : line.dimText
            }
        }
    }

    // The handle: green on a picture as read from its file, orange on one worked out.
    Rectangle {
        x: Math.max(0, Math.min(line.width, line.xOfIndex(line.handleIndex))) - width / 2
        y: line.trackY + 3 - height / 2
        width: 18
        height: 18
        radius: 9
        color: line.anim && line.anim.fromFile ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
        border.color: Kirigami.Theme.backgroundColor
        border.width: 2
    }

    MouseArea {
        id: area
        property real dragIndex: 0
        property int sent: -1
        x: -9
        y: line.trackY - 14
        width: line.width + 18
        height: 34
        enabled: line.count > 0
        cursorShape: Qt.PointingHandCursor
        function at(mx) {
            dragIndex = Math.max(0, Math.min(line.count - 1, (mx - 9) / Math.max(1, line.width) * (line.count - 1)));
            var i = Math.round(dragIndex);
            if (i === sent)
                return;
            sent = i;
            line.showIndex(i);
        }
        onPressed: function (m) { sent = -1; line.pressedOn(); at(m.x); }
        onPositionChanged: function (m) { if (pressed) at(m.x); }
        onReleased: dragIndex = Math.round(dragIndex)
    }
}
