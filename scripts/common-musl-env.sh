#!/usr/bin/env bash

TARGET="${TARGET:-riscv64-linux-musl}"
CROSS_PREFIX="${CROSS_PREFIX:-${TARGET}-}"
TOOLCHAIN_BIN="${TOOLCHAIN_BIN:-/opt/riscv64-linux-musl-cross/bin}"

detect_host_jobs() {
    local jobs

    jobs="$(nproc 2>/dev/null || true)"
    if [ -z "$jobs" ] && command -v sysctl >/dev/null 2>&1; then
        jobs="$(sysctl -n hw.ncpu 2>/dev/null || true)"
    fi
    case "$jobs" in
        ''|*[!0-9]*) jobs=1 ;;
    esac
    printf '%s\n' "$jobs"
}

JOBS="${JOBS:-$(detect_host_jobs)}"

COMMON_CFLAGS="${COMMON_CFLAGS:--Os}"
COMMON_CXXFLAGS="${COMMON_CXXFLAGS:-$COMMON_CFLAGS}"
COMMON_CPPFLAGS="${COMMON_CPPFLAGS:-}"
COMMON_LDFLAGS="${COMMON_LDFLAGS:--static}"

append_flags() {
    local var_name="$1"
    local extra_flags="$2"
    local current_value="${!var_name-}"

    [ -n "$extra_flags" ] || return 0

    if [ -n "$current_value" ]; then
        export "$var_name=$current_value $extra_flags"
    else
        export "$var_name=$extra_flags"
    fi
}

ensure_musl_toolchain() {
    if command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1; then
        return 0
    fi

    if [ -x "${TOOLCHAIN_BIN}/${CROSS_PREFIX}gcc" ]; then
        export PATH="${TOOLCHAIN_BIN}:$PATH"
        return 0
    fi

    echo "[ERROR] 找不到 musl 交叉编译器: ${CROSS_PREFIX}gcc"
    echo "[HINT] 可选方案:"
    echo "       1. 把 ${CROSS_PREFIX}gcc 加到 PATH"
    echo "       2. 设置 TOOLCHAIN_BIN=/your/toolchain/bin"
    exit 1
}

setup_musl_toolchain() {
    ensure_musl_toolchain

    export CC="${CC:-${CROSS_PREFIX}gcc}"
    export CXX="${CXX:-${CROSS_PREFIX}g++}"
    export AR="${AR:-${CROSS_PREFIX}ar}"
    export AS="${AS:-${CROSS_PREFIX}as}"
    export LD="${LD:-${CROSS_PREFIX}ld}"
    export RANLIB="${RANLIB:-${CROSS_PREFIX}ranlib}"
    export STRIP="${STRIP:-${CROSS_PREFIX}strip}"
    export STRIP_BIN="${STRIP_BIN:-$STRIP}"
    export READELF_BIN="${READELF_BIN:-${CROSS_PREFIX}readelf}"
    export FORCE_UNSAFE_CONFIGURE="${FORCE_UNSAFE_CONFIGURE:-1}"

    append_flags CFLAGS "$COMMON_CFLAGS"
    append_flags CXXFLAGS "$COMMON_CXXFLAGS"
    append_flags CPPFLAGS "$COMMON_CPPFLAGS"
    append_flags LDFLAGS "$COMMON_LDFLAGS"
}

log_musl_toolchain() {
    echo "[INFO] target       : $TARGET"
    echo "[INFO] cross prefix : $CROSS_PREFIX"
    echo "[INFO] toolchain bin: $TOOLCHAIN_BIN"
    echo "[INFO] CFLAGS       : ${CFLAGS:-}"
    echo "[INFO] LDFLAGS      : ${LDFLAGS:-}"
}

resolve_toolchain_root() {
    if [ -n "${TOOLCHAIN_ROOT:-}" ]; then
        printf '%s\n' "$TOOLCHAIN_ROOT"
        return 0
    fi

    printf '%s\n' "$(cd "${TOOLCHAIN_BIN}/.." && pwd)"
}

resolve_musl_sysroot() {
    local toolchain_root

    if [ -n "${MUSL_SYSROOT:-}" ]; then
        printf '%s\n' "$MUSL_SYSROOT"
        return 0
    fi

    toolchain_root="$(resolve_toolchain_root)"
    printf '%s\n' "$toolchain_root/$TARGET"
}

resolve_gcc_base_dir() {
    local toolchain_root

    toolchain_root="$(resolve_toolchain_root)"
    printf '%s\n' "$toolchain_root/lib/gcc/$TARGET"
}

resolve_gcc_version() {
    local gcc_base
    local version_dir

    if [ -n "${GCC_VERSION:-}" ]; then
        printf '%s\n' "$GCC_VERSION"
        return 0
    fi

    gcc_base="$(resolve_gcc_base_dir)"
    if [ ! -d "$gcc_base" ]; then
        echo "[ERROR] 找不到 gcc 版本目录: $gcc_base" >&2
        return 1
    fi

    version_dir="$(
        find "$gcc_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
            | sort \
            | tail -n 1
    )"
    if [ -z "$version_dir" ]; then
        echo "[ERROR] gcc 版本目录为空: $gcc_base" >&2
        return 1
    fi

    basename "$version_dir"
}

resolve_gcc_libdir() {
    local gcc_base
    local gcc_version

    gcc_base="$(resolve_gcc_base_dir)"
    gcc_version="$(resolve_gcc_version)"
    printf '%s\n' "$gcc_base/$gcc_version"
}
