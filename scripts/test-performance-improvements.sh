#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc -O \
  DropDrive/Utilities/BoundedAsyncMap.swift \
  DropDrive/Utilities/LinkIdentity.swift \
  scripts/performance-harness/main.swift \
  -o "$OUT/performance-harness"

"$OUT/performance-harness"
