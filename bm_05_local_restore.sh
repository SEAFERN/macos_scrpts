#!/bin/bash
set -e
set -o pipefail

# ================================
# Local PostgreSQL Restore Script
# ================================

# --- Local DB Config ---
LOCAL_DB_NAME="boutique_match"
LOCAL_DB_USER="postgres"          # Change to 'tli' if you use that locally
LOCAL_DB_PASSWORD="postgres"
LOCAL_DB_HOST="localhost"
LOCAL_DB_PORT="5432"

# --- Input File ---
DUMP_FILE="$1"

if [ -z "$DUMP_FILE" ]; then
  echo "Usage: $0 <path_to_dump_file>"
  exit 1
fi

echo "=== [1] Restoring '$DUMP_FILE' into local DB '$LOCAL_DB_NAME' ==="
export PGPASSWORD="$LOCAL_DB_PASSWORD"

# --- Step 1: Terminate active sessions ---
echo "Terminating active sessions..."
psql -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -d postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname = '$LOCAL_DB_NAME'
    AND pid <> pg_backend_pid();
" || true

# --- Step 2: Drop and recreate database ---
echo "Dropping old database (if exists)..."
psql -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -d postgres -c "DROP DATABASE IF EXISTS $LOCAL_DB_NAME;"

echo "Creating fresh database..."
psql -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -d postgres -c "CREATE DATABASE $LOCAL_DB_NAME OWNER $LOCAL_DB_USER;"

# --- Step 3: Restore from dump ---
echo "Restoring from dump..."
pg_restore --clean --if-exists --no-owner --no-acl \
           -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" \
           -d "$LOCAL_DB_NAME" "$DUMP_FILE"

echo "=== ✅ Restore completed successfully ==="
