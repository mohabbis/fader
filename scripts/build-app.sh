#!/usr/bin/env bash
# Builds Fader.app with Swift. No need to open the Xcode project.
#
#   scripts/build-app.sh             # native architecture
#   UNIVERSAL=1 scripts/build-app.sh # arm64 + x86_64
#   open build/Fader.app
#
# Needs macOS 14.2+ and the Xcode Command Line Tools (`xcode-select --install`).
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: Fader.app can only be built on macOS." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift was not found. Install the Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.2}"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building release binary"
swift build -c release --product Fader ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --product Fader ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$ROOT/build/Fader.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Fader" "$APP/Contents/MacOS/Fader"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${SIGN_IDENTITY:--}"
echo "==> Signing (identity: $IDENTITY)"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"

ZIP="$ROOT/build/Fader.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Done: $APP"
echo "    Run it with: open \"$APP\""
echo "    Or install it: cp -R \"$APP\" /Applications/"
