import Foundation

final class SnapshotStore {
    static let shared = SnapshotStore()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.backupnotify.snapshotstore", qos: .utility)

    private var snapshotsDirectoryURL: URL {
        StorageUtils.appSupportURL.appendingPathComponent("snapshots", isDirectory: true)
    }

    private init() {}

    func loadSnapshot(forMonitorId monitorId: UUID) -> DirectorySnapshot? {
        queue.sync {
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
    }

    func saveSnapshot(_ snapshot: DirectorySnapshot) {
        queue.async { [self] in
            do {
                try StorageUtils.ensureDirectory(snapshotsDirectoryURL)
                let url = snapshotURL(for: snapshot.monitorId)
                let data = try StorageUtils.encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                Logger.shared.error("Failed to save snapshot: \(error.localizedDescription)")
            }
        }
    }

    func deleteSnapshot(forMonitorId monitorId: UUID) {
        queue.async { [self] in
            let url = snapshotURL(for: monitorId)
            guard fileManager.fileExists(atPath: url.path) else { return }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                Logger.shared.error("Failed to delete snapshot: \(error.localizedDescription)")
            }
        }
    }

    private func snapshotURL(for monitorId: UUID) -> URL {
        snapshotsDirectoryURL.appendingPathComponent("\(monitorId.uuidString).json")
    }
}
