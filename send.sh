#!/bin/bash
# Adds one magnet link or .torrent file to a remote Transmission daemon over
# its RPC API. Prints the torrent's name, or an error on stderr (exit 1).
#
#   send.sh 'magnet:?xt=urn:btih:…'
#   send.sh ~/Downloads/something.torrent
#   send.sh --web-url            # prints the web UI address
#
# Settings come from a "config" file next to this script (written by
# build.sh), and can be overridden by environment variables of the same name:
#   TR_URL       http://host:9091/transmission/rpc
#   TR_USER      RPC username; empty for a server without authentication
#   TR_KEYCHAIN  Keychain service holding the password (account = TR_USER)
# The password is read from the Keychain and handed to curl on stdin, so it
# never appears on a command line.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
_url=${TR_URL-}; _user=${TR_USER-}; _kc=${TR_KEYCHAIN-}
[ -f "$here/config" ] && . "$here/config"
TR_URL=${_url:-${TR_URL:-}}; TR_USER=${_user:-${TR_USER:-}}; TR_KEYCHAIN=${_kc:-${TR_KEYCHAIN:-send-to-transmission}}
[ -n "$TR_URL" ] || { echo "TR_URL is not set (run build.sh, or export TR_URL)" >&2; exit 2; }

if [ "${1-}" = --web-url ]; then echo "${TR_URL%/rpc}/web/"; exit 0; fi
[ $# -eq 1 ] || { echo "usage: send.sh <magnet link | file.torrent>" >&2; exit 2; }

curlcfg() {
  [ -n "$TR_USER" ] || return 0
  local pw
  pw=$(security find-generic-password -s "$TR_KEYCHAIN" -a "$TR_USER" -w 2>/dev/null) \
    || { echo "no Keychain password: service '$TR_KEYCHAIN', account '$TR_USER'" >&2; return 1; }
  # curl config syntax: escape backslashes and double quotes.
  pw=${pw//\\/\\\\}; pw=${pw//\"/\\\"}
  printf 'user = "%s:%s"\n' "$TR_USER" "$pw"
}
cfg=$(curlcfg)

body=$(mktemp); trap 'rm -f "$body"' EXIT
/usr/bin/python3 - "$1" > "$body" <<'PY'
import base64, json, sys
a = sys.argv[1]
if a.startswith("magnet:"):
    args = {"filename": a}
else:
    with open(a, "rb") as f:
        args = {"metainfo": base64.b64encode(f.read()).decode()}
print(json.dumps({"method": "torrent-add", "arguments": args}))
PY

# CSRF protection: the first request is answered 409 with a session id,
# which every later request must echo back.
code_and_sid=$(printf '%s\n' "$cfg" | curl -s -m 10 -K - -o /dev/null -D - -w '%{http_code}\n' "$TR_URL" || true)
sid=$(printf '%s\n' "$code_and_sid" | awk 'tolower($1)=="x-transmission-session-id:"{print $2}' | tr -d '\r')
if [ -z "$sid" ]; then
  case $(printf '%s\n' "$code_and_sid" | tail -1) in
    401) echo "Transmission rejected the username or password" >&2 ;;
    403) echo "Transmission refused this computer (check rpc-whitelist on the server)" >&2 ;;
    000) echo "can't reach Transmission at $TR_URL" >&2 ;;
    *)   echo "unexpected answer from $TR_URL" >&2 ;;
  esac
  exit 1
fi
printf '%s\n' "$cfg" | curl -s -m 30 -K - -H "X-Transmission-Session-Id: $sid" --data-binary @"$body" "$TR_URL" \
  | /usr/bin/python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)
except ValueError:
    sys.exit("unexpected answer from Transmission")
if r.get("result") != "success":
    sys.exit("Transmission said: %s" % r.get("result"))
a = r["arguments"]
t = a.get("torrent-added") or a.get("torrent-duplicate")
print(("Already there: " if "torrent-duplicate" in a else "") + t["name"])'
