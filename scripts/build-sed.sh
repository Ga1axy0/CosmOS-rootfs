#!/usr/bin/env bash
set -e

PKG=sed
VERSION=4.9

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
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
    echo "[ERROR] 找不到 sed 源码包: $TARBALL"
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
gl_cv_func_mbrtowc_incomplete_state=yes
gl_cv_func_mbrtowc_nul_retval=yes
gl_cv_func_mbrtowc_retval=yes
gl_cv_func_mbsrtowcs_works=yes
gl_cv_func_wcrtomb_works=yes
gl_cv_func_wctob_works=yes
gl_cv_func_btowc_eof=yes
EOF

"$SRC_DIR/configure" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --disable-nls \
    --cache-file=config.cache

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

# sed 常见脚本会找 /bin/sed
if [ -x "$ROOTFS/usr/bin/sed" ]; then
    ln -sf "../usr/bin/sed" "$ROOTFS/bin/sed"
fi

# strip
if [ -x "$ROOTFS/usr/bin/sed" ]; then
    "$STRIP" "$ROOTFS/usr/bin/sed" 2>/dev/null || true
fi

echo "[OK] sed installed into:"
echo "     $ROOTFS/usr/bin/sed"
echo "     $ROOTFS/bin/sed -> ../usr/bin/sed"

file "$ROOTFS/usr/bin/sed" || true
