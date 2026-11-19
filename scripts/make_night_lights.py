#!/usr/bin/env python3
# Copyright 2026 rcspam
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# SPDX-License-Identifier: GPL-2.0-or-later

"""Make contents/ui/components/vendor/night-lights.bin.gz, the lights of
the towns the radar map lights on the night side.

Input: NASA Earth Observatory, Black Marble 2016, grey, 3 km
(BlackMarble_2016_3km_gray.jpg, 13500 x 6750, equirectangular from 90N and
180W, public domain), https://earthobservatory.nasa.gov/features/NightLights

Every cell of the picture at KEEP or brighter goes in the file with its
brightness. The page draws the points from them (WidgetEarth
.nightLightsVertices, glue-earth.js): a cell of brightness v gets on
average density * ((v - FLOOR) / (255 - FLOOR)) ** POWER points, density
being the widget's setting; every cell of a town centre, a scatter of
points over the countryside. Cells under KEEP would give almost none.
Packed as WidgetEarth.decodeNightLights() reads them, then gzipped:
  "AWN2", u16 columns and u16 rows of the grid, u32 cell count (little
  endian), u8 FLOOR, u8 POWER * 100, then per cell, row by row and left to
  right: varint rows down from the cell before, varint columns across
  (from the cell before in the same row, from column 0 on a new row), the
  brightness byte.

usage: make_night_lights.py <BlackMarble_2016_3km_gray.jpg> <out.bin.gz>
"""
import gzip
import struct
import sys

import numpy as np
from PIL import Image

FLOOR = 10      # the picture's background noise is below
POWER = 1.2     # higher keeps fewer faint points
KEEP = 15       # fainter cells: some 500 points of 240 000 at density 1


def varint(n, out):
    while n >= 0x80:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)


def pick(grey):
    """Rows, columns and brightness of the cells kept, row by row."""
    rows, cols = np.nonzero(grey >= KEEP)
    return rows, cols, grey[rows, cols]


def pack(width, height, rows, cols, values):
    out = bytearray(b'AWN2')
    out += struct.pack('<HHIBB', width, height, len(rows), FLOOR, round(POWER * 100))
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
    data = gzip.compress(pack(width, height, rows, cols, values), 9, mtime=0)
    with open(sys.argv[2], 'wb') as f:
        f.write(data)
    print('%d cells, %d bytes' % (len(rows), len(data)))


if __name__ == '__main__':
    main()
