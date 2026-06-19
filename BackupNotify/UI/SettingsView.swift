import SwiftUI
import AppKit

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var engine: MonitorEngine

    var body: some View {
        TabView {
            MonitorSettingsTab()
                .tabItem { Label("监控", systemImage: "eye") }
            NotifySettingsTab()
                .tabItem { Label("通知", systemImage: "bell") }
            GeneralSettingsTab()
                .tabItem { Label("通用", systemImage: "gear") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 550, height: 450)
    }
}

// MARK: - MonitorSettingsTab

struct MonitorSettingsTab: View {
    @State private var monitors: [MonitorConfig] = []
    @State private var pollingInterval: TimeInterval = 300
    @State private var scanDepth: Int = 1

    private let pollingOptions: [(String, TimeInterval)] = [
        ("30秒", 30),
        ("1分钟", 60),
        ("5分钟", 300),
        ("15分钟", 900),
        ("30分钟", 1800)
    ]

    var body: some View {
        Form {
            Section(header: Text("监控目录")) {
                if monitors.isEmpty {
                    Text("未添加监控目录")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach($monitors) { $monitor in
                        HStack {
                            Toggle("", isOn: $monitor.enabled)
                                .labelsHidden()
                                .onChange(of: monitor.enabled) { _ in saveConfig() }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(monitor.name)
                                    .font(.body)
                                Text(monitor.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button(action: { deleteMonitor(monitor) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button("添加目录") { addDirectory() }
            }

            Section(header: Text("扫描设置")) {
                Picker("轮询间隔", selection: $pollingInterval) {
                    ForEach(pollingOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                .onChange(of: pollingInterval) { _ in saveConfig() }

                Stepper("扫描深度：\(scanDepth)", value: $scanDepth, in: 1...5)
                    .onChange(of: scanDepth) { _ in saveConfig() }
            }
        }
        .padding()
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        let config = ConfigStore.shared.load()
        monitors = config.monitors
        pollingInterval = config.pollingInterval
        scanDepth = config.scanDepth
    }

    private func saveConfig() {
        var config = ConfigStore.shared.load()
        config.monitors = monitors
        config.pollingInterval = pollingInterval
        config.scanDepth = scanDepth
        ConfigStore.shared.save(config)
    }

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择监控目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let newMonitor = MonitorConfig(
            path: url.path,
            name: url.lastPathComponent,
            depth: scanDepth
        )
        monitors.append(newMonitor)
        saveConfig()
    }

    private func deleteMonitor(_ monitor: MonitorConfig) {
        monitors.removeAll { $0.id == monitor.id }
        saveConfig()
    }
}

// MARK: - NotifySettingsTab

struct NotifySettingsTab: View {
    @State private var webhooks: [WebhookConfig] = []
    @State private var quietHoursEnabled: Bool = false
    @State private var startHour: Int = 22
    @State private var startMinute: Int = 0
    @State private var endHour: Int = 8
    @State private var endMinute: Int = 0
    @State private var enableLocalNotification: Bool = true
    @State private var showAddWebhookSheet: Bool = false

    // Add Webhook sheet state
    @State private var newWebhookName: String = ""
    @State private var newWebhookPlatform: WebhookPlatform = .feishu
    @State private var newWebhookURL: String = ""

    // Webhook test feedback
    @State private var testResults: [UUID: WebhookTestState] = [:]

    enum WebhookTestState: Equatable {
        case idle
        case testing
        case success(statusCode: Int)
        case failure(error: String)
    }

    var body: some View {
        Form {
            Section(header: Text("Webhook列表")) {
                if webhooks.isEmpty {
                    Text("未配置Webhook")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach($webhooks) { $webhook in
                        HStack {
                            Text(webhook.platform.displayName)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(platformColor(webhook.platform).opacity(0.15))
                                .cornerRadius(4)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(webhook.name)
                                    .font(.body)
                                Text(truncatedURL(webhook.url))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Test result indicator
                            if let state = testResults[webhook.id] {
                                testStateIcon(state)
                            }

                            Toggle("", isOn: $webhook.enabled)
                                .labelsHidden()
                                .onChange(of: webhook.enabled) { _ in saveConfig() }

                            Button(action: { testWebhook(webhook) }) {
                                Image(systemName: "paperplane")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("发送测试消息")

                            Button(action: { deleteWebhook(webhook) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button("添加Webhook") {
                    newWebhookName = ""
                    newWebhookURL = ""
                    newWebhookPlatform = .feishu
                    showAddWebhookSheet = true
                }
            }

            Section(header: Text("免打扰时间")) {
                Toggle("启用免打扰", isOn: $quietHoursEnabled)
                    .onChange(of: quietHoursEnabled) { _ in saveQuietHours() }

                if quietHoursEnabled {
                    HStack {
                        Text("开始时间")
                        Spacer()
                        Picker("", selection: $startHour) {
                            ForEach(0..<24, id: \.self) { Text("\($0)时").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        .onChange(of: startHour) { _ in saveQuietHours() }

                        Picker("", selection: $startMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d分", $0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        .onChange(of: startMinute) { _ in saveQuietHours() }
                    }

                    HStack {
                        Text("结束时间")
                        Spacer()
                        Picker("", selection: $endHour) {
                            ForEach(0..<24, id: \.self) { Text("\($0)时").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        .onChange(of: endHour) { _ in saveQuietHours() }

                        Picker("", selection: $endMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d分", $0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        .onChange(of: endMinute) { _ in saveQuietHours() }
                    }
                }
            }

            Section {
                Toggle("macOS本地通知", isOn: $enableLocalNotification)
                    .onChange(of: enableLocalNotification) { _ in
                        var config = ConfigStore.shared.load()
                        config.enableLocalNotification = enableLocalNotification
                        ConfigStore.shared.save(config)
                    }
            }
        }
        .padding()
        .sheet(isPresented: $showAddWebhookSheet) {
            addWebhookSheet
        }
        .onAppear { loadConfig() }
    }

    @ViewBuilder
    private func testStateIcon(_ state: WebhookTestState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .success(let code):
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
                .help("测试成功 (HTTP \(code))")
        case .failure(let error):
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
                .help("测试失败: \(error)")
        }
    }

    private var addWebhookSheet: some View {
        VStack(spacing: 16) {
            Text("添加Webhook")
                .font(.headline)

            Form {
                TextField("名称", text: $newWebhookName)
                Picker("平台", selection: $newWebhookPlatform) {
                    ForEach(WebhookPlatform.allCases, id: \.self) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                TextField("Webhook URL", text: $newWebhookURL)
            }
            .frame(height: 140)

            HStack {
                Button("取消") { showAddWebhookSheet = false }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("添加") {
                    addWebhook()
                    showAddWebhookSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newWebhookName.trimmingCharacters(in: .whitespaces).isEmpty ||
                          newWebhookURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
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
    }

    private func saveQuietHours() {
        var config = ConfigStore.shared.load()
        config.quietHours = QuietHours(
            enabled: quietHoursEnabled,
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute
        )
        ConfigStore.shared.save(config)
    }

    private func addWebhook() {
        let webhook = WebhookConfig(
            url: newWebhookURL.trimmingCharacters(in: .whitespaces),
            name: newWebhookName.trimmingCharacters(in: .whitespaces),
            platform: newWebhookPlatform
        )
        webhooks.append(webhook)
        saveConfig()
    }

    private func deleteWebhook(_ webhook: WebhookConfig) {
        webhooks.removeAll { $0.id == webhook.id }
        saveConfig()
    }

    private func testWebhook(_ webhook: WebhookConfig) {
        Logger.shared.info("发送测试Webhook: \(webhook.name)")
        testResults[webhook.id] = .testing

        let manager = WebhookManager()
        Task {
            let result = await manager.testWebhook(config: webhook)
            if result.success {
                Logger.shared.info("测试Webhook成功: \(webhook.name)")
                testResults[webhook.id] = .success(statusCode: result.statusCode ?? 0)
            } else {
                Logger.shared.error("测试Webhook失败: \(webhook.name) - \(result.error ?? "未知错误")")
                testResults[webhook.id] = .failure(error: result.error ?? "未知错误")
            }

            // Auto-clear result after 10 seconds
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if testResults[webhook.id] != .testing {
                testResults[webhook.id] = .idle
            }
        }
    }

    private func truncatedURL(_ url: String) -> String {
        if url.count > 40 {
            let prefix = url.prefix(37)
            return "\(prefix)..."
        }
        return url
    }

    private func platformColor(_ platform: WebhookPlatform) -> Color {
        switch platform {
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
    @State private var launchAtLogin: Bool = false
    @State private var logRetentionDays: Int = 14
    @State private var videoExtensions: [String] = []
    @State private var newExtension: String = ""
    @State private var showClearConfirmation: Bool = false

    var body: some View {
        Form {
            Section(header: Text("启动设置")) {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _ in
                        var config = ConfigStore.shared.load()
                        config.launchAtLogin = launchAtLogin
                        ConfigStore.shared.save(config)
                    }
            }

            Section(header: Text("日志设置")) {
                Stepper("日志保留天数：\(logRetentionDays)天", value: $logRetentionDays, in: 1...365)
                    .onChange(of: logRetentionDays) { _ in
                        var config = ConfigStore.shared.load()
                        config.logRetentionDays = logRetentionDays
                        ConfigStore.shared.save(config)
                        Logger.shared.updateRetentionDays(logRetentionDays)
                    }
            }

            Section(header: Text("视频文件扩展名")) {
                ForEach(videoExtensions, id: \.self) { ext in
                    HStack {
                        Text(".\(ext)")
                        Spacer()
                        Button(action: { removeExtension(ext) }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("新扩展名（不含点号）", text: $newExtension)
                        .textFieldStyle(.roundedBorder)

                    Button(action: { addExtension() }) {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(newExtension.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section(header: Text("文件夹")) {
                HStack {
                    Button("打开日志文件夹") {
                        NSWorkspace.shared.open(Logger.shared.logsDirectory)
                    }

                    Spacer()

                    Button("打开配置文件夹") {
                        NSWorkspace.shared.open(StorageUtils.appSupportURL)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("清除历史记录") { showClearConfirmation = true }
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
        .padding()
        .alert("确认清除", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                HistoryStore.shared.clearAll()
            }
        } message: {
            Text("确定要清除所有历史记录吗？此操作无法撤销。")
        }
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        let config = ConfigStore.shared.load()
        launchAtLogin = config.launchAtLogin
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

// MARK: - AboutTab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("BackupNotify")
                .font(.title)
                .fontWeight(.bold)

            Text("v1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("macOS 备份监控通知工具\n监控目录变化，推送 Webhook 通知")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Text("MIT License")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
