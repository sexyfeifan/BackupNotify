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
struct SlackTemplate {

    /// Render the event as a Slack Block Kit payload.
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
                [
                    "type": "mrkdwn",
                    "text": "*🕐 Created:*\n\(DateUtils.displayString(from: event.createdAt))"
                ] as [String: Any],
                [
                    "type": "mrkdwn",
                    "text": "*🕐 Modified:*\n\(DateUtils.displayString(from: event.modifiedAt))"
                ] as [String: Any],
                [
                    "type": "mrkdwn",
                    "text": "*📊 Total Size:*\n\(ByteFormatter.string(fromByteCount: Int64(event.totalSizeBytes)))"
                ] as [String: Any],
                [
                    "type": "mrkdwn",
                    "text": "*📄 Files:*\n\(event.fileCount)"
                ] as [String: Any],
                [
                    "type": "mrkdwn",
                    "text": "*🎬 Videos:*\n\(event.videoCount)"
                ] as [String: Any],
                [
                    "type": "mrkdwn",
                    "text": "*🎬 Video Size:*\n\(ByteFormatter.string(fromByteCount: Int64(event.videoSizeBytes)))"
                ] as [String: Any]
            ]
        ] as [String: Any])

        // Level details
        if !event.levels.isEmpty {
            blocks.append(["type": "divider"])

            let levelsText = event.levels.map { level in
                "• `\(level.relativePath)` — \(ByteFormatter.string(fromByteCount: Int64(level.sizeBytes)))"
            }.joined(separator: "\n")

            blocks.append([
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "*📂 Sub-directories:*\n\(levelsText)"
                ] as [String: Any]
            ] as [String: Any])
        }

        let payload: [String: Any] = [
            "blocks": blocks
        ]

        return serialize(payload)
    }

    private static func serialize(_ object: [String: Any]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return Data()
        }
        return data
    }
}
