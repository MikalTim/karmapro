#!/bin/bash
# Builds Karma Pro from source.
#
#   ./build.sh                 macOS: the AppKit app bundle ("Karma Pro.app").
#   ./build.sh --intel-only    macOS: same, x86_64 slice only.
#   ./build.sh --no-appkit     Any OS: only the headless `karma` CLI, via SwiftPM
#                              (.build/release/karma). This is the default, and
#                              the only option, on Linux.
set -e
cd "$(dirname "$0")"

APPKIT=1
[ "$(uname -s)" = "Darwin" ] || APPKIT=0

# Architectures to build. Both slices are compiled and then combined into one
# universal binary, so the app runs natively on Intel Macs and on Apple Silicon
# without needing Rosetta.
# Pass --intel-only to skip the arm64 slice while iterating on an Intel Mac.
ARCHS=("x86_64" "arm64")
case "${1:-}" in
  --intel-only) ARCHS=("x86_64") ;;
  --no-appkit|--headless) APPKIT=0 ;;
  "") ;;
  *)
    echo "Unknown option: $1 (expected no arguments, --intel-only or --no-appkit)" >&2
    exit 2
    ;;
esac

if [ "$APPKIT" = 0 ]; then
  if [ "${1:-}" = "--intel-only" ]; then
    echo "--intel-only builds the AppKit app, which needs macOS." >&2
    exit 2
  fi
  echo "Building the headless karma CLI (AppKit UI disabled)…"
  swift build -c release --product karma
  echo "Built $(swift build -c release --show-bin-path)/karma"
  exit 0
fi

APP="Karma Pro.app"
BIN="$APP/Contents/MacOS/Karma Pro"

# The AppKit app compiles the portable engine (Sources/KarmaCore) and the
# macOS UI (Sources/KarmaAppKit) together as one module, exactly as before the
# split, so the UI keeps using the engine's internal types directly.
SOURCES=()
while IFS= read -r source; do
  SOURCES+=("$source")
done < <(find Sources/KarmaCore Sources/KarmaAppKit -name '*.swift' | LC_ALL=C sort)

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Minimum macOS the built app will run on. Keep it as low as the code allows so
# the app works on older macOS (the default target is the *current* OS, which
# would otherwise prevent the app from launching on anything older).
MIN_MACOS="12.0"

echo "Compiling Karma Pro (${ARCHS[*]})…"
SLICES=()
for ARCH in "${ARCHS[@]}"; do
  SLICE="$BUILD_DIR/$ARCH"
  echo "  - $ARCH"
  swiftc -O -target "${ARCH}-apple-macos${MIN_MACOS}" -swift-version 5 -o "$SLICE" "${SOURCES[@]}"
  SLICES+=("$SLICE")
done
lipo -create "${SLICES[@]}" -output "$BIN"
echo "Built binary: $(lipo -archs "$BIN")"

echo "Copying Info.plist and icon…"
# Always copy the Info.plist and icon from the source resources dir into the bundle,
# so a clean rebuild always produces a complete bundle.
cp Resources_src/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Resources_src/AppIcon.icns ]; then
  cp Resources_src/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [ -f Resources_src/SplashImage.jpg ]; then
  cp Resources_src/SplashImage.jpg "$APP/Contents/Resources/SplashImage.jpg"
fi
if [ -f Resources_src/HelpSplash.jpg ]; then
  cp Resources_src/HelpSplash.jpg "$APP/Contents/Resources/HelpSplash.jpg"
fi
if [ -f Resources_src/HelpContent.md ]; then
  cp Resources_src/HelpContent.md "$APP/Contents/Resources/HelpContent.md"
fi
if [ -f Resources_src/AIPrompts.json ]; then
  cp Resources_src/AIPrompts.json "$APP/Contents/Resources/AIPrompts.json"
fi
if [ -d Resources_src/Models ]; then
  # Remove the previous copy first: plain `cp -R src existing-dir` would nest
  # the models as Models/Models and duplicate them on every rebuild.
  rm -rf "$APP/Contents/Resources/Models"
  cp -R Resources_src/Models "$APP/Contents/Resources/Models"
fi

codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
