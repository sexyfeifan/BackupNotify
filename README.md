# BackupNotify

macOS 菜单栏应用 — 监控备份目录变化，自动推送专业格式的 Webhook 通知。

专为影视制作、摄影团队设计：监控存储卡/NAS/外置硬盘中的新备份文件夹，即时通知团队成员。

## 功能概览

### 核心监控

- **多目录监控** — 同时监控多个存储路径（外置硬盘、NAS、本地目录）
- **智能检测** — 基于快照对比，精确识别新增文件夹，不重复推送
- **视频识别** — 自动识别视频文件（MOV/MXF/R3D/BRAW/CRM 等 15+ 格式）
- **排除规则** — 支持 glob 通配符（`*.tmp`、`temp_*`）排除不需要的目录
- **灵活轮询** — 30 秒 / 1 分钟 / 5 分钟 / 15 分钟 / 30 分钟可选

### 通知推送

- **多平台支持** — 飞书 / 钉钉 / 企业微信 / Slack / Discord / 自定义 Webhook
- **专业报告格式** — 完整文件树、文件大小、文件数量、视频统计
- **模板系统** — 标准 JSON / 专业报告 / 自定义模板（支持 15+ 变量）
- **模板预览** — 添加 Webhook 时实时预览推送内容
- **双测试按钮** — 连通性测试（HEAD 请求）+ 推送测试（发送真实消息）
- **失败重试** — 自动重试 3 次（5s / 15s / 30s 间隔）
- **免打扰时段** — 支持跨日范围（如 22:00 - 08:00）

### 通知内容示例

```
══════════════════════════════════════════════════
              📋 备份报告
                 A001
══════════════════════════════════════════════════

  备份文件夹  A001
  监控源      A机 SD卡
  目标路径    /Volumes/SD_CARD/DCIM/100MEDIA/A001
  备份时间    2026-06-20 10:30:00
  通知时间    2026-06-20 10:30:05
  检测耗时    5.2s
  总大小      12.4 GB
  文件总数    58 个
  视频文件    12 个（10.2 GB）

──────────────────────────────────────────────────
  📁 文件结构
──────────────────────────────────────────────────
📁 A001/ (58 个文件)  12.4 GB
├── 📁 CLIPS/ (40 个文件)  8.1 GB
│   ├── 🎬 B001C001_260203YY.MOV  2.1 GB
│   └── 🎬 B001C002_260203YY.MOV  2.0 GB
└── 📁 RAW/ (18 个文件)  4.3 GB
    ├── 🖼  IMG_0001.CR3  25 MB
    └── 🖼  IMG_0002.CR3  24 MB

──────────────────────────────────────────────────
  BackupNotify · 2026-06-20 10:30:05
══════════════════════════════════════════════════
```

### 系统集成

- **macOS 系统通知** — Notification Center 推送
- **登录自启动** — 通过 SMAppService 管理（macOS 13+）
- **完全磁盘访问检测** — 自动检测 /Volumes/ 路径权限并引导授权
- **菜单栏常驻** — 无 Dock 图标，纯菜单栏应用

### 数据管理

- **历史记录** — 搜索、查看详情、重新发送、删除
- **CSV 导出** — 一键导出全部历史记录
- **日志查看器** — 实时刷新，按级别过滤（INFO/DEBUG/WARN/ERROR）
- **日志轮转** — 可配置保留天数（7/14/30/90/365/永久）

### 版本更新

- **GitHub 更新检测** — 关于页面一键检查新版本
- **版本对比** — 语义化版本号比较，显示下载链接

## 系统要求

- macOS 13.0 Ventura+
- Xcode 15.0+
- Swift 5.9+

## 安装

从 [Releases](https://github.com/sexyfeifan/BackupNotify/releases) 页面下载最新 DMG，拖入 Applications 即可。

## 构建

```bash
# 使用 xcodegen 生成项目（推荐）
brew install xcodegen
xcodegen generate
open BackupNotify.xcodeproj

# 或直接构建
xcodebuild -project BackupNotify.xcodeproj -scheme BackupNotify -configuration Release build

# 打包 DMG
xcodebuild -project BackupNotify.xcodeproj -scheme BackupNotify -configuration Release
# .app 位于 DerivedData/Build/Products/Release/
```

## 架构

```
BackupNotify/
├── App/                    — 应用入口与生命周期
│   └── BackupNotifyApp.swift
├── Engine/                 — 目录扫描引擎
│   ├── DirectoryScanner.swift    — 目录遍历 + 排除规则
│   ├── FolderAnalyzer.swift      — 文件分析 + 完整文件树构建
│   ├── LevelSizeCalculator.swift — 视频目录层级计算
│   ├── MonitorEngine.swift       — 核心调度引擎
│   └── VideoDetector.swift       — 视频文件识别
├── Notify/                 — 通知系统
│   ├── LocalNotifier.swift       — macOS 系统通知
│   ├── ReportBuilder.swift       — 专业报告生成器
│   ├── TemplateEngine.swift      — 模板渲染引擎
│   ├── WebhookManager.swift      — Webhook 发送 + 重试
│   └── Templates/                — 各平台模板
│       ├── FeishuTemplate.swift
│       ├── DingTalkTemplate.swift
│       ├── WeComTemplate.swift
│       ├── SlackTemplate.swift
│       ├── DiscordTemplate.swift
│       └── TestTemplate.swift
├── Storage/                — 数据模型与持久化
│   ├── ConfigStore.swift         — 配置读写
│   ├── HistoryStore.swift        — 历史记录
│   ├── Logger.swift              — 日志系统
│   ├── Models.swift              — 数据模型
│   └── SnapshotStore.swift       — 目录快照
├── UI/                     — SwiftUI 界面
│   ├── MenuBarView.swift         — 菜单栏面板
│   ├── SettingsView.swift        — 设置页（6 个 Tab）
│   ├── HistoryView.swift         — 历史记录
│   ├── LogViewer.swift           — 日志查看器
│   └── ErrorBoundary.swift       — 错误边界
├── Utils/                  — 工具类
│   ├── ByteFormatter.swift       — 字节格式化
│   ├── DateUtils.swift           — 日期工具
│   ├── LoginItemManager.swift    — 登录自启动
│   ├── PermissionChecker.swift   — 权限检测
│   └── StorageUtils.swift        — 存储路径
└── Resources/              — 资源文件
    ├── Info.plist
    └── Assets.xcassets/
```

## 数据存储

所有数据存储在 `~/Library/Application Support/BackupNotify/`：

```
BackupNotify/
├── config.json                     — 应用配置
├── snapshots/{monitor_id}.json     — 目录快照（已知文件夹）
├── history.json                    — 通知历史记录
└── logs/
    └── backupnotify_YYYY-MM-DD.log — 运行日志
```

## 自定义模板变量

在 Webhook 设置中选择「自定义」模板，支持以下变量：

| 变量 | 说明 |
|------|------|
| `{name}` | 备份文件夹名 |
| `{path}` | 完整路径 |
| `{monitor_name}` | 监控源备注名 |
| `{backup_time}` | 备份时间 |
| `{notify_time}` | 通知时间 |
| `{total_size}` | 总大小 |
| `{file_count}` | 文件数 |
| `{video_count}` | 视频数 |
| `{file_tree}` | 完整文件树 |
| `{report}` | 完整报告文本 |

## 许可证

MIT License
