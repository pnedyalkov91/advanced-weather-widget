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
 * ConfigLocationManualSubPage — Enter a location manually by name + coordinates.
 * Includes a "Test" button that checks availability against every supported
 * weather provider in parallel and reports the results.
 * Requires: required property var configRoot
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

ColumnLayout {
    id: manualSubPageRoot
    required property var configRoot
    spacing: 0

    // ── Form state ─────────────────────────────────────────────────────
    property string mName: ""
    property string mLat: ""
    property string mLon: ""
    property string mAlt: ""
    property string mTimezone: ""

    // ── Edit mode ──────────────────────────────────────────────────────
    // When >= 0, the form is editing an existing saved-location entry at
    // that index in cfg_savedLocations. `_applyToConfig()` then updates
    // that entry in place instead of creating a new pending entry.
    // -1 = "Add new location" mode (default).
    property int editingIndex: -1
    readonly property bool isEditMode: editingIndex >= 0

    // Numeric validity — normalize "," to "." so users in locales like
    // Bulgarian/German (where the keyboard decimal is ",") still parse correctly.
    readonly property real _latNum: parseFloat(String(mLat).replace(",", "."))
    readonly property real _lonNum: parseFloat(String(mLon).replace(",", "."))
    readonly property int _altNum: parseInt(mAlt, 10)
    readonly property bool _latValid: !isNaN(_latNum) && _latNum >= -90  && _latNum <= 90
    readonly property bool _lonValid: !isNaN(_lonNum) && _lonNum >= -180 && _lonNum <= 180
    readonly property bool _altValid: mAlt.length === 0 || !isNaN(_altNum)
    readonly property bool _formValid: _latValid && _lonValid && _altValid && mName.trim().length > 0

    // ── Auto-stage to cfg_* — KCM Apply handles the final commit ───────
    // Debounced so we don't thrash on every keystroke.
    Timer {
        id: stageTimer
        interval: 250
        repeat: false
        onTriggered: manualSubPageRoot._applyToConfig()
    }
    onMNameChanged:     stageTimer.restart()
    onMLatChanged:      stageTimer.restart()
    onMLonChanged:      stageTimer.restart()
    onMAltChanged:      stageTimer.restart()
    onMTimezoneChanged: stageTimer.restart()

    // ── IANA timezone list (commonly-used subset) ──────────────────────
    readonly property var _timezoneList: [
        "UTC",
        "Africa/Abidjan", "Africa/Algiers", "Africa/Cairo", "Africa/Casablanca",
        "Africa/Johannesburg", "Africa/Lagos", "Africa/Nairobi", "Africa/Tunis",
        "America/Anchorage", "America/Argentina/Buenos_Aires", "America/Bogota",
        "America/Caracas", "America/Chicago", "America/Denver", "America/Halifax",
        "America/Havana", "America/Lima", "America/Los_Angeles", "America/Mexico_City",
        "America/New_York", "America/Noronha", "America/Phoenix", "America/Santiago",
        "America/Sao_Paulo", "America/St_Johns", "America/Toronto", "America/Vancouver",
        "Antarctica/McMurdo",
        "Asia/Almaty", "Asia/Baghdad", "Asia/Bangkok", "Asia/Beirut",
        "Asia/Dhaka", "Asia/Dubai", "Asia/Ho_Chi_Minh", "Asia/Hong_Kong",
        "Asia/Jakarta", "Asia/Jerusalem", "Asia/Kabul", "Asia/Karachi",
        "Asia/Kathmandu", "Asia/Kolkata", "Asia/Kuala_Lumpur", "Asia/Manila",
        "Asia/Riyadh", "Asia/Seoul", "Asia/Shanghai", "Asia/Singapore",
        "Asia/Taipei", "Asia/Tashkent", "Asia/Tehran", "Asia/Tokyo",
        "Asia/Yangon", "Asia/Yekaterinburg", "Asia/Yerevan",
        "Atlantic/Azores", "Atlantic/Cape_Verde", "Atlantic/Reykjavik",
        "Australia/Adelaide", "Australia/Brisbane", "Australia/Darwin",
        "Australia/Hobart", "Australia/Melbourne", "Australia/Perth", "Australia/Sydney",
        "Europe/Amsterdam", "Europe/Athens", "Europe/Belgrade", "Europe/Berlin",
        "Europe/Brussels", "Europe/Bucharest", "Europe/Budapest", "Europe/Chisinau",
        "Europe/Copenhagen", "Europe/Dublin", "Europe/Helsinki", "Europe/Istanbul",
        "Europe/Kyiv", "Europe/Lisbon", "Europe/London", "Europe/Luxembourg",
        "Europe/Madrid", "Europe/Minsk", "Europe/Moscow", "Europe/Oslo",
        "Europe/Paris", "Europe/Prague", "Europe/Riga", "Europe/Rome",
        "Europe/Sofia", "Europe/Stockholm", "Europe/Tallinn", "Europe/Vienna",
        "Europe/Vilnius", "Europe/Warsaw", "Europe/Zurich",
        "Pacific/Auckland", "Pacific/Chatham", "Pacific/Fiji", "Pacific/Guam",
        "Pacific/Honolulu", "Pacific/Midway", "Pacific/Noumea", "Pacific/Pago_Pago",
        "Pacific/Port_Moresby", "Pacific/Tahiti", "Pacific/Tongatapu"
    ]
    readonly property var _timezoneListWithAuto: {
        var out = [i18n("Auto (detect on save)")];
        return out.concat(_timezoneList);
    }

    // ── Provider test state ────────────────────────────────────────────
    // Each entry: { key, label, state:0..3, message, needsKey }
    //   state: 0 idle, 1 checking, 2 ok, 3 error, 4 skipped (no key)
    property var providerResults: _initialProviders()
    property bool testingActive: false
    property int _testGen: 0

    function _initialProviders() {
        return [
            { key: "openMeteo",      label: "Open-Meteo",       state: 0, message: "", needsKey: false },
            { key: "metno",          label: "met.no",           state: 0, message: "", needsKey: false },
            { key: "openWeather",    label: "OpenWeatherMap",   state: 0, message: "", needsKey: true  },
            { key: "weatherApi",     label: "WeatherAPI.com",   state: 0, message: "", needsKey: true  },
            { key: "pirateWeather",  label: "Pirate Weather",   state: 0, message: "", needsKey: true  },
            { key: "visualCrossing", label: "Visual Crossing",  state: 0, message: "", needsKey: true  },
            { key: "tomorrowIo",     label: "Tomorrow.io",      state: 0, message: "", needsKey: true  },
            { key: "stormGlass",     label: "StormGlass",       state: 0, message: "", needsKey: true  },
            { key: "weatherbit",     label: "Weatherbit",       state: 0, message: "", needsKey: true  },
            { key: "qWeather",       label: "QWeather",         state: 0, message: "", needsKey: true  }
        ];
    }

    function _setResult(key, state, message) {
        var arr = providerResults.slice();
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].key === key) {
                arr[i] = { key: arr[i].key, label: arr[i].label, state: state, message: message, needsKey: arr[i].needsKey };
                break;
            }
        }
        providerResults = arr;
    }

    function _buildProviderUrl(p, lat, lon) {
        // Returns { url, useAuthHeader, authKey, rawKey, missingKey }
        var cfg = Plasmoid.configuration;
        if (p === "openMeteo")
            return { url: "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon + "&current=temperature_2m" };
        if (p === "metno")
            return { url: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=" + lat + "&lon=" + lon };
        if (p === "openWeather") {
            var ow = (cfg.owApiKey || "").trim();
            if (!ow) return { missingKey: true };
            return { url: "https://api.openweathermap.org/data/2.5/weather?lat=" + lat + "&lon=" + lon + "&units=metric&appid=" + encodeURIComponent(ow) };
        }
        if (p === "weatherApi") {
            var wa = (cfg.waApiKey || "").trim();
            if (!wa) return { missingKey: true };
            return { url: "https://api.weatherapi.com/v1/current.json?key=" + encodeURIComponent(wa) + "&q=" + encodeURIComponent(lat + "," + lon) };
        }
        if (p === "pirateWeather") {
            var pw = (cfg.pwApiKey || "").trim();
            if (!pw) return { missingKey: true };
            return { url: "https://api.pirateweather.net/forecast/" + encodeURIComponent(pw) + "/" + lat + "," + lon + "?units=ca&exclude=minutely,hourly,daily,alerts" };
        }
        if (p === "visualCrossing") {
            var vc = (cfg.vcApiKey || "").trim();
            if (!vc) return { missingKey: true };
            return { url: "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/" + lat + "," + lon + "?key=" + encodeURIComponent(vc) + "&unitGroup=metric&include=current" };
        }
        if (p === "tomorrowIo") {
            var tio = (cfg.tioApiKey || "").trim();
            if (!tio) return { missingKey: true };
            return { url: "https://api.tomorrow.io/v4/weather/realtime?location=" + lat + "," + lon + "&units=metric&apikey=" + encodeURIComponent(tio) };
        }
        if (p === "stormGlass") {
            var sg = (cfg.sgApiKey || "").trim();
            if (!sg) return { missingKey: true };
            return { url: "https://api.stormglass.io/v2/weather/point?lat=" + lat + "&lng=" + lon + "&params=airTemperature", useAuthHeader: true, authKey: sg };
        }
        if (p === "weatherbit") {
            var wb = (cfg.wbApiKey || "").trim();
            if (!wb) return { missingKey: true };
            return { url: "https://api.weatherbit.io/v2.0/current?lat=" + lat + "&lon=" + lon + "&key=" + encodeURIComponent(wb) + "&units=M" };
        }
        if (p === "qWeather") {
            var qw = (cfg.qwApiKey || "").trim();
            if (!qw) return { missingKey: true };
            var qwLoc = encodeURIComponent(parseFloat(lon).toFixed(2) + "," + parseFloat(lat).toFixed(2));
            return { url: "https://devapi.qweather.com/v7/weather/now?location=" + qwLoc + "&key=" + encodeURIComponent(qw) + "&unit=m" };
        }
        return null;
    }

    function runTest() {
        if (!_latValid || !_lonValid) return;
        _testGen++;
        var myGen = _testGen;
        testingActive = true;
        providerResults = _initialProviders();

        var lat = _latNum;
        var lon = _lonNum;
        var completed = 0;
        var total = providerResults.length;

        providerResults.forEach(function(entry) {
            var p = entry.key;
            var info = _buildProviderUrl(p, lat, lon);
            if (!info || info.missingKey) {
                _setResult(p, 4, i18n("Skipped — API key not configured"));
                if (++completed >= total && myGen === _testGen) testingActive = false;
                return;
            }
            _setResult(p, 1, i18n("Testing…"));

            var req = new XMLHttpRequest();
            req.open("GET", info.url);
            if (p === "metno")
                req.setRequestHeader("User-Agent", "AdvancedWeatherWidget/1.0 github.com/pnedyalkov91/advanced-weather-widget");
            if (info.useAuthHeader)
                req.setRequestHeader("Authorization", info.authKey);

            // 10s timeout per request
            var timeoutTimer = Qt.createQmlObject(
                'import QtQuick; Timer { interval: 10000; repeat: false; running: true }',
                manualSubPageRoot, "manualTestTimer_" + p);
            timeoutTimer.triggered.connect(function() {
                if (req.readyState !== XMLHttpRequest.DONE) {
                    try { req.abort(); } catch (e) {}
                    if (myGen === _testGen)
                        _setResult(p, 3, i18n("Timed out"));
                    if (++completed >= total && myGen === _testGen) testingActive = false;
                }
                timeoutTimer.destroy();
            });

            req.onreadystatechange = function() {
                if (req.readyState !== XMLHttpRequest.DONE) return;
                if (myGen !== _testGen) return;
                timeoutTimer.stop();
                timeoutTimer.destroy();

                if (req.status === 200) {
                    // QWeather returns HTTP 200 even on auth failure — check body code
                    if (p === "qWeather") {
                        try {
                            var body = JSON.parse(req.responseText);
                            if (body.code !== "200") {
                                _setResult(p, 3, i18n("Error (code %1)", body.code));
                                if (++completed >= total) testingActive = false;
                                return;
                            }
                        } catch (e) {
                            _setResult(p, 3, i18n("Invalid response"));
                            if (++completed >= total) testingActive = false;
                            return;
                        }
                    }
                    _setResult(p, 2, i18n("Available"));
                } else if (req.status === 401 || req.status === 403) {
                    _setResult(p, 3, i18n("Invalid API key (HTTP %1)", req.status));
                } else if (req.status === 0) {
                    _setResult(p, 3, i18n("Network error"));
                } else {
                    _setResult(p, 3, i18n("Not available (HTTP %1)", req.status));
                }
                if (++completed >= total) testingActive = false;
            };
            req.send();
        });
    }

    function _applyToConfig() {
        if (!_formValid) return;
        var lat = _latNum;
        var lon = _lonNum;
        var alt = (mAlt.length > 0 && !isNaN(_altNum)) ? _altNum : 0;
        var name = mName.trim();
        // Empty mTimezone means "Auto" — leave cfg_timezone unchanged so the
        // existing auto-detect flow on refresh fills it in.
        var tz = mTimezone;

        var locs;
        try {
            locs = JSON.parse(configRoot.cfg_savedLocations || "[]");
            if (!Array.isArray(locs)) locs = [];
        } catch (e) { locs = []; }

        // ── EDIT MODE ─────────────────────────────────────────────────
        // When editing an existing saved location, update that entry in
        // place (preserving its star flag and list position) instead of
        // creating a new _pendingEntry. The entry's lat/lon may also be
        // changed — that's fine, we just overwrite in place.
        if (isEditMode && editingIndex >= 0 && editingIndex < locs.length) {
            var prev = locs[editingIndex] || {};
            var wasActive = Math.abs(configRoot.cfg_latitude  - (prev.lat || 0)) < 0.01 &&
                            Math.abs(configRoot.cfg_longitude - (prev.lon || 0)) < 0.01;
            var updated = {
                name: name,
                lat: lat,
                lon: lon
            };
            if (alt !== 0)                              updated.altitude    = alt;
            if (tz && tz.length > 0)                    updated.timezone    = tz;
            else if (prev.timezone)                     updated.timezone    = prev.timezone;
            if (prev.countryCode)                       updated.countryCode = prev.countryCode;
            if (prev.starred)                           updated.starred     = true;
            locs[editingIndex] = updated;
            configRoot.cfg_savedLocations = JSON.stringify(locs);

            // If the edited entry is the currently-active location, also
            // update the live cfg_* so KCM Apply syncs it to Plasmoid.
            if (wasActive) {
                configRoot.cfg_autoDetectLocation = false;
                configRoot.cfg_locationName = name;
                configRoot.cfg_latitude     = lat;
                configRoot.cfg_longitude    = lon;
                configRoot.cfg_altitude     = alt;
                if (tz && tz.length > 0)
                    configRoot.cfg_timezone = tz;
            }
            configRoot._pendingEntry = null;
            return;
        }

        // ── ADD-NEW MODE (original behaviour) ─────────────────────────
        var isNew = !locs.some(function(l) {
            return Math.abs(l.lat - lat) < 0.01 && Math.abs(l.lon - lon) < 0.01;
        });

        configRoot.cfg_autoDetectLocation = false;
        configRoot.cfg_locationName = name;
        configRoot.cfg_latitude = lat;
        configRoot.cfg_longitude = lon;
        configRoot.cfg_altitude = alt;
        if (tz.length > 0)
            configRoot.cfg_timezone = tz;

        if (isNew) {
            configRoot._pendingEntry = {
                name: name,
                lat: lat,
                lon: lon,
                altitude: alt,
                timezone: tz.length > 0 ? tz : (configRoot.cfg_timezone || ""),
                countryCode: configRoot.cfg_countryCode || ""
            };
        } else {
            configRoot._pendingEntry = null;
        }
    }

    // ── Header ──────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.leftMargin: 4
        Layout.rightMargin: 8
        Layout.bottomMargin: 4
        spacing: 4

        Button {
            icon.name: "go-previous"
            text: i18n("Back")
            flat: true
            onClicked: {
                // Leaving the page exits edit mode so the next "Enter Manually"
                // starts a fresh "Add Location" flow.
                manualSubPageRoot.editingIndex = -1;
                configRoot._goBack();
            }
        }
        Label {
            Layout.fillWidth: true
            text: manualSubPageRoot.isEditMode
                ? i18n("Edit Saved Location")
                : i18n("Add Location Manually")
            font.bold: true
        }
    }

    // ── Form ────────────────────────────────────────────────────────────
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                type: Kirigami.MessageType.Information
                visible: true
                text: i18n("Need the coordinates for a place? You can look them up at <a href=\"https://www.mapcoordinates.net/\">mapcoordinates.net</a>.")
                onLinkActivated: Qt.openUrlExternally(link)
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing

                TextField {
                    Kirigami.FormData.label: i18n("Location name:")
                    Layout.fillWidth: true
                    Layout.preferredWidth: 320
                    placeholderText: i18n("e.g. Sofia, Bulgaria")
                    text: manualSubPageRoot.mName
                    onTextEdited: manualSubPageRoot.mName = text
                    selectByMouse: true
                }

                TextField {
                    id: latField
                    Kirigami.FormData.label: i18n("Latitude:")
                    Layout.fillWidth: true
                    Layout.preferredWidth: 320
                    placeholderText: i18n("-90 to 90 (e.g. 42.6977)")
                    text: manualSubPageRoot.mLat
                    onTextEdited: manualSubPageRoot.mLat = text
                    selectByMouse: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    // Locale-independent: accept both "." and "," as decimal.
                    // The numeric parser (_latNum) normalizes "," → ".".
                    validator: RegularExpressionValidator {
                        regularExpression: /^-?(\d{1,2}([.,]\d{0,7})?)?$/
                    }
                }

                TextField {
                    id: lonField
                    Kirigami.FormData.label: i18n("Longitude:")
                    Layout.fillWidth: true
                    Layout.preferredWidth: 320
                    placeholderText: i18n("-180 to 180 (e.g. 23.3219)")
                    text: manualSubPageRoot.mLon
                    onTextEdited: manualSubPageRoot.mLon = text
                    selectByMouse: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegularExpressionValidator {
                        regularExpression: /^-?(\d{1,3}([.,]\d{0,7})?)?$/
                    }
                }

                TextField {
                    id: altField
                    Kirigami.FormData.label: i18n("Altitude (%1):",
                        configRoot.cfg_altitudeUnit === "ft" ? i18n("feet") : i18n("meters"))
                    Layout.fillWidth: true
                    Layout.preferredWidth: 320
                    placeholderText: i18n("Recommended — e.g. 560")
                    text: manualSubPageRoot.mAlt
                    onTextEdited: manualSubPageRoot.mAlt = text
                    selectByMouse: true
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: -500; top: 9000 }
                }

                Label {
                    Kirigami.FormData.label: " "
                    Layout.fillWidth: true
                    Layout.preferredWidth: 320
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    text: i18n("Altitude is optional, but strongly recommended for accurate forecasts. MET Norway (met.no) uses it to correct temperature and pressure for elevation; leaving it at 0 for a mountain location will return sea-level values.")
                }

                ComboBox {
                    id: timezoneCombo
                    Kirigami.FormData.label: i18n("Timezone:")
                    Layout.fillWidth: true
                    Layout.preferredWidth: 320
                    editable: true
                    model: manualSubPageRoot._timezoneListWithAuto
                    // Index 0 = "Auto" placeholder → maps to empty mTimezone
                    currentIndex: {
                        if (!manualSubPageRoot.mTimezone || manualSubPageRoot.mTimezone.length === 0)
                            return 0;
                        var idx = manualSubPageRoot._timezoneList.indexOf(manualSubPageRoot.mTimezone);
                        return idx >= 0 ? (idx + 1) : -1;
                    }
                    onActivated: function(index) {
                        manualSubPageRoot.mTimezone = (index <= 0) ? "" : manualSubPageRoot._timezoneList[index - 1];
                    }
                    // Editable: let the user type a custom IANA id
                    onEditTextChanged: {
                        if (!activeFocus) return;
                        var t = editText.trim();
                        if (t.length === 0 || t === manualSubPageRoot._timezoneListWithAuto[0]) {
                            manualSubPageRoot.mTimezone = "";
                        } else if (manualSubPageRoot._timezoneList.indexOf(t) >= 0) {
                            manualSubPageRoot.mTimezone = t;
                        } else {
                            // Accept custom input — user may know a valid IANA id not in our list
                            manualSubPageRoot.mTimezone = t;
                        }
                    }
                }
            }

            // ── Buttons ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Button {
                    text: i18n("Test across providers")
                    icon.name: "view-certificate-server"
                    enabled: manualSubPageRoot._latValid && manualSubPageRoot._lonValid && !manualSubPageRoot.testingActive
                    onClicked: manualSubPageRoot.runTest()
                }
                Item { Layout.fillWidth: true }
            }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                wrapMode: Text.WordWrap
                opacity: 0.75
                text: manualSubPageRoot._formValid
                    ? (manualSubPageRoot.isEditMode
                        ? i18n("Changes staged. Click the main Apply button to save.")
                        : i18n("Location staged. Click the main Apply button to save."))
                    : i18n("Enter a location name and valid coordinates, then click the main Apply button.")
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            // ── Provider test results ───────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    Kirigami.Heading {
                        level: 4
                        text: i18n("Provider availability")
                    }
                    Item { Layout.fillWidth: true }
                    BusyIndicator {
                        running: manualSubPageRoot.testingActive
                        visible: running
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: i18n("Click \"Test across providers\" to check if the coordinates are serviceable by each supported weather provider. Providers requiring an API key that is not configured will be skipped.")
                }

                Repeater {
                    model: manualSubPageRoot.providerResults
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                            source: {
                                switch (modelData.state) {
                                case 2: return "dialog-ok";
                                case 3: return "dialog-error";
                                case 1: return "view-refresh";
                                case 4: return "dialog-information";
                                default: return "dialog-question";
                                }
                            }
                            color: {
                                switch (modelData.state) {
                                case 2: return Kirigami.Theme.positiveTextColor;
                                case 3: return Kirigami.Theme.negativeTextColor;
                                case 4: return Kirigami.Theme.disabledTextColor;
                                default: return Kirigami.Theme.textColor;
                                }
                            }
                        }
                        Label {
                            text: modelData.label
                            Layout.preferredWidth: 140
                            Layout.minimumWidth: 140
                            font.bold: true
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            opacity: modelData.state === 4 ? 0.65 : 1.0
                            text: modelData.message || (modelData.state === 0 ? i18n("Not tested") : "")
                            color: {
                                switch (modelData.state) {
                                case 2: return Kirigami.Theme.positiveTextColor;
                                case 3: return Kirigami.Theme.negativeTextColor;
                                default: return Kirigami.Theme.textColor;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
