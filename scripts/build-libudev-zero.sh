#!/usr/bin/env bash
set -euo pipefail

# Build only the static libudev compatibility library needed by Cargo host
# crates.  These crates run as riscv64gc-unknown-linux-gnu programs, so the
# archive must use the GNU/glibc ABI rather than the rootfs's musl ABI.

PKG=libudev-zero
VERSION=1.0.4

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
GLIBC_SYSROOT="${GLIBC_SYSROOT:-/usr/riscv64-linux-gnu}"
GLIBC_SYSROOT_DIR="${GLIBC_SYSROOT_DIR:-/opt/riscv64-linux-gnu-sysroot}"
GLIBC_CLANG_TARGET="${GLIBC_CLANG_TARGET:-riscv64-linux-gnu}"
HOST_CLANG="${HOST_CLANG:-clang}"
HOST_AR="${HOST_AR:-ar}"
HOST_RANLIB="${HOST_RANLIB:-ranlib}"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.gz"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"
GUEST_SYSROOT="$ROOTFS$GLIBC_SYSROOT_DIR"

case "${BUSYBOX_ARCH:-}" in
    loongarch|loongarch64|la)
        echo "[SKIP] $PKG is only needed by the RISC-V self-hosting toolchain"
        exit 0
        ;;
esac

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

[ -f "$TARBALL" ] || die "libudev-zero source archive not found: $TARBALL"
[ -d "$GLIBC_SYSROOT/include" ] || die "glibc source sysroot headers not found: $GLIBC_SYSROOT/include"
[ -d "$GUEST_SYSROOT/lib" ] || die "guest glibc sysroot is not prepared: $GUEST_SYSROOT (run build-glibc-host-sysroot first)"
command -v "$HOST_CLANG" >/dev/null 2>&1 || die "host Clang not found: $HOST_CLANG"
command -v "$HOST_AR" >/dev/null 2>&1 || die "host ar not found: $HOST_AR"
command -v "$HOST_RANLIB" >/dev/null 2>&1 || die "host ranlib not found: $HOST_RANLIB"

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] tarball      : $TARBALL"
echo "[INFO] source dir   : $SRC_DIR"
echo "[INFO] source sysroot: $GLIBC_SYSROOT"
echo "[INFO] guest sysroot : $GLIBC_SYSROOT_DIR"
echo "[INFO] clang target  : $GLIBC_CLANG_TARGET"

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

glibc_cc="$HOST_CLANG --target=$GLIBC_CLANG_TARGET --sysroot=$GLIBC_SYSROOT"

make -C "$SRC_DIR" -j"$JOBS" libudev.a libudev.pc \
    CC="$glibc_cc" \
    AR="$HOST_AR" \
    CFLAGS=-O2 \
    PREFIX="$GLIBC_SYSROOT_DIR" \
    LIBDIR="$GLIBC_SYSROOT_DIR/lib" \
    INCLUDEDIR="$GLIBC_SYSROOT_DIR/include" \
    PKGCONFIGDIR="$GLIBC_SYSROOT_DIR/lib/pkgconfig" \
    USB_IDS_PATH=/usr/share/hwdata/usb.ids

if ! file "$SRC_DIR/udev.o" | grep -q 'RISC-V'; then
    file "$SRC_DIR/udev.o" >&2 || true
    die "libudev-zero was not compiled for RISC-V"
fi

install -Dm644 "$SRC_DIR/libudev.a" "$GUEST_SYSROOT/lib/libudev.a"
install -Dm644 "$SRC_DIR/udev.h" "$GUEST_SYSROOT/include/libudev.h"
install -Dm644 "$SRC_DIR/libudev.pc" "$GUEST_SYSROOT/lib/pkgconfig/libudev.pc"
"$HOST_RANLIB" "$GUEST_SYSROOT/lib/libudev.a"

echo "[OK] static GNU libudev compatibility library installed:"
file "$SRC_DIR/udev.o"
ls -l \
    "$GUEST_SYSROOT/lib/libudev.a" \
    "$GUEST_SYSROOT/include/libudev.h" \
    "$GUEST_SYSROOT/lib/pkgconfig/libudev.pc"

