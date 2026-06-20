import Foundation

struct DiscordTemplate: NotificationTemplate {

    static func render(event: BackupEvent) -> Data {
        let report = ReportBuilder.build(from: event)

        var fields: [[String: Any]] = []
        for section in report.sections {
            fields.append([
                "name": section.label,
                "value": section.value,
                "inline": true
            ] as [String: Any])
        }

        var description = ""
        if !report.fileTree.isEmpty {
            description = "**文件树：**\n```\n\(report.fileTree)\n```"
        }

        let embed: [String: Any] = [
            "title": "📋 \(report.title) — \(report.subtitle)",
            "color": 3_066_993,
            "fields": fields,
            "description": description,
            "footer": ["text": report.footer] as [String: Any],
            "timestamp": DateUtils.iso8601String(from: event.notifiedAt)
        ]

        let payload: [String: Any] = ["embeds": [embed]]
        return TemplateHelpers.serialize(payload)
    }
}
