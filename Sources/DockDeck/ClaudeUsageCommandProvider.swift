import Darwin
import Foundation
import SwiftTerm

protocol ClaudeUsageCommandReading: AnyObject {
    func read(now: Date) -> Result<UsageProviderSnapshot, UsageProviderError>
    func cancel()
}

enum ClaudeUsageProbeSchedule {
    static let delayRange: ClosedRange<TimeInterval> = (10 * 60)...(20 * 60)
    static let exhaustedFallbackDelay: TimeInterval = 60 * 60
    static let resetGraceDelay: TimeInterval = 30

    static func delay(unitValue: Double) -> TimeInterval {
        let unitValue = min(max(unitValue, 0), 1)
        return delayRange.lowerBound
            + ((delayRange.upperBound - delayRange.lowerBound) * unitValue)
    }

    static func nextDelay(
        proposed: TimeInterval,
        windows: [UsageWindow],
        now: Date
    ) -> TimeInterval {
        if let delay = exhaustedDelay(windows: windows, now: now) { return delay }
        guard proposed.isFinite else { return delayRange.lowerBound }
        return min(max(proposed, delayRange.lowerBound), delayRange.upperBound)
    }

    static func exhaustedDelay(windows: [UsageWindow], now: Date) -> TimeInterval? {
        let blockingWindows = windows.filter {
            $0.customLabel == nil && $0.remainingPercent <= 0
        }
        guard !blockingWindows.isEmpty else { return nil }

        let futureResets = blockingWindows.compactMap(\.resetsAt).filter { $0 > now }
        let hasUnknownReset = blockingWindows.contains { $0.resetsAt == nil }
        guard !futureResets.isEmpty || hasUnknownReset else { return nil }

        var delay = hasUnknownReset ? exhaustedFallbackDelay : 0
        if let latestReset = futureResets.max() {
            delay = max(delay, latestReset.timeIntervalSince(now) + resetGraceDelay)
        }
        return delay
    }
}

enum ClaudeBinaryLocator {
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let home = homeDirectory.path
        var candidates = [
            environment["DOCKDECK_CLAUDE_PATH"],
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
        ].compactMap { $0 }
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/claude" })
        }
        var seen: Set<String> = []
        return candidates.first {
            seen.insert($0).inserted && FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }
}

enum ClaudeUsageSnapshotMerger {
    static func merge(_ snapshots: [UsageProviderSnapshot]) -> UsageProviderSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        let ordered = snapshots.enumerated().sorted { lhs, rhs in
            if lhs.element.observedAt == rhs.element.observedAt {
                return lhs.offset < rhs.offset
            }
            return lhs.element.observedAt < rhs.element.observedAt
        }.map(\.element)

        var windowsByID: [String: UsageWindow] = [:]
        for snapshot in ordered {
            for window in snapshot.windows { windowsByID[window.id] = window }
        }
        let windows = windowsByID.values.sorted { lhs, rhs in
            switch (lhs.customLabel, rhs.customLabel) {
            case (nil, nil): lhs.durationMinutes < rhs.durationMinutes
            case (nil, _): true
            case (_, nil): false
            case (let left?, let right?): left < right
            }
        }
        guard !windows.isEmpty, let latest = ordered.last else { return nil }
        return UsageProviderSnapshot(
            windows: windows,
            freshness: latest.freshness,
            detail: latest.detail,
            observedAt: latest.observedAt)
    }
}

enum ClaudeUsageCommandParser {
    static let maximumOutputBytes = 262_144

    private enum WindowKind: CaseIterable {
        case fiveHour
        case sevenDay
        case fable

        var durationMinutes: Int {
            switch self {
            case .fiveHour: 5 * 60
            case .sevenDay: 7 * 24 * 60
            case .fable: 0
            }
        }

        var customLabel: String? { self == .fable ? "FBL" : nil }
    }

    static func parse(_ data: Data, capturedAt: Date = Date()) throws
        -> UsageProviderSnapshot
    {
        guard data.count <= maximumOutputBytes else {
            throw UsageProviderError.invalidResponse("Claude /usage output exceeds 256 KiB")
        }
        return try parse(String(decoding: data, as: UTF8.self), capturedAt: capturedAt)
    }

    static func parse(_ rawText: String, capturedAt: Date = Date()) throws
        -> UsageProviderSnapshot
    {
        let text = sanitized(rawText)
        let lowercase = text.lowercased()
        if requiresAuthentication(lowercase) {
            throw UsageProviderError.authenticationRequired("Sign in to Claude Code")
        }
        guard !text.isEmpty, !lowercase.contains("could not load usage"),
            !lowercase.contains("loading usage")
        else {
            throw UsageProviderError.invalidResponse("Claude /usage is unavailable")
        }

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let headings = lines.enumerated().compactMap { index, line in
            headingKind(for: line).map { (index, $0) }
        }
        var windows: [WindowKind: UsageWindow] = [:]
        for (offset, heading) in headings.enumerated() {
            let end = offset + 1 < headings.count ? headings[offset + 1].0 : lines.count
            let section = lines[heading.0..<min(end, heading.0 + 16)].joined(separator: "\n")
            guard let parsed = try parseWindow(
                section, kind: heading.1, capturedAt: capturedAt)
            else { continue }
            let previousReset = windows[heading.1]?.resetsAt
            windows[heading.1] = UsageWindow(
                durationMinutes: parsed.durationMinutes,
                usedPercent: parsed.usedPercent,
                resetsAt: parsed.resetsAt ?? previousReset,
                customLabel: parsed.customLabel)
        }

        let orderedWindows = WindowKind.allCases.compactMap { windows[$0] }
        guard !orderedWindows.isEmpty else {
            throw UsageProviderError.invalidResponse("Claude returned no /usage windows")
        }
        return UsageProviderSnapshot(
            windows: orderedWindows,
            freshness: .live,
            detail: "Claude /usage · \(capturedAt.formatted(date: .abbreviated, time: .shortened))",
            observedAt: capturedAt)
    }

    private static func headingKind(for line: String) -> WindowKind? {
        let line = line.lowercased()
        if line.contains("current week (fable)") || line.contains("fable limit") {
            return .fable
        }
        if line.contains("current week (all models)") || line.contains("7-day limit")
            || line.contains("7 day limit")
        {
            return .sevenDay
        }
        if line.contains("current session") || line.contains("5-hour limit")
            || line.contains("5 hour limit")
        {
            return .fiveHour
        }
        return nil
    }

    private static func parseWindow(
        _ section: String,
        kind: WindowKind,
        capturedAt: Date
    ) throws -> UsageWindow? {
        guard let percentageText = firstCapture(
            in: section, pattern: #"(\d{1,3}(?:[\.,]\d+)?)\s*%"#),
            let percentage = Double(percentageText.replacingOccurrences(of: ",", with: ".")),
            (0...100).contains(percentage)
        else { return nil }
        let lowercase = section.lowercased()
        let usedPercent = lowercase.contains("% remaining") || lowercase.contains("% left")
            ? 100 - percentage : percentage
        return UsageWindow(
            durationMinutes: kind.durationMinutes,
            usedPercent: usedPercent,
            resetsAt: resetDate(in: section, capturedAt: capturedAt),
            customLabel: kind.customLabel)
    }

    private static func resetDate(in section: String, capturedAt: Date) -> Date? {
        guard var value = firstCapture(
            in: section,
            pattern: #"(?i)resets?\s*(?:at|on)?\s*[:·\-]?\s*([^\n]{1,120})"#)
        else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let relativeUnits: [(String, TimeInterval)] = [
            (#"(?i)(\d+)\s*(?:days?|d)\b"#, 86_400),
            (#"(?i)(\d+)\s*(?:hours?|hrs?|hr|h)\b"#, 3_600),
            (#"(?i)(\d+)\s*(?:minutes?|mins?|min|m)\b"#, 60),
            (#"(?i)(\d+)\s*(?:seconds?|secs?|sec|s)\b"#, 1),
        ]
        var relative: TimeInterval = 0
        for (pattern, multiplier) in relativeUnits {
            if let component = firstCapture(in: value, pattern: pattern).flatMap(Double.init) {
                relative += component * multiplier
            }
        }
        if relative > 0, relative <= 8 * 24 * 60 * 60 {
            return capturedAt.addingTimeInterval(relative)
        }

        if let date = ISO8601DateFormatter().date(from: value) {
            return validated(date, capturedAt: capturedAt)
        }

        let timeZone = firstCapture(in: value, pattern: #"\(([^\)\n]{1,64})\)\s*$"#)
            .flatMap(TimeZone.init(identifier:)) ?? .current
        value = replacing(
            pattern: #"\s*\([^\)\n]{1,64}\)\s*$"#, in: value, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dateFormats = [
            "MMM d, yyyy 'at' h:mma", "MMM d yyyy 'at' h:mma",
            "MMM d, yyyy 'at' ha", "MMM d yyyy 'at' ha",
            "MMM d 'at' h:mma", "MMM d 'at' ha",
            "MMM d, yyyy 'at' h:mm a", "MMM d yyyy 'at' h:mm a",
            "MMM d 'at' h:mm a", "MMM d 'at' h a",
        ]
        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            formatter.defaultDate = capturedAt
            formatter.isLenient = false
            guard var date = formatter.date(from: value) else { continue }
            if !format.contains("yyyy"), date < capturedAt.addingTimeInterval(-60),
                let nextYear = Calendar(identifier: .gregorian).date(
                    byAdding: .year, value: 1, to: date)
            {
                date = nextYear
            }
            if let result = validated(date, capturedAt: capturedAt) { return result }
        }

        guard let time = firstCapture(
            in: value,
            pattern: #"(?i)^\s*((?:[01]?\d|2[0-3]):[0-5]\d\s*(?:am|pm)?|(?:1[0-2]|0?[1-9])\s*(?:am|pm))\s*$"#)
        else { return nil }
        let timeFormats = ["h:mma", "h:mm a", "ha", "h a", "HH:mm"]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        for format in timeFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            formatter.defaultDate = capturedAt
            formatter.isLenient = false
            guard let parsed = formatter.date(from: time),
                let today = calendar.date(
                    bySettingHour: calendar.component(.hour, from: parsed),
                    minute: calendar.component(.minute, from: parsed), second: 0,
                    of: capturedAt)
            else { continue }
            let date = today < capturedAt.addingTimeInterval(-60)
                ? calendar.date(byAdding: .day, value: 1, to: today) : today
            if let date, let result = validated(date, capturedAt: capturedAt) { return result }
        }
        return nil
    }

    private static func validated(_ date: Date, capturedAt: Date) -> Date? {
        let range = capturedAt.addingTimeInterval(-60)...capturedAt.addingTimeInterval(8 * 86_400)
        return range.contains(date) ? date : nil
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    fileprivate static func requiresAuthentication(_ lowercaseText: String) -> Bool {
        [
            "not logged in", "login required", "please log in", "sign in to claude",
            "oauth authorization expired", "authentication failed", "invalid api key",
        ].contains { lowercaseText.contains($0) }
    }

    private static func replacing(
        pattern: String, in text: String, with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    private static func sanitized(_ rawText: String) -> String {
        var text = rawText.replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        for pattern in [
            #"\u001B\][^\u0007]*(?:\u0007|\u001B\\)"#,
            #"\u001B\[[0-?]*[ -/]*[@-~]"#,
            #"[\u0000-\u0008\u000B\u000C\u000E-\u001A\u001C-\u001F]"#,
        ] {
            text = replacing(pattern: pattern, in: text, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class ClaudeUsageCommandProvider: ClaudeUsageCommandReading {
    private enum ProbeFailure: Error {
        case retryable(String)
        case cancelled
    }

    private static let directTimeout: TimeInterval = 10
    private static let ptyTimeout: TimeInterval = 16

    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: URL
    private let probeDirectory: URL
    private let lock = NSLock()
    private var operationID: UUID?
    private var activeProcess: Process?
    private var activeTerminal: HeadlessTerminal?

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        probeDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.probeDirectory = probeDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DockDeck", isDirectory: true)
                .appendingPathComponent("ClaudeProbe", isDirectory: true)
    }

    func read(now: Date = Date()) -> Result<UsageProviderSnapshot, UsageProviderError> {
        guard let executable = ClaudeBinaryLocator.locate(
            environment: environment, homeDirectory: homeDirectory)
        else {
            return .failure(.claudeExecutableNotFound)
        }
        do {
            try prepareProbeDirectory()
        } catch {
            return .failure(.transport("Could not prepare Claude probe directory"))
        }

        let operation = UUID()
        begin(operation)
        defer { finish(operation) }

        do {
            let directSession = UUID()
            defer { cleanupSessionArtifact(directSession) }
            do {
                let output = try runDirect(
                    executable: executable, sessionID: directSession, operation: operation)
                return .success(try ClaudeUsageCommandParser.parse(output, capturedAt: now))
            } catch ProbeFailure.cancelled {
                throw ProbeFailure.cancelled
            } catch let error as UsageProviderError {
                if case .authenticationRequired = error { return .failure(error) }
            } catch {
                guard isCurrent(operation) else { throw ProbeFailure.cancelled }
            }

            guard isCurrent(operation) else { throw ProbeFailure.cancelled }
            let ptySession = UUID()
            defer { cleanupSessionArtifact(ptySession) }
            let screen = try runPTY(
                executable: executable, sessionID: ptySession, operation: operation)
            return .success(try ClaudeUsageCommandParser.parse(screen, capturedAt: now))
        } catch let error as UsageProviderError {
            return .failure(error)
        } catch ProbeFailure.cancelled {
            return .failure(.transport("Claude /usage refresh cancelled"))
        } catch ProbeFailure.retryable(let message) {
            return .failure(.transport(message))
        } catch {
            return .failure(.transport("Could not read Claude /usage"))
        }
    }

    func cancel() {
        let process: Process?
        let terminal: HeadlessTerminal?
        lock.lock()
        operationID = nil
        process = activeProcess
        terminal = activeTerminal
        activeProcess = nil
        activeTerminal = nil
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
        terminal?.process.terminate()
    }

    private func runDirect(
        executable: URL, sessionID: UUID, operation: UUID
    ) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let output = ClaudeUsageOutputBuffer(limit: ClaudeUsageCommandParser.maximumOutputBytes)
        let collector = ClaudeUsagePipeCollector(
            handles: [outputPipe.fileHandleForReading, errorPipe.fileHandleForReading],
            output: output)
        process.executableURL = executable
        process.arguments = launchArguments(sessionID: sessionID, command: "/usage")
        process.environment = launchEnvironment(executable: executable)
        process.currentDirectoryURL = probeDirectory
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
        } catch {
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            collector.finish()
            throw error
        }
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        register(process, operation: operation)
        defer {
            collector.finish()
            clear(process, operation: operation)
        }
        guard isCurrent(operation) else {
            process.terminate()
            throw ProbeFailure.cancelled
        }

        if terminated.wait(timeout: .now() + Self.directTimeout) == .timedOut {
            process.terminate()
            if terminated.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 1)
            }
            throw ProbeFailure.retryable("Claude /usage timed out")
        }
        collector.finish()
        guard isCurrent(operation) else { throw ProbeFailure.cancelled }
        let result = output.value()
        guard !result.exceededLimit else {
            throw UsageProviderError.invalidResponse("Claude /usage output exceeds 256 KiB")
        }
        return result.data
    }

    private func runPTY(
        executable: URL, sessionID: UUID, operation: UUID
    ) throws -> Data {
        let queue = DispatchQueue(label: "DockDeck.ClaudeUsagePTY")
        let ended = DispatchSemaphore(value: 0)
        let options = TerminalOptions(
            cols: 160, rows: 140, scrollback: 0,
            enableSixelReported: false, kittyImageCacheLimitBytes: 1_048_576)
        let terminal = HeadlessTerminal(queue: queue, options: options) { _ in ended.signal() }
        register(terminal, operation: operation)
        terminal.process.startProcess(
            executable: executable.path,
            args: launchArguments(sessionID: sessionID, command: nil),
            environment: launchEnvironment(executable: executable).map { "\($0.key)=\($0.value)" },
            currentDirectory: probeDirectory.path)
        defer {
            terminal.process.terminate()
            clear(terminal, operation: operation)
        }

        let startedAt = Date()
        var commandSentAt: Date?
        var parsedAt: Date?
        while Date().timeIntervalSince(startedAt) < Self.ptyTimeout {
            guard isCurrent(operation) else { throw ProbeFailure.cancelled }
            let screen = queue.sync {
                terminal.terminal.getBufferAsData()
            }
            let text = String(decoding: screen, as: UTF8.self)
            let lowercase = text.lowercased()
            if lowercase.contains("quick safety check:")
                || lowercase.contains("trust this folder")
            {
                throw UsageProviderError.invalidResponse(
                    "Claude PTY fallback requires workspace trust")
            }
            if ClaudeUsageCommandParser.requiresAuthentication(lowercase) {
                throw UsageProviderError.authenticationRequired("Sign in to Claude Code")
            }

            if commandSentAt == nil,
                text.contains("❯") || Date().timeIntervalSince(startedAt) >= 3
            {
                terminal.send("/usage\r")
                commandSentAt = Date()
            }
            if commandSentAt != nil,
                (try? ClaudeUsageCommandParser.parse(screen)) != nil
            {
                if parsedAt == nil { parsedAt = Date() }
                if Date().timeIntervalSince(parsedAt!) >= 0.6 {
                    terminal.send(data: [0x1b][...])
                    Thread.sleep(forTimeInterval: 0.15)
                    terminal.send("/exit\r")
                    _ = ended.wait(timeout: .now() + 1)
                    return screen
                }
            }
            if !terminal.process.running { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw ProbeFailure.retryable("Claude PTY /usage timed out")
    }

    private func launchArguments(sessionID: UUID, command: String?) -> [String] {
        var arguments = [
            "--safe-mode", "--tools", "", "--allowed-tools", "",
            "--session-id", sessionID.uuidString.lowercased(),
        ]
        if let command { arguments.append(command) }
        return arguments
    }

    private func launchEnvironment(executable: URL) -> [String: String] {
        var result = environment
        for key in result.keys where key.hasPrefix("ANTHROPIC_")
            || key.hasPrefix("CLAUDE_CODE_OAUTH_TOKEN")
        {
            result.removeValue(forKey: key)
        }
        result["DISABLE_AUTOUPDATER"] = "1"
        result["FORCE_COLOR"] = "0"
        result["NO_COLOR"] = "1"
        result["LANG"] = "en_US.UTF-8"
        result["LC_ALL"] = "en_US.UTF-8"
        result["PWD"] = probeDirectory.path
        let executableDirectory = executable.deletingLastPathComponent().path
        let path = result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        if !path.split(separator: ":").contains(Substring(executableDirectory)) {
            result["PATH"] = "\(executableDirectory):\(path)"
        }
        return result
    }

    private func prepareProbeDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: probeDirectory.path, isDirectory: &isDirectory) {
            let values = try probeDirectory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard isDirectory.boolValue, values.isDirectory == true,
                values.isSymbolicLink != true
            else { throw UsageProviderError.invalidResponse("Unsafe Claude probe directory") }
        } else {
            try fileManager.createDirectory(
                at: probeDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: probeDirectory.path)
    }

    private func cleanupSessionArtifact(_ sessionID: UUID) {
        let encodedDirectory = probeDirectory.path.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 48...57, 65...90, 97...122: Character(scalar)
            default: "-"
            }
        }
        let projectDirectory = homeDirectory
            .appendingPathComponent(".claude/projects", isDirectory: true)
            .appendingPathComponent(String(encodedDirectory), isDirectory: true)
        let artifact = projectDirectory.appendingPathComponent(
            "\(sessionID.uuidString.lowercased()).jsonl")

        // ponytail: Claude can flush its session file just after the CLI exits. Retry this
        // exact random session briefly; replace this with a no-persistence CLI flag if added.
        for attempt in 0..<6 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.1) }
            guard let values = try? artifact.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                values.isRegularFile == true, values.isSymbolicLink != true
            else { continue }
            try? fileManager.removeItem(at: artifact)
        }
        if (try? fileManager.contentsOfDirectory(atPath: projectDirectory.path).isEmpty) == true {
            try? fileManager.removeItem(at: projectDirectory)
        }
    }

    private func begin(_ operation: UUID) {
        cancel()
        lock.withLock { operationID = operation }
    }

    private func finish(_ operation: UUID) {
        lock.withLock {
            guard operationID == operation else { return }
            operationID = nil
            activeProcess = nil
            activeTerminal = nil
        }
    }

    private func isCurrent(_ operation: UUID) -> Bool {
        lock.withLock { operationID == operation }
    }

    private func register(_ process: Process, operation: UUID) {
        lock.withLock {
            if operationID == operation { activeProcess = process }
        }
    }

    private func clear(_ process: Process, operation: UUID) {
        lock.withLock {
            if operationID == operation, activeProcess === process { activeProcess = nil }
        }
    }

    private func register(_ terminal: HeadlessTerminal, operation: UUID) {
        lock.withLock {
            if operationID == operation { activeTerminal = terminal }
        }
    }

    private func clear(_ terminal: HeadlessTerminal, operation: UUID) {
        lock.withLock {
            if operationID == operation, activeTerminal === terminal { activeTerminal = nil }
        }
    }
}

private final class ClaudeUsagePipeCollector {
    private struct Reader {
        let handle: FileHandle
        let source: DispatchSourceRead
    }

    private let queue = DispatchQueue(label: "DockDeck.ClaudeUsagePipeCollector")
    private let cancellationGroup = DispatchGroup()
    private let output: ClaudeUsageOutputBuffer
    private let lock = NSLock()
    private var readers: [Reader] = []
    private var finished = false

    init(handles: [FileHandle], output: ClaudeUsageOutputBuffer) {
        self.output = output
        readers = handles.map { handle in
            let descriptor = handle.fileDescriptor
            let flags = fcntl(descriptor, F_GETFL)
            if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }
            let source = DispatchSource.makeReadSource(
                fileDescriptor: descriptor, queue: queue)
            cancellationGroup.enter()
            source.setEventHandler { [weak self] in self?.drain(descriptor) }
            source.setCancelHandler { [cancellationGroup] in cancellationGroup.leave() }
            source.resume()
            return Reader(handle: handle, source: source)
        }
    }

    func finish() {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !finished else { return false }
            finished = true
            return true
        }
        guard shouldFinish else { return }
        queue.sync {
            for reader in readers {
                drain(reader.handle.fileDescriptor)
                reader.source.cancel()
            }
        }
        _ = cancellationGroup.wait(timeout: .now() + 1)
        readers.forEach { try? $0.handle.close() }
    }

    private func drain(_ descriptor: Int32) {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count > 0 {
                output.append(Data(bytes.prefix(count)))
            } else if count == -1, errno == EINTR {
                continue
            } else {
                return
            }
        }
    }
}

private final class ClaudeUsageOutputBuffer {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var exceededLimit = false

    init(limit: Int) { self.limit = limit }

    func append(_ value: Data) {
        lock.withLock {
            guard !value.isEmpty else { return }
            let remaining = max(limit - data.count, 0)
            data.append(value.prefix(remaining))
            if value.count > remaining { exceededLimit = true }
        }
    }

    func value() -> (data: Data, exceededLimit: Bool) {
        lock.withLock { (data, exceededLimit) }
    }
}
