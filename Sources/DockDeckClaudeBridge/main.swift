import Darwin
import Foundation

enum ClaudeBridgePayload {
    static func observationTime(
        from input: Data,
        fallback: TimeInterval,
        fileModificationDate: (String) -> Date? = { path in
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            else { return nil }
            return attributes[.modificationDate] as? Date
        }
    ) -> TimeInterval {
        guard
            let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
            let transcriptPath = root["transcript_path"] as? String,
            !transcriptPath.isEmpty,
            let modificationDate = fileModificationDate(transcriptPath)
        else { return fallback }
        return min(modificationDate.timeIntervalSince1970, fallback)
    }

    static func cacheData(from input: Data, observedAt: TimeInterval) throws -> Data? {
        guard let root = try JSONSerialization.jsonObject(with: input) as? [String: Any],
            let rateLimits = root["rate_limits"] as? [String: Any]
        else {
            return nil
        }
        return try JSONSerialization.data(
            withJSONObject: [
                "observed_at": observedAt,
                "rate_limits": rateLimits,
            ],
            options: [.sortedKeys])
    }

    static func statusLine(from input: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
            let rateLimits = root["rate_limits"] as? [String: Any]
        else {
            return "Claude usage pending"
        }
        let fields: [(String, String)] = [
            ("5h", "five_hour"), ("7d", "seven_day"),
            // ponytail: replace these aliases when Anthropic documents a Fable status-line key.
            ("FBL", rateLimits["seven_day_fable"] == nil ? "fable" : "seven_day_fable"),
        ]
        let segments = fields.compactMap { label, key -> String? in
            guard let window = rateLimits[key] as? [String: Any],
                let percentage = window["used_percentage"] as? NSNumber
            else {
                return nil
            }
            let remaining = min(max(100 - percentage.doubleValue, 0), 100)
            return "\(label) \(Int(remaining.rounded()))% left"
        }
        return segments.isEmpty ? "Claude usage pending" : "Claude " + segments.joined(separator: " · ")
    }
}

enum ClaudeBridgeRuntime {
    static let maximumInputBytes = 1_048_576

    static func cacheURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["DOCKDECK_CLAUDE_CACHE_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("DockDeck", isDirectory: true)
            .appendingPathComponent("claude-rate-limits.json")
    }

    static func writeCache(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func runPassthrough(arguments: [String], input: Data) throws -> Int32? {
        guard let first = arguments.first else { return nil }

        let process = Process()
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        if first == "--passthrough-shell", arguments.count >= 2 {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", arguments[1]]
        } else if first == "--", arguments.count >= 2 {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = Array(arguments.dropFirst())
        } else {
            throw UsageError.invalidArguments
        }

        try process.run()
        try inputPipe.fileHandleForWriting.write(contentsOf: input)
        try inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    enum UsageError: LocalizedError {
        case inputTooLarge
        case invalidArguments

        var errorDescription: String? {
            switch self {
            case .inputTooLarge:
                "Claude status-line input exceeds 1 MiB"
            case .invalidArguments:
                "Use --passthrough-shell <command> or -- <executable> [arguments]"
            }
        }
    }
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard input.count <= ClaudeBridgeRuntime.maximumInputBytes else {
    FileHandle.standardError.write(
        Data("dockdeck-claude-bridge: Claude status-line input exceeds 1 MiB\n".utf8))
    exit(1)
}

do {
    let now = Date().timeIntervalSince1970
    if let cache = try ClaudeBridgePayload.cacheData(
        from: input,
        observedAt: ClaudeBridgePayload.observationTime(from: input, fallback: now))
    {
        try ClaudeBridgeRuntime.writeCache(cache, to: ClaudeBridgeRuntime.cacheURL())
    }

    let arguments = Array(CommandLine.arguments.dropFirst())
    if let status = try ClaudeBridgeRuntime.runPassthrough(arguments: arguments, input: input) {
        exit(status)
    }
    FileHandle.standardOutput.write(Data((ClaudeBridgePayload.statusLine(from: input) + "\n").utf8))
} catch {
    FileHandle.standardError.write(
        Data("dockdeck-claude-bridge: \(error.localizedDescription)\n".utf8))
    exit(1)
}
