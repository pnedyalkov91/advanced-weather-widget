/*
 * Copyright 2026 rcspam
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The time line of the bar: a track, colored up to the handle; under it
// one mark per picture (colored once read, red when it failed) and the
// hours, now in bold; above it the days, each from a line at its midnight,
// and the ranges of the satellite and the radar (the radar's nowcast
// paler). Pressing pauses, dragging shows the picture under the hand.
// What changes seldom (the times, the frames read or failed, now) comes
// apart from what changes while playing (position, fromFile): the marks are
// not worked out again on every picture.
Item {
    id: line
    property var times: []           // the frames' times (ms)
    property var ready: []           // read, by frame
    property var failed: []          // failed, by frame
    property int nowIndex: 0         // the frame of now
    // { lo, hi } or null: the positions the play keeps to (a source's range
    // with a forecast layer, inside the files' steps that cover it).
    property var bounds: null
    property real position: -1       // the position shown (a frame and a fraction), -1 for none
    property bool fromFile: false    // a frame as read from its file, not worked out
    property var radar: null         // the radar's range (window.animState().radar)
    property var satellite: null     // the satellite's
    property bool interpolate: true  // the pictures in between; off, real images only
    // The time of a Date as the widget writes it (its date and time settings).
    property var formatTime: function (d) { return d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat); }
    readonly property int count: times.length
    signal pressedOn()
    signal showIndex(int i)
    signal showPosition(real pos)

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color dimText: Kirigami.Theme.disabledTextColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    implicitHeight: 62
    readonly property real trackY: 28
    readonly property real t0: !count ? 0 : bounds ? timeOfIndex(bounds.lo) : times[0]
    readonly property real t1: !count ? 1 : bounds ? timeOfIndex(bounds.hi) : times[count - 1]
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
        return k + 1 < count ? times[k] + (times[k + 1] - times[k]) * f : times[k];
    }
    function xOfIndex(i) { return count > 1 ? xOfTime(timeOfIndex(i)) : 0; }
    function inView(x) { return x >= -0.5 && x <= width + 0.5; }

    // The hours written under the line: every labelMin minutes counted
    // from now, the fewest leaving labelGap pixels between two (a round
    // number of minutes: 10, 20, 30 min, 1, 2, 3, 6, 12 h, a day...); now
    // always, in bold, the others kept clear of it.
    readonly property real labelGap: 46
    readonly property int labelMin: {
        if (count < 2 || v1 <= v0)
            return 180;
        // Within bounds the frames are 3 h apart, the hours written as for the radar alone.
        var perMin = width / ((v1 - v0) / 60000), stepMin = bounds ? 10 : (times[1] - times[0]) / 60000;
        var steps = [10, 20, 30, 60, 120, 180, 360, 720, 1440, 2880, 10080];
        for (var k = 0; k < steps.length; k++)
            if (steps[k] >= stepMin - 0.5 && steps[k] * perMin >= labelGap)
                return steps[k];
        return steps[steps.length - 1];
    }
    // By time, not by picture: the end of a solo's range falls between two
    // steps (the end of the radar, 22:10 after 22:00) and gets no label.
    function labelShown(i) {
        if (bounds)
            return false;
        if (i === nowIndex)
            return true;
        var min = Math.abs(times[i] - times[nowIndex]) / 60000, r = min % labelMin;
        return (r < 0.5 || labelMin - r < 0.5) && Math.abs(xOfIndex(i) - xOfIndex(nowIndex)) >= labelGap;
    }
    // Within bounds: the hours by time instead, every labelMin minutes
    // counted from now (to 10 minutes), now among them.
    readonly property real boundNow: bounds ? Math.round(Date.now() / 600000) * 600000 : 0
    readonly property var boundLabels: {
        var out = [];
        if (!bounds || count < 2 || t1 <= t0)
            return out;
        var S = labelMin * 60000;
        for (var t = boundNow - Math.floor((boundNow - t0) / S) * S; t <= t1 + 1; t += S)
            out.push(t);
        return out;
    }
    readonly property real handleIndex: area.pressed ? area.dragIndex : position >= 0 ? position : nowIndex

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
    // paler from forecastFrom; its name beside it. Its layer off, it goes
    // away; on, it is lit while the handle stands in its range, greyed
    // outside it. It fades and slides between the three.
    component Band: Item {
        id: band
        property var src: null         // line.radar or line.satellite
        property color color
        property string title
        property bool nameAfter: true
        // The last range known: the band fades out on it once its layer is off.
        property var range: null
        onSrcChanged: if (src && src.start !== null) range = src
        readonly property bool layerOn: !!src && !!src.on
        readonly property bool known: !!range && line.count > 1 && range.end > line.v0 && range.start < line.v1
        readonly property real handleTime: line.position >= 0 ? line.timeOfIndex(line.position) : NaN
        readonly property bool lit: layerOn && known && handleTime >= range.start && handleTime <= range.end
        readonly property real x0: known ? Math.max(0, line.xOfTime(range.start)) : 0
        readonly property real x1: known ? Math.min(line.width, line.xOfTime(range.end)) : 0
        readonly property real xf: known && range.forecastFrom ? Math.max(x0, Math.min(x1, line.xOfTime(range.forecastFrom))) : x1
        visible: known && opacity > 0
        opacity: !layerOn ? 0 : lit ? 1 : 0.55
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: band.layerOn ? 0 : 4
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
        height: 5
        width: line.width
        Rectangle { x: band.x0; width: Math.max(2, band.xf - band.x0); height: 5; radius: 2.5; color: band.color }
        Rectangle { visible: band.x1 > band.xf; x: band.xf; width: band.x1 - band.xf; height: 5; radius: 2.5; color: band.color; opacity: 0.45 }
        PlasmaComponents.Label {
            text: band.title
            color: band.color
            font.bold: true
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
            x: band.nameAfter ? band.x1 + 5 : band.x0 - 6 - width
        }
    }

    // The satellite in the grey of the theme's text, the radar in magenta.
    Band { y: 2; src: line.satellite; color: Qt.tint(line.dimText, "#3080a0d0"); title: i18n("Satellite"); nameAfter: false }
    Band { y: 10; src: line.radar; color: "#c93fc2"; title: i18n("Radar") }

    // The days: a line at each midnight, the day's name after it (the first one at the start).
    PlasmaComponents.Label {
        x: Math.max(0, line.xOfTime(line.t0))
        y: 15
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
            PlasmaComponents.Label {
                x: 4
                y: 15
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

    // Within bounds, the hours by time, each with its mark.
    Repeater {
        model: line.boundLabels
        Item {
            required property var modelData
            readonly property bool isNow: Math.abs(modelData - line.boundNow) < 1000
            x: line.xOfTime(modelData)
            visible: line.inView(x) && (isNow || Math.abs(x - line.xOfTime(line.boundNow)) >= line.labelGap)
            Rectangle {
                x: -0.75
                y: line.trackY + 10
                width: 1.5
                height: 5
                color: line.dimText
            }
            PlasmaComponents.Label {
                x: -width / 2
                y: line.trackY + 17
                text: line.formatTime(new Date(modelData))
                font.pixelSize: 11
                font.bold: isNow
                color: isNow ? line.fg : line.dimText
            }
        }
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
                color: line.failed[index] ? Kirigami.Theme.negativeTextColor
                     : line.ready[index] ? line.accent : line.dimText
            }
            PlasmaComponents.Label {
                visible: line.labelShown(index)
                x: -width / 2
                y: line.trackY + 17
                text: line.formatTime(new Date(line.times[index]))
                font.pixelSize: 11
                font.bold: index === line.nowIndex
                color: index === line.nowIndex ? line.fg : line.dimText
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
        color: line.fromFile ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
        border.color: Kirigami.Theme.backgroundColor
        border.width: 2
    }

    MouseArea {
        id: area
        property real dragIndex: 0
        property real sent: -1
        x: -9
        y: line.trackY - 14
        width: line.width + 18
        height: 34
        enabled: line.count > 0
        cursorShape: Qt.PointingHandCursor
        // The time under the hand, as a position between the frames: to 10
        // minutes everywhere (the pictures worked out between those of the
        // files, the Sun, the Moon and the night move between them too), or
        // on an image of the radar or the satellite, on in its range, when
        // one is nearer. Without the pictures in between: the nearest real
        // one, a frame of the files or an image of those two.
        function _posOfTime(t) {
            var ts = line.times, last = line.count - 1;
            for (var k = 0; k < last; k++)
                if (t < ts[k + 1])
                    return k + Math.max(0, t - ts[k]) / (ts[k + 1] - ts[k]);
            return last;
        }
        function _snap(t) {
            var S = 600000, best = Math.round(t / S) * S;
            if (!line.interpolate) {
                best = line.times[0];
                for (var k = 1; k < line.count; k++)
                    if (Math.abs(line.times[k] - t) < Math.abs(best - t))
                        best = line.times[k];
            }
            [line.radar, line.satellite].forEach(function (s) {
                if (!s || !s.on || s.start === null || !(s.gap > 0) || t < s.start || t >= s.end)
                    return;
                var top = s.last !== null && s.last !== undefined ? s.last : s.end - s.gap;
                var img = Math.min(top, s.start + Math.round((t - s.start) / s.gap) * s.gap);
                if (Math.abs(img - t) < Math.abs(best - t))
                    best = img;
            });
            return best;
        }
        function at(mx) {
            var x = Math.max(0, Math.min(1, (mx - 9) / Math.max(1, line.width)));
            var t = Math.max(line.times[0], Math.min(line.times[line.count - 1], _snap(line.v0 + x * (line.v1 - line.v0))));
            var p = _posOfTime(t);
            if (line.bounds)
                p = Math.max(line.bounds.lo, Math.min(line.bounds.hi, p));
            dragIndex = p;
            if (p === sent)
                return;
            sent = p;
            line.showPosition(p);
        }
        onPressed: function (m) { sent = -1; line.pressedOn(); at(m.x); }
        onPositionChanged: function (m) { if (pressed) at(m.x); }
    }
}
