#!/usr/bin/env bash
set -e

PKG=util-linux
VERSION=2.40.0

# 当前脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="$PROJECT_ROOT/rootfs"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="$PROJECT_ROOT/build"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.xz"
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
    echo "[ERROR] 找不到 util-linux 源码包: $TARBALL"
    exit 1
fi

mkdir -p "$ROOTFS/bin" "$ROOTFS/usr/bin" "$ROOTFS/usr/lib"
mkdir -p "$BUILD_ROOT"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1
cd "$BUILD_DIR"

# 防止 configure 使用宿主机的 ncurses/tinfo/pkg-config
export PKG_CONFIG=/bin/false
export NCURSES_CONFIG=/bin/false
export NCURSESW_CONFIG=/bin/false
export NCURSES6_CONFIG=/bin/false
export NCURSESW6_CONFIG=/bin/false

# 强制告诉 configure：没有目标架构 tinfo/ncurses
export ac_cv_lib_tinfo_tgetent=no
export ac_cv_lib_tinfow_tgetent=no
export ac_cv_lib_ncursesw_tgetent=no
export ac_cv_lib_ncurses_tgetent=no
export ac_cv_header_ncursesw_ncurses_h=no
export ac_cv_header_ncursesw_term_h=no
export ac_cv_header_ncurses_h=no
export ac_cv_header_term_h=no

# 配置，禁用不需要的功能，尽量少依赖
"$SRC_DIR/configure" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --disable-nls \
    --disable-makeinstall-chown \
    --disable-makeinstall-setuid \
    --disable-liblastlog2 \
    --disable-ul \
    --disable-more \
    --disable-pg \
    --disable-setterm \
    --disable-mesg \
    --disable-wall \
    --disable-write \
    --without-python \
    --without-systemdsystemunitdir \
    --without-selinux \
    --without-ncurses \
    --without-readline \
    CC="$CC"

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

# 常用工具补到 /bin
UTILS_BIN_LINKS="
mount umount fdisk cfdisk blkid lslogins login logout hostname dmesg kill killall pgrep pkill renice script swapoff swapon hwclock stty mesg logger
"

for x in $UTILS_BIN_LINKS; do
    if [ -x "$ROOTFS/usr/bin/$x" ]; then
        ln -sf "../usr/bin/$x" "$ROOTFS/bin/$x"
    fi
done

# strip 二进制
find "$ROOTFS/usr/bin" -type f -exec sh -c '
for f do
    if file "$f" | grep -q "ELF"; then
        '"$STRIP"' "$f" 2>/dev/null || true
    fi
done
' sh {} +

echo "[OK] util-linux installed into:"
echo "     $ROOTFS/usr/bin"
echo "     $ROOTFS/bin -> symlinks"

file "$ROOTFS/bin/mount" || true
file "$ROOTFS/bin/umount" || true
