#!/usr/bin/env bash
# One-time (idempotent) macOS setup for building Theta.
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
#   6. make sure $THEOS/vendor/lib has CydiaSubstrate.framework (sideload link step)
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

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only"
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

# 6. CydiaSubstrate for the link step (-F$THEOS/vendor/lib -weak_framework CydiaSubstrate)
if [[ -d "$THEOS/vendor/lib/CydiaSubstrate.framework/Headers" ]]; then
	log "Theos vendors CydiaSubstrate.framework"
else
	log "Copying third_party/CydiaSubstrate.framework into $THEOS/vendor/lib"
	mkdir -p "$THEOS/vendor/lib"
	rm -rf "$THEOS/vendor/lib/CydiaSubstrate.framework"
	cp -R "$REPO_DIR/third_party/CydiaSubstrate.framework" "$THEOS/vendor/lib/"
fi

log "Done. Toolchain: $("$TOOLCHAIN_LINK/usr/bin/clang" --version | head -1)"
if [[ "$THEOS" != "$HOME/theos" ]]; then
	log "build.sh defaults to ~/theos; export THEOS=$THEOS in your shell profile"
fi
