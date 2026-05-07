#!/bin/bash
# Installs a LaunchAgent so the NecroMatcher webhook server starts at login and stays running.
# Run once after clone or path change. Requires: brew install webhook (or webhook on PATH).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.kyjor.necromatcher-webhook"
DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
HOOKS_FILE="${SCRIPT_DIR}/hooks.json"
WEBHOOK_BIN="$(command -v webhook)"
BIND="${WEBHOOK_BIND:-127.0.0.1}"
PORT="${WEBHOOK_PORT:-2095}"

if ! command -v webhook >/dev/null 2>&1; then
  echo "webhook not on PATH. Install with: brew install webhook" >&2
  exit 1
fi

chmod +x "${SCRIPT_DIR}/verify-and-run.sh" "${SCRIPT_DIR}/build-and-upload-mac.sh" "${SCRIPT_DIR}/build-mac.sh" "${SCRIPT_DIR}/steam-upload-mac.sh" 2>/dev/null || true
# Some setups mark copied scripts with restrictive provenance/quarantine metadata.
# Clear known exec-blocking attrs so launchd can execute the starter script.
xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true
xattr -dr com.apple.provenance "$SCRIPT_DIR" 2>/dev/null || true

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"

cat > "$DEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${WEBHOOK_BIN}</string>
    <string>-hooks</string>
    <string>${HOOKS_FILE}</string>
    <string>-ip</string>
    <string>${BIND}</string>
    <string>-port</string>
    <string>${PORT}</string>
    <string>-verbose</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/necromatcher-webhook.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/necromatcher-webhook.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
PLIST

USER_ID="$(id -u)"
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${USER_ID}" "$DEST"
launchctl enable "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
launchctl kickstart -k "gui/${USER_ID}/${LABEL}"

echo "LaunchAgent ${LABEL} installed and started."
echo "Logs: ${HOME}/Library/Logs/necromatcher-webhook.log (and .err.log)"
