#!/usr/bin/env bash
# kimi-work-linux — Kimi Work macOS DMG → Linux Electron app conversion entry point.
#
# This script drives the conversion pipeline. Each stage lives in scripts/lib/*.sh
# and is sourced in install-helpers → dmg → inspect → asar → native-modules →
# electron → assemble → patches.
#
# IMPORTANT: This tool does NOT redistribute Moonshot AI software. It fetches the
# upstream DMG from Moonshot's CDN at build time and automates a conversion the
# user could do by hand on their own copy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── defaults (overridable via env) ──────────────────────────────────────────
: "${KIMI_APP_ID:=com.moonshot.kimi}"
: "${KIMI_APP_DISPLAY_NAME:=Kimi Work}"
: "${KIMI_VERSION:=}"
: "${KIMI_INSTALL_DIR:=$SCRIPT_DIR/kimi-app}"
: "${KIMI_UPSTREAM_DOWNLOAD_URL:=https://appsupport.moonshot.cn/api/app/pkg/latest/macos/download}"
: "${KIMI_UPSTREAM_DMG_BASE:=https://kimi-img.moonshot.cn/app/download/mac}"

# ── flags parsed by main() ──────────────────────────────────────────────────
INSPECT=0
FRESH=0
FETCH_ONLY=0
EXTRACT_ONLY=0
PACKAGE_ONLY=0
PROVIDED_DMG_PATH=""
REPORT_DIR="$SCRIPT_DIR"

usage() {
	cat <<EOF
kimi-work-linux — Kimi Work macOS DMG → Linux Electron app converter

使い方 / Usage:
  ./install.sh [options] [DMG_PATH]

Options:
  --inspect          Inspect only: analyze app.asar, write inspect-report.json, do not convert
  --fresh            Discard the cached DMG and re-fetch
  --fetch-only       Only download (cache) the upstream DMG, then exit
  --extract-only     Only extract the .app from the DMG, then exit
  --package-only     Only package an already-built kimi-app/, then exit
  --report-dir DIR   Where to write reports (default: repo root)
  --install-dir DIR  Where to generate the app (default: ./kimi-app)
  -h, --help         Show this help

Environment:
  KIMI_UPSTREAM_DOWNLOAD_URL  Redirect endpoint → latest macOS DMG (default: Moonshot appsupport)
  KIMI_UPSTREAM_DMG_URL       Override the DMG URL entirely
  KIMI_VERSION                Pin an upstream version (default: auto via redirect)
  KIMI_INSTALL_DIR            Generated app directory (default: ./kimi-app)
  ELECTRON_MIRROR             Mirror root for the Linux Electron download

Disclaimer:
  Unofficial. Does not redistribute Moonshot AI software. Fetches the upstream
  DMG at build time and automates a conversion performed on the user's own copy.
EOF
}

# ── helpers (filled out across commits) ─────────────────────────────────────
info()  { printf '\033[1;34m[kimi]\033[0m %s\n' "$*" >&2; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }
die()   { error "$*"; exit 1; }

# Source a pipeline library if it exists (lets stages land incrementally).
load_lib() {
	local name="$1"
	local lib="$SCRIPT_DIR/scripts/lib/$name.sh"
	[ -f "$lib" ] && { # shellcheck disable=SC1090
		source "$lib"
	}
}

# ── main ────────────────────────────────────────────────────────────────────
main() {
	while [ $# -gt 0 ]; do
		case "$1" in
			-h|--help) usage; exit 0 ;;
			--inspect) INSPECT=1 ;;
			--fresh) FRESH=1 ;;
			--fetch-only) FETCH_ONLY=1 ;;
			--extract-only) EXTRACT_ONLY=1 ;;
			--package-only) PACKAGE_ONLY=1 ;;
			--report-dir) REPORT_DIR="${2:-}"; shift ;;
			--install-dir) KIMI_INSTALL_DIR="${2:-}"; shift ;;
			--) shift; break ;;
			-*) die "unknown option: $1 (try --help)" ;;
			*) PROVIDED_DMG_PATH="$1" ;;
		esac
		shift
	done

	load_lib install-helpers
	load_lib dmg
	load_lib inspect
	load_lib asar
	load_lib native-modules
	load_lib electron
	load_lib assemble
	load_lib runtimes
	load_lib patches
	check_deps

	# Stage: resolve + (optionally) download the DMG.
	get_dmg

	if [ "$FETCH_ONLY" = 1 ]; then
		info "DMG ready: ${RESOLVED_DMG_PATH:-<none>}"
		exit 0
	fi

	# Stage: extract the .app bundle.
	extract_dmg "${RESOLVED_DMG_PATH:-}"

	if [ "$EXTRACT_ONLY" = 1 ]; then
		info "extracted app bundle: ${APP_BUNDLE_DIR:-<none>}"
		exit 0
	fi

	if [ "$INSPECT" = 1 ]; then
		inspect_app "${APP_BUNDLE_DIR:-}"
		exit 0
	fi

	# Stage: extract, swap Linux native prebuilds, strip macOS-only, repack.
	# Install linux siblings BEFORE stripping so the loader sees the linux
	# package and we remove only the darwin leftovers.
	local resources="${APP_BUNDLE_DIR}/Contents/Resources"
	asar_extract "$resources/app.asar"
	install_linux_prebuilds "$ASAR_EXTRACTED_DIR" "$(detect_arch)"
	strip_non_linux_natives "$ASAR_EXTRACTED_DIR"

	# Stage: apply asar patches (descriptors under scripts/patches/core/).
	apply_patches "$ASAR_EXTRACTED_DIR"

	asar_pack "$ASAR_EXTRACTED_DIR" "$SCRIPT_DIR/app.asar"
	info "asar repacked with Linux natives: ${REPACKED_ASAR:-<none>}"

	# Stage: fetch + stage the matching Linux Electron runtime.
	download_electron "$KIMI_INSTALL_DIR" "$(detect_arch)"
	info "electron staged: ${ELECTRON_BIN:-<none>}"

	# Stage: replace darwin-bundled daimon runtimes (Python, uv) + neutralize
	# the darwin-only kimi-webbridge. Done on the APP_BUNDLE_DIR in place so
	# assemble_app copies the linux versions into kimi-app/.
	replace_daimon_runtimes "$(detect_arch)"

	# Stage: assemble the runnable kimi-app/ (asar + electron + launcher).
	assemble_app "$KIMI_INSTALL_DIR"
	info "kimi-app assembled: $KIMI_INSTALL_DIR"
	info "launch with: $KIMI_INSTALL_DIR/start.sh"
	if [ "$PACKAGE_ONLY" = 1 ]; then
		info "run 'make deb' or 'make appimage' to package the app."
	fi
}

main "$@"
