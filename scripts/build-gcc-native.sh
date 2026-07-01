#!/usr/bin/env bash
set -euo pipefail

PKG=gcc-native
PREFIX=/usr

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
HOST_CC="${HOST_CC:-gcc}"

setup_musl_toolchain

toolchain_root="$(resolve_toolchain_root)"
sysroot="$(resolve_musl_sysroot)"
toolchain_gcc_version="$(resolve_gcc_version)"
build_machine="$("$HOST_CC" -dumpmachine 2>/dev/null || true)"

declare -a PRECHECK_FAILURES=()
declare -a configure_args=()

record_failure() {
    local message="$1"

    PRECHECK_FAILURES+=("$message")
}

find_gcc_tarball_for_version() {
    local version="$1"
    local ext
    local candidate

    for ext in tar.xz tar.gz tar.bz2; do
        candidate="$THIRD_PARTY/gcc-${version}.${ext}"
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

resolve_gcc_source_version() {
    local version="$1"
    local fallback_version

    if [ -n "${GCC_SOURCE_VERSION:-}" ]; then
        printf '%s\n' "$GCC_SOURCE_VERSION"
        return 0
    fi

    if find_gcc_tarball_for_version "$version" >/dev/null; then
        printf '%s\n' "$version"
        return 0
    fi

    fallback_version="$(printf '%s\n' "$version" | sed -n 's/^\([0-9]\+\.[0-9]\+\)\.[0-9]\+$/\1.0/p')"
    if [ -n "$fallback_version" ] && [ "$fallback_version" != "$version" ] \
        && find_gcc_tarball_for_version "$fallback_version" >/dev/null; then
        printf '%s\n' "$fallback_version"
        return 0
    fi

    printf '%s\n' "$version"
}

read_prerequisite_archive_name() {
    local prereq_name="$1"
    local prereq_script="$src_dir/contrib/download_prerequisites"

    sed -n "s/^${prereq_name}='\\([^']*\\)'$/\\1/p" "$prereq_script" | head -n 1
}
unpack_tarball_into() {
    local tarball="$1"
    local dest_dir="$2"

    rm -rf "$dest_dir"
    mkdir -p "$dest_dir"
    tar xf "$tarball" -C "$dest_dir" --strip-components=1
}

refresh_prerequisite_config_scripts() {
    local package_dir
    local package_name
    local script_path

    for package_name in gmp mpfr mpc; do
        package_dir="$src_dir/$package_name"
        [ -d "$package_dir" ] || continue

        if [ -f "$src_dir/config.sub" ]; then
            while IFS= read -r script_path; do
                cp -f "$src_dir/config.sub" "$script_path"
            done < <(find "$package_dir" -name config.sub -type f)
        fi
        if [ -f "$src_dir/config.guess" ]; then
            while IFS= read -r script_path; do
                cp -f "$src_dir/config.guess" "$script_path"
            done < <(find "$package_dir" -name config.guess -type f)
        fi
    done
}

bridge_gcc_runtime_support_files() {
    local runtime_version_dir="$ROOTFS/usr/lib/gcc/$TARGET/$toolchain_gcc_version"
    local compiler_version_dir="$ROOTFS/usr/lib/gcc/$TARGET/$gcc_source_version"
    local pattern
    local src
    local dst

    [ "$gcc_source_version" != "$toolchain_gcc_version" ] || return 0
    [ -d "$runtime_version_dir" ] || return 0
    [ -d "$compiler_version_dir" ] || return 0

    echo "[INFO] bridge gcc runtime support: $toolchain_gcc_version -> $gcc_source_version"

    for pattern in \
        "crtbegin*.o" \
        "crtend*.o" \
        "libgcc.a" \
        "libgcc_eh.a" \
        "libgcov.a" \
        "libgcc_s.so" \
        "libgcc_s.so.*"
    do
        for src in "$runtime_version_dir"/$pattern; do
            [ -e "$src" ] || continue
            dst="$compiler_version_dir/$(basename "$src")"
            if [ ! -e "$dst" ]; then
                ln -sf "../$toolchain_gcc_version/$(basename "$src")" "$dst"
            fi
        done
    done
}

install_native_gcc_symlinks() {
    local bindir="$ROOTFS/usr/bin"

    mkdir -p "$bindir"

    if [ -x "$bindir/${TARGET}-gcc" ] && [ ! -e "$bindir/gcc" ]; then
        ln -sf "${TARGET}-gcc" "$bindir/gcc"
    fi
    if [ -x "$bindir/${TARGET}-g++" ] && [ ! -e "$bindir/g++" ]; then
        ln -sf "${TARGET}-g++" "$bindir/g++"
    fi
    if [ -x "$bindir/${TARGET}-cpp" ] && [ ! -e "$bindir/cpp" ]; then
        ln -sf "${TARGET}-cpp" "$bindir/cpp"
    fi
    if [ -x "$bindir/gcc" ] && [ ! -e "$bindir/cc" ]; then
        ln -sf gcc "$bindir/cc"
    fi
    if [ -x "$bindir/g++" ] && [ ! -e "$bindir/c++" ]; then
        ln -sf g++ "$bindir/c++"
    fi
    if [ -x "$bindir/gcc" ] && [ ! -e "$bindir/${TARGET}-gcc" ]; then
        ln -sf gcc "$bindir/${TARGET}-gcc"
    fi
    if [ -x "$bindir/g++" ] && [ ! -e "$bindir/${TARGET}-g++" ]; then
        ln -sf g++ "$bindir/${TARGET}-g++"
    fi
    if [ -x "$bindir/cpp" ] && [ ! -e "$bindir/${TARGET}-cpp" ]; then
        ln -sf cpp "$bindir/${TARGET}-cpp"
    fi
}

strip_native_gcc_binaries() {
    local strip_bin="$STRIP"
    local search_root

    for search_root in "$ROOTFS/usr/bin" "$ROOTFS/usr/libexec/gcc"; do
        [ -d "$search_root" ] || continue
        find "$search_root" -type f -exec sh -c '
strip_bin="$1"
shift
for f in "$@"; do
    if file "$f" | grep -q "ELF"; then
        "$strip_bin" "$f" 2>/dev/null || true
    fi
done
' sh "$strip_bin" {} +
    done
}

gcc_source_version="$(resolve_gcc_source_version "$toolchain_gcc_version")"
if [ -n "${GCC_TARBALL:-}" ]; then
    gcc_tarball="$GCC_TARBALL"
else
    gcc_tarball="$(find_gcc_tarball_for_version "$gcc_source_version" || true)"
    if [ -z "$gcc_tarball" ]; then
        gcc_tarball="$THIRD_PARTY/gcc-${gcc_source_version}.tar.xz"
    fi
fi
src_dir="$BUILD_ROOT/gcc-${gcc_source_version}-src"
build_dir="$BUILD_ROOT/gcc-${gcc_source_version}-build"

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] sysroot      : $sysroot"
echo "[INFO] toolchain gcc: $toolchain_gcc_version"
echo "[INFO] source gcc   : $gcc_source_version"
echo "[INFO] gcc tarball  : $gcc_tarball"
echo "[INFO] source dir   : $src_dir"
echo "[INFO] build dir    : $build_dir"
echo "[INFO] host cc      : $HOST_CC"
echo "[INFO] build triple : ${build_machine:-unknown}"
log_musl_toolchain

if ! command -v "$HOST_CC" >/dev/null 2>&1; then
    record_failure "host compiler not found: $HOST_CC"
fi
if [ -z "$build_machine" ]; then
    record_failure "cannot detect build triple from $HOST_CC -dumpmachine"
fi
if [ ! -d "$sysroot/include" ] || [ ! -d "$sysroot/lib" ]; then
    record_failure "toolchain sysroot is incomplete: $sysroot"
fi
if [ ! -f "$gcc_tarball" ]; then
    record_failure "missing native gcc source tarball: $gcc_tarball"
fi

if [ "${#PRECHECK_FAILURES[@]}" -gt 0 ]; then
    echo "[ERROR] native gcc/g++ 基础前置检查未通过:"
    for item in "${PRECHECK_FAILURES[@]}"; do
        echo "       - $item"
    done
    exit 1
fi

mkdir -p "$BUILD_ROOT"
rm -rf "$src_dir" "$build_dir"
mkdir -p "$src_dir" "$build_dir"
tar xf "$gcc_tarball" -C "$src_dir" --strip-components=1

if [ ! -f "$src_dir/contrib/download_prerequisites" ]; then
    echo "[ERROR] GCC 源码中缺少 contrib/download_prerequisites"
    exit 1
fi

gmp_archive="$(read_prerequisite_archive_name gmp)"
mpfr_archive="$(read_prerequisite_archive_name mpfr)"
mpc_archive="$(read_prerequisite_archive_name mpc)"

if [ -z "$gmp_archive" ] || [ -z "$mpfr_archive" ] || [ -z "$mpc_archive" ]; then
    echo "[ERROR] 无法从 GCC 源码中解析 gmp/mpfr/mpc 依赖版本"
    exit 1
fi

gmp_tarball="$THIRD_PARTY/$gmp_archive"
mpfr_tarball="$THIRD_PARTY/$mpfr_archive"
mpc_tarball="$THIRD_PARTY/$mpc_archive"

if [ ! -f "$gmp_tarball" ]; then
    record_failure "missing GCC prerequisite tarball: $gmp_tarball"
fi
if [ ! -f "$mpfr_tarball" ]; then
    record_failure "missing GCC prerequisite tarball: $mpfr_tarball"
fi
if [ ! -f "$mpc_tarball" ]; then
    record_failure "missing GCC prerequisite tarball: $mpc_tarball"
fi

if [ "${#PRECHECK_FAILURES[@]}" -gt 0 ]; then
    echo "[ERROR] native gcc/g++ 依赖源码不完整:"
    for item in "${PRECHECK_FAILURES[@]}"; do
        echo "       - $item"
    done
    echo "[HINT] 对于 gcc-${gcc_source_version}，请至少补齐:"
    echo "       - $gmp_archive"
    echo "       - $mpfr_archive"
    echo "       - $mpc_archive"
    echo "[HINT] 把这些源码包放到: $THIRD_PARTY"
    exit 1
fi

echo "[INFO] unpack GCC prerequisites into source tree..."
unpack_tarball_into "$gmp_tarball" "$src_dir/gmp"
unpack_tarball_into "$mpfr_tarball" "$src_dir/mpfr"
unpack_tarball_into "$mpc_tarball" "$src_dir/mpc"
refresh_prerequisite_config_scripts

configure_args=(
    "--build=$build_machine"
    "--host=$TARGET"
    "--target=$TARGET"
    "--prefix=$PREFIX"
    "--with-sysroot=/"
    "--with-build-sysroot=$ROOTFS"
    "--with-local-prefix=/usr/local"
    "--with-native-system-header-dir=/usr/include"
    "--enable-languages=c,c++"
    "--disable-bootstrap"
    "--disable-multilib"
    "--disable-nls"
    "--disable-werror"
    "--disable-libsanitizer"
    "--disable-libquadmath"
    "--disable-libgomp"
    "--disable-libssp"
    "--disable-libvtv"
    "--disable-libatomic"
    "--disable-libitm"
    "--disable-decimal-float"
    "--disable-libada"
    "--disable-libphobos"
    "--disable-libstdcxx-pch"
    "--disable-lto"
    "--without-isl"
)

echo "[INFO] configure native gcc/g++..."
(
    cd "$build_dir"
    MAKEINFO=true \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    AS="$AS" \
    LD="$LD" \
    RANLIB="$RANLIB" \
    "$src_dir/configure" "${configure_args[@]}"
)

echo "[INFO] build all-gcc..."
make -C "$build_dir" -j"$JOBS" MAKEINFO=true all-gcc

echo "[INFO] install install-gcc..."
make -C "$build_dir" DESTDIR="$ROOTFS" MAKEINFO=true install-gcc

bridge_gcc_runtime_support_files
install_native_gcc_symlinks
strip_native_gcc_binaries

echo "[OK] native gcc/g++ installed into:"
echo "     $ROOTFS/usr/bin"
echo "     $ROOTFS/usr/libexec/gcc"
echo "     $ROOTFS/usr/lib/gcc"

file "$ROOTFS/usr/bin/gcc" 2>/dev/null || true
file "$ROOTFS/usr/bin/g++" 2>/dev/null || true
find "$ROOTFS/usr/libexec/gcc" -name cc1 -o -name cc1plus 2>/dev/null | sed -n '1,8p'
