#!/usr/bin/env bash
set -e

PKG=procps-ng
VERSION=4.0.5

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
    echo "[ERROR] 找不到 procps-ng 源码包: $TARBALL"
    exit 1
fi

mkdir -p "$ROOTFS/bin" "$ROOTFS/sbin" \
         "$ROOTFS/usr/bin" "$ROOTFS/usr/sbin" "$ROOTFS/usr/lib"
mkdir -p "$BUILD_ROOT"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

cd "$BUILD_DIR"

"$SRC_DIR/configure" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --exec-prefix="$PREFIX" \
    --disable-nls \
    --disable-modern-top \
    --disable-kill \
    --without-systemd \
    --without-ncurses \
    --without-libcap \
    --without-selinux \
    CC="$CC"

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

for x in ps free uptime vmstat pgrep pkill pmap pwdx tload watch top slabtop; do
    if [ -x "$ROOTFS/usr/bin/$x" ]; then
        ln -sf "../usr/bin/$x" "$ROOTFS/bin/$x"
    fi
done

if [ -x "$ROOTFS/usr/sbin/sysctl" ]; then
    ln -sf "../usr/sbin/sysctl" "$ROOTFS/sbin/sysctl"
fi

find "$ROOTFS/usr/bin" "$ROOTFS/usr/sbin" -type f -exec sh -c '
for f do
    if file "$f" | grep -q "ELF"; then
        '"$STRIP"' "$f" 2>/dev/null || true
    fi
done
' sh {} +

echo "[OK] procps-ng installed into:"
echo "     $ROOTFS/usr/bin"
echo "     $ROOTFS/usr/sbin"

file "$ROOTFS/usr/bin/ps" || true
file "$ROOTFS/usr/bin/free" || true
file "$ROOTFS/usr/bin/uptime" || true
