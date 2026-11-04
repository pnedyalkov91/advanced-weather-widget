#!/usr/bin/env python3
"""Make contents/ui/components/vendor/coast-borders.bin, the coasts and the
land borders the radar map draws over its color layers (temperature...).

Input: Natural Earth 1:10m GeoJSON (public domain),
https://github.com/nvkelso/natural-earth-vector/tree/master/geojson
  ne_10m_coastline.geojson, ne_10m_admin_0_boundary_lines_land.geojson

The lines are simplified (Douglas-Peucker, 0.005 degree, about 500 m) and
packed as WidgetEarth.decodeLines() (glue-earth.js) reads them:
  "AWL1", varint line count, then per line: kind byte (0 coast, 1 border),
  varint point count, points as zigzag varint deltas of lon and lat in
  thousandths of a degree.

usage: make_coast_lines.py <coastline.geojson> <boundary_lines_land.geojson> <out.bin>
"""
import json
import sys

TOLERANCE = 0.005


def simplify(pts, tol):
    """Douglas-Peucker, without recursion."""
    n = len(pts)
    if n < 3:
        return pts
    keep = [False] * n
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        length = (dx * dx + dy * dy) ** 0.5
        best, best_i = -1.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            if length:
                d = abs(dy * (px - ax) - dx * (py - ay)) / length
            else:
                d = ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
            if d > best:
                best, best_i = d, i
        if best > tol:
            keep[best_i] = True
            stack += [(a, best_i), (best_i, b)]
    return [p for p, k in zip(pts, keep) if k]


def varint(v, buf):
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            buf.append(b | 0x80)
        else:
            buf.append(b)
            return


def zigzag(v):
    return (v << 1) ^ (v >> 63)


def lines_of(path):
    for feature in json.load(open(path))["features"]:
        g = feature["geometry"]
        if g["type"] == "MultiLineString":
            yield from g["coordinates"]
        else:
            yield g["coordinates"]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    coast, borders, out = sys.argv[1:]
    lines = []
    for kind, path in ((0, coast), (1, borders)):
        for line in lines_of(path):
            pts = [(round(x * 1000), round(y * 1000)) for x, y in simplify(line, TOLERANCE)]
            # Points the rounding made equal add nothing.
            pts = [p for i, p in enumerate(pts) if i == 0 or p != pts[i - 1]]
            if len(pts) >= 2:
                lines.append((kind, pts))
    buf = bytearray(b"AWL1")
    varint(len(lines), buf)
    for kind, pts in lines:
        buf.append(kind)
        varint(len(pts), buf)
        px = py = 0
        for x, y in pts:
            varint(zigzag(x - px), buf)
            varint(zigzag(y - py), buf)
            px, py = x, y
    with open(out, "wb") as f:
        f.write(buf)
    print("%s: %d lines, %d points, %d bytes" % (out, len(lines), sum(len(p) for _, p in lines), len(buf)))


if __name__ == "__main__":
    main()
