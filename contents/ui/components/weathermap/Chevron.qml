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
import org.kde.kirigami as Kirigami

// The little arrow of a list.
Canvas {
    id: chevron
    property color stroke: Kirigami.Theme.disabledTextColor
    implicitWidth: 10
    implicitHeight: 6
    onStrokeChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        c.strokeStyle = stroke;
        c.lineWidth = 1.5;
        c.lineCap = "round";
        c.lineJoin = "round";
        c.beginPath();
        c.moveTo(1, 1);
        c.lineTo(5, 5);
        c.lineTo(9, 1);
        c.stroke();
    }
}
