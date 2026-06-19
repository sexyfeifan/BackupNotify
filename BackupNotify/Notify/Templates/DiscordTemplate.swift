import Foundation

/// Renders a BackupEvent as a Discord webhook embed.
///
/// Discord webhook format:
/// {
///   "embeds": [{
///     "title": "...",
///     "description": "...",
///     "color": 3066993,
///     "fields": [
///       { "name": "...", "value": "...", "inline": true },
///       ...
///     ],
///     "footer": { "text": "..." },
///     "timestamp": "..."
///   }]
/// }
struct DiscordTemplate {

    /// Render the event as a Discord embed payload.
    static func render(event: BackupEvent) -> Data {
        // Build fields
        var fields: [[String: Any]] = []

        fields.append(makeField(name: "📂 Folder", value: event.folderName, inline: true))
        fields.append(makeField(name: "📁 Path", value: "`\(event.folderPath)`", inline: false))
        fields.append(makeField(
            name: "🕐 Created",
            value: DateUtils.displayString(from: event.createdAt),
            inline: true
        ))
        fields.append(makeField(
            name: "🕐 Modified",
            value: DateUtils.displayString(from: event.modifiedAt),
            inline: true
        ))
        fields.append(makeField(
            name: "📊 Total Size",
            value: ByteFormatter.string(fromByteCount: Int64(event.totalSizeBytes)),
            inline: true
        ))
        fields.append(makeField(name: "📄 Files", value: "\(event.fileCount)", inline: true))
        fields.append(makeField(name: "🎬 Videos", value: "\(event.videoCount)", inline: true))
        fields.append(makeField(
            name: "🎬 Video Size",
            value: ByteFormatter.string(fromByteCount: Int64(event.videoSizeBytes)),
            inline: true
        ))

        // Level details
        if !event.levels.isEmpty {
            let levelsText = event.levels.map { level in
                "• `\(level.relativePath)` — \(ByteFormatter.string(fromByteCount: Int64(level.sizeBytes)))"
            }.joined(separator: "\n")

            fields.append(makeField(name: "📂 Sub-directories", value: levelsText, inline: false))
        }

        // Embed object
        let embed: [String: Any] = [
            "title": "📹 New Backup — \(event.folderName)",
            "color": 3_066_993,  // Green (#2ECC71)
            "fields": fields,
            "footer": [
                "text": "BackupNotify"
            ] as [String: Any],
            "timestamp": DateUtils.iso8601String(from: event.notifiedAt)
        ]

        let payload: [String: Any] = [
            "embeds": [embed]
        ]

        return serialize(payload)
    }

    // MARK: - Helpers

    private static func makeField(name: String, value: String, inline: Bool) -> [String: Any] {
        return [
            "name": name,
            "value": value,
            "inline": inline
        ] as [String: Any]
    }

    private static func serialize(_ object: [String: Any]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return Data()
        }
        return data
    }
}
