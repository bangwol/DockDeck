import Foundation
import XCTest
@testable import DockDeck

final class LocalizationTests: XCTestCase {
    func testCoreStringsExistInBothLanguagesAndUnknownTextIsPreserved() throws {
        for (language, expected) in [("en", "Settings…"), ("ko", "설정…")] {
            let url = try XCTUnwrap(AppResources.bundle.url(forResource: language, withExtension: "lproj"))
            let bundle = try XCTUnwrap(Bundle(url: url))
            XCTAssertEqual(L10n.text("Settings…", bundle: bundle), expected)
            XCTAssertEqual(L10n.text("custom-module-id", bundle: bundle), "custom-module-id")
        }
    }

    func testPackagedResourcesDoNotDependOnTheBuildDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Fixture.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "test.DockDeck.resources", "CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let copied = resources.appendingPathComponent("DockDeck_DockDeck.bundle")
        try FileManager.default.copyItem(at: AppResources.bundle.bundleURL, to: copied)
        let main = try XCTUnwrap(Bundle(url: app))
        XCTAssertEqual(AppResources.resolve(in: main).bundleURL.standardizedFileURL, copied.standardizedFileURL)
        XCTAssertNotNil(AppResources.resolve(in: main).url(forResource: "ClaudeIcon-Rounded", withExtension: "svg", subdirectory: "ProviderMarks"))
    }
}
