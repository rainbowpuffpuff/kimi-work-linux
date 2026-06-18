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

	# ── Why we UNPACK app.asar instead of shipping it as an archive ────────
	# Kimi Work resolves agent/component paths on linux/win via
	#   path.join(app.getAppPath(), "resources", "targets", `${platform}-${arch}`)
	# i.e. <appRoot>/resources/targets/linux-x64/daimon-bundle/...
	# On macOS the same dirs live at Contents/Resources/resources/ (an asar-
	# external real directory), reached via process.resourcesPath.
	#
	# If we ship app.asar as an archive file, getAppPath() returns the archive
	# path and child_process.spawn() cannot exec through an asar virtual FS
	# → "spawn ENOTDIR". So we extract app.asar into a real directory NAMED
	# "app.asar" beside the Electron runtime. Electron treats a directory at
	# resources/app.asar exactly like the archive (getAppPath() still returns
	# .../app.asar), but now the path is a real directory tree spawn() can
	# reach. We then drop the component dirs (daimon-bundle, gateway, …)
	# under app.asar/resources/targets/linux-x64/ where the app looks for them.
	local eresources="$dest/electron/resources"
	mkdir -p "$eresources"

	local appdir="$eresources/app.asar"
	info "unpacking app.asar → $appdir (real dir, so spawn() can reach it)"
	rm -rf "$appdir" "$eresources/app.asar.unpacked"
	npx --yes asar extract "$asar" "$appdir" >/dev/null
	# Merge the previously-unpacked native binaries (they were unpacked beside
	# the archive because Electron can't require() *.node from inside an asar).
	# Now that the whole app is a real dir, copy them back into the tree.
	if [ -d "$unpacked" ]; then
		( cd "$unpacked" && find . -type f | while read -r f; do
			mkdir -p "$appdir/$(dirname "${f#./}")"
			cp "$f" "$appdir/${f#./}"
		done )
	fi

	# Generate the launcher from the template.
	local tmpl="$SCRIPT_DIR/launcher/start.sh.template"
	[ -f "$tmpl" ] || die "start.sh template missing: $tmpl"
	cp "$tmpl" "$dest/start.sh"
	chmod +x "$dest/start.sh"

	# ── Stage component resource dirs at the path the app joins together ──
	# Kimi Work ships its agent components OUTSIDE the asar, under
	# Contents/Resources/resources/{daimon-bundle,gateway,runtime,skills,…}.
	# Path resolution differs by platform:
	#   darwin : path.join(process.resourcesPath, "resources")
	#            → <Contents/Resources>/resources/<component>
	#   linux  : path.join(app.getAppPath(), "resources", "targets",
	#                      `${process.platform}-${process.arch}`)
	#            → <app.asar>/resources/targets/linux-x64/<component>
	# Since we unpacked app.asar to a real dir above, getAppPath() returns
	# .../app.asar (a directory), so the linux-x64 path is reachable by
	# spawn(). We copy the macOS components there. We also mirror them to the
	# darwin-style flat path (.../app.asar/resources/resources/) so any code
	# path that uses process.resourcesPath directly also resolves.
	local app="${APP_BUNDLE_DIR:-}"
	local mac_resources="$app/Contents/Resources/resources"
	if [ -n "$app" ] && [ -d "$mac_resources" ]; then
		local arch="${KIMI_ASSEMBLE_ARCH:-$(detect_arch 2>/dev/null || echo x64)}"
		local platform_arch="linux-${arch}"
		# Wipe only the dirs we own inside app.asar/resources/, then (re)create.
		# (app.asar/resources/resources and .../targets are our targets; other
		# entries under app.asar/resources/ belong to the app's own bundle.)
		local appres="$appdir/resources"
		local targets_root="$appres/targets/$platform_arch"
		local flat_root="$appres/resources"
		rm -rf "$targets_root" "$flat_root"
		mkdir -p "$targets_root" "$flat_root"

		# Copy every component from the macOS resources/ dir (NOT the locale
		# *.lproj dirs that live one level up in Contents/Resources/).
		for entry in "$mac_resources"/* "$mac_resources"/.*; do
			[ -e "$entry" ] || continue
			local base; base="$(basename "$entry")"
			case "$base" in .|..) continue ;; esac
			cp -a "$entry" "$targets_root/$base"
			cp -a "$entry" "$flat_root/$base"
		done

		# icon(s) at the root of Contents/Resources/. Kimi Work ships icon.icns
		# only (no PNG), so convert the icns → 1024px PNG for the Linux desktop
		# entry / AppImage. Pillow (PIL) is required; else skip with a warning.
		local icns_root="$app/Contents/Resources"
		for ic in icon.png icon_windows.png; do
			[ -f "$icns_root/$ic" ] && cp "$icns_root/$ic" "$dest/$ic"
		done
		if [ ! -f "$dest/icon.png" ] && [ -f "$icns_root/icon.icns" ]; then
			_icns_to_png "$icns_root/icon.icns" "$dest/icon.png" \
				|| warn "could not convert icon.icns → PNG (install python3-pil?)"
		fi
	fi

	info "kimi-app assembled → $dest"
	info "launch with: $dest/start.sh"
}
