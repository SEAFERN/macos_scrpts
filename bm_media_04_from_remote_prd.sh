#!/bin/bash
set -e
set -o pipefail

# ===============================================
# Pull Site Image Data FROM Remote PRD Server
# BoutiqueMatch Production ➜ Local Sync (smart)
# ===============================================

# --- Configuration ---
REMOTE_USER="deploy"                        # production server user
REMOTE_HOST="209.38.0.37"                   # production server IP
REMOTE_MEDIA_DIR="/var/www/boutique_match/media_root"
LOCAL_BACKUP_DIR="/Users/tli/Downloads/CODE_LOCAL/2025-0922_BoutiqueMatch/media_from_prd"
SSH_KEY="~/.ssh/id_rsa"                     # path to SSH private key

# --- Display Summary ---
echo "==============================================="
echo "📦  Starting BoutiqueMatch Production ➜ Local Media Pull"
echo "-----------------------------------------------"
echo "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR"
echo "Local:  $LOCAL_BACKUP_DIR"
echo "==============================================="
echo

# --- Step 1: Ensure local directory exists ---
echo "=== [1] Ensuring local backup directory exists ==="
mkdir -p "$LOCAL_BACKUP_DIR"

# --- Step 2: Sync media files from production ---
echo "=== [2] Pulling media files (rsync incremental) ==="
rsync -avz --progress -e "ssh -i $SSH_KEY" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR/" "$LOCAL_BACKUP_DIR/"

# --- Step 3: Summary ---
echo
echo "✅ Media files pulled successfully from production."
echo "   Saved to: $LOCAL_BACKUP_DIR"
echo
echo "💡 Quick verification (local top 10 files):"
ls -lh "$LOCAL_BACKUP_DIR" | head -n 20
echo
echo "💾 Done — production ➜ local media sync complete."
echo "==============================================="
