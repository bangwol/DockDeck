import SwiftUI

struct GitHubInboxPanelView: View {
    @ObservedObject var store: GitHubInboxStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                VStack(spacing: 2) {
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
                    .frame(maxHeight: .infinity)
                    if let entry = snapshot.entries.first {
                        notificationLine(entry)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
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
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(value.map(compactGitHubCount) ?? "--")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(baseColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func notificationLine(_ entry: GitHubInboxEntry) -> some View {
        HStack(spacing: 4) {
            Text(entry.reasonLabel)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(githubReasonColor(entry.reason))
                .fixedSize()
            Text(entry.repositoryName)
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                .foregroundStyle(baseColor.opacity(0.62))
                .lineLimit(1)
                .frame(maxWidth: 44)
            Text(entry.title)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(baseColor.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: 12)
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
        if let entry = snapshot.entries.first {
            parts.append("\(entry.reasonLabel.lowercased()) in \(entry.repository): \(entry.title)")
        }
        if case .unavailable(let message) = store.status {
            parts.append("Last refresh failed: \(message)")
        }
        return parts.joined(separator: ", ")
    }
}

struct GitHubInboxDetailView: View {
    @ObservedObject var store: GitHubInboxStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        summary("Unread", snapshot.unreadCount, color: .cyan)
                        summary("Mentions", snapshot.mentionCount, color: .mint)
                        summary("Reviews", snapshot.reviewRequestCount, color: .orange)
                        summary(
                            snapshot.actionsRepository == nil ? "CI" : "Failures",
                            snapshot.actionsRepository == nil
                                ? snapshot.ciNotificationCount
                                : snapshot.failedRunsLastSevenDays,
                            color: snapshot.actionsRepository == nil ? .purple : .red)
                    }
                    Divider().opacity(0.5)
                    if snapshot.entries.isEmpty {
                        Text("No unread notification messages")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(baseColor.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 5) {
                                ForEach(snapshot.entries) { entry in
                                    detailRow(entry)
                                }
                            }
                        }
                    }
                    if case .unavailable(let message) = store.status {
                        Label("Showing saved data — \(message)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                GitHubInboxPanelView(store: store, theme: theme)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.12)))
    }

    private func summary(_ title: String, _ value: Int?, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(color)
            Text(value.map(compactGitHubCount) ?? "--")
                .foregroundStyle(baseColor)
                .monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(baseColor.opacity(0.08), in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private func detailRow(_ entry: GitHubInboxEntry) -> some View {
        Group {
            if let webURL = entry.webURL {
                Link(destination: webURL) {
                    detailRowContent(entry, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .help("Open on GitHub")
                .accessibilityHint("Opens in your default browser")
            } else {
                detailRowContent(entry, showsDisclosure: false)
            }
        }
    }

    private func detailRowContent(
        _ entry: GitHubInboxEntry, showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Text(entry.reasonLabel)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(githubReasonColor(entry.reason))
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(entry.repository)
                    if let updatedAt = entry.updatedAt {
                        Text("·")
                        Text(updatedAt, style: .relative)
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(baseColor.opacity(0.58))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(baseColor.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(baseColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }
}

private func compactGitHubCount(_ value: Int) -> String {
    switch value {
    case 1_000...: String(format: "%.1fK", Double(value) / 1_000)
    default: String(max(value, 0))
    }
}

private func githubReasonColor(_ reason: String) -> Color {
    switch reason {
    case "review_requested": .orange
    case "mention", "team_mention": .mint
    case "ci_activity": .purple
    case "assign": .yellow
    default: .cyan
    }
}
