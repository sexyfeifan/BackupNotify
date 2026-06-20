import Foundation

struct SlackTemplate: NotificationTemplate {

    static func render(event: BackupEvent) -> Data {
        let report = ReportBuilder.build(from: event)
        var blocks: [[String: Any]] = []

        // Header
        blocks.append([
            "type": "header",
            "text": [
                "type": "plain_text",
                "text": "📋 \(report.title) — \(report.subtitle)",
                "emoji": true
            ] as [String: Any]
        ] as [String: Any])

        // Fields (two-column grid)
        var fields: [[String: Any]] = []
        for section in report.sections {
            fields.append(["type": "mrkdwn", "text": "*\(section.label):*\n\(section.value)"] as [String: Any])
        }
        // Slack fields come in pairs
        if fields.count % 2 != 0 {
            fields.append(["type": "mrkdwn", "text": " "] as [String: Any])
        }
        blocks.append(["type": "section", "fields": fields] as [String: Any])

        // File tree
        if !report.fileTree.isEmpty {
            blocks.append(["type": "divider"] as [String: Any])
            blocks.append([
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "*文件树:*\n```\n\(report.fileTree)\n```"
                ] as [String: Any]
            ] as [String: Any])
        }

        // Footer
        blocks.append([
            "type": "context",
            "elements": [
                ["type": "mrkdwn", "text": report.footer] as [String: Any]
            ]
        ] as [String: Any])

        let payload: [String: Any] = ["blocks": blocks]
        return TemplateHelpers.serialize(payload)
    }
}
