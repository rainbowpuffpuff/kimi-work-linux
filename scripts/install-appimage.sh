#!/usr/bin/env bash
# install-appimage.sh — install the newest dist/KimiWork-*.AppImage user-locally:
#   ~/Applications/KimiWork.AppImage            (stable path)
#   ~/.local/share/applications/kimi-work.desktop
#   ~/.local/share/icons/kimi-work.png
# No root needed; suitable for atomic desktops (Bazzite, Silverblue, …).
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info() { printf '\033[1;34m[kimi-appimage]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[kimi-appimage error]\033[0m %s\n' "$*" >&2; exit 1; }

APPS_DIR="${KIMI_APPIMAGE_DIR:-$HOME/Applications}"
TARGET="$APPS_DIR/KimiWork.AppImage"

src="$(ls -t "$REPO_DIR"/dist/KimiWork-*.AppImage 2>/dev/null | head -n1)"
[ -n "$src" ] || die "no AppImage in $REPO_DIR/dist — build one first: make appimage"

mkdir -p "$APPS_DIR" "$HOME/.local/share/applications" "$HOME/.local/share/icons"
info "installing $(basename "$src") → $TARGET"
cp "$src" "$TARGET"
chmod +x "$TARGET"

icon="$REPO_DIR/dist/kimi-work.AppDir/opt/kimi-work/icon.png"
[ -f "$icon" ] || icon="$REPO_DIR/kimi-app/icon.png"
if [ -f "$icon" ]; then
	cp "$icon" "$HOME/.local/share/icons/kimi-work.png"
fi

cat > "$HOME/.local/share/applications/kimi-work.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kimi Work
Comment=Kimi Work (unofficial Linux build)
Exec=$TARGET %U
Icon=kimi-work
Terminal=false
Categories=Office;Utility;
EOF
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

info "done — launch from your app menu or directly: $TARGET"
