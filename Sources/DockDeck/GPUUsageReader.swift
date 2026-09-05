import Foundation
import IOKit

enum GPUUsageReader {
    static func read() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var maximum: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service,
                "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                let statistics = property as? [String: Any],
                let value = utilization(statistics) else { continue }
            maximum = max(maximum ?? value, value)
        }
        return maximum
    }

    static func utilization(_ statistics: [String: Any]) -> Double? {
        // ponytail: the driver dictionary is not a public metric contract. Show
        // unavailable if absent; replace with a public system GPU API when offered.
        guard let number = statistics["Device Utilization %"] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite && (0...100).contains(value) ? value : nil
    }
}
