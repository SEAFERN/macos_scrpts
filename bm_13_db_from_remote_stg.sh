#!/bin/bash
set -e
set -o pipefail

# ================================
# Copy Remote Staging DB -> Local DB
# ================================

# --- Remote server config ---
REMOTE_USER="root"
REMOTE_HOST="209.38.0.37"
REMOTE_ENV="/var/www/boutique_match_stg/.env_stg"
REMOTE_PATH="/tmp/boutique_match_stg.dump"

# --- Local macOS DB config ---
LOCAL_DB_NAME="boutique_match"
LOCAL_DB_USER="postgres"
LOCAL_DB_PASSWORD="postgres"
LOCAL_DB_HOST="localhost"
LOCAL_DB_PORT="5432"

# === Step 1: Dump staging DB remotely ===
echo "=== [1] Dumping staging DB on remote ==="
ssh $REMOTE_USER@$REMOTE_HOST bash <<'EOF'
  set -e
  set -a
  source /var/www/boutique_match_stg/.env_stg
  set +a

  export PGPASSWORD="$DB_PASSWORD"
  echo "Creating dump of staging database: \$DB_NAME"
  pg_dump -U "\$DB_USER" -h "\$DB_HOST" -p "\$DB_PORT" \
    -Fc --no-owner --no-acl "\$DB_NAME" > "$REMOTE_PATH"

  echo "✅ Dump created at $REMOTE_PATH"
EOF

# === Step 2: Copy dump from remote to local ===
echo "=== [2] Copying dump from remote to local ==="
scp $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH /tmp/boutique_match_stg_to_local.dump

# === Step 3: Restore into local database ===
echo "=== [3] Restoring into local database '$LOCAL_DB_NAME' ==="
export PGPASSWORD="$LOCAL_DB_PASSWORD"

# Drop active connections and recreate DB
psql -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -d postgres -c "
  SELECT pg_terminate_backend(pg_stat_activity.pid)
  FROM pg_stat_activity
  WHERE datname = '$LOCAL_DB_NAME' AND pid <> pg_backend_pid();
" || true

psql -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -d postgres -c "DROP DATABASE IF EXISTS $LOCAL_DB_NAME;"
psql -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -d postgres -c "CREATE DATABASE $LOCAL_DB_NAME OWNER $LOCAL_DB_USER;"

pg_restore --clean --if-exists --no-owner --no-acl \
  -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" \
  -d "$LOCAL_DB_NAME" /tmp/boutique_match_stg_to_local.dump

echo "=== [4] Cleaning up ==="
rm -f /tmp/boutique_match_stg_to_local.dump

echo "=== ✅ Database successfully copied from staging to local ($LOCAL_DB_NAME) ==="
