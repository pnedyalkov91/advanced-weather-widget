import QtWebEngine

// The radar map's own storage (QtWebEngine 6.9 and later): the wind kept from
// the open-data files, the map tiles and the like survive a Plasma restart.
// RadarWebEngineViewLibreWXR.qml loads this file through a Loader: on an older
// QtWebEngine the type is missing, the load fails, and the map keeps the
// default profile, whose storage lives in memory only.
WebEngineProfilePrototype {
    storageName: "advanced-weather-widget-map"
}
