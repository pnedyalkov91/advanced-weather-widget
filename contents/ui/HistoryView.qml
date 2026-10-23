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
 * HistoryView.qml - "History" tab: past weather for the active location from
 * the Open-Meteo Historical Weather API.
 *
 *   • Period picker: presets (yesterday … this year), a single day, or a
 *     custom range (HistoryDatePicker).
 *   • Summary tiles, a temperature-range + precipitation chart (hover for
 *     the day's values) and an expandable newest-first daily list.
 *
 * All requests/parsing live in providers/openMeteoHistory.js; unit
 * conversion and fonts go through weatherRoot like every other tab, so the
 * user's unit settings are honoured.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "providers/openMeteoHistory.js" as H
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
    readonly property var _period: H.resolvePeriod(preset, customStart, customEnd, _latest)
    readonly property bool _sameYear: _period.start.substring(0, 4) === _period.end.substring(0, 4)

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

    readonly property bool _hasLocation: !!weatherRoot && weatherRoot.hasSelectedTown === true
    // Re-fetch when the active location changes while the tab is alive.
    readonly property string _locKey: _hasLocation ? (weatherRoot._locLat() + "," + weatherRoot._locLon()) : ""

    readonly property var _rows: days.slice().reverse()
    readonly property var _tiles: _buildTiles(summary)

    // ── Helpers ───────────────────────────────────────────────────────────
    function _f(px, bold) {
        return weatherRoot ? weatherRoot.wf(px, bold) : Qt.font({ pixelSize: px, bold: !!bold });
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
    function _time(iso) {
        // "2026-10-21T07:12" -> locale short time
        if (!iso || iso.length < 16 || !weatherRoot)
            return "--";
        return weatherRoot.formatTimeForDisplay(iso.substring(11, 16));
    }
    function _day(iso, withYear) {
        return Qt.formatDate(H.parseIso(iso), withYear ? "ddd, d MMM yyyy" : "ddd, d MMM");
    }
    function _date(iso) {
        return H.isIso(iso) ? Qt.formatDate(H.parseIso(iso), "d MMM yyyy") : "--";
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

    function _buildTiles(s) {
        var t = [];
        if (!s || s.count === 0)
            return t;
        if (_isNum(s.avgMeanC))
            t.push({ label: i18n("Average"), value: _temp(s.avgMeanC),
                     sub: i18n("High %1 · Low %2", _temp(s.avgMaxC), _temp(s.avgMinC)) });
        if (s.hottest)
            t.push({ label: i18n("Warmest day"), value: _temp(s.hottest.v), sub: _day(s.hottest.date, false) });
        if (s.coldest)
            t.push({ label: i18n("Coldest night"), value: _temp(s.coldest.v), sub: _day(s.coldest.date, false) });
        if (_isNum(s.totalPrecipMm))
            t.push({ label: i18n("Precipitation"), value: _precip(s.totalPrecipMm),
                     sub: i18np("%1 wet day", "%1 wet days", s.wetDays) });
        if (s.wettest && s.wettest.v > 0)
            t.push({ label: i18n("Wettest day"), value: _precip(s.wettest.v), sub: _day(s.wettest.date, false) });
        if (_isNum(s.totalSnowCm) && s.totalSnowCm > 0)
            t.push({ label: i18n("Snowfall"), value: _snow(s.totalSnowCm),
                     sub: i18np("%1 snowy day", "%1 snowy days", s.snowDays) });
        if (s.maxWind)
            t.push({ label: i18n("Strongest wind"), value: _wind(s.maxWind.v), sub: _day(s.maxWind.date, false) });
        if (s.maxGust)
            t.push({ label: i18n("Strongest gust"), value: _wind(s.maxGust.v), sub: _day(s.maxGust.date, false) });
        if (_isNum(s.totalSunshineHours))
            t.push({ label: i18n("Sunshine"), value: _hours(s.totalSunshineHours),
                     sub: i18n("%1 per day", _hours(s.totalSunshineHours / s.count)) });
        if (_isNum(s.avgHumidity))
            t.push({ label: i18n("Humidity"), value: _percent(s.avgHumidity), sub: i18n("average") });
        if (_isNum(s.avgPressureHpa))
            t.push({ label: i18n("Pressure"), value: _pressure(s.avgPressureHpa), sub: i18n("average") });
        if (_isNum(s.avgCloudPercent))
            t.push({ label: i18n("Cloud cover"), value: _percent(s.avgCloudPercent), sub: i18n("average") });
        return t;
    }

    function _detailPairs(d) {
        var p = [];
        if (_isNum(d.meanC))
            p.push([i18n("Mean temperature"), _temp(d.meanC)]);
        if (_isNum(d.apparentMaxC) || _isNum(d.apparentMinC))
            p.push([i18n("Feels like"), _temp(d.apparentMaxC) + " / " + _temp(d.apparentMinC)]);
        if (_isNum(d.rainMm))
            p.push([i18n("Rain"), _precip(d.rainMm)]);
        if (_isNum(d.snowCm) && d.snowCm > 0)
            p.push([i18n("Snowfall"), _snow(d.snowCm)]);
        if (_isNum(d.precipHours))
            p.push([i18n("Precipitation hours"), Math.round(d.precipHours) + " " + i18n("h")]);
        if (_isNum(d.windKmh))
            p.push([i18n("Wind"), (_wind(d.windKmh) + " " + _compass(d.windDir)).trim()]);
        if (_isNum(d.gustKmh))
            p.push([i18n("Gusts"), _wind(d.gustKmh)]);
        if (_isNum(d.sunshineSec))
            p.push([i18n("Sunshine"), _hours(d.sunshineSec / 3600)]);
        if (_isNum(d.cloudPercent))
            p.push([i18n("Cloud cover"), _percent(d.cloudPercent)]);
        if (_isNum(d.humidity))
            p.push([i18n("Humidity"), _percent(d.humidity)]);
        if (_isNum(d.pressureHpa))
            p.push([i18n("Pressure"), _pressure(d.pressureHpa)]);
        if (d.sunrise)
            p.push([i18n("Sunrise"), _time(d.sunrise)]);
        if (d.sunset)
            p.push([i18n("Sunset"), _time(d.sunset)]);
        return p;
    }

    readonly property var _presetModel: [
        { value: "yesterday",  label: i18n("Yesterday") },
        { value: "last7",      label: i18n("Last 7 days") },
        { value: "last30",     label: i18n("Last 30 days") },
        { value: "last90",     label: i18n("Last 90 days") },
        { value: "thisMonth",  label: i18n("This month") },
        { value: "lastMonth",  label: i18n("Last month") },
        { value: "thisYear",   label: i18n("This year") },
        { value: "single",     label: i18n("Single day…") },
        { value: "custom",     label: i18n("Custom range…") }
    ]

    // ── Persistence ───────────────────────────────────────────────────────
    function _restoreConfig() {
        var p = Plasmoid.configuration.historyPeriod || "last30";
        var known = false;
        for (var i = 0; i < _presetModel.length; ++i)
            if (_presetModel[i].value === p) { known = true; break; }
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

    // ── Loading ───────────────────────────────────────────────────────────
    function _abortPending() {
        if (_handle) {
            _handle.abort();
            _handle = null;
        }
    }

    function load(force) {
        _latest = H.latestAvailable();
        if (!_hasLocation) {
            _abortPending();
            _gen++;
            status = "idle";
            return;
        }
        var p = H.resolvePeriod(preset, customStart, customEnd, _latest);
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
            root.days = res.days;
            root.summary = res.summary;
            root.missingDays = res.missingDays;
            root._loadedKey = key;
            root._loadedAt = Date.now();
            root.hoverIndex = -1;
            root.status = "ok";
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

    // ── Chart hover ───────────────────────────────────────────────────────
    property int hoverIndex: -1

    // ══════════════════════════════════════════════════════════════════════
    // UI
    // ══════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── Period controls ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

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
                font: root._f(11, false)
                onActivated: function (idx) {
                    root._setPreset(root._presetModel[idx].value);
                }
            }

            Button {
                id: startButton
                visible: root.preset === "single" || root.preset === "custom"
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

            Item { Layout.fillWidth: true }
        }

        // ── Range caption / notes ─────────────────────────────────────
        Label {
            Layout.fillWidth: true
            visible: root._hasLocation
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.textColor
            opacity: 0.7
            font: root._f(9, false)
            text: {
                var p = root._period;
                var place = root.weatherRoot ? root.weatherRoot._locName() : "";
                var range = p.start === p.end
                    ? root._day(p.start, true)
                    : root._day(p.start, true) + " – " + root._day(p.end, true);
                var t = place.length > 0 ? place + " · " + range : range;
                if (p.clamped)
                    t += " · " + i18n("Range limited to %1 days", H.MAX_RANGE_DAYS);
                if (root.status === "ok" && root.missingDays > 0)
                    t += " · " + i18np("%1 day has no data yet", "%1 days have no data yet", root.missingDays);
                return t;
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
                Behavior on opacity { NumberAnimation { duration: 120 } }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                // ── Summary + chart ───────────────────────────────────
                header: Item {
                    width: list.width
                    height: headerColumn.implicitHeight + 10
                    // The header grows when the data arrives; without this the
                    // view keeps its old scroll offset and shows only the bottom
                    // of it.
                    onHeightChanged: Qt.callLater(list.positionViewAtBeginning)

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
                                    Layout.preferredHeight: tileCol.implicitHeight + 14
                                    radius: 8
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)

                                    ColumnLayout {
                                        id: tileCol
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            margins: 8
                                        }
                                        spacing: 1
                                        Label {
                                            Layout.fillWidth: true
                                            text: tile.modelData.label
                                            elide: Text.ElideRight
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.6
                                            font: root._f(9, false)
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: tile.modelData.value
                                            elide: Text.ElideRight
                                            color: Kirigami.Theme.textColor
                                            font: root._f(13, true)
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: tile.modelData.sub
                                            elide: Text.ElideRight
                                            color: Kirigami.Theme.textColor
                                            opacity: 0.6
                                            font: root._f(9, false)
                                        }
                                    }
                                }
                            }
                        }

                        // Chart legend / hover readout
                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            elide: Text.ElideRight
                            color: Kirigami.Theme.textColor
                            font: root._f(10, root.hoverIndex >= 0)
                            visible: root.days.length > 1
                            text: {
                                var i = root.hoverIndex;
                                if (i < 0 || i >= root.days.length)
                                    return i18n("Temperature range and daily precipitation");
                                var d = root.days[i];
                                if (!d.hasData)
                                    return root._day(d.dateStr, true) + " · " + i18n("No data");
                                return root._day(d.dateStr, true) + " · "
                                    + root._temp(d.maxC) + " / " + root._temp(d.minC)
                                    + " · " + root._precip(d.precipMm);
                            }
                        }

                        Canvas {
                            id: chart
                            Layout.fillWidth: true
                            Layout.preferredHeight: 150
                            visible: root.days.length > 1
                            renderTarget: Canvas.Image

                            readonly property real tempFrac: 0.68
                            readonly property var _days: root.days
                            readonly property int _hover: root.hoverIndex

                            on_DaysChanged: requestPaint()
                            on_HoverChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()

                            readonly property color _textColor: Kirigami.Theme.textColor
                            on_TextColorChanged: requestPaint()

                            function _tc(a) {
                                var c = Kirigami.Theme.textColor;
                                return Qt.rgba(c.r, c.g, c.b, a);
                            }

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                var days = chart._days;
                                var n = days.length;
                                var cw = width, ch = height;
                                if (n < 2 || cw <= 0 || ch <= 0)
                                    return;

                                var slot = cw / n;
                                var tempH = Math.round(ch * tempFrac);
                                var precipTop = tempH + 10;
                                var precipH = ch - precipTop;

                                // Temperature scale
                                var lo = Infinity, hi = -Infinity;
                                for (var i = 0; i < n; ++i) {
                                    var d = days[i];
                                    if (isFinite(d.maxC)) { hi = Math.max(hi, d.maxC); lo = Math.min(lo, d.maxC); }
                                    if (isFinite(d.minC)) { hi = Math.max(hi, d.minC); lo = Math.min(lo, d.minC); }
                                }
                                if (!isFinite(lo) || !isFinite(hi))
                                    return;
                                if (hi - lo < 4) {
                                    var mid = (hi + lo) / 2;
                                    hi = mid + 2;
                                    lo = mid - 2;
                                }
                                var padT = 6, padB = 6;
                                var span = hi - lo;
                                function ty(v) {
                                    return padT + (hi - v) / span * (tempH - padT - padB);
                                }

                                // Hover column
                                if (chart._hover >= 0 && chart._hover < n) {
                                    ctx.fillStyle = chart._tc(0.08);
                                    ctx.fillRect(chart._hover * slot, 0, slot, ch);
                                }

                                // Freezing line
                                if (lo < 0 && hi > 0) {
                                    ctx.strokeStyle = chart._tc(0.35);
                                    ctx.lineWidth = 1;
                                    ctx.setLineDash([3, 3]);
                                    ctx.beginPath();
                                    ctx.moveTo(0, Math.round(ty(0)) + 0.5);
                                    ctx.lineTo(cw, Math.round(ty(0)) + 0.5);
                                    ctx.stroke();
                                    ctx.setLineDash([]);
                                }

                                // Range bars: colour runs hot -> cold over the plot height
                                var grad = ctx.createLinearGradient(0, padT, 0, tempH - padB);
                                grad.addColorStop(0.0, "#ef5350");
                                grad.addColorStop(1.0, "#42a5f5");
                                ctx.fillStyle = grad;
                                var bw = Math.max(1, Math.min(slot * 0.62, 14));
                                for (var j = 0; j < n; ++j) {
                                    var dj = days[j];
                                    if (!isFinite(dj.maxC) || !isFinite(dj.minC))
                                        continue;
                                    var y1 = ty(dj.maxC), y2 = ty(dj.minC);
                                    ctx.globalAlpha = 0.85;
                                    ctx.fillRect(j * slot + (slot - bw) / 2, y1, bw, Math.max(2, y2 - y1));
                                }
                                ctx.globalAlpha = 1.0;

                                // Mean line (broken at missing days)
                                ctx.strokeStyle = chart._tc(0.9);
                                ctx.lineWidth = 1.5;
                                ctx.beginPath();
                                var pen = false;
                                for (var k = 0; k < n; ++k) {
                                    var m = days[k].meanC;
                                    if (!isFinite(m)) { pen = false; continue; }
                                    var px = k * slot + slot / 2, py = ty(m);
                                    if (pen) ctx.lineTo(px, py); else ctx.moveTo(px, py);
                                    pen = true;
                                }
                                ctx.stroke();

                                // Precipitation bars
                                var pmax = 5;
                                for (var q = 0; q < n; ++q)
                                    if (isFinite(days[q].precipMm))
                                        pmax = Math.max(pmax, days[q].precipMm);
                                ctx.fillStyle = "#42a5f5";
                                for (var r = 0; r < n; ++r) {
                                    var pm = days[r].precipMm;
                                    if (!isFinite(pm) || pm <= 0)
                                        continue;
                                    var h = Math.max(1, pm / pmax * precipH);
                                    ctx.globalAlpha = 0.8;
                                    ctx.fillRect(r * slot + (slot - bw) / 2, precipTop + precipH - h, bw, h);
                                }
                                ctx.globalAlpha = 1.0;

                                // Baseline under the precipitation bars
                                ctx.strokeStyle = chart._tc(0.25);
                                ctx.lineWidth = 1;
                                ctx.beginPath();
                                ctx.moveTo(0, precipTop + precipH + 0.5);
                                ctx.lineTo(cw, precipTop + precipH + 0.5);
                                ctx.stroke();
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                onPositionChanged: function (mouse) {
                                    var n = root.days.length;
                                    if (n < 1)
                                        return;
                                    root.hoverIndex = Math.max(0, Math.min(n - 1, Math.floor(mouse.x / width * n)));
                                }
                                onExited: root.hoverIndex = -1
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.days.length > 1
                            Label {
                                text: root.days.length > 0 ? root._date(root.days[0].dateStr) : ""
                                color: Kirigami.Theme.textColor
                                opacity: 0.6
                                font: root._f(9, false)
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: root.days.length > 0 ? root._date(root.days[root.days.length - 1].dateStr) : ""
                                color: Kirigami.Theme.textColor
                                opacity: 0.6
                                font: root._f(9, false)
                            }
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
                    Behavior on height { NumberAnimation { duration: 120 } }
                    clip: true

                    readonly property var _icon: (modelData.hasData && root._isNum(modelData.code) && root.resolveConditionIconFn)
                        ? root.resolveConditionIconFn(modelData.code, false, 26) : null

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
                                    text: root._day(row.modelData.dateStr, !root._sameYear)
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
                                    Layout.preferredHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)
                                    Label {
                                        id: pairLabel
                                        anchors.left: parent.left
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
                text: root.preset === "single" ? i18n("Select day")
                    : (datePopup.target === "end" ? i18n("Select end date") : i18n("Select start date"))
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
        }
    }
}
