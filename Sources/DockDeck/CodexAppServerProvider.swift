import Foundation

enum CodexRateLimitParser {
    struct Envelope: Decodable {
        let id: Int?
        let method: String?
        let result: ResultPayload?
        let params: UpdatePayload?
        let error: RPCError?
    }

    struct ResultPayload: Decodable {
        let rateLimits: Bucket?
        let rateLimitsByLimitId: [String: Bucket]?
    }

    struct UpdatePayload: Decodable {
        let rateLimits: Bucket?
    }

    struct Bucket: Decodable {
        let limitId: String?
        let limitName: String?
        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let windowDurationMins: Int?
        let resetsAt: TimeInterval?
    }

    struct RPCError: Decodable {
        let code: Int?
        let message: String
    }

    static func decodeEnvelope(_ data: Data) throws -> Envelope {
        try JSONDecoder().decode(Envelope.self, from: data)
    }

    static func snapshot(from result: ResultPayload) throws -> UsageProviderSnapshot {
        let bucket =
            result.rateLimitsByLimitId?["codex"]
            ?? result.rateLimits
            ?? result.rateLimitsByLimitId?.values.first
        guard let bucket else {
            throw UsageProviderError.invalidResponse("Codex returned no rate-limit bucket")
        }
        return try snapshot(from: bucket)
    }

    static func snapshot(from bucket: Bucket) throws -> UsageProviderSnapshot {
        let windows = [bucket.primary, bucket.secondary]
            .compactMap { $0 }
            .compactMap(makeUsageWindow)
            .sorted { $0.durationMinutes < $1.durationMinutes }
        guard !windows.isEmpty else {
            throw UsageProviderError.invalidResponse("Codex returned no quota windows")
        }
        let detail = [bucket.limitName, bucket.planType]
            .compactMap { $0 }
            .joined(separator: " · ")
        return UsageProviderSnapshot(
            windows: windows,
            freshness: .live,
            detail: detail.isEmpty ? nil : detail)
    }

    private static func makeUsageWindow(_ window: Window) -> UsageWindow? {
        guard let usedPercent = window.usedPercent,
            let durationMinutes = window.windowDurationMins,
            durationMinutes > 0
        else {
            return nil
        }
        return UsageWindow(
            durationMinutes: durationMinutes,
            usedPercent: min(max(usedPercent, 0), 100),
            resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:)))
    }
}

enum CodexBinaryLocator {
    static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var paths: [String] = []
        if let override = environment["DOCKDECK_CODEX_PATH"], !override.isEmpty {
            paths.append(override)
        }
        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.bun/bin/codex",
        ])

        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            paths.append(
                contentsOf: versions.sorted(by: isNewerVersion).map {
                    "\(nvmRoot)/\($0)/bin/codex"
                })
        }

        var seen = Set<String>()
        return paths.first { path in
            seen.insert(path).inserted && FileManager.default.isExecutableFile(atPath: path)
        }.map(URL.init(fileURLWithPath:))
    }

    private static func isNewerVersion(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split(separator: ".").compactMap { Int($0) }
        let right = rhs.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart != rightPart { return leftPart > rightPart }
        }
        return lhs > rhs
    }

    static func launchEnvironment(
        for executableURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = environment
        let executableDirectory = executableURL.deletingLastPathComponent().path
        let path = environment["PATH"] ?? "/usr/bin:/bin"
        let entries = path.split(separator: ":").map(String.init)
        if !entries.contains(executableDirectory) {
            environment["PATH"] = "\(executableDirectory):\(path)"
        }
        return environment
    }
}

final class CodexAppServerProvider {
    typealias UpdateHandler = (Result<UsageProviderSnapshot, UsageProviderError>) -> Void

    private let queue = DispatchQueue(label: "DockDeck.CodexAppServer")
    private let configuredExecutableURL: URL?
    private let maximumMessageBytes = 1_048_576
    private let requestTimeout: TimeInterval = 10
    private let restartDelays: [TimeInterval] = [60, 120, 300]

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var handler: UpdateHandler?
    private var pendingRateLimitID: Int?
    private var pendingTimeout: DispatchWorkItem?
    private var restartWorkItem: DispatchWorkItem?
    private var restartIndex = 0
    private var nextRequestID = 1
    private var active = false

    init(executableURL: URL? = nil) {
        configuredExecutableURL = executableURL
    }

    func start(handler: @escaping UpdateHandler) {
        queue.async { [weak self] in
            guard let self else { return }
            self.handler = handler
            self.active = true
            self.launchIfNeeded()
        }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self, self.active else { return }
            if self.process?.isRunning == true {
                self.sendRateLimitReadIfNeeded()
            } else if self.restartWorkItem == nil {
                self.launchIfNeeded()
            }
        }
    }

    func stop() {
        queue.sync {
            self.active = false
            self.restartWorkItem?.cancel()
            self.restartWorkItem = nil
            self.pendingTimeout?.cancel()
            self.pendingTimeout = nil
            self.pendingRateLimitID = nil
            let process = self.process
            self.clearProcessState()
            if process?.isRunning == true { process?.terminate() }
        }
    }

    private func launchIfNeeded() {
        guard active, process?.isRunning != true else { return }
        guard let executableURL = configuredExecutableURL ?? CodexBinaryLocator.locate() else {
            handler?(.failure(.executableNotFound))
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.environment = CodexBinaryLocator.launchEnvironment(for: executableURL)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async {
                self?.consume(data)
            }
        }
        let errorHandle = errorPipe.fileHandleForReading
        errorHandle.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        process.terminationHandler = { [weak self, weak process] terminated in
            guard let process else { return }
            self?.queue.async {
                self?.processTerminated(process, status: terminated.terminationStatus)
            }
        }

        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        outputBuffer.removeAll(keepingCapacity: true)
        nextRequestID = 1

        do {
            try process.run()
            try send([
                "method": "initialize",
                "id": nextID(),
                "params": [
                    "clientInfo": [
                        "name": "dockdeck",
                        "title": "DockDeck",
                        "version": "0.1.0",
                    ]
                ],
            ])
            try send(["method": "initialized", "params": [:]])
            sendRateLimitReadIfNeeded()
        } catch {
            failTransport("Could not start Codex app-server: \(error.localizedDescription)")
        }
    }

    private func sendRateLimitReadIfNeeded() {
        guard pendingRateLimitID == nil, process?.isRunning == true else { return }
        let id = nextID()
        do {
            try send(["method": "account/rateLimits/read", "id": id])
            pendingRateLimitID = id
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.pendingRateLimitID == id else { return }
                self.pendingRateLimitID = nil
                self.pendingTimeout = nil
                self.handler?(.failure(.transport("Codex rate-limit request timed out")))
            }
            pendingTimeout = timeout
            queue.asyncAfter(deadline: .now() + requestTimeout, execute: timeout)
        } catch {
            failTransport("Could not request Codex rate limits: \(error.localizedDescription)")
        }
    }

    private func send(_ object: [String: Any]) throws {
        guard let inputHandle else {
            throw UsageProviderError.transport("Codex app-server stdin is unavailable")
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else {
            outputHandle?.readabilityHandler = nil
            return
        }
        outputBuffer.append(data)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            guard outputBuffer.distance(from: outputBuffer.startIndex, to: newline)
                <= maximumMessageBytes
            else {
                failTransport("Codex app-server message exceeded 1 MiB")
                return
            }
            var line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            guard !line.isEmpty else { continue }
            handleLine(line)
        }

        if outputBuffer.count > maximumMessageBytes {
            failTransport("Codex app-server message exceeded 1 MiB")
        }
    }

    private func handleLine(_ data: Data) {
        guard let envelope = try? CodexRateLimitParser.decodeEnvelope(data) else { return }

        if envelope.id == pendingRateLimitID {
            pendingTimeout?.cancel()
            pendingTimeout = nil
            pendingRateLimitID = nil

            if let rpcError = envelope.error {
                let message = rpcError.message
                if message.localizedCaseInsensitiveContains("auth")
                    || message.localizedCaseInsensitiveContains("login")
                {
                    handler?(.failure(.authenticationRequired(message)))
                } else {
                    handler?(.failure(.invalidResponse(message)))
                }
                return
            }
            guard let result = envelope.result else {
                handler?(.failure(.invalidResponse("Codex returned an empty response")))
                return
            }
            do {
                let snapshot = try CodexRateLimitParser.snapshot(from: result)
                restartIndex = 0
                handler?(.success(snapshot))
            } catch let error as UsageProviderError {
                handler?(.failure(error))
            } catch {
                handler?(.failure(.invalidResponse(error.localizedDescription)))
            }
            return
        }

        if envelope.method == "account/rateLimits/updated",
            let bucket = envelope.params?.rateLimits
        {
            do {
                handler?(.success(try CodexRateLimitParser.snapshot(from: bucket)))
            } catch let error as UsageProviderError {
                handler?(.failure(error))
            } catch {
                handler?(.failure(.invalidResponse(error.localizedDescription)))
            }
        }
    }

    private func processTerminated(_ terminated: Process, status: Int32) {
        guard process === terminated else { return }
        clearProcessState()
        guard active else { return }
        handler?(.failure(.transport("Codex app-server exited with status \(status)")))
        scheduleRestart()
    }

    private func failTransport(_ message: String) {
        handler?(.failure(.transport(message)))
        let process = process
        clearProcessState()
        if process?.isRunning == true { process?.terminate() }
        if active { scheduleRestart() }
    }

    private func clearProcessState() {
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        outputHandle = nil
        errorHandle = nil
        inputHandle = nil
        process = nil
        outputBuffer.removeAll(keepingCapacity: false)
        pendingTimeout?.cancel()
        pendingTimeout = nil
        pendingRateLimitID = nil
    }

    private func scheduleRestart() {
        guard restartWorkItem == nil else { return }
        let delay = restartDelays[min(restartIndex, restartDelays.count - 1)]
        restartIndex = min(restartIndex + 1, restartDelays.count - 1)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWorkItem = nil
            self.launchIfNeeded()
        }
        restartWorkItem = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func nextID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }
}
