#!/bin/bash
set -e
set -o pipefail

# ======================================================
# Backup local DB -> Restore to Remote Staging DB (v4)
# ======================================================
# Usage:
#   ./bm_03_copy_db_to_remote_stg_v4.sh
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
REMOTE_ENV="/var/www/boutique_match_stg/.env_stg"
REMOTE_PATH="/tmp/boutique_match.dump"
REMOTE_SCRIPT="/tmp/boutique_match_restore_stg.sh"
REMOTE_SERVICE="boutique_match_stg_gunicorn.service"

# --- Cleanup trap ---
trap 'rm -f /tmp/boutique_match.dump /tmp/boutique_match_restore_stg.sh 2>/dev/null || true' EXIT

echo "=== [1] Dumping local database '$LOCAL_DB_NAME' as $LOCAL_DB_USER ==="
export PGPASSWORD="$LOCAL_DB_PASSWORD"
pg_dump -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" \
  -Fc --no-owner --no-acl "$LOCAL_DB_NAME" > /tmp/boutique_match.dump

echo "=== [2] Copying dump to remote server ($REMOTE_HOST) ==="
scp /tmp/boutique_match.dump $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH

echo "=== [3] Creating remote restore script ==="
cat > /tmp/boutique_match_restore_stg.sh <<EOSCRIPT
#!/bin/bash
set -e
set -a
source /var/www/boutique_match_stg/.env_stg
set +a

export PGPASSWORD="\$DB_PASSWORD"
REMOTE_PATH="/tmp/boutique_match.dump"

# --- Logging directory ---
LOG_DIR="/var/log/boutique_match_stg"
mkdir -p "\$LOG_DIR" 2>/dev/null || true
chmod 777 "\$LOG_DIR" || true
LOG_FILE="\$LOG_DIR/restore_\$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "\$LOG_FILE") 2>&1

echo ">>> [0] Starting staging DB restore for \$DB_NAME (\$DB_USER @ \$DB_HOST:\$DB_PORT)"
echo ">>> Logging to: \$LOG_FILE"

echo ">>> [1] Stopping Gunicorn service..."
systemctl stop $REMOTE_SERVICE || true

echo ">>> [2] Terminating active DB sessions..."
sudo -u postgres psql -c "
  SELECT pg_terminate_backend(pg_stat_activity.pid)
  FROM pg_stat_activity
  WHERE pg_stat_activity.datname = '\$DB_NAME'
    AND pid <> pg_backend_pid();" || true

echo ">>> [3] Dropping old database (if exists)..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS \$DB_NAME;"

echo ">>> [4] Creating fresh database owned by \$DB_USER..."
sudo -u postgres psql -c "CREATE DATABASE \$DB_NAME OWNER \$DB_USER;"

echo ">>> [5] Restoring dump into \$DB_NAME from \$REMOTE_PATH..."
pg_restore --clean --if-exists --no-owner --no-acl \
           -U "\$DB_USER" -h "\$DB_HOST" -p "\$DB_PORT" \
           -d "\$DB_NAME" "\$REMOTE_PATH"

echo ">>> [6] Cleaning up dump..."
rm -f "\$REMOTE_PATH"

echo ">>> [7] Normalizing ownership and privileges..."
sudo -u postgres psql -d "\$DB_NAME" <<'SQL'
  ALTER SCHEMA public OWNER TO boutique_match_stg_user;
  DO \$\$
  DECLARE r RECORD;
  BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
      BEGIN
        EXECUTE format('ALTER TABLE public.%I OWNER TO boutique_match_stg_user;', r.tablename);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped table % due to: %', r.tablename, SQLERRM;
      END;
    END LOOP;
    FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public' LOOP
      BEGIN
        EXECUTE format('ALTER SEQUENCE public.%I OWNER TO boutique_match_stg_user;', r.sequencename);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped sequence % due to: %', r.sequencename, SQLERRM;
      END;
    END LOOP;
  END
  \$\$;
  GRANT USAGE ON SCHEMA public TO boutique_match_stg_user;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO boutique_match_stg_user;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO boutique_match_stg_user;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO boutique_match_stg_user;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO boutique_match_stg_user;
SQL

echo ">>> [8] Restarting Gunicorn service..."
systemctl start $REMOTE_SERVICE

echo ">>> ✅ Restore complete — ownership and privileges fixed for boutique_match_stg_user"
echo ">>> Log file saved at: \$LOG_FILE"
EOSCRIPT

echo "=== [4] Copying and executing remote restore script ==="
scp /tmp/boutique_match_restore_stg.sh $REMOTE_USER@$REMOTE_HOST:$REMOTE_SCRIPT
ssh $REMOTE_USER@$REMOTE_HOST "bash $REMOTE_SCRIPT && rm -f $REMOTE_SCRIPT"

echo "=== ✅ Database copied, normalized, and logged on staging ($REMOTE_HOST) ==="
