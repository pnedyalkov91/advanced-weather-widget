import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "mapIcons.js" as MapIcons

// An icon of the Weather Map from contents/icons/weathermap/ (name without
// .svg). The white drawings (mask) take the color of the theme's text, so
// they read on a light theme too; the colored ones stay as drawn.
// With a layerKey (radar, wind, snow…), the icon follows the map's icon
// theme instead (cfg weatherMapIconTheme), name and mask then unused.
Kirigami.Icon {
    id: wm
    property string name
    property bool mask: false
    property string layerKey
    property color tint: Kirigami.Theme.textColor
    readonly property var themed: layerKey !== ""
        ? MapIcons.resolve(layerKey, Plasmoid.configuration.weatherMapIconTheme || "weathermap", Math.max(width, height), Qt.resolvedUrl("../../../icons/"))
        : null
    readonly property bool _mask: themed ? themed.mask : mask
    source: themed ? themed.source : Qt.resolvedUrl("../../../icons/weathermap/" + name + ".svg")
    fallback: themed && themed.fallback !== "" ? themed.fallback : "unknown"
    isMask: _mask
    color: _mask ? tint : "transparent"
    roundToIconSize: false
    scale: themed ? themed.scale : 1
}
