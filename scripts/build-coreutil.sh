#!/usr/bin/env bash
set -e

PKG=coreutils
VERSION=9.5

# 当前脚本路径：scripts/build-coreutil.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"

# 项目根目录：scripts 的上一级
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"

TARBALL="$THIRD_PARTY/coreutils-${VERSION}.tar.xz"
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
    echo "[ERROR] 找不到源码包: $TARBALL"
    exit 1
fi

mkdir -p "$BUILD_ROOT"
mkdir -p "$ROOTFS/bin" "$ROOTFS/usr/bin" "$ROOTFS/usr/lib"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

cd "$BUILD_DIR"

cat > config.cache <<EOF
ac_cv_func_malloc_0_nonnull=yes
ac_cv_func_realloc_0_nonnull=yes
gl_cv_func_working_mkstemp=yes
gl_cv_func_getcwd_null=yes
gl_cv_func_getcwd_path_max=yes
gl_cv_func_chown_follows_symlink=yes
gl_cv_func_link_follows_symlink=yes
gl_cv_func_link_works=yes
gl_cv_func_readlink_works=yes
gl_cv_func_unlink_honors_slashes=yes
gl_cv_func_mkdir_trailing_dot_works=yes
gl_cv_func_mkdir_trailing_slash_works=yes
gl_cv_func_rmdir_works=yes
gl_cv_func_stat_file_slash=yes
gl_cv_func_stat_dir_slash=yes
gl_cv_func_lstat_dereferences_slashed_symlink=yes
gl_cv_func_tzset_clobber=no
gl_cv_func_strtod_works=yes
gl_cv_func_strtold_works=yes
gl_cv_func_printf_directive_n=yes
gl_cv_func_printf_infinite=yes
gl_cv_func_printf_infinite_long_double=yes
gl_cv_func_printf_sizes_c99=yes
gl_cv_func_printf_long_double=yes
EOF

"$SRC_DIR/configure" \
    --host="$TARGET" \
    --build="$("$SRC_DIR/build-aux/config.guess")" \
    --prefix="$PREFIX" \
    --disable-nls \
    --cache-file=config.cache

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

# 给 /bin 补常用软链接
COREUTILS_BIN_LINKS="
cat chmod chown cp date dd df echo false ln ls mkdir mknod mv pwd rm rmdir
sleep stty sync true uname basename dirname env expr hostname id printf test
"

for x in $COREUTILS_BIN_LINKS; do
    if [ -x "$ROOTFS/usr/bin/$x" ]; then
        ln -sf "../usr/bin/$x" "$ROOTFS/bin/$x"
    fi
done

if [ -x "$ROOTFS/usr/bin/[" ]; then
    ln -sf "../usr/bin/[" "$ROOTFS/bin/["
fi

# strip 减小体积
find "$ROOTFS/usr/bin" -type f -exec sh -c '
    for f do
        if file "$f" | grep -q "ELF"; then
            '"$STRIP"' "$f" 2>/dev/null || true
        fi
    done
' sh {} +

echo "[OK] coreutils installed into:"
echo "     $ROOTFS/usr/bin"
echo "     $ROOTFS/bin -> symlinks"

file "$ROOTFS/usr/bin/ls" || true
