#!/usr/bin/env bash
set -e

PKG=binutils
VERSION=2.41

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
    echo "[ERROR] 找不到 binutils 源码包: $TARBALL"
    exit 1
fi

mkdir -p "$BUILD_ROOT" "$ROOTFS/usr/bin" "$ROOTFS/usr/lib" "$ROOTFS/bin"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

cd "$BUILD_DIR"

BUILD="$(gcc -dumpmachine)"

"$SRC_DIR/configure" \
    --build="$BUILD" \
    --host="$TARGET" \
    --target="$TARGET" \
    --prefix="$PREFIX" \
    --disable-nls \
    --disable-werror \
    --disable-multilib \
    --disable-gdb \
    --disable-gprofng \
    CC="$CC" \
    AR="$AR" \
    AS="$AS" \
    LD="$LD" \
    RANLIB="$RANLIB"

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

# 如果生成的是 ${TARGET}-ar 这种前缀名字，就补成 ar
BINUTILS_CMDS="as ld ar nm objdump readelf ranlib strip size strings objcopy addr2line c++filt elfedit"

for x in $BINUTILS_CMDS; do
    if [ -x "$ROOTFS/usr/bin/${TARGET}-$x" ] && [ ! -e "$ROOTFS/usr/bin/$x" ]; then
        ln -sf "${TARGET}-$x" "$ROOTFS/usr/bin/$x"
    fi

    if [ -x "$ROOTFS/usr/bin/$x" ]; then
        ln -sf "../usr/bin/$x" "$ROOTFS/bin/$x"
    fi
done

# strip 只能 strip ELF，且不要因为失败中断
find "$ROOTFS/usr/bin" -type f -exec sh -c '
for f do
    if file "$f" | grep -q "ELF"; then
        '"$STRIP"' "$f" 2>/dev/null || true
    fi
done
' sh {} +

echo "[OK] binutils installed into:"
echo "     $ROOTFS/usr/bin"
echo "     $ROOTFS/bin -> symlinks"

echo "[INFO] check native names:"
file "$ROOTFS/usr/bin/ar" || true
file "$ROOTFS/usr/bin/ld" || true
file "$ROOTFS/usr/bin/as" || true
file "$ROOTFS/usr/bin/objdump" || true
file "$ROOTFS/usr/bin/readelf" || true

echo "[INFO] check prefixed names:"
file "$ROOTFS/usr/bin/${TARGET}-ar" || true
file "$ROOTFS/usr/bin/${TARGET}-ld" || true
file "$ROOTFS/usr/bin/${TARGET}-as" || true
