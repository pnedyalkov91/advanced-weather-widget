import QtQuick
import org.kde.kirigami as Kirigami

// The little arrow of a list.
Canvas {
    id: chevron
    property color stroke: Kirigami.Theme.disabledTextColor
    implicitWidth: 10
    implicitHeight: 6
    onStrokeChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        c.strokeStyle = stroke;
        c.lineWidth = 1.5;
        c.lineCap = "round";
        c.lineJoin = "round";
        c.beginPath();
        c.moveTo(1, 1);
        c.lineTo(5, 5);
        c.lineTo(9, 1);
        c.stroke();
    }
}
