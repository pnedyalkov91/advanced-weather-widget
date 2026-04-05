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

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: compactRepresentation

    implicitWidth: Kirigami.Units.iconSizes.medium
    implicitHeight: Kirigami.Units.iconSizes.medium

    TrayCompactView {
        id: compactItemInTray
        anchors.fill: parent
        weatherRoot: root
    }

    // No MouseArea — in the system tray, Plasma handles the click-to-open
    // natively.  Adding our own click handler causes a double-toggle
    // (our toggle + system tray's toggle cancel each other out).
}
