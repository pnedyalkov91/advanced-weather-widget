#!/usr/bin/env python3
# Copyright 2026 Petar Nedyalkov
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# SPDX-License-Identifier: GPL-2.0-or-later

"""Make contents/ui/components/vendor/places.json.gz, the cities the radar
map names over its color layers (see "City names" in glue-adapter-maplibre.js).

Input: Natural Earth 1:10m populated places GeoJSON (public domain),
https://github.com/nvkelso/natural-earth-vector/tree/master/geojson
  ne_10m_populated_places.geojson

Kept: every national capital and every place of 100 000 or more people
(about 3 100 of 7 300). Output, gzipped JSON:
  { "v": 1, "langs": ["de", "es", ...],
    "c": [[lon, lat, minZoom, "name", ["de name", "", ...]], ...] }
lon and lat in hundredths of a degree (integers), minZoom the MapLibre zoom
from which the place is named (0 for the biggest cities), the names in the
order of "langs" with "" where the same as the default name. Sorted by
importance, the first the first to be named when labels collide.

Natural Earth has no Bulgarian or Czech names: those two languages (and any
place without a name in the user's language) show the default name.

usage: make_places.py <populated_places.geojson> <out.json.gz>
"""
import gzip
import json
import sys

# Languages of the widget that Natural Earth names (NAME_<KEY>), by the code
# the page matches the system locale against (language, or language-script).
LANGS = [("de", "DE"), ("es", "ES"), ("fr", "FR"), ("pt", "PT"), ("ru", "RU"),
         ("uk", "UK"), ("hu", "HU"), ("it", "IT"), ("nl", "NL"), ("pl", "PL"),
         ("sv", "SV"), ("tr", "TR"), ("ja", "JA"), ("ko", "KO"),
         ("zh", "ZH"), ("zh-TW", "ZHT")]

MIN_POP = 100000

# Population from which a place is named at a zoom (MapLibre's, 512 px
# tiles); a national capital comes CAPITAL_BONUS levels earlier. The labels
# also keep clear of each other, so the busiest areas stay readable.
ZOOMS = [(10_000_000, 0.0), (5_000_000, 1.0), (2_000_000, 2.0), (1_000_000, 3.0),
         (500_000, 3.8), (300_000, 4.6), (200_000, 5.4), (0, 6.2)]
CAPITAL_BONUS = 1.5
CAPITAL_FLOOR = 2.0   # but no capital is named before this zoom


def min_zoom(pop, capital):
    z = next(z for p, z in ZOOMS if pop >= p)
    if capital:
        z = min(z, max(CAPITAL_FLOOR, z - CAPITAL_BONUS))
    return round(max(z, 0.0), 1)


def main(src, out):
    with open(src, encoding="utf-8") as f:
        features = json.load(f)["features"]
    rows = []
    for ft in features:
        p = ft["properties"]
        pop = p.get("POP_MAX") or 0
        capital = p.get("ADM0CAP") == 1
        if not capital and pop < MIN_POP:
            continue
        name = (p.get("NAME") or p.get("NAMEASCII") or "").strip()
        if not name:
            continue
        lon, lat = ft["geometry"]["coordinates"][:2]
        names = []
        for _code, key in LANGS:
            n = (p.get("NAME_" + key) or "").strip()
            names.append("" if n == name else n)
        rows.append((pop, capital, [round(lon * 100), round(lat * 100),
                                    min_zoom(pop, capital), name, names]))
    # Most important first: capitals count as a million more people.
    rows.sort(key=lambda r: -(r[0] + (1_000_000 if r[1] else 0)))
    data = {"v": 1, "langs": [c for c, _ in LANGS], "c": [r[2] for r in rows]}
    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with gzip.GzipFile(out, "wb", compresslevel=9, mtime=0) as g:
        g.write(raw)
    print("%d places, %d bytes of JSON, %d gzipped" % (len(rows), len(raw), len(gzip.compress(raw, 9))))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
