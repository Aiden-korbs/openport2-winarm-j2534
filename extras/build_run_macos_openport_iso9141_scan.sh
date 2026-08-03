#!/bin/sh
set -eu

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$BASE_DIR/macos_openport_iso9141_mode09.c"
OUT="$BASE_DIR/macos_openport_iso9141_mode09"
LOG="$BASE_DIR/macos_openport_scan_$(date +%Y%m%d_%H%M%S).log"

if ! command -v pkg-config >/dev/null 2>&1; then
    echo "pkg-config not found. Install dependencies with: brew install libusb pkg-config" >&2
    exit 1
fi

if ! pkg-config --exists libusb-1.0; then
    echo "libusb-1.0 not found. Install it with: brew install libusb pkg-config" >&2
    exit 1
fi

cc -Wall -Wextra -O2 -arch arm64 "$SRC" -o "$OUT" $(pkg-config --cflags --libs libusb-1.0)
echo "Writing scan log to: $LOG"
"$OUT" --scan | tee "$LOG"
