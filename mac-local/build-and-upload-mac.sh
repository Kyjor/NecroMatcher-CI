#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBHOOK_ENV="$SCRIPT_DIR/webhook.env"
LOCAL_CREDS_ENV="$SCRIPT_DIR/local-creds.env"

if [ -f "$WEBHOOK_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$WEBHOOK_ENV"
  set +a
fi

if [ -f "$LOCAL_CREDS_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$LOCAL_CREDS_ENV"
  set +a
fi

"$SCRIPT_DIR/build-mac.sh"
"$SCRIPT_DIR/steam-upload-mac.sh" regular
"$SCRIPT_DIR/steam-upload-mac.sh" demo

