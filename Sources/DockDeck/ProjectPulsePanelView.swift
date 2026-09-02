import Foundation
import SwiftUI

struct ProjectPulsePanelView: View {
    @ObservedObject var store: ProjectPulseStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                ProjectPulseContent(snapshot: snapshot, status: store.status, baseColor: baseColor)
            } else {
                switch store.status {
                case .notConfigured:
                    placeholder("Choose a repository", symbol: "folder.badge.plus")
                case .loading:
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Reading repository…")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(baseColor.opacity(0.78))
                case .failed(let message):
                    placeholder(message, symbol: "exclamationmark.triangle")
                case .ready:
                    placeholder("Repository unavailable", symbol: "folder.badge.questionmark")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private func placeholder(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(baseColor.opacity(0.72))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
    }
}

private struct ProjectPulseContent: View {
    let snapshot: ProjectPulseSnapshot
    let status: ProjectPulseStatus
    let baseColor: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(snapshot.git.repositoryName)
                    .fontWeight(.bold)
                    .foregroundStyle(baseColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 3)
                if case .loading = status {
                    ProgressView().controlSize(.mini)
                }
                if let activity = snapshot.githubActivity {
                    ProjectActivityMetric(
                        label: "7D", value: activity.totalContributions,
                        help: "Contributions in the last 7 days", baseColor: baseColor)
                    if activity.restrictedContributions > 0 {
                        HStack(spacing: 1.5) {
                            Image(systemName: "lock.fill")
                            Text(compactProjectValue(activity.restrictedContributions))
                        }
                        .foregroundStyle(baseColor.opacity(0.72))
                        .fixedSize()
                        .help(
                            "Restricted or private contributions: "
                                + "\(activity.restrictedContributions)")
                    }
                } else if let workflow = snapshot.workflow {
                    WorkflowBadge(workflow: workflow)
                }
            }
            if let activity = snapshot.githubActivity {
                HStack(spacing: 5) {
                    ProjectActivityMetric(
                        label: "COM", value: activity.commitContributions,
                        help: "Commit contributions", baseColor: baseColor)
                    Spacer(minLength: 2)
                    ProjectActivityMetric(
                        label: "PR", value: activity.pullRequestContributions,
                        help: "Pull requests opened", baseColor: baseColor)
                    ProjectActivityMetric(
                        label: "REV", value: activity.reviewContributions,
                        help: "Pull request reviews", baseColor: baseColor)
                    ProjectActivityMetric(
                        label: "ISS", value: activity.issueContributions,
                        help: "Issues opened", baseColor: baseColor)
                }
            } else if let github = snapshot.github {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(baseColor.opacity(0.62))
                    Text(github.defaultBranch)
                        .foregroundStyle(baseColor.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    ProjectActivityMetric(
                        label: "7D", value: github.commitsLastSevenDays,
                        help: "Commits to the default branch in the last 7 days",
                        baseColor: baseColor)
                    ProjectActivityMetric(
                        label: "PR", value: github.openPullRequests,
                        help: "Open pull requests", baseColor: baseColor)
                    ProjectActivityMetric(
                        label: "ISS", value: github.openIssues,
                        help: "Open issues", baseColor: baseColor)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(baseColor.opacity(0.62))
                    Text(snapshot.git.branch)
                        .foregroundStyle(baseColor.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 3)
                    Text(changeLabel)
                        .foregroundStyle(changeColor)
                    if !syncLabel.isEmpty {
                        Text(syncLabel)
                            .foregroundStyle(baseColor.opacity(0.7))
                    }
                }
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(helpText)
    }

    private var accessibilityTitle: String {
        if let activity = snapshot.githubActivity {
            return "GitHub activity for \(activity.login)"
        }
        return snapshot.github?.nameWithOwner ?? snapshot.git.repositoryName
    }

    private var changeLabel: String {
        if snapshot.git.conflictCount > 0 { return "!\(snapshot.git.conflictCount)" }
        return snapshot.git.changeCount == 0 ? "CLEAN" : "Δ\(snapshot.git.changeCount)"
    }

    private var changeColor: Color {
        if snapshot.git.conflictCount > 0 { return .red }
        return snapshot.git.changeCount == 0 ? .green : .orange
    }

    private var syncLabel: String {
        let ahead = snapshot.git.aheadCount > 0 ? "↑\(snapshot.git.aheadCount)" : ""
        let behind = snapshot.git.behindCount > 0 ? "↓\(snapshot.git.behindCount)" : ""
        return ahead + behind
    }

    private var helpText: String {
        if let activity = snapshot.githubActivity {
            var parts = [
                "GitHub activity for @\(activity.login)",
                "\(activity.totalContributions) contributions in the last 7 days",
                "\(activity.commitContributions) commits",
                "\(activity.pullRequestContributions) pull requests",
                "\(activity.reviewContributions) pull request reviews",
                "\(activity.issueContributions) issues",
                "commits across \(activity.repositoriesWithCommits) repositories",
            ]
            if activity.restrictedContributions > 0 {
                parts.append(
                    "\(activity.restrictedContributions) restricted or private contributions")
            }
            if case .failed(let message) = status { parts.append(message) }
            return parts.joined(separator: " · ")
        }
        if let github = snapshot.github {
            var parts = [
                github.nameWithOwner,
                github.isPrivate ? "private repository" : "public repository",
                "\(github.commitsLastSevenDays) commits in the last 7 days",
                "\(github.openPullRequests) open pull requests",
                "\(github.openIssues) open issues",
                "\(github.stargazerCount) stars, \(github.forkCount) forks",
            ]
            if let pushedAt = github.pushedAt {
                parts.append("last push \(pushedAt.formatted(date: .abbreviated, time: .shortened))")
            }
            if let headOID = github.headOID { parts.append("head \(headOID)") }
            if let workflow = snapshot.workflow { parts.append(workflow.title) }
            if case .failed(let message) = status { parts.append(message) }
            return parts.joined(separator: " · ")
        }
        let git = snapshot.git
        var parts = [
            "\(git.repositoryName) · \(git.branch)",
            "staged \(git.stagedCount), modified \(git.modifiedCount), untracked "
                + "\(git.untrackedCount), conflicts \(git.conflictCount)",
            "ahead \(git.aheadCount), behind \(git.behindCount)",
        ]
        if let workflow = snapshot.workflow { parts.append(workflow.title) }
        if case .failed(let message) = status { parts.append(message) }
        return parts.joined(separator: " · ")
    }
}

private struct ProjectActivityMetric: View {
    let label: String
    let value: Int
    let help: String
    let baseColor: Color

    var body: some View {
        HStack(spacing: 1.5) {
            Text(label)
                .foregroundStyle(baseColor.opacity(0.55))
            Text(compactValue)
                .foregroundStyle(baseColor.opacity(0.9))
        }
        .fixedSize()
        .help("\(help): \(value)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
        .accessibilityValue("\(value)")
    }

    private var compactValue: String {
        compactProjectValue(value)
    }
}

private func compactProjectValue(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

private struct WorkflowBadge: View {
    let workflow: ProjectWorkflowSnapshot

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbolName)
            Text(label)
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(color)
        .lineLimit(1)
        .help(workflow.title)
        .accessibilityLabel("GitHub Actions \(label): \(workflow.title)")
    }

    private var label: String {
        switch workflow.state {
        case .success: "PASS"
        case .failure: "FAIL"
        case .running: "RUN"
        case .queued: "WAIT"
        case .neutral: "DONE"
        case .unavailable: "N/A"
        }
    }

    private var symbolName: String {
        switch workflow.state {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .running: "circle.dotted"
        case .queued: "clock"
        case .neutral: "minus.circle"
        case .unavailable: "questionmark.circle"
        }
    }

    private var color: Color {
        switch workflow.state {
        case .success: .green
        case .failure: .red
        case .running, .queued: .blue
        case .neutral, .unavailable: Color(nsColor: .secondaryLabelColor)
        }
    }
}
