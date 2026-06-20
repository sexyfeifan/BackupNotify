import Foundation

struct WeComTemplate: NotificationTemplate {

    static func render(event: BackupEvent) -> Data {
        let report = ReportBuilder.build(from: event)
        var md = ""

        md += "# 📋 \(report.title)\n"
        md += "> **\(report.subtitle)**\n\n"

        for section in report.sections {
            md += "**\(section.label)：**<font color=\"info\">\(section.value)</font>\n"
        }

        if !report.fileTree.isEmpty {
            md += "\n**文件树：**\n```\n\(report.fileTree)\n```\n"
        }

        let payload: [String: Any] = [
            "msgtype": "markdown",
            "markdown": ["content": md] as [String: Any]
        ]

        return TemplateHelpers.serialize(payload)
    }
}
