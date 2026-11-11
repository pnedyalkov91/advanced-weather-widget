import QtQuick
import org.kde.plasma.components as PlasmaComponents
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../../js/configUtils.js" as ConfigUtils

// The stack of the Weather Maps' layers in its popup, top first: a line
// a layer, its drag handle then its switch. A line dragged by its handle
// floats over the list while the others make room for it; dropped, the
// new order is given by orderPicked(). saved: weatherMapLayerOrder;
// disabled: the ids switched off (weatherMapDisabledLayers). The radar
// always shows.
ListView {
    id: stackList
    property bool ownLook: false     // the widget's own small switches
    property string saved
    property var disabled: []
    property var labels: ({})
    signal orderPicked(string json)
    signal layerToggled(string id, bool on)
    property string _written: ""

    function isOn(id) {
        return id === "radar" || disabled.indexOf(id) < 0;
    }
    function reload() {
        stackModel.clear();
        ConfigUtils.weatherStackOrder(saved).forEach(function (id) { stackModel.append({ lid: id }); });
    }
    function save() {
        var order = [];
        for (var i = 0; i < stackModel.count; i++)
            order.push(stackModel.get(i).lid);
        _written = JSON.stringify(order);
        orderPicked(_written);
    }

    implicitHeight: contentHeight
    interactive: false
    model: ListModel { id: stackModel }
    Component.onCompleted: reload()
    onSavedChanged: if (saved !== _written) reload()
    moveDisplaced: Transition {
        YAnimator { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
    }

    // No required properties: the handle reads the delegate's index from
    // its context, which Qt leaves out when a delegate has some.
    delegate: Item {
        id: stackRow
        width: stackList.width
        implicitHeight: stackLine.implicitHeight
        // The line itself, a child of the delegate: the handle lifts it out
        // of the list while it is dragged, then puts it back.
        Rectangle {
            id: stackLine
            objectName: "line-" + model.lid
            width: stackRow.width
            implicitHeight: lineLayout.implicitHeight + 4
            radius: 3
            color: dragHandle.dragActive ? Kirigami.Theme.alternateBackgroundColor : "transparent"
            border.color: dragHandle.dragActive ? Kirigami.Theme.highlightColor : "transparent"
            RowLayout {
                id: lineLayout
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                Kirigami.ListItemDragHandle {
                    id: dragHandle
                    objectName: "handle-" + model.lid
                    listItem: stackLine
                    listView: stackList
                    onMoveRequested: function (oldIndex, newIndex) { stackModel.move(oldIndex, newIndex, 1); }
                    onDropped: stackList.save()
                }
                MapSwitch {
                    own: stackList.ownLook
                    Layout.fillWidth: true
                    text: stackList.labels[model.lid] || model.lid || ""
                    enabled: model.lid !== "radar"
                    checked: stackList.isOn(model.lid)
                    onToggled: {
                        stackList.layerToggled(model.lid, checked);
                        checked = Qt.binding(function () { return stackList.isOn(model.lid); });
                    }
                }
            }
        }
    }
}
