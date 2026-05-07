#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="/Users/kyjor/Documents/Projects/Julia/gmtk-2024"
TARGET="${1:-regular}"

CONTENT_ROOT="$SOURCE_ROOT"
UPLOAD_FILE="Battler.app.zip"

if [ ! -f "$CONTENT_ROOT/$UPLOAD_FILE" ]; then
  echo "$UPLOAD_FILE not found at $CONTENT_ROOT. Run build-mac.sh first."
  exit 1
fi

if [ -n "${STEAMCMD_DIR:-}" ]; then
  :
elif [ -d "/Users/kyjor/Documents/sdk/tools/ContentBuilder/builder_osx" ]; then
  STEAMCMD_DIR="/Users/kyjor/Documents/sdk/tools/ContentBuilder/builder_osx"
else
  STEAMCMD_DIR="/Users/kyjor/Documents/CI/ContentBuilder/builder_osx"
fi

if [ ! -x "$STEAMCMD_DIR/steamcmd.sh" ]; then
  echo "steamcmd.sh not found or not executable in $STEAMCMD_DIR"
  exit 1
fi

STEAM_USERNAME="${STEAM_USERNAME:-kyjorllc}"

case "$TARGET" in
  regular)
    : "${STEAM_APP_ID:?STEAM_APP_ID must be set}"
    : "${STEAM_DEPOT_ID:?STEAM_DEPOT_ID must be set}"
    APP_ID="$STEAM_APP_ID"
    DEPOT_ID="$STEAM_DEPOT_ID"
    BUILD_DESC="${STEAM_BUILD_DESC:-Mac build $(date '+%Y-%m-%d %H:%M:%S')}"
    SET_LIVE_BRANCH="${STEAM_BRANCH:-testing}"
    ;;
  demo)
    : "${STEAM_DEMO_APP_ID:?STEAM_DEMO_APP_ID must be set}"
    : "${STEAM_DEMO_DEPOT_ID:?STEAM_DEMO_DEPOT_ID must be set}"
    APP_ID="$STEAM_DEMO_APP_ID"
    DEPOT_ID="$STEAM_DEMO_DEPOT_ID"
    BUILD_DESC="${STEAM_DEMO_BUILD_DESC:-Demo Mac build $(date '+%Y-%m-%d %H:%M:%S')}"
    SET_LIVE_BRANCH="${STEAM_DEMO_BRANCH:-${STEAM_BRANCH:-testing}}"
    ;;
  *)
    echo "Unknown upload target: $TARGET (expected: regular or demo)"
    exit 1
    ;;
esac

VDF_FILE="$(mktemp /tmp/app_build_${APP_ID}_XXXXXX.vdf)"

cat > "$VDF_FILE" <<EOF
"AppBuild"
{
    "AppID" "${APP_ID}"
    "Desc" "${BUILD_DESC}"
    "ContentRoot" "${CONTENT_ROOT}"
    "BuildOutput" "${STEAM_BUILD_OUTPUT:-$STEAMCMD_DIR/../output}"
    "Depots"
    {
        "${DEPOT_ID}"
        {
            "FileMapping"
            {
                "LocalPath" "${UPLOAD_FILE}"
                "DepotPath" "."
                "recursive" "0"
            }
        }
    }
    "Preview" "0"
    "SetLive" "${SET_LIVE_BRANCH}"
}
EOF

cd "$STEAMCMD_DIR"
if [ -n "${STEAM_PASSWORD:-}" ]; then
  ./steamcmd.sh +login "$STEAM_USERNAME" "$STEAM_PASSWORD" +run_app_build "$VDF_FILE" +quit
else
  ./steamcmd.sh +login "$STEAM_USERNAME" +run_app_build "$VDF_FILE" +quit
fi

echo "Steam upload ($TARGET) complete using $VDF_FILE"

