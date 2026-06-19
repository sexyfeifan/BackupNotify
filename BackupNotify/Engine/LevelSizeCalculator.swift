import Foundation

// MARK: - LevelInfo (local definition; canonical version lives in Storage/Models.swift)

/// Describes a directory level where video files reside.
/// The Storage/Models.swift version is authoritative; this is a compatible mirror
/// so the Engine compiles standalone during parallel development.
struct LevelInfo: Identifiable, Codable, Hashable {
    let id: UUID
    let relativePath: String
    let sizeBytes: UInt64
    let fileCount: Int

    init(id: UUID = UUID(), relativePath: String, sizeBytes: UInt64, fileCount: Int) {
        self.id = id
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
    }
}

// MARK: - LevelSizeCalculator

struct LevelSizeCalculator {

    private static let systemFiles: Set<String> = [
        ".DS_Store",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        ".VolumeIcon.icns",
        ".DocumentRevisions-V100"
    ]

    // MARK: - Public API

    /// Calculate sizes at each level down to where video files exist.
    ///
    /// Algorithm:
    /// 1. Walk the directory tree from `basePath`.
    /// 2. For each subdirectory, check if it *directly* contains video files.
    /// 3. If yes → record this directory's total size as a level entry.
    /// 4. If no  → recurse into its subdirectories.
    /// 5. Return all level entries sorted by relative path.
    ///
    /// - Parameters:
    ///   - basePath: Root directory to walk.
    ///   - videoDetector: Detector configured with the active video extensions.
    /// - Returns: Array of `LevelInfo` entries, sorted by `relativePath`.
    func calculateLevels(basePath: String, videoDetector: VideoDetector) -> [LevelInfo] {
        var levels: [LevelInfo] = []
        var visited = Set<String>()
        walkDirectory(
            path: basePath,
            basePath: basePath,
            videoDetector: videoDetector,
            levels: &levels,
            visited: &visited
        )
        return levels.sorted { $0.relativePath < $1.relativePath }
    }

    // MARK: - Recursive Walk

    /// Recursively walk a directory, collecting level info where videos are found.
    private func walkDirectory(
        path: String,
        basePath: String,
        videoDetector: VideoDetector,
        levels: inout [LevelInfo],
        visited: inout Set<String>
    ) {
        let fm = FileManager.default

        // Prevent symlink loops
        let canonical = (path as NSString).standardizingPath
        if visited.contains(canonical) { return }
        visited.insert(canonical)

        // Check accessibility
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        guard fm.isReadableFile(atPath: path) else {
            return
        }

        // Check if this directory directly contains video files
        let videos = videoDetector.findVideos(in: path)
        if !videos.isEmpty {
            // Record this level
            let relativePath = relativePathString(from: basePath, to: path)
            let (size, count) = directorySize(path: path)
            let level = LevelInfo(
                relativePath: relativePath,
                sizeBytes: size,
                fileCount: count
            )
            levels.append(level)
            // Don't recurse further — videos found at this level
            return
        }

        // No videos here — recurse into subdirectories
        guard let children = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for childURL in children {
            let childName = childURL.lastPathComponent
            if Self.systemFiles.contains(childName) { continue }

            var childIsDir: ObjCBool = false
            guard fm.fileExists(atPath: childURL.path, isDirectory: &childIsDir),
                  childIsDir.boolValue else {
                continue
            }

            walkDirectory(
                path: childURL.path,
                basePath: basePath,
                videoDetector: videoDetector,
                levels: &levels,
                visited: &visited
            )
        }
    }

    // MARK: - Helpers

    /// Compute total size and file count of a directory (non-recursive, files only).
    private func directorySize(path: String) -> (UInt64, Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var totalSize: UInt64 = 0
        var fileCount = 0

        for itemURL in items {
            let name = itemURL.lastPathComponent
            if Self.systemFiles.contains(name) { continue }

            let resourceValues = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if resourceValues?.isDirectory == true { continue }

            let size = UInt64(resourceValues?.fileSize ?? 0)
            totalSize += size
            fileCount += 1
        }

        return (totalSize, fileCount)
    }

    /// Compute a relative path string from `base` to `target`.
    private func relativePathString(from base: String, to target: String) -> String {
        let baseURL = URL(fileURLWithPath: base)
        let targetURL = URL(fileURLWithPath: target)
        let rel = targetURL.path.replacingOccurrences(of: baseURL.path, with: "")
        // Strip leading slash if present
        if rel.hasPrefix("/") {
            return String(rel.dropFirst())
        }
        return rel
    }
}
