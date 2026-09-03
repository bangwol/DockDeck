import SwiftUI

struct GitHubInboxPanelView: View {
    @ObservedObject var store: GitHubInboxStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HStack(spacing: 5) {
                    metric("NEW", snapshot.unreadCount, color: .cyan)
                    metric("@", snapshot.mentionCount, color: .mint)
                    metric("REV", snapshot.reviewRequestCount, color: .orange)
                    if snapshot.actionsRepository != nil {
                        metric("FAIL", snapshot.failedRunsLastSevenDays, color: .red)
                    } else {
                        metric("CI", snapshot.ciNotificationCount, color: .purple)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .help(helpText(snapshot))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("GitHub Inbox")
                .accessibilityValue(helpText(snapshot))
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func metric(_ title: String, _ value: Int?, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(value.map(compactCount) ?? "--")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(baseColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        HStack(spacing: 7) {
            if case .loading = store.status {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "bell.slash")
            }
            Text(placeholderText)
                .lineLimit(2)
        }
        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
        .foregroundStyle(baseColor.opacity(0.78))
        .padding(.horizontal, 9)
    }

    private var placeholderText: String {
        switch store.status {
        case .loading: "Loading GitHub Inbox"
        case .ready: "GitHub Inbox unavailable"
        case .unavailable(let message): message
        }
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }

    private func compactCount(_ value: Int) -> String {
        switch value {
        case 1_000...: String(format: "%.1fK", Double(value) / 1_000)
        default: String(max(value, 0))
        }
    }

    private func helpText(_ snapshot: GitHubInboxSnapshot) -> String {
        var parts = [
            "\(snapshot.unreadCount) unread notifications",
            "\(snapshot.mentionCount) mentions",
            "\(snapshot.reviewRequestCount) review requests",
        ]
        if let repository = snapshot.actionsRepository,
            let failures = snapshot.failedRunsLastSevenDays
        {
            parts.append("\(failures) failed Actions runs in \(repository) over 7 days")
        } else {
            parts.append("\(snapshot.ciNotificationCount) CI notifications")
        }
        if case .unavailable(let message) = store.status {
            parts.append("Last refresh failed: \(message)")
        }
        return parts.joined(separator: ", ")
    }
}
