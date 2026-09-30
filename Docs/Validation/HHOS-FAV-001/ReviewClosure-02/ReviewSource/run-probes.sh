#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc ProbeTypes.swift ProbeSupport.swift ExtractedSyncMethods.swift ExtractedMerge.swift main.swift -o "$BUILD_DIR/review-probe"
"$BUILD_DIR/review-probe"
