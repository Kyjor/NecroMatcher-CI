#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="/Users/kyjor/Documents/Projects/Julia/gmtk-2024"
BATTLER_DIR="$SOURCE_ROOT/Battler"

if [ ! -d "$BATTLER_DIR" ]; then
  echo "Battler directory not found at $BATTLER_DIR"
  exit 1
fi

cd "$BATTLER_DIR"
git stash
git pull

export JULIA_PROJECT="$BATTLER_DIR"
export SHOULD_BUILD=true
JULIA_BIN="${JULIA_BIN:-}"
if [ -z "$JULIA_BIN" ]; then
  JULIA_BIN="$(command -v julia || true)"
fi
if [ -z "$JULIA_BIN" ] && [ -x "$HOME/.juliaup/bin/julia" ]; then
  JULIA_BIN="$HOME/.juliaup/bin/julia"
fi
if [ -z "$JULIA_BIN" ]; then
  echo "julia executable not found. Set JULIA_BIN in mac-local/local-creds.env."
  exit 1
fi

# Ensure child processes spawned by tests can find julia by name.
export PATH="$(dirname "$JULIA_BIN"):/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Battler's SHOULD_BUILD path currently expects git at /opt/homebrew/bin/git on macOS.
# Create a local shim to /usr/bin/git when needed so launchd runs are consistent.
if [ ! -x /opt/homebrew/bin/git ] && [ -x /usr/bin/git ]; then
  mkdir -p /opt/homebrew/bin 2>/dev/null || true
  ln -sf /usr/bin/git /opt/homebrew/bin/git 2>/dev/null || true
fi

"$JULIA_BIN" -e 'using Pkg; Pkg.activate("."); Pkg.test()' --project="."

mkdir -p "$SOURCE_ROOT/Build/bin"
cp "$BATTLER_DIR/config.julgame" "$SOURCE_ROOT/Build/"
cp "$BATTLER_DIR/libsteam_api.dylib" "$SOURCE_ROOT/Build/bin/"
cp "$BATTLER_DIR/src/steam_appid.txt" "$SOURCE_ROOT/Build/bin/"

# Absolute path so $0 in codesign_build.sh is not "../..."; also avoids wrong entitlements path.
"$SOURCE_ROOT/codesign_build.sh"

cd "$SOURCE_ROOT"
if [ ! -d "Battler.app" ]; then
  echo "Battler.app not found after codesign step"
  exit 1
fi

rm -f Battler.app.zip
/usr/bin/ditto -c -k --keepParent Battler.app Battler.app.zip

