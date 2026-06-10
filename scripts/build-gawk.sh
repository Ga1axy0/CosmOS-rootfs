#!/usr/bin/env bash
set -e

PKG=gawk
VERSION=5.4.0

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
    echo "[ERROR] 找不到 gawk 源码包: $TARBALL"
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

# awk 常用路径补到 /bin
if [ -x "$ROOTFS/usr/bin/gawk" ]; then
    ln -sf "../usr/bin/gawk" "$ROOTFS/bin/gawk"
    ln -sf "../usr/bin/gawk" "$ROOTFS/bin/awk"
fi

if [ -x "$ROOTFS/usr/bin/awk" ]; then
    ln -sf "../usr/bin/awk" "$ROOTFS/bin/awk"
fi

# strip
for x in gawk awk; do
    if [ -x "$ROOTFS/usr/bin/$x" ]; then
        "$STRIP" "$ROOTFS/usr/bin/$x" 2>/dev/null || true
    fi
done

echo "[OK] gawk installed into:"
echo "     $ROOTFS/usr/bin/gawk"
echo "     $ROOTFS/bin/gawk -> ../usr/bin/gawk"
echo "     $ROOTFS/bin/awk  -> ../usr/bin/gawk or ../usr/bin/awk"

file "$ROOTFS/usr/bin/gawk" || true
