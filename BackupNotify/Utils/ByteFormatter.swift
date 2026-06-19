import Foundation

enum ByteFormatter {
    private static let units: [(suffix: String, divisor: UInt64)] = [
        ("TB", 1_099_511_627_776),
        ("GB", 1_073_741_824),
        ("MB", 1_048_576),
        ("KB", 1_024),
        ("B",   1),
    ]

    /// Format a byte count into a human-readable string (e.g. "12.3 GB").
    static func formatBytes(_ bytes: UInt64) -> String {
        for unit in units {
            if bytes >= unit.divisor {
                let value = Double(bytes) / Double(unit.divisor)
                if unit.suffix == "B" {
                    return "\(bytes) B"
                }
                return String(format: "%.1f %@", value, unit.suffix)
            }
        }
        return "0 B"
    }

    /// UInt64 overload — direct pass-through, no overflow risk.
    static func string(fromByteCount bytes: UInt64) -> String {
        formatBytes(bytes)
    }

    /// Int64 overload for compatibility with platform APIs that return Int64 byte counts.
    static func string(fromByteCount bytes: Int64) -> String {
        formatBytes(UInt64(max(0, bytes)))
    }
}
