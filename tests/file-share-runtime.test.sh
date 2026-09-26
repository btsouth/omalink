#!/usr/bin/env bash
# Real component, private omabox desktop, synthetic helper only.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
cp "$project_dir/FileShare.qml" "$project_dir/FileShareModel.js" "$work/"
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
export OMALINK_FILE_UI_LOG="$work/requests"
cat >"$work/bin/omalink-files" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
device=$1
shift
jq -cn --arg device "$device" --args '{device:$device,paths:$ARGS.positional}' -- "$@" >>"$OMALINK_FILE_UI_LOG"
sleep 0.3
case "$device" in
  malformed) printf 'not json'; exit 0 ;;
  failure) jq -cn --argjson count "$#" '{ok:false,state:"failed",code:"offline",count:$count}'; exit 1 ;;
  *) jq -cn --argjson count "$#" '{ok:true,state:"accepted",code:"accepted",count:$count}' ;;
esac
EOF
chmod +x "$work/bin/omalink-files"
cp "$project_dir/tests/file-share-runtime.qml" "$work/shell.qml"
timeout --kill-after=2s 20s qs -p "$work" >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
cat "$work/log"
grep -q 'omalink file share runtime tests passed' "$work/log"
if grep -Eq 'ReferenceError|TypeError|SyntaxError|Unable to assign|FAIL:' "$work/log"; then exit 1; fi
jq -se 'length == 3 and .[0].device == "old" and .[0].paths == ["/tmp/a #\n"] and .[1].device == "malformed" and .[2].device == "failure"' "$work/requests"
