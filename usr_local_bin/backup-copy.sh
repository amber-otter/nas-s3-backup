#!/usr/bin/env bash
# rclone copy: 只增不刪，NAS 刪了 S3 仍保留（搭配 S3 版本控制做長期封存）
set -euo pipefail

RCLONE_CONFIG="/etc/rclone/rclone.conf"
SOURCE="/mnt/nas/backup"
DEST="s3-nas-backup:your-company-nas-backup/archive"
LOG_DIR="/var/log/rclone"
LOG_FILE="${LOG_DIR}/copy-$(date +%Y%m%d-%H%M%S).log"
BWLIMIT="50M"

mkdir -p "${LOG_DIR}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting rclone copy" | tee -a "${LOG_FILE}"

rclone copy "${SOURCE}" "${DEST}" \
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
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copy completed successfully" | tee -a "${LOG_FILE}"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copy FAILED with exit code ${EXIT_CODE}" | tee -a "${LOG_FILE}"
  exit ${EXIT_CODE}
fi
