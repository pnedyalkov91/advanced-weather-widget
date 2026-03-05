#!/usr/bin/env bash
set -euo pipefail

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASEDIR"

DOMAIN="plasma_applet_org.kde.plasma.advanced-weather-widget"  # сложи твоя домейн
OUTDIR="translate"
POT="$OUTDIR/template.pot"

mkdir -p "$OUTDIR"

# 1) Събира всички QML/JS файлове
FILES=$(find . \
  -path './translate' -prune -o \
  -path './.git' -prune -o \
  -type f \( -name '*.qml' -o -name '*.js' \) -print)

# 2) Генерира POT от i18n() calls
xgettext \
  --from-code=UTF-8 \
  --add-comments=TRANSLATORS \
  --package-name="$DOMAIN" \
  --msgid-bugs-address="https://github.com/pnedyalkov91/advanced-weather-widget/issues" \
  --keyword=i18n \
  --keyword=i18nc:1c,2 \
  --keyword=i18np:1,2 \
  --keyword=i18ncp:1c,2,3 \
  --keyword=i18nd:1,2 \
  --keyword=i18ndc:1,2c,3 \
  --keyword=i18ndp:1,2,3 \
  --keyword=i18ndcp:1,2c,3,4 \
  --language=JavaScript \
  --output="$POT" \
  $FILES

echo "Updated: $POT"
