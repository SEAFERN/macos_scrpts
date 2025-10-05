#!/usr/bin/env bash
# Upload a local dump file and restore it on remote server
# Usage: ./upload_and_restore.sh /local/path/to/dumpfile.dump

set -euo pipefail

# === Config ===
LOCAL_FILE="$1"
REMOTE_USER="root"
REMOTE_HOST="209.38.0.37"
REMOTE_PATH="/path/to"
DB_NAME="boutique_match_stg"
DB_USER="boutique_match_user"
DB_HOST="localhost"
DB_PORT="5432"
GUNICORN_SERVICE="boutique_match_stg_gunicorn.service"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /local/path/to/dumpfile.dump"
  exit 1
fi

BASENAME=$(basename "$LOCAL_FILE")
REMOTE_FILE="$REMOTE_PATH/$BASENAME"

echo "=== [1] Uploading $LOCAL_FILE to $REMOTE_USER@$REMOTE_HOST:$REMOTE_FILE ==="
scp "$LOCAL_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_FILE"

echo "=== [2] Running restore on remote server ==="
ssh "$REMOTE_USER@$REMOTE_HOST" bash -s <<EOF
  set -euo pipefail
  echo ">>> Stopping Gunicorn service ($GUNICORN_SERVICE)"
  systemctl stop "$GUNICORN_SERVICE" || true

  echo ">>> Terminating existing DB connections"
  sudo -u postgres psql -d postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname = '$DB_NAME'
    AND pid <> pg_backend_pid();
  "

  echo ">>> Dropping old DB (if exists)"
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"

  echo ">>> Creating fresh DB owned by $DB_USER"
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

  echo ">>> Restoring dump into $DB_NAME"
  pg_restore \
    --no-owner \
    --no-privileges \
    -U "$DB_USER" \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -d "$DB_NAME" \
    "$REMOTE_FILE"

  echo ">>> Fixing schema ownership"
  sudo -u postgres psql -d "$DB_NAME" -c "ALTER SCHEMA public OWNER TO $DB_USER;"

  echo ">>> Restarting Gunicorn service ($GUNICORN_SERVICE)"
  systemctl start "$GUNICORN_SERVICE"

  echo ">>> ✅ Restore completed successfully for $DB_NAME"
EOF
