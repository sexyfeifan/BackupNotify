import SwiftUI
import AppKit

// MARK: - HistoryView

/// 备份历史记录视图
struct HistoryView: View {
    @StateObject private var store = HistoryStoreObservable()

    @State private var searchText: String = ""
    @State private var selectedEventID: BackupEvent.ID?
    @State private var showDeleteConfirm: Bool = false
    @State private var showResendProgress: Bool = false
    @State private var resendMessage: String = ""
    @State private var resendInProgress: Bool = false

    var body: some View {
        HSplitView {
            // 左侧：事件列表
            VStack(spacing: 0) {
                searchBar

                if filteredEvents.isEmpty {
                    EmptyStateView(
                        systemImage: "clock.arrow.circlepath",
                        title: "暂无历史记录",
                        message: "备份事件发生后将自动记录在此处"
                    )
                } else {
                    eventList
                }
            }
            .frame(minWidth: 400)

            // 右侧：详情面板
            detailPanel
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showResendProgress) {
            resendSheet
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let id = selectedEventID {
                    store.deleteEvent(id: id)
                    selectedEventID = nil
                }
            }
        } message: {
            Text("确定要删除此条历史记录吗？此操作不可撤销。")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索文件夹名或路径…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Event List

    private var eventList: some View {
        List(filteredEvents, selection: $selectedEventID) { event in
            eventRow(event)
                .tag(event.id)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func eventRow(_ event: BackupEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：文件夹名 + 时间
            HStack {
                Text(event.folderName)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                RelativeTimeLabel(date: event.notifiedAt)
            }

            // 第二行：路径
            Text(event.folderPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            // 第三行：大小 + 视频信息 + webhook 状态
            HStack(spacing: 12) {
                Label(ByteFormatter.formatBytes(event.totalSizeBytes), systemImage: "doc")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("\(event.videoCount) 个视频 (\(ByteFormatter.formatBytes(event.videoSizeBytes)))",
                      systemImage: "video")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Webhook 状态
                HStack(spacing: 4) {
                    ForEach(event.webhookResults, id: \.webhookId) { result in
                        WebhookStatusIcon(name: result.webhookName, success: result.success)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let event = selectedEvent {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 标题
                    Text(event.folderName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Divider()

                    // 基本信息
                    Group {
                        detailRow(label: "监控名称", value: event.monitorName)
                        detailRow(label: "文件夹路径", value: event.folderPath)
                        detailRow(label: "发现时间", value: DateUtils.formatDate(event.createdAt))
                        detailRow(label: "修改时间", value: DateUtils.formatDate(event.modifiedAt))
                        detailRow(label: "通知时间", value: DateUtils.formatDate(event.notifiedAt))
                    }

                    Divider()

                    // 文件统计
                    Group {
                        Text("文件统计")
                            .font(.headline)
                        detailRow(label: "总大小", value: ByteFormatter.formatBytes(event.totalSizeBytes))
                        detailRow(label: "文件数量", value: "\(event.fileCount)")
                        detailRow(label: "视频数量", value: "\(event.videoCount)")
                        detailRow(label: "视频大小", value: ByteFormatter.formatBytes(event.videoSizeBytes))
                        if !event.videoExtensions.isEmpty {
                            detailRow(label: "视频格式", value: event.videoExtensions.joined(separator: ", "))
                        }
                    }

                    Divider()

                    // 层级详情
                    if !event.levels.isEmpty {
                        Text("目录层级详情")
                            .font(.headline)

                        ForEach(event.levels.indices, id: \.self) { index in
                            let level = event.levels[index]
                            HStack {
                                Text(level.relativePath)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(ByteFormatter.formatBytes(level.sizeBytes))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }

                        Divider()
                    }

                    // Webhook 结果
                    if !event.webhookResults.isEmpty {
                        Text("通知状态")
                            .font(.headline)

                        ForEach(event.webhookResults, id: \.webhookId) { result in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.success ? .green : .red)
                                    Text(result.webhookName)
                                        .font(.subheadline)
                                    Spacer()
                                    if let code = result.statusCode {
                                        Text("HTTP \(code)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if let error = result.error {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                        .lineLimit(2)
                                }
                                Text("发送时间：\(DateUtils.formatDate(result.sentAt))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 320)
        } else {
            EmptyStateView(
                systemImage: "sidebar.right",
                title: "选择记录查看详情",
                message: "从左侧列表中选择一条备份历史记录"
            )
            .frame(minWidth: 320)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                resendSelectedEvent()
            } label: {
                Label("重新发送", systemImage: "arrow.clockwise")
            }
            .disabled(selectedEventID == nil || resendInProgress)
            .help("重新发送选中事件的 Webhook 通知")

            Button {
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(selectedEventID == nil)
            .help("删除选中的历史记录")

            Button {
                exportCSV()
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
            }
            .help("将所有历史记录导出为 CSV 文件")
        }
    }

    // MARK: - Resend Sheet

    private var resendSheet: some View {
        VStack(spacing: 16) {
            if resendInProgress {
                ProgressView()
                    .scaleEffect(1.2)
                Text("正在重新发送通知…")
                    .font(.headline)
            } else {
                Image(systemName: resendMessage.contains("成功") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(resendMessage.contains("成功") ? .green : .orange)
                Text(resendMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                Button("完成") {
                    showResendProgress = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 350)
    }

    // MARK: - Helpers

    private var selectedEvent: BackupEvent? {
        guard let id = selectedEventID else { return nil }
        return filteredEvents.first { $0.id == id }
    }

    private var filteredEvents: [BackupEvent] {
        if searchText.isEmpty {
            return store.events
        }
        return store.events.filter {
            $0.folderName.localizedCaseInsensitiveContains(searchText) ||
            $0.folderPath.localizedCaseInsensitiveContains(searchText) ||
            $0.monitorName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Actions

    private func resendSelectedEvent() {
        guard let event = selectedEvent else { return }
        resendInProgress = true
        resendMessage = ""
        showResendProgress = true

        Task {
            let config = ConfigStore.shared.load()
            let webhookManager = WebhookManager()
            let results = await webhookManager.notify(event: event, webhooks: config.webhooks)

            let successCount = results.filter { $0.success }.count
            let failCount = results.filter { !$0.success }.count

            await MainActor.run {
                resendInProgress = false
                if failCount == 0 && successCount > 0 {
                    resendMessage = "发送成功！已通知 \(successCount) 个 Webhook。"
                } else if successCount > 0 {
                    resendMessage = "部分成功：\(successCount) 个成功，\(failCount) 个失败。"
                } else if results.isEmpty {
                    resendMessage = "没有已启用的 Webhook，请先在设置中配置。"
                } else {
                    resendMessage = "发送失败，所有 \(failCount) 个 Webhook 均未成功。"
                }
                Logger.shared.info("Resend event \(event.folderName): \(successCount) ok, \(failCount) fail")
            }
        }
    }

    private func exportCSV() {
        let csvContent = HistoryStore.shared.exportCSV()

        let panel = NSSavePanel()
        panel.title = "导出历史记录"
        panel.nameFieldStringValue = "BackupNotify_历史记录.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
                Logger.shared.info("CSV exported to \(url.path)")
            } catch {
                Logger.shared.error("Failed to export CSV: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - HistoryStoreObservable

/// 包装 HistoryStore 供 SwiftUI 使用的 ObservableObject
final class HistoryStoreObservable: ObservableObject {
    @Published var events: [BackupEvent] = []

    private let historyStore = HistoryStore.shared

    init() {
        reload()
    }

    func reload() {
        events = historyStore.getAll()
    }

    func deleteEvent(id: UUID) {
        historyStore.delete(id: id)
        reload()
    }

    func search(query: String) -> [BackupEvent] {
        historyStore.search(query: query)
    }
}

// MARK: - Preview

#if DEBUG
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .frame(width: 900, height: 600)
    }
}
#endif
