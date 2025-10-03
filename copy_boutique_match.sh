#!/bin/bash

# Usage: ./copy_boutique_match.sh <REMOTE_USER> <REMOTE_HOST>
# Example: ./copy_boutique_match.sh root 209.38.0.37

REMOTE_USER="$1"
REMOTE_HOST="$2"
REMOTE_PATH="/var/www/boutique_match.tar"
LOCAL_PATH="/Users/tli/Downloads/"

# Ensure both args are provided
if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_HOST" ]; then
  echo "Usage: $0 <REMOTE_USER> <REMOTE_HOST>"
  exit 1
fi

echo "📦 Copying $REMOTE_PATH from $REMOTE_USER@$REMOTE_HOST to $LOCAL_PATH"
scp "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}" "${LOCAL_PATH}"

if [ $? -eq 0 ]; then
  echo "✅ File copied successfully to $LOCAL_PATH"
else
  echo "❌ File copy failed"
fi
