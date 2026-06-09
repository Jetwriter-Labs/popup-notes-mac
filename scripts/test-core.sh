#!/usr/bin/env bash
# Runs the PopupNotesCore tests. On Command Line Tools, Swift Testing's
# Testing.framework is present but off the default search path, and the
# _Testing_Foundation cross-import overlay ships no swiftmodule — so we add
# the framework path and disable cross-import overlays. Under a full Xcode
# toolchain, Swift Testing resolves normally and no extra flags are needed.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/PopupNotesCore"
DEVDIR="$(xcode-select -p)"
FWK="$DEVDIR/Library/Developer/Frameworks"

if [[ "$DEVDIR" == *CommandLineTools* && -d "$FWK/Testing.framework" ]]; then
  echo "Command Line Tools detected — using Swift Testing workaround flags."
  exec swift test --package-path "$PKG_DIR" \
    -Xswiftc -F -Xswiftc "$FWK" \
    -Xlinker -F -Xlinker "$FWK" \
    -Xlinker -rpath -Xlinker "$FWK" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    "$@"
else
  echo "Full Xcode toolchain detected — running swift test normally."
  exec swift test --package-path "$PKG_DIR" "$@"
fi
