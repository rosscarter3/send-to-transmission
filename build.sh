#!/bin/bash
# Builds "Send to Transmission.app" into ~/Applications, stores the RPC
# password in the Keychain, and makes the app the default handler for
# magnet links and .torrent files.
#
#   ./build.sh --url http://nas.local:9091 --user alice
#   ./build.sh --url http://nas.local:9091                # no authentication
#
# Options:
#   --url URL         Transmission address; /transmission/rpc is added if missing
#   --user NAME       RPC username (omit if the server has no authentication)
#   --keychain NAME   Keychain service for the password (default send-to-transmission)
#   --app PATH        where to put the app (default ~/Applications/Send to Transmission.app)
#   --no-default      build only; don't change the magnet/.torrent handlers
set -euo pipefail
cd "$(dirname "$0")"
URL= USER_NAME= KC=send-to-transmission APP="$HOME/Applications/Send to Transmission.app" SETDEFAULT=1
while [ $# -gt 0 ]; do
  case $1 in
    --url) URL=$2; shift 2 ;;
    --user) USER_NAME=$2; shift 2 ;;
    --keychain) KC=$2; shift 2 ;;
    --app) APP=$2; shift 2 ;;
    --no-default) SETDEFAULT=0; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$URL" ] || { echo "--url is required (e.g. --url http://nas.local:9091)" >&2; exit 2; }
URL=${URL%/}
case $URL in */rpc) ;; */transmission) URL=$URL/rpc ;; *) URL=$URL/transmission/rpc ;; esac
ID=local.send-to-transmission

if [ -n "$USER_NAME" ] && ! security find-generic-password -s "$KC" -a "$USER_NAME" >/dev/null 2>&1; then
  echo "Password for Transmission user '$USER_NAME' (stored in the Keychain as '$KC'):"
  # -w as the last argument makes security prompt for it, so it never
  # appears on a command line.
  security add-generic-password -s "$KC" -a "$USER_NAME" -l "Transmission RPC ($URL)" -w
fi

mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
osacompile -o "$APP" main.applescript
cp send.sh "$APP/Contents/Resources/"
printf 'TR_URL=%q\nTR_USER=%q\nTR_KEYCHAIN=%q\n' "$URL" "$USER_NAME" "$KC" > "$APP/Contents/Resources/config"

P="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$P"; }
pb "Add :CFBundleIdentifier string $ID" 2>/dev/null || pb "Set :CFBundleIdentifier $ID"
pb "Add :LSUIElement bool true"             # no Dock icon
pb "Add :CFBundleURLTypes array"
pb "Add :CFBundleURLTypes:0 dict"
pb "Add :CFBundleURLTypes:0:CFBundleURLName string Magnet link"
pb "Add :CFBundleURLTypes:0:CFBundleURLSchemes array"
pb "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string magnet"
# Declare the .torrent type here, so it still exists once a desktop torrent
# client (which normally declares it) is removed.
pb "Add :UTImportedTypeDeclarations array"
pb "Add :UTImportedTypeDeclarations:0 dict"
pb "Add :UTImportedTypeDeclarations:0:UTTypeIdentifier string org.bittorrent.torrent"
pb "Add :UTImportedTypeDeclarations:0:UTTypeDescription string BitTorrent Document"
pb "Add :UTImportedTypeDeclarations:0:UTTypeConformsTo array"
pb "Add :UTImportedTypeDeclarations:0:UTTypeConformsTo:0 string public.data"
pb "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification dict"
pb "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension array"
pb "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:0 string torrent"
pb "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.mime-type string application/x-bittorrent"
# osacompile adds a catch-all document type for "on open"; replace it.
pb "Delete :CFBundleDocumentTypes" 2>/dev/null || true
pb "Add :CFBundleDocumentTypes array"
pb "Add :CFBundleDocumentTypes:0 dict"
pb "Add :CFBundleDocumentTypes:0:CFBundleTypeName string BitTorrent Document"
pb "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer"
pb "Add :CFBundleDocumentTypes:0:LSHandlerRank string Owner"
pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes array"
pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string org.bittorrent.torrent"

# Ad-hoc signature (the Info.plist changed after osacompile signed it).
/usr/bin/codesign --force --deep -s - "$APP" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

if [ "$SETDEFAULT" = 1 ]; then
  /usr/bin/osascript -l JavaScript -e "
ObjC.import('CoreServices');
var a = \$.LSSetDefaultHandlerForURLScheme(\$('magnet'), \$('$ID'));
var b = \$.LSSetDefaultRoleHandlerForContentType(\$('org.bittorrent.torrent'), 0xFFFFFFFF, \$('$ID'));
if (a || b) { 'could not set the default handlers (' + a + ', ' + b + ')' } else { 'default handler for magnet: and .torrent' }"
fi
echo "Built $APP"
echo "Test: \"$APP/Contents/Resources/send.sh\" --web-url"
