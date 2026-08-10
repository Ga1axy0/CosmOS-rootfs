#!/bin/sh
# QEMU testcode for the nested LoongArch QEMU smoke test.
#
# This is deliberately separate from buildstorm_testcode.sh.  It consumes the
# already-built arceos-helloworld artifact under /work/tgoskits/target and
# never removes or rebuilds target/.
#
# The script is staged in the rootfs tree first.  The evaluation image can
# copy it to /glibc/qemu_testcode.sh beside buildstorm_testcode.sh; this file
# does not modify sdcard-la-pub.img.

set -u

echo "#### OS COMP TEST GROUP START qemu-glibc ####"

AXARCH=${QEMU_TEST_ARCH:-$(uname -m 2>/dev/null || printf unknown)}
case "$AXARCH" in
    loongarch64)
        ;;
    *)
        echo "[qemu_testcode] unsupported guest architecture: $AXARCH" >&2
        echo "QEMU_BOOT arch=$AXARCH ok=false reason=unsupported_arch"
        echo "#### OS COMP TEST GROUP END qemu-glibc ####"
        exit 2
        ;;
esac

WORKSPACE=${QEMU_WORKSPACE:-/work/tgoskits}
TARGET_DIR=${QEMU_TARGET_DIR:-$WORKSPACE/target}
MIN_BYTES=${QEMU_MIN_BYTES:-500000}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-600}

case "$MIN_BYTES" in
    ''|*[!0-9]*)
        echo "[qemu_testcode] invalid QEMU_MIN_BYTES: $MIN_BYTES" >&2
        echo "QEMU_BOOT arch=$AXARCH ok=false reason=invalid_min_bytes"
        echo "#### OS COMP TEST GROUP END qemu-glibc ####"
        exit 2
        ;;
esac
case "$QEMU_TIMEOUT" in
    ''|*[!0-9]*)
        echo "[qemu_testcode] invalid QEMU_TIMEOUT: $QEMU_TIMEOUT" >&2
        echo "QEMU_BOOT arch=$AXARCH ok=false reason=invalid_timeout"
        echo "#### OS COMP TEST GROUP END qemu-glibc ####"
        exit 2
        ;;
esac

# ART may be exported by a caller that split the QEMU portion out of
# buildstorm_testcode.sh.  When run independently, prefer the existing
# release artifact in target/ instead.
ART=${ART:-${QEMU_ARTIFACT:-}}
case "$ART" in
    *.bin)
        ART=${ART%.bin}
        ;;
esac

if [ -z "$ART" ]; then
    for candidate in \
        "$TARGET_DIR/loongarch64-unknown-linux-musl/release/arceos-helloworld" \
        "$TARGET_DIR/loongarch64-unknown-linux-musl/release/helloworld"
    do
        if [ -f "$candidate" ]; then
            ART=$candidate
            break
        fi
    done
fi

if [ -z "$ART" ] && [ -d "$TARGET_DIR" ]; then
    ART=$(find "$TARGET_DIR" -type f -path '*/release/*' \( \
        -name arceos-helloworld -o -name helloworld \
    \) 2>/dev/null | sort | head -1)
fi

BYTES=0
if [ -n "$ART" ] && [ -f "$ART" ]; then
    BYTES=$(wc -c <"$ART" 2>/dev/null || printf 0)
fi

if [ -z "$ART" ] || [ ! -f "$ART" ] || [ "$BYTES" -lt "$MIN_BYTES" ]; then
    echo "[qemu_testcode] no usable existing arceos-helloworld artifact" >&2
    echo "[qemu_testcode] target=$TARGET_DIR artifact=${ART:-<none>} bytes=$BYTES" >&2
    echo "QEMU_BOOT arch=$AXARCH ok=false reason=missing_artifact bytes=$BYTES"
    echo "#### OS COMP TEST GROUP END qemu-glibc ####"
    exit 1
fi

echo "[qemu_testcode] using existing artifact: $ART ($BYTES bytes)"
EFI=${ART}.bin
QROOT=${QEMU_ROOT:-/opt/qemu-la64}
QEMU_LD=${QEMU_LD:-$QROOT/lib/ld-linux-loongarch-lp64d.so.1}
QEMU_BIN=${QEMU_BIN:-$QROOT/bin/qemu-system-loongarch64}
QEMU_CODE=${QEMU_CODE:-$QROOT/share/edk2/loongarch64/code.fd}
QEMU_VARS=${QEMU_VARS:-$QROOT/share/edk2/loongarch64/vars.fd}

missing=""
[ -f "$EFI" ] || missing="$missing EFI=$EFI"
[ -x "$QEMU_LD" ] || missing="$missing loader=$QEMU_LD"
[ -x "$QEMU_BIN" ] || missing="$missing qemu=$QEMU_BIN"
[ -f "$QEMU_CODE" ] || missing="$missing code_fd=$QEMU_CODE"
[ -f "$QEMU_VARS" ] || missing="$missing vars_fd=$QEMU_VARS"
if [ -n "$missing" ]; then
    echo "[qemu_testcode] missing QEMU input:$missing" >&2
    echo "QEMU_BOOT arch=$AXARCH ok=false reason=missing_qemu_input"
    echo "#### OS COMP TEST GROUP END qemu-glibc ####"
    exit 1
fi

# Keep all mutable QEMU inputs in a private temporary directory.  In
# particular, do not use the source vars.fd or a persistent ESP under /work.
TMP_PARENT=${QEMU_TMP_PARENT:-/tmp}
mkdir -p "$TMP_PARENT" 2>/dev/null || {
    echo "[qemu_testcode] cannot create temporary parent: $TMP_PARENT" >&2
    echo "QEMU_BOOT arch=$AXARCH ok=false reason=tmp_parent"
    echo "#### OS COMP TEST GROUP END qemu-glibc ####"
    exit 1
}
RUN_DIR=$(mktemp -d "$TMP_PARENT/qemu-testcode.XXXXXX" 2>/dev/null) || {
    echo "[qemu_testcode] cannot create temporary run directory" >&2
    echo "QEMU_BOOT arch=$AXARCH ok=false reason=tmp_dir"
    echo "#### OS COMP TEST GROUP END qemu-glibc ####"
    exit 1
}

QPID=""
cleanup_child() {
    if [ -n "$QPID" ]; then
        kill "$QPID" 2>/dev/null || true
        wait "$QPID" 2>/dev/null || true
        QPID=""
    fi
}

cleanup() {
    cleanup_child
    if [ "${QEMU_KEEP_TMP:-0}" != 1 ] && [ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ]; then
        rm -rf "$RUN_DIR"
    fi
}

on_signal() {
    cleanup
    exit 130
}

trap cleanup EXIT
trap on_signal HUP INT TERM

ESP_DIR="$RUN_DIR/esp"
VARS_FILE="$RUN_DIR/vars.fd"
RUN_OUT=${QEMU_RUN_OUT:-/tmp/qemu_testcode.run.out}
mkdir -p "$ESP_DIR/EFI/BOOT" "$(dirname "$RUN_OUT")" || {
    echo "[qemu_testcode] cannot prepare QEMU temporary files" >&2
    echo "QEMU_BOOT arch=$AXARCH ok=false reason=tmp_files"
    exit 1
}

cp "$EFI" "$ESP_DIR/EFI/BOOT/BOOTLOONGARCH64.EFI" || {
    echo "[qemu_testcode] cannot stage EFI application" >&2
    echo "QEMU_BOOT arch=$AXARCH ok=false reason=stage_efi"
    exit 1
}
cp "$QEMU_VARS" "$VARS_FILE" || {
    echo "[qemu_testcode] cannot copy UEFI variable store" >&2
    echo "QEMU_BOOT arch=$AXARCH ok=false reason=stage_vars"
    exit 1
}

echo "----- boot arceos-helloworld in qemu (untimed, arch=$AXARCH) -----"
: >"$RUN_OUT" || {
    echo "[qemu_testcode] cannot create QEMU log: $RUN_OUT" >&2
    echo "QEMU_BOOT arch=$AXARCH ok=false reason=run_log"
    exit 1
}

RUN_OK=0
"$QEMU_LD" --library-path "$QROOT/lib" "$QEMU_BIN" \
    -L "$QROOT/share/qemu" \
    -machine virt -cpu la464 -smp 1 -m 2G -nographic -serial mon:stdio \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$QEMU_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$VARS_FILE" \
    -drive format=raw,file=fat:rw:"$ESP_DIR" \
    >"$RUN_OUT" 2>&1 &
QPID=$!

i=0
while [ "$i" -lt "$QEMU_TIMEOUT" ]; do
    if grep -qi "hello, world" "$RUN_OUT" 2>/dev/null; then
        RUN_OK=1
        break
    fi
    if ! kill -0 "$QPID" 2>/dev/null; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

cleanup_child

if [ "$RUN_OK" -eq 1 ]; then
    echo "QEMU_BOOT arch=$AXARCH ok=true elapsed_s=$i bytes=$BYTES"
    status=0
else
    echo "QEMU_BOOT arch=$AXARCH ok=false elapsed_s=$i bytes=$BYTES"
    echo "----- qemu_testcode.run.out tail -----"
    tail -25 "$RUN_OUT" 2>/dev/null || true
    status=1
fi

echo "[qemu_testcode] log: $RUN_OUT"
echo "#### OS COMP TEST GROUP END qemu-glibc ####"
exit "$status"
