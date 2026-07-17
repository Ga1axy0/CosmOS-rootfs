#!/usr/bin/env bash
set -euo pipefail

# Build a guest-native pkg-config implementation.  The tool itself is linked
# statically against musl so it can run in the minimal rootfs, while its search
# path also covers the isolated glibc sysroot used by Cargo host crates.

PKG=pkgconf
VERSION=3.0.3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
GLIBC_SYSROOT_DIR="${GLIBC_SYSROOT_DIR:-/opt/riscv64-linux-gnu-sysroot}"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.gz"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"

case "${BUSYBOX_ARCH:-}" in
    loongarch|loongarch64|la)
        echo "[SKIP] $PKG is only needed by the RISC-V self-hosting toolchain"
        exit 0
        ;;
esac

setup_musl_toolchain

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] tarball      : $TARBALL"
echo "[INFO] source dir   : $SRC_DIR"
echo "[INFO] glibc sysroot: $GLIBC_SYSROOT_DIR"
log_musl_toolchain

if [ ! -f "$TARBALL" ]; then
    echo "[ERROR] pkgconf source archive not found: $TARBALL" >&2
    exit 1
fi

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR" "$ROOTFS/usr/bin"
tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

make -C "$SRC_DIR" -f Makefile.lite -j"$JOBS" \
    CC="$CC" \
    STRIP="$STRIP" \
    STATIC=-static \
    SYSTEM_LIBDIR=/lib:/usr/lib \
    SYSTEM_INCLUDEDIR=/usr/include \
    PKG_DEFAULT_PATH="$GLIBC_SYSROOT_DIR/lib/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"

install -Dm755 "$SRC_DIR/pkgconf-lite" "$ROOTFS/usr/bin/pkgconf"
ln -snf pkgconf "$ROOTFS/usr/bin/pkg-config"

echo "[OK] guest pkg-config installed:"
file "$ROOTFS/usr/bin/pkgconf"
ls -l "$ROOTFS/usr/bin/pkg-config"

