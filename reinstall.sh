#!/bin/sh
# Reinstall the Advanced Weather Widget applet and restart Plasma, for the dev loop.
# Use this after changing widget QML/JS. (The separate C++ calendar plugin under
# plugin/ only needs plugin/install.sh when its .cpp/.h change.)
set -eu

here="$(cd "$(dirname "$0")" && pwd)"

# Install from a CLEAN staging copy that holds only the applet's own files
# (metadata.json + contents/, plus LICENSE/README for good manners). Installing the
# repo root directly dragged the whole tree into the package - including plugin/,
# which carries its OWN metadata.json for the calendar plugin (no KPackageStructure,
# not a Plasma/Applet). kpackagetool6 walks the package for "metadata" and can
# resolve that nested file instead of the root one, so `--remove`/`--upgrade` then
# fail with: KPackageStructure ... does not match requested format "Plasma/Applet".
# Staging keeps the packaged applet self-contained and that error away for good.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT INT TERM

cp "$here/metadata.json" "$stage/"
cp -r "$here/contents" "$stage/"
[ -f "$here/LICENSE" ] && cp "$here/LICENSE" "$stage/" || true
[ -f "$here/README.md" ] && cp "$here/README.md" "$stage/" || true

# --upgrade if already installed, --install otherwise - so the first run also works.
if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -q "org.kde.plasma.advanced-weather-widget"; then
    kpackagetool6 --type Plasma/Applet --upgrade "$stage"
else
    kpackagetool6 --type Plasma/Applet --install "$stage"
fi

# Drop the stale QML cache so the new code is actually picked up.
rm -rf "$HOME/.cache/plasmashell/qmlcache"

# Restart the shell so the running applet reloads.
systemctl --user restart plasma-plasmashell

echo "Reinstalled and Plasma restarted."
