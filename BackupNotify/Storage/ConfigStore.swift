import Foundation

// MARK: - StorageUtils

/// Shared filesystem utilities used by all Store classes.
enum StorageUtils {

    /// The Application Support directory for BackupNotify.
    static var appSupportURL: URL {
        guard let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first else {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/BackupNotify", isDirectory: true)
        }
        return url.appendingPathComponent("BackupNotify", isDirectory: true)
    }

    static func ensureDirectory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true
            )
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let jsonOptions: JSONSerialization.WritingOptions = [.sortedKeys]
}

// MARK: - ConfigStore

final class ConfigStore {
    static let shared = ConfigStore()

    private let fileManager = FileManager.default

    private var configFileURL: URL {
        StorageUtils.appSupportURL.appendingPathComponent("config.json")
    }

    private init() {}

    // MARK: - Public API

    func load() -> AppConfig {
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            let defaultConfig = AppConfig.default
            save(defaultConfig)
            return defaultConfig
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            return try StorageUtils.decoder.decode(AppConfig.self, from: data)
        } catch {
            Logger.shared.error("Failed to load config: \(error.localizedDescription)")
            return AppConfig.default
        }
    }

    func save(_ config: AppConfig) {
        do {
            try StorageUtils.ensureDirectory(StorageUtils.appSupportURL)
            let data = try StorageUtils.encoder.encode(config)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            Logger.shared.error("Failed to save config: \(error.localizedDescription)")
        }
    }
}
