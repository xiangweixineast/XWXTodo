#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/XWXTodo/XWXTodo.xcodeproj"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
DESTINATION="generic/platform=macOS"

rm -rf "$DERIVED_DATA" "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Build without developer certificates, then apply ad-hoc signing for local zip distribution.
xcodebuild build \
  -project "$PROJECT" \
  -scheme XWXTodo \
  -destination "$DESTINATION" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$DERIVED_DATA/Build/Products/Release/XWXTodo.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app at $APP_PATH" >&2
  exit 1
fi

echo "Warning: XWXTodo.zip is ad-hoc signed and not notarized; Gatekeeper may block it on other Macs." >&2
codesign --force --deep --options runtime --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$APP_PATH" "$DIST_DIR/XWXTodo.zip"
echo "$DIST_DIR/XWXTodo.zip"
