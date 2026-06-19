import Foundation

// MARK: - HistoryStore

final class HistoryStore {
    static let shared = HistoryStore()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.backupnotify.historystore", qos: .utility)

    private var historyFileURL: URL {
        StorageUtils.appSupportURL.appendingPathComponent("history.json")
    }

    private init() {}

    // MARK: - Public API

    func addEvent(_ event: BackupEvent) {
        queue.sync {
            var events = loadEventsInternal()
            events.insert(event, at: 0)
            saveEventsInternal(events)
            Logger.shared.info("Event added: \(event.folderName) from monitor \(event.monitorName)")
        }
    }

    func getRecent(_ count: Int) -> [BackupEvent] {
        queue.sync {
            let events = loadEventsInternal()
            return Array(events.prefix(count))
        }
    }

    func getAll() -> [BackupEvent] {
        queue.sync {
            loadEventsInternal()
        }
    }

    func search(query: String) -> [BackupEvent] {
        queue.sync {
            let events = loadEventsInternal()
            let lowerQuery = query.lowercased()
            return events.filter {
                $0.folderName.lowercased().contains(lowerQuery) ||
                $0.monitorName.lowercased().contains(lowerQuery) ||
                $0.folderPath.lowercased().contains(lowerQuery)
            }
        }
    }

    func delete(id: UUID) {
        queue.sync {
            var events = loadEventsInternal()
            events.removeAll { $0.id == id }
            saveEventsInternal(events)
            Logger.shared.info("Event deleted: \(id)")
        }
    }

    func clearAll() {
        queue.sync {
            saveEventsInternal([])
            Logger.shared.info("All history cleared")
        }
    }

    /// Export history as CSV with proper escaping (RFC 4180).
    func exportCSV() -> String {
        queue.sync {
            let events = loadEventsInternal()
            let dateFormatter = ISO8601DateFormatter()
            var csv = "ID,MonitorName,FolderName,FolderPath,CreatedAt,ModifiedAt,TotalSizeBytes,FileCount,VideoCount,VideoSizeBytes,NotifiedAt\n"
            for event in events {
                let fields = [
                    event.id.uuidString,
                    escapeCSV(event.monitorName),
                    escapeCSV(event.folderName),
                    escapeCSV(event.folderPath),
                    dateFormatter.string(from: event.createdAt),
                    dateFormatter.string(from: event.modifiedAt),
                    "\(event.totalSizeBytes)",
                    "\(event.fileCount)",
                    "\(event.videoCount)",
                    "\(event.videoSizeBytes)",
                    dateFormatter.string(from: event.notifiedAt)
                ]
                csv += fields.joined(separator: ",") + "\n"
            }
            return csv
        }
    }

    // MARK: - Private

    private func loadEventsInternal() -> [BackupEvent] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: historyFileURL)
            return try StorageUtils.decoder.decode([BackupEvent].self, from: data)
        } catch {
            Logger.shared.error("Failed to load history: \(error.localizedDescription)")
            return []
        }
    }

    private func saveEventsInternal(_ events: [BackupEvent]) {
        do {
            try StorageUtils.ensureDirectory(historyFileURL.deletingLastPathComponent())
            let data = try StorageUtils.encoder.encode(events)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            Logger.shared.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    /// RFC 4180 CSV field escaping: wrap in double quotes, escape internal quotes.
    private func escapeCSV(_ field: String) -> String {
        if field.contains("\"") || field.contains(",") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return "\"\(field)\""
    }
}
