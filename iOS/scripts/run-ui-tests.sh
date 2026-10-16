#!/usr/bin/env bash
# Run ReSourcer UITests on macOS (requires Xcode + Simulator).
#
# Usage:
#   E2E_SERVER_URL=http://127.0.0.1:1234 E2E_API_KEY=... bash iOS/scripts/run-ui-tests.sh
#
# Optional:
#   E2E_ALLOW_MUTATION=1   # allow bulk-delete confirm to actually delete
#   DESTINATION='platform=iOS Simulator,name=iPhone 17'
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

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"

# xcodebuild forwards env vars prefixed with TEST_RUNNER_ into the XCTest
# process (prefix stripped). They must be in xcodebuild's process environment,
# not trailing KEY=value build settings (those do not reach ProcessInfo).
export E2E_SERVER_URL E2E_API_KEY
export E2E_ALLOW_MUTATION="${E2E_ALLOW_MUTATION:-0}"
export TEST_RUNNER_E2E_SERVER_URL="$E2E_SERVER_URL"
export TEST_RUNNER_E2E_API_KEY="$E2E_API_KEY"
export TEST_RUNNER_E2E_ALLOW_MUTATION="$E2E_ALLOW_MUTATION"

echo "-- running ReSourcerUITests on $DESTINATION"
echo "-- E2E_SERVER_URL=$E2E_SERVER_URL"
# ONLY_TESTING 可覆盖，例如：ONLY_TESTING=ReSourcerUITests/ShareDownloadUITests
ONLY_TESTING="${ONLY_TESTING:-ReSourcerUITests}"
xcodebuild \
  -project ReSourcer.xcodeproj \
  -scheme ReSourcer \
  -destination "$DESTINATION" \
  -only-testing:"$ONLY_TESTING" \
  test
