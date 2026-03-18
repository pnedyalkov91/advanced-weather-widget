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
import QtQuick.Window
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

    // ── Horizontal layout content filter ──────────────────────────────
    // Controls what is shown in simple mode horizontal layout (type 0):
    //   "both"      — icon + temperature (default)
    //   "icon_only" — weather icon only, temperature hidden
    //   "temp_only" — temperature only, icon hidden
    // Has no effect on vertical / compressed layouts.
    readonly property string simpleHorizContent: Plasmoid.configuration.panelSimpleHorizontalContent || "both"

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

    // ── True panel height (horizontal panels) ────────────────────────────
    // KDE panels apply internal top/bottom margins before allocating height
    // to widgets, so compactRoot.height < the declared panel thickness.
    // compactRoot.parent is the Plasma panel layout container whose height
    // is always the full declared thickness, initialises correctly, and
    // updates reactively when the panel is resized.
    // NOTE: Plasmoid.containment.height is NOT used — it starts at 0 and
    // is not tracked by QML bindings, so it would keep _fullPanelH wrong.
    // Window.height (QtQuick.Window attached property) = height of the
    // enclosing QQuickWindow = Plasma panel strip height (e.g. 48 px).
    // This is the reliable, reactive source for the true panel height.
    // parent.height = Loader height = post-margin widget height (~32 px) — wrong.
    // Plasmoid.containment.height starts at 0 and isn't tracked by QML — wrong.
    // True panel height for horizontal panels.
    // KDE panels always apply Kirigami.Units.largeSpacing (8 px) as top and
    // bottom padding, so the widget receives (panelHeight - 16 px).
    // Adding that padding back gives the declared panel thickness.
    // Window.height is used as an upper-bound sanity cap — it can be larger
    // than the panel on some Plasma setups (shell window vs panel window).
    readonly property int _fullPanelH: !vertical
        ? (Window.height > 0
            ? Math.min(Window.height, compactRoot.height + Kirigami.Units.largeSpacing * 2)
            : compactRoot.height + Kirigami.Units.largeSpacing * 2)
        : compactRoot.height

    // True panel width for vertical panels.
    // KDE subtracts largeSpacing (8 px) from ONE side of vertical-panel
    // widgets (the side away from the screen edge), so:
    //   compactRoot.width ≈ panelThickness - largeSpacing
    // Adding largeSpacing back recovers the declared panel thickness:
    //   e.g. compactRoot.width=40, largeSpacing=8 → _fullPanelW=48 ✓
    readonly property int _fullPanelW: vertical
        ? compactRoot.width + Kirigami.Units.largeSpacing
        : compactRoot.width

    // ── Symbolic-icon scale for simple mode ───────────────────────────────
    // ↓↓ EDIT THIS LINE to resize symbolic (wi-font) icons in simple mode ↓↓
    // Horizontal panels: 1.0 = icon fills full panel height (same as colorful)
    // Vertical panels use the same scale for consistency.
    // Values below 0.5 may look too small.
    readonly property real simpleSymbolicScale: compactRoot.vertical ? 1.00 : 1.00
    // Derived cell size for symbolic icons only — colorful always uses simpleIconSz.
    readonly property int simpleSymbolicIconSz: Math.max(12, Math.round(compactRoot.simpleIconSz * compactRoot.simpleSymbolicScale))

    // ── Simple-mode computed sizes ─────────────────────────────────────────
    // simpleIconSz: auto horizontal type0   = full panel height
    //               auto horizontal type1   = panel height / 2 (stacked)
    //               auto vertical   (all)   = panel width  (icon fills panel thickness)
    //               manual = user value (no cap — let KDE clip if needed).
    // simpleIconSz:
    //   vertical type 0 (side-by-side) → _fullPanelW / 2 = 24 px at 48 px panel
    //   vertical type 1 (stacked)      → _fullPanelW     = 48 px at 48 px panel
    //   horizontal type 0              → _fullPanelH     (48 px at 48 px panel)
    //   horizontal type 1              → _fullPanelH / 2
    readonly property int simpleIconSz: compactRoot.simpleIconAuto ? (compactRoot.vertical ? (compactRoot.simpleLayoutType === 0 ? Math.max(16, Math.round(compactRoot._fullPanelW / 2)) : Math.max(16, compactRoot._fullPanelW)) : (compactRoot.simpleLayoutType === 1 ? Math.max(16, Math.round(compactRoot._fullPanelH / 2)) : Math.max(16, compactRoot._fullPanelH))) : compactRoot.simpleIconPx

    // simpleFontSz auto sizing:
    //
    //   horizontal type 0  (side-by-side) → height / 2
    //     e.g. 64 px panel: icon = 64 px, font = 32 px
    //
    //   horizontal type 1  (stacked)      → height / 4   (icon = height/2, font = icon/2)
    //     e.g. 64 px panel: icon = 32 px, font = 16 px
    //
    //   horizontal type 2  (compressed)   → height / 2   (same as type 0)
    //
    //   vertical (auto)                   → panel width / 3
    //     e.g. 48 px panel: icon = 48 px, font = 16 px
    //
    // manual = user value.
    // simpleFontSz:
    //   horizontal type 0 → _fullPanelH * 11/24 ≈ 22 px at 48 px
    //   horizontal type 1 → _fullPanelH / 3     = 16 px at 48 px
    //   vertical (all)    → _fullPanelW / 3      = 16 px at 48 px
    readonly property int simpleFontSz: compactRoot.simpleFontAuto ? (!compactRoot.vertical ? (compactRoot.simpleLayoutType === 1 ? Math.max(8, Math.round(compactRoot._fullPanelH / 3)) : Math.max(8, Math.round(compactRoot._fullPanelH * 11 / 24))) : Math.max(8, Math.round(compactRoot._fullPanelW / 3))) : compactRoot.simpleFontPx

    // ── Write auto-computed sizes + panel geometry back to config ────────
    // simpleIconAutoSz / simpleFontAutoSz — live values for the applied
    //   layout type; used as fallback when panel dim is not yet stored.
    // simplePanelDim — raw panel thickness (_fullPanelW or _fullPanelH).
    //   The config page uses this to recompute auto sizes for whatever
    //   layout type is currently buffered in the dialog (before Apply).
    // simplePanelIsVertical — orientation flag, read by config page.
    readonly property int _simplePanelDim: compactRoot.vertical
        ? compactRoot._fullPanelW : compactRoot._fullPanelH
    on_SimplePanelDimChanged: {
        Plasmoid.configuration.simplePanelDim = compactRoot._simplePanelDim;
        Plasmoid.configuration.simplePanelIsVertical = compactRoot.vertical;
    }
    onSimpleIconSzChanged: {
        if (compactRoot.simpleIconAuto)
            Plasmoid.configuration.simpleIconAutoSz = compactRoot.simpleIconSz;
    }
    onSimpleFontSzChanged: {
        if (compactRoot.simpleFontAuto)
            Plasmoid.configuration.simpleFontAutoSz = compactRoot.simpleFontSz;
    }
    Component.onCompleted: {
        if (compactRoot.simpleIconAuto)
            Plasmoid.configuration.simpleIconAutoSz = compactRoot.simpleIconSz;
        if (compactRoot.simpleFontAuto)
            Plasmoid.configuration.simpleFontAutoSz = compactRoot.simpleFontSz;
        Plasmoid.configuration.simplePanelDim = compactRoot._simplePanelDim;
        Plasmoid.configuration.simplePanelIsVertical = compactRoot.vertical;
    }

    // ── Multiline options ─────────────────────────────────────────────────
    readonly property string mlIconStyle: Plasmoid.configuration.panelMultilineIconStyle || "colorful"
    readonly property int multiLines: Math.max(1, Plasmoid.configuration.panelMultiLines || 2)
    readonly property bool multiAnimate: Plasmoid.configuration.panelMultiAnimate !== false
    // 0 = auto-fit panel height; >0 = user-specified px (from settings spinner)
    readonly property int _mlIconSizeCfg: Plasmoid.configuration.panelMultilineIconSize || 0
    readonly property int mlIconSize: _mlIconSizeCfg > 0 ? _mlIconSizeCfg : Math.min(compactRoot._fullPanelH, 64)
    // Vertical multiline sizing (panel width drives icon; font drives rows)
    readonly property int mlVertIconSz: _mlIconSizeCfg > 0 ? _mlIconSizeCfg : Math.min(Math.max(16, width - 4), 64)
    // Row height must fit both text AND icons (wi-font glyph or SVG).
    readonly property int mlVertRowH: Math.max(14, panelFontPx + 6, glyphSize + 4, svgIconPx + 4)

    // ── Root implicit sizes ───────────────────────────────────────────────
    // Simple mode horizontal: width is driven by simpleGrid.implicitWidth so the
    // click area hugs icon + gap + temperature text with no dead space.
    // Compressed (type 2) uses a standalone Item — fall back to icon square + margins.
    implicitWidth: isMultiLine ? mlIconSize + 6 + 110 + 2 * leftRightMargin : isSimpleMode ? (vertical ? Kirigami.Units.gridUnit * 2 : (simpleLayoutType === 2 ?
            // compressed: just the icon square + margins
            Math.max(Kirigami.Units.gridUnit * 2, simpleIconSz + 2 * leftRightMargin) :
            // side-by-side / stacked: track actual GridLayout content width
            Math.max(Kirigami.Units.gridUnit * 2, simpleGrid.implicitWidth + 2 * leftRightMargin))) : compactRow.implicitWidth + 2 * leftRightMargin

    // vertical simple type 0 (side-by-side): content height = max(icon, font)+4;
    // no gridUnit floor so the widget stays compact and matches preferredHeight.
    // all other vertical simple types keep the gridUnit*2 floor.
    implicitHeight: isMultiLine ? Math.max(multiLines * (panelFontPx + 8), 32)
        : (isSimpleMode && vertical)
            ? (simpleLayoutType === 0
                ? Math.max(simpleIconSz, simpleFontSz) + 4
                : Math.max(Kirigami.Units.gridUnit * 2, simpleIconSz + 4))
        : Kirigami.Units.gridUnit * 2

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
        var iH = compactRoot.simpleIconSz;
        var tH = compactRoot.simpleFontSz;
        if (simpleLayoutType === 1)
            return iH + tH + 6;
        if (simpleLayoutType === 2) {
            var compressedIconSz = compactRoot.vertical
                ? (compactRoot.simpleIconAuto ? Math.max(16, compactRoot._fullPanelW) : Math.max(16, compactRoot.simpleIconPx))
                : iH;
            return compressedIconSz + 4;
        }
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
        // Expand to true panel height on horizontal so the icon cell is not
        // capped at the post-margin widget height. Mirrors simpleRoot pattern.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: (!compactRoot.vertical && compactRoot.isMultiLine)
            ? compactRoot._fullPanelH : parent.height

        // ── HORIZONTAL: icon left + scrolling rows right ──────────────────
        RowLayout {
            visible: !compactRoot.vertical
            anchors.fill: parent
            anchors.leftMargin: compactRoot.leftRightMargin
            anchors.rightMargin: compactRoot.leftRightMargin
            spacing: 6

            Item {
                // multiLineRoot is now expanded to _fullPanelH so no cap needed.
                // Icon fills true panel height in auto mode; manual value used as-is.
                readonly property int iconSz: _mlIconSizeCfg > 0
                    ? _mlIconSizeCfg
                    : compactRoot._fullPanelH
                Layout.preferredWidth: iconSz
                Layout.preferredHeight: iconSz
                Layout.alignment: Qt.AlignVCenter
                // Symbolic: KDE icon with -symbolic suffix (same as simple mode)
                Kirigami.Icon {
                    width: parent.iconSz
                    height: parent.iconSz
                    anchors.centerIn: parent
                    visible: compactRoot.mlIconStyle === "symbolic"
                    source: compactRoot.weatherRoot
                        ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode,
                            compactRoot.weatherRoot.isNightTime(), true)
                        : "weather-none-available-symbolic"
                    smooth: true
                }
                // Colorful
                Kirigami.Icon {
                    width: parent.iconSz
                    height: parent.iconSz
                    anchors.centerIn: parent
                    visible: compactRoot.mlIconStyle !== "symbolic"
                    source: compactRoot.weatherRoot
                        ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode,
                            compactRoot.weatherRoot.isNightTime())
                        : "weather-none-available"
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
                    // Use _fullPanelH so each row fills the true panel height / N lines
                    readonly property real rowH: compactRoot._fullPanelH > 0 ? Math.max(12, compactRoot._fullPanelH / compactRoot.multiLines) : Math.max(12, compactRoot.panelFontPx + 8)
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
                Kirigami.Icon {
                    width: parent.width
                    height: parent.height
                    anchors.centerIn: parent
                    visible: compactRoot.mlIconStyle === "symbolic"
                    source: compactRoot.weatherRoot
                        ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode,
                            compactRoot.weatherRoot.isNightTime(), true)
                        : "weather-none-available-symbolic"
                    smooth: true
                }
                Kirigami.Icon {
                    width: parent.width
                    height: parent.height
                    anchors.centerIn: parent
                    visible: compactRoot.mlIconStyle !== "symbolic"
                    source: compactRoot.weatherRoot
                        ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode,
                            compactRoot.weatherRoot.isNightTime())
                        : "weather-none-available"
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
        // Use _fullPanelH so the grid is not clipped when the icon/font is
        // larger than the post-margin widget height (compactRoot.height).
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: (!compactRoot.vertical && compactRoot.isSimpleMode) ? compactRoot._fullPanelH : parent.height
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
            // Vertical: fill panel thickness so the temp column gets real width.
            // Horizontal: content-sized so anchors.centerIn can centre the block.
            width: compactRoot.vertical ? compactRoot._fullPanelW : implicitWidth

            // Vertical panels and horizontal stacked (type 1): collapse the grid to
            // exactly its content height so anchors.centerIn centres the icon+temp
            // pair cleanly.
            //
            // Horizontal type 0 (side-by-side): fill the full parent height so the
            // icon row gets the maximum available space without any shrinkage.
            // Always use implicitHeight: the grid is exactly its content size,
            // and anchors.centerIn centres the block both horizontally and
            // vertically in the panel — critical for symbolic icons which are
            // smaller than the panel height and would appear top-aligned otherwise.
            // Horizontal type 0: use full panel height so the icon cell
            // (which may be larger than the post-margin widget height) fits.
            // All other cases collapse to content height for clean centering.
            height: (!compactRoot.vertical && compactRoot.simpleLayoutType === 0) ? compactRoot._fullPanelH : implicitHeight

            // type 1 → 2 rows × 1 col; type 0 → 1 row × 2 cols
            rows: compactRoot.simpleLayoutType === 1 ? 2 : 1
            columns: compactRoot.simpleLayoutType === 1 ? 1 : 2

            // uniformCellHeights disabled: with different icon/font sizes (e.g. 24 and
            // 16 px) forcing equal rows inflates the grid beyond the panel height.
            // Each row uses its natural cell height; rowSpacing provides the gap.
            uniformCellHeights: false

            // columnSpacing: always 4 px between icon and temp for vertical type 0 so
            //   there is a visible gap at every panel size.
            // rowSpacing: for vertical + stacked scale with panel width so the gap
            //   shrinks proportionally as the panel gets narrower, never causes overlap.
            // ← EDIT: change the numbers below to adjust spacing between icon and temperature
            //   columnSpacing controls horizontal-type (type 0) on vertical panels
            //   rowSpacing    controls vertical-type   (type 1) on vertical panels
            // Horizontal type 0 spacing between icon and temperature:
            //   colorful icons fill their cell edge-to-edge → 6 px looks tight but right
            //   symbolic (wi-font) glyphs have internal padding → need more gap
            // ↓↓ EDIT the two numbers below to tune spacing for each icon style ↓↓
            //      first number  = colorful icon gap (px)
            //      second number = symbolic icon gap (px)
            // vertical type 0: no gap — icon and temperature sit flush side-by-side
            columnSpacing: compactRoot.simpleLayoutType === 0 ? (compactRoot.vertical ? 0 : (compactRoot.simpleIconStyle === "colorful" ? 6 : 8)) : 0

            // ↓↓ EDIT the two numbers below to adjust the gap between icon and temperature
            //    in stacked (type 1) simple mode layout:
            //      first number  = vertical panels gap (px)
            //      second number = horizontal panels gap (px)
            rowSpacing: compactRoot.simpleLayoutType === 1 ? (compactRoot.vertical ? 0 : 8) : 0

            // ── Icon cell ─────────────────────────────────────────────────
            Item {
                // Hide until the glyph has loaded to avoid mis-sized cells
                // In horizontal layout (type 0), hide when content filter is "temp_only"
                visible: compactRoot.simpleLayoutType !== 0 || compactRoot.simpleHorizContent !== "temp_only"
                Layout.alignment: Qt.AlignCenter
                // No clip needed: HorizontalFit never overflows its cell.

                // Cell sizing:
                //   colorful → always simpleIconSz (icon fills the cell completely)
                //   symbolic → simpleSymbolicIconSz (scaled-down cell; scale set by
                //              simpleSymbolicScale property above)
                //
                // vertical auto  → fill available width up to the computed icon size
                // vertical manual / horizontal → fixed square
                // Base icon cell size from icon style and computed/manual size.
                readonly property int _baseCellSz: compactRoot.simpleIconStyle === "colorful" ? compactRoot.simpleIconSz : compactRoot.simpleSymbolicIconSz
                // On horizontal panels cap at panel height so the GridLayout row never
                // expands beyond simpleGrid.height (prevents icon overflowing downward
                // and temperature cell shifting).
                // _cellSz is always derived from panel dimensions so fillWidth is never
                // needed — pinning explicitly avoids Qt distributing columns unevenly
                // when both cells have fillWidth:true (causes the "go right" bug with
                // colorful icons on vertical panels in auto mode).
                // vertical type 0 auto: cap to half panel width (24px at 48px panel)
                //   so icon and temp share the panel width equally.
                // vertical type 0 manual: no cap — honour the user's chosen size.
                // vertical type 1/2: cap to full panel width.
                readonly property int _cellSz: compactRoot.vertical
                    ? (compactRoot.simpleLayoutType === 0
                        ? (compactRoot.simpleIconAuto
                            ? Math.min(_baseCellSz, Math.round(compactRoot._fullPanelW / 2))
                            : _baseCellSz)
                        : Math.min(_baseCellSz, compactRoot._fullPanelW))
                    : Math.min(_baseCellSz, compactRoot._fullPanelH)
                // Pin the cell to exactly _cellSz on both axes.
                // The grid is sized to implicitWidth so anchors.centerIn centres
                // the content block — no fillWidth needed on the icon cell.
                Layout.fillWidth: false
                Layout.fillHeight: false
                Layout.preferredWidth: _cellSz
                Layout.minimumWidth: _cellSz
                Layout.maximumWidth: _cellSz
                // vertical type 0 auto: pin cell height to simpleFontSz so the row
                //   is compact (no gap when font is small; icon renders larger than
                //   the cell height but is clipped cleanly — same as panel behaviour).
                // vertical type 0 manual: use _cellSz so a large icon isn't clipped.
                // All other cases: square cell (height = _cellSz).
                readonly property int _cellH: (compactRoot.vertical && compactRoot.simpleLayoutType === 0)
                    ? (compactRoot.simpleIconAuto ? compactRoot.simpleFontSz : _cellSz)
                    : _cellSz
                Layout.preferredHeight: _cellH
                Layout.minimumHeight: _cellH
                Layout.maximumHeight: _cellH

                // Widget order: 0 = icon first, 1 = temp first
                Layout.row: compactRoot.simpleLayoutType === 1 ? (compactRoot.simpleWidgetOrder === 0 ? 0 : 1) : 0
                Layout.column: compactRoot.simpleLayoutType === 1 ? 0 : (compactRoot.simpleWidgetOrder === 0 ? 0 : 1)

                // Symbolic icon: append "-symbolic" to the KDE icon name so the
                // icon engine serves the monochrome symbolic variant rather than
                // the colourful one. This is the standard Plasma convention —
                // the KDE weather widget changelog states:
                // "Ask for -symbolic versions everywhere we want monochrome icons."
                Kirigami.Icon {
                    id: iconGlyph
                    width: compactRoot.simpleSymbolicIconSz
                    height: compactRoot.simpleSymbolicIconSz
                    anchors.centerIn: parent
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    source: compactRoot.weatherRoot ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode, compactRoot.weatherRoot.isNightTime(), true) : "weather-none-available-symbolic"
                    smooth: true
                }
                // Colorful icon: explicit size + centerIn, same as symbolic.
                // anchors.fill was constrained to the post-margin cell (~32 px on a
                // 48 px panel); explicit size uses _cellSz = Window.height correctly.
                Kirigami.Icon {
                    width: parent._cellSz
                    height: parent._cellSz
                    anchors.centerIn: parent
                    visible: compactRoot.simpleIconStyle === "colorful"
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    smooth: true
                }
            }

            // ── Temperature cell ──────────────────────────────────────────
            Item {
                // In horizontal layout (type 0), hide when content filter is "icon_only"
                visible: tempText.text.length > 0 && (compactRoot.simpleLayoutType !== 0 || compactRoot.simpleHorizContent !== "icon_only")
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compactRoot.vertical
                // Pin height to simpleFontSz on all layouts.
                // The icon cell is also pinned to simpleFontSz for vertical type 0,
                // so row height = simpleFontSz — compact with no gaps.
                Layout.minimumWidth: compactRoot.vertical ? 0 : tempText.paintedWidth
                Layout.maximumWidth: compactRoot.vertical ? Infinity : tempText.paintedWidth
                Layout.preferredHeight: compactRoot.simpleFontSz
                Layout.minimumHeight: compactRoot.simpleFontSz
                Layout.maximumHeight: compactRoot.simpleFontSz

                Layout.row: compactRoot.simpleLayoutType === 1 ? (compactRoot.simpleWidgetOrder === 0 ? 1 : 0) : 0
                Layout.column: compactRoot.simpleLayoutType === 1 ? 0 : (compactRoot.simpleWidgetOrder === 0 ? 1 : 0)

                Text {
                    id: tempText
                    anchors.fill: parent
                    text: compactRoot.weatherRoot ? compactRoot.weatherRoot.tempValue(compactRoot.weatherRoot.temperatureC) : "--"
                    font.family: Kirigami.Theme.defaultFont.family
                    font.pixelSize: compactRoot.simpleFontSz
                    fontSizeMode: Text.FixedSize
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
            // Expand to _fullPanelH on horizontal so the square is not capped
            // at the post-margin widget height — same fix as simpleRoot.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: (!compactRoot.vertical && compactRoot.isSimpleMode)
                ? compactRoot._fullPanelH : parent.height
            visible: compactRoot.simpleLayoutType === 2

            // Orientation-aware square sizing using _fullPanelH (true panel height).
            // Auto: icon = full panel height (48 px on a 48 px panel).
            // Manual: use icon size setting.
            readonly property int squareSide: compactRoot.simpleIconAuto
                ? (compactRoot.vertical
                    ? Math.max(16, compactRoot._fullPanelW)
                    : Math.max(16, compactRoot._fullPanelH))
                : Math.max(16, compactRoot.simpleIconPx)
            Item {
                id: compressedSquare
                width: compressedWrapper.squareSide
                height: compressedWrapper.squareSide
                anchors.centerIn: parent

                // Symbolic icon — KDE theme icon with -symbolic suffix
                Kirigami.Icon {
                    id: compressedIconGlyph
                    width: parent.width
                    height: parent.height
                    anchors.centerIn: parent
                    visible: compactRoot.simpleIconStyle !== "colorful"
                    source: compactRoot.weatherRoot
                        ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode,
                            compactRoot.weatherRoot.isNightTime(), true)
                        : "weather-none-available-symbolic"
                    smooth: true
                }
                // Colorful icon
                Kirigami.Icon {
                    width: parent.width
                    height: parent.height
                    anchors.centerIn: parent
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
                        // Auto: squareSide / 3 ≈ 16 px when squareSide = 48 px
                        font.pixelSize: compactRoot.simpleFontAuto ? Math.max(8, Math.round(compressedWrapper.squareSide / 3)) : Math.max(8, compactRoot.simpleFontPx)
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
