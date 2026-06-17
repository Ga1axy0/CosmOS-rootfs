#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"

TARGET="${TARGET:-riscv64-linux-musl}"
MUSL_ARCH="${MUSL_ARCH:-${TARGET%%-*}}"
MUSL_LIB="${MUSL_LIB:-/opt/riscv64-linux-musl-cross/riscv64-linux-musl/lib}"

glibc_lib_candidates() {
    local toolchain="$1"
    local gnu_target="$2"

    printf '%s\n' \
        "$toolchain/$gnu_target/lib64" \
        "$toolchain/$gnu_target/lib" \
        "$toolchain/sysroot/usr/lib64" \
        "$toolchain/sysroot/usr/lib" \
        "$toolchain/sysroot/lib64" \
        "$toolchain/sysroot/lib" \
        "$toolchain/lib64" \
        "$toolchain/lib"
}

find_glibc_lib() {
    local toolchain="$1"
    local gnu_target="${GLIBC_TARGET:-${MUSL_ARCH}-linux-gnu}"
    local candidate
    local fallback=""

    [ -n "$toolchain" ] || return 1

    while IFS= read -r candidate; do
        if [ ! -d "$candidate" ]; then
            continue
        fi

        if [ -z "$fallback" ]; then
            fallback="$candidate"
        fi

        if compgen -G "$candidate/ld-linux*.so*" >/dev/null \
            || [ -e "$candidate/libc.so.6" ] \
            || [ -e "$candidate/libm.so.6" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(glibc_lib_candidates "$toolchain" "$gnu_target")

    if [ -n "$fallback" ]; then
        printf '%s\n' "$fallback"
        return 0
    fi

    return 1
}

copy_first_runtime_match() {
    local pattern="$1"
    shift

    local candidate
    for candidate in "$@"; do
        [ -d "$candidate" ] || continue
        if compgen -G "$candidate/$pattern" >/dev/null; then
            cp -a "$candidate"/$pattern "$ROOTFS/lib/" 2>/dev/null || true
            return 0
        fi
    done

    return 1
}

install_loongarch_lib64_loader_aliases() {
    [ "$MUSL_ARCH" = "loongarch64" ] || return 0

    mkdir -p "$ROOTFS/lib64"

    if [ -e "$ROOTFS/lib/ld-linux-loongarch-lp64d.so.1" ]; then
        ln -snf ../lib/ld-linux-loongarch-lp64d.so.1 \
            "$ROOTFS/lib64/ld-linux-loongarch-lp64d.so.1"
    fi

    if [ -e "$ROOTFS/lib/libc.so" ]; then
        ln -snf ../lib/libc.so "$ROOTFS/lib64/ld-musl-loongarch-lp64d.so.1"
    fi
}

install_loongarch_usr_lib64_glibc() {
    [ "$MUSL_ARCH" = "loongarch64" ] || return 0
    [ -e "$ROOTFS/lib/libc.so.6" ] || return 0
    [ -e "$ROOTFS/lib/libm.so.6" ] || return 0

    mkdir -p "$ROOTFS/usr/lib64"
    cp -a "$ROOTFS/lib/libc.so.6" "$ROOTFS/usr/lib64/libc.so.6"
    cp -a "$ROOTFS/lib/libm.so.6" "$ROOTFS/usr/lib64/libm.so.6"
}

if [ -z "${GLIBC_LIB:-}" ]; then
    if [ -n "${GLIBC_TOOLCHAIN:-}" ]; then
        GLIBC_LIB="$(find_glibc_lib "$GLIBC_TOOLCHAIN" || true)"
    else
        GLIBC_LIB="/usr/riscv64-linux-gnu/lib"
    fi
fi

echo "[INFO] rootfs    : $ROOTFS"
echo "[INFO] glibc lib : $GLIBC_LIB"
echo "[INFO] musl lib  : $MUSL_LIB"

mkdir -p "$ROOTFS/lib" "$ROOTFS/usr/lib"

echo "[INFO] installing glibc runtime libs..."

if [ -n "$GLIBC_LIB" ] && [ -d "$GLIBC_LIB" ]; then
    GLIBC_GNU_TARGET="${GLIBC_TARGET:-${MUSL_ARCH}-linux-gnu}"
    mapfile -t GLIBC_CANDIDATES < <(glibc_lib_candidates "${GLIBC_TOOLCHAIN:-}" "$GLIBC_GNU_TARGET")

    cp -a "$GLIBC_LIB"/ld-linux*.so* "$ROOTFS/lib/" 2>/dev/null || true

    cp -a "$GLIBC_LIB"/libc.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libm.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libpthread.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/librt.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libdl.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libutil.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libresolv.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libnss_*.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libcrypt.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libthread_db.so* "$ROOTFS/lib/" 2>/dev/null || true
    cp -a "$GLIBC_LIB"/libBrokenLocale.so* "$ROOTFS/lib/" 2>/dev/null || true

    copy_first_runtime_match "libgcc_s.so*" "$GLIBC_LIB" "${GLIBC_CANDIDATES[@]}"
else
    echo "[WARN] glibc lib dir not found: $GLIBC_LIB"
fi

echo "[INFO] installing musl runtime libs..."

if [ -d "$MUSL_LIB" ]; then
    if [ -e "$MUSL_LIB/libc.so" ]; then
        cp -a "$MUSL_LIB/libc.so" "$ROOTFS/lib/libc.so"
    fi

    for ld in "$MUSL_LIB"/ld-musl-"$MUSL_ARCH"*.so*; do
        [ -e "$ld" ] || continue
        name="$(basename "$ld")"

        if [ -L "$ld" ]; then
            ln -sf libc.so "$ROOTFS/lib/$name"
        else
            cp -a "$ld" "$ROOTFS/lib/$name"
        fi
    done

    if [ -e "$ROOTFS/lib/libc.so" ] && [ ! -e "$ROOTFS/lib/ld-musl-$MUSL_ARCH.so.1" ]; then
        ln -sf libc.so "$ROOTFS/lib/ld-musl-$MUSL_ARCH.so.1"
    fi
    if [ "$MUSL_ARCH" = "riscv64" ] && [ -e "$ROOTFS/lib/libc.so" ] && [ ! -e "$ROOTFS/lib/ld-musl-riscv64-sf.so.1" ]; then
        ln -sf libc.so "$ROOTFS/lib/ld-musl-riscv64-sf.so.1"
    fi
else
    echo "[WARN] musl lib dir not found: $MUSL_LIB"
fi

install_loongarch_lib64_loader_aliases
install_loongarch_usr_lib64_glibc

echo "[INFO] installed runtime loaders:"
ls -l "$ROOTFS/lib"/ld-linux*.so* 2>/dev/null || true
ls -l "$ROOTFS/lib"/ld-musl-*.so* 2>/dev/null || true
ls -l "$ROOTFS/lib64"/ld-linux*.so* 2>/dev/null || true
ls -l "$ROOTFS/lib64"/ld-musl-*.so* 2>/dev/null || true

echo "[INFO] installed libc:"
ls -l "$ROOTFS/lib"/libc.so* 2>/dev/null || true

echo "[OK] libc runtime libraries installed"
