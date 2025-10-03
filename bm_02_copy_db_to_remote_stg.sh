#!/bin/bash
set -e
set -o pipefail

# ================================
# Backup local DB -> Restore to Remote Staging DB
# ================================

# --- Local macOS DB config ---
LOCAL_DB_NAME="boutique_match"
LOCAL_DB_USER="postgres"
LOCAL_DB_PASSWORD="postgres"
LOCAL_DB_HOST="localhost"
LOCAL_DB_PORT="5432"

# --- Remote server config ---
REMOTE_USER="root"
REMOTE_HOST="209.38.0.37"
REMOTE_ENV="/var/www/boutique_match_stg/.env_stg"
REMOTE_PATH="/tmp/boutique_match.dump"
REMOTE_SERVICE="boutique_match_stg_gunicorn.service"

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
  set -a
  source $REMOTE_ENV
  set +a

  export PGPASSWORD="\$DB_PASSWORD"

  echo "Stopping Gunicorn service..."
  systemctl stop $REMOTE_SERVICE || true

  echo "Terminating active DB sessions..."
  sudo -u postgres psql -c "
    SELECT pg_terminate_backend(pg_stat_activity.pid)
    FROM pg_stat_activity
    WHERE pg_stat_activity.datname = '\$DB_NAME'
      AND pid <> pg_backend_pid();"

  echo "Dropping old database..."
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS \$DB_NAME;"

  echo "Creating fresh database owned by \$DB_USER..."
  sudo -u postgres psql -c "CREATE DATABASE \$DB_NAME OWNER \$DB_USER;"

  echo "Restoring dump into \$DB_NAME..."
  pg_restore --clean --if-exists --no-owner --no-acl \
             -U "\$DB_USER" -h "\$DB_HOST" -p "\$DB_PORT" \
             -d "\$DB_NAME" "$REMOTE_PATH"

  echo "Cleaning up dump..."
  rm -f "$REMOTE_PATH"

  echo "Restarting Gunicorn service..."
  systemctl start $REMOTE_SERVICE
EOF

echo "=== ✅ Database copied successfully to staging ($REMOTE_HOST:$DB_NAME) ==="
