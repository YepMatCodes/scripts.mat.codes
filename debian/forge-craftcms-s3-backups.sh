#!/bin/sh

# ==============================================================================
# File: forge-craftcms-s3-backups.sh
# Description: Syncs CraftCMS site files and databases to an S3 bucket.
#              This script performs the following:
#              - Iterates over directories in the /home/forge directory searching for
#                   CraftCMS sites.
#              - Creates a DB backup for each site into /home/forge/db-backups
#              - Syncs all files for each site to S3 bucket stored in a directory
#                   with the current server's hostname
#              - Syncs DB backups to same S3 directory under a separate /DB-Backups directory
# Author: Mathew Norman
# Created: 2026-03-27
# Last Updated: 2026-03-27
# ==============================================================================

# Require S3 bucket name parameter
if [ -z "$1" ]; then
  echo "Usage: $0 <s3-bucket-name>"
  exit 1
fi

S3_BUCKET_NAME="$1"
S3_BACKUP_TARGET="s3://${S3_BUCKET_NAME}/${HOSTNAME}"

HOSTNAME="$(hostname)"

DB_BACKUP_DIRECTORY="/home/forge/db-backups"
LOG_DIRECTORY="/home/forge/scripts/logs"

# Create backup and log directories if not already present
mkdir -p "${DB_BACKUP_DIRECTORY}"
mkdir -p "${LOG_DIRECTORY}"

# Backup craft databases
create_database_backup() {
    local CRAFT_DIRECTORY="$1"

    # Isolate the server name by stripping the /home/forge/ portion and any trailing /current or slashes
    SITE_NAME="${CRAFT_DIRECTORY#/home/forge/}"
    SITE_NAME="${SITE_NAME%/current/}"
    SITE_NAME="${SITE_NAME%/current}"
    SITE_NAME="${SITE_NAME%/}"

    local SITE_DB_BACKUP_PATH="/home/forge/db-backups/${SITE_NAME}/"
    mkdir -p "${SITE_DB_BACKUP_PATH}"

    # Backup the craft database
    "${CRAFT_DIRECTORY}/craft" db/backup "${SITE_DB_BACKUP_PATH}"
}

# Sync site files to S3
s3_sync_files() {
    local CRAFT_DIRECTORY="$1"

    # Isolate the server name by stripping the /home/forge/ portion and any trailing /current or slashes
    SITE_NAME="${CRAFT_DIRECTORY#/home/forge/}"
    SITE_NAME="${SITE_NAME%/current/}"
    SITE_NAME="${SITE_NAME%/current}"
    SITE_NAME="${SITE_NAME%/}"

    # Sync site files
    echo "\nSyncing ${SITE_NAME} site files"
    aws s3 sync "${CRAFT_DIRECTORY}" "${S3_BACKUP_TARGET}/${SITE_NAME}" --no-progress
}

# Sync DB backup directory
s3_sync_db_backups() {
    echo "\nPerforming database backup"
    aws s3 sync "${DB_BACKUP_DIRECTORY}" "${S3_BACKUP_TARGET}/${SITE_NAME}" --no-progress
}

# Loop through all directories in /home/forge looking for craft installs
for d in /home/forge/*/; do
  if [ -d "$d" ] && [ -f "${d}craft" ]; then
    create_database_backup "${d}"
    s3_sync_files "${d}"
  elif [ -d "${d}current" ] && [ -f "${d}current/craft" ]; then
    create_database_backup "${d}current/"
    s3_sync_files "${d}current/"
  fi
done

s3_sync_db_backups

echo "S3 backups done"

exit 0
