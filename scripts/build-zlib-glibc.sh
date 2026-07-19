#!/usr/bin/env bash
set -euo pipefail

# Build the static zlib development package used by Cargo host crates.  The
# Rust host target is riscv64gc-unknown-linux-gnu, so this archive must use the
# GNU/glibc ABI and live beside the isolated glibc host sysroot rather than in
# the native guest's musl /usr/lib.

PKG=zlib
VERSION=1.3.2
SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16

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
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-glibc-src"
GUEST_SYSROOT="$ROOTFS$GLIBC_SYSROOT_DIR"

case "${BUSYBOX_ARCH:-}" in
    loongarch|loongarch64|la)
        echo "[SKIP] $PKG GNU host library is only needed by the RISC-V Rust toolchain"
        exit 0
        ;;
esac

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

[ -f "$TARBALL" ] || die "zlib source archive not found: $TARBALL"
[ -d "$GLIBC_SYSROOT/include" ] || die "glibc source sysroot headers not found: $GLIBC_SYSROOT/include"
[ -d "$GUEST_SYSROOT/lib" ] || \
    die "guest glibc sysroot is not prepared: $GUEST_SYSROOT (run build-glibc-host-sysroot first)"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found"
command -v "$HOST_CLANG" >/dev/null 2>&1 || die "host Clang not found: $HOST_CLANG"
command -v "$HOST_AR" >/dev/null 2>&1 || die "host ar not found: $HOST_AR"
command -v "$HOST_RANLIB" >/dev/null 2>&1 || die "host ranlib not found: $HOST_RANLIB"

actual_sha256="$(sha256sum "$TARBALL" | awk '{print $1}')"
[ "$actual_sha256" = "$SHA256" ] || \
    die "zlib archive checksum mismatch: expected $SHA256, got $actual_sha256"

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

(
    cd "$SRC_DIR"
    CHOST="$GLIBC_CLANG_TARGET" \
        CC="$glibc_cc" \
        AR="$HOST_AR" \
        RANLIB="$HOST_RANLIB" \
        CFLAGS="-O2 -fPIC" \
        ./configure \
            --static \
            --prefix="$GLIBC_SYSROOT_DIR" \
            --libdir="$GLIBC_SYSROOT_DIR/lib" \
            --includedir="$GLIBC_SYSROOT_DIR/include"

    # zlib's configure links feature probes.  This host intentionally carries
    # only the target glibc sysroot (without a complete target GCC runtime), so
    # those probes cannot link and incorrectly add NO_STRERROR/NO_vsnprintf.
    # Both interfaces are guaranteed by the glibc headers staged above; remove
    # only those false-negative defines before compiling the static archive.
    sed -i \
        -e 's/ -DNO_STRERROR//g' \
        -e 's/ -DNO_vsnprintf//g' \
        Makefile
    if grep -qE 'DNO_(STRERROR|vsnprintf)' Makefile; then
        die "failed to correct zlib configure feature probes"
    fi

    make -j"$JOBS" libz.a
    make install DESTDIR="$ROOTFS"
)

if ! file "$SRC_DIR/adler32.o" | grep -q 'RISC-V'; then
    file "$SRC_DIR/adler32.o" >&2 || true
    die "zlib was not compiled for RISC-V"
fi

for required in \
    "$GUEST_SYSROOT/include/zlib.h" \
    "$GUEST_SYSROOT/include/zconf.h" \
    "$GUEST_SYSROOT/lib/libz.a" \
    "$GUEST_SYSROOT/lib/pkgconfig/zlib.pc"
do
    [ -s "$required" ] || die "zlib installation is incomplete: $required"
done

"$HOST_RANLIB" "$GUEST_SYSROOT/lib/libz.a"

echo "[OK] static GNU zlib development package installed:"
file "$SRC_DIR/adler32.o"
ls -l \
    "$GUEST_SYSROOT/include/zlib.h" \
    "$GUEST_SYSROOT/include/zconf.h" \
    "$GUEST_SYSROOT/lib/libz.a" \
    "$GUEST_SYSROOT/lib/pkgconfig/zlib.pc"
