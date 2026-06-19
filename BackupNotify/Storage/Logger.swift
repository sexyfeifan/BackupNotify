import Foundation
import os.log

// MARK: - Logger

final class Logger {
    static let shared = Logger()

    enum Level: String {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"
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

    /// Cached retention days — avoids re-reading config on every log write.
    private var cachedRetentionDays: Int = 14

    private var logsDirectoryURL: URL {
        StorageUtils.appSupportURL.appendingPathComponent("logs", isDirectory: true)
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

    private init() {
        // Load retention days once at init.
        cachedRetentionDays = ConfigStore.shared.load().logRetentionDays
    }

    /// Update the cached retention days (called when user changes settings).
    func updateRetentionDays(_ days: Int) {
        cachedRetentionDays = days
    }

    // MARK: - Public API

    func info(_ message: String) {
        log(.info, message)
    }

    func warn(_ message: String) {
        log(.warn, message)
    }

    func warning(_ message: String) {
        log(.warn, message)
    }

    func error(_ message: String) {
        log(.error, message)
    }

    func debug(_ message: String) {
        log(.debug, message)
    }

    // MARK: - Private

    private func log(_ level: Level, _ message: String) {
        let timestamp = timestampFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue)] \(message)\n"

        // System log
        let osLevel: OSLogType
        switch level {
        case .info, .debug: osLevel = .info
        case .warn:         osLevel = .default
        case .error:        osLevel = .error
        }
        os_log("%{public}@", log: osLog, type: osLevel, message)

        // File log
        queue.async { [self] in
            self.writeToFile(logLine)
        }
    }

    private func writeToFile(_ line: String) {
        do {
            try StorageUtils.ensureDirectory(logsDirectoryURL)
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
            // Logger must not recurse — write to os_log as last resort.
            os_log("Logger file write failed: %{public}@", log: osLog, type: .error, error.localizedDescription)
        }
    }

    private func rotateOldLogs() {
        let cutoffDate = Calendar.current.date(
            byAdding: .day, value: -cachedRetentionDays, to: Date()
        )!

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
}
