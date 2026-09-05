import Darwin
import Foundation

struct ServiceMonitorEndpoint: Codable, Equatable, Identifiable {
    static let maximumCount = 4
    static let maximumNameLength = 24
    static let maximumURLLength = 2_048

    let id: UUID
    var name: String
    var urlString: String

    init(id: UUID = UUID(), name: String, urlString: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(Self.maximumNameLength)) }
        return ServiceMonitorURLValidator.validatedURL(urlString)?.host ?? "Service"
    }

    func normalizedForStorage() -> Self {
        let name = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maximumNameLength))
        var urlString = String(
            urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maximumURLLength))
        if ServiceMonitorURLValidator.containsCredentials(urlString) { urlString = "" }
        return Self(id: id, name: name, urlString: urlString)
    }
}

enum ServiceMonitorURLValidator {
    private static let credentialQueryNames: Set<String> = [
        "access_token", "api_key", "apikey", "auth", "authorization", "credential", "key",
        "password", "passwd", "secret", "sig", "signature", "token",
    ]

    static func validatedURL(_ value: String) -> URL? {
        validationMessage(value) == nil
            ? URLComponents(string: trimmed(value))?.url : nil
    }

    static func validationMessage(_ value: String) -> String? {
        let value = trimmed(value)
        guard !value.isEmpty, value.count <= ServiceMonitorEndpoint.maximumURLLength else {
            return "Enter an HTTPS URL."
        }
        guard let components = URLComponents(string: value), let host = components.host,
            !host.isEmpty
        else { return "Enter a complete URL with a host." }
        guard !containsCredentials(components) else {
            return "Credentials are not stored in service URLs."
        }
        switch components.scheme?.lowercased() {
        case "https":
            return components.url == nil ? "Enter a valid HTTPS URL." : nil
        case "http":
            return isLocalHost(host)
                ? (components.url == nil ? "Enter a valid local URL." : nil)
                : "Public services must use HTTPS."
        default:
            return "Only HTTPS and local HTTP URLs are supported."
        }
    }

    static func containsCredentials(_ value: String) -> Bool {
        guard let components = URLComponents(string: trimmed(value)) else { return false }
        return containsCredentials(components)
    }

    private static func containsCredentials(_ components: URLComponents) -> Bool {
        if components.user != nil || components.password != nil { return true }
        return (components.queryItems ?? []).contains { item in
            let name = item.name.lowercased().replacingOccurrences(of: "-", with: "_")
            return credentialQueryNames.contains(name)
                || name.hasSuffix("_token")
                || name.hasSuffix("_secret")
                || name.hasSuffix("_password")
                || name.hasSuffix("_signature")
                || name.hasSuffix("_credential")
        }
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLocalHost(_ value: String) -> Bool {
        let host = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host == "localhost" || host.hasSuffix(".local") || !host.contains(".") {
            return true
        }
        if isPrivateIPv4(host) { return true }
        return isPrivateIPv6(host)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        var address = in_addr()
        guard inet_pton(AF_INET, host, &address) == 1 else { return false }
        let value = UInt32(bigEndian: address.s_addr)
        let first = value >> 24
        let second = (value >> 16) & 0xff
        return first == 10
            || first == 127
            || (first == 169 && second == 254)
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
    }

    private static func isPrivateIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return false }
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        let loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
        let uniqueLocal = bytes.first.map { $0 & 0xfe == 0xfc } ?? false
        let linkLocal = bytes.count > 1 && bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80
        return loopback || uniqueLocal || linkLocal
    }
}

enum ServiceMonitorState: Equatable {
    case idle
    case checking
    case up(statusCode: Int, latencyMilliseconds: Int)
    case degraded(String)
    case offline(String)
    case down(String)

    var shortLabel: String {
        switch self {
        case .idle: "WAIT"
        case .checking: "…"
        case .up(_, let latency): "\(latency)ms"
        case .degraded: "WARN"
        case .offline: "OFF"
        case .down: "DOWN"
        }
    }

    var detail: String {
        switch self {
        case .idle: "Waiting to check"
        case .checking: "Checking"
        case .up(let statusCode, let latency):
            "HTTP \(statusCode) in \(latency) ms"
        case .degraded(let reason): "Transient failure: \(reason)"
        case .offline(let reason), .down(let reason): reason
        }
    }
}

final class ServiceMonitorProbeDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [Int: (URLResponse?, Error?) -> Void] = [:]

    func register(_ task: URLSessionTask, completion: @escaping (URLResponse?, Error?) -> Void) {
        lock.withLock { completions[task.taskIdentifier] = completion }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        finish(task: dataTask, response: response, error: nil)
        // Health checks need the status and headers, never the response body.
        completionHandler(.cancel)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        finish(task: task, response: task.response, error: error)
    }

    private func finish(task: URLSessionTask, response: URLResponse?, error: Error?) {
        let callback = lock.withLock { completions.removeValue(forKey: task.taskIdentifier) }
        callback?(response, error)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let sourceURL = task.currentRequest?.url, let destinationURL = request.url,
            ServiceMonitorURLValidator.validatedURL(destinationURL.absoluteString) != nil
        else {
            completionHandler(nil)
            return
        }
        let downgradesTLS = sourceURL.scheme?.lowercased() == "https"
            && destinationURL.scheme?.lowercased() != "https"
        completionHandler(downgradesTLS ? nil : request)
    }
}

struct ServiceMonitorItem: Identifiable, Equatable {
    let endpoint: ServiceMonitorEndpoint
    var state: ServiceMonitorState

    var id: UUID { endpoint.id }
}

final class ServiceMonitorStore: ObservableObject {
    @Published private(set) var items: [ServiceMonitorItem]
    private(set) var latencyHistories: [UUID: MetricHistory] = [:]

    private var endpoints: [ServiceMonitorEndpoint]
    private var refreshInterval: TimeInterval
    private var timer: Timer?
    private var tasks: [UUID: URLSessionDataTask] = [:]
    private var consecutiveFailures: [UUID: Int] = [:]
    private var delayedRefresh: DispatchWorkItem?
    private var generation = 0
    private var isRunning = false
    private let session: URLSession
    private let sessionDelegate: ServiceMonitorProbeDelegate
    private var refreshCadence = ModuleRefreshCadence()

    init(
        endpoints: [ServiceMonitorEndpoint] = PanelSettings.serviceMonitorEndpoints,
        refreshInterval: TimeInterval = PanelSettings.serviceMonitorRefreshInterval,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        let endpoints = Self.limitedUniqueEndpoints(endpoints)
        self.endpoints = endpoints
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        items = endpoints.map { ServiceMonitorItem(endpoint: $0, state: .idle) }

        let delegate = ServiceMonitorProbeDelegate()
        sessionDelegate = delegate
        session = Self.makeSession(configuration: sessionConfiguration, delegate: delegate)
    }

    deinit { session.invalidateAndCancel() }

    private static func makeSession(
        configuration: URLSessionConfiguration?, delegate: ServiceMonitorProbeDelegate
    ) -> URLSession {
        let configuration = configuration ?? .ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        scheduleTimer()
    }

    func stop() {
        guard isRunning || timer != nil || !tasks.isEmpty else { return }
        isRunning = false
        generation += 1
        timer?.invalidate()
        timer = nil
        delayedRefresh?.cancel()
        delayedRefresh = nil
        cancelTasks()
    }

    func updateConfiguration(
        endpoints: [ServiceMonitorEndpoint], refreshInterval: TimeInterval
    ) {
        let endpoints = Self.limitedUniqueEndpoints(endpoints)
        let previousItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let previousHistories = latencyHistories
        self.endpoints = endpoints
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        items = endpoints.map {
            let previous = previousItems[$0.id]
            let unchanged = previous?.endpoint.urlString == $0.urlString
            return ServiceMonitorItem(
                endpoint: $0, state: unchanged ? previous?.state ?? .idle : .idle)
        }
        latencyHistories = Dictionary(uniqueKeysWithValues: endpoints.compactMap { endpoint in
            guard previousItems[endpoint.id]?.endpoint.urlString == endpoint.urlString,
                let history = previousHistories[endpoint.id]
            else { return nil }
            return (endpoint.id, history)
        })
        consecutiveFailures = Dictionary(uniqueKeysWithValues: endpoints.compactMap { endpoint in
            guard previousItems[endpoint.id]?.endpoint.urlString == endpoint.urlString,
                let count = consecutiveFailures[endpoint.id]
            else { return nil }
            return (endpoint.id, count)
        })
        guard isRunning else { return }
        generation += 1
        cancelTasks()
        scheduleTimer()
        scheduleConfigurationRefresh()
    }

    func setRuntimeActivity(
        _ activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) {
        guard refreshCadence.update(activity: activity, lowPowerMode: lowPowerMode),
            isRunning
        else { return }
        scheduleTimer()
    }

    func refresh() {
        guard isRunning else { return }
        generation += 1
        let generation = generation
        delayedRefresh?.cancel()
        delayedRefresh = nil
        cancelTasks()

        for endpoint in endpoints {
            guard let url = ServiceMonitorURLValidator.validatedURL(endpoint.urlString) else {
                consecutiveFailures[endpoint.id] = 2
                update(endpoint.id, state: .down(
                    ServiceMonitorURLValidator.validationMessage(endpoint.urlString)
                        ?? "Invalid URL"))
                continue
            }
            update(endpoint.id, state: .checking)
            startRequest(
                endpointID: endpoint.id, url: url, method: "HEAD",
                startedAt: ProcessInfo.processInfo.systemUptime, generation: generation)
        }
    }

    private func startRequest(
        endpointID: UUID, url: URL, method: String, startedAt: TimeInterval,
        generation: Int
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        if method == "GET" { request.setValue("bytes=0-0", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        sessionDelegate.register(task) { [weak self] response, error in
            let latency = max(
                Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000).rounded()), 0)
            DispatchQueue.main.async {
                self?.complete(
                    endpointID: endpointID, url: url, method: method,
                    response: response, error: error,
                    latencyMilliseconds: latency, startedAt: startedAt,
                    generation: generation)
            }
        }
        tasks[endpointID] = task
        task.resume()
    }

    private func complete(
        endpointID: UUID,
        url: URL,
        method: String,
        response: URLResponse?,
        error: Error?,
        latencyMilliseconds: Int,
        startedAt: TimeInterval,
        generation: Int
    ) {
        guard isRunning, generation == self.generation else { return }
        tasks.removeValue(forKey: endpointID)
        if let error {
            if Self.isOffline(error) {
                consecutiveFailures[endpointID] = 0
                update(endpointID, state: .offline("Network offline"))
            } else {
                recordFailure(endpointID, reason: Self.failureLabel(error))
            }
            return
        }
        guard let response = response as? HTTPURLResponse else {
            recordFailure(endpointID, reason: "No HTTP response")
            return
        }
        if method == "HEAD", response.statusCode == 405 || response.statusCode == 501 {
            startRequest(
                endpointID: endpointID, url: url, method: "GET", startedAt: startedAt,
                generation: generation)
            return
        }
        if (200..<300).contains(response.statusCode) {
            consecutiveFailures[endpointID] = 0
            update(
                endpointID,
                state: .up(
                    statusCode: response.statusCode,
                    latencyMilliseconds: latencyMilliseconds))
        } else {
            recordFailure(endpointID, reason: "HTTP \(response.statusCode)")
        }
    }

    private func recordFailure(_ endpointID: UUID, reason: String) {
        let count = (consecutiveFailures[endpointID] ?? 0) + 1
        consecutiveFailures[endpointID] = count
        update(endpointID, state: count >= 2 ? .down(reason) : .degraded(reason))
    }

    private func update(_ endpointID: UUID, state: ServiceMonitorState) {
        guard let index = items.firstIndex(where: { $0.id == endpointID }) else { return }
        if case .up(_, let latencyMilliseconds) = state {
            var history = latencyHistories[endpointID] ?? MetricHistory()
            history.append(Double(latencyMilliseconds))
            latencyHistories[endpointID] = history
        }
        items[index].state = state
    }

    func latencyHistory(for endpointID: UUID) -> MetricHistory {
        latencyHistories[endpointID] ?? MetricHistory()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard isRunning else {
            timer = nil
            return
        }
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: refreshInterval)
        timer = .moduleRefreshTimer(interval: interval) { [weak self] in self?.refresh() }
    }

    private func scheduleConfigurationRefresh() {
        delayedRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.refresh() }
        delayedRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func cancelTasks() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private static func failureLabel(_ error: Error) -> String {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return "Network error" }
        switch error.code {
        case NSURLErrorTimedOut: return "Timed out"
        case NSURLErrorNotConnectedToInternet: return "Offline"
        case NSURLErrorNetworkConnectionLost: return "Connection lost"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid:
            return "TLS error"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "Host not found"
        case NSURLErrorCannotConnectToHost: return "Connection failed"
        case NSURLErrorCancelled: return "Cancelled"
        default: return "Network error"
        }
    }

    private static func isOffline(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain
            && error.code == NSURLErrorNotConnectedToInternet
    }

    private static func limitedUniqueEndpoints(
        _ endpoints: [ServiceMonitorEndpoint]
    ) -> [ServiceMonitorEndpoint] {
        var seen: Set<UUID> = []
        var result: [ServiceMonitorEndpoint] = []
        for endpoint in endpoints where seen.insert(endpoint.id).inserted {
            result.append(endpoint)
            if result.count == ServiceMonitorEndpoint.maximumCount { break }
        }
        return result
    }

    private static func resolvedRefreshInterval(_ value: TimeInterval) -> TimeInterval {
        PanelSettings.serviceMonitorRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultServiceMonitorRefreshInterval
    }
}
