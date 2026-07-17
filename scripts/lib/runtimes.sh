#!/usr/bin/env bash
# runtimes.sh — replace the darwin-bundled Python + uv in the daimon-bundle
# with their Linux equivalents. Sourced by install.sh (do not execute directly).
#
# @kimi/daimon (the agent/CLI bundle) ships a standalone CPython 3.12 and uv,
# both built for darwin-arm64. They live at:
#   Contents/Resources/resources/daimon-bundle/runtime/python/cpython-3.12/
#   Contents/Resources/resources/daimon-bundle/runtime/uv/uv
# bundle.json records the exact python-build-standalone release tag + asset
# name, so we can fetch the matching linux tarball from the same release and
# drop it into the same path. uv comes from astral-sh/uv GitHub releases.
#
# Node is NOT bundled (DAIMON_BUNDLE_NODE_BIN) — the host Node or the bundled
# Electron's Node is expected to supply it. We point DAIMON_BUNDLE_NODE_BIN at
# the bundled Electron's node if available, via the launcher.

RUNTIME_CACHE_DIR="${KIMI_RUNTIME_CACHE_DIR:-$SCRIPT_DIR/.cache/runtimes}"

# Map our arch to the python-build-standalone / uv GNU libc triple.
_linux_triple() {
	case "${1:-$(detect_arch)}" in
		x64)   echo "x86_64-unknown-linux-gnu" ;;
		arm64) echo "aarch64-unknown-linux-gnu" ;;
		*) die "no linux triple for $(detect_arch)" ;;
	esac
}

_uv_arch_dir() {
	case "${1:-$(detect_arch)}" in
		x64)   echo "x86_64-unknown-linux-gnu" ;;
		arm64) echo "aarch64-unknown-linux-gnu" ;;
		*) die "no uv arch for $(detect_arch)" ;;
	esac
}

# Replace the bundled darwin CPython with the matching linux build from the
# same python-build-standalone release tag (read from bundle.json).
_replace_daimon_python() {
	local bundle_dir="${APP_BUNDLE_DIR:-}/Contents/Resources/resources/daimon-bundle"
	local bundle_json="$bundle_dir/bundle.json"
	[ -f "$bundle_json" ] || { warn "no daimon bundle.json; skipping python"; return 0; }

	# Parse python runtime metadata from bundle.json.
	local py_target py_tag py_asset py_path
	py_target="$(python3 -c "import json;print(json.load(open('$bundle_json'))['runtimes']['python']['target'])" 2>/dev/null || echo 3.12)"
	py_tag="$(python3 -c   "import json;print(json.load(open('$bundle_json'))['runtimes']['python']['releaseTag'])" 2>/dev/null || echo 20260610)"
	py_path="$(python3 -c "import json;print(json.load(open('$bundle_json'))['runtimes']['python']['path'])" 2>/dev/null || echo runtime/python/cpython-3.12)"

	local arch="${1:-$(detect_arch)}"
	local triple; triple="$(_linux_triple "$arch")"
	# Derive the full python version from the darwin asset name in bundle.json,
	# falling back to a constructed name. Asset convention:
	#   cpython-<ver>+<tag>-<triple>-install_only.tar.gz
	local darwin_asset
	darwin_asset="$(python3 -c "import json;print(json.load(open('$bundle_json'))['runtimes']['python'].get('asset',''))" 2>/dev/null || true)"
	# Swap the triple in the asset name: cpython-X+tag-aarch64-apple-darwin-... → ...-x86_64-unknown-linux-gnu-...
	local linux_asset=""
	if [ -n "$darwin_asset" ]; then
		linux_asset="$(printf '%s' "$darwin_asset" | sed -E "s/-[a-z0-9]+-(apple-darwin|unknown-linux-gnu|pc-windows-msvc)-install_only/-${triple}-install_only/")"
	fi
	# Sanity: ensure the derived name carries our linux triple.
	case "$linux_asset" in
		*"$triple"*) ;;  # good
		*) linux_asset="cpython-${py_target}.*+${py_tag}-${triple}-install_only.tar.gz" ;;
	esac

	local runtime_root="$bundle_dir/$(dirname "$py_path")"
	local py_dest="$bundle_dir/$py_path"
	local url="https://github.com/astral-sh/python-build-standalone/releases/download/${py_tag}/${linux_asset}"
	info "replacing daimon Python (${py_target}, tag ${py_tag}) → linux ${triple}"
	info "  $url"

	mkdir -p "$RUNTIME_CACHE_DIR"
	local tmp="$RUNTIME_CACHE_DIR/python-${py_tag}-${triple}.tar.gz"
	if [ ! -f "$tmp" ]; then
		curl -fL --retry 3 -C - -o "$tmp.part" -- "$url" || { warn "python download failed; agent python features unavailable"; return 0; }
		mv "$tmp.part" "$tmp"
	fi

	# python-build-standalone extracts to a 'python/' top dir; install it into
	# the bundle's expected cpython-<ver> path.
	local extract="$RUNTIME_CACHE_DIR/python-${py_tag}-${triple}"
	rm -rf "$extract" "$py_dest"
	mkdir -p "$extract"
	tar -xzf "$tmp" -C "$extract"
	# The tarball contains either python/ or cpython-<ver>/ at its root.
	local inner; inner="$(find "$extract" -maxdepth 1 -type d ! -path "$extract" | head -n1)"
	[ -n "$inner" ] || { warn "python tarball layout unexpected; skipping"; return 0; }
	mkdir -p "$runtime_root"
	mv "$inner" "$py_dest"
	chmod +x "$py_dest/bin/python${py_target}" 2>/dev/null || true
	# Verify the real binary (bin/python3 is a symlink to python3.12 on
	# python-build-standalone, so resolve it before the ELF check).
	local pybin="$py_dest/bin/python${py_target}"
	[ -x "$pybin" ] && _verify_elf "$pybin" "daimon python" || warn "daimon python binary missing"
	info "  placed daimon python → $py_dest ✓"
}

# Replace the bundled darwin uv with the linux build from astral-sh/uv.
_replace_daimon_uv() {
	local bundle_dir="${APP_BUNDLE_DIR:-}/Contents/Resources/resources/daimon-bundle"
	local uv_dest="$bundle_dir/runtime/uv/uv"
	[ -d "$(dirname "$uv_dest")" ] || { warn "no daimon uv dir; skipping"; return 0; }

	local arch="${1:-$(detect_arch)}"
	local uvdir; uvdir="$(_uv_arch_dir "$arch")"
	local url="https://github.com/astral-sh/uv/releases/latest/download/uv-${uvdir}.tar.gz"
	info "replacing daimon uv → linux ${uvdir}"
	info "  $url"

	mkdir -p "$RUNTIME_CACHE_DIR"
	local tmp="$RUNTIME_CACHE_DIR/uv-${uvdir}.tar.gz"
	if [ ! -f "$tmp" ]; then
		curl -fL --retry 3 -C - -o "$tmp.part" -- "$url" || { warn "uv download failed; agent uv features unavailable"; return 0; }
		mv "$tmp.part" "$tmp"
	fi

	local extract="$RUNTIME_CACHE_DIR/uv-${uvdir}"
	rm -rf "$extract"
	mkdir -p "$extract"
	tar -xzf "$tmp" -C "$extract"
	local newuv; newuv="$(find "$extract" -type f -name uv -perm -u+x | head -n1)"
	[ -n "$newuv" ] || newuv="$(find "$extract" -type f -name uv | head -n1)"
	[ -n "$newuv" ] || { warn "uv binary not found in tarball; skipping"; return 0; }
	_verify_elf "$newuv" "daimon uv"
	cp "$newuv" "$uv_dest"
	chmod +x "$uv_dest"
	info "  placed daimon uv → $uv_dest ✓"
}

# kimi-webbridge is a standalone Go daemon (loopback HTTP on 127.0.0.1:10086)
# that the Electron main process spawns unconditionally at every boot:
#   <resources>/kimi-webbridge start --foreground
# There are NO platform or signature checks on that path (verified in
# app.asar main/index.js, 3.1.1), so the darwin Mach-O can simply be replaced
# with Moonshot's official Linux build from their CDN — same version lineage
# as the bundled darwin binary. The only remaining piece is the browser
# extension, which users install in Chrome/Edge themselves.
# (daimon-bundle/bundle.json's includesWebBridge:false / setupMode:"skip" only
# means the daimon doesn't manage webbridge — it is NOT disabled app-wide.)
_replace_webbridge_linux() {
	local wb="${APP_BUNDLE_DIR:-}/Contents/Resources/resources/kimi-webbridge"
	[ -f "$wb" ] || return 0

	local arch="${1:-$(detect_arch)}"
	local cdn_arch; cdn_arch="$(case "$arch" in
		x64) echo "amd64" ;;
		arm64) echo "arm64" ;;
		*) die "no webbridge build for $arch" ;;
	esac)"
	local version="${KIMI_WEBBRIDGE_VERSION:-latest}"
	local url="https://cdn.kimi.com/webbridge/${version}/releases/kimi-webbridge-linux-${cdn_arch}"
	info "replacing darwin kimi-webbridge → official linux build (${version}, linux-${cdn_arch})"
	info "  $url"

	mkdir -p "$RUNTIME_CACHE_DIR"
	local tmp="$RUNTIME_CACHE_DIR/kimi-webbridge-linux-${cdn_arch}-${version}"
	# Pinned versions are cached; "latest" is always re-fetched (the daemon
	# tracks the auto-updating browser extension's release line; ~10 MB).
	if [ "$version" = "latest" ] || [ ! -f "$tmp" ]; then
		if curl -fL --retry 3 -C - -o "$tmp.part" -- "$url"; then
			mv "$tmp.part" "$tmp"
		else
			rm -f "$tmp.part"
			[ -f "$tmp" ] || { warn "webbridge download failed; browser automation unavailable"; return 0; }
			warn "webbridge download failed; using cached copy"
		fi
	fi

	_verify_elf "$tmp" "kimi-webbridge"
	cp "$tmp" "$wb"
	chmod +x "$wb"
	info "  placed kimi-webbridge (linux-${cdn_arch}) → $wb ✓"
}

# The bundle ships its own Node.js at resources/runtime/node (darwin-arm64).
# Replace it with the matching linux build from nodejs.org (official binaries),
# keeping the version from the .node-stamp file. daimon/gateway invoke this.
_replace_bundled_node() {
	local rt_dir="${APP_BUNDLE_DIR:-}/Contents/Resources/resources/runtime"
	local stamp="$rt_dir/.node-stamp"
	[ -f "$rt_dir/node" ] || { warn "no bundled runtime/node; skipping"; return 0; }

	local arch="${1:-$(detect_arch)}"
	local node_arch; node_arch="$(case "$arch" in
		x64) echo "x64" ;;
		arm64) echo "arm64" ;;
		*) die "no node arch for $arch" ;;
	esac)"

	# Parse "<version>-<platform>-<arch>" → version. e.g. 24.15.0-darwin-arm64
	local version="24.15.0"
	if [ -f "$stamp" ]; then
		version="$(sed -E 's/^([0-9][0-9.]*).*/\1/' "$stamp" 2>/dev/null || echo 24.15.0)"
	fi
	info "replacing bundled Node ${version} → linux ${node_arch}"

	mkdir -p "$RUNTIME_CACHE_DIR"
	local url="https://nodejs.org/dist/v${version}/node-v${version}-linux-${node_arch}.tar.xz"
	local tmp="$RUNTIME_CACHE_DIR/node-v${version}-linux-${node_arch}.tar.xz"
	if [ ! -f "$tmp" ]; then
		curl -fL --retry 3 -C - -o "$tmp.part" -- "$url" || { warn "node download failed; gateway/daimon will need a system node"; return 0; }
		mv "$tmp.part" "$tmp"
	fi

	local extract="$RUNTIME_CACHE_DIR/node-v${version}-linux-${node_arch}"
	rm -rf "$extract"
	mkdir -p "$extract"
	tar -xJf "$tmp" -C "$extract"
	local newnode; newnode="$extract/node-v${version}-linux-${node_arch}/bin/node"
	[ -f "$newnode" ] || { warn "node binary not found in tarball; skipping"; return 0; }
	_verify_elf "$newnode" "bundled node"
	cp "$newnode" "$rt_dir/node"
	chmod +x "$rt_dir/node"
	# Update the stamp so the app doesn't think it still has the darwin build.
	printf '%s-linux-%s\n' "$version" "$node_arch" > "$stamp"
	info "  placed bundled node ${version} (linux-${node_arch}) → $rt_dir/node ✓"
}

# Top-level: replace all daimon-bundled darwin runtimes.
replace_daimon_runtimes() {
	local arch="${1:-$(detect_arch)}"
	_replace_daimon_python "$arch"
	_replace_daimon_uv "$arch"
	_replace_bundled_node "$arch"
	_replace_webbridge_linux "$arch"
}
