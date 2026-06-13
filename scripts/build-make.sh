#!/usr/bin/env bash
set -e

PKG=make
VERSION=4.4.1

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
    echo "[ERROR] 找不到 make 源码包: $TARBALL"
    exit 1
fi

mkdir -p "$ROOTFS/bin" "$ROOTFS/usr/bin" "$ROOTFS/usr/lib"
mkdir -p "$BUILD_ROOT"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

cd "$BUILD_DIR"

cat > config.cache <<'EOF'
ac_cv_func_malloc_0_nonnull=yes
ac_cv_func_realloc_0_nonnull=yes
gl_cv_func_working_mkstemp=yes
gl_cv_func_getcwd_null=yes
gl_cv_func_getcwd_path_max=yes
EOF

"$SRC_DIR/configure" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --disable-nls \
    --cache-file=config.cache \
    CC="$CC"

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

# 常见脚本可能找 /bin/make
if [ -x "$ROOTFS/usr/bin/make" ]; then
    ln -sf "../usr/bin/make" "$ROOTFS/bin/make"
fi

if [ -x "$ROOTFS/usr/bin/make" ]; then
    "$STRIP" "$ROOTFS/usr/bin/make" 2>/dev/null || true
fi

echo "[OK] make installed into:"
echo "     $ROOTFS/usr/bin/make"
echo "     $ROOTFS/bin/make -> ../usr/bin/make"

file "$ROOTFS/usr/bin/make" || true
