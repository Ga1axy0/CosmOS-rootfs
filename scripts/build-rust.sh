#!/usr/bin/env bash
set -euo pipefail

# Install a fixed RISC-V-native Rust toolchain into the rootfs.
#
# The host running this script is normally x86_64.  rustup therefore needs
# --force-non-host to download a toolchain whose binaries run on RISC-V Linux;
# this is different from `rustup target add`, which only installs target
# libraries.  The temporary rustup/cargo homes are deliberately isolated from
# the developer's normal Rust installation.

PKG=rust-toolchain

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
RUST_STAGE_ROOT="${RUST_STAGE_ROOT:-$PROJECT_ROOT/build/rust-riscv64}"

RUSTUP_BIN="${RUSTUP_BIN:-rustup}"
RUST_CHANNEL="${RUST_CHANNEL:-nightly-2026-05-28}"
RUST_HOST="${RUST_HOST:-riscv64gc-unknown-linux-gnu}"
RUST_TARGET="${RUST_TARGET:-riscv64gc-unknown-none-elf}"
RUST_PROFILE="${RUST_PROFILE:-minimal}"
RUST_INSTALL_DIR="${RUST_INSTALL_DIR:-/opt/rust-nightly-2026-05-28-riscv64gc-unknown-linux-gnu}"

RUSTUP_HOME="${RUSTUP_HOME:-$RUST_STAGE_ROOT/rustup}"
CARGO_HOME="${CARGO_HOME:-$RUST_STAGE_ROOT/cargo}"

QEMU_RISCV64="${QEMU_RISCV64:-qemu-riscv64}"
QEMU_RISCV64_LD_PREFIX="${QEMU_RISCV64_LD_PREFIX:-$ROOTFS}"

if [[ "$RUST_INSTALL_DIR" != /* ]]; then
    echo "[ERROR] RUST_INSTALL_DIR must be an absolute path: $RUST_INSTALL_DIR" >&2
    exit 2
fi

# The base rootfs and rootfs-rv are RISC-V images.  Do not put a RISC-V
# compiler into the LoongArch variant; rootfs-la is built from the same base
# directory and has its own architecture-specific toolchain.
case "${BUSYBOX_ARCH:-}" in
    loongarch|loongarch64|la)
        echo "[SKIP] $PKG is RISC-V-only; LoongArch rootfs does not receive it"
        exit 0
        ;;
esac

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

command -v "$RUSTUP_BIN" >/dev/null 2>&1 || die "rustup not found: $RUSTUP_BIN"

TOOLCHAIN_NAME="${RUST_CHANNEL}-${RUST_HOST}"
TOOLCHAIN_DIR="${RUSTUP_HOME}/toolchains/${TOOLCHAIN_NAME}"
ROOTFS_TOOLCHAIN_DIR="$ROOTFS$RUST_INSTALL_DIR"

mkdir -p "$ROOTFS" "$RUST_STAGE_ROOT" "$RUSTUP_HOME" "$CARGO_HOME"
export RUSTUP_HOME CARGO_HOME

toolchain_is_ready() {
    local required

    for required in \
        "$TOOLCHAIN_DIR/bin/rustc" \
        "$TOOLCHAIN_DIR/bin/cargo" \
        "$TOOLCHAIN_DIR/bin/rustdoc" \
        "$TOOLCHAIN_DIR/lib/rustlib/$RUST_TARGET/lib" \
        "$TOOLCHAIN_DIR/lib/rustlib/src/rust" \
        "$TOOLCHAIN_DIR/lib/rustlib/$RUST_HOST/bin/rust-lld"
    do
        [ -e "$required" ] || return 1
    done

    [ -x "$TOOLCHAIN_DIR/bin/rustc" ] || return 1
    [ -x "$TOOLCHAIN_DIR/bin/cargo" ] || return 1
    [ -x "$TOOLCHAIN_DIR/bin/rustdoc" ] || return 1
}

if toolchain_is_ready; then
    echo "[INFO] reuse Rust toolchain: $TOOLCHAIN_DIR"
else
    echo "[INFO] install Rust toolchain: $TOOLCHAIN_NAME"
    "$RUSTUP_BIN" toolchain install "$TOOLCHAIN_NAME" \
        --force-non-host \
        --force \
        --no-self-update \
        --profile "$RUST_PROFILE" \
        --component rust-src \
        --component llvm-tools-preview \
        --component rustfmt \
        --component clippy \
        --target "$RUST_TARGET"
fi

toolchain_is_ready || die "Rust toolchain is incomplete: $TOOLCHAIN_DIR"

echo "[INFO] Rust compiler:"
file "$TOOLCHAIN_DIR/bin/rustc" || true

if command -v "$QEMU_RISCV64" >/dev/null 2>&1 && [ -d "$QEMU_RISCV64_LD_PREFIX" ]; then
    echo "[INFO] probing RISC-V Rust binaries with $QEMU_RISCV64"
    "$QEMU_RISCV64" -L "$QEMU_RISCV64_LD_PREFIX" \
        "$TOOLCHAIN_DIR/bin/rustc" -vV | sed -n '1,8p'
    "$QEMU_RISCV64" -L "$QEMU_RISCV64_LD_PREFIX" \
        "$TOOLCHAIN_DIR/bin/cargo" -V
    "$QEMU_RISCV64" -L "$QEMU_RISCV64_LD_PREFIX" \
        "$TOOLCHAIN_DIR/bin/rustdoc" -V
else
    echo "[WARN] qemu-riscv64 or its loader prefix is unavailable; skip runtime probe" >&2
fi

echo "[INFO] copy fixed Rust toolchain into $ROOTFS_TOOLCHAIN_DIR"
mkdir -p "$ROOTFS_TOOLCHAIN_DIR"
cp -a "$TOOLCHAIN_DIR/." "$ROOTFS_TOOLCHAIN_DIR/"

install_rootfs_wrapper() {
    local tool_name="$1"
    local source_path="$2"
    local guest_path="$3"
    local wrapper_path="$ROOTFS/usr/bin/$tool_name"

    [ -e "$source_path" ] || return 0
    mkdir -p "$ROOTFS/usr/bin"

    # The Rust executables use an $ORIGIN/../lib RPATH.  A symlink under
    # /usr/bin changes $ORIGIN and makes librustc_driver unavailable.  Keep
    # /usr/bin as a real wrapper so the executable still sees its own /opt
    # directory while the dynamic loader also sees the Rust shared libraries.
    rm -f "$wrapper_path"
    printf '%s\n' '#!/bin/sh' > "$wrapper_path"
    if [[ "$tool_name" == cargo ]]; then
        # bindgen is loaded by Cargo build scripts.  These paths are harmless
        # before build-libclang-riscv64 runs and keep wrapper regeneration
        # from discarding the libclang environment.
        printf '%s\n' \
            'export LIBCLANG_PATH="/usr/lib/llvm-18/lib"' \
            'export LD_LIBRARY_PATH="/usr/lib/llvm-18/lib:/usr/lib/riscv64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
            >> "$wrapper_path"
    fi
    printf 'export LD_LIBRARY_PATH="%s${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\n' \
        "$RUST_INSTALL_DIR/lib" >> "$wrapper_path"
    printf 'exec "%s" "$@"\n' "$guest_path" >> "$wrapper_path"
    chmod 0755 "$wrapper_path"
}

# Expose the real binaries through wrappers.  Do not copy ~/.cargo/bin
# proxies: those are rustup shims and would look for a guest-side rustup
# installation.
for tool_name in cargo cargo-clippy cargo-fmt rustc rustdoc rustfmt clippy-driver; do
    install_rootfs_wrapper "$tool_name" \
        "$ROOTFS_TOOLCHAIN_DIR/bin/$tool_name" \
        "$RUST_INSTALL_DIR/bin/$tool_name"
done

# The StarryOS Cargo config uses rust-lld.  Expose the LLVM tools as well so
# cargo-binutils-style build steps can work without another package manager.
LLVM_BIN_DIR="$TOOLCHAIN_DIR/lib/rustlib/$RUST_HOST/bin"
for tool_path in "$LLVM_BIN_DIR"/*; do
    [ -e "$tool_path" ] || continue
    tool_name="$(basename "$tool_path")"
    case "$tool_name" in
        rust-lld|rust-objcopy|llvm-*|llc|opt|wasm-component-ld)
            install_rootfs_wrapper "$tool_name" \
                "$ROOTFS_TOOLCHAIN_DIR/lib/rustlib/$RUST_HOST/bin/$tool_name" \
                "$RUST_INSTALL_DIR/lib/rustlib/$RUST_HOST/bin/$tool_name"
            ;;
    esac
done

echo "[OK] $PKG installed"
echo "     host   : $RUST_HOST"
echo "     target : $RUST_TARGET"
echo "     path   : $ROOTFS_TOOLCHAIN_DIR"
du -sh "$ROOTFS_TOOLCHAIN_DIR" 2>/dev/null || true
