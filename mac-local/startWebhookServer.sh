#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_FILE="$SCRIPT_DIR/hooks.json"
WEBHOOK_ENV="$SCRIPT_DIR/webhook.env"
LOCAL_CREDS_ENV="$SCRIPT_DIR/local-creds.env"

for f in "$WEBHOOK_ENV" "$LOCAL_CREDS_ENV"; do
  if [ -f "$f" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$f"
    set +a
  fi
done

PORT="${WEBHOOK_PORT:-2095}"
BIND="${WEBHOOK_BIND:-127.0.0.1}"

webhook \
  -template \
  -hooks "$HOOKS_FILE" \
  -ip "$BIND" \
  -port "$PORT" \
  -verbose

