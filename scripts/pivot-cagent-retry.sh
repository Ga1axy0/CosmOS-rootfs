#!/bin/sh

attempt=1
max_attempts=5

while :; do
    "$CAGENT_REAL_AGENT" "$@"
    status=$?
    if [ "$status" -eq 0 ] || [ "$attempt" -ge "$max_attempts" ]; then
        exit "$status"
    fi
    attempt=$((attempt + 1))
    "$BUSYBOX" sleep 0.05
done
