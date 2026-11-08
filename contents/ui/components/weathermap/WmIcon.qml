import QtQuick
import org.kde.kirigami as Kirigami

// An icon of the Weather Map from contents/icons/weathermap/ (name without
// .svg). The white drawings (mask) take the color of the theme's text, so
// they read on a light theme too; the colored ones stay as drawn.
Kirigami.Icon {
    property string name
    property bool mask: false
    property color tint: Kirigami.Theme.textColor
    source: Qt.resolvedUrl("../../../icons/weathermap/" + name + ".svg")
    isMask: mask
    color: mask ? tint : "transparent"
    roundToIconSize: false
}
