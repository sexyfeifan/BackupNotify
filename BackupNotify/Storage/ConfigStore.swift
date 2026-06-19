import Foundation

final class ConfigStore {
    static let shared = ConfigStore()

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

    private var configDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BackupNotify", isDirectory: true)
    }

    private var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config.json")
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
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            Logger.shared.error("Failed to load config: \(error.localizedDescription)")
            return AppConfig.default
        }
    }

    func save(_ config: AppConfig) {
        do {
            try ensureDirectoryExists(configDirectoryURL)
            let data = try encoder.encode(config)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            Logger.shared.error("Failed to save config: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
