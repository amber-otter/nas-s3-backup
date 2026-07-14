#!/usr/bin/env bash
# rclone sync: S3 完全鏡像 NAS 現況，NAS 刪了 S3 也刪
set -euo pipefail

RCLONE_CONFIG="/etc/rclone/rclone.conf"
SOURCE="/mnt/nas/backup"
DEST="s3-nas-backup:your-company-nas-backup/sync"
LOG_DIR="/var/log/rclone"
LOG_FILE="${LOG_DIR}/sync-$(date +%Y%m%d-%H%M%S).log"
BWLIMIT="50M"

mkdir -p "${LOG_DIR}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting rclone sync" | tee -a "${LOG_FILE}"

rclone sync "${SOURCE}" "${DEST}" \
  --config "${RCLONE_CONFIG}" \
  --bwlimit "${BWLIMIT}" \
  --transfers 4 \
  --checkers 8 \
  --log-level INFO \
  --log-file "${LOG_FILE}" \
  --stats 60s \
  --stats-one-line

EXIT_CODE=$?

if [ ${EXIT_CODE} -eq 0 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync completed successfully" | tee -a "${LOG_FILE}"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync FAILED with exit code ${EXIT_CODE}" | tee -a "${LOG_FILE}"
  exit ${EXIT_CODE}
fi
