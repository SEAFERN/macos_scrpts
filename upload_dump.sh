#!/usr/bin/env bash
# Upload local dump file to remote server with scp
# Usage: ./upload_dump.sh /local/path/to/dumpfile.dump

set -euo pipefail

# === Config ===
LOCAL_FILE="$1"
REMOTE_USER="root"                # change if needed
REMOTE_HOST="209.38.0.37"        # e.g. 207.81.204.2
REMOTE_PATH="/path/to"          # where to put the dump

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /local/path/to/dumpfile.dump"
  exit 1
fi

echo "=== Uploading $LOCAL_FILE to $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH ==="
scp "$LOCAL_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"

echo "=== ✅ Upload complete ==="
