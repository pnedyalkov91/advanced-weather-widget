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

KCM.SimpleKCM {
    id: root

    property bool cfg_alertNotificationsEnabled: false
    property bool cfg_alertNotificationsYellowEnabled: false
    property bool cfg_alertNotificationsOrangeEnabled: true
    property bool cfg_alertNotificationsRedEnabled: true
    property bool cfg_alertNotificationsPurpleEnabled: true
    property bool cfg_alertNotificationsCriticalEnabled: true
    property bool cfg_alertNotificationsRepeatEnabled: true
    property string cfg_alertNotificationsTypeSettings: "{}"

    // Parsed working copy of the per-type settings JSON map.
    property var alertTypeSettings: ({})

    // Canonical MeteoAlarm awareness types shown in the per-type list.
    readonly property var alertTypeList: [
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
    ]

    function alertTypeEnabled(t) {
        var s = alertTypeSettings[t];
        return (!s || s.enabled === undefined) ? true : s.enabled === true;
    }
    // Default repeat interval for types that haven't set their own. Matches
    // main.qml's _defaultAlertRepeatMinutes — there is no global interval.
    readonly property int defaultAlertRepeatMinutes: 30
    function alertTypeMinutes(t) {
        var s = alertTypeSettings[t];
        var m = (s && s.minutes !== undefined) ? parseInt(s.minutes, 10) : NaN;
        return isNaN(m) ? defaultAlertRepeatMinutes : Math.max(1, Math.min(720, m));
    }
    function setAlertType(t, enabled, minutes) {
        var copy = {};
        for (var k in alertTypeSettings) copy[k] = alertTypeSettings[k];
        copy[t] = { enabled: enabled, minutes: minutes };
        alertTypeSettings = copy;
        cfg_alertNotificationsTypeSettings = JSON.stringify(copy);
    }

    property bool cfg_notificationTodayEnabled: false
    property string cfg_notificationTodayTime: "08:00"

    property bool cfg_notificationTomorrowEnabled: false
    property string cfg_notificationTomorrowTime: "20:00"

    property bool cfg_notificationRainEnabled: false

    property bool cfg_notificationSnowEnabled: false

    property bool cfg_notificationUvEnabled: false
    property string cfg_notificationUvTime: "08:00"

    property bool cfg_notificationSpaceWeatherEnabled: false
    property string cfg_notificationSpaceWeatherTime: "08:00"

    Component.onCompleted: {
        try {
            var o = JSON.parse(cfg_alertNotificationsTypeSettings || "{}");
            alertTypeSettings = (o && typeof o === "object") ? o : ({});
        } catch (e) {
            alertTypeSettings = ({});
        }
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

    // True when the locale (incl. KDE's 12/24-hour toggle) uses a 12-hour clock.
    // The AM/PM designator ("AP"/"ap") only appears in 12-hour format strings.
    readonly property bool use12HourClock: {
        var f = Qt.locale().timeFormat(Locale.ShortFormat);
        return /a/i.test(f);
    }
    // Convert between 24-hour storage (HH:mm) and 12-hour display.
    function hour24To12(h) { var x = h % 12; return x === 0 ? 12 : x; }
    function hour12To24(h12, isPm) {
        if (isPm) return (h12 === 12) ? 12 : h12 + 12;
        return (h12 === 12) ? 0 : h12;
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

    component SingleTimeEditor: RowLayout {
        id: singleTimeEditor
        required property string time
        required property bool active
        signal timeEdited(string value)
        Layout.fillWidth: true
        spacing: 6
        enabled: active
        opacity: enabled ? 1.0 : 0.5

        // Storage is always 24-hour "HH:mm"; display follows the locale clock.
        readonly property bool use12h: root.use12HourClock
        readonly property int hour24: root.timeHour(time)
        readonly property int minute: root.timeMinute(time)

        Label { text: i18n("Time:") }
        SpinBox {
            id: hourSpin
            from: singleTimeEditor.use12h ? 1 : 0
            to: singleTimeEditor.use12h ? 12 : 23
            editable: true
            value: singleTimeEditor.use12h ? root.hour24To12(singleTimeEditor.hour24) : singleTimeEditor.hour24
            textFromValue: function(v) { return singleTimeEditor.use12h ? ("" + v) : ("0" + v).slice(-2); }
            valueFromText: function(t) {
                var n = parseInt(t, 10) || 0;
                return singleTimeEditor.use12h ? Math.max(1, Math.min(12, n)) : Math.max(0, Math.min(23, n));
            }
            onValueModified: {
                var h24 = singleTimeEditor.use12h
                    ? root.hour12To24(value, ampmCombo.currentIndex === 1)
                    : value;
                singleTimeEditor.timeEdited(root.timeFromParts(h24, singleTimeEditor.minute));
            }
        }
        Label { text: ":" }
        SpinBox {
            from: 0
            to: 59
            editable: true
            value: singleTimeEditor.minute
            textFromValue: function(v) { return ("0" + v).slice(-2); }
            valueFromText: function(t) { return Math.max(0, Math.min(59, parseInt(t, 10) || 0)); }
            onValueModified: singleTimeEditor.timeEdited(root.timeFromParts(singleTimeEditor.hour24, value))
        }
        ComboBox {
            id: ampmCombo
            visible: singleTimeEditor.use12h
            Layout.preferredWidth: implicitWidth
            model: [Qt.locale().amText, Qt.locale().pmText]
            currentIndex: singleTimeEditor.hour24 < 12 ? 0 : 1
            onActivated: {
                var h24 = root.hour12To24(root.hour24To12(singleTimeEditor.hour24), currentIndex === 1);
                singleTimeEditor.timeEdited(root.timeFromParts(h24, singleTimeEditor.minute));
            }
        }
    }

    // KCM.SimpleKCM is itself a Kirigami.ScrollablePage, so it already
    // provides mouse-wheel/touchpad scrolling for its content. Wrapping
    // this in a second, nested ScrollView (as a previous version did)
    // breaks wheel/touchpad scrolling: the outer page's flickable sees
    // the nested ScrollView's height (which fills the viewport) and never
    // detects an overflow, so it doesn't relay scroll events down — and
    // the page appears to not scroll at all. Just use a plain ColumnLayout.
    ColumnLayout {
        spacing: 14

        Kirigami.Heading {
            text: i18n("Notifications")
            level: 3
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            showCloseButton: true
            visible: true
            text: i18n("Each notification type can be enabled independently, with its own daily time where applicable.")
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
                Switch {
                    text: i18n("Purple")
                    checked: root.cfg_alertNotificationsPurpleEnabled
                    onToggled: root.cfg_alertNotificationsPurpleEnabled = checked
                }

                // Info button — explains what each severity color means.
                Kirigami.Icon {
                    source: "help-about"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                    opacity: severityInfoHover.hovered ? 1.0 : 0.7

                    HoverHandler { id: severityInfoHover }

                    ToolTip.visible: severityInfoHover.hovered
                    ToolTip.text: i18n("Weather-alert severity levels, from lowest to highest:\n\n🟡 Yellow — Minor: be aware of the conditions.\n🟠 Orange — Moderate: be prepared.\n🔴 Red — Severe: take action.\n🟣 Purple — Extreme: extraordinarily dangerous, take action immediately.\n\nTurn a level off to stop receiving notifications for alerts of that severity.")
                }
            }

            Switch {
                enabled: root.cfg_alertNotificationsEnabled
                opacity: enabled ? 1.0 : 0.5
                text: i18n("Treat alert notifications as critical")
                checked: root.cfg_alertNotificationsCriticalEnabled
                onToggled: root.cfg_alertNotificationsCriticalEnabled = checked
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Information
                showCloseButton: true
                visible: root.cfg_alertNotificationsEnabled && root.cfg_alertNotificationsCriticalEnabled
                text: i18n("Critical notifications are still shown even when Do Not Disturb is enabled, or while you're playing a game or watching a fullscreen video (if those options are enabled in System Settings → Notifications).")
            }

            Switch {
                enabled: root.cfg_alertNotificationsEnabled
                opacity: enabled ? 1.0 : 0.5
                text: i18n("Repeat reminder until dismissed")
                checked: root.cfg_alertNotificationsRepeatEnabled
                onToggled: root.cfg_alertNotificationsRepeatEnabled = checked
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Information
                showCloseButton: true
                visible: root.cfg_alertNotificationsEnabled && !root.cfg_alertNotificationsRepeatEnabled
                text: i18n("Each alert is shown only once, without Dismiss and Postpone buttons.")
            }

            // ── Per-type overrides ─────────────────────────────────────────
            Label {
                Layout.topMargin: 4
                enabled: root.cfg_alertNotificationsEnabled
                opacity: enabled ? 1.0 : 0.5
                text: i18n("Per alert type:")
                font.bold: true
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Information
                showCloseButton: true
                visible: root.cfg_alertNotificationsEnabled
                text: i18n("Disable a type to silence it, or give it its own repeat interval. The interval is used only when 'Repeat reminder until dismissed' is on.")
            }

            Repeater {
                model: root.alertTypeList
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    enabled: root.cfg_alertNotificationsEnabled
                    opacity: enabled ? 1.0 : 0.5
                    spacing: 8

                    Switch {
                        Layout.preferredWidth: 200
                        text: modelData.name
                        checked: root.alertTypeEnabled(modelData.type)
                        onToggled: root.setAlertType(modelData.type, checked, root.alertTypeMinutes(modelData.type))
                    }
                    Item { Layout.fillWidth: true }
                    SpinBox {
                        enabled: root.cfg_alertNotificationsRepeatEnabled && root.alertTypeEnabled(modelData.type)
                        opacity: enabled ? 1.0 : 0.5
                        from: 1
                        to: 720
                        stepSize: 1
                        value: root.alertTypeMinutes(modelData.type)
                        onValueModified: root.setAlertType(modelData.type, root.alertTypeEnabled(modelData.type), value)
                    }
                    Label { text: i18n("minutes") }
                }
            }
        }

        // Today's weather
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            SectionHeader { title: i18n("Today's weather") }

            Switch {
                text: i18n("Notify with today's forecast")
                checked: root.cfg_notificationTodayEnabled
                onToggled: root.cfg_notificationTodayEnabled = checked
            }

            SingleTimeEditor {
                active: root.cfg_notificationTodayEnabled
                time: root.cfg_notificationTodayTime
                onTimeEdited: function(value) { root.cfg_notificationTodayTime = value; }
            }
        }

        // Tomorrow forecast
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            SectionHeader { title: i18n("Tomorrow forecast") }

            Switch {
                text: i18n("Notify with tomorrow's forecast")
                checked: root.cfg_notificationTomorrowEnabled
                onToggled: root.cfg_notificationTomorrowEnabled = checked
            }

            SingleTimeEditor {
                active: root.cfg_notificationTomorrowEnabled
                time: root.cfg_notificationTomorrowTime
                onTimeEdited: function(value) { root.cfg_notificationTomorrowTime = value; }
            }
        }

        // Rain/Storm
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            SectionHeader { title: i18n("Rain/Storm") }

            Switch {
                text: i18n("Notify about upcoming rain/storms")
                checked: root.cfg_notificationRainEnabled
                onToggled: root.cfg_notificationRainEnabled = checked
            }
        }

        // Snow
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            SectionHeader { title: i18n("Snow") }

            Switch {
                text: i18n("Notify about upcoming snow")
                checked: root.cfg_notificationSnowEnabled
                onToggled: root.cfg_notificationSnowEnabled = checked
            }
        }

        // UV index
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            SectionHeader { title: i18n("UV index") }

            Switch {
                text: i18n("Notify with today's UV forecast")
                checked: root.cfg_notificationUvEnabled
                onToggled: root.cfg_notificationUvEnabled = checked
            }

            SingleTimeEditor {
                active: root.cfg_notificationUvEnabled
                time: root.cfg_notificationUvTime
                onTimeEdited: function(value) { root.cfg_notificationUvTime = value; }
            }
        }

        // Geomagnetic activity
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            SectionHeader { title: i18n("Geomagnetic activity") }

            Switch {
                text: i18n("Notify with today's geomagnetic activity forecast")
                checked: root.cfg_notificationSpaceWeatherEnabled
                onToggled: root.cfg_notificationSpaceWeatherEnabled = checked
            }

            SingleTimeEditor {
                active: root.cfg_notificationSpaceWeatherEnabled
                time: root.cfg_notificationSpaceWeatherTime
                onTimeEdited: function(value) { root.cfg_notificationSpaceWeatherTime = value; }
            }
        }

        Item { Layout.preferredHeight: 12 }
    }
}
