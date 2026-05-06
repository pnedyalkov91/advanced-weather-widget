/*
 * Copyright 2026  Petar Nedyalkov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

/**
 * RadarView.qml - dependency-safe wrapper for the optional QtWebEngine radar.
 *
 * Keep this file free of QtWebEngine imports. Plasma loads this type together
 * with FullView, even when the Radar tab is not selected.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Item {
    id: radarRoot

    property var weatherRoot
    readonly property bool radarReady: radarLoader.status === Loader.Ready && radarLoader.item !== null

    implicitHeight: 380

    onWeatherRootChanged: _syncLoadedItem()

    Loader {
        id: radarLoader
        anchors.fill: parent
        active: radarRoot.visible
        source: Qt.resolvedUrl("components/RadarWebEngineView.qml")
        asynchronous: false

        onLoaded: radarRoot._syncLoadedItem()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Kirigami.Units.largeSpacing
        }
        spacing: Kirigami.Units.smallSpacing
        visible: radarLoader.status === Loader.Error

        Item {
            Layout.fillHeight: true
        }

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            source: "globe"
            color: Kirigami.Theme.textColor
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            level: 3
            text: i18n("QtWebEngine is not installed")
            wrapMode: Text.WordWrap
        }

        TextEdit {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: Kirigami.Theme.textColor
            text: i18n("The Radar tab requires the QtWebEngine package, which is not installed on this system.")
            readOnly: true
            selectByMouse: true
            wrapMode: Text.WordWrap
            selectedTextColor: Kirigami.Theme.highlightedTextColor
            selectionColor: Kirigami.Theme.highlightColor
            font: Kirigami.Theme.defaultFont
        }

        TextEdit {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: Kirigami.Theme.textColor
            text: i18n("Install it for your distribution:\n- Fedora / RHEL: qt6-qtwebengine\n- openSUSE / Arch: qt6-webengine\n- Debian / Kubuntu / KDE Neon: qml6-module-qtwebengine")
            readOnly: true
            selectByMouse: true
            wrapMode: Text.WordWrap
            selectedTextColor: Kirigami.Theme.highlightedTextColor
            selectionColor: Kirigami.Theme.highlightColor
            font: Kirigami.Theme.defaultFont
        }

        Item {
            Layout.preferredHeight: Kirigami.Units.smallSpacing
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: i18n("Open install guide")
            icon.name: "help-about"
            onClicked: Qt.openUrlExternally("https://github.com/pnedyalkov91/advanced-weather-widget#%EF%B8%8F-prerequisites--dependencies")
        }

        Item {
            Layout.fillHeight: true
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: radarLoader.status === Loader.Loading
        visible: running
    }

    function reload() {
        if (radarReady) {
            radarLoader.item.reload();
        }
    }

    function _syncLoadedItem() {
        if (radarReady) {
            radarLoader.item.weatherRoot = radarRoot.weatherRoot;
        }
    }
}
