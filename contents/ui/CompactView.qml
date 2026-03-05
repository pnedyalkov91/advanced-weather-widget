/**
 * CompactView.qml — Panel / compact representation
 *
 * Renders the thin panel bar: wi-font icon + value chips separated by a bullet.
 * Also hosts the custom tooltip popup (TooltipContent).
 *
 * Display modes (Plasmoid.configuration.panelInfoMode):
 *   "single"    — all items in one row (original behaviour)
 *   "multiline" — large weather icon on the left, item rows scrolling on right;
 *                 fills the full panel height set by the user in KDE settings
 *   "simple"    — icon + temperature only
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

import "js/weather.js" as W

PlasmaCore.ToolTipArea {
    id: compactRoot
    active: Plasmoid.configuration.tooltipEnabled !== false

    // ── Interface — bound from main.qml ──────────────────────────────────
    /** Reference to the PlasmoidItem root */
    property var weatherRoot

    // ── Layout ───────────────────────────────────────────────────────────
    readonly property int leftRightMargin: 4
    readonly property int itemSpacing: Plasmoid.configuration.panelItemSpacing !== undefined ? Plasmoid.configuration.panelItemSpacing : 5

    // When panelUseSystemFont is true (Automatic) always use the theme default size.
    readonly property int panelFontPx: {
        if (!Plasmoid.configuration.panelUseSystemFont && Plasmoid.configuration.panelFontSize > 0)
            return Math.round(Plasmoid.configuration.panelFontSize * 4 / 3);
        return Kirigami.Theme.defaultFont.pixelSize;
    }

    // Glyphs rendered 30 % larger than text
    readonly property int glyphSize: Math.max(12, Math.round(panelFontPx * 1.3))

    // svgIconPx — display size for SVG panel icons
    readonly property int svgIconPx: {
        var theme = Plasmoid.configuration.panelIconTheme || "wi-font";
        if (theme === "wi-font")
            return glyphSize;
        return Plasmoid.configuration.panelIconSize || 22;
    }

    // ── Mode helpers ──────────────────────────────────────────────────────
    readonly property bool isMultiLine: Plasmoid.configuration.panelInfoMode === "multiline"
    readonly property bool isSimpleMode: Plasmoid.configuration.panelInfoMode === "simple"

    // Simple mode sub-options
    readonly property int simpleLayoutType: Plasmoid.configuration.panelSimpleLayoutType || 0
    readonly property int simpleWidgetOrder: Plasmoid.configuration.panelSimpleWidgetOrder || 0
    readonly property string simpleIconStyle: Plasmoid.configuration.panelSimpleIconStyle || "symbolic"

    // Dynamic sizes for simple mode – more aggressive scaling
    readonly property int simpleIconSize: {
        if (Plasmoid.configuration.simpleIconSizeMode === "manual")
            return Plasmoid.configuration.simpleIconSizeManual;
        var h = compactRoot.height > 8 ? compactRoot.height : 28;
        if (simpleLayoutType === 1) // vertical
            return Math.min(Math.round(h * 0.55), 100);
        if (simpleLayoutType === 2) // compressed
            return Math.min(Math.round(h * 1.2), 120);
        return Math.min(Math.round(h * 1.2), 120);
    }

    readonly property int simpleFontSize: {
        if (Plasmoid.configuration.simpleFontSizeMode === "manual")
            return Plasmoid.configuration.simpleFontSizeManual;
        var h = compactRoot.height > 8 ? compactRoot.height : 28;
        if (simpleLayoutType === 1) // vertical
            return Math.max(8, Math.floor(h * 0.45));
        if (simpleLayoutType === 2) // compressed
            // Scale with height, cap at 48px to keep badge readable but not too large
            return Math.max(8, Math.min(Math.floor(h * 0.5), 48));
        return Math.max(8, Math.floor(h * 0.55)); // horizontal
    }

    // Multiline mode: icon style
    readonly property string mlIconStyle: Plasmoid.configuration.panelMultilineIconStyle || "colorful"
    readonly property int multiLines: Math.max(1, Plasmoid.configuration.panelMultiLines || 2)
    readonly property bool multiAnimate: Plasmoid.configuration.panelMultiAnimate !== false

    // mlIconSize: large weather icon on the left of the multiline layout.
    readonly property int mlIconSize: Math.min(Math.max(multiLines * (panelFontPx + 8), 32) - 4, 64)

    implicitHeight: isMultiLine ? Math.max(multiLines * (panelFontPx + 8), 32) : Kirigami.Units.gridUnit * 2

    // Simple mode width calculation using the dynamic sizes
    readonly property int _simpleW: {
        var m = 2 * leftRightMargin;
        if (simpleLayoutType === 2) // compressed
            return simpleIconSize + Math.round(simpleFontSize * 1.5) + m; // more room for badge
        if (simpleLayoutType === 1) // vertical
            return simpleIconSize + m;
        // horizontal
        return simpleIconSize + Math.round(simpleFontSize * 1.5) + 8 + m; // more width for text
    }

    implicitWidth: isMultiLine ? mlIconSize + 6 + 110 + 2 * leftRightMargin : isSimpleMode ? _simpleW : compactRow.implicitWidth + 2 * leftRightMargin

    // Layout properties - critical for proper panel integration
    Layout.fillHeight: true
    Layout.fillWidth: Plasmoid.configuration.panelFillWidth
    Layout.preferredWidth: Plasmoid.configuration.panelFillWidth ? -1 : isSimpleMode ? _simpleW : isMultiLine ? mlIconSize + 6 + (Plasmoid.configuration.panelWidth || 110) + 2 * leftRightMargin : implicitWidth
    Layout.minimumWidth: 30 // Prevents forcing too much space
    Layout.preferredHeight: -1 // Let the panel decide
    Layout.minimumHeight: implicitHeight

    // ── Wi-font (panel glyphs) ────────────────────────────────────────────
    FontLoader {
        id: wiFontPanel
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    // ── Icon theme ────────────────────────────────────────────────────────
    readonly property string iconTheme: Plasmoid.configuration.panelIconTheme || "wi-font"

    // ── Reactive panel items ──────────────────────────────────────────────
    property var panelItemsData: {
        if (!weatherRoot)
            return [];
        var _ = weatherRoot.temperatureC + weatherRoot.windKmh + weatherRoot.windDirection + weatherRoot.humidityPercent + weatherRoot.pressureHpa + weatherRoot.weatherCode + weatherRoot.panelScrollIndex + weatherRoot.sunriseTimeText.length + weatherRoot.sunsetTimeText.length + Plasmoid.configuration.panelItemOrder + Plasmoid.configuration.panelItemIcons + Plasmoid.configuration.panelInfoMode + Plasmoid.configuration.panelSeparator + Plasmoid.configuration.panelSunTimesMode + compactRoot.iconTheme + Plasmoid.configuration.panelIconSize;
        return _buildItems();
    }

    property var multiLineItemsData: {
        var all = panelItemsData;
        var result = [];
        for (var i = 0; i < all.length; ++i)
            if (!all[i].isSep)
                result.push(all[i]);
        return result;
    }

    readonly property real multiLineRowH: height > 0 ? Math.max(14, height / multiLines) : Math.max(14, panelFontPx + 8)

    // ── Multiline scroll state ────────────────────────────────────────────
    property int mlScrollOffset: 0

    Timer {
        id: mlScrollTimer
        interval: Math.max(1, Plasmoid.configuration.panelScrollSeconds || 4) * 1000
        running: compactRoot.isMultiLine && compactRoot.multiLineItemsData.length > compactRoot.multiLines
        repeat: true
        onTriggered: {
            var total = compactRoot.multiLineItemsData.length;
            compactRoot.mlScrollOffset = (compactRoot.mlScrollOffset + 1) % total;
        }
    }

    onIsMultiLineChanged: mlScrollOffset = 0
    onMultiLineItemsDataChanged: mlScrollOffset = 0

    // ── Custom tooltip popup ──────────────────────────────────────────────
    mainItem: TooltipContent {
        weatherRoot: compactRoot.weatherRoot
    }

    // ══════════════════════════════════════════════════════════════════════
    // SINGLE / SCROLL MODE
    // ══════════════════════════════════════════════════════════════════════
    RowLayout {
        id: compactRow
        visible: !compactRoot.isMultiLine && !compactRoot.isSimpleMode
        anchors.fill: parent
        anchors.leftMargin: compactRoot.leftRightMargin
        anchors.rightMargin: compactRoot.leftRightMargin
        spacing: compactRoot.itemSpacing
        clip: true

        Repeater {
            model: compactRoot.panelItemsData
            delegate: RowLayout {
                id: slRowItem
                required property var modelData
                spacing: slRowItem.modelData.isSep ? 0 : 5

                // wi-font glyph
                Text {
                    visible: slRowItem.modelData.glyphVis && slRowItem.modelData.glyphType === "wi"
                    text: slRowItem.modelData.glyph
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: compactRoot.glyphSize
                    color: Kirigami.Theme.textColor
                    Layout.alignment: Qt.AlignVCenter
                }
                // Kirigami icon (KDE system theme)
                Kirigami.Icon {
                    visible: slRowItem.modelData.glyphVis && slRowItem.modelData.glyphType === "kde" && slRowItem.modelData.glyph.length > 0
                    source: slRowItem.modelData.glyph
                    implicitWidth: compactRoot.svgIconPx
                    implicitHeight: compactRoot.svgIconPx
                }
                // Kirigami icon (fallback type)
                Kirigami.Icon {
                    visible: slRowItem.modelData.glyphVis && slRowItem.modelData.glyphType === "kirigami" && slRowItem.modelData.glyph.length > 0
                    source: slRowItem.modelData.glyph
                    implicitWidth: compactRoot.glyphSize
                    implicitHeight: compactRoot.glyphSize
                }
                // SVG icon with fallback
                Item {
                    visible: slRowItem.modelData.glyphVis && slRowItem.modelData.glyphType === "svg" && slRowItem.modelData.glyph.length > 0
                    implicitWidth: compactRoot.svgIconPx
                    implicitHeight: compactRoot.svgIconPx
                    Kirigami.Icon {
                        anchors.fill: parent
                        source: slRowItem.modelData.glyphKdeFallback || ""
                        visible: (slRowItem.modelData.glyphKdeFallback || "").length > 0
                    }
                    Kirigami.Icon {
                        anchors.fill: parent
                        source: slRowItem.modelData.glyph
                        isMask: compactRoot.iconTheme === "symbolic"
                        color: Kirigami.Theme.textColor
                    }
                }
                // Value text
                Label {
                    text: slRowItem.modelData.text
                    font: slRowItem.modelData.isSep ? Qt.font({
                        pixelSize: compactRoot.panelFontPx,
                        bold: false
                    }) : compactRoot.weatherRoot ? compactRoot.weatherRoot.wpf(compactRoot.panelFontPx, false) : Qt.font({
                        pixelSize: compactRoot.panelFontPx
                    })
                    color: Kirigami.Theme.textColor
                    verticalAlignment: Text.AlignVCenter
                    opacity: slRowItem.modelData.isSep ? 0.5 : 1.0
                    elide: Text.ElideRight
                    Layout.maximumWidth: {
                        if (slRowItem.modelData.isSep)
                            return implicitWidth;
                        var w = Plasmoid.configuration.panelWidth || 0;
                        return w > 0 ? w : 120;
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // MULTILINE MODE
    // ══════════════════════════════════════════════════════════════════════
    RowLayout {
        id: multiLineRow
        visible: compactRoot.isMultiLine && !compactRoot.isSimpleMode
        anchors.fill: parent
        anchors.leftMargin: compactRoot.leftRightMargin
        anchors.rightMargin: compactRoot.leftRightMargin
        spacing: 6

        Kirigami.Icon {
            id: weatherIconLarge
            readonly property int iconSz: compactRoot.height > 8 ? Math.min(compactRoot.height - 4, 64) : compactRoot.mlIconSize
            source: compactRoot.weatherRoot ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode, compactRoot.weatherRoot.isNightTime()) : "weather-none-available"
            isMask: compactRoot.mlIconStyle === "symbolic"
            color: compactRoot.mlIconStyle === "symbolic" ? Kirigami.Theme.textColor : "transparent"
            Layout.preferredWidth: iconSz
            Layout.preferredHeight: iconSz
            Layout.alignment: Qt.AlignVCenter
            smooth: true
        }

        Item {
            id: rowsClip
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Column {
                id: scrollCol
                width: parent.width

                readonly property real rowH: compactRoot.height > 0 ? Math.max(12, compactRoot.height / compactRoot.multiLines) : Math.max(12, compactRoot.panelFontPx + 8)
                readonly property int rowFontPx: {
                    var useSystem = Plasmoid.configuration.panelUseSystemFont;
                    var savedPt = Plasmoid.configuration.panelFontSize || 0;
                    var maxFromRow = Math.max(8, Math.floor(rowH * 0.72));
                    if (!useSystem && savedPt > 0)
                        return Math.min(maxFromRow, Math.round(savedPt * 4 / 3));
                    return Math.max(8, Math.floor(rowH * 0.65));
                }

                Behavior on y {
                    enabled: compactRoot.multiAnimate && compactRoot.mlScrollOffset !== 0
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.InOutCubic
                    }
                }
                y: -(compactRoot.mlScrollOffset * scrollCol.rowH)

                Repeater {
                    model: compactRoot.multiLineItemsData
                    delegate: RowLayout {
                        id: mlRowItem
                        required property var modelData
                        required property int index
                        width: scrollCol.width
                        height: scrollCol.rowH
                        spacing: 6
                        clip: true

                        Text {
                            visible: mlRowItem.modelData.glyphVis && mlRowItem.modelData.glyphType === "wi"
                            text: mlRowItem.modelData.glyph
                            font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                            font.pixelSize: Math.round(scrollCol.rowFontPx * 1.3)
                            color: Kirigami.Theme.textColor
                            verticalAlignment: Text.AlignVCenter
                        }
                        Kirigami.Icon {
                            visible: mlRowItem.modelData.glyphVis && mlRowItem.modelData.glyphType === "kde" && mlRowItem.modelData.glyph.length > 0
                            source: mlRowItem.modelData.glyph
                            implicitWidth: compactRoot.svgIconPx
                            implicitHeight: compactRoot.svgIconPx
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Kirigami.Icon {
                            visible: mlRowItem.modelData.glyphVis && mlRowItem.modelData.glyphType === "kirigami" && mlRowItem.modelData.glyph.length > 0
                            source: mlRowItem.modelData.glyph
                            implicitWidth: scrollCol.rowFontPx
                            implicitHeight: scrollCol.rowFontPx
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Item {
                            visible: mlRowItem.modelData.glyphVis && mlRowItem.modelData.glyphType === "svg" && mlRowItem.modelData.glyph.length > 0
                            implicitWidth: compactRoot.svgIconPx
                            implicitHeight: compactRoot.svgIconPx
                            Layout.alignment: Qt.AlignVCenter
                            Kirigami.Icon {
                                anchors.fill: parent
                                source: mlRowItem.modelData.glyphKdeFallback || ""
                                visible: (mlRowItem.modelData.glyphKdeFallback || "").length > 0
                            }
                            Kirigami.Icon {
                                anchors.fill: parent
                                source: mlRowItem.modelData.glyph
                                isMask: compactRoot.iconTheme === "symbolic"
                                color: Kirigami.Theme.textColor
                            }
                        }
                        Label {
                            text: mlRowItem.modelData.text
                            font: compactRoot.weatherRoot ? compactRoot.weatherRoot.wpf(scrollCol.rowFontPx, false) : Qt.font({
                                pixelSize: scrollCol.rowFontPx
                            })
                            color: Kirigami.Theme.textColor
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // SIMPLE MODE — icon + temperature
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: simpleLayout
        anchors.fill: parent
        visible: compactRoot.isSimpleMode

        readonly property int iconSize: compactRoot.simpleIconSize
        readonly property int fontSize: compactRoot.simpleFontSize

        // ── Horizontal ────────────────────────────────────────────────────
        RowLayout {
            anchors.centerIn: parent
            spacing: Math.max(2, Math.round(simpleLayout.fontSize * 0.1))
            visible: compactRoot.simpleLayoutType === 0

            // Icon when order is temperature first (icon appears second)
            Item {
                visible: compactRoot.simpleWidgetOrder === 0
                Layout.preferredWidth: simpleLayout.iconSize
                Layout.preferredHeight: simpleLayout.iconSize
                Layout.minimumWidth: simpleLayout.iconSize
                Layout.maximumWidth: simpleLayout.iconSize
                Layout.minimumHeight: simpleLayout.iconSize
                Layout.maximumHeight: simpleLayout.iconSize
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter

                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle === "colorful"
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    smooth: true
                }
                Text {
                    anchors.fill: parent
                    anchors.topMargin: 2
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: Math.round(simpleLayout.iconSize * 0.6)
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Label {
                text: compactRoot.weatherRoot ? compactRoot.weatherRoot.tempValue(compactRoot.weatherRoot.temperatureC) : "--"
                font.pixelSize: simpleLayout.fontSize
                font.bold: false
                color: Kirigami.Theme.textColor
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
            }

            // Icon when order is icon first (icon appears first)
            Item {
                visible: compactRoot.simpleWidgetOrder === 1
                Layout.preferredWidth: simpleLayout.iconSize
                Layout.preferredHeight: simpleLayout.iconSize
                Layout.minimumWidth: simpleLayout.iconSize
                Layout.maximumWidth: simpleLayout.iconSize
                Layout.minimumHeight: simpleLayout.iconSize
                Layout.maximumHeight: simpleLayout.iconSize
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter

                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle === "colorful"
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    smooth: true
                }
                Text {
                    anchors.fill: parent
                    anchors.topMargin: 2
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: Math.round(simpleLayout.iconSize * 0.6)
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // ── Compressed — temperature badge overlaps bottom-right of icon ––
        Item {
            anchors.centerIn: parent
            visible: compactRoot.simpleLayoutType === 2
            width: simpleLayout.iconSize + Math.round(simpleLayout.fontSize * 0.8)
            height: simpleLayout.iconSize

            // Icon container
            Item {
                id: compressedIconContainer
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: simpleLayout.iconSize
                height: simpleLayout.iconSize

                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle === "colorful"
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    smooth: true
                }
                Text {
                    anchors.fill: parent
                    width: parent.width   // or set a fixed size
                    height: parent.height
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: Math.round(simpleLayout.iconSize * 0.7)
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Temperature badge
            Rectangle {
                anchors.right: compressedIconContainer.right
                anchors.bottom: compressedIconContainer.bottom
                anchors.rightMargin: -Math.round(simpleLayout.fontSize * 1)
                anchors.bottomMargin: -Math.round(simpleLayout.fontSize * 0.15)
                width: tempBadge.implicitWidth + 8
                height: tempBadge.implicitHeight + 4
                radius: height / 2
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.8)
                Label {
                    id: tempBadge
                    anchors.centerIn: parent
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.tempValue(compactRoot.weatherRoot.temperatureC) : "--"
                    font.pixelSize: simpleLayout.fontSize
                    font.bold: false
                    color: Kirigami.Theme.textColor
                }
            }
        }

        // ── Vertical ──────────────────────────────────────────────────────
        ColumnLayout {
            anchors.centerIn: parent
            spacing: Math.max(1, Math.round(simpleLayout.fontSize * (-1.5)))
            visible: compactRoot.simpleLayoutType === 1

            // Top icon (when order icon first)
            Item {
                visible: compactRoot.simpleWidgetOrder === 0
                Layout.preferredWidth: simpleLayout.iconSize
                Layout.preferredHeight: simpleLayout.iconSize
                Layout.minimumWidth: simpleLayout.iconSize
                Layout.maximumWidth: simpleLayout.iconSize
                Layout.minimumHeight: simpleLayout.iconSize
                Layout.maximumHeight: simpleLayout.iconSize
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignHCenter

                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle === "colorful"
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    smooth: true
                }
                Text {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: Math.round(simpleLayout.iconSize * 0.9)
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Label {
                text: compactRoot.weatherRoot ? compactRoot.weatherRoot.tempValue(compactRoot.weatherRoot.temperatureC) : "--"
                font.pixelSize: simpleLayout.fontSize
                font.bold: false
                color: Kirigami.Theme.textColor
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            // Bottom icon (when order temperature first)
            Item {
                visible: compactRoot.simpleWidgetOrder === 1
                Layout.preferredWidth: simpleLayout.iconSize
                Layout.preferredHeight: simpleLayout.iconSize
                Layout.minimumWidth: simpleLayout.iconSize
                Layout.maximumWidth: simpleLayout.iconSize
                Layout.minimumHeight: simpleLayout.iconSize
                Layout.maximumHeight: simpleLayout.iconSize
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignHCenter

                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle === "colorful"
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    smooth: true
                }
                Text {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: Math.round(simpleLayout.iconSize * 0.9)
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    } // Item (simple mode)

    // ── Tap to expand ─────────────────────────────────────────────────────
    TapHandler {
        acceptedButtons: Qt.LeftButton
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onTapped: if (compactRoot.weatherRoot)
            compactRoot.weatherRoot.expanded = !compactRoot.weatherRoot.expanded
    }

    // ── Private: build panel items array ─────────────────────────────────
    function _buildItems() {
        var r = weatherRoot;
        if (!r)
            return [];
        if (!r.hasSelectedTown)
            return [
                {
                    glyph: "\uF041",
                    glyphVis: true,
                    glyphType: "wi",
                    text: i18n("Add a location"),
                    isSep: false
                }
            ];

        var iconMap = r.parsePanelItemIcons();
        var sep = Plasmoid.configuration.panelSeparator || " \u2022 ";
        var order = (Plasmoid.configuration.panelItemOrder || "condition;temperature").split(";").filter(function (t) {
            return t.trim().length > 0;
        });
        var tokens = order;
        var theme = Plasmoid.configuration.panelIconTheme || "wi-font";
        var result = [];

        tokens.forEach(function (tok) {
            tok = tok.trim();
            var show = (tok in iconMap) ? iconMap[tok] : true;
            var iconInfo = r.panelItemIconInfo(tok);

            if (tok === "suntimes") {
                var sunMode = Plasmoid.configuration.panelSunTimesMode || "upcoming";
                if (sunMode === "both" && theme === "wi-font") {
                    if (result.length > 0)
                        result.push({
                            glyph: "",
                            glyphVis: false,
                            glyphType: "wi",
                            glyphKdeFallback: "",
                            text: sep,
                            isSep: true
                        });
                    result.push({
                        glyph: "\uF051",
                        glyphVis: show,
                        glyphType: "wi",
                        glyphKdeFallback: "",
                        text: r.sunriseTimeText,
                        isSep: false
                    });
                    result.push({
                        glyph: "",
                        glyphVis: false,
                        glyphType: "wi",
                        glyphKdeFallback: "",
                        text: " ",
                        isSep: true
                    });
                    result.push({
                        glyph: "\uF052",
                        glyphVis: show,
                        glyphType: "wi",
                        glyphKdeFallback: "",
                        text: r.sunsetTimeText,
                        isSep: false
                    });
                    return;
                }
                if (sunMode === "both" && theme !== "wi-font") {
                    var riseInfo2, setInfo2;
                    if (theme === "kde") {
                        riseInfo2 = {
                            type: "kde",
                            source: "weather-sunrise",
                            kdeFallback: ""
                        };
                        setInfo2 = {
                            type: "kde",
                            source: "weather-sunset",
                            kdeFallback: ""
                        };
                    } else if (theme === "custom") {
                        var rawC2 = Plasmoid.configuration.panelCustomIcons || "", cmap2 = {};
                        rawC2.split(";").forEach(function (p) {
                            var kv = p.split("=");
                            if (kv.length === 2)
                                cmap2[kv[0].trim()] = kv[1].trim();
                        });
                        riseInfo2 = {
                            type: "kde",
                            source: cmap2["suntimes-sunrise"] || "weather-sunrise",
                            kdeFallback: ""
                        };
                        setInfo2 = {
                            type: "kde",
                            source: cmap2["suntimes-sunset"] || "weather-sunset",
                            kdeFallback: ""
                        };
                    } else {
                        var iconSz2 = Plasmoid.configuration.panelIconSize || 22;
                        var rt2 = (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light") ? "symbolic-light" : theme;
                        var base2 = Qt.resolvedUrl("../icons/" + rt2 + "/" + iconSz2 + "/wi-");
                        riseInfo2 = {
                            type: "svg",
                            source: base2 + "sunrise.svg",
                            kdeFallback: ""
                        };
                        setInfo2 = {
                            type: "svg",
                            source: base2 + "sunset.svg",
                            kdeFallback: ""
                        };
                    }
                    if (result.length > 0)
                        result.push({
                            glyph: "",
                            glyphVis: false,
                            glyphType: "wi",
                            glyphKdeFallback: "",
                            text: sep,
                            isSep: true
                        });
                    result.push({
                        glyph: riseInfo2.source,
                        glyphVis: show,
                        glyphType: riseInfo2.type,
                        glyphKdeFallback: "",
                        text: r.sunriseTimeText,
                        isSep: false
                    });
                    result.push({
                        glyph: "",
                        glyphVis: false,
                        glyphType: "wi",
                        glyphKdeFallback: "",
                        text: " ",
                        isSep: true
                    });
                    result.push({
                        glyph: setInfo2.source,
                        glyphVis: show,
                        glyphType: setInfo2.type,
                        glyphKdeFallback: "",
                        text: r.sunsetTimeText,
                        isSep: false
                    });
                    return;
                }
                var stx = r.panelItemTextOnly(tok);
                if (!stx || stx.length === 0)
                    return;
                if (result.length > 0)
                    result.push({
                        glyph: "",
                        glyphVis: false,
                        glyphType: "wi",
                        glyphKdeFallback: "",
                        text: sep,
                        isSep: true
                    });
                result.push({
                    glyph: iconInfo.source,
                    glyphVis: show && iconInfo.source.length > 0,
                    glyphType: iconInfo.type,
                    glyphKdeFallback: iconInfo.kdeFallback || "",
                    text: stx,
                    isSep: false
                });
                return;
            }

            var txt = r.panelItemTextOnly(tok);
            if (!txt || txt.length === 0)
                return;
            if (result.length > 0)
                result.push({
                    glyph: "",
                    glyphVis: false,
                    glyphType: "wi",
                    glyphKdeFallback: "",
                    text: sep,
                    isSep: true
                });
            result.push({
                glyph: iconInfo.source,
                glyphVis: show && iconInfo.source.length > 0,
                glyphType: iconInfo.type,
                glyphKdeFallback: iconInfo.kdeFallback || "",
                text: txt,
                isSep: false
            });
        });
        return result;
    }
}
