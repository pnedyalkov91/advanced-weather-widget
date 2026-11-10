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
 * ConfigAlertsTab.qml - Weather Alerts tab content
 *
 * Extracted from configGeneral.qml for readability.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

GridLayout {
    id: alertsTab

    Layout.fillWidth: true
    // children with a maximum width would otherwise cap the grid itself and make
    // it flip between one and two columns
    Layout.maximumWidth: Number.POSITIVE_INFINITY
    Layout.alignment: Qt.AlignTop
    // Label and control on one line when there is room (like the wide mode of
    // Kirigami.FormLayout); the label goes above its control in a narrow window.
    columns: width >= Kirigami.Units.gridUnit * 30 ? 2 : 1
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: columns === 1 ? Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing * 2

    /** Reference to the root KCM (configGeneral) for cfg_* properties */
    required property var configRoot

    // ── Alert language ────────────────────────────────────────────────────
    // Alerts are CAP documents with one <info> block per language, so the
    // language is chosen client-side. The list offered for a location is the
    // language(s) the country's authorities are known to publish in, plus
    // English; if an alert has no block in the chosen language the native one
    // is shown instead.

    // Saved locations as written by the Location page (read from the applied
    // config; a location added in the same dialog shows up after Apply).
    readonly property var _savedLocations: {
        try {
            var a = JSON.parse(Plasmoid.configuration.savedLocations || "[]");
            return Array.isArray(a) ? a : [];
        } catch (e) {
            return [];
        }
    }

    readonly property var _langNames: ({
            "en": "English",
            "de": "Deutsch (" + i18n("German") + ")",
            "fr": "Français (" + i18n("French") + ")",
            "it": "Italiano (" + i18n("Italian") + ")",
            "rm": "Rumantsch (" + i18n("Romansh") + ")",
            "nl": "Nederlands (" + i18n("Dutch") + ")",
            "lb": "Lëtzebuergesch (" + i18n("Luxembourgish") + ")",
            "fi": "Suomi (" + i18n("Finnish") + ")",
            "sv": "Svenska (" + i18n("Swedish") + ")",
            "es": "Español (" + i18n("Spanish") + ")",
            "ca": "Català (" + i18n("Catalan") + ")",
            "eu": "Euskara (" + i18n("Basque") + ")",
            "gl": "Galego (" + i18n("Galician") + ")",
            "ga": "Gaeilge (" + i18n("Irish") + ")",
            "cy": "Cymraeg (" + i18n("Welsh") + ")",
            "gd": "Gàidhlig (" + i18n("Scottish Gaelic") + ")",
            "mt": "Malti (" + i18n("Maltese") + ")",
            "el": "Ελληνικά (" + i18n("Greek") + ")",
            "tr": "Türkçe (" + i18n("Turkish") + ")",
            "sl": "Slovenščina (" + i18n("Slovenian") + ")",
            "hr": "Hrvatski (" + i18n("Croatian") + ")",
            "bs": "Bosanski (" + i18n("Bosnian") + ")",
            "sr": "Srpski (" + i18n("Serbian") + ")",
            "hu": "Magyar (" + i18n("Hungarian") + ")",
            "sk": "Slovenčina (" + i18n("Slovak") + ")",
            "mk": "Македонски (" + i18n("Macedonian") + ")",
            "sq": "Shqip (" + i18n("Albanian") + ")",
            "he": "עברית (" + i18n("Hebrew") + ")",
            "ar": "العربية (" + i18n("Arabic") + ")"
        })

    // ISO 3166-1 alpha-2 -> official / widely published alert languages.
    // Single-language countries are left out on purpose: they only get
    // "Native" and "English".
    readonly property var _countryLangs: ({
            "CH": ["de", "fr", "it", "rm"],
            "BE": ["nl", "fr", "de"],
            "LU": ["lb", "fr", "de"],
            "FI": ["fi", "sv"],
            "ES": ["es", "ca", "eu", "gl"],
            "IE": ["ga"],
            "MT": ["mt"],
            "CY": ["el", "tr"],
            "IT": ["it", "de", "fr", "sl"],
            "GB": ["cy", "gd"],
            "AT": ["de", "sl", "hr", "hu"],
            "BA": ["bs", "hr", "sr"],
            "SI": ["sl", "it", "hu"],
            "SK": ["sk", "hu"],
            "MK": ["mk", "sq"],
            "IL": ["he", "ar"],
            "US": ["es"],
            "CA": ["fr"]
        })

    /** "lat,lon" with 4 decimals - the same key WeatherService looks up. */
    function locationKey(loc) {
        var la = parseFloat(loc.lat), lo = parseFloat(loc.lon);
        if (isNaN(la) || isNaN(lo))
            return "";
        return la.toFixed(4) + "," + lo.toFixed(4);
    }

    // Languages that only ever appear as a country's native language (they are
    // not offered as extra choices), so just their own name is needed.
    readonly property var _extraEndonyms: ({
            "bg": "Български",
            "cs": "Čeština",
            "da": "Dansk",
            "et": "Eesti",
            "is": "Íslenska",
            "lt": "Lietuvių",
            "lv": "Latviešu",
            "no": "Norsk",
            "pl": "Polski",
            "pt": "Português",
            "ro": "Română",
            "uk": "Українська"
        })

    // ISO 3166-1 alpha-2 -> the language the country's authority publishes
    // its alerts in. Countries without one clear language (CH, BE, LU, ...)
    // are left out and get a generic "Native language" label.
    readonly property var _nativeLang: ({
            "AL": "sq", "AT": "de", "AU": "en", "BG": "bg", "CA": "en",
            "CY": "el", "CZ": "cs", "DE": "de", "DK": "da", "EE": "et",
            "ES": "es", "FI": "fi", "FR": "fr", "GB": "en", "GR": "el",
            "HR": "hr", "HU": "hu", "IE": "en", "IL": "he", "IS": "is",
            "IT": "it", "LT": "lt", "LV": "lv", "MD": "ro", "MK": "mk",
            "MT": "mt", "NL": "nl", "NO": "no", "NZ": "en", "PL": "pl",
            "PT": "pt", "RO": "ro", "RS": "sr", "SE": "sv", "SI": "sl",
            "SK": "sk", "TR": "tr", "UA": "uk", "US": "en"
        })

    /** A language written in itself ("Deutsch", "Български"), or "" if unknown. */
    function endonym(code) {
        if (_extraEndonyms[code])
            return _extraEndonyms[code];
        var n = _langNames[code];
        if (!n)
            return "";
        var p = n.indexOf(" (");
        return p > 0 ? n.substring(0, p) : n;
    }

    /** Dropdown entries for a location's country code. */
    function languageOptions(countryCode) {
        var cc = (countryCode || "").toUpperCase();
        var nativeCode = _nativeLang[cc] || "";
        var nativeName = endonym(nativeCode);
        var opts = [
            {
                // Only "Default" is translatable; the language name is shown as is.
                text: nativeName.length > 0 ? i18nc("@item:inlistbox %1 is a language name written in that language", "%1 (Default)", nativeName) : i18n("Native language of the alert (Default)"),
                value: ""
            }
        ];
        // the native language is already the default entry
        if (nativeCode !== "en")
            opts.push({
                text: _langNames["en"],
                value: "en"
            });
        var list = _countryLangs[cc] || [];
        for (var i = 0; i < list.length; ++i) {
            if (list[i] === nativeCode)
                continue;
            opts.push({
                text: _langNames[list[i]] || list[i],
                value: list[i]
            });
        }
        return opts;
    }

    function _languageMap() {
        try {
            var m = JSON.parse(alertsTab.configRoot.cfg_alertsLanguageByLocation || "{}");
            return (m && typeof m === "object") ? m : {};
        } catch (e) {
            return {};
        }
    }

    function languageFor(loc) {
        var v = _languageMap()[locationKey(loc)];
        return (typeof v === "string") ? v : "";
    }

    function setLanguageFor(loc, code) {
        var key = locationKey(loc);
        if (key.length === 0)
            return;
        var m = _languageMap();
        if (code && code.length > 0)
            m[key] = code;
        else
            delete m[key];
        alertsTab.configRoot.cfg_alertsLanguageByLocation = JSON.stringify(m);
    }

    // Section title with a thin rule, same look as the Notifications page.
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

    // ═══════════════════════════════════════════════════════════════
    // SECTION: Weather Alerts
    // ═══════════════════════════════════════════════════════════════
    SectionHeader {
        title: i18n("Weather Alerts Provider")
        Layout.columnSpan: alertsTab.columns
    }

    Label {
        text: i18n("Alerts provider:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: alertsTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    ComboBox {
        id: alertsProviderCombo
        Layout.preferredWidth: 280
        model: [
            {
                text: i18n("MeteoAlarm + NOAA NWS (Native)"),
                value: "native"
            },
            {
                text: i18n("LibreWXR"),
                value: "librewxr"
            },
            {
                text: i18n("FOSS Public Alert Server"),
                value: "foss"
            }
        ]
        textRole: "text"
        currentIndex: {
            for (var i = 0; i < model.length; i++)
                if (model[i].value === alertsTab.configRoot.cfg_alertsProvider)
                    return i;
            return 0;
        }
        onActivated: alertsTab.configRoot.cfg_alertsProvider = model[currentIndex].value
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: alertsTab.columns
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "native"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://www.meteoalarm.org/'>EUMETNET MeteoAlarm</a> + <a href='https://www.weather.gov/'>NOAA NWS</a><br/><br/>" + "European locations use the official MeteoAlarm feeds (38 countries), US locations use the NOAA National Weather Service alerts API, with met.no MetAlerts as a fallback. If your weather provider delivers its own alerts (e.g. WeatherAPI.com, Pirate Weather), those are used directly.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: alertsTab.columns
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "librewxr"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://librewxr.net/'>LibreWXR</a><br/><br/>" + "LibreWXR is a free, open-source weather API that aggregates official CAP alerts worldwide (WMO Severe Weather Information Centre, NOAA NWS, and others) and matches them to your exact location. Alert notifications work the same as with the native provider.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    Kirigami.InlineMessage {
        Layout.columnSpan: alertsTab.columns
        Layout.fillWidth: true
        visible: alertsTab.configRoot.cfg_alertsProvider === "foss"
        showCloseButton: true
        type: Kirigami.MessageType.Information
        text: i18n("Alerts provider: <a href='https://alerts.kde.org/'>FOSS Public Alert Server</a><br/><br/>" + "KDE's FOSS Public Alert Server collects official severe-weather warnings in CAP format from agencies worldwide and matches them to your exact location. Alert notifications work the same as with the native provider.")
        onLinkActivated: Qt.openUrlExternally(link)
    }

    // ═══════════════════════════════════════════════════════════════
    // SECTION: Alert language
    // Applies to alerts that come as CAP documents (MeteoAlarm in native
    // mode, and the FOSS Public Alert Server). LibreWXR, NOAA NWS and
    // met.no MetAlerts deliver one language only, so the section is hidden.
    // ═══════════════════════════════════════════════════════════════
    SectionHeader {
        visible: alertsTab.configRoot.cfg_alertsProvider !== "librewxr"
        title: i18n("Alert Language")
        Layout.columnSpan: alertsTab.columns
    }

    Label {
        visible: alertsTab.configRoot.cfg_alertsProvider !== "librewxr"
        text: i18n("Native language:")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
        Layout.topMargin: alertsTab.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
    }
    Switch {
        id: nativeLanguageSwitch
        visible: alertsTab.configRoot.cfg_alertsProvider !== "librewxr"
        text: i18n("Use the alert's native language")
        checked: alertsTab.configRoot.cfg_alertsLanguageNative
        onToggled: alertsTab.configRoot.cfg_alertsLanguageNative = checked
    }

    Label {
        visible: alertsTab.configRoot.cfg_alertsProvider !== "librewxr"
        Layout.columnSpan: alertsTab.columns
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.7
        text: alertsTab.configRoot.cfg_alertsLanguageNative ? i18n("Alerts are shown in the language the issuing authority uses for your country.") : i18n("Choose the alert language for each saved location. If an alert is not published in that language, its native language is shown instead.")
    }

    Label {
        visible: alertsTab.configRoot.cfg_alertsProvider !== "librewxr" && !alertsTab.configRoot.cfg_alertsLanguageNative && alertsTab._savedLocations.length === 0
        Layout.columnSpan: alertsTab.columns
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: i18n("There are no saved locations yet. Save a location on the Location page to choose its alert language.")
    }

    Repeater {
        model: (alertsTab.configRoot.cfg_alertsProvider !== "librewxr" && !alertsTab.configRoot.cfg_alertsLanguageNative) ? alertsTab._savedLocations : []

        delegate: RowLayout {
            id: locRow
            required property var modelData
            readonly property var opts: alertsTab.languageOptions(modelData.countryCode)

            Layout.columnSpan: alertsTab.columns
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Label {
                text: locRow.modelData.name || ""
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
            ComboBox {
                Layout.preferredWidth: 280
                model: locRow.opts
                textRole: "text"
                currentIndex: {
                    var cur = alertsTab.languageFor(locRow.modelData);
                    for (var i = 0; i < locRow.opts.length; i++)
                        if (locRow.opts[i].value === cur)
                            return i;
                    return 0;
                }
                onActivated: alertsTab.setLanguageFor(locRow.modelData, locRow.opts[currentIndex].value)
            }
        }
    }

    // Invisible filler row: it lets the second column take ALL spare width, so the
    // label column keeps its width when rows are shown or hidden.
    Item {
        visible: alertsTab.columns === 2
        implicitWidth: 0
        implicitHeight: 0
    }
    Item {
        visible: alertsTab.columns === 2
        Layout.fillWidth: true
        implicitWidth: 0
        implicitHeight: 0
    }
}
