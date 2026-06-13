#!/usr/bin/env bash
set -e

PKG=shadow
VERSION=4.19.4

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-musl-env.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"

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
    echo "[ERROR] 找不到 shadow 源码包: $TARBALL"
    exit 1
fi

mkdir -p "$ROOTFS/bin" "$ROOTFS/sbin" \
         "$ROOTFS/usr/bin" "$ROOTFS/usr/sbin" "$ROOTFS/usr/lib" \
         "$ROOTFS/etc"
mkdir -p "$BUILD_ROOT"

rm -rf "$SRC_DIR" "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR"

tar xf "$TARBALL" -C "$SRC_DIR" --strip-components=1

cd "$BUILD_DIR"

# shadow's configure requires pkg-config even when optional pkg-config based
# dependencies are disabled. Keep it available, but do not let it discover
# host .pc files while cross-compiling.
export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"
export PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-/nonexistent}"
export PKG_CONFIG_PATH=

"$SRC_DIR/configure" \
    --host="$TARGET" \
    --prefix="$PREFIX" \
    --exec-prefix="$PREFIX" \
    --sbindir="$PREFIX/sbin" \
    --disable-nls \
    --disable-man \
    --disable-shared \
    --disable-rpath \
    --disable-logind \
    --disable-subordinate-ids \
    --disable-lastlog \
    --without-audit \
    --without-libpam \
    --without-btrfs \
    --without-selinux \
    --without-acl \
    --without-attr \
    --without-skey \
    --without-tcb \
    --without-nscd \
    --without-sssd \
    --without-su \
    --without-libbsd \
    CC="$CC"

make -j"$JOBS"
make DESTDIR="$ROOTFS" install

mkdir -p "$ROOTFS/etc/default"
touch "$ROOTFS/etc/shadow" "$ROOTFS/etc/gshadow"
chmod 0644 "$ROOTFS/etc/shadow" "$ROOTFS/etc/gshadow"

if [ ! -s "$ROOTFS/etc/login.defs" ]; then
    cat > "$ROOTFS/etc/login.defs" <<'EOF'
UID_MIN			 1000
UID_MAX			60000
GID_MIN			 1000
GID_MAX			60000
CREATE_HOME		no
USERGROUPS_ENAB		yes
MAIL_DIR		/tmp
PASS_MAX_DAYS		99999
PASS_MIN_DAYS		0
PASS_WARN_AGE		7
EOF
fi

if [ ! -s "$ROOTFS/etc/default/useradd" ]; then
    cat > "$ROOTFS/etc/default/useradd" <<'EOF'
GROUP=100
HOME=/tmp
SHELL=/bin/sh
CREATE_MAIL_SPOOL=no
EOF
fi

for x in useradd userdel groupdel groupadd; do
    if [ -x "$ROOTFS/usr/sbin/$x" ]; then
        ln -sf "../sbin/$x" "$ROOTFS/usr/bin/$x"
        ln -sf "../usr/sbin/$x" "$ROOTFS/sbin/$x"
    fi
done

for dir in "$ROOTFS/usr/bin" "$ROOTFS/usr/sbin" "$ROOTFS/sbin"; do
    [ -d "$dir" ] || continue
    find "$dir" -type f -exec sh -c '
for f do
    if file "$f" | grep -q "ELF"; then
        '"$STRIP"' "$f" 2>/dev/null || true
    fi
done
' sh {} +
done

echo "[OK] shadow installed into:"
echo "     $ROOTFS/usr/sbin"
echo "     $ROOTFS/usr/bin -> account tool symlinks"

file "$ROOTFS/usr/sbin/useradd" || true
file "$ROOTFS/usr/sbin/userdel" || true
file "$ROOTFS/usr/sbin/groupdel" || true
