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
    private let webhookManager: WebhookManager
    private let logger: Logger
    private let scanQueue = DispatchQueue(label: "com.backupnotify.scan", qos: .utility)

    // MARK: - Init

    /// Full initializer with explicit dependencies.
    init(
        config: AppConfig,
        snapshotStore: SnapshotStore,
        webhookManager: WebhookManager,
        logger: Logger
    ) {
        self.config = config
        self.snapshotStore = snapshotStore
        self.webhookManager = webhookManager
        self.logger = logger
        self.analyzer = FolderAnalyzer(logger: logger)

        updateActiveMonitors()
    }

    /// Convenience initializer using singletons and saved configuration.
    convenience init() {
        let logger = Logger.shared
        let configStore = ConfigStore.shared
        let config = configStore.load()
        self.init(
            config: config,
            snapshotStore: SnapshotStore.shared,
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

        logger.info("MonitorEngine starting — interval \(config.pollingIntervalSeconds)s, "
                     + "\(config.monitors.filter(\.enabled).isEmpty ? "no" : "\(activeMonitors)") monitors")
        isRunning = true
        lastError = nil

        // Run first scan immediately, then schedule on interval
        scanOnce()

        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(config.pollingIntervalSeconds),
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
    ///
    /// Scanning is dispatched to a background queue so the UI stays responsive.
    /// Results (published property updates) are delivered on the main thread.
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

            // Update published state on main thread
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

        if wasRunning {
            stop()
        }

        config = newConfig
        updateActiveMonitors()

        if wasRunning {
            start()
        }
    }

    // MARK: - Private: Per-Monitor Processing

    /// Process a single monitor: scan, diff, analyze new folders, notify.
    private func processMonitor(
        _ monitor: MonitorConfig,
        config: AppConfig,
        errorAccumulator: inout String?
    ) {
        let monitorPath = monitor.path
        logger.debug("Processing monitor: \(monitor.name) at \(monitorPath)")

        // a. Scan directory at configured depth
        let scannedFolders = scanner.scanDirectory(at: monitorPath, depth: monitor.depth)

        guard !scannedFolders.isEmpty else {
            logger.debug("No folders found at \(monitorPath)")
            return
        }

        // b. Load snapshot for this monitor
        let snapshot = snapshotStore.loadSnapshot(for: monitor.id)
        let knownSet = Set(snapshot.knownFolders)

        // c. Compute new folders
        let newFolders = scannedFolders.filter { !knownSet.contains($0) }

        if newFolders.isEmpty {
            logger.debug("No new folders for monitor \(monitor.name)")
        } else {
            logger.info("\(newFolders.count) new folder(s) for monitor \(monitor.name)")

            // d. Analyze each new folder, notify, and record
            for folderName in newFolders {
                let fullPath = (monitorPath as NSString).appendingPathComponent(folderName)

                // Skip empty folders
                guard !isEmptyDirectory(fullPath) else {
                    logger.debug("Skipping empty folder: \(folderName)")
                    continue
                }

                // Analyze
                let folderInfo = analyzer.analyze(
                    path: fullPath,
                    videoExtensions: config.videoExtensions
                )

                // Build event
                let event = BackupEvent(
                    monitorId: monitor.id,
                    monitorName: monitor.name,
                    folderInfo: folderInfo,
                    timestamp: Date()
                )

                // Send webhook
                do {
                    try webhookManager.send(event: event, config: config)
                    logger.info("Webhook sent for: \(folderName)")
                } catch {
                    let msg = "Webhook failed for \(folderName): \(error.localizedDescription)"
                    logger.error(msg)
                    errorAccumulator = msg
                }

                // Save event to history
                snapshotStore.saveEvent(event)
            }
        }

        // e. Update snapshot with all scanned folders (including previously known ones)
        let updatedSnapshot = MonitorSnapshot(
            monitorId: monitor.id,
            knownFolders: scannedFolders,
            lastScanDate: Date()
        )
        snapshotStore.saveSnapshot(updatedSnapshot)
    }

    // MARK: - Private Helpers

    /// Check if a directory is empty (no files or subdirectories, ignoring system files).
    private func isEmptyDirectory(_ path: String) -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return true
        }

        let systemFiles: Set<String> = [
            ".DS_Store", ".Spotlight-V100", ".Trashes",
            ".fseventsd", ".TemporaryItems"
        ]

        let meaningful = contents.filter { !systemFiles.contains($0) }
        return meaningful.isEmpty
    }

    /// Update the `activeMonitors` published property.
    private func updateActiveMonitors() {
        activeMonitors = config.monitors.filter(\.enabled).count
    }
}

// MARK: - Convenience: BackupEvent Factory Extension

extension BackupEvent {
    /// Create a BackupEvent from a FolderInfo analysis result.
    init(
        monitorId: UUID,
        monitorName: String,
        folderInfo: FolderInfo,
        timestamp: Date
    ) {
        self.init(
            id: UUID(),
            monitorId: monitorId,
            monitorName: monitorName,
            folderName: folderInfo.name,
            folderPath: folderInfo.path,
            createdAt: folderInfo.createdAt,
            totalSizeBytes: folderInfo.totalSizeBytes,
            fileCount: folderInfo.fileCount,
            videoCount: folderInfo.videoCount,
            videoSizeBytes: folderInfo.videoSizeBytes,
            videoExtensions: folderInfo.videoExtensions,
            levels: folderInfo.levels,
            timestamp: timestamp,
            webhookDelivered: false
        )
    }
}
