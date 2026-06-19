import Foundation

// MARK: - LevelSizeCalculator

/// Calculates directory sizes at each level where video files reside.
///
/// Algorithm:
/// 1. Walk the directory tree from `basePath`.
/// 2. For each subdirectory, check if it *directly* contains video files.
/// 3. If yes → record this directory's total size as a level entry.
/// 4. If no  → recurse into its subdirectories.
/// 5. Return all level entries sorted by relative path.
///
/// Uses the canonical `LevelInfo` from Storage/Models.swift.
struct LevelSizeCalculator {

    // MARK: - Public API

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

    private func walkDirectory(
        path: String,
        basePath: String,
        videoDetector: VideoDetector,
        levels: inout [LevelInfo],
        visited: inout Set<String>
    ) {
        let fm = FileManager.default

        let canonical = fm.resolvingSymlinksInPath(path)
        if visited.contains(canonical) { return }
        visited.insert(canonical)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        guard fm.isReadableFile(atPath: path) else { return }

        let videos = videoDetector.findVideos(in: path)
        if !videos.isEmpty {
            let relativePath = relativePathString(from: basePath, to: path)
            let (size, count) = directorySize(path: path)
            let level = LevelInfo(
                relativePath: relativePath,
                sizeBytes: size,
                fileCount: count
            )
            levels.append(level)
            return
        }

        guard let children = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for childURL in children {
            let childName = childURL.lastPathComponent
            if SystemFiles.contains(childName) { continue }

            var childIsDir: ObjCBool = false
            guard fm.fileExists(atPath: childURL.path, isDirectory: &childIsDir),
                  childIsDir.boolValue else { continue }

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

    private func directorySize(path: String) -> (UInt64, Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey],
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

    /// Compute relative path using URL path components to avoid string replacement bugs.
    /// e.g. base="/foo/bar" target="/foo/bar/baz/file" → "baz/file"
    private func relativePathString(from base: String, to target: String) -> String {
        let baseURL = URL(fileURLWithPath: base)
        let targetURL = URL(fileURLWithPath: target)

        let baseComponents = baseURL.pathComponents
        let targetComponents = targetURL.pathComponents

        // Find common prefix length
        var commonLength = 0
        for (i, component) in baseComponents.enumerated() {
            guard i < targetComponents.count, component == targetComponents[i] else { break }
            commonLength = i + 1
        }

        // Build relative path from remaining target components
        let remaining = targetComponents.dropFirst(commonLength)
        return remaining.joined(separator: "/")
    }
}
