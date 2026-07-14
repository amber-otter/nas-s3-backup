#!/usr/bin/env bash
# 在目標 Linux host 上執行這支腳本，將所有設定檔部署到正確位置
# 使用方式：sudo bash deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "請用 sudo 執行：sudo bash deploy.sh"
  exit 1
fi

echo "=== 部署 rclone 設定 ==="

# rclone.conf（需事先填入 Access Key 再部署）
mkdir -p /etc/rclone
cp "${SCRIPT_DIR}/etc_rclone/rclone.conf" /etc/rclone/rclone.conf
chmod 600 /etc/rclone/rclone.conf
chown root:root /etc/rclone/rclone.conf
echo "[OK] /etc/rclone/rclone.conf"

echo "=== 部署備份腳本 ==="
cp "${SCRIPT_DIR}/usr_local_bin/backup-sync.sh" /usr/local/bin/backup-sync.sh
cp "${SCRIPT_DIR}/usr_local_bin/backup-copy.sh" /usr/local/bin/backup-copy.sh
chmod 755 /usr/local/bin/backup-sync.sh
chmod 755 /usr/local/bin/backup-copy.sh
echo "[OK] /usr/local/bin/backup-sync.sh"
echo "[OK] /usr/local/bin/backup-copy.sh"

echo "=== 部署 systemd units ==="
cp "${SCRIPT_DIR}/etc_systemd_system/rclone-sync.service" /etc/systemd/system/
cp "${SCRIPT_DIR}/etc_systemd_system/rclone-sync.timer"   /etc/systemd/system/
cp "${SCRIPT_DIR}/etc_systemd_system/rclone-copy.service" /etc/systemd/system/
cp "${SCRIPT_DIR}/etc_systemd_system/rclone-copy.timer"   /etc/systemd/system/
echo "[OK] systemd units"

echo "=== 部署 logrotate ==="
cp "${SCRIPT_DIR}/etc_logrotate.d/rclone" /etc/logrotate.d/rclone
echo "[OK] /etc/logrotate.d/rclone"

echo "=== 重新載入 systemd ==="
systemctl daemon-reload

echo ""
echo "============================================"
echo "部署完成。請確認以下事項後再啟用 timer："
echo ""
echo "1. 編輯 /etc/rclone/rclone.conf，填入真實的 Access Key 與 Region"
echo "2. 編輯 /usr/local/bin/backup-sync.sh 與 backup-copy.sh，"
echo "   將 your-company-nas-backup 換成你的 S3 bucket 名稱"
echo "3. 確認 NFS 已掛載：df -h /mnt/nas/backup"
echo ""
echo "確認後執行："
echo "  sudo systemctl enable --now rclone-sync.timer"
echo "  sudo systemctl enable --now rclone-copy.timer"
echo "============================================"
