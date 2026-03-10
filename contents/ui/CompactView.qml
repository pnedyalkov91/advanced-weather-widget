/**
 * CompactView.qml — Panel / compact representation
 *
 * Renders the panel bar: wi-font icon + value chips separated by a bullet.
 * Also hosts the custom tooltip popup (TooltipContent).
 *
 * Display modes (Plasmoid.configuration.panelInfoMode):
 *   "single"    — all items in one row
 *   "multiline" — large weather icon left + scrolling item rows right
 *   "simple"    — icon + temperature only
 *
 * Simple mode layout types (Plasmoid.configuration.panelSimpleLayoutType):
 *   0 = side-by-side  (icon | temp)
 *   1 = stacked       (icon over temp, or temp over icon)
 *   2 = compressed    (temp badge overlapping bottom-right of icon)
 *
 * Key sizing rules (mirrors weather-widget-plus/CompactItem.qml):
 *   • vertical panel   → cells fill WIDTH,  fontSizeMode = Text.HorizontalFit
 *   • horizontal panel → cells fill HEIGHT, fontSizeMode = Text.VerticalFit
 *   • Layout.fillHeight is false for vertical panels (prevents widget
 *     greedily consuming all vertical space in the panel)
 *   • uniformCellHeights only applies when vertical + stacked (type 1)
 *   • The GridLayout is centered in its parent at content size so no
 *     dead space bleeds through around icon/temp cells
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

    // ── Public interface — bound from main.qml ────────────────────────────
    property var weatherRoot

    // ── Panel orientation ─────────────────────────────────────────────────
    // True when the plasmoid lives in a vertical (left / right) panel.
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // ── Shared sizing ─────────────────────────────────────────────────────
    readonly property int leftRightMargin: 4
    readonly property int itemSpacing: Plasmoid.configuration.panelItemSpacing !== undefined ? Plasmoid.configuration.panelItemSpacing : 5

    readonly property int panelFontPx: {
        if (!Plasmoid.configuration.panelUseSystemFont && Plasmoid.configuration.panelFontSize > 0)
            return Math.round(Plasmoid.configuration.panelFontSize * 4 / 3);
        return Kirigami.Theme.defaultFont.pixelSize;
    }
    // Wi-font glyphs rendered slightly larger than normal text
    readonly property int glyphSize: Math.max(12, Math.round(panelFontPx * 1.3))
    readonly property int svgIconPx: {
        var th = Plasmoid.configuration.panelIconTheme || "wi-font";
        return th === "wi-font" ? glyphSize : (Plasmoid.configuration.panelIconSize || 22);
    }

    // ── Mode helpers ──────────────────────────────────────────────────────
    readonly property bool isMultiLine: Plasmoid.configuration.panelInfoMode === "multiline"
    readonly property bool isSimpleMode: Plasmoid.configuration.panelInfoMode === "simple"

    readonly property int simpleLayoutType: Plasmoid.configuration.panelSimpleLayoutType || 0
    readonly property int simpleWidgetOrder: Plasmoid.configuration.panelSimpleWidgetOrder || 0
    readonly property string simpleIconStyle: Plasmoid.configuration.panelSimpleIconStyle || "symbolic"

    // ── Vertical-panel size scale factors ────────────────────────────────
    // Change these two values to resize icon and temperature in vertical panels.
    // 1.0 = natural size (auto-fits panel thickness).  > 1.0 = larger, < 1.0 = smaller.
    // ── Simple-mode sizing (reads from Plasmoid.configuration) ──────────────
    // Icon size: auto = fills cell via HorizontalFit/VerticalFit
    //            manual = fixed pixel size set in settings (Icon Size spinner)
    // Font size: auto = proportional to rendered icon (50% of paintedHeight)
    //            manual = fixed pixel size set in settings (Font Size spinner)
    readonly property bool simpleIconAuto: (Plasmoid.configuration.simpleIconSizeMode || "auto") === "auto"
    readonly property int simpleIconPx: Plasmoid.configuration.simpleIconSizeManual || 32
    readonly property bool simpleFontAuto: (Plasmoid.configuration.simpleFontSizeMode || "auto") === "auto"
    readonly property int simpleFontPx: Plasmoid.configuration.simpleFontSizeManual || 14

    // ── Multiline options ─────────────────────────────────────────────────
    readonly property string mlIconStyle: Plasmoid.configuration.panelMultilineIconStyle || "colorful"
    readonly property int multiLines: Math.max(1, Plasmoid.configuration.panelMultiLines || 2)
    readonly property bool multiAnimate: Plasmoid.configuration.panelMultiAnimate !== false
    // 0 = auto-fit panel height; >0 = user-specified px (from settings spinner)
    readonly property int _mlIconSizeCfg: Plasmoid.configuration.panelMultilineIconSize || 0
    readonly property int mlIconSize: _mlIconSizeCfg > 0 ? _mlIconSizeCfg : Math.min(Math.max(multiLines * (panelFontPx + 8), 32) - 4, 64)
    // Vertical multiline sizing (panel width drives icon; font drives rows)
    readonly property int mlVertIconSz: _mlIconSizeCfg > 0 ? _mlIconSizeCfg : Math.min(Math.max(16, width - 4), 64)
    // Row height must fit both text AND icons (wi-font glyph or SVG).
    readonly property int mlVertRowH: Math.max(14, panelFontPx + 6, glyphSize + 4, svgIconPx + 4)

    // ── Root implicit sizes ───────────────────────────────────────────────
    // For vertical panels + stacked simple mode, reserve double the usual
    // height so KDE allocates enough room for two stacked cells.
    // side-by-side (type 0) on horizontal panel needs room for icon + temp
    // Simple mode on a horizontal panel: track panel height so the widget
    // stays exactly as wide as its content regardless of how tall the panel gets.
    //   type 0 side-by-side → icon (≈h) + gap (10) + temp (≈h*0.5) + margins
    //   type 1 stacked / type 2 compressed → one square ≈ h + margins
    implicitWidth: isMultiLine ? mlIconSize + 6 + 110 + 2 * leftRightMargin : isSimpleMode ? (vertical ? Kirigami.Units.gridUnit * 2 : (simpleLayoutType === 0 ? Math.max(Kirigami.Units.gridUnit * 4, Math.round(compactRoot.height * 1.8) + 10 + 2 * leftRightMargin) : Math.max(Kirigami.Units.gridUnit * 2, compactRoot.height + 2 * leftRightMargin))) : compactRow.implicitWidth + 2 * leftRightMargin

    implicitHeight: isMultiLine ? Math.max(multiLines * (panelFontPx + 8), 32) : Kirigami.Units.gridUnit * 2

    // ── Layout hints to the panel ─────────────────────────────────────────
    // vertical panels: fillHeight=false keeps the widget from consuming all
    // available panel height.  preferredHeight scales with panel thickness
    // (= widget width) so the click area grows as the panel gets wider.
    // vertical single-line: fillHeight when "Fill panel" is on (expands to full panel height)
    // vertical: fillHeight when "Fill panel" is on — works for all display modes
    // vertical single-line: fillHeight when "Fill panel" is on
    // Fill-panel for vertical single-line mirrors the horizontal pattern:
    //   horizontal: fillWidth:true  + preferredWidth:-1
    //   vertical:   fillHeight:true + preferredHeight:-1
    readonly property bool vertFill: vertical && !isSimpleMode && !isMultiLine && Plasmoid.configuration.panelFillWidth

    Layout.fillHeight: !vertical || compactRoot.vertFill
    Layout.fillWidth: vertical || Plasmoid.configuration.panelFillWidth

    Layout.preferredWidth: (vertical || Plasmoid.configuration.panelFillWidth) ? -1 : isMultiLine ? mlIconSize + 6 + (Plasmoid.configuration.panelWidth || 110) + 2 * leftRightMargin : implicitWidth
    Layout.preferredHeight: {
        // Vertical single-line + fill: return -1 so fillHeight can expand freely
        // (mirrors preferredWidth:-1 used for horizontal fill)
        if (compactRoot.vertFill)
            return -1;
        if (vertical && isMultiLine)
            return compactRoot.mlVertIconSz + compactRoot.multiLines * compactRoot.mlVertRowH + 8;
        if (vertical && !compactRoot.isSimpleMode && !isMultiLine) {
            var pd = compactRoot.panelItemsData;
            var nItems = 0, nSeps = 0;
            for (var ii = 0; ii < pd.length; ++ii)
                pd[ii].isSep ? nSeps++ : nItems++;
            var sepH = compactRoot.panelFontPx + 4;  // matches separator Label font
            var gaps = Math.max(0, nItems + nSeps - 1) * compactRoot.itemSpacing;
            return nItems * compactRoot.mlVertRowH + nSeps * sepH + gaps + 4;
        }
        if (!vertical)
            return -1;
        var iH = compactRoot.simpleIconAuto ? Math.max(Kirigami.Units.gridUnit * 2, Math.round(compactRoot.width)) : compactRoot.simpleIconPx;
        var tH = compactRoot.simpleFontAuto ? Math.round(iH * 0.5) : compactRoot.simpleFontPx;
        if (simpleLayoutType === 1)
            return iH + tH + 6;
        if (simpleLayoutType === 2)
            return iH + 4;
        return Math.max(iH, tH) + 4;
    }
    Layout.minimumWidth: 20
    Layout.minimumHeight: implicitHeight

    // ── Wi-font loader ────────────────────────────────────────────────────
    FontLoader {
        id: wiFontPanel
        source: Qt.resolvedUrl("../fonts/weathericons-regular-webfont.ttf")
    }

    readonly property string iconTheme: Plasmoid.configuration.panelIconTheme || "wi-font"

    // ── Reactive panel items data ─────────────────────────────────────────
    property var panelItemsData: {
        if (!weatherRoot)
            return [];
        // Touch every reactive property so this re-evaluates when data changes
        var _deps = weatherRoot.temperatureC + weatherRoot.windKmh + weatherRoot.windDirection + weatherRoot.humidityPercent + weatherRoot.pressureHpa + weatherRoot.weatherCode + weatherRoot.panelScrollIndex + weatherRoot.sunriseTimeText.length + weatherRoot.sunsetTimeText.length + Plasmoid.configuration.panelItemOrder + Plasmoid.configuration.panelItemIcons + Plasmoid.configuration.panelInfoMode + Plasmoid.configuration.panelSeparator + Plasmoid.configuration.panelSunTimesMode + compactRoot.iconTheme + Plasmoid.configuration.panelIconSize;
        return _buildItems();
    }

    property var multiLineItemsData: {
        var all = panelItemsData, r = [];
        for (var i = 0; i < all.length; ++i)
            if (!all[i].isSep)
                r.push(all[i]);
        return r;
    }

    readonly property real multiLineRowH: height > 0 ? Math.max(14, height / multiLines) : Math.max(14, panelFontPx + 8)

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

    mainItem: TooltipContent {
        weatherRoot: compactRoot.weatherRoot
    }

    // ══════════════════════════════════════════════════════════════════════
    // SINGLE / SCROLL MODE
    // ══════════════════════════════════════════════════════════════════════
    // ══════════════════════════════════════════════════════════════════════
    // SINGLE LINE MODE — orientation aware
    //   Horizontal panel: all items in one row (original behaviour)
    //   Vertical panel:   each item on its own row, stacked top-to-bottom
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: singleLineRoot
        visible: !compactRoot.isMultiLine && !compactRoot.isSimpleMode
        anchors.fill: parent

        // ── HORIZONTAL: all items in one scrolling row ────────────────
        RowLayout {
            id: compactRow
            visible: !compactRoot.vertical
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
                    spacing: 5

                    Text {
                        visible: slRowItem.modelData.glyphVis && slRowItem.modelData.glyphType === "wi"
                        text: slRowItem.modelData.glyph
                        font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                        font.pixelSize: compactRoot.glyphSize
                        color: Kirigami.Theme.textColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Kirigami.Icon {
                        visible: slRowItem.modelData.glyphVis && slRowItem.modelData.glyphType === "kde" && slRowItem.modelData.glyph.length > 0
                        source: slRowItem.modelData.glyph
                        implicitWidth: compactRoot.svgIconPx
                        implicitHeight: compactRoot.svgIconPx
                    }
                    Kirigami.Icon {
                        visible: slRowItem.modelData.glyphVis && slRowItem.modelData.glyphType === "kirigami" && slRowItem.modelData.glyph.length > 0
                        source: slRowItem.modelData.glyph
                        implicitWidth: compactRoot.glyphSize
                        implicitHeight: compactRoot.glyphSize
                    }
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
                    Label {
                        text: slRowItem.modelData.text
                        font: compactRoot.weatherRoot ? compactRoot.weatherRoot.wpf(compactRoot.panelFontPx, false) : Qt.font({
                            pixelSize: compactRoot.panelFontPx
                        })
                        color: Kirigami.Theme.textColor
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        } // RowLayout (horizontal)

        // ── VERTICAL: each item on its own row ───────────────────────
        // When vertFill is on, data rows share the extra height equally
        // (Layout.fillHeight:true on each row distributes the surplus).
        ColumnLayout {
            visible: compactRoot.vertical
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            spacing: compactRoot.itemSpacing

            Repeater {
                model: compactRoot.panelItemsData
                delegate: Item {
                    id: slVertItem
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    // Separators stay thin; data rows expand to fill surplus height
                    Layout.fillHeight: !slVertItem.modelData.isSep && compactRoot.vertFill
                    Layout.preferredHeight: slVertItem.modelData.isSep ? (compactRoot.panelFontPx + 4) : compactRoot.mlVertRowH
                    Layout.minimumHeight: slVertItem.modelData.isSep ? (compactRoot.panelFontPx + 4) : compactRoot.mlVertRowH

                    // ── Separator ─────────────────────────────────────
                    Label {
                        visible: slVertItem.modelData.isSep
                        anchors.fill: parent
                        text: slVertItem.modelData.text.trim() || "\u2022"
                        font: compactRoot.weatherRoot ? compactRoot.weatherRoot.wpf(compactRoot.panelFontPx, false) : Qt.font({
                            pixelSize: compactRoot.panelFontPx
                        })
                        color: Kirigami.Theme.textColor
                        opacity: 0.5
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    // ── Data row ──────────────────────────────────────
                    RowLayout {
                        visible: !slVertItem.modelData.isSep
                        anchors.fill: parent
                        spacing: 4
                        clip: false

                        Text {
                            visible: slVertItem.modelData.glyphVis && slVertItem.modelData.glyphType === "wi"
                            text: slVertItem.modelData.glyph
                            font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                            font.pixelSize: compactRoot.glyphSize
                            color: Kirigami.Theme.textColor
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Kirigami.Icon {
                            visible: slVertItem.modelData.glyphVis && slVertItem.modelData.glyphType === "kde" && slVertItem.modelData.glyph.length > 0
                            source: slVertItem.modelData.glyph
                            implicitWidth: compactRoot.svgIconPx
                            implicitHeight: compactRoot.svgIconPx
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Kirigami.Icon {
                            visible: slVertItem.modelData.glyphVis && slVertItem.modelData.glyphType === "kirigami" && slVertItem.modelData.glyph.length > 0
                            source: slVertItem.modelData.glyph
                            implicitWidth: compactRoot.mlVertRowH
                            implicitHeight: compactRoot.mlVertRowH
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Item {
                            visible: slVertItem.modelData.glyphVis && slVertItem.modelData.glyphType === "svg" && slVertItem.modelData.glyph.length > 0
                            implicitWidth: compactRoot.svgIconPx
                            implicitHeight: compactRoot.svgIconPx
                            Layout.alignment: Qt.AlignVCenter
                            Kirigami.Icon {
                                anchors.fill: parent
                                source: slVertItem.modelData.glyphKdeFallback || ""
                                visible: (slVertItem.modelData.glyphKdeFallback || "").length > 0
                            }
                            Kirigami.Icon {
                                anchors.fill: parent
                                source: slVertItem.modelData.glyph
                                isMask: compactRoot.iconTheme === "symbolic"
                                color: Kirigami.Theme.textColor
                            }
                        }
                        Label {
                            text: slVertItem.modelData.text
                            font: compactRoot.weatherRoot ? compactRoot.weatherRoot.wpf(compactRoot.mlVertRowH - 4, false) : Qt.font({
                                pixelSize: compactRoot.mlVertRowH - 4
                            })
                            color: Kirigami.Theme.textColor
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.maximumWidth: {
                                var w = Plasmoid.configuration.panelWidth || 0;
                                return w > 0 ? w : Number.MAX_VALUE;
                            }
                        }
                    }
                }
            }
        } // ColumnLayout (vertical)
    } // singleLineRoot

    // ══════════════════════════════════════════════════════════════════════
    // MULTILINE MODE
    // ══════════════════════════════════════════════════════════════════════
    // ══════════════════════════════════════════════════════════════════════
    // MULTILINE MODE — orientation aware
    //   Horizontal panel: icon on the left, text rows on the right (RowLayout)
    //   Vertical panel:   icon on top,      text rows below       (ColumnLayout)
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: multiLineRoot
        visible: compactRoot.isMultiLine && !compactRoot.isSimpleMode
        anchors.fill: parent

        // ── HORIZONTAL: icon left + scrolling rows right ──────────────────
        RowLayout {
            visible: !compactRoot.vertical
            anchors.fill: parent
            anchors.leftMargin: compactRoot.leftRightMargin
            anchors.rightMargin: compactRoot.leftRightMargin
            spacing: 6

            Item {
                readonly property int iconSz: compactRoot.height > 8 ? Math.min(compactRoot.height - 4, 64) : compactRoot.mlIconSize
                Layout.preferredWidth: iconSz
                Layout.preferredHeight: iconSz
                Layout.alignment: Qt.AlignVCenter
                Text {
                    anchors.fill: parent
                    visible: compactRoot.mlIconStyle === "symbolic"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: 999
                    font.pointSize: 0
                    minimumPixelSize: 8
                    fontSizeMode: Text.Fit
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.mlIconStyle !== "symbolic"
                    source: compactRoot.weatherRoot ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode, compactRoot.weatherRoot.isNightTime()) : "weather-none-available"
                    smooth: true
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                Column {
                    id: scrollCol
                    width: parent.width
                    readonly property real rowH: compactRoot.height > 0 ? Math.max(12, compactRoot.height / compactRoot.multiLines) : Math.max(12, compactRoot.panelFontPx + 8)
                    readonly property int rowFontPx: {
                        var sys = Plasmoid.configuration.panelUseSystemFont;
                        var savedP = Plasmoid.configuration.panelFontSize || 0;
                        var maxR = Math.max(8, Math.floor(rowH * 0.72));
                        if (!sys && savedP > 0)
                            return Math.min(maxR, Math.round(savedP * 4 / 3));
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
        } // RowLayout (horizontal)

        // ── VERTICAL: icon top + scrolling rows below ─────────────────────
        ColumnLayout {
            visible: compactRoot.vertical
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            spacing: 2

            Item {
                Layout.preferredWidth: compactRoot.mlVertIconSz
                Layout.preferredHeight: compactRoot.mlVertIconSz
                Layout.alignment: Qt.AlignHCenter
                Text {
                    anchors.fill: parent
                    visible: compactRoot.mlIconStyle === "symbolic"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: 999
                    font.pointSize: 0
                    minimumPixelSize: 8
                    fontSizeMode: Text.Fit
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.mlIconStyle !== "symbolic"
                    source: compactRoot.weatherRoot ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode, compactRoot.weatherRoot.isNightTime()) : "weather-none-available"
                    smooth: true
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: compactRoot.multiLines * compactRoot.mlVertRowH
                clip: true
                Column {
                    id: scrollColV
                    width: parent.width
                    readonly property real rowH: compactRoot.mlVertRowH
                    readonly property int rowFontPx: {
                        var sys = Plasmoid.configuration.panelUseSystemFont;
                        var savedP = Plasmoid.configuration.panelFontSize || 0;
                        var maxR = Math.max(8, Math.floor(rowH * 0.72));
                        if (!sys && savedP > 0)
                            return Math.min(maxR, Math.round(savedP * 4 / 3));
                        return Math.max(8, Math.floor(rowH * 0.65));
                    }
                    Behavior on y {
                        enabled: compactRoot.multiAnimate && compactRoot.mlScrollOffset !== 0
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutCubic
                        }
                    }
                    y: -(compactRoot.mlScrollOffset * scrollColV.rowH)

                    Repeater {
                        model: compactRoot.multiLineItemsData
                        delegate: RowLayout {
                            id: mlRowItemV
                            required property var modelData
                            required property int index
                            width: scrollColV.width
                            height: scrollColV.rowH
                            spacing: 4
                            clip: true
                            Text {
                                visible: mlRowItemV.modelData.glyphVis && mlRowItemV.modelData.glyphType === "wi"
                                text: mlRowItemV.modelData.glyph
                                font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                                font.pixelSize: Math.round(scrollColV.rowFontPx * 1.3)
                                color: Kirigami.Theme.textColor
                                verticalAlignment: Text.AlignVCenter
                            }
                            Kirigami.Icon {
                                visible: mlRowItemV.modelData.glyphVis && mlRowItemV.modelData.glyphType === "kde" && mlRowItemV.modelData.glyph.length > 0
                                source: mlRowItemV.modelData.glyph
                                implicitWidth: compactRoot.svgIconPx
                                implicitHeight: compactRoot.svgIconPx
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Kirigami.Icon {
                                visible: mlRowItemV.modelData.glyphVis && mlRowItemV.modelData.glyphType === "kirigami" && mlRowItemV.modelData.glyph.length > 0
                                source: mlRowItemV.modelData.glyph
                                implicitWidth: scrollColV.rowFontPx
                                implicitHeight: scrollColV.rowFontPx
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Item {
                                visible: mlRowItemV.modelData.glyphVis && mlRowItemV.modelData.glyphType === "svg" && mlRowItemV.modelData.glyph.length > 0
                                implicitWidth: compactRoot.svgIconPx
                                implicitHeight: compactRoot.svgIconPx
                                Layout.alignment: Qt.AlignVCenter
                                Kirigami.Icon {
                                    anchors.fill: parent
                                    source: mlRowItemV.modelData.glyphKdeFallback || ""
                                    visible: (mlRowItemV.modelData.glyphKdeFallback || "").length > 0
                                }
                                Kirigami.Icon {
                                    anchors.fill: parent
                                    source: mlRowItemV.modelData.glyph
                                    isMask: compactRoot.iconTheme === "symbolic"
                                    color: Kirigami.Theme.textColor
                                }
                            }
                            Label {
                                text: mlRowItemV.modelData.text
                                font: compactRoot.weatherRoot ? compactRoot.weatherRoot.wpf(scrollColV.rowFontPx, false) : Qt.font({
                                    pixelSize: scrollColV.rowFontPx
                                })
                                color: Kirigami.Theme.textColor
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        } // ColumnLayout (vertical)
    } // multiLineRoot

    // ══════════════════════════════════════════════════════════════════════
    // SIMPLE MODE — icon + temperature
    //
    // Architecture (directly mirrors weather-widget-plus/CompactItem.qml):
    //
    //   vertical panel   → cells fill WIDTH,  fontSizeMode = Text.HorizontalFit
    //   horizontal panel → cells fill HEIGHT, fontSizeMode = Text.VerticalFit
    //
    // The GridLayout is sized to exactly its content and centered inside
    // the widget — so no dead space appears between or around cells.
    //
    // uniformCellHeights is ONLY enabled for vertical + stacked (type 1),
    // matching the reference behaviour exactly.
    //
    // Compressed (type 2) is built separately: a square Item (side =
    // min(width, height)) contains both the icon and the badge so the badge
    // always overlaps the bottom-right corner of the actual painted icon.
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: simpleRoot
        anchors.fill: parent
        visible: compactRoot.isSimpleMode

        // fontSizeMode driven purely by panel orientation — not layout type
        readonly property int autoFontSizeMode: compactRoot.vertical ? Text.HorizontalFit : Text.VerticalFit

        // ── Layout types 0 (side-by-side) and 1 (stacked) ────────────────
        // The GridLayout is anchored to the CENTER of its parent and sized
        // to exactly its content.  This prevents any dead space from pooling
        // around the cells when the panel is larger than the content.
        //
        //   vertical panel:
        //     width  = full widget width (cells fill it with HorizontalFit)
        //     height = auto (sum of row paintedHeights; GridLayout.implicitHeight)
        //
        //   horizontal panel:
        //     height = full widget height (cells fill it with VerticalFit)
        //     width  = auto (sum of column paintedWidths; GridLayout.implicitWidth)
        GridLayout {
            id: simpleGrid
            visible: compactRoot.simpleLayoutType !== 2

            // Centre in parent; size determined by axis.
            anchors.centerIn: parent
            width: compactRoot.vertical ? parent.width : implicitWidth

            // vertical + stacked (type 1): height = implicitHeight so the grid is exactly
            // 2×paintedHeight + rowSpacing and sits centred — no dead space above/below cells.
            // All other cases: fill the available widget height.
            height: (compactRoot.vertical && compactRoot.simpleLayoutType === 1) ? implicitHeight : parent.height - 2

            // type 1 → 2 rows × 1 col; type 0 → 1 row × 2 cols
            rows: compactRoot.simpleLayoutType === 1 ? 2 : 1
            columns: compactRoot.simpleLayoutType === 1 ? 1 : 2

            // uniformCellHeights only for vertical + stacked — exactly as reference
            uniformCellHeights: compactRoot.simpleLayoutType === 1 && compactRoot.vertical

            // columnSpacing: always 4 px between icon and temp for vertical type 0 so
            //   there is a visible gap at every panel size.
            // rowSpacing: for vertical + stacked scale with panel width so the gap
            //   shrinks proportionally as the panel gets narrower, never causes overlap.
            // ← EDIT: change the numbers below to adjust spacing between icon and temperature
            //   columnSpacing controls horizontal-type (type 0) on vertical panels
            //   rowSpacing    controls vertical-type   (type 1) on vertical panels
            columnSpacing: compactRoot.simpleLayoutType === 0 ? (compactRoot.vertical ? 2 : 10) : 0
            rowSpacing: (compactRoot.vertical && compactRoot.simpleLayoutType === 1) ? Math.max(0, Math.min(2, Math.round(compactRoot.width * 2.02))) : 0

            // ── Icon cell ─────────────────────────────────────────────────
            Item {
                // Hide until the glyph has loaded to avoid mis-sized cells
                visible: iconGlyph.text.length > 0 || compactRoot.simpleIconStyle === "colorful"
                Layout.alignment: Qt.AlignCenter
                // No clip needed: HorizontalFit never overflows its cell.

                // vertical panel: fill width; height clamped to paintedHeight
                // horizontal panel: fill height; width clamped to paintedWidth
                Layout.fillWidth: compactRoot.vertical
                Layout.fillHeight: !compactRoot.vertical
                Layout.minimumWidth: compactRoot.vertical ? 0 : iconGlyph.paintedWidth
                Layout.maximumWidth: compactRoot.vertical ? Infinity : iconGlyph.paintedWidth
                Layout.minimumHeight: compactRoot.vertical ? iconGlyph.paintedHeight : 0
                Layout.maximumHeight: compactRoot.vertical ? iconGlyph.paintedHeight : Infinity

                // Widget order: 0 = icon first, 1 = temp first
                Layout.row: compactRoot.simpleLayoutType === 1 ? (compactRoot.simpleWidgetOrder === 0 ? 0 : 1) : 0
                Layout.column: compactRoot.simpleLayoutType === 1 ? 0 : (compactRoot.simpleWidgetOrder === 0 ? 0 : 1)

                Text {
                    id: iconGlyph
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    // font.pixelSize = upper cap for HorizontalFit on vertical panels.
                    // Auto: 999 + autoFontSizeMode → fills cell (HorizontalFit/VerticalFit).
                    // Manual: fixed pixel size from settings + FixedSize.
                    font.pixelSize: compactRoot.simpleIconAuto ? 999 : compactRoot.simpleIconPx
                    font.pointSize: 0
                    minimumPixelSize: Math.round(Kirigami.Units.gridUnit / 2)
                    fontSizeMode: compactRoot.simpleIconAuto ? simpleRoot.autoFontSizeMode : Text.FixedSize
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.NoWrap
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle === "colorful"
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    smooth: true
                }
            }

            // ── Temperature cell ──────────────────────────────────────────
            Item {
                visible: tempText.text.length > 0
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compactRoot.vertical
                Layout.fillHeight: !compactRoot.vertical
                Layout.minimumWidth: compactRoot.vertical ? 0 : tempText.paintedWidth
                Layout.maximumWidth: compactRoot.vertical ? Infinity : tempText.paintedWidth
                Layout.minimumHeight: compactRoot.vertical ? tempText.paintedHeight : 0
                Layout.maximumHeight: compactRoot.vertical ? tempText.paintedHeight : Infinity

                Layout.row: compactRoot.simpleLayoutType === 1 ? (compactRoot.simpleWidgetOrder === 0 ? 1 : 0) : 0
                Layout.column: compactRoot.simpleLayoutType === 1 ? 0 : (compactRoot.simpleWidgetOrder === 0 ? 1 : 0)

                Text {
                    id: tempText
                    anchors.fill: parent
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.tempValue(compactRoot.weatherRoot.temperatureC) : "--"
                    font.family: Kirigami.Theme.defaultFont.family
                    font.pixelSize: compactRoot.simpleFontAuto ? Math.max(compactRoot.panelFontPx, Math.round(iconGlyph.paintedHeight * 0.5)) : compactRoot.simpleFontPx
                    font.pointSize: 0
                    minimumPixelSize: Math.round(Kirigami.Units.gridUnit / 2)
                    fontSizeMode: compactRoot.simpleFontAuto ? simpleRoot.autoFontSizeMode : Text.FixedSize
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.NoWrap
                }
            }
        } // GridLayout (types 0 and 1)

        // ── Compressed (type 2) ───────────────────────────────────────────
        //
        // A square Item (side = min(widget width, widget height)) is centered
        // in the widget.  Both the weather icon AND the badge Rectangle live
        // INSIDE that square, so the badge always anchors to the bottom-right
        // corner of the actual painted icon regardless of panel orientation.
        Item {
            id: compressedWrapper
            anchors.fill: parent
            visible: compactRoot.simpleLayoutType === 2

            // Orientation-aware square sizing:
            //   vertical panel   → side = panel THICKNESS (= widget width)
            //   horizontal panel → side = panel HEIGHT (= widget height)
            // This ensures the compressed icon grows when the panel is resized.
            // Auto: size from panel thickness/height. Manual: use icon size setting.
            readonly property int squareSide: compactRoot.simpleIconAuto ? (compactRoot.vertical ? Math.max(16, compactRoot.width) : Math.max(16, compactRoot.height - 2)) : Math.max(16, compactRoot.simpleIconPx)
            Item {
                id: compressedSquare
                width: compressedWrapper.squareSide
                height: compressedWrapper.squareSide
                anchors.centerIn: parent

                // Weather icon — fills the square; Text.Fit respects both axes
                Text {
                    id: compressedIconGlyph
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconChar() : "?"
                    font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                    font.pixelSize: 999
                    font.pointSize: 0
                    minimumPixelSize: Math.round(Kirigami.Units.gridUnit / 2)
                    fontSizeMode: Text.Fit    // fit both axes for a square cell
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.NoWrap
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: compactRoot.simpleIconStyle === "colorful"
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    smooth: true
                }

                // Temperature badge — anchored inside the square's bottom-right
                // so it always overlaps the icon corner regardless of panel size
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: compressedBadge.implicitWidth + 8
                    height: compressedBadge.implicitHeight + 4
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)

                    Label {
                        id: compressedBadge
                        anchors.centerIn: parent
                        text: compactRoot.weatherRoot ? compactRoot.weatherRoot.tempValue(compactRoot.weatherRoot.temperatureC) : "--"
                        // Badge font ≈ 28 % of the square side; min 8 px
                        // Respect Font Size setting; auto = 40% of square side
                        font.pixelSize: compactRoot.simpleFontAuto ? Math.max(8, Math.round(compressedWrapper.squareSide * 0.4)) : Math.max(8, compactRoot.simpleFontPx)
                        font.bold: false
                        color: Kirigami.Theme.textColor
                    }
                }
            }
        } // compressed

    } // simpleRoot

    // ── Tap to open / close the full view ─────────────────────────────────
    TapHandler {
        acceptedButtons: Qt.LeftButton
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onTapped: if (compactRoot.weatherRoot)
            compactRoot.weatherRoot.expanded = !compactRoot.weatherRoot.expanded
    }

    // ── Private helpers ───────────────────────────────────────────────────
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
                    glyphKdeFallback: "",
                    text: i18n("Add a location"),
                    isSep: false
                }
            ];

        var iconMap = r.parsePanelItemIcons();
        var sep = Plasmoid.configuration.panelSeparator || " \u2022 ";
        var tokens = (Plasmoid.configuration.panelItemOrder || "condition;temperature").split(";").filter(function (t) {
            return t.trim().length > 0;
        });
        var theme = Plasmoid.configuration.panelIconTheme || "wi-font";
        var result = [];

        function pushSep() {
            result.push({
                glyph: "",
                glyphVis: false,
                glyphType: "wi",
                glyphKdeFallback: "",
                text: sep,
                isSep: true
            });
        }
        function pushItem(src, vis, type, fallback, txt) {
            result.push({
                glyph: src,
                glyphVis: vis && src.length > 0,
                glyphType: type,
                glyphKdeFallback: fallback || "",
                text: txt,
                isSep: false
            });
        }
        function pushSpaceSep() {
            result.push({
                glyph: "",
                glyphVis: false,
                glyphType: "wi",
                glyphKdeFallback: "",
                text: " ",
                isSep: true
            });
        }

        tokens.forEach(function (tok) {
            tok = tok.trim();
            var show = (tok in iconMap) ? iconMap[tok] : true;
            var iconInfo = r.panelItemIconInfo(tok);

            if (tok === "suntimes") {
                var sunMode = Plasmoid.configuration.panelSunTimesMode || "upcoming";

                if (sunMode === "both" && theme === "wi-font") {
                    if (result.length > 0)
                        pushSep();
                    pushItem("\uF051", show, "wi", "", r.sunriseTimeText);
                    pushSpaceSep();
                    pushItem("\uF052", show, "wi", "", r.sunsetTimeText);
                    return;
                }

                if (sunMode === "both") {
                    var rInfo, sInfo;
                    if (theme === "kde") {
                        rInfo = {
                            type: "kde",
                            source: "weather-sunrise"
                        };
                        sInfo = {
                            type: "kde",
                            source: "weather-sunset"
                        };
                    } else if (theme === "custom") {
                        var cmap = {};
                        (Plasmoid.configuration.panelCustomIcons || "").split(";").forEach(function (p) {
                            var kv = p.split("=");
                            if (kv.length === 2)
                                cmap[kv[0].trim()] = kv[1].trim();
                        });
                        rInfo = {
                            type: "kde",
                            source: cmap["suntimes-sunrise"] || "weather-sunrise"
                        };
                        sInfo = {
                            type: "kde",
                            source: cmap["suntimes-sunset"] || "weather-sunset"
                        };
                    } else {
                        var sz = Plasmoid.configuration.panelIconSize || 22;
                        var rt = (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light") ? "symbolic-light" : theme;
                        var base = Qt.resolvedUrl("../icons/" + rt + "/" + sz + "/wi-");
                        rInfo = {
                            type: "svg",
                            source: base + "sunrise.svg"
                        };
                        sInfo = {
                            type: "svg",
                            source: base + "sunset.svg"
                        };
                    }
                    if (result.length > 0)
                        pushSep();
                    pushItem(rInfo.source, show, rInfo.type, "", r.sunriseTimeText);
                    pushSpaceSep();
                    pushItem(sInfo.source, show, sInfo.type, "", r.sunsetTimeText);
                    return;
                }

                // upcoming / only-one variant
                var stx = r.panelItemTextOnly(tok);
                if (!stx || stx.length === 0)
                    return;
                if (result.length > 0)
                    pushSep();
                pushItem(iconInfo.source, show, iconInfo.type, iconInfo.kdeFallback, stx);
                return;
            }

            var txt = r.panelItemTextOnly(tok);
            if (!txt || txt.length === 0)
                return;
            if (result.length > 0)
                pushSep();
            pushItem(iconInfo.source, show, iconInfo.type, iconInfo.kdeFallback, txt);
        });

        return result;
    }
}
