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
            !SystemFiles.contains(item) && isVideoFile(item)
        }
    }
}
