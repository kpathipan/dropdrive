#!/bin/bash
# Single-platform publication is deliberately disabled. Prepare both signed/
# packaged builds first; the coordinator defaults to read-only verification.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ruby scripts/paired-release.rb "$@"
