import XCTest

@testable import DockDeck

final class CLIUpdateTests: XCTestCase {
    func testVersionsCompareNumericallyAndRejectUntrustedOutput() throws {
        XCTAssertLessThan(try XCTUnwrap(CLIVersion("0.99.0")), try XCTUnwrap(CLIVersion("0.153.4")))
        XCTAssertEqual(CLIVersion("1.2.3+build.4"), CLIVersion("1.2.3"))
        XCTAssertFalse(try XCTUnwrap(CLIVersion("0.154.0-alpha.1")).isStable)
        for invalid in ["latest", "1.2", "1.2.3\n", "1.2.3; open bad", "999999999999.2.3"] {
            XCTAssertNil(CLIVersion(invalid), invalid)
        }
        for (id, output, expected) in [
            (DiagnosticCheckID.codex, "codex-cli 0.153.4\n", "0.153.4"),
            (.claude, "2.1.236 (Claude Code)\n", "2.1.236"),
            (.github, "gh version 2.96.0 (2026-07-24)\nhttps://github.com/cli/cli", "2.96.0"),
        ] {
            XCTAssertEqual(CLIVersion.parseOutput(Data(output.utf8), id: id)?.text, expected)
            XCTAssertNil(CLIVersion.parseOutput(Data("Error loading configuration: 1.2.3".utf8), id: id))
        }
    }

    func testInstallationDetectionUsesResolvedPackageAndChannel() {
        let home = "/Users/test"
        let cases: [(DiagnosticCheckID, String, CLIInstallation)] = [
            (.codex, home + "/.nvm/versions/node/v24/lib/node_modules/@openai/codex/bin/codex.js",
                .npm(prefix: home + "/.nvm/versions/node/v24", package: "@openai/codex")),
            (.claude, "/opt/homebrew/Caskroom/claude-code/2.1.236/claude",
                .homebrew(prefix: "/opt/homebrew", package: "claude-code", cask: true)),
            (.claude, "/usr/local/Caskroom/claude-code@latest/2.2.0/claude",
                .homebrew(prefix: "/usr/local", package: "claude-code@latest", cask: true)),
            (.github, "/opt/homebrew/Cellar/gh/2.96.0/bin/gh",
                .homebrew(prefix: "/opt/homebrew", package: "gh", cask: false)),
            (.claude, home + "/.local/share/claude/versions/2.1.236", .claudeNative),
            (.codex, "/Applications/ChatGPT.app/Contents/Resources/codex", .bundled),
            (.codex, "/opt/homebrew/bin/codex", .unknown),
            (.codex, "/tmp/lib/node_modules/@openai/codex-untrusted/bin/codex", .unknown),
            (.claude, "/opt/homebrew/Caskroom/claude-code-fork/2.1.236/claude", .unknown),
        ]
        for (id, path, expected) in cases {
            XCTAssertEqual(CLIInstallation.detect(id: id, resolvedPath: path, home: home), expected, path)
        }
        let stable = CLIInstallation.homebrew(prefix: "/opt/homebrew", package: "claude-code", cask: true)
        XCTAssertEqual(stable.metadataURL?.absoluteString, "https://formulae.brew.sh/api/cask/claude-code.json")
        XCTAssertEqual(stable.updateCommand(executable: "/ignored", isExecutable: { _ in true }),
            "'/opt/homebrew/bin/brew' upgrade --cask claude-code")
        XCTAssertNil(stable.updateCommand(executable: "/ignored", isExecutable: { _ in false }))
        XCTAssertNil(CLIInstallation.bundled.updateCommand(executable: "/ignored"))
        XCTAssertNil(CLIInstallation.unknown.metadataURL)
    }

    func testNPMCommandPreservesPrefixAndQuotesShellMetacharacters() throws {
        let prefix = "/tmp/Node's $(touch bad)"
        let installation = CLIInstallation.npm(prefix: prefix, package: "@openai/codex")
        let command = try XCTUnwrap(installation.updateCommand(executable: "/ignored", isExecutable: { _ in true }))
        XCTAssertEqual(command,
            "PATH='/tmp/Node'\\''s $(touch bad)/bin':\"$PATH\" '/tmp/Node'\\''s $(touch bad)/bin/npm' install -g --prefix '/tmp/Node'\\''s $(touch bad)' @openai/codex@latest")
        // Parse the generated command with a fake npm; no installation command is executed.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = directory.appendingPathComponent("Node's $(touch bad)/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let npm = bin.appendingPathComponent("npm")
        try Data("#!/bin/sh\n/usr/bin/printf '%s\\n' \"$@\"\n".utf8).write(to: npm)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: npm.path)
        let generated = try XCTUnwrap(CLIInstallation.npm(prefix: bin.deletingLastPathComponent().path,
            package: "@openai/codex").updateCommand(executable: "/ignored", isExecutable: { _ in true }))
        let output = try BoundedProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", generated], currentDirectoryURL: directory)
        XCTAssertEqual(String(decoding: output, as: UTF8.self),
            "install\n-g\n--prefix\n\(bin.deletingLastPathComponent().path)\n@openai/codex@latest\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("bad").path))
    }

    func testReleaseMetadataRejectsMalformedPreviewAndOversizedResponses() {
        for json in [#"{"version":"0.153.4"}"#, #"{"versions":{"stable":"0.153.4"}}"#] {
            XCTAssertEqual(CLIReleaseChecker.parseMetadata(Data(json.utf8))?.text, "0.153.4")
        }
        for json in [#"{"version":"1.0.0-alpha.1"}"#, #"{"version":"https://bad"}"#, "[]", "{}", "not json"] {
            XCTAssertNil(CLIReleaseChecker.parseMetadata(Data(json.utf8)))
        }
        XCTAssertNil(CLIReleaseChecker.parseMetadata(Data(repeating: 32, count: 256 * 1_024 + 1)))
    }

    func testReleaseCacheExpiresAndFailureDoesNotClaimCurrent() async {
        var now = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let checker = CLIReleaseChecker(fetch: { _ in
            requests += 1
            if requests > 1 { throw URLError(.notConnectedToInternet) }
            return Data(#"{"version":"0.153.4"}"#.utf8)
        }, now: { now })
        let old = info(version: "0.145.0")
        let first = await checker.check(old)
        XCTAssertTrue(first.updateAvailable)
        now = now.addingTimeInterval(60)
        let afterInstall = await checker.check(info(version: "0.153.4"))
        XCTAssertFalse(afterInstall.updateAvailable)
        XCTAssertEqual(afterInstall.checkedAt, first.checkedAt)
        XCTAssertEqual(requests, 1)
        now = now.addingTimeInterval(21_600)
        let offline = await checker.check(old)
        XCTAssertNil(offline.latestVersion)
        XCTAssertNotNil(offline.checkedAt)
        XCTAssertFalse(offline.updateAvailable)
        _ = await checker.check(old)
        XCTAssertEqual(requests, 2)
        now = now.addingTimeInterval(301)
        _ = await checker.check(old)
        XCTAssertEqual(requests, 3)
    }

    func testPreviewBundledAndUnknownInstallsDoNotFetchOrSuggestDowngrade() async {
        var requests = 0
        let checker = CLIReleaseChecker(fetch: { _ in
            requests += 1
            return Data(#"{"version":"0.153.4"}"#.utf8)
        })
        for candidate in [info(version: "0.154.0-alpha.1"), info(version: nil),
            info(version: "0.153.4", installation: .bundled),
            info(version: "0.153.4", installation: .unknown)]
        {
            let result = await checker.check(candidate)
            XCTAssertNil(result.checkedAt)
            XCTAssertFalse(result.updateAvailable)
        }
        XCTAssertEqual(requests, 0)
        let ahead = await checker.check(info(version: "0.154.0"))
        XCTAssertFalse(ahead.updateAvailable)
    }

    @MainActor
    func testStoreKeepsReadinessSeparateAndOmitsVersionDetailsFromReport() async throws {
        let checker = CLIReleaseChecker(fetch: { _ in Data(#"{"version":"0.153.4"}"#.utf8) })
        let item = DiagnosticCheckItem(id: .codex, title: "Codex", symbolName: "terminal",
            state: .ready, detail: "Installed and signed in", checkedAt: Date(), lastSuccessfulAt: Date(),
            cliUpdate: info(version: "0.145.0"))
        let store = DiagnosticsStore(checker: { [item] }, releaseChecker: checker)
        store.refresh()
        for _ in 0..<200 where store.isRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(store.isRefreshing)
        let result = try XCTUnwrap(store.items.first)
        XCTAssertEqual(result.state, .ready)
        XCTAssertTrue(result.cliUpdate?.updateAvailable == true)
        let report = store.report()
        XCTAssertFalse(report.contains("0.145.0"))
        XCTAssertFalse(report.contains("/private/cli"))
        XCTAssertFalse(report.contains("npm install"))
    }

    func testLiveCLIReleaseMetadata() async throws {
        guard ProcessInfo.processInfo.environment["DOCKDECK_LIVE_CLI_CHECKS"] == "1" else {
            throw XCTSkip("Set DOCKDECK_LIVE_CLI_CHECKS to check installed CLIs and public release APIs")
        }
        let checker = CLIReleaseChecker()
        for (id, executable) in [
            (DiagnosticCheckID.codex, CodexBinaryLocator.locate()),
            (.claude, ClaudeBinaryLocator.locate()),
            (.github, ProjectPulseBinaryLocator.githubCLI()),
        ] {
            guard let executable else { continue }
            let installed = CLIUpdateInfo.inspect(id: id, executable: executable,
                environment: ProcessInfo.processInfo.environment)
            XCTAssertNotNil(installed.installedVersion, id.title)
            guard installed.installation.metadataURL != nil else { continue }
            let result = await checker.check(installed)
            XCTAssertNotNil(result.latestVersion, id.title)
            print("CLI release check: \(id.title), installed \(result.installedVersion?.text ?? "unknown"), published \(result.latestVersion?.text ?? "unknown")")
        }
    }

    private func info(version: String?, installation: CLIInstallation = .npm(prefix: "/private", package: "@openai/codex")) -> CLIUpdateInfo {
        CLIUpdateInfo(installedVersion: version.flatMap(CLIVersion.init), installation: installation,
            executablePath: "/private/cli", command: "npm install")
    }
}
