import Foundation
import Combine

// MARK: - MonitorEngine

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

    // MARK: - Init

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

    func start() {
        guard !isRunning else {
            logger.warning("MonitorEngine.start() — already running")
            return
        }

        // Always reload latest config before starting
        config = ConfigStore.shared.load()
        updateActiveMonitors()

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

    func stop() {
        logger.info("MonitorEngine stopping")
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func scanOnce() {
        // Reload config each scan cycle to pick up webhook/setting changes
        config = ConfigStore.shared.load()

        let monitors = config.monitors.filter(\.enabled)
        guard !monitors.isEmpty else {
            logger.warning("scanOnce() — no enabled monitors, skipping")
            return
        }

        let capturedConfig = config

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            self.logger.info("Scan cycle starting — \(monitors.count) monitor(s)")
            var errors: [String] = []

            for monitor in monitors {
                await self.processMonitor(monitor, config: capturedConfig, errors: &errors)
            }

            let combinedError = errors.isEmpty ? nil : errors.joined(separator: "; ")

            await MainActor.run {
                self.lastScanDate = Date()
                self.lastError = combinedError
            }

            self.logger.info("Scan cycle complete")
        }
    }

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
        errors: inout [String]
    ) async {
        let monitorPath = monitor.path
        logger.debug("Processing monitor: \(monitor.name) at \(monitorPath)")

        var visited = Set<String>()
        let scannedFolders = scanner.scanDirectory(at: monitorPath, depth: monitor.depth, visited: &visited, excludePatterns: monitor.excludePatterns)

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

                let event = BackupEvent(
                    monitorId: monitor.id,
                    monitorName: monitor.name,
                    folderInfo: folderInfo
                )

                // Save event to history
                historyStore.addEvent(event)

                // Send local notification if enabled
                if config.enableLocalNotification {
                    LocalNotifier.notify(event: event)
                }

                // Check quiet hours before sending webhooks
                if let qh = config.quietHours, qh.enabled, isInQuietHours(qh) {
                    logger.info("Skipping webhook — quiet hours active (\(qh.startHour):\(String(format: "%02d", qh.startMinute))-\(qh.endHour):\(String(format: "%02d", qh.endMinute)))")
                } else {
                    // Send webhook notifications (non-blocking, no semaphore)
                    let webhooks = config.webhooks
                    let enabledWebhooks = webhooks.filter { $0.enabled }

                    if !enabledWebhooks.isEmpty {
                        logger.info("Sending webhook to \(enabledWebhooks.count) endpoint(s) for \(folderName)")

                        let webhookMgr = self.webhookManager
                        let history = self.historyStore
                        let monitorName = monitor.name
                        let loggerRef = self.logger

                        Task.detached(priority: .utility) {
                            let results = await webhookMgr.notify(event: event, webhooks: webhooks)
                            var updatedEvent = event
                            updatedEvent.webhookResults = results
                            history.updateEvent(updatedEvent)

                            let failed = results.filter { !$0.success }
                            if !failed.isEmpty {
                                let names = failed.map(\.webhookName).joined(separator: ", ")
                                loggerRef.error("Webhook failed for \(monitorName)/\(folderName): \(names)")
                            } else {
                                loggerRef.info("Webhook sent successfully for \(monitorName)/\(folderName)")
                            }
                        }
                    } else {
                        logger.debug("No enabled webhooks for \(folderName), skipping notification")
                    }
                }
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

    // MARK: - Quiet Hours

    private func isInQuietHours(_ qh: QuietHours) -> Bool {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let startMinutes = qh.startHour * 60 + qh.startMinute
        let endMinutes = qh.endHour * 60 + qh.endMinute

        if startMinutes <= endMinutes {
            // Same day range (e.g. 09:00 - 17:00)
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Overnight range (e.g. 22:00 - 08:00)
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
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
