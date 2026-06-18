#!/usr/bin/env bash
# native-modules.sh — resolve Linux native modules via prebuild swap (no rebuild).
# Sourced by install.sh (do not execute directly).
#
# Verified against Kimi Work 3.0.22 (asar-extracted + app.asar.unpacked):
#
#   module                          role                linux prebuild
#   ──────────────────────────────  ──────────────────  ─────────────────────────────
#   @minify-html/node-darwin-arm64  HTML minifier       @minify-html/node-linux-<arch>
#   @napi-rs/canvas-darwin-arm64    canvas/skia render  @napi-rs/canvas-linux-<arch>-gnu
#   fsevents                        macOS FS watcher    (none — delete; chokidar falls back)
#   @esbuild/darwin-arm64           build-time only     (none — delete; unused at runtime)
#   @sentry/cli-darwin              sentry CLI binary   (none — delete; optional)
#
# Both @minify-html/node and @napi-rs/canvas are N-API based → ABI-agnostic, so
# their prebuilt .node runs under Electron without @electron/rebuild. They are
# distributed as optionalDependencies sibling packages; on macOS only the
# darwin sibling is installed. We fetch the matching linux sibling from npm
# and drop it into node_modules/ next to the existing darwin one.
#
# NOTE: Kimi Work does NOT bundle node-pty (unlike ZCode), so there is no pty
# prebuild to swap here.

NATIVE_BUILD_DIR="${KIMI_NATIVE_BUILD_DIR:-$SCRIPT_DIR/.cache/native-build}"

# Map our arch to the npm suffix conventions used by the two native families.
# @minify-html/node uses <plat>-<arch>; @napi-rs/canvas uses <plat>-<arch>-<libc>.
_npm_arch_suffix() {
	local arch="${1:-$(detect_arch)}"
	case "$arch" in
		x64)   echo "x64" ;;
		arm64) echo "arm64" ;;
		*) die "no npm prebuild arch for $arch" ;;
	esac
}

# Fetch a single platform sibling package from npm into the staging dir.
# Usage: _npm_fetch_platform_pkg <pkg-spec>  → prints installed node_modules path
_npm_fetch_platform_pkg() {
	local spec="$1"
	rm -rf "$NATIVE_BUILD_DIR"
	mkdir -p "$NATIVE_BUILD_DIR"
	( cd "$NATIVE_BUILD_DIR" \
		&& npm init -y >/dev/null 2>&1 \
		&& npm install "$spec" --no-save --ignore-scripts --foreground-scripts >/dev/null 2>&1 ) \
		|| die "npm install $spec failed"
	local pkg="${spec%%@*}"  # strip @version if present
	[ -d "$NATIVE_BUILD_DIR/node_modules/$pkg" ] \
		|| die "$pkg did not install"
	echo "$NATIVE_BUILD_DIR/node_modules/$pkg"
}

# Swap the darwin native prebuilds for their Linux equivalents.
install_linux_prebuilds() {
	local dir="${1:-$ASAR_EXTRACTED_DIR}"
	local arch="${2:-$(detect_arch)}"
	local arch_suffix; arch_suffix="$(_npm_arch_suffix "$arch")"

	info "installing Linux native prebuilds (arch=$arch_suffix)..."

	# ── @minify-html/node-linux-<arch> ──────────────────────────────────────
	if [ -d "$dir/node_modules/@minify-html/node" ]; then
		local spec="@minify-html/node-linux-${arch_suffix}"
		info "fetching $spec..."
		local staged; staged="$(_npm_fetch_platform_pkg "$spec")"
		local node_file; node_file="$(find "$staged" -name '*.node' | head -n1)"
		[ -n "$node_file" ] || die "no .node in $spec"
		_verify_elf "$node_file" "$spec"
		local dest="$dir/node_modules/@minify-html/node-linux-${arch_suffix}"
		rm -rf "$dest" && mkdir -p "$dest"
		cp -a "$staged/." "$dest/"
		info "  placed @minify-html/node-linux-${arch_suffix} ✓"
	else
		warn "@minify-html/node not in asar; skipping"
	fi

	# ── @napi-rs/canvas-linux-<arch>-gnu ───────────────────────────────────
	if [ -d "$dir/node_modules/@napi-rs/canvas" ]; then
		# gnu libc (Ubuntu/Debian/Arch). musl variant exists for Alpine.
		local libc="gnu"
		if [ -f /etc/alpine-release ] 2>/dev/null; then libc="musl"; fi
		local spec="@napi-rs/canvas-linux-${arch_suffix}-${libc}"
		info "fetching $spec..."
		local staged; staged="$(_npm_fetch_platform_pkg "$spec")"
		local node_file; node_file="$(find "$staged" -name '*.node' | head -n1)"
		[ -n "$node_file" ] || die "no .node in $spec"
		_verify_elf "$node_file" "$spec"
		local dest="$dir/node_modules/@napi-rs/canvas-linux-${arch_suffix}-${libc}"
		rm -rf "$dest" && mkdir -p "$dest"
		cp -a "$staged/." "$dest/"
		info "  placed @napi-rs/canvas-linux-${arch_suffix}-${libc} ✓"
	else
		warn "@napi-rs/canvas not in asar; skipping"
	fi
}

# Assert a file is a Linux ELF (catches stray darwin/win binaries early).
_verify_elf() {
	local f="$1" label="$2"
	local ftype; ftype="$(file "$f")"
	case "$ftype" in
		*ELF*) info "  prebuild is ELF ✓ ($label)" ;;
		*) die "prebuild is NOT ELF ($label): $ftype" ;;
	esac
}
