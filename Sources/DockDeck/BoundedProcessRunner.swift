import Darwin
import Foundation

enum BoundedProcessError: Error, Equatable {
    case launchFailed
    case timedOut
    case outputTooLarge
    case nonZeroExit(Int32)
}

enum BoundedProcessRunner {
    static let defaultMaximumOutputBytes = 1_048_576

    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        environmentAdditions: [String: String] = [:],
        timeout: TimeInterval = 8,
        maximumOutputBytes: Int = defaultMaximumOutputBytes,
        allowedExitStatuses: Set<Int32> = [0]
    ) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        var resolvedEnvironment = environment ?? ProcessInfo.processInfo.environment
        environmentAdditions.forEach { resolvedEnvironment[$0.key] = $0.value }
        process.environment = resolvedEnvironment
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let capture = BoundedProcessCapture(limit: maximumOutputBytes)
        let collector = BoundedProcessCollector(
            outputHandle: outputPipe.fileHandleForReading,
            errorHandle: errorPipe.fileHandleForReading,
            capture: capture,
            onLimitExceeded: { [weak process] in
                if process?.isRunning == true { process?.terminate() }
            })

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            collector.finish()
            throw BoundedProcessError.launchFailed
        }
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()

        if terminated.wait(timeout: .now() + max(timeout, 0.1)) == .timedOut {
            stop(process, terminated: terminated)
            collector.finish()
            throw BoundedProcessError.timedOut
        }
        collector.finish()
        guard !capture.exceededLimit else { throw BoundedProcessError.outputTooLarge }
        guard allowedExitStatuses.contains(process.terminationStatus) else {
            throw BoundedProcessError.nonZeroExit(process.terminationStatus)
        }
        return capture.output
    }

    private static func stop(_ process: Process, terminated: DispatchSemaphore) {
        process.terminate()
        if terminated.wait(timeout: .now() + 1) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = terminated.wait(timeout: .now() + 1)
        }
    }
}

private final class BoundedProcessCapture {
    private let lock = NSLock()
    private let limit: Int
    private var storedOutput = Data()
    private var storedByteCount = 0
    private var didExceedLimit = false

    var output: Data { lock.withLock { storedOutput } }
    var exceededLimit: Bool { lock.withLock { didExceedLimit } }

    init(limit: Int) { self.limit = max(limit, 0) }

    func appendOutput(_ data: Data) -> Bool {
        append(data, capturesOutput: true)
    }

    func appendError(_ data: Data) -> Bool {
        append(data, capturesOutput: false)
    }

    private func append(_ data: Data, capturesOutput: Bool) -> Bool {
        lock.withLock {
            guard !data.isEmpty else { return false }
            let wasWithinLimit = !didExceedLimit
            let remaining = max(limit - storedByteCount, 0)
            if capturesOutput { storedOutput.append(data.prefix(remaining)) }
            storedByteCount += min(data.count, remaining)
            if data.count > remaining { didExceedLimit = true }
            return wasWithinLimit && didExceedLimit
        }
    }
}

private final class BoundedProcessCollector {
    private struct Reader {
        let handle: FileHandle
        let capturesOutput: Bool
        let source: DispatchSourceRead
    }

    private let queue = DispatchQueue(label: "DockDeck.BoundedProcessCollector")
    private let cancellationGroup = DispatchGroup()
    private let capture: BoundedProcessCapture
    private let onLimitExceeded: () -> Void
    private let lock = NSLock()
    private var readers: [Reader] = []
    private var finished = false

    init(
        outputHandle: FileHandle,
        errorHandle: FileHandle,
        capture: BoundedProcessCapture,
        onLimitExceeded: @escaping () -> Void
    ) {
        self.capture = capture
        self.onLimitExceeded = onLimitExceeded
        readers = [(outputHandle, true), (errorHandle, false)].map { handle, capturesOutput in
            let descriptor = handle.fileDescriptor
            let flags = fcntl(descriptor, F_GETFL)
            if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }
            let source = DispatchSource.makeReadSource(
                fileDescriptor: descriptor, queue: queue)
            cancellationGroup.enter()
            source.setEventHandler { [weak self] in
                self?.drain(descriptor, capturesOutput: capturesOutput)
            }
            source.setCancelHandler { [cancellationGroup] in cancellationGroup.leave() }
            source.resume()
            return Reader(
                handle: handle, capturesOutput: capturesOutput, source: source)
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
                drain(reader.handle.fileDescriptor, capturesOutput: reader.capturesOutput)
                reader.source.cancel()
            }
        }
        _ = cancellationGroup.wait(timeout: .now() + 1)
        readers.forEach { try? $0.handle.close() }
    }

    private func drain(_ descriptor: Int32, capturesOutput: Bool) {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count > 0 {
                let data = Data(bytes.prefix(count))
                let exceeded = capturesOutput
                    ? capture.appendOutput(data) : capture.appendError(data)
                if exceeded { onLimitExceeded() }
            } else if count == -1, errno == EINTR {
                continue
            } else {
                return
            }
        }
    }
}
