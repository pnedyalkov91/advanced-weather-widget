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
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The layers still loading, over the map at the bottom left, see-through
// as the date (the page blurs the map under it): a row a layer, its icon,
// its name (not when compact), a bar and its pictures in. A row comes when
// its layer starts loading; full, its bar turns green, then it fades out.
// The box is there only while a row is. progress: { id: { done, total } }
// (window.animState().progress); map: the WeatherMapView.
Rectangle {
    id: box
    property var map
    property var progress: ({})
    // Too narrow for the names: the icons alone, the name in a tooltip.
    property bool compact: false

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color dimText: Kirigami.Theme.disabledTextColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    readonly property var names: ({
        wind: i18n("Wind"), radar: i18n("Radar"), satellite: i18n("Satellite"),
        precipitation: i18n("Precipitation"), clouds: i18n("Cloud cover"), temperature: i18n("Temperature"),
        pressure: i18n("Pressure"), isobars: i18n("Isobars"), humidity: i18n("Relative humidity"), dewpoint: i18n("Dew point"), airquality: i18n("Air quality")
    })
    // How long a full row stays before it fades out (ms).
    readonly property int holdMs: 700

    ListModel { id: rows }        // { key, done, total, finished }

    function indexOf(id) {
        for (var i = 0; i < rows.count; i++)
            if (rows.get(i).key === id)
                return i;
        return -1;
    }
    // A layer already in when first seen gets no row: nothing to wait for.
    onProgressChanged: {
        var p = progress || {}, i, id;
        for (i = rows.count - 1; i >= 0; i--)
            if (!p[rows.get(i).key])
                rows.remove(i);
        for (id in p) {
            var e = p[id], full = e.done >= e.total;
            i = indexOf(id);
            if (i < 0) {
                if (!full && e.total > 0)
                    rows.append({ key: id, done: e.done, total: e.total, finished: false });
            } else {
                rows.setProperty(i, "done", e.done);
                rows.setProperty(i, "total", e.total);
                rows.setProperty(i, "finished", full);
            }
        }
    }

    visible: opacity > 0
    opacity: rows.count > 0 ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
    width: column.implicitWidth + 20
    height: column.implicitHeight + 14
    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    radius: 8
    clip: true
    color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, box.map.panelOpacity / 100)
    border.width: 1
    border.color: box.tint(0.10)

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 10
        anchors.topMargin: 7
        spacing: 5
        Repeater {
            model: rows
            delegate: RowLayout {
                id: row
                required property string key
                required property int done
                required property int total
                required property bool finished
                // The row's height, down to 0 as it goes.
                property real h: 16
                spacing: 7
                clip: true
                Layout.fillWidth: true
                Layout.preferredHeight: h
                Layout.maximumHeight: h

                // Full: a moment in green, then out.
                Timer {
                    running: row.finished
                    interval: box.holdMs
                    onTriggered: fadeOut.start()
                }
                SequentialAnimation {
                    id: fadeOut
                    ParallelAnimation {
                        NumberAnimation { target: row; property: "opacity"; to: 0; duration: 250 }
                        NumberAnimation { target: row; property: "h"; to: 0; duration: 250; easing.type: Easing.InCubic }
                    }
                    ScriptAction {
                        script: {
                            var i = box.indexOf(row.key);
                            if (i >= 0 && rows.get(i).finished)
                                rows.remove(i);
                        }
                    }
                }
                // Loading again (a zoom) before it went: back as it was.
                onFinishedChanged: if (!finished) {
                    fadeOut.stop();
                    row.opacity = 1;
                    row.h = 16;
                }

                WmIcon {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    layerKey: row.key
                    tint: box.fg
                }
                PlasmaComponents.Label {
                    visible: !box.compact
                    Layout.fillWidth: true
                    text: box.names[row.key] || row.key
                    color: box.fg
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.preferredWidth: box.compact ? 48 : 70
                    Layout.preferredHeight: 3
                    radius: 1.5
                    color: box.tint(0.12)
                    Rectangle {
                        width: parent.width * (row.total > 0 ? Math.min(1, row.done / row.total) : 0)
                        height: parent.height
                        radius: 1.5
                        color: row.finished ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.highlightColor
                        Behavior on width { NumberAnimation { duration: 150 } }
                    }
                }
                PlasmaComponents.Label {
                    Layout.preferredWidth: countMetrics.width
                    horizontalAlignment: Text.AlignRight
                    text: row.done + "/" + row.total
                    color: box.dimText
                    font.pixelSize: 11
                }
                HoverHandler { id: rowHover; enabled: box.compact }
                PlasmaComponents.ToolTip {
                    text: i18n("%1: %2/%3", box.names[row.key] || row.key, row.done, row.total)
                    visible: box.compact && rowHover.hovered
                    delay: Kirigami.Units.toolTipDelay
                }
            }
        }
    }
    // One width for the counts: "999/999".
    TextMetrics { id: countMetrics; font.pixelSize: 11; text: "999/999" }
}
