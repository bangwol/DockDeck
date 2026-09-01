import Foundation

enum ClaudeRateLimitParser {
    struct Cache: Decodable {
        let observedAt: TimeInterval?
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case observedAt
            case observedAtSnake = "observed_at"
            case rateLimits = "rate_limits"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            observedAt =
                try container.decodeIfPresent(TimeInterval.self, forKey: .observedAt)
                ?? container.decodeIfPresent(TimeInterval.self, forKey: .observedAtSnake)
            rateLimits = try container.decodeIfPresent(RateLimits.self, forKey: .rateLimits)
        }
    }

    struct RateLimits: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    struct Window: Decodable {
        let usedPercentage: Double?
        let resetsAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    static func snapshot(
        from data: Data, modificationDate: Date?, now: Date = Date()
    ) throws -> UsageProviderSnapshot {
        let cache: Cache
        do {
            cache = try JSONDecoder().decode(Cache.self, from: data)
        } catch {
            throw UsageProviderError.invalidResponse(
                "Claude bridge cache is invalid: \(error.localizedDescription)")
        }
        guard let rateLimits = cache.rateLimits else {
            throw UsageProviderError.invalidResponse(
                "Claude bridge cache has no rate_limits object")
        }

        let candidates: [(Int, Window?)] = [
            (5 * 60, rateLimits.fiveHour),
            (7 * 24 * 60, rateLimits.sevenDay),
        ]
        let windows = candidates.compactMap { duration, window -> UsageWindow? in
            guard let window, let usedPercentage = window.usedPercentage else { return nil }
            return UsageWindow(
                durationMinutes: duration,
                usedPercent: min(max(usedPercentage, 0), 100),
                resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:)))
        }
        guard !windows.isEmpty else {
            throw UsageProviderError.invalidResponse("Claude returned no quota windows")
        }

        let observedAt = cache.observedAt.map(Date.init(timeIntervalSince1970:)) ?? modificationDate
        let observationIsOld = observedAt.map { now.timeIntervalSince($0) > 10 * 60 } ?? true
        let resetHasPassed = windows.contains { window in
            window.resetsAt.map { $0 <= now } ?? false
        }
        let freshness: UsageFreshness =
            observationIsOld || resetHasPassed ? .stale : .live
        return UsageProviderSnapshot(
            windows: windows,
            freshness: freshness,
            detail: observedAt.map { "Observed \($0.formatted(date: .abbreviated, time: .shortened))" })
    }
}

final class ClaudeStatuslineCacheProvider {
    let cacheURL: URL
    private let maximumCacheBytes = 65_536

    init(cacheURL: URL? = nil) {
        if let cacheURL {
            self.cacheURL = cacheURL
        } else if let override = ProcessInfo.processInfo.environment[
            "DOCKDECK_CLAUDE_CACHE_PATH"], !override.isEmpty
        {
            self.cacheURL = URL(fileURLWithPath: override)
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.cacheURL = applicationSupport
                .appendingPathComponent("DockDeck", isDirectory: true)
                .appendingPathComponent("claude-rate-limits.json")
        }
    }

    func read(now: Date = Date()) -> Result<UsageProviderSnapshot, UsageProviderError> {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return .failure(.bridgeNotInstalled)
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
            if let size = attributes[.size] as? NSNumber,
                size.intValue > maximumCacheBytes
            {
                return .failure(.invalidResponse("Claude bridge cache exceeds 64 KiB"))
            }
            let data = try Data(contentsOf: cacheURL, options: [.mappedIfSafe])
            let modificationDate = attributes[.modificationDate] as? Date
            return .success(
                try ClaudeRateLimitParser.snapshot(
                    from: data, modificationDate: modificationDate, now: now))
        } catch let error as UsageProviderError {
            return .failure(error)
        } catch {
            return .failure(.transport(
                "Could not read Claude bridge cache: \(error.localizedDescription)"))
        }
    }
}
