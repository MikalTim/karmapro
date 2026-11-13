#!/bin/bash
# Builds Karma Pro from source.
#
#   ./build.sh                 macOS: the AppKit app bundle ("Karma Pro.app").
#                              Linux: same as --no-appkit.
#   ./build.sh --intel-only    macOS: same, x86_64 slice only.
#   ./build.sh --no-appkit     Any OS: the `karma` CLI with the web front end
#                              (`karma --serve`). Builds with SwiftPM, builds the
#                              Svelte app in Web/ (needs Node and npm), and puts
#                              karma-web/ and karma-resources/ next to the binary
#                              (.build/release/).
#   ./build.sh --headless      Any OS: the `karma` CLI without the web server
#                              (no Vapor, no Node needed). Puts karma-resources/
#                              next to the binary.
set -e
cd "$(dirname "$0")"

APPKIT=1
[ "$(uname -s)" = "Darwin" ] || APPKIT=0
WEB=1

# Architectures to build. Both slices are compiled and then combined into one
# universal binary, so the app runs natively on Intel Macs and on Apple Silicon
# without needing Rosetta.
# Pass --intel-only to skip the arm64 slice while iterating on an Intel Mac.
ARCHS=("x86_64" "arm64")
case "${1:-}" in
  --intel-only) ARCHS=("x86_64") ;;
  --no-appkit) APPKIT=0 ;;
  --headless) APPKIT=0; WEB=0 ;;
  "") ;;
  *)
    echo "Unknown option: $1 (expected no arguments, --intel-only, --no-appkit or --headless)" >&2
    exit 2
    ;;
esac

if [ "$APPKIT" = 0 ]; then
  if [ "${1:-}" = "--intel-only" ]; then
    echo "--intel-only builds the AppKit app, which needs macOS." >&2
    exit 2
  fi
  if [ "$WEB" = 1 ]; then
    echo "Building the karma CLI with the web front end (AppKit UI disabled)…"
    swift build -c release --product karma
  else
    echo "Building the headless karma CLI (no web server, AppKit UI disabled)…"
    swift build -c release --product karma --disable-default-traits
  fi
  BIN_DIR="$(swift build -c release --show-bin-path)"
  rm -rf "$BIN_DIR/karma-resources" "$BIN_DIR/karma-web"
  cp -R Resources_src "$BIN_DIR/karma-resources"
  if [ "$WEB" = 1 ]; then
    echo "Building the web front end…"
    (cd Web && npm ci && npm run build)
    cp -R Web/dist "$BIN_DIR/karma-web"
  fi
  echo "Built $BIN_DIR/karma"
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
