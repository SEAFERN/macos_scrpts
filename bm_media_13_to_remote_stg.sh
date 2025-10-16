#!/bin/bash
set -e
set -o pipefail

# ===============================================
# Copy Local Site Image Data to Remote STG Server
# (No permission changes)
# ===============================================

# --- Configuration ---
LOCAL_MEDIA_DIR="/Users/tli/Downloads/CODE_LOCAL/2025-0922_BoutiqueMatch/media"
REMOTE_USER="deploy"                       # adjust if needed
REMOTE_HOST="209.38.0.37"                  # your staging server IP
REMOTE_PATH="/var/www/boutique_match_stg"
SSH_KEY="~/.ssh/id_rsa"                    # optional: path to SSH key

# --- Display Summary ---
echo "=== Copying site image data to remote staging ==="
echo "Local:  $LOCAL_MEDIA_DIR"
echo "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/media"
echo

# --- Step 1: Ensure remote directory exists ---
echo "=== [1] Ensuring remote media directory exists ==="
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_PATH/media"

# --- Step 2: Copy media files ---
echo "=== [2] Copying media files (no permission modification) ==="
rsync -avz --progress -e "ssh -i $SSH_KEY" \
  "$LOCAL_MEDIA_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/media/"

echo
echo "✅ Media files successfully copied to $REMOTE_PATH/media"
echo
echo "💡 Tip: You can verify on server with:"
echo "   ls -lh $REMOTE_PATH/media | head -n 20"
