#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/translate"
POT_FILE="$OUT_DIR/template.pot"
TMP_FILES="$OUT_DIR/.i18n_files.txt"
PACKAGE_NAME="Advanced Weather Widget"
BUGS_URL="https://github.com/pnedyalkov91/advanced-weather-widget/issues"
mkdir -p "$OUT_DIR"
cd "$ROOT_DIR"
command -v xgettext  >/dev/null 2>&1 || { echo "xgettext not found";  exit 1; }
command -v msgmerge  >/dev/null 2>&1 || { echo "msgmerge not found";  exit 1; }
echo "Collecting translatable files..."
find . \
  \( -path "./.git" -o -path "./translate" -o -path "./build" -o -path "./dist" -o -path "./node_modules" \) -prune -o \
  -type f \( -name "*.qml" -o -name "*.js" \) -print | sort > "$TMP_FILES"
if [ ! -s "$TMP_FILES" ]; then
  echo "No QML/JS files found."
  exit 1
fi
echo "Generating POT file..."
xgettext \
  --from-code=UTF-8 \
  --language=JavaScript \
  --package-name="$PACKAGE_NAME" \
  --msgid-bugs-address="$BUGS_URL" \
  --add-comments=TRANSLATORS \
  --sort-output \
  --no-wrap \
  --keyword=i18n \
  --keyword=i18nc:1c,2 \
  --keyword=i18np:1,2 \
  --keyword=i18ncp:1c,2,3 \
  --keyword=xi18n \
  --keyword=xi18nc:1c,2 \
  --keyword=I18N_NOOP \
  --files-from="$TMP_FILES" \
  --output="$POT_FILE"
rm -f "$TMP_FILES"
echo "POT updated: $POT_FILE"
shopt -s nullglob
PO_FILES=("$OUT_DIR"/*.po)
if [ ${#PO_FILES[@]} -gt 0 ]; then
  echo "Updating PO files..."
  for po in "${PO_FILES[@]}"; do
    echo "  -> $(basename "$po")"
    msgmerge --update --backup=none --no-wrap "$po" "$POT_FILE"
  done
else
  echo "No .po files found in $OUT_DIR"
fi
echo "Done."
