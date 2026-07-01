#!/usr/bin/env bash
set -euo pipefail

PKG=ncurses
VERSION=6.5

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.gz"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"
BUILD_DIR="$BUILD_ROOT/${PKG}-${VERSION}-build"
TERMINFO_SRC_SUBDIR="$SRC_DIR/misc"

PREFIX="/usr"
setup_musl_toolchain

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] tarball      : $TARBALL"
echo "[INFO] build dir    : $BUILD_DIR"
log_musl_toolchain

if [ ! -f "$TARBALL" ]; then
    echo "[ERROR] 找不到 ncurses 源码包: $TARBALL"
    echo "[HINT] 请先把 ncurses-${VERSION}.tar.gz 放到 third-party/"
    exit 1
fi

mkdir -p "$ROOTFS/usr/include" "$ROOTFS/usr/lib" "$ROOTFS/usr/share/terminfo"
mkdir -p "$BUILD_ROOT"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1
cd "$BUILD_DIR"

"$SRC_DIR/configure" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --without-shared \
    --with-normal \
    --without-debug \
    --without-ada \
    --without-cxx \
    --without-cxx-binding \
    --without-manpages \
    --without-progs \
    --without-tests \
    --enable-widec \
    --disable-home-terminfo \
    CC="$CC"

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

HOST_TIC="${HOST_TIC:-$(command -v tic || true)}"
if [ -z "$HOST_TIC" ]; then
    echo "[ERROR] 找不到宿主机 tic，无法生成 terminfo 数据库"
    echo "[HINT] 请安装 ncurses/terminfo 工具，或设置 HOST_TIC=/path/to/tic"
    exit 1
fi

echo "[INFO] host tic     : $HOST_TIC"
cross_compiling=yes \
TIC_PATH="$HOST_TIC" \
DESTDIR="$ROOTFS" \
source="$TERMINFO_SRC_SUBDIR/terminfo.src" \
sh "$BUILD_DIR/misc/run_tic.sh"

if [ -f "$ROOTFS/usr/lib/libncursesw.a" ]; then
    ln -snf libncursesw.a "$ROOTFS/usr/lib/libncurses.a"
    ln -snf libncursesw.a "$ROOTFS/usr/lib/libtinfo.a"
fi

echo "[OK] ncurses installed into:"
echo "     $ROOTFS/usr/include"
echo "     $ROOTFS/usr/lib"
echo "     $ROOTFS/usr/share/terminfo"
