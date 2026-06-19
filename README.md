# BackupNotify

macOS 菜单栏应用 — 监控备份目录并在新文件夹出现时发送 Webhook 通知。

## 功能

- 监控多个目录，检测新文件夹
- 统计文件夹大小、文件数、视频文件数
- 支持飞书/钉钉/企业微信/Slack/Discord 等 Webhook 平台
- 免打扰时段设置
- 本地通知提醒
- 历史记录与 CSV 导出
- 自动日志轮转

## 系统要求

- macOS 13.0 Ventura+
- Xcode 15.0+
- Swift 5.9+

## 构建

```bash
open BackupNotify.xcodeproj
# 或
xcodebuild -project BackupNotify.xcodeproj -scheme BackupNotify -configuration Release
```

## 架构

```
BackupNotify/
├── App/          — 应用入口与生命周期
├── Engine/       — 目录扫描引擎
├── Notify/       — Webhook 通知与模板
├── Storage/      — 数据模型与持久化
├── UI/           — SwiftUI 界面
├── Utils/        — 工具函数
└── Resources/    — 资源文件
```

## 数据存储

所有数据存储在 `~/Library/Application Support/BackupNotify/`:
- `config.json` — 应用配置
- `snapshots/{monitor_id}.json` — 目录快照
- `history.json` — 通知历史
- `logs/backupnotify_YYYY-MM-DD.log` — 日志文件

## 许可证

MIT License
