import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class MusicTests: XCTestCase {
    func testAppleEventParserBoundsMetadataAndProgress() throws {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "playing"), at: 1)
        descriptor.insert(
            NSAppleEventDescriptor(string: String(repeating: "x", count: 200)), at: 2)
        descriptor.insert(NSAppleEventDescriptor(string: "Artist\nName"), at: 3)
        descriptor.insert(NSAppleEventDescriptor(string: "  "), at: 4)
        descriptor.insert(NSAppleEventDescriptor(double: 240), at: 5)
        descriptor.insert(NSAppleEventDescriptor(double: 250), at: 6)
        let now = Date(timeIntervalSince1970: 100)

        let snapshot = try MusicAppleEventParser.parse(descriptor, now: now)

        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.track?.title.count, 160)
        XCTAssertEqual(snapshot.track?.artist, "Artist Name")
        XCTAssertNil(snapshot.track?.album)
        XCTAssertEqual(snapshot.track?.position, 240)
        XCTAssertEqual(snapshot.track?.progress, 1)
        XCTAssertEqual(snapshot.observedAt, now)
    }

    func testAuthorizationStatusMapping() {
        XCTAssertEqual(MusicAutomationAuthorization.resolved(0), .authorized)
        XCTAssertEqual(MusicAutomationAuthorization.resolved(-1744), .needsConsent)
        XCTAssertEqual(MusicAutomationAuthorization.resolved(-1743), .denied)
        XCTAssertEqual(MusicAutomationAuthorization.resolved(-600), .notRunning)
        XCTAssertEqual(MusicAutomationAuthorization.resolved(-1), .unavailable)
    }

    func testAutomaticRefreshNeverPromptsAndConnectDoes() {
        let snapshot = fixtureSnapshot()
        let provider = FakeMusicAutomationProvider(snapshot: snapshot)
        provider.authorization = { $0 ? .authorized : .needsConsent }
        let queue = DispatchQueue(label: "DockDeckTests.MusicConnect")
        let store = MusicStore(provider: provider, queue: queue)
        let permissionRequired = expectation(description: "Permission required")
        var requiredFulfilled = false
        let requiredCancellable = store.$status.sink { status in
            guard !requiredFulfilled, status == .permissionRequired else { return }
            requiredFulfilled = true
            permissionRequired.fulfill()
        }
        defer {
            store.stop()
            requiredCancellable.cancel()
        }

        store.start()
        wait(for: [permissionRequired], timeout: 2)
        XCTAssertEqual(provider.authorizationPrompts, [false])

        let connected = expectation(description: "Music connected")
        var connectedFulfilled = false
        let connectedCancellable = store.$snapshot.sink { value in
            guard !connectedFulfilled, value == snapshot else { return }
            connectedFulfilled = true
            connected.fulfill()
        }
        defer { connectedCancellable.cancel() }
        store.requestAccess()
        store.requestAccess()
        wait(for: [connected], timeout: 2)

        XCTAssertEqual(provider.authorizationPrompts, [false, true])
        XCTAssertEqual(store.status, .ready)
    }

    func testConnectOpensMusicAndRapidCommandsAreDebounced() {
        let snapshot = fixtureSnapshot()
        let provider = FakeMusicAutomationProvider(snapshot: snapshot)
        provider.isMusicRunning = false
        let queue = DispatchQueue(label: "DockDeckTests.MusicCommands")
        let store = MusicStore(provider: provider, queue: queue)
        let stopped = expectation(description: "Music is not running")
        var stoppedFulfilled = false
        let stoppedCancellable = store.$status.sink { status in
            guard !stoppedFulfilled, status == .notRunning else { return }
            stoppedFulfilled = true
            stopped.fulfill()
        }
        defer {
            store.stop()
            stoppedCancellable.cancel()
        }

        store.start()
        wait(for: [stopped], timeout: 2)

        let connected = expectation(description: "Music opened and connected")
        var connectedFulfilled = false
        let connectedCancellable = store.$snapshot.sink { value in
            guard !connectedFulfilled, value == snapshot else { return }
            connectedFulfilled = true
            connected.fulfill()
        }
        defer { connectedCancellable.cancel() }
        store.requestAccess()
        wait(for: [connected], timeout: 2)

        XCTAssertEqual(provider.openCount, 1)
        XCTAssertTrue(store.send(.next, at: 100))
        XCTAssertFalse(store.send(.next, at: 100.1))
        queue.sync {}
        XCTAssertEqual(provider.commands, [.next])
    }

    func testCompactPanelRenders() throws {
        let size = NSSize(width: 214, height: 59)
        let store = MusicStore(
            initialSnapshot: fixtureSnapshot(), initialStatus: .ready)
        let view = NSHostingView(
            rootView: MusicPanelView(store: store, theme: Theme.theme(id: ""))
                .frame(width: size.width, height: size.height))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    private func fixtureSnapshot() -> MusicPlaybackSnapshot {
        MusicPlaybackSnapshot(
            state: .playing,
            track: MusicTrackSnapshot(
                title: "Midnight Drive", artist: "DockDeck", album: "Preview",
                duration: 240, position: 90),
            observedAt: Date(timeIntervalSince1970: 100))
    }
}

private final class FakeMusicAutomationProvider: MusicAutomationProviding {
    var isMusicRunning = true
    var authorization: (Bool) -> MusicAutomationAuthorization = { _ in .authorized }
    var authorizationPrompts: [Bool] = []
    var commands: [MusicCommand] = []
    var openCount = 0
    let snapshot: MusicPlaybackSnapshot

    init(snapshot: MusicPlaybackSnapshot) {
        self.snapshot = snapshot
    }

    func authorizationStatus(prompt: Bool) -> MusicAutomationAuthorization {
        authorizationPrompts.append(prompt)
        return authorization(prompt)
    }

    func readPlayback(now: Date) throws -> MusicPlaybackSnapshot { snapshot }

    func send(_ command: MusicCommand) throws {
        commands.append(command)
    }

    func openMusic(completion: @escaping (Bool) -> Void) {
        openCount += 1
        isMusicRunning = true
        completion(true)
    }
}
