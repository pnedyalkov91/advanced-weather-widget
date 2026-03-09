#!/bin/sh
# Build .mo files from translate/*.po
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$DIR/.."
DOMAIN="plasma_applet_org.kde.plasma.advanced-weather-widget"

for POFILE in "$DIR"/*.po; do
  [ -f "$POFILE" ] || continue
  LOCALE="$(basename "$POFILE" .po)"
  OUTDIR="$PACKAGE_ROOT/contents/locale/$LOCALE/LC_MESSAGES"
  mkdir -p "$OUTDIR"
  msgfmt "$POFILE" -o "$OUTDIR/$DOMAIN.mo"
  echo "Built $OUTDIR/$DOMAIN.mo"
done
