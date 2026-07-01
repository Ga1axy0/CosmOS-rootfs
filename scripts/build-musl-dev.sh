#!/usr/bin/env bash
set -euo pipefail

PKG=musl-dev

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"

setup_musl_toolchain

toolchain_root="$(resolve_toolchain_root)"
sysroot="$(resolve_musl_sysroot)"
gcc_version="$(resolve_gcc_version)"
gcc_libdir="$(resolve_gcc_libdir)"
include_fixed_dir="$gcc_libdir/include-fixed"

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] sysroot      : $sysroot"
echo "[INFO] gcc version  : $gcc_version"
echo "[INFO] gcc libdir   : $gcc_libdir"
log_musl_toolchain

if [ ! -d "$sysroot/include" ] || [ ! -d "$sysroot/lib" ]; then
    echo "[ERROR] 找不到 toolchain sysroot: $sysroot"
    echo "[HINT] 可选方案:"
    echo "       1. 确认 TOOLCHAIN_BIN 指向正确的 musl 交叉工具链"
    echo "       2. 手动设置 MUSL_SYSROOT=/path/to/$TARGET"
    exit 1
fi

mkdir -p \
    "$ROOTFS/usr/include" \
    "$ROOTFS/usr/lib" \
    "$ROOTFS/usr/lib/gcc/$TARGET/$gcc_version" \
    "$ROOTFS/lib"
mkdir -p "$BUILD_ROOT"

echo "[INFO] install libc / libstdc++ headers..."
cp -a "$sysroot/include/." "$ROOTFS/usr/include/"

echo "[INFO] install target runtime / startup files..."
cp -a "$sysroot/lib/." "$ROOTFS/usr/lib/"

# Native gcc commonly searches /lib first for the startup objects and a few
# core runtime libraries. Mirror the essential files there as well.
for pattern in \
    "crt*.o" \
    "libc.so" "libc.so.*" "libc.a" \
    "libm.so" "libm.so.*" "libm.a" \
    "libpthread.so" "libpthread.so.*" "libpthread.a" \
    "libdl.so" "libdl.so.*" "libdl.a" \
    "librt.so" "librt.so.*" "librt.a" \
    "libutil.so" "libutil.so.*" "libutil.a" \
    "libcrypt.so" "libcrypt.so.*" "libcrypt.a" \
    "libgcc_s.so" "libgcc_s.so.*" \
    "libstdc++.so" "libstdc++.so.*" "libstdc++.a" \
    "libstdc++fs.so" "libstdc++fs.so.*" "libstdc++fs.a"
do
    cp -a "$sysroot/lib"/$pattern "$ROOTFS/lib/" 2>/dev/null || true
done

echo "[INFO] install gcc support files..."
cp -a "$gcc_libdir/." "$ROOTFS/usr/lib/gcc/$TARGET/$gcc_version/"
if [ -d "$include_fixed_dir" ]; then
    mkdir -p "$ROOTFS/usr/lib/gcc/$TARGET/$gcc_version/include-fixed"
    cp -a "$include_fixed_dir/." "$ROOTFS/usr/lib/gcc/$TARGET/$gcc_version/include-fixed/"
fi

echo "[OK] musl-dev staged into:"
echo "     $ROOTFS/usr/include"
echo "     $ROOTFS/usr/lib"
echo "     $ROOTFS/usr/lib/gcc/$TARGET/$gcc_version"
echo "     $ROOTFS/lib"
