import SwiftUI
import AppKit

// MARK: - LogViewer

/// 日志文件查看器
struct LogViewer: View {
    @StateObject private var viewModel = LogViewerModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            logContent
        }
        .onAppear { viewModel.loadLog() }
        .onReceive(viewModel.refreshTimer) { _ in
            viewModel.loadLog()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Level filters
            FilterToggleButton(title: "全部", isSelected: viewModel.activeFilter == nil, color: .secondary) {
                viewModel.activeFilter = nil
            }
            FilterToggleButton(title: "INFO", isSelected: viewModel.activeFilter == .info, color: .gray) {
                viewModel.activeFilter = viewModel.activeFilter == .info ? nil : .info
            }
            FilterToggleButton(title: "DEBUG", isSelected: viewModel.activeFilter == .debug, color: .cyan) {
                viewModel.activeFilter = viewModel.activeFilter == .debug ? nil : .debug
            }
            FilterToggleButton(title: "WARN", isSelected: viewModel.activeFilter == .warn, color: .yellow) {
                viewModel.activeFilter = viewModel.activeFilter == .warn ? nil : .warn
            }
            FilterToggleButton(title: "ERROR", isSelected: viewModel.activeFilter == .error, color: .red) {
                viewModel.activeFilter = viewModel.activeFilter == .error ? nil : .error
            }

            Spacer()

            Text("\(viewModel.filteredLines.count) 行")
                .font(.caption)
                .foregroundColor(.secondary)

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
            if let timestamp = line.timestamp {
                Text(timestamp)
                    .foregroundColor(.secondary)
                Text(" ")
            }

            if let level = line.level {
                Text("[\(level.rawValue)]")
                    .foregroundColor(colorForLevel(level))
                    .fontWeight(.medium)
                Text(" ")
            }

            Text(line.message)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }

    private func colorForLevel(_ level: Logger.Level) -> Color {
        switch level {
        case .info:  return .gray
        case .debug: return .cyan
        case .warn:  return .yellow
        case .error: return .red
        }
    }
}

// MARK: - FilterToggleButton

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

struct ParsedLogLine: Equatable {
    var timestamp: String?
    var level: Logger.Level?
    var message: String
}

// MARK: - LogViewerModel

final class LogViewerModel: ObservableObject {
    @Published var allLines: [ParsedLogLine] = []
    @Published var activeFilter: Logger.Level? = nil

    let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

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
            // Read last N lines efficiently using FileHandle
            let lines = try readLastLines(from: fileURL, maxLines: maxLines)
            allLines = lines.map { parseLine($0) }
        } catch {
            allLines = [ParsedLogLine(
                timestamp: nil,
                level: .error,
                message: "读取日志文件失败：\(error.localizedDescription)"
            )]
        }
    }

    /// Efficiently read the last N lines from a file without loading the entire file into memory.
    private func readLastLines(from url: URL, maxLines: Int) throws -> [String] {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > 0 else { return [] }

        // For small files (< 1MB), read entirely
        if fileSize < 1_000_000 {
            fileHandle.seek(toFileOffset: 0)
            let data = fileHandle.readDataToEndOfFile()
            let content = String(data: data, encoding: .utf8) ?? ""
            let allLines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            return Array(allLines.suffix(maxLines))
        }

        // For large files, read last 512KB and extract lines
        let readSize: UInt64 = 512_000
        let offset = fileSize > readSize ? fileSize - readSize : 0
        fileHandle.seek(toFileOffset: offset)
        let data = fileHandle.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8) ?? ""
        let allLines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // If we started mid-line, drop the first (potentially partial) line
        let lines = offset > 0 ? Array(allLines.dropFirst()) : allLines
        return Array(lines.suffix(maxLines))
    }

    private static let logPattern = try! NSRegularExpression(pattern: "^\\[([^\\]]+)\\]\\s*\\[(INFO|WARN|ERROR|DEBUG)\\]\\s*(.+)$", options: [])

    /// Parse log line format: [2026-06-19 14:30:00.123] [INFO] message
    private func parseLine(_ raw: String) -> ParsedLogLine {
        let regex = Self.logPattern
        guard let match = regex.firstMatch(
                in: raw,
                range: NSRange(raw.startIndex..., in: raw)
              ) else {
            return ParsedLogLine(timestamp: nil, level: nil, message: raw)
        }

        // Safe unwrap with guard
        guard let timestampRange = Range(match.range(at: 1), in: raw),
              let levelRange = Range(match.range(at: 2), in: raw),
              let messageRange = Range(match.range(at: 3), in: raw) else {
            return ParsedLogLine(timestamp: nil, level: nil, message: raw)
        }

        let timestamp = String(raw[timestampRange])
        let levelStr = String(raw[levelRange])
        let message = String(raw[messageRange])

        let level: Logger.Level?
        switch levelStr {
        case "INFO":  level = .info
        case "WARN":  level = .warn
        case "ERROR": level = .error
        case "DEBUG": level = .debug
        default:      level = nil
        }

        return ParsedLogLine(timestamp: timestamp, level: level, message: message)
    }
}
