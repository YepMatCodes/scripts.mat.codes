#!/usr/bin/env bash

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
# Parameters:
#             <bucket_name> | defaults to using environment value
#                  "FORGE_CRAFT_S3_BUCKET_NAME" if set.
#             --retention <n in days> | defaults to 30 days (optional)
#
# Author: Mathew Norman
# Created: 2026-03-27
# Last Updated: 2026-03-27
# ==============================================================================

RETENTION_DAYS=30
POSITIONAL_BUCKET=""

# Process any retention parameter
while [ $# -gt 0 ]; do
  case "$1" in
    --retention)
      RETENTION_DAYS="$2"
      shift 2
      ;;
    --retention=*)
      RETENTION_DAYS="${1#*=}"
      shift
      ;;
    *)
      POSITIONAL_BUCKET="$1"
      shift
      ;;
  esac
done

# Set bucket name
S3_BUCKET_NAME="${FORGE_CRAFT_S3_BUCKET_NAME:-$POSITIONAL_BUCKET}"

if [ -z "$S3_BUCKET_NAME" ]; then
  printf "Usage: $0 [--retention DAYS] <s3-bucket-name>"
  exit 1
fi

readonly S3_BUCKET_NAME

HOSTNAME="$(hostname)"
S3_BACKUP_TARGET="s3://${S3_BUCKET_NAME}/${HOSTNAME}"


DB_BACKUP_DIRECTORY="/home/forge/_db-backups"
LOG_DIRECTORY="/home/forge/backup-logs"

# Create backup and log directories if not already present
mkdir -p "${DB_BACKUP_DIRECTORY}"
mkdir -p "${LOG_DIRECTORY}"

# Setup logging
# TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="${LOG_DIRECTORY}/forge-craftcms-s3-backups.log"

exec > >(tee -a "${LOG_FILE}") 2>&1

# Backup craft databases
create_database_backup() {
    local CRAFT_DIRECTORY="$1"

    # Isolate the server name by stripping the /home/forge/ portion and any trailing /current or slashes
    SITE_NAME="${CRAFT_DIRECTORY#/home/forge/}"
    SITE_NAME="${SITE_NAME%/current/}"
    SITE_NAME="${SITE_NAME%/current}"
    SITE_NAME="${SITE_NAME%/}"

    local SITE_DB_BACKUP_PATH="${DB_BACKUP_DIRECTORY}/${SITE_NAME}/"
    mkdir -p "${SITE_DB_BACKUP_PATH}"

    # Backup the craft database
    # if "${CRAFT_DIRECTORY}/craft" db/backup "${SITE_DB_BACKUP_PATH}" \
    #         --zip 1 --interactive 0 \
    #         > /dev/null 2>&1; then
    #     printf "[SUCCESS][DBEXPORT] $(date '+%Y-%m-%d %H:%M:%S') Craft DB backup completed for ${SITE_NAME}\n"
    # else
    #     printf "[ERROR][DBEXPORT] $(date '+%Y-%m-%d %H:%M:%S') Craft DB backup failed for ${SITE_NAME}\n"
    # fi
}

# Sync site files to S3
s3_sync_files() {
    local CRAFT_DIRECTORY="$1"

    # Isolate the server name by stripping the /home/forge/ portion and any trailing /current or slashes
    SITE_NAME="${CRAFT_DIRECTORY#/home/forge/}"
    SITE_NAME="${SITE_NAME%/current/}"
    SITE_NAME="${SITE_NAME%/current}"
    SITE_NAME="${SITE_NAME%/}"

    # printf ${SITE_NAME}

    # Sync site files
    # if aws s3 sync "${CRAFT_DIRECTORY}" "${S3_BACKUP_TARGET}/${SITE_NAME}" \
    #       --profile craftcms-backups \
    #       --exclude ".git/*" \
    #       --exclude "vendor/*" \
    #       --exclude "node_modules/*" \
    #       --exclude "storage/runtime/*" \
    #       --exclude "*/.git/*" \
    #       --exclude "*/vendor/*" \
    #       --exclude "*/node_modules/*" \
    #       --exclude "*/storage/runtime/*" \
    #       --no-progress \
    #       --only-show-errors; then
    #     printf "[SUCCESS][FILESYNC] $(date '+%Y-%m-%d %H:%M:%S') S3 sync completed for ${SITE_NAME}\n"
    # else
    #     printf "[ERROR][FILESYNC] $(date '+%Y-%m-%d %H:%M:%S') S3 sync failed for ${SITE_NAME}\n"
    # fi
}

# Sync DB backup directory
s3_sync_db_backups() {
    DB_S3_BACKUP_TARGET="${S3_BACKUP_TARGET}/_DB-Backups"

    printf "[DEBUG][DBSYNC] Backup dir: %s\n" "${DB_BACKUP_DIRECTORY}"
    printf "[DEBUG][DBSYNC] Backup target: %s\n" "${DB_S3_BACKUP_TARGET}"

    # aws s3 sync "${DB_BACKUP_DIRECTORY}" "${DB_S3_BACKUP_TARGET}" \
    #     --profile craftcms-backups \
    #     --no-progress \
    #     --only-show-errors
    # STATUS=$?

    # if [ "${STATUS}" -eq 0 ]; then
    #     printf "[SUCCESS][DBSYNC] %s S3 sync completed for DB Backups\n" \
    #         "$(date '+%Y-%m-%d %H:%M:%S')"
    # else
    #     printf "[ERROR][DBSYNC] %s S3 sync failed for DB Backups (exit code: %s)\n" \
    #         "$(date '+%Y-%m-%d %H:%M:%S')" "${STATUS}"
    #     return "${STATUS}"
    # fi
}

# Delete DB backups older than a given retention date (default: 30 days)
s3_backup_retention() {
    printf "\nRemoving backups older than ${RETENTION_DAYS} days old\n"
    find "${DB_BACKUP_DIRECTORY}" -type f -mtime +"${RETENTION_DAYS}" \
        -print -delete
}

printf "Backup started at: $(date '+%Y-%m-%d %H:%M:%S')\n\n"

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
s3_backup_retention

printf "\nBackup finished at: $(date '+%Y-%m-%d %H:%M:%S')\n"

exit 0
