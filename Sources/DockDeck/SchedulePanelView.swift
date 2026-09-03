import SwiftUI

struct SchedulePanelView: View {
    @ObservedObject var store: ScheduleStore
    let theme: Theme

    var body: some View {
        Group {
            if !store.canReadAnySource {
                placeholder(
                    text: authorizationText,
                    symbol: "calendar.badge.exclamationmark")
            } else if store.events.isEmpty && store.reminders.isEmpty {
                placeholder(
                    text: store.status == .loading ? "Loading schedule" : "No upcoming items",
                    symbol: store.status == .loading ? "arrow.clockwise" : "calendar")
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let presentation = ScheduleAgendaTimeline.presentation(
                        events: store.events, reminders: store.reminders, now: context.date)
                    {
                        switch presentation {
                        case .event(let eventPresentation):
                            event(eventPresentation, now: context.date)
                        case .reminder(let reminderPresentation):
                            reminder(reminderPresentation, now: context.date)
                        }
                    } else {
                        placeholder(text: "No upcoming items", symbol: "calendar")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func reminder(
        _ presentation: ScheduleReminderPresentation, now: Date
    ) -> some View {
        let item = presentation.reminder
        let overdue = presentation.mode == .overdue
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(overdue ? "DUE" : "TODO")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(reminderColor(overdue: overdue).opacity(0.24)))
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(reminderRelativeText(item, now: now))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(baseColor.opacity(0.76))
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(baseColor.opacity(0.14))
                    if overdue {
                        Capsule()
                            .fill(reminderColor(overdue: true))
                            .frame(width: proxy.size.width)
                    }
                }
            }
            .frame(height: 3)

            HStack(spacing: 5) {
                Text(reminderTimeText(item))
                Text("·")
                Text(item.listTitle).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 7.5, weight: .medium, design: .rounded))
            .foregroundStyle(baseColor.opacity(0.66))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .help(reminderAccessibilitySummary(presentation, now: now))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(reminderAccessibilitySummary(presentation, now: now))
    }

    private func event(_ presentation: SchedulePresentation, now: Date) -> some View {
        let item = presentation.event
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(presentation.mode == .current ? "NOW" : "NEXT")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(badgeColor(presentation.mode).opacity(0.24)))
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .lineLimit(1)
                if let joinURL = item.joinURL {
                    Link(destination: joinURL) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Join meeting on \(joinURL.host ?? "conference service")")
                    .accessibilityLabel("Join \(item.title)")
                }
                Spacer(minLength: 2)
                Text(relativeText(presentation, now: now))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(baseColor.opacity(0.76))
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(baseColor.opacity(0.14))
                    Capsule()
                        .fill(badgeColor(presentation.mode))
                        .frame(
                            width: proxy.size.width
                                * CGFloat(presentation.mode == .current
                                    ? presentation.progress : 0))
                }
            }
            .frame(height: 3)

            HStack(spacing: 5) {
                Text(timeText(item))
                Text("·")
                Text(item.calendarTitle).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 7.5, weight: .medium, design: .rounded))
            .foregroundStyle(baseColor.opacity(0.66))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .help(accessibilitySummary(presentation, now: now))
        .accessibilityElement(children: item.joinURL == nil ? .ignore : .contain)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilitySummary(presentation, now: now))
    }

    private func placeholder(text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(baseColor.opacity(0.78))
            .padding(.horizontal, 10)
            .accessibilityElement(children: .combine)
    }

    private var authorizationText: String {
        "Grant Calendar or Reminders access in Settings"
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private func badgeColor(_ mode: SchedulePresentationMode) -> Color {
        mode == .current ? .green : Color.accentColor
    }

    private func reminderColor(overdue: Bool) -> Color {
        overdue ? .orange : Color.accentColor
    }

    private func relativeText(_ presentation: SchedulePresentation, now: Date) -> String {
        let seconds = presentation.mode == .current
            ? presentation.event.endDate.timeIntervalSince(now)
            : presentation.event.startDate.timeIntervalSince(now)
        let prefix = presentation.mode == .current ? "" : "in "
        let suffix = presentation.mode == .current ? " left" : ""
        return prefix + durationText(max(seconds, 0)) + suffix
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "<1m" }
        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    private func timeText(_ event: ScheduleEventItem) -> String {
        if event.isAllDay { return "All day" }
        return "\(Self.timeFormatter.string(from: event.startDate))–"
            + Self.timeFormatter.string(from: event.endDate)
    }

    private func reminderRelativeText(_ reminder: ScheduleReminderItem, now: Date) -> String {
        let seconds = reminder.dueDate.timeIntervalSince(now)
        return seconds <= 0
            ? durationText(abs(seconds)) + " late"
            : "in " + durationText(seconds)
    }

    private func reminderTimeText(_ reminder: ScheduleReminderItem) -> String {
        if reminder.isAllDay { return Self.dateFormatter.string(from: reminder.dueDate) }
        return Self.dueFormatter.string(from: reminder.dueDate)
    }

    private func accessibilitySummary(
        _ presentation: SchedulePresentation, now: Date
    ) -> String {
        let state = presentation.mode == .current ? "Current event" : "Next event"
        return "\(state), \(timeText(presentation.event)), "
            + "\(relativeText(presentation, now: now)), "
            + presentation.event.calendarTitle
    }

    private func reminderAccessibilitySummary(
        _ presentation: ScheduleReminderPresentation, now: Date
    ) -> String {
        let state = presentation.mode == .overdue ? "Overdue reminder" : "Upcoming reminder"
        return "\(state), \(reminderTimeText(presentation.reminder)), "
            + "\(reminderRelativeText(presentation.reminder, now: now)), "
            + presentation.reminder.listTitle
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}
