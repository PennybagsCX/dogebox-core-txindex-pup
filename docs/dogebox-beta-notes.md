# Dogebox OS beta — field notes for pup authors

Learned 2026-09-13 while publishing and running the first third-party pups (NanoPC-T6, Dogebox OS beta). Also reported upstream in [Dogebox-WG/pups#28](https://github.com/Dogebox-WG/pups/issues/28).

## Publishing a Pup Source

1. **Source URLs must end in `.git`** — `https://github.com/owner/repo` fails with `unknown source type`.
2. **The repo needs semver git tags** (`v0.0.1`, …). Commits alone → `no valid semver tags found`.
3. After pushing a new tag, the box may keep serving the old listing until `/opt/dogebox/pup-update-cache.json` is deleted and a refresh runs.
4. The dashboard error toast for failed source adds shows `<Todo: Show reason>` — the real error is in `journalctl -u dogeboxd`.

## Manifest facts (verified against dogeboxd source + live behavior)

- `container.build.nixFileSha256` = `sha256sum pup.nix` (hex) of the pup.nix at the tagged commit.
- `exposes[].listenOnHost` + `webUI: true` → dogeboxd binds a **host port in the 10000-range** that proxies to the container — your manifest port is internal only. The assigned port can change on reinstall; the dashboard's "Launch web" always knows the current one.
- `meta.logoPath` is only checked for existence — logo changes don't affect the build hash.

## Install / update / uninstall behavior

- **Version updates create a NEW pup instance with FRESH storage** (new pup ID, empty `/storage`). The old instance lingers as a stopped record. To carry data across an update: stop both containers and rename the old storage dir over the new one (`mv` on the same filesystem is instant), then start the new one.
- **Purge only works on disabled pups** (`Cannot purge pup in state ready` otherwise), and the purge queue can fail silently, leaving ghost records that survive daemon restarts and reboots. Recovery: stop dogeboxd, delete `/opt/dogebox/pups/pup_<id>.gob` and the pup's dirs, start dogeboxd. The `.gob` files are the pup state.
- Avoid `systemctl stop` on pup containers behind dogeboxd's back — it auto-restarts enabled pups. Use the API `disable`.

## System-level extensions (sanctioned)

- `PUT /system/custom-nix` (dashboard-bearer-token auth, port 3000) accepts a NixOS module; it's validated (`nix-instantiate --parse`), imported into the system config, and triggers a rebuild. This is the supported way to add e.g. Samba or Tailscale, and it survives OS updates. Gotcha: each attribute (`networking.firewall.allowedUDPPorts` etc.) may only be declared once per module body.

## DLNA / SSDP — container multicast does NOT reach the LAN

Pups live on an internal routed bridge (10.69.0.x). **UPnP/DLNA discovery (SSDP multicast, UDP 1900, 239.255.255.250) does not traverse it** — a DLNA server inside a pup (e.g. Jellyfin's DLNA plugin) will never appear in a smart TV's source list, no matter how it's configured.

**Pattern that works:** run the DLNA server on the HOST via custom-nix. `services.minidlna` (nixpkgs) with `settings.media_dir` pointing at the pup's storage path works immediately — verified with a 2016 Samsung Tizen TV discovering and connecting within a minute. Two gotchas:
1. minidlna runs as its own user — `/opt/dogebox` is `drwx------ dogeboxd`, so the whole path needs `chmod o+x` for the scanner to read the media dirs (0 files indexed until then).
2. Option shape (nixpkgs 25.11): `services.minidlna.settings = { friendly_name = "..."; media_dir = [ "V,/path" ]; };` — not `friendlyName`/`mediaDirectories`/`config.*`.

Bonus: MiniDLNA's status page (`http://<box>:8200`) lists connecting clients — handy for verifying which TVs see the server.

## Nix packaging gotchas

- The nixpkgs `jellyfin` wrapper already injects `--ffmpeg` — passing it yourself crashes Jellyfin with `Option 'ffmpeg' is defined multiple times`.
- Fresh Jellyfin needs ~2 minutes before the `/Startup/*` API answers (404 before that). Headless setup order: `POST /Startup/User` → `/Startup/Configuration` → `/Startup/Complete`.
