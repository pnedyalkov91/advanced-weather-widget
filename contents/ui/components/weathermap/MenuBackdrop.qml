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
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg

// The background of the Weather Map's menus, see-through as the layer
// column and the time bar: what lies under the menu, blurred as much as
// under them, then the theme's frame (or the clean look's tint) at the same
// opacity. Menus mostly stand over the column, which the page cannot blur
// (it is QML): so the menu blurs a copy of the map's stage (map, column,
// bar), cut to its own rectangle, and only while it is shown.
Item {
    id: bd
    property var map                  // WeatherMapView: menuStage, panelBlur, panelOpacity, ownControls
    property var popup                // the popup this is the background of
    property int borders: KSvg.FrameSvg.AllBorders
    readonly property alias margins: frame.margins

    readonly property Item stage: map ? map.menuStage : null
    readonly property bool shown: !!popup && popup.visible && !!stage
    readonly property real blurPx: map ? map.panelBlur : 0
    readonly property real alpha: map ? map.panelOpacity / 100 : 1
    readonly property bool own: map ? map.ownControls : false
    readonly property real radius: borders === KSvg.FrameSvg.AllBorders ? Kirigami.Units.cornerRadius : 0
    // How far past the menu the copy reaches, so that its edges blur what
    // lies beyond them too (cut to the stage).
    readonly property real pad: Math.ceil(blurPx * 2)

    // Where the menu stands over the stage. Read on every frame while it is
    // shown: it slides in, and its parent (the column) folds under it.
    property rect area: Qt.rect(0, 0, 0, 0)
    function place() {
        if (!shown)
            return;
        var p = mapToItem(stage, 0, 0);
        var x0 = Math.max(0, Math.floor(p.x - pad)), y0 = Math.max(0, Math.floor(p.y - pad));
        var x1 = Math.min(stage.width, Math.ceil(p.x + width + pad)), y1 = Math.min(stage.height, Math.ceil(p.y + height + pad));
        var r = Qt.rect(x0, y0, Math.max(0, x1 - x0), Math.max(0, y1 - y0));
        if (r !== area) {
            area = r;
            copy.x = x0 - p.x;
            copy.y = y0 - p.y;
        }
    }
    FrameAnimation {
        running: bd.shown
        onTriggered: bd.place()
    }
    onShownChanged: place()

    Item {
        id: glass
        anchors.fill: parent
        visible: bd.shown
        clip: true
        // Rounded as the frame.
        layer.enabled: bd.shown && bd.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        ShaderEffectSource {
            id: copy
            // Nothing referenced while the menu is closed.
            sourceItem: bd.shown ? bd.stage : null
            sourceRect: bd.area
            width: bd.area.width
            height: bd.area.height
            live: true
            visible: false
        }
        MultiEffect {
            source: copy
            x: copy.x
            y: copy.y
            width: copy.width
            height: copy.height
            // Edges taken as they are, not faded into nothing.
            autoPaddingEnabled: false
            blurEnabled: bd.blurPx > 0
            blur: 1.0
            blurMax: Math.round(bd.blurPx * 2)
            // As the page's saturate(1.3).
            saturation: 0.3
        }
    }
    Rectangle {
        id: roundMask
        width: bd.width
        height: bd.height
        radius: bd.radius
        visible: false
        layer.enabled: true
    }

    // The Plasma look: the theme's frame; the clean look: a plain tint and a thin line.
    KSvg.FrameSvgItem {
        id: frame
        visible: !bd.own
        anchors.fill: parent
        imagePath: "widgets/background"
        enabledBorders: bd.borders
        opacity: bd.alpha
    }
    Rectangle {
        visible: bd.own
        anchors.fill: parent
        radius: bd.radius
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, bd.alpha)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
    }
}
