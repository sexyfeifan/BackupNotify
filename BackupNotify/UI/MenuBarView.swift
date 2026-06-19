import SwiftUI
import AppKit

// MARK: - MenuBarView

/// 菜单栏弹出面板
struct MenuBarView: View {
    @ObservedObject var engine: MonitorEngine
    @State private var recentEvents: [BackupEvent] = []
    @State private var refreshTrigger = false

    /// 每 30 秒刷新一次
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            statusSection
            Divider()
            recentSection
            Divider()
            actionButtons
            Divider()
            footerButtons
        }
        .frame(width: 320)
        .onAppear { loadRecent() }
        .onReceive(timer) { _ in
            loadRecent()
            refreshTrigger.toggle()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title3)
                .foregroundColor(.accentColor)
            Text("BackupNotify")
                .font(.headline)

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if engine.lastError != nil {
            StatusBadge(status: .error)
        } else if engine.isRunning {
            StatusBadge(status: .running)
        } else {
            StatusBadge(status: .paused)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("监控目录：\(engine.activeMonitors) 个")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let lastScan = engine.lastScanDate {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("上次扫描：\(DateUtils.formatRelative(lastScan))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if engine.activeMonitors == 0 {
                Text("暂无监控目录，点击设置添加")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Recent Notifications

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近通知")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            if recentEvents.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "暂无记录",
                    message: "备份事件将在此处显示"
                )
                .frame(height: 100)
            } else {
                ForEach(recentEvents) { event in
                    recentEventRow(event)
                    if event.id != recentEvents.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func recentEventRow(_ event: BackupEvent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.folderName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    SizeLabel(bytes: event.totalSizeBytes)
                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                    RelativeTimeLabel(date: event.notifiedAt)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Quick Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: { engine.scanOnce() }) {
                Label("立即扫描", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(!engine.isRunning && engine.activeMonitors == 0)

            Button(action: {
                if engine.isRunning {
                    engine.stop()
                } else {
                    engine.start()
                }
            }) {
                Label(
                    engine.isRunning ? "暂停监控" : "恢复监控",
                    systemImage: engine.isRunning ? "pause.fill" : "play.fill"
                )
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(engine.activeMonitors == 0 && !engine.isRunning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(spacing: 0) {
            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gear")
                        .font(.caption)
                    Text("设置...")
                        .font(.subheadline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                        .font(.caption)
                    Text("退出")
                        .font(.subheadline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .padding(.top, 6)
        }
    }

    // MARK: - Helpers

    private func loadRecent() {
        recentEvents = HistoryStore.shared.getRecent(5)
    }

    private func openSettings() {
        // Safe: uses the standard macOS Settings window selector.
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettings:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
