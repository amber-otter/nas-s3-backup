# NAS → AWS S3 備份系統

在地端 Linux host 上透過 NFS 掛載 NetApp NAS，使用 rclone 定期將備份同步到 AWS S3。

```
NetApp Storage
     └── NAS (NFS export)
          └── Linux host (rclone)
               └── AWS S3
```

## 備份模式

| 模式 | 說明 | S3 路徑 |
|------|------|---------|
| sync（鏡像）| S3 完全反映 NAS 現況，NAS 刪了 S3 也刪 | `bucket/sync/` |
| copy（封存）| 只增不刪，NAS 刪了 S3 仍保留 | `bucket/archive/` |

兩個模式同時運行，互不干擾。

## 檔案說明

```
etc_rclone/
  rclone.conf                 rclone S3 設定範例

usr_local_bin/
  backup-sync.sh              sync 模式備份腳本範例
  backup-copy.sh              copy 模式備份腳本範例

etc_systemd_system/
  rclone-sync.service         sync 模式 systemd service 範例
  rclone-sync.timer           sync 模式 systemd timer 範例（每天 02:00）
  rclone-copy.service         copy 模式 systemd service 範例
  rclone-copy.timer           copy 模式 systemd timer 範例（每天 03:00）

etc_logrotate.d/
  rclone                      logrotate 設定範例（保留 30 天）
```

## 設定步驟

詳見 [SETUP_GUIDE.md](./SETUP_GUIDE.md)。

開始前請向管理員索取：
- S3 Bucket 名稱
- AWS Access Key ID
- AWS Secret Access Key

## 需求

- Linux host：Ubuntu/Debian 或 RHEL/CentOS/Rocky
- NAS 可透過 NFS 存取
- Linux host 對外可連線 HTTPS（port 443）
