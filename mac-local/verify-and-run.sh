#!/bin/bash
# Called by adnanh/webhook before the local build. If LOCAL_WEBHOOK_SECRET is set
# in the environment of the webhook process (e.g. via mac-local/webhook.env), the
# request must include header X-Local-Build-Token with the same value.

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

exec "$SCRIPT_DIR/build-and-upload-mac.sh"
