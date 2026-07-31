#!/usr/bin/env bash
# Builds MarkdownWriter.app from the SwiftPM executable.
# SwiftPM can't emit an app bundle, so we assemble one around the binary.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/MarkdownWriter.app"

swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/MarkdownWriter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MarkdownWriter"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for local use, not for distribution.
codesign --force --sign - "$APP"

# Register the bundle so Finder offers it for .md files.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

echo "Built $APP"
echo "Run: open '$APP'"
