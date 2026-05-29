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
import org.kde.notification
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    property bool cfg_alertNotificationsEnabled: false
    property bool cfg_alertNotificationsYellowEnabled: false
    property bool cfg_alertNotificationsOrangeEnabled: true
    property bool cfg_alertNotificationsRedEnabled: true
    property string cfg_notificationAlertsDays: "1,1,1,1,1,1,1"
    property string cfg_notificationAlertsTimes: "08:00"
    property string cfg_notificationAlertsCustomMessage: ""

    property bool cfg_notificationTomorrowEnabled: false
    property string cfg_notificationTomorrowDays: "1,1,1,1,1,1,1"
    property string cfg_notificationTomorrowTimes: "08:00"
    property string cfg_notificationTomorrowCustomMessage: ""

    property bool cfg_notificationRainStartEnabled: false
    property int cfg_notificationRainStartLeadHours: 3
    property string cfg_notificationRainStartDays: "1,1,1,1,1,1,1"
    property string cfg_notificationRainStartTimes: "08:00"
    property string cfg_notificationRainStartCustomMessage: ""

    property bool cfg_notificationRainEndEnabled: false
    property int cfg_notificationRainEndLeadHours: 1
    property string cfg_notificationRainEndDays: "1,1,1,1,1,1,1"
    property string cfg_notificationRainEndTimes: "08:00"
    property string cfg_notificationRainEndCustomMessage: ""

    property bool cfg_notificationUvEnabled: false
    property int cfg_notificationUvThreshold: 8
    property string cfg_notificationUvDays: "1,1,1,1,1,1,1"
    property string cfg_notificationUvTimes: "08:00"
    property string cfg_notificationUvCustomMessage: ""

    property bool cfg_notificationSpaceWeatherEnabled: false
    property double cfg_notificationSpaceWeatherKpThreshold: 5.0
    property int cfg_notificationSpaceWeatherGThreshold: 1
    property string cfg_notificationSpaceWeatherDays: "1,1,1,1,1,1,1"
    property string cfg_notificationSpaceWeatherTimes: "08:00"
    property string cfg_notificationSpaceWeatherCustomMessage: ""

    readonly property var _dayLabels: [
        i18n("Sun"), i18n("Mon"), i18n("Tue"), i18n("Wed"), i18n("Thu"), i18n("Fri"), i18n("Sat")
    ]

    function dayEnabled(mask, idx) {
        var parts = (mask || "1,1,1,1,1,1,1").split(",");
        if (idx < 0 || idx > 6)
            return true;
        if (idx >= parts.length)
            return true;
        return parts[idx].trim() !== "0";
    }

    function setDay(mask, idx, on) {
        var parts = (mask || "1,1,1,1,1,1,1").split(",");
        while (parts.length < 7)
            parts.push("1");
        parts[idx] = on ? "1" : "0";
        return parts.slice(0, 7).join(",");
    }

    function normalizeTime(s, fallback) {
        var t = (s || "").trim();
        var m = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(t);
        if (!m)
            return fallback;
        var hh = ("0" + parseInt(m[1], 10)).slice(-2);
        var mm = ("0" + parseInt(m[2], 10)).slice(-2);
        return hh + ":" + mm;
    }

    function timesList(raw) {
        var src = (raw || "").replace(/;/g, ",");
        var parts = src.split(",");
        var out = [];
        for (var i = 0; i < parts.length; i++) {
            var t = normalizeTime(parts[i], "");
            if (t.length > 0)
                out.push(t);
        }
        if (out.length === 0)
            out.push("08:00");
        return out;
    }

    function updateTimeAt(raw, idx, nextText, fallback) {
        var items = timesList(raw);
        if (idx < 0 || idx >= items.length)
            return items.join(",");
        items[idx] = normalizeTime(nextText, fallback || items[idx] || "08:00");
        return items.join(",");
    }

    function addTime(raw) {
        var items = timesList(raw);
        items.push(items[items.length - 1] || "08:00");
        return items.join(",");
    }

    function removeTime(raw, idx) {
        var items = timesList(raw);
        if (items.length <= 1)
            return items.join(",");
        if (idx >= 0 && idx < items.length)
            items.splice(idx, 1);
        return items.join(",");
    }

    function timeHour(hhmm) {
        var t = normalizeTime(hhmm, "08:00");
        return parseInt(t.substring(0, 2), 10);
    }

    function timeMinute(hhmm) {
        var t = normalizeTime(hhmm, "08:00");
        return parseInt(t.substring(3, 5), 10);
    }

    function timeFromParts(h, m) {
        var hh = ("0" + Math.max(0, Math.min(23, parseInt(h, 10) || 0))).slice(-2);
        var mm = ("0" + Math.max(0, Math.min(59, parseInt(m, 10) || 0))).slice(-2);
        return hh + ":" + mm;
    }

    function triggerTest(type) {
        var t = (type || "alerts").toLowerCase();
        var msg = "";
        var title = "";
        var urg = Notification.NormalUrgency;

        if (t === "tomorrow") {
            title = i18n("Test: Tomorrow forecast");
            msg = (cfg_notificationTomorrowCustomMessage || "").trim();
            if (msg.length === 0)
                msg = i18n("High 24° / Low 13°");
        } else if (t === "rainstart") {
            title = i18n("Test: Rain/Storm start");
            msg = (cfg_notificationRainStartCustomMessage || "").trim();
            if (msg.length === 0)
                msg = i18n("Expected to start in 4 h.");
        } else if (t === "rainend") {
            title = i18n("Test: Rain/Storm end");
            msg = (cfg_notificationRainEndCustomMessage || "").trim();
            if (msg.length === 0)
                msg = i18n("Expected to end in 2 h.");
        } else if (t === "uv") {
            title = i18n("Test: UV warning");
            msg = (cfg_notificationUvCustomMessage || "").trim();
            if (msg.length === 0)
                msg = i18n("UV index is 9.1.");
            urg = Notification.HighUrgency;
        } else if (t === "space") {
            title = i18n("Test: Geomagnetic warning");
            msg = (cfg_notificationSpaceWeatherCustomMessage || "").trim();
            if (msg.length === 0)
                msg = i18n("Kp 6.0 · G2");
            urg = Notification.HighUrgency;
        } else {
            title = i18n("Test: Weather alert");
            msg = (cfg_notificationAlertsCustomMessage || "").trim();
            if (msg.length === 0)
                msg = i18n("Severe thunderstorm warning");
            urg = Notification.CriticalUrgency;
        }

        previewNotification.title = title;
        previewNotification.text = msg;
        previewNotification.urgency = urg;
        previewNotification.sendEvent();
    }

    Notification {
        id: previewNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "weather-storm"
        flags: Notification.CloseOnTimeout | Notification.SkipGrouping | Notification.DefaultEvent
    }

    component SectionHeader: RowLayout {
        required property string title
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: parent.title
            font.bold: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.5
        }
    }

    component NotificationTimesEditor: ColumnLayout {
        id: timesEditor
        required property string times
        required property bool active
        signal timesEdited(string value)
        readonly property var entries: root.timesList(times)
        Layout.fillWidth: true
        spacing: 4
        enabled: active
        opacity: enabled ? 1.0 : 0.5

        Label { text: i18n("Times:") }

        Repeater {
            model: timesEditor.entries
            delegate: RowLayout {
                spacing: 6
                SpinBox {
                    from: 0
                    to: 23
                    value: root.timeHour(modelData)
                    editable: true
                    textFromValue: function(v) { return ("0" + v).slice(-2); }
                    valueFromText: function(t) { return Math.max(0, Math.min(23, parseInt(t, 10) || 0)); }
                    onValueModified: {
                        var mm = root.timeMinute(modelData);
                        timesEditor.timesEdited(root.updateTimeAt(timesEditor.times, index, root.timeFromParts(value, mm), modelData));
                    }
                }
                Label { text: ":" }
                SpinBox {
                    from: 0
                    to: 59
                    value: root.timeMinute(modelData)
                    editable: true
                    textFromValue: function(v) { return ("0" + v).slice(-2); }
                    valueFromText: function(t) { return Math.max(0, Math.min(59, parseInt(t, 10) || 0)); }
                    onValueModified: {
                        var hh = root.timeHour(modelData);
                        timesEditor.timesEdited(root.updateTimeAt(timesEditor.times, index, root.timeFromParts(hh, value), modelData));
                    }
                }
                ToolButton {
                    text: "+"
                    onClicked: timesEditor.timesEdited(root.addTime(timesEditor.times))
                }
                ToolButton {
                    text: "\u2212"
                    enabled: timesEditor.entries.length > 1
                    onClicked: timesEditor.timesEdited(root.removeTime(timesEditor.times, index))
                }
            }
        }
    }

    ScrollView {
        id: notificationsScroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: notificationsScroll.availableWidth
            spacing: 14

            Kirigami.Heading {
                text: i18n("Notifications")
                level: 3
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Information
                visible: true
                text: i18n("Each notification type can be enabled independently with its own weekdays, times, custom message, and test button.")
            }

            // Alerts
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                SectionHeader { title: i18n("Weather alerts") }

                Switch {
                    text: i18n("Enable alert notifications")
                    checked: root.cfg_alertNotificationsEnabled
                    onToggled: root.cfg_alertNotificationsEnabled = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    enabled: root.cfg_alertNotificationsEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 10
                    Label { text: i18n("Severities:") }
                    Switch {
                        text: i18n("Yellow")
                        checked: root.cfg_alertNotificationsYellowEnabled
                        onToggled: root.cfg_alertNotificationsYellowEnabled = checked
                    }
                    Switch {
                        text: i18n("Orange")
                        checked: root.cfg_alertNotificationsOrangeEnabled
                        onToggled: root.cfg_alertNotificationsOrangeEnabled = checked
                    }
                    Switch {
                        text: i18n("Red")
                        checked: root.cfg_alertNotificationsRedEnabled
                        onToggled: root.cfg_alertNotificationsRedEnabled = checked
                    }
                }

                RowLayout {
                    enabled: root.cfg_alertNotificationsEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 6
                    Label { text: i18n("Days:") }
                    Repeater {
                        model: 7
                        delegate: CheckBox {
                            text: root._dayLabels[index]
                            checked: root.dayEnabled(root.cfg_notificationAlertsDays, index)
                            onToggled: root.cfg_notificationAlertsDays = root.setDay(root.cfg_notificationAlertsDays, index, checked)
                        }
                    }
                }

                NotificationTimesEditor {
                    active: root.cfg_alertNotificationsEnabled
                    times: root.cfg_notificationAlertsTimes
                    onTimesEdited: function(value) { root.cfg_notificationAlertsTimes = value; }
                }

                TextField {
                    Layout.fillWidth: true
                    enabled: root.cfg_alertNotificationsEnabled
                    opacity: enabled ? 1.0 : 0.5
                    placeholderText: i18n("Custom message (optional)")
                    text: root.cfg_notificationAlertsCustomMessage
                    onTextChanged: root.cfg_notificationAlertsCustomMessage = text
                }

                Button {
                    enabled: root.cfg_alertNotificationsEnabled
                    text: i18n("Test alert notification")
                    icon.name: "notifications"
                    onClicked: root.triggerTest("alerts")
                }
            }

            // Tomorrow forecast
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                SectionHeader { title: i18n("Tomorrow forecast") }

                Switch {
                    text: i18n("Notify with tomorrow min/max temperature")
                    checked: root.cfg_notificationTomorrowEnabled
                    onToggled: root.cfg_notificationTomorrowEnabled = checked
                }

                RowLayout {
                    enabled: root.cfg_notificationTomorrowEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 6
                    Label { text: i18n("Days:") }
                    Repeater {
                        model: 7
                        delegate: CheckBox {
                            text: root._dayLabels[index]
                            checked: root.dayEnabled(root.cfg_notificationTomorrowDays, index)
                            onToggled: root.cfg_notificationTomorrowDays = root.setDay(root.cfg_notificationTomorrowDays, index, checked)
                        }
                    }
                }

                NotificationTimesEditor {
                    active: root.cfg_notificationTomorrowEnabled
                    times: root.cfg_notificationTomorrowTimes
                    onTimesEdited: function(value) { root.cfg_notificationTomorrowTimes = value; }
                }

                TextField {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationTomorrowEnabled
                    opacity: enabled ? 1.0 : 0.5
                    placeholderText: i18n("Custom message (optional)")
                    text: root.cfg_notificationTomorrowCustomMessage
                    onTextChanged: root.cfg_notificationTomorrowCustomMessage = text
                }

                Button {
                    enabled: root.cfg_notificationTomorrowEnabled
                    text: i18n("Test tomorrow notification")
                    icon.name: "notifications"
                    onClicked: root.triggerTest("tomorrow")
                }
            }

            // Rain/storm start
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                SectionHeader { title: i18n("Rain/Storm start") }

                Switch {
                    text: i18n("Notify when rain/storm is expected to start")
                    checked: root.cfg_notificationRainStartEnabled
                    onToggled: root.cfg_notificationRainStartEnabled = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationRainStartEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 8
                    Label { text: i18n("Only if starts after at least:") }
                    SpinBox {
                        from: 0
                        to: 72
                        value: root.cfg_notificationRainStartLeadHours
                        onValueModified: root.cfg_notificationRainStartLeadHours = value
                    }
                    Label { text: i18n("hours") }
                }

                RowLayout {
                    enabled: root.cfg_notificationRainStartEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 6
                    Label { text: i18n("Days:") }
                    Repeater {
                        model: 7
                        delegate: CheckBox {
                            text: root._dayLabels[index]
                            checked: root.dayEnabled(root.cfg_notificationRainStartDays, index)
                            onToggled: root.cfg_notificationRainStartDays = root.setDay(root.cfg_notificationRainStartDays, index, checked)
                        }
                    }
                }

                NotificationTimesEditor {
                    active: root.cfg_notificationRainStartEnabled
                    times: root.cfg_notificationRainStartTimes
                    onTimesEdited: function(value) { root.cfg_notificationRainStartTimes = value; }
                }

                TextField {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationRainStartEnabled
                    opacity: enabled ? 1.0 : 0.5
                    placeholderText: i18n("Custom message (optional)")
                    text: root.cfg_notificationRainStartCustomMessage
                    onTextChanged: root.cfg_notificationRainStartCustomMessage = text
                }

                Button {
                    enabled: root.cfg_notificationRainStartEnabled
                    text: i18n("Test rain start notification")
                    icon.name: "notifications"
                    onClicked: root.triggerTest("rainStart")
                }
            }

            // Rain/storm end
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                SectionHeader { title: i18n("Rain/Storm end") }

                Switch {
                    text: i18n("Notify when rain/storm is expected to end")
                    checked: root.cfg_notificationRainEndEnabled
                    onToggled: root.cfg_notificationRainEndEnabled = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationRainEndEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 8
                    Label { text: i18n("Only if ends after at least:") }
                    SpinBox {
                        from: 0
                        to: 72
                        value: root.cfg_notificationRainEndLeadHours
                        onValueModified: root.cfg_notificationRainEndLeadHours = value
                    }
                    Label { text: i18n("hours") }
                }

                RowLayout {
                    enabled: root.cfg_notificationRainEndEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 6
                    Label { text: i18n("Days:") }
                    Repeater {
                        model: 7
                        delegate: CheckBox {
                            text: root._dayLabels[index]
                            checked: root.dayEnabled(root.cfg_notificationRainEndDays, index)
                            onToggled: root.cfg_notificationRainEndDays = root.setDay(root.cfg_notificationRainEndDays, index, checked)
                        }
                    }
                }

                NotificationTimesEditor {
                    active: root.cfg_notificationRainEndEnabled
                    times: root.cfg_notificationRainEndTimes
                    onTimesEdited: function(value) { root.cfg_notificationRainEndTimes = value; }
                }

                TextField {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationRainEndEnabled
                    opacity: enabled ? 1.0 : 0.5
                    placeholderText: i18n("Custom message (optional)")
                    text: root.cfg_notificationRainEndCustomMessage
                    onTextChanged: root.cfg_notificationRainEndCustomMessage = text
                }

                Button {
                    enabled: root.cfg_notificationRainEndEnabled
                    text: i18n("Test rain end notification")
                    icon.name: "notifications"
                    onClicked: root.triggerTest("rainEnd")
                }
            }

            // UV warnings
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                SectionHeader { title: i18n("UV warnings") }

                Switch {
                    text: i18n("Notify when UV exceeds threshold")
                    checked: root.cfg_notificationUvEnabled
                    onToggled: root.cfg_notificationUvEnabled = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationUvEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 8
                    Label { text: i18n("UV threshold:") }
                    SpinBox {
                        from: 1
                        to: 15
                        value: root.cfg_notificationUvThreshold
                        onValueModified: root.cfg_notificationUvThreshold = value
                    }
                }

                RowLayout {
                    enabled: root.cfg_notificationUvEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 6
                    Label { text: i18n("Days:") }
                    Repeater {
                        model: 7
                        delegate: CheckBox {
                            text: root._dayLabels[index]
                            checked: root.dayEnabled(root.cfg_notificationUvDays, index)
                            onToggled: root.cfg_notificationUvDays = root.setDay(root.cfg_notificationUvDays, index, checked)
                        }
                    }
                }

                NotificationTimesEditor {
                    active: root.cfg_notificationUvEnabled
                    times: root.cfg_notificationUvTimes
                    onTimesEdited: function(value) { root.cfg_notificationUvTimes = value; }
                }

                TextField {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationUvEnabled
                    opacity: enabled ? 1.0 : 0.5
                    placeholderText: i18n("Custom message (optional)")
                    text: root.cfg_notificationUvCustomMessage
                    onTextChanged: root.cfg_notificationUvCustomMessage = text
                }

                Button {
                    enabled: root.cfg_notificationUvEnabled
                    text: i18n("Test UV notification")
                    icon.name: "notifications"
                    onClicked: root.triggerTest("uv")
                }
            }

            // Kp / G warnings
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                SectionHeader { title: i18n("Kp and G-index warnings") }

                Switch {
                    text: i18n("Notify on geomagnetic activity")
                    checked: root.cfg_notificationSpaceWeatherEnabled
                    onToggled: root.cfg_notificationSpaceWeatherEnabled = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationSpaceWeatherEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 8
                    Label { text: i18n("Kp threshold:") }
                    SpinBox {
                        from: 0
                        to: 9
                        value: Math.round(root.cfg_notificationSpaceWeatherKpThreshold)
                        onValueModified: root.cfg_notificationSpaceWeatherKpThreshold = value
                    }
                    Label { text: i18n("G threshold:") }
                    SpinBox {
                        from: 0
                        to: 5
                        value: root.cfg_notificationSpaceWeatherGThreshold
                        onValueModified: root.cfg_notificationSpaceWeatherGThreshold = value
                    }
                }

                RowLayout {
                    enabled: root.cfg_notificationSpaceWeatherEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 6
                    Label { text: i18n("Days:") }
                    Repeater {
                        model: 7
                        delegate: CheckBox {
                            text: root._dayLabels[index]
                            checked: root.dayEnabled(root.cfg_notificationSpaceWeatherDays, index)
                            onToggled: root.cfg_notificationSpaceWeatherDays = root.setDay(root.cfg_notificationSpaceWeatherDays, index, checked)
                        }
                    }
                }

                NotificationTimesEditor {
                    active: root.cfg_notificationSpaceWeatherEnabled
                    times: root.cfg_notificationSpaceWeatherTimes
                    onTimesEdited: function(value) { root.cfg_notificationSpaceWeatherTimes = value; }
                }

                TextField {
                    Layout.fillWidth: true
                    enabled: root.cfg_notificationSpaceWeatherEnabled
                    opacity: enabled ? 1.0 : 0.5
                    placeholderText: i18n("Custom message (optional)")
                    text: root.cfg_notificationSpaceWeatherCustomMessage
                    onTextChanged: root.cfg_notificationSpaceWeatherCustomMessage = text
                }

                Button {
                    enabled: root.cfg_notificationSpaceWeatherEnabled
                    text: i18n("Test Kp/G notification")
                    icon.name: "notifications"
                    onClicked: root.triggerTest("space")
                }
            }

            Item { Layout.preferredHeight: 12 }
        }
    }
}
