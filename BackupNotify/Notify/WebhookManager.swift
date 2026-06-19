import Foundation
import os

class WebhookManager {
    private let session: URLSession
    private let logger = Logger(subsystem: "com.backupnotify", category: "WebhookManager")
    private let templateEngine = TemplateEngine()

    /// Retry intervals in seconds: 5s, 15s, 30s
    private let retryIntervals: [UInt64] = [5, 15, 30]

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Send notification for a backup event to all enabled webhooks.
    /// Returns an array of results, one per webhook attempted.
    func notify(event: BackupEvent, webhooks: [WebhookConfig]) async -> [WebhookResult] {
        let enabled = webhooks.filter { $0.enabled }
        guard !enabled.isEmpty else {
            logger.info("No enabled webhooks to notify for event \(event.id)")
            return []
        }

        logger.info("Sending notifications to \(enabled.count) webhook(s) for backup: \(event.folderName)")

        return await withTaskGroup(of: WebhookResult.self, returning: [WebhookResult].self) { group in
            for webhook in enabled {
                group.addTask { [self] in
                    let rendered = self.templateEngine.render(
                        event: event,
                        platform: webhook.platform,
                        customTemplate: webhook.customTemplate
                    )
                    // The rendered URL is the platform default; prefer the config URL
                    let targetURL = webhook.url

                    return await self.sendWithRetry(
                        url: targetURL,
                        body: rendered.body,
                        headers: rendered.headers,
                        webhookId: webhook.id,
                        webhookName: webhook.name
                    )
                }
            }

            var results: [WebhookResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Test a single webhook connection by sending a test message.
    func testWebhook(config: WebhookConfig) async -> WebhookResult {
        logger.info("Testing webhook: \(config.name) (\(config.platform.displayName))")

        let testBody = TestTemplate.render(platform: config.platform)
        let headers = defaultHeaders(for: config.platform)

        return await sendWithRetry(
            url: config.url,
            body: testBody,
            headers: headers,
            webhookId: config.id,
            webhookName: config.name
        )
    }

    // MARK: - Private

    /// Send to a single webhook with retry logic.
    /// Attempts up to 3 times with intervals of 5s, 15s, 30s.
    private func sendWithRetry(
        url: String,
        body: Data,
        headers: [String: String],
        webhookId: UUID,
        webhookName: String
    ) async -> WebhookResult {
        guard let endpoint = URL(string: url) else {
            logger.error("Invalid webhook URL: \(url)")
            return WebhookResult(
                webhookId: webhookId,
                webhookName: webhookName,
                success: false,
                statusCode: nil,
                error: "Invalid URL: \(url)",
                sentAt: Date()
            )
        }

        var lastError: String?
        var lastStatusCode: Int?

        for attempt in 0..<retryIntervals.count + 1 {
            // Build request
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 30
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            do {
                let (responseData, response) = try await session.data(for: request)
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                lastStatusCode = statusCode

                // Treat 2xx as success
                if (200..<300).contains(statusCode) {
                    logger.info("Webhook '\(webhookName)' succeeded (HTTP \(statusCode)) on attempt \(attempt + 1)")
                    return WebhookResult(
                        webhookId: webhookId,
                        webhookName: webhookName,
                        success: true,
                        statusCode: statusCode,
                        error: nil,
                        sentAt: Date()
                    )
                }

                // Some platforms return non-2xx with a JSON body indicating success
                if let bodyString = String(data: responseData, encoding: .utf8) {
                    lastError = "HTTP \(statusCode): \(bodyString)"
                } else {
                    lastError = "HTTP \(statusCode)"
                }

                logger.warning("Webhook '\(webhookName)' attempt \(attempt + 1) failed: HTTP \(statusCode)")

            } catch {
                lastError = error.localizedDescription
                logger.warning("Webhook '\(webhookName)' attempt \(attempt + 1) error: \(error.localizedDescription)")
            }

            // Wait before retry (skip wait on last attempt)
            if attempt < retryIntervals.count {
                let delaySeconds = retryIntervals[attempt]
                logger.debug("Retrying webhook '\(webhookName)' in \(delaySeconds)s...")
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }

        logger.error("Webhook '\(webhookName)' failed after all retry attempts")
        return WebhookResult(
            webhookId: webhookId,
            webhookName: webhookName,
            success: false,
            statusCode: lastStatusCode,
            error: lastError ?? "Unknown error",
            sentAt: Date()
        )
    }

    /// Default Content-Type headers per platform (supplements the default application/json).
    private func defaultHeaders(for platform: WebhookPlatform) -> [String: String] {
        // Most platforms accept plain application/json.
        // Platforms that need special headers can be added here.
        switch platform {
        case .feishu, .dingtalk, .wecom, .slack, .discord, .custom:
            return [:]
        }
    }
}
