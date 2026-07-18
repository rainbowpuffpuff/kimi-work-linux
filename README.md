# kimi-work-linux

Run **Kimi Work / Kimi Desktop** (Moonshot AI's desktop AI agent) on Linux by
converting the upstream macOS build into a runnable Linux Electron app —
**automated, in one shell command.**

Moonshot AI ships official Kimi Work installers for macOS and Windows only.
This project fills in Linux by converting the upstream macOS `kimi_<ver>.dmg`
into a runnable Linux Electron app and packaging it as a `.deb` / `AppImage`.

> **Fork note (omdano):** this fork adds **working Kimi WebBridge browser
> automation** (via Moonshot's official, but unadvertised, Linux webbridge
> daemon), support for the **≥3.1 installer-wrapped DMG layout**, a strip of
> the macOS xattr shadow files that broke the daimon runtime, rootless
> **AppImage installs**, and a **weekly systemd auto-updater**. Verified
> end-to-end on Kimi Work **3.1.1** (Bazzite 44, KDE/Wayland): GUI launches,
> login + membership sync work, the daimon reaches `ready`, all gateway
> plugins install, and the webbridge daemon answers on `127.0.0.1:10086`.

> **Fork note (rainbowpuffpuff):** on top of omdano, this fork adds **Linux
> deep-link routing** (`kimi://` / `kimi-work://` from Chat webview +
> `.desktop` handlers + AppImage cold-start) so Invite / “open in Work”
> actually opens the local app. **Partial fix only** — claim / invite-to-earn
> / draw rewards still often do not complete after handoff; see
> [Deep links (partial fix)](#deep-links-partial-fix).

> **Status:** the conversion pipeline, `.deb`/`AppImage` packaging, and a
> one-command installer are implemented and **verified end-to-end against the
> real Kimi Work 3.0.22 DMG** upstream, and against **3.1.1** in this fork
> (see [Verified below](#verified)).

## ⚠️ Disclaimer

This is an **unofficial community project**. Kimi Work / Kimi Desktop is a
product of **Moonshot AI (月之暗面)**. This tool:

- **Does not redistribute any Moonshot AI software.** No upstream binaries are
  stored in this repository.
- Automates the conversion process that users perform on their own copy of the
  upstream DMG, which is fetched from Moonshot's CDN at build time.
- Is not affiliated with, endorsed by, or sponsored by Moonshot AI.

Use of the converted app is subject to Moonshot AI's own terms of service.
Ensure you have the right to run Kimi on your platform before using this tool.

## How it works

Kimi Work is an Electron app, but it is more complex than a typical one: it
bundles an agent runtime (`@kimi/daimon`), a gateway (`openclaw`/`clawhub`),
and standalone Python/Node/uv runtimes alongside the main `app.asar`. The
conversion handles all of them:

1. **Resolve** the latest version by following Moonshot's redirect endpoint
   (`appsupport.moonshot.cn/api/app/pkg/latest/macos/download` → `kimi_<ver>.dmg`).
2. **Fetch** the upstream macOS DMG (cached by HTTP fingerprint, resumable).
3. **Extract** the `.app` bundle with `7zz` (modern 7-Zip; old `p7zip` cannot
   open current APFS DMGs). Handles the ≥3.1 layout where the real app is
   nested inside `Kimi Installer.app/Contents/Helpers/Kimi.app`, and strips
   the macOS xattr shadow files (`*:com.apple.*`, ~84k of them) that 7z
   extracts — they otherwise double directory entry counts and break the
   daimon's runtime-resource preflight (`provision-failed`).
4. **Inspect** `app.asar` to discover native modules, the Electron version,
   integrity checks, and the bundle layout → `inspect-report.json`.
5. **Swap** every darwin native for its Linux equivalent across **four**
   component trees (see table below), all N-API / prebuild-based → no rebuild.
6. **Replace** the darwin-bundled Python, uv, and Node runtimes with their
   Linux builds (same upstream release tags).
7. **Replace** the darwin `kimi-webbridge` Mach-O with Moonshot's **official
   Linux daemon** from `cdn.kimi.com/webbridge` (same version lineage; the
   Electron main process spawns `resources/kimi-webbridge start --foreground`
   unconditionally at boot, with no platform or signature checks).
8. **Strip** macOS-only leftovers (`fsevents`, `@esbuild/darwin-*`, symlinks,
   the conpty `spawn-helper`, …).
9. **Repack** `app.asar` deterministically, with native binaries unpacked
   beside the asar (Electron cannot `require()` from inside).
10. **Download** the matching Linux Electron runtime.
11. **Assemble** `kimi-app/` (Electron + repacked asar + launcher + icon) and
    generate `start.sh`.
12. **Package** as `.deb` / `AppImage`.

### Verified

End-to-end run against **Kimi Work 3.0.22** (macOS arm64 DMG → Linux x64, upstream):

| Check | Result |
| --- | --- |
| DMG download | ✅ 730 MB, resumable |
| Pipeline stages | ✅ all pass |
| **Mach-O binaries remaining** | **✅ 0** |
| Native binaries (Linux ELF) | ✅ 22 — all ELF-verified |
| `.deb` build | ✅ `kimi-work_3.0.22-klinux1_amd64.deb` (596 MB) |

End-to-end run against **Kimi Work 3.1.1** (this fork, Bazzite 44 / KDE Wayland):

| Check | Result |
| --- | --- |
| DMG layout | ✅ installer-wrapped `Kimi.app` located + extracted |
| GUI launch | ✅ window renders; login + membership sync OK |
| daimon agent runtime | ✅ provision → spawn → `ready` (ws control on 127.0.0.1) |
| Gateway plugins | ✅ 8/8 installed (incl. `kimi-webbridge`) |
| WebBridge daemon | ✅ official Linux build spawned by the app itself; `curl 127.0.0.1:10086/status` → `{"running":true,"version":"v1.11.3"}` |

The four component trees and their darwin → Linux swaps:

| Tree | Native module | Linux package |
| --- | --- | --- |
| **main `app.asar`** | `@minify-html/node-darwin-arm64` | `@minify-html/node-linux-x64` |
| | `@napi-rs/canvas-darwin-arm64` | `@napi-rs/canvas-linux-x64-gnu` |
| | `fsevents` | *(deleted; chokidar falls back)* |
| **gateway** (`openclaw`) | `@mariozechner/clipboard-darwin-arm64` | `…-clipboard-linux-x64-gnu` |
| | `@snazzah/davey-darwin-arm64` | `…-davey-linux-x64-gnu` |
| | `@napi-rs/canvas-darwin-arm64` | `…-canvas-linux-x64-gnu` |
| | `@lydell/node-pty-darwin-arm64` | `…-node-pty-linux-x64` |
| | `@img/sharp-darwin-arm64` + `sharp-libvips-darwin-arm64` | `…-sharp-linux-x64` + `…-sharp-libvips-linux-x64` |
| | `sqlite-vec-darwin-arm64` | `sqlite-vec-linux-x64` |
| | `koffi` (darwin-only build dir) | full `koffi` pkg → `build/koffi/linux_x64/` |
| **daimon-bundle** (`@kimi/daimon`) | `better-sqlite3` (prebuild-install) | fresh install → `build/Release/better_sqlite3.node` |
| **bundled runtimes** | Python 3.12 (cpython, darwin) | python-build-standalone, same release tag (linux) |
| | uv (darwin) | astral-sh/uv (linux) |
| | Node v24.15.0 (darwin) | nodejs.org (linux) |
| | `kimi-webbridge` (darwin Mach-O) | official Linux daemon (`cdn.kimi.com/webbridge`) |

## Prerequisites

- Linux x86_64 (Ubuntu/Debian tested first; other distros later). arm64 should
  work via the same pipeline (linux arm64 prebuilds all exist).
- `curl`, `python3`, `unzip`, `make`
- Modern **7-Zip** (`7zz` ≥ 23.x). The ancient `p7zip` 16.02 cannot extract
  current DMGs — `make install-deps` bootstraps a modern `7zz` if needed.
- `dpkg-deb` (for `.deb`), `appimagetool` (for AppImage — auto-downloaded)
- A C++ toolchain (`build-essential`) — only needed if a native rebuild is
  required (the default path uses prebuilds, no rebuild).
- Node.js / npm — used at build time for `asar` / `prebuild-install`. The
  built app bundles its own Electron + Node runtime; you do **not** need a
  distro `nodejs` to run it.
- `python3-pil` (Pillow) — to convert the shipped `icon.icns` → PNG.

## Quick start

Clone, then run `make bootstrap` — it installs or updates to the latest
upstream version:

```bash
git clone https://github.com/omdano/kimi-work-linux.git
cd kimi-work-linux
make bootstrap            # deps → fetch latest DMG → build → package → install
```

`make bootstrap` (a.k.a. `scripts/install-latest.sh`) detects the latest
upstream version, skips the rebuild if you are already up to date, and
installs the `.deb` (it will prompt for sudo). Pass `FORCE=1` to rebuild
regardless: `make bootstrap FORCE=1`.

Step by step:

```bash
make install-deps         # bootstrap 7zz + system build deps
make inspect              # analyze the upstream DMG → inspect-report.json
make build-app            # build ./kimi-app/
./kimi-app/start.sh       # run it
make deb                  # build a .deb into dist/
make appimage             # build an AppImage into dist/
```

Rootless AppImage install + auto-updates (recommended on atomic distros such
as Bazzite / Silverblue, where `.deb` doesn't apply):

```bash
make appimage-install     # ~/Applications/KimiWork.AppImage + menu entry (no root)
make install-updater      # weekly systemd --user timer (see below)
```

## Auto-updates (AppImage path)

`make install-updater` installs `kimi-work-update.timer`, a weekly systemd
**user** timer (no root, `Persistent=true`, randomized ≤1h delay) that runs
`scripts/auto-update.sh`. Each run:

1. Reads the latest upstream version from Moonshot's redirect endpoint.
2. Compares it with the installed version tracked in
   `~/.local/state/kimi-work-linux/version`.
3. If newer: fast-forwards this repo (when clean), rebuilds from the latest
   DMG, rebuilds the AppImage, and reinstalls `~/Applications/KimiWork.AppImage`
   (stable path — shortcuts never break). Skips the run while the app is
   running. Logs to `~/.local/state/kimi-work-linux/update.log` and sends a
   desktop notification on success.

Manage it with `make uninstall-updater`, or run a check by hand:
`bash scripts/auto-update.sh` (`--force` to rebuild regardless).
Do **not** use the app's built-in updater — it only serves Windows/macOS
payloads.

## WebBridge (browser automation) on Linux

Browser automation works on Linux out of the box with this fork. The Electron
main process spawns `resources/kimi-webbridge start --foreground` at every
boot with no platform or signature checks, and this fork swaps in Moonshot's
official Linux daemon (same `v1.x` lineage as the bundled macOS one).

The daemon alone is not enough — on **every** platform it drives your browser
through the **Kimi WebBridge browser extension**:

1. Install the extension in Chrome/Edge (the app links to
   `kimi.com/features/webbridge`, or search the Chrome Web Store).
2. Verify: `curl -s 127.0.0.1:10086/status` should report
   `"extension_connected":true`.

## Configuration (environment variables)

| Variable | Default | Purpose |
| --- | --- | --- |
| `KIMI_UPSTREAM_DOWNLOAD_URL` | `https://appsupport.moonshot.cn/api/app/pkg/latest/macos/download` | The redirect endpoint that resolves to the latest macOS DMG |
| `KIMI_UPSTREAM_DMG_URL` | resolved from the redirect | Override the DMG URL entirely |
| `KIMI_VERSION` | auto-detected from the redirect's `Location` | Pin an upstream version (e.g. `3.0.22`) |
| `KIMI_INSTALL_DIR` | `./kimi-app` | Where the runnable app is generated |
| `KIMI_ELECTRON_VERSION` | from `inspect-report.json` / Info.plist | Pin the Electron runtime version |
| `KIMI_WEBBRIDGE_VERSION` | `latest` | Pin the webbridge daemon version (e.g. `v1.11.3`) |
| `KIMI_APPIMAGE_DIR` | `~/Applications` | Where `install-appimage.sh` puts the AppImage |
| `ELECTRON_MIRROR` | GitHub releases | Mirror root for the Linux Electron download |

## Project structure

```
install.sh               # conversion entry point (drives the pipeline)
Makefile                 # bootstrap / build-app / package / deb / appimage / inspect / run-app
scripts/
  install-deps.sh        # bootstrap 7zz + system build deps
  install-latest.sh      # one-command install / update (latest version detection)
  build-deb.sh           # .deb packaging
  build-appimage.sh      # AppImage packaging
  install-appimage.sh    # rootless AppImage install (~/Applications + .desktop)
  auto-update.sh         # weekly updater driver (version check → rebuild → install)
  lib/                   # pipeline stages:
    install-helpers.sh     arch/distro detection, deps + modern 7zz check
    dmg.sh                 redirect-based version detection + fingerprint-cached download;
                           ≥3.1 installer-app handling + macOS xattr shadow strip
    inspect.sh             asar analyzer → inspect-report.json
    asar.sh                extract / strip darwin artifacts / deterministic repack
    native-modules.sh      Linux prebuild swap across all node_modules trees
    electron.sh            resolve + cache + extract matching Linux Electron runtime
    runtimes.sh            replace darwin Python/uv/Node + official Linux webbridge
    assemble.sh            wire repacked asar + electron + launcher → kimi-app/
    package-common.sh      shared .deb/AppImage staging
    patches.sh             asar patch engine driver
  patches/                # asar patch engine (apply/engine/registry/shared) + core/
launcher/
  start.sh.template      # Linux launcher (Wayland/X11, --no-sandbox, fontconfig hint)
packaging/
  linux/                 # .deb control + desktop entry
  appimage/              # AppRun + runtime
  systemd/               # kimi-work-update.{service.in,timer} for auto-updates
```

## Known limitations

- **GUI launch on 3.0.22 was untested upstream** — 3.1.1 is verified on this
  fork (see [Verified](#verified)); other distros/versions may still surprise.
- **Auto-updater inside the app is not patched** — Kimi runs
  `electron-updater` against `https://kimi-img.moonshot.cn/app/upgrade/`,
  which only serves Windows/macOS payloads. Use `make bootstrap` or the
  weekly systemd updater above instead.
- The daemon's port cleanup uses `lsof` and the skill deploy uses `tar`;
  both are standard on desktop Linux, and failures there are non-fatal.
- **Deep links open Work, but invite / claim / “draw” rewards may still not
  complete** — see [Deep links (partial fix)](#deep-links-partial-fix).

## Deep links (partial fix)

This tree applies `scripts/patches/core/linux-deeplink/` at build time and
registers both `kimi-work://` and `kimi://` on the `.desktop` entry so the
Chat webview no longer drops in-app deep links.

**What works**

- Invite / “open in Work app” no longer dies with “No Apps Available”.
- `xdg-open 'kimi-work://home'` and in-app `kimi://action/…` focus the
  desktop shell and open the Work surface (logged as
  `handleDeepLink protocol=…` in `~/.config/kimi-desktop/logs/main.log`).

**What still does not work (open bug)**

- Opening the local Work app this way does **not** fully deliver
  invite-to-earn / claim / draw rewards the way the official macOS/Windows
  app (or pure browser claim flow) does.
- `kimi-work://` still mostly maps to `openPage()` (show Work tab). Query /
  path payloads used for claim state are incomplete; rewards often do not
  apply after the handoff.

**Environment where this was observed**

| Field | Value |
| --- | --- |
| OS | Fedora Linux 44 (Workstation Edition) |
| Kernel | 7.1.3-200.fc44.x86_64 |
| Arch | x86_64 |
| Session | Wayland |
| Hardware | Framework Laptop 16 (AMD Ryzen 7040 Series) |
| Kimi Work | 3.1.2 (macOS arm64 DMG → Linux AppImage via this pipeline) |

## Acknowledgments

The architecture is directly inspired by — and borrows design patterns from:

- [`robustonian/zcode-linux`](https://github.com/robustonian/zcode-linux) — the
  same conversion approach for Z.ai's ZCode desktop app.
- [`ilysenko/codex-desktop-linux`](https://github.com/ilysenko/codex-desktop-linux)
  — the original approach for OpenAI Codex Desktop.

This fork is based on [`omdano/kimi-work-linux`](https://github.com/omdano/kimi-work-linux)
(which itself is based on [`robustonian/kimi-work-linux`](https://github.com/robustonian/kimi-work-linux)).

## License

MIT. See [LICENSE](LICENSE).
