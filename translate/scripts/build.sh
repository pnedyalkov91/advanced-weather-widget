#!/bin/sh
# Build .mo files from translate/*.po
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRANSLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_ROOT="$(cd "$TRANSLATE_DIR/.." && pwd)"
DOMAIN="plasma_applet_org.kde.plasma.advanced-weather-widget"

for POFILE in "$TRANSLATE_DIR"/*.po; do
  [ -f "$POFILE" ] || continue
  LOCALE="$(basename "$POFILE" .po)"
  OUTDIR="$PACKAGE_ROOT/contents/locale/$LOCALE/LC_MESSAGES"
  mkdir -p "$OUTDIR"
  msgfmt "$POFILE" -o "$OUTDIR/$DOMAIN.mo"
  echo "Built $OUTDIR/$DOMAIN.mo"
done
