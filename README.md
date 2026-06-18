# kimi-work-linux

Run **Kimi Work / Kimi Desktop** (Moonshot AI's desktop AI agent) on Linux by
converting the upstream macOS build into a runnable Linux Electron app —
**automated, in one shell command.**

Moonshot AI ships official Kimi Work installers for macOS and Windows only.
This project fills in Linux by converting the upstream macOS `kimi_<ver>.dmg`
into a runnable Linux Electron app and packaging it as a `.deb` / `AppImage`.

> **Status:** the conversion pipeline + `.deb`/`AppImage` packaging + a
> one-command installer are implemented. Native module rebuilds (if any new
> ones ship upstream) and the auto-updater are deferred. See the commit
> history for progress.

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

Kimi Work is an Electron app. Electron apps bundle their UI/logic in a
platform-independent `app.asar`; only the Electron runtime and a few native
modules are platform-specific. So the conversion is:

1. **Resolve** the latest version by following Moonshot's redirect endpoint
   (`appsupport.moonshot.cn/api/app/pkg/latest/macos/download` → `kimi_<ver>.dmg`).
2. **Fetch** the upstream macOS DMG (cached by HTTP fingerprint).
3. **Extract** the `.app` bundle with `7zz` (modern 7-Zip; old `p7zip` cannot
   open current APFS DMGs).
4. **Inspect** `app.asar` to discover native modules, the Electron version,
   integrity checks, and the bundle layout.
5. **Strip** macOS-only pieces (`fsevents`, `@rollup/rollup-darwin-*`,
   darwin/win32 node-pty prebuilds, …).
6. **Install** the matching Linux native prebuilds (`node-pty` etc.) via npm —
   N-API based, so ABI-agnostic, no rebuild required.
7. **Repack** `app.asar` deterministically, with native binaries unpacked
   beside the asar (Electron cannot `require()` from inside).
8. **Download** the matching Linux Electron runtime.
9. **Assemble** `kimi-app/` (Electron + repacked asar + launcher) and generate
   `start.sh`.
10. **Package** as `.deb` / `AppImage`.

## Prerequisites

- Linux x86_64 (Ubuntu/Debian tested first; other distros later). arm64 should
  work via the Apple-Silicon DMG.
- `curl`, `python3`, `unzip`, `make`
- Modern **7-Zip** (`7zz` ≥ 23.x). The ancient `p7zip` 16.02 cannot extract
  current DMGs — `make install-deps` bootstraps a modern `7zz` if needed.
- `dpkg-deb` (for `.deb`), `appimagetool` (for AppImage)
- A C++ toolchain (`build-essential`) — only needed if a native rebuild is
  required (the default path uses prebuilds).
- Node.js / npm — used at build time for `asar` / `@electron/rebuild`. The
  built app bundles its own Electron runtime; you do **not** need a distro
  `nodejs` to run it.

## Quick start

Clone, then run `make bootstrap` — it installs or updates to the latest
upstream version:

```bash
git clone <this repo> kimi-work-linux
cd kimi-work-linux
make bootstrap            # deps → fetch latest DMG → build → package → install
```

`make bootstrap` (a.k.a. `scripts/install-latest.sh`) detects the latest
upstream version, skips the rebuild if you are already up to date, and
installs the `.deb` (it will prompt for sudo). Pass `--force` to rebuild
regardless: `make bootstrap -- --force`.

Step by step:

```bash
make install-deps         # bootstrap 7zz + system build deps
make inspect              # analyze the upstream DMG → inspect-report.json
make build-app            # build ./kimi-app/
./kimi-app/start.sh       # run it
make deb                  # build a .deb into dist/
make appimage             # build an AppImage into dist/
```

## Configuration (environment variables)

| Variable | Default | Purpose |
| --- | --- | --- |
| `KIMI_UPSTREAM_DOWNLOAD_URL` | `https://appsupport.moonshot.cn/api/app/pkg/latest/macos/download` | The redirect endpoint that resolves to the latest macOS DMG |
| `KIMI_UPSTREAM_DMG_URL` | resolved from the redirect | Override the DMG URL entirely |
| `KIMI_VERSION` | auto-detected from the redirect's `Location` | Pin an upstream version (e.g. `3.0.22`) |
| `KIMI_INSTALL_DIR` | `./kimi-app` | Where the runnable app is generated |
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
  lib/                   # pipeline stages (dmg / asar / native-modules / electron / inspect / assemble / package-common)
  patches/               # asar patch engine + Kimi-specific patch descriptors
launcher/
  start.sh.template      # Linux launcher (Wayland/X11, GPU workarounds, --no-sandbox)
packaging/
  linux/                 # .deb control + desktop entry
  appimage/              # AppRun + runtime
```

## Acknowledgments

The architecture is directly inspired by — and borrows design patterns from:

- [`robustonian/zcode-linux`](https://github.com/robustonian/zcode-linux) — the
  same conversion approach for Z.ai's ZCode desktop app.
- [`ilysenko/codex-desktop-linux`](https://github.com/ilysenko/codex-desktop-linux)
  — the original approach for OpenAI Codex Desktop.

## License

MIT. See [LICENSE](LICENSE).
