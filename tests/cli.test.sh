#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

cat >"$temp_dir/kdeconnect-cli" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --list-available ]]; then
  if [[ -n ${OMALINK_TEST_EXTRA_DEVICE:-} ]]; then
    printf '%s\n' 'abc123 Pixel 9' 'def456 Galaxy S25' '../bad Injected'
  else
    printf '%s\n' 'abc123 Pixel 9' 'def456 Galaxy S25'
  fi
  exit 0
fi
if [[ ${1:-} == --device && ${3:-} == --ring ]]; then
  [[ ${2:-} == abc123 ]]
  exit
fi
if [[ ${1:-} == --device && ${3:-} == --send-clipboard ]]; then
  [[ ${2:-} == abc123 ]]
  exit
fi
if [[ ${1:-} == --device && ${3:-} == --share-text ]]; then
  [[ ${2:-} == abc123 && ${4:-} == "hello phone" ]]
  exit
fi
if [[ ${1:-} == --device && ${3:-} == --share ]]; then
  [[ ${2:-} == abc123 && ${4:-} == "https://omalink.app" ]]
  exit
fi
if [[ ${1:-} == --device && ${3:-} == --send-sms ]]; then
  [[ ${2:-} == abc123 && ${4:-} == "New message" && ${5:-} == --destination && ${6:-} == +15550000001 ]]
  exit
fi
exit 1
EOF
chmod +x "$temp_dir/kdeconnect-cli"

cat >"$temp_dir/busctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$0.all.log"
if [[ " $* " == *" replyToConversation "* || " $* " == *" sendReply "* || " $* " == *" requestAttachmentFile "* ]]; then
  exit 0
fi
if [[ " $* " == *" monitor "* ]]; then
  if [[ -n ${OMALINK_TEST_FLOOD:-} ]]; then
    head -c 20000000 /dev/zero | tr '\0' 'F'
  fi
  if [[ -n ${OMALINK_TEST_HUGE_BODY:-} ]]; then
    bigbody="$(head -c 20000 /dev/zero | tr '\0' 'B')"
    printf '{"type":"signal","interface":"org.kde.kdeconnect.device.conversations","member":"conversationUpdated","payload":{"data":[{"data":[1,"%s",[["+155****0001"]],1,1,0,7,10,-1,[]]}]}}\n' "$bigbody"
  fi
  if [[ -n ${OMALINK_TEST_MANY_MESSAGES:-} ]]; then
    for index in $(seq 1 300); do
      printf '{"type":"signal","interface":"org.kde.kdeconnect.device.conversations","member":"conversationUpdated","payload":{"data":[{"data":[1,"body %s",[["+155****0001"]],%s,1,0,7,10,-1,[]]}]}}\n' \
        "$index" "$index"
    done
  fi
  printf '{"type":"signal","interface":"org.kde.kdeconnect.device.conversations","member":"attachmentReceived","payload":{"data":["%s","PART_1.jpeg"]}}\n' "$OMALINK_TEST_ATTACHMENT"
  sleep 3
  exit 0
fi
if [[ " $* " == *" sendAction "* ]]; then echo "sendAction $*" >>"$0.log"; exit 0; fi
if [[ " $* " == *" Set ssv "* ]]; then echo "setVolume $*" >>"$0.log"; exit 0; fi
if [[ " $* " == *"mprisremote seek "* ]]; then echo "seek $*" >>"$0.log"; exit 0; fi
case "${*: -1}" in
  charge) if [[ -n ${OMALINK_TEST_JUNK:-} ]]; then printf '%s\n' 'i lots'; else printf '%s\n' 'i 71'; fi ;;
  isCharging) if [[ -n ${OMALINK_TEST_JUNK:-} ]]; then printf '%s\n' 'b maybe'; else printf '%s\n' 'b false'; fi ;;
  cellularNetworkStrength) printf '%s\n' 'i 3' ;;
  cellularNetworkType) printf '%s\n' 's "5G"' ;;
  dismiss) echo "dismiss $*" >>"$0.log"; exit 0 ;;
  requestAllConversationThreads) : >"$0.requested"; exit 0 ;;
  appName)
    printf 'read\n' >>"$0.appname.log"
    if [[ -n ${OMALINK_TEST_LONG_NAMES:-} ]]; then
      long="$(head -c 100000 /dev/zero | tr '\0' 'A')"
      printf '{"type":"s","data":"%s"}\n' "$long"
      exit 0
    fi
    if [[ " $* " == *"notif.3"* || " $* " == *"notif.10"* ]]; then
      printf '%s\n' '{"type":"s","data":"Visual Voicemail"}'
    elif [[ " $* " == *"notif.4"* || " $* " == *"notif.11"* ]]; then
      printf '%s\n' '{"type":"s","data":"Authenticator"}'
    else
      printf '%s\n' '{"type":"s","data":"Messages"}'
    fi
    ;;
  internalId)
    if [[ " $* " == *"notif.3"* || " $* " == *"notif.10"* ]]; then
      printf '%s\n' '{"type":"s","data":"0|com.samsung.vvm|1|null|1"}'
    elif [[ " $* " == *"notif.4"* || " $* " == *"notif.11"* ]]; then
      printf '%s\n' '{"type":"s","data":"0|com.azure.authenticator|1|null|1"}'
    else
      printf '%s\n' '{"type":"s","data":"0|com.google.android.apps.messaging|1|null|1"}'
    fi
    ;;
  isConversation)
    if [[ " $* " == *"notif.3"* || " $* " == *"notif.4"* || " $* " == *"notif.9"* || " $* " == *"notif.10"* ]]; then
      printf '%s\n' '{"type":"b","data":false}'
    else
      printf '%s\n' '{"type":"b","data":true}'
    fi
    ;;
  silent)
    if [[ " $* " == *"/notifications/notif.10 "* ]]; then
      printf '%s\n' '{"type":"b","data":true}'
    else
      printf '%s\n' '{"type":"b","data":false}'
    fi
    ;;
  replyId)
    if [[ -n ${OMALINK_TEST_LONG_NAMES:-} ]]; then
      long="$(head -c 100000 /dev/zero | tr '\0' 'R')"
      printf '{"type":"s","data":"%s"}\n' "$long"
      exit 0
    fi
    printf '%s\n' '{"type":"s","data":"reply-uuid.1"}'
    ;;
  activeNotifications)
    if [[ -n ${OMALINK_TEST_MANY_NOTIFICATIONS:-} ]]; then
      printf '{"type":"as","data":[['
      for index in $(seq 1 300); do printf '"notif.%s",' "$index"; done
      printf '"notif.last"]]}\n'
    else
      printf '%s\n' '{"type":"as","data":[["notif.1","notif.2","notif.3","notif.4"]]}'
    fi
    ;;
  activeConversations)
    if [[ -n ${OMALINK_TEST_LONG_PREVIEW:-} ]]; then
      long="$(head -c 5000 /dev/zero | tr '\0' 'P')"
      printf '{"type":"av","data":[[{"type":"(isa(s)xiixixa(xsss))","data":[1,"%s",[["+155****0001"]],2000,1,0,7,10,-1,[]]}]]}\n' "$long"
    elif [[ -n ${OMALINK_TEST_MANY_ATTACHMENTS:-} ]]; then
      # Three chunks, because a single argument is capped at 128 KB.
      chunk="$(head -c 100000 /dev/zero | tr '\0' 'A')"
      printf '{"type":"av","data":[[{"type":"(isa(s)xiixixa(xsss))","data":[1,"Many",[["+155****0001"]],2000,1,0,7,10,-1,['
      for index in $(seq 1 40); do
        [[ $index == 1 ]] || printf ','
        printf '[%s,"image/jpeg","%s%s%s","PART_%s.jpeg"]' "$index" "$chunk" "$chunk" "$chunk" "$index"
      done
      printf ']]}]]}\n'
    elif [[ -n ${OMALINK_TEST_MANY_THREADS:-} ]]; then
      printf '{"type":"av","data":[['
      for index in $(seq 1 300); do
        printf '{"type":"(isa(s)xiixixa(xsss))","data":[1,"Thread %s",[["+155****%04d"]],%s,1,0,%s,10,-1,[]]},' \
          "$index" "$index" "$index" "$index"
      done
      printf '{"type":"(isa(s)xiixixa(xsss))","data":[1,"Newest",[["+155****0001"]],9999,1,0,999,10,-1,[]]}]]}\n'
    elif [[ -n ${COLD_CONVERSATION_CACHE:-} && ! -e "$0.requested" ]]; then
      printf '%s\n' '{"type":"av","data":[[]]}'
    else
      printf '%s\n' '{"type":"av","data":[[{"type":"(isa(s)xiixixa(xsss))","data":[1,"Newest",[["+15550000001"]],2000,1,0,7,10,-1,[[42,"image/jpeg","VGh1bWI=","PART_1.jpeg"]]]},{"type":"(isa(s)xiixixa(xsss))","data":[1,"Older",[["+15550000002"]],1000,2,1,8,11,-1,[]]}]]}'
    fi
    ;;
  playerList)
    if [[ " $* " == *"/def456/"* ]]; then
      printf '%s\n' '{"type":"as","data":[]}'
    else
      printf '%s\n' '{"type":"as","data":["Apple Music"]}'
    fi
    ;;
  title)
    if [[ -n ${OMALINK_TEST_LONG_TITLE:-} ]]; then
      long="$(head -c 5000 /dev/zero | tr '\0' 'T')"
      printf '{"type":"s","data":"%s"}\n' "$long"
    elif [[ " $* " == *"/notif.9 "* ]]; then
      printf '%s\n' '{"type":"s","data":"<img src=\"http://192.168.1.1/x.png\">Hi"}'
    elif [[ " $* " == *"/notifications/"* ]]; then
      printf '%s\n' '{"type":"s","data":"Phone title"}'
    else
      printf '%s\n' 's "Overthinking"'
    fi
    ;;
  text)
    if [[ -n ${OMALINK_TEST_LONG_TITLE:-} ]]; then
      long="$(head -c 20000 /dev/zero | tr '\0' 'X')"
      printf '{"type":"s","data":"%s"}\n' "$long"
    elif [[ " $* " == *"/notif.9 "* ]]; then
      printf '%s\n' '{"type":"s","data":"<b>Bold</b> & Co"}'
    else
      printf '%s\n' '{"type":"s","data":"Phone text"}'
    fi
    ;;
  artist) printf '%s\n' 's "usedcvnt"' ;;
  album) printf '%s\n' 's "Ultraviolet"' ;;
  player) printf '%s\n' 's "Apple Music"' ;;
  localAlbumArtUrl) printf '%s\n' "s \"$OMALINK_TEST_ALBUM_ART\"" ;;
  volume) if [[ -n ${OMALINK_TEST_JUNK:-} ]]; then printf '%s\n' 'i lots'; else printf '%s\n' 'i 40'; fi ;;
  length) printf '%s\n' 'i 144023' ;;
  position) printf '%s\n' 'i 94844' ;;
  isPlaying) if [[ -n ${OMALINK_TEST_JUNK:-} ]]; then printf '%s\n' 'b perhaps'; else printf '%s\n' 'b true'; fi ;;
  canSeek) printf '%s\n' 'b true' ;;
  iconPath)
    if [[ " $* " == *"/notif.1 "* ]]; then
      printf '%s\n' "{\"type\":\"s\",\"data\":\"$OMALINK_TEST_ICON_PATH\"}"
    elif [[ " $* " == *"/notif.2 "* ]]; then
      printf '%s\n' '{"type":"s","data":"/etc/hostname"}'
    else
      printf '%s\n' '{"type":"s","data":""}'
    fi
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$temp_dir/busctl"

cat >"$temp_dir/dbus-monitor" <<'EOF'
#!/usr/bin/env bash
printf 'signal time=1.0 sender=:1.5 -> destination=(null destination) serial=9 path=/modules/kdeconnect/devices/abc123/notifications; interface=org.kde.kdeconnect.device.notifications; member=notificationPosted\n'
printf '   string "notif.9"\n'
printf 'signal time=1.1 sender=:1.5 -> destination=(null destination) serial=10 path=/modules/kdeconnect/devices/abc123/notifications; interface=org.kde.kdeconnect.device.notifications; member=notificationPosted\n'
printf '   string "notif.10"\n'
printf 'signal time=1.2 sender=:1.5 -> destination=(null destination) serial=11 path=/modules/kdeconnect/devices/abc123/notifications; interface=org.kde.kdeconnect.device.notifications; member=notificationPosted\n'
printf '   string "notif.11"\n'
EOF
chmod +x "$temp_dir/dbus-monitor"

cat >"$temp_dir/notify-send" <<'EOF'
#!/usr/bin/env bash
echo "notify $*" >>"$0.log"
echo default
EOF
chmod +x "$temp_dir/notify-send"

cat >"$temp_dir/qs" <<'EOF'
#!/usr/bin/env bash
echo "qs $*" >>"$0.log"
EOF
chmod +x "$temp_dir/qs"

cat >"$temp_dir/xdg-open" <<'EOF'
#!/usr/bin/env bash
echo "open $*" >>"$0.log"
EOF
chmod +x "$temp_dir/xdg-open"

cat >"$temp_dir/xdg-mime" <<'EOF'
#!/usr/bin/env bash
# The desktop's classifier is what the open gate consults, so it is stubbed the
# way the other tools are: one name reports a parameterised mime type, and a
# switch makes the classifier unavailable so the content scan is exercised alone.
if [[ -n ${OMALINK_TEST_XDG_MIME_FAIL:-} ]]; then
  exit 1
fi
case ${*: -1} in
  *param.html) printf 'text/html; charset=utf-8\n'; exit 0 ;;
esac
exec /usr/bin/xdg-mime "$@"
EOF
chmod +x "$temp_dir/xdg-mime"

cat >"$temp_dir/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '[{"name":"DP-9","focused":true},{"name":"HDMI-1","focused":false}]\n'
EOF
chmod +x "$temp_dir/hyprctl"

contact_dir="$temp_dir/data/kpeoplevcard/kdeconnect-abc123"
mkdir -p "$contact_dir"
cat >"$contact_dir/contact.vcf" <<'EOF'
BEGIN:VCARD
VERSION:2.1
FN:Alex Rivera
TEL;CELL:+15550000001
END:VCARD
EOF

# Phone-supplied paths are only accepted from KDE Connect's own directories,
# so the fixtures live where the daemon and its plugins would write them.
export XDG_CACHE_HOME="$temp_dir/cache"
export TMPDIR="$temp_dir/tmp"
cache_root="$temp_dir/cache/kdeconnect.daemon"
art_dir="$cache_root/kdeconnect/albumart"
icon_dir="$temp_dir/tmp/kdeconnect_${USER:-$(id -un)}"
attachment_dir="$cache_root/Pixel 9"
mkdir -p "$art_dir" "$icon_dir" "$attachment_dir"
printf '\xff\xd8\xff\xe0jpegbytes' >"$art_dir/art.jpg"
printf '\xff\xd8\xff\xe0jpegbytes' >"$art_dir/art with space.jpg"
printf '\x89PNG\r\n\x1a\npngbytes' >"$icon_dir/abc123"
{ printf '\x89PNG\r\n\x1a\n'; head -c 2097152 /dev/zero; } >"$icon_dir/bigicon"
printf '<svg xmlns="http://www.w3.org/2000/svg"><image href="http://192.168.1.1/x.png"/></svg>' >"$art_dir/evil.svg"
{ printf '\x89PNG\r\n\x1a\n'; head -c 8388601 /dev/zero; } >"$art_dir/big.png"
{ printf '\x89PNG\r\n\x1a\n'; head -c 8388600 /dev/zero; } >"$art_dir/at-limit.png"
: >"$art_dir/empty.png"
ln -s "$temp_dir/outside.png" "$art_dir/link.jpg"
printf '\x89PNG\r\n\x1a\npngbytes' >"$temp_dir/hardlink-source.png"
ln -f "$temp_dir/hardlink-source.png" "$art_dir/hardlinked.png"
ln -s "$temp_dir" "$art_dir/escape"
printf '\x89PNG\r\n\x1a\npngbytes' >"$temp_dir/outside.png"

mkfifo "$art_dir/pipe"
attachment_fixture="$attachment_dir/PART_1.jpeg"
printf 'jpegbytes' >"$attachment_fixture"
# Attachments the phone named: text that claims to be a photo, and one far over
# any sane size cap (sparse, so creating it costs nothing).
printf 'this is text the phone called a photo' >"$cache_root/notreally.png"
truncate -s 73400320 "$cache_root/large-attachment.bin"
: >"$cache_root/empty-attachment.bin"
export OMALINK_TEST_ALBUM_ART="file://$art_dir/art.jpg"
export OMALINK_TEST_ICON_PATH="$icon_dir/abc123"
export OMALINK_TEST_ATTACHMENT="$attachment_fixture"

long_name_dir="$temp_dir/data-longname/kpeoplevcard/kdeconnect-abc123"
mkdir -p "$long_name_dir"
{
  printf 'BEGIN:VCARD\nVERSION:2.1\nFN:'
  head -c 300 /dev/zero | tr '\0' 'N'
  printf '\nTEL;CELL:+155****4321\nEND:VCARD\n'
} >"$long_name_dir/contact.vcf"
many_contacts_dir="$temp_dir/data-many/kpeoplevcard/kdeconnect-abc123"
mkdir -p "$many_contacts_dir"
{
  for index in $(seq 1 2100); do
    printf 'BEGIN:VCARD\nVERSION:2.1\nFN:Person %s\nTEL;CELL:+1555%06d\nEND:VCARD\n' "$index" "$index"
  done
} >"$many_contacts_dir/many.vcf"

status="$(PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status)"
junk_status="$(OMALINK_TEST_JUNK=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status)"
jq -e '.devices[0].battery.charge == null and .devices[0].battery.charging == false
  and .devices[0].media.volume == 0 and .devices[0].media.isPlaying == false
  and (.devices[0].notifications | length) == 3' <<<"$junk_status" >/dev/null
injected_status="$(OMALINK_TEST_EXTRA_DEVICE=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status)"
jq -e '(.devices | length) == 2 and ([.devices[].id] | index("../bad")) == null' <<<"$injected_status" >/dev/null
many_status="$(OMALINK_TEST_MANY_NOTIFICATIONS=1 PATH="$temp_dir:/usr/bin" timeout 60 "$project_dir/bin/omalink" status)"
jq -e '(.devices[0].notifications | length) == 25' <<<"$many_status" >/dev/null
many_filtered="$(OMALINK_TEST_MANY_NOTIFICATIONS=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" --notify-apps nomatch status)"
jq -e '(.devices[0].notifications | length) == 0' <<<"$many_filtered" >/dev/null
: >"$temp_dir/busctl.appname.log"
OMALINK_TEST_MANY_NOTIFICATIONS=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" --notify-apps nomatch status >/dev/null
# The stub reports two devices, so the read cap is 100 per device.
[[ "$(wc -l <"$temp_dir/busctl.appname.log")" == 200 ]]
: >"$temp_dir/busctl.appname.log"
OMALINK_TEST_MANY_NOTIFICATIONS=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status >/dev/null
[[ "$(wc -l <"$temp_dir/busctl.appname.log")" -le 60 ]]
jq -e '.installed == true and (.devices | length) == 2 and .devices[0].name == "Pixel 9" and .devices[0].battery.charge == 71 and .devices[0].connectivity.type == "5G" and (.devices[0].notifications | length) == 3' <<<"$status" >/dev/null
voicemail_status="$(PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" --notify-apps "voicemail" status)"
jq -e '(.devices[0].notifications | length) == 1 and .devices[0].notifications[0].appName == "Visual Voicemail"' <<<"$voicemail_status" >/dev/null
all_status="$(PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" --notify-apps "" status)"
jq -e '(.devices[0].notifications | length) == 4' <<<"$all_status" >/dev/null
jq -e --arg art "$art_dir/art.jpg" '.devices[0].media == {player: "Apple Music", title: "Overthinking", artist: "usedcvnt", album: "Ultraviolet", volume: 40, length: 144023, position: 94844, isPlaying: true, canSeek: true, albumArt: $art, players: ["Apple Music"]}' <<<"$status" >/dev/null
jq -e '.devices[1].media == null' <<<"$status" >/dev/null
jq -e --arg icon "$icon_dir/abc123" '.devices[0].notifications[0].iconPath == $icon and .devices[0].notifications[1].iconPath == ""' <<<"$status" >/dev/null
jq -e '.devices[0].notifications[0] | .title == "Phone title" and .text == "Phone text" and .isConversation == true and .dismissable == false' <<<"$status" >/dev/null
if OMALINK_TEST_ICON_PATH="$icon_dir/notraster" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status | jq -r '.devices[0].notifications[0].iconPath' | grep -q .; then
  echo "a notification icon that is not an image was accepted" >&2
  exit 1
fi

# Album art and notification icons come from the phone: only local files under
# KDE Connect's directories, verified as small raster images, are accepted.
album_art_case() {
  OMALINK_TEST_ALBUM_ART="$1" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status \
    | jq -r '.devices[0].media.albumArt'
}
for rejected in \
  "http://192.168.1.1/art.jpg" \
  "https://example.com/art.jpg" \
  "data:image/png;base64,AAAA" \
  "qrc:/art.jpg" \
  "file://$temp_dir/outside.png" \
  "file://$art_dir" \
  "file://$art_dir/link.jpg" \
  "file://$art_dir/hardlinked.png" \
  "file://$art_dir/empty.png" \
  "file://$art_dir/escape/outside.png" \
  "file://$art_dir/pipe" \
  "file://$art_dir/evil.svg" \
  "file://$art_dir/big.png" \
  "file://$art_dir/../outside.png" \
  "file://$art_dir/%2e%2e/%2e%2e/outside.png" \
  "file://$art_dir/art%00.jpg" \
  "file://$art_dir/art%2.jpg" \
  "file:///dev/zero"; do
  if [[ -n "$(album_art_case "$rejected")" ]]; then
    echo "album art was accepted from $rejected" >&2
    exit 1
  fi
done
[[ "$(album_art_case "file://$art_dir/art%20with%20space.jpg")" == "$art_dir/art with space.jpg" ]]
[[ "$(album_art_case "file://$art_dir/at-limit.png")" == "$art_dir/at-limit.png" ]]
[[ "$(album_art_case "")" == "" ]]
if [[ -n "$(OMALINK_TEST_ICON_PATH="$icon_dir/bigicon" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status | jq -r '.devices[0].notifications[0].iconPath')" ]]; then
  echo "an oversized notification icon was accepted" >&2
  exit 1
fi
media="$(PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media abc123)"
jq -e '.title == "Overthinking" and .artist == "usedcvnt" and .players == ["Apple Music"]' <<<"$media" >/dev/null
[[ "$(PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media def456)" == "null" ]]
: >"$temp_dir/busctl.log"
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media-action abc123 PlayPause >/dev/null
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media-volume abc123 65 >/dev/null
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media-seek abc123 100000 >/dev/null
# Every invocation the suite made must separate its options from its arguments:
# one call site losing its -- is enough for a phone value to be read as an option.
if grep -qE '(call|get-property|monitor) org\.kde\.kdeconnect' "$temp_dir/busctl.all.log"; then
  echo "a busctl call does not separate its options from its arguments:" >&2
  grep -E '(call|get-property|monitor) org\.kde\.kdeconnect' "$temp_dir/busctl.all.log" | head -3 >&2
  exit 1
fi
if grep -q -- '--address' "$temp_dir/busctl.all.log"; then
  echo "a phone-supplied value reached busctl as an option" >&2
  exit 1
fi
grep -q 'sendAction .*PlayPause' "$temp_dir/busctl.log"
grep -q 'setVolume .*volume i 65' "$temp_dir/busctl.log"
grep -q 'seek .*i 5156' "$temp_dir/busctl.log"
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" ring abc123 >/dev/null
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" clipboard abc123 >/dev/null
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" share abc123 "hello phone" >/dev/null
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" share abc123 "https://omalink.app" >/dev/null
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" dismiss abc123 notification-1 >/dev/null
: >"$temp_dir/busctl.log"
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" dismiss-all abc123 >/dev/null
[[ "$(grep -c '/notifications/notif\.' "$temp_dir/busctl.log")" == 3 ]]
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" reply abc123 7 "Test reply" >/dev/null
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" notify-reply abc123 reply-uuid.1 "Quick reply" >/dev/null
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" sms abc123 +15550000001 "New message" >/dev/null
contacts="$(XDG_DATA_HOME="$temp_dir/data" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" contacts abc123)"
jq -e 'length == 1 and .[0].name == "Alex Rivera" and .[0].number == "+15550000001"' <<<"$contacts" >/dev/null
long_name_contacts="$(XDG_DATA_HOME="$temp_dir/data-longname" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" contacts abc123)"
jq -e 'length == 1 and (.[0].name | length) == 256' <<<"$long_name_contacts" >/dev/null
many_contacts="$(XDG_DATA_HOME="$temp_dir/data-many" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" contacts abc123)"
jq -e 'length == 2000' <<<"$many_contacts" >/dev/null
conversations="$(XDG_DATA_HOME="$temp_dir/data" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" conversations abc123)"
jq -e 'length == 2 and .[0].threadId == 7 and .[0].unread == true and .[0].names[0] == "Alex Rivera" and .[1].incoming == false' <<<"$conversations" >/dev/null
jq -e '.[0].attachments[0] == {partId: 42, mimeType: "image/jpeg", thumbnail: "VGh1bWI=", unique: "PART_1.jpeg"} and .[1].attachments == []' <<<"$conversations" >/dev/null
many_threads="$(OMALINK_TEST_MANY_THREADS=1 XDG_DATA_HOME="$temp_dir/data" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" conversations abc123)"
jq -e 'length == 200 and .[0].timestamp == 9999 and .[-1].timestamp == 102' <<<"$many_threads" >/dev/null
many_messages="$(OMALINK_TEST_MANY_MESSAGES=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" messages abc123 7)"
jq -e 'length == 200 and .[-1].body == "body 300" and .[0].body == "body 101"' <<<"$many_messages" >/dev/null
thread_messages="$(PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" messages abc123 7)"
jq -e 'length == 0' <<<"$thread_messages" >/dev/null
many_attachments="$(OMALINK_TEST_MANY_ATTACHMENTS=1 XDG_DATA_HOME="$temp_dir/data" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" conversations abc123)"
jq -e '.[0].attachmentCount == 40 and (.[0].attachments | length) == 10
  and ([.[0].attachments[].thumbnail] | all(. == ""))' <<<"$many_attachments" >/dev/null
[[ ${#many_attachments} -lt 100000 ]]
huge_body="$(OMALINK_TEST_HUGE_BODY=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" messages abc123 7)"
jq -e 'length == 1 and (.[0].body | length) == 8192' <<<"$huge_body" >/dev/null
long_preview="$(OMALINK_TEST_LONG_PREVIEW=1 XDG_DATA_HOME="$temp_dir/data" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" conversations abc123)"
jq -e '(.[0].preview | length) == 1024' <<<"$long_preview" >/dev/null
long_names="$(OMALINK_TEST_LONG_NAMES=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status)"
jq -e '(.devices[0].notifications[0].appName | length) == 256
  and (.devices[0].notifications[0].replyId | length) == 128' <<<"$long_names" >/dev/null
long_title="$(OMALINK_TEST_LONG_TITLE=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" status)"
jq -e '(.devices[0].notifications[0].title | length) == 1024
  and (.devices[0].notifications[0].text | length) == 8192' <<<"$long_title" >/dev/null
rm -f "$temp_dir/busctl.requested"
cold_conversations="$(COLD_CONVERSATION_CACHE=1 XDG_DATA_HOME="$temp_dir/data" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" conversations abc123)"
jq -e 'length == 2 and .[0].threadId == 7' <<<"$cold_conversations" >/dev/null
[[ -e "$temp_dir/busctl.requested" ]]
attachment_path="$(PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment abc123 42 PART_1.jpeg)"
image_path="$(OMALINK_TEST_ATTACHMENT="$art_dir/art.jpg" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment abc123 42 PART_1.jpeg image)"
[[ $image_path == "$art_dir/art.jpg" ]]
if OMALINK_TEST_ATTACHMENT="$cache_root/notreally.png" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment abc123 42 PART_1.jpeg image >/dev/null 2>&1; then
  echo "an attachment the phone called an image was loaded as one" >&2
  exit 1
fi
large_path="$(OMALINK_TEST_ATTACHMENT="$cache_root/large-attachment.bin" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment abc123 42 PART_1.jpeg file)"
[[ $large_path == "$cache_root/large-attachment.bin" ]]
if OMALINK_TEST_ATTACHMENT="$cache_root/empty-attachment.bin" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment abc123 42 PART_1.jpeg file >/dev/null 2>&1; then
  echo "an empty attachment was accepted" >&2
  exit 1
fi
# A phone flooding the bus must not keep the poll filling the capture for its
# whole 30 second window.
flood_start=$SECONDS
if OMALINK_TEST_FLOOD=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment abc123 42 PART_1.jpeg file >/dev/null 2>&1; then
  echo "a flooded capture was accepted" >&2
  exit 1
fi
if (( SECONDS - flood_start > 15 )); then
  echo "the attachment poll did not stop when the capture passed its cap" >&2
  exit 1
fi
# A failed jq must not skip the cleanup trap and leave the capture behind.
leftovers_before="$(find "$temp_dir/tmp" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)"
OMALINK_TEST_FLOOD=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" messages abc123 7 >/dev/null 2>&1 || true
leftovers_after="$(find "$temp_dir/tmp" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)"
if (( leftovers_after != leftovers_before )); then
  echo "a failed capture left its temporary directory behind" >&2
  exit 1
fi
[[ $attachment_path == "$attachment_fixture" ]]
if OMALINK_TEST_ATTACHMENT=/etc/hostname PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment abc123 42 PART_1.jpeg >/dev/null 2>&1; then
  echo "an attachment outside the KDE Connect directories was accepted" >&2
  exit 1
fi
saved_home="$temp_dir/home"
mkdir -p "$saved_home"
first_save="$(HOME="$saved_home" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment-save "$attachment_fixture")"
[[ $first_save == "$saved_home/Downloads/PART_1.jpeg" && -f $first_save ]]
second_save="$(HOME="$saved_home" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment-save "$attachment_fixture")"
[[ $second_save == "$saved_home/Downloads/PART_1-1.jpeg" && -f $second_save ]]
if HOME="$saved_home" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment-save "$temp_dir/outside.png" >/dev/null 2>&1; then
  echo "saving a file outside the KDE Connect directories was accepted" >&2
  exit 1
fi

# Opening an attachment hands the phone's file to the desktop. Anything that
# would run is refused, whatever it is named.
printf '\xff\xd8\xff\xe0jpegbytes' >"$cache_root/photo.jpg"
{ printf '\x7fELF'; head -c 32 /dev/zero; } >"$cache_root/disguised.jpg"
printf '[Desktop Entry]\nExec=/bin/sh\n' >"$cache_root/evil.desktop"
printf '#!/bin/sh\necho hi\n' >"$cache_root/evil.sh"
printf '<html><body><img src="http://192.168.1.1/beacon.png"></body></html>' >"$cache_root/page.html"
printf '[InternetShortcut]\nURL=http://192.168.1.1/\n' >"$cache_root/shortcut.url"
printf '<!doctype html><img src="http://192.168.1.1/beacon.png">' >"$cache_root/lower.bin"
printf 'not an image at all' >"$icon_dir/notraster"
# A page the content scan misses (it starts with an XML declaration) and one the
# mime classifier misses (a name it cannot type, so only the scan refuses it).
printf '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' >"$cache_root/xmlpage.txt"
printf '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' >"$cache_root/scanpage.txt"
printf '<html><body>x</body></html>' >"$cache_root/param.html"
printf '#!/bin/sh\necho BOOM\n' >"$cache_root/unreadable.bin"
chmod 000 "$cache_root/unreadable.bin"
: >"$temp_dir/xdg-open.log"
PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment-open "$cache_root/photo.jpg"
sleep 0.3
grep -q "open $cache_root/photo.jpg" "$temp_dir/xdg-open.log"
for refused in "$cache_root/disguised.jpg" "$cache_root/evil.desktop" "$cache_root/evil.sh" "$cache_root/unreadable.bin" "$cache_root/page.html" "$cache_root/lower.bin" "$cache_root/xmlpage.txt" "$cache_root/scanpage.txt" "$cache_root/param.html" "$cache_root/shortcut.url" "$art_dir/evil.svg" "$temp_dir/outside.png"; do
  if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment-open "$refused" >/dev/null 2>&1; then
    echo "opening $refused was accepted" >&2
    exit 1
  fi
done
# With the classifier unavailable, the content scan alone still has to refuse the
# page, and the magic check alone still has to refuse a program.
for refused_without_mime in "$cache_root/scanpage.txt" "$cache_root/disguised.jpg"; do
  if OMALINK_TEST_XDG_MIME_FAIL=1 PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment-open "$refused_without_mime" >/dev/null 2>&1; then
    echo "opening $refused_without_mime was accepted without the mime classifier" >&2
    exit 1
  fi
done
if grep -q 'evil\.\|disguised\|unreadable\|page\.html\|shortcut\|xmlpage\|scanpage\|param' "$temp_dir/xdg-open.log"; then
  echo "a refused file was handed to the desktop" >&2
  exit 1
fi
saved_page="$(HOME="$saved_home" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment-save "$cache_root/page.html")"
[[ $saved_page == "$saved_home/Downloads/page.html" && -f $saved_page ]]
if HOME="$saved_home" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment-save "$cache_root/evil.sh" >/dev/null 2>&1; then
  echo "saving a file the phone made runnable was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" dismiss '../bad' notification-1 >/dev/null 2>&1; then
  echo "invalid device id was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" reply abc123 bad "Test reply" >/dev/null 2>&1; then
  echo "invalid thread id was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" notify-reply abc123 'bad reply;id' "Quick reply" >/dev/null 2>&1; then
  echo "invalid reply id was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" attachment abc123 notanumber PART_1.jpeg >/dev/null 2>&1; then
  echo "invalid attachment part id was accepted" >&2
  exit 1
fi
# A value that looks like an option has to be rejected as an argument, not
# quietly fail later on: exit 2 is the usage rejection.
expect_usage() {
  local rc=0
  PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" "$@" >/dev/null 2>&1 || rc=$?
  if [[ $rc != 2 ]]; then
    echo "expected an argument rejection for [$*], got exit $rc" >&2
    exit 1
  fi
}
expect_usage attachment abc123 42 '--address=tcp:host=127.0.0.1,port=1'
expect_usage attachment abc123 42 '--host=attacker@evil.example'
expect_usage attachment abc123 42 '-1'
expect_usage dismiss abc123 '--user'
expect_usage notify-reply abc123 '--user' 'hi'
expect_usage ring '--user'
expect_usage clipboard '--user'
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media '../bad' >/dev/null 2>&1; then
  echo "invalid media device id was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media-action abc123 Disco >/dev/null 2>&1; then
  echo "invalid media action was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media-volume abc123 101 >/dev/null 2>&1; then
  echo "out-of-range media volume was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media-volume abc123 abc >/dev/null 2>&1; then
  echo "non-numeric media volume was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media-seek abc123 -5 >/dev/null 2>&1; then
  echo "negative media seek was accepted" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" media-seek def456 1000 >/dev/null 2>&1; then
  echo "media seek without media was accepted" >&2
  exit 1
fi

[[ "$(XDG_STATE_HOME="$temp_dir/state" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" seen)" == "{}" ]]
XDG_STATE_HOME="$temp_dir/state" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" mark-seen 7 2000 9 1500
XDG_STATE_HOME="$temp_dir/state" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" mark-seen 7 2500
jq -e '."7" == 2500 and ."9" == 1500' \
  <<<"$(XDG_STATE_HOME="$temp_dir/state" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" seen)" >/dev/null
if XDG_STATE_HOME="$temp_dir/state" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" mark-seen 7 >/dev/null 2>&1; then
  echo "odd mark-seen arguments were accepted" >&2
  exit 1
fi
if XDG_STATE_HOME="$temp_dir/state" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" mark-seen abc 100 >/dev/null 2>&1; then
  echo "invalid mark-seen thread id was accepted" >&2
  exit 1
fi

# The watcher reaps only its own orphaned dbus-monitor, never an unrelated pid.
sleep 60 &
bystander=$!
printf '%s\n' "$bystander" >"$temp_dir/omalink-watch.pid"
watch_out="$(XDG_RUNTIME_DIR="$temp_dir" XDG_CONFIG_HOME="$temp_dir/xdg" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" watch)"
if ! kill -0 "$bystander" 2>/dev/null; then
  echo "the watcher killed an unrelated process" >&2
  exit 1
fi
kill "$bystander" 2>/dev/null || true
[[ -s "$temp_dir/omalink-watch.pid" ]]
[[ $watch_out == $'posted abc123 notif.9\nposted abc123 notif.10\nposted abc123 notif.11' ]]
grep -q '^\[Event/notification\]$' "$temp_dir/xdg/kdeconnect.notifyrc"
grep -q '^Action=$' "$temp_dir/xdg/kdeconnect.notifyrc"
grep -q 'default=Open' "$temp_dir/notify-send.log"
grep -q '&lt;img src="http://192.168.1.1/x.png"&gt;' "$temp_dir/notify-send.log"
grep -q '&lt;b&gt;Bold&lt;/b&gt; &amp; Co' "$temp_dir/notify-send.log"
if grep -q 'Tom & Jerry\|& Co' "$temp_dir/notify-send.log"; then
  echo "an ampersand reached the popup unescaped" >&2
  exit 1
fi
if grep -q '<img src=' "$temp_dir/notify-send.log"; then
  echo "phone notification text reached the popup unescaped" >&2
  exit 1
fi
grep -q 'New message' "$temp_dir/notify-send.log"
[[ "$(grep -c '^notify ' "$temp_dir/notify-send.log")" == 2 ]]
grep -q 'ipc call omalink.phone.DP-9 open' "$temp_dir/qs.log"
: >"$temp_dir/notify-send.log"
quiet_out="$(XDG_RUNTIME_DIR="$temp_dir" XDG_CONFIG_HOME="$temp_dir/xdg" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" watch --popups off)"
[[ $quiet_out == $'posted abc123 notif.9\nposted abc123 notif.10\nposted abc123 notif.11' ]]
[[ ! -s "$temp_dir/notify-send.log" ]]

# An orphaned monitor is reaped, and only when it really is one.
bash -c 'exec -a dbus-monitor sleep 60' &
orphan=$!
printf '%s\n' "$orphan" >"$temp_dir/omalink-watch.pid"
: >"$temp_dir/notify-send.log"
XDG_RUNTIME_DIR="$temp_dir" XDG_CONFIG_HOME="$temp_dir/xdg" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" watch >/dev/null
if kill -0 "$orphan" 2>/dev/null; then
  echo "the watcher left its orphaned monitor running" >&2
  kill "$orphan" 2>/dev/null || true
  exit 1
fi

# A symlink planted under the watcher's names must not become a file it writes
# through, which is what a world-writable runtime directory allows.
# Two victims, because the two writes differ: the pid is written (so an empty
# target shows it) and the lock is only opened for writing (so a non-empty target
# shows the truncation). A non-empty pid target would be removed by the
# stale-reap path first and hide the guard.
: >"$temp_dir/victim-empty.txt"
printf 'keep me\n' >"$temp_dir/victim-full.txt"
ln -sf "$temp_dir/victim-empty.txt" "$temp_dir/omalink-watch.pid"
ln -sf "$temp_dir/victim-full.txt" "$temp_dir/omalink-watch.lock"
XDG_RUNTIME_DIR="$temp_dir" XDG_CONFIG_HOME="$temp_dir/xdg" PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" watch >/dev/null
if [[ -s "$temp_dir/victim-empty.txt" ]]; then
  echo "the watcher wrote through a planted pid symlink" >&2
  exit 1
fi
if [[ "$(cat "$temp_dir/victim-full.txt")" != "keep me" ]]; then
  echo "the watcher truncated a file through a planted lock symlink" >&2
  exit 1
fi
if PATH="$temp_dir:/usr/bin" "$project_dir/bin/omalink" sms abc123 'bad;number' "Test" >/dev/null 2>&1; then
  echo "invalid SMS destination was accepted" >&2
  exit 1
fi

echo "cli tests passed"
