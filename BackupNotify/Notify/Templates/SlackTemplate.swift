import Foundation

/// Renders a BackupEvent using Slack Block Kit.
///
/// Slack webhook format:
/// {
///   "blocks": [
///     { "type": "header", "text": { "type": "plain_text", "text": "..." } },
///     { "type": "section", "fields": [...] },
///     { "type": "divider" },
///     ...
///   ]
/// }
struct SlackTemplate: NotificationTemplate {

    static func render(event: BackupEvent) -> Data {
        var blocks: [[String: Any]] = []

        // Header
        blocks.append([
            "type": "header",
            "text": [
                "type": "plain_text",
                "text": "📹 New Backup — \(event.folderName)",
                "emoji": true
            ] as [String: Any]
        ] as [String: Any])

        // Context: timestamp
        blocks.append([
            "type": "context",
            "elements": [
                [
                    "type": "mrkdwn",
                    "text": "Detected at \(DateUtils.displayString(from: event.notifiedAt))"
                ] as [String: Any]
            ]
        ] as [String: Any])

        // Main info section
        blocks.append([
            "type": "section",
            "text": [
                "type": "mrkdwn",
                "text": "*📂 Folder:* `\(event.folderName)`\n*📁 Path:* `\(event.folderPath)`"
            ] as [String: Any]
        ] as [String: Any])

        // Fields section (two-column grid)
        blocks.append([
            "type": "section",
            "fields": [
                makeMrkdwn("*🕐 Created:*\n\(DateUtils.displayString(from: event.createdAt))"),
                makeMrkdwn("*🕐 Modified:*\n\(DateUtils.displayString(from: event.modifiedAt))"),
                makeMrkdwn("*📊 Total Size:*\n\(ByteFormatter.string(fromByteCount: event.totalSizeBytes))"),
                makeMrkdwn("*📄 Files:*\n\(event.fileCount)"),
                makeMrkdwn("*🎬 Videos:*\n\(event.videoCount)"),
                makeMrkdwn("*🎬 Video Size:*\n\(ByteFormatter.string(fromByteCount: event.videoSizeBytes))"),
            ]
        ] as [String: Any])

        // Level details
        if !event.levels.isEmpty {
            blocks.append(["type": "divider"])
            let levelsText = TemplateHelpers.formatLevelsText(event.levels, bullet: "•")
            blocks.append([
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "*📂 Sub-directories:*\n\(levelsText)"
                ] as [String: Any]
            ] as [String: Any])
        }

        let payload: [String: Any] = ["blocks": blocks]
        return TemplateHelpers.serialize(payload)
    }

    // MARK: - Helpers

    private static func makeMrkdwn(_ text: String) -> [String: Any] {
        ["type": "mrkdwn", "text": text] as [String: Any]
    }
}
