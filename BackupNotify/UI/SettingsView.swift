import SwiftUI
import AppKit

// MARK: - SettingsView (Root)

struct SettingsView: View {
    @ObservedObject var engine: MonitorEngine
    @State private var selectedTab: SettingsTab = .monitor

    enum SettingsTab: String, CaseIterable {
        case monitor = "监控"
        case notify = "通知"
        case general = "通用"
        case history = "历史"
        case log = "日志"
        case about = "关于"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        VStack(spacing: 4) {
                            Image(systemName: iconFor(tab))
                                .font(.system(size: 16))
                            Text(tab.rawValue)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .monitor:
                    MonitorSettingsTab(engine: engine)
                case .notify:
                    NotifySettingsTab(engine: engine)
                case .general:
                    GeneralSettingsTab(engine: engine)
                case .history:
                    HistoryView()
                case .log:
                    LogViewer()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: selectedTab == .history ? 900 : 560, height: selectedTab == .history ? 600 : 480)
    }

    private func iconFor(_ tab: SettingsTab) -> String {
        switch tab {
        case .monitor: return "eye.fill"
        case .notify:  return "bell.fill"
        case .general: return "gearshape.fill"
        case .history: return "clock.arrow.circlepath"
        case .log:     return "doc.text.fill"
        case .about:   return "info.circle.fill"
        }
    }
}

// MARK: - MonitorSettingsTab

struct MonitorSettingsTab: View {
    @ObservedObject var engine: MonitorEngine
    @State private var monitors: [MonitorConfig] = []
    @State private var pollingInterval: TimeInterval = 300
    @State private var showPermissionAlert = false
    @State private var permissionAlertPath = ""
    @State private var hasFullDiskAccess = false

    private let pollingOptions: [(String, TimeInterval)] = [
        ("30 秒", 30),
        ("1 分钟", 60),
        ("5 分钟", 300),
        ("15 分钟", 900),
        ("30 分钟", 1800)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Permission warning
                if needsPermissionBanner {
                    permissionBanner
                }

                // Polling interval
                sectionCard("扫描间隔") {
                    HStack(spacing: 8) {
                        ForEach(pollingOptions, id: \.1) { option in
                            Button {
                                pollingInterval = option.1
                                saveConfig()
                            } label: {
                                Text(option.0)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(pollingInterval == option.1 ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(pollingInterval == option.1 ? .white : .primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Monitor list
                sectionCard("监控目录") {
                    if monitors.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title2)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("尚未添加监控目录")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 6) {
                            ForEach($monitors) { $monitor in
                                MonitorRow(
                                    monitor: $monitor,
                                    onDelete: { deleteMonitor(monitor) },
                                    onChange: { saveConfig() }
                                )
                            }
                        }
                    }

                    Button { addDirectory() } label: {
                        Label("添加目录", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .alert("需要磁盘访问权限", isPresented: $showPermissionAlert) {
            Button("打开系统设置") {
                PermissionChecker.openFullDiskAccessSettings()
            }
            Button("仍然添加", role: .destructive) {
                let newMonitor = MonitorConfig(path: permissionAlertPath, name: (permissionAlertPath as NSString).lastPathComponent)
                monitors.append(newMonitor)
                saveConfig()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("BackupNotify 需要「完全磁盘访问」权限才能读取：\n\n\(permissionAlertPath)\n\n请在系统设置中授权后重试。")
        }
        .onAppear {
            loadConfig()
            refreshPermissionStatus()
        }
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }

    private func loadConfig() {
        let config = ConfigStore.shared.load()
        monitors = config.monitors
        pollingInterval = config.pollingInterval
    }

    private func saveConfig() {
        var config = ConfigStore.shared.load()
        config.monitors = monitors
        config.pollingInterval = pollingInterval
        ConfigStore.shared.save(config)
        engine.reloadConfig(config)
    }

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择监控目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path

        // Check if path requires Full Disk Access
        if PermissionChecker.requiresFullDiskAccess(path) {
            let status = PermissionChecker.checkAccess(path)
            if status == .noPermission {
                permissionAlertPath = path
                showPermissionAlert = true
                return
            }
        }

        let newMonitor = MonitorConfig(path: path, name: url.lastPathComponent)
        monitors.append(newMonitor)
        saveConfig()
    }

    private func deleteMonitor(_ monitor: MonitorConfig) {
        monitors.removeAll { $0.id == monitor.id }
        saveConfig()
    }

    // MARK: - Permission Helpers

    private var needsPermissionBanner: Bool {
        // Show banner if any monitor is on /Volumes/ and FDA is missing
        if !hasFullDiskAccess { return true }
        // Or if any monitor path is not accessible
        for monitor in monitors {
            let status = PermissionChecker.checkAccess(monitor.path)
            if status == .noPermission { return true }
        }
        return false
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("磁盘访问权限不足")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("监控外置硬盘或 NAS 需要「完全磁盘访问」权限")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                PermissionChecker.openFullDiskAccessSettings()
            } label: {
                Text("去授权")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }

    private func refreshPermissionStatus() {
        hasFullDiskAccess = PermissionChecker.hasFullDiskAccess()
    }
}

// MARK: - MonitorRow (editable name)

struct MonitorRow: View {
    @Binding var monitor: MonitorConfig
    var onDelete: () -> Void
    var onChange: () -> Void

    @State private var isEditingName = false
    @State private var editName: String = ""
    @State private var accessStatus: PermissionChecker.AccessStatus = .accessible
    @State private var showExcludePatterns = false
    @State private var newPattern: String = ""

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: $monitor.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: monitor.enabled) { _ in onChange() }

                VStack(alignment: .leading, spacing: 2) {
                    if isEditingName {
                        HStack(spacing: 4) {
                            TextField("备注名", text: $editName, onCommit: {
                                let trimmed = editName.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty { monitor.name = trimmed }
                                isEditingName = false
                                onChange()
                            })
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .frame(maxWidth: 160)

                            Button {
                                let trimmed = editName.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty { monitor.name = trimmed }
                                isEditingName = false
                                onChange()
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)

                            Button {
                                isEditingName = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(monitor.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Button {
                                editName = monitor.name
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help("编辑备注名")
                        }
                    }

                    HStack(spacing: 4) {
                        Text(monitor.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if accessStatus != .accessible {
                            Image(systemName: accessStatus == .noPermission ? "lock.fill" : "questionmark.circle")
                                .font(.system(size: 9))
                                .foregroundColor(accessStatus == .noPermission ? .orange : .secondary)
                                .help(PermissionChecker.description(for: accessStatus))
                        }
                    }
                }

                Spacer()

                // Exclude patterns toggle
                Button { showExcludePatterns.toggle() } label: {
                    Image(systemName: showExcludePatterns ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("排除规则")

                Button {
                    PermissionChecker.openFullDiskAccessSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("打开系统设置")

                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // Exclude patterns section
            if showExcludePatterns {
                excludePatternsSection
            }
        }
        .padding(8)
        .background(accessStatus == .noPermission ? Color.orange.opacity(0.06) : Color.secondary.opacity(0.06))
        .cornerRadius(6)
        .onAppear { checkAccess() }
    }

    private var excludePatternsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            HStack {
                Text("排除规则")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Text("支持 * 和 ? 通配符")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            if monitor.excludePatterns.isEmpty {
                Text("暂无排除规则")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            } else {
                FlowLayout(spacing: 4) {
                    ForEach(monitor.excludePatterns, id: \.self) { pattern in
                        HStack(spacing: 3) {
                            Text(pattern)
                                .font(.caption)
                            Button { removePattern(pattern) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }

            HStack {
                TextField("添加规则 (如: *.DS_Store, temp_*)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button { addPattern() } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 4)
    }

    private func addPattern() {
        let pattern = newPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !monitor.excludePatterns.contains(pattern) else { return }
        monitor.excludePatterns.append(pattern)
        newPattern = ""
        onChange()
    }

    private func removePattern(_ pattern: String) {
        monitor.excludePatterns.removeAll { $0 == pattern }
        onChange()
    }

    private func checkAccess() {
        accessStatus = PermissionChecker.checkAccess(monitor.path)
    }
}

// MARK: - NotifySettingsTab

struct NotifySettingsTab: View {
    @ObservedObject var engine: MonitorEngine
    @State private var webhooks: [WebhookConfig] = []
    @State private var quietHoursEnabled: Bool = false
    @State private var startHour: Int = 22
    @State private var startMinute: Int = 0
    @State private var endHour: Int = 8
    @State private var endMinute: Int = 0
    @State private var enableLocalNotification: Bool = true
    @State private var showAddSheet: Bool = false
    @State private var newWebhookName: String = ""
    @State private var newWebhookPlatform: WebhookPlatform = .feishu
    @State private var newWebhookURL: String = ""
    @State private var newWebhookTemplate: WebhookTemplatePreset = .standard
    @State private var newWebhookCustomTemplate: String = ""
    @State private var webhookURLError: String = ""
    @State private var testResults: [UUID: TestState] = [:]
    @State private var pingResults: [UUID: TestState] = [:]

    enum TestState: Equatable {
        case idle, testing
        case ok(Int)
        case fail(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Webhooks
                sectionCard("Webhook 推送") {
                    if webhooks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bell.slash")
                                .font(.title2)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("尚未配置 Webhook")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 6) {
                            ForEach($webhooks) { $webhook in
                                webhookRow($webhook)
                            }
                        }
                    }

                    Button { showAddSheet = true } label: {
                        Label("添加 Webhook", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .padding(.top, 4)
                }

                // Quiet hours
                sectionCard("免打扰") {
                    Toggle("启用免打扰时段", isOn: $quietHoursEnabled)
                        .font(.subheadline)
                        .onChange(of: quietHoursEnabled) { _ in saveQuietHours() }

                    if quietHoursEnabled {
                        HStack(spacing: 16) {
                            timePicker("开始", hour: $startHour, minute: $startMinute)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            timePicker("结束", hour: $endHour, minute: $endMinute)
                        }
                    }
                }

                // Local notification
                sectionCard("本地通知") {
                    Toggle("macOS 系统通知", isOn: $enableLocalNotification)
                        .font(.subheadline)
                        .onChange(of: enableLocalNotification) { _ in
                            var config = ConfigStore.shared.load()
                            config.enableLocalNotification = enableLocalNotification
                            ConfigStore.shared.save(config)
                        }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showAddSheet) { addWebhookSheet }
        .onAppear { loadConfig() }
    }

    // MARK: - Webhook Row

    private func webhookRow(_ binding: Binding<WebhookConfig>) -> some View {
        let webhook = binding.wrappedValue
        return HStack(spacing: 10) {
            Text(webhook.platform.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(platformColor(webhook.platform).opacity(0.15))
                .foregroundColor(platformColor(webhook.platform))
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(webhook.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(truncatedURL(webhook.url))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Ping result
            if let state = pingResults[webhook.id], state != .idle {
                miniStatus(state, label: "连通")
            }

            // Send result
            if let state = testResults[webhook.id], state != .idle {
                miniStatus(state, label: "推送")
            }

            Toggle("", isOn: binding.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: webhook.enabled) { _ in saveConfig() }

            // Connection test button
            Button { pingWebhook(webhook) } label: {
                Image(systemName: "network")
                    .font(.caption)
                    .foregroundColor(.cyan)
            }
            .buttonStyle(.plain)
            .help("连通性测试")

            // Send test button
            Button { testWebhook(webhook) } label: {
                Image(systemName: "paperplane.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("发送测试消息")

            Button { deleteWebhook(webhook) } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func miniStatus(_ state: TestState, label: String) -> some View {
        switch state {
        case .testing:
            ProgressView().controlSize(.mini).frame(width: 12, height: 12)
        case .ok(let code):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
                .help("\(label)成功 (HTTP \(code))")
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.red)
                .help("\(label)失败")
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Add Webhook Sheet

    private var addWebhookSheet: some View {
        VStack(spacing: 16) {
            Text("添加 Webhook")
                .font(.headline)

            Form {
                TextField("名称", text: $newWebhookName)
                Picker("平台", selection: $newWebhookPlatform) {
                    ForEach(WebhookPlatform.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                TextField("URL", text: $newWebhookURL)
                if !webhookURLError.isEmpty {
                    Text(webhookURLError)
                        .font(.caption2)
                        .foregroundColor(.red)
                }

                Picker("内容模板", selection: $newWebhookTemplate) {
                    ForEach(WebhookTemplatePreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: newWebhookTemplate) { preset in
                    if preset != .custom {
                        newWebhookCustomTemplate = preset.template
                    }
                }
            }
            .frame(height: 160)

            // Template preview
            if newWebhookTemplate != .standard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("模板预览")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("实际内容将替换变量")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.6))
                    }

                    ScrollView {
                        Text(templatePreviewText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.black.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.15))
                    )
                }
            }

            // Custom template editor
            if newWebhookTemplate == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义模板")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    TextEditor(text: $newWebhookCustomTemplate)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    Text("变量: {name} {path} {monitor_name} {backup_time} {notify_time} {total_size} {file_count} {file_tree} {report}")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                }
            }

            HStack {
                Button("取消") { showAddSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("添加") {
                    addWebhook()
                    if webhookURLError.isEmpty {
                        showAddSheet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newWebhookName.trimmingCharacters(in: .whitespaces).isEmpty ||
                          newWebhookURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// Render template preview with sample data substituted.
    private var templatePreviewText: String {
        let template: String
        if newWebhookTemplate == .custom {
            template = newWebhookCustomTemplate.isEmpty ? "（请在下方输入模板内容）" : newWebhookCustomTemplate
        } else {
            template = newWebhookTemplate.template
        }

        let sample: [String: String] = [
            "{name}":            "A001",
            "{path}":            "/Volumes/SD_CARD/DCIM/100MEDIA/A001",
            "{monitor_name}":    "A机 SD卡",
            "{created_at}":      "2026-06-20T10:30:00Z",
            "{modified_at}":     "2026-06-20T10:45:00Z",
            "{notified_at}":     "2026-06-20T10:30:05Z",
            "{backup_time}":     "2026/6/20 10:30:00",
            "{notify_time}":     "2026/6/20 10:30:05",
            "{total_size}":      "12.4 GB",
            "{total_size_bytes}": "13314398617",
            "{file_count}":      "58",
            "{video_count}":     "12",
            "{video_size}":      "10.2 GB",
            "{file_tree}":       "文件树：\n├── CLIPS    8.1 GB · 40 个文件\n└── RAW    4.3 GB · 18 个文件",
            "{levels}":          "• CLIPS — 8.1 GB\n• RAW — 4.3 GB",
            "{levels_json}":     "[{\"relativePath\":\"CLIPS\",\"sizeBytes\":8692000000}]",
            "{report}":          sampleReport,
        ]

        var result = template
        for (key, value) in sample {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    private var sampleReport: String {
        """
        ══════════════════════════════════════
          备份报告
        ══════════════════════════════════════

          备份文件夹    A001
          监控源    A机 SD卡
          目标路径    /Volumes/SD_CARD/DCIM/100MEDIA/A001
          备份时间    2026/6/20 10:30:00
          通知时间    2026/6/20 10:30:05
          总大小    12.4 GB
          文件数    58 个
          视频文件    12 个（10.2 GB）

        ──────────────────────────────────────
          文件树
        ──────────────────────────────────────
        ├── CLIPS    8.1 GB · 40 个文件
        └── RAW    4.3 GB · 18 个文件

        ──────────────────────────────────────
          BackupNotify • 2026/6/20 10:30:05
        ══════════════════════════════════════
        """
    }

    // MARK: - Webhook Template Presets

    enum WebhookTemplatePreset: String, CaseIterable {
        case standard = "标准（JSON）"
        case report = "报告（纯文本）"
        case custom = "自定义"

        var displayName: String { rawValue }

        var template: String {
            switch self {
            case .standard:
                return ""
            case .report:
                return "{report}"
            case .custom:
                return ""
            }
        }

        var showPreview: Bool { true }
    }

    // MARK: - Helpers

    private func timePicker(_ label: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: hour) {
                ForEach(0..<24, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .frame(width: 50)
            Text(":")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: minute) {
                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 50)
        }
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }

    private func loadConfig() {
        let config = ConfigStore.shared.load()
        webhooks = config.webhooks
        enableLocalNotification = config.enableLocalNotification
        if let qh = config.quietHours {
            quietHoursEnabled = qh.enabled
            startHour = qh.startHour
            startMinute = qh.startMinute
            endHour = qh.endHour
            endMinute = qh.endMinute
        }
    }

    private func saveConfig() {
        var config = ConfigStore.shared.load()
        config.webhooks = webhooks
        ConfigStore.shared.save(config)
        engine.reloadConfig(config)
    }

    private func saveQuietHours() {
        var config = ConfigStore.shared.load()
        config.quietHours = QuietHours(
            enabled: quietHoursEnabled,
            startHour: startHour, startMinute: startMinute,
            endHour: endHour, endMinute: endMinute
        )
        ConfigStore.shared.save(config)
        engine.reloadConfig(config)
    }

    private func addWebhook() {
        let urlStr = newWebhookURL.trimmingCharacters(in: .whitespaces)

        // Validate URL
        guard let url = URL(string: urlStr),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme) else {
            webhookURLError = "URL 必须以 http:// 或 https:// 开头"
            return
        }
        webhookURLError = ""

        let isCustom = newWebhookTemplate == .custom
        let customTmpl = isCustom ? newWebhookCustomTemplate.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let webhook = WebhookConfig(
            url: urlStr,
            name: newWebhookName.trimmingCharacters(in: .whitespaces),
            platform: newWebhookPlatform,
            customTemplate: (newWebhookTemplate != .standard && newWebhookTemplate != .custom)
                ? newWebhookTemplate.template
                : customTmpl
        )
        webhooks.append(webhook)
        saveConfig()
        newWebhookName = ""
        newWebhookURL = ""
        newWebhookTemplate = .standard
        newWebhookCustomTemplate = ""
    }

    private func deleteWebhook(_ webhook: WebhookConfig) {
        webhooks.removeAll { $0.id == webhook.id }
        saveConfig()
    }

    private func testWebhook(_ webhook: WebhookConfig) {
        testResults[webhook.id] = .testing
        let mgr = WebhookManager()
        Task {
            let result = await mgr.testWebhook(config: webhook)
            testResults[webhook.id] = result.success
                ? .ok(result.statusCode ?? 0)
                : .fail(result.error ?? "未知错误")
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if testResults[webhook.id] != .testing {
                testResults[webhook.id] = .idle
            }
        }
    }

    private func pingWebhook(_ webhook: WebhookConfig) {
        pingResults[webhook.id] = .testing
        let mgr = WebhookManager()
        Task {
            let result = await mgr.pingWebhook(url: webhook.url)
            pingResults[webhook.id] = result.reachable
                ? .ok(result.statusCode ?? 0)
                : .fail(result.error ?? "不可达")
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if pingResults[webhook.id] != .testing {
                pingResults[webhook.id] = .idle
            }
        }
    }

    private func truncatedURL(_ url: String) -> String {
        url.count > 40 ? "\(url.prefix(37))..." : url
    }

    private func platformColor(_ p: WebhookPlatform) -> Color {
        switch p {
        case .feishu:   return .blue
        case .dingtalk: return .cyan
        case .wecom:    return .green
        case .slack:    return .purple
        case .discord:  return .indigo
        case .custom:   return .gray
        }
    }
}

// MARK: - GeneralSettingsTab

struct GeneralSettingsTab: View {
    @ObservedObject var engine: MonitorEngine
    @State private var launchAtLogin: Bool = false
    @State private var logRetentionDays: Int = 14
    @State private var videoExtensions: [String] = []
    @State private var newExtension: String = ""
    @State private var showClearConfirmation: Bool = false
    @State private var clearResult: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Launch
                sectionCard("启动") {
                    Toggle("登录时自动启动", isOn: $launchAtLogin)
                        .font(.subheadline)
                        .onChange(of: launchAtLogin) { newValue in
                            var config = ConfigStore.shared.load()
                            config.launchAtLogin = newValue
                            ConfigStore.shared.save(config)
                            LoginItemManager.setEnabled(newValue)
                        }
                }

                // Log retention
                sectionCard("日志") {
                    HStack {
                        Text("保留天数")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $logRetentionDays) {
                            Text("永久").tag(0)
                            ForEach([7, 14, 30, 90, 365], id: \.self) { d in
                                Text("\(d) 天").tag(d)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        .onChange(of: logRetentionDays) { _ in
                            var config = ConfigStore.shared.load()
                            config.logRetentionDays = logRetentionDays
                            ConfigStore.shared.save(config)
                            Logger.shared.updateRetentionDays(logRetentionDays)
                        }
                    }

                    Button { NSWorkspace.shared.open(Logger.shared.logsDirectory) } label: {
                        Label("打开日志文件夹", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                // Video extensions
                sectionCard("视频文件扩展名") {
                    FlowLayout(spacing: 6) {
                        ForEach(videoExtensions, id: \.self) { ext in
                            HStack(spacing: 4) {
                                Text(".\(ext)")
                                    .font(.caption)
                                Button { removeExtension(ext) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }

                    HStack {
                        TextField("新扩展名", text: $newExtension)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        Button { addExtension() } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newExtension.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // Danger zone
                sectionCard("数据") {
                    HStack {
                        Button { NSWorkspace.shared.open(StorageUtils.appSupportURL) } label: {
                            Label("配置文件夹", systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)

                        Spacer()

                        Button { showClearConfirmation = true } label: {
                            Label("清除历史记录", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)

                        if let msg = clearResult {
                            Text(msg)
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .padding(16)
        }
        .alert("确认清除", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                HistoryStore.shared.clearAll()
                clearResult = "已清除"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { clearResult = nil }
            }
        } message: {
            Text("确定要清除所有历史记录吗？此操作无法撤销。")
        }
        .onAppear { loadConfig() }
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }

    private func loadConfig() {
        let config = ConfigStore.shared.load()
        launchAtLogin = LoginItemManager.isEnabled
        logRetentionDays = config.logRetentionDays
        videoExtensions = config.videoExtensions
    }

    private func addExtension() {
        let ext = newExtension.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        guard !ext.isEmpty, !videoExtensions.contains(ext) else { return }
        videoExtensions.append(ext)
        saveVideoExtensions()
        newExtension = ""
    }

    private func removeExtension(_ ext: String) {
        videoExtensions.removeAll { $0 == ext }
        saveVideoExtensions()
    }

    private func saveVideoExtensions() {
        var config = ConfigStore.shared.load()
        config.videoExtensions = videoExtensions
        ConfigStore.shared.save(config)
    }
}

// MARK: - FlowLayout (tag cloud)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (offsets, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: - AboutTab

struct AboutTab: View {
    @State private var appVersion: String = ""
    @State private var updateStatus: UpdateStatus = .idle
    @State private var latestVersion: String = ""
    @State private var releaseURL: String = ""

    enum UpdateStatus {
        case idle, checking, available, latest, error(String)
    }

    private let githubRepo = "sexyfeifan/BackupNotify"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 8)

                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("BackupNotify")
                    .font(.title)
                    .fontWeight(.bold)

                Text("v\(appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("macOS 备份监控通知工具\n监控目录变化，推送 Webhook 通知")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Divider()

                // Update checker
                VStack(spacing: 12) {
                    HStack {
                        Text("版本检测")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                    }

                    switch updateStatus {
                    case .idle:
                        Button { checkForUpdates() } label: {
                            Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)

                    case .checking:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在检查...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                    case .available:
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.green)
                                Text("发现新版本 v\(latestVersion)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            Button { openRelease() } label: {
                                Label("前往下载", systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }

                    case .latest:
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已是最新版本")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                    case .error(let msg):
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("检查失败")
                                    .font(.subheadline)
                            }
                            Text(msg)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Button { checkForUpdates() } label: {
                                Text("重试")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)

                // Info
                VStack(spacing: 6) {
                    infoRow("引擎", "SwiftUI + Combine")
                    infoRow("平台", "macOS 13+")
                    infoRow("校验", "SHA-256")
                    infoRow("作者", "@sexyfeifan")
                    infoRow("联系", "zhoufeifan@gmail.com")
                    infoRow("许可证", "MIT License")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(10)

                Spacer()
            }
            .padding(20)
        }
        .onAppear {
            appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func checkForUpdates() {
        updateStatus = .checking
        Task {
            let urlStr = "https://api.github.com/repos/\(githubRepo)/releases/latest"
            guard let url = URL(string: urlStr) else {
                updateStatus = .error("无效 URL")
                return
            }
            do {
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    updateStatus = .error("网络错误")
                    return
                }
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                    updateStatus = .error("请求过于频繁，请稍后再试")
                    return
                }
                guard httpResponse.statusCode == 200 else {
                    updateStatus = .error("HTTP \(httpResponse.statusCode)")
                    return
                }
                let release = try JSONDecoder().decode(GHRelease.self, from: data)
                let remote = release.tagName.replacingOccurrences(of: "v", with: "")
                let local = appVersion
                if compareVersions(remote, local) > 0 {
                    latestVersion = remote
                    releaseURL = release.htmlURL
                    updateStatus = .available
                } else {
                    updateStatus = .latest
                }
            } catch {
                updateStatus = .error(error.localizedDescription)
            }
        }
    }

    private func openRelease() {
        if let url = URL(string: releaseURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let na = i < pa.count ? pa[i] : 0
            let nb = i < pb.count ? pb[i] : 0
            if na > nb { return 1 }
            if na < nb { return -1 }
        }
        return 0
    }
}

// MARK: - GitHub Release DTO

private struct GHRelease: Codable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
