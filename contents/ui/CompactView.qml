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
 * CompactView.qml - Panel / compact representation
 *
 * Renders the panel bar: wi-font icon + value chips separated by a bullet.
 * Also hosts the custom tooltip popup (TooltipContent).
 *
 * Display modes (Plasmoid.configuration.panelInfoMode):
 *   "single"    - all items in one row
 *   "multiline" - large weather icon left + scrolling item rows right
 *   "simple"    - icon + temperature only
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
 *
 * Simple mode sizing:
 *   • auto   → icon/font use geometry allocated by Plasma
 *   • large  → icon/font use reconstructed full panel thickness
 *   • manual → icon/font use configured pixel sizes
 *   • icon and font size modes are independent
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

import "js/weather.js" as W
import "js/iconResolver.js" as IconResolver
import "js/tempColors.js" as TempColorsJS
import "js/configUtils.js" as ConfigUtils
import "components"

PlasmaCore.ToolTipArea {
    id: compactRoot
    active: Plasmoid.configuration.tooltipEnabled !== false

    // ── Public interface - bound from main.qml ────────────────────────────
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
    // Bundled SVG icon themes shipped under contents/icons/. They render like the
    // colorful style (full cell, no color mask), only the artwork differs.
    readonly property bool simpleIconIsBundled: compactRoot.simpleIconStyle === "symbolic-bundled"
        || compactRoot.simpleIconStyle === "flat-color"
        || compactRoot.simpleIconStyle === "3d-oxygen"
        || compactRoot.simpleIconStyle === "meteocons"
    readonly property string simpleClickAreaMode: Plasmoid.configuration.panelSimpleClickAreaMode || "auto"
    readonly property int simpleClickAreaSize: Math.max(20, Plasmoid.configuration.panelSimpleClickAreaSize || 96)
    readonly property bool simpleTempShadowEnabled: Plasmoid.configuration.panelSimpleTempShadowEnabled === true
    readonly property real simpleTempShadowIntensity: Math.max(0.1, Math.min(1.0, Plasmoid.configuration.panelSimpleTempShadowIntensity !== undefined ? Plasmoid.configuration.panelSimpleTempShadowIntensity : 0.8))
    readonly property color simpleTempShadowColor: {
        var c = Plasmoid.configuration.panelSimpleTempShadowColor;
        return (c && c.length > 0) ? c : Kirigami.Theme.backgroundColor;
    }
    // Follows the same cold-to-hot scale as the forecast curve when enabled,
    // so the panel reading and the curve below it speak the same language.
    readonly property bool simpleTempColorDynamic: Plasmoid.configuration.simpleTempColorDynamic === true
    readonly property color simpleTempColor: {
        if (compactRoot.simpleTempColorDynamic && weatherRoot && weatherRoot.temperatureC !== undefined && weatherRoot.temperatureC !== null)
            return TempColorsJS.colorForTemperature(weatherRoot.temperatureC, TempColorsJS.isDarkBackground(Kirigami.Theme.backgroundColor));
        var c = Plasmoid.configuration.simpleTempColor;
        return (c && c.length > 0) ? c : Kirigami.Theme.textColor;
    }

    // ── Horizontal layout content filter ──────────────────────────────
    // Controls what is shown in simple mode horizontal layout (type 0):
    //   "both"      - icon + temperature (default)
    //   "icon_only" - weather icon only, temperature hidden
    //   "temp_only" - temperature only, icon hidden
    // Has no effect on vertical / compressed layouts.
    readonly property string simpleHorizContent: Plasmoid.configuration.panelSimpleHorizontalContent || "both"

    // Whether a location has been configured
    readonly property bool _hasLocation: weatherRoot && weatherRoot.hasSelectedTown

    // ── Vertical-panel size scale factors ────────────────────────────────
    // Change these two values to resize icon and temperature in vertical panels.
    // 1.0 = natural size (auto-fits panel thickness).  > 1.0 = larger, < 1.0 = smaller.
    // ── Simple-mode sizing (reads from Plasmoid.configuration) ──────────────
    // Icon size: auto = based on geometry allocated by Plasma
    //            large = based on reconstructed full panel thickness
    //            manual = fixed pixel size set in settings (Icon Size spinner)
    // Font size: auto = based on geometry allocated by Plasma
    //            large = based on reconstructed full panel thickness
    //            manual = fixed pixel size set in settings (Font Size spinner)
    // Icon and font size modes are independent.
    readonly property string simpleIconSizeMode: Plasmoid.configuration.simpleIconSizeMode || "auto"
    readonly property bool simpleIconLarge: compactRoot.simpleIconSizeMode === "large"
    readonly property bool simpleIconManual: compactRoot.simpleIconSizeMode === "manual"
    readonly property bool simpleIconAuto: !compactRoot.simpleIconLarge && !compactRoot.simpleIconManual
    readonly property bool simpleIconUsesPanelSize: compactRoot.simpleIconAuto || compactRoot.simpleIconLarge
    readonly property int simpleIconPx: Plasmoid.configuration.simpleIconSizeManual || 32
    readonly property string simpleFontSizeMode: Plasmoid.configuration.simpleFontSizeMode || "auto"
    readonly property bool simpleFontLarge: compactRoot.simpleFontSizeMode === "large"
    readonly property bool simpleFontManual: compactRoot.simpleFontSizeMode === "manual"
    readonly property bool simpleFontAuto: !compactRoot.simpleFontLarge && !compactRoot.simpleFontManual
    readonly property bool simpleFontUsesPanelSize: compactRoot.simpleFontAuto || compactRoot.simpleFontLarge
    readonly property int simpleFontPx: Plasmoid.configuration.simpleFontSizeManual || 14

    // ── Plasma-allocated compact geometry ────────────────────────────────
    // Plasma applies the panel-theme margins before assigning this geometry.
    // Auto icon and font sizing use the available dimensions directly.
    readonly property int _allocatedPanelH: compactRoot.height
    readonly property int _allocatedPanelW: compactRoot.width

    // ── True panel height (horizontal panels) ────────────────────────────
    // KDE panels apply internal top/bottom margins before allocating height
    // to widgets, so compactRoot.height < the declared panel thickness.
    // compactRoot.parent is the Plasma panel layout container whose height
    // is always the full declared thickness, initialises correctly, and
    // updates reactively when the panel is resized.
    // NOTE: Plasmoid.containment.height is NOT used - it starts at 0 and
    // is not tracked by QML bindings, so it would keep _fullPanelH wrong.
    // Window.height (QtQuick.Window attached property) = height of the
    // enclosing QQuickWindow = Plasma panel strip height (e.g. 48 px).
    // This is the reliable, reactive source for the true panel height.
    // parent.height = Loader height = post-margin widget height (~32 px) - wrong.
    // Plasmoid.containment.height starts at 0 and isn't tracked by QML - wrong.
    // True panel height for horizontal panels.
    // KDE panels always apply Kirigami.Units.largeSpacing (8 px) as top and
    // bottom padding, so the widget receives (panelHeight - 16 px).
    // Adding that padding back gives the declared panel thickness.
    // Window.height is used as an upper-bound sanity cap - it can be larger
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

    // ── Panel dimension selected by each size mode ───────────────────────
    // auto   → geometry allocated by Plasma
    // large  → reconstructed full panel thickness
    // manual → configured pixel size; panel dimensions are not used for size
    // Icon and font select their panel dimensions independently.
    readonly property int _simpleIconPanelH: compactRoot.simpleIconLarge
        ? compactRoot._fullPanelH : compactRoot._allocatedPanelH
    readonly property int _simpleIconPanelW: compactRoot.simpleIconLarge
        ? compactRoot._fullPanelW : compactRoot._allocatedPanelW
    readonly property int _simpleFontPanelH: compactRoot.simpleFontLarge
        ? compactRoot._fullPanelH : compactRoot._allocatedPanelH
    readonly property int _simpleFontPanelW: compactRoot.simpleFontLarge
        ? compactRoot._fullPanelW : compactRoot._allocatedPanelW
    readonly property bool _simpleShowsIcon: compactRoot.simpleLayoutType !== 0
        || compactRoot.simpleHorizContent !== "temp_only"
    readonly property bool _simpleShowsFont: compactRoot.simpleLayoutType !== 0
        || compactRoot.simpleHorizContent !== "icon_only"
    // Layout extent:
    //   base                    → geometry allocated by Plasma
    //   visible large-mode item → reconstructed full panel dimension
    //   manual pixel size       → does not expand the panel-derived extent
    readonly property int _simpleContentPanelH: Math.max(
        compactRoot._allocatedPanelH,
        compactRoot._simpleShowsIcon ? compactRoot._simpleIconPanelH : 0,
        compactRoot._simpleShowsFont ? compactRoot._simpleFontPanelH : 0)
    readonly property int _simpleContentPanelW: Math.max(
        compactRoot._allocatedPanelW,
        compactRoot._simpleShowsIcon ? compactRoot._simpleIconPanelW : 0,
        compactRoot._simpleShowsFont ? compactRoot._simpleFontPanelW : 0)

    // ── Symbolic-icon scale for simple mode ───────────────────────────────
    // ↓↓ EDIT THIS LINE to resize symbolic (wi-font) icons in simple mode ↓↓
    // Horizontal panels: 1.0 = icon uses the same base size as colorful icons.
    // Vertical panels use the same scale for consistency.
    // Values below 0.5 may look too small.
    readonly property real simpleSymbolicScale: compactRoot.vertical ? 1.00 : 1.00
    // Derived cell size for symbolic icons only - colorful always uses simpleIconSz.
    readonly property int simpleSymbolicIconSz: Math.max(12, Math.round(compactRoot.simpleIconSz * compactRoot.simpleSymbolicScale))

    // ── Simple-mode computed sizes ─────────────────────────────────────────
    // simpleIconSz: auto   = formulas below use allocated panel geometry
    //               large  = the same formulas use full panel thickness
    //               manual = user value (no cap - let KDE clip if needed).
    // _simpleIconPanelW/H selects allocated geometry for auto and full panel
    // thickness for large.
    // simpleIconSz:
    //   vertical type 0 (side-by-side) → _simpleIconPanelW / 2
    //     e.g. 48 px selected dimension: icon = 24 px
    //   vertical type 1/2              → _simpleIconPanelW
    //     e.g. 48 px selected dimension: icon = 48 px
    //   horizontal type 0/2            → _simpleIconPanelH
    //     e.g. 48 px selected dimension: icon = 48 px
    //   horizontal type 1 (stacked)    → _simpleIconPanelH / 2
    //     e.g. 48 px selected dimension: icon = 24 px
    // Divided values are rounded; all panel-derived values are at least 16 px.
    readonly property int simpleIconSz: compactRoot.simpleIconUsesPanelSize ? (compactRoot.vertical ? (compactRoot.simpleLayoutType === 0 ? Math.max(16, Math.round(compactRoot._simpleIconPanelW / 2)) : Math.max(16, compactRoot._simpleIconPanelW)) : (compactRoot.simpleLayoutType === 1 ? Math.max(16, Math.round(compactRoot._simpleIconPanelH / 2)) : Math.max(16, compactRoot._simpleIconPanelH))) : compactRoot.simpleIconPx

    // simpleFontSz auto/large sizing:
    // _simpleFontPanelW/H selects allocated geometry for auto and full panel
    // thickness for large.
    //
    //   horizontal type 0 (side-by-side) → height * 11/24
    //     e.g. 48 px selected dimension: font = 22 px
    //
    //   horizontal type 1 (stacked)      → height / 3
    //     e.g. 48 px selected dimension: font = 16 px
    //
    //   horizontal type 2 (compressed)   → height / 3
    //     e.g. 48 px selected dimension: font = 16 px
    //
    //   vertical (all)                   → panel width / 3
    //     e.g. 48 px selected dimension: font = 16 px
    //
    // Values are rounded; all panel-derived values are at least 8 px.
    // manual = user value.
    // simpleFontSz:
    //   horizontal type 0   → _simpleFontPanelH * 11/24
    //   horizontal type 1/2 → _simpleFontPanelH / 3
    //   vertical (all)      → _simpleFontPanelW / 3
    readonly property int simpleFontSz: compactRoot.simpleFontUsesPanelSize ? (!compactRoot.vertical ? (compactRoot.simpleLayoutType === 1 || compactRoot.simpleLayoutType === 2 ? Math.max(8, Math.round(compactRoot._simpleFontPanelH / 3)) : Math.max(8, Math.round(compactRoot._simpleFontPanelH * 11 / 24))) : Math.max(8, Math.round(compactRoot._simpleFontPanelW / 3))) : compactRoot.simpleFontPx

    // ── Write auto/large-computed sizes + panel geometry back to config ──
    // simpleIconAutoSz / simpleFontAutoSz - live values for the applied
    //   auto/large mode and layout type; used as fallback when panel dim
    //   is not yet stored.
    // simplePanelDim - geometry allocated to the compact representation.
    // simplePanelLargeDim - reconstructed full panel thickness.
    //   The config page uses both to recompute sizes for whatever
    //   layout type is currently buffered in the dialog (before Apply).
    // simplePanelIsVertical - orientation flag, read by config page.
    readonly property int _simplePanelDim: compactRoot.vertical
        ? compactRoot._allocatedPanelW : compactRoot._allocatedPanelH
    readonly property int _simplePanelLargeDim: compactRoot.vertical
        ? compactRoot._fullPanelW : compactRoot._fullPanelH
    on_SimplePanelDimChanged: {
        Plasmoid.configuration.simplePanelDim = compactRoot._simplePanelDim;
        Plasmoid.configuration.simplePanelIsVertical = compactRoot.vertical;
    }
    on_SimplePanelLargeDimChanged: {
        Plasmoid.configuration.simplePanelLargeDim = compactRoot._simplePanelLargeDim;
    }
    onVerticalChanged: {
        Plasmoid.configuration.simplePanelIsVertical = compactRoot.vertical;
    }
    onSimpleIconSzChanged: {
        if (compactRoot.simpleIconUsesPanelSize)
            Plasmoid.configuration.simpleIconAutoSz = compactRoot.simpleIconSz;
    }
    onSimpleFontSzChanged: {
        if (compactRoot.simpleFontUsesPanelSize)
            Plasmoid.configuration.simpleFontAutoSz = compactRoot.simpleFontSz;
    }
    Component.onCompleted: {
        if (compactRoot.simpleIconUsesPanelSize)
            Plasmoid.configuration.simpleIconAutoSz = compactRoot.simpleIconSz;
        if (compactRoot.simpleFontUsesPanelSize)
            Plasmoid.configuration.simpleFontAutoSz = compactRoot.simpleFontSz;
        Plasmoid.configuration.simplePanelDim = compactRoot._simplePanelDim;
        Plasmoid.configuration.simplePanelLargeDim = compactRoot._simplePanelLargeDim;
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
    // Compressed (type 2) uses a standalone Item - fall back to icon square + margins.
    // When no location is set, use the no-location prompt width.
    implicitWidth: !_hasLocation ? noLocationRow.implicitWidth + 2 * leftRightMargin
        : isMultiLine ? mlIconSize + 6 + 110 + 2 * leftRightMargin : isSimpleMode ? (vertical ? Kirigami.Units.gridUnit * 2 : (simpleLayoutType === 2 ?
            // compressed: just the icon square + margins
            Math.max(Kirigami.Units.gridUnit * 2, simpleIconSz + 2 * leftRightMargin) :
            // side-by-side / stacked: track actual GridLayout content width
            Math.max(Kirigami.Units.gridUnit * 2, simpleGrid.implicitWidth + 2 * leftRightMargin))) : Math.ceil(compactRow.implicitWidth) + 2 * leftRightMargin + compactRow._widthSafetyPx

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
    // vertical: fillHeight when "Fill panel" is on - works for all display modes
    // Fill-panel just toggles Layout.fillWidth/fillHeight so the widget CAN
    // grow into slack space; Layout.preferredWidth/Height still report the
    // real content size as a floor (see notes below) so the widget never
    // collapses when a competing flexible panel item is also present.
    readonly property bool vertFill: vertical && !isSimpleMode && !isMultiLine && Plasmoid.configuration.panelFillWidth

    Layout.fillHeight: !vertical || compactRoot.vertFill || (compactRoot.isSimpleMode && compactRoot.vertical && compactRoot.simpleClickAreaMode === "fill")
    Layout.fillWidth: vertical || Plasmoid.configuration.panelFillWidth || (compactRoot.isSimpleMode && !compactRoot.vertical && compactRoot.simpleClickAreaMode === "fill")

    Layout.preferredWidth: (compactRoot.isSimpleMode && !compactRoot.vertical)
        ? (compactRoot.simpleClickAreaMode === "fill" ? -1 : (compactRoot.simpleClickAreaMode === "manual" ? compactRoot.simpleClickAreaSize : implicitWidth))
        // NOTE: panelFillWidth intentionally does NOT map to -1 here. A -1
        // preferredWidth gives Plasma's panel layout no baseline to anchor
        // on, so when another flexible item (e.g. a user-added Panel
        // Spacer) is also competing for space, Plasma can end up granting
        // this widget almost nothing (collapsing toward Layout.minimumWidth)
        // and handing the spacer everything instead - the widget's content
        // effectively disappears. Using implicitWidth as the baseline keeps
        // the full weather info as a floor; Layout.fillWidth (still driven
        // by panelFillWidth below) is what lets it additionally grow into
        // any real slack space.
        : vertical ? -1 : isMultiLine ? mlIconSize + 6 + (Plasmoid.configuration.panelWidth || 110) + 2 * leftRightMargin : implicitWidth
    Layout.preferredHeight: {
        if (compactRoot.isSimpleMode && compactRoot.vertical) {
            if (compactRoot.simpleClickAreaMode === "fill")
                return -1;
            if (compactRoot.simpleClickAreaMode === "manual")
                return compactRoot.simpleClickAreaSize;
        }
        // NOTE: vertFill intentionally does NOT return -1 here anymore - see
        // the matching note on Layout.preferredWidth above. Falling through
        // to the content-based height below gives Plasma a real baseline;
        // Layout.fillHeight (still driven by vertFill) handles growing into
        // any actual slack space.
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
                ? (compactRoot.simpleIconUsesPanelSize ? Math.max(16, compactRoot._simpleIconPanelW) : Math.max(16, compactRoot.simpleIconPx))
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
    readonly property string _cvTemp: weatherRoot ? weatherRoot.tempValue(weatherRoot.temperatureC, "panel") : "--"

    // ── Datetime tick (updates every second to keep the datetime item live) ──
    property int _dateTimeTick: 0
    Timer {
        id: dateTimeTimer
        interval: 1000
        running: (Plasmoid.configuration.panelItemOrder || "").indexOf("datetime") >= 0
            || (Plasmoid.configuration.tooltipItemOrder || "").indexOf("datetime") >= 0
        repeat: true
        onTriggered: compactRoot._dateTimeTick++
    }

    // ── Reactive panel items data ─────────────────────────────────────────
    property var panelItemsData: {
        if (!weatherRoot)
            return [];
        // Subscribe to weatherData object (fires once per refresh) plus scalar deps
        // Use safe fallback strings instead of .length to prevent TypeErrors breaking the binding.
        var _deps = (weatherRoot.weatherData || "") + weatherRoot.panelScrollIndex
            + (weatherRoot.sunriseTimeText || "") + (weatherRoot.sunsetTimeText || "")
            + (weatherRoot.moonriseTimeText || "") + (weatherRoot.moonsetTimeText || "")
            + Plasmoid.configuration.panelItemOrder + Plasmoid.configuration.panelItemIcons
            + Plasmoid.configuration.panelInfoMode + Plasmoid.configuration.panelSeparator
            + Plasmoid.configuration.panelSunTimesMode + Plasmoid.configuration.panelMoonPhaseMode
            + compactRoot.iconTheme + Plasmoid.configuration.panelIconSize
            + compactRoot._dateTimeTick;
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
            var totalItems = compactRoot.multiLineItemsData.length;
            var visibleLines = compactRoot.multiLines;
            if (totalItems <= visibleLines) {
                compactRoot.mlScrollOffset = 0;
            } else {
                var maxOffset = totalItems - visibleLines;
                compactRoot.mlScrollOffset = (compactRoot.mlScrollOffset + 1);
                if (compactRoot.mlScrollOffset > maxOffset) {
                    compactRoot.mlScrollOffset = 0;
                }
            }
        }
    }
    onIsMultiLineChanged: mlScrollOffset = 0
    onMultiLineItemsDataChanged: if (mlScrollOffset >= multiLineItemsData.length) mlScrollOffset = 0

    mainItem: TooltipContent {
        weatherRoot: compactRoot.weatherRoot
        _dateTimeTick: compactRoot._dateTimeTick
    }

    // ══════════════════════════════════════════════════════════════════════
    // SINGLE / SCROLL MODE
    // ══════════════════════════════════════════════════════════════════════
    // ══════════════════════════════════════════════════════════════════════
    // SINGLE LINE MODE - orientation aware
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

            // Cheap insurance against Text implicitWidth under-measuring the
            // actually-painted text (e.g. the air-quality chip embeds a
            // color emoji glyph, and font-fallback shaping used at paint
            // time can end up a few px wider than the implicitWidth the
            // layout was sized from). Without this, the shortfall gets
            // hard-clipped off the last item by this RowLayout's clip:true.
            readonly property int _widthSafetyPx: 12

            Repeater {
                model: compactRoot.panelItemsData
                delegate: RowLayout {
                    id: slRowItem
                    required property var modelData
                    spacing: 5

                    WeatherIcon {
                        visible: slRowItem.modelData.iconVis
                        iconInfo: slRowItem.modelData.iconInfo
                        iconSize: (slRowItem.modelData.iconInfo.type || "") === "wi" ? compactRoot.glyphSize : compactRoot.svgIconPx
                        wiFontFamily: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                        wiFontReady: wiFontPanel.status === FontLoader.Ready
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Label {
                        text: slRowItem.modelData.text
                        font: compactRoot.weatherRoot ? compactRoot.weatherRoot.wpf(compactRoot.panelFontPx, false) : Qt.font({
                            pixelSize: compactRoot.panelFontPx
                        })
                        color: Kirigami.Theme.textColor
                        verticalAlignment: Text.AlignVCenter
                        Layout.alignment: Qt.AlignVCenter
                        // Intentionally NOT elide/Layout.fillWidth: those mark this
                        // Label as "flexible", letting the RowLayout squeeze it below
                        // its implicit (full-text) width whenever the panel is slow to
                        // grant the widget its updated preferredWidth (e.g. next to an
                        // expanding spacer). Without fillWidth, this Label always sizes
                        // to its own implicitWidth, which is exactly what already drives
                        // compactRow.implicitWidth → compactRoot.implicitWidth →
                        // Layout.preferredWidth, so Plasma is asked for the full width
                        // localized text needs instead of whatever it happened to grant
                        // on an earlier layout pass.
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

                        WeatherIcon {
                            visible: slVertItem.modelData.iconVis
                            iconInfo: slVertItem.modelData.iconInfo
                            iconSize: (slVertItem.modelData.iconInfo.type || "") === "wi" ? compactRoot.glyphSize : compactRoot.svgIconPx
                            wiFontFamily: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                            wiFontReady: wiFontPanel.status === FontLoader.Ready
                            Layout.alignment: Qt.AlignVCenter
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
    // MULTILINE MODE - orientation aware
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
                // Colorful / custom
                Kirigami.Icon {
                    width: parent.iconSz
                    height: parent.iconSz
                    anchors.centerIn: parent
                    visible: compactRoot.mlIconStyle !== "symbolic"
                    source: compactRoot.weatherRoot
                        ? compactRoot.weatherRoot.getMultilineModeIconSource()
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
                            WeatherIcon {
                                visible: mlRowItem.modelData.iconVis
                                iconInfo: mlRowItem.modelData.iconInfo
                                iconSize: (mlRowItem.modelData.iconInfo.type || "") === "wi" ? Math.round(scrollCol.rowFontPx * 1.3) : compactRoot.svgIconPx
                                wiFontFamily: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                                wiFontReady: wiFontPanel.status === FontLoader.Ready
                                Layout.alignment: Qt.AlignVCenter
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
                        ? compactRoot.weatherRoot.getMultilineModeIconSource()
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
                            WeatherIcon {
                                visible: mlRowItemV.modelData.iconVis
                                iconInfo: mlRowItemV.modelData.iconInfo
                                iconSize: (mlRowItemV.modelData.iconInfo.type || "") === "wi" ? Math.round(scrollColV.rowFontPx * 1.3) : compactRoot.svgIconPx
                                wiFontFamily: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                                wiFontReady: wiFontPanel.status === FontLoader.Ready
                                Layout.alignment: Qt.AlignVCenter
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
    // SIMPLE MODE - icon + temperature
    //
    // Architecture (directly mirrors weather-widget-plus/CompactItem.qml):
    //
    //   vertical panel   → cells fill WIDTH,  fontSizeMode = Text.HorizontalFit
    //   horizontal panel → cells fill HEIGHT, fontSizeMode = Text.VerticalFit
    //
    // The GridLayout is sized to exactly its content and centered inside
    // the widget - so no dead space appears between or around cells.
    //
    // uniformCellHeights is ONLY enabled for vertical + stacked (type 1),
    // matching the reference behaviour exactly.
    //
    // Compressed (type 2) is built separately: a square Item (side =
    // squareSide) contains both the icon and the badge so the badge always
    // overlaps the bottom-right corner of the actual painted icon.
    //
    // Size modes select the geometry used by this layout:
    //   auto   → geometry allocated by Plasma
    //   large  → reconstructed full panel thickness
    //   manual → configured pixel size
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: simpleRoot
        // Use _simpleContentPanelH on horizontal panels so large icon/font
        // modes are not clipped. Auto/manual keep Plasma's allocated height.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: (!compactRoot.vertical && compactRoot.isSimpleMode) ? compactRoot._simpleContentPanelH : parent.height
        visible: compactRoot.isSimpleMode

        // fontSizeMode driven purely by panel orientation - not layout type
        readonly property int autoFontSizeMode: compactRoot.vertical ? Text.HorizontalFit : Text.VerticalFit

        // ── No location prompt ────────────────────────────────────────────
        RowLayout {
            id: noLocationRow
            anchors.centerIn: parent
            spacing: 5
            visible: !compactRoot._hasLocation

            Text {
                text: "\uF041"
                font.family: wiFontPanel.status === FontLoader.Ready ? wiFontPanel.font.family : ""
                font.pixelSize: compactRoot.simpleFontSz
                color: Kirigami.Theme.textColor
                Layout.alignment: Qt.AlignVCenter
            }
            Label {
                text: i18n("Add a location")
                font.pixelSize: compactRoot.panelFontPx
                color: Kirigami.Theme.textColor
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── Layout types 0 (side-by-side) and 1 (stacked) ────────────────
        // The GridLayout is anchored to the CENTER of its parent and sized
        // to exactly its content.  This prevents any dead space from pooling
        // around the cells when the panel is larger than the content.
        //
        //   vertical panel:
        //     width  = panel width selected by visible size modes
        //     height = auto (sum of row paintedHeights; GridLayout.implicitHeight)
        //
        //   horizontal panel:
        //     height = panel height selected by visible size modes (type 0)
        //     width  = auto (sum of column paintedWidths; GridLayout.implicitWidth)
        //
        // auto/manual keep Plasma's allocation; a visible large-mode item
        // expands the corresponding dimension to full panel thickness.
        GridLayout {
            id: simpleGrid
            visible: compactRoot.simpleLayoutType !== 2 && compactRoot.weatherRoot && compactRoot.weatherRoot.hasSelectedTown

            // Centre in parent; size determined by axis.
            anchors.centerIn: parent
            // Vertical: fill the selected panel thickness so the temp column
            // gets real width.
            // Horizontal: content-sized so anchors.centerIn can centre the block.
            width: compactRoot.vertical ? compactRoot._simpleContentPanelW : implicitWidth

            // Vertical panels and horizontal stacked (type 1): collapse the grid to
            // exactly its content height so anchors.centerIn centres the icon+temp
            // pair cleanly.
            //
            // Horizontal type 0 (side-by-side): use _simpleContentPanelH so the
            // icon row gets the maximum selected height without any shrinkage.
            // In large mode this may be greater than the post-margin widget height.
            // All other cases use implicitHeight: the grid is exactly its content
            // size, and anchors.centerIn centres the block both horizontally and
            // vertically in the panel - critical for symbolic icons which are
            // smaller than the panel height and would appear top-aligned otherwise.
            height: (!compactRoot.vertical && compactRoot.simpleLayoutType === 0) ? compactRoot._simpleContentPanelH : implicitHeight

            // type 1 → 2 rows × 1 col; type 0 → 1 row × 2 cols
            rows: compactRoot.simpleLayoutType === 1 ? 2 : 1
            columns: compactRoot.simpleLayoutType === 1 ? 1 : 2

            // uniformCellHeights disabled: with different icon/font sizes (e.g. 24 and
            // 16 px) forcing equal rows inflates the grid beyond the panel height.
            // Each row uses its natural cell height; rowSpacing provides the gap.
            uniformCellHeights: false

            // Fixed 4 px gap between icon and temperature:
            //   columnSpacing → side-by-side (type 0)
            //   rowSpacing    → stacked (type 1)
            columnSpacing: compactRoot.simpleLayoutType === 0 ? 4 : 0
            rowSpacing: compactRoot.simpleLayoutType === 1 ? 4 : 0

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
                // Large follows the auto layout rules but uses full panel thickness.
                // Base icon cell size from icon style and computed/manual size.
                readonly property int _baseCellSz: (compactRoot.simpleIconStyle === "colorful" || compactRoot.simpleIconIsBundled) ? compactRoot.simpleIconSz : compactRoot.simpleSymbolicIconSz
                // On horizontal panels, auto/large cap the icon at the selected
                // panel height so the GridLayout row never expands beyond
                // simpleGrid.height (prevents icon overflow and cell shifting).
                // _cellSz is explicit in every mode, so fillWidth is never needed -
                // pinning it avoids Qt distributing columns unevenly
                // when both cells have fillWidth:true (causes the "go right" bug with
                // colorful icons on vertical panels in auto mode).
                // vertical type 0 auto/large: cap to half the selected panel width
                //   (24px at 48px) so icon and temp share the panel width equally.
                // vertical type 0 manual: no cap - honour the user's chosen size.
                // vertical type 1/2 auto/large: cap to the selected panel width.
                // all other manual cases: no panel cap.
                readonly property int _cellSz: !compactRoot.simpleIconUsesPanelSize
                    ? _baseCellSz
                    : compactRoot.vertical
                        ? (compactRoot.simpleLayoutType === 0
                            ? Math.min(_baseCellSz, Math.round(compactRoot._simpleIconPanelW / 2))
                            : Math.min(_baseCellSz, compactRoot._simpleIconPanelW))
                        : Math.min(_baseCellSz, compactRoot._simpleIconPanelH)
                // Pin the cell to exactly _cellSz on both axes.
                // The grid is sized to implicitWidth so anchors.centerIn centres
                // the content block - no fillWidth needed on the icon cell.
                Layout.fillWidth: false
                Layout.fillHeight: false
                Layout.preferredWidth: _cellSz
                Layout.minimumWidth: _cellSz
                Layout.maximumWidth: _cellSz
                // vertical type 0 auto/large: pin cell height to simpleFontSz so the row
                //   is compact (no gap when font is small; icon renders larger than
                //   the cell height but is clipped cleanly - same as panel behaviour).
                // vertical type 0 manual: use _cellSz so a large icon isn't clipped.
                // All other cases: square cell (height = _cellSz).
                readonly property int _cellH: (compactRoot.vertical && compactRoot.simpleLayoutType === 0)
                    ? (compactRoot.simpleIconUsesPanelSize ? compactRoot.simpleFontSz : _cellSz)
                    : _cellSz
                Layout.preferredHeight: _cellH
                Layout.minimumHeight: _cellH
                Layout.maximumHeight: _cellH

                // Widget order: 0 = icon first, 1 = temp first
                Layout.row: compactRoot.simpleLayoutType === 1 ? (compactRoot.simpleWidgetOrder === 0 ? 0 : 1) : 0
                Layout.column: compactRoot.simpleLayoutType === 1 ? 0 : (compactRoot.simpleWidgetOrder === 0 ? 0 : 1)

                // Symbolic icon: append "-symbolic" to the KDE icon name so the
                // icon engine serves the monochrome symbolic variant rather than
                // the colourful one. This is the standard Plasma convention -
                // the KDE weather widget changelog states:
                // "Ask for -symbolic versions everywhere we want monochrome icons."
                Kirigami.Icon {
                    id: iconGlyph
                    width: compactRoot.simpleSymbolicIconSz
                    height: compactRoot.simpleSymbolicIconSz
                    anchors.centerIn: parent
                    visible: compactRoot.simpleIconStyle === "symbolic"
                    source: compactRoot.weatherRoot ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode, compactRoot.weatherRoot.isNightTime(), true) : "weather-none-available-symbolic"
                    smooth: true
                }
                // Colorful / custom icon: explicit size + centerIn, same as symbolic.
                // anchors.fill was constrained to the post-margin cell (~32 px on a
                // 48 px panel); explicit size uses _cellSz selected by the current mode.
                Kirigami.Icon {
                    width: parent._cellSz
                    height: parent._cellSz
                    anchors.centerIn: parent
                    visible: compactRoot.simpleIconStyle === "colorful" || compactRoot.simpleIconStyle === "custom" || compactRoot.simpleIconIsBundled
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    // The bundled symbolic SVGs are drawn with fill="currentColor" and
                    // stay invisible unless Kirigami tints them; the other bundled
                    // themes carry their own colours.
                    isMask: compactRoot.simpleIconStyle === "symbolic-bundled"
                    color: compactRoot.simpleIconStyle === "symbolic-bundled" ? Kirigami.Theme.textColor : "transparent"
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
                // so row height = simpleFontSz - compact with no gaps.
                // This applies to auto and large; manual uses _cellSz.
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
                    text: compactRoot._cvTemp
                    font.family: Kirigami.Theme.defaultFont.family
                    font.bold: false
                    font.pixelSize: compactRoot.simpleFontSz
                    fontSizeMode: Text.FixedSize
                    color: compactRoot.simpleTempColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.NoWrap
                }
                // Anti-aliased outline: DropShadow with high spread renders a
                // smooth background-coloured halo around each glyph, giving the
                // same contrast as Text.Outline but with GPU-composited AA.
                DropShadow {
                    visible: compactRoot.simpleTempShadowEnabled
                    anchors.fill: tempText
                    source: tempText
                    radius: 3
                    samples: 16
                    spread: compactRoot.simpleTempShadowIntensity
                    color: compactRoot.simpleTempShadowColor
                    cached: true
                }
            }
        } // GridLayout (types 0 and 1)

        // ── Compressed (type 2) ───────────────────────────────────────────
        //
        // A square Item (side = squareSide) is centered in the widget.  Both
        // the weather icon AND the badge Rectangle live INSIDE that square,
        // so the badge always anchors to the bottom-right corner of the actual
        // painted icon regardless of panel orientation.
        Item {
            id: compressedWrapper
            // Use _simpleContentPanelH on horizontal panels so large icon/font
            // modes are not clipped. Auto/manual keep Plasma's allocated height.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: (!compactRoot.vertical && compactRoot.isSimpleMode)
                ? compactRoot._simpleContentPanelH : parent.height
            visible: compactRoot.simpleLayoutType === 2 && compactRoot.weatherRoot && compactRoot.weatherRoot.hasSelectedTown

            // Orientation-aware square sizing:
            //   auto   → icon panel dimension allocated by Plasma
            //   large  → reconstructed full panel thickness
            //   manual → configured icon size
            // All modes use a minimum of 16 px.
            readonly property int squareSide: compactRoot.simpleIconUsesPanelSize
                ? (compactRoot.vertical
                    ? Math.max(16, compactRoot._simpleIconPanelW)
                    : Math.max(16, compactRoot._simpleIconPanelH))
                : Math.max(16, compactRoot.simpleIconPx)
            Item {
                id: compressedSquare
                width: compressedWrapper.squareSide
                height: compressedWrapper.squareSide
                anchors.centerIn: parent

                // Symbolic icon - KDE theme icon with -symbolic suffix
                Kirigami.Icon {
                    id: compressedIconGlyph
                    width: parent.width
                    height: parent.height
                    anchors.centerIn: parent
                    visible: compactRoot.simpleIconStyle === "symbolic"
                    source: compactRoot.weatherRoot
                        ? W.weatherCodeToIcon(compactRoot.weatherRoot.weatherCode,
                            compactRoot.weatherRoot.isNightTime(), true)
                        : "weather-none-available-symbolic"
                    smooth: true
                }
                // Colorful / custom icon
                Kirigami.Icon {
                    width: parent.width
                    height: parent.height
                    anchors.centerIn: parent
                    visible: compactRoot.simpleIconStyle === "colorful" || compactRoot.simpleIconStyle === "custom" || compactRoot.simpleIconIsBundled
                    source: compactRoot.weatherRoot ? compactRoot.weatherRoot.getSimpleModeIconSource() : ""
                    // The bundled symbolic SVGs are drawn with fill="currentColor" and
                    // stay invisible unless Kirigami tints them; the other bundled
                    // themes carry their own colours.
                    isMask: compactRoot.simpleIconStyle === "symbolic-bundled"
                    color: compactRoot.simpleIconStyle === "symbolic-bundled" ? Kirigami.Theme.textColor : "transparent"
                    smooth: true
                }

                // Temperature badge - position, spacing and color are configurable
                Rectangle {
                    id: compressedBadgeRect
                    readonly property string _pos: Plasmoid.configuration.compressedBadgePosition || "bottom-right"
                    readonly property int _spacing: Plasmoid.configuration.compressedBadgeSpacing || 0

                    // Use computed x/y instead of anchors to avoid QML sticky-anchor issues
                    x: {
                        if (_pos === "bottom-right" || _pos === "top-right")
                            return parent.width - width - _spacing;
                        if (_pos === "bottom-left" || _pos === "top-left")
                            return _spacing;
                        // center
                        return (parent.width - width) / 2;
                    }
                    y: {
                        if (_pos.indexOf("bottom") === 0)
                            return parent.height - height - _spacing;
                        // top
                        return _spacing;
                    }

                    width: compressedBadge.implicitWidth + 6
                    height: compressedBadge.implicitHeight + 2
                    radius: height / 2
                    color: {
                        var cc = Plasmoid.configuration.compressedBadgeColor || "";
                        var op = Plasmoid.configuration.compressedBadgeOpacity !== undefined
                            ? Plasmoid.configuration.compressedBadgeOpacity : 0.85;
                        if (cc.length > 0) {
                            var parsed = Qt.color(cc);
                            return Qt.rgba(parsed.r, parsed.g, parsed.b, op);
                        }
                        return Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                       Kirigami.Theme.backgroundColor.g,
                                       Kirigami.Theme.backgroundColor.b, op);
                    }

                    Label {
                        id: compressedBadge
                        anchors.centerIn: parent
                        text: compactRoot._cvTemp
                        font.family: Kirigami.Theme.defaultFont.family
                        font.pixelSize: compactRoot.simpleFontUsesPanelSize
                            ? Math.max(8, Math.round((compactRoot.vertical
                                ? compactRoot._simpleFontPanelW
                                : compactRoot._simpleFontPanelH) / 3))
                            : Math.max(8, compactRoot.simpleFontPx)
                        font.bold: false
                        color: compactRoot.simpleTempColor
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
    // Icons base directory - resolved once for IconResolver calls
    readonly property string _iconsBaseDir: Qt.resolvedUrl("../icons/") + ""

    function _buildItems() {
        var r = weatherRoot;
        if (!r)
            return [];
        if (!r.hasSelectedTown)
            return [
                {
                    iconInfo: { type: "wi", source: "\uF041", svgFallback: "", isMask: false },
                    iconVis: true,
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
                iconInfo: { type: "wi", source: "", svgFallback: "", isMask: false },
                iconVis: false,
                text: sep,
                isSep: true
            });
        }
        function pushInfoItem(info, vis, txt) {
            result.push({
                iconInfo: info,
                iconVis: vis && (info.source || "").length > 0,
                text: txt,
                isSep: false
            });
        }
        function pushSpaceSep() {
            result.push({
                iconInfo: { type: "wi", source: "", svgFallback: "", isMask: false },
                iconVis: false,
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

                if (sunMode === "both") {
                    // Both sunrise and sunset on the same line
                    var iconSz = Plasmoid.configuration.panelIconSize || 22;
                    var svgTheme = (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light")
                        ? "symbolic-light" : theme;

                    var rInfo, sInfo;
                    if (theme === "wi-font") {
                        rInfo = { type: "wi", source: "\uF051", svgFallback: "", isMask: false };
                        sInfo = { type: "wi", source: "\uF052", svgFallback: "", isMask: false };
                    } else if (theme === "custom") {
                        var cmap = {};
                        (Plasmoid.configuration.panelCustomIcons || "").split(";").forEach(function (p) {
                            var kv = p.split("=");
                            if (kv.length === 2)
                                cmap[kv[0].trim()] = kv[1].trim();
                        });
                        rInfo = { type: "kde", source: cmap["suntimes-sunrise"] || "weather-sunrise", svgFallback: "", isMask: false };
                        sInfo = { type: "kde", source: cmap["suntimes-sunset"] || "weather-sunset", svgFallback: "", isMask: false };
                    } else {
                        rInfo = IconResolver.resolve("suntimes-sunrise", iconSz, compactRoot._iconsBaseDir, svgTheme);
                        sInfo = IconResolver.resolve("suntimes-sunset", iconSz, compactRoot._iconsBaseDir, svgTheme);
                    }

                    if (result.length > 0)
                        pushSep();
                    pushInfoItem(rInfo, show, r.formatTimeForDisplay(r.sunriseTimeText));
                    pushSpaceSep();
                    pushInfoItem(sInfo, show, r.formatTimeForDisplay(r.sunsetTimeText));
                    return;
                }

                // upcoming / only-one variant
                var stx = r.panelItemTextOnly(tok);
                if (!stx || stx.length === 0)
                    return;
                if (result.length > 0)
                    pushSep();
                pushInfoItem(iconInfo, show, stx);
                return;
            }

            if (tok === "moonphase") {
                var moonMode = Plasmoid.configuration.panelMoonPhaseMode || "full";

                // Multi-chip modes: "full" = phase + rise + set, "times" = rise + set, "upcoming" = phase + upcoming
                if (moonMode === "full" || moonMode === "times" || moonMode === "upcoming") {
                    var iconSzM = Plasmoid.configuration.panelIconSize || 22;
                    var svgThemeM = (theme === "symbolic" && Plasmoid.configuration.panelSymbolicVariant === "light")
                        ? "symbolic-light" : theme;

                    if (result.length > 0)
                        pushSep();

                    // Phase chip (only for "full" and "upcoming")
                    if (moonMode === "full" || moonMode === "upcoming") {
                        pushInfoItem(iconInfo, show, r.moonPhaseLabel());
                        pushSpaceSep();
                    }

                    if (moonMode === "upcoming") {
                        // upcoming: show next rise or set
                        var upTok = r._moonUpcoming() === "rise" ? "moonphase-moonrise" : "moonphase-moonset";
                        var upTime = r._moonUpcoming() === "rise" ? r.formatTimeForDisplay(r.moonriseTimeText) : r.formatTimeForDisplay(r.moonsetTimeText);
                        pushInfoItem(r.panelItemIconInfo(upTok), show, upTime);
                    } else {
                        // full / times: show both rise and set
                        var mrInfo, msInfo;
                        if (theme === "wi-font") {
                            mrInfo = { type: "wi", source: "\uF0C9", svgFallback: "", isMask: false };
                            msInfo = { type: "wi", source: "\uF0CA", svgFallback: "", isMask: false };
                        } else if (theme === "custom") {
                            var cmapM = {};
                            (Plasmoid.configuration.panelCustomIcons || "").split(";").forEach(function (p) {
                                var kv = p.split("=");
                                if (kv.length === 2)
                                    cmapM[kv[0].trim()] = kv[1].trim();
                            });
                            mrInfo = { type: "kde", source: cmapM["moonrise"] || "weather-clear-night", svgFallback: "", isMask: false };
                            msInfo = { type: "kde", source: cmapM["moonset"] || "weather-clear-night", svgFallback: "", isMask: false };
                        } else {
                            mrInfo = IconResolver.resolve("moonrise", iconSzM, compactRoot._iconsBaseDir, svgThemeM);
                            msInfo = IconResolver.resolve("moonset", iconSzM, compactRoot._iconsBaseDir, svgThemeM);
                        }

                        pushInfoItem(mrInfo, show, r.formatTimeForDisplay(r.moonriseTimeText));
                        pushSpaceSep();
                        pushInfoItem(msInfo, show, r.formatTimeForDisplay(r.moonsetTimeText));
                    }
                    return;
                }

                // Single-chip modes: "phase", "moonrise", "moonset", "upcoming-times"
                var mtx = r.panelItemTextOnly(tok);
                if (!mtx || mtx.length === 0)
                    return;
                if (result.length > 0)
                    pushSep();
                pushInfoItem(iconInfo, show, mtx);
                return;
            }

            // ── Alerts: no alerts → single flag + "None"; with alerts → flag + type glyph + text ──
            if (tok === "alerts") {
                var alertTxt = r.panelItemTextOnly(tok);
                if (!alertTxt || alertTxt.length === 0)
                    return;
                if (result.length > 0)
                    pushSep();
                var pa = (r.weatherAlerts && r.weatherAlerts.length > 0)
                    ? r.primaryAlert() : null;
                if (pa) {
                    // Have alerts: flag icon (no text) + type glyph icon + alert name text
                    pushInfoItem(iconInfo, show, "");
                    var glyphInfo = {
                        type: "wi",
                        source: r.alertTypeGlyph(pa.awarenessType || 0),
                        svgFallback: "",
                        isMask: false
                    };
                    pushInfoItem(glyphInfo, show, alertTxt);
                } else {
                    // No alerts: single flag icon + "None" text (no double icon)
                    pushInfoItem(iconInfo, show, alertTxt);
                }
                return;
            }

            var txt = r.panelItemTextOnly(tok);
            if (!txt || txt.length === 0)
                return;
            if (result.length > 0)
                pushSep();
            pushInfoItem(iconInfo, show, txt);
        });

        return result;
    }
}
