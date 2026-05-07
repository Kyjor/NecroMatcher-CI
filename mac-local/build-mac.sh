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

julia -e 'using Pkg; Pkg.activate("."); Pkg.test()' --project="."

mkdir -p "$SOURCE_ROOT/Build/bin"
cp "$BATTLER_DIR/config.julgame" "$SOURCE_ROOT/Build/"
cp "$BATTLER_DIR/libsteam_api.dylib" "$SOURCE_ROOT/Build/bin/"
cp "$BATTLER_DIR/src/steam_appid.txt" "$SOURCE_ROOT/Build/bin/"

../codesign_build.sh

cd "$SOURCE_ROOT"
if [ ! -d "Battler.app" ]; then
  echo "Battler.app not found after codesign step"
  exit 1
fi

rm -f Battler.app.zip
/usr/bin/ditto -c -k --keepParent Battler.app Battler.app.zip

