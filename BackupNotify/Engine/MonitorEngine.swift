import Foundation
import Combine

// MARK: - MonitorEngine

/// The main orchestrator for BackupNotify.
///
/// Owns the scan loop, coordinates DirectoryScanner ↔ FolderAnalyzer ↔ SnapshotStore ↔ WebhookManager,
/// and publishes UI-facing state via `@Published` properties.
class MonitorEngine: ObservableObject {

    // MARK: - Published State

    @Published var isRunning: Bool = false
    @Published var lastScanDate: Date?
    @Published var activeMonitors: Int = 0
    @Published var lastError: String?

    // MARK: - Dependencies

    private var timer: Timer?
    private var config: AppConfig
    private let scanner = DirectoryScanner()
    private let analyzer: FolderAnalyzer
    private let snapshotStore: SnapshotStore
    private let historyStore: HistoryStore
    private let webhookManager: WebhookManager
    private let logger: Logger
    private let scanQueue = DispatchQueue(label: "com.backupnotify.scan", qos: .utility)

    // MARK: - Init

    /// Full initializer with explicit dependencies.
    init(
        config: AppConfig,
        snapshotStore: SnapshotStore,
        historyStore: HistoryStore,
        webhookManager: WebhookManager,
        logger: Logger
    ) {
        self.config = config
        self.snapshotStore = snapshotStore
        self.historyStore = historyStore
        self.webhookManager = webhookManager
        self.logger = logger
        self.analyzer = FolderAnalyzer(logger: logger)

        updateActiveMonitors()
    }

    /// Convenience initializer using singletons and saved configuration.
    convenience init() {
        let logger = Logger.shared
        let config = ConfigStore.shared.load()
        self.init(
            config: config,
            snapshotStore: SnapshotStore.shared,
            historyStore: HistoryStore.shared,
            webhookManager: WebhookManager(),
            logger: logger
        )
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Start the periodic monitoring loop.
    func start() {
        guard !isRunning else {
            logger.warning("MonitorEngine.start() called but engine is already running")
            return
        }

        guard !config.monitors.filter(\.enabled).isEmpty else {
            logger.warning("No enabled monitors — engine will not start")
            lastError = "No enabled monitors configured"
            return
        }

        logger.info("MonitorEngine starting — interval \(config.pollingIntervalSeconds)s, " +
                     "\(activeMonitors) monitors")
        isRunning = true
        lastError = nil

        scanOnce()

        timer = Timer.scheduledTimer(
            withTimeInterval: config.pollingIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            self?.scanOnce()
        }
    }

    /// Stop the monitoring loop.
    func stop() {
        logger.info("MonitorEngine stopping")
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Perform a single scan cycle across all enabled monitors.
    func scanOnce() {
        let monitors = config.monitors.filter(\.enabled)
        guard !monitors.isEmpty else {
            logger.warning("scanOnce() — no enabled monitors, skipping")
            return
        }

        let capturedConfig = config

        scanQueue.async { [weak self] in
            guard let self else { return }

            self.logger.info("Scan cycle starting — \(monitors.count) monitor(s)")
            var anyError: String?

            for monitor in monitors {
                self.processMonitor(monitor, config: capturedConfig, errorAccumulator: &anyError)
            }

            DispatchQueue.main.async {
                self.lastScanDate = Date()
                self.lastError = anyError
            }

            self.logger.info("Scan cycle complete")
        }
    }

    /// Reload configuration (called when user changes settings).
    func reloadConfig(_ newConfig: AppConfig) {
        logger.info("Reloading configuration")
        let wasRunning = isRunning

        if wasRunning { stop() }

        config = newConfig
        updateActiveMonitors()

        if wasRunning { start() }
    }

    // MARK: - Private: Per-Monitor Processing

    private func processMonitor(
        _ monitor: MonitorConfig,
        config: AppConfig,
        errorAccumulator: inout String?
    ) {
        let monitorPath = monitor.path
        logger.debug("Processing monitor: \(monitor.name) at \(monitorPath)")

        let scannedFolders = scanner.scanDirectory(at: monitorPath, depth: monitor.depth)

        guard !scannedFolders.isEmpty else {
            logger.debug("No folders found at \(monitorPath)")
            return
        }

        let snapshot = snapshotStore.loadSnapshot(forMonitorId: monitor.id)
        let knownSet = Set(snapshot?.knownFolders ?? [])

        let newFolders = scannedFolders.filter { !knownSet.contains($0) }

        if newFolders.isEmpty {
            logger.debug("No new folders for monitor \(monitor.name)")
        } else {
            logger.info("\(newFolders.count) new folder(s) for monitor \(monitor.name)")

            for folderName in newFolders {
                let fullPath = (monitorPath as NSString).appendingPathComponent(folderName)

                guard !isEmptyDirectory(fullPath) else {
                    logger.debug("Skipping empty folder: \(folderName)")
                    continue
                }

                let folderInfo = analyzer.analyze(
                    path: fullPath,
                    videoExtensions: config.videoExtensions
                )

                // Build event
                let event = BackupEvent(
                    monitorId: monitor.id,
                    monitorName: monitor.name,
                    folderInfo: folderInfo
                )

                // Send webhook notifications
                Task {
                    do {
                        try await webhookManager.send(event: event, config: config)
                        logger.info("Webhook sent for: \(folderName)")
                    } catch {
                        let msg = "Webhook failed for \(folderName): \(error.localizedDescription)"
                        logger.error(msg)
                        await MainActor.run { errorAccumulator = msg }
                    }
                }

                // Save event to history
                historyStore.addEvent(event)
            }
        }

        // Update snapshot with all scanned folders
        let updatedSnapshot = DirectorySnapshot(
            monitorId: monitor.id,
            timestamp: Date(),
            knownFolders: Set(scannedFolders)
        )
        snapshotStore.saveSnapshot(updatedSnapshot)
    }

    // MARK: - Private Helpers

    private func isEmptyDirectory(_ path: String) -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return true }
        let meaningful = contents.filter { !SystemFiles.contains($0) }
        return meaningful.isEmpty
    }

    private func updateActiveMonitors() {
        activeMonitors = config.monitors.filter(\.enabled).count
    }
}
