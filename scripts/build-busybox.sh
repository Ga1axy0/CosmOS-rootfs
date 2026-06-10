#!/usr/bin/env bash
set -euo pipefail

# =========================
# build-busybox.sh
# 只编译 busybox，并只复制 /bin/busybox
# 不执行 make install，不自动生成 applet 链接
# =========================

PKG=busybox
VERSION=1.36.1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="$PROJECT_ROOT/rootfs"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="$PROJECT_ROOT/build"

TARBALL="$THIRD_PARTY/${PKG}-${VERSION}.tar.bz2"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"

setup_musl_toolchain

echo "[INFO] project root : $PROJECT_ROOT"
echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] tarball      : $TARBALL"
echo "[INFO] source dir   : $SRC_DIR"
log_musl_toolchain

if [ ! -f "$TARBALL" ]; then
    echo "[ERROR] 找不到 busybox 源码包: $TARBALL"
    echo "[HINT] 下载:"
    echo "       cd $THIRD_PARTY"
    echo "       wget https://busybox.net/downloads/busybox-${VERSION}.tar.bz2"
    exit 1
fi

mkdir -p "$ROOTFS/bin"

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1
cd "$SRC_DIR"

export ARCH=riscv
export CROSS_COMPILE="$CROSS_PREFIX"

disable_config() {
    local symbol="$1"

    if grep -q "^${symbol}=y" .config; then
        sed -i.bak "s/^${symbol}=y/# ${symbol} is not set/" .config
    elif ! grep -q "^# ${symbol} is not set" .config; then
        printf '# %s is not set\n' "$symbol" >> .config
    fi
}

enable_config() {
    local symbol="$1"

    if grep -q "^# ${symbol} is not set" .config; then
        sed -i.bak "s/^# ${symbol} is not set/${symbol}=y/" .config
    elif grep -q "^${symbol}=n" .config; then
        sed -i.bak "s/^${symbol}=n/${symbol}=y/" .config
    elif ! grep -q "^${symbol}=y" .config; then
        printf '%s=y\n' "$symbol" >> .config
    fi
}

echo "[INFO] make defconfig"
make defconfig

# musl 静态自举 busybox
enable_config CONFIG_STATIC
disable_config CONFIG_PIE

# BusyBox tc applet 依赖的旧 CBQ UAPI 在新内核头中可能缺失。
# 这里直接关闭 tc，避免和 iproute2 提供的 tc 重复。
disable_config CONFIG_TC
disable_config CONFIG_FEATURE_TC_INGRESS

rm -f .config.bak

echo "[INFO] make oldconfig (accept defaults for new symbols)"

set +o pipefail
yes "" | make oldconfig
set -o pipefail

echo "[INFO] build busybox"
make -j"$JOBS"

if [ ! -x busybox ]; then
    echo "[ERROR] busybox 没有生成"
    exit 1
fi

echo "[INFO] copy only one binary: $ROOTFS/bin/busybox"
cp -av busybox "$ROOTFS/bin/busybox"

if command -v "$STRIP_BIN" >/dev/null 2>&1; then
    "$STRIP_BIN" "$ROOTFS/bin/busybox" 2>/dev/null || true
fi

echo "[OK] busybox installed only as $ROOTFS/bin/busybox"

if [ ! -s busybox.links ]; then
    echo "[INFO] generate busybox.links"
    make busybox.links
fi

if [ ! -s busybox.links ]; then
    echo "[ERROR] busybox.links 没有生成"
    exit 1
fi

echo "[INFO] create BusyBox applet symlinks from busybox.links"
while IFS= read -r applet_path; do
    [ -n "$applet_path" ] || continue

    case "$(basename "$applet_path")" in
        init | linuxrc)
            echo "[INFO] skip applet symlink: $applet_path"
            continue
            ;;
    esac

    appdir="$(dirname "$applet_path")"
    case "$appdir" in
        /)
            bb_path="bin/busybox"
            ;;
        /bin)
            bb_path="busybox"
            ;;
        /sbin)
            bb_path="../bin/busybox"
            ;;
        /usr/bin | /usr/sbin)
            bb_path="../../bin/busybox"
            ;;
        *)
            echo "[WARN] skip unsupported BusyBox applet path: $applet_path"
            continue
            ;;
    esac

    mkdir -p "$ROOTFS$appdir"
    ln -snf "$bb_path" "$ROOTFS$applet_path"
done < busybox.links

echo "[OK] busybox installed"
echo "[INFO] check:"
ls -l "$ROOTFS/bin/busybox"
ls -l "$ROOTFS/sbin/ip" 2>/dev/null || true
file "$ROOTFS/bin/busybox" || true

echo "[INFO] check:"
ls -l "$ROOTFS/bin/busybox"
file "$ROOTFS/bin/busybox" || true

echo "[INFO] ELF interpreter:"
if command -v "$READELF_BIN" >/dev/null 2>&1; then
    "$READELF_BIN" -l "$ROOTFS/bin/busybox" | grep interpreter || echo "[INFO] static binary: no PT_INTERP"
    echo "[INFO] shared library dependencies:"
    "$READELF_BIN" -d "$ROOTFS/bin/busybox" | grep NEEDED || echo "[INFO] static binary: no NEEDED entries"
else
    echo "[WARN] readelf not found: $READELF_BIN"
fi
