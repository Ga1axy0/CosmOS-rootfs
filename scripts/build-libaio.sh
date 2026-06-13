#!/usr/bin/env bash
set -e

PKG=libaio
VERSION=0.3.113

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.gz"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"

PREFIX="/usr"
setup_musl_toolchain
# libaio 的上游 Makefile 同时会尝试生成共享库，这里只保留 musl 交叉工具链，
# 不把全局 -static LDFLAGS 传进去，避免共享库目标和静态链接参数冲突。
unset LDFLAGS

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] tarball      : $TARBALL"
echo "[INFO] source dir   : $SRC_DIR"
log_musl_toolchain
echo "[INFO] install mode : static archive only"

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

make -j"$JOBS" \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    prefix="$PREFIX"

# libaio 的 Makefile 有时 install 行为比较怪，
# 这里手动安装最稳。
install -Dm644 src/libaio.h "$ROOTFS/usr/include/libaio.h"

if [ ! -f src/libaio.a ]; then
    echo "[ERROR] 没找到生成的静态库 src/libaio.a"
    exit 1
fi

install -Dm644 src/libaio.a "$ROOTFS/usr/lib/libaio.a"
"$RANLIB" "$ROOTFS/usr/lib/libaio.a" 2>/dev/null || true

echo "[OK] libaio static archive installed:"
ls -l "$ROOTFS/usr/lib"/libaio.a 2>/dev/null || true
ls -l "$ROOTFS/usr/include/libaio.h"

file "$ROOTFS/usr/lib/libaio.a" || true
