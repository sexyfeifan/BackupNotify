import Foundation

// MARK: - SnapshotStore

final class SnapshotStore {
    static let shared = SnapshotStore()

    private let fileManager = FileManager.default

    private var snapshotsDirectoryURL: URL {
        StorageUtils.appSupportURL.appendingPathComponent("snapshots", isDirectory: true)
    }

    private init() {}

    // MARK: - Public API

    func loadSnapshot(forMonitorId monitorId: UUID) -> DirectorySnapshot? {
        let url = snapshotURL(for: monitorId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try StorageUtils.decoder.decode(DirectorySnapshot.self, from: data)
        } catch {
            Logger.shared.error("Failed to load snapshot for \(monitorId): \(error.localizedDescription)")
            return nil
        }
    }

    func saveSnapshot(_ snapshot: DirectorySnapshot) {
        do {
            try StorageUtils.ensureDirectory(snapshotsDirectoryURL)
            let url = snapshotURL(for: snapshot.monitorId)
            let data = try StorageUtils.encoder.encode(snapshot)
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
}
