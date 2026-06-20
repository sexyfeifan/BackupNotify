import Foundation

struct DingTalkTemplate: NotificationTemplate {

    static func render(event: BackupEvent) -> Data {
        let title = "📋 备份报告 — \(event.folderName)"
        let md = ReportBuilder.markdown(from: event)

        let payload: [String: Any] = [
            "msgtype": "markdown",
            "markdown": [
                "title": title,
                "text": md
            ] as [String: Any]
        ]

        return TemplateHelpers.serialize(payload)
    }
}
