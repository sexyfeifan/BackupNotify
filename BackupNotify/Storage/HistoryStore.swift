import Foundation

final class HistoryStore {
    static let shared = HistoryStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let queue = DispatchQueue(label: "com.backupnotify.historystore", qos: .utility)

    private var historyFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BackupNotify/history.json")
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

    func exportCSV() -> String {
        queue.sync {
            let events = loadEventsInternal()
            var csv = "ID,MonitorName,FolderName,FolderPath,CreatedAt,ModifiedAt,TotalSizeBytes,FileCount,VideoCount,VideoSizeBytes,NotifiedAt\n"
            let dateFormatter = ISO8601DateFormatter()
            for event in events {
                csv += "\(event.id.uuidString),\"\(event.monitorName)\",\"\(event.folderName)\",\"\(event.folderPath)\",\(dateFormatter.string(from: event.createdAt)),\(dateFormatter.string(from: event.modifiedAt)),\(event.totalSizeBytes),\(event.fileCount),\(event.videoCount),\(event.videoSizeBytes),\(dateFormatter.string(from: event.notifiedAt))\n"
            }
            return csv
        }
    }

    // MARK: - Private

    private func loadEventsInternal() -> [BackupEvent] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: historyFileURL)
            return try decoder.decode([BackupEvent].self, from: data)
        } catch {
            Logger.shared.error("Failed to load history: \(error.localizedDescription)")
            return []
        }
    }

    private func saveEventsInternal(_ events: [BackupEvent]) {
        do {
            let parentDir = historyFileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            let data = try encoder.encode(events)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            Logger.shared.error("Failed to save history: \(error.localizedDescription)")
        }
    }
}
