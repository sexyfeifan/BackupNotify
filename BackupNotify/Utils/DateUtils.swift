import Foundation

enum DateUtils {
    private static let displayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Format a Date into "yyyy-MM-dd HH:mm:ss" display string.
    static func formatDate(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    /// Alias used by templates: `DateUtils.displayString(from:)`.
    static func displayString(from date: Date) -> String {
        displayFormatter.string(from: date)
    }

    /// Format a Date into ISO 8601 string.
    static func iso8601String(from date: Date) -> String {
        iso8601.string(from: date)
    }

    /// Human-readable relative time: "刚刚" / "3分钟前" / "2小时前".
    static func formatRelative(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow

        // Handle future dates (clock skew) gracefully
        guard interval >= 0 else { return formatDate(date) }

        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分钟前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)天前"
        } else {
            return formatDate(date)
        }
    }
}
