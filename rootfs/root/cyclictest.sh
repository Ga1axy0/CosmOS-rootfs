#!/bin/bash
set -euo pipefail

# Compare the compiled-in fair scheduler from inside the guest.
#
# Usage:
#   ./cyclictest.sh cfs
#   RUNS=5 DURATION=60s ./cyclictest.sh eevdf
#
# The label is part of the output directory and every result filename.  This
# prevents an EEVDF run from silently overwriting a CFS JSON file.

BASE=${CYCLICTEST_BASE:-/mnt/musl}
LABEL=${1:-${SCHEDULER_LABEL:-unknown}}
RUNS=${RUNS:-3}
DURATION=${DURATION:-30s}
INTERVAL_US=${INTERVAL_US:-1000}
CPUSET=${CPUSET:-0-7}
THREADS=${THREADS:-8}
# Keep enough buckets for the 250 ms-scale outlier seen in the first stress
# comparison while allowing callers to lower this for short smoke tests.
HISTOGRAM_US=${HISTOGRAM_US:-300000}
HACKBENCH_LOOPS=${HACKBENCH_LOOPS:-100000000}
HACKBENCH_WARMUP=${HACKBENCH_WARMUP:-1}
RUN_RT_CONTROL=${RUN_RT_CONTROL:-1}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUTPUT_DIR=${OUTPUT_DIR:-/tmp/cyclictest-${LABEL}-${STAMP}}

case "$LABEL" in
    *[!A-Za-z0-9._-]*)
        echo "invalid scheduler label: $LABEL" >&2
        exit 2
        ;;
esac

case "$RUNS" in
    ''|*[!0-9]*|0)
        echo "RUNS must be a positive integer" >&2
        exit 2
        ;;
esac

test -x "$BASE/cyclictest" || {
    echo "missing cyclictest at $BASE/cyclictest" >&2
    exit 1
}
test -x "$BASE/hackbench" || {
    echo "missing hackbench at $BASE/hackbench" >&2
    exit 1
}

mkdir -p "$OUTPUT_DIR"
{
    printf 'scheduler_label=%s\n' "$LABEL"
    printf 'started_utc=%s\n' "$STAMP"
    printf 'duration=%s interval_us=%s cpuset=%s threads=%s runs=%s\n' \
        "$DURATION" "$INTERVAL_US" "$CPUSET" "$THREADS" "$RUNS"
    printf 'histogram_us=%s hackbench_loops=%s\n' "$HISTOGRAM_US" "$HACKBENCH_LOOPS"
    uname -a
} >"$OUTPUT_DIR/metadata.txt"

hackbench_pid=
cleanup_hackbench() {
    if [ -n "${hackbench_pid:-}" ]; then
        if kill -0 "$hackbench_pid" 2>/dev/null; then
            kill -2 "$hackbench_pid" 2>/dev/null || true
            wait "$hackbench_pid" 2>/dev/null || true
        fi
        hackbench_pid=
    fi
}
trap cleanup_hackbench EXIT INT TERM

run_fair_test() {
    local name=$1
    shift
    local json="$OUTPUT_DIR/${name}.json"
    local histogram="$OUTPUT_DIR/${name}.hist"

    echo "[cyclictest] $name"
    "$BASE/cyclictest" \
        --policy=other -p 0 "$@" \
        -i "$INTERVAL_US" -D "$DURATION" -q \
        --json="$json" --histogram="$HISTOGRAM_US" --histfile="$histogram"
}

run_rt_control() {
    local name=$1
    local json="$OUTPUT_DIR/${name}.json"
    local histogram="$OUTPUT_DIR/${name}.hist"

    echo "[cyclictest] $name (FIFO control)"
    "$BASE/cyclictest" \
        --policy=fifo -p 99 -a "$CPUSET" -t "$THREADS" \
        -i "$INTERVAL_US" -D "$DURATION" -q \
        --json="$json" --histogram="$HISTOGRAM_US" --histfile="$histogram"
}

cd "$BASE"
for ((run = 1; run <= RUNS; run++)); do
    run_fair_test "fair-p1-r${run}" -a 0 -t 1
    run_fair_test "fair-p${THREADS}-r${run}" -a "$CPUSET" -t "$THREADS"

    echo "[cyclictest] starting hackbench for fair-stress-p${THREADS}-r${run}"
    "$BASE/hackbench" -l "$HACKBENCH_LOOPS" \
        >"$OUTPUT_DIR/fair-stress-p${THREADS}-r${run}-hackbench.log" 2>&1 &
    hackbench_pid=$!
    sleep "$HACKBENCH_WARMUP"
    run_fair_test "fair-stress-p${THREADS}-r${run}" \
        -a "$CPUSET" -t "$THREADS"
    cleanup_hackbench
done

if [ "$RUN_RT_CONTROL" != 0 ]; then
    for ((run = 1; run <= RUNS; run++)); do
        run_rt_control "rt-fifo-p${THREADS}-r${run}"
    done
fi

echo "[cyclictest] results: $OUTPUT_DIR"
