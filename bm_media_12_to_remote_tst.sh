#!/bin/bash
set -e
set -o pipefail

# ======================================================
# Copy Local Media Files -> Remote TST Server (v3)
# ======================================================
# Usage:
#   ./bm_media_12_to_remote_tst.sh
# ======================================================

# --- Local and remote config ---
LOCAL_MEDIA_DIR="/Users/tli/Downloads/CODE_LOCAL/2025-0922_BoutiqueMatch/media"
REMOTE_USER="deploy"
REMOTE_HOST="209.38.0.37"
REMOTE_MEDIA_DIR="/var/www/boutique_match_tst/media_root"
SSH_KEY="~/.ssh/id_rsa"   # adjust if using a different key
DOMAIN="tst.boutiquematch.ca"

# --- Summary ---
echo "=== [0] Sync Media Files to Test Environment ==="
echo "Local:  $LOCAL_MEDIA_DIR"
echo "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR"
echo "Domain: https://$DOMAIN"
echo

# --- Ensure local directory exists ---
if [ ! -d "$LOCAL_MEDIA_DIR" ]; then
  echo "❌ Local media directory not found: $LOCAL_MEDIA_DIR"
  exit 1
fi

# --- Step 1: Ensure remote directory exists ---
echo "=== [1] Ensuring remote media directory exists ==="
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_MEDIA_DIR && chmod 775 $REMOTE_MEDIA_DIR && chown -R deploy:www-data $REMOTE_MEDIA_DIR"

# --- Step 2: Rsync media files ---
echo "=== [2] Syncing media files to remote test server ==="
rsync -avzh --progress --delete -e "ssh -i $SSH_KEY" \
  "$LOCAL_MEDIA_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR/"

echo
echo "✅ Media files successfully synced to $REMOTE_MEDIA_DIR"
echo

# --- Step 3: Fix ownership and permissions remotely ---
echo "=== [3] Fixing remote ownership and permissions ==="
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "sudo chown -R deploy:www-data $REMOTE_MEDIA_DIR && sudo chmod -R 775 $REMOTE_MEDIA_DIR"

# --- Step 4: Health check (optional) ---
echo "=== [4] Verifying media directory on remote ==="
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "ls -lh $REMOTE_MEDIA_DIR | head -n 10"

echo
echo "✅ Media sync complete for $DOMAIN"
echo "   Source: $LOCAL_MEDIA_DIR"
echo "   Target: $REMOTE_MEDIA_DIR"
echo "   Ownership: deploy:www-data"
echo
echo "💡 Tip: You can run this script anytime to refresh uploaded media."
