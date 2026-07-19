#!/usr/bin/env bash
set -euo pipefail

# Stage the RISC-V glibc development sysroot needed to link programs built for
# the Rust host target.  This is deliberately separate from the native musl
# toolchain used by StarryOS target builds.

PKG=glibc-host-sysroot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOTFS="${ROOTFS_DIR:-$PROJECT_ROOT/rootfs}"
GLIBC_SYSROOT="${GLIBC_SYSROOT:-/usr/riscv64-linux-gnu}"
GLIBC_SYSROOT_DIR="${GLIBC_SYSROOT_DIR:-/opt/riscv64-linux-gnu-sysroot}"
GLIBC_HOST_TARGET="${GLIBC_HOST_TARGET:-riscv64gc-unknown-linux-gnu}"
GLIBC_HOST_LINKER="${GLIBC_HOST_LINKER:-/usr/bin/riscv64gc-unknown-linux-gnu-gcc}"

# Only rootfs-rv has the RISC-V Rust host toolchain.  In particular, never
# install this sysroot into the LoongArch variant copied from the same base.
case "${BUSYBOX_ARCH:-}" in
    loongarch|loongarch64|la)
        echo "[SKIP] $PKG is RISC-V-only; LoongArch rootfs does not receive it"
        exit 0
        ;;
esac

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

[ -d "$GLIBC_SYSROOT" ] || die "RISC-V glibc sysroot not found: $GLIBC_SYSROOT"
[ -x "$ROOTFS/usr/bin/gcc" ] || \
    die "native guest GCC driver not found: $ROOTFS/usr/bin/gcc (enable WITH_NATIVE_GCC=1)"

source_include="$GLIBC_SYSROOT/include"
source_lib="$GLIBC_SYSROOT/lib"

# Accept the usual Debian cross layout as well as a conventional sysroot with
# usr/include and usr/lib.  The current host uses the former.
if [ ! -d "$source_include" ] && [ -d "$GLIBC_SYSROOT/usr/include" ]; then
    source_include="$GLIBC_SYSROOT/usr/include"
fi
if [ ! -d "$source_lib" ] && [ -d "$GLIBC_SYSROOT/usr/lib" ]; then
    source_lib="$GLIBC_SYSROOT/usr/lib"
fi

for required in \
    "$source_include" \
    "$source_lib/crt1.o" \
    "$source_lib/crti.o" \
    "$source_lib/crtn.o" \
    "$source_lib/libc.so" \
    "$source_lib/libc.so.6" \
    "$source_lib/ld-linux-riscv64-lp64d.so.1"
do
    [ -e "$required" ] || die "incomplete RISC-V glibc sysroot; missing $required"
done

guest_sysroot="$ROOTFS$GLIBC_SYSROOT_DIR"
guest_lib="$GLIBC_SYSROOT_DIR/lib"

echo "[INFO] rootfs       : $ROOTFS"
echo "[INFO] source sysroot: $GLIBC_SYSROOT"
echo "[INFO] guest sysroot : $GLIBC_SYSROOT_DIR"
echo "[INFO] host target   : $GLIBC_HOST_TARGET"
echo "[INFO] host linker   : $GLIBC_HOST_LINKER"

mkdir -p "$guest_sysroot/include" "$guest_sysroot/lib" "$guest_sysroot/usr"
cp -a "$source_include/." "$guest_sysroot/include/"
cp -a "$source_lib/." "$guest_sysroot/lib/"

# Make the staged tree look like a normal --sysroot layout for both lld and
# build scripts which inspect /usr/include or /usr/lib.
ln -snf ../include "$guest_sysroot/usr/include"
ln -snf ../lib "$guest_sysroot/usr/lib"

# Debian's libc.so is an ld script containing absolute paths from the host
# sysroot.  Rewrite those paths to sysroot-relative absolute paths.  With
# --sysroot, lld resolves /lib and /usr/lib below the selected sysroot; using
# the guest's actual /opt/... path here would make lld prepend the sysroot a
# second time (and produce e.g. ".../sysroot/opt/.../libc.so.6").
for linker_script in "$guest_sysroot/lib"/*.so; do
    [ -f "$linker_script" ] || continue
    if file "$linker_script" | grep -qE 'ASCII|text|script'; then
        sed -i "s#${source_lib}#/lib#g" "$linker_script"
    fi
done

# The glibc development sysroot normally ships libgcc_s.so.1 but not its
# unversioned linker name.  Rustc passes -lgcc_s, so provide that name in the
# isolated sysroot without touching the musl toolchain.
if [ ! -e "$guest_sysroot/lib/libgcc_s.so" ] && [ -e "$guest_sysroot/lib/libgcc_s.so.1" ]; then
    ln -s libgcc_s.so.1 "$guest_sysroot/lib/libgcc_s.so"
fi

# The built-in riscv64gc-unknown-linux-gnu Rust target has linker flavor
# `gnu-cc`, so rustc expects a compiler driver rather than a raw `ld`. The
# driver supplies Scrt1.o/crti.o/crtn.o, GCC's crtbegin/crtend objects, and
# the glibc PT_INTERP. Calling rust-lld directly produces an ET_DYN file with
# entry point zero and no interpreter.
#
# The native guest GCC defaults to musl, but its specs support `-mglibc`.
# Point it at the isolated glibc sysroot while retaining GCC's own runtime
# object directory for crtbegin/crtend and libgcc.
linker_path="$ROOTFS$GLIBC_HOST_LINKER"
mkdir -p "$(dirname "$linker_path")"

# The native GCC install keeps its fixed compiler headers outside the search
# path selected by -mglibc/--sysroot.  glibc's limits.h uses include_next to
# reach GCC's limits.h, so make that directory explicit in the GNU host
# wrapper.  Select the version that belongs to the installed cc1 driver rather
# than a possibly co-installed cross-toolchain runtime.
gcc_include_fixed=""
for cc1_path in "$ROOTFS/usr/libexec/gcc/riscv64-linux-musl"/*/cc1; do
    [ -f "$cc1_path" ] || continue
    gcc_version="$(basename "$(dirname "$cc1_path")")"
    candidate="/usr/lib/gcc/riscv64-linux-musl/$gcc_version/include-fixed"
    if [ -d "$ROOTFS$candidate" ]; then
        gcc_include_fixed="$candidate"
        break
    fi
done
[ -n "$gcc_include_fixed" ] || \
    die "native GCC fixed include directory not found below $ROOTFS/usr/lib/gcc"

cat > "$linker_path" <<EOF
#!/bin/bash
set -e

sysroot="$GLIBC_SYSROOT_DIR"
exec /usr/bin/gcc \\
    -mglibc \\
    --sysroot="\$sysroot" \\
    -B"\$sysroot/lib/" \\
    -isystem "$gcc_include_fixed" \\
    "\$@"
EOF
chmod 0755 "$linker_path"

echo "[OK] $PKG staged"
du -sh "$guest_sysroot" 2>/dev/null || true
