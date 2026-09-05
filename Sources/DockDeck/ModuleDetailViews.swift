import SwiftUI

struct UsageModuleDetailView: View {
    @ObservedObject var store: UsageStore
    let theme: Theme

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                ForEach(store.providers) { provider in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(provider.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(store.refreshPlan(for: provider.id))
                                if let observedAt = provider.observedAt {
                                    Text("Updated \(observedAt.formatted(date: .abbreviated, time: .shortened))")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let label = provider.freshness.label {
                                Text(label)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(freshnessColor(provider.freshness))
                            }
                            Button(action: store.refresh) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh usage")
                            .accessibilityLabel("Refresh usage")
                        }
                        if let detail = provider.detail, !provider.windows.isEmpty,
                            provider.freshness != .live
                        {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if provider.windows.isEmpty {
                            Text(provider.detail ?? "Usage data is not available yet")
                                .font(.caption)
                                .foregroundStyle(baseColor.opacity(0.62))
                        } else {
                            ForEach(provider.windows) { window in
                                usageRow(window)
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        baseColor.opacity(0.065),
                        in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .moduleDetailSurface()
    }

    private func usageRow(_ window: UsageWindow) -> some View {
        let mode = PanelSettings.usageDisplayMode
        let value = mode.value(for: window)
        return VStack(spacing: 4) {
            HStack {
                Text(window.customLabel == "FBL" ? "Fable" : window.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(value.rounded()))% \(mode.rawValue)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text("·")
                    .foregroundStyle(baseColor.opacity(0.35))
                Text(UsageResetFormatter.compactString(for: window.resetsAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(baseColor.opacity(0.65))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(baseColor.opacity(0.12))
                    Capsule()
                        .fill(usageMeterColor(for: window, normal: baseColor))
                        .frame(width: proxy.size.width * CGFloat(value / 100))
                }
            }
            .frame(height: 5)
        }
        .help(UsageResetFormatter.helpText(for: window))
        .accessibilityElement(children: .combine)
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }
    private func freshnessColor(_ freshness: UsageFreshness) -> Color {
        switch freshness {
        case .live: .green
        case .loading, .stale: .orange
        case .signIn, .unavailable, .setupRequired: .red
        }
    }
}

struct SystemStatsModuleDetailView: View {
    @ObservedObject var store: SystemStatsStore
    let theme: Theme

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(store.selectedMetrics) { metric in
                    metricCard(metric)
                }
            }
        }
        .moduleDetailSurface()
    }

    private func metricCard(_ metric: SystemStatsMetric) -> some View {
        let history = store.history(for: metric)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(metric.title, systemImage: metric.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(baseColor.opacity(0.72))
                Spacer()
                Text(value(for: metric))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            if history.samples.count >= 2 {
                MetricSparkline(samples: history.samples, color: color(for: metric))
                    .frame(height: 22)
            } else {
                Capsule()
                    .fill(color(for: metric).opacity(0.22))
                    .frame(height: 4)
            }
        }
        .padding(10)
        .background(baseColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    private func value(for metric: SystemStatsMetric) -> String {
        switch metric {
        case .cpu:
            return percent(store.snapshot.cpuPercent)
        case .memory:
            return percent(store.snapshot.memoryPercent)
        case .disk:
            return percent(store.snapshot.diskPercent)
        case .network:
            return "↓\(ByteRateFormatter.compactString(store.snapshot.downloadBytesPerSecond)) "
                + "↑\(ByteRateFormatter.compactString(store.snapshot.uploadBytesPerSecond))"
        case .thermal:
            return store.snapshot.temperatureCelsius.map {
                "\(Int($0.rounded()))°C"
            } ?? store.snapshot.thermalPressure?.accessibilityTitle ?? "--"
        }
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "--"
    }

    private func color(for metric: SystemStatsMetric) -> Color {
        switch metric {
        case .cpu, .memory, .disk: .cyan
        case .network: .mint
        case .thermal:
            switch store.snapshot.thermalPressure {
            case .nominal: .mint
            case .fair: .yellow
            case .serious: .orange
            case .critical: .red
            case nil: .secondary
            }
        }
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }
}

struct ServiceMonitorModuleDetailView: View {
    @ObservedObject var store: ServiceMonitorStore
    let theme: Theme

    var body: some View {
        Group {
            if store.items.isEmpty {
                Label("Add HTTPS services in Settings", systemImage: "plus.circle")
                    .foregroundStyle(baseColor.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.items) { item in
                            serviceRow(item)
                        }
                    }
                }
            }
        }
        .moduleDetailSurface()
    }

    private func serviceRow(_ item: ServiceMonitorItem) -> some View {
        let history = store.latencyHistory(for: item.id)
        return HStack(spacing: 10) {
            Circle()
                .fill(color(item.state))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.endpoint.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(item.state.detail)
                    .font(.caption)
                    .foregroundStyle(baseColor.opacity(0.72))
                    .textSelection(.enabled)
                if let start = item.outageStartedAt {
                    Text("Last failure began \(start.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let end = item.outageEndedAt {
                        Text("Recovered after \(end.timeIntervalSince(start).formatted(.number.precision(.fractionLength(0)))) seconds")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Recovery not yet observed · \(start, style: .relative)")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if let successfulAt = item.lastSuccessfulAt {
                    Text("Last OK \(successfulAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let p50 = history.percentile(0.5), let p95 = history.percentile(0.95) {
                Text("p50 \(Int(p50.rounded())) · p95 \(Int(p95.rounded())) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(baseColor.opacity(0.68))
            }
        }
        .padding(10)
        .frame(minHeight: 44)
        .background(baseColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    private func color(_ state: ServiceMonitorState) -> Color {
        switch state {
        case .idle, .checking, .offline: .secondary
        case .up: .green
        case .degraded: .orange
        case .down: .red
        }
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }
}

struct ScheduleModuleDetailView: View {
    @ObservedObject var store: ScheduleStore
    let theme: Theme

    var body: some View {
        Group {
            if !store.canReadAnySource {
                Label(
                    "Grant Calendar or Reminders access in Settings",
                    systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(baseColor.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.events.isEmpty && store.reminders.isEmpty {
                Label("No upcoming items", systemImage: "calendar")
                    .foregroundStyle(baseColor.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.events.prefix(6)) { event in eventRow(event) }
                        ForEach(store.reminders.prefix(6)) { reminder in reminderRow(reminder) }
                    }
                }
            }
        }
        .moduleDetailSurface()
    }

    private func eventRow(_ event: ScheduleEventItem) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(eventSubtitle(event))
                    .font(.caption)
                    .foregroundStyle(baseColor.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer()
            if let joinURL = event.joinURL {
                Link(destination: joinURL) {
                    Image(systemName: "video.fill")
                }
                .buttonStyle(.borderless)
                .help("Join meeting")
            }
        }
        .moduleDetailRow(baseColor)
    }

    private func reminderRow(_ reminder: ScheduleReminderItem) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checklist")
                .foregroundStyle(reminder.dueDate <= Date() ? .orange : .mint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(dateTime(reminder.dueDate)) · \(reminder.listTitle)")
                    .font(.caption)
                    .foregroundStyle(baseColor.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer()
        }
        .moduleDetailRow(baseColor)
    }

    private func eventSubtitle(_ event: ScheduleEventItem) -> String {
        let time = event.isAllDay
            ? event.startDate.formatted(date: .abbreviated, time: .omitted)
            : "\(dateTime(event.startDate))–\(event.endDate.formatted(date: .omitted, time: .shortened))"
        return "\(time) · \(event.calendarTitle)"
    }

    private func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }
}

struct ProjectPulseModuleDetailView: View {
    @ObservedObject var store: ProjectPulseStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(projectTitle(snapshot))
                                    .font(.callout.weight(.bold))
                                Text(projectSubtitle(snapshot))
                                    .font(.caption)
                                    .foregroundStyle(baseColor.opacity(0.62))
                            }
                            Spacer()
                            if let workflow = snapshot.workflow {
                                Text(workflow.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 95))], spacing: 7
                        ) {
                            ForEach(metrics(snapshot), id: \.title) { metric in
                                DetailValueCard(
                                    title: metric.title, value: metric.value,
                                    color: metric.color, baseColor: baseColor)
                            }
                        }
                        if case .failed(let message) = store.status {
                            Label(
                                "Showing saved data — \(message)",
                                systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } else {
                Label(projectPlaceholder, systemImage: "folder.badge.questionmark")
                    .foregroundStyle(baseColor.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .moduleDetailSurface()
    }

    private func projectTitle(_ snapshot: ProjectPulseSnapshot) -> String {
        snapshot.githubActivity.map { "@\($0.login)" }
            ?? snapshot.github?.nameWithOwner
            ?? snapshot.git.repositoryName
    }

    private func projectSubtitle(_ snapshot: ProjectPulseSnapshot) -> String {
        if snapshot.githubActivity != nil { return "GitHub activity · last 7 days" }
        return snapshot.github?.defaultBranch ?? snapshot.git.branch
    }

    private func metrics(_ snapshot: ProjectPulseSnapshot) -> [DetailMetricValue] {
        if let activity = snapshot.githubActivity {
            return [
                .init("Contributions", activity.totalContributions, .cyan),
                .init("Commits", activity.commitContributions, .mint),
                .init("Pull requests", activity.pullRequestContributions, .orange),
                .init("Reviews", activity.reviewContributions, .purple),
                .init("Issues", activity.issueContributions, .yellow),
                .init("Repositories", activity.repositoriesWithCommits, .blue),
            ]
        }
        if let github = snapshot.github {
            return [
                .init("7-day commits", github.commitsLastSevenDays, .cyan),
                .init("Open PRs", github.openPullRequests, .orange),
                .init("Open issues", github.openIssues, .yellow),
                .init("Stars", github.stargazerCount, .mint),
                .init("Forks", github.forkCount, .purple),
            ]
        }
        let git = snapshot.git
        return [
            .init("Staged", git.stagedCount, .mint),
            .init("Modified", git.modifiedCount, .orange),
            .init("Untracked", git.untrackedCount, .cyan),
            .init("Conflicts", git.conflictCount, .red),
            .init("Ahead", git.aheadCount, .blue),
            .init("Behind", git.behindCount, .purple),
        ]
    }

    private var projectPlaceholder: String {
        switch store.status {
        case .notConfigured: "Choose a repository in Settings"
        case .loading: "Reading repository"
        case .failed(let message): message
        case .ready: "Repository unavailable"
        }
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }
}

struct DockerModuleDetailView: View {
    @ObservedObject var store: DockerStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 82))], spacing: 7
                    ) {
                        DetailValueCard(
                            title: "Running", value: "\(snapshot.runningCount)",
                            color: .green, baseColor: baseColor)
                        DetailValueCard(
                            title: "Stopped", value: "\(snapshot.stoppedCount)",
                            color: .secondary, baseColor: baseColor)
                        DetailValueCard(
                            title: "Unhealthy", value: "\(snapshot.unhealthyCount)",
                            color: .red, baseColor: baseColor)
                        DetailValueCard(
                            title: "CPU", value: percent(snapshot.cpuPercent),
                            color: .cyan, baseColor: baseColor)
                        DetailValueCard(
                            title: "Memory", value: memory(snapshot.memoryBytes),
                            color: .orange, baseColor: baseColor)
                    }
                    if !snapshot.containers.isEmpty {
                        Text("Running containers · highest CPU first · up to 50")
                            .font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(snapshot.containers) { container in
                                    HStack {
                                        Text(container.name).lineLimit(1).help(container.name)
                                        Spacer()
                                        Text(percent(container.cpuPercent)).frame(width: 75, alignment: .trailing)
                                        Text(memory(container.memoryBytes)).frame(width: 90, alignment: .trailing)
                                    }
                                    .font(.callout).monospacedDigit()
                                    .padding(8)
                                    .background(baseColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(container.name), CPU \(percent(container.cpuPercent)), memory \(memory(container.memoryBytes))")
                                }
                            }
                        }
                    } else {
                        Text(snapshot.runningCount == 0 ? "No running containers" : "Individual metrics unavailable")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Updated \(snapshot.observedAt.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(baseColor.opacity(0.55))
                        Spacer()
                        if case .unavailable(let message) = store.status {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }
            } else {
                Label(dockerPlaceholder, systemImage: "shippingbox")
                    .foregroundStyle(baseColor.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .moduleDetailSurface()
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0) } ?? "--"
    }

    private func memory(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0,
            value < Double(Int64.max)
        else { return "--" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(value.rounded()), countStyle: .memory)
    }

    private var dockerPlaceholder: String {
        switch store.status {
        case .loading: "Loading Docker"
        case .ready: "Docker unavailable"
        case .unavailable(let message): message
        }
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }
}

struct MusicModuleDetailView: View {
    @ObservedObject var store: MusicStore
    let theme: Theme

    var body: some View {
        VStack(spacing: 14) {
            if let track = store.snapshot?.track {
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 42, height: 42)
                        .background(baseColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist + albumSuffix(track.album))
                            .font(.caption)
                            .foregroundStyle(baseColor.opacity(0.62))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(store.snapshot?.state.title ?? "Stopped")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.pink)
                }
                progress(track)
            } else {
                Label(placeholder, systemImage: placeholderSymbol)
                    .foregroundStyle(baseColor.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                Button(action: { store.send(.previous) }) {
                    Label("Previous", systemImage: "backward.end.fill")
                }
                .disabled(!store.canControl)
                Button(action: { store.send(.playPause) }) {
                    Label(playPauseTitle, systemImage: playPauseSymbol)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canControl)
                Button(action: { store.send(.next) }) {
                    Label("Next", systemImage: "forward.end.fill")
                }
                .disabled(!store.canControl)
                Spacer()
                if store.status == .permissionRequired || store.status == .notRunning {
                    Button("Connect", action: store.requestAccess)
                } else {
                    Button("Open Music", action: store.openMusic)
                }
            }
            .controlSize(.regular)
        }
        .moduleDetailSurface()
    }

    private func progress(_ track: MusicTrackSnapshot) -> some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(baseColor.opacity(0.12))
                    Capsule()
                        .fill(.pink)
                        .frame(width: proxy.size.width * CGFloat(track.progress ?? 0))
                }
            }
            .frame(height: 5)
            HStack {
                Text(time(track.position))
                Spacer()
                Text(time(track.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(baseColor.opacity(0.58))
        }
    }

    private func albumSuffix(_ album: String?) -> String {
        album.map { " · \($0)" } ?? ""
    }

    private func time(_ interval: TimeInterval?) -> String {
        guard let interval else { return "--:--" }
        let seconds = max(Int(interval.rounded(.down)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var placeholder: String {
        switch store.status {
        case .checking: "Checking Music"
        case .notRunning: "Open and connect the macOS Music app"
        case .permissionRequired: "Connect Music in Settings"
        case .permissionDenied: "Allow DockDeck in macOS Automation settings"
        case .ready: "Nothing playing"
        case .unavailable: "Music automation unavailable"
        }
    }

    private var placeholderSymbol: String {
        switch store.status {
        case .permissionDenied, .unavailable: "exclamationmark.triangle"
        case .permissionRequired: "lock"
        case .notRunning: "power"
        default: "music.note"
        }
    }

    private var playPauseTitle: String {
        store.snapshot?.state.isPlaying == true ? "Pause" : "Play"
    }

    private var playPauseSymbol: String {
        store.snapshot?.state.isPlaying == true ? "pause.fill" : "play.fill"
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }
}

private struct DetailMetricValue {
    let title: String
    let value: String
    let color: Color

    init(_ title: String, _ value: Int, _ color: Color) {
        self.title = title
        self.value = "\(value)"
        self.color = color
    }
}

private struct DetailValueCard: View {
    let title: String
    let value: String
    let color: Color
    let baseColor: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(baseColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(baseColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }
}

struct CustomTileModuleDetailView: View {
    @ObservedObject var store: CustomTileStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = store.snapshot {
                    Text(snapshot.content.title).font(.headline)
                    Text(snapshot.content.value).font(.title2).textSelection(.enabled)
                    if let detail = snapshot.content.detail {
                        Text(detail).textSelection(.enabled)
                    }
                    Text("Last success: \(snapshot.observedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(store.statusDescription)
                    .foregroundStyle(store.isStale ? Color.orange : .secondary)
                Button("Run again", action: store.refresh)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .moduleDetailSurface()
    }
}

private extension View {
    func moduleDetailSurface() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.12)))
    }

    func moduleDetailRow(_ baseColor: Color) -> some View {
        padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(baseColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .combine)
    }
}
