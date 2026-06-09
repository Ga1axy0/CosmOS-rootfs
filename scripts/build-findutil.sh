#!/usr/bin/env bash
set -e

PKG=findutils
VERSION=4.10.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="$PROJECT_ROOT/rootfs"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="$PROJECT_ROOT/build"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.xz"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"
BUILD_DIR="$BUILD_ROOT/${PKG}-${VERSION}-build"

TARGET="riscv64-linux-gnu"
CROSS_PREFIX="${TARGET}-"
PREFIX="/usr"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] tarball      : $TARBALL"
echo "[INFO] target       : $TARGET"
echo "[INFO] build dir    : $BUILD_DIR"

if [ ! -f "$TARBALL" ]; then
    echo "[ERROR] 找不到 findutils 源码包: $TARBALL"
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

export CC="${CROSS_PREFIX}gcc"
export AR="${CROSS_PREFIX}ar"
export AS="${CROSS_PREFIX}as"
export LD="${CROSS_PREFIX}ld"
export RANLIB="${CROSS_PREFIX}ranlib"
export STRIP="${CROSS_PREFIX}strip"
export FORCE_UNSAFE_CONFIGURE=1

"$SRC_DIR/configure" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --disable-nls \
    --cache-file=config.cache

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

# 常用路径补到 /bin
for x in find xargs; do
    if [ -x "$ROOTFS/usr/bin/$x" ]; then
        ln -sf "../usr/bin/$x" "$ROOTFS/bin/$x"
    fi
done

# strip
for x in find xargs locate updatedb; do
    if [ -x "$ROOTFS/usr/bin/$x" ]; then
        "$STRIP" "$ROOTFS/usr/bin/$x" 2>/dev/null || true
    fi
done

echo "[OK] findutils installed into:"
echo "     $ROOTFS/usr/bin"
echo "     $ROOTFS/bin/find  -> ../usr/bin/find"
echo "     $ROOTFS/bin/xargs -> ../usr/bin/xargs"

file "$ROOTFS/usr/bin/find" || true
file "$ROOTFS/usr/bin/xargs" || true