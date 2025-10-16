#!/bin/bash
set -e
set -o pipefail

# ===============================================
# BoutiqueMatch Bi-Directional Media Sync (Local ↔ PRD)
# Smart rsync with safety preview
# ===============================================

# --- Configuration ---
REMOTE_USER="deploy"
REMOTE_HOST="209.38.0.37"
REMOTE_MEDIA_DIR="/var/www/boutique_match/media_root"
LOCAL_MEDIA_DIR="/Users/tli/Downloads/CODE_LOCAL/2025-0922_BoutiqueMatch/media"
SSH_KEY="~/.ssh/id_rsa"

# --- Display Summary ---
echo "==============================================="
echo "🔄  BoutiqueMatch Bi-Directional Media Sync"
echo "-----------------------------------------------"
echo "Local:  $LOCAL_MEDIA_DIR"
echo "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR"
echo "==============================================="
echo

# --- Step 1: Ensure both directories exist ---
echo "=== [1] Ensuring local and remote directories exist ==="
mkdir -p "$LOCAL_MEDIA_DIR"
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_MEDIA_DIR"
echo "✅ Verified."

# --- Step 2: Preview changes (dry run) ---
echo
echo "=== [2] Performing dry run preview ==="
echo "🟩 Files that would be updated from LOCAL → REMOTE:"
rsync -avzn --delete -e "ssh -i $SSH_KEY" \
  "$LOCAL_MEDIA_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR/" | grep -E '^>f' || true

echo
echo "🟦 Files that would be updated from REMOTE → LOCAL:"
rsync -avzn --delete -e "ssh -i $SSH_KEY" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR/" "$LOCAL_MEDIA_DIR/" | grep -E '^>f' || true

echo
read -rp "Proceed with sync in both directions? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "❌ Sync cancelled."
  exit 0
fi

# --- Step 3: Sync LOCAL → REMOTE ---
echo
echo "=== [3] Syncing LOCAL → REMOTE ==="
rsync -avz --update --progress -e "ssh -i $SSH_KEY" \
  "$LOCAL_MEDIA_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR/"

# --- Step 4: Sync REMOTE → LOCAL ---
echo
echo "=== [4] Syncing REMOTE → LOCAL ==="
rsync -avz --update --progress -e "ssh -i $SSH_KEY" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_MEDIA_DIR/" "$LOCAL_MEDIA_DIR/"

# --- Step 5: Verification ---
echo
echo "✅ Bi-directional sync completed successfully."
echo "   Local dir:  $LOCAL_MEDIA_DIR"
echo "   Remote dir: $REMOTE_MEDIA_DIR"
echo
echo "💡 Quick check (local top 10):"
ls -lh "$LOCAL_MEDIA_DIR" | head -n 20
echo
echo "💡 Quick check (remote top 10):"
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "ls -lh $REMOTE_MEDIA_DIR | head -n 20"
echo
echo "📦 Done — Local ↔ Production media now in sync."
echo "==============================================="
