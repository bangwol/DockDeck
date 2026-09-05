import XCTest
@testable import DockDeck

final class DeckProfileTests: XCTestCase {
    private var profile: DeckProfile {
        DeckProfile(name: "Work", configuration: .init(left: [.terminal], right: [.usage, .weather], enabled: [.terminal, .usage]),
            autoSlideModules: [.usage], autoSlideInterval: 10)
    }

    func testArchiveRejectsInvalidTrustBoundaryBeforeNormalizing() throws {
        let archive = DeckProfileArchive(profiles: [profile])
        XCTAssertEqual(try JSONDecoder().decode(DeckProfileArchive.self, from: archive.data()).validated(), archive)
        var invalid = archive
        invalid.schemaVersion = 2
        XCTAssertThrowsError(try invalid.validated())
        invalid = archive
        invalid.profiles.append(profile)
        XCTAssertThrowsError(try invalid.validated())
        invalid = archive
        invalid.profiles[0].configuration.right.append(.terminal)
        XCTAssertThrowsError(try invalid.validated())
        invalid = archive
        invalid.profiles[0].configuration.enabled = []
        XCTAssertThrowsError(try invalid.validated())
        invalid = archive
        invalid.profiles[0].configuration.right.append(.init(rawValue: "unknown"))
        XCTAssertThrowsError(try invalid.validated())
        invalid = archive
        invalid.profiles[0].autoSlideModules = [.weather]
        XCTAssertThrowsError(try invalid.validated())
        for interval in [0, 301, Double.infinity, .nan] {
            invalid = archive
            invalid.profiles[0].autoSlideInterval = interval
            XCTAssertThrowsError(try invalid.validated())
        }
        for name in ["", " Work", "Work\n", String(repeating: "a", count: 49)] {
            invalid = archive
            invalid.profiles[0].name = name
            XCTAssertThrowsError(try invalid.validated())
        }
    }

    func testLegacyNetworkArchiveRemainsImportableAndMigratesOnApply() throws {
        var old = profile
        old.configuration.right = [.network]
        old.configuration.enabled = [.terminal, .network]
        old.autoSlideModules = [.network]
        XCTAssertNoThrow(try DeckProfileArchive(profiles: [old]).validated())
        XCTAssertEqual(old.configuration.normalized().enabled, [.terminal, .systemStats])
        XCTAssertEqual(old.autoSlide.modules, [.systemStats])
    }

    func testLibraryPreservesDataOnInvalidImportOrWriteFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profiles.json")
        XCTAssertThrowsError(try DeckProfileArchive.read(from: directory))
        let store = DeckProfileStore(url: url)
        let archive = DeckProfileArchive(profiles: [profile])
        try store.replace(archive)
        let saved = try Data(contentsOf: url)
        var invalid = archive
        invalid.schemaVersion = 3
        XCTAssertThrowsError(try store.replace(invalid))
        XCTAssertEqual(try Data(contentsOf: url), saved)
        XCTAssertEqual(DeckProfileStore(url: url).archive, archive)
        let oversized = directory.appendingPathComponent("large.json")
        try Data(repeating: 32, count: DeckProfileArchive.maximumBytes + 1).write(to: oversized)
        XCTAssertThrowsError(try DeckProfileArchive.read(from: oversized))
        let failing = DeckProfileStore(url: url.appendingPathComponent("not-a-directory"))
        XCTAssertThrowsError(try failing.replace(archive))
        XCTAssertTrue(failing.archive.profiles.isEmpty)
        try Data("broken".utf8).write(to: url)
        let corrupt = DeckProfileStore(url: url)
        XCTAssertNotNil(corrupt.loadError)
        XCTAssertThrowsError(try corrupt.save(name: "New", configuration: profile.configuration, autoSlide: profile.autoSlide))
        XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
    }

    func testProfileRetainsTerminalUntilReenabledWithoutStoppingOtherModules() {
        let coordinator = ModuleRuntimeCoordinator()
        var terminalStarts = 0
        var terminalStops = 0
        var weatherStops = 0
        coordinator.register(.terminal, start: { terminalStarts += 1 }, stop: { terminalStops += 1 }, suspendsWhenInactive: false)
        coordinator.register(.weather, start: {}, stop: { weatherStops += 1 })
        coordinator.synchronize(enabledModules: [.terminal, .weather], visibleModules: [.terminal])
        let retains = DeckProfileTerminalPolicy.retain(isRunning: true, retained: false, nextEnabled: false)
        coordinator.synchronize(enabledModules: retains ? [.terminal] : [])
        XCTAssertEqual(terminalStarts, 1)
        XCTAssertEqual(terminalStops, 0)
        XCTAssertEqual(weatherStops, 1)
        XCTAssertFalse(DeckProfileTerminalPolicy.retain(isRunning: true, retained: true, nextEnabled: true))
        coordinator.synchronize(enabledModules: [.terminal], visibleModules: [.terminal])
        XCTAssertEqual(terminalStarts, 1)
        coordinator.synchronize(enabledModules: [])
        XCTAssertEqual(terminalStops, 1)
        XCTAssertFalse(DeckProfileTerminalPolicy.retain(isRunning: false, retained: false, nextEnabled: false))
    }
}
