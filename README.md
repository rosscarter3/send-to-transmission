# Send to Transmission

A tiny macOS app that makes magnet links and `.torrent` files go to a
[Transmission](https://transmissionbt.com) daemon on another machine (a NAS,
a home server, a Raspberry Pi) instead of a desktop torrent client.

Click a magnet link in the browser, or double-click a `.torrent` file: it's
added to the remote Transmission and a notification shows its name. Manage
the downloads in Transmission's own web UI.

- Native: an AppleScript applet plus one shell script. No Electron, no
  Rosetta, nothing to install beyond what ships with macOS (with the Command
  Line Tools for `python3`).
- The RPC password lives in the macOS Keychain and is passed to `curl` on
  stdin, never on a command line.
- Works with authentication on or off, and tells you clearly when the
  server is unreachable, the password is wrong, or the server's
  `rpc-whitelist` refuses your Mac.

## Install

```sh
git clone https://github.com/rosscarter3/send-to-transmission.git
cd send-to-transmission
./build.sh --url http://nas.local:9091 --user alice
```

This:
1. asks for the RPC password once and stores it in the Keychain
   (service `send-to-transmission`);
2. builds `~/Applications/Send to Transmission.app`;
3. makes it the default handler for `magnet:` links and `.torrent` files.
   macOS may ask you to confirm the change.

Leave out `--user` if your server has no authentication. Run
`./build.sh --help` for the other options (a different Keychain item or app
location, or `--no-default` to build without changing the handlers).

If a desktop torrent client is still installed, it may claim magnet links
back when it next runs. Remove it, or re-run `build.sh`.

## Use

- Click a magnet link, or open a `.torrent` file.
- Open the app itself to see which server it sends to, with a button for the
  web UI.
- From a terminal:
  ```sh
  "~/Applications/Send to Transmission.app/Contents/Resources/send.sh" 'magnet:?xt=urn:btih:…'
  ```
  `send.sh` reads its settings from the `config` file next to it. `TR_URL`,
  `TR_USER` and `TR_KEYCHAIN` in the environment override them.

## Server side

Transmission's RPC has to accept connections from your Mac. In the daemon's
`settings.json`, either turn `rpc-whitelist-enabled` off or add your LAN, for
example `"rpc-whitelist": "127.0.0.1,192.168.1.*"`. With the
linuxserver/transmission Docker image, that's the `WHITELIST` variable.

Use the RPC over plain HTTP only on a network you trust: the password is sent
with HTTP basic auth. For anything further away, put it behind HTTPS and give
`--url https://…`.

## Change or remove

- **New server or password:** re-run `build.sh`. To change a stored
  password: `security delete-generic-password -s send-to-transmission`, then
  re-run.
- **Uninstall:** delete the app, then the Keychain item as above. macOS falls
  back to whichever app handles magnet links next.

## How it works

`build.sh` compiles `main.applescript` with `osacompile`, and adds `send.sh` and
a `config` file to the app's Resources. It then edits `Info.plist` to declare
the `magnet` URL scheme and the `org.bittorrent.torrent` file type, ad-hoc
signs the app, and sets it as the default handler through Launch Services.

`send.sh` makes a `torrent-add` call to the
[RPC API](https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md):
magnet links as `filename`, `.torrent` files base64-encoded as `metainfo`.
It handles the API's CSRF session-id handshake.

## Licence

MIT
