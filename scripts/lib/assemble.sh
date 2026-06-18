#!/usr/bin/env bash
# assemble.sh — assemble the runnable kimi-app/ from the staged pieces.
# Sourced by install.sh (do not execute directly).

# Convert an Apple .icns to a PNG (largest frame), via Pillow. Best-effort.
_icns_to_png() {
	local icns="$1" out="$2"
	python3 - "$icns" "$out" <<'PY' || return 1
import sys
try:
    from PIL import Image
except Exception as e:
    sys.stderr.write(f"Pillow unavailable: {e}\n"); sys.exit(1)
icns, out = sys.argv[1], sys.argv[2]
im = Image.open(icns)
best = im.copy()
for i in range(1, 64):
    try:
        im.seek(i)
    except EOFError:
        break
    if im.size[0] >= best.size[0]:
        best = im.copy()
best.convert("RGBA").save(out)
print(f"icns → {out} ({best.size[0]}x{best.size[1]})")
PY
}

assemble_app() {
	local dest="${1:-$KIMI_INSTALL_DIR}"
	local asar="${2:-${REPACKED_ASAR:-$SCRIPT_DIR/app.asar}}"
	local unpacked="${3:-$SCRIPT_DIR/app.asar.unpacked}"

	[ -x "$dest/electron/electron" ] || die "electron not staged (run download_electron first)"
	[ -f "$asar" ] || die "repacked app.asar not found: $asar"

	# Place app.asar + unpacked beside the Electron runtime. Electron reads
	# resources/app.asar (preferring it over default_app.asar).
	local eresources="$dest/electron/resources"
	mkdir -p "$eresources"
	rm -f "$eresources/app.asar"
	rm -rf "$eresources/app.asar.unpacked"
	cp "$asar" "$eresources/app.asar"
	[ -d "$unpacked" ] && cp -r "$unpacked" "$eresources/app.asar.unpacked"

	# Generate the launcher from the template.
	local tmpl="$SCRIPT_DIR/launcher/start.sh.template"
	[ -f "$tmpl" ] || die "start.sh template missing: $tmpl"
	cp "$tmpl" "$dest/start.sh"
	chmod +x "$dest/start.sh"

	# Stage extra resource dirs + icon from macOS Contents/Resources/ — place
	# them beside app.asar in electron/resources/ so the app finds them via
	# process.resourcesPath.
	local app="${APP_BUNDLE_DIR:-}"
	local resources="$app/Contents/Resources"
	if [ -n "$app" ] && [ -d "$resources" ]; then
		# Copy every non-asar resource dir (catches Kimi's own asset dirs
		# without us having to enumerate them by name).
		for d in "$resources"/*/; do
			[ -d "$d" ] || continue
			local name; name="$(basename "$d")"
			case "$name" in
				app.asar*) continue ;;   # skip app.asar + app.asar.unpacked
			esac
			rm -rf "$eresources/$name"
			cp -r "$d" "$eresources/$name"
		done
		# icon(s) at the root of Resources/. Kimi Work ships icon.icns only
		# (no PNG), so convert the icns → 1024px PNG for the Linux desktop
		# entry / AppImage. Pillow (PIL) is required for this; if absent we
		# fall back to any existing PNG, or skip with a warning.
		for ic in icon.png icon_windows.png; do
			[ -f "$resources/$ic" ] && cp "$resources/$ic" "$dest/$ic"
		done
		if [ ! -f "$dest/icon.png" ] && [ -f "$resources/icon.icns" ]; then
			_icns_to_png "$resources/icon.icns" "$dest/icon.png" \
				|| warn "could not convert icon.icns → PNG (install python3-pil?)"
		fi
	fi

	info "kimi-app assembled → $dest"
	info "launch with: $dest/start.sh"
}
