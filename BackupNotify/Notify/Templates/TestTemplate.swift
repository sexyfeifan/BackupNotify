import Foundation

/// Renders simple test messages for each platform to verify webhook connectivity.
///
/// Each platform has a different payload format; this module produces the correct
/// one-liner test message so the user can confirm the webhook endpoint works
/// before real backup events start flowing.
struct TestTemplate {

    /// Render a test message body for the given platform.
    static func render(platform: WebhookPlatform) -> Data {
        switch platform {
        case .feishu:   return renderFeishu()
        case .dingtalk: return renderDingTalk()
        case .wecom:    return renderWeCom()
        case .slack:    return renderSlack()
        case .discord:  return renderDiscord()
        case .custom:   return renderCustom()
        }
    }

    // MARK: - Feishu

    private static func renderFeishu() -> Data {
        let payload: [String: Any] = [
            "msg_type": "interactive",
            "card": [
                "header": [
                    "title": [
                        "tag": "plain_text",
                        "content": "✅ BackupNotify 连接测试"
                    ] as [String: Any],
                    "template": "blue"
                ] as [String: Any],
                "elements": [
                    [
                        "tag": "div",
                        "text": [
                            "tag": "lark_md",
                            "content": "Webhook 连接成功！\n\n当检测到新备份时，您将在此收到通知。\n\n**测试时间：** \(DateUtils.displayString(from: Date()))"
                        ] as [String: Any]
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ]
        return TemplateHelpers.serialize(payload)
    }

    // MARK: - DingTalk

    private static func renderDingTalk() -> Data {
        let payload: [String: Any] = [
            "msgtype": "markdown",
            "markdown": [
                "title": "✅ BackupNotify 连接测试",
                "text": "## ✅ BackupNotify 连接测试\n\nWebhook 连接成功！\n\n当检测到新备份时，您将在此收到通知。\n\n**测试时间：** \(DateUtils.displayString(from: Date()))\n"
            ] as [String: Any]
        ]
        return TemplateHelpers.serialize(payload)
    }

    // MARK: - WeCom

    private static func renderWeCom() -> Data {
        let payload: [String: Any] = [
            "msgtype": "markdown",
            "markdown": [
                "content": "# ✅ BackupNotify 连接测试\nWebhook 连接成功！\n当检测到新备份时，您将在此收到通知。\n**测试时间：**\(DateUtils.displayString(from: Date()))"
            ] as [String: Any]
        ]
        return TemplateHelpers.serialize(payload)
    }

    // MARK: - Slack

    private static func renderSlack() -> Data {
        let payload: [String: Any] = [
            "blocks": [
                [
                    "type": "header",
                    "text": [
                        "type": "plain_text",
                        "text": "✅ BackupNotify Connection Test",
                        "emoji": true
                    ] as [String: Any]
                ] as [String: Any],
                [
                    "type": "section",
                    "text": [
                        "type": "mrkdwn",
                        "text": "Webhook connected successfully!\n\nYou will receive notifications here when new backups are detected.\n\n*Tested at:* \(DateUtils.displayString(from: Date()))"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ]
        return TemplateHelpers.serialize(payload)
    }

    // MARK: - Discord

    private static func renderDiscord() -> Data {
        let payload: [String: Any] = [
            "embeds": [
                [
                    "title": "✅ BackupNotify Connection Test",
                    "description": "Webhook connected successfully!\n\nYou will receive notifications here when new backups are detected.",
                    "color": 3_447_003,  // Blue (#3498DB)
                    "footer": [
                        "text": "BackupNotify • Tested at \(DateUtils.displayString(from: Date()))"
                    ] as [String: Any],
                    "timestamp": DateUtils.iso8601String(from: Date())
                ] as [String: Any]
            ]
        ]
        return TemplateHelpers.serialize(payload)
    }

    // MARK: - Custom

    private static func renderCustom() -> Data {
        let payload: [String: Any] = [
            "event": "test",
            "message": "BackupNotify webhook connection test successful.",
            "timestamp": DateUtils.iso8601String(from: Date())
        ]
        return TemplateHelpers.serialize(payload)
    }
}
