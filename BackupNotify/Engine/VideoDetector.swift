import Foundation

struct VideoDetector {
    /// Supported video file extensions (lowercase, without leading dot)
    let extensions: [String]

    init(extensions: [String]) {
        self.extensions = extensions.map { $0.lowercased().replacingOccurrences(of: ".", with: "") }
    }

    // MARK: - Public API

    /// Check if a file is a video based on its extension.
    func isVideoFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return extensions.contains(ext)
    }

    /// Find all video files in a directory (non-recursive).
    func findVideos(in path: String) -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
            return []
        }

        return items.filter { item in
            !isSystemFile(item) && isVideoFile(item)
        }
    }

    // MARK: - Helpers

    /// Check if a filename matches a known macOS system artifact.
    func isSystemFile(_ name: String) -> Bool {
        let systemFiles: Set<String> = [
            ".DS_Store",
            ".Spotlight-V100",
            ".Trashes",
            ".fseventsd",
            ".TemporaryItems",
            ".VolumeIcon.icns",
            ".DocumentRevisions-V100"
        ]
        return systemFiles.contains(name)
    }
}
