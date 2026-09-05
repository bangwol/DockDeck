import Foundation

// Fixed categories only: never retain executable paths, arguments, or output.
enum ProcessDiagnosticSource: String, CaseIterable {
    case customTile = "Custom Tiles", docker = "Docker", diagnostics = "Integration Checks"
    case quickAction = "Quick Actions", other = "Other Commands"
}

struct ProcessDiagnosticMetric {
    let source: ProcessDiagnosticSource
    var lastDuration: TimeInterval = 0
    var lastSuccessfulAt: Date?
    var timeouts = 0
    var cancellations = 0
}

final class ProcessDiagnostics {
    static let shared = ProcessDiagnostics()
    private let lock = NSLock()
    private var metrics: [ProcessDiagnosticSource: ProcessDiagnosticMetric] = [:]

    func record(source: ProcessDiagnosticSource, duration: TimeInterval,
                failure: BoundedProcessError?, now: Date = Date()) {
        lock.withLock {
            var item = metrics[source] ?? ProcessDiagnosticMetric(source: source)
            item.lastDuration = duration.isFinite ? max(duration, 0) : 0
            if failure == nil { item.lastSuccessfulAt = now }
            if failure == .timedOut { item.timeouts = min(item.timeouts + 1, 999_999) }
            if failure == .cancelled { item.cancellations = min(item.cancellations + 1, 999_999) }
            metrics[source] = item
        }
    }

    func snapshot() -> [ProcessDiagnosticMetric] {
        lock.withLock { ProcessDiagnosticSource.allCases.compactMap { metrics[$0] } }
    }
}
