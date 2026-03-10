#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_FILE="translation-status.md"

shopt -s nullglob

pot_files=( ./*.pot )
po_files=( ./*.po )

if [[ ${#pot_files[@]} -eq 0 ]]; then
    echo "Error: No .pot file found in: $SCRIPT_DIR" >&2
    exit 1
fi

if [[ ${#pot_files[@]} -gt 1 ]]; then
    echo "Error: Multiple .pot files found in: $SCRIPT_DIR" >&2
    echo "Please keep only one .pot file in the folder." >&2
    exit 1
fi

if [[ ${#po_files[@]} -eq 0 ]]; then
    echo "Error: No .po files found in: $SCRIPT_DIR" >&2
    exit 1
fi

TEMPLATE_FILE="${pot_files[0]}"

count_entries() {
    local file="$1"
    awk '
        /^#~/ { next }                 # skip obsolete entries
        /^msgid "/ {
            if ($0 != "msgid \"\"") {  # skip header
                count++
            }
        }
        END { print count + 0 }
    ' "$file"
}

count_translated() {
    local file="$1"
    awk '
        BEGIN {
            in_msgid = 0
            in_msgstr = 0
            msgid = ""
            msgstr = ""
            obsolete = 0
            fuzzy = 0
        }

        function flush_entry() {
            if (obsolete) {
                reset_entry()
                return
            }

            if (msgid != "" && msgid != "\"\"") {
                if (!fuzzy && msgstr != "") {
                    translated++
                }
            }
            reset_entry()
        }

        function reset_entry() {
            in_msgid = 0
            in_msgstr = 0
            msgid = ""
            msgstr = ""
            obsolete = 0
            fuzzy = 0
        }

        /^#~/ {
            obsolete = 1
            next
        }

        /^#,.*fuzzy/ {
            fuzzy = 1
            next
        }

        /^msgid / {
            if (msgid != "" || msgstr != "") {
                flush_entry()
            }
            in_msgid = 1
            in_msgstr = 0
            msgid = $0
            sub(/^msgid /, "", msgid)
            next
        }

        /^msgstr / {
            in_msgid = 0
            in_msgstr = 1
            msgstr = $0
            sub(/^msgstr /, "", msgstr)
            next
        }

        /^"/ {
            if (in_msgid) {
                msgid = msgid $0
            } else if (in_msgstr) {
                msgstr = msgstr $0
            }
            next
        }

        /^$/ {
            if (msgid != "" || msgstr != "") {
                flush_entry()
            }
            next
        }

        END {
            if (msgid != "" || msgstr != "") {
                flush_entry()
            }
            print translated + 0
        }
    ' "$file"
}

TOTAL_LINES="$(count_entries "$TEMPLATE_FILE")"

if [[ "$TOTAL_LINES" -le 0 ]]; then
    echo "Error: Could not determine total lines from template: $TEMPLATE_FILE" >&2
    exit 1
fi

{
    echo "## Status"
    echo
    echo "|  Locale  |  Lines  | % Done|"
    echo "|----------|---------|-------|"
    printf "| %-8s | %7d | %5s |\n" "Template" "$TOTAL_LINES" ""
} > "$OUTPUT_FILE"

IFS=$'\n' sorted_po_files=($(printf '%s\n' "${po_files[@]}" | sort))
unset IFS

for po_file in "${sorted_po_files[@]}"; do
    locale="$(basename "$po_file" .po)"
    translated="$(count_translated "$po_file")"
    percent=$(( translated * 100 / TOTAL_LINES ))

    printf "| %-8s | %3d/%-3d | %4d%% |\n" \
        "$locale" "$translated" "$TOTAL_LINES" "$percent" >> "$OUTPUT_FILE"
done

echo "Generated: $SCRIPT_DIR/$OUTPUT_FILE"
