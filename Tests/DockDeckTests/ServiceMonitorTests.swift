import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class ServiceMonitorTests: XCTestCase {
    func testOutageStartsAtFirstFailureAndRetainsRecoveryAcrossChecks() {
        let now = Date(timeIntervalSince1970: 1000)
        var item = ServiceMonitorItem(endpoint: .init(name: "API", urlString: "https://example.com"), state: .idle)
        item.observe(.offline("Offline"), at: now)
        XCTAssertNil(item.outageStartedAt)
        item.observe(.degraded("HTTP 503"), at: now)
        item.observe(.checking, at: now.addingTimeInterval(10))
        item.observe(.down("HTTP 503"), at: now.addingTimeInterval(20))
        XCTAssertEqual(item.outageStartedAt, now)
        XCTAssertNil(item.outageEndedAt)
        item.observe(.up(statusCode: 200, latencyMilliseconds: 10), at: now.addingTimeInterval(60))
        XCTAssertEqual(item.outageEndedAt, now.addingTimeInterval(60))
        XCTAssertEqual(item.lastSuccessfulAt, now.addingTimeInterval(60))
        item.observe(.checking, at: now.addingTimeInterval(80))
        XCTAssertEqual(item.outageEndedAt, now.addingTimeInterval(60))
        item.observe(.degraded("Timed out"), at: now.addingTimeInterval(90))
        XCTAssertEqual(item.outageStartedAt, now.addingTimeInterval(90))
        XCTAssertNil(item.outageEndedAt)
        item.observe(.up(statusCode: 200, latencyMilliseconds: 10), at: now)
        XCTAssertEqual(item.outageEndedAt, item.outageStartedAt)
    }

    func testURLValidationRequiresSecurePublicServices() {
        XCTAssertNotNil(
            ServiceMonitorURLValidator.validatedURL("https://status.example.com/health"))
        XCTAssertNotNil(ServiceMonitorURLValidator.validatedURL("http://localhost:8080/health"))
        XCTAssertNotNil(ServiceMonitorURLValidator.validatedURL("http://192.168.1.20/status"))
        XCTAssertNotNil(ServiceMonitorURLValidator.validatedURL("http://[::1]:8080/status"))
        XCTAssertNil(ServiceMonitorURLValidator.validatedURL("http://example.com/health"))
        XCTAssertNil(ServiceMonitorURLValidator.validatedURL("http://8.8.8.8/health"))
        XCTAssertNil(ServiceMonitorURLValidator.validatedURL("http://172.32.0.1/health"))
        XCTAssertNil(ServiceMonitorURLValidator.validatedURL("ftp://example.com/health"))
    }

    func testProbeRejectsUnsafeRedirects() throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = try XCTUnwrap(URL(string: "https://example.com/health"))
        let task = session.dataTask(with: source)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        let delegate = ServiceMonitorProbeDelegate()
        for destination in ["http://localhost/health", "https://user:password@example.com",
                            "https://example.com?token=secret"] {
            let request = URLRequest(url: try XCTUnwrap(URL(string: destination)))
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                newRequest: request) { redirected in
                XCTAssertNil(redirected, destination)
            }
        }
        let safe = URLRequest(url: try XCTUnwrap(URL(string: "https://example.org/health")))
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: safe) { redirected in
            XCTAssertEqual(redirected?.url, safe.url)
        }
    }

    func testGetFallbackCompletesAtHeadersWithoutWaitingForBody() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceMonitorURLProtocol.self]
        defer {
            ServiceMonitorURLProtocol.handler = nil
            ServiceMonitorURLProtocol.holdsBody = false
        }
        ServiceMonitorURLProtocol.holdsBody = true
        var methods: [String] = []
        ServiceMonitorURLProtocol.handler = { request in
            methods.append(request.httpMethod ?? "")
            if request.httpMethod == "GET" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-0")
            }
            return try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: request.httpMethod == "HEAD" ? 405 : 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "1073741824", "Content-Type": "application/json"]))
        }
        let store = ServiceMonitorStore(
            endpoints: [ServiceMonitorEndpoint(name: "API", urlString: "https://example.com")],
            refreshInterval: 120, sessionConfiguration: configuration)
        let completed = expectation(description: "Headers are enough for health check")
        var fulfilled = false
        let cancellable = store.$items.sink { items in
            guard !fulfilled, case .up(200, _) = items.first?.state else { return }
            fulfilled = true
            completed.fulfill()
        }
        store.start()
        wait(for: [completed], timeout: 2)
        XCTAssertEqual(methods, ["HEAD", "GET"])
        cancellable.cancel()
        store.stop()
    }

    func testURLValidationRejectsPublicNumericHostsOverHTTP() {
        let hosts = [
            "[2001:4860:4860::8888]", "[2001:4860:4860::8888%25en0]",
            "[::ffff:8.8.8.8]", "[::ffff:808:808]", "[ff02::1]", "[::]",
            "134744072", "0x08080808", "010.010.010.010", "8.8.2056", "8.8.8.8.",
        ]

        for host in hosts {
            let url = "http://\(host)/health"
            XCTAssertNil(ServiceMonitorURLValidator.validatedURL(url), url)
            XCTAssertEqual(
                ServiceMonitorURLValidator.validationMessage(url),
                "Public services must use HTTPS.", url)
            XCTAssertNotNil(
                ServiceMonitorURLValidator.validatedURL("https://\(host)/health"), host)
        }
    }

    func testURLValidationPreservesLocalNumericHostsAndNames() {
        let hosts = [
            "localhost", "printer", "printer.local", "LOCALHOST.",
            "127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.20", "169.254.1.2",
            "127.1", "2130706433", "0x7f000001", "0300.0250.1.1",
            "[::1]", "[fc00::1]", "[fd00::1]", "[fe80::1]", "[fe80::1%25en0]",
            "[::ffff:127.0.0.1]", "[::ffff:c0a8:114]",
        ]

        for host in hosts {
            let url = "http://\(host):8080/health"
            XCTAssertNotNil(ServiceMonitorURLValidator.validatedURL(url), url)
        }
    }

    func testURLValidationRejectsCredentials() {
        let value = "https://user:password@example.com/health"

        XCTAssertNil(ServiceMonitorURLValidator.validatedURL(value))
        XCTAssertEqual(
            ServiceMonitorURLValidator.validationMessage(value),
            "Credentials are not stored in service URLs.")
    }

    func testURLValidationRejectsSecretQueryParameters() {
        let values = [
            "https://example.com/health?api_key=secret",
            "https://example.com/health?access-token=secret",
            "https://example.com/health?X-Amz-Credential=secret",
            "https://example.com/health?X-Amz-Signature=secret",
        ]

        for value in values {
            XCTAssertNil(ServiceMonitorURLValidator.validatedURL(value))
            XCTAssertTrue(ServiceMonitorURLValidator.containsCredentials(value))
        }
        XCTAssertNotNil(
            ServiceMonitorURLValidator.validatedURL("https://example.com/health?format=short"))
    }

    func testStorageNormalizationDropsCredentialsAndBoundsText() {
        let endpoint = ServiceMonitorEndpoint(
            name: String(repeating: "A", count: 40),
            urlString: "https://user:password@example.com")

        let normalized = endpoint.normalizedForStorage()

        XCTAssertEqual(normalized.name.count, ServiceMonitorEndpoint.maximumNameLength)
        XCTAssertEqual(normalized.urlString, "")

        let secretQuery = ServiceMonitorEndpoint(
            name: "API", urlString: "https://example.com/health?token=secret")
        XCTAssertEqual(secretQuery.normalizedForStorage().urlString, "")
    }

    func testServiceStatePresentsCompactLabels() {
        XCTAssertEqual(
            ServiceMonitorState.up(statusCode: 204, latencyMilliseconds: 83).shortLabel,
            "83ms")
        XCTAssertEqual(ServiceMonitorState.down("HTTP 503").shortLabel, "DOWN")
        XCTAssertEqual(ServiceMonitorState.down("HTTP 503").detail, "HTTP 503")
        XCTAssertEqual(ServiceMonitorState.degraded("Timed out").shortLabel, "WARN")
        XCTAssertEqual(ServiceMonitorState.offline("Network offline").shortLabel, "OFF")
    }

    func testStoreRemovesDuplicateEndpointIDs() {
        let id = UUID()
        let endpoints = [
            ServiceMonitorEndpoint(id: id, name: "First", urlString: "https://one.example"),
            ServiceMonitorEndpoint(id: id, name: "Second", urlString: "https://two.example"),
        ]

        let store = ServiceMonitorStore(endpoints: endpoints, refreshInterval: 30)

        XCTAssertEqual(store.items.map(\.endpoint.name), ["First"])
    }

    func testStoreUsesHeadAndPublishesSuccessfulProbe() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceMonitorURLProtocol.self]
        let endpoint = ServiceMonitorEndpoint(
            name: "API", urlString: "https://status.example.com/health")
        ServiceMonitorURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "HEAD")
            return HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 204,
                httpVersion: "HTTP/1.1",
                headerFields: nil)!
        }
        let store = ServiceMonitorStore(
            endpoints: [endpoint], refreshInterval: 120, sessionConfiguration: configuration)
        let completed = expectation(description: "Probe completed")
        var fulfilled = false
        let cancellable = store.$items.sink { items in
            guard !fulfilled, case .up(let code, _) = items.first?.state else { return }
            fulfilled = true
            XCTAssertEqual(code, 204)
            completed.fulfill()
        }

        store.start()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(store.latencyHistory(for: endpoint.id).samples.count, 1)

        cancellable.cancel()
        store.stop()
        ServiceMonitorURLProtocol.handler = nil
    }

    func testStoreFallsBackToBoundedGetWhenHeadIsUnsupported() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceMonitorURLProtocol.self]
        let endpoint = ServiceMonitorEndpoint(
            name: "API", urlString: "https://status.example.com/health")
        var methods: [String] = []
        ServiceMonitorURLProtocol.handler = { request in
            methods.append(request.httpMethod ?? "")
            if request.httpMethod == "GET" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-0")
            }
            return HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: request.httpMethod == "HEAD" ? 405 : 204,
                httpVersion: "HTTP/1.1", headerFields: nil)!
        }
        let store = ServiceMonitorStore(
            endpoints: [endpoint], refreshInterval: 120, sessionConfiguration: configuration)
        let completed = expectation(description: "Fallback probe completed")
        let cancellable = store.$items.sink { items in
            guard case .up(let code, _) = items.first?.state else { return }
            XCTAssertEqual(code, 204)
            completed.fulfill()
        }

        store.start()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(methods, ["HEAD", "GET"])
        cancellable.cancel()
        store.stop()
        ServiceMonitorURLProtocol.handler = nil
    }

    func testStoreRequiresTwoFailuresBeforePublishingDown() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceMonitorURLProtocol.self]
        let endpoint = ServiceMonitorEndpoint(
            name: "API", urlString: "https://status.example.com/health")
        ServiceMonitorURLProtocol.handler = { request in
            HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 503,
                httpVersion: "HTTP/1.1", headerFields: nil)!
        }
        let store = ServiceMonitorStore(
            endpoints: [endpoint], refreshInterval: 120, sessionConfiguration: configuration)
        let firstFailure = expectation(description: "Transient failure")
        let confirmedFailure = expectation(description: "Confirmed failure")
        var requestedSecondProbe = false
        let cancellable = store.$items.sink { items in
            switch items.first?.state {
            case .degraded:
                guard !requestedSecondProbe else { return }
                requestedSecondProbe = true
                firstFailure.fulfill()
                DispatchQueue.main.async { store.refresh() }
            case .down:
                confirmedFailure.fulfill()
            default:
                break
            }
        }

        store.start()
        wait(for: [firstFailure, confirmedFailure], timeout: 1)

        cancellable.cancel()
        store.stop()
        ServiceMonitorURLProtocol.handler = nil
    }

    func testConnectionLostCountsAsEndpointFailure() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceMonitorURLProtocol.self]
        let endpoint = ServiceMonitorEndpoint(
            name: "API", urlString: "https://status.example.com/health")
        ServiceMonitorURLProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        let store = ServiceMonitorStore(
            endpoints: [endpoint], refreshInterval: 120, sessionConfiguration: configuration)
        let completed = expectation(description: "Connection loss recorded")
        let cancellable = store.$items.sink { items in
            guard case .degraded(let reason) = items.first?.state else { return }
            XCTAssertEqual(reason, "Connection lost")
            completed.fulfill()
        }

        store.start()
        wait(for: [completed], timeout: 1)

        cancellable.cancel()
        store.stop()
        ServiceMonitorURLProtocol.handler = nil
    }

    func testPanelRendersFourServicesAtCompactSize() throws {
        let endpoints = (1...4).map {
            ServiceMonitorEndpoint(
                name: "Service \($0)", urlString: "https://service\($0).example.com")
        }
        let store = ServiceMonitorStore(endpoints: endpoints, refreshInterval: 120)
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: ServiceMonitorPanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}

private final class ServiceMonitorURLProtocol: URLProtocol {
    static var holdsBody = false
    static var handler: ((URLRequest) throws -> HTTPURLResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let response = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !Self.holdsBody || request.httpMethod == "HEAD" {
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
