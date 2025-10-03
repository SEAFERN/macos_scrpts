#!/bin/bash
set -e
set -o pipefail

# ================================
# Copy Local DB -> Remote DB
# ================================

# --- Local macOS DB config ---
LOCAL_DB_NAME="boutique_match"
LOCAL_DB_USER="postgres"         # superuser for pg_dump
LOCAL_DB_PASSWORD="postgres"
LOCAL_DB_HOST="localhost"
LOCAL_DB_PORT="5432"

# --- Remote server config ---
REMOTE_USER="root"                        # or "deploy"
REMOTE_HOST="209.38.0.37"
REMOTE_ENV="/var/www/boutique_match_stg/.env_stg"
REMOTE_PATH="/tmp/boutique_match.dump"

# === Step 1: Dump local DB (custom format, no owners/ACLs) ===
echo "=== Dumping local database as $LOCAL_DB_USER ==="
export PGPASSWORD="$LOCAL_DB_PASSWORD"
pg_dump -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" \
  -Fc --no-owner --no-acl "$LOCAL_DB_NAME" > /tmp/boutique_match.dump

# === Step 2: Copy dump to remote ===
echo "=== Copying dump to remote ==="
scp /tmp/boutique_match.dump $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH

# === Step 3: Restore on remote ===
echo "=== Restoring on remote ==="
ssh $REMOTE_USER@$REMOTE_HOST bash <<EOF
  set -e
  # Load remote DB credentials
  set -a
  source $REMOTE_ENV
  set +a

  export PGPASSWORD="\$DB_PASSWORD"

  echo "Dropping old database (if exists)..."
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS \$DB_NAME;"

  echo "Creating fresh database owned by \$DB_USER..."
  sudo -u postgres psql -c "CREATE DATABASE \$DB_NAME OWNER \$DB_USER;"

  echo "Restoring dump into \$DB_NAME..."
  pg_restore --clean --if-exists --no-owner --no-acl \
             -U "\$DB_USER" -h "\$DB_HOST" -p "\$DB_PORT" \
             -d "\$DB_NAME" "$REMOTE_PATH"

  echo "Cleaning up..."
  rm -f "$REMOTE_PATH"
EOF

echo "=== ✅ Database copied successfully to $REMOTE_HOST:$DB_NAME ==="
