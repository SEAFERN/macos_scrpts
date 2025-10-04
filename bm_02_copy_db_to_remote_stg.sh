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
REMOTE_SCRIPT="/tmp/boutique_match_restore_stg.sh"
REMOTE_SERVICE="boutique_match_stg_gunicorn.service"

# === Step 1: Dump local DB (custom format, no owners/ACLs) ===
echo "=== Dumping local database as $LOCAL_DB_USER ==="
export PGPASSWORD="$LOCAL_DB_PASSWORD"
pg_dump -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" \
  -Fc --no-owner --no-acl "$LOCAL_DB_NAME" > /tmp/boutique_match.dump

# === Step 2: Copy dump to remote ===
echo "=== Copying dump to remote ==="
scp /tmp/boutique_match.dump $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH

# === Step 3: Create remote restore script ===
cat > /tmp/boutique_match_restore_stg.sh <<'EOSCRIPT'
#!/bin/bash
set -e
set -a
source /var/www/boutique_match_stg/.env_stg
set +a

export PGPASSWORD="$DB_PASSWORD"
REMOTE_PATH="/tmp/boutique_match.dump"

echo "Stopping Gunicorn service..."
systemctl stop boutique_match_stg_gunicorn.service || true

echo "Terminating active DB sessions..."
sudo -u postgres psql -c "
  SELECT pg_terminate_backend(pg_stat_activity.pid)
  FROM pg_stat_activity
  WHERE pg_stat_activity.datname = '${DB_NAME}'
    AND pid <> pg_backend_pid();" || true

echo "Dropping old database..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};"

echo "Creating fresh database owned by ${DB_USER}..."
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

echo "Restoring dump into ${DB_NAME} from ${REMOTE_PATH}..."
pg_restore --clean --if-exists --no-owner --no-acl \
           -U "${DB_USER}" -h "${DB_HOST}" -p "${DB_PORT}" \
           -d "${DB_NAME}" "${REMOTE_PATH}"

echo "Cleaning up dump..."
rm -f "${REMOTE_PATH}"

echo "=== [Post-restore normalization] ==="
sudo -u postgres psql -d "${DB_NAME}" <<SQL
  ALTER SCHEMA public OWNER TO ${DB_USER};
  DO \$\$
  DECLARE r RECORD;
  BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
      EXECUTE format('ALTER TABLE public.%I OWNER TO ${DB_USER};', r.tablename);
    END LOOP;
    FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
    LOOP
      EXECUTE format('ALTER SEQUENCE public.%I OWNER TO ${DB_USER};', r.sequencename);
    END LOOP;
  END\$\$;
  GRANT USAGE ON SCHEMA public TO ${DB_USER};
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
SQL

echo "Restarting Gunicorn service..."
systemctl start boutique_match_stg_gunicorn.service

echo "✅ Restore complete — ownership and privileges fixed for ${DB_USER}"
EOSCRIPT

# === Step 4: Copy script to remote and execute ===
echo "=== Copying and executing remote restore script ==="
scp /tmp/boutique_match_restore_stg.sh $REMOTE_USER@$REMOTE_HOST:$REMOTE_SCRIPT
ssh $REMOTE_USER@$REMOTE_HOST "bash $REMOTE_SCRIPT && rm -f $REMOTE_SCRIPT"

echo "=== ✅ Database copied and normalized on staging ($REMOTE_HOST) ==="
