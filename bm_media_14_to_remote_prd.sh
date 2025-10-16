#!/bin/bash
set -e
set -o pipefail

# ===============================================
# Copy Local Site Image Data to Remote PRD Server
# BoutiqueMatch Production Sync (smart)
# ===============================================

# --- Configuration ---
LOCAL_MEDIA_DIR="/Users/tli/Downloads/CODE_LOCAL/2025-0922_BoutiqueMatch/media"
REMOTE_USER="deploy"                       # use deploy user for consistency
REMOTE_HOST="209.38.0.37"                  # your production droplet IP
REMOTE_PATH="/var/www/boutique_match"
REMOTE_MEDIA_DIR="$REMOTE_PATH/media_root"
SSH_KEY="~/.ssh/id_rsa"                    # optional: change if using a different key

# --- Display Summary ---
echo "==============================================="
echo "📦  Starting BoutiqueMatch Production Media Sync"
echo "-----------------------------------------------"
echo "Local:  $LOCAL_MEDIA_DIR"
echo "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR"
echo "==============================================="
echo

# --- Step 1: Ensure remote directory exists ---
echo "=== [1] Ensuring remote media directory exists ==="
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_MEDIA_DIR"

# --- Step 2: Copy media files (incremental, safe) ---
echo "=== [2] Syncing media files (rsync incremental) ==="
rsync -avz --progress -e "ssh -i $SSH_KEY" \
  "$LOCAL_MEDIA_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR/"

# --- Step 3: Summary ---
echo
echo "✅ Media files synced successfully to: $REMOTE_MEDIA_DIR"
echo
echo "💡 Quick verification (remote top 10 files):"
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "ls -lh $REMOTE_MEDIA_DIR | head -n 20"
echo
echo "💾 Done — local ➜ production media sync complete."
echo "==============================================="
