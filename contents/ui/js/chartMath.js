/*
 * Copyright 2026 Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://gnu.org>.
 */

/**
 * chartMath.js - maths shared by HistoryChartGraphs.qml and HistoryChartKQC.qml.
 */
.pragma library

/**
 * Smooth curve through the points (xs[k], ys[k]) (xs ascending): a monotone cubic
 * (Fritsch-Carlson / "PCHIP") sampled `sub` times between every two points.
 *
 * A plain cubic spline overshoots at every peak and valley, so a line through the highest
 * value of a graph left the plot (and was cut off at its edge) - and a line could dip below
 * a real minimum. This curve never leaves the range of the two points it joins, so the
 * line passes through every value and never beyond the highest / lowest one.
 *
 * Returns { x: [...], y: [...] } (the original points are included).
 */
function smooth(xs, ys, sub) {
    var n = xs.length;
    if (n < 3 || sub < 2)
        return {
            x: xs.slice(),
            y: ys.slice()
        };
    var h = [], d = [], m = [];
    var k;
    for (k = 0; k < n - 1; ++k) {
        h.push(xs[k + 1] - xs[k]);
        d.push((ys[k + 1] - ys[k]) / h[k]);
    }
    for (k = 1; k < n - 1; ++k) {
        if (d[k - 1] * d[k] <= 0) {
            m[k] = 0;                       // a peak or a valley: flat there
        } else {
            var w1 = 2 * h[k] + h[k - 1], w2 = h[k] + 2 * h[k - 1];
            m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k]);
        }
    }
    function endSlope(h0, h1, d0, d1) {
        var e = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1);
        if (e * d0 <= 0)
            return 0;
        if (d0 * d1 <= 0 && Math.abs(e) > 3 * Math.abs(d0))
            return 3 * d0;
        return e;
    }
    m[0] = endSlope(h[0], h[1], d[0], d[1]);
    m[n - 1] = endSlope(h[n - 2], h[n - 3], d[n - 2], d[n - 3]);

    var ox = [], oy = [];
    for (k = 0; k < n - 1; ++k) {
        for (var s = 0; s < sub; ++s) {
            var t = s / sub, t2 = t * t, t3 = t2 * t;
            ox.push(xs[k] + t * h[k]);
            oy.push((2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h[k] * m[k] + (-2 * t3 + 3 * t2) * ys[k + 1] + (t3 - t2) * h[k] * m[k + 1]);
        }
    }
    ox.push(xs[n - 1]);
    oy.push(ys[n - 1]);
    return {
        x: ox,
        y: oy
    };
}

/** How many samples per segment for `n` points: about 500 in all, 1-8 per segment. */
function samplesPerSegment(n) {
    return Math.max(1, Math.min(8, Math.floor(500 / Math.max(1, n - 1))));
}
