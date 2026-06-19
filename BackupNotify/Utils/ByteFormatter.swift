import Foundation

enum ByteFormatter {
    private static let units: [(suffix: String, divisor: UInt64)] = [
        ("TB", 1_099_511_627_776),
        ("GB", 1_073_741_824),
        ("MB", 1_048_576),
        ("KB", 1_024),
        ("B",   1),
    ]

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
}
