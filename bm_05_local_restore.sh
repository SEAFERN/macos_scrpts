#!/bin/bash
set -e
set -o pipefail

# ================================
# Local PostgreSQL Restore Script
# ================================

# --- Local DB Config ---
LOCAL_DB_NAME="boutique_match"
LOCAL_DB_USER="postgres"
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

# --- Drop and recreate DB ---
echo "Dropping old database (if exists)..."
psql -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -c "DROP DATABASE IF EXISTS $LOCAL_DB_NAME;"

echo "Creating fresh database..."
psql -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -c "CREATE DATABASE $LOCAL_DB_NAME OWNER $LOCAL_DB_USER;"

# --- Restore ---
echo "Restoring from dump..."
pg_restore --clean --if-exists --no-owner --no-acl \
           -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" \
           -d "$LOCAL_DB_NAME" "$DUMP_FILE"

echo "=== ✅ Restore completed successfully ==="
