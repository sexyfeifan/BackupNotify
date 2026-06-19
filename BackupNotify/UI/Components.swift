import SwiftUI

// MARK: - StatusBadge

/// 彩色状态圆点 + 文字标签
struct StatusBadge: View {
    enum Status {
        case running
        case paused
        case error

        var color: Color {
            switch self {
            case .running: return .green
            case .paused:  return .orange
            case .error:   return .red
            }
        }

        var label: String {
            switch self {
            case .running: return "运行中"
            case .paused:  return "已暂停"
            case .error:   return "错误"
            }
        }
    }

    let status: Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
            Text(status.label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - WebhookStatusIcon

/// Webhook 发送状态图标，带 tooltip
struct WebhookStatusIcon: View {
    let name: String
    let success: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(success ? .green : .red)
                .font(.caption)
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .help(success ? "\(name)：发送成功" : "\(name)：发送失败")
    }
}

// MARK: - SizeLabel

/// 格式化文件大小显示
struct SizeLabel: View {
    let bytes: UInt64

    var body: some View {
        Text(ByteFormatter.formatBytes(bytes))
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - RelativeTimeLabel

/// 相对时间标签："刚刚" / "3分钟前" / "2小时前"
struct RelativeTimeLabel: View {
    let date: Date

    @State private var displayText: String = ""

    // 每 30 秒刷新一次显示
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(displayText)
            .font(.caption)
            .foregroundColor(.secondary)
            .onAppear { displayText = DateUtils.formatRelative(date) }
            .onReceive(timer) { _ in
                displayText = DateUtils.formatRelative(date)
            }
    }
}

// MARK: - EmptyStateView

/// 空列表占位视图
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Previews

#if DEBUG
struct Components_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StatusBadge(status: .running)
            StatusBadge(status: .paused)
            StatusBadge(status: .error)

            WebhookStatusIcon(name: "飞书", success: true)
            WebhookStatusIcon(name: "钉钉", success: false)

            SizeLabel(bytes: 1_073_741_824)

            RelativeTimeLabel(date: Date().addingTimeInterval(-7200))

            EmptyStateView(
                systemImage: "tray",
                title: "暂无记录",
                message: "备份事件将在此处显示"
            )
            .frame(height: 200)
        }
        .padding()
    }
}
#endif
