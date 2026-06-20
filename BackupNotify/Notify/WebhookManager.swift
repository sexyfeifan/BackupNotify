import Foundation

// MARK: - WebhookManager

class WebhookManager {
    private let session: URLSession
    private let logger = Logger.shared
    private let templateEngine = TemplateEngine()

    /// Retry intervals in seconds: 5s, 15s, 30s
    private let retryIntervals: [UInt64] = [5, 15, 30]

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Send notification for a backup event to all enabled webhooks.
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
                    return await self.sendWithRetry(
                        url: webhook.url,
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

    /// Convenience: send event to webhooks derived from AppConfig.
    func send(event: BackupEvent, config: AppConfig) async throws {
        let results = await notify(event: event, webhooks: config.webhooks)
        if results.contains(where: { !$0.success }) {
            let failed = results.filter { !$0.success }.map(\.webhookName).joined(separator: ", ")
            throw WebhookError.partialFailure(failed: failed)
        }
    }

    /// Test a single webhook connection by sending a test message.
    func testWebhook(config: WebhookConfig) async -> WebhookResult {
        logger.info("Testing webhook: \(config.name) (\(config.platform.displayName))")

        let testBody = TestTemplate.render(platform: config.platform)

        return await sendWithRetry(
            url: config.url,
            body: testBody,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            webhookId: config.id,
            webhookName: config.name
        )
    }

    /// Ping a webhook URL to check connectivity (HEAD request, no body sent).
    func pingWebhook(url: String) async -> (reachable: Bool, statusCode: Int?, error: String?) {
        guard let endpoint = URL(string: url),
              let scheme = endpoint.scheme,
              ["http", "https"].contains(scheme) else {
            return (false, nil, "无效 URL")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (code < 400, code, nil)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    // MARK: - Private

    private func sendWithRetry(
        url: String,
        body: Data,
        headers: [String: String],
        webhookId: UUID,
        webhookName: String
    ) async -> WebhookResult {
        guard let endpoint = URL(string: url),
              let scheme = endpoint.scheme,
              ["http", "https"].contains(scheme) else {
            logger.error("Invalid webhook URL (missing http/https scheme)")
            return WebhookResult(
                webhookId: webhookId,
                webhookName: webhookName,
                success: false,
                statusCode: nil,
                error: "Invalid URL: must start with http:// or https://",
                sentAt: Date()
            )
        }

        var lastError: String?
        var lastStatusCode: Int?

        for attempt in 0..<(retryIntervals.count + 1) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 30
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            do {
                let (responseData, response) = try await session.data(for: request)
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                lastStatusCode = statusCode

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

            if attempt < retryIntervals.count {
                let delaySeconds = retryIntervals[attempt]
                do {
                    try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                } catch {
                    logger.info("Webhook '\(webhookName)' retry cancelled")
                    break
                }
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
}

// MARK: - WebhookError

enum WebhookError: LocalizedError {
    case partialFailure(failed: String)

    var errorDescription: String? {
        switch self {
        case .partialFailure(let failed):
            return "部分 Webhook 发送失败: \(failed)"
        }
    }
}
