import SwiftUI
import AppKit

// MARK: - LogViewer

/// 日志文件查看器
struct LogViewer: View {
    @StateObject private var viewModel = LogViewerModel()

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            toolbar

            Divider()

            // 日志内容
            if viewModel.filteredLines.isEmpty {
                EmptyStateView(
                    systemImage: "doc.text.magnifyingglass",
                    title: "暂无日志",
                    message: "当前日志文件为空或不存在"
                )
            } else {
                logContent
            }
        }
        .onAppear {
            viewModel.loadLog()
        }
        .onReceive(viewModel.refreshTimer) { _ in
            viewModel.loadLog()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // 日志级别过滤
            HStack(spacing: 4) {
                FilterToggleButton(
                    title: "全部",
                    isSelected: viewModel.activeFilter == nil,
                    color: .secondary
                ) {
                    viewModel.activeFilter = nil
                }

                FilterToggleButton(
                    title: "INFO",
                    isSelected: viewModel.activeFilter == .info,
                    color: .gray
                ) {
                    viewModel.activeFilter = viewModel.activeFilter == .info ? nil : .info
                }

                FilterToggleButton(
                    title: "WARN",
                    isSelected: viewModel.activeFilter == .warn,
                    color: .yellow
                ) {
                    viewModel.activeFilter = viewModel.activeFilter == .warn ? nil : .warn
                }

                FilterToggleButton(
                    title: "ERROR",
                    isSelected: viewModel.activeFilter == .error,
                    color: .red
                ) {
                    viewModel.activeFilter = viewModel.activeFilter == .error ? nil : .error
                }
            }

            Spacer()

            // 日志行数
            Text("\(viewModel.filteredLines.count) 行")
                .font(.caption)
                .foregroundColor(.secondary)

            // 自动刷新指示灯
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("自动刷新")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // 操作按钮
            Button {
                viewModel.loadLog()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("立即刷新日志内容")

            Button {
                openLogsFolder()
            } label: {
                Label("打开日志文件夹", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中打开日志文件夹")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.filteredLines.enumerated()), id: \.offset) { index, line in
                        LogLineView(line: line)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .font(.system(.caption, design: .monospaced))
            .onChange(of: viewModel.filteredLines.count) { _ in
                // 新内容出现时滚动到底部
                if !viewModel.filteredLines.isEmpty {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(viewModel.filteredLines.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openLogsFolder() {
        NSWorkspace.shared.open(Logger.shared.logsDirectory)
    }
}

// MARK: - LogLineView

/// 单行日志视图，带颜色编码
struct LogLineView: View {
    let line: ParsedLogLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 时间戳
            if let timestamp = line.timestamp {
                Text(timestamp)
                    .foregroundColor(.secondary)
                Text(" ")
            }

            // 级别标签
            if let level = line.level {
                Text("[\(level.rawValue)]")
                    .foregroundColor(colorForLevel(level))
                    .fontWeight(.medium)
                Text(" ")
            }

            // 消息内容
            Text(line.message)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }

    private func colorForLevel(_ level: Logger.Level) -> Color {
        switch level {
        case .info:  return .gray
        case .warn:  return .yellow
        case .error: return .red
        }
    }
}

// MARK: - FilterToggleButton

/// 日志级别过滤切换按钮
struct FilterToggleButton: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if color != .secondary {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ParsedLogLine

/// 解析后的日志行
struct ParsedLogLine: Equatable {
    var timestamp: String?
    var level: Logger.Level?
    var message: String
}

// MARK: - LogViewerModel

/// 日志查看器的视图模型
final class LogViewerModel: ObservableObject {
    @Published var allLines: [ParsedLogLine] = []
    @Published var activeFilter: Logger.Level? = nil

    let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    /// 最多读取最后 5000 行，避免内存问题
    private let maxLines = 5000

    var filteredLines: [ParsedLogLine] {
        guard let filter = activeFilter else { return allLines }
        return allLines.filter { $0.level == filter }
    }

    func loadLog() {
        let fileURL = Logger.shared.logFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            allLines = []
            return
        }

        do {
            // 处理大文件：读取最后 N 行
            let rawContent = try String(contentsOf: fileURL, encoding: .utf8)
            let rawLines = rawContent.components(separatedBy: "\n").filter { !$0.isEmpty }

            // 只保留最后 maxLines 行
            let linesToProcess = rawLines.suffix(maxLines)

            allLines = linesToProcess.map { parseLine($0) }
        } catch {
            allLines = [ParsedLogLine(
                timestamp: nil,
                level: .error,
                message: "读取日志文件失败：\(error.localizedDescription)"
            )]
        }
    }

    /// 解析日志行格式: [2026-06-19 14:30:00.123] [INFO] message
    private func parseLine(_ raw: String) -> ParsedLogLine {
        // 尝试匹配 [timestamp] [LEVEL] message 格式
        let pattern = "^\\[([^\\]]+)\\]\\s*\\[(INFO|WARN|ERROR)\\]\\s*(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                in: raw,
                range: NSRange(raw.startIndex..., in: raw)
              ) else {
            return ParsedLogLine(timestamp: nil, level: nil, message: raw)
        }

        let timestamp = String(raw[Range(match.range(at: 1), in: raw)!])
        let levelStr = String(raw[Range(match.range(at: 2), in: raw)!])
        let message = String(raw[Range(match.range(at: 3), in: raw)!])

        let level: Logger.Level?
        switch levelStr {
        case "INFO":  level = .info
        case "WARN":  level = .warn
        case "ERROR": level = .error
        default:      level = nil
        }

        return ParsedLogLine(timestamp: timestamp, level: level, message: message)
    }
}

// MARK: - Preview

#if DEBUG
struct LogViewer_Previews: PreviewProvider {
    static var previews: some View {
        LogViewer()
            .frame(width: 700, height: 500)
    }
}
#endif
