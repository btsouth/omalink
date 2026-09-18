#!/usr/bin/env bash

# Guards the QML properties this plugin adds. textFormat exists on Text, TextArea
# and TextEdit, but not on TextField, so adding it to the wrong element is a load
# error in the shell rather than a lint warning. And every Image.source that can
# hold phone data has to come from Model.localImageSource or Model.thumbnailUri,
# which is where the scheme check, the URI encoding and the size cap live.

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

owner_of() {
  local file="$1" line="$2"
  awk -v target="$line" '
    NR <= target && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\{/ { owner = $0 }
    NR == target { print owner }
  ' "$project_dir/$file" | tr -d '[:space:]'
}

while IFS= read -r match; do
  file="${match%%:*}"
  remainder="${match#*:}"
  line="${remainder%%:*}"
  owner="$(owner_of "$file" "$line")"
  case $owner in
    Text{ | TextArea{ | TextEdit{ ) ;;
    *)
      echo "textFormat on an element that has no such property: $file:$line (${owner:-unknown owner})" >&2
      status=1
      ;;
  esac
done < <(cd "$project_dir" && grep -rn "textFormat:" --include="*.qml" . | sed 's|^\./||')

for file in "$project_dir"/*.qml; do
  name="${file##*/}"
  gated="$(sed -n 's/.*property [A-Za-z]* \([A-Za-z]*\) *: *Model\.\(localImageSource\|thumbnailUri\).*/\1/p' "$file")"
  while IFS= read -r match; do
    line="${match%%:*}"
    source_line="${match#*:}"
    allowed=0
    case $source_line in
      *'Model.localImageSource'* | *'Model.thumbnailUri'* | *'source: ""'*) allowed=1 ;;
    esac
    for candidate in $gated; do
      case $source_line in
        *"$candidate"*) allowed=1 ;;
      esac
    done
    if (( allowed == 0 )); then
      echo "Image.source is not gated by Model.localImageSource: $name:$line ($(echo "$source_line" | sed 's/^[[:space:]]*//'))" >&2
      status=1
    fi
  done < <(grep -n "^[[:space:]]*source:" "$file" | sed 's/^[[:space:]]*//')
done

[[ $status == 0 ]] || exit 1
echo "qml tests passed"
