#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOTFS="$PROJECT_ROOT/rootfs"

GLIBC_LIB="${GLIBC_LIB:-/usr/riscv64-linux-gnu/lib}"
MUSL_LIB="${MUSL_LIB:-/opt/riscv64-linux-musl-cross/riscv64-linux-musl/lib}"

echo "[INFO] rootfs    : $ROOTFS"
echo "[INFO] glibc lib : $GLIBC_LIB"
echo "[INFO] musl lib  : $MUSL_LIB"

mkdir -p "$ROOTFS/lib" "$ROOTFS/usr/lib"

echo "[INFO] installing glibc runtime libs..."

if [ -d "$GLIBC_LIB" ]; then
    cp -a "$GLIBC_LIB"/ld-linux-riscv64*.so* "$ROOTFS/lib/" 2>/dev/null || true

    cp -a "$GLIBC_LIB"/libc.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libm.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libpthread.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/librt.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libdl.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libutil.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libresolv.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libnss_*.so* "$ROOTFS/lib/" 2>/dev/null || true

    cp -a "$GLIBC_LIB"/libgcc_s.so* "$ROOTFS/lib/" 2>/dev/null || true
else
    echo "[WARN] glibc lib dir not found: $GLIBC_LIB"
fi

echo "[INFO] installing musl runtime libs..."

if [ -d "$MUSL_LIB" ]; then
    if [ -e "$MUSL_LIB/libc.so" ]; then
        cp -a "$MUSL_LIB/libc.so" "$ROOTFS/lib/libc.so"
    fi

    for ld in "$MUSL_LIB"/ld-musl-riscv64*.so*; do
        [ -e "$ld" ] || continue
        name="$(basename "$ld")"

        if [ -L "$ld" ]; then
            ln -sf libc.so "$ROOTFS/lib/$name"
        else
            cp -a "$ld" "$ROOTFS/lib/$name"
        fi
    done

    if [ -e "$ROOTFS/lib/libc.so" ] && [ ! -e "$ROOTFS/lib/ld-musl-riscv64.so.1" ]; then
        ln -sf libc.so "$ROOTFS/lib/ld-musl-riscv64.so.1"
    fi
else
    echo "[WARN] musl lib dir not found: $MUSL_LIB"
fi

echo "[INFO] installed runtime loaders:"
ls -l "$ROOTFS/lib"/ld-linux-riscv64*.so* 2>/dev/null || true
ls -l "$ROOTFS/lib"/ld-musl-riscv64*.so* 2>/dev/null || true

echo "[INFO] installed libc:"
ls -l "$ROOTFS/lib"/libc.so* 2>/dev/null || true

echo "[OK] libc runtime libraries installed"