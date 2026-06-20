import Foundation

struct FeishuTemplate: NotificationTemplate {

    static func render(event: BackupEvent) -> Data {
        let report = ReportBuilder.build(from: event)

        let header: [String: Any] = [
            "title": [
                "tag": "plain_text",
                "content": "📋 \(report.title) — \(report.subtitle)"
            ] as [String: Any],
            "template": "green"
        ]

        var elements: [[String: Any]] = []

        for section in report.sections {
            elements.append([
                "tag": "div",
                "text": [
                    "tag": "lark_md",
                    "content": "**\(section.label)：**\(section.value)"
                ] as [String: Any]
            ] as [String: Any])
        }

        if !report.fileTree.isEmpty {
            elements.append(["tag": "hr"])
            elements.append([
                "tag": "div",
                "text": [
                    "tag": "lark_md",
                    "content": "**文件树：**\n```\n\(report.fileTree)\n```"
                ] as [String: Any]
            ] as [String: Any])
        }

        elements.append(["tag": "hr"])
        elements.append([
            "tag": "note",
            "elements": [
                [
                    "tag": "plain_text",
                    "content": report.footer
                ] as [String: Any]
            ]
        ] as [String: Any])

        let payload: [String: Any] = [
            "msg_type": "interactive",
            "card": ["header": header, "elements": elements]
        ]

        return TemplateHelpers.serialize(payload)
    }
}
