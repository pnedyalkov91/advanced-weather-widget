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
    readonly property color themeTextColor: Kirigami.Theme.textColor
    readonly property color themeBackgroundColor: Kirigami.Theme.backgroundColor
    property var weatherRoot
    property var verticalScrollView
    property int expandedIndex: -1
    property int _singleExpandFetchGeneration: 0
    property bool _needsForecastReset: true

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
    property var _viewportPrefetchQueue: []
    property bool _viewportPrefetchInFlight: false
    property string _viewportPrefetchActiveDate: ""
    property int _viewportPrefetchGeneration: 0
    readonly property int _viewportPrefetchRadius: 2
    property var _hourlyDataVersions: ({})
    property var _hourlyDisplayCache: ({})

    function _cancelExpandAllFetch(clearData) {
        _expandAllFetchGeneration++;
        _expandAllQueue = [];
        _expandAllActiveFetches = 0;
        expandAllFetchPump.stop();
        _loadingDays = {};
        if (clearData) {
            _perDayHourlyData = {};
            _hourlyDataVersions = {};
            _hourlyDisplayCache = {};
        }
    }

    function _cancelViewportPrefetch() {
        _viewportPrefetchGeneration++;
        _viewportPrefetchQueue = [];
        if (_viewportPrefetchActiveDate) {
            var loadDone = Object.assign({}, _loadingDays);
            delete loadDone[_viewportPrefetchActiveDate];
            _loadingDays = loadDone;
        }
        viewportPrefetchPump.stop();
        viewportPrefetchDebounce.stop();
    }

    function _activeHourlyProvider() {
        var provider = Plasmoid.configuration.weatherProvider || "adaptive";
        return provider === "adaptive" ? "openMeteo" : provider;
    }

    function _hourlyCoverageHours() {
        var provider = _activeHourlyProvider();
        if (provider === "qWeather")
            return 168;
        if (provider === "weatherbit")
            return 48;
        return 0;
    }

    function _isDateOutsideHourlyCoverage(dateStr) {
        var hours = _hourlyCoverageHours();
        if (hours <= 0 || !dateStr)
            return false;
        var targetStartMs = weatherRoot ? weatherRoot.locationDateTimeToEpoch(dateStr, "00:00") : NaN;
        if (isNaN(targetStartMs))
            return false;
        var horizon = new Date(Date.now() + hours * 60 * 60 * 1000);
        return targetStartMs > horizon.getTime();
    }

    function _emptyHourlyMessage(dateStr) {
        if (_isDateOutsideHourlyCoverage(dateStr)) {
            var provider = _activeHourlyProvider();
            if (provider === "qWeather")
                return i18n("QWeather provides hourly forecasts for up to 168 hours (7 days). Daily forecast is still available for this date.");
            if (provider === "weatherbit")
                return i18n("Weatherbit provides hourly forecasts for up to 48 hours. Daily forecast is still available for this date.");
        }
        return i18n("No hourly data available");
    }

    function _forecastModelCount() {
        if (!weatherRoot || weatherRoot.dailyData.length === 0)
            return 0;
        return weatherRoot.forecastDisplayCount(showToday, Plasmoid.configuration.forecastDays);
    }

    function _viewIndexToDataIndex(viewIndex) {
        return weatherRoot ? (weatherRoot.firstForecastDataIndex(showToday) + viewIndex) : viewIndex;
    }

    function _dateStrForViewIndex(viewIndex) {
        var dataIndex = _viewIndexToDataIndex(viewIndex);
        if (!weatherRoot || !weatherRoot.dailyData[dataIndex])
            return "";
        return weatherRoot.dailyData[dataIndex].dateStr || "";
    }

    function _queueViewportPrefetch() {
        if (expandAll || !visible || !weatherRoot)
            return;

        _cancelViewportPrefetch();

        var modelCount = _forecastModelCount();
        if (modelCount === 0)
            return;

        var firstVisible = 0;
        var lastVisible = Math.min(modelCount - 1, 1);
        if (forecastListView) {
            firstVisible = forecastListView.indexAt(8, forecastListView.contentY + 1);
            if (firstVisible < 0)
                firstVisible = 0;
            lastVisible = forecastListView.indexAt(8, forecastListView.contentY + forecastListView.height - 2);
            if (lastVisible < 0)
                lastVisible = Math.min(modelCount - 1, firstVisible + 2);
        }

        if (expandedIndex >= 0) {
            firstVisible = Math.min(firstVisible, expandedIndex);
            lastVisible = Math.max(lastVisible, expandedIndex);
        }

        firstVisible = Math.max(0, firstVisible - 1);
        lastVisible = Math.min(modelCount - 1, lastVisible + _viewportPrefetchRadius);

        var queue = [];
        for (var viewIndex = firstVisible; viewIndex <= lastVisible; viewIndex++) {
            var dateStr = _dateStrForViewIndex(viewIndex);
            if (!dateStr)
                continue;
            if (_isDateOutsideHourlyCoverage(dateStr)) {
                _storeHourlyData(dateStr, []);
                continue;
            }
            if (Object.prototype.hasOwnProperty.call(_perDayHourlyData, dateStr) || _loadingDays[dateStr])
                continue;
            queue.push(dateStr);
        }

        if (queue.length === 0)
            return;

        _viewportPrefetchQueue = queue;
        viewportPrefetchPump.restart();
    }

    function _pumpViewportPrefetchQueue() {
        if (expandAll || !visible || !weatherRoot || _viewportPrefetchInFlight)
            return;

        var generation = _viewportPrefetchGeneration;
        while (_viewportPrefetchQueue.length > 0) {
            var dateStr = _viewportPrefetchQueue.shift();
            if (!dateStr)
                continue;
            if (Object.prototype.hasOwnProperty.call(_perDayHourlyData, dateStr) || _loadingDays[dateStr])
                continue;

            _viewportPrefetchInFlight = true;
            _viewportPrefetchActiveDate = dateStr;
            var loading = Object.assign({}, _loadingDays);
            loading[dateStr] = true;
            _loadingDays = loading;

            (function(ds, gen) {
                weatherRoot.fetchHourlyForDateDirect(ds, function(hourlyArr) {
                    var loadDone = Object.assign({}, forecastRoot._loadingDays);
                    delete loadDone[ds];
                    forecastRoot._loadingDays = loadDone;
                    if (forecastRoot._viewportPrefetchActiveDate === ds)
                        forecastRoot._viewportPrefetchActiveDate = "";
                    forecastRoot._viewportPrefetchInFlight = false;
                    if (gen !== forecastRoot._viewportPrefetchGeneration) {
                        if (forecastRoot._viewportPrefetchQueue.length > 0)
                            viewportPrefetchPump.restart();
                        return;
                    }
                    forecastRoot._storeHourlyData(ds, hourlyArr);
                    if (forecastRoot._viewportPrefetchQueue.length > 0)
                        viewportPrefetchPump.restart();
                });
            })(dateStr, generation);
            break;
        }
    }

    function _timeToMinutes(timeText) {
        if (!timeText || timeText === "--")
            return -1;
        var parts = timeText.split(":");
        if (parts.length < 2)
            return -1;
        var hours = parseInt(parts[0], 10);
        var minutes = parseInt(parts[1], 10);
        if (isNaN(hours) || isNaN(minutes))
            return -1;
        return hours * 60 + minutes;
    }

    function _formatHourForDisplay(timeText) {
        if (!timeText || timeText === "--")
            return "--";
        var parts = timeText.split(":");
        if (parts.length < 2)
            return timeText;
        var hours = parseInt(parts[0], 10);
        var minutes = parseInt(parts[1], 10);
        if (isNaN(hours) || isNaN(minutes))
            return timeText;
        var date = new Date();
        date.setHours(hours, minutes, 0, 0);
        return Qt.formatTime(date, Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function _sunTimeTextForDay(dayData, sunrise) {
        if (!dayData)
            return "--";
        var daySpecific = sunrise ? dayData.sunriseTimeText : dayData.sunsetTimeText;
        if (daySpecific && daySpecific !== "--")
            return daySpecific;
        if (!weatherRoot)
            return "--";
        return sunrise ? weatherRoot.sunriseTimeText : weatherRoot.sunsetTimeText;
    }

    function _storeHourlyData(dateStr, hourlyArr) {
        var dataUpd = Object.assign({}, _perDayHourlyData);
        dataUpd[dateStr] = hourlyArr || [];
        _perDayHourlyData = dataUpd;

        var versions = Object.assign({}, _hourlyDataVersions);
        versions[dateStr] = (versions[dateStr] || 0) + 1;
        _hourlyDataVersions = versions;
        _hourlyDisplayCache = {};
    }

    function _seedHourlyDataFromPrefetch(dateStr) {
        if (!weatherRoot || !dateStr)
            return false;
        if (Object.prototype.hasOwnProperty.call(_perDayHourlyData, dateStr))
            return true;
        if (typeof weatherRoot.prefetchedHourlyForDate !== "function")
            return false;
        var prefetched = weatherRoot.prefetchedHourlyForDate(dateStr);
        if (prefetched === null || prefetched === undefined)
            return false;
        _storeHourlyData(dateStr, prefetched);
        return true;
    }

    function _initialAutoOpenDateStr() {
        if (!weatherRoot || weatherRoot.dailyData.length === 0 || expandAll || !autoOpen)
            return "";
        var firstDataIndex = weatherRoot.firstForecastDataIndex(forecastRoot.showToday);
        if (firstDataIndex >= weatherRoot.dailyData.length)
            return "";
        return weatherRoot.dailyData[firstDataIndex].dateStr || "";
    }

    function _primeInitialExpandedState() {
        var dateStr = _initialAutoOpenDateStr();
        if (!dateStr)
            return;
        expandedIndex = 0;
        _seedHourlyDataFromPrefetch(dateStr);
    }

    function _loadSingleExpandHourly(dateStr) {
        if (!weatherRoot || !dateStr)
            return;
        if (_seedHourlyDataFromPrefetch(dateStr))
            return;
        if (typeof weatherRoot.isHourlyPrefetchInFlight === "function"
                && weatherRoot.isHourlyPrefetchInFlight(dateStr)) {
            var prefetchedLoading = Object.assign({}, _loadingDays);
            prefetchedLoading[dateStr] = true;
            _loadingDays = prefetchedLoading;
            return;
        }
        if (Object.prototype.hasOwnProperty.call(_perDayHourlyData, dateStr))
            return;
        if (_loadingDays[dateStr])
            return;
        if (_isDateOutsideHourlyCoverage(dateStr)) {
            _storeHourlyData(dateStr, []);
            return;
        }

        _singleExpandFetchGeneration++;
        var generation = _singleExpandFetchGeneration;
        var loading = Object.assign({}, _loadingDays);
        loading[dateStr] = true;
        _loadingDays = loading;

        weatherRoot.fetchHourlyForDateDirect(dateStr, function(hourlyArr) {
            var loadDone = Object.assign({}, forecastRoot._loadingDays);
            delete loadDone[dateStr];
            forecastRoot._loadingDays = loadDone;
            if (generation !== forecastRoot._singleExpandFetchGeneration)
                return;
            forecastRoot._storeHourlyData(dateStr, hourlyArr);
        });
    }

    function _hourlyDisplayItems(dayData, hourlyData, dataIndex) {
        if (!dayData || !hourlyData || hourlyData.length === 0)
            return [];

        var dateStr = dayData.dateStr || "";
        var sunriseText = _sunTimeTextForDay(dayData, true);
        var sunsetText = _sunTimeTextForDay(dayData, false);
        var cacheKey = [
            dateStr,
            _hourlyDataVersions[dateStr] || 0,
            showSunEvents ? 1 : 0,
            (weatherRoot && dateStr === weatherRoot.locationDateString()) ? 1 : 0,
            sunriseText,
            sunsetText
        ].join("|");
        if (Object.prototype.hasOwnProperty.call(_hourlyDisplayCache, cacheKey))
            return _hourlyDisplayCache[cacheKey];

        var nowMins = -1;
        var todayStr = weatherRoot ? weatherRoot.locationDateString() : "";
        if (dateStr.length > 0 && dateStr === todayStr)
            nowMins = (weatherRoot ? weatherRoot.locationNowMins() : -1) - 60;

        var sunriseMins = _timeToMinutes(sunriseText);
        var sunsetMins = _timeToMinutes(sunsetText);

        var source = [];
        for (var index = 0; index < hourlyData.length; index++) {
            var hourly = hourlyData[index];
            var mins = _timeToMinutes(hourly.hour);
            if (nowMins >= 0 && mins >= 0 && mins < nowMins)
                continue;
            source.push(hourly);
        }

        var items = [];
        var riseInserted = !showSunEvents || sunriseMins < 0 || (nowMins >= 0 && sunriseMins < nowMins);
        var setInserted = !showSunEvents || sunsetMins < 0 || (nowMins >= 0 && sunsetMins < nowMins);
        var firstHourly = true;

        function pushSunItem(isSunriseItem, timeText) {
            items.push({
                key: dateStr + "|" + (isSunriseItem ? "sunrise" : "sunset") + "|" + timeText,
                isSunrise: isSunriseItem,
                isSunset: !isSunriseItem,
                time: timeText,
                displayTime: weatherRoot ? weatherRoot.formatTimeForDisplay(timeText) : timeText,
                autoScrollTarget: false
            });
        }

        for (var sourceIndex = 0; sourceIndex < source.length; sourceIndex++) {
            var sourceHourly = source[sourceIndex];
            var hourMins = _timeToMinutes(sourceHourly.hour);
            if (!riseInserted && hourMins >= 0 && hourMins > sunriseMins) {
                pushSunItem(true, sunriseText);
                riseInserted = true;
            }
            if (!setInserted && hourMins >= 0 && hourMins > sunsetMins) {
                pushSunItem(false, sunsetText);
                setInserted = true;
            }

            var item = {};
            for (var key in sourceHourly)
                item[key] = sourceHourly[key];
            item.key = dateStr + "|hour|" + (sourceHourly.hour || sourceIndex);
            item.isSunrise = false;
            item.isSunset = false;
            item.displayTime = _formatHourForDisplay(sourceHourly.hour);
            item.isNight = hourMins >= 0 && sunriseMins >= 0 && sunsetMins >= 0
                ? (hourMins < sunriseMins || hourMins >= sunsetMins)
                : false;
            item.tempText = weatherRoot ? weatherRoot.tempValue(sourceHourly.tempC) : "--";
            item.windText = weatherRoot ? weatherRoot.windValue(sourceHourly.windKmh) : "--";
            item.pressureText = weatherRoot ? weatherRoot.pressureValue(sourceHourly.pressureHpa) : "--";
            var kpEntry = weatherRoot
                ? (weatherRoot.kpForecastForHour(dateStr, sourceHourly.hour || "") || weatherRoot.kpForecastForDate(dateStr))
                : null;
            item.kpText = (!kpEntry || kpEntry.kp === null || kpEntry.kp === undefined || isNaN(kpEntry.kp))
                ? i18n("No info")
                : "Kp " + kpEntry.kp.toFixed(1) + " (" + (kpEntry.gScale || "G0") + ")";
            item.uvText = (sourceHourly.uvIndex === null || sourceHourly.uvIndex === undefined || isNaN(sourceHourly.uvIndex))
                ? "--"
                : "UV " + sourceHourly.uvIndex.toFixed(1);
            item.precipText = weatherRoot ? weatherRoot.precipSumText(sourceHourly.precipMm) : "--";
            item.visibilityText = weatherRoot ? weatherRoot.visibilityValue(sourceHourly.visibilityKm) : "--";
            var precipProbText = W.hourlyPrecipProbText(sourceHourly.precipProb, sourceHourly.code);
            var humidityText = (!isNaN(sourceHourly.humidity) && sourceHourly.humidity !== undefined)
                ? Math.round(sourceHourly.humidity) + "%"
                : "--";
            item.precipDisplayText = precipProbText !== null ? precipProbText : humidityText;
            item.precipRateVisible = sourceHourly.precipMm !== undefined
                && !isNaN(sourceHourly.precipMm)
                && sourceHourly.precipMm > 0
                && W.isPrecipCode(sourceHourly.code);
            item.precipRateText = weatherRoot ? weatherRoot.precipValue(sourceHourly.precipMm) : "--";
            item.autoScrollTarget = firstHourly;
            firstHourly = false;
            items.push(item);
        }

        _hourlyDisplayCache[cacheKey] = items;
        return items;
    }

    function _startExpandAll() {
        if (!weatherRoot || weatherRoot.dailyData.length === 0) return;
        _expandAllFetchGeneration++;
        _expandAllQueue = [];
        _expandAllActiveFetches = 0;
        _perDayHourlyData = {};
        var loading = {};
        var startDi  = weatherRoot.firstForecastDataIndex(forecastRoot.showToday);
        var endDi    = Math.min(weatherRoot.dailyData.length, startDi + Plasmoid.configuration.forecastDays);
        for (var di = startDi; di < endDi; di++) {
            var dateStr = weatherRoot.dailyData[di].dateStr || "";
            if (!dateStr) continue;
            if (_isDateOutsideHourlyCoverage(dateStr)) {
                _storeHourlyData(dateStr, []);
                continue;
            }
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
                    forecastRoot._storeHourlyData(ds, hourlyArr);
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

    Timer {
        id: viewportPrefetchPump
        interval: 80
        repeat: false
        onTriggered: forecastRoot._pumpViewportPrefetchQueue()
    }

    Timer {
        id: viewportPrefetchDebounce
        interval: 120
        repeat: false
        onTriggered: forecastRoot._queueViewportPrefetch()
    }

    function activateForecast() {
        _autoOpenDone = false;
        _collapsedDays = {};
        _loadingDays = {};
        _cancelViewportPrefetch();
        if (expandAll) {
            _autoOpenDone = true;
            _perDayHourlyData = {};
            _hourlyDataVersions = {};
            _hourlyDisplayCache = {};
            _startExpandAll();
        } else {
            _cancelExpandAllFetch(false);
            var dateStr = _initialAutoOpenDateStr();
            if (expandedIndex === 0 && dateStr) {
                _autoOpenDone = true;
                _loadSingleExpandHourly(dateStr);
                viewportPrefetchDebounce.restart();
            } else {
                _doAutoOpen();
            }
        }
        _needsForecastReset = false;
    }

    onExpandAllChanged: {
        if (expandAll) {
            expandedIndex = -1;
            _autoOpenDone = true;
            _collapsedDays = {};
            _loadingDays   = {};
            _singleExpandFetchGeneration++;
            _cancelViewportPrefetch();
            if (visible && weatherRoot && weatherRoot.dailyData.length > 0)
                _startExpandAll();
        } else {
            _cancelExpandAllFetch(true);
            _collapsedDays = {};
            _autoOpenDone = false;
            _singleExpandFetchGeneration++;
            _cancelViewportPrefetch();
            if (visible)
                _doAutoOpen();
        }
    }

    onExpandedIndexChanged: {
        if (!expandAll && visible)
            viewportPrefetchDebounce.restart();
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
        var firstDataIndex = weatherRoot.firstForecastDataIndex(forecastRoot.showToday);
        if (firstDataIndex >= weatherRoot.dailyData.length) return;
        forecastRoot.expandedIndex = 0;
        forecastRoot._loadSingleExpandHourly(weatherRoot.dailyData[firstDataIndex].dateStr || "");
        viewportPrefetchDebounce.restart();
    }

    onVisibleChanged: {
        if (visible) {
            if (_needsForecastReset) {
                activateForecast();
            } else if (!expandAll) {
                viewportPrefetchDebounce.restart();
            }
        } else {
            _cancelExpandAllFetch(false);
            _cancelViewportPrefetch();
        }
    }

    Connections {
        target: weatherRoot
        function onDailyDataChanged() {
            forecastRoot._needsForecastReset = true;
            if (!forecastRoot.visible) {
                forecastRoot._autoOpenDone = false;
                forecastRoot._singleExpandFetchGeneration++;
                forecastRoot._cancelExpandAllFetch(true);
                forecastRoot._primeInitialExpandedState();
                return;
            }
            if (forecastRoot.expandAll) {
                // expandAll always re-fetches when new data arrives —
                // independent of autoOpen and _autoOpenDone.
                forecastRoot._perDayHourlyData = {};
                forecastRoot._hourlyDataVersions = {};
                forecastRoot._hourlyDisplayCache = {};
                forecastRoot._loadingDays      = {};
                forecastRoot._startExpandAll();
            } else {
                forecastRoot._singleExpandFetchGeneration++;
                forecastRoot._perDayHourlyData = {};
                forecastRoot._hourlyDataVersions = {};
                forecastRoot._hourlyDisplayCache = {};
                forecastRoot._loadingDays = {};
                forecastRoot._cancelViewportPrefetch();
                var dataIndex = forecastRoot.showToday
                    ? forecastRoot.expandedIndex
                    : forecastRoot.expandedIndex + 1;
                if (forecastRoot.expandedIndex >= 0 && dataIndex >= 0 && dataIndex < weatherRoot.dailyData.length) {
                    forecastRoot._autoOpenDone = true;
                    forecastRoot._loadSingleExpandHourly(weatherRoot.dailyData[dataIndex].dateStr || "");
                    viewportPrefetchDebounce.restart();
                } else {
                    forecastRoot.expandedIndex = -1;
                    forecastRoot._autoOpenDone = false;
                    forecastRoot._doAutoOpen();
                }
            }
        }

        function onPrefetchedHourlyByDateChanged() {
            if (!forecastRoot.visible) {
                forecastRoot._primeInitialExpandedState();
                return;
            }
            if (forecastRoot.expandAll || forecastRoot.expandedIndex < 0)
                return;

            var dataIndex = forecastRoot.showToday
                ? forecastRoot.expandedIndex
                : forecastRoot.expandedIndex + 1;
            if (dataIndex < 0 || dataIndex >= weatherRoot.dailyData.length)
                return;

            var dateStr = weatherRoot.dailyData[dataIndex].dateStr || "";
            if (!forecastRoot._seedHourlyDataFromPrefetch(dateStr))
                return;

            var loadDone = Object.assign({}, forecastRoot._loadingDays);
            delete loadDone[dateStr];
            forecastRoot._loadingDays = loadDone;
        }
    }

    Component.onCompleted: {
        if (!visible)
            _primeInitialExpandedState();
    }

    implicitHeight: parent ? parent.height : 220

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
        var scrollTarget = verticalScrollView ? verticalScrollView : forecastListView;
        if (!scrollTarget)
            return false;
        var delta = _wheelDeltaY(wheel);
        if (delta === 0)
            return false;
        var scale = wheel.pixelDelta.y !== 0 ? 1 : 0.5;
        var amount = delta * scale;

        var flick = scrollTarget.flickableItem || scrollTarget.contentItem || scrollTarget;
        if (flick && flick.contentHeight !== undefined && flick.contentY !== undefined) {
            var maxY = Math.max(0, flick.contentHeight - flick.height);
            flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - amount));
            return true;
        }

        var bar = scrollTarget.ScrollBar ? scrollTarget.ScrollBar.vertical : null;
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
        color: forecastRoot.themeTextColor
        font: weatherRoot ? weatherRoot.wf(12, false) : Qt.font({})
    }

    ListView {
        id: forecastListView
        anchors.fill: parent
        clip: true
        visible: weatherRoot && weatherRoot.dailyData.length > 0
        model: forecastRoot._forecastModelCount()
        spacing: 0
        reuseItems: true
        cacheBuffer: height * 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AlwaysOff
        }
        onContentYChanged: viewportPrefetchDebounce.restart()
        onHeightChanged: viewportPrefetchDebounce.restart()
        onModelChanged: viewportPrefetchDebounce.restart()
        Component.onCompleted: viewportPrefetchDebounce.restart()

        delegate: Column {
                    required property int index
                    readonly property int dataIndex: forecastRoot._viewIndexToDataIndex(index)
                    width: ListView.view ? ListView.view.width : forecastRoot.width
                    spacing: 0

                    // Per-delegate hourly data: in expandAll mode pulls from the
                    // per-day cache; single-expand reuses the same date-keyed cache.
                    property var _dayHourlyData: {
                        var dateStr = (weatherRoot && weatherRoot.dailyData[dataIndex])
                            ? (weatherRoot.dailyData[dataIndex].dateStr || "") : "";
                        if (forecastRoot.expandAll && dateStr) {
                            if (forecastRoot._collapsedDays[dateStr]) return [];
                            return forecastRoot._perDayHourlyData[dateStr] || [];
                        }
                        if (!forecastRoot.expandAll && forecastRoot.expandedIndex === index && dateStr)
                            return forecastRoot._perDayHourlyData[dateStr] || [];
                        return [];
                    }

                    property var _dayDisplayItems: forecastRoot._hourlyDisplayItems(
                        weatherRoot && weatherRoot.dailyData[dataIndex] ? weatherRoot.dailyData[dataIndex] : null,
                        _dayHourlyData,
                        dataIndex)

                    readonly property bool _dayIsLoading: {
                        var dateStr = (weatherRoot && weatherRoot.dailyData[dataIndex])
                            ? (weatherRoot.dailyData[dataIndex].dateStr || "") : "";
                        if (forecastRoot.expandAll && dateStr && !forecastRoot._collapsedDays[dateStr])
                            return !!forecastRoot._loadingDays[dateStr];
                        if (!forecastRoot.expandAll && forecastRoot.expandedIndex === index && dateStr)
                            return !!forecastRoot._loadingDays[dateStr];
                        return false;
                    }

                    // ── day row ─────────────────────────────────────────
                    Rectangle {
                        id: dayRow
                        width: parent.width
                        height: Math.max(52, rowLayoutInner.implicitHeight + 12)
                        color: (rowMouse.containsMouse || (forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) ? Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.08) : "transparent"
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
                                        var ds = weatherRoot.dailyData[dataIndex].dateStr || "";
                                        if (weatherRoot && ds === weatherRoot.locationDateString())
                                            return i18n("Today");
                                        if (!ds)
                                            return "";
                                        return weatherRoot ? weatherRoot.dayNameForDateStr(ds, Locale.LongFormat) : "";
                                    }
                                    color: forecastRoot.themeTextColor
                                    font: weatherRoot.wf(12, true)
                                }
                                Label {
                                    text: {
                                        var ds = weatherRoot.dailyData[dataIndex].dateStr || "";
                                        if (!ds)
                                            return "";
                                        return weatherRoot
                                            ? weatherRoot.formatDateStrForDisplay(ds, Qt.locale().dateFormat(Locale.ShortFormat))
                                            : "";
                                    }
                                    color: forecastRoot.themeTextColor
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
                                color: forecastRoot.themeTextColor
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
                                        color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                        font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                        font.pixelSize: forecastRoot.iconSz
                                    }
                                }

                                Label {
                                    text: weatherRoot.windValue(weatherRoot.dailyData[dataIndex].windKmh)
                                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
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
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
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
                                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._kpVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
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
                                        if (!e || e.kp === null || e.kp === undefined || isNaN(e.kp)) return i18n("No information");
                                        return "Kp " + e.kp.toFixed(1) + " (" + (e.gScale || "G0") + ")";
                                    }
                                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._uvVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
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
                                        return (uv === null || uv === undefined || isNaN(uv)) ? "--" : "UV " + uv.toFixed(1);
                                    }
                                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._precipVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
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
                                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._visibilityVisible && (rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible || rowLayoutInner._precipVisible)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "•"
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
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
                                    color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.72)
                                    font: weatherRoot.wf(10, false)
                                }
                            }

                            Label {
                                visible: rowLayoutInner._windVisible || rowLayoutInner._pressureVisible || rowLayoutInner._kpVisible || rowLayoutInner._uvVisible || rowLayoutInner._precipVisible || rowLayoutInner._visibilityVisible
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                Layout.rightMargin: 6
                                text: "•"
                                color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.4)
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
                                    color: forecastRoot.themeTextColor
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
                                        forecastRoot._loadSingleExpandHourly(dateStr);
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
                        color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.04)
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
                            visible: !_dayIsLoading && ((forecastRoot.expandAll && !forecastRoot._collapsedDays[weatherRoot.dailyData[dataIndex].dateStr || ""]) || forecastRoot.expandedIndex === index) && _dayHourlyData.length === 0
                            text: forecastRoot._emptyHourlyMessage(weatherRoot.dailyData[dataIndex].dateStr || "")
                            color: forecastRoot.themeTextColor
                            font: weatherRoot ? weatherRoot.wf(11, false) : Qt.font({})
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            width: Math.max(0, parent.width - 24)
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
                                    property var _hourlyWithSun: _dayDisplayItems

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
                                                        text: modelData.displayTime || "--"
                                                        color: forecastRoot.themeTextColor
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
                                                            return forecastRoot.resolveConditionIcon(modelData.code || 0, modelData.isNight === true, forecastRoot.iconSz);
                                                        }
                                                        iconSize: 44
                                                        iconColor: forecastRoot.themeTextColor
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
                                                var bg = forecastRoot.themeBackgroundColor;
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
                                                              : (modelData.tempText || "--")
                                                        color: forecastRoot.themeTextColor
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
                                                        text: modelData.precipDisplayText || "--"
                                                        color: forecastRoot.themeTextColor
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
                                                            text: modelData.windText || "--"
                                                            color: forecastRoot.themeTextColor
                                                            font: weatherRoot ? weatherRoot.wf(9, false) : Qt.font({})
                                                            opacity: 0.7
                                                        }
                                                        Text {
                                                            visible: !parent.parent._isSun && weatherRoot && !isNaN(modelData.windDeg)
                                                            text: W.windDirectionGlyph(modelData.windDeg)
                                                            font.family: wiFont.status === FontLoader.Ready ? wiFont.font.family : ""
                                                            font.pixelSize: 24
                                                            color: forecastRoot.themeTextColor
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
                                                        iconColor: forecastRoot.themeTextColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: modelData.pressureText || "--"
                                                        color: forecastRoot.themeTextColor
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
                                                        iconColor: forecastRoot.themeTextColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: modelData.kpText || i18n("No info")
                                                        color: forecastRoot.themeTextColor
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
                                                        iconColor: forecastRoot.themeTextColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: modelData.uvText || "--"
                                                        color: forecastRoot.themeTextColor
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
                                                        iconColor: forecastRoot.themeTextColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: modelData.precipText || "--"
                                                        color: forecastRoot.themeTextColor
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
                                                        iconColor: forecastRoot.themeTextColor
                                                        opacity: 0.7
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                    Label {
                                                        visible: !parent._isSun
                                                        text: modelData.visibilityText || "--"
                                                        color: forecastRoot.themeTextColor
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
                            HourlyCardsView {
                                anchors.fill: parent
                                hostRoot: forecastRoot
                                serviceRoot: weatherRoot
                                wiFont: wiFont
                                hourlyItems: _dayDisplayItems
                                autoScrollToCurrent: weatherRoot && (weatherRoot.dailyData[dataIndex].dateStr || "") === weatherRoot.locationDateString()
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(forecastRoot.themeTextColor.r, forecastRoot.themeTextColor.g, forecastRoot.themeTextColor.b, 0.08)
                    }
                }
        }
    }
