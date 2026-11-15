#!/usr/bin/env python3
# Copyright 2026 rcspam
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# SPDX-License-Identifier: GPL-2.0-or-later

"""Make contents/ui/components/vendor/night-lights.bin, the lights of the
towns the radar map lights on the night side, as points.

Input: NASA Earth Observatory, Black Marble 2016, grey, 3 km
(BlackMarble_2016_3km_gray.jpg, 13500 x 6750, equirectangular from 90N and
180W, public domain), https://earthobservatory.nasa.gov/features/NightLights

Each cell of the picture brighter than FLOOR becomes a point with a chance
that grows with its brightness, ((v - FLOOR) / (255 - FLOOR)) ** POWER,
drawn from a fixed seed: every cell of a town centre, a scatter of points
over the countryside. Packed as WidgetEarth.decodeNightLights()
(glue-earth.js) reads them:
  "AWN1", u16 columns and u16 rows of the grid, u32 point count (little
  endian), then per point, row by row and left to right: varint rows down
  from the point before, varint columns across (from the point before in
  the same row, from column 0 on a new row), the brightness byte.

usage: make_night_lights.py <BlackMarble_2016_3km_gray.jpg> <out.bin>
"""
import struct
import sys

import numpy as np
from PIL import Image

FLOOR = 10      # the picture's background noise is below
POWER = 1.2     # higher keeps fewer faint points
SEED = 20161


def varint(n, out):
    while n >= 0x80:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)


def pick(grey):
    """Rows, columns and brightness of the points kept, row by row."""
    v = grey.astype(np.float32)
    rows, cols = np.nonzero(grey >= FLOOR)
    lit = v[rows, cols]
    chance = ((lit - FLOOR) / (255.0 - FLOOR)) ** POWER
    keep = np.random.default_rng(SEED).random(len(lit)) < chance
    return rows[keep], cols[keep], grey[rows[keep], cols[keep]]


def pack(width, height, rows, cols, values):
    out = bytearray(b'AWN1')
    out += struct.pack('<HHI', width, height, len(rows))
    last_row, last_col = 0, 0
    for r, c, v in zip(rows.tolist(), cols.tolist(), values.tolist()):
        if r != last_row:
            last_col = 0
        varint(r - last_row, out)
        varint(c - last_col, out)
        out.append(v)
        last_row, last_col = r, c
    return bytes(out)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    Image.MAX_IMAGE_PIXELS = None
    grey = np.asarray(Image.open(sys.argv[1]).convert('L'))
    height, width = grey.shape
    rows, cols, values = pick(grey)
    data = pack(width, height, rows, cols, values)
    with open(sys.argv[2], 'wb') as f:
        f.write(data)
    print('%d points, %d bytes' % (len(rows), len(data)))


if __name__ == '__main__':
    main()
