import Foundation

final class SnapshotStore {
    static let shared = SnapshotStore()

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

    private var snapshotsDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BackupNotify/snapshots", isDirectory: true)
    }

    private init() {}

    // MARK: - Public API

    func loadSnapshot(forMonitorId monitorId: UUID) -> DirectorySnapshot? {
        let url = snapshotURL(for: monitorId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(DirectorySnapshot.self, from: data)
        } catch {
            Logger.shared.error("Failed to load snapshot for \(monitorId): \(error.localizedDescription)")
            return nil
        }
    }

    func saveSnapshot(_ snapshot: DirectorySnapshot) {
        do {
            try ensureDirectoryExists(snapshotsDirectoryURL)
            let url = snapshotURL(for: snapshot.monitorId)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.shared.error("Failed to save snapshot: \(error.localizedDescription)")
        }
    }

    func deleteSnapshot(forMonitorId monitorId: UUID) {
        let url = snapshotURL(for: monitorId)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Logger.shared.error("Failed to delete snapshot: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func snapshotURL(for monitorId: UUID) -> URL {
        snapshotsDirectoryURL.appendingPathComponent("\(monitorId.uuidString).json")
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
