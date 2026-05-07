#!/bin/bash
# Installs a LaunchAgent so the NecroMatcher webhook server starts at login and stays running.
# Run once after clone or path change. Requires: brew install webhook (or webhook on PATH).
#
# GitHub webhook HMAC: set GITHUB_WEBHOOK_SECRET in mac-local/webhook.env or mac-local/local-creds.env (gitignored).
# This script copies those files to ~/.config/necromatcher-ci/ — LaunchAgent cannot source env from ~/Documents (macOS TCC).
# hooks.json uses a Go template; webhook must run with -template (handled by the runner).

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run this script with sudo. User LaunchAgents must load in your GUI session as your login user." >&2
  echo "Run: ./mac-local/install-launchagent.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.kyjor.necromatcher-webhook"
DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
HOOKS_FILE="${SCRIPT_DIR}/hooks.json"
BIND="${WEBHOOK_BIND:-127.0.0.1}"
PORT="${WEBHOOK_PORT:-2095}"

if ! command -v webhook >/dev/null 2>&1; then
  echo "webhook not on PATH. Install with: brew install webhook" >&2
  exit 1
fi

WEBHOOK_BIN="$(command -v webhook)"

chmod +x "${SCRIPT_DIR}/verify-and-run.sh" "${SCRIPT_DIR}/build-and-upload-mac.sh" "${SCRIPT_DIR}/build-mac.sh" "${SCRIPT_DIR}/steam-upload-mac.sh" 2>/dev/null || true
# Some setups mark copied scripts with restrictive provenance/quarantine metadata.
# Clear known exec-blocking attrs so launchd can execute the starter script.
xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true
xattr -dr com.apple.provenance "$SCRIPT_DIR" 2>/dev/null || true

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"

# LaunchAgents cannot read env files under ~/Documents (TCC). Copy secrets to ~/.config for the runner.
CONFIG_DIR="${HOME}/.config/necromatcher-ci"
mkdir -p "$CONFIG_DIR"
for name in webhook.env local-creds.env; do
  if [ -f "${SCRIPT_DIR}/${name}" ]; then
    cp -f "${SCRIPT_DIR}/${name}" "${CONFIG_DIR}/${name}"
  fi
done

# Runner sources only ~/.config copies (not mac-local/*.env under Documents).
RUNNER="${HOME}/Library/LaunchAgents/${LABEL}-runner.sh"
cat > "$RUNNER" <<RUNNER_SCRIPT
#!/bin/bash
set -euo pipefail
WEBHOOK_BIN="${WEBHOOK_BIN}"
HOOKS_FILE="${HOOKS_FILE}"
BIND="${BIND}"
PORT="${PORT}"
CONFIG_DIR="\${HOME}/.config/necromatcher-ci"
for f in "\${CONFIG_DIR}/webhook.env" "\${CONFIG_DIR}/local-creds.env"; do
  if [ -f "\$f" ]; then
    set -a
    # shellcheck source=/dev/null
    . "\$f"
    set +a
  fi
done
exec "\$WEBHOOK_BIN" -template -hooks "\$HOOKS_FILE" -ip "\$BIND" -port "\$PORT" -verbose
RUNNER_SCRIPT
chmod +x "$RUNNER"

cat > "$DEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${RUNNER}</string>
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
echo "Runner: ${RUNNER}"
echo "Edit secrets in ${SCRIPT_DIR}/webhook.env or ${SCRIPT_DIR}/local-creds.env then re-run this script — copies sync to ${CONFIG_DIR}/ (LaunchAgent cannot read Documents)."
echo "Logs: ${HOME}/Library/Logs/necromatcher-webhook.log (and .err.log)"
