#!/usr/bin/env bash
set -e

# =========================
# build-bash.sh
# =========================

PKG=bash
VERSION=5.3  # 可以改成你下载的版本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="$PROJECT_ROOT/rootfs"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="$PROJECT_ROOT/build"

TARBALL="$THIRD_PARTY/bash-${VERSION}.tar.gz"
SRC_DIR="$BUILD_ROOT/${PKG}-${VERSION}-src"
BUILD_DIR="$BUILD_ROOT/${PKG}-${VERSION}-build"

# ===== 目标架构 =====
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
    echo "[ERROR] 找不到 bash 源码包: $TARBALL"
    exit 1
fi

# 创建必要目录
mkdir -p "$ROOTFS/bin" "$ROOTFS/sbin" "$ROOTFS/lib" \
         "$ROOTFS/usr/bin" "$ROOTFS/usr/sbin" "$ROOTFS/usr/lib"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

# 解压源码
tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1
cd "$BUILD_DIR"

# 设置交叉编译工具链
export CC="${CROSS_PREFIX}gcc"
export AR="${CROSS_PREFIX}ar"
export AS="${CROSS_PREFIX}as"
export LD="${CROSS_PREFIX}ld"
export RANLIB="${CROSS_PREFIX}ranlib"
export STRIP="${CROSS_PREFIX}strip"
export FORCE_UNSAFE_CONFIGURE=1

# 配置
"$SRC_DIR/configure" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --without-bash-malloc \
    --disable-nls \
    --enable-static-link \
    CC="$CC"

# 编译并安装
make -j"$JOBS"
make DESTDIR="$ROOTFS" install

# 创建 /bin/bash 链接
if [ -x "$ROOTFS/usr/bin/bash" ]; then
    ln -sf ../usr/bin/bash "$ROOTFS/bin/bash"
    ln -sf bash "$ROOTFS/bin/sh"  # /bin/sh 链接到 bash
fi

# strip 减小体积
if command -v "$STRIP" >/dev/null 2>&1; then
    find "$ROOTFS/usr/bin" -type f -exec sh -c '
        for f do
            if file "$f" | grep -q "ELF"; then
                '"$STRIP"' "$f" 2>/dev/null || true
            fi
        done
    ' sh {} +
fi

echo "[OK] bash installed into $ROOTFS/usr/bin and linked /bin/bash & /bin/sh"
file "$ROOTFS/usr/bin/bash" || true