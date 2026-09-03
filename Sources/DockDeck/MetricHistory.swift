import Foundation
import SwiftUI

struct MetricSample: Equatable, Identifiable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

struct MetricHistory: Equatable {
    static let retentionInterval: TimeInterval = 15 * 60
    static let maximumSampleCount = 900

    private(set) var samples: [MetricSample] = []

    mutating func append(_ value: Double?, at timestamp: Date = Date()) {
        guard let value, value.isFinite, value >= 0 else { return }
        if let last = samples.last, timestamp < last.timestamp {
            samples.removeAll(keepingCapacity: true)
        }
        samples.append(MetricSample(timestamp: timestamp, value: value))
        let cutoff = timestamp.addingTimeInterval(-Self.retentionInterval)
        samples.removeAll { $0.timestamp < cutoff }
        if samples.count > Self.maximumSampleCount {
            samples.removeFirst(samples.count - Self.maximumSampleCount)
        }
    }

    func percentile(_ quantile: Double) -> Double? {
        guard !samples.isEmpty, quantile.isFinite else { return nil }
        let values = samples.map(\.value).sorted()
        let position = min(max(quantile, 0), 1) * Double(values.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else { return values[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return values[lowerIndex] + (values[upperIndex] - values[lowerIndex]) * fraction
    }
}

struct MetricSparkline: View {
    let samples: [MetricSample]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule().fill(color.opacity(0.10))
                if samples.count >= 2 {
                    path(in: proxy.size)
                        .stroke(
                            color,
                            style: StrokeStyle(
                                lineWidth: 1.15, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func path(in size: CGSize) -> Path {
        let values = samples.map(\.value)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let range = maximum - minimum
        let firstDate = samples.first?.timestamp.timeIntervalSinceReferenceDate ?? 0
        let lastDate = samples.last?.timestamp.timeIntervalSinceReferenceDate ?? firstDate
        let duration = lastDate - firstDate

        var path = Path()
        for (index, sample) in samples.enumerated() {
            let xFraction = duration > 0
                ? (sample.timestamp.timeIntervalSinceReferenceDate - firstDate) / duration
                : Double(index) / Double(max(samples.count - 1, 1))
            let yFraction = range > 0 ? (sample.value - minimum) / range : 0.5
            let point = CGPoint(
                x: size.width * CGFloat(min(max(xFraction, 0), 1)),
                y: size.height * CGFloat(1 - min(max(yFraction, 0), 1)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
