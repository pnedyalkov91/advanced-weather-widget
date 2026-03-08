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
    // Recommended range: 0.5 – 2.0
    readonly property real vertIconScale: 0.5   // ← EDIT: icon / font-icon size in vertical panels
    readonly property real vertTempScale: 1.0   // ← EDIT: temperature value size in vertical panels

    // Derived pixel sizes for vertical-panel simple mode.
    // Using fontSizeMode: FixedSize + explicit px so the scale actually takes effect.
    // (HorizontalFit ignores font.pixelSize — it always shrinks to fit cell width.)
    //   vertIconPx = panel thickness × vertIconScale
    //   vertTempPx = vertIconPx × 0.5 × vertTempScale
    readonly property int vertIconPx: Math.max(Math.round(Kirigami.Units.gridUnit / 2), Math.round((width - 2 * leftRightMargin) * vertIconScale))
    readonly property int vertTempPx: Math.max(Math.round(Kirigami.Units.gridUnit / 2), Math.round(vertIconPx * 0.5 * vertTempScale))

    // ── Multiline options ─────────────────────────────────────────────────
    readonly property string mlIconStyle: Plasmoid.configuration.panelMultilineIconStyle || "colorful"
    readonly property int multiLines: Math.max(1, Plasmoid.configuration.panelMultiLines || 2)
    readonly property bool multiAnimate: Plasmoid.configuration.panelMultiAnimate !== false
    readonly property int mlIconSize: Math.min(Math.max(multiLines * (panelFontPx + 8), 32) - 4, 64)

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
    Layout.fillHeight: !vertical || isMultiLine
    Layout.fillWidth: Plasmoid.configuration.panelFillWidth

    Layout.preferredWidth: Plasmoid.configuration.panelFillWidth ? -1 : isMultiLine ? mlIconSize + 6 + (Plasmoid.configuration.panelWidth || 110) + 2 * leftRightMargin : implicitWidth
    Layout.preferredHeight: {
        if (!vertical || isMultiLine)
            return -1;
        if (!isSimpleMode)
            return implicitHeight;
        // Slot height is driven by vertIconPx / vertTempPx so the allocated
        // height grows/shrinks with the scale factors.
        var iH = compactRoot.vertIconPx;
        var tH = compactRoot.vertTempPx;
        if (simpleLayoutType === 1)
            return iH + tH + 6;  // stacked: icon + gap + temp
        if (simpleLayoutType === 2)
            return iH + 4;        // compressed: square + badge
        return Math.max(iH, tH) + 4;                      // side-by-side: one row
    }
    // For simple mode on a horizontal panel the widget must be at least
    // as wide as it is tall so the click area covers the full content
    // (e.g. compressed square whose side = height - 2).
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
    }

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
            width: compactRoot.vertical ? (parent.width - 2 * compactRoot.leftRightMargin) : implicitWidth

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
            columnSpacing: compactRoot.simpleLayoutType === 0 ? (compactRoot.vertical ? 4 : 10) : 0
            rowSpacing: (compactRoot.vertical && compactRoot.simpleLayoutType === 1) ? Math.max(1, Math.min(4, Math.round(compactRoot.width * 0.08))) : 0

            // ── Icon cell ─────────────────────────────────────────────────
            Item {
                // Hide until the glyph has loaded to avoid mis-sized cells
                visible: iconGlyph.text.length > 0 || compactRoot.simpleIconStyle === "colorful"
                Layout.alignment: Qt.AlignCenter
                // clip prevents the glyph from visually bleeding into the temp cell
                // when the panel is very narrow and fontSizeMode hits minimumPixelSize
                clip: true

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
                    // Vertical: FixedSize + vertIconPx so scale actually works.
                    // HorizontalFit ignores font.pixelSize — it always shrinks to cell width.
                    // Horizontal: keep HorizontalFit/VerticalFit (autoFontSizeMode).
                    font.pixelSize: compactRoot.vertical ? compactRoot.vertIconPx : 999
                    font.pointSize: 0        // must clear pointSize when pixelSize is set
                    minimumPixelSize: Math.round(Kirigami.Units.gridUnit / 2)
                    fontSizeMode: compactRoot.vertical ? Text.FixedSize : simpleRoot.autoFontSizeMode
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
                clip: true

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
                    // Always 75 % of the icon's painted size so temp is visually
                    // smaller than the weather glyph regardless of panel orientation.
                    // fontSizeMode is FixedSize — the icon auto-fits and drives the
                    // reference size; temp just follows proportionally.
                    // Minimum is the KDE panel font size (panelFontPx reads from
                    // Kirigami.Theme.defaultFont or the user's custom font size).
                    // font.pixelSize is the UPPER CAP; autoFontSizeMode lets the
                    // text shrink below that cap when the cell is too narrow (e.g.
                    // vertical panel, type 0, each cell = half panel width).
                    // font.pixelSize = upper cap (40% of icon height, at least panelFontPx).
                    // minimumPixelSize must be a small absolute floor so HorizontalFit can
                    // actually shrink the temp text when the cell is narrow — e.g. vertical
                    // panel type 0 at 20px width gives each cell only ~10px.  Using
                    // panelFontPx (~14px) as the floor prevented shrinking and caused overlap.
                    // temperature relative to the icon.  The upper cap is still derived from
                    // iconGlyph.paintedHeight so the two elements stay proportional.
                    // Vertical: FixedSize + vertTempPx.
                    // Horizontal: auto-fit with upper cap from icon painted height.
                    font.pixelSize: compactRoot.vertical ? compactRoot.vertTempPx : Math.max(compactRoot.panelFontPx, Math.round(iconGlyph.paintedHeight * 0.5))
                    font.pointSize: 0
                    minimumPixelSize: Math.round(Kirigami.Units.gridUnit / 2)
                    fontSizeMode: compactRoot.vertical ? Text.FixedSize : simpleRoot.autoFontSizeMode
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
            readonly property int squareSide: compactRoot.vertical ? Math.max(16, compactRoot.vertIconPx) : Math.max(16, compactRoot.height - 2)
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
                        font.pixelSize: Math.max(8, Math.round(compressedWrapper.squareSide * 0.4))
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
