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
 * HistoryView.qml - "History" tab: past weather for the active location from
 * the Open-Meteo Historical Weather API.
 *
 *   • Period picker: presets (yesterday … this year), a single day, or a
 *     custom range (HistoryDatePicker).
 *   • < / > step the period back and forth (see _navigate()).
 *   • Summary tiles, a temperature + precipitation chart (hover for the day's
 *     values; zoom buttons make it scroll sideways) and an expandable
 *     newest-first daily list.
 *
 * All requests/parsing live in providers/openMeteoHistory.js; unit
 * conversion and fonts go through weatherRoot like every other tab, so the
 * user's unit settings are honoured. Dates and times follow Appearance →
 * Misc → Date and Time (see _date / _day / _time), and the tile / detail
 * icons follow Appearance → Widget → Details → Icon theme.
 *
 * The chart is components/HistoryChartGraphs.qml (Qt Graphs, styled after
 * the KDE Plasma Weather applet). Where Qt Graphs is unavailable the Loader
 * falls back to components/HistoryChartKQC.qml, the same chart drawn with
 * KDE's KQuickCharts (org.kde.quickcharts). If neither module is installed a
 * short message is shown instead of the chart.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "providers/openMeteoHistory.js" as H
import "js/iconResolver.js" as IconResolver
import "js/configUtils.js" as ConfigUtils
import "components"

Item {
    id: root

    property var weatherRoot
    /** FullView.resolveConditionIcon(code, isNight, size) -> iconInfo for WeatherIcon. */
    property var resolveConditionIconFn: null

    // FullView overrides this from the popup height.
    implicitHeight: 360

    // ── Period state (persisted in Plasmoid.configuration) ────────────────
    property string preset: "last30"
    property string customStart: ""
    property string customEnd: ""

    // Newest selectable day; refreshed on every load so a popup left open
    // across midnight does not keep requesting the old range.
    property string _latest: H.latestAvailable()
    // How many steps the "<" arrow has moved a preset back in time (0 = the
    // preset as is). "single" / "custom" are stepped by editing their dates.
    property int _offset: 0
    readonly property var _period: H.resolvePeriod(preset, customStart, customEnd, _latest, _offset)

    // ── Data state ────────────────────────────────────────────────────────
    property string status: "idle"          // idle | loading | ok | error
    property var days: []
    property var summary: null
    property int missingDays: 0
    property int errorStatus: 0
    property string errorText: ""
    property string _loadedKey: ""
    property double _loadedAt: 0
    property int _gen: 0
    property var _handle: null
    property var _timesHandle: null

    readonly property bool _hasLocation: !!weatherRoot && weatherRoot.hasSelectedTown === true
    // Re-fetch when the active location changes while the tab is alive.
    readonly property string _locKey: _hasLocation ? (weatherRoot._locLat() + "," + weatherRoot._locLon()) : ""

    readonly property var _rows: days.slice().reverse()
    readonly property var _tiles: _buildTiles(summary)

    // ── Helpers ───────────────────────────────────────────────────────────
    function _f(px, bold) {
        return weatherRoot ? weatherRoot.wf(px, bold) : Qt.font({
            pixelSize: px,
            bold: !!bold
        });
    }
    function _isNum(v) {
        return typeof v === "number" && isFinite(v);
    }
    function _temp(c) {
        return _isNum(c) && weatherRoot ? weatherRoot.tempValue(c) : "--";
    }
    function _wind(kmh) {
        return _isNum(kmh) && weatherRoot ? weatherRoot.windValue(kmh) : "--";
    }
    function _precip(mm) {
        return _isNum(mm) && weatherRoot ? weatherRoot.precipSumText(mm) : "--";
    }
    function _snow(cm) {
        return _isNum(cm) && weatherRoot ? weatherRoot.snowDepthText(cm) : "--";
    }
    function _pressure(hpa) {
        return _isNum(hpa) && weatherRoot ? weatherRoot.pressureValue(hpa) : "--";
    }
    function _percent(v) {
        return _isNum(v) ? Math.round(v) + "%" : "--";
    }
    function _hours(h) {
        return _isNum(h) ? h.toFixed(1) + " " + i18n("h") : "--";
    }
    // ── Dates and times: Appearance → Misc → Date and Time ────────────────
    // Same effective values as ConfigMiscTab: the display* keys are empty
    // until chosen, and the older header-only keys are the fallback, so an
    // existing setting carries over. Read through Plasmoid.configuration, so
    // everything below updates as soon as the setting changes.
    readonly property string _dateFmt: Plasmoid.configuration.displayDateFormat || Plasmoid.configuration.headerDateFormat || "locale-long"
    readonly property string _timeFmt: Plasmoid.configuration.displayTimeFormat || Plasmoid.configuration.headerTimeFormat || "locale"

    function _timeFormat() {
        return _timeFmt === "locale" ? Qt.locale().timeFormat(Locale.ShortFormat) : _timeFmt;
    }

    /** "2026-10-21T07:12" -> time in the chosen format. */
    function _time(iso) {
        if (!iso || iso.length < 16)
            return "--";
        var h = parseInt(iso.substring(11, 13), 10);
        var m = parseInt(iso.substring(14, 16), 10);
        if (isNaN(h) || isNaN(m))
            return "--";
        // Built as a local date: only the clock time matters.
        return Qt.formatTime(new Date(2000, 0, 1, h, m), _timeFormat());
    }
    /** Date in the chosen format, built exactly like the widget header and
     *  the preview on the Misc page (toLocaleDateString for the two region
     *  defaults, Qt.formatDate for presets / custom formats).
     *
     *  roomy = true  : there is space (heading, daily rows) - "Region default
     *                  (long)" is shown in full, e.g. "петък, 30 октомври 2026 г.".
     *  roomy = false : tight space (tiles, buttons, ranges) - "Region default
     *                  (long)" is shortened to weekday + short date, as the
     *                  note on the Misc page says; "Region default (short)"
     *                  is the plain short date.
     *  Every other format is shown exactly as chosen, in both cases. */
    function _fmtDate(d, roomy, longName) {
        var f = _dateFmt;
        if (f === "locale-long") {
            if (roomy === true)
                return d.toLocaleDateString(Qt.locale(), Locale.LongFormat);
            var wd = Qt.locale().dayName(d.getDay(), longName === true ? Locale.LongFormat : Locale.ShortFormat);
            return wd + ", " + d.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
        }
        if (f === "locale-short")
            return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
        return Qt.formatDate(d, f);
    }
    /** ISO date -> date in the chosen format. */
    function _date(iso, roomy) {
        return H.isIso(iso) ? _fmtDate(H.parseIso(iso), roomy === true, false) : "--";
    }
    /** ISO date -> date in the chosen format, with the weekday where the
     *  format has one (see _fmtDate). longName -> full weekday name in the
     *  shortened "Region default (long)" form. */
    function _day(iso, longName, roomy) {
        return H.isIso(iso) ? _fmtDate(H.parseIso(iso), roomy === true, longName === true) : "--";
    }
    /** Day, plus the hour when Open-Meteo's hourly data gave one, e.g. "Tue, 20.10.26, 14:00". */
    function _when(entry) {
        var d = _day(entry.date, true);
        return entry.time ? d + ", " + _time(entry.time) : d;
    }
    function _compass(deg) {
        if (!_isNum(deg))
            return "";
        var names = [i18n("N"), i18n("NE"), i18n("E"), i18n("SE"), i18n("S"), i18n("SW"), i18n("W"), i18n("NW")];
        return names[Math.round(((deg % 360) + 360) % 360 / 45) % 8];
    }
    function _condition(code) {
        return _isNum(code) && weatherRoot ? weatherRoot.weatherCodeToText(code, false) : "";
    }

    // ── Icons: Appearance → Widget → Details → Icon theme ─────────────────
    // Same resolution as DetailsView / ForecastView's stat items: the
    // widgetIconTheme setting ("wi-font" is the legacy name for symbolic),
    // per-item custom icons when the theme is "kde", and the configured size.
    readonly property url iconsBaseDir: Qt.resolvedUrl("../icons/")
    readonly property string _iconTheme: {
        var t = Plasmoid.configuration.widgetIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    // Bundled SVGs only exist at 16/22/24/32 px; snap to the nearest.
    readonly property int _iconSz: {
        var want = Plasmoid.configuration.widgetIconSize || 16;
        var sizes = [16, 22, 24, 32];
        var best = sizes[0];
        for (var i = 1; i < sizes.length; ++i)
            if (Math.abs(sizes[i] - want) < Math.abs(best - want))
                best = sizes[i];
        return best;
    }
    // History rows are denser than the Details cards, so cap at 22 px.
    readonly property int _rowIconSz: Math.min(_iconSz, 22)
    readonly property var _customIcons: ConfigUtils.parseConfigMap(Plasmoid.configuration.widgetDetailsCustomIcons || "")

    function _icon(itemId, size) {
        var sz = size || _rowIconSz;
        if (_iconTheme === "kde" && itemId in _customIcons && _customIcons[itemId].length > 0)
            return {
                type: "kde",
                source: _customIcons[itemId],
                svgFallback: "",
                isMask: false
            };
        return IconResolver.resolve(itemId, sz, iconsBaseDir, _iconTheme);
    }

    function _buildTiles(s) {
        var t = [];
        if (!s || s.count === 0)
            return t;
        if (_isNum(s.avgMeanC))
            t.push({
                icon: "temperature",
                label: i18n("Average"),
                value: _temp(s.avgMeanC),
                sub: i18n("High %1 · Low %2", _temp(s.avgMaxC), _temp(s.avgMinC))
            });
        if (s.hottest)
            t.push({
                icon: "temperature",
                label: i18n("Warmest day"),
                value: _temp(s.hottest.v),
                sub: _when(s.hottest)
            });
        if (s.coldest)
            t.push({
                icon: "temperature",
                label: i18n("Coldest night"),
                value: _temp(s.coldest.v),
                sub: _when(s.coldest)
            });
        if (_isNum(s.totalPrecipMm))
            t.push({
                icon: "precipsum",
                label: i18n("Precipitation"),
                value: _precip(s.totalPrecipMm),
                sub: i18np("%1 wet day", "%1 wet days", s.wetDays)
            });
        if (s.wettest && s.wettest.v > 0)
            t.push({
                icon: "umbrella",
                label: i18n("Wettest day"),
                value: _precip(s.wettest.v),
                sub: _day(s.wettest.date, true)
            });
        if (_isNum(s.totalSnowCm) && s.totalSnowCm > 0)
            t.push({
                icon: "snowcover",
                label: i18n("Snowfall"),
                value: _snow(s.totalSnowCm),
                sub: i18np("%1 snowy day", "%1 snowy days", s.snowDays)
            });
        if (s.maxWind)
            t.push({
                icon: "wind",
                label: i18n("Strongest wind"),
                value: _wind(s.maxWind.v),
                sub: _when(s.maxWind)
            });
        if (s.maxGust)
            t.push({
                icon: "wind",
                label: i18n("Strongest gust"),
                value: _wind(s.maxGust.v),
                sub: _when(s.maxGust)
            });
        if (_isNum(s.totalSunshineHours))
            t.push({
                icon: "suntimes",
                label: i18n("Sunshine"),
                value: _hours(s.totalSunshineHours),
                sub: i18n("%1 per day", _hours(s.totalSunshineHours / s.count))
            });
        if (_isNum(s.avgHumidity))
            t.push({
                icon: "humidity",
                label: i18n("Humidity"),
                value: _percent(s.avgHumidity),
                sub: i18n("average")
            });
        if (_isNum(s.avgPressureHpa))
            t.push({
                icon: "pressure",
                label: i18n("Pressure"),
                value: _pressure(s.avgPressureHpa),
                sub: i18n("average")
            });
        if (_isNum(s.avgCloudPercent))
            t.push({
                icon: "condition",
                label: i18n("Cloud cover"),
                value: _percent(s.avgCloudPercent),
                sub: i18n("average")
            });
        return t;
    }

    function _detailPairs(d) {
        var p = [];
        if (_isNum(d.meanC))
            p.push([i18n("Mean temperature"), _temp(d.meanC), "temperature"]);
        if (_isNum(d.apparentMaxC) || _isNum(d.apparentMinC))
            p.push([i18n("Feels like"), _temp(d.apparentMaxC) + " / " + _temp(d.apparentMinC), "feelslike"]);
        if (_isNum(d.rainMm))
            p.push([i18n("Rain"), _precip(d.rainMm), "precipsum"]);
        if (_isNum(d.snowCm) && d.snowCm > 0)
            p.push([i18n("Snowfall"), _snow(d.snowCm), "snowcover"]);
        if (_isNum(d.precipHours))
            p.push([i18n("Precipitation hours"), Math.round(d.precipHours) + " " + i18n("h"), "umbrella"]);
        if (_isNum(d.windKmh))
            p.push([i18n("Wind"), (_wind(d.windKmh) + " " + _compass(d.windDir)).trim(), "wind"]);
        if (_isNum(d.gustKmh))
            p.push([i18n("Gusts"), _wind(d.gustKmh), "wind"]);
        if (_isNum(d.sunshineSec))
            p.push([i18n("Sunshine"), _hours(d.sunshineSec / 3600), "suntimes"]);
        if (_isNum(d.cloudPercent))
            p.push([i18n("Cloud cover"), _percent(d.cloudPercent), "condition"]);
        if (_isNum(d.humidity))
            p.push([i18n("Humidity"), _percent(d.humidity), "humidity"]);
        if (_isNum(d.pressureHpa))
            p.push([i18n("Pressure"), _pressure(d.pressureHpa), "pressure"]);
        if (d.sunrise)
            p.push([i18n("Sunrise"), _time(d.sunrise), "sunrise"]);
        if (d.sunset)
            p.push([i18n("Sunset"), _time(d.sunset), "sunset"]);
        return p;
    }

    readonly property var _presetModel: [
        {
            value: "yesterday",
            label: i18n("Yesterday")
        },
        {
            value: "last7",
            label: i18n("Last 7 days")
        },
        {
            value: "last30",
            label: i18n("Last 30 days")
        },
        {
            value: "last90",
            label: i18n("Last 90 days")
        },
        {
            value: "thisMonth",
            label: i18n("This month")
        },
        {
            value: "lastMonth",
            label: i18n("Last month")
        },
        {
            value: "thisYear",
            label: i18n("This year")
        },
        {
            value: "single",
            label: i18n("Single day…")
        },
        {
            value: "custom",
            label: i18n("Custom range…")
        }
    ]

    // ── Persistence ───────────────────────────────────────────────────────
    function _restoreConfig() {
        var p = Plasmoid.configuration.historyPeriod || "last30";
        var known = false;
        for (var i = 0; i < _presetModel.length; ++i)
            if (_presetModel[i].value === p) {
                known = true;
                break;
            }
        preset = known ? p : "last30";
        var s = Plasmoid.configuration.historyStartDate || "";
        var e = Plasmoid.configuration.historyEndDate || "";
        customStart = H.isIso(s) ? s : "";
        customEnd = H.isIso(e) ? e : "";
    }
    function _persist() {
        Plasmoid.configuration.historyPeriod = preset;
        Plasmoid.configuration.historyStartDate = customStart;
        Plasmoid.configuration.historyEndDate = customEnd;
    }

    function _setPreset(value) {
        if ((value === "single" || value === "custom") && preset !== "single" && preset !== "custom") {
            // Seed the dates from what is currently shown so the picker
            // opens on something meaningful.
            var p = _period;
            customStart = p.start;
            customEnd = value === "single" ? p.start : p.end;
        }
        _offset = 0;
        if (value === "custom" && !H.isIso(customEnd))
            customEnd = _latest;
        preset = value;
        _persist();
        _reloadTimer.restart();
    }

    function _applyPickedDate(iso) {
        if (datePopup.target === "end") {
            customEnd = iso;
        } else {
            customStart = iso;
            if (preset === "custom" && (!H.isIso(customEnd) || customEnd < iso))
                customEnd = iso;
        }
        _persist();
        datePopup.close();
        _reloadTimer.restart();
    }

    // ── Period navigation (< and > beside the preset box) ─────────────────
    readonly property bool _isPicked: preset === "single" || preset === "custom"
    readonly property bool _canGoOlder: _period.start > H.EARLIEST_DATE
    // Nothing is newer than the latest complete day (yesterday).
    readonly property bool _canGoNewer: _isPicked ? _period.end < _latest : _offset > 0

    /** dir < 0: one period older, dir > 0: one period newer. */
    function _navigate(dir) {
        if (dir < 0 ? !_canGoOlder : !_canGoNewer)
            return;
        if (_isPicked) {
            var r = H.shiftRange(_period.start, _period.end, dir, _latest);
            customStart = r.start;
            customEnd = r.end;
            _persist();
        } else {
            _offset = Math.max(0, _offset - dir);
        }
        _reloadTimer.restart();
    }

    function _stepTip(dir) {
        var day = preset === "yesterday" || preset === "single";
        if (dir < 0)
            return day ? i18n("Previous day") : i18n("Previous period");
        return day ? i18n("Next day") : i18n("Next period");
    }

    // ── Loading ───────────────────────────────────────────────────────────
    function _abortPending() {
        if (_handle) {
            _handle.abort();
            _handle = null;
        }
        if (_timesHandle) {
            _timesHandle.abort();
            _timesHandle = null;
        }
    }

    /** Second step after the daily data: the hour of the warmest / coldest /
     *  windiest moments (see openMeteoHistory.js). Tiles first show just the
     *  date and gain the time when this arrives; if it fails they stay as is. */
    function _loadTimes(summary, gen, opts) {
        _timesHandle = H.fetchExtremeTimes(opts, summary, function (withTimes) {
            if (gen !== root._gen)
                return;
            root._timesHandle = null;
            root.summary = withTimes;
        });
    }

    function load(force) {
        _latest = H.latestAvailable();
        if (!_hasLocation) {
            _abortPending();
            _gen++;
            status = "idle";
            return;
        }
        var p = H.resolvePeriod(preset, customStart, customEnd, _latest, _offset);
        var lat = weatherRoot._locLat();
        var lon = weatherRoot._locLon();
        var key = lat + "|" + lon + "|" + p.start + "|" + p.end;
        if (!force && key === _loadedKey && status === "ok")
            return;

        _abortPending();
        var my = ++_gen;
        status = "loading";
        _handle = H.fetchHistory({
            latitude: lat,
            longitude: lon,
            timezone: weatherRoot._activeLocTz || "",
            start: p.start,
            end: p.end,
            force: force === true
        }, function (err, res) {
            if (my !== root._gen)
                return;                      // superseded or aborted
            root._handle = null;
            if (err || !res) {
                root.errorStatus = err ? err.status : 0;
                root.errorText = err ? err.message : "";
                root.days = [];
                root.summary = null;
                root.status = "error";
                return;
            }
            list.rememberScroll();           // keep the page where the user left it
            root.days = res.days;
            root.summary = res.summary;
            root.missingDays = res.missingDays;
            root._loadedKey = key;
            root._loadedAt = Date.now();
            root.status = "ok";
            root._loadTimes(res.summary, my, {
                latitude: lat,
                longitude: lon,
                timezone: weatherRoot._activeLocTz || "",
                start: p.start,
                end: p.end
            });
            Qt.callLater(list.restoreScroll);
        });
    }

    /** Refresh button / retry. */
    function reload() {
        load(true);
    }
    /** Called when the tab is shown again: refetch if the range, place or day changed, or data is old. */
    function reloadIfStale() {
        if (status === "loading")
            return;
        if (status !== "ok" || Date.now() - _loadedAt > 30 * 60 * 1000)
            load(true);
        else
            load(false);
    }

    Timer {
        id: _reloadTimer
        interval: 250
        repeat: false
        onTriggered: root.load(false)
    }

    on_LocKeyChanged: {
        if (_hasLocation)
            _reloadTimer.restart();
    }

    Component.onCompleted: {
        _restoreConfig();
        load(false);
    }
    Component.onDestruction: {
        _gen++;
        _abortPending();
    }

    // Chart implementation (see header comment): Qt Graphs first, KQuickCharts
    // when the Qt Graphs module could not be loaded. The flags turn false when
    // the Loader reports an error for that chart.
    property bool _graphsOk: true
    property bool _kqcOk: true
    readonly property string _chartSource: _graphsOk ? "components/HistoryChartGraphs.qml" : (_kqcOk ? "components/HistoryChartKQC.qml" : "")

    // ══════════════════════════════════════════════════════════════════════
    // UI
    // ══════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── Period controls:  <  ……  [ preset ▾ ] [ date ] [ date ]  ……  > ──
        // The arrows sit at the two ends of the widget; the preset box and,
        // for "single day" / "custom range", the date buttons are centred.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ToolButton {
                id: olderButton
                icon.name: "go-previous"
                display: AbstractButton.IconOnly
                enabled: root._canGoOlder
                onClicked: root._navigate(-1)
                ToolTip.visible: hovered
                ToolTip.text: root._stepTip(-1)
                Accessible.name: root._stepTip(-1)
            }

            Item {
                Layout.fillWidth: true
            }

            ComboBox {
                id: presetBox
                Layout.preferredWidth: 170
                model: root._presetModel
                textRole: "label"
                valueRole: "value"
                currentIndex: {
                    for (var i = 0; i < root._presetModel.length; ++i)
                        if (root._presetModel[i].value === root.preset)
                            return i;
                    return 2;
                }
                // Stepped back from "Yesterday" with <: show which day it is.
                displayText: (root.preset === "yesterday" && root._offset > 0) ? root._day(root._period.start, true) : currentText
                font: root._f(11, false)
                onActivated: function (idx) {
                    root._setPreset(root._presetModel[idx].value);
                }
            }

            Button {
                id: startButton
                visible: root._isPicked
                icon.name: "view-calendar"
                text: root._date(root._period.start)
                font: root._f(11, false)
                ToolTip.visible: hovered
                ToolTip.text: root.preset === "single" ? i18n("Choose the day") : i18n("Start date")
                onClicked: {
                    datePopup.target = "start";
                    datePopup.open();
                }
            }
            Label {
                visible: root.preset === "custom"
                text: "–"
                color: Kirigami.Theme.textColor
                font: root._f(11, false)
            }
            Button {
                id: endButton
                visible: root.preset === "custom"
                icon.name: "view-calendar"
                text: root._date(root._period.end)
                font: root._f(11, false)
                ToolTip.visible: hovered
                ToolTip.text: i18n("End date")
                onClicked: {
                    datePopup.target = "end";
                    datePopup.open();
                }
            }

            Item {
                Layout.fillWidth: true
            }

            ToolButton {
                id: newerButton
                icon.name: "go-next"
                display: AbstractButton.IconOnly
                enabled: root._canGoNewer
                onClicked: root._navigate(1)
                ToolTip.visible: hovered
                ToolTip.text: root._stepTip(1)
                Accessible.name: root._stepTip(1)
            }
        }

        // ── Location name · selected date / period, centred ───────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root._hasLocation
            spacing: 0

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                color: Kirigami.Theme.textColor
                font: root._f(11, false)
                text: {
                    var p = root._period;
                    // The heading has room for the long region format (it elides
                    // if a very wide range does not fit).
                    var range = p.start === p.end ? root._day(p.start, false, true) : root._day(p.start, true, true) + " – " + root._day(p.end, true, true);
                    var place = root.weatherRoot ? String(root.weatherRoot._locName()) : "";
                    if (place.length === 0)
                        return range;
                    place = place.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                    return "<b>" + place + "</b> · " + range;
                }
            }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                opacity: 0.55
                font: root._f(9, false)
                text: {
                    var notes = [];
                    if (root._period.clamped)
                        notes.push(i18n("Range limited to %1 days", H.MAX_RANGE_DAYS));
                    if (root.status === "ok" && root.missingDays > 0)
                        notes.push(i18np("%1 day has no data yet", "%1 days have no data yet", root.missingDays));
                    return notes.join(" · ");
                }
            }
        }

        // ── Content ───────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // No location
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: !root._hasLocation
                text: i18n("Select a location to see its weather history")
                icon.name: "mark-location"
            }

            // Loading (first load only; later loads keep the old data visible)
            BusyIndicator {
                anchors.centerIn: parent
                visible: root._hasLocation && root.status === "loading" && root.days.length === 0
                running: visible
            }

            // Error
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: root._hasLocation && root.status === "error"
                icon.name: "dialog-warning"
                text: {
                    if (root.errorStatus === 0)
                        return i18n("Could not reach Open-Meteo. Check your connection and try again.");
                    if (root.errorStatus === 429)
                        return i18n("Open-Meteo is rate limiting requests. Please try again in a little while.");
                    if (root.errorText.length > 0)
                        return root.errorText;
                    return i18n("Weather history is unavailable (HTTP %1).", root.errorStatus);
                }
                helpfulAction: Kirigami.Action {
                    icon.name: "view-refresh"
                    text: i18n("Try again")
                    onTriggered: root.reload()
                }
            }

            // No usable data in the range
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: root._hasLocation && root.status === "ok" && !!root.summary && root.summary.count === 0
                icon.name: "weather-none-available"
                text: i18n("No data is available for this period yet. The most recent days can take up to about five days to appear.")
            }

            ListView {
                id: list
                anchors.fill: parent
                visible: root._hasLocation && root.days.length > 0 && !!root.summary && root.summary.count > 0
                clip: true
                spacing: 4
                model: root._rows
                boundsBehavior: Flickable.StopAtBounds
                // Dim while a refresh is running behind the old data.
                opacity: root.status === "loading" ? 0.5 : 1.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                // New data replaces the model, which makes a ListView jump to
                // the top. Changing the period (dropdown, < / >) should leave
                // the page where it is, so the scroll offset is remembered
                // across the swap and put back (the header may change height
                // a moment later, hence the short window).
                property real _keepOffset: -1
                function rememberScroll() {
                    _keepOffset = (visible && contentHeight > height) ? contentY - originY : -1;
                    if (_keepOffset >= 0)
                        _keepTimer.restart();
                }
                function restoreScroll() {
                    if (_keepOffset < 0)
                        return;
                    contentY = originY + Math.max(0, Math.min(_keepOffset, contentHeight - height));
                }
                onContentHeightChanged: {
                    if (_keepOffset >= 0)
                        Qt.callLater(restoreScroll);
                }
                Timer {
                    id: _keepTimer
                    interval: 400
                    onTriggered: list._keepOffset = -1
                }

                // ── Summary + chart ───────────────────────────────────
                header: Item {
                    width: list.width
                    height: headerColumn.implicitHeight + 10
                    // The header grows when the data arrives; without this the
                    // view keeps its old scroll offset and shows only the bottom
                    // of it.
                    onHeightChanged: {
                        if (list._keepOffset >= 0)
                            Qt.callLater(list.restoreScroll);
                        else
                            Qt.callLater(list.positionViewAtBeginning);
                    }

                    ColumnLayout {
                        id: headerColumn
                        width: parent.width - 10
                        spacing: 8

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            rowSpacing: 6
                            columnSpacing: 6

                            Repeater {
                                model: root._tiles
                                delegate: Rectangle {
                                    id: tile
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 100
                                    Layout.preferredHeight: tileCol.implicitHeight + 10
                                    radius: 8
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)

                                    ColumnLayout {
                                        id: tileCol
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            leftMargin: 8
                                            rightMargin: 8
                                        }
                                        spacing: 0
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            WeatherIcon {
                                                iconInfo: root._icon(tile.modelData.icon)
                                                iconSize: root._rowIconSz
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: tile.modelData.label
                                                elide: Text.ElideRight
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.6
                                                font: root._f(9, false)
                                            }
                                        }
                                        // <value> (details): on one line, wrapping the
                                        // details below the value only if they do not fit
                                        Flow {
                                            id: tileValueLine
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Label {
                                                text: tile.modelData.value
                                                color: Kirigami.Theme.textColor
                                                font: root._f(13, true)
                                            }
                                            Label {
                                                width: Math.min(implicitWidth, tileValueLine.width)
                                                text: "(" + tile.modelData.sub + ")"
                                                elide: Text.ElideRight
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.6
                                                font: root._f(9, false)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Zoom toolbar: the days in view while zoomed, then - / + / restore.
                        // The chart owns the zoom state; zooming in makes it
                        // wider than the popup and scrolls sideways.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: root.days.length > 3
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: Kirigami.Theme.textColor
                                opacity: 0.7
                                font: root._f(9, false)
                                text: {
                                    var c = chartLoader.item;
                                    if (c && c.canZoomIn === true && c.zoomed !== true)
                                        return i18n("Tip: double-click the graph, or hold Ctrl and scroll the mouse wheel, to zoom in");
                                    if (!c || c.zoomed !== true || root.days.length === 0)
                                        return "";
                                    var a = root.days[Math.min(c.visibleFirst, root.days.length - 1)];
                                    var b = root.days[Math.min(c.visibleLast, root.days.length - 1)];
                                    return root._date(a.dateStr) + " – " + root._date(b.dateStr);
                                }
                            }
                            ToolButton {
                                icon.name: "zoom-out"
                                display: AbstractButton.IconOnly
                                enabled: !!chartLoader.item && chartLoader.item.zoomed === true
                                onClicked: chartLoader.item.zoomOut()
                                ToolTip.visible: hovered
                                ToolTip.text: i18n("Zoom out")
                                Accessible.name: i18n("Zoom out")
                            }
                            ToolButton {
                                icon.name: "zoom-in"
                                display: AbstractButton.IconOnly
                                enabled: !!chartLoader.item && chartLoader.item.canZoomIn === true
                                onClicked: chartLoader.item.zoomIn()
                                ToolTip.visible: hovered
                                ToolTip.text: i18n("Zoom in (or double-click the graph, or hold Ctrl and scroll the mouse wheel)")
                                Accessible.name: i18n("Zoom in")
                            }
                            ToolButton {
                                icon.name: "zoom-original"
                                display: AbstractButton.IconOnly
                                enabled: !!chartLoader.item && chartLoader.item.zoomed === true
                                onClicked: chartLoader.item.resetZoom()
                                ToolTip.visible: hovered
                                ToolTip.text: i18n("Restore")
                                Accessible.name: i18n("Restore")
                            }
                        }

                        // Chart: Qt Graphs (KDE weather applet style); KQuickCharts
                        // when Qt Graphs is not available.
                        Loader {
                            id: chartLoader
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: root.days.length > 1 && root._chartSource !== ""
                            source: root._chartSource
                            onLoaded: {
                                item.view = root;
                                item.outerFlickable = list;
                                item.days = Qt.binding(function () {
                                    return root.days;
                                });
                            }
                            onStatusChanged: {
                                // Switching the source from inside its own status change
                                // would be a binding loop, so do it a moment later.
                                if (status !== Loader.Error)
                                    return;
                                if (root._graphsOk) {
                                    console.warn("History: Qt Graphs chart unavailable, using KDE Quick Charts");
                                    Qt.callLater(function () {
                                        root._graphsOk = false;
                                    });
                                } else if (root._kqcOk) {
                                    console.warn("History: KDE Quick Charts (org.kde.quickcharts) unavailable, no chart");
                                    Qt.callLater(function () {
                                        root._kqcOk = false;
                                    });
                                }
                            }
                        }

                        // Neither chart module could be loaded
                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: root.days.length > 1 && root._chartSource === ""
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            font: root._f(9, false)
                            text: i18n("The chart needs the Qt Graphs or the KDE Quick Charts QML module.")
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            text: i18n("Daily details")
                            color: Kirigami.Theme.textColor
                            font: root._f(11, true)
                        }
                    }
                }

                // ── Daily rows ────────────────────────────────────────
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    property bool open: false

                    width: list.width - 10
                    height: rowColumn.implicitHeight + 12
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, open ? 0.11 : 0.05)
                    Behavior on height {
                        NumberAnimation {
                            duration: 120
                        }
                    }
                    clip: true

                    readonly property var _icon: (modelData.hasData && root._isNum(modelData.code) && root.resolveConditionIconFn) ? root.resolveConditionIconFn(modelData.code, false, 26) : null

                    ColumnLayout {
                        id: rowColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 8
                            topMargin: 6
                        }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Item {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                WeatherIcon {
                                    anchors.centerIn: parent
                                    visible: row._icon !== null
                                    iconInfo: row._icon
                                    iconSize: 26
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 120
                                spacing: 0
                                Label {
                                    Layout.fillWidth: true
                                    text: root._day(row.modelData.dateStr, true, true)
                                    elide: Text.ElideRight
                                    color: Kirigami.Theme.textColor
                                    font: root._f(11, true)
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: row.modelData.hasData ? root._condition(row.modelData.code) : i18n("No data yet")
                                    elide: Text.ElideRight
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.6
                                    font: root._f(9, false)
                                }
                            }

                            Label {
                                visible: row.modelData.hasData
                                text: root._temp(row.modelData.maxC) + " / " + root._temp(row.modelData.minC)
                                color: Kirigami.Theme.textColor
                                font: root._f(11, false)
                            }
                            Label {
                                visible: row.modelData.hasData
                                Layout.preferredWidth: 64
                                horizontalAlignment: Text.AlignRight
                                text: root._precip(row.modelData.precipMm)
                                color: root._isNum(row.modelData.precipMm) && row.modelData.precipMm >= H.WET_DAY_MM ? "#42a5f5" : Kirigami.Theme.textColor
                                opacity: root._isNum(row.modelData.precipMm) && row.modelData.precipMm > 0 ? 1.0 : 0.5
                                font: root._f(10, false)
                            }
                            Kirigami.Icon {
                                visible: row.modelData.hasData
                                source: row.open ? "go-up" : "go-down"
                                Layout.preferredWidth: 14
                                Layout.preferredHeight: 14
                                opacity: 0.5
                            }
                        }

                        // Expanded detail grid
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 2
                            visible: row.open && row.modelData.hasData
                            columns: 4
                            columnSpacing: 10
                            rowSpacing: 3

                            Repeater {
                                model: row.open ? root._detailPairs(row.modelData) : []
                                delegate: Item {
                                    id: pair
                                    required property var modelData
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 100
                                    Layout.preferredHeight: Math.max(16, pairLabel.implicitHeight, pairValue.implicitHeight)
                                    WeatherIcon {
                                        id: pairIcon
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        iconInfo: root._icon(pair.modelData[2], 16)
                                        iconSize: 16
                                    }
                                    Label {
                                        id: pairLabel
                                        anchors.left: pairIcon.right
                                        anchors.leftMargin: 6
                                        anchors.right: pairValue.left
                                        anchors.rightMargin: 6
                                        text: pair.modelData[0]
                                        elide: Text.ElideRight
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.6
                                        font: root._f(9, false)
                                    }
                                    Label {
                                        id: pairValue
                                        anchors.right: parent.right
                                        text: pair.modelData[1]
                                        color: Kirigami.Theme.textColor
                                        font: root._f(10, false)
                                    }
                                }
                            }
                        }
                    }

                    TapHandler {
                        enabled: row.modelData.hasData
                        onTapped: row.open = !row.open
                    }
                    HoverHandler {
                        cursorShape: row.modelData.hasData ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }

                // Footnote
                footer: Label {
                    width: list.width - 10
                    topPadding: 8
                    bottomPadding: 4
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: i18n("Historical values are reanalysis data on a roughly 10 km grid, so they can differ from nearby station readings.")
                    color: Kirigami.Theme.textColor
                    opacity: 0.5
                    font: root._f(8, false)
                }
            }
        }
    }

    // ── Date picker popup ─────────────────────────────────────────────────
    Popup {
        id: datePopup
        property string target: "start"      // "start" | "end"

        anchors.centerIn: Overlay.overlay
        modal: true
        dim: false
        padding: 10
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        width: 300

        onAboutToShow: {
            var sel = target === "end" ? root._period.end : root._period.start;
            datePicker.selectedDate = sel;
            datePicker.minDate = (target === "end" && root.preset === "custom") ? root._period.start : H.EARLIEST_DATE;
            datePicker.maxDate = root._latest;
            datePicker.showMonthOf(sel);
        }

        contentItem: ColumnLayout {
            spacing: 6
            Label {
                Layout.fillWidth: true
                text: root.preset === "single" ? i18n("Select day") : (datePopup.target === "end" ? i18n("Select end date") : i18n("Select start date"))
                color: Kirigami.Theme.textColor
                font: root._f(11, true)
            }
            HistoryDatePicker {
                id: datePicker
                Layout.fillWidth: true
                rangeStart: root.preset === "custom" ? root._period.start : ""
                rangeEnd: root.preset === "custom" ? root._period.end : ""
                onPicked: function (iso) {
                    root._applyPickedDate(iso);
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Data is available from %1 until yesterday.", root._date(H.EARLIEST_DATE))
                color: Kirigami.Theme.textColor
                opacity: 0.55
                font: root._f(9, false)
            }
            Label {
                Layout.fillWidth: true
                visible: root.preset === "custom"
                wrapMode: Text.WordWrap
                // Example: a start date of 1 Jan 2015 gives an end date of 1 Jan 2016.
                text: i18n("Range limited to %1 days: if the chosen range is longer, the end date is set automatically (for example, start date %2 gives end date %3).", H.MAX_RANGE_DAYS, root._date("2015-01-01"), root._date(H.addDays("2015-01-01", H.MAX_RANGE_DAYS - 1)))
                color: Kirigami.Theme.textColor
                opacity: 0.55
                font: root._f(9, false)
            }
        }
    }
}
