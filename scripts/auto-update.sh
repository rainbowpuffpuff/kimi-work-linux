#!/usr/bin/env bash
# auto-update.sh — AppImage auto-updater for Kimi Work on Linux.
#
# Checks Moonshot's redirect endpoint for the latest upstream version; when it
# differs from the installed version (tracked in a state file), does a fresh
# rebuild (latest DMG → kimi-app → AppImage) and reinstalls it user-locally.
# Designed for a systemd --user timer, but works standalone:
#
#   bash scripts/auto-update.sh [--force] [--quiet]
#
# State:   ~/.local/state/kimi-work-linux/{version,update.log}
# Install: ~/Applications/KimiWork.AppImage (stable path; shortcuts don't break)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/kimi-work-linux"
VERSION_FILE="$STATE_DIR/version"
LOG_FILE="$STATE_DIR/update.log"

FORCE=0 QUIET=0
for a in "$@"; do
	case "$a" in
		--force|-f) FORCE=1 ;;
		--quiet|-q) QUIET=1 ;;
		-h|--help)  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown arg: $a (try --help)" >&2; exit 2 ;;
	esac
done

mkdir -p "$STATE_DIR"
if [ "$QUIET" = 1 ]; then
	exec >>"$LOG_FILE" 2>&1
else
	exec > >(tee -a "$LOG_FILE") 2>&1
fi

info() { printf '%s [kimi-update] %s\n' "$(date -Is)" "$*"; }

# Latest published upstream version, parsed from the redirect endpoint's
# Location header (…/kimi_<ver>.dmg). The endpoint rejects HEAD; GET + discard.
detect_latest() {
	if [ -n "${KIMI_VERSION:-}" ]; then echo "$KIMI_VERSION"; return 0; fi
	local url="${KIMI_UPSTREAM_DOWNLOAD_URL:-https://appsupport.moonshot.cn/api/app/pkg/latest/macos/download}"
	local loc fn
	loc="$(curl -fsS --max-time 20 --connect-timeout 8 -o /dev/null -D - -- "$url" 2>/dev/null \
		| awk -F': ' 'tolower($1)=="location"{gsub(/\r/,"",$2);print $2;exit}')"
	[ -n "$loc" ] || return 1
	fn="$(basename "$loc")"
	sed -nE 's/^[Kk]imi[_-]([0-9][0-9.a-zA-Z_-]*)\.(dmg|exe|zip|pkg)$/\1/p' <<<"$fn"
}

app_running() {
	pgrep -f "KimiWork[^ ]*\.AppImage" >/dev/null 2>&1 && return 0
	pgrep -f "kimi-app/electron" >/dev/null 2>&1 && return 0
	return 1
}

main() {
	local latest current
	latest="$(detect_latest || true)"
	current="$(cat "$VERSION_FILE" 2>/dev/null || true)"
	info "latest upstream: ${latest:-<unreachable>}   installed: ${current:-<none>}"

	[ -n "$latest" ] || { info "cannot determine latest version; retrying next run"; exit 0; }
	if [ "$FORCE" != 1 ] && [ -n "$current" ] && [ "$current" = "$latest" ]; then
		info "up to date ($current)"
		exit 0
	fi
	if app_running; then
		info "Kimi Work is running; skipping (will retry next run)"
		exit 0
	fi

	# Fast-forward the repo itself when clean (picks up conversion fixes);
	# a dirty or diverged checkout is simply built as-is.
	if git -C "$REPO_DIR" diff --quiet 2>/dev/null && git -C "$REPO_DIR" diff --cached --quiet 2>/dev/null; then
		git -C "$REPO_DIR" pull --ff-only >/dev/null 2>&1 \
			&& info "repo fast-forwarded to $(git -C "$REPO_DIR" rev-parse --short HEAD)" \
			|| info "repo pull skipped (non-ff or offline); building current checkout"
	else
		info "repo has local changes; building current checkout"
	fi

	info "building $latest from the latest DMG (--fresh)..."
	( cd "$REPO_DIR" && ./install.sh --fresh )
	( cd "$REPO_DIR" && bash scripts/build-appimage.sh )
	bash "$SCRIPT_DIR/install-appimage.sh"
	echo "$latest" > "$VERSION_FILE"

	info "updated: ${current:-none} → $latest"
	if command -v notify-send >/dev/null 2>&1; then
		notify-send "Kimi Work" "Updated to $latest" -i kimi-work || true
	fi
}

main
