#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_FILE="$SCRIPT_DIR/hooks.json"
WEBHOOK_ENV="$SCRIPT_DIR/webhook.env"

if [ -f "$WEBHOOK_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$WEBHOOK_ENV"
  set +a
fi

PORT="${WEBHOOK_PORT:-2095}"
BIND="${WEBHOOK_BIND:-127.0.0.1}"

webhook \
  -hooks "$HOOKS_FILE" \
  -ip "$BIND" \
  -port "$PORT" \
  -verbose

