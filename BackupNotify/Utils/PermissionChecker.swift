import Foundation
import AppKit

/// Checks whether the app has filesystem access to external/NAS volumes.
/// macOS requires "Full Disk Access" for paths under /Volumes/.
enum PermissionChecker {

    enum AccessStatus {
        case accessible          // directory is readable
        case noPermission        // directory exists but not readable (needs FDA)
        case notFound            // directory doesn't exist
        case unknownVolume       // can't determine volume status
    }

    /// Check if a path is on an external or network volume (requires Full Disk Access).
    static func requiresFullDiskAccess(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/")
    }

    /// Check actual read access to a path.
    static func checkAccess(_ path: String) -> AccessStatus {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return .notFound
        }

        guard isDir.boolValue else {
            return .notFound
        }

        // Try to read directory contents
        do {
            let contents = try fm.contentsOfDirectory(atPath: path)
            // If we're on /Volumes/ and got contents, we have access
            if !contents.isEmpty || !requiresFullDiskAccess(path) {
                return .accessible
            }
            // Empty directory on /Volumes/ — could be empty dir OR no permission
            // Try to read attributes of a known system file to distinguish
            let testPath = (path as NSString).appendingPathComponent(".DS_Store")
            if fm.fileExists(atPath: testPath) {
                // .DS_Store exists but contentsOfDirectory returned empty → no permission
                return .noPermission
            }
            // Truly empty directory
            return .accessible
        } catch {
            // Error reading directory → likely permission issue
            if requiresFullDiskAccess(path) {
                return .noPermission
            }
            return .noPermission
        }
    }

    /// Check if the app has Full Disk Access by trying to read /Volumes/.
    static func hasFullDiskAccess() -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: "/Volumes") else {
            return false
        }
        // If we can list /Volumes/, we likely have FDA
        // But if the list is empty, we might not (rare edge case: no volumes mounted)
        return !contents.isEmpty
    }

    /// Open System Settings → Privacy & Security → Full Disk Access.
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Human-readable description of access status.
    static func description(for status: AccessStatus) -> String {
        switch status {
        case .accessible:
            return "可访问"
        case .noPermission:
            return "需要完全磁盘访问权限"
        case .notFound:
            return "目录不存在"
        case .unknownVolume:
            return "无法检测"
        }
    }
}
