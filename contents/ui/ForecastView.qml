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
 * ForecastView.qml — "Forecast" tab of the main widget popup
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "js/weather.js" as W
import "js/iconResolver.js" as IconResolver
import "js/configUtils.js" as ConfigUtils
import "components"

Item {
    id: forecastRoot
    property var weatherRoot
    property var verticalScrollView
    property int expandedIndex: -1

    // ── Auto-open: expand the first available day's hourly forecast ────────
    readonly property bool autoOpen: Plasmoid.configuration.forecastAutoOpen !== false
    property bool _autoOpenDone: false

    // ── Expand-all: show hourly for every day simultaneously ───────────────
    readonly property bool expandAll: Plasmoid.configuration.forecastExpandAll === true
    // Per-day hourly cache: maps dateStr → hourly array; populated progressively
    property var _perDayHourlyData: ({})
    // Per-day loading state: maps dateStr → true while a fetch is in flight
    property var _loadingDays: ({})
    // Set of dateStr values the user has manually collapsed in expandAll mode
    property var _collapsedDays: ({})
    property var _expandAllQueue: []
    property int _expandAllActiveFetches: 0
    property int _expandAllFetchGeneration: 0
    readonly property int _expandAllMaxConcurrentFetches: 1

    function _cancelExpandAllFetch(clearData) {
        _expandAllFetchGeneration++;
        _expandAllQueue = [];
        _expandAllActiveFetches = 0;
        expandAllFetchPump.stop();
        _loadingDays = {};
        if (clearData)
            _perDayHourlyData = {};
    }

    function _startExpandAll() {
        if (!weatherRoot || weatherRoot.dailyData.length === 0) return;
        _expandAllFetchGeneration++;
        _expandAllQueue = [];
        _expandAllActiveFetches = 0;
        _perDayHourlyData = {};
        var loading = {};
        var total    = Math.min(Plasmoid.configuration.forecastDays, weatherRoot.dailyData.length);
        var startDi  = forecastRoot.showToday ? 0 : 1;
        for (var di = startDi; di < total; di++) {
            var dateStr = weatherRoot.dailyData[di].dateStr || "";
            if (!dateStr) continue;
            _expandAllQueue.push(dateStr);
            loading[dateStr] = true;
        }
        _loadingDays = loading;
        expandAllFetchPump.restart();
    }

    function _pumpExpandAllQueue() {
        if (!expandAll || !weatherRoot) return;
        var generation = _expandAllFetchGeneration;
        while (_expandAllActiveFetches < _expandAllMaxConcurrentFetches && _expandAllQueue.length > 0) {
            var dateStr = _expandAllQueue.shift();
            _expandAllActiveFetches++;
            (function(ds, gen) {
                weatherRoot.fetchHourlyForDateDirect(ds, function(hourlyArr) {
                    if (gen !== forecastRoot._expandAllFetchGeneration) return;
                    var dataUpd = Object.assign({}, forecastRoot._perDayHourlyData);
                    dataUpd[ds] = hourlyArr || [];
                    forecastRoot._perDayHourlyData = dataUpd;
                    var loadDone = Object.assign({}, forecastRoot._loadingDays);
                    delete loadDone[ds];
                    forecastRoot._loadingDays = loadDone;
                    forecastRoot._expandAllActiveFetches = Math.max(0, forecastRoot._expandAllActiveFetches - 1);
                    if (forecastRoot._expandAllQueue.length > 0)
                        expandAllFetchPump.restart();
                });
            })(dateStr, generation);
        }
    }

    Timer {
        id: expandAllFetchPump
        interval: 80
        repeat: false
        onTriggered: forecastRoot._pumpExpandAllQueue()
    }

    function activateForecast() {
        _autoOpenDone = false;
        _collapsedDays = {};
        _loadingDays = {};
        if (expandAll) {
            _autoOpenDone = true;
            _perDayHourlyData = {};
            _startExpandAll();
        } else {
            _cancelExpandAllFetch(true);
            _doAutoOpen();
        }
    }

    onExpandAllChanged: {
        if (expandAll) {
            expandedIndex = -1;
            _autoOpenDone = true;
            _collapsedDays = {};
            _loadingDays   = {};
            if (visible && weatherRoot && weatherRoot.dailyData.length > 0)
                _startExpandAll();
        } else {
            _cancelExpandAllFetch(true);
            _collapsedDays = {};
            _autoOpenDone = false;
            if (visible)
                _doAutoOpen();
        }
    }

    onAutoOpenChanged: {
        _autoOpenDone = false;
        if (visible && !expandAll)
            _doAutoOpen();
    }

    function _doAutoOpen() {
        if (_autoOpenDone) return;
        if (!weatherRoot || weatherRoot.dailyData.length === 0) return;
        _autoOpenDone = true;
        if (expandAll) {
            _startExpandAll();
            return;
        }
        if (!autoOpen) return;
        var firstDataIndex = forecastRoot.showToday ? 0 : 1;
        if (firstDataIndex >= weatherRoot.dailyData.length) return;
        forecastRoot.expandedIndex = 0;
        weatherRoot.hourlyData = [];
        weatherRoot.fetchHourlyForDate(weatherRoot.dailyData[firstDataIndex].dateStr || "");
    }

    onVisibleChanged: {
        if (visible) {
            activateForecast();
        } else {
            _cancelExpandAllFetch(false);
        }
    }

    Connections {
        target: weatherRoot
        function onDailyDataChanged() {
            if (!forecastRoot.visible) {
                forecastRoot._autoOpenDone = false;
                forecastRoot._cancelExpandAllFetch(true);
                return;
            }
            if (forecastRoot.expandAll) {
                // expandAll always re-fetches when new data arrives —
                // independent of autoOpen and _autoOpenDone.
                forecastRoot._perDayHourlyData = {};
                forecastRoot._loadingDays      = {};
                forecastRoot._startExpandAll();
            } else if (forecastRoot.expandedIndex >= 0) {
                // A day is already expanded (auto-opened or clicked) — re-fetch
                // its hourly data so the panel doesn't keep showing the forecast
                // from before the refresh. Keep the old data on screen while the
                // fetch is in flight to avoid a collapse/flash.
                var dataIndex = forecastRoot.showToday
                    ? forecastRoot.expandedIndex
                    : forecastRoot.expandedIndex + 1;
                if (dataIndex < weatherRoot.dailyData.length)
                    weatherRoot.fetchHourlyForDate(weatherRoot.dailyData[dataIndex].dateStr || "");
                else
                    forecastRoot.expandedIndex = -1;
            } else {
                forecastRoot._doAutoOpen();
            }
        }
    }

    // Set implicit height based on content
    implicitHeight: (weatherRoot && weatherRoot.dailyData.length > 0) ? forecastColumn.height : (emptyLabel.implicitHeight + 40)

    // Font for weather icons (wind direction glyph)
    FontLoader {
        id: wiFont
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    // Resolved at load time so the path is correct in all rendering contexts
    readonly property url iconsBaseDir: Qt.resolvedUrl("../icons/")

    // Forecast icon theme — uses the same theme as the main condition icon.
    readonly property string widgetIconTheme: {
        var t = Plasmoid.configuration.conditionIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property int iconSz: Plasmoid.configuration.widgetIconSize || 16
    readonly property string iconTheme: widgetIconTheme
    // Icon theme used for the optional daily-forecast stat items (Appearance → Widget → Items)
    readonly property string itemsIconTheme: {
        var t = Plasmoid.configuration.widgetIconTheme || "symbolic";
        return (t === "wi-font") ? "symbolic" : t;
    }
    readonly property bool showSunEvents:   Plasmoid.configuration.forecastShowSunEvents !== false
    readonly property bool showToday:       Plasmoid.configuration.forecastShowToday !== false
    readonly property bool showWind:        Plasmoid.configuration.forecastShowWind !== false
    readonly property string hourlyLayout:  Plasmoid.configuration.forecastHourlyLayout || "cards"
    readonly property bool _forecastDualTemp: Plasmoid.configuration.dualTempEnabled === true && Plasmoid.configuration.dualTempInWidget !== false
    readonly property bool _forecastShowTempUnit: Plasmoid.configuration.showTempUnit === true
    readonly property int _forecastWindColumnWidth: 104
    readonly property int _forecastStatColumnWidth: 92
    readonly property int _forecastTempColumnWidth: _forecastDualTemp
        ? (_forecastShowTempUnit ? 178 : 132)
        : (_forecastShowTempUnit ? 82 : 58)

    // ── Hourly forecast extra stats ─────────────────────────────────
    readonly property bool _hourlyShowWind:       Plasmoid.configuration.forecastHourlyShowWind !== false
    readonly property bool _hourlyShowPressure:   Plasmoid.configuration.forecastHourlyShowPressure === true
    readonly property bool _hourlyShowKpIndex:    Plasmoid.configuration.forecastHourlyShowKpIndex === true
    readonly property bool _hourlyShowUvIndex:    Plasmoid.configuration.forecastHourlyShowUvIndex === true
    readonly property bool _hourlyShowPrecipSum:  Plasmoid.configuration.forecastHourlyShowPrecipSum === true
    readonly property bool _hourlyShowVisibility: Plasmoid.configuration.forecastHourlyShowVisibility === true
    readonly property int _hourlyExtraRowCount: {
        var c = 0;
        if (forecastRoot._hourlyShowPressure) c++;
        if (forecastRoot._hourlyShowKpIndex) c++;
        if (forecastRoot._hourlyShowUvIndex) c++;
        if (forecastRoot._hourlyShowPrecipSum) c++;
        if (forecastRoot._hourlyShowVisibility) c++;
        return c;
    }
    readonly property int _hourlyCardHeight: 200 + _hourlyExtraRowCount * 26
    // Sum of strip rows always shown: time(18) + icon(48) + trend(32) + temp(18) + precip(18) + 4×2 spacing
    readonly property int _hourlyStripBaseHeight: 142
    readonly property int _hourlyStripContentHeight: _hourlyStripBaseHeight + (_hourlyShowWind ? 30 : 0) + _hourlyExtraRowCount * 20
    // Reserve room for the horizontal scrollbar so it never covers the last row or the
    // day-section divider. Breeze (and other classic themes) render an always-visible,
    // thicker inline scrollbar than the default Plasma overlay, so size the reserve to
    // the actual scrollbar height at runtime (with a sensible floor).
    readonly property int _hourlyStripScrollbarReserve: Math.max(16, _stripScrollbarHeight + 6)
    property int _stripScrollbarHeight: 16
    readonly property int _hourlyStripHeight: _hourlyStripContentHeight + 8 + _hourlyStripScrollbarReserve
    readonly property int _hourlyCardWidth: {
        var w = 100;
        if (_hourlyShowKpIndex)    w = Math.max(w, 132);
        if (_hourlyShowVisibility) w = Math.max(w, 112);
        if (_hourlyShowPressure)   w = Math.max(w, 108);
        if (_hourlyShowPrecipSum)  w = Math.max(w, 104);
        if (_hourlyShowUvIndex)    w = Math.max(w, 100);
        if (_hourlyShowWind)       w = Math.max(w, 100);
        return w;
    }

    function _wheelDeltaX(wheel) {
        return wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x;
    }

    function _wheelDeltaY(wheel) {
        return wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y;
    }

    function _wheelWantsHorizontal(wheel) {
        if (wheel.modifiers & Qt.ShiftModifier)
            return true;
        var dx = Math.abs(_wheelDeltaX(wheel));
        var dy = Math.abs(_wheelDeltaY(wheel));
        return dx > 0 && dx >= dy;
    }

    function _isClassicMouseWheel(wheel) {
        return wheel.pixelDelta.x === 0 && wheel.pixelDelta.y === 0
            && (wheel.angleDelta.x !== 0 || wheel.angleDelta.y !== 0);
    }

    function _hourlyWheelWantsHorizontal(wheel) {
        if (_wheelWantsHorizontal(wheel))
            return true;
        // Classic mouse wheels emit vertical angleDelta only.
        // In hourly horizontal views, map that to horizontal scroll.
        return _isClassicMouseWheel(wheel) && wheel.angleDelta.y !== 0;
    }

    function _scrollParentVertically(wheel) {
        if (!verticalScrollView)
            return false;
        var delta = _wheelDeltaY(wheel);
        if (delta === 0)
            return false;
        var scale = wheel.pixelDelta.y !== 0 ? 1 : 0.5;
        var amount = delta * scale;

        var flick = verticalScrollView.flickableItem || verticalScrollView.contentItem || verticalScrollView;
        if (flick && flick.contentHeight !== undefined && flick.contentY !== undefined) {
            var maxY = Math.max(0, flick.contentHeight - flick.height);
            flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - amount));
            return true;
        }

        var bar = verticalScrollView.ScrollBar ? verticalScrollView.ScrollBar.vertical : null;
        if (bar) {
            var maxPos = Math.max(0, 1.0 - bar.size);
            bar.position = Math.max(0, Math.min(maxPos, bar.position - amount / 1200));
            return true;
        }
        return false;
    }

    /** Resolve a condition icon, handling the "custom" theme with per-condition overrides.
     *  Delegates to ConfigUtils.resolveCustomConditionIcon() — single source of truth. */
    function resolveConditionIcon(code, isNight, iconSize) {
        return ConfigUtils.resolveCustomConditionIcon(
            code, isNight, iconSize, forecastRoot.iconsBaseDir,
            forecastRoot.widgetIconTheme,
            Plasmoid.configuration.widgetConditionCustomIcons || "",
            W.weatherCodeToIcon, IconResolver.resolveCondition);
    }

    // ── empty state ───────────────────────────────────────────────────────
    BusyIndicator {
        id: emptyBusy
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: emptyLabel.top
        anchors.bottomMargin: 8
        running: visible
        visible: weatherRoot && weatherRoot.loading && weatherRoot.dailyData.length === 0
    }

    Label {
        id: emptyLabel
        anchors.centerIn: parent
        visible: !weatherRoot || weatherRoot.dailyData.length === 0
        text: (weatherRoot && weatherRoot.loading) ? i18n("Loading forecast…") : i18n("No forecast data")
        color: Kirigami.Theme.textColor
        font: weatherRoot ? weatherRoot.wf(12, false) : Qt.font({})
    }

    Column {
        id: forecastColumn
        width: parent.width
        spacing: 0
        visible: weatherRoot && weatherRoot.dailyData.length > 0

            Repeater {
                model: {
                    if (!weatherRoot || weatherRoot.dailyData.length === 0) return 0;
                    var total = Math.min(Plasmoid.configuration.forecastDays, weatherRoot.dailyData.length);
                    return forecastRoot.showToday ? total : Math.max(0, total - 1);
                }

                delegate: Column {
                    required property int index
                    readonly property int dataIndex: forecastRoot.showToday ? index : index + 1
                    width: parent.width
                    spacing: 0

                    // Per-delegate hourly data: in expandAll mode pulls from the
                    // per-day cache; in single-expand mode uses weatherRoot.hourlyData
                    // (only valid for the currently expanded day).
                    property var _dayHourlyData: {
                        var dateStr = (weatherRoot && weatherRoot.dailyData[dataIndex])
                            ? (weatherRoot.dailyData[dataIndex].dateStr || "") : "";
                        if (forecastRoot.expandAll && dateStr) {
                            if (forecastRoot._collapsedDays[dateStr]) return [];
                            return forecastRoot._perDayHourlyData[dateStr] || [];
                        }
                        if (!forecastRoot.expandAll && forecastRoot.expandedIndex === index)
                            return weatherRoot ? weatherRoot.hourlyData : [];
                        return [];
                    }

                    readonly property string _daySunriseText: {
                        if (weatherRoot && weatherRoot.dailyData[dataIndex] && weatherRoot.dailyData[dataIndex].sunriseTimeText)
                            return weatherRoot.dailyData[dataIndex].sunriseTimeText;
                        return weatherRoot ? weatherRoot.sunriseTimeText : "--";
                    }

                    readonly property string _daySunsetText: {
                        if (weatherRoot && weatherRoot.dailyData[dataIndex] && weatherRoot.dailyData[dataIndex].sunsetTimeText)
                            return weatherRoot.dailyData[dataIndex].sunsetTimeText;
                        return weatherRoot ? weatherRoot.sunsetTimeText : "--";
                    }

                    readonly property bool _dayOutsideQWeatherHourlyRange: {
                        if ((Plasmoid.configuration.weatherProvider || "adaptive") !== "qWeather")
                            return false;
                        var ds = (weatherRoot && weatherRoot.dailyData[dataIndex])
                            ? (weatherRoot.dailyData[dataIndex].dateStr || "") : "";
                        if (!ds)
                            return false;
                        var parts = ds.split("-");
                        if (parts.length < 3)
                            return false;
                        var year = parseInt(parts[0], 10);
                        var month = parseInt(parts[1], 10) - 1;
                        var day = parseInt(parts[2], 10);
                        if (isNaN(year) || isNaN(month) || isNaN(day))
                            return false;
                        var dayStartMs = new Date(year, month, day, 0, 0, 0, 0).getTime();
                        var hourlyLimitMs = (new Date()).getTime() + 168 * 3600 * 1000;
                        return dayStartMs >= hourlyLimitMs;
                    }

                    readonly property bool _dayIsLoading: {
                        var dateStr = (weatherRoot && weatherRoot.dailyData[dataIndex])
                            ? (weatherRoot.dailyData[dataIndex].dateStr || "") : "";
                        if (forecastRoot.expandAll && dateStr && !forecastRoot._collapsedDays[dateStr])
                            return !!forecastRoot._loadingDays[dateStr];
                        return false;
                    }

                    // ── day row ─────────────────────────────────────────
                    Rectangle {
                        id: dayRow
                        width: parent.width
                        height: Math.max(52, rowLayoutInner.implicitHeight + 12)
                        color: (rowMouse.containsMouse || (forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        RowLayout {
                            id: rowLayoutInner
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 14
                            }
                            spacing: 0

                            // ── visibility flags for the optional per-day stat items,
                            // used to decide when to show a "•" separator between them ──
                            readonly property bool _windVisible: forecastRoot.showWind && !isNaN(weatherRoot.dailyData[dataIndex].windKmh)
                            readonly property bool _pressureVisible: Plasmoid.configuration.forecastShowPressure === true
                            readonly property bool _kpVisible: Plasmoid.configuration.forecastShowKpIndex === true
                            readonly property bool _uvVisible: Plasmoid.configuration.forecastShowUvIndex === true
                            readonly property bool _precipVisible: Plasmoid.configuration.forecastShowPrecipSum === true
                            readonly property bool _visibilityVisible: Plasmoid.configuration.forecastShowVisibility === true

                            Kirigami.Icon {
                                source: ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) ? "arrow-down" : "arrow-right"
                                width: 14
                                height: 14
                                opacity: 0.45
                                Layout.alignment: Qt.AlignVCenter
                                Layout.rightMargin: 6
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 110
                                Layout.minimumWidth: 110
                                Layout.maximumWidth: 110
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1
                                Label {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: {
                                        var di = dataIndex;
                                        if (di === 0)
                                            return i18n("Today");
                                        var ds = weatherRoot.dailyData[di].dateStr;
                                        if (!ds)
                                            return "";
                                        var parts = ds.split("-");
                                        if (parts.length !== 3)
                                            return "";
                                        var d = new Date(parts[0], parts[1] - 1, parts[2]);
                                        return Qt.locale().dayName(d.getDay(), Locale.LongFormat);
                                    }
                                    color: Kirigami.Theme.textColor
                                    font: weatherRoot.wf(12, true)
                                }
                                Label {
                                    text: {
                                        var ds = weatherRoot.dailyData[dataIndex].dateStr || "";
                                        if (!ds)
                                            return "";
                                        var d = new Date(ds);
                                        var fmt = Qt.locale().dateFormat(Locale.ShortFormat);
                                        return Qt.formatDate(d, fmt);
                                    }
                                    color: Kirigami.Theme.textColor
                                    font: weatherRoot.wf(9, false)
                                }
                            }

                            WeatherIcon {
                                iconInfo: forecastRoot.resolveConditionIcon(
                                    weatherRoot.dailyData[dataIndex].code, false,
                                    forecastRoot.iconSz)
                                iconSize: 28
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.rightMargin: 4
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: weatherRoot.weatherCodeToText(weatherRoot.dailyData[dataIndex].code)
                                color: Kirigami.Theme.textColor
                                font: weatherRoot.wf(11, false)
                                wrapMode: Text.WordWrap
                            }

                            Item {
                                Layout.preferredWidth: 5
                            }

                            RowLayout {
                                visible: rowLayoutInner._windVisible
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: Math.max(forecastRoot._forecastWindColumnWidth, implicitWidth)
                                Layout.minimumWidth: forecastRoot._forecastWindColumnWidth
                                Layout.maximumWidth: Math.max(forecastRoot._forecastWindColumnWidth, implicitWidth)
                                spacing: 1

                                Item {
                                    Layout.fillWidth: true
                                }

                                Item {
                                    visible: !isNaN(weatherRoot.dailyData[dataIndex].windDir)
                                    implicitWidth: forecastRoot.iconSz
                                    implicitHeight: forecastRoot.iconSz
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: W.windDirectionGlyph(weatherRoot.dailyData[dataIndex].windDir)
                                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.72)
                                        font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                        font.pixelSize: forecastRoot.iconSz
                                    }
                                }

                                Label {
                                    text: weatherRoot.windValue(weatherRoot.dailyData[dataIndex].windKmh)
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                    elide: Text.ElideRight
                                }

                                Item {
                                    Layout.fillWidth: true
                                }
                            }

                            Label {
                                visible: rowLayoutInner._pressureVisible && rowLayoutInner._windVisible
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
                                font: weatherRoot.wf(10, false)
                            }

                            RowLayout {
                                visible: Plasmoid.configuration.forecastShowPressure === true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                                Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                spacing: 4
                                WeatherIcon {
                                    iconInfo: IconResolver.resolve("pressure", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                    iconSize: forecastRoot.iconSz
                                }
                                Label {
                                    text: weatherRoot.pressureValue(weatherRoot.dailyData[dataIndex].pressureHpa)
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._kpVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
                                font: weatherRoot.wf(10, false)
                            }

                            RowLayout {
                                visible: Plasmoid.configuration.forecastShowKpIndex === true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                                Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                spacing: 4
                                WeatherIcon {
                                    iconInfo: IconResolver.resolve("spaceweather", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                    iconSize: forecastRoot.iconSz
                                }
                                Label {
                                    text: {
                                        var e = weatherRoot.kpForecastForDate(weatherRoot.dailyData[dataIndex].dateStr || "");
                                        if (!e || isNaN(e.kp)) return i18n("No information");
                                        return "Kp " + e.kp.toFixed(1) + " (" + (e.gScale || "G0") + ")";
                                    }
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._uvVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
                                font: weatherRoot.wf(10, false)
                            }

                            RowLayout {
                                visible: Plasmoid.configuration.forecastShowUvIndex === true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                                Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                spacing: 4
                                WeatherIcon {
                                    iconInfo: IconResolver.resolve("uvindex", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                    iconSize: forecastRoot.iconSz
                                }
                                Label {
                                    text: {
                                        var uv = weatherRoot.dailyData[dataIndex].uvMax;
                                        return isNaN(uv) ? "--" : "UV " + uv.toFixed(1);
                                    }
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._precipVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
                                font: weatherRoot.wf(10, false)
                            }

                            RowLayout {
                                visible: Plasmoid.configuration.forecastShowPrecipSum === true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                                Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                spacing: 4
                                WeatherIcon {
                                    iconInfo: IconResolver.resolve("precipsum", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                    iconSize: forecastRoot.iconSz
                                }
                                Label {
                                    text: weatherRoot.precipSumText(weatherRoot.dailyData[dataIndex].precipMm)
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._visibilityVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible || rowLayoutInner._precipVisible)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
                                font: weatherRoot.wf(10, false)
                            }

                            RowLayout {
                                visible: Plasmoid.configuration.forecastShowVisibility === true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.preferredWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                Layout.minimumWidth: forecastRoot._forecastStatColumnWidth
                                Layout.maximumWidth: Math.max(forecastRoot._forecastStatColumnWidth, implicitWidth)
                                spacing: 4
                                WeatherIcon {
                                    iconInfo: IconResolver.resolve("visibility", forecastRoot.iconSz, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                    iconSize: forecastRoot.iconSz
                                }
                                Label {
                                    text: weatherRoot.visibilityValue(weatherRoot.dailyData[dataIndex].visibilityKm)
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible || rowLayoutInner._precipVisible || rowLayoutInner._visibilityVisible
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.rightMargin: 6
                                text: "•"
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
                                font: weatherRoot.wf(10, false)
                            }

                            RowLayout {
                                spacing: 2
                                Layout.alignment: Qt.AlignRight
                                Layout.preferredWidth: Math.max(forecastRoot._forecastTempColumnWidth, implicitWidth)
                                Layout.minimumWidth: forecastRoot._forecastTempColumnWidth
                                Layout.maximumWidth: Math.max(forecastRoot._forecastTempColumnWidth, implicitWidth)
                                Item {
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: weatherRoot.tempValue(weatherRoot.dailyData[dataIndex].minC)
                                    color: "#42a5f5"
                                    font: weatherRoot.wf(12, false)
                                }
                                Label {
                                    text: "/"
                                    color: Kirigami.Theme.textColor
                                    font: weatherRoot.wf(12, false)
                                }
                                Label {
                                    text: weatherRoot.tempValue(weatherRoot.dailyData[dataIndex].maxC)
                                    color: "#ff6e40"
                                    font: weatherRoot.wf(12, true)
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var dateStr = weatherRoot.dailyData[dataIndex].dateStr || "";
                                if (forecastRoot.expandAll) {
                                    // Toggle this specific day's collapsed state
                                    var col = Object.assign({}, forecastRoot._collapsedDays);
                                    if (col[dateStr]) {
                                        delete col[dateStr];
                                    } else {
                                        col[dateStr] = true;
                                    }
                                    forecastRoot._collapsedDays = col;
                                } else {
                                    if (forecastRoot.expandedIndex === index) {
                                        forecastRoot.expandedIndex = -1;
                                    } else {
                                        forecastRoot.expandedIndex = index;
                                        if (weatherRoot) {
                                            weatherRoot.hourlyData = [];
                                            weatherRoot.fetchHourlyForDate(dateStr);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── inline hourly panel ─────────────────────────────
                    Rectangle {
                        id: hourlyPanel
                        width: parent.width
                        height: ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) ? (forecastRoot.hourlyLayout === "strip" ? forecastRoot._hourlyStripHeight : forecastRoot._hourlyCardHeight + 40) : 0
                        visible: height > 0
                        clip: true
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        Behavior on height {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.InOutQuad
                            }
                        }

                        // Per-day loading spinner (expandAll parallel fetch)
                        BusyIndicator {
                            anchors.centerIn: parent
                            running: _dayIsLoading
                            visible: _dayIsLoading
                        }

                        // Plain loading text for single-expand mode
                        Label {
                            anchors.centerIn: parent
                            width: parent.width - 24
                            visible: !_dayIsLoading && ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) && _dayHourlyData.length === 0
                            text: _dayOutsideQWeatherHourlyRange
                                ? i18n("QWeather provides hourly forecasts for up to 168 hours (7 days). Daily forecast is still available for this date.")
                                : i18n("Loading hourly data…")
                            color: Kirigami.Theme.textColor
                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Only instantiate the heavy hourly UI for the expanded day.
                        Loader {
                            anchors.fill: parent
                            active: ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) && weatherRoot && _dayHourlyData.length > 0
                            asynchronous: true
                            sourceComponent: forecastRoot.hourlyLayout === "strip" ? stripHourlyComponent : cardsHourlyComponent
                        }

                        Component {
                            id: stripHourlyComponent
                            Item {
                                anchors.fill: parent

                                // ── STRIP LAYOUT ──────────────────────────────────
                                Flickable {
                                    id: stripScrollView
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    clip: true
                                    flickableDirection: Flickable.HorizontalFlick
                                    contentWidth: stripContent.width
                                    contentHeight: stripContent.height
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.horizontal: ScrollBar {
                                        id: stripHBar
                                        policy: ScrollBar.AsNeeded
                                        // Feed the real (theme-dependent) scrollbar thickness back to the
                                        // strip height calc so the reserve matches Breeze's always-visible
                                        // inline scrollbar as well as the slim default-theme overlay.
                                        onImplicitHeightChanged: {
                                            if (implicitHeight > 0)
                                                forecastRoot._stripScrollbarHeight = implicitHeight;
                                        }
                                        Component.onCompleted: {
                                            if (implicitHeight > 0)
                                                forecastRoot._stripScrollbarHeight = implicitHeight;
                                        }
                                    }

                                    NumberAnimation {
                                        id: stripWheelAnimation
                                        target: stripScrollView
                                        property: "contentX"
                                        duration: 140
                                        easing.type: Easing.OutCubic
                                    }

                                    // Build combined model same as cards (with sun events)
                                    property var _hourlyWithSun: {
                                        if (!_dayHourlyData || !_dayHourlyData.length) return [];
                                        function toMins(t) {
                                            if (!t || t === "--") return -1;
                                            var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                        }
                                        // For today (index 0) filter out past hours; keep 1 hour buffer so current hour stays visible
                                        var nowMins = -1;
                                        if (index === 0) {
                                            var _now = new Date();
                                            nowMins = _now.getHours() * 60 + _now.getMinutes() - 60;
                                        }
                                        var source = nowMins >= 0
                                            ? _dayHourlyData.filter(function(h) { var m = toMins(h.hour); return m < 0 || m >= nowMins; })
                                            : _dayHourlyData;
                                        if (!forecastRoot.showSunEvents)
                                            return source;
                                        var rise = toMins(_daySunriseText);
                                        var set_ = toMins(_daySunsetText);
                                        // Only insert sun markers if they are still in the future (for today)
                                        var riseInserted = rise < 0 || (nowMins >= 0 && rise < nowMins);
                                        var setInserted  = set_  < 0 || (nowMins >= 0 && set_  < nowMins);
                                        var result = [];
                                        source.forEach(function(h) {
                                            var hm = toMins(h.hour);
                                            if (!riseInserted && hm >= 0 && hm > rise) {
                                                result.push({ isSunrise: true, isSunset: false, time: _daySunriseText });
                                                riseInserted = true;
                                            }
                                            if (!setInserted && hm >= 0 && hm > set_) {
                                                result.push({ isSunrise: false, isSunset: true, time: _daySunsetText });
                                                setInserted = true;
                                            }
                                            result.push(h);
                                        });
                                        return result;
                                    }

                                    readonly property int colW: 100
                                    readonly property int colSpacing: 0

                                    // Column of rows
                                    Item {
                                        id: stripContent
                                        height: forecastRoot._hourlyStripContentHeight
                                        width: stripScrollView._hourlyWithSun.length * (stripScrollView.colW + stripScrollView.colSpacing)

                                        // Temps array for trend line (only regular hourly entries)
                                        property var _temps: {
                                            var arr = [];
                                            var items = stripScrollView._hourlyWithSun;
                                            for (var i = 0; i < items.length; i++) {
                                                if (!items[i].isSunrise && !items[i].isSunset)
                                                    arr.push({ col: i, tempC: items[i].tempC });
                                            }
                                            return arr;
                                        }

                                        // ── Row 0: time labels ──────────────────────
                                        Row {
                                            id: stripTimeRow
                                            x: 0; y: 4
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: Item {
                                                    required property var modelData
                                                    width: stripScrollView.colW
                                                    height: 18
                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: {
                                                            if (modelData.isSunrise || modelData.isSunset)
                                                                return weatherRoot ? weatherRoot.formatTimeForDisplay(modelData.time) : "--";
                                                            if (!modelData.hour || modelData.hour === "--") return "--";
                                                            var parts = modelData.hour.split(":");
                                                            if (parts.length < 2) return modelData.hour;
                                                            var d = new Date();
                                                            d.setHours(parseInt(parts[0],10), parseInt(parts[1],10), 0, 0);
                                                            return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
                                                        }
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(9, modelData.isSunrise || modelData.isSunset) : Qt.font({})
                                                        opacity: (modelData.isSunrise || modelData.isSunset) ? 0.9 : 0.7
                                                    }
                                                }
                                            }
                                        }

                                        // ── Row 1: icons ────────────────────────────
                                        Row {
                                            id: stripIconRow
                                            x: 0; y: stripTimeRow.y + stripTimeRow.height + 2
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: Item {
                                                    required property var modelData
                                                    width: stripScrollView.colW
                                                    height: 48
                                                    WeatherIcon {
                                                        anchors.centerIn: parent
                                                        iconInfo: {
                                                            if (modelData.isSunrise)
                                                                return IconResolver.resolve("sunrise", 32, forecastRoot.iconsBaseDir,
                                                                    forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                                    (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom") ? "symbolic" : forecastRoot.widgetIconTheme);
                                                            if (modelData.isSunset)
                                                                return IconResolver.resolve("sunset", 32, forecastRoot.iconsBaseDir,
                                                                    forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                                    (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom") ? "symbolic" : forecastRoot.widgetIconTheme);
                                                            var isNight = false;
                                                            if (modelData.hour && modelData.hour !== "--") {
                                                                var p2 = modelData.hour.split(":");
                                                                if (p2.length >= 2) {
                                                                    var hm2 = parseInt(p2[0],10)*60+parseInt(p2[1],10);
                                                                    function _sm(t) { if (!t||t==="--") return -1; var p=t.split(":"); return p.length<2?-1:parseInt(p[0],10)*60+parseInt(p[1],10); }
                                                                    var rise2=_sm(_daySunriseText);
                                                                    var set2=_sm(_daySunsetText);
                                                                    if (rise2>=0&&set2>=0) isNight=hm2<rise2||hm2>=set2;
                                                                }
                                                            }
                                                            return forecastRoot.resolveConditionIcon(modelData.code||0, isNight, forecastRoot.iconSz);
                                                        }
                                                        iconSize: 44
                                                        iconColor: Kirigami.Theme.textColor
                                                    }
                                                }
                                            }
                                        }

                                        // ── Trend line canvas ────────────────────────
                                        Canvas {
                                            id: trendCanvas
                                            x: 0
                                            y: stripIconRow.y + stripIconRow.height + 2
                                            width: stripContent.width
                                            height: 32
                                            property var temps: stripContent._temps
                                            onTempsChanged: requestPaint()

                                            // Detect light theme by background luminance
                                            readonly property bool darkTheme: {
                                                var bg = Kirigami.Theme.backgroundColor;
                                                return (0.299*bg.r + 0.587*bg.g + 0.114*bg.b) < 0.5;
                                            }
                                            onDarkThemeChanged: requestPaint()

                                            // Map a temperature in °C to a CSS color string
                                            function tempColor(t) {
                                                // Dark theme: bright/pastel stops readable on dark bg
                                                // Light theme: deeper/saturated stops readable on light bg
                                                var stops = darkTheme ? [
                                                    { t: -10, r:  50, g: 100, b: 255 },
                                                    { t:   0, r:   0, g: 180, b: 255 },
                                                    { t:  10, r:  80, g: 220, b: 160 },
                                                    { t:  20, r: 220, g: 220, b:  40 },
                                                    { t:  30, r: 255, g: 130, b:   0 },
                                                    { t:  40, r: 220, g:  30, b:  30 }
                                                ] : [
                                                    { t: -10, r:  20, g:  60, b: 200 },
                                                    { t:   0, r:   0, g: 120, b: 210 },
                                                    { t:  10, r:   0, g: 160, b:  80 },
                                                    { t:  20, r: 170, g: 150, b:   0 },
                                                    { t:  30, r: 210, g:  80, b:   0 },
                                                    { t:  40, r: 180, g:  10, b:  10 }
                                                ];
                                                if (t <= stops[0].t) return "rgba(" + stops[0].r + "," + stops[0].g + "," + stops[0].b + ",1.0)";
                                                if (t >= stops[stops.length-1].t) { var s=stops[stops.length-1]; return "rgba("+s.r+","+s.g+","+s.b+",1.0)"; }
                                                for (var i = 1; i < stops.length; i++) {
                                                    if (t <= stops[i].t) {
                                                        var frac = (t - stops[i-1].t) / (stops[i].t - stops[i-1].t);
                                                        var r = Math.round(stops[i-1].r + frac * (stops[i].r - stops[i-1].r));
                                                        var g = Math.round(stops[i-1].g + frac * (stops[i].g - stops[i-1].g));
                                                        var b = Math.round(stops[i-1].b + frac * (stops[i].b - stops[i-1].b));
                                                        return "rgba(" + r + "," + g + "," + b + ",1.0)";
                                                    }
                                                }
                                                return "rgba(0,0,0,0.8)";
                                            }

                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ctx.clearRect(0, 0, width, height);
                                                var pts = temps;
                                                if (!pts || pts.length < 2) return;
                                                var minT = pts[0].tempC, maxT = pts[0].tempC;
                                                for (var i = 1; i < pts.length; i++) {
                                                    if (pts[i].tempC < minT) minT = pts[i].tempC;
                                                    if (pts[i].tempC > maxT) maxT = pts[i].tempC;
                                                }
                                                var range = maxT - minT;
                                                var pad = 5;
                                                var cw = stripScrollView.colW + stripScrollView.colSpacing;
                                                function xOf(col) { return col * cw + cw / 2; }
                                                function yOf(t) {
                                                    if (range < 0.01) return height / 2;
                                                    return pad + (1 - (t - minT) / range) * (height - pad * 2);
                                                }
                                                // Draw segment by segment, each with its midpoint color
                                                ctx.lineWidth = 2.5;
                                                ctx.lineJoin = "round";
                                                ctx.lineCap = "round";
                                                for (var j = 1; j < pts.length; j++) {
                                                    var x0 = xOf(pts[j-1].col), y0 = yOf(pts[j-1].tempC);
                                                    var x1 = xOf(pts[j].col),   y1 = yOf(pts[j].tempC);
                                                    var grad = ctx.createLinearGradient(x0, y0, x1, y1);
                                                    grad.addColorStop(0, tempColor(pts[j-1].tempC));
                                                    grad.addColorStop(1, tempColor(pts[j].tempC));
                                                    ctx.strokeStyle = grad;
                                                    ctx.beginPath();
                                                    ctx.moveTo(x0, y0);
                                                    ctx.lineTo(x1, y1);
                                                    ctx.stroke();
                                                }
                                                // Dots colored by temp
                                                for (var k = 0; k < pts.length; k++) {
                                                    ctx.fillStyle = tempColor(pts[k].tempC);
                                                    ctx.beginPath();
                                                    ctx.arc(xOf(pts[k].col), yOf(pts[k].tempC), 3, 0, Math.PI * 2);
                                                    ctx.fill();
                                                }
                                            }
                                        }

                                        // ── Row 2: temperature labels ────────────────
                                        Row {
                                            id: stripTempRow
                                            x: 0; y: trendCanvas.y + trendCanvas.height + 2
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: Item {
                                                    required property var modelData
                                                    width: stripScrollView.colW
                                                    height: 18
                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: (modelData.isSunrise || modelData.isSunset) ? i18n(modelData.isSunrise ? "Sunrise" : "Sunset")
                                                              : (weatherRoot ? weatherRoot.tempValue(modelData.tempC) : "--")
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(10, !(modelData.isSunrise || modelData.isSunset)) : Qt.font({})
                                                        opacity: (modelData.isSunrise || modelData.isSunset) ? 0.75 : 1.0
                                                    }
                                                }
                                            }
                                        }

                                        // ── Row 3: precipitation ─────────────────────
                                        Row {
                                            id: stripPrecipRow
                                            x: 0; y: stripTempRow.y + stripTempRow.height + 2
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                    width: stripScrollView.colW
                                                    height: 18
                                                    spacing: 2
                                                    Item { Layout.fillWidth: true }
                                                    WeatherIcon {
                                                        visible: !parent._isSun
                                                        iconInfo: IconResolver.resolve("umbrella", 16, forecastRoot.iconsBaseDir,
                                                            forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                            (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom") ? "symbolic" : forecastRoot.widgetIconTheme)
                                                        iconSize: 16
                                                        iconColor: "#7ec8e3"
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: {
                                                            if (parent._isSun) return "";
                                                            var ppText = W.hourlyPrecipProbText(modelData.precipProb, modelData.code);
                                                            if (ppText !== null) return ppText;
                                                            var h = modelData.humidity;
                                                            return (!isNaN(h) && h !== undefined) ? Math.round(h) + "%" : "--";
                                                        }
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }
                                        }

                                        // ── Row 4: wind ───────────────────────────────
                                        Row {
                                            id: stripWindRow
                                            x: 0; y: stripPrecipRow.y + stripPrecipRow.height + 2
                                            height: 28
                                            visible: forecastRoot._hourlyShowWind
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: Item {
                                                    required property var modelData
                                                    readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                    width: stripScrollView.colW
                                                    height: 28
                                                    RowLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 2
                                                        Label {
                                                            visible: !parent.parent._isSun
                                                            text: weatherRoot && modelData.windKmh !== undefined ? weatherRoot.windValue(modelData.windKmh) : "--"
                                                            color: Kirigami.Theme.textColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            opacity: 0.7
                                                        }
                                                        Text {
                                                            visible: !parent.parent._isSun && weatherRoot && !isNaN(modelData.windDeg)
                                                            text: W.windDirectionGlyph(modelData.windDeg)
                                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                            font.pixelSize: 24
                                                            color: Kirigami.Theme.textColor
                                                            opacity: 0.7
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // ── Row 5: pressure ───────────────────────────
                                        Row {
                                            id: stripPressureRow
                                            x: 0; y: stripWindRow.visible ? (stripWindRow.y + stripWindRow.height + 2) : stripWindRow.y
                                            visible: forecastRoot._hourlyShowPressure
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                    width: stripScrollView.colW
                                                    height: 18
                                                    spacing: 2
                                                    Item { Layout.fillWidth: true }
                                                    WeatherIcon {
                                                        visible: !parent._isSun
                                                        iconInfo: IconResolver.resolve("pressure", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                        iconSize: 16
                                                        iconColor: Kirigami.Theme.textColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: weatherRoot ? weatherRoot.pressureValue(modelData.pressureHpa) : "--"
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }
                                        }

                                        // ── Row 6: Kp/G index ─────────────────────────
                                        Row {
                                            id: stripKpRow
                                            x: 0; y: stripPressureRow.visible ? (stripPressureRow.y + stripPressureRow.height + 2) : stripPressureRow.y
                                            visible: forecastRoot._hourlyShowKpIndex
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                    width: stripScrollView.colW
                                                    height: 18
                                                    spacing: 2
                                                    Item { Layout.fillWidth: true }
                                                    WeatherIcon {
                                                        visible: !parent._isSun
                                                        iconInfo: IconResolver.resolve("spaceweather", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                        iconSize: 16
                                                        iconColor: Kirigami.Theme.textColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: {
                                                            if (!weatherRoot) return i18n("No info");
                                                            var d = weatherRoot.dailyData[dataIndex].dateStr || "";
                                                            var e = weatherRoot.kpForecastForHour(d, modelData.hour || "")
                                                                    || weatherRoot.kpForecastForDate(d);
                                                            if (!e || isNaN(e.kp)) return i18n("No info");
                                                            return "Kp " + e.kp.toFixed(1) + " (" + (e.gScale || "G0") + ")";
                                                        }
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }
                                        }

                                        // ── Row 7: UV index ────────────────────────────
                                        Row {
                                            id: stripUvRow
                                            x: 0; y: stripKpRow.visible ? (stripKpRow.y + stripKpRow.height + 2) : stripKpRow.y
                                            visible: forecastRoot._hourlyShowUvIndex
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                    width: stripScrollView.colW
                                                    height: 18
                                                    spacing: 2
                                                    Item { Layout.fillWidth: true }
                                                    WeatherIcon {
                                                        visible: !parent._isSun
                                                        iconInfo: IconResolver.resolve("uvindex", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                        iconSize: 16
                                                        iconColor: Kirigami.Theme.textColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: {
                                                            var uv = modelData.uvIndex;
                                                            return (uv === undefined || isNaN(uv)) ? "--" : "UV " + uv.toFixed(1);
                                                        }
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }
                                        }

                                        // ── Row 8: precipitation sum ──────────────────
                                        Row {
                                            id: stripPrecipSumRow
                                            x: 0; y: stripUvRow.visible ? (stripUvRow.y + stripUvRow.height + 2) : stripUvRow.y
                                            visible: forecastRoot._hourlyShowPrecipSum
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                    width: stripScrollView.colW
                                                    height: 18
                                                    spacing: 2
                                                    Item { Layout.fillWidth: true }
                                                    WeatherIcon {
                                                        visible: !parent._isSun
                                                        iconInfo: IconResolver.resolve("precipsum", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                        iconSize: 16
                                                        iconColor: Kirigami.Theme.textColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: weatherRoot ? weatherRoot.precipSumText(modelData.precipMm) : "--"
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }
                                        }

                                        // ── Row 9: visibility ──────────────────────────
                                        Row {
                                            id: stripVisibilityRow
                                            x: 0; y: stripPrecipSumRow.visible ? (stripPrecipSumRow.y + stripPrecipSumRow.height + 2) : stripPrecipSumRow.y
                                            visible: forecastRoot._hourlyShowVisibility
                                            spacing: stripScrollView.colSpacing
                                            Repeater {
                                                model: stripScrollView._hourlyWithSun
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    readonly property bool _isSun: modelData.isSunrise === true || modelData.isSunset === true
                                                    width: stripScrollView.colW
                                                    height: 18
                                                    spacing: 2
                                                    Item { Layout.fillWidth: true }
                                                    WeatherIcon {
                                                        visible: !parent._isSun
                                                        iconInfo: IconResolver.resolve("visibility", 16, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                        iconSize: 16
                                                        iconColor: Kirigami.Theme.textColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: weatherRoot ? weatherRoot.visibilityValue(modelData.visibilityKm) : "--"
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(10, false) : Qt.font({})
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: stripScrollView
                                    acceptedButtons: Qt.NoButton
                                    onWheel: function(wheel) {
                                        if (forecastRoot._hourlyWheelWantsHorizontal(wheel)) {
                                            var delta = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : forecastRoot._wheelDeltaX(wheel);
                                            var pixelDelta = wheel.angleDelta.x === 0 && wheel.pixelDelta.x !== 0;
                                            if (delta === 0) {
                                                delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : forecastRoot._wheelDeltaY(wheel);
                                                pixelDelta = wheel.angleDelta.y === 0 && wheel.pixelDelta.y !== 0;
                                            }
                                            var maxX = Math.max(0, stripScrollView.contentWidth - stripScrollView.width);
                                            var targetX = pixelDelta
                                                ? Math.max(0, Math.min(maxX, stripScrollView.contentX - delta))
                                                : Math.max(0, Math.min(maxX, stripScrollView.contentX - (delta / 120) * stripScrollView.colW * 2));
                                            stripWheelAnimation.to = targetX;
                                            stripWheelAnimation.restart();
                                            wheel.accepted = true;
                                        } else {
                                            wheel.accepted = forecastRoot._scrollParentVertically(wheel);
                                        }
                                    }
                                }
                            }
                        }

                        Component {
                            id: cardsHourlyComponent
                            Item {
                                anchors.fill: parent

                                // ── CARDS LAYOUT ───────────────────────────────────
                                ScrollView {
                                    id: hourlyScrollView
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    clip: true
                                    // ScrollView itself does not have flickableDirection.
                                    // This property needs to be set on the internal flickableItem.
                                    Component.onCompleted: {
                                        if (hourlyScrollView.flickableItem) {
                                            hourlyScrollView.flickableItem.flickableDirection = Flickable.HorizontalFlick;
                                        }
                                    }
                                    contentWidth: hourlyRow.implicitWidth
                                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                                    NumberAnimation {
                                        id: hourlyWheelAnimation
                                        target: hourlyScrollView.ScrollBar.horizontal
                                        property: "position"
                                        duration: 140
                                        easing.type: Easing.OutCubic
                                    }

                                    // Auto-scroll to current hour for "Today" (index === 0)
                                    Timer {
                                        id: scrollTimer
                                        interval: 150
                                        onTriggered: {
                                            if (index !== 0 || !_dayHourlyData.length) return;
                                            var now = new Date();
                                            var currentTotalMins = now.getHours() * 60 + now.getMinutes();
                                            var closestIdx = 0;
                                            var minDiff = 86400;
                                            for (var i = 0; i < _dayHourlyData.length; i++) {
                                                var h = _dayHourlyData[i].hour;
                                                if (!h) continue;
                                                var parts = h.split(":");
                                                if (parts.length < 2) continue;
                                                var hm = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                                                var diff = Math.abs(hm - currentTotalMins);
                                                if (diff < minDiff) {
                                                    minDiff = diff;
                                                    closestIdx = i;
                                                }
                                            }
                                            if (forecastRoot.showSunEvents && _daySunriseText && _daySunsetText) {
                                                function toMins(t) {
                                                    if (!t || t === "--") return -1;
                                                    var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                                }
                                                var rise = toMins(_daySunriseText);
                                                var set_ = toMins(_daySunsetText);
                                                var targetMins = closestIdx < _dayHourlyData.length ? toMins(_dayHourlyData[closestIdx].hour) : -1;
                                                if (rise >= 0 && targetMins >= 0 && rise < targetMins) closestIdx++;
                                                if (set_ >= 0 && targetMins >= 0 && set_ < targetMins) closestIdx++;
                                            }
                                            var hourlyWidth = forecastRoot._hourlyCardWidth;
                                            var sunWidth = 70;
                                            var spacing = 6;
                                            var scrollPos = 0;
                                            if (forecastRoot.showSunEvents && _daySunriseText && _daySunsetText) {
                                                function toMins2(t) {
                                                    if (!t || t === "--") return -1;
                                                    var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                                }
                                                var rise2 = toMins2(_daySunriseText);
                                                var set2 = toMins2(_daySunsetText);
                                                for (var j = 0; j < closestIdx; j++) {
                                                    var hm2 = toMins2(_dayHourlyData[j].hour);
                                                    if (rise2 >= 0 && hm2 > rise2) { scrollPos += sunWidth + spacing; rise2 = -1; }
                                                    if (set2 >= 0 && hm2 > set2) { scrollPos += sunWidth + spacing; set2 = -1; }
                                                    scrollPos += hourlyWidth + spacing;
                                                }
                                            } else {
                                                scrollPos = closestIdx * (hourlyWidth + spacing);
                                            }
                                            var bar = hourlyScrollView.ScrollBar.horizontal;
                                            if (!bar) return;
                                            var contentW = hourlyRow.implicitWidth || hourlyRow.width || (_dayHourlyData.length * (hourlyWidth + spacing));
                                            var viewW = hourlyScrollView.width;
                                            if (contentW > viewW) {
                                                var maxPos = Math.max(0, contentW - viewW);
                                                var targetPos = Math.min(scrollPos, maxPos);
                                                bar.position = targetPos / contentW;
                                            }
                                        }
                                    }
                                    Connections {
                                        target: weatherRoot
                                        function onHourlyDataChanged() {
                                            if (index !== 0 || !_dayHourlyData.length) return;
                                            scrollTimer.start();
                                        }
                                    }

                                    Row {
                                        id: hourlyRow
                                        spacing: 6
                                        height: parent.height

                                        // Build combined model: hourly entries + sunrise/sunset marker cards
                                        // inserted between the hour that precedes each event.
                                        property var _hourlyWithSun: {
                                            if (!_dayHourlyData || !_dayHourlyData.length) return [];
                                            function toMins(t) {
                                                if (!t || t === "--") return -1;
                                                var p = t.split(":"); return p.length < 2 ? -1 : parseInt(p[0],10)*60+parseInt(p[1],10);
                                            }
                                            // For today (index 0) filter out past hours; keep 1 hour buffer
                                            var nowMins = -1;
                                            if (index === 0) {
                                                var _now = new Date();
                                                nowMins = _now.getHours() * 60 + _now.getMinutes() - 60;
                                            }
                                            var source = nowMins >= 0
                                                ? _dayHourlyData.filter(function(h) { var m = toMins(h.hour); return m < 0 || m >= nowMins; })
                                                : _dayHourlyData;
                                            if (!forecastRoot.showSunEvents)
                                                return source;
                                            var rise = toMins(_daySunriseText);
                                            var set_ = toMins(_daySunsetText);
                                            var riseInserted = rise < 0 || (nowMins >= 0 && rise < nowMins);
                                            var setInserted  = set_  < 0 || (nowMins >= 0 && set_  < nowMins);
                                            var result = [];
                                            source.forEach(function(h) {
                                                var hm = toMins(h.hour);
                                                if (!riseInserted && hm >= 0 && hm > rise) {
                                                    result.push({ isSunrise: true,  isSunset: false, time: _daySunriseText });
                                                    riseInserted = true;
                                                }
                                                if (!setInserted && hm >= 0 && hm > set_) {
                                                    result.push({ isSunset: true,  isSunrise: false, time: _daySunsetText });
                                                    setInserted = true;
                                                }
                                                result.push(h);
                                            });
                                            return result;
                                        }

                                        Repeater {
                                            model: parent._hourlyWithSun

                                            delegate: Rectangle {
                                                required property var modelData
                                                // Sunrise/sunset cards are slim; hourly cards are full height
                                                width: (modelData.isSunrise || modelData.isSunset) ? 70 : forecastRoot._hourlyCardWidth
                                                height: forecastRoot._hourlyCardHeight
                                                radius: 8
                                                color: (modelData.isSunrise || modelData.isSunset)
                                                    ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                                                    : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                                                border.width: 1

                                                // ── Sunrise / Sunset card ─────────────────────────────
                                                ColumnLayout {
                                                    visible: modelData.isSunrise === true || modelData.isSunset === true
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    WeatherIcon {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        iconInfo: IconResolver.resolve(
                                                            modelData.isSunrise ? "sunrise" : "sunset",
                                                            32,
                                                            forecastRoot.iconsBaseDir,
                                                            forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                            (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom" || forecastRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : forecastRoot.widgetIconTheme)
                                                        iconSize: 32
                                                        iconColor: Kirigami.Theme.textColor
                                                    }
                                                    Label {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: weatherRoot ? weatherRoot.formatTimeForDisplay(modelData.time) : "--"
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(10, true) : Qt.font({ bold: true })
                                                    }
                                                }

                                                // ── Regular hourly card ───────────────────────────────
                                                ColumnLayout {
                                                    visible: !(modelData.isSunrise === true || modelData.isSunset === true)
                                                    anchors {
                                                        fill: parent
                                                        margins: 6
                                                    }
                                                    spacing: 4

                                                    Label {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: {
                                                            if (!modelData.hour || modelData.hour === "--")
                                                                return "--";
                                                            var parts = modelData.hour.split(":");
                                                            if (parts.length < 2)
                                                                return modelData.hour;
                                                            var h = parseInt(parts[0], 10);
                                                            var m = parseInt(parts[1], 10);
                                                            if (isNaN(h) || isNaN(m))
                                                                return modelData.hour;
                                                            var d = new Date();
                                                            d.setHours(h, m, 0, 0);
                                                            return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
                                                        }
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                    }

                                                    WeatherIcon {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        iconInfo: {
                                                            // Derive night flag from the hour vs sunrise/sunset
                                                            var isNight = false;
                                                            if (modelData.hour && modelData.hour !== "--") {
                                                                var parts = modelData.hour.split(":");
                                                                if (parts.length >= 2) {
                                                                    var hMins = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                                                                    function parseSunMins(t) {
                                                                        if (!t || t === "--") return -1;
                                                                        var p = t.split(":");
                                                                        return p.length < 2 ? -1 : parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
                                                                    }
                                                                    var rise = parseSunMins(_daySunriseText);
                                                                    var set_ = parseSunMins(_daySunsetText);
                                                                    if (rise >= 0 && set_ >= 0)
                                                                        isNight = hMins < rise || hMins >= set_;
                                                                }
                                                            }
                                                            return forecastRoot.resolveConditionIcon(
                                                                modelData.code || 0, isNight,
                                                                forecastRoot.iconSz);
                                                        }
                                                        iconSize: 48
                                                    }

                                                    Label {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: weatherRoot ? weatherRoot.tempValue(modelData.tempC) : "--"
                                                        color: Kirigami.Theme.textColor
                                                        font: weatherRoot ? weatherRoot.wf(11, true) : Qt.font({ bold: true })
                                                    }

                                                    RowLayout {
                                                        visible: forecastRoot._hourlyShowWind
                                                        Layout.alignment: Qt.AlignHCenter
                                                        spacing: 4
                                                        Label {
                                                            text: weatherRoot && modelData.windKmh !== undefined ? weatherRoot.windValue(modelData.windKmh) : "--"
                                                            color: Kirigami.Theme.textColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        }
                                                        Text {
                                                            visible: weatherRoot && !isNaN(modelData.windDeg)
                                                            text: W.windDirectionGlyph(modelData.windDeg)
                                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                            font.pixelSize: 20
                                                            color: Kirigami.Theme.textColor
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                    }

                                                    RowLayout {
                                                        visible: forecastRoot._hourlyShowPressure
                                                        Layout.alignment: Qt.AlignHCenter
                                                        spacing: 3
                                                        WeatherIcon {
                                                            iconInfo: IconResolver.resolve("pressure", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                            iconSize: 24
                                                            iconColor: Kirigami.Theme.textColor
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                        Label {
                                                            text: weatherRoot ? weatherRoot.pressureValue(modelData.pressureHpa) : "--"
                                                            color: Kirigami.Theme.textColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        }
                                                    }

                                                    RowLayout {
                                                        visible: forecastRoot._hourlyShowKpIndex
                                                        Layout.alignment: Qt.AlignHCenter
                                                        spacing: 3
                                                        WeatherIcon {
                                                            iconInfo: IconResolver.resolve("spaceweather", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                            iconSize: 24
                                                            iconColor: Kirigami.Theme.textColor
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                        Label {
                                                            text: {
                                                                if (!weatherRoot) return i18n("No info");
                                                                var d = weatherRoot.dailyData[dataIndex].dateStr || "";
                                                                var e = weatherRoot.kpForecastForHour(d, modelData.hour || "")
                                                                        || weatherRoot.kpForecastForDate(d);
                                                                if (!e || isNaN(e.kp)) return i18n("No info");
                                                                return "Kp " + e.kp.toFixed(1) + " (" + (e.gScale || "G0") + ")";
                                                            }
                                                            color: Kirigami.Theme.textColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        }
                                                    }

                                                    RowLayout {
                                                        visible: forecastRoot._hourlyShowUvIndex
                                                        Layout.alignment: Qt.AlignHCenter
                                                        spacing: 3
                                                        WeatherIcon {
                                                            iconInfo: IconResolver.resolve("uvindex", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                            iconSize: 24
                                                            iconColor: Kirigami.Theme.textColor
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                        Label {
                                                            text: {
                                                                var uv = modelData.uvIndex;
                                                                return (uv === undefined || isNaN(uv)) ? "--" : "UV " + uv.toFixed(1);
                                                            }
                                                            color: Kirigami.Theme.textColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        }
                                                    }

                                                    RowLayout {
                                                        visible: forecastRoot._hourlyShowPrecipSum
                                                        Layout.alignment: Qt.AlignHCenter
                                                        spacing: 3
                                                        WeatherIcon {
                                                            iconInfo: IconResolver.resolve("precipsum", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                            iconSize: 24
                                                            iconColor: Kirigami.Theme.textColor
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                        Label {
                                                            text: weatherRoot ? weatherRoot.precipSumText(modelData.precipMm) : "--"
                                                            color: Kirigami.Theme.textColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        }
                                                    }

                                                    RowLayout {
                                                        visible: forecastRoot._hourlyShowVisibility
                                                        Layout.alignment: Qt.AlignHCenter
                                                        spacing: 3
                                                        WeatherIcon {
                                                            iconInfo: IconResolver.resolve("visibility", 24, forecastRoot.iconsBaseDir, forecastRoot.itemsIconTheme)
                                                            iconSize: 24
                                                            iconColor: Kirigami.Theme.textColor
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                        Label {
                                                            text: weatherRoot ? weatherRoot.visibilityValue(modelData.visibilityKm) : "--"
                                                            color: Kirigami.Theme.textColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        }
                                                    }

                                                    RowLayout {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        spacing: 3
                                                        WeatherIcon {
                                                            iconInfo: IconResolver.resolve("umbrella", 32, forecastRoot.iconsBaseDir,
                                                                forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                                (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom" || forecastRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : forecastRoot.widgetIconTheme)
                                                            iconSize: 32
                                                            iconColor: Kirigami.Theme.textColor
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                        Label {
                                                            text: {
                                                                var ppText = W.hourlyPrecipProbText(modelData.precipProb, modelData.code);
                                                                if (ppText !== null) return ppText;
                                                                var h = modelData.humidity;
                                                                return (!isNaN(h) && h !== undefined) ? Math.round(h) + "%" : "--";
                                                            }
                                                            color: Kirigami.Theme.textColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                        }
                                                    }

                                                    RowLayout {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        spacing: -5
                                                        // Open-Meteo can report a trace precip amount (e.g. 0.1 mm)
                                                        // for an hour whose weather code and probability are dry.
                                                        // Only show the rate when the code itself implies precipitation,
                                                        // so it doesn't contradict a clear/sunny icon at 0% probability.
                                                        visible: modelData.precipMm !== undefined && !isNaN(modelData.precipMm)
                                                                 && modelData.precipMm > 0 && W.isPrecipCode(modelData.code)
                                                        WeatherIcon {
                                                            iconInfo: IconResolver.resolve("preciprate", 32, forecastRoot.iconsBaseDir,
                                                                forecastRoot.widgetIconTheme === "kde" ? "flat-color" :
                                                                (forecastRoot.widgetIconTheme === "wi-font" || forecastRoot.widgetIconTheme === "custom" || forecastRoot.widgetIconTheme === "kde-symbolic") ? "symbolic" : forecastRoot.widgetIconTheme)
                                                            iconSize: 32
                                                            iconColor: Kirigami.Theme.textColor
                                                            opacity: 0.6
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                        Label {
                                                            text: weatherRoot ? weatherRoot.precipValue(modelData.precipMm) : "--"
                                                            color: Kirigami.Theme.textColor
                                                            opacity: 0.6
                                                            font: weatherRoot ? weatherRoot.wf(8, false) : Qt.font({})
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: hourlyScrollView
                                    acceptedButtons: Qt.NoButton
                                    onWheel: function(wheel) {
                                        var bar = hourlyScrollView.ScrollBar.horizontal;
                                        if (!bar)
                                            return;
                                        if (forecastRoot._hourlyWheelWantsHorizontal(wheel)) {
                                            var delta = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : forecastRoot._wheelDeltaX(wheel);
                                            var pixelDelta = wheel.angleDelta.x === 0 && wheel.pixelDelta.x !== 0;
                                            if (delta === 0) {
                                                delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : forecastRoot._wheelDeltaY(wheel);
                                                pixelDelta = wheel.angleDelta.y === 0 && wheel.pixelDelta.y !== 0;
                                            }
                                            var maxPos = Math.max(0, 1.0 - bar.size);
                                            var targetPos = pixelDelta
                                                ? Math.max(0, Math.min(maxPos, bar.position - delta / Math.max(1, hourlyRow.implicitWidth)))
                                                : Math.max(0, Math.min(maxPos, bar.position - (delta / 120) * 0.15));
                                            hourlyWheelAnimation.to = targetPos;
                                            hourlyWheelAnimation.restart();
                                            wheel.accepted = true;
                                        } else {
                                            wheel.accepted = forecastRoot._scrollParentVertically(wheel);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                    }
                }
            }
        }
    }
