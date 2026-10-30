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
 * ConfigWidgetTab.qml - Widget tab with sub-tabs: General, Details, Forecast
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: widgetTab
    spacing: 0

    /** Reference to the root KCM (configAppearance) for cfg_* properties */
    required property var configRoot

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

    // The forecast detail switches on ONE line (they wrap only when the page is too narrow).
    // GraphOrderList (below) works on the same switches: it lists the graphs that are switched
    // on - for the "Graphs" layout - so they can be dragged into order and given their colors.
    component StatSwitches: ColumnLayout {
        id: ss
        /** The KCM root that owns the cfg_* properties */
        required property var cfgRoot
        /** [{key, label, cfg, defaultColor?, colors?, orderable?, graphsOnly?, missingFirst?}]
         *   colors:       [{key, label, defaultColor, cfg?}] for a graph that is drawn with more than one
         *                 line (the temperature graph); each color is chosen on its own. A color that has
         *                 a cfg is only offered while that switch is on. Without `colors` the graph has
         *                 the one color `defaultColor`, saved under `key`.
         *   orderable:    false = a switch only, without a row of its own in the list
         *   graphsOnly:   true = the switch is only shown with the "Graphs" layout (it does nothing elsewhere)
         *   missingFirst: true = a saved order that lacks this graph puts it on top (the temperature
         *                 graph was always on top before it could be moved) */
        property var defs: []
        /** Name of the cfg_* string property that holds the graph order ("temp;wind;pressure;...") */
        property string orderProp: ""
        /** Name of the cfg_* string property that holds the graph colors ("wind=#66bb6a;uv=#ffb300") */
        property string colorsProp: ""
        /** True while the "Graphs" layout is chosen */
        property bool reorderable: false
        spacing: Kirigami.Units.smallSpacing

        // the saved order, completed with any detail that is missing from it
        function _fullOrder() {
            var raw = String(ss.cfgRoot[ss.orderProp] || "").split(";");
            var out = [];
            function known(k) {
                for (var i = 0; i < ss.defs.length; ++i)
                    if (ss.defs[i].key === k && ss.defs[i].orderable !== false)
                        return true;
                return false;
            }
            for (var i = 0; i < raw.length; ++i) {
                var k = raw[i].trim();
                if (k.length > 0 && out.indexOf(k) < 0 && known(k))
                    out.push(k);
            }
            for (var j = 0; j < ss.defs.length; ++j) {
                var d = ss.defs[j];
                if (d.orderable === false || out.indexOf(d.key) >= 0)
                    continue;
                // An order saved before the temperature graph could be moved has no "temp" in it and
                // that graph was on top then: keep it there (ForecastView reads such an order the same way).
                if (d.missingFirst === true)
                    out.unshift(d.key);
                else
                    out.push(d.key);
            }
            return out;
        }
        function _def(k) {
            for (var i = 0; i < ss.defs.length; ++i)
                if (ss.defs[i].key === k)
                    return ss.defs[i];
            return null;
        }
        // the colors of a graph: its `colors`, else the one color it has under its own key
        function _slots(d) {
            if (d.colors !== undefined && d.colors.length > 0)
                return d.colors;
            return [
                {
                    key: d.key,
                    label: d.label,
                    defaultColor: d.defaultColor || ""
                }
            ];
        }
        // the built-in color saved under `slotKey` (a color of any graph of the switches)
        function _slotDefault(slotKey) {
            for (var i = 0; i < ss.defs.length; ++i) {
                var s = ss._slots(ss.defs[i]);
                for (var j = 0; j < s.length; ++j)
                    if (s[j].key === slotKey)
                        return s[j].defaultColor || "";
            }
            return "";
        }
        // the switched-on details, in the saved order
        readonly property var _enabled: {
            var full = ss._fullOrder();
            var out = [];
            for (var i = 0; i < full.length; ++i) {
                var d = ss._def(full[i]);
                if (d && ss.cfgRoot[d.cfg] === true)
                    out.push(d);
            }
            return out;
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: ss.defs
                delegate: Switch {
                    required property var modelData
                    // a graph-only switch (the temperature graph) is meaningless in the other layouts
                    visible: modelData.graphsOnly !== true || ss.reorderable
                    text: modelData.label
                    checked: ss.cfgRoot[modelData.cfg] === true
                    onToggled: ss.cfgRoot[modelData.cfg] = checked
                }
            }
        }

        Label {
            visible: {
                var d = ss._def("kp");
                return d !== null && ss.cfgRoot[d.cfg] === true;
            }
            Layout.fillWidth: true
            text: i18n("The geomagnetic (Kp/G) forecast is only available up to 3 days ahead")
            wrapMode: Text.WordWrap
            opacity: 0.7
        }
    }

    // Drag-and-drop list of the graphs of a StatSwitches: the order they are stacked in, and
    // (edit button) the colors of each graph. Same approach as ConfigTooltipSubPage.qml: a working
    // ListModel is moved live while dragging, and the order is written back to cfg_ once the
    // item is dropped. A graph with more than one line (the temperature graph) is ONE row with a
    // swatch per color; its edit button opens a small dialog where each color is chosen on its own.
    // It hides itself unless the "Graphs" layout is chosen and at least one graph is on.
    component GraphOrderList: ColumnLayout {
        id: gl
        /** The StatSwitches whose switched-on graphs are listed */
        required property var stats
        visible: gl.stats.visible && gl.stats.reorderable && gl.stats.orderProp.length > 0 && gl._enabled.length > 0
        spacing: 0

        // the colors that were chosen: {slotKey: "#rrggbb"}
        readonly property var _colors: {
            var out = {};
            var raw = String(gl.stats.cfgRoot[gl.stats.colorsProp] || "").split(";");
            for (var i = 0; i < raw.length; ++i) {
                var kv = raw[i].split("=");
                if (kv.length === 2 && /^#[0-9a-fA-F]{6}$/.test(kv[1].trim()))
                    out[kv[0].trim()] = kv[1].trim().toLowerCase();
            }
            return out;
        }
        // the key of the color that is being edited
        property string _editKey: ""
        // True while WE write the order, so the model is not rebuilt under the user's hands.
        property bool _applyingOrder: false
        readonly property var _enabled: gl.stats._enabled
        // The most colors a row can have: every row gets room for that many swatches, so the rows line up.
        readonly property int _maxSlots: {
            var n = 1;
            for (var i = 0; i < gl.stats.defs.length; ++i)
                n = Math.max(n, gl.stats._slots(gl.stats.defs[i]).length);
            return n;
        }

        ListModel {
            id: orderModel
        }

        function _rebuildOrderModel() {
            orderModel.clear();
            var en = gl.stats._enabled;
            for (var i = 0; i < en.length; ++i)
                orderModel.append({
                    itemKey: en[i].key,
                    itemLabel: en[i].label
                });
        }
        // The colors of a row that are in use. A color that has its own switch (the chance of
        // precipitation in the hourly graph) is only listed while that switch is on.
        function _slotsOf(key) {
            var d = gl.stats._def(key);
            if (!d)
                return [];
            var all = gl.stats._slots(d);
            var out = [];
            for (var i = 0; i < all.length; ++i)
                if (all[i].cfg === undefined || gl.stats.cfgRoot[all[i].cfg] === true)
                    out.push(all[i]);
            return out;
        }
        function _labelOf(key) {
            var d = gl.stats._def(key);
            return d ? d.label : "";
        }
        // the color a swatch shows: the chosen one, else the built-in one
        function _shownColor(slot) {
            return gl._colors[slot.key] || slot.defaultColor || "#888888";
        }
        // does any color of the row differ from the built-in one?
        function _anyCustom(key) {
            var s = gl._slotsOf(key);
            for (var i = 0; i < s.length; ++i)
                if (gl._colors[s[i].key] !== undefined)
                    return true;
            return false;
        }
        // The switched-on graphs changed from outside (a switch was toggled, the config was reset...)
        on_EnabledChanged: {
            if (!gl._applyingOrder)
                gl._rebuildOrderModel();
        }
        Component.onCompleted: gl._rebuildOrderModel()

        // Writes the order shown in the list back to the config. Graphs that are switched
        // off keep their place in the saved order; the switched-on ones are refilled in the
        // order of the list.
        function _applyOrder() {
            var keys = [];
            for (var i = 0; i < orderModel.count; ++i)
                keys.push(orderModel.get(i).itemKey);
            var full = gl.stats._fullOrder();
            var out = [];
            var n = 0;
            for (var j = 0; j < full.length; ++j) {
                if (keys.indexOf(full[j]) >= 0)
                    out.push(keys[n++]);
                else
                    out.push(full[j]);
            }
            gl._applyingOrder = true;
            gl.stats.cfgRoot[gl.stats.orderProp] = out.join(";");
            gl._applyingOrder = false;
        }

        // Saves colors, written in one go: `changes` is {slotKey: "#rrggbb"}; an empty color (or the
        // built-in one) removes the entry.
        function _setColors(changes) {
            var m = Object.assign({}, gl._colors);
            for (var key in changes) {
                var hex = changes[key];
                var builtIn = String(gl.stats._slotDefault(key)).toLowerCase();
                if (!hex || hex.toLowerCase() === builtIn)
                    delete m[key];
                else
                    m[key] = hex.toLowerCase();
            }
            var parts = [];
            for (var k in m)
                parts.push(k + "=" + m[k]);
            gl.stats.cfgRoot[gl.stats.colorsProp] = parts.join(";");
        }
        function _setColor(key, hex) {
            var c = {};
            c[key] = hex;
            gl._setColors(c);
        }
        // back to the built-in colors of a whole row
        function _resetRow(key) {
            var s = gl._slotsOf(key);
            var c = {};
            for (var i = 0; i < s.length; ++i)
                c[s[i].key] = "";
            gl._setColors(c);
        }
        function _hex(c) {
            function h(v) {
                var s = Math.round(v * 255).toString(16);
                return s.length < 2 ? "0" + s : s;
            }
            return "#" + h(c.r) + h(c.g) + h(c.b);
        }
        function _edit(key, current) {
            gl._editKey = key;
            colorDialog.color = current;
            colorDialog.currentColor = current;
            colorDialog.open();
        }
        // The edit button of a row: a row with one color goes straight to the color dialog; a row with
        // several colors (the temperature graph) opens the small dialog that lists them.
        function _editRow(key) {
            var s = gl._slotsOf(key);
            if (s.length > 1) {
                colorsDialog.rowKey = key;
                colorsDialog.open();
            } else if (s.length === 1) {
                gl._edit(s[0].key, gl._shownColor(s[0]));
            }
        }

        // The platform's own color dialog (Qt.labs.platform): the native one where the desktop
        // has it, otherwise Qt's QColorDialog - not a dialog drawn in QML.
        Platform.ColorDialog {
            id: colorDialog
            title: i18n("Choose the color of the graph")
            onAccepted: gl._setColor(gl._editKey, gl._hex(colorDialog.color))
        }

        // The small dialog of a row with more than one color: every color has its own swatch,
        // change button and reset button, so they are chosen independently of each other.
        Dialog {
            id: colorsDialog
            // the row whose colors are shown
            property string rowKey: ""
            readonly property var slots: gl._slotsOf(colorsDialog.rowKey)

            title: i18n("Colors - %1", gl._labelOf(colorsDialog.rowKey))
            modal: true
            parent: Overlay.overlay
            anchors.centerIn: parent
            standardButtons: Dialog.Close

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: colorsDialog.slots
                    delegate: RowLayout {
                        id: slotRow
                        required property var modelData
                        readonly property string shown: gl._shownColor(slotRow.modelData)
                        readonly property bool custom: gl._colors[slotRow.modelData.key] !== undefined
                        Layout.fillWidth: true
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: Kirigami.Units.gridUnit
                            implicitHeight: Kirigami.Units.gridUnit
                            radius: width / 2
                            color: slotRow.shown
                            border.width: 1
                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.35)
                        }
                        Label {
                            text: slotRow.modelData.label
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        // back to the built-in color (only when this color was changed)
                        ToolButton {
                            implicitWidth: Kirigami.Units.iconSizes.medium
                            implicitHeight: Kirigami.Units.iconSizes.medium
                            icon.name: "edit-undo"
                            enabled: slotRow.custom
                            opacity: slotRow.custom ? 1.0 : 0.0
                            onClicked: gl._setColor(slotRow.modelData.key, "")
                            ToolTip.text: i18n("Use the built-in color")
                            ToolTip.visible: hovered
                            ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        Button {
                            text: i18n("Change…")
                            icon.name: "document-edit"
                            onClicked: gl._edit(slotRow.modelData.key, slotRow.shown)
                        }
                    }
                }
            }
        }

        Label {
            text: i18n("Drag to reorder the graphs, or use the edit button to change a color")
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        ListView {
            id: orderList
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            // the page around it scrolls, so this list just shows all of its rows
            Layout.preferredHeight: contentHeight
            interactive: false
            spacing: 0
            model: orderModel
            displaced: Transition {
                YAnimator {
                    duration: Kirigami.Units.longDuration
                }
            }
            delegate: Item {
                id: orderDelegateRoot
                width: orderList.width
                implicitHeight: orderDelegateCol.implicitHeight
                ColumnLayout {
                    id: orderDelegateCol
                    spacing: 0
                    width: parent.width
                    ItemDelegate {
                        id: orderRowDelegate
                        Layout.fillWidth: true
                        hoverEnabled: true
                        down: false
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.ListItemDragHandle {
                                listItem: orderRowDelegate
                                listView: orderList
                                onMoveRequested: function (oldIndex, newIndex) {
                                    if (newIndex !== oldIndex)
                                        orderModel.move(oldIndex, newIndex, 1);
                                }
                                onDropped: gl._applyOrder()
                            }
                            // the colors of the graph: a swatch for each of its lines
                            Row {
                                id: swatchRow
                                readonly property var slots: gl._slotsOf(model.itemKey)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: gl._maxSlots * Kirigami.Units.gridUnit + (gl._maxSlots - 1) * swatchRow.spacing
                                spacing: Kirigami.Units.smallSpacing
                                Repeater {
                                    model: swatchRow.slots
                                    delegate: Rectangle {
                                        id: swatch
                                        required property var modelData
                                        implicitWidth: Kirigami.Units.gridUnit
                                        implicitHeight: Kirigami.Units.gridUnit
                                        radius: width / 2
                                        color: gl._shownColor(swatch.modelData)
                                        border.width: 1
                                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.35)
                                        // which line a swatch is, when the row has more than one
                                        HoverHandler {
                                            id: swatchHover
                                        }
                                        ToolTip.text: swatch.modelData.label
                                        ToolTip.visible: swatchHover.hovered && swatchRow.slots.length > 1
                                        ToolTip.delay: Kirigami.Units.toolTipDelay
                                    }
                                }
                            }
                            Label {
                                text: (model.index + 1) + "."
                                opacity: 0.6
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.2
                            }
                            Label {
                                text: model.itemLabel
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            // back to the built-in colors (only when a color of the row was changed)
                            ToolButton {
                                readonly property bool custom: gl._anyCustom(model.itemKey)
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                icon.name: "edit-undo"
                                enabled: custom
                                opacity: custom ? 1.0 : 0.0
                                onClicked: gl._resetRow(model.itemKey)
                                ToolTip.text: swatchRow.slots.length > 1 ? i18n("Use the built-in colors") : i18n("Use the built-in color")
                                ToolTip.visible: hovered
                                ToolTip.delay: Kirigami.Units.toolTipDelay
                            }
                            // edit: choose the color (a row with several colors opens a small dialog)
                            ToolButton {
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                icon.name: "document-edit"
                                onClicked: gl._editRow(model.itemKey)
                                ToolTip.text: swatchRow.slots.length > 1 ? i18n("Change the colors") : (model.itemKey === "kp" ? i18n("Change the color (replaces the colors of the G scale)") : i18n("Change the color"))
                                ToolTip.visible: hovered
                                ToolTip.delay: Kirigami.Units.toolTipDelay
                            }
                        }
                    }
                    Kirigami.Separator {
                        Layout.fillWidth: true
                        opacity: 0.4
                    }
                }
            }
        }
    }

    /** Emitted when the user clicks Configure… to push the details sub-page */
    signal pushSubPage
    /** Emitted when the user clicks Configure… to push the simple items sub-page */
    signal pushSimpleSubPage

    /** Icon theme choices shared by all combos */
    readonly property var iconThemeModel: [
        {
            text: i18n("KDE Icon Theme"),
            value: "kde"
        },
        {
            text: i18n("Symbolic (Bundled)"),
            value: "symbolic"
        },
        {
            text: i18n("Flat Color (Bundled)"),
            value: "flat-color"
        },
        {
            text: i18n("3D Oxygen (Bundled)"),
            value: "3d-oxygen"
        },
        {
            text: i18n("Meteocons (Bundled)"),
            value: "meteocons"
        }
    ]

    /** Condition icon theme choices - adds KDE Symbolic and Custom options */
    readonly property var conditionIconThemeModel: [
        {
            text: i18n("KDE Icon Theme (Colorful)"),
            value: "kde"
        },
        {
            text: i18n("KDE Icon Theme (Symbolic)"),
            value: "kde-symbolic"
        },
        {
            text: i18n("Symbolic (Bundled)"),
            value: "symbolic"
        },
        {
            text: i18n("Flat Color (Bundled)"),
            value: "flat-color"
        },
        {
            text: i18n("3D Oxygen (Bundled)"),
            value: "3d-oxygen"
        },
        {
            text: i18n("Meteocons (Bundled)"),
            value: "meteocons"
        },
        {
            text: i18n("Custom\u2026"),
            value: "custom"
        }
    ]

    function findThemeIndex(theme) {
        if (theme === "wi-font")
            theme = "symbolic";
        for (var i = 0; i < iconThemeModel.length; ++i)
            if (iconThemeModel[i].value === theme)
                return i;
        return 0;
    }

    function findConditionThemeIndex(theme) {
        if (theme === "wi-font")
            theme = "symbolic";
        for (var i = 0; i < conditionIconThemeModel.length; ++i)
            if (conditionIconThemeModel[i].value === theme)
                return i;
        return 0;
    }

    // ── Visible tabs ──────────────────────────────────────────────────────
    // cfg_widgetVisibleTabs holds a semicolon-separated list of tab ids
    // ("details;forecast;radar;history", or "none"). Older configs may still
    // hold "both" (= all tabs) or a single tab id; those are read as-is and
    // rewritten in the list form on the next toggle.
    readonly property var tabIds: ["details", "forecast", "radar", "history"]

    function visibleTabList() {
        var v = configRoot.cfg_widgetVisibleTabs || "both";
        if (v === "both")
            return tabIds.slice();
        if (v === "none")
            return [];
        return v.split(";").map(function (t) {
            return t.trim();
        });
    }
    function isTabVisible(id) {
        return visibleTabList().indexOf(id) >= 0;
    }
    function setTabVisible(id, on) {
        var cur = visibleTabList();
        var idx = cur.indexOf(id);
        if (on && idx < 0)
            cur.push(id);
        else if (!on && idx >= 0)
            cur.splice(idx, 1);
        // Keep the canonical display order whatever order the switches were flipped in.
        var out = tabIds.filter(function (t) {
            return cur.indexOf(t) >= 0;
        });
        configRoot.cfg_widgetVisibleTabs = out.length === 0 ? "none" : out.join(";");
    }

    // Refresh both icon theme combos (General > Weather icon theme, Details >
    // Icon theme) after the icon theme scope dialog (configAppearance.qml)
    // applied a theme from another tab, or was cancelled.
    Connections {
        target: widgetTab.configRoot
        function onIconThemesSynced() {
            conditionIconThemeCombo.currentIndex = widgetTab.findConditionThemeIndex(widgetTab.configRoot.cfg_conditionIconTheme);
            widgetIconThemeCombo.currentIndex = widgetTab.findThemeIndex(widgetTab.configRoot.cfg_widgetIconTheme);
        }
    }

    PlasmaComponents.TabBar {
        id: subTabBar
        Layout.fillWidth: true
        PlasmaComponents.TabButton {
            icon.name: "preferences-system-windows"
            text: i18n("General")
        }
        PlasmaComponents.TabButton {
            icon.name: "view-list-details"
            text: i18n("Details")
        }
        PlasmaComponents.TabButton {
            icon.name: "weather-few-clouds"
            text: i18n("Forecast")
        }
    }

    Item {
        Layout.preferredHeight: Kirigami.Units.largeSpacing
    }

    // Tab pages live in a plain ColumnLayout and only the selected one is visible.
    // A StackLayout is as tall as its TALLEST page, which left empty space and a
    // permanent scrollbar under the shorter tabs; layouts ignore hidden items.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // ── SUB-TAB 0: General ────────────────────────────────────────
        GridLayout {
            id: _form1
            visible: subTabBar.currentIndex === 0
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

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Layout
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Layout")
                Layout.columnSpan: _form1.columns
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            Label {
                text: i18n("Mode:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: layoutModeCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Advanced (all tabs)"),
                            value: "advanced"
                        },
                        {
                            text: i18n("Simple"),
                            value: "simple"
                        }
                    ]
                    Component.onCompleted: {
                        currentIndex = (widgetTab.configRoot.cfg_widgetLayoutMode === "simple") ? 1 : 0;
                    }
                    onActivated: widgetTab.configRoot.cfg_widgetLayoutMode = model[currentIndex].value
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Appearance
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Appearance")
                Layout.columnSpan: _form1.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            Label {
                text: i18n("Weather icon theme:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: conditionIconThemeCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: widgetTab.conditionIconThemeModel
                    Component.onCompleted: currentIndex = widgetTab.findConditionThemeIndex(widgetTab.configRoot.cfg_conditionIconTheme)
                    // Asks "Apply everywhere / only here / Cancel" when the theme also
                    // exists in other icon theme settings (see configAppearance.qml).
                    // "KDE Symbolic" and "Custom…" are specific to this combo and
                    // are applied directly, exactly as before.
                    onActivated: widgetTab.configRoot.requestIconTheme("condition", model[currentIndex].value)
                }
            }
            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2 && (widgetTab.configRoot.cfg_conditionIconTheme === "custom")
                implicitWidth: 0
                implicitHeight: 0
            }
            Button {
                visible: widgetTab.configRoot.cfg_conditionIconTheme === "custom"
                text: i18n("Configure weather icons…")
                icon.name: "configure"
                onClicked: widgetTab.configRoot.conditionIconDialog.openWithContext("widget")
            }

            Label {
                text: i18n("Icon glow:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Switch {
                    checked: widgetTab.configRoot.cfg_iconGlowEnabled
                    onToggled: widgetTab.configRoot.cfg_iconGlowEnabled = checked
                }
                Label {
                    text: widgetTab.configRoot.cfg_iconGlowEnabled ? i18n("Enabled") : i18n("Disabled")
                    opacity: 0.8
                    MouseArea {
                        anchors.fill: parent
                        onClicked: widgetTab.configRoot.cfg_iconGlowEnabled = !widgetTab.configRoot.cfg_iconGlowEnabled
                    }
                }
            }
            Label {
                text: i18n("Glow intensity:")
                visible: widgetTab.configRoot.cfg_iconGlowEnabled
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_iconGlowEnabled
                spacing: Kirigami.Units.largeSpacing
                Slider {
                    Layout.preferredWidth: 160
                    from: 0.1
                    to: 1.0
                    stepSize: 0.05
                    value: widgetTab.configRoot.cfg_iconGlowIntensity
                    onMoved: widgetTab.configRoot.cfg_iconGlowIntensity = value
                }
                Label {
                    text: Math.round(widgetTab.configRoot.cfg_iconGlowIntensity * 100) + "%"
                    opacity: 0.65
                    Layout.preferredWidth: 40
                }
            }

            Label {
                text: i18n("Footer:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    id: footerSwitch
                    checked: widgetTab.configRoot.cfg_showUpdateText
                    onToggled: widgetTab.configRoot.cfg_showUpdateText = checked
                }
                Label {
                    text: i18n("Show update time and provider")
                    opacity: 0.8
                    MouseArea {
                        anchors.fill: parent
                        onClicked: footerSwitch.toggle()
                    }
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Tabs & Header behavior
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Tabs & Header Behavior")
                Layout.columnSpan: _form1.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            Label {
                text: i18n("Default tab:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: defaultTabCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Details"),
                            value: "details"
                        },
                        {
                            text: i18n("Forecast"),
                            value: "forecast"
                        },
                        {
                            text: i18n("Radar"),
                            value: "radar"
                        },
                        {
                            text: i18n("History"),
                            value: "history"
                        }
                    ]
                    Component.onCompleted: {
                        var v = widgetTab.configRoot.cfg_widgetDefaultTab || "details";
                        if (v === "forecast")
                            currentIndex = 1;
                        else if (v === "radar")
                            currentIndex = 2;
                        else if (v === "history")
                            currentIndex = 3;
                        else
                            currentIndex = 0;
                    }
                    onActivated: widgetTab.configRoot.cfg_widgetDefaultTab = model[currentIndex].value
                }
            }
            Label {
                text: i18n("Visible tabs:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            Flow {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Switch {
                    text: i18n("Details")
                    checked: widgetTab.isTabVisible("details")
                    onToggled: widgetTab.setTabVisible("details", checked)
                }
                Switch {
                    text: i18n("Forecast")
                    checked: widgetTab.isTabVisible("forecast")
                    onToggled: widgetTab.setTabVisible("forecast", checked)
                }
                Switch {
                    text: i18n("Radar")
                    checked: widgetTab.isTabVisible("radar")
                    onToggled: widgetTab.setTabVisible("radar", checked)
                }
                Switch {
                    text: i18n("History")
                    checked: widgetTab.isTabVisible("history")
                    onToggled: widgetTab.setTabVisible("history", checked)
                }
            }
            Label {
                text: i18n("Sunrise / Sunset:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowSunriseSunset
                    onToggled: widgetTab.configRoot.cfg_simpleShowSunriseSunset = checked
                }
            }

            Label {
                text: i18n("Header:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Switch {
                    id: headerDateTimeSwitch
                    text: i18n("Date and time")
                    checked: widgetTab.configRoot.cfg_headerShowDateTime
                    onToggled: widgetTab.configRoot.cfg_headerShowDateTime = checked
                }
                Switch {
                    text: i18n("Location name")
                    checked: widgetTab.configRoot.cfg_headerShowLocation
                    onToggled: widgetTab.configRoot.cfg_headerShowLocation = checked
                }
                Switch {
                    text: i18n("Switch location")
                    checked: widgetTab.configRoot.cfg_headerShowSwitchLocation
                    onToggled: widgetTab.configRoot.cfg_headerShowSwitchLocation = checked
                }
                Switch {
                    text: i18n("Keep widget open")
                    checked: widgetTab.configRoot.cfg_headerShowPinButton
                    onToggled: widgetTab.configRoot.cfg_headerShowPinButton = checked
                }
                Switch {
                    text: i18n("Detect location")
                    checked: widgetTab.configRoot.cfg_headerShowDetectButton
                    onToggled: widgetTab.configRoot.cfg_headerShowDetectButton = checked
                }
                Switch {
                    text: i18n("Refresh")
                    checked: widgetTab.configRoot.cfg_headerShowRefreshButton
                    onToggled: widgetTab.configRoot.cfg_headerShowRefreshButton = checked
                }
            }

            Item {
                // empty label cell: keeps the hint in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.maximumWidth: 340
                wrapMode: Text.WordWrap
                opacity: 0.65
                font: Kirigami.Theme.smallFont
                text: i18n("Date and time formats are set in Misc → Date and Time.")
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Widget popup size
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Widget Size")
                Layout.columnSpan: _form1.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            Label {
                text: i18n("Minimum width:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: minWidthModeCombo
                    Layout.preferredWidth: 130
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Auto"),
                            value: "auto"
                        },
                        {
                            text: i18n("Manual"),
                            value: "manual"
                        }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual" ? 1 : 0
                    onActivated: widgetTab.configRoot.cfg_widgetMinWidthMode = model[currentIndex].value
                }
                SpinBox {
                    enabled: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual"
                    from: 200
                    to: 2000
                    stepSize: 10
                    // Auto placeholder mirrors the actual auto-mode value computed
                    // in main.qml's fullRepresentation block - keep these in sync.
                    value: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual" ? widgetTab.configRoot.cfg_widgetMinWidth : (widgetTab.configRoot.cfg_widgetLayoutMode === "simple" ? 765 : 800)
                    onValueModified: widgetTab.configRoot.cfg_widgetMinWidth = value
                }
                Label {
                    visible: widgetTab.configRoot.cfg_widgetMinWidthMode === "manual"
                    text: "px"
                    opacity: 0.65
                }
            }
            Label {
                text: i18n("Minimum height:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form1.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: minHeightModeCombo
                    Layout.preferredWidth: 130
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Auto"),
                            value: "auto"
                        },
                        {
                            text: i18n("Manual"),
                            value: "manual"
                        }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual" ? 1 : 0
                    onActivated: widgetTab.configRoot.cfg_widgetMinHeightMode = model[currentIndex].value
                }
                SpinBox {
                    enabled: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual"
                    from: 200
                    to: 2000
                    stepSize: 10
                    // Auto placeholder mirrors the actual auto-mode value computed
                    // in main.qml's fullRepresentation block - keep these in sync.
                    value: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual" ? widgetTab.configRoot.cfg_widgetMinHeight : (widgetTab.configRoot.cfg_widgetLayoutMode === "simple" ? 550 : 750)
                    onValueModified: widgetTab.configRoot.cfg_widgetMinHeight = value
                }
                Label {
                    visible: widgetTab.configRoot.cfg_widgetMinHeightMode === "manual"
                    text: "px"
                    opacity: 0.65
                }
            }

            // Invisible filler row: it lets the second column take ALL spare width, so the
            // label column keeps its width when rows are shown or hidden.
            Item {
                visible: _form1.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                visible: _form1.columns === 2
                Layout.fillWidth: true
                implicitWidth: 0
                implicitHeight: 0
            }
        }

        // ── SUB-TAB 1: Details ────────────────────────────────────────
        GridLayout {
            id: _form2
            visible: subTabBar.currentIndex === 1
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

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Icons
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Icons")
                Layout.columnSpan: _form2.columns
            }
            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            Label {
                text: i18n("Icon theme:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: widgetIconThemeCombo
                    Layout.preferredWidth: 200
                    textRole: "text"
                    model: widgetTab.iconThemeModel
                    Component.onCompleted: currentIndex = widgetTab.findThemeIndex(widgetTab.configRoot.cfg_widgetIconTheme)
                    // Asks "Apply everywhere / only here / Cancel" when the theme also
                    // exists in other icon theme settings (see configAppearance.qml).
                    onActivated: widgetTab.configRoot.requestIconTheme("details", model[currentIndex].value)
                }
                Label {
                    text: i18n("Size:")
                    opacity: 0.8
                }
                ComboBox {
                    id: widgetIconSizeCombo
                    Layout.preferredWidth: 90
                    textRole: "text"
                    model: [
                        {
                            text: "16 px",
                            value: 16
                        },
                        {
                            text: "22 px",
                            value: 22
                        },
                        {
                            text: "24 px",
                            value: 24
                        },
                        {
                            text: "32 px",
                            value: 32
                        }
                    ]
                    Component.onCompleted: {
                        for (var i = 0; i < model.length; ++i)
                            if (model[i].value === widgetTab.configRoot.cfg_widgetIconSize) {
                                currentIndex = i;
                                break;
                            }
                        if (currentIndex < 0)
                            currentIndex = 0;
                    }
                    onActivated: widgetTab.configRoot.cfg_widgetIconSize = model[currentIndex].value
                }
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            // ── Warning - KDE themes lack some item icons ──
            Kirigami.InlineMessage {
                Layout.columnSpan: _form2.columns
                Layout.fillWidth: true
                visible: widgetTab.configRoot.cfg_widgetIconTheme === "kde"
                type: Kirigami.MessageType.Warning
                text: i18n("KDE icon themes don't fully support many item icons. You can set your own icons by clicking \"Set your own icons\".")
                showCloseButton: true
                actions: [
                    Kirigami.Action {
                        text: i18n("Set your own icons\u2026")
                        icon.name: "view-visible"
                        onTriggered: {
                            widgetTab.configRoot.initDetailsModel();
                            widgetTab.pushSubPage();
                        }
                    }
                ]
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Layout
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Layout")
                Layout.columnSpan: _form2.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }
            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Label {
                text: i18n("Details layout:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                ComboBox {
                    id: detailsLayoutCombo
                    Layout.preferredWidth: 160
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Cards (2 columns)"),
                            value: "cards2"
                        },
                        {
                            text: i18n("List"),
                            value: "list"
                        }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetDetailsLayout === "list" ? 1 : 0
                    onActivated: widgetTab.configRoot.cfg_widgetDetailsLayout = model[currentIndex].value
                }
            }

            // Cards height (hidden in list mode or simple mode)
            Label {
                text: i18n("Cards height:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: cardsHeightModeCombo
                    Layout.preferredWidth: 130
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Auto"),
                            value: true
                        },
                        {
                            text: i18n("Manual"),
                            value: false
                        }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetCardsHeightAuto ? 0 : 1
                    onActivated: {
                        var newMode = model[currentIndex].value;
                        if (widgetTab.configRoot.cfg_widgetCardsHeightAuto !== newMode)
                            widgetTab.configRoot.cfg_widgetCardsHeightAuto = newMode;
                    }
                }
                SpinBox {
                    enabled: !widgetTab.configRoot.cfg_widgetCardsHeightAuto
                    from: 30
                    to: 120
                    value: widgetTab.configRoot.cfg_widgetCardsHeight
                    onValueModified: widgetTab.configRoot.cfg_widgetCardsHeight = value
                }
                Label {
                    visible: !widgetTab.configRoot.cfg_widgetCardsHeightAuto
                    text: "px"
                    opacity: 0.65
                }
            }

            // Expanded cards height (hidden in list mode or simple mode)
            Label {
                text: i18n("Expanded cards height:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple" && widgetTab.configRoot.cfg_widgetDetailsLayout !== "list"
                spacing: Kirigami.Units.largeSpacing
                ComboBox {
                    id: expandedCardsHeightModeCombo
                    Layout.preferredWidth: 130
                    textRole: "text"
                    model: [
                        {
                            text: i18n("Auto"),
                            value: true
                        },
                        {
                            text: i18n("Manual"),
                            value: false
                        }
                    ]
                    currentIndex: widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto ? 0 : 1
                    onActivated: {
                        var newMode = model[currentIndex].value;
                        if (widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto !== newMode)
                            widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto = newMode;
                    }
                }
                SpinBox {
                    enabled: !widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto
                    from: 120
                    to: 500
                    value: widgetTab.configRoot.cfg_widgetExpandedCardsHeight
                    onValueModified: widgetTab.configRoot.cfg_widgetExpandedCardsHeight = value
                }
                Label {
                    visible: !widgetTab.configRoot.cfg_widgetExpandedCardsHeightAuto
                    text: "px"
                    opacity: 0.65
                }
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Items - switches between advanced and simple mode
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: widgetTab.configRoot.cfg_widgetLayoutMode === "simple" ? i18n("Simple Mode Items") : i18n("Details Items")
                Layout.columnSpan: _form2.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }
            Item {
                // empty label cell: keeps the control in the second column
                visible: _form2.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            // Advanced mode: details items preview + Configure
            Label {
                text: i18n("Details items:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            Item {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                implicitWidth: detailsPreviewRow.implicitWidth
                implicitHeight: detailsPreviewRow.implicitHeight
                RowLayout {
                    id: detailsPreviewRow
                    spacing: 10
                    Flow {
                        spacing: 4
                        Layout.maximumWidth: 260
                        Repeater {
                            model: widgetTab.configRoot.cfg_widgetDetailsOrder.split(";").filter(function (t) {
                                return t.length > 0;
                            })
                            delegate: Rectangle {
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.10)
                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                border.width: 1
                                implicitWidth: detailChipLbl.implicitWidth + 10
                                implicitHeight: detailChipLbl.implicitHeight + 6
                                Label {
                                    id: detailChipLbl
                                    anchors.centerIn: parent
                                    text: {
                                        var d = modelData.trim();
                                        for (var i = 0; i < widgetTab.configRoot.allDetailsDefs.length; ++i)
                                            if (widgetTab.configRoot.allDetailsDefs[i].itemId === d)
                                                return widgetTab.configRoot.allDetailsDefs[i].label;
                                        return d;
                                    }
                                }
                            }
                        }
                    }
                    Button {
                        text: i18n("Configure…")
                        icon.name: "configure"
                        onClicked: widgetTab.pushSubPage()
                    }
                }
            }

            // Simple mode: simple chips preview + Configure
            Label {
                text: i18n("Simple chips:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            Item {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                implicitWidth: simplePreviewRow.implicitWidth
                implicitHeight: simplePreviewRow.implicitHeight
                RowLayout {
                    id: simplePreviewRow
                    spacing: 10
                    Flow {
                        spacing: 4
                        Layout.maximumWidth: 260
                        Repeater {
                            model: widgetTab.configRoot.cfg_widgetSimpleDetailsOrder.split(";").filter(function (t) {
                                return t.length > 0;
                            })
                            delegate: Rectangle {
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.10)
                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                border.width: 1
                                implicitWidth: simpleChipLbl.implicitWidth + 10
                                implicitHeight: simpleChipLbl.implicitHeight + 6
                                Label {
                                    id: simpleChipLbl
                                    anchors.centerIn: parent
                                    text: {
                                        var d = modelData.trim();
                                        for (var i = 0; i < widgetTab.configRoot.allSimpleDefs.length; ++i)
                                            if (widgetTab.configRoot.allSimpleDefs[i].itemId === d)
                                                return widgetTab.configRoot.allSimpleDefs[i].label;
                                        return d;
                                    }
                                }
                            }
                        }
                    }
                    Button {
                        text: i18n("Configure…")
                        icon.name: "configure"
                        onClicked: widgetTab.pushSimpleSubPage()
                    }
                }
            }

            Label {
                text: i18n("Stats items:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form2.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowStatsChips
                    onToggled: widgetTab.configRoot.cfg_simpleShowStatsChips = checked
                }
            }

            // Invisible filler row: it lets the second column take ALL spare width, so the
            // label column keeps its width when rows are shown or hidden.
            Item {
                visible: _form2.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                visible: _form2.columns === 2
                Layout.fillWidth: true
                implicitWidth: 0
                implicitHeight: 0
            }
        }

        // ── SUB-TAB 2: Forecast ───────────────────────────────────────
        GridLayout {
            id: _form3
            visible: subTabBar.currentIndex === 2
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

            // ═══════════════════════════════════════════════════════════════
            // SECTION: General
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("General")
                Layout.columnSpan: _form3.columns
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            Label {
                text: i18n("Forecast days:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            SpinBox {
                from: 3
                to: 16
                value: widgetTab.configRoot.cfg_forecastDays
                onValueModified: widgetTab.configRoot.cfg_forecastDays = value
            }
            Label {
                text: i18n("Show Today:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowToday
                    onToggled: widgetTab.configRoot.cfg_forecastShowToday = checked
                }
            }
            Label {
                text: i18n("Auto-open hourly forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    id: forecastAutoOpenSwitch
                    checked: widgetTab.configRoot.cfg_forecastAutoOpen
                    onToggled: widgetTab.configRoot.cfg_forecastAutoOpen = checked
                }
                Label {
                    text: forecastAutoOpenSwitch.checked ? i18n("Opens today's hourly forecast automatically (or the next available day)") : i18n("All days start collapsed")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    opacity: 0.7
                }
            }
            Label {
                text: i18n("Expand all days:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    id: forecastExpandAllSwitch
                    checked: widgetTab.configRoot.cfg_forecastExpandAll
                    onToggled: widgetTab.configRoot.cfg_forecastExpandAll = checked
                }
                Label {
                    text: forecastExpandAllSwitch.checked ? i18n("All days show hourly forecast when opening the tab") : i18n("Only the clicked day expands")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    opacity: 0.7
                }
            }
            Label {
                text: i18n("Show past weather info for today:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    id: forecastShowPastHoursSwitch
                    checked: widgetTab.configRoot.cfg_forecastShowPastHours
                    onToggled: widgetTab.configRoot.cfg_forecastShowPastHours = checked
                }
                Label {
                    text: forecastShowPastHoursSwitch.checked ? i18n("Already-passed hours for today stay in place, greyed out, instead of being removed") : i18n("Already-passed hours are removed from today's hourly forecast")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    opacity: 0.7
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Daily Forecast Settings
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Daily Forecast Settings")
                Layout.columnSpan: _form3.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
            }

            Label {
                text: i18n("Daily layout:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            ComboBox {
                textRole: "text"
                readonly property var _opts: [
                    {
                        text: i18n("Standard"),
                        value: "rows"
                    },
                    {
                        text: i18n("Graphs"),
                        value: "graphs"
                    }
                ]
                model: _opts
                currentIndex: {
                    var v = widgetTab.configRoot.cfg_forecastLayout;
                    for (var i = 0; i < _opts.length; i++)
                        if (_opts[i].value === v)
                            return i;
                    return 0;
                }
                onActivated: widgetTab.configRoot.cfg_forecastLayout = _opts[currentIndex].value
            }
            Label {
                text: i18n("Show in daily forecast:")
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            StatSwitches {
                id: dailyStats
                // in the second column, next to the title (the switches wrap only when the page is too narrow)
                Layout.fillWidth: true
                cfgRoot: widgetTab.configRoot
                orderProp: "cfg_forecastGraphOrder"
                colorsProp: "cfg_forecastGraphColors"
                reorderable: widgetTab.configRoot.cfg_forecastLayout === "graphs"
                defs: [
                    {
                        // high and low are ONE row of the order list, each with its own color
                        key: "temp",
                        label: i18n("Temperature low/high"),
                        cfg: "cfg_forecastShowTemp",
                        graphsOnly: true,
                        missingFirst: true,
                        colors: [
                            {
                                key: "temphigh",
                                label: i18n("Temperature high"),
                                defaultColor: "#ef5350"
                            },
                            {
                                key: "templow",
                                label: i18n("Temperature low"),
                                defaultColor: "#42a5f5"
                            }
                        ]
                    },
                    {
                        key: "wind",
                        label: i18n("Wind"),
                        cfg: "cfg_forecastShowWind",
                        defaultColor: "#66bb6a"
                    },
                    {
                        key: "pressure",
                        label: i18n("Pressure"),
                        cfg: "cfg_forecastShowPressure",
                        defaultColor: "#ab47bc"
                    },
                    {
                        key: "kp",
                        label: i18n("Kp index/G"),
                        cfg: "cfg_forecastShowKpIndex",
                        defaultColor: "#ffa726"
                    },
                    {
                        key: "uv",
                        label: i18n("UV index"),
                        cfg: "cfg_forecastShowUvIndex",
                        defaultColor: "#ffb300"
                    },
                    {
                        key: "precip",
                        label: i18n("Precip sum"),
                        cfg: "cfg_forecastShowPrecipSum",
                        defaultColor: "#26c6da"
                    },
                    {
                        key: "vis",
                        label: i18n("Visibility"),
                        cfg: "cfg_forecastShowVisibility",
                        defaultColor: "#90a4ae"
                    }
                ]
            }
            // title + drag-and-drop list (only with the "Graphs" layout and at least one graph switched on)
            Label {
                text: i18n("Daily graph order:")
                visible: dailyOrder.visible
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            GraphOrderList {
                id: dailyOrder
                stats: dailyStats
                Layout.fillWidth: true
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Hourly Forecast Settings
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Hourly Forecast Settings")
                Layout.columnSpan: _form3.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Label {
                text: i18n("Hourly layout:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            ComboBox {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                textRole: "text"
                readonly property var _opts: [
                    {
                        text: i18n("Cards"),
                        value: "cards"
                    },
                    {
                        text: i18n("Strip"),
                        value: "strip"
                    },
                    {
                        text: i18n("Graphs"),
                        value: "graphs"
                    }
                ]
                model: _opts
                currentIndex: {
                    var v = widgetTab.configRoot.cfg_forecastHourlyLayout;
                    for (var i = 0; i < _opts.length; i++)
                        if (_opts[i].value === v)
                            return i;
                    return 0;
                }
                onActivated: widgetTab.configRoot.cfg_forecastHourlyLayout = _opts[currentIndex].value
            }
            Label {
                text: i18n("Sunrise/sunset markers:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_forecastShowSunEvents
                    onToggled: widgetTab.configRoot.cfg_forecastShowSunEvents = checked
                }
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode !== "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
            }

            Label {
                text: i18n("Show in hourly forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            StatSwitches {
                id: hourlyStats
                // in the second column, next to the title (the switches wrap only when the page is too narrow)
                visible: widgetTab.configRoot.cfg_widgetLayoutMode !== "simple"
                Layout.fillWidth: true
                cfgRoot: widgetTab.configRoot
                orderProp: "cfg_forecastHourlyGraphOrder"
                colorsProp: "cfg_forecastHourlyGraphColors"
                reorderable: widgetTab.configRoot.cfg_forecastHourlyLayout === "graphs"
                defs: [
                    {
                        // the temperature and the chance of precipitation are ONE row of the order list
                        // (the chance of precipitation is drawn with the temperature graph), each with its own color
                        key: "temp",
                        label: i18n("Temperature and chance of precip."),
                        cfg: "cfg_forecastHourlyShowTemp",
                        graphsOnly: true,
                        missingFirst: true,
                        colors: [
                            {
                                key: "temp",
                                label: i18n("Temperature"),
                                defaultColor: "#ef5350"
                            },
                            {
                                key: "precipprob",
                                label: i18n("Chance of precip."),
                                defaultColor: "#26c6da",
                                cfg: "cfg_forecastHourlyShowPrecipProb"
                            }
                        ]
                    },
                    {
                        // a switch only: its color is the second color of the temperature row
                        key: "precipprob",
                        label: i18n("Chance of precip."),
                        cfg: "cfg_forecastHourlyShowPrecipProb",
                        orderable: false
                    },
                    {
                        key: "wind",
                        label: i18n("Wind"),
                        cfg: "cfg_forecastHourlyShowWind",
                        defaultColor: "#66bb6a"
                    },
                    {
                        key: "pressure",
                        label: i18n("Pressure"),
                        cfg: "cfg_forecastHourlyShowPressure",
                        defaultColor: "#ab47bc"
                    },
                    {
                        key: "kp",
                        label: i18n("Kp index/G"),
                        cfg: "cfg_forecastHourlyShowKpIndex",
                        defaultColor: "#ffa726"
                    },
                    {
                        key: "uv",
                        label: i18n("UV index"),
                        cfg: "cfg_forecastHourlyShowUvIndex",
                        defaultColor: "#ffb300"
                    },
                    {
                        key: "precip",
                        label: i18n("Precip sum"),
                        cfg: "cfg_forecastHourlyShowPrecipSum",
                        defaultColor: "#26c6da"
                    },
                    {
                        key: "vis",
                        label: i18n("Visibility"),
                        cfg: "cfg_forecastHourlyShowVisibility",
                        defaultColor: "#90a4ae"
                    }
                ]
            }
            // title + drag-and-drop list (only with the "Graphs" layout and at least one graph switched on)
            Label {
                text: i18n("Hourly graph order:")
                visible: hourlyOrder.visible
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing
            }
            GraphOrderList {
                id: hourlyOrder
                stats: hourlyStats
                Layout.fillWidth: true
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode === "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            // ═══════════════════════════════════════════════════════════════
            // SECTION: Simple widget
            // ═══════════════════════════════════════════════════════════════
            SectionHeader {
                title: i18n("Simple Widget")
                Layout.columnSpan: _form3.columns
                Layout.topMargin: Kirigami.Units.largeSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            Item {
                // empty label cell: keeps the control in the second column
                visible: _form3.columns === 2 && (widgetTab.configRoot.cfg_widgetLayoutMode === "simple")
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                Layout.preferredHeight: Kirigami.Units.smallSpacing
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
            }

            Label {
                text: i18n("Forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowForecast
                    onToggled: widgetTab.configRoot.cfg_simpleShowForecast = checked
                }
            }

            Label {
                text: i18n("Compass in forecast:")
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.topMargin: _form3.columns === 1 ? Kirigami.Units.smallSpacing * 2 : 0
            }
            RowLayout {
                visible: widgetTab.configRoot.cfg_widgetLayoutMode === "simple"
                enabled: widgetTab.configRoot.cfg_simpleShowForecast
                Switch {
                    checked: widgetTab.configRoot.cfg_simpleShowForecastCompass
                    onToggled: widgetTab.configRoot.cfg_simpleShowForecastCompass = checked
                }
            }

            // Invisible filler row: it lets the second column take ALL spare width, so the
            // label column keeps its width when rows are shown or hidden.
            Item {
                visible: _form3.columns === 2
                implicitWidth: 0
                implicitHeight: 0
            }
            Item {
                visible: _form3.columns === 2
                Layout.fillWidth: true
                implicitWidth: 0
                implicitHeight: 0
            }
        }
    }
}
