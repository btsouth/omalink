#!/usr/bin/env bash

# Static checks on the QML this plugin ships, for the two mistakes that are load
# errors or security holes in the shell rather than lint warnings:
#
#   - a property added to an element that does not have it (textFormat on Qt
#     Quick Controls' TextField, for example, stops the window from loading);
#   - phone data reaching a Text without textFormat: Text.PlainText, or an Image
#     without the shared gate and a bounded sourceSize.
#
# The checks walk element blocks by indentation, so a wrapped binding, a space
# before the colon, or a new property line cannot slip past them.

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

blocks() {
  # One line per element block, innermost included: file, first line number, and
  # the block text with newlines folded to | so a multi-line binding stays
  # readable by one read. A stack tracks nesting, because the block that matters
  # (a Text, an Image) is usually not the outermost one.
  awk '
    {
      match($0, /^[[:space:]]*/); indent = RLENGTH
      is_open  = ($0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\{[[:space:]]*$/)
      is_close = ($0 ~ /^[[:space:]]*\}[[:space:]]*$/)
      if (is_open) {
        depth++
        starts[depth] = NR
        indents[depth] = indent
        texts[depth] = ""
      }
      for (d = 1; d <= depth; d++) texts[d] = texts[d] $0 "|"
      if (is_close && depth > 0 && indent <= indents[depth]) {
        printf "%s\t%s\t%s\n", FILENAME, starts[depth], texts[depth]
        depth--
      }
    }
  ' "$1"
}

owner_of() {
  local file="$1" line="$2"
  awk -v target="$line" '
    NR <= target && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\{/ { owner = $0 }
    NR == target { print owner }
  ' "$file" | tr -d '[:space:]'
}

fail() {
  echo "$1" >&2
  status=1
}

# textFormat exists on Text, TextArea and TextEdit, and on nothing else here. The
# owner is the nearest enclosing element, not the whole block, because outer
# elements contain these lines too.
while IFS= read -r match; do
  file="${match%%:*}"
  remainder="${match#*:}"
  line="${remainder%%:*}"
  owner="$(owner_of "$project_dir/$file" "$line")"
  case $owner in
    Text{ | TextArea{ | TextEdit{ ) ;;
    *) fail "textFormat on an element that has no such property: $file:$line (${owner:-unknown owner})" ;;
  esac
done < <(cd "$project_dir" && grep -rn 'textFormat:' --include='*.qml' . | sed 's|^\./||')

for file in "$project_dir"/*.qml; do
  name="${file##*/}"
  gated_names="$(sed -n 's/.*property [A-Za-z]* \([A-Za-z]*\) *: *Model\.\(localImageSource\|thumbnailUri\).*/\1/p' "$file")"
  declared_names="$(sed -n 's/.*property [A-Za-z]* \([A-Za-z]*\) *:.*/\1/p' "$file")"

  while IFS=$'\t' read -r _ line text; do
    [[ -n $text ]] || continue
    owner="$(printf '%s' "${text%%|*}" | tr -d '[:space:]')"

    # A Text showing phone data has to say so.
    if [[ $owner == Text{ ]] && printf '%s' "$text" | grep -qE 'text[[:space:]]*:.*(Model\.|modelData\.|media\.|root\.viewerStatus|root\.notifReplyTitle|root\.shareDeviceName|phone\.statusText)'; then
      printf '%s' "$text" | grep -q 'textFormat: Text.PlainText' ||
        fail "Text showing phone data without textFormat: $name:$line"
    fi

    if [[ $owner == Image{ ]] && printf '%s' "$text" | grep -qE 'source[[:space:]]*:'; then
      source_line="$(printf '%s' "$text" | tr '|' '\n' | grep -E '^[[:space:]]*source[[:space:]]*:' | head -n 1)"

      # Raw phone data must not be read here unless the gate produced it.
      if printf '%s' "$source_line" | grep -qE '(modelData\.|phone\.|root\.viewerPath)'; then
        printf '%s' "$source_line" | grep -qE 'Model\.(localImageSource|thumbnailUri)' ||
          fail "Image.source reads phone data directly: $name:$line"
      fi

      # Any declared property used as the source has to be built by the gate.
      if ! printf '%s' "$source_line" | grep -qE 'Model\.(localImageSource|thumbnailUri)'; then
        for candidate in $declared_names; do
          case $source_line in
            *"$candidate"*) ;;
            *) continue ;;
          esac
          case $gated_names in
            *"$candidate"*) ;;
            *) fail "Image.source uses $candidate, which the gate does not build: $name:$line" ;;
          esac
        done
      fi

      # And the decode has to be bounded.
      printf '%s' "$text" | grep -q 'sourceSize\.' ||
        fail "Image from phone data without a sourceSize bound: $name:$line"
    fi
  done < <(blocks "$file")

  # An imperative source assignment would bypass the binding entirely.
  if grep -nE '\.source[[:space:]]*=' "$file" >/dev/null; then
    fail "Image.source assigned imperatively in $name"
  fi

  # The phone's player is read through Model.mediaState, which is never null:
  # reading it straight off the device is what filled the journal with
  # "Cannot read property 'volume' of null".
  if grep -nE 'modelData\.media\.' "$file" >/dev/null; then
    fail "reads the phone's player without Model.mediaState in $name"
  fi
done

[[ $status == 0 ]] || exit 1
echo "qml tests passed"
