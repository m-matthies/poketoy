#!/bin/bash
# Runs `swift test`. With only the Command Line Tools installed, SwiftPM's build backend
# intermittently fails to locate the Swift Testing macro plugin, so pass its path explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing"
if [ -d "$PLUGINS" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
