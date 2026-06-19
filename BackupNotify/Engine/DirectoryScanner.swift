import Foundation

// MARK: - DirectoryScanner

struct DirectoryScanner {

    // MARK: - Public API

    /// Scan a directory up to `depth` levels deep.
    /// Returns array of folder names at the target depth level.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the directory to scan.
    ///   - depth: How many levels deep to look. 1 = immediate children.
    /// - Returns: Sorted array of folder name strings at the target depth.
    func scanDirectory(at path: String, depth: Int) -> [String] {
        guard depth >= 1 else { return [] }

        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)

        guard isAccessible(path) else { return [] }

        var visited = Set<String>()

        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )

            var results: [String] = []

            for itemURL in contents {
                let itemName = itemURL.lastPathComponent
                if SystemFiles.contains(itemName) { continue }

                // Resolve symlinks and detect loops
                guard let resolved = resolveSymlink(itemURL.path, visited: &visited) else {
                    continue
                }

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                if depth == 1 {
                    results.append(itemName)
                } else {
                    let deeper = scanDirectory(at: resolved, depth: depth - 1)
                    results.append(contentsOf: deeper)
                }
            }

            return results.sorted()

        } catch {
            return []
        }
    }

    /// Check if a directory exists and is accessible.
    func isAccessible(_ path: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        guard fm.isReadableFile(atPath: path) else { return false }
        do {
            _ = try fm.contentsOfDirectory(atPath: path)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    /// Resolve a symlink and detect loops by tracking visited real paths.
    /// Returns nil if a loop is detected or the path can't be resolved.
    private func resolveSymlink(_ path: String, visited: inout Set<String>) -> String? {
        let fm = FileManager.default

        let attrs = try? fm.attributesOfItem(atPath: path)
        let isSymlink = attrs?[.type] as? FileAttributeType == .typeSymbolicLink

        let resolved: String
        if isSymlink {
            guard let destination = try? fm.destinationOfSymbolicLink(atPath: path) else {
                return nil
            }
            if destination.hasPrefix("/") {
                resolved = destination
            } else {
                resolved = (path as NSString).deletingLastPathComponent
                    .appending("/").appending(destination)
            }
        } else {
            resolved = path
        }

        let canonical = (resolved as NSString).standardizingPath
        if visited.contains(canonical) { return nil }
        visited.insert(canonical)
        return canonical
    }
}
