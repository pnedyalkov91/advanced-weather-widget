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

/**
 * main.qml — Advanced Weather Widget root
 *
 * Responsibilities:
 *  - Declare all weather data properties (the "model")
 *  - Expose helper functions used by sub-views (tempValue, windValue, ...)
 *  - Host WeatherService (API fetching)
 *  - Wire timers and config Connections
 *  - Declare compactRepresentation and fullRepresentation
 *
 * Sub-views receive `weatherRoot: root` so they can read data and call
 * helpers without duplicating logic.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtPositioning
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.notification
import org.kde.kirigami as Kirigami

import "js/weather.js" as W
import "js/moonphase.js" as Moon
import "js/suncalc.js" as SC
import "js/iconResolver.js" as IconResolver
import "js/configUtils.js" as ConfigUtils

PlasmoidItem {
    id: root

    // In the system tray, do NOT set sizing / switch / preferredRepresentation
    // hints — they confuse Plasma's tray popup manager and cause a rapid
    // expanded toggling loop.  -1 lets Plasma use its own defaults.
    readonly property bool _isSimpleMode: (Plasmoid.configuration.widgetLayoutMode || "advanced") === "simple"
    implicitWidth: inTray ? -1 : (_isSimpleMode ? 800 : 540)
    implicitHeight: inTray ? -1 : 550
    switchWidth: inTray ? -1 : 200
    switchHeight: inTray ? -1 : 100

    // In a panel (compact form factor) use the compact representation;
    // on the desktop prefer the full view.
    // In the system tray, leave unset (null) so Plasma's tray container
    // manages compact/full switching on its own.
    preferredRepresentation: inTray ? null
        : (Plasmoid.formFactor === PlasmaCore.Types.Horizontal ||
           Plasmoid.formFactor === PlasmaCore.Types.Vertical)
          ? compactRepresentation : fullRepresentation

    hideOnWindowDeactivate: !Plasmoid.configuration.keepOpen

    // System tray status — keeps the widget visible in the notification area.
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    // Detect system tray — evaluated immediately at property-init time
    // so the compactRepresentation binding resolves BEFORE Plasma
    // instantiates the compact view.  Belt-and-suspenders: containmentType
    // first, pluginName second, formFactor alone third.
    property bool inTray: _detectInTray()

    function _detectInTray() {
        // Method 1: containmentType == 129 (CustomEmbedded) + Horizontal
        try {
            if (Plasmoid.containment.containmentType == 129
                && Plasmoid.formFactor == 2) {
                return true;
            }
        } catch (e) {}
        // Method 2: pluginName contains 'systemtray'
        try {
            var pn = Plasmoid.containment.pluginName || "";
            if (pn.indexOf("systemtray") >= 0) {
                return true;
            }
        } catch (e) {}
        return false;
    }

    // ══════════════════════════════════════════════════════════════════════
    // Weather data model
    // ══════════════════════════════════════════════════════════════════════

    property bool loading: false

    // Single-object weather data. Providers write r.weatherDataStaged = {...} once.
    // Qt.callLater defers the actual weatherData assignment to the next event loop tick
    // so the XHR callback returns immediately — the 17 accessor Changed signals fire
    // when the UI thread is idle instead of blocking the network callback.
    property var weatherDataStaged: null
    property var weatherData: null
    function _applyWeatherData() { weatherData = weatherDataStaged; }
    onWeatherDataStagedChanged: Qt.callLater(_applyWeatherData)

    readonly property real   temperatureC:          weatherData ? weatherData.temperatureC          : NaN
    readonly property real   apparentC:             weatherData ? weatherData.apparentC             : NaN
    readonly property real   windKmh:               weatherData ? weatherData.windKmh               : NaN
    readonly property real   windDirection:         weatherData ? weatherData.windDirection         : NaN
    readonly property real   pressureHpa:           weatherData ? weatherData.pressureHpa           : NaN
    readonly property real   humidityPercent:       weatherData ? weatherData.humidityPercent       : NaN
    readonly property real   visibilityKm:          weatherData ? weatherData.visibilityKm          : NaN
    readonly property real   dewPointC:             weatherData ? weatherData.dewPointC             : NaN
    readonly property real   precipMmh:             weatherData ? weatherData.precipMmh             : NaN
    readonly property real   uvIndex:               weatherData ? weatherData.uvIndex               : NaN
    readonly property real   snowDepthCm:           weatherData ? weatherData.snowDepthCm           : NaN
    readonly property int    weatherCode:           weatherData ? weatherData.weatherCode           : -1
    readonly property int    isDay:                 weatherData ? weatherData.isDay                 : -1
    readonly property int    locationUtcOffsetMins: weatherData ? weatherData.locationUtcOffsetMins : 0
    readonly property string sunriseTimeText:       weatherData ? weatherData.sunriseTimeText       : "--"
    readonly property string sunsetTimeText:        weatherData ? weatherData.sunsetTimeText        : "--"
    readonly property var    dailyData:             weatherData ? weatherData.dailyData             : []
    readonly property real   precipSumMm:           dailyData.length > 0 && !isNaN(dailyData[0].precipMm) ? dailyData[0].precipMm : NaN

    property var aqiDataStaged: null
    property var aqiData: null
    function _applyAqiData() { aqiData = aqiDataStaged; }
    onAqiDataStagedChanged: Qt.callLater(_applyAqiData)

    // Inline accessors — callers subscribe to aqiData directly rather than
    // 8 separate reactive properties each adding their own subscriber chain.
    function airQualityIndex() { return aqiData ? aqiData.index  : NaN; }
    function airQualityLabel()  { return aqiData ? aqiData.label  : ""; }
    function aqiPm10()  { return aqiData ? aqiData.pm10  : NaN; }
    function aqiPm2_5() { return aqiData ? aqiData.pm2_5 : NaN; }
    function aqiCo()    { return aqiData ? aqiData.co    : NaN; }
    function aqiNo2()   { return aqiData ? aqiData.no2   : NaN; }
    function aqiSo2()   { return aqiData ? aqiData.so2   : NaN; }
    function aqiO3()    { return aqiData ? aqiData.o3    : NaN; }
    property var weatherAlerts: []         // [{headline, severity, description}]
    // Per-alert notification state, keyed by alert fingerprint (identity —
    // not location), so dismiss/postpone survive switching locations:
    //   fingerprint -> { dismissed: bool, nextDueMs: number, expiresMs: number }
    // Persisted to Plasmoid.configuration.alertNotificationState.
    property var _alertNotificationState: ({})
    // The fingerprint of the alert currently shown in weatherAlertNotification —
    // lets the Dismiss/Postpone actions know which entry to update.
    property string _activeAlertNotificationFingerprint: ""
    property var _notificationSentKeys: ({})
    // Keys older than this are pruned when persisting, so the stored map can't
    // grow without bound (e.g. time-based rain keys). 3 days covers "today" +
    // a buffer across DST / timezone shifts.
    readonly property int _notificationSentKeyMaxAgeMs: 3 * 24 * 60 * 60 * 1000
    property var _notificationHourlyWindow: []
    property int _notificationHourlyReqId: 0
    property real _notificationHourlyLastFetchMs: 0
    property var pollenDataStaged: []
    property var pollenData: []             // [{key, value}] UPI 0–12 per pollen type — set via _applyPollenData
    function _applyPollenData() { pollenData = pollenDataStaged; }
    onPollenDataStagedChanged: Qt.callLater(_applyPollenData)
    property var spaceWeather: null         // NOAA SWPC data object
    property var spaceWeatherDailyForecast: ({}) // dateStr -> {kp, gScale}, ~3 days ahead
    property var spaceWeatherForecastPeriods: [] // sorted [{startMs, kp, gScale}], 3-hour UTC periods
    property string moonriseTimeText: "--"
    property string moonsetTimeText: "--"
    property var hourlyData: []
    property int panelScrollIndex: 0
    property string updateText: ""

    // Parsed activeLocation — staged so the _locName/_locLat/_locLon/hasSelectedTown
    // cascade fires in the next event loop tick (Qt.callLater) rather than synchronously
    // inside the Plasmoid.configuration write, preventing UI hangs on location switch.
    property var activeLocStaged: ({})
    // Individual typed fields — QML detects per-field changes precisely,
    // avoiding the full var-object dirty cascade.
    property string _activeLocName: ""
    property real   _activeLocLat:  0
    property real   _activeLocLon:  0
    property string _activeLocTz:   ""
    property string _activeLocCC:   ""
    property real   _activeLocAlt:  0

    function _applyActiveLoc() {
        if (_batchingLocation) return;
        var o = activeLocStaged;
        if (!o) return;
        _activeLocName = o.name        || "";
        _activeLocLat  = o.lat         || 0;
        _activeLocLon  = o.lon         || 0;
        _activeLocTz   = o.timezone    || "";
        _activeLocCC   = o.countryCode || "";
        _activeLocAlt  = o.altitude    !== undefined ? o.altitude : 0;
        // No refreshDebounce here — activeLocation (the source for
        // WeatherService._activeLoc) hasn't been written yet at this point.
        // The actual refresh is triggered by:
        //  • Popup path:    _applyPendingLocFields() writes activeLocation
        //                   first, then calls refreshDebounce.restart()
        //  • KCM Apply:     save() writes activeLocation first, then
        //                   KCM syncs individual props → onLatitudeChanged
        //                   → refreshDebounce.restart()
    }

    // Prefer Plasmoid.configuration (reliably updated by both popup _applyPendingLocFields
    // and KCM Apply via cfg_* sync) over the in-memory _activeLoc* snapshots which can
    // lag when activeLocation JSON fails to propagate from the KCM context.
    function _locName() { return Plasmoid.configuration.locationName || _activeLocName || ""; }
    function _locLat()  { return Plasmoid.configuration.latitude  !== 0 ? Plasmoid.configuration.latitude  : _activeLocLat; }
    function _locLon()  { return Plasmoid.configuration.longitude !== 0 ? Plasmoid.configuration.longitude : _activeLocLon; }

    // Imperative rather than reactive — only notifies subscribers when the
    // boolean value actually flips. A reactive binding re-notifies on every
    // _activeLocName change (even true→true), which triggers FullView Layout
    // resize cascades costing ~70ms on every location switch.
    property bool hasSelectedTown: false
    function _updateHasSelectedTown() {
        var name = Plasmoid.configuration.locationName || _activeLocName || "";
        var next;
        if (name.trim().length > 0) {
            next = true;
        } else if (Plasmoid.configuration.autoDetectLocation) {
            var lat = Plasmoid.configuration.latitude !== 0 ? Plasmoid.configuration.latitude : _activeLocLat;
            var lon = Plasmoid.configuration.longitude !== 0 ? Plasmoid.configuration.longitude : _activeLocLon;
            next = (lat !== 0.0 || lon !== 0.0);
        } else {
            next = false;
        }
        if (hasSelectedTown !== next) hasSelectedTown = next;
    }
    on_ActiveLocNameChanged:  _updateHasSelectedTown()
    on_ActiveLocLatChanged:   _updateHasSelectedTown()
    on_ActiveLocLonChanged:   _updateHasSelectedTown()
    onActiveLocStagedChanged: Qt.callLater(_applyActiveLoc)

    // ══════════════════════════════════════════════════════════════════════
    // Representations
    // ══════════════════════════════════════════════════════════════════════

    // toolTipMainText: {
    //     if (!hasSelectedTown) return i18n("No location set");
    //     return Plasmoid.configuration.locationName || i18n("Weather");
    // }
    // toolTipSubText: {
    //     if (!hasSelectedTown || isNaN(temperatureC)) return "";
    //     var parts = [];
    //     parts.push(tempValue(temperatureC));
    //     if (weatherCode >= 0)
    //         parts.push(weatherCodeToText(weatherCode, isNightTime()));
    //     if (!isNaN(humidityPercent))
    //         parts.push(i18n("Humidity") + ": " + Math.round(humidityPercent) + "%");
    //     if (!isNaN(windKmh))
    //         parts.push(i18n("Wind") + ": " + windValue(windKmh));
    //     return parts.join(" | ");
    // }
    // toolTipTextFormat: Text.PlainText

    toolTipMainText: ""  // suppress Plasma's built-in metadata tooltip
    toolTipSubText: ""

    // ── Separate Component declarations for panel vs tray ────────────────
    property Component cr: CompactView {
        weatherRoot: root
    }
    property Component crInTray: CompactRepresentationInTray {}

    compactRepresentation: inTray ? crInTray : cr

    fullRepresentation: FullView {
        weatherRoot: root
        inSystemTray: root.inTray
        // ── Popup size ───────────────────────────────────────────────────
        // In the system tray use preferred sizes only (no large minimums)
        // so Plasma can actually show the popup in the constrained tray area.
        // In the panel, enforce minimums as configured.

        Layout.minimumWidth: {
            if (root.inTray) return 0;
            if (!root.hasSelectedTown) return 280;
            var isSimple = (Plasmoid.configuration.widgetLayoutMode || "advanced") === "simple";
            if ((Plasmoid.configuration.widgetMinWidthMode || "auto") === "manual")
                return Math.max(200, Plasmoid.configuration.widgetMinWidth || (isSimple ? 765 : 800));
            return isSimple ? 765 : 800;
        }
        Layout.minimumHeight: {
            if (root.inTray) return 0;
            if (!root.hasSelectedTown) return 220;
            var isSimple = (Plasmoid.configuration.widgetLayoutMode || "advanced") === "simple";
            if ((Plasmoid.configuration.widgetMinHeightMode || "auto") === "manual")
                return Math.max(200, Plasmoid.configuration.widgetMinHeight || (isSimple ? 550 : 750));
            return isSimple ? 550 : 750;
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Contextual actions — shown in Plasma's system-tray popup header bar
    // (HighPriority → toolbar button next to pin & configure)
    // ══════════════════════════════════════════════════════════════════════

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Detect / change location")
            icon.name: "find-location-symbolic"
            priority: PlasmaCore.Action.HighPriority
            onTriggered: openLocationSettings()
        },
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh-symbolic"
            priority: PlasmaCore.Action.HighPriority
            enabled: !root.loading
            onTriggered: refreshWeather(true)
        }
    ]

    // ══════════════════════════════════════════════════════════════════════
    // Service — all API calls delegated to WeatherService
    // ══════════════════════════════════════════════════════════════════════

    WeatherService {
        id: weatherService
        weatherRoot: root
    }

    // Each notification category gets its own Notification instance.
    // QML's Notification.sendEvent() updates the *same* underlying
    // notification (by id) on repeat calls rather than creating a new one —
    // sharing one instance across categories meant that when several were
    // due in the same evaluator tick, each sendEvent() silently replaced the
    // previous category's still-in-flight notification, so only the last
    // one evaluated (space weather) ever appeared on screen.
    Notification {
        id: todayNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: _bundledAlertIcon("storm-warning")
        flags: Notification.CloseOnTimeout | Notification.SkipGrouping | Notification.DefaultEvent
    }
    Notification {
        id: tomorrowNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: _bundledAlertIcon("storm-warning")
        flags: Notification.CloseOnTimeout | Notification.SkipGrouping | Notification.DefaultEvent
    }
    Notification {
        id: rainNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: _bundledAlertIcon("storm-warning")
        flags: Notification.CloseOnTimeout | Notification.SkipGrouping | Notification.DefaultEvent
    }
    Notification {
        id: uvNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: _bundledAlertIcon("storm-warning")
        flags: Notification.CloseOnTimeout | Notification.SkipGrouping | Notification.DefaultEvent
    }
    Notification {
        id: spaceWeatherNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: _bundledAlertIcon("storm-warning")
        flags: Notification.CloseOnTimeout | Notification.SkipGrouping | Notification.DefaultEvent
    }

    // Dedicated notification for weather alerts. When repeat is enabled it stays
    // open (no auto-timeout) and offers Dismiss / Postpone actions. When repeat is
    // disabled it is shown once as a normal auto-closing notification with no actions.
    Notification {
        id: weatherAlertNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: _bundledAlertIcon("storm-warning")
        flags: root._alertNotificationRepeatEnabled()
            ? (Notification.Persistent | Notification.SkipGrouping | Notification.DefaultEvent)
            : (Notification.CloseOnTimeout | Notification.SkipGrouping | Notification.DefaultEvent)

        actions: root._alertNotificationRepeatEnabled() ? [dismissAlertAction, postponeAlertAction] : []
    }

    NotificationAction {
        id: dismissAlertAction
        label: i18n("Dismiss")
        onActivated: root._dismissAlertNotification()
    }

    NotificationAction {
        id: postponeAlertAction
        // No fixed "%1 min" label: the actual postpone delay is computed
        // per-alert (halfway to its expiry, capped by the repeat-interval
        // setting), so a static minute count here would often be wrong.
        label: i18n("Postpone")
        onActivated: root._postponeAlertNotification()
    }

    // ══════════════════════════════════════════════════════════════════════
    // Auto-detect location — 3-tier fallback
    //
    // Tier 1: GeoClue2 explicitly (PositionSource name: "geoclue2")
    // Tier 2: Any available Qt Positioning plugin (PositionSource, no name)
    // Tier 3: IP-based geolocation (geo.kamero.ai → reallyfreegeoip.org)
    //
    // Active whenever the user has chosen "Automatically detect location".
    // On every position update it:
    //   1. Writes lat/lon/alt directly to Plasmoid.configuration so the
    //      weather fetch and the config dialog both see the fresh values.
    //   2. Triggers a weather refresh (via onLatitudeChanged / onLongitudeChanged).
    //   3. Calls _autoReverseGeocode to update the city name — but ONLY when
    //      a name is already stored. First-time naming (empty locationName) is
    //      handled exclusively by configLocation.qml's confirm dialog so the
    //      user can review the detected place before it is saved.
    // ══════════════════════════════════════════════════════════════════════

    // Which tier is currently active: 0 = idle, 1 = geoclue2, 2 = generic, 3 = IP
    property int _locationTier: 0

    function _applyAutoPosition(lat, lon, alt) {
        // Deactivate sources after a successful fix to avoid duplicate callbacks
        geoclue2Source.active = false;
        genericPositionSource.active = false;
        Plasmoid.configuration.latitude = lat;
        Plasmoid.configuration.longitude = lon;
        if (!isNaN(alt) && alt > 0)
            Plasmoid.configuration.altitude = Math.round(alt);
        // Always reverse-geocode: on first run locationName is empty and
        // would never get populated if we skipped it.
        _autoReverseGeocode(lat, lon);
    }

    function _startAutoDetect() {
        if (!Plasmoid.configuration.autoDetectLocation) return;
        _locationTier = 1;
        geoclue2Source.active = true;
        geoclue2Source.update();
        // Timeout: if GeoClue2 doesn't respond within 8 s, escalate
        _geoclue2Timer.restart();
    }

    function _escalateToGenericSource() {
        geoclue2Source.active = false;
        _locationTier = 2;
        genericPositionSource.active = true;
        genericPositionSource.update();
        _genericSourceTimer.restart();
    }

    function _escalateToIpGeo() {
        genericPositionSource.active = false;
        _locationTier = 3;
        _ipGeolocate();
    }

    Timer {
        id: _geoclue2Timer; interval: 8000; repeat: false
        onTriggered: {
            if (_locationTier === 1) {
                console.log("[Location] GeoClue2 timed out, trying generic PositionSource…");
                _escalateToGenericSource();
            }
        }
    }
    Timer {
        id: _genericSourceTimer; interval: 8000; repeat: false
        onTriggered: {
            if (_locationTier === 2) {
                console.log("[Location] Generic PositionSource timed out, trying IP geolocation…");
                _escalateToIpGeo();
            }
        }
    }
    Timer {
        id: _ipGeoTimer; interval: 10000; repeat: false
        property var _activeReq: null
        onTriggered: {
            if (_locationTier === 3 && _activeReq) {
                console.warn("[Location] Tier 3 IP geolocation timed out");
                _activeReq.abort();
                _activeReq = null;
                _locationTier = 0;
            }
        }
    }
    Timer {
        id: _autoDetectRepeatTimer
        interval: 300000   // re-check every 5 minutes
        repeat: true
        running: Plasmoid.configuration.autoDetectLocation
        onTriggered: _startAutoDetect()
    }

    // Tier 1 — GeoClue2 explicitly
    PositionSource {
        id: geoclue2Source
        name: "geoclue2"
        active: false
        updateInterval: 300000

        onPositionChanged: {
            var c = position.coordinate;
            if (!c || !c.isValid) return;
            _geoclue2Timer.stop();
            _locationTier = 0;
            console.log("[Location] Tier 1 (GeoClue2): position acquired");
            _applyAutoPosition(c.latitude, c.longitude, c.altitude);
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && _locationTier === 1) {
                console.log("[Location] Tier 1 (GeoClue2) error:", sourceError, "— escalating");
                _geoclue2Timer.stop();
                _escalateToGenericSource();
            }
        }
    }

    // Tier 2 — any available Qt Positioning plugin
    PositionSource {
        id: genericPositionSource
        active: false
        updateInterval: 300000

        onPositionChanged: {
            var c = position.coordinate;
            if (!c || !c.isValid) return;
            _genericSourceTimer.stop();
            _locationTier = 0;
            console.log("[Location] Tier 2 (generic PositionSource): position acquired");
            _applyAutoPosition(c.latitude, c.longitude, c.altitude);
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && _locationTier === 2) {
                console.log("[Location] Tier 2 (generic) error:", sourceError, "— escalating to IP");
                _genericSourceTimer.stop();
                _escalateToIpGeo();
            }
        }
    }

    // Tier 3 — IP-based geolocation
    function _ipGeolocate() {
        console.log("[Location] Tier 3: trying geo.kamero.ai…");
        var req = new XMLHttpRequest();
        _ipGeoTimer._activeReq = req;
        _ipGeoTimer.restart();
        req.open("GET", "https://geo.kamero.ai/api/geo");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            if (req.status === 200) {
                try {
                    var data = JSON.parse(req.responseText);
                    var lat = parseFloat(data.latitude);
                    var lon = parseFloat(data.longitude);
                    if (!isNaN(lat) && !isNaN(lon)) {
                        _ipGeoTimer.stop();
                        _ipGeoTimer._activeReq = null;
                        _locationTier = 0;
                        console.log("[Location] Tier 3 (geo.kamero.ai): position acquired");
                        _applyAutoPosition(lat, lon, NaN);
                        return;
                    }
                } catch (e) { console.warn("[Location] geo.kamero.ai parse error:", e); }
            }
            // Fallback to reallyfreegeoip.org
            _ipGeolocateFallback();
        };
        req.send();
    }

    function _ipGeolocateFallback() {
        console.log("[Location] Tier 3 fallback: trying reallyfreegeoip.org…");
        var req = new XMLHttpRequest();
        _ipGeoTimer._activeReq = req;
        _ipGeoTimer.restart();
        req.open("GET", "https://reallyfreegeoip.org/json/");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE) return;
            _ipGeoTimer.stop();
            _ipGeoTimer._activeReq = null;
            if (req.status === 200) {
                try {
                    var data = JSON.parse(req.responseText);
                    var lat = parseFloat(data.latitude);
                    var lon = parseFloat(data.longitude);
                    if (!isNaN(lat) && !isNaN(lon)) {
                        _locationTier = 0;
                        console.log("[Location] Tier 3 (reallyfreegeoip.org): position acquired");
                        _applyAutoPosition(lat, lon, NaN);
                        return;
                    }
                } catch (e) { console.warn("[Location] reallyfreegeoip parse error:", e); }
            }
            _locationTier = 0;
            console.warn("[Location] All 3 tiers failed — no position available");
        };
        req.send();
    }

    /**
     * Reverse-geocodes lat/lon via Nominatim and writes the nearest city
     * name directly to Plasmoid.configuration.locationName.
     * Uses the system locale language with English fallback.
     * Falls back through: city → town → village → hamlet → suburb →
     *                     municipality → county → display_name.
     */
    function _autoReverseGeocode(lat, lon) {
        var req = new XMLHttpRequest();
        var lang = Qt.locale().name.split("_")[0];
        var acceptLang = (lang.length > 0) ? lang + ",en;q=0.8" : "en";
        req.open("GET", "https://nominatim.openstreetmap.org/reverse" + "?format=jsonv2&zoom=10&addressdetails=1" + "&accept-language=" + acceptLang + "&lat=" + lat + "&lon=" + lon);
        req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 (KDE Plasma plasmoid)");
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (req.status !== 200)
                return;
            try {
                var data = JSON.parse(req.responseText);
                if (!data)
                    return;
                var a = (data.address) ? data.address : {};
                var city = a.city || a.town || a.village || a.hamlet || a.suburb || a.municipality || a.county || "";
                var country = a.country || "";
                var name;
                if (city.length > 0 && country.length > 0)
                    name = city + ", " + country;
                else if (city.length > 0)
                    name = city;
                else if (country.length > 0)
                    name = country;
                else
                    name = data.display_name || "";
                if (name.length > 0)
                    Plasmoid.configuration.locationName = name;
                // Capture country code for MeteoAlarm alerts
                var cc = (a.country_code || "").toUpperCase();
                if (cc.length > 0)
                    Plasmoid.configuration.countryCode = cc;
            } catch (e) { console.warn("[Location] reverse geocode parse error:", e); }
        };
        req.send();
    }

    /** Set to true around a batch location-config write to suppress intermediate debounce restarts. */
    property bool _batchingLocation: false

    /** Pending location for deferred individual-field sync. */
    property var _pendingLoc: null

    /** Sync individual config fields from the pending location — called deferred. */
    function _applyPendingLocFields() {
        var loc = _pendingLoc;
        if (!loc) return;
        _pendingLoc = null;
        _batchingLocation = true;
        Plasmoid.configuration.autoDetectLocation = false;
        Plasmoid.configuration.activeLocation = JSON.stringify({
            name:        loc.name        || "",
            lat:         loc.lat         || 0,
            lon:         loc.lon         || 0,
            altitude:    loc.altitude    !== undefined ? loc.altitude : 0,
            timezone:    loc.timezone    || "",
            countryCode: loc.countryCode || ""
        });
        Plasmoid.configuration.locationName  = loc.name        || "";
        Plasmoid.configuration.latitude      = loc.lat         || 0;
        Plasmoid.configuration.longitude     = loc.lon         || 0;
        if (loc.altitude  !== undefined) Plasmoid.configuration.altitude    = loc.altitude;
        if (loc.timezone)               Plasmoid.configuration.timezone     = loc.timezone;
        if (loc.countryCode)            Plasmoid.configuration.countryCode  = loc.countryCode;
        _batchingLocation = false;
        refreshDebounce.restart();
    }

    /** Write all location fields as a single JSON config entry — one signal, one binding cascade. */
    function applyLocation(loc) {
        // Stage both the in-memory update and the KConfig persist — both deferred
        // so the click handler returns in <1ms and the popup closes without a hang.
        activeLocStaged = {
            name:        loc.name        || "",
            lat:         loc.lat         || 0,
            lon:         loc.lon         || 0,
            altitude:    loc.altitude    !== undefined ? loc.altitude : 0,
            timezone:    loc.timezone    || "",
            countryCode: loc.countryCode || ""
        };
        // _applyActiveLoc fires via onActiveLocStagedChanged → Qt.callLater
        // KConfig persist fires 800ms later via _locPersistTimer
        _pendingLoc = loc;
        _locPersistTimer.restart();
    }

    /** Refresh current weather + forecast (called by button, timers, config changes).
     *  force=true (manual refresh button) also bypasses the space weather throttle. */
    function refreshWeather(force) {
        refreshDebounce.stop();
        weatherService.refreshNow(force === true);
    }

    /** Fetch hourly data for a specific date — called by FullView */
    function fetchHourlyForDate(dateStr) {
        weatherService.fetchHourlyForDate(dateStr);
    }

    /** Fetch hourly data without touching shared hourlyData — used by expand-all forecast */
    function fetchHourlyForDateDirect(dateStr, callback) {
        weatherService.fetchHourlyForDateDirect(dateStr, callback);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Value formatters — delegate pure math to weather.js, inject config here
    // ══════════════════════════════════════════════════════════════════════

    // ── Date/time item formatter ─────────────────────────────────────────────
    function _formatItemDateTime(dateFmt, timeFmt) {
        var now = new Date();
        var dateStr = "";
        if (dateFmt === "locale-long")       dateStr = now.toLocaleDateString(Qt.locale(), Locale.LongFormat);
        else if (dateFmt === "locale-short") dateStr = now.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
        else if (dateFmt && dateFmt !== "")  dateStr = Qt.formatDate(now, dateFmt);
        var timeStr = "";
        if (timeFmt === "locale")            timeStr = now.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
        else if (timeFmt && timeFmt !== "") timeStr = Qt.formatTime(now, timeFmt);
        var sep = (dateStr.length > 0 && timeStr.length > 0) ? "  " : "";
        return dateStr + sep + timeStr;
    }

    // Returns the effective temperature unit, respecting "kde" locale mode.
    function _tempUnit() {
        if (Plasmoid.configuration.unitsMode === "kde")
            return Qt.locale().measurementSystem === 1 ? "F" : "C";
        return Plasmoid.configuration.temperatureUnit || "C";
    }
    function tempValue(celsius, context) {
        var unit = _tempUnit();
        var primary = W.formatTemp(celsius, unit, Plasmoid.configuration.roundValues, Plasmoid.configuration.showTempUnit);
        if (!Plasmoid.configuration.dualTempEnabled) return primary;
        var inCtx = (context === "panel"   && Plasmoid.configuration.dualTempInPanel)
                 || (context === "tooltip" && Plasmoid.configuration.dualTempInTooltip)
                 || (context !== "panel" && context !== "tooltip" && Plasmoid.configuration.dualTempInWidget);
        if (!inCtx) return primary;
        var altUnit = (unit === "C") ? "F" : "C";
        var sep = Plasmoid.configuration.dualTempSeparator !== undefined ? Plasmoid.configuration.dualTempSeparator : " / ";
        var secondary = W.formatTemp(celsius, altUnit, Plasmoid.configuration.roundValues, Plasmoid.configuration.showTempUnit);
        return Plasmoid.configuration.dualTempSwapOrder
            ? secondary + sep + primary
            : primary + sep + secondary;
    }

    function _windUnit() {
        if (Plasmoid.configuration.unitsMode === "kde")
            return Qt.locale().measurementSystem === 1 ? "mph" : "kmh";
        return Plasmoid.configuration.windSpeedUnit || "kmh";
    }
    function windValue(kmh) {
        if (isNaN(kmh) || kmh === null || kmh === undefined) return "--";
        var unit = _windUnit();
        return W.formatWindValue(kmh, unit) + " " + i18n(W.windUnitLabel(unit));
    }

    function _pressureUnit() {
        if (Plasmoid.configuration.unitsMode === "kde")
            return Qt.locale().measurementSystem === 1 ? "inHg" : "hPa";
        return Plasmoid.configuration.pressureUnit || "hPa";
    }
    function pressureValue(hpa) {
        if (isNaN(hpa) || hpa === null || hpa === undefined) return "--";
        var unit = _pressureUnit();
        return W.formatPressureValue(hpa, unit) + " " + i18n(W.pressureUnitLabel(unit));
    }

    function _isImperial() {
        if (Plasmoid.configuration.unitsMode === "kde")
            return Qt.locale().measurementSystem === 1;
        return (_tempUnit() === "F");
    }

    function precipValue(mmh) {
        if (isNaN(mmh)) return "--";
        if (_isImperial())
            return (mmh / 25.4).toFixed(2) + " " + i18n("in/h");
        return mmh.toFixed(1) + " " + i18n("mm/h");
    }

    function precipSumText(mm) {
        if (isNaN(mm)) return "--";
        if (_isImperial())
            return (mm / 25.4).toFixed(2) + " " + i18n("in");
        return mm.toFixed(1) + " " + i18n("mm");
    }

    function visibilityValue(km) {
        if (isNaN(km)) return "--";
        if (_isImperial())
            return (km * 0.621371).toFixed(1) + " " + i18n("mi");
        return km.toFixed(1) + " " + i18n("km");
    }

    /** {kp, gScale} for the given dateStr from the ~3-day NOAA Kp forecast, or null. */
    function kpForecastForDate(dateStr) {
        var m = spaceWeatherDailyForecast || {};
        return m[dateStr] || null;
    }

    /** {kp, gScale} for the 3-hour NOAA Kp forecast period covering the given
     *  local dateStr + "HH:MM" sample, or null when outside the forecast range. */
    function kpForecastForHour(dateStr, hhmm) {
        var arr = spaceWeatherForecastPeriods || [];
        var t = _hourSampleEpoch(dateStr, hhmm);
        if (isNaN(t)) return null;
        for (var i = arr.length - 1; i >= 0; i--) {
            var p = arr[i];
            if (p.startMs <= t)
                return (t < p.startMs + 3 * 3600000) ? p : null;
        }
        return null;
    }

    function uvIndexText(uv) {
        if (isNaN(uv)) return "--";
        var v = Math.round(uv * 10) / 10;
        if (v <= 2) return v + " (" + i18n("Low") + ")";
        if (v <= 5) return v + " (" + i18n("Moderate") + ")";
        if (v <= 7) return v + " (" + i18n("High") + ")";
        if (v <= 10) return v + " (" + i18n("Very High") + ")";
        return v + " (" + i18n("Extreme") + ")";
    }

    function airQualityText() {
        var aqi = airQualityIndex();
        if (isNaN(aqi)) return "--";
        // EU AQI band
        var label = "";
        var square = "";
        if (aqi < 25)       { label = i18n("Good");           square = "\u{1F7E2}"; }  // 🟢
        else if (aqi < 50)  { label = i18n("Fair");           square = "\u{1F7E1}"; }  // 🟡
        else if (aqi < 75)  { label = i18n("Moderate");       square = "\u{1F7E0}"; }  // 🟠
        else if (aqi < 100) { label = i18n("Poor");           square = "\u{1F534}"; }  // 🔴
        else if (aqi < 150) { label = i18n("Very Poor");      square = "\u{1F7E3}"; }  // 🟣
        else                { label = i18n("Extremely Poor"); square = "\u{1F7E4}"; }  // 🟤
        // Compute AQHI from EU AQI
        var aqhi;
        if (aqi <= 0)        aqhi = 1;
        else if (aqi <= 25)  aqhi = 1 + (aqi / 25) * 2;
        else if (aqi <= 50)  aqhi = 4 + ((aqi - 25) / 25) * 2;
        else if (aqi <= 75)  aqhi = 7;
        else if (aqi <= 100) aqhi = 8 + ((aqi - 75) / 25);
        else                 aqhi = 10;
        return square + " " + label + " · " + i18n("AQI") + ": " + Math.round(aqi) + " | " + i18n("AQHI") + ": " + Math.round(aqhi);
    }

    /**
     * Returns the dominant pollen display text for the panel / tooltip chip.
     * Format: "<PollenName>: <Label> (<value>)"
     */
    function pollenText() {
        if (!pollenData || pollenData.length === 0) return "--";
        var best = null;
        for (var i = 0; i < pollenData.length; i++) {
            var p = pollenData[i];
            if (isNaN(p.value) || p.value === null) continue;
            if (!best || p.value > best.value) best = p;
        }
        if (!best) return "--";
        var label = "";
        if (best.value < 2.5)      label = i18n("Low");
        else if (best.value < 4.9) label = i18n("Moderate");
        else if (best.value < 7.3) label = i18n("High");
        else                       label = i18n("Very High");
        var name = "";
        switch (best.key) {
            case "alder":   name = i18n("Alder");   break;
            case "birch":   name = i18n("Birch");   break;
            case "grass":   name = i18n("Grass");   break;
            case "mugwort": name = i18n("Mugwort"); break;
            case "olive":   name = i18n("Olive");   break;
            case "ragweed": name = i18n("Ragweed"); break;
            default:        name = best.key;
        }
        return name + ": " + label + " (" + best.value.toFixed(1) + ")";
    }

    /**
     * Returns the space weather display text for the panel / tooltip chip.
     * Collapsed: "Kp 3.3" — or "Kp 5.0 · G1" when storm active.
     */
    function spaceWeatherText() {
        var sw = spaceWeather;
        if (!sw || isNaN(sw.kp)) return "--";
        return "Kp " + sw.kp.toFixed(1) + " · " + (sw.gScale || "G0");
    }

    function snowDepthText(cm) {
        if (isNaN(cm)) return "--";
        if (_isImperial())
            return (cm / 2.54).toFixed(1) + " " + i18n("in");
        return cm.toFixed(1) + " " + i18n("cm");
    }

    /** Returns a numeric priority for an alert color — higher = more severe. */
    function alertColorPriority(color) {
        var c = (color || "").toLowerCase();
        if (c === "red")    return 3;
        if (c === "orange") return 2;
        if (c === "yellow") return 1;
        return 0;
    }

    /**
     * Returns the single highest-priority currently-active alert,
     * or the first alert if none are active yet.
     */
    function primaryAlert() {
        if (!weatherAlerts || weatherAlerts.length === 0) return null;
        var now = new Date();
        var best = null;
        for (var i = 0; i < weatherAlerts.length; i++) {
            var a = weatherAlerts[i];
            var onset   = a.onset   ? new Date(a.onset)   : null;
            var expires = a.expires ? new Date(a.expires) : null;
            var active  = (!onset || onset <= now) && (!expires || expires >= now);
            if (!active) continue;
            if (!best || alertColorPriority(a.color) > alertColorPriority(best.color))
                best = a;
        }
        return best || weatherAlerts[0];
    }

    function alertsText() {
        if (!weatherAlerts || weatherAlerts.length === 0) return i18n("None");
        var p = primaryAlert();
        return p ? (p.displayName || p.headline || i18n("1 Alert")) : i18n("None");
    }

    function alertTypeGlyph(typeNum) {
        switch (typeNum) {
            case 1:  return "\uF050"; // wind
            case 2:  return "\uF076"; // snow/ice
            case 3:  return "\uF01E"; // thunderstorm
            case 4:  return "\uF014"; // fog
            case 5:  return "\uF072"; // high temperature
            case 6:  return "\uF076"; // low temperature
            case 7:  return "\uF0CD"; // coastal event
            case 8:  return "\uF0C7"; // forest fire
            case 9:  return "\uF076"; // avalanche
            case 10: return "\uF019"; // rain
            case 11: return "\uF04E"; // flooding
            case 12: return "\uF019"; // rain-flood
            default: return "\uF0CE"; // generic warning
        }
    }

    /** Canonical MeteoAlarm awareness types exposed in the config UI.
     *  rain-flood (12) is folded into rain (10); unknown (0) is not configurable. */
    function _alertTypeList() {
        return [
            { type: 1,  name: i18n("Wind") },
            { type: 2,  name: i18n("Snow/Ice") },
            { type: 3,  name: i18n("Thunderstorm") },
            { type: 4,  name: i18n("Fog") },
            { type: 5,  name: i18n("High temperature") },
            { type: 6,  name: i18n("Low temperature") },
            { type: 7,  name: i18n("Coastal event") },
            { type: 8,  name: i18n("Forest fire") },
            { type: 9,  name: i18n("Avalanche") },
            { type: 10, name: i18n("Rain") },
            { type: 11, name: i18n("Flood") }
        ];
    }

    /** Normalizes an alert's awareness type to one of the configurable types
     *  (folds rain-flood 12 → rain 10; everything unknown → 10/rain is NOT assumed,
     *  unknown stays 0 and is treated as always-allowed with the global interval). */
    function _alertConfigType(awarenessType) {
        var t = parseInt(awarenessType, 10);
        if (isNaN(t)) return 0;
        if (t === 12) return 10;   // rain-flood → rain
        return t;
    }

    /** Default repeat interval (minutes) for alert types that haven't set
     *  their own — there is no global "Repeat reminder every" setting anymore;
     *  each alert type carries its own interval. */
    readonly property int _defaultAlertRepeatMinutes: 30

    /** Parsed JSON map: awareness type → { enabled, minutes }. */
    property var _alertTypeSettings: ({})
    function _loadAlertTypeSettings() {
        try {
            var o = JSON.parse(Plasmoid.configuration.alertNotificationsTypeSettings || "{}");
            _alertTypeSettings = (o && typeof o === "object") ? o : ({});
        } catch (e) {
            _alertTypeSettings = ({});
        }
    }

    /** Whether the given alert's type is enabled for notifications.
     *  Unknown types (0) and types with no stored setting default to enabled. */
    function _alertTypeEnabled(awarenessType) {
        var t = _alertConfigType(awarenessType);
        if (t === 0) return true;
        var s = _alertTypeSettings[t];
        if (!s || s.enabled === undefined) return true;
        return s.enabled === true;
    }

    /** Per-type repeat interval in minutes, falling back to the default. */
    function _alertTypeRepeatMinutes(awarenessType) {
        var t = _alertConfigType(awarenessType);
        var s = (t !== 0) ? _alertTypeSettings[t] : null;
        var m = (s && s.minutes !== undefined) ? parseInt(s.minutes, 10) : NaN;
        if (isNaN(m)) m = _defaultAlertRepeatMinutes;
        return Math.max(1, Math.min(720, m));
    }

    function _resetAlertNotificationState() {
        _alertNotificationState = ({});
        Plasmoid.configuration.alertNotificationState = "{}";
    }

    /** Marks a once-per-day key as already sent (without actually sending a
     *  notification) — used when a category is toggled back on, so it stays
     *  silent for today/now instead of immediately firing, and only resumes
     *  notifying from its next natural occurrence (e.g. tomorrow). */
    function _markNotificationSentKey(key) {
        _notificationSentKeys[key] = Date.now();
        _persistNotificationSentKeys();
    }

    // Rain notifications are keyed by a dynamically-computed upcoming event
    // timestamp (no stable per-day key to pre-mark), so re-arming uses a
    // one-shot suppression flag instead: skip exactly the first evaluation
    // right after enabling, then resume normal firing.
    property bool _suppressRainNotificationOnce: false
    property bool _suppressSnowNotificationOnce: false

    function _notificationTimeToMinutes(raw, fallback) {
        var s = (raw || "").trim();
        var m = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(s);
        if (!m) return fallback;
        return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
    }

    function _notificationTypeEnabled(type) {
        switch (type) {
        case "alerts": return Plasmoid.configuration.alertNotificationsEnabled === true;
        case "today": return Plasmoid.configuration.notificationTodayEnabled === true;
        case "tomorrow": return Plasmoid.configuration.notificationTomorrowEnabled === true;
        case "rain": return Plasmoid.configuration.notificationRainEnabled === true;
        case "snow": return Plasmoid.configuration.notificationSnowEnabled === true;
        case "uv": return Plasmoid.configuration.notificationUvEnabled === true;
        case "space": return Plasmoid.configuration.notificationSpaceWeatherEnabled === true;
        default: return false;
        }
    }

    /** Allows a once-per-day notification any time at/after timeStr (and before midnight).
     *  The actual once-per-day limit is enforced by _sendNotificationOnce's per-day key,
     *  so a missed evaluator tick around the scheduled time (e.g. plasmashell restart,
     *  suspend) doesn't skip the notification entirely for that day. */
    function _dailyTimeAllows(timeStr, now) {
        var t = _notificationTimeToMinutes(timeStr, 8 * 60);
        var nowM = now.getHours() * 60 + now.getMinutes();
        return nowM >= t;
    }

    function _alertColorAllowed(color) {
        var c = (color || "").toLowerCase();
        // Backward-compatible fallback to old minSeverity if new switches are absent.
        var hasSwitches = (Plasmoid.configuration.alertNotificationsYellowEnabled !== undefined)
            && (Plasmoid.configuration.alertNotificationsOrangeEnabled !== undefined)
            && (Plasmoid.configuration.alertNotificationsRedEnabled !== undefined);
        if (!hasSwitches) {
            var p = alertColorPriority(c);
            var minSeverity = (Plasmoid.configuration.alertNotificationsMinSeverity || "orange").toLowerCase();
            if (minSeverity === "red")
                return p >= 3;
            if (minSeverity === "yellow")
                return p >= 1;
            return p >= 2;
        }
        if (c === "red")
            return Plasmoid.configuration.alertNotificationsRedEnabled === true;
        if (c === "orange")
            return Plasmoid.configuration.alertNotificationsOrangeEnabled === true;
        if (c === "yellow")
            return Plasmoid.configuration.alertNotificationsYellowEnabled === true;
        return true;
    }


    function _isAlertActiveNow(a, now) {
        var onset = a && a.onset ? new Date(a.onset) : null;
        var expires = a && a.expires ? new Date(a.expires) : null;
        return (!onset || onset <= now) && (!expires || expires >= now);
    }

    function _alertFingerprint(a) {
        var name = (a.displayName || a.headline || "").trim().toLowerCase();
        var src = (a.source || "").trim().toLowerCase();
        var onset = a.onset || "";
        var expires = a.expires || "";
        return [name, src, onset, expires].join("|");
    }

    /** Whether the persistent alert notification should repeat (and offer
     *  Dismiss/Postpone). When false, each alert is shown exactly once. */
    function _alertNotificationRepeatEnabled() {
        return Plasmoid.configuration.alertNotificationsRepeatEnabled !== false;
    }

    /** Looks up (or lazily creates) the per-alert state entry for a fingerprint. */
    function _alertEntry(fingerprint) {
        var entry = _alertNotificationState[fingerprint];
        if (!entry) {
            entry = { dismissed: false, nextDueMs: 0, expiresMs: 0 };
            _alertNotificationState[fingerprint] = entry;
        }
        return entry;
    }

    function _dismissAlertNotification() {
        if (!_activeAlertNotificationFingerprint) return;
        var entry = _alertEntry(_activeAlertNotificationFingerprint);
        entry.dismissed = true;
        _persistAlertNotificationState();
    }

    /** Postpone duration: halfway between now and the alert's expiry, capped
     *  by the alert type's own repeat interval as a maximum — so a multi-day
     *  alert doesn't go silent for absurdly long, but a soon-to-expire alert
     *  gets a shorter, more relevant snooze instead of always waiting the
     *  full repeat interval. */
    function _alertPostponeMs(expiresMs, awarenessType) {
        var maxMs = _alertTypeRepeatMinutes(awarenessType) * 60000;
        if (!expiresMs) return maxMs;
        var untilExpiry = expiresMs - Date.now();
        if (untilExpiry <= 0) return maxMs;
        return Math.min(maxMs, Math.max(60000, Math.round(untilExpiry / 2)));
    }

    function _postponeAlertNotification() {
        if (!_activeAlertNotificationFingerprint) return;
        var entry = _alertEntry(_activeAlertNotificationFingerprint);
        entry.dismissed = false;
        entry.nextDueMs = Date.now() + _alertPostponeMs(entry.expiresMs, entry.awarenessType);
        _persistAlertNotificationState();
    }

    function _formatAlertTimestamp(raw) {
        if (!raw) return "";
        var d = new Date(raw);
        if (isNaN(d.getTime())) return "";
        return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " "
            + d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    /** "<onset> – <expires>" / "until <expires>" / "from <onset>" / "". */
    function _alertEffectiveRangeText(a) {
        var onset = _formatAlertTimestamp(a.onset || a.effective);
        var expires = _formatAlertTimestamp(a.expires);
        if (onset && expires) return onset + " – " + expires;
        if (onset) return i18n("from %1", onset);
        if (expires) return i18n("until %1", expires);
        return "";
    }

    /** Notification title: "<Location>, <Region>" (region from the alert area, if known). */
    function _alertNotificationTitle(a, location) {
        var loc = (location || "").trim();
        if (loc.length === 0) loc = i18n("your location");
        var region = (a.area || "").trim();
        return region.length > 0 ? (loc + ", " + region) : loc;
    }

    /** Escapes HTML-significant characters so alert text can't break the
     *  notification body's <b> markup. */
    function _escapeHtml(s) {
        return (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    /** Maps an alert severity color to a colored-circle emoji — KDE notification
     *  bodies strip <font color>, but emoji glyphs keep their own color. */
    function _alertSeverityEmoji(color) {
        var c = (color || "").toLowerCase();
        if (c === "red")    return "🔴"; // 🔴
        if (c === "orange") return "🟠"; // 🟠
        if (c === "yellow") return "🟡"; // 🟡
        return "";
    }

    /** Notification body: severity, headline, effective range, instruction, provider. */
    function _alertNotificationBody(a) {
        var lines = [];
        var emoji = _alertSeverityEmoji(a.color);
        var severity = (a.severity || a.color || "").trim();
        if (severity.length > 0) {
            var marker = emoji.length > 0 ? (emoji + " ") : "";
            lines.push(i18n("<b>Severity:</b> %1%2", marker, _escapeHtml(severity.toUpperCase())));
        }
        lines.push(i18n("<b>Headline:</b> %1", _escapeHtml(a.displayName || a.headline || i18n("Weather alert"))));
        var range = _alertEffectiveRangeText(a);
        if (range.length > 0)
            lines.push(i18n("<b>Effective:</b> %1", range));
        var instruction = (a.instruction || "").trim();
        if (instruction.length > 0)
            lines.push(i18n("<b>Instruction:</b> %1", _escapeHtml(instruction)));
        var provider = (a.senderName || a.source || "").trim();
        if (provider.length > 0)
            lines.push(i18n("<b>Provider:</b> %1", _escapeHtml(provider)));
        return lines.join("\n");
    }

    /** Builds an absolute file path to a bundled flat-color weather icon. */
    function _bundledAlertIcon(stem) {
        return _iconsBaseDir + "flat-color/32/wi-" + stem + ".svg";
    }

    /**
     * Picks an icon for the alert notification matching the alert's weather
     * type. Rain, snow/ice, fog and thunderstorm use the KDE icon theme's
     * native weather icons; the remaining types use the bundled flat-color
     * icon set, falling back to a generic storm-warning icon when unknown.
     */
    function _alertNotificationIconName(a) {
        switch (a.awarenessType) {
        case 2:                                         // snow/ice
        case 9:  return "weather-snow";                 // avalanche
        case 3:  return "weather-storm";                // thunderstorm
        case 4:  return "weather-fog";                  // fog
        case 10:
        case 12: return "weather-showers";              // rain / rain-flood
        }
        var stem = "storm-warning";
        switch (a.awarenessType) {
        case 1:  stem = "strong-wind"; break;          // wind
        case 5:  stem = "hot"; break;                  // high temperature
        case 6:  stem = "snowflake-cold"; break;       // low temperature
        case 7:  stem = "small-craft-advisory"; break; // coastal event
        case 8:  stem = "fire"; break;                 // forest fire
        case 11: stem = "flood"; break;                // flooding
        }
        return _bundledAlertIcon(stem);
    }

    /** Sends (or refreshes) the persistent weather-alert notification for a single alert. */
    function _sendAlertNotification(alert) {
        var location = (_locName() || "").trim();
        _activeAlertNotificationFingerprint = _alertFingerprint(alert);
        weatherAlertNotification.title = _alertNotificationTitle(alert, location);
        weatherAlertNotification.text = _alertNotificationBody(alert);
        weatherAlertNotification.iconName = _alertNotificationIconName(alert);
        if (Plasmoid.configuration.alertNotificationsCriticalEnabled) {
            weatherAlertNotification.urgency = Notification.CriticalUrgency;
        } else {
            var p = alertColorPriority(alert.color);
            weatherAlertNotification.urgency = (p >= 3) ? Notification.HighUrgency
                : (p >= 2) ? Notification.NormalUrgency
                : Notification.LowUrgency;
        }
        weatherAlertNotification.sendEvent();
    }

    /** Picks the dedicated Notification instance for a dedup key's category,
     *  so simultaneously-due notifications don't clobber each other (see the
     *  comment above the Notification declarations). */
    function _notificationObjectForKey(key) {
        if (key.indexOf("today:") === 0) return todayNotification;
        if (key.indexOf("tomorrow:") === 0) return tomorrowNotification;
        if (key.indexOf("rain-") === 0) return rainNotification;
        if (key.indexOf("uv-") === 0) return uvNotification;
        if (key.indexOf("space-") === 0) return spaceWeatherNotification;
        return todayNotification;
    }

    function _sendNotification(title, text, urgency, iconName, notificationObj) {
        var n = notificationObj || todayNotification;
        n.title = title;
        n.text = text;
        n.urgency = urgency;
        n.iconName = iconName || _bundledAlertIcon("storm-warning");
        n.sendEvent();
    }

    function _sendNotificationOnce(key, title, text, urgency, iconName) {
        var notificationObj = _notificationObjectForKey(key);
        if (!key || key.length === 0) {
            _sendNotification(title, text, urgency, iconName, notificationObj);
            return true;
        }
        if (_notificationSentKeys[key])
            return false;
        _notificationSentKeys[key] = Date.now();
        _persistNotificationSentKeys();
        _sendNotification(title, text, urgency, iconName, notificationObj);
        return true;
    }

    /** Load the persisted once-per-day keys so dedup survives a plasmashell restart. */
    function _loadNotificationSentKeys() {
        try {
            var o = JSON.parse(Plasmoid.configuration.notificationSentKeys || "{}");
            _notificationSentKeys = (o && typeof o === "object") ? o : ({});
        } catch (e) {
            _notificationSentKeys = ({});
        }
    }

    /** Load the persisted per-alert dismiss/postpone state so it survives a restart. */
    function _loadAlertNotificationState() {
        try {
            var o = JSON.parse(Plasmoid.configuration.alertNotificationState || "{}");
            _alertNotificationState = (o && typeof o === "object") ? o : ({});
        } catch (e) {
            _alertNotificationState = ({});
        }
    }

    /** Drop entries for alerts that have expired, then write the map back to config. */
    function _persistAlertNotificationState() {
        var now = Date.now();
        var pruned = {};
        for (var k in _alertNotificationState) {
            if (!_alertNotificationState.hasOwnProperty(k)) continue;
            var entry = _alertNotificationState[k];
            if (!entry.expiresMs || entry.expiresMs >= now)
                pruned[k] = entry;
        }
        _alertNotificationState = pruned;
        Plasmoid.configuration.alertNotificationState = JSON.stringify(pruned);
    }

    /** Prune stale keys, then write the map back to config. */
    function _persistNotificationSentKeys() {
        var cutoff = Date.now() - _notificationSentKeyMaxAgeMs;
        var pruned = {};
        for (var k in _notificationSentKeys) {
            if (_notificationSentKeys.hasOwnProperty(k) && _notificationSentKeys[k] >= cutoff)
                pruned[k] = _notificationSentKeys[k];
        }
        _notificationSentKeys = pruned;
        Plasmoid.configuration.notificationSentKeys = JSON.stringify(pruned);
    }

    /**
     * Weather-alert notifications fire whenever a new alert becomes active
     * (no day/time schedule — alerts are checked on every weather refresh,
     * which polls every refreshIntervalMinutes). While an alert remains
     * active, the notification repeats every per-type interval
     * (_alertTypeRepeatMinutes, default 30) until the user dismisses it (no
     * repeat until a new alert appears) or postpones it (repeats again after
     * the postpone interval).
     *
     * State is tracked per alert *identity* (fingerprint: name+source+
     * onset+expires), not per location — so dismissing/postponing an alert
     * sticks even if the user switches to a different location and back
     * (or to a different location under the same regional warning).
     */
    function _processAlertNotifications(now) {
        if (!Plasmoid.configuration.alertNotificationsEnabled) {
            _resetAlertNotificationState();
            return;
        }

        var alerts = weatherAlerts || [];
        if (alerts.length === 0)
            return;

        var nowMs = now.getTime();
        var repeatEnabled = _alertNotificationRepeatEnabled();
        var didChange = false;

        for (var i = 0; i < alerts.length; i++) {
            var a = alerts[i];
            if (!_isAlertActiveNow(a, now))
                continue;
            if (!_alertColorAllowed(a.color))
                continue;
            if (!_alertTypeEnabled(a.awarenessType))
                continue;

            var fp = _alertFingerprint(a);
            var entry = _alertNotificationState[fp];
            var isNewAlert = !entry;
            if (isNewAlert) {
                entry = { dismissed: false, nextDueMs: 0, expiresMs: 0, shownOnce: false, awarenessType: 0 };
                _alertNotificationState[fp] = entry;
            }
            // Keep the expiry fresh so pruning drops it once it truly expires.
            var expMs = a.expires ? new Date(a.expires).getTime() : 0;
            if (expMs !== entry.expiresMs) {
                entry.expiresMs = expMs;
                didChange = true;
            }
            // Track the type so Postpone can use the per-type interval as its cap.
            var awType = parseInt(a.awarenessType, 10) || 0;
            if (awType !== entry.awarenessType) {
                entry.awarenessType = awType;
                didChange = true;
            }

            if (isNewAlert) {
                _sendAlertNotification(a);
                entry.shownOnce = true;
                entry.nextDueMs = nowMs + _alertTypeRepeatMinutes(a.awarenessType) * 60000;
                didChange = true;
                continue;
            }

            // Repeat disabled: alert was already shown once; never re-fire while
            // it stays active (the user only wants a single, button-less alert).
            if (!repeatEnabled)
                continue;

            if (entry.dismissed)
                continue;

            if (nowMs >= entry.nextDueMs) {
                _sendAlertNotification(a);
                entry.nextDueMs = nowMs + _alertTypeRepeatMinutes(a.awarenessType) * 60000;
                didChange = true;
            }
        }

        if (didChange)
            _persistAlertNotificationState();
    }

    /** Lowercases the first character, for mid-sentence use (e.g. "Overcast" -> "overcast"). */
    function _lowercaseFirst(s) {
        if (!s || s.length === 0) return s;
        return s.charAt(0).toLowerCase() + s.slice(1);
    }

    /** "<Day> will be <condition> with a low of <min> and a high of <max>." */
    function _highLowSummary(dayLabel, condition, d) {
        var hi = tempValue(d.maxC);
        var lo = tempValue(d.minC);
        return i18n("%1 will be %2 with a low of %3 and a high of %4.",
            dayLabel, _lowercaseFirst(condition), lo, hi);
    }

    function _processTodayNotification(now) {
        if (!_notificationTypeEnabled("today"))
            return;
        if (!_dailyTimeAllows(Plasmoid.configuration.notificationTodayTime, now))
            return;
        if (!dailyData || dailyData.length === 0)
            return;
        var d = dailyData[0];
        var location = (_locName() || "").trim() || i18n("your location");
        var condition = weatherCodeToText(d.code);
        var msg = _highLowSummary(i18n("Today"), condition, d);
        var title = i18n("%1 - Today", location);
        var icon = W.weatherCodeToIcon(d.code, isNightTime());
        var dateKey = d.dateStr || Qt.formatDate(now, "yyyy-MM-dd");
        _sendNotificationOnce("today:" + dateKey, title, msg, Notification.NormalUrgency, icon);
    }

    function _conditionPriority(code) {
        if (code === 95 || code === 96 || code === 99) return 6; // thunderstorm
        if (code >= 71 && code <= 86) return 5;                  // snow / snow showers
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return 4; // drizzle/rain/showers
        if (code === 45 || code === 48) return 3;                // fog
        if (code === 3) return 2;
        if (code === 2) return 1;
        return 0;
    }

    function _conditionPhrase(code) {
        if (code === 96 || code === 99) return i18n("showers and thunderstorms");
        if (code === 95) return i18n("thunderstorms");
        if (code === 85 || code === 86) return i18n("snow showers");
        if (code >= 71 && code <= 77) return i18n("snow");
        if (code >= 80 && code <= 82) return i18n("showers");
        if (code === 56 || code === 57 || code === 66 || code === 67) return i18n("freezing rain");
        if (code >= 61 && code <= 65) return i18n("rain");
        if (code === 51 || code === 53 || code === 55) return i18n("drizzle");
        if (code === 45 || code === 48) return i18n("fog");
        if (code === 3) return i18n("overcast skies");
        if (code === 2) return i18n("cloudy skies");
        if (code === 1) return i18n("a few clouds");
        return i18n("clear skies");
    }

    /** Picks the most notable part-of-day condition (morning/afternoon/tonight) for dateStr. */
    function _dayConditionSummary(dateStr, fallbackCode) {
        var segs = [
            { label: i18n("Morning"), startH: 6, endH: 12, best: -1, code: 0 },
            { label: i18n("Afternoon"), startH: 12, endH: 18, best: -1, code: 0 },
            { label: i18n("Tonight"), startH: 18, endH: 24, best: -1, code: 0 }
        ];
        var arr = _notificationHourlyWindow || [];
        for (var i = 0; i < arr.length; i++) {
            var p = arr[i];
            if (p.dateStr !== dateStr) continue;
            var hour = new Date(p.timeMs).getHours();
            for (var s = 0; s < segs.length; s++) {
                if (hour >= segs[s].startH && hour < segs[s].endH) {
                    var pr = _conditionPriority(p.code);
                    if (pr > segs[s].best) { segs[s].best = pr; segs[s].code = p.code; }
                }
            }
        }
        var winner = null;
        for (var k = 0; k < segs.length; k++) {
            if (segs[k].best >= 3 && (!winner || segs[k].best > winner.best))
                winner = segs[k];
        }
        if (winner) return i18n("%1 %2", winner.label, _conditionPhrase(winner.code));
        return weatherCodeToText(fallbackCode);
    }

    function _processTomorrowNotification(now) {
        if (!_notificationTypeEnabled("tomorrow"))
            return;
        if (!_dailyTimeAllows(Plasmoid.configuration.notificationTomorrowTime, now))
            return;
        if (!dailyData || dailyData.length < 2)
            return;
        var d = dailyData[1];
        if (!d || !d.dateStr)
            return;
        var location = (_locName() || "").trim() || i18n("your location");
        var condition = _dayConditionSummary(d.dateStr, d.code);
        var msg = _highLowSummary(i18n("Tomorrow"), condition, d);
        var title = i18n("%1 - Tomorrow", location);
        var icon = W.weatherCodeToIcon(d.code, false);
        _sendNotificationOnce("tomorrow:" + d.dateStr, title, msg, Notification.NormalUrgency, icon);
    }

    function _isStormCode(code) {
        return code === 95 || code === 96 || code === 99;
    }

    /** Snow fall / snow grains (71-77) and snow showers (85-86). */
    function _isSnowCode(code) {
        return (code >= 71 && code <= 77) || code === 85 || code === 86;
    }

    function _isRainOrStormCode(code) {
        if (_isStormCode(code)) return true;
        // Drizzle (51-57), rain & freezing rain (61-67), rain showers (80-82).
        // Deliberately excludes the snow band (71-77, 85-86) so snowfall does
        // not trigger a "Rain expected" notification.
        return (code >= 51 && code <= 67) || (code >= 80 && code <= 82);
    }

    function _hourSampleEpoch(dateStr, hhmm) {
        if (!dateStr || !hhmm || hhmm.length < 4)
            return NaN;
        return new Date(dateStr + "T" + hhmm + ":00").getTime();
    }

    /** Finds the next start/end transition for a boolean sample field ("wet" or "snow").
     *  Returns { timeMs, active, code, dateStr, prevCode } or null. */
    function _nextConditionTransition(nowMs, wantStart, field) {
        var arr = _notificationHourlyWindow || [];
        if (arr.length === 0)
            return null;
        var prevActive = false;
        var prevCode = NaN;
        var hadPast = false;
        for (var i = 0; i < arr.length; i++) {
            var p = arr[i];
            if (p.timeMs <= nowMs) {
                prevActive = p[field];
                prevCode = p.code;
                hadPast = true;
            } else {
                break;
            }
        }
        if (!hadPast) {
            prevActive = false;
            prevCode = NaN;
        }
        if (!wantStart && !prevActive)
            return null;
        for (var j = 0; j < arr.length; j++) {
            var c = arr[j];
            if (c.timeMs <= nowMs)
                continue;
            if (wantStart && !prevActive && c[field])
                return { timeMs: c.timeMs, active: c[field], code: c.code, dateStr: c.dateStr, prevCode: prevCode };
            if (!wantStart && prevActive && !c[field])
                return { timeMs: c.timeMs, active: c[field], code: c.code, dateStr: c.dateStr, prevCode: prevCode };
            prevActive = c[field];
            prevCode = c.code;
        }
        return null;
    }

    function _nextRainTransition(nowMs, wantStart) {
        return _nextConditionTransition(nowMs, wantStart, "wet");
    }

    function _nextSnowTransition(nowMs, wantStart) {
        return _nextConditionTransition(nowMs, wantStart, "snow");
    }

    /** "Thunderstorm" for storm codes (95/96/99), otherwise "Rain". */
    function _rainOrThunderLabel(code) {
        return _isStormCode(code) ? i18n("Thunderstorms") : i18n("Rain");
    }

    /** "in the next hours" / "this morning" / "this afternoon" / "tonight" for a target time. */
    function _dayPartLabel(targetMs, nowMs) {
        if ((targetMs - nowMs) <= 3 * 3600000) return i18n("in the next hours");
        var h = new Date(targetMs).getHours();
        if (h >= 6 && h < 12) return i18n("this morning");
        if (h >= 12 && h < 18) return i18n("this afternoon");
        return i18n("tonight");
    }

    /** Rain/snow transitions are only notified when they happen "today": before
     *  tomorrow 06:00, so late-night rain still counts as "tonight" but
     *  _dayPartLabel's same-day wording stays truthful. The hourly window spans
     *  today + tomorrow (the tomorrow-outlook notification needs it), so without
     *  this cutoff a dry today would trigger "Rain expected this afternoon" for
     *  an event more than a day away. */
    function _conditionNotificationCutoffMs(nowMs) {
        var d = new Date(nowMs);
        d.setHours(0, 0, 0, 0);
        return d.getTime() + 30 * 3600000; // today 00:00 + 30h = tomorrow 06:00
    }

    function _processRainNotifications(now) {
        if (!Plasmoid.configuration.notificationRainEnabled)
            return;
        if ((_notificationHourlyWindow || []).length === 0)
            return;
        if (_suppressRainNotificationOnce) {
            _suppressRainNotificationOnce = false;
            return;
        }
        var nowMs = now.getTime();
        var startEv = _nextRainTransition(nowMs, true);
        var endEv = _nextRainTransition(nowMs, false);
        // Events past today are tomorrow-outlook territory, not "expected soon".
        var cutoffMs = _conditionNotificationCutoffMs(nowMs);
        if (startEv && startEv.timeMs >= cutoffMs) startEv = null;
        if (endEv && endEv.timeMs >= cutoffMs) endEv = null;
        if (startEv && (!endEv || startEv.timeMs <= endEv.timeMs)) {
            var label = _rainOrThunderLabel(startEv.code);
            var title = i18n("%1 expected", label);
            var msg = i18n("%1 possible %2.", label, _dayPartLabel(startEv.timeMs, nowMs));
            var icon = W.weatherCodeToIcon(startEv.code, isNightTime());
            _sendNotificationOnce("rain-start:" + startEv.timeMs, title, msg, Notification.NormalUrgency, icon);
        } else if (endEv) {
            var label2 = _rainOrThunderLabel(endEv.prevCode);
            var title2 = i18n("%1 ending", label2);
            var msg2 = i18n("%1 expected to end %2.", label2, _dayPartLabel(endEv.timeMs, nowMs));
            var icon2 = W.weatherCodeToIcon(endEv.prevCode, isNightTime());
            _sendNotificationOnce("rain-end:" + endEv.timeMs, title2, msg2, Notification.NormalUrgency, icon2);
        }
    }

    function _processSnowNotifications(now) {
        if (!Plasmoid.configuration.notificationSnowEnabled)
            return;
        if ((_notificationHourlyWindow || []).length === 0)
            return;
        if (_suppressSnowNotificationOnce) {
            _suppressSnowNotificationOnce = false;
            return;
        }
        var nowMs = now.getTime();
        var startEv = _nextSnowTransition(nowMs, true);
        var endEv = _nextSnowTransition(nowMs, false);
        // Events past today are tomorrow-outlook territory, not "expected soon".
        var cutoffMs = _conditionNotificationCutoffMs(nowMs);
        if (startEv && startEv.timeMs >= cutoffMs) startEv = null;
        if (endEv && endEv.timeMs >= cutoffMs) endEv = null;
        if (startEv && (!endEv || startEv.timeMs <= endEv.timeMs)) {
            var title = i18n("Snow expected");
            var msg = i18n("Snow possible %1.", _dayPartLabel(startEv.timeMs, nowMs));
            var icon = W.weatherCodeToIcon(startEv.code, isNightTime());
            _sendNotificationOnce("snow-start:" + startEv.timeMs, title, msg, Notification.NormalUrgency, icon);
        } else if (endEv) {
            var title2 = i18n("Snow ending");
            var msg2 = i18n("Snow expected to end %1.", _dayPartLabel(endEv.timeMs, nowMs));
            var icon2 = W.weatherCodeToIcon(endEv.prevCode, isNightTime());
            _sendNotificationOnce("snow-end:" + endEv.timeMs, title2, msg2, Notification.NormalUrgency, icon2);
        }
    }

    function _yesterdayDateStr(todayStr) {
        var d = new Date(todayStr + "T00:00:00");
        d.setDate(d.getDate() - 1);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    /** "an increase/decrease/similar ... from yesterday", or "" if no valid prior value. */
    function _trendText(curr, prevVal, prevDateStr, todayStr) {
        if (prevDateStr !== _yesterdayDateStr(todayStr) || isNaN(prevVal) || prevVal < 0) return "";
        if (curr > prevVal + 0.05) return i18n("an increase from yesterday");
        if (curr < prevVal - 0.05) return i18n("a decrease from yesterday");
        return i18n("similar to yesterday");
    }

    function _uvLevelText(uv) {
        if (uv <= 2) return i18n("low");
        if (uv <= 5) return i18n("moderate");
        if (uv <= 7) return i18n("high");
        if (uv <= 10) return i18n("very high");
        return i18n("extreme");
    }

    function _processUvNotification(now) {
        if (!Plasmoid.configuration.notificationUvEnabled)
            return;
        if (!_dailyTimeAllows(Plasmoid.configuration.notificationUvTime, now))
            return;
        if (!dailyData || dailyData.length === 0)
            return;
        var d = dailyData[0];
        var uvMax = (d.uvMax !== undefined && !isNaN(d.uvMax)) ? d.uvMax : uvIndex;
        if (isNaN(uvMax))
            return;
        var todayStr = d.dateStr || Qt.formatDate(now, "yyyy-MM-dd");
        var trend = _trendText(uvMax, Plasmoid.configuration.notificationUvLastValue,
            Plasmoid.configuration.notificationUvLastDate, todayStr);
        var valueText = (Math.round(uvMax * 10) / 10).toString();
        var msg = i18n("UV will be %1 (%2)", _uvLevelText(uvMax), valueText);
        if (trend.length > 0) msg = msg + ", " + trend;
        msg = msg + ".";
        var title = i18n("UV index");
        var fired = _sendNotificationOnce("uv-today:" + todayStr, title,
            msg, Notification.NormalUrgency, "weather-clear");
        if (fired) {
            Plasmoid.configuration.notificationUvLastDate = todayStr;
            Plasmoid.configuration.notificationUvLastValue = uvMax;
        }
    }

    function _gScaleToNumber(g) {
        var s = (g || "G0").toString().toUpperCase().replace("G", "");
        var n = parseInt(s, 10);
        return isNaN(n) ? 0 : n;
    }

    function _kpLevelText(gScale) {
        switch (_gScaleToNumber(gScale || "G0")) {
        case 0: return i18n("quiet");
        case 1: return i18n("minor");
        case 2: return i18n("moderate");
        case 3: return i18n("strong");
        case 4: return i18n("severe");
        default: return i18n("extreme");
        }
    }

    function _processSpaceWeatherNotification(now) {
        if (!Plasmoid.configuration.notificationSpaceWeatherEnabled)
            return;
        if (!_dailyTimeAllows(Plasmoid.configuration.notificationSpaceWeatherTime, now))
            return;
        var sw = spaceWeather;
        var todayStr = Qt.formatDate(now, "yyyy-MM-dd");
        // "Will be" = today's outlook, so prefer the NOAA daily forecast max;
        // the current observed Kp is only a fallback when the forecast feed failed.
        var fc = kpForecastForDate(todayStr);
        var kpVal = (fc && !isNaN(fc.kp)) ? fc.kp : (sw && !isNaN(sw.kp) ? sw.kp : NaN);
        var gVal = (fc && fc.gScale) ? fc.gScale : ((sw && sw.gScale) ? sw.gScale : "G0");
        if (isNaN(kpVal))
            return;
        var trend = _trendText(kpVal, Plasmoid.configuration.notificationSpaceWeatherLastKp,
            Plasmoid.configuration.notificationSpaceWeatherLastDate, todayStr);
        var msg = i18n("Geomagnetic activity will be %1 (Kp %2)", _kpLevelText(gVal), kpVal.toFixed(1));
        if (trend.length > 0) msg = msg + ", " + trend;
        msg = msg + ".";
        var title = i18n("Geomagnetic activity");
        var fired = _sendNotificationOnce("space-today:" + todayStr, title,
            msg, Notification.NormalUrgency, "weather-clear-night");
        if (fired) {
            Plasmoid.configuration.notificationSpaceWeatherLastDate = todayStr;
            Plasmoid.configuration.notificationSpaceWeatherLastKp = kpVal;
        }
    }

    /** Runs fn(now), logging (but not propagating) any exception so one
     *  failing notification type can't block the others. */
    function _safeNotificationStep(name, fn, now) {
        try {
            fn(now);
        } catch (e) {
            console.warn("[weather notifications] " + name + " failed: " + e);
        }
    }

    function _evaluateNotifications() {
        var now = new Date();
        _safeNotificationStep("alerts", _processAlertNotifications, now);
        _safeNotificationStep("today", _processTodayNotification, now);
        _safeNotificationStep("tomorrow", _processTomorrowNotification, now);
        _safeNotificationStep("rain", _processRainNotifications, now);
        _safeNotificationStep("snow", _processSnowNotifications, now);
        _safeNotificationStep("uv", _processUvNotification, now);
        _safeNotificationStep("space", _processSpaceWeatherNotification, now);
    }

    function _refreshNotificationRainWindowIfNeeded(force) {
        if (!hasSelectedTown) {
            _notificationHourlyWindow = [];
            return;
        }
        if (!_notificationTypeEnabled("rain") && !_notificationTypeEnabled("snow") && !_notificationTypeEnabled("tomorrow")) {
            _notificationHourlyWindow = [];
            return;
        }
        var nowMs = Date.now();
        var pollMs = Math.max(5, Plasmoid.configuration.refreshIntervalMinutes || 15) * 60000;
        if (!force && (nowMs - _notificationHourlyLastFetchMs) < pollMs)
            return;
        _notificationHourlyLastFetchMs = nowMs;

        var today = Qt.formatDate(new Date(), "yyyy-MM-dd");
        var tomorrowDate = new Date();
        tomorrowDate.setDate(tomorrowDate.getDate() + 1);
        var tomorrow = Qt.formatDate(tomorrowDate, "yyyy-MM-dd");
        var reqId = ++_notificationHourlyReqId;

        fetchHourlyForDateDirect(today, function(a) {
            if (reqId !== _notificationHourlyReqId) return;
            fetchHourlyForDateDirect(tomorrow, function(b) {
                if (reqId !== _notificationHourlyReqId) return;
                var merged = [];
                function pushSamples(dateStr, rows) {
                    rows = rows || [];
                    for (var i = 0; i < rows.length; i++) {
                        var h = rows[i];
                        var tms = _hourSampleEpoch(dateStr, h.hour || "");
                        if (isNaN(tms)) continue;
                        var code = (h.code !== undefined) ? h.code : NaN;
                        var precip = (h.precipMm !== undefined && h.precipMm !== null) ? h.precipMm : NaN;
                        // Snow also reports precipitation (water equivalent); don't let the
                        // precip fallback flag a snowy hour as rain.
                        var wet = _isRainOrStormCode(code)
                                  || (!_isSnowCode(code) && !isNaN(precip) && precip >= 0.2);
                        var snow = _isSnowCode(code);
                        merged.push({ timeMs: tms, wet: wet, snow: snow, code: code, dateStr: dateStr });
                    }
                }
                pushSamples(today, a || []);
                pushSamples(tomorrow, b || []);
                merged.sort(function(x, y) { return x.timeMs - y.timeMs; });
                _notificationHourlyWindow = merged;
                _evaluateNotifications();
            });
        });
    }

    // ══════════════════════════════════════════════════════════════════════
    // Weather code / condition helpers  (need i18n — must stay in QML)
    // ══════════════════════════════════════════════════════════════════════

    /**
     * Returns the human-readable condition string for a WMO weather code (WW).
     * Uses the full Open-Meteo / WMO WW code table.
     * Pass night=true (or call isNightTime()) to get "Clear night" for code 0.
     * Forecast rows pass no night argument — daytime descriptions are used.
     */
    function weatherCodeToText(code, night) {
        var n = (night === true);
        switch (code) {
        case 0:
            return n ? i18n("Clear night") : i18n("Clear sky");
        case 1:
            return i18n("Mainly clear");
        case 2:
            return i18n("Partly cloudy");
        case 3:
            return i18n("Overcast");
        case 45:
            return i18n("Fog");
        case 48:
            return i18n("Rime fog");
        case 51:
            return i18n("Light drizzle");
        case 53:
            return i18n("Drizzle");
        case 55:
            return i18n("Heavy drizzle");
        case 56:
            return i18n("Light freezing drizzle");
        case 57:
            return i18n("Freezing drizzle");
        case 61:
            return i18n("Light rain");
        case 63:
            return i18n("Rain");
        case 65:
            return i18n("Heavy rain");
        case 66:
            return i18n("Light freezing rain");
        case 67:
            return i18n("Freezing rain");
        case 71:
            return i18n("Light snow");
        case 73:
            return i18n("Snow");
        case 75:
            return i18n("Heavy snow");
        case 77:
            return i18n("Snow grains");
        case 80:
            return i18n("Light showers");
        case 81:
            return i18n("Showers");
        case 82:
            return i18n("Heavy showers");
        case 85:
            return i18n("Light snow showers");
        case 86:
            return i18n("Snow showers");
        case 95:
            return i18n("Thunderstorm");
        case 96:
            return i18n("Thunderstorm with hail");
        case 99:
            return i18n("Heavy thunderstorm with hail");
        default:
            return i18n("Partly cloudy");
        }
    }

    /** Returns the condition icon SVG stem for a weather code + night flag. */
    function _conditionSvgStem(code, night) {
        return IconResolver._conditionSvgStem(code, night);
    }

    // Icons base directory — resolved once so it works in all contexts
    readonly property string _iconsBaseDir: Qt.resolvedUrl("../icons/") + ""

    function getSimpleModeIconSource() {
        var theme = Plasmoid.configuration.panelIconTheme || "wi-font";
        var code  = weatherCode;
        var night = isNightTime();
        var style = Plasmoid.configuration.panelSimpleIconStyle || "symbolic";
        // Custom style: use per-condition custom icons from panelCustomIcons
        if (style === "custom") {
            var customMap = {};
            var raw = Plasmoid.configuration.panelCustomIcons || "";
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        customMap[kv[0].trim()] = kv[1].trim();
                });
            }
            if (customMap["condition-custom"] === "1") {
                var condKey = _resolveConditionKey(code, night);
                if (condKey in customMap && customMap[condKey].length > 0)
                    return customMap[condKey];
            }
            return W.weatherCodeToIcon(code, night);
        }
        if (style === "colorful" || theme === "kde" || theme === "custom")
            return W.weatherCodeToIcon(code, night);
        var iconSz = Plasmoid.configuration.panelIconSize || 22;
        var resolvedTheme = (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light")
            ? "symbolic-light" : theme;
        return IconResolver.svgUrl(IconResolver._conditionSvgStem(code, night), iconSz, _iconsBaseDir, resolvedTheme);
    }

    function getMultilineModeIconSource() {
        var code  = weatherCode;
        var night = isNightTime();
        var style = Plasmoid.configuration.panelMultilineIconStyle || "colorful";
        if (style === "custom") {
            var customMap = {};
            var raw = Plasmoid.configuration.panelCustomIcons || "";
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        customMap[kv[0].trim()] = kv[1].trim();
                });
            }
            if (customMap["condition-custom"] === "1") {
                var condKey = _resolveConditionKey(code, night);
                if (condKey in customMap && customMap[condKey].length > 0)
                    return customMap[condKey];
            }
            return W.weatherCodeToIcon(code, night);
        }
        return W.weatherCodeToIcon(code, night);
    }

    function getSimpleModeIconChar() {
        var code = weatherCode;
        var night = isNightTime();
        if (code === 0)
            return night ? "\uF02E" : "\uF00D";
        if (code <= 2)
            return night ? "\uF086" : "\uF002";
        if (code === 3)
            return "\uF013";
        if (code <= 48)
            return "\uF014";
        if (code <= 65)
            return night ? "\uF028" : "\uF019";
        if (code <= 75)
            return "\uF064";
        if (code <= 99)
            return "\uF01E";
        return "\uF041";
    }

    function isNightTime() {
        // Prefer the API-reported is_day flag — accurate on first load
        // before sunrise/sunset strings have been populated.
        if (isDay >= 0)
            return isDay === 0;
        // Fallback: derive from stored sunrise/sunset times.
        var now = new Date();
        var nowMins = now.getHours() * 60 + now.getMinutes();
        function parseMins(t) {
            if (!t || t === "--")
                return -1;
            var p = t.split(":");
            return (p.length < 2) ? -1 : parseInt(p[0]) * 60 + parseInt(p[1]);
        }
        var rise = parseMins(sunriseTimeText);
        var set_ = parseMins(sunsetTimeText);
        if (rise < 0 || set_ < 0)
            return false;
        return nowMins < rise || nowMins >= set_;
    }

    // ══════════════════════════════════════════════════════════════════════
    // Moon phase helpers  (i18n wrapping for labels done here)
    // ══════════════════════════════════════════════════════════════════════

    function moonPhaseLabel() {
        // Each string is a literal so xgettext can extract all 8 translations.
        // moonPhaseNameKey() returns the English key; we map it here.
        var key = Moon.moonPhaseNameKey(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
        if (key === "New Moon")
            return i18n("New Moon");
        if (key === "Waxing Crescent")
            return i18n("Waxing Crescent");
        if (key === "First Quarter")
            return i18n("First Quarter");
        if (key === "Waxing Gibbous")
            return i18n("Waxing Gibbous");
        if (key === "Full Moon")
            return i18n("Full Moon");
        if (key === "Waning Gibbous")
            return i18n("Waning Gibbous");
        if (key === "Last Quarter")
            return i18n("Last Quarter");
        if (key === "Waning Crescent")
            return i18n("Waning Crescent");
        return key; // fallback: untranslated (should never be reached)
    }

    function moonPhaseGlyph() {
        return Moon.moonPhaseFontIcon(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
    }

    /** Compute moonrise / moonset using suncalc.js and update root properties */
    function _computeMoonTimes() {
        var lat = Plasmoid.configuration.latitude;
        var lon = Plasmoid.configuration.longitude;
        if (isNaN(lat) || isNaN(lon) || (lat === 0 && lon === 0)) {
            moonriseTimeText = "--";
            moonsetTimeText = "--";
            return;
        }
        var t = SC.getMoonTimes(new Date(), lat, lon, locationUtcOffsetMins);
        moonriseTimeText = t.rise || "--";
        moonsetTimeText  = t.set  || "--";
    }

    onWeatherAlertsChanged: _evaluateNotifications()
    onDailyDataChanged: _evaluateNotifications()
    onUvIndexChanged: _evaluateNotifications()
    onSpaceWeatherChanged: _evaluateNotifications()

    onLoadingChanged: {
        if (!loading) {
            weatherService._safetyTimer.stop();
            if (weatherData && !isNaN(weatherData.temperatureC))
                _computeMoonTimes();
            _refreshNotificationRainWindowIfNeeded(true);
            _evaluateNotifications();
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Panel item helpers — used by CompactView to build panel chips
    // ══════════════════════════════════════════════════════════════════════

    function parseSunTimeMins(t) {
        if (!t || t === "--")
            return -1;
        var p = t.split(":");
        return (p.length < 2) ? -1 : parseInt(p[0]) * 60 + parseInt(p[1]);
    }

    /**
     * Re-formats an internal "HH:mm" (24 h) string to the system locale short
     * time format.  Qt.locale().timeFormat(Locale.ShortFormat) returns the
     * platform time format string, e.g. "h:mm AP" (12 h) or "HH:mm" (24 h).
     * Using Qt.formatTime on a synthetic Date applies that format correctly
     * without any manual AM/PM logic.
     */
    function formatTimeForDisplay(hhmmStr) {
        if (!hhmmStr || hhmmStr === "--")
            return "--";
        var parts = hhmmStr.split(":");
        if (parts.length < 2)
            return hhmmStr;
        var h = parseInt(parts[0], 10);
        var m = parseInt(parts[1], 10);
        if (isNaN(h) || isNaN(m))
            return hhmmStr;
        var d = new Date();
        d.setHours(h, m, 0, 0);
        return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function parsePanelItemIcons() {
        return ConfigUtils.parseBoolMap(Plasmoid.configuration.panelItemIcons || "");
    }

    /** Returns the wi-font glyph (or Kirigami icon name) for a panel chip */
    function panelItemGlyph(tok) {
        if (tok === "temperature")
            return "\uF055";        // wi-thermometer
        if (tok === "feelslike")
            return "\uF055";        // wi-thermometer
        if (tok === "humidity")
            return "\uF07A";        // wi-humidity
        if (tok === "pressure")
            return "\uF079";        // wi-barometer
        if (tok === "location")
            return "\uF0B1";       // wi-direction (F0B1)
        if (tok === "moonphase") {
            var mm = Plasmoid.configuration.panelMoonPhaseMode || "full";
            if (mm === "moonrise") return "\uF0C9";
            if (mm === "moonset") return "\uF0CA";
            if (mm === "upcoming-times") return _moonUpcoming() === "rise" ? "\uF0C9" : "\uF0CA";
            return moonPhaseGlyph();
        }
        if (tok === "moonphase-moonrise")
            return "\uF0C9";
        if (tok === "moonphase-moonset")
            return "\uF0CA";
        if (tok === "wind")
            return W.windDirectionGlyph(windDirection);
        if (tok === "condition") {
            var n = isNightTime(), c = weatherCode;
            if (c === 0)
                return n ? "\uF02E" : "\uF00D";
            if (c <= 2)
                return n ? "\uF086" : "\uF002";
            if (c === 3)
                return "\uF013";
            if (c === 45 || c === 48)
                return "\uF014";
            if (c <= 65)
                return n ? "\uF028" : "\uF019";
            if (c <= 75)
                return "\uF064";
            if (c <= 99)
                return "\uF01E";
            return "\uF041";
        }
        if (tok === "suntimes") {
            var mode = Plasmoid.configuration.panelSunTimesMode || "upcoming";
            if (mode === "sunset")
                return "\uF052";
            var nowMins = (new Date()).getHours() * 60 + (new Date()).getMinutes();
            var riseMins = parseSunTimeMins(sunriseTimeText);
            var setMins = parseSunTimeMins(sunsetTimeText);
            if (mode === "upcoming") {
                if (riseMins >= 0 && nowMins < riseMins)
                    return "\uF051";
                if (setMins >= 0 && nowMins < setMins)
                    return "\uF052";
            }
            return "\uF051";
        }
        if (tok === "preciprate")
            return "\uF04E";        // wi-sprinkle (rain drop)
        if (tok === "precipsum")
            return "\uF07C";        
        if (tok === "uvindex")
            return "\uF072";        // wi-hot
        if (tok === "airquality")
            return "\uF074";        // wi-smog
        if (tok === "pollen")
            return "\uF082";        // wi-sandstorm
        if (tok === "spaceweather")
            return "\uF06E";        // wi-solar-eclipse
        if (tok === "alerts") {
            var pa = primaryAlert();
            if (pa) return alertTypeGlyph(pa.awarenessType || 0);
            return "\uF0CE";        // wi-gale-warning (flag)
        }
        if (tok === "snowcover")
            return "\uF076";        // wi-snowflake-cold
        if (tok === "datetime")
            return "\uF08C";        // wi-time-3
        return "";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // panelItemIconInfo(tok) — returns { type, source } for the active icon theme
    //
    //   type: "wi"       → wi-font glyph char (Text element)
    //         "kirigami" → Kirigami icon name
    //         "svg"      → resolved URL of an SVG in contents/icons/<theme>/
    //         "kde"      → KDE system icon name (Kirigami.Icon, may be missing)
    //
    // SVG file name convention (files must exist under contents/icons/<theme>/):
    //   thermometer.svg  humidity.svg  barometer.svg  wind.svg
    //   sunrise.svg  sunset.svg  location.svg
    //   condition-<code>.svg  (e.g. condition-0.svg for clear sky)
    //   moon-<phase>.svg  (e.g. wi-moon-alt-full.svg)
    // ─────────────────────────────────────────────────────────────────────────
    function panelItemIconInfo(tok) {
        var theme = Plasmoid.configuration.panelIconTheme || "wi-font";

        // ── Font icons (default) ──────────────────────────────────────────────
        if (theme === "wi-font") {
            var g = panelItemGlyph(tok);
            return { type: "wi", source: g, svgFallback: "", isMask: false };
        }

        // ── Custom icon theme — user picks each icon individually ────────────
        if (theme === "custom") {
            var customMap = {};
            var raw = Plasmoid.configuration.panelCustomIcons || "";
            if (raw.length > 0) {
                raw.split(";").forEach(function (pair) {
                    var kv = pair.split("=");
                    if (kv.length === 2 && kv[0].trim().length > 0)
                        customMap[kv[0].trim()] = kv[1].trim();
                });
            }
            var defaults = {
                condition: W.weatherCodeToIcon(weatherCode, isNightTime()),
                temperature: "thermometer",
                feelslike: "thermometer",
                humidity: "weather-showers",
                pressure: "weather-overcast",
                wind: "weather-windy",
                moonphase: "weather-clear-night",
                location: "mark-location",
                preciprate: "weather-showers",
                precipsum: "flood",
                uvindex: "weather-clear",
                airquality: "weather-many-clouds",
                pollen: "sandstorm",
                spaceweather: "stars",
                alerts: "weather-storm",
                snowcover: "weather-snow-scattered"
            };

            if (tok === "condition") {
                if (customMap["condition-custom"] === "1") {
                    var code2 = weatherCode;
                    var night2 = isNightTime();
                    var condKey = _resolveConditionKey(code2, night2);
                    var fallback2 = W.weatherCodeToIcon(code2, night2);
                    var condSaved2 = (condKey in customMap && customMap[condKey].length > 0) ? customMap[condKey] : fallback2;
                    return { type: "kde", source: condSaved2, svgFallback: "", isMask: false };
                }
                return { type: "kde", source: W.weatherCodeToIcon(weatherCode, isNightTime()), svgFallback: "", isMask: false };
            }

            if (tok === "suntimes") {
                var mode2 = Plasmoid.configuration.panelSunTimesMode || "upcoming";
                var nowM2 = (new Date()).getHours() * 60 + (new Date()).getMinutes();
                var riseM2 = parseSunTimeMins(sunriseTimeText);
                var setM2 = parseSunTimeMins(sunsetTimeText);
                var useSet2 = (mode2 === "sunset") || (mode2 === "upcoming" && riseM2 >= 0 && nowM2 >= riseM2 && (setM2 < 0 || nowM2 < setM2));
                var sunKey2 = useSet2 ? "suntimes-sunset" : "suntimes-sunrise";
                var sunDef2 = useSet2 ? "weather-sunset" : "weather-sunrise";
                var sunSaved2 = (sunKey2 in customMap && customMap[sunKey2].length > 0) ? customMap[sunKey2] : sunDef2;
                return { type: "kde", source: sunSaved2, svgFallback: "", isMask: false };
            }

            if (tok === "moonphase" || tok === "moonphase-moonrise" || tok === "moonphase-moonset") {
                if (tok === "moonphase-moonrise") {
                    var mrSaved = (("moonrise" in customMap) && customMap["moonrise"].length > 0) ? customMap["moonrise"] : "weather-clear-night";
                    return { type: "kde", source: mrSaved, svgFallback: "", isMask: false };
                }
                if (tok === "moonphase-moonset") {
                    var msSaved = (("moonset" in customMap) && customMap["moonset"].length > 0) ? customMap["moonset"] : "weather-clear-night";
                    return { type: "kde", source: msSaved, svgFallback: "", isMask: false };
                }
                var mm2 = Plasmoid.configuration.panelMoonPhaseMode || "full";
                if (mm2 === "moonrise") {
                    var mrS2 = (("moonrise" in customMap) && customMap["moonrise"].length > 0) ? customMap["moonrise"] : "weather-clear-night";
                    return { type: "kde", source: mrS2, svgFallback: "", isMask: false };
                }
                if (mm2 === "moonset") {
                    var msS2 = (("moonset" in customMap) && customMap["moonset"].length > 0) ? customMap["moonset"] : "weather-clear-night";
                    return { type: "kde", source: msS2, svgFallback: "", isMask: false };
                }
                if (mm2 === "upcoming-times") {
                    var utKey = _moonUpcoming() === "rise" ? "moonrise" : "moonset";
                    var utSaved = ((utKey in customMap) && customMap[utKey].length > 0) ? customMap[utKey] : "weather-clear-night";
                    return { type: "kde", source: utSaved, svgFallback: "", isMask: false };
                }
                // Phase-showing modes: use bundled SVG moon phase icon
                var iconSzC = Plasmoid.configuration.panelIconSize || 22;
                var moonStemC = Moon.moonPhaseSvgStem(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
                return IconResolver.resolveMoonPhase(moonStemC, iconSzC, _iconsBaseDir, "flat-color");
            }

            var iconName = (tok in customMap && customMap[tok].length > 0) ? customMap[tok] : (tok in defaults ? defaults[tok] : "");
            return { type: "kde", source: iconName, svgFallback: "", isMask: false };
        }

        // ── KDE / SVG themes — unified via IconResolver ──────────────────────
        // KDE theme: KDE icon primary, symbolic SVG fallback.
        // SVG themes: SVG primary, KDE fallback.
        // KDE theme: KDE primary, symbolic SVG fallback (handled by IconResolver).
        var iconSz = Plasmoid.configuration.panelIconSize || 22;
        var svgTheme = (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light")
            ? "symbolic-light" : theme;

        // Dynamic items: condition, suntimes, moonphase
        if (tok === "condition")
            return IconResolver.resolveCondition(weatherCode, isNightTime(), iconSz, _iconsBaseDir, svgTheme);

        if (tok === "suntimes") {
            var sunTok = _resolveSuntimesTok();
            return IconResolver.resolve(sunTok, iconSz, _iconsBaseDir, svgTheme);
        }

        if (tok === "moonphase" || tok === "moonphase-moonrise" || tok === "moonphase-moonset") {
            if (tok === "moonphase-moonrise")
                return IconResolver.resolve("moonrise", iconSz, _iconsBaseDir, svgTheme);
            if (tok === "moonphase-moonset")
                return IconResolver.resolve("moonset", iconSz, _iconsBaseDir, svgTheme);
            var mm3 = Plasmoid.configuration.panelMoonPhaseMode || "full";
            if (mm3 === "moonrise") return IconResolver.resolve("moonrise", iconSz, _iconsBaseDir, svgTheme);
            if (mm3 === "moonset") return IconResolver.resolve("moonset", iconSz, _iconsBaseDir, svgTheme);
            if (mm3 === "upcoming-times") return IconResolver.resolve(_moonUpcoming() === "rise" ? "moonrise" : "moonset", iconSz, _iconsBaseDir, svgTheme);
            var moonStem = Moon.moonPhaseSvgStem(Moon.moonAgeFromPhase(SC.getMoonIllumination(new Date()).phase));
            return IconResolver.resolveMoonPhase(moonStem, iconSz, _iconsBaseDir, svgTheme);
        }

        // Standard items: temperature, humidity, pressure, wind, location, etc.
        return IconResolver.resolve(tok, iconSz, _iconsBaseDir, svgTheme);
    }

    /** Determines whether to show sunrise or sunset for suntimes panel item */
    function _resolveSuntimesTok() {
        var mode = Plasmoid.configuration.panelSunTimesMode || "upcoming";
        if (mode === "sunset") return "suntimes-sunset";
        if (mode === "sunrise") return "suntimes-sunrise";
        if (mode === "both") return "suntimes-sunrise"; // CompactView handles both-mode split
        // "upcoming": pick based on current time
        var nowM = (new Date()).getHours() * 60 + (new Date()).getMinutes();
        var riseM = parseSunTimeMins(sunriseTimeText);
        var setM = parseSunTimeMins(sunsetTimeText);
        var useSet = (riseM >= 0 && nowM >= riseM && (setM < 0 || nowM < setM));
        return useSet ? "suntimes-sunset" : "suntimes-sunrise";
    }

    /** Returns "rise" or "set" depending on which moon event is next */
    function _moonUpcoming() {
        var nowM = (new Date()).getHours() * 60 + (new Date()).getMinutes();
        var riseM = parseSunTimeMins(moonriseTimeText);
        var setM = parseSunTimeMins(moonsetTimeText);
        if (riseM >= 0 && nowM < riseM) return "rise";
        if (setM >= 0 && nowM < setM) return "set";
        return "rise";
    }

    /** Maps a WMO code + night flag to a condition custom icon key.
     *  Delegates to ConfigUtils.resolveConditionKey() — single source of truth. */
    function _resolveConditionKey(code, night) {
        return ConfigUtils.resolveConditionKey(code, night);
    }


    /** Returns the display text for a panel chip */
    function panelItemTextOnly(tok) {
        var mode = Plasmoid.configuration.panelSunTimesMode || "upcoming";
        if (tok === "location")
            return (_locName() || "").split(",")[0].trim();
        if (tok === "temperature")
            return tempValue(temperatureC);
        if (tok === "condition")
            return weatherCodeToText(weatherCode, isNightTime());
        if (tok === "wind")
            return windValue(windKmh);
        if (tok === "feelslike")
            return tempValue(apparentC);
        if (tok === "humidity")
            return isNaN(humidityPercent) ? "--" : Math.round(humidityPercent) + "%";
        if (tok === "pressure")
            return pressureValue(pressureHpa);
        if (tok === "moonphase" || tok === "moonphase-moonrise" || tok === "moonphase-moonset") {
            if (tok === "moonphase-moonrise")
                return formatTimeForDisplay(moonriseTimeText);
            if (tok === "moonphase-moonset")
                return formatTimeForDisplay(moonsetTimeText);
            var mm = Plasmoid.configuration.panelMoonPhaseMode || "full";
            if (mm === "phase") return moonPhaseLabel();
            if (mm === "moonrise") return formatTimeForDisplay(moonriseTimeText);
            if (mm === "moonset") return formatTimeForDisplay(moonsetTimeText);
            if (mm === "upcoming-times")
                return _moonUpcoming() === "rise" ? formatTimeForDisplay(moonriseTimeText) : formatTimeForDisplay(moonsetTimeText);
            // "full", "upcoming", "times" — main chip shows phase label; CompactView handles multi-chip
            return moonPhaseLabel();
        }
        if (tok === "suntimes") {
            var nowMins = (new Date()).getHours() * 60 + (new Date()).getMinutes();
            var riseMins = parseSunTimeMins(sunriseTimeText);
            var setMins = parseSunTimeMins(sunsetTimeText);
            if (mode === "upcoming") {
                if (riseMins >= 0 && nowMins < riseMins)
                    return formatTimeForDisplay(sunriseTimeText);
                if (setMins >= 0 && nowMins < setMins)
                    return formatTimeForDisplay(sunsetTimeText);
                return formatTimeForDisplay(sunriseTimeText);
            }
            if (mode === "sunrise")
                return formatTimeForDisplay(sunriseTimeText);
            if (mode === "sunset")
                return formatTimeForDisplay(sunsetTimeText);
            return formatTimeForDisplay(sunriseTimeText) + " / " + formatTimeForDisplay(sunsetTimeText);
        }
        if (tok === "preciprate")
            return precipValue(precipMmh);
        if (tok === "precipsum")
            return precipSumText(precipSumMm);
        if (tok === "uvindex")
            return uvIndexText(uvIndex);
        if (tok === "airquality")
            return airQualityText();
        if (tok === "pollen")
            return pollenText();
        if (tok === "spaceweather")
            return spaceWeatherText();
        if (tok === "alerts")
            return alertsText();
        if (tok === "snowcover")
            return snowDepthText(snowDepthCm);
        if (tok === "datetime")
            return _formatItemDateTime(
                Plasmoid.configuration.panelDateTimeFormat,
                Plasmoid.configuration.panelTimeFormat);
        return "";
    }

    // ══════════════════════════════════════════════════════════════════════
    // Font helper — sub-views call weatherRoot.wf(px, bold)
    // ══════════════════════════════════════════════════════════════════════

    function wf(pixelSize, bold) {
        if (Plasmoid.configuration.useSystemFont)
            return Qt.font({
                bold: bold || false
            });
        return Qt.font({
            family: Plasmoid.configuration.fontFamily || "sans-serif",
            pixelSize: Plasmoid.configuration.fontSize ? Plasmoid.configuration.fontSize + (pixelSize - 11) : pixelSize,
            bold: (Plasmoid.configuration.fontBold || bold) || false
        });
    }

    // wpf() — panel-specific font (uses panelUseSystemFont / panelFontFamily / panelFontBold).
    // The pixelSize parameter is always used as-is (multiline derives it from row height;
    // single-line passes panelFontPx which already incorporates panelFontSize).
    // wpf() — panel font; in manual mode converts stored pointSize to pixelSize.
    // Platform.FontDialog returns pointSize; Qt.font() needs pixelSize.
    // Standard 96 dpi conversion: 1pt = 4/3 px.
    function wpf(pixelSize, bold) {
        if (Plasmoid.configuration.panelUseSystemFont)
            return Qt.font({
                pixelSize: pixelSize,
                bold: bold || false
            });
        var savedPt = Plasmoid.configuration.panelFontSize || 0;
        var usePx = (savedPt > 0) ? Math.round(savedPt * 4 / 3) : pixelSize;
        return Qt.font({
            family: Plasmoid.configuration.panelFontFamily || Kirigami.Theme.defaultFont.family,
            pixelSize: usePx,
            bold: (Plasmoid.configuration.panelFontBold || bold) || false
        });
    }

    // ══════════════════════════════════════════════════════════════════════
    // Navigation helpers
    // ══════════════════════════════════════════════════════════════════════

    function openLocationSettings() {
        var action = Plasmoid.internalAction("configure");
        if (action)
            action.trigger();
    }

    // ══════════════════════════════════════════════════════════════════════
    // Timers
    // ══════════════════════════════════════════════════════════════════════

    // Auto-refresh weather data
    Timer {
        interval: Math.max(5, Plasmoid.configuration.refreshIntervalMinutes) * 60000
        running: Plasmoid.configuration.autoRefresh
        repeat: true
        onTriggered: refreshWeather()
    }

    // Notification evaluator loop. Runs every 30s so postponed alert
    // reminders (down to 1 minute) fire promptly; the hourly rain/tomorrow
    // data fetch inside _refreshNotificationRainWindowIfNeeded is separately
    // throttled to refreshIntervalMinutes, so this doesn't add extra requests.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            _refreshNotificationRainWindowIfNeeded(false);
            _evaluateNotifications();
        }
    }

    // Config-change debounce — coalesces rapid-fire signals that occur when
    // KDE KCM applies all cfg_ values at once on Apply/OK.  latitude, longitude,
    // timezone and locationName are written to Plasmoid.configuration one by one;
    // each triggers onXxxChanged → without debouncing, refreshWeather() fires
    // with only the first value updated (e.g. lat written, lon still 0) which
    // sends a bad API request and shows garbage data.  The 350 ms window allows
    // all config keys to settle before a single real refresh is performed.
    // _pendingRainWindowRefresh piggybacks the same settling window: calling
    // _refreshNotificationRainWindowIfNeeded() directly from the individual
    // onLatitudeChanged/onLongitudeChanged handlers (as a previous version
    // did) reads service.latitude/longitude before both have been written,
    // fetching hourly data for a mismatched old/new coordinate pair — so the
    // rain/upcoming-hours notification silently has no data after a location
    // switch. Deferring it here guarantees coordinates have settled first.
    property bool _pendingRainWindowRefresh: false
    Timer {
        id: refreshDebounce
        interval: 600
        repeat: false
        onTriggered: {
            refreshWeather();
            if (root._pendingRainWindowRefresh) {
                root._pendingRainWindowRefresh = false;
                root._refreshNotificationRainWindowIfNeeded(true);
            }
        }
    }

    // Persists location to KConfig after popup closes — avoids blocking KConfig
    // D-Bus writes on the UI thread during the location-switch click animation.
    Timer {
        id: _locPersistTimer
        interval: 800
        repeat: false
        onTriggered: root._applyPendingLocFields()
    }

    // Panel scroll ticker removed — "scroll/cycle" mode was removed.
    // The multiline Timer in CompactView.qml handles scrolling independently.

    // ══════════════════════════════════════════════════════════════════════
    // System resume detection — refresh weather after hibernate/suspend
    // ══════════════════════════════════════════════════════════════════════

    // Heartbeat timer: detects time jumps indicating system was asleep.
    // When the system wakes from hibernate/suspend, this timer runs immediately
    // and detects that more time has passed than the interval.
    property var _lastHeartbeat: Date.now()
    Timer {
        interval: 60000  // 1 minute
        running: true
        repeat: true
        onTriggered: {
            var now = Date.now();
            var elapsed = now - root._lastHeartbeat;
            root._lastHeartbeat = now;
            // If more than 3 minutes passed since last tick, system was likely suspended
            if (elapsed > 180000) {
                refreshDebounce.restart();
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Startup + config change reactions
    // ══════════════════════════════════════════════════════════════════════

    Component.onCompleted: {
        // Re-check in case the initial property binding ran before
        // containment was fully wired up.
        if (!inTray) {
            var detected = _detectInTray();
            if (detected)
                inTray = true;
        }

        // DefaultBackground: Plasma draws the standard widget frame on the desktop.
        // ConfigurableBackground: tells Plasma to show the "Show / Hide background"
        // toggle button when the widget is on the desktop in edit mode.
        // Must be set here (not as a static binding) so Plasma picks it up after
        // the component is fully live — same pattern used by Wunderground and others.
        Plasmoid.backgroundHints = PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground;
        // Populate location fields immediately from saved config (no deferral needed at startup)
        var s = Plasmoid.configuration.activeLocation || "{}";
        try {
            var o = JSON.parse(s);
            if (o && typeof o === "object") {
                root._activeLocName = o.name        || "";
                root._activeLocLat  = o.lat         || 0;
                root._activeLocLon  = o.lon         || 0;
                root._activeLocTz   = o.timezone    || "";
                root._activeLocCC   = o.countryCode || "";
                root._activeLocAlt  = o.altitude    !== undefined ? o.altitude : 0;
            }
        } catch(e) {}
        _updateHasSelectedTown();
        refreshDebounce.restart();
        // Restore the once-per-day "already sent" keys BEFORE the first evaluation
        // so a plasmashell restart doesn't re-fire daily notifications already
        // shown today (e.g. the geomagnetic-activity summary).
        _loadNotificationSentKeys();
        _loadAlertNotificationState();
        _loadAlertTypeSettings();
        _refreshNotificationRainWindowIfNeeded(true);
        _evaluateNotifications();
        if (Plasmoid.configuration.autoDetectLocation)
            _startAutoDetect();
    }

    Connections {
        target: Plasmoid.configuration
        function onActiveLocationChanged() {
            var s = Plasmoid.configuration.activeLocation || "{}";
            try {
                var o = JSON.parse(s);
                if (o && typeof o === "object") {
                    // Skip if fields already match (set by applyLocation via _applyActiveLoc)
                    if (root._activeLocLat === (o.lat || 0) && root._activeLocLon === (o.lon || 0) && root._activeLocName === (o.name || "")) return;
                    root.activeLocStaged = o;
                    return;
                }
            } catch(e) {}
            root.activeLocStaged = {};
        }
        // Location/provider/timezone changes must NOT reset alert-notification
        // state: it's keyed by alert identity (fingerprint), not location, so
        // dismiss/postpone correctly survive switching locations. They also
        // must NOT clear _notificationSentKeys — that would make
        // today/tomorrow/rain/UV/space-weather notifications (deduped only by
        // date) re-fire immediately for the new location even though they
        // already fired today.
        function onLocationNameChanged() {
            root._updateHasSelectedTown();
            root.weatherAlerts = [];
            if (!root._batchingLocation) refreshDebounce.restart();
        }
        function onLatitudeChanged() {
            root._pendingRainWindowRefresh = true;
            root.weatherAlerts = [];
            if (!root._batchingLocation) refreshDebounce.restart();
        }
        function onLongitudeChanged() {
            root._pendingRainWindowRefresh = true;
            root.weatherAlerts = [];
            if (!root._batchingLocation) refreshDebounce.restart();
        }
        function onTimezoneChanged() {
            root._pendingRainWindowRefresh = true;
            if (!root._batchingLocation) refreshDebounce.restart();
        }
        function onWeatherProviderChanged() {
            root._pendingRainWindowRefresh = true;
            refreshDebounce.restart();
        }
        function onForecastDaysChanged() {
            root._pendingRainWindowRefresh = true;
            refreshDebounce.restart();
        }
        // These must NOT call _resetAlertNotificationState(): that wipes the
        // dismiss/postpone state for every alert (all severities), so toggling
        // just one severity switch would re-notify every other already-
        // dismissed active alert too. Alerts excluded by _alertColorAllowed()
        // are simply skipped in _processAlertNotifications — no reset needed;
        // their dismiss state (if any) is preserved for when they're re-enabled.
        function onAlertNotificationsEnabledChanged() {
            root._evaluateNotifications();
        }
        function onAlertNotificationsYellowEnabledChanged() {
            root._evaluateNotifications();
        }
        function onAlertNotificationsOrangeEnabledChanged() {
            root._evaluateNotifications();
        }
        function onAlertNotificationsRedEnabledChanged() {
            root._evaluateNotifications();
        }
        function onAlertNotificationsRepeatEnabledChanged() {
            root._evaluateNotifications();
        }
        function onNotificationAlertsRepeatMinutesChanged() {
            root._evaluateNotifications();
        }
        function onAlertNotificationsTypeSettingsChanged() {
            root._loadAlertTypeSettings();
            root._evaluateNotifications();
        }
        function onNotificationAlertsDaysChanged() {
            root._evaluateNotifications();
        }
        function onNotificationAlertsTimesChanged() {
            root._evaluateNotifications();
        }
        // Toggling a category back ON must not immediately fire it just
        // because Apply was hit — it should stay silent until its next
        // natural occurrence. So pre-mark today's key as "already sent"
        // rather than clearing it (which would make _evaluateNotifications()
        // treat it as never-fired and send right away).
        function onNotificationTodayEnabledChanged() {
            if (Plasmoid.configuration.notificationTodayEnabled) {
                var dateKey = (root.dailyData && root.dailyData[0] && root.dailyData[0].dateStr)
                    || Qt.formatDate(new Date(), "yyyy-MM-dd");
                root._markNotificationSentKey("today:" + dateKey);
            }
            root._evaluateNotifications();
        }
        function onNotificationTodayTimeChanged() {
            root._evaluateNotifications();
        }
        function onNotificationTomorrowEnabledChanged() {
            if (Plasmoid.configuration.notificationTomorrowEnabled) {
                var d = root.dailyData && root.dailyData[1];
                if (d && d.dateStr)
                    root._markNotificationSentKey("tomorrow:" + d.dateStr);
            }
            root._refreshNotificationRainWindowIfNeeded(true);
            root._evaluateNotifications();
        }
        function onNotificationTomorrowTimeChanged() {
            root._evaluateNotifications();
        }
        function onNotificationRainEnabledChanged() {
            if (Plasmoid.configuration.notificationRainEnabled)
                root._suppressRainNotificationOnce = true;
            root._refreshNotificationRainWindowIfNeeded(true);
            root._evaluateNotifications();
        }
        function onNotificationSnowEnabledChanged() {
            if (Plasmoid.configuration.notificationSnowEnabled)
                root._suppressSnowNotificationOnce = true;
            root._refreshNotificationRainWindowIfNeeded(true);
            root._evaluateNotifications();
        }
        function onNotificationUvEnabledChanged() {
            root._evaluateNotifications();
        }
        function onNotificationUvTimeChanged() {
            root._evaluateNotifications();
        }
        function onNotificationSpaceWeatherEnabledChanged() {
            root._evaluateNotifications();
        }
        function onNotificationSpaceWeatherTimeChanged() {
            root._evaluateNotifications();
        }
        function onPanelInfoModeChanged() {
            root.panelScrollIndex = 0;
        }
    }
}
