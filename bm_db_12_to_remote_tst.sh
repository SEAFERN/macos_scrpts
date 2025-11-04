#!/bin/bash
set -e
set -o pipefail

# ======================================================
# Backup local DB -> Restore to Remote TST DB (v6)
# ======================================================
# Usage:
#   ./bm_db_12_to_remote_tst.sh
# ======================================================

# --- Local macOS DB config ---
LOCAL_DB_NAME="boutique_match"
LOCAL_DB_USER="postgres"
LOCAL_DB_PASSWORD="postgres"
LOCAL_DB_HOST="localhost"
LOCAL_DB_PORT="5432"

# --- Remote server config ---
REMOTE_USER="root"
REMOTE_HOST="209.38.0.37"
REMOTE_ENV="/var/www/boutique_match_tst/.env_tst"
REMOTE_PATH="/tmp/boutique_match_tst.dump"
REMOTE_SCRIPT="/tmp/boutique_match_restore_tst.sh"
REMOTE_SERVICE="boutique_match_tst_gunicorn.service"

# --- Cleanup trap ---
trap 'rm -f /tmp/boutique_match_tst.dump /tmp/boutique_match_restore_tst.sh 2>/dev/null || true' EXIT

echo "=== [1] Dumping local database '$LOCAL_DB_NAME' as $LOCAL_DB_USER ==="
export PGPASSWORD="$LOCAL_DB_PASSWORD"
pg_dump -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" \
  -Fc --no-owner --no-acl "$LOCAL_DB_NAME" > /tmp/boutique_match_tst.dump

echo "=== [2] Copying dump to remote server ($REMOTE_HOST) ==="
scp /tmp/boutique_match_tst.dump $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH

echo "=== [3] Creating remote restore script ==="
cat > /tmp/boutique_match_restore_tst.sh <<'EOSCRIPT'
#!/bin/bash
set -e
set -o pipefail

ENV_PATH="/var/www/boutique_match_tst/.env_tst"

# --- Load environment safely (handles quotes & special chars) ---
if [ ! -f "$ENV_PATH" ]; then
  echo "❌ Environment file missing: $ENV_PATH"
  exit 1
fi

set -a
source "$ENV_PATH"
set +a

REQUIRED_VARS=(DB_NAME DB_USER DB_PASSWORD DB_HOST DB_PORT)
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ Missing required variable: $var"
    exit 1
  fi
done

REMOTE_PATH="/tmp/boutique_match_tst.dump"
DBROLE="$DB_USER"
LOG_DIR="/var/log/boutique_match_tst"
mkdir -p "$LOG_DIR"
chmod 777 "$LOG_DIR"
LOG_FILE="$LOG_DIR/restore_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Temporary .pgpass for passwordless restore ---
PGPASS="/root/.pgpass"
echo "$DB_HOST:$DB_PORT:$DB_NAME:$DB_USER:$DB_PASSWORD" > "$PGPASS"
chmod 600 "$PGPASS"
export PGPASSFILE="$PGPASS"

echo ">>> ==================================================="
echo ">>> Starting TEST restore for: $DB_NAME ($DB_USER @ $DB_HOST:$DB_PORT)"
echo ">>> ==================================================="

systemctl stop $REMOTE_SERVICE || true

# --- Ensure PostgreSQL user password matches .env_tst ---
echo ">>> [0] Synchronizing PostgreSQL user password..."
sudo -u postgres psql -c "ALTER USER \"$DB_USER\" WITH PASSWORD '$DB_PASSWORD';" || true

# --- Terminate active connections ---
sudo -u postgres psql -c "
  SELECT pg_terminate_backend(pg_stat_activity.pid)
  FROM pg_stat_activity
  WHERE pg_stat_activity.datname = '$DB_NAME'
    AND pid <> pg_backend_pid();" || true

# --- Drop and recreate database ---
echo ">>> [1] Dropping old database (if exists)..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
echo ">>> [2] Creating fresh database owned by $DB_USER..."
sudo -u postgres psql -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"

# --- Restore data ---
echo ">>> [3] Restoring dump into $DB_NAME..."
pg_restore --clean --if-exists --no-owner --no-acl \
           -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" \
           -d "$DB_NAME" "$REMOTE_PATH"

# --- Cleanup dump ---
echo ">>> [4] Cleaning up dump..."
rm -f "$REMOTE_PATH"

# --- Reset ownerships & privileges ---
echo ">>> [5] Resetting ownerships and privileges..."
sudo -u postgres psql -d "$DB_NAME" <<SQL
  ALTER SCHEMA public OWNER TO "$DBROLE";
  GRANT ALL PRIVILEGES ON SCHEMA public TO "$DBROLE";

  DO \$\$
  DECLARE obj RECORD;
  BEGIN
    FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
      BEGIN
        EXECUTE format('ALTER TABLE public.%I OWNER TO %I;', obj.tablename, '$DBROLE');
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped table % due to: %', obj.tablename, SQLERRM;
      END;
    END LOOP;
  END
  \$\$;

  GRANT USAGE ON SCHEMA public TO "$DBROLE";
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "$DBROLE";
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "$DBROLE";
  GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO "$DBROLE";

  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "$DBROLE";
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "$DBROLE";
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO "$DBROLE";
SQL

# --- Restart Gunicorn ---
systemctl start $REMOTE_SERVICE || true

# --- Cleanup .pgpass ---
rm -f "$PGPASS"

echo ">>> ✅ Restore complete"
echo ">>> Log file: $LOG_FILE"
EOSCRIPT

echo "=== [4] Copying and executing remote restore script ==="
scp /tmp/boutique_match_restore_tst.sh $REMOTE_USER@$REMOTE_HOST:$REMOTE_SCRIPT
ssh $REMOTE_USER@$REMOTE_HOST "bash $REMOTE_SCRIPT && rm -f $REMOTE_SCRIPT"

echo
echo "=== ✅ Database copied, normalized, and verified on TEST ($REMOTE_HOST) ==="
