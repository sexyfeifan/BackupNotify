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
    let fileEntries: [FileEntry]
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

        // Build complete file tree
        var fileEntries: [FileEntry] = []
        buildFileTree(path: path, basePath: path, depth: 0, entries: &fileEntries)

        logger.debug(
            "Folder analysis complete: \(folderName) — " +
            "\(fileCount) files, \(videoFiles.count) videos, " +
            "\(totalSize) bytes total, \(videoSize) bytes video, " +
            "\(fileEntries.count) tree entries"
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
            levels: levels,
            fileEntries: fileEntries
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

        // Use resolvingSymlinksInPath for proper canonicalization (handles symlinks)
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if visited.contains(canonical) { return }
        visited.insert(canonical)

        guard fm.isReadableFile(atPath: path) else { return }

        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
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

    /// Recursively build a complete file tree with depth information.
    private func buildFileTree(
        path: String,
        basePath: String,
        depth: Int,
        entries: inout [FileEntry]
    ) {
        guard depth < maxDepth else { return }

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // Pre-compute isDirectory to avoid I/O in sort comparator
        let itemsWithInfo: [(URL, Bool, String)] = items.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return (url, isDir, url.lastPathComponent)
        }

        let sorted = itemsWithInfo.sorted { a, b in
            if a.1 != b.1 { return a.1 } // directories first
            return a.2.localizedCaseInsensitiveCompare(b.2) == .orderedAscending
        }

        for (itemURL, isDir, name) in sorted {
            if SystemFiles.contains(name) { continue }

            let relativePath: String
            if depth == 0 {
                relativePath = name
            } else {
                let baseComponents = URL(fileURLWithPath: basePath).pathComponents
                let itemComponents = itemURL.pathComponents
                relativePath = itemComponents.dropFirst(baseComponents.count).joined(separator: "/")
            }

            if isDir {
                let (dirSize, dirFileCount) = directorySize(path: itemURL.path)

                entries.append(FileEntry(
                    name: name,
                    relativePath: relativePath,
                    sizeBytes: dirSize,
                    isDirectory: true,
                    depth: depth,
                    childCount: dirFileCount
                ))

                buildFileTree(
                    path: itemURL.path,
                    basePath: basePath,
                    depth: depth + 1,
                    entries: &entries
                )
            } else {
                let resourceValues = try? itemURL.resourceValues(forKeys: [.fileSizeKey])
                let size = UInt64(resourceValues?.fileSize ?? 0)
                entries.append(FileEntry(
                    name: name,
                    relativePath: relativePath,
                    sizeBytes: size,
                    isDirectory: false,
                    depth: depth
                ))
            }
        }
    }

    private func directorySize(path: String) -> (UInt64, Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var totalSize: UInt64 = 0
        var fileCount = 0

        for itemURL in items {
            let name = itemURL.lastPathComponent
            if SystemFiles.contains(name) { continue }

            let resourceValues = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if resourceValues?.isDirectory == true { continue }

            let size = UInt64(resourceValues?.fileSize ?? 0)
            totalSize += size
            fileCount += 1
        }

        return (totalSize, fileCount)
    }

    private func folderDates(path: String) -> (Date, Date) {
        let fallback = Date()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return (fallback, fallback)
        }
        let created = attrs[.creationDate] as? Date ?? fallback
        let modified = attrs[.modificationDate] as? Date ?? fallback
        return (created, modified)
    }
}
