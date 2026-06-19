import Foundation

enum DateUtils {
    private static let displayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    static func formatDate(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    static func formatRelative(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow

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
