/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * ConfigLocationPositionSources — encapsulates both QtPositioning PositionSource
 * items so that configLocation.qml can load this file with a Loader only when
 * QtPositioning is actually installed.  If the package is absent, this file is
 * never loaded, the top-level configLocation.qml parses cleanly, and the user
 * sees a helpful install-hint banner instead of a blank page.
 *
 * Signals are emitted instead of calling parent functions directly to avoid
 * cross-document id references.
 */
import QtQuick
import QtPositioning

Item {
    id: psRoot

    // ── External control ───────────────────────────────────────────────────
    // configLocation.qml sets these to activate/deactivate each source.
    property bool geoclue2Active: false
    property bool genericActive: false

    // ── Signals back to configLocation.qml ────────────────────────────────
    signal geoclue2PositionAcquired(real lat, real lon, real alt)
    signal geoclue2Error()
    signal genericPositionAcquired(real lat, real lon, real alt)
    signal genericError()

    // Expose update() calls as functions so configLocation.qml can trigger
    // them without needing direct access to the PositionSource ids.
    function geoclue2DoUpdate() { cfgGeoclue2Source.update(); }
    function genericDoUpdate()  { cfgGenericSource.update();  }

    // ── Tier 1 — GeoClue2 explicitly ──────────────────────────────────────
    PositionSource {
        id: cfgGeoclue2Source
        name: "geoclue2"
        active: psRoot.geoclue2Active
        updateInterval: 300000

        onPositionChanged: {
            var c = position.coordinate;
            if (!c || !c.isValid)
                return;
            psRoot.geoclue2PositionAcquired(c.latitude, c.longitude, c.altitude);
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError)
                psRoot.geoclue2Error();
        }
    }

    // ── Tier 2 — any available Qt Positioning plugin ───────────────────────
    PositionSource {
        id: cfgGenericSource
        active: psRoot.genericActive
        updateInterval: 300000

        onPositionChanged: {
            var c = position.coordinate;
            if (!c || !c.isValid)
                return;
            psRoot.genericPositionAcquired(c.latitude, c.longitude, c.altitude);
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError)
                psRoot.genericError();
        }
    }
}
