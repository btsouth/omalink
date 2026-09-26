#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT
mkdir "$temp_dir/tools" "$temp_dir/files"
export OMALINK_FILE_TEST="$temp_dir"
export PATH="$temp_dir/tools:$PATH"

cat >"$temp_dir/tools/busctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >>"$OMALINK_FILE_TEST/all.calls"
[[ $1 == --user && $2 == --auto-start=no ]]
if [[ ${3:-} == --json=short ]]; then shift 3; else shift 2; fi
operation=$1
[[ $2 == -- ]]
shift 2
if [[ $operation == call && $4 == GetNameOwner ]]; then
  [[ $1 == org.freedesktop.DBus && $5 == s && $6 == org.kde.kdeconnect ]]
  [[ ${SCENARIO:-} != backend_missing ]] || exit 1
  if [[ -e $OMALINK_FILE_TEST/owner.read && ${SCENARIO:-} == owner_changed ]]; then
    printf '%s\n' '{"type":"s","data":[":1.999"]}'
  else
    printf '%s\n' '{"type":"s","data":[":1.42"]}'
  fi
  touch "$OMALINK_FILE_TEST/owner.read"
  exit 0
fi
[[ $1 == :1.42 ]]
if [[ $operation == get-property ]]; then
  [[ $2 == /modules/kdeconnect/devices/abc123 && $3 == org.kde.kdeconnect.device ]]
  case ${SCENARIO:-} in
    status_failure) printf '%s\n' '{"type":"b","data":true}'; exit 1 ;;
    malformed) printf '%s\n' '{"type":"b","data":"true"}'; exit 0 ;;
    flood) head -c 1000000 /dev/zero | tr '\0' 'F'; exit 0 ;;
    slow) sleep 30; exit 0 ;;
  esac
  if [[ $4 == isPaired && ${SCENARIO:-} == unpaired ]] || [[ $4 == isReachable && ${SCENARIO:-} == offline ]]; then
    printf '%s\n' '{"type":"b","data":false}'
  else
    printf '%s\n' '{"type":"b","data":true}'
  fi
  exit 0
fi
[[ $operation == call ]]
if [[ $4 == hasPlugin ]]; then
  [[ $2 == /modules/kdeconnect/devices/abc123 && $3 == org.kde.kdeconnect.device && $5 == s && $6 == kdeconnect_share ]]
  if [[ ${SCENARIO:-} == no_share ]]; then
    printf '%s\n' '{"type":"b","data":[false]}'
  else
    printf '%s\n' '{"type":"b","data":[true]}'
  fi
  exit 0
fi
[[ $2 == /modules/kdeconnect/devices/abc123/share && $3 == org.kde.kdeconnect.device.share && $4 == shareUrls && $5 == as ]]
shift 5
count=$1
shift
[[ $# == "$count" ]]
printf '%s\0' "$@" >>"$OMALINK_FILE_TEST/dispatch.args"
printf 'dispatch\n' >>"$OMALINK_FILE_TEST/dispatch.count"
case ${SCENARIO:-} in
  dispatch_failure) exit 1 ;;
  dispatch_slow) sleep 30; exit 0 ;;
esac
EOF
chmod +x "$temp_dir/tools/busctl"

helper="$project_dir/bin/omalink-files"
reset_calls() { rm -f -- "$temp_dir/"{all.calls,owner.read,dispatch.args,dispatch.count}; }
run_expect() {
  local exit_code="$1" state="$2" code="$3" actual=0
  shift 3
  output="$("$helper" "$@")" || actual=$?
  [[ $actual == "$exit_code" ]] || { printf 'Unexpected exit %s: %s\n' "$actual" "$output" >&2; exit 1; }
  jq -e --arg state "$state" --arg code "$code" '.state == $state and .code == $code and (.count | type == "number")' >/dev/null <<<"$output"
}
ordinary="$temp_dir/files/example.txt"
printf 'example\n' >"$ordinary"
reset_calls
run_expect 2 failed invalid_device '../abc123' "$ordinary"
run_expect 2 failed invalid_device '--address=tcp:host=malicious' "$ordinary"
run_expect 2 failed file_count abc123
run_expect 2 failed invalid_path abc123 relative.txt
run_expect 2 failed unreadable_file abc123 "$temp_dir/files"
run_expect 2 failed unreadable_file abc123 "$temp_dir/no-file"
mkfifo "$temp_dir/fifo"
run_expect 2 failed unreadable_file abc123 "$temp_dir/fifo"
touch "$temp_dir/unreadable"
chmod 000 "$temp_dir/unreadable"
run_expect 2 failed unreadable_file abc123 "$temp_dir/unreadable"
run_expect 2 failed duplicate_file abc123 "$ordinary" "$ordinary"
invalid_utf8="$temp_dir/files/"$'invalid-\xff'
touch "$invalid_utf8"
run_expect 2 failed invalid_path abc123 "$invalid_utf8"
truncate -s 8589934593 "$temp_dir/large"
run_expect 2 failed size_limit abc123 "$temp_dir/large"
truncate -s 4294967297 "$temp_dir/large-a"
truncate -s 4294967297 "$temp_dir/large-b"
run_expect 2 failed size_limit abc123 "$temp_dir/large-a" "$temp_dir/large-b"
paths=()
for index in {1..33}; do touch "$temp_dir/files/$index"; paths+=("$temp_dir/files/$index"); done
run_expect 2 failed file_count abc123 "${paths[@]}"
[[ ! -e $temp_dir/all.calls ]]

# Exact byte round trip for spaces, shell metacharacters, Unicode and newlines.
# None of these names can become an option, shell command, URI fragment or query.
weird="$temp_dir/files/"$'--address=evil résumé #?% $(touch SENTINEL) `echo bad`\n'
touch "$weird"
run_expect 0 accepted accepted abc123 "$ordinary" "$weird"
jq -e '.ok == true and .count == 2' >/dev/null <<<"$output"
[[ $(wc -l <"$temp_dir/dispatch.count") == 1 && ! -e SENTINEL ]]
mapfile -d '' -t urls <"$temp_dir/dispatch.args"
expected="$(jq -nr --arg path "$weird" '"file://" + ($path | @uri | gsub("%2F"; "/"))')"
[[ ${urls[1]} == "$expected" && ${urls[1]} == *'%0A' && ${urls[1]} == *'%23%3F%25'* ]]
[[ ${urls[0]} == "file://$ordinary" ]]

for scenario in backend_missing unpaired offline status_failure malformed flood no_share owner_changed; do
  reset_calls
  export SCENARIO="$scenario"
  case "$scenario" in
    backend_missing) code=backend_unavailable ;;
    unpaired | offline) code="$scenario" ;;
    no_share) code=share_unavailable ;;
    owner_changed) code=backend_changed ;;
    *) code=status_unavailable ;;
  esac
  run_expect 1 failed "$code" abc123 "$ordinary"
  [[ ! -e $temp_dir/dispatch.count ]]
done
reset_calls
export SCENARIO=slow
started=$SECONDS
run_expect 1 failed status_unavailable abc123 "$ordinary"
(( SECONDS - started < 9 ))
[[ ! -e $temp_dir/dispatch.count ]]
for scenario in dispatch_failure dispatch_slow; do
  reset_calls
  export SCENARIO="$scenario"
  started=$SECONDS
  run_expect 1 unconfirmed dispatch_unconfirmed abc123 "$ordinary"
  (( SECONDS - started < 14 ))
  [[ $(wc -l <"$temp_dir/dispatch.count") == 1 ]]
  jq -e '.ok == false' >/dev/null <<<"$output"
done
unset SCENARIO
reset_calls
run_expect 0 accepted accepted abc123 "${paths[@]:0:32}"
jq -e '.count == 32' >/dev/null <<<"$output"
[[ $(wc -l <"$temp_dir/dispatch.count") == 1 ]]
reset_calls
truncate -s 8589934592 "$temp_dir/boundary"
run_expect 0 accepted accepted abc123 "$temp_dir/boundary"
ln -s "$ordinary" "$temp_dir/link"
run_expect 0 accepted accepted abc123 "$temp_dir/link"
printf '%s\n' 'File sharing helper tests passed'
