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

pragma ComponentBehavior: Bound

/**
 * WeatherIcon.qml - Unified weather icon renderer
 *
 * Renders a weather icon with automatic fallback:
 *   1. KDE system icon (if type === "kde")
 *   2. Bundled SVG fallback (if svgFallback is set and KDE icon missing)
 *   3. Wi-font glyph (if type === "wi", for compact panel display)
 *
 * Usage (new simplified API):
 *   WeatherIcon {
 *       iconType: "kde"              // "kde" | "svg" | "wi"
 *       iconSource: "thermometer"    // KDE icon name, SVG URL, or wi-font glyph
 *       svgFallback: "file:///..."   // optional bundled SVG fallback URL
 *       iconSize: 22
 *       isMask: false                // true for monochrome symbolic SVGs
 *   }
 *
 * Or with iconResolver.js:
 *   WeatherIcon {
 *       iconInfo: IconResolver.resolve("humidity", 22, iconsBaseDir, "symbolic")
 *       iconSize: 22
 *   }
 */

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "../js/iconResolver.js" as IconResolver

Item {
    id: weatherIcon

    // ── Shorthand: set from iconResolver.js result object ─────────────────
    /** Pass the result of IconResolver.resolve() directly */
    property var iconInfo: null

    // ── Derived properties - reactively track iconInfo ─────────────────
    // These are always in sync with iconInfo via QML bindings (no
    // imperative onChanged handler needed).  When iconInfo is null the
    // defaults produce an empty/invisible state.
    readonly property string _infoType: iconInfo ? String(iconInfo.type || "") : ""
    readonly property string _infoSource: iconInfo ? String(iconInfo.source || "") : ""
    readonly property string _infoFallback: iconInfo ? String(iconInfo.svgFallback || "") : ""
    readonly property bool _infoMask: iconInfo ? (iconInfo.isMask === true) : false

    // ── Individual properties (can also be set directly) ──────────────────
    /** Icon type: "kde" (system icon), "svg" (file URL), "wi" (wi-font glyph) */
    property string iconType: _infoType

    /** The icon source: KDE icon name, SVG file URL, or wi-font glyph char */
    property string iconSource: _infoSource

    /** Pixel size for the icon */
    property int iconSize: 22

    /** Bundled SVG fallback URL - used when KDE icon is not found */
    property string svgFallback: _infoFallback

    /** Whether to render the SVG as a monochrome mask (symbolic theme) */
    property bool isMask: _infoMask

    /** Optional icon colour override (defaults to theme text colour) */
    property color iconColor: Kirigami.Theme.textColor

    /** Static (non-animated) glow behind the icon - a blurred copy of the
      * icon in its own colours.  Follows the global config toggle by
      * default; can be overridden per instance. */
    property bool glowEnabled: Plasmoid.configuration && Plasmoid.configuration.iconGlowEnabled === true

    /** Glow strength 0.1-1.0 - drives the halo's opacity, brightness, AND
      * reach (blurMax/pad below) - all three scale with it, not just
      * brightness/opacity, so the slider produces an actually visible
      * difference rather than a barely-perceptible brightness nudge on an
      * already-faint effect. */
    property real glowIntensity: (Plasmoid.configuration && Plasmoid.configuration.iconGlowIntensity !== undefined) ? Plasmoid.configuration.iconGlowIntensity : 0.85

    /** Whether the glow may bleed past the icon's own box. The full halo
      * (widget popup) spreads outward beyond iconSize and needs an
      * unclipped ancestor chain to paint into. Panel rows sit under
      * clip:true ancestors for marquee/scroll behaviour, so glowBleed:false
      * is used there - the glow is contained entirely within the icon's
      * existing iconSize box instead, which never gets clipped no matter
      * what the ancestors do. */
    property bool glowBleed: true

    /** Contained mode needs somewhere inside the box for the halo to be
      * visible: a same-size layer directly behind an opaque icon is
      * completely hidden with nothing showing around it - verified by
      * direct pixel sampling: a same-box glow measured as indistinguishable
      * from background regardless of intensity. So instead of requesting
      * extra space, the visible icon content is rendered slightly smaller
      * than the box (shrinkScale) when contained, leaving a real margin -
      * inside the box that's already reserved by the panel layout - for
      * the glow to occupy. Only takes effect when the glow is actually on
      * and contained; a plain icon is unaffected. */
    readonly property real _contentScale: (glowEnabled && !glowBleed) ? 0.78 : 1.0
    readonly property int _contentSize: Math.max(1, Math.round(iconSize * _contentScale))

    // MultiEffect never reports an implicit size of its own - verified by
    // direct measurement, implicitWidth/Height read back as 0 even with
    // autoPaddingEnabled - so relying on a Loader/effect to size itself
    // renders a 0×0 item (i.e. nothing at all). The padded box has to be
    // computed and assigned explicitly. Bleed mode's pad also scales with
    // glowIntensity (0.3-1.0× of the max reach) so higher intensity looks
    // like a visibly bigger, bolder halo, not just a brighter one.
    // Contained mode's pad stays fixed to the shrink margin above - that
    // margin is the hard ceiling the panel layout allows regardless of
    // intensity, so only blur/brightness/opacity flex with it there.
    //
    // NOTE on scale: measured directly - the glow's actual visible falloff
    // extends roughly 2x past the nominal blurMax value, not 1x. A blurMax
    // of iconSize*0.6 (as this briefly shipped) produces a halo that visibly
    // reaches ~2.3x the icon's own diameter - the oversized "zoom" bloom.
    // iconSize*0.1 measured out to a clean, proportionate ~25px halo past a
    // 120px icon's true edge instead.
    readonly property int _glowPad: glowBleed ? Math.max(3, Math.round(iconSize * 0.1 * (0.3 + 0.7 * glowIntensity))) : Math.max(1, Math.round((iconSize - _contentSize) / 2))
    readonly property int _glowBoxSize: _contentSize + _glowPad * 2

    // ── Wi-font specific (only needed for "wi" type) ──────────────────────
    /** The loaded wi-font family name (from FontLoader.font.family) */
    property string wiFontFamily: ""

    /** Whether the wi-font FontLoader is ready */
    property bool wiFontReady: false

    // ── Size ──────────────────────────────────────────────────────────────
    implicitWidth: iconSize
    implicitHeight: iconSize
    width: iconSize
    height: iconSize
    // The bleeding halo spreads past the icon bounds, so clipping must be
    // off for it. Contained mode never exceeds this item's own box (see
    // _contentScale above), so it doesn't need clip touched at all.
    clip: iconType !== "wi" && !glowEnabled

    visible: iconSource.length > 0

    // The bundled artwork URL this icon should draw: the icon itself for
    // type "svg", or the fallback behind a KDE theme name.
    readonly property string _bundledSrc: iconType === "svg" ? iconSource : svgFallback

    // True for a real file reference (file:///..., qrc:/..., or an absolute
    // path). Anything else - a bare "wi-humidity"-style name - must never be
    // drawn as bundled artwork: handing it to the icon machinery is what makes
    // Qt walk the whole theme chain for a file that cannot be in any theme.
    readonly property bool _bundledIsFile: _bundledSrc.indexOf("://") > 0 || _bundledSrc.indexOf("qrc:/") === 0 || _bundledSrc.charAt(0) === "/"

    // ── Single loaded branch ──────────────────────────────────────────────
    // Exactly one element is instantiated per icon (wi-font Text, one Image
    // for bundled artwork, or one Kirigami.Icon for a KDE theme name).  Every
    // Kirigami.Icon carries a PlasmaTheme object that re-syncs on each window
    // expose, and pays icon-theme lookups on polish - with hundreds of icons
    // in the forecast/details delegates, keeping five dormant Icon siblings
    // per WeatherIcon froze the GUI thread on popup open.
    //
    // Bundled artwork is drawn with a plain Image, NOT Kirigami.Icon: it ships
    // in the package as ordinary files, so it has no business in the icon
    // theme's lookup path, and Qt's loader neither caches theme misses nor
    // stops at the first one (it also retries every dash-stripped name,
    // wi-time-3 -> wi-time -> wi, in every theme directory).  An Image reads
    // the file once and the decoded pixmap is shared per URL+size across all
    // delegates.  The bundled fallback behind a KDE name is only created when
    // that name actually misses - and once a name has missed, later icons skip
    // the doomed theme lookup altogether.
    Loader {
        id: iconLoader
        width: weatherIcon._contentSize
        height: weatherIcon._contentSize
        anchors.centerIn: parent
        sourceComponent: {
            if (weatherIcon.iconType === "wi")
                return weatherIcon.wiFontReady ? wiComp : null;
            if (weatherIcon.iconSource.length === 0)
                return null;
            if (weatherIcon.iconType === "svg")
                return weatherIcon._bundledIsFile ? svgComp : iconComp;
            if (weatherIcon.iconType === "kde") {
                if (weatherIcon.svgFallback.length > 0 && weatherIcon._bundledIsFile && IconResolver.isKdeIconMissing(weatherIcon.iconSource))
                    return svgComp;
                return iconComp;
            }
            return null;
        }
    }

    // ── Static glow ───────────────────────────────────────────────────────
    // A blurred, slightly brightened copy of the icon drawn behind it.
    // Purely static - no animation.  The MultiEffect (and its offscreen
    // texture) only exists while the option is enabled, so the default
    // configuration pays nothing.
    //
    // width/height are set explicitly to _glowBoxSize (verified necessary:
    // MultiEffect's implicit size measures as 0 regardless of
    // autoPaddingEnabled, so without an explicit size this Loader renders
    // at 0×0 and the glow is invisible). autoPaddingEnabled:true then
    // renders the source at native scale, centered within that explicit
    // box, with blur bleeding into the padding rather than the source
    // being stretched to fill it - verified by pixel sampling.
    Loader {
        width: weatherIcon._glowBoxSize
        height: weatherIcon._glowBoxSize
        anchors.centerIn: iconLoader
        z: -1
        active: weatherIcon.glowEnabled && iconLoader.item !== null
        sourceComponent: MultiEffect {
            source: iconLoader
            autoPaddingEnabled: true
            blurEnabled: true
            blur: 0.5 + 0.5 * weatherIcon.glowIntensity
            blurMax: weatherIcon._glowPad
            brightness: 0.3 * weatherIcon.glowIntensity
            saturation: 0.4
            opacity: 0.3 + 0.7 * weatherIcon.glowIntensity
        }
    }

    // ── Wi-font glyph ─────────────────────────────────────────────────────
    Component {
        id: wiComp
        Text {
            text: weatherIcon.iconSource
            font.family: weatherIcon.wiFontFamily
            font.pixelSize: Math.round(weatherIcon._contentSize * 0.88)
            color: weatherIcon.iconColor
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── Bundled SVG artwork (a plain file - never the icon theme) ─────────
    // Symbolic artwork is black (fill="currentColor", which Qt renders as the
    // default colour) and is tinted to iconColor on the GPU.  MultiEffect's
    // colorization multiplies the tint by the pixel's luminance, so a black
    // source needs brightness 1.0 first (premultiplied: rgb += a, which keeps
    // the alpha shape and turns the glyph white) for the tint to come out as
    // the plain iconColor.  Coloured themes (flat-color, 3d-oxygen, meteocons)
    // skip the layer entirely and draw as-is.
    //
    // Rasterised at 2x the logical size so it stays crisp on HiDPI; the pixmap
    // cache keys on URL + size, so every delegate showing the same icon at the
    // same size shares one decoded texture.
    Component {
        id: svgComp
        Image {
            source: weatherIcon._bundledSrc
            sourceSize: Qt.size(Math.max(1, Math.round(weatherIcon._contentSize * 2)), Math.max(1, Math.round(weatherIcon._contentSize * 2)))
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            cache: true
            asynchronous: false
            layer.enabled: weatherIcon.isMask && status === Image.Ready
            layer.effect: MultiEffect {
                brightness: 1.0
                colorization: 1.0
                colorizationColor: weatherIcon.iconColor
            }
        }
    }

    // ── KDE system icon (theme name) ──────────────────────────────────────
    // Only reached for type "kde" (or an "svg" source that is not a file
    // reference, which keeps the old behaviour for such oddities).
    Component {
        id: iconComp
        Kirigami.Icon {
            id: primaryIcon
            source: weatherIcon.iconSource
            isMask: weatherIcon.isMask
            color: weatherIcon.isMask ? weatherIcon.iconColor : "transparent"
            fallback: weatherIcon.iconType === "kde" ? (weatherIcon.svgFallback.length > 0 ? "" : (weatherIcon.isMask ? "dialog-question-symbolic" : "dialog-question")) : "unknown"

            // Remember a KDE name the theme does not have, so the next icon
            // asking for it goes straight to the bundled artwork instead of
            // repeating a lookup Qt will not cache.  Same Error-not-!valid
            // gate as the fallback Loader below.  Only recorded when there is
            // a bundled fallback to take over.
            onStatusChanged: {
                if (status === Kirigami.Icon.Error && weatherIcon.iconType === "kde" && weatherIcon.svgFallback.length > 0)
                    IconResolver.markKdeIconMissing(weatherIcon.iconSource);
            }

            // Bundled SVG fallback - only exists when the KDE icon is missing.
            // Gate on status === Error, not !valid: a failed theme lookup still
            // reports valid=true (placeholder machinery), and Error is only set
            // after the lookup finishes, so no transient fallback gets built
            // while the primary icon is still loading.
            Loader {
                anchors.fill: parent
                active: weatherIcon.iconType === "kde" && weatherIcon.svgFallback.length > 0 && weatherIcon._bundledIsFile && primaryIcon.status === Kirigami.Icon.Error
                sourceComponent: svgComp
            }
        }
    }
}
