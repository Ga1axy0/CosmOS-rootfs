#!/usr/bin/env bash
set -euo pipefail

# Install the Ubuntu Noble RISC-V libclang runtime used by bindgen in CosmOS.
# The .deb files are kept in third-party so rootfs builds remain offline and
# reproducible; dpkg-deb is only used as an archive extractor.

PKG=libclang-riscv64

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
THIRD_PARTY="$PROJECT_ROOT/third-party/libclang-riscv64-noble"
MANIFEST="$THIRD_PARTY/SHA256SUMS"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
STAGE_DIR="$BUILD_ROOT/libclang-riscv64-stage"

LIBCLANG_DIR=/usr/lib/llvm-18/lib
MULTIARCH_LIBDIR=/usr/lib/riscv64-linux-gnu

case "${BUSYBOX_ARCH:-}" in
    loongarch|loongarch64|la)
        echo "[SKIP] $PKG contains RISC-V binaries and is not installed in rootfs-la"
        exit 0
        ;;
esac

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

[[ -n "$ROOTFS" && "$ROOTFS" != / ]] || die "unsafe rootfs path: $ROOTFS"
[ -d "$ROOTFS" ] || die "rootfs directory not found: $ROOTFS"
[ -f "$MANIFEST" ] || die "package checksum manifest not found: $MANIFEST"

for tool in sha256sum dpkg-deb file; do
    command -v "$tool" >/dev/null 2>&1 || die "required host tool not found: $tool"
done

echo "[INFO] verify Ubuntu Noble RISC-V packages"
(
    cd "$THIRD_PARTY"
    sha256sum --strict -c "$(basename "$MANIFEST")"
)

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

while read -r expected_sha256 archive; do
    [ -n "${archive:-}" ] || continue
    case "$archive" in
        *.deb) ;;
        *) die "unexpected manifest entry: $archive" ;;
    esac

    deb="$THIRD_PARTY/$archive"
    [ -f "$deb" ] || die "package archive not found: $deb"

    architecture="$(dpkg-deb -f "$deb" Architecture)"
    [ "$architecture" = riscv64 ] || \
        die "wrong package architecture for $archive: $architecture"

    echo "[INFO] extract $(dpkg-deb -f "$deb" Package) $(dpkg-deb -f "$deb" Version)"
    dpkg-deb -x "$deb" "$STAGE_DIR"
done < "$MANIFEST"

for required in \
    "$STAGE_DIR$LIBCLANG_DIR/libclang.so.1" \
    "$STAGE_DIR$LIBCLANG_DIR/libLLVM.so.1" \
    "$STAGE_DIR$MULTIARCH_LIBDIR/libstdc++.so.6" \
    "$STAGE_DIR$MULTIARCH_LIBDIR/libgcc_s.so.1" \
    "$STAGE_DIR$MULTIARCH_LIBDIR/libffi.so.8" \
    "$STAGE_DIR$MULTIARCH_LIBDIR/libedit.so.2" \
    "$STAGE_DIR$MULTIARCH_LIBDIR/libxml2.so.2" \
    "$STAGE_DIR$MULTIARCH_LIBDIR/libzstd.so.1" \
    "$STAGE_DIR$MULTIARCH_LIBDIR/libz.so.1" \
    "$STAGE_DIR$MULTIARCH_LIBDIR/libtinfo.so.6"
do
    [ -e "$required" ] || die "staged libclang runtime is incomplete: $required"
done

if ! file "$STAGE_DIR$MULTIARCH_LIBDIR/libclang-18.so.18" | grep -q 'RISC-V'; then
    file "$STAGE_DIR$MULTIARCH_LIBDIR/libclang-18.so.18" >&2 || true
    die "libclang is not a RISC-V shared library"
fi

echo "[INFO] install libclang and its runtime closure into $ROOTFS"
cp -a "$STAGE_DIR/." "$ROOTFS/"

# Make libclang discoverable in interactive login shells.
mkdir -p "$ROOTFS/etc/profile.d"
profile_snippet="$ROOTFS/etc/profile.d/cosmos-libclang.sh"
printf '%s\n' \
    "export LIBCLANG_PATH=\"$LIBCLANG_DIR\"" \
    "export LD_LIBRARY_PATH=\"$LIBCLANG_DIR:$MULTIARCH_LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\"" \
    > "$profile_snippet"
chmod 0644 "$profile_snippet"

profile="$ROOTFS/etc/profile"
profile_marker='# Load CosmOS package environment.'
if [ -f "$profile" ] && ! grep -Fq "$profile_marker" "$profile"; then
    {
        printf '\n%s\n' "$profile_marker"
        printf '%s\n' \
            'for profile_script in /etc/profile.d/*.sh; do' \
            '    [ -r "$profile_script" ] && . "$profile_script"' \
            'done' \
            'unset profile_script'
    } >> "$profile"
fi

# Existing rootfs trees may already contain a Cargo wrapper from build-rust.
# Patch it idempotently as well; Cargo build scripts inherit both variables.
cargo_wrapper="$ROOTFS/usr/bin/cargo"
if [ -f "$cargo_wrapper" ] && \
        ! grep -Fq "LIBCLANG_PATH=\"$LIBCLANG_DIR\"" "$cargo_wrapper"; then
    wrapper_tmp="$cargo_wrapper.libclang.tmp"
    {
        head -n 1 "$cargo_wrapper"
        printf '%s\n' \
            "export LIBCLANG_PATH=\"$LIBCLANG_DIR\"" \
            "export LD_LIBRARY_PATH=\"$LIBCLANG_DIR:$MULTIARCH_LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
        tail -n +2 "$cargo_wrapper"
    } > "$wrapper_tmp"
    chmod 0755 "$wrapper_tmp"
    mv "$wrapper_tmp" "$cargo_wrapper"
fi

echo "[OK] $PKG installed"
echo "     LIBCLANG_PATH : $LIBCLANG_DIR"
echo "     runtime libs  : $MULTIARCH_LIBDIR"
du -sh "$ROOTFS$LIBCLANG_DIR" "$ROOTFS$MULTIARCH_LIBDIR" 2>/dev/null || true
