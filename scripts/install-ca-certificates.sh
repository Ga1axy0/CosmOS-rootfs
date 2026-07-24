#!/usr/bin/env bash
set -euo pipefail

# Install the host CA bundle into the guest rootfs.  CosmOS does not currently
# ship a package manager/ca-certificates updater, while host-side tools such as
# tg-xtask use rustls' platform verifier and expect the standard Linux bundle.

ROOTFS="${ROOTFS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../rootfs" && pwd)}"
CA_SOURCE="${CA_CERT_SOURCE:-${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}}"
CA_DEST="$ROOTFS/etc/ssl/certs/ca-certificates.crt"

if [[ ! -s "$CA_SOURCE" ]]; then
    echo "[ERROR] CA bundle not found or empty: $CA_SOURCE" >&2
    echo "[HINT] Set CA_CERT_SOURCE to a PEM bundle before building the rootfs." >&2
    exit 1
fi

mkdir -p "$(dirname "$CA_DEST")"
install -m 0644 "$CA_SOURCE" "$CA_DEST"

echo "[OK] installed CA bundle: $CA_DEST"
ls -lh "$CA_DEST"
