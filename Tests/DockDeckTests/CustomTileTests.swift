import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class CustomTileTests: XCTestCase {
    func testConfigurationBoundsStoredInputs() {
        let configuration = CustomTileConfiguration(
            title: String(repeating: "T", count: 40) + "\nsecret",
            executablePath: " /usr/bin/printf\nignored ",
            arguments: Array(repeating: String(repeating: "a", count: 1_100), count: 20),
            shortcutName: String(repeating: "S", count: 300),
            refreshInterval: 310)

        XCTAssertEqual(configuration.title.count, CustomTileConfiguration.maximumTitleLength)
        XCTAssertEqual(configuration.executablePath, "/usr/bin/printf ignored")
        XCTAssertEqual(configuration.arguments.count, CustomTileConfiguration.maximumArgumentCount)
        XCTAssertTrue(configuration.arguments.allSatisfy {
            $0.count == CustomTileConfiguration.maximumArgumentLength
        })
        XCTAssertEqual(
            configuration.shortcutName.count,
            CustomTileConfiguration.maximumShortcutNameLength)
        XCTAssertEqual(configuration.refreshInterval, 300)
    }

    func testOutputParserAcceptsBoundedJSONAndPlainText() throws {
        let json = try CustomTileOutputParser.parse(
            Data(#"{"title":"Build","value":"Passing","detail":"main","symbol":"checkmark.circle"}"#.utf8),
            fallbackTitle: "Fallback")
        let plain = try CustomTileOutputParser.parse(
            Data("42%\nReady".utf8), fallbackTitle: "Capacity")

        XCTAssertEqual(
            json,
            CustomTileContent(
                title: "Build", value: "Passing", detail: "main",
                symbolName: "checkmark.circle"))
        XCTAssertEqual(
            plain,
            CustomTileContent(
                title: "Capacity", value: "42%", detail: "Ready", symbolName: nil))
        XCTAssertThrowsError(
            try CustomTileOutputParser.parse(Data(), fallbackTitle: "Empty"))
        XCTAssertThrowsError(
            try CustomTileOutputParser.parse(
                Data(#"{"value":}"#.utf8), fallbackTitle: "Malformed"))
    }

    func testClientRunsExecutableWithoutShell() throws {
        let configuration = CustomTileConfiguration(
            title: "Build",
            executablePath: "/usr/bin/printf",
            arguments: [#"{"value":"Passing","detail":"main"}"#])

        let snapshot = try CustomTileClient().read(
            configuration: configuration, now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(snapshot.content.title, "Build")
        XCTAssertEqual(snapshot.content.value, "Passing")
        XCTAssertEqual(snapshot.content.detail, "main")
    }

    func testCommandEnforcesCustomOutputLimit() {
        XCTAssertThrowsError(
            try ProjectPulseCommand.run(
                executableURL: URL(fileURLWithPath: "/bin/dd"),
                arguments: ["if=/dev/zero", "bs=32769", "count=1"],
                currentDirectoryURL: FileManager.default.temporaryDirectory,
                maximumOutputBytes: CustomTileOutputParser.maximumOutputBytes)
        ) { error in
            XCTAssertEqual(error as? ProjectPulseError, .outputTooLarge)
        }
    }

    func testCommandEnforcesTimeout() {
        XCTAssertThrowsError(
            try ProjectPulseCommand.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                currentDirectoryURL: FileManager.default.temporaryDirectory,
                timeout: 0.05,
                maximumOutputBytes: CustomTileOutputParser.maximumOutputBytes)
        ) { error in
            XCTAssertEqual(error as? ProjectPulseError, .commandTimedOut)
        }
    }

    func testStoreRefreshesAndCompactPanelRenders() throws {
        let snapshot = CustomTileSnapshot(
            content: CustomTileContent(
                title: "Build", value: "Passing", detail: "main",
                symbolName: "checkmark.circle"),
            observedAt: Date())
        let store = CustomTileStore(
            configuration: CustomTileConfiguration(executablePath: "/usr/bin/printf"),
            reader: FakeCustomTileReader(snapshot: snapshot))
        let loaded = expectation(description: "Custom tile loaded")
        var fulfilled = false
        let cancellable = store.$snapshot.sink {
            guard !fulfilled, $0 == snapshot else { return }
            fulfilled = true
            loaded.fulfill()
        }
        defer {
            store.stop()
            cancellable.cancel()
        }

        store.start()
        wait(for: [loaded], timeout: 2)

        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: CustomTilePanelView(store: store, theme: Theme.theme(id: ""))
                .frame(width: size.width, height: size.height))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}

private struct FakeCustomTileReader: CustomTileReading {
    let snapshot: CustomTileSnapshot

    func read(
        configuration: CustomTileConfiguration, now: Date
    ) throws -> CustomTileSnapshot {
        snapshot
    }
}
