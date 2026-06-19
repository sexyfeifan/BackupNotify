import Foundation
import os.log

final class Logger {
    static let shared = Logger()

    enum Level: String {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
    }

    private let osLog = OSLog(subsystem: "com.backupnotify", category: "general")
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    private let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    private let queue = DispatchQueue(label: "com.backupnotify.logger", qos: .utility)

    private var logsDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BackupNotify/logs", isDirectory: true)
    }

    /// Public accessor for the current day's log file URL.
    var logFileURL: URL {
        let fileName = "backupnotify_\(dateFormatter.string(from: Date())).log"
        return logsDirectoryURL.appendingPathComponent(fileName)
    }

    /// Public accessor for the logs directory URL.
    var logsDirectory: URL {
        return logsDirectoryURL
    }

    private init() {}

    // MARK: - Public API

    func info(_ message: String) {
        log(.info, message)
    }

    func warn(_ message: String) {
        log(.warn, message)
    }

    func error(_ message: String) {
        log(.error, message)
    }

    // MARK: - Private

    private func log(_ level: Level, _ message: String) {
        let timestamp = timestampFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] \(message)\n"

        // System log
        let osLevel: OSLogType
        switch level {
        case .info:  osLevel = .info
        case .warn:  osLevel = .default
        case .error: osLevel = .error
        }
        os_log("%{public}@", log: osLog, type: osLevel, message)

        // File log
        queue.async { [self] in
            self.writeToFile(logLine)
        }
    }

    private func writeToFile(_ line: String) {
        do {
            try ensureDirectoryExists(logsDirectoryURL)
            rotateOldLogs()

            let fileName = "backupnotify_\(dateFormatter.string(from: Date())).log"
            let fileURL = logsDirectoryURL.appendingPathComponent(fileName)

            if fileManager.fileExists(atPath: fileURL.path),
               let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Silent fail for logger — avoid recursion
        }
    }

    private func rotateOldLogs() {
        let retentionDays = ConfigStore.shared.load().logRetentionDays
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!

        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for file in files {
            guard file.pathExtension == "log" else { continue }
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate,
               created < cutoffDate {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
