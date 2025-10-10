#!/bin/bash
set -e
set -o pipefail

# ================================
# Local PostgreSQL Backup Script
# ================================

# --- Local DB Config ---
LOCAL_DB_NAME="boutique_match"
LOCAL_DB_USER="postgres"
LOCAL_DB_PASSWORD="postgres"
LOCAL_DB_HOST="localhost"
LOCAL_DB_PORT="5432"

# --- Backup Output ---
BACKUP_DIR="$HOME/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/${LOCAL_DB_NAME}_${TIMESTAMP}.dump"

# --- Ensure backup directory exists ---
mkdir -p "$BACKUP_DIR"

echo "=== [1] Dumping local database '$LOCAL_DB_NAME' as $LOCAL_DB_USER ==="
export PGPASSWORD="$LOCAL_DB_PASSWORD"

pg_dump -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" \
  -Fc --no-owner --no-acl "$LOCAL_DB_NAME" > "$BACKUP_FILE"

echo "=== ✅ Backup completed: $BACKUP_FILE ==="

