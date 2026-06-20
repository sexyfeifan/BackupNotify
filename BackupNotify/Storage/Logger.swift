import Foundation
import os

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

    /// Cached retention days — all reads/writes go through queue for thread safety.
    private var _cachedRetentionDays: Int = 14
    private var _lastRotationTime: Date = .distantPast

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
        _cachedRetentionDays = ConfigStore.shared.load().logRetentionDays
    }

    /// Update the cached retention days (called when user changes settings).
    func updateRetentionDays(_ days: Int) {
        queue.async { self._cachedRetentionDays = days }
    }

    // MARK: - Public API

    func info(_ message: String) {
        log(.info, message)
    }

    @available(*, deprecated, renamed: "warning")
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

        let osLevel: OSLogType
        switch level {
        case .info, .debug: osLevel = .info
        case .warn:         osLevel = .default
        case .error:        osLevel = .error
        }
        os_log("%{public}@", log: osLog, type: osLevel, message)

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
            os_log("Logger file write failed: %{public}@", log: osLog, type: .error, error.localizedDescription)
        }
    }

    private func rotateOldLogs() {
        // Only rotate once per hour, not on every log write
        let now = Date()
        guard now.timeIntervalSince(_lastRotationTime) > 3600 else { return }
        _lastRotationTime = now

        let days = _cachedRetentionDays  // Already on queue, safe to read
        guard days > 0 else { return }  // 0 = permanent, never delete
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return
        }

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
