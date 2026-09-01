import Foundation
import XCTest

@testable import DockDeck

final class ShellEnvironmentTests: XCTestCase {
    func testCompactPromptHookUsesPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = try ShellEnvironment.installCompactPromptHook(at: root)
        let hook = directory.appendingPathComponent(".zshenv")
        let contents = try String(contentsOf: hook, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: hook.path)

        XCTAssertTrue(contents.contains("PROMPT='%% '"))
        XCTAssertTrue(contents.contains("source \"$ZDOTDIR/.zshenv\""))
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
    }
}
