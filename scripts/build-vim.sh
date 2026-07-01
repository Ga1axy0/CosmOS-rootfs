#!/usr/bin/env bash
set -euo pipefail

PKG=vim
VERSION=9.1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.gz"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"
BUILD_DIR="$BUILD_ROOT/${PKG}-${VERSION}-build"

PREFIX="/usr"
setup_musl_toolchain

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] tarball      : $TARBALL"
echo "[INFO] build dir    : $BUILD_DIR"
log_musl_toolchain

if [ ! -f "$TARBALL" ]; then
    echo "[ERROR] 找不到 vim 源码包: $TARBALL"
    echo "[HINT] 请先把 vim-${VERSION}.tar.gz 放到 third-party/"
    exit 1
fi

if [ ! -f "$ROOTFS/usr/lib/libncursesw.a" ]; then
    echo "[ERROR] vim 依赖 ncurses，请先执行 build-ncurses 或在 rootfs-init 时加 WITH_VIM=1"
    exit 1
fi

mkdir -p "$ROOTFS/usr/bin" "$ROOTFS/bin" "$ROOTFS/usr/share"
mkdir -p "$BUILD_ROOT"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1
# Vim 顶层 configure 只是一个跳板脚本，要求在源码树内部运行。
# 这里直接进入 src/ 做原地配置，避免 out-of-tree 调用失败。
cd "$SRC_DIR/src"

export CPPFLAGS="${CPPFLAGS:-} -I$ROOTFS/usr/include -I$ROOTFS/usr/include/ncursesw"
export LDFLAGS="${LDFLAGS:-} -L$ROOTFS/usr/lib"
export LIBS="${LIBS:-} -lncursesw"
export PKG_CONFIG="${PKG_CONFIG:-no}"
export PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-/nonexistent}"
export PKG_CONFIG_PATH=

vim_cv_getcwd_broken=no \
vim_cv_memmove_handles_overlap=yes \
vim_cv_bcopy_handles_overlap=yes \
vim_cv_memcpy_handles_overlap=yes \
vim_cv_stat_ignores_slash=yes \
vim_cv_terminfo=yes \
vim_cv_tgetent=zero \
vim_cv_toupper_broken=no \
./configure \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --disable-nls \
    --disable-gui \
    --without-x \
    --disable-selinux \
    --disable-xsmp \
    --disable-netbeans \
    --with-features=normal \
    --with-tlib=ncursesw \
    --enable-multibyte \
    CC="$CC"

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

if [ -x "$ROOTFS/usr/bin/vim" ]; then
    ln -snf ../usr/bin/vim "$ROOTFS/bin/vim"
    ln -snf vim "$ROOTFS/usr/bin/vi"
    "$STRIP" "$ROOTFS/usr/bin/vim" 2>/dev/null || true
fi

echo "[OK] vim installed into:"
echo "     $ROOTFS/usr/bin/vim"
echo "     $ROOTFS/usr/bin/vi -> vim"
echo "     $ROOTFS/bin/vim -> ../usr/bin/vim"
