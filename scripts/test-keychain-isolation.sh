#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc -D DEBUG \
  DropDrive/Services/KeychainNamespace.swift \
  scripts/keychain-harness/main.swift \
  -o "$OUT/keychain-debug"
"$OUT/keychain-debug" "DropDriveAuthSession.debug"

xcrun swiftc \
  DropDrive/Services/KeychainNamespace.swift \
  scripts/keychain-harness/main.swift \
  -o "$OUT/keychain-release"
"$OUT/keychain-release" "DropDriveAuthSession"
