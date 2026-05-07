#!/bin/bash
# Called by adnanh/webhook before the local build. If LOCAL_WEBHOOK_SECRET is set
# in the environment of the webhook process (e.g. via mac-local/webhook.env), the
# request must include header X-Local-Build-Token with the same value.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${LOCAL_WEBHOOK_SECRET:-}" ]; then
  if [ "${HTTP_X_LOCAL_BUILD_TOKEN:-}" != "$LOCAL_WEBHOOK_SECRET" ]; then
    echo "Unauthorized" >&2
    exit 1
  fi
fi

exec "$SCRIPT_DIR/build-and-upload-mac.sh"
