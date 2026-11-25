#!/usr/bin/env bash
# One-time (idempotent) macOS or Linux (Debian) setup for building Theta.
#
#   ./scripts/setup-toolchain.sh            # installs into $THEOS, default ~/theos
#   THEOS=/opt/theos ./scripts/setup-toolchain.sh
#
# What it does:
#   1. brew install make (gmake) and ldid
#   2. clone Theos into $THEOS if missing, at the pinned $THEOS_COMMIT
#   3. unpack the patched iPhoneOS 14.5 SDK into $THEOS/sdks
#   4. point $THEOS/toolchain/Xcode14.xctoolchain at the local Xcode / CLT toolchain
#   5. graft libc++ headers into the 14.5 SDK (modern clang needs <cmath>)
# On Linux it prints the `sudo apt install` line for missing packages instead of running it, and
# sets up Debian clang 19 + lld with a cctools toolchain (see setup_linux).
# Safe to re-run; each step skips itself when already done.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
# Theos commit this fork is built and tested with. Bump it on purpose.
THEOS_COMMIT="304e0799973e8145f32e4ca2de6c747a84b758ce"
SDK_TARBALL="$REPO_DIR/sdks/iPhoneOS14.5.sdk.tar.xz"
SDK_DIR="$THEOS/sdks/iPhoneOS14.5.sdk"
TOOLCHAIN_LINK="$THEOS/toolchain/Xcode14.xctoolchain"

log() { echo "[Setup] $*"; }
die() { echo "[Setup] ERROR: $*" >&2; exit 1; }

# Linux (Debian 13 tested): Debian's clang 19 + lld compile for iOS, the L1ghtmann cctools
# toolchain supplies ldid / otool / install_name_tool / strip / lipo and the libc++ headers.
# The script never runs sudo; it prints the apt line for whatever is missing.
setup_linux() {
	local arch asset sha clang_dir="/usr/lib/llvm-19/bin" missing=() pkgs=() tool
	local tc="$THEOS/toolchain" shim="$THEOS/toolchain/theta-linux"
	local rt_tag="llvmorg-19.1.7"
	local rt_sha="bc0b9f10e8d1a1ac5905d710f1c9fead23878e31233748d580393edc4e3bfc18"

	case "$(uname -m)" in
		x86_64)        asset="iOSToolchain-x86_64.tar.xz"
		               sha="a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e" ;;
		aarch64|arm64) asset="iOSToolchain-aarch64.tar.xz"
		               sha="9051e9d531de5e511f0fab40d925d625bc6efe7ed9dce821d179c09de9bc690b" ;;
		*) die "unsupported CPU $(uname -m)" ;;
	esac

	# 1. Packages (apt names)
	[[ -x "$clang_dir/clang" && -x "$clang_dir/clang++" ]] || pkgs+=(clang-19)
	[[ -x "$clang_dir/ld64.lld" ]] || pkgs+=(lld-19)
	[[ -x "$clang_dir/llvm-ar" ]] || pkgs+=(llvm-19)
	for tool in gmake:make cc:gcc git:git curl:curl xz:xz-utils zip:zip python3:python3 perl:perl; do
		command -v "${tool%%:*}" &>/dev/null || pkgs+=("${tool##*:}")
	done
	if [[ ${#pkgs[@]} -gt 0 ]]; then
		log "missing packages. Run:"
		log "  sudo apt install ${pkgs[*]}"
		die "install them, then re-run this script"
	fi
	log "packages present ($("$clang_dir/clang" --version | head -1))"

	# 2. Theos
	if [[ -f "$THEOS/makefiles/common.mk" ]]; then
		log "Theos present at $THEOS"
		local current
		current="$(git -C "$THEOS" rev-parse HEAD 2>/dev/null || true)"
		if [[ "$current" != "$THEOS_COMMIT" ]]; then
			log "WARNING: Theos is at ${current:-unknown}, this fork is tested with $THEOS_COMMIT"
			log "  git -C \"$THEOS\" checkout $THEOS_COMMIT && git -C \"$THEOS\" submodule update --init --recursive"
		fi
	else
		[[ -e "$THEOS" ]] && die "$THEOS exists but is not a Theos checkout"
		log "Cloning Theos $THEOS_COMMIT into $THEOS"
		git clone --quiet https://github.com/theos/theos.git "$THEOS"
		git -C "$THEOS" checkout --quiet "$THEOS_COMMIT"
		git -C "$THEOS" submodule update --quiet --init --recursive
	fi
	mkdir -p "$tc"

	# 3. Cctools toolchain (only ldid, otool, install_name_tool, strip, lipo, libtool, libc++ headers)
	if [[ -x "$tc/linux/iphone/bin/ldid" ]]; then
		log "cctools toolchain present"
	else
		log "Downloading $asset"
		local dl; dl="$(mktemp -d)"
		curl -fsSL -o "$dl/$asset" "https://github.com/L1ghtmann/llvm-project/releases/download/test-210562a/$asset" \
			|| { rm -rf "$dl"; die "download failed"; }
		if [[ "$(sha256sum "$dl/$asset" | cut -d' ' -f1)" != "$sha" ]]; then
			rm -rf "$dl"; die "checksum mismatch for $asset"
		fi
		tar -xJf "$dl/$asset" -C "$tc" --warning=no-unknown-keyword
		rm -rf "$dl"
	fi

	# 4. Patched 14.5 SDK (GNU tar warns about the macOS xattr headers in the tarball)
	if [[ -d "$SDK_DIR" ]]; then
		log "SDK present at $SDK_DIR"
	else
		[[ -f "$SDK_TARBALL" ]] || die "missing $SDK_TARBALL"
		log "Unpacking patched iPhoneOS 14.5 SDK"
		mkdir -p "$THEOS/sdks"
		tar -xJf "$SDK_TARBALL" -C "$THEOS/sdks" --warning=no-unknown-keyword
	fi

	# 5. libc++ headers (Debian's libc++-dev headers are configured for Linux and fail)
	if [[ -f "$SDK_DIR/usr/include/c++/v1/cmath" ]]; then
		log "libc++ headers already present in SDK"
	else
		[[ -f "$tc/linux/iphone/include/c++/v1/cmath" ]] || die "no libc++ headers in $tc/linux/iphone"
		mkdir -p "$SDK_DIR/usr/include/c++"
		cp -R "$tc/linux/iphone/include/c++/v1" "$SDK_DIR/usr/include/c++/v1"
		log "Grafted libc++ headers from the cctools toolchain"
	fi

	# 6. Toolchain dir: Debian clang with lld, plus the cctools the build needs
	mkdir -p "$shim/usr/bin" "$shim/lib"
	for tool in clang clang++; do
		printf '#!/bin/sh\nexec %s/%s -fuse-ld=lld "$@"\n' "$clang_dir" "$tool" > "$shim/usr/bin/$tool"
		chmod +x "$shim/usr/bin/$tool"
	done
	for tool in ldid otool install_name_tool strip lipo libtool; do
		ln -sfn "$tc/linux/iphone/bin/$tool" "$shim/usr/bin/$tool"
	done
	if [[ -e "$TOOLCHAIN_LINK" && ! -L "$TOOLCHAIN_LINK" ]]; then
		log "Keeping existing real toolchain at $TOOLCHAIN_LINK"
	else
		ln -sfn "$shim" "$TOOLCHAIN_LINK"
		log "Linked $TOOLCHAIN_LINK -> $shim"
	fi

	# 7. libclang_rt.ios.a: __isOSVersionAtLeast / __isPlatformVersionAtLeast for @available,
	#    which Apple clang ships and Debian's clang lacks for Darwin. Built from LLVM's source.
	if [[ -f "$shim/lib/libclang_rt.ios.a" ]]; then
		log "libclang_rt.ios.a present"
	else
		log "Building libclang_rt.ios.a ($rt_tag os_version_check.c)"
		local rt; rt="$(mktemp -d)"
		curl -fsSL -o "$rt/os_version_check.c" \
			"https://raw.githubusercontent.com/llvm/llvm-project/$rt_tag/compiler-rt/lib/builtins/os_version_check.c" \
			|| { rm -rf "$rt"; die "download failed"; }
		if [[ "$(sha256sum "$rt/os_version_check.c" | cut -d' ' -f1)" != "$rt_sha" ]]; then
			rm -rf "$rt"; die "checksum mismatch for os_version_check.c"
		fi
		"$clang_dir/clang" -target arm64-apple-ios14.0 -isysroot "$SDK_DIR" -O2 \
			-c "$rt/os_version_check.c" -o "$rt/os_version_check.o" \
			|| { rm -rf "$rt"; die "compiling os_version_check.c failed"; }
		"$clang_dir/llvm-ar" rcs "$shim/lib/libclang_rt.ios.a" "$rt/os_version_check.o"
		rm -rf "$rt"
	fi

	log "Done. Toolchain: $("$TOOLCHAIN_LINK/usr/bin/clang" --version | head -1)"
	if [[ "$THEOS" != "$HOME/theos" ]]; then
		log "build.sh defaults to ~/theos; export THEOS=$THEOS in your shell profile"
	fi
}

if [[ "$(uname -s)" == "Linux" ]]; then
	setup_linux
	exit 0
fi

[[ "$(uname -s)" == "Darwin" ]] || die "macOS and Linux only"
xcode-select -p &>/dev/null || die "install the Xcode command-line tools first: xcode-select --install"

# 1. Homebrew packages
command -v brew &>/dev/null || die "Homebrew is required (https://brew.sh)"
for formula in make ldid; do
	if brew list --formula "$formula" &>/dev/null; then
		log "brew: $formula already installed"
	else
		log "brew: installing $formula"
		brew install "$formula"
	fi
done

# 2. Theos
if [[ -f "$THEOS/makefiles/common.mk" ]]; then
	log "Theos present at $THEOS"
	current="$(git -C "$THEOS" rev-parse HEAD 2>/dev/null || true)"
	if [[ "$current" != "$THEOS_COMMIT" ]]; then
		log "WARNING: Theos is at ${current:-unknown}, this fork is tested with $THEOS_COMMIT"
		log "  git -C \"$THEOS\" checkout $THEOS_COMMIT && git -C \"$THEOS\" submodule update --init --recursive"
	fi
else
	[[ -e "$THEOS" ]] && die "$THEOS exists but is not a Theos checkout"
	log "Cloning Theos $THEOS_COMMIT into $THEOS"
	git clone --quiet https://github.com/theos/theos.git "$THEOS"
	git -C "$THEOS" checkout --quiet "$THEOS_COMMIT"
	git -C "$THEOS" submodule update --quiet --init --recursive
fi

# 3. Patched 14.5 SDK
if [[ -d "$SDK_DIR" ]]; then
	log "SDK present at $SDK_DIR"
else
	[[ -f "$SDK_TARBALL" ]] || die "missing $SDK_TARBALL"
	log "Unpacking patched iPhoneOS 14.5 SDK"
	mkdir -p "$THEOS/sdks"
	tar -xJf "$SDK_TARBALL" -C "$THEOS/sdks"
fi

# 4. Toolchain. The Makefile hard-codes PREFIX = $THEOS/toolchain/Xcode14.xctoolchain/usr/bin/.
#    Xcode 14 no longer installs on current macOS, so link whatever toolchain is selected.
#    A real directory there (an actual Xcode 14 toolchain) is left alone.
dev_dir="$(xcode-select -p)"
if [[ -d "$dev_dir/Toolchains/XcodeDefault.xctoolchain" ]]; then
	toolchain="$dev_dir/Toolchains/XcodeDefault.xctoolchain"
else
	toolchain="$dev_dir"   # Command Line Tools: usr/bin/clang lives directly under it
fi
[[ -x "$toolchain/usr/bin/clang" ]] || die "no clang under $toolchain"
mkdir -p "$THEOS/toolchain"
if [[ -e "$TOOLCHAIN_LINK" && ! -L "$TOOLCHAIN_LINK" ]]; then
	log "Keeping existing real toolchain at $TOOLCHAIN_LINK"
else
	ln -sfn "$toolchain" "$TOOLCHAIN_LINK"
	log "Linked $TOOLCHAIN_LINK -> $toolchain"
fi

# 5. libc++ headers. The amalgamated TU is Objective-C++, so the SDK's simd/math.h
#    includes <cmath>; the patched 14.5 SDK ships no C++ headers and clang >= 15 errors out.
#    Re-unpacking the SDK wipes this graft, so re-run this script afterwards.
if [[ -f "$SDK_DIR/usr/include/c++/v1/cmath" ]]; then
	log "libc++ headers already present in SDK"
else
	grafted=0
	for src in \
		"$TOOLCHAIN_LINK/usr/include/c++/v1" \
		"$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)/usr/include/c++/v1" \
		"$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)/usr/include/c++/v1"
	do
		if [[ -f "$src/cmath" ]]; then
			mkdir -p "$SDK_DIR/usr/include/c++"
			cp -R "$src" "$SDK_DIR/usr/include/c++/v1"
			log "Grafted libc++ headers from $src"
			grafted=1
			break
		fi
	done
	[[ "$grafted" -eq 1 ]] || die "could not find libc++ headers to graft into $SDK_DIR"
fi

log "Done. Toolchain: $("$TOOLCHAIN_LINK/usr/bin/clang" --version | head -1)"
if [[ "$THEOS" != "$HOME/theos" ]]; then
	log "build.sh defaults to ~/theos; export THEOS=$THEOS in your shell profile"
fi
