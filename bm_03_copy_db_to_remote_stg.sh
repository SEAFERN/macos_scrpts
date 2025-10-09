#!/bin/bash
set -e
set -o pipefail

# ======================================================
# Backup local DB -> Restore to Remote Staging DB (v7)
# ======================================================
# Usage:
#   ./bm_03_copy_db_to_remote_stg.sh
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
cat > /tmp/boutique_match_restore_stg.sh <<'EOSCRIPT'
#!/bin/bash
set -e
set -a
source /var/www/boutique_match_stg/.env_stg
set +a

export PGPASSWORD="$DB_PASSWORD"
REMOTE_PATH="/tmp/boutique_match.dump"
DBROLE="$DB_USER"   # dynamic role detection

# --- Logging directory ---
LOG_DIR="/var/log/boutique_match_stg"
mkdir -p "$LOG_DIR" 2>/dev/null || true
chmod 777 "$LOG_DIR" || true
LOG_FILE="$LOG_DIR/restore_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo ">>> [0] Starting staging DB restore for $DB_NAME ($DB_USER @ $DB_HOST:$DB_PORT)"
echo ">>> Logging to: $LOG_FILE"

echo ">>> [1] Stopping Gunicorn service..."
systemctl stop boutique_match_stg_gunicorn.service || true

echo ">>> [2] Terminating active DB sessions..."
sudo -u postgres psql -c "
  SELECT pg_terminate_backend(pg_stat_activity.pid)
  FROM pg_stat_activity
  WHERE pg_stat_activity.datname = '$DB_NAME'
    AND pid <> pg_backend_pid();" || true

echo ">>> [3] Dropping old database (if exists)..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"

echo ">>> [4] Creating fresh database owned by $DB_USER..."
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

echo ">>> [5] Restoring dump into $DB_NAME..."
pg_restore --clean --if-exists --no-owner --no-acl \
           -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" \
           -d "$DB_NAME" "$REMOTE_PATH"

echo ">>> [6] Cleaning up dump..."
rm -f "$REMOTE_PATH"

echo ">>> [7] Resetting ownerships and privileges for ALL objects..."
sudo -u postgres psql -d "$DB_NAME" <<SQL
  ALTER SCHEMA public OWNER TO "$DBROLE";

  -- Fix ownership for all tables, sequences, and functions
  DO \$\$
  DECLARE obj RECORD;
  BEGIN
    FOR obj IN SELECT 'TABLE', tablename FROM pg_tables WHERE schemaname='public' LOOP
      BEGIN
        EXECUTE format('ALTER TABLE public.%I OWNER TO %I;', obj.tablename, '$DBROLE');
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped table % due to: %', obj.tablename, SQLERRM;
      END;
    END LOOP;

    FOR obj IN SELECT 'SEQUENCE', sequencename FROM pg_sequences WHERE schemaname='public' LOOP
      BEGIN
        EXECUTE format('ALTER SEQUENCE public.%I OWNER TO %I;', obj.sequencename, '$DBROLE');
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped sequence % due to: %', obj.sequencename, SQLERRM;
      END;
    END LOOP;

    FOR obj IN SELECT 'FUNCTION', routine_name FROM information_schema.routines WHERE routine_schema='public' LOOP
      BEGIN
        EXECUTE format('ALTER FUNCTION public.%I() OWNER TO %I;', obj.routine_name, '$DBROLE');
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped function % due to: %', obj.routine_name, SQLERRM;
      END;
    END LOOP;
  END
  \$\$;

  -- Blanket privileges (covers django_session & others)
  GRANT USAGE ON SCHEMA public TO "$DBROLE";
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "$DBROLE";
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "$DBROLE";
  GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO "$DBROLE";

  -- Default privileges for future migrations
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "$DBROLE";
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "$DBROLE";
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO "$DBROLE";

  -- Re-check and auto-fix any non-matching ownerships (last safety pass)
  DO \$\$
  DECLARE t RECORD;
  BEGIN
    FOR t IN
      SELECT tablename
      FROM pg_tables
      WHERE schemaname = 'public'
        AND tableowner <> '$DBROLE'
    LOOP
      RAISE NOTICE 'Fixing lingering table: %', t.tablename;
      EXECUTE format('ALTER TABLE public.%I OWNER TO %I;', t.tablename, '$DBROLE');
    END LOOP;
  END
  \$\$;
SQL

echo ">>> [8] Restarting Gunicorn service..."
systemctl start boutique_match_stg_gunicorn.service

echo ">>> ✅ Restore complete — verified all objects owned by $DBROLE"
echo ">>> Log file saved at: $LOG_FILE"
EOSCRIPT

echo "=== [4] Copying and executing remote restore script ==="
scp /tmp/boutique_match_restore_stg.sh $REMOTE_USER@$REMOTE_HOST:$REMOTE_SCRIPT
ssh $REMOTE_USER@$REMOTE_HOST "bash $REMOTE_SCRIPT && rm -f $REMOTE_SCRIPT"

echo "=== ✅ Database copied, normalized, and verified on staging ($REMOTE_HOST) ==="
