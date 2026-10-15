#!/usr/bin/env bash
# Run ReSourcer UITests on macOS (requires Xcode + Simulator).
#
# Usage:
#   E2E_SERVER_URL=http://127.0.0.1:1234 E2E_API_KEY=... bash iOS/scripts/run-ui-tests.sh
#
# Optional:
#   E2E_ALLOW_MUTATION=1   # allow bulk-delete confirm to actually delete
#   DESTINATION='platform=iOS Simulator,name=iPhone 16'
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT/iOS"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found — run this script on a Mac with Xcode installed."
  exit 2
fi

if [ -z "${E2E_SERVER_URL:-}" ] || [ -z "${E2E_API_KEY:-}" ]; then
  echo "E2E_SERVER_URL and E2E_API_KEY are required."
  exit 2
fi

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 16}"

# Export so XCTest ProcessInfo.environment can read them in setUp
export E2E_SERVER_URL E2E_API_KEY
export E2E_ALLOW_MUTATION="${E2E_ALLOW_MUTATION:-0}"

echo "-- running ReSourcerUITests on $DESTINATION"
xcodebuild \
  -project ReSourcer.xcodeproj \
  -scheme ReSourcer \
  -destination "$DESTINATION" \
  -only-testing:ReSourcerUITests \
  test
