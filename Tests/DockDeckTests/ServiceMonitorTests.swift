import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class ServiceMonitorTests: XCTestCase {
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
        let session = URLSession(configuration: configuration)
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
            endpoints: [endpoint], refreshInterval: 120, session: session)
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

        cancellable.cancel()
        store.stop()
        session.invalidateAndCancel()
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
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
