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

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.components as PlasmaComponents
import "tabs"

KCM.AbstractKCM {
    id: root
    Kirigami.ColumnView.fillWidth: true

    // ── Config properties ─────────────────────────────────────────────────
    property string cfg_weatherProvider: "adaptive"
    // Last explicitly-chosen (non-adaptive) provider - restored when Adaptive
    // is turned back off. Kept in sync by onCfg_weatherProviderChanged below.
    property string cfg_lastManualProvider: ""
    property string cfg_owApiKey: ""
    property string cfg_waApiKey: ""
    property string cfg_pwApiKey: ""
    property string cfg_vcApiKey: ""
    property string cfg_tioApiKey: ""
    property string cfg_sgApiKey: ""
    property string cfg_wbApiKey: ""
    property string cfg_qwApiKey: ""
    property string cfg_qwApiHost: ""
    property string cfg_aemetApiKey: ""
    property bool cfg_radarEnabled: true
    property string cfg_radarProvider: "rainviewer"
    property string cfg_librewxrUrl: "https://api.librewxr.net"
    property string cfg_librewxrWindQuality: "balanced"
    property bool cfg_radarGpuWorkaround: false
    property string cfg_alertsProvider: "native"
    property string cfg_fossAlertUrl: "https://alerts.kde.org"
    property bool cfg_autoRefresh: true
    property int cfg_refreshIntervalMinutes: 15

    // ── Legacy props - keep bound so KCM doesn't lose them ────────────────
    property bool cfg_showScrollbox: true
    property int cfg_scrollboxLines: 2
    property string cfg_scrollboxItems: "Humidity;Wind;Pressure;Dew Point;Visibility"
    property bool cfg_animateTransitions: true

    // ── Derived state ─────────────────────────────────────────────────────
    readonly property bool isAdaptive: cfg_weatherProvider === "adaptive"
    readonly property bool isOpenWeather: cfg_weatherProvider === "openWeather"
    readonly property bool isWeatherApi: cfg_weatherProvider === "weatherApi"
    readonly property bool isPirateWeather: cfg_weatherProvider === "pirateWeather"
    readonly property bool isVisualCrossing: cfg_weatherProvider === "visualCrossing"
    readonly property bool isTomorrowIo: cfg_weatherProvider === "tomorrowIo"
    readonly property bool isStormGlass: cfg_weatherProvider === "stormGlass"
    readonly property bool isWeatherbit: cfg_weatherProvider === "weatherbit"
    readonly property bool isQWeather: cfg_weatherProvider === "qWeather"
    readonly property bool isAemet: cfg_weatherProvider === "aemet"
    readonly property bool needsKeyUi: isOpenWeather || isWeatherApi || isPirateWeather || isVisualCrossing || isTomorrowIo || isStormGlass || isWeatherbit || isQWeather || isAemet

    // Owned by the Location page (not part of this tab set), but declared
    // here too so this page can force it off for AEMET below - kcfg entries
    // can be read/written from any config page that declares the matching
    // cfg_ property, they all bind to the same on-disk value.
    property bool cfg_autoDetectLocation: false

    onCfg_weatherProviderChanged: {
        if (cfg_weatherProvider !== "adaptive")
            cfg_lastManualProvider = cfg_weatherProvider;
        // AEMET needs your exact configured location (Spain-only, resolved
        // to a municipio) - IP-based auto-detect is too imprecise for that,
        // so turn it off the moment AEMET is chosen. Does not turn back on
        // by itself if you switch away from AEMET again.
        if (cfg_weatherProvider === "aemet")
            cfg_autoDetectLocation = false;
    }

    // ── API key test state ────────────────────────────────────────────────
    // 0 = idle, 1 = testing, 2 = success, 3 = error
    property int apiTestState: 0
    property string apiTestMessage: ""
    property int _testGen: 0

    // ── Radar GPU-compositing workaround (hybrid-GPU/Wayland crash) ───────
    // Writes/removes a plasma-workspace session env script. This can only be
    // consumed by plasmashell at next login (env scripts run before the
    // session starts), so toggling this has no live effect on the current
    // session - the InlineMessage below makes that explicit to the user.
    readonly property string _radarGpuScriptPath: "~/.config/plasma-workspace/env/advanced-weather-widget-radar-gpu-workaround.sh"
    // TODO: point this at the real tracker issue for the hybrid-GPU crash before shipping.
    readonly property string _radarGpuIssueUrl: "https://github.com/OWNER/REPO/issues/ISSUE_NUMBER"

    // 0 = idle, 1 = checking, 2 = active this session, 3 = saved but needs a
    // logout, 4 = script missing/mismatched despite being enabled, 5 = just
    // turned off but still live for the rest of this session
    property int radarGpuTestState: 0
    property string radarGpuTestMessage: ""
    property var _radarGpuScriptPresent: undefined
    property var _radarGpuLiveActive: undefined

    // Whether this is a systemd-managed session - decides both whether
    // apply(false) even attempts a live env-var clear, and how the "Off -"
    // message below is worded. 0 = still checking, 1 = systemd, 2 = not
    // systemd (or systemctl unavailable). Detected once, not on every
    // checkStatus() round trip, since it can't change during a session.
    property int radarGpuSystemdState: 0

    /** Exposed so ConfigRadarTab.qml (a separate file/scope) can call apply()/checkStatus()/logout() */
    property alias radarGpuWorkaroundExec: radarGpuWorkaroundExec

    function _evaluateGpuStatus() {
        // Both checks are async and land independently - wait for both before
        // deciding on a combined status.
        if (root._radarGpuScriptPresent === undefined || root._radarGpuLiveActive === undefined)
            return;

        if (!root.cfg_radarGpuWorkaround) {
            // The switch is off - the script has already been removed (or
            // never existed). This isn't reporting on the switch itself,
            // just on what's still true for the CURRENTLY RUNNING session,
            // since env-var changes can't be retroactively applied to a
            // session that already started with the old value.
            if (root._radarGpuLiveActive) {
                root.radarGpuTestState = 5;
                if (root.radarGpuSystemdState === 1) {
                    root.radarGpuTestMessage = i18n("Off - the workaround script has been removed, so it won't load on your next login. Your system uses systemd, so anything launched fresh from here on may already reflect the cleared value - but anything already open (like a terminal you still have up) keeps showing the old one regardless, and a full log out and back in is the only guaranteed way to clear it everywhere.");
                } else if (root.radarGpuSystemdState === 2) {
                    root.radarGpuTestMessage = i18n("Off - the workaround script has been removed, so it won't load on your next login. This session already started with GPU compositing disabled though, and your system isn't systemd-managed, so there's no way to clear that live - it stays disabled (including anything you open freshly in this session) until you log out and back in.");
                } else {
                    root.radarGpuTestMessage = i18n("Off - the workaround script has been removed, so it won't load on your next login. This session already started with GPU compositing disabled though, so it stays that way (and anything already open, like a terminal, keeps showing the old value) until you log out and back in.");
                }
            } else {
                root.radarGpuTestState = 0;
                root.radarGpuTestMessage = "";
            }
            console.log("[Advanced Weather Widget Config] radar GPU workaround status:", root.radarGpuTestMessage || "(off, nothing lingering)");
            return;
        }

        if (root._radarGpuLiveActive) {
            root.radarGpuTestState = 2;
            root.radarGpuTestMessage = i18n("Active - GPU compositing is currently disabled for the radar map in this session.");
        } else if (root._radarGpuScriptPresent) {
            root.radarGpuTestState = 3;
            root.radarGpuTestMessage = i18n("Saved, but not active yet - log out and back in for it to take effect.");
        } else {
            root.radarGpuTestState = 4;
            root.radarGpuTestMessage = i18n("The workaround script wasn't found on disk. Try toggling the option off and on again.");
        }
        console.log("[Advanced Weather Widget Config] radar GPU workaround status:", root.radarGpuTestMessage);
    }

    Plasma5Support.DataSource {
        id: radarGpuWorkaroundExec
        engine: "executable"
        connectedSources: []
        Component.onCompleted: {
            // One-time, independent of checkStatus()'s recurring 2-way
            // check - "is this session systemd-managed" doesn't change
            // while the config page is open.
            connectSource("if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then echo SYSTEMD:YES; else echo SYSTEMD:NO; fi");
        }
        onNewData: function (sourceName, data) {
            var out = (data["stdout"] || "").toString().trim();
            if (sourceName.indexOf("if grep -qs") === 0) {
                root._radarGpuScriptPresent = out.indexOf("SCRIPT:PRESENT") !== -1;
                console.log("[Advanced Weather Widget Config] radar GPU workaround script on disk:", root._radarGpuScriptPresent ? "present, contains the expected export line" : "missing, or doesn't match the expected export line", "(" + root._radarGpuScriptPath + ")");
                root._evaluateGpuStatus();
            } else if (sourceName.indexOf("if [ \"$QTWEBENGINE_CHROMIUM_FLAGS\"") === 0) {
                root._radarGpuLiveActive = out.indexOf("LIVE:ACTIVE") !== -1;
                console.log("[Advanced Weather Widget Config] QTWEBENGINE_CHROMIUM_FLAGS in this session:", root._radarGpuLiveActive ? "\"--disable-gpu-compositing\" - workaround is active" : "not set to the workaround value - not active in this session yet");
                root._evaluateGpuStatus();
            } else if (sourceName.indexOf("if [ -d /run/systemd/system ]") === 0) {
                root.radarGpuSystemdState = out.indexOf("SYSTEMD:YES") !== -1 ? 1 : 2;
                console.log("[Advanced Weather Widget Config] systemd-managed session:", root.radarGpuSystemdState === 1 ? "yes" : "no (or systemctl unavailable)");
                // Refresh in case a status was already showing the
                // generic/unknown wording while this was still in flight.
                root._evaluateGpuStatus();
            } else if (data["exit code"] !== 0) {
                console.warn("[Advanced Weather Widget Config] radar GPU workaround command failed:", sourceName, "stderr=", data["stderr"]);
            } else {
                console.log("[Advanced Weather Widget Config] radar GPU workaround command OK:", sourceName);
            }
            disconnectSource(sourceName);
        }
        function apply(enabled) {
            var cmd;
            if (enabled) {
                cmd = "mkdir -p ~/.config/plasma-workspace/env && printf '%s\\n' 'export QTWEBENGINE_CHROMIUM_FLAGS=\"--disable-gpu-compositing\"' > " + root._radarGpuScriptPath;
            } else {
                // Removing the script only stops the NEXT login from picking
                // this up - it can't retroactively change an env var that
                // THIS session's already-running processes already inherited
                // at login. Best-effort extra step, gated on an actual
                // systemd check rather than just swallowing the error:
                // Plasma 6's systemd-based session startup also pushes
                // env-script exports into the systemd --user manager, so
                // anything launched via systemd/dbus activation from here on
                // (a fresh terminal, for instance - not one already open)
                // may pick up the cleared value without waiting for a full
                // logout. Plain `unset VARNAME` would NOT achieve this - it
                // would only affect this one-shot subprocess, which exits
                // immediately after, never touching the session it was
                // spawned from.
                cmd = "rm -f " + root._radarGpuScriptPath + "; if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then systemctl --user unset-environment QTWEBENGINE_CHROMIUM_FLAGS 2>/dev/null; fi";
            }
            connectSource(cmd);
            // Any earlier status check is stale now - clear it until re-checked.
            root.radarGpuTestState = 0;
            root.radarGpuTestMessage = "";
            root._radarGpuScriptPresent = undefined;
            root._radarGpuLiveActive = undefined;
        }
        function checkStatus() {
            root.radarGpuTestState = 1;
            root.radarGpuTestMessage = i18n("Checking…");
            root._radarGpuScriptPresent = undefined;
            root._radarGpuLiveActive = undefined;
            console.log("[Advanced Weather Widget Config] checking radar GPU workaround status: script path =", root._radarGpuScriptPath, ", expected export = QTWEBENGINE_CHROMIUM_FLAGS=\"--disable-gpu-compositing\"");
            connectSource("if grep -qs 'QTWEBENGINE_CHROMIUM_FLAGS=\"--disable-gpu-compositing\"' " + root._radarGpuScriptPath + "; then echo SCRIPT:PRESENT; else echo SCRIPT:MISSING; fi");
            connectSource("if [ \"$QTWEBENGINE_CHROMIUM_FLAGS\" = \"--disable-gpu-compositing\" ]; then echo LIVE:ACTIVE; else echo LIVE:INACTIVE; fi");
        }
        function logout() {
            connectSource("qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout");
        }
    }

    // ── Provider location check state ─────────────────────────────────
    // 0 = idle, 1 = checking, 2 = ok, 3 = error
    property int locationCheckState: 0
    property string locationCheckMessage: ""
    property int _locGen: 0

    // Mirrors WeatherService.qml's _isSpainLocation() - this config page runs
    // in its own QML context with no access to the running WeatherService
    // instance, so the same countryCode-with-bbox-fallback check is
    // duplicated here rather than shared.
    function _isSpainLocation() {
        var cc = Plasmoid.configuration.countryCode || "";
        if (cc.length > 0)
            return cc === "ES";
        var lat = Plasmoid.configuration.latitude;
        var lon = Plasmoid.configuration.longitude;
        if (isNaN(lat) || isNaN(lon))
            return false;
        if (lat >= 35.8 && lat <= 43.9 && lon >= -9.5 && lon <= 4.4)
            return true;    // peninsula + Balearics
        if (lat >= 27.5 && lat <= 29.5 && lon >= -18.3 && lon <= -13.3)
            return true;    // Canary Islands
        return false;
    }

    function verifyProviderLocation() {
        _locGen++;
        var myGen = _locGen;
        var lat = Plasmoid.configuration.latitude;
        var lon = Plasmoid.configuration.longitude;
        if (!lat && !lon) {
            locationCheckState = 0;
            return;
        }
        var provider = cfg_weatherProvider;
        if (provider === "adaptive" || provider === "openMeteo") {
            locationCheckState = 0;
            return;  // Open-Meteo/adaptive always works
        }
        locationCheckState = 1;
        locationCheckMessage = i18n("Checking location availability…");

        var req = new XMLHttpRequest();
        var url;
        if (provider === "openWeather") {
            var owKey = (cfg_owApiKey || "").trim();
            if (!owKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.openweathermap.org/data/2.5/weather?lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon) + "&units=metric&appid=" + encodeURIComponent(owKey);
        } else if (provider === "weatherApi") {
            var waKey = (cfg_waApiKey || "").trim();
            if (!waKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.weatherapi.com/v1/current.json?key=" + encodeURIComponent(waKey) + "&q=" + encodeURIComponent(lat + "," + lon);
        } else if (provider === "pirateWeather") {
            var pwKey = (cfg_pwApiKey || "").trim();
            if (!pwKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.pirateweather.net/forecast/" + encodeURIComponent(pwKey) + "/" + lat + "," + lon + "?units=ca&exclude=minutely,hourly,daily,alerts";
        } else if (provider === "visualCrossing") {
            var vcKey = (cfg_vcApiKey || "").trim();
            if (!vcKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/" + lat + "," + lon + "?key=" + encodeURIComponent(vcKey) + "&unitGroup=metric&include=current";
        } else if (provider === "tomorrowIo") {
            var tioKey = (cfg_tioApiKey || "").trim();
            if (!tioKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.tomorrow.io/v4/weather/realtime?location=" + lat + "," + lon + "&units=metric&apikey=" + encodeURIComponent(tioKey);
        } else if (provider === "stormGlass") {
            var sgKey = (cfg_sgApiKey || "").trim();
            if (!sgKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.stormglass.io/v2/weather/point?lat=" + encodeURIComponent(lat) + "&lng=" + encodeURIComponent(lon) + "&params=airTemperature";
        } else if (provider === "weatherbit") {
            var wbKey = (cfg_wbApiKey || "").trim();
            if (!wbKey) {
                locationCheckState = 0;
                return;
            }
            url = "https://api.weatherbit.io/v2.0/current?lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon) + "&key=" + encodeURIComponent(wbKey) + "&units=M";
        } else if (provider === "metno") {
            url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=" + encodeURIComponent(lat) + "&lon=" + encodeURIComponent(lon);
        } else if (provider === "bbc") {
            // BBC has no key; verify by resolving the nearest location id.
            url = "https://locator-service.api.bbci.co.uk/locations?api_key=AGbFAKx58hyjQScCXIYrxuEwJh2W2cmv&stack=aws&locale=en&filter=international&place-types=settlement%2Cairport%2Cdistrict&order=importance&latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon) + "&format=json";
        } else if (provider === "qWeather") {
            var qwKey = (cfg_qwApiKey || "").trim();
            if (!qwKey) {
                locationCheckState = 0;
                return;
            }
            var qwHost = (cfg_qwApiHost || "").trim();
            if (!qwHost)
                qwHost = "https://devapi.qweather.com";
            qwHost = qwHost.replace(/\/+$/, "");
            var qwLoc = encodeURIComponent(lon.toFixed(2) + "," + lat.toFixed(2));
            url = qwHost + "/v7/weather/now?location=" + qwLoc + "&unit=m";
        } else if (provider === "aemet") {
            var aeKey = (cfg_aemetApiKey || "").trim();
            if (!aeKey) {
                locationCheckState = 0;
                return;
            }
            if (!root._isSpainLocation()) {
                locationCheckState = 3;
                locationCheckMessage = i18n("AEMET only covers Spain - this location has no coverage.");
                return;
            }
            // AEMET has no lat/lon endpoint - only the first ("self-discovery")
            // hop is checked here, against a fixed always-valid municipio
            // (28079 = Madrid), just to confirm the key/connectivity work.
            // The real per-location municipio resolution happens at refresh
            // time in the widget itself.
            url = "https://opendata.aemet.es/opendata/api/prediccion/especifica/municipio/diaria/28079?api_key=" + encodeURIComponent(aeKey);
        } else {
            locationCheckState = 0;
            return;
        }
        req.open("GET", url);
        if (provider === "metno")
            req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
        if (provider === "stormGlass")
            req.setRequestHeader("Authorization", (cfg_sgApiKey || "").trim());
        if (provider === "qWeather")
            req.setRequestHeader("X-QW-Api-Key", (cfg_qwApiKey || "").trim());
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (_locGen !== myGen)
                return;
            var pLabel = root.providerDisplayName(provider);
            if (provider === "aemet") {
                if (req.status === 200) {
                    try {
                        var aeBody = JSON.parse(req.responseText);
                        if (aeBody.estado !== 200 || typeof aeBody.datos !== "string") {
                            locationCheckState = 3;
                            locationCheckMessage = i18n("AEMET error (code %1). Check your API key.", aeBody.estado);
                            return;
                        }
                    } catch (e) {
                        locationCheckState = 3;
                        locationCheckMessage = i18n("Invalid response from AEMET.");
                        return;
                    }
                    // Deliberately just the one request - it's enough to
                    // confirm the key/connectivity/location work, without an
                    // extra hop to the short-lived "datos" URL.
                    locationCheckState = 2;
                    locationCheckMessage = i18n("Location is available on %1.", pLabel);
                } else {
                    locationCheckState = 3;
                    locationCheckMessage = i18n("Location is not available on %1 (HTTP %2). Try a different provider or location.", pLabel, req.status);
                }
                return;
            }
            if (req.status === 200) {
                locationCheckState = 2;
                locationCheckMessage = i18n("Location is available on %1.", pLabel);
            } else {
                locationCheckState = 3;
                locationCheckMessage = i18n("Location is not available on %1 (HTTP %2). Try a different provider or location.", pLabel, req.status);
            }
        };
        req.send();
    }

    function providerDisplayName(p) {
        if (p === "openWeather")
            return "OpenWeatherMap";
        if (p === "weatherApi")
            return "WeatherAPI.com";
        if (p === "metno")
            return "met.no";
        if (p === "bbc")
            return "BBC Weather";
        if (p === "pirateWeather")
            return "Pirate Weather";
        if (p === "visualCrossing")
            return "Visual Crossing";
        if (p === "tomorrowIo")
            return "Tomorrow.io";
        if (p === "stormGlass")
            return "StormGlass";
        if (p === "weatherbit")
            return "Weatherbit";
        if (p === "qWeather")
            return "QWeather";
        if (p === "aemet")
            return "AEMET";
        return "Open-Meteo";
    }

    function testApiKey(rawKey) {
        _testGen++;
        var myGen = _testGen;
        var key = (rawKey || "").trim();
        if (!key) {
            apiTestState = 3;
            apiTestMessage = i18n("API key is empty.");
            return;
        }
        apiTestState = 1;
        apiTestMessage = i18n("Testing connection…");

        var req = new XMLHttpRequest();
        var url;
        var useAuthHeader = false;
        if (root.isOpenWeather) {
            url = "https://api.openweathermap.org/data/2.5/weather?lat=42.7&lon=23.3&units=metric&appid=" + encodeURIComponent(key);
        } else if (root.isPirateWeather) {
            url = "https://api.pirateweather.net/forecast/" + encodeURIComponent(key) + "/42.7,23.3" + "?units=ca&exclude=minutely,hourly,daily,alerts";
        } else if (root.isVisualCrossing) {
            url = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/42.7,23.3" + "?key=" + encodeURIComponent(key) + "&unitGroup=metric&include=current";
        } else if (root.isTomorrowIo) {
            url = "https://api.tomorrow.io/v4/weather/realtime?location=42.7,23.3&units=metric&apikey=" + encodeURIComponent(key);
        } else if (root.isStormGlass) {
            url = "https://api.stormglass.io/v2/weather/point?lat=42.7&lng=23.3&params=airTemperature";
            useAuthHeader = true;
        } else if (root.isWeatherbit) {
            url = "https://api.weatherbit.io/v2.0/current?lat=42.7&lon=23.3&key=" + encodeURIComponent(key) + "&units=M";
        } else if (root.isQWeather) {
            var qwHost = (root.cfg_qwApiHost || "").trim();
            if (!qwHost)
                qwHost = "https://devapi.qweather.com";
            qwHost = qwHost.replace(/\/+$/, "");
            url = qwHost + "/v7/weather/now?location=23.30,42.70&unit=m";
            useAuthHeader = true;
        } else if (root.isAemet) {
            // Same fixed-reference-point approach as the other branches
            // above, adapted to AEMET's municipio-code addressing: 28079 is
            // Madrid, always valid, so this purely tests the key/connectivity.
            url = "https://opendata.aemet.es/opendata/api/prediccion/especifica/municipio/diaria/28079?api_key=" + encodeURIComponent(key);
        } else {
            url = "https://api.weatherapi.com/v1/current.json?key=" + encodeURIComponent(key) + "&q=42.7,23.3";
        }
        req.open("GET", url);
        if (root.isQWeather)
            req.setRequestHeader("X-QW-Api-Key", key);
        else if (useAuthHeader)
            req.setRequestHeader("Authorization", key);
        req.onreadystatechange = function () {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            if (_testGen !== myGen)
                return;
            if (req.status === 200) {
                // QWeather returns HTTP 200 even on auth failure - check body code
                if (root.isQWeather) {
                    try {
                        var qwBody = JSON.parse(req.responseText);
                        if (qwBody.code !== "200") {
                            apiTestState = 3;
                            apiTestMessage = i18n("QWeather error (code %1). Check your API key.", qwBody.code);
                            return;
                        }
                    } catch (e) {
                        apiTestState = 3;
                        apiTestMessage = i18n("Invalid response from QWeather.");
                        return;
                    }
                } else if (root.isAemet) {
                    try {
                        var aeBody = JSON.parse(req.responseText);
                        if (aeBody.estado !== 200 || typeof aeBody.datos !== "string") {
                            apiTestState = 3;
                            apiTestMessage = i18n("AEMET error (code %1). Check your API key.", aeBody.estado);
                            return;
                        }
                    } catch (e) {
                        apiTestState = 3;
                        apiTestMessage = i18n("Invalid response from AEMET.");
                        return;
                    }
                    // Deliberately just the one request above - it's enough
                    // to confirm the key/connectivity work, without an extra
                    // hop to the short-lived "datos" URL.
                }
                apiTestState = 2;
                var pLabel = root.providerDisplayName(root.cfg_weatherProvider);
                apiTestMessage = i18n("Connection successful! %1 key is valid.", pLabel);
                root.verifyProviderLocation();
            } else if (req.status === 401 || req.status === 403) {
                apiTestState = 3;
                apiTestMessage = i18n("Invalid API key. Please check and try again.");
            } else {
                apiTestState = 3;
                apiTestMessage = i18n("Connection failed (HTTP %1).", req.status);
            }
        };
        req.send();
    }

    // Providers without Adaptive - Adaptive is handled by the switch above
    readonly property var providerModel: [
        {
            text: i18n("Open-Meteo (recommended, free)"),
            value: "openMeteo"
        },
        {
            text: i18n("met.no (free)"),
            value: "metno"
        },
        {
            text: i18n("BBC Weather (free)"),
            value: "bbc"
        },
        {
            text: i18n("OpenWeatherMap (Key Required)"),
            value: "openWeather"
        },
        {
            text: i18n("WeatherAPI.com (Key Required)"),
            value: "weatherApi"
        },
        {
            text: i18n("Pirate Weather (Key Required)"),
            value: "pirateWeather"
        },
        {
            text: i18n("Visual Crossing (Key Required)"),
            value: "visualCrossing"
        },
        {
            text: i18n("Tomorrow.io (Key Required)"),
            value: "tomorrowIo"
        },
        {
            text: i18n("StormGlass (Key Required)"),
            value: "stormGlass"
        },
        {
            text: i18n("Weatherbit (Key Required)"),
            value: "weatherbit"
        },
        {
            text: i18n("QWeather (Key Required)"),
            value: "qWeather"
        },
        {
            text: i18n("AEMET - Spain only (Key Required)"),
            value: "aemet"
        }
    ]

    function providerIndexFor(val) {
        for (var i = 0; i < providerModel.length; ++i)
            if (providerModel[i].value === val)
                return i;
        return 0;
    }

    // ══════════════════════════════════════════════════════════════════════
    // TAB BAR - 3 tabs: Provider, Radar, Weather Alerts
    // ══════════════════════════════════════════════════════════════════════
    header: PlasmaComponents.TabBar {
        id: tabBar

        PlasmaComponents.TabButton {
            icon.name: "network-connect"
            text: i18n("Provider")
        }
        PlasmaComponents.TabButton {
            icon.name: "weather-showers-scattered"
            text: i18n("Radar")
        }
        PlasmaComponents.TabButton {
            icon.name: "task-attention"
            text: i18n("Weather Alerts")
        }
    }

    Kirigami.ScrollablePage {
        anchors.fill: parent

        // Tab pages live in a plain ColumnLayout and only the selected one is visible.
        // A StackLayout is as tall as its TALLEST page, which left empty space and a
        // permanent scrollbar under the shorter tabs; layouts ignore hidden items.
        ColumnLayout {
            Layout.fillWidth: true

            // TAB 0 - PROVIDER
            ConfigProviderTab {
                visible: tabBar.currentIndex === 0
                configRoot: root
            }

            // TAB 1 - RADAR
            ConfigRadarTab {
                visible: tabBar.currentIndex === 1
                configRoot: root
            }

            // TAB 2 - WEATHER ALERTS
            ConfigAlertsTab {
                visible: tabBar.currentIndex === 2
                configRoot: root
            }
        }
    }
}
