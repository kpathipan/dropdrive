#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
upload_tests_tmp=$(mktemp -d -t dropdrive-upload-harness)
trap 'rm -rf "$upload_tests_tmp"' EXIT
xcrun swiftc -parse-as-library -O -swift-version 5 -default-isolation MainActor \
  DropDrive/Models/AutomationCommand.swift DropDrive/Models/UploadJob.swift \
  DropDrive/Models/GoogleAccount.swift DropDrive/Services/UploadSource.swift \
  DropDrive/Services/UploadStore.swift DropDrive/Services/DriveUploadEngine.swift \
  DropDrive/Utilities/UploadDropFiles.swift \
  scripts/upload-harness/Stubs.swift scripts/upload-harness/main.swift \
  -o "$upload_tests_tmp/upload-tests"
"$upload_tests_tmp/upload-tests"
