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
import QtQuick.Controls as QQC2

// The switches of the Weather Maps' column, a little smaller than the
// desktop's: the style draws the indicator twice as wide as it is high.
QQC2.Switch {
    indicator.implicitHeight: 14
}
