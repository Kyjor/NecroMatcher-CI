#!/usr/bin/env bash
# Codesign the PackageCompiler-built Battler app for distribution (Build tree + .app bundle for notarization).
# Run from repo root after building with SHOULD_BUILD=true.
#
# Set your identity (list with: security find-identity -v -p codesigning):
#   export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
# Then: ./codesign_build.sh
#
# After signing: create zip with  ditto -c -k --keepParent Battler.app Battler.app.zip
# Then notarize: xcrun notarytool submit Battler.app.zip --keychain-profile battler-notary --wait

set -e
cd "$(dirname "$0")"

if [[ "$(uname)" != Darwin ]]; then
  echo "Codesigning is for macOS only. Skipping."
  exit 0
fi

BINARY="Build/bin/Battler"
if [[ ! -f "$BINARY" ]]; then
  echo "Build binary not found: $BINARY. Run the build first (SHOULD_BUILD=true)."
  exit 1
fi

IDENTITY="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY, e.g. export CODESIGN_IDENTITY=\"Developer ID Application: Your Name (TEAM_ID)\"}"
ENTITLEMENTS="$(dirname "$0")/entitlements.plist"

echo "Signing all dylibs and executables in Build (required for notarization)..."
find Build -type f \( -name "*.dylib" -o -name "*.so" \) -print0 | while IFS= read -r -d '' f; do
  codesign --force --options runtime --timestamp -s "$IDENTITY" "$f"
done

# Sign helper executables (not the main Battler yet)
for f in Build/bin/julia Build/libexec/julia/7z; do
  [[ -f "$f" ]] && codesign --force --options runtime --timestamp -s "$IDENTITY" "$f"
done
find Build/share/julia/artifacts -type f -perm -111 ! -name "*.sh" ! -name "*.jl" 2>/dev/null | while read -r f; do
  file "$f" 2>/dev/null | grep -q "Mach-O" && codesign --force --options runtime --timestamp -s "$IDENTITY" "$f" || true
done

echo "Signing $BINARY with entitlements..."
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" -s "$IDENTITY" "$BINARY"
codesign -vv "$BINARY"

echo "Creating macOS app bundle Battler.app..."
APP_DIR="Battler.app"
APP_CONTENTS="$APP_DIR/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

echo "Copying Build into app Resources..."
rsync -a Build/ "$APP_RESOURCES/Build/"

echo "Creating launcher script in Contents/MacOS..."
cat > "$APP_MACOS/Battler" <<'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/../Resources/Build/bin/Battler" "$@"
EOF
chmod +x "$APP_MACOS/Battler"

INFO_PLIST="$APP_CONTENTS/Info.plist"
cat > "$INFO_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Necro Matcher</string>
  <key>CFBundleDisplayName</key>
  <string>Necro Matcher</string>
  <key>CFBundleIdentifier</key>
  <string>com.kyjor.necromatcher</string>
  <key>CFBundleVersion</key>
  <string>1.0.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleExecutable</key>
  <string>Battler</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.15.0</string>
</dict>
</plist>
EOF

echo "Signing Battler.app bundle..."
codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP_DIR"
codesign -vv "$APP_DIR"

echo "Signed Battler binary and Battler.app bundle."
