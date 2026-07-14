# NAS → AWS S3 備份系統 設定指南

## 架構概覽

```mermaid
flowchart LR
    NAS["NetApp NAS"] -->|NFS| Host["Linux 備份主機\n(rclone)"] -->|HTTPS| S3["AWS S3"]
```

## 前置條件

- 地端 Linux host（Ubuntu/Debian 或 RHEL/CentOS/Rocky）
- 可連線到 NetApp NAS 的網路
- Linux host 可對外連線到 AWS（需開放 HTTPS 443 out）

### 由管理員事先提供的資訊

開始前，請向管理員索取以下三項資訊：

| 項目 | 說明 | 範例 |
|------|------|------|
| S3 Bucket 名稱 | 備份目標的 bucket | `mycompany-nas-backup` |
| Access Key ID | AWS 認證 ID | `AKIAIOSFODNN7EXAMPLE` |
| Secret Access Key | AWS 認證金鑰 | `wJalrXUtnFEMI/K7MDENG/...` |

以上資訊在後續步驟中會用到，請先備妥。

---

## 第一步：安裝 NFS client

### Ubuntu / Debian

```bash
sudo apt update && sudo apt install -y nfs-common
```

### RHEL / CentOS / Rocky

```bash
sudo dnf install -y nfs-utils
```

確認安裝成功：

```bash
showmount --version
```

---

## 第二步：掛載 NAS

### 2-1 建立 mount point

```bash
sudo mkdir -p /mnt/nas/backup
```

### 2-2 查看 NAS 有哪些 NFS export

將 `<NAS_IP>` 換成你的 NAS IP：

```bash
showmount -e <NAS_IP>
```

輸出範例：
```
Export list for 192.168.1.100:
/vol/backup  *
```

### 2-3 手動掛載測試

將 `<NAS_IP>` 與 `<EXPORT_PATH>` 換成你的值（例如 `/vol/backup`）：

```bash
sudo mount -t nfs -o rw,hard,intr,rsize=65536,wsize=65536,timeo=14 \
  <NAS_IP>:<EXPORT_PATH> /mnt/nas/backup
```

確認掛載成功：

```bash
df -h /mnt/nas/backup
ls /mnt/nas/backup
```

`df` 應顯示 NAS 的容量，`ls` 應看到備份檔案。

### 2-4 設定開機自動掛載

編輯 `/etc/fstab`：

```bash
sudo vim /etc/fstab
```

在檔案末尾加入以下一行（替換 IP 與路徑）：

```
<NAS_IP>:<EXPORT_PATH>  /mnt/nas/backup  nfs  rw,hard,intr,rsize=65536,wsize=65536,timeo=14,_netdev  0  0
```

> `_netdev` 確保等網路就緒後才掛載，避免開機卡住。

儲存後驗證 fstab 語法：

```bash
sudo mount -a
```

無任何輸出即代表正確。重新掛載測試：

```bash
sudo umount /mnt/nas/backup && sudo mount /mnt/nas/backup
df -h /mnt/nas/backup
```

---

## 第三步：安裝並設定 rclone

> 以下步驟需要管理員提供的 Bucket 名稱、Access Key ID 與 Secret Access Key。

### 3-1 安裝 rclone

```bash
sudo apt install -y curl unzip   # Ubuntu/Debian
# 或
sudo dnf install -y curl unzip   # RHEL/Rocky

curl https://rclone.org/install.sh | sudo bash
```

確認安裝版本：

```bash
rclone version
```

應顯示 v1.60 以上。

### 3-2 建立設定檔

```bash
sudo mkdir -p /etc/rclone
sudo touch /etc/rclone/rclone.conf
sudo chmod 600 /etc/rclone/rclone.conf
sudo chown root:root /etc/rclone/rclone.conf
```

### 3-3 填寫設定

```bash
sudo vim /etc/rclone/rclone.conf
```

貼入以下內容，替換所有 `< >` 的值：

```ini
[s3-nas-backup]
type = s3
provider = AWS
access_key_id = <YOUR_ACCESS_KEY_ID>
secret_access_key = <YOUR_SECRET_ACCESS_KEY>
region = <YOUR_REGION>
server_side_encryption = AES256
```

> `region` 範例：`ap-northeast-1`（東京）、`ap-southeast-1`（新加坡）

確認權限正確：

```bash
ls -la /etc/rclone/rclone.conf
# 應顯示：-rw------- 1 root root
```

### 3-4 測試 S3 連線

將 `mycompany-nas-backup` 換成管理員提供的 bucket 名稱：

```bash
sudo rclone --config /etc/rclone/rclone.conf ls s3-nas-backup:mycompany-nas-backup
```

- 空白輸出 → 正常（bucket 尚無資料）
- 列出檔案清單 → 正常
- 出現任何錯誤訊息 → 請聯絡管理員確認 Access Key 與 Bucket 名稱是否正確

---

## 第四步：建立備份腳本

建立兩支腳本，分別對應 sync 與 copy 兩種模式。腳本內容範例如下，建立時將 `mycompany-nas-backup` 換成管理員提供的 bucket 名稱。

**兩種模式的差異：**

| 模式 | 指令 | 目的地多出的檔案 | 來源刪除後 | 適合情境 |
|------|------|-----------------|-----------|---------|
| 鏡像模式 | `rclone sync` | **刪除**（與來源保持完全一致）| 目的地也跟著刪除 | 節省空間、保持即時鏡像 |
| 封存模式 | `rclone copy` | 保留不動 | 目的地仍保留 | 長期封存、保留歷史版本 |

> ⚠️ 使用 `sync` 前建議先加 `--dry-run` 參數確認會異動哪些檔案，避免誤刪。

### 4-1 建立 sync 腳本（鏡像模式）

建立 `/usr/local/bin/backup-sync.sh`，內容範例：

```bash
#!/usr/bin/env bash
set -euo pipefail

RCLONE_CONFIG="/etc/rclone/rclone.conf"
SOURCE="/mnt/nas/backup"
DEST="s3-nas-backup:mycompany-nas-backup/sync"
LOG_DIR="/var/log/rclone"
LOG_FILE="${LOG_DIR}/sync-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting rclone sync" | tee -a "${LOG_FILE}"

rclone sync "${SOURCE}" "${DEST}" \
  --config "${RCLONE_CONFIG}" \
  --bwlimit 50M \
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
```

建立完成後設定執行權限：

```bash
sudo chmod 755 /usr/local/bin/backup-sync.sh
```

### 4-2 建立 copy 腳本（封存模式）

建立 `/usr/local/bin/backup-copy.sh`，內容範例：

```bash
#!/usr/bin/env bash
set -euo pipefail

RCLONE_CONFIG="/etc/rclone/rclone.conf"
SOURCE="/mnt/nas/backup"
DEST="s3-nas-backup:mycompany-nas-backup/archive"
LOG_DIR="/var/log/rclone"
LOG_FILE="${LOG_DIR}/copy-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting rclone copy" | tee -a "${LOG_FILE}"

rclone copy "${SOURCE}" "${DEST}" \
  --config "${RCLONE_CONFIG}" \
  --bwlimit 50M \
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
```

建立完成後設定執行權限：

```bash
sudo chmod 755 /usr/local/bin/backup-copy.sh
```

### 4-3 先跑 dry-run 確認（不會真的傳檔案）

```bash
sudo rclone sync /mnt/nas/backup s3-nas-backup:mycompany-nas-backup/sync \
  --config /etc/rclone/rclone.conf \
  --dry-run \
  --log-level INFO
```

輸出應顯示會傳哪些檔案，確認路徑與數量合理。copy 模式同理：

```bash
sudo rclone copy /mnt/nas/backup s3-nas-backup:mycompany-nas-backup/archive \
  --config /etc/rclone/rclone.conf \
  --dry-run \
  --log-level INFO
```

### 4-4 手動執行一次確認正常

```bash
sudo /usr/local/bin/backup-sync.sh
sudo /usr/local/bin/backup-copy.sh
```

執行完成後，請管理員確認 S3 bucket 內 `sync/` 與 `archive/` 下已有檔案。

---

## 第五步：設定 systemd 定期排程（Optional）

> 若不需要自動排程，可略過此步驟，改用手動執行備份腳本。

### 5-1 建立 service 與 timer unit 檔案

以下共需建立四個檔案，內容如範例所示，可依需求調整排程時間。

**/etc/systemd/system/rclone-sync.service**
```ini
[Unit]
Description=rclone sync - NAS to S3 mirror
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-sync.sh
User=root
StandardOutput=journal
StandardError=journal
TimeoutStartSec=3600
```

**/etc/systemd/system/rclone-sync.timer**
```ini
[Unit]
Description=rclone sync timer - daily at 02:00

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
```

**/etc/systemd/system/rclone-copy.service**
```ini
[Unit]
Description=rclone copy - NAS to S3 archive
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-copy.sh
User=root
StandardOutput=journal
StandardError=journal
TimeoutStartSec=3600
```

**/etc/systemd/system/rclone-copy.timer**
```ini
[Unit]
Description=rclone copy timer - daily at 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
```

### 5-2 啟用 timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rclone-sync.timer
sudo systemctl enable --now rclone-copy.timer
```

確認狀態：

```bash
sudo systemctl list-timers | grep rclone
```

兩個 timer 應顯示 `active (waiting)` 並有下次執行時間。

---

## 第六步：設定 Log Rotation（Optional）

> 若不需要自動清理 log，可略過此步驟。

建立 `/etc/logrotate.d/rclone`，內容範例如下：

```
/var/log/rclone/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
```

上方設定會每天 rotate 一次，保留 30 天，舊 log 自動壓縮。可依需求調整 `rotate` 的天數。

建立後測試設定是否正確：

```bash
sudo logrotate --debug /etc/logrotate.d/rclone
```

無 error 訊息即正確。

---

## 驗證清單

全部完成後，逐項確認：

| 項目 | 驗證指令 | 預期結果 |
|------|----------|----------|
| NFS 掛載 | `df -h /mnt/nas/backup` | 顯示 NAS 容量 |
| 開機持久 | `sudo mount -a` | 無錯誤輸出 |
| rclone 連線 | `sudo rclone --config /etc/rclone/rclone.conf ls s3-nas-backup:mycompany-nas-backup` | 列出 sync/ 與 archive/ |
| Sync 執行 | `sudo /usr/local/bin/backup-sync.sh` | log 最後顯示 `Sync completed successfully` |
| Copy 執行 | `sudo /usr/local/bin/backup-copy.sh` | log 最後顯示 `Copy completed successfully` |
| S3 上傳確認 | 請管理員確認 S3 bucket 已收到資料 | sync/ 與 archive/ 下有檔案 |
| Timer 運作（Optional） | `systemctl list-timers \| grep rclone` | 兩個 timer 均 active |
| Logrotate（Optional） | `sudo logrotate --debug /etc/logrotate.d/rclone` | 無 error |

---

## 常用維運指令

```bash
# 查看最近一次 sync 執行結果
sudo journalctl -u rclone-sync.service -n 50

# 查看最近一次 copy 執行結果
sudo journalctl -u rclone-copy.service -n 50

# 查看所有 rclone log 檔案
ls -lht /var/log/rclone/

# 手動立即觸發 sync
sudo systemctl start rclone-sync.service

# 手動立即觸發 copy
sudo systemctl start rclone-copy.service

# 暫停定期排程（不影響手動執行）
sudo systemctl stop rclone-sync.timer

# 恢復定期排程
sudo systemctl start rclone-sync.timer

# 查看 S3 bucket 目前使用量
sudo rclone --config /etc/rclone/rclone.conf size s3-nas-backup:mycompany-nas-backup
```

---

## sync 與 copy 的差別

| | sync（鏡像）| copy（封存）|
|-|------------|------------|
| NAS 刪了檔案 | S3 也跟著刪 | S3 仍保留 |
| S3 路徑 | `bucket/sync/` | `bucket/archive/` |
| 排程時間 | 每天 02:00 | 每天 03:00 |
| 適合用途 | 災難還原（快速還原當下狀態）| 長期封存（找回已刪除的舊檔） |

兩個模式同時跑，互不干擾。
