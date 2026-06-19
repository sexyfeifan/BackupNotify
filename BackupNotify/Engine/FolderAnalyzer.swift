import Foundation

// MARK: - FolderInfo

/// Comprehensive analysis result for a single backup folder.
struct FolderInfo {
    let name: String
    let path: String
    let createdAt: Date
    let modifiedAt: Date
    let totalSizeBytes: UInt64
    let fileCount: Int
    let videoCount: Int
    let videoSizeBytes: UInt64
    let videoExtensions: [String]
    let levels: [LevelInfo]
}

// MARK: - FolderAnalyzer

class FolderAnalyzer {

    private let logger: Logger
    private let calculator: LevelSizeCalculator
    private let maxDepth: Int

    init(logger: Logger, calculator: LevelSizeCalculator = LevelSizeCalculator(), maxDepth: Int = 20) {
        self.logger = logger
        self.calculator = calculator
        self.maxDepth = maxDepth
    }

    // MARK: - Public API

    /// Analyze a folder: compute size, count files, detect videos, calculate level sizes.
    func analyze(path: String, videoExtensions: [String]) -> FolderInfo {
        let fm = FileManager.default
        let folderName = (path as NSString).lastPathComponent
        let detector = VideoDetector(extensions: videoExtensions)

        logger.debug("Analyzing folder: \(path)")

        let (createdAt, modifiedAt) = folderDates(path: path)

        var totalSize: UInt64 = 0
        var fileCount = 0
        var videoSize: UInt64 = 0
        var videoFiles: [String] = []
        var visited = Set<String>()

        walkFolder(
            path: path,
            detector: detector,
            totalSize: &totalSize,
            fileCount: &fileCount,
            videoSize: &videoSize,
            videoFiles: &videoFiles,
            visited: &visited,
            currentDepth: 0
        )

        let levels = calculator.calculateLevels(basePath: path, videoDetector: detector)

        logger.debug(
            "Folder analysis complete: \(folderName) — " +
            "\(fileCount) files, \(videoFiles.count) videos, " +
            "\(totalSize) bytes total, \(videoSize) bytes video"
        )

        return FolderInfo(
            name: folderName,
            path: path,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            totalSizeBytes: totalSize,
            fileCount: fileCount,
            videoCount: videoFiles.count,
            videoSizeBytes: videoSize,
            videoExtensions: videoExtensions,
            levels: levels
        )
    }

    // MARK: - Recursive Walk

    private func walkFolder(
        path: String,
        detector: VideoDetector,
        totalSize: inout UInt64,
        fileCount: inout Int,
        videoSize: inout UInt64,
        videoFiles: inout [String],
        visited: inout Set<String>,
        currentDepth: Int
    ) {
        guard currentDepth < maxDepth else { return }

        let fm = FileManager.default

        let canonical = (path as NSString).standardizingPath
        if visited.contains(canonical) { return }
        visited.insert(canonical)

        guard fm.isReadableFile(atPath: path) else { return }

        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("Failed to read directory: \(path)")
            return
        }

        for itemURL in items {
            let name = itemURL.lastPathComponent
            if SystemFiles.contains(name) { continue }

            let resourceValues = try? itemURL.resourceValues(
                forKeys: [.fileSizeKey, .isDirectoryKey]
            )

            let isDir = resourceValues?.isDirectory ?? false

            if isDir {
                walkFolder(
                    path: itemURL.path,
                    detector: detector,
                    totalSize: &totalSize,
                    fileCount: &fileCount,
                    videoSize: &videoSize,
                    videoFiles: &videoFiles,
                    visited: &visited,
                    currentDepth: currentDepth + 1
                )
            } else {
                let size = UInt64(resourceValues?.fileSize ?? 0)
                totalSize += size
                fileCount += 1

                if detector.isVideoFile(name) {
                    videoSize += size
                    videoFiles.append(name)
                }
            }
        }
    }

    // MARK: - Helpers

    private func folderDates(path: String) -> (Date, Date) {
        let fm = FileManager.default
        let fallback = Date()

        guard let attrs = try? fm.attributesOfItem(atPath: path) else {
            return (fallback, fallback)
        }

        let created = attrs[.creationDate] as? Date ?? fallback
        let modified = attrs[.modificationDate] as? Date ?? fallback
        return (created, modified)
    }
}
