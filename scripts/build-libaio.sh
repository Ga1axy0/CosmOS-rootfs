#!/usr/bin/env bash
set -e

PKG=libaio
VERSION=0.3.113

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="$PROJECT_ROOT/rootfs"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="$PROJECT_ROOT/build"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.gz"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"

TARGET="riscv64-linux-gnu"
CROSS_PREFIX="${TARGET}-"
PREFIX="/usr"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] tarball      : $TARBALL"
echo "[INFO] target       : $TARGET"
echo "[INFO] source dir   : $SRC_DIR"

if [ ! -f "$TARBALL" ]; then
    echo "[ERROR] 找不到 libaio 源码包: $TARBALL"
    echo "[HINT] wget https://releases.pagure.org/libaio/libaio-${VERSION}.tar.gz -P third-party"
    exit 1
fi

mkdir -p "$BUILD_ROOT"
mkdir -p "$ROOTFS/usr/lib" "$ROOTFS/usr/include"

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

cd "$SRC_DIR"

export CC="${CROSS_PREFIX}gcc"
export AR="${CROSS_PREFIX}ar"
export RANLIB="${CROSS_PREFIX}ranlib"
export STRIP="${CROSS_PREFIX}strip"

make -j"$JOBS" \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    prefix="$PREFIX"

# libaio 的 Makefile 有时 install 行为比较怪，
# 这里手动安装最稳。
install -Dm644 src/libaio.h "$ROOTFS/usr/include/libaio.h"

if [ -f src/libaio.a ]; then
    install -Dm644 src/libaio.a "$ROOTFS/usr/lib/libaio.a"
    "$RANLIB" "$ROOTFS/usr/lib/libaio.a" 2>/dev/null || true
fi

# 共享库一般是 src/libaio.so.1.0.2
SO_REAL="$(find src -maxdepth 1 -type f -name 'libaio.so.*.*.*' | head -n 1)"

if [ -z "$SO_REAL" ]; then
    echo "[ERROR] 没找到生成的 libaio.so.x.y.z"
    find src -maxdepth 1 -name 'libaio.so*' -ls
    exit 1
fi

SO_BASENAME="$(basename "$SO_REAL")"

install -Dm755 "$SO_REAL" "$ROOTFS/usr/lib/$SO_BASENAME"

ln -sf "$SO_BASENAME" "$ROOTFS/usr/lib/libaio.so.1"
ln -sf "libaio.so.1" "$ROOTFS/usr/lib/libaio.so"

"$STRIP" "$ROOTFS/usr/lib/$SO_BASENAME" 2>/dev/null || true

echo "[OK] libaio installed:"
ls -l "$ROOTFS/usr/lib"/libaio.so*
ls -l "$ROOTFS/usr/lib"/libaio.a 2>/dev/null || true
ls -l "$ROOTFS/usr/include/libaio.h"

file "$ROOTFS/usr/lib/$SO_BASENAME" || true
"${CROSS_PREFIX}readelf" -d "$ROOTFS/usr/lib/$SO_BASENAME" | grep SONAME || true