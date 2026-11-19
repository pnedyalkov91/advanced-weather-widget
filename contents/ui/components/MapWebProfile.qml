import QtCore
import QtWebEngine

// The radar map's own storage (QtWebEngine 6.9 and later): the wind kept from
// the open-data files, the map tiles and the like survive a Plasma restart.
// WeatherMapView.qml loads this file through a Loader: on an older
// QtWebEngine the type is missing, the load fails, and the map keeps the
// default profile, whose storage lives in memory only.
WebEngineProfilePrototype {
    storageName: "advanced-weather-widget-map"
    // Everything the map keeps (IndexedDB, local storage...) goes next to
    // the HTTP cache, in plasmashell's cache folder. By default it lands in
    // ~/.local/share, where file indexers like Baloo may pick up every tile
    // written. configGeneral.qml's mapCachePath points at this same folder.
    persistentStoragePath: decodeURIComponent(StandardPaths.writableLocation(StandardPaths.CacheLocation).toString().replace(/^file:\/\//, "")) + "/QtWebEngine/advanced-weather-widget-map"
    // The radar's tiles are read ahead into this cache (glue-prefetch.js):
    // about 215 MB for the whole radar range over one area, the ring and
    // the levels in and out counted. 1 GB keeps several areas; the oldest
    // entries, those of images gone from the range, go first.
    // WeatherMapView sets it from weatherMapCacheMB when it loads this file.
    // Never changed afterwards: written on the live profile (Qt 6.10), any
    // new size emptied the cache and broke the open page's requests.
    httpCacheMaximumSize: 1024 * 1024 * 1024
}
