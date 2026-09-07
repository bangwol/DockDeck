import Foundation

struct CLIVersion: Equatable, Comparable {
    let text: String
    private let components: [Int]
    let isStable: Bool

    init?(_ text: String) {
        guard text.utf8.count <= 80,
            text.range(of: #"^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z"#,
                options: .regularExpression) != nil
        else { return nil }
        self.text = text
        let core = text.split(whereSeparator: { $0 == "-" || $0 == "+" })[0]
        components = core.split(separator: ".").compactMap { Int($0) }
        isStable = !text.split(separator: "+")[0].contains("-")
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components && lhs.isStable == rhs.isStable
    }

    static func parseOutput(_ data: Data, id: DiagnosticCheckID) -> Self? {
        guard let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first else {
            return nil
        }
        let fields = line.split(separator: " ")
        switch id {
        case .codex:
            guard fields.count == 2, fields[0] == "codex-cli" else { return nil }
            return Self(String(fields[1]))
        case .claude:
            guard fields.count == 3, fields[1] == "(Claude", fields[2] == "Code)" else { return nil }
            return Self(String(fields[0]))
        case .github:
            guard fields.count >= 3, fields[0] == "gh", fields[1] == "version" else { return nil }
            return Self(String(fields[2]))
        default: return nil
        }
    }
}

enum CLIInstallation: Equatable {
    case npm(prefix: String, package: String)
    case homebrew(prefix: String, package: String, cask: Bool)
    case claudeNative
    case bundled
    case unknown

    static func detect(id: DiagnosticCheckID, resolvedPath: String, home: String) -> Self {
        if resolvedPath.split(separator: "/").contains(where: { $0.hasSuffix(".app") }) {
            return .bundled
        }
        let packages: [String]
        switch id {
        case .codex: packages = ["codex"]
        case .claude: packages = ["claude-code", "claude-code@latest"]
        case .github: packages = ["gh"]
        default: return .unknown
        }
        for prefix in ["/opt/homebrew", "/usr/local"] {
            for package in packages {
                let cask = id != .github
                let directory = cask ? "Caskroom" : "Cellar"
                if resolvedPath.hasPrefix("\(prefix)/\(directory)/\(package)/") {
                    return .homebrew(prefix: prefix, package: package, cask: cask)
                }
            }
        }
        let npmPackage = id == .codex ? "@openai/codex" : "@anthropic-ai/claude-code"
        if id == .codex || id == .claude,
            let range = resolvedPath.range(of: "/lib/node_modules/\(npmPackage)/"),
            range.lowerBound != resolvedPath.startIndex
        {
            return .npm(prefix: String(resolvedPath[..<range.lowerBound]), package: npmPackage)
        }
        if id == .claude, resolvedPath.hasPrefix("\(home)/.local/share/claude/versions/") {
            return .claudeNative
        }
        return .unknown
    }

    var title: String {
        switch self {
        case .npm: "npm"
        case .homebrew(_, let package, _): "Homebrew · \(package)"
        case .claudeNative: L10n.text("Native installer")
        case .bundled: L10n.text("App-bundled CLI")
        case .unknown: L10n.text("Unknown installation")
        }
    }

    var metadataURL: URL? {
        switch self {
        case .npm(_, let package):
            URL(string: "https://registry.npmjs.org/\(package)/latest")
        case .homebrew(_, let package, let cask):
            URL(string: "https://formulae.brew.sh/api/\(cask ? "cask" : "formula")/\(package).json")
        case .claudeNative:
            URL(string: "https://registry.npmjs.org/@anthropic-ai/claude-code/latest")
        case .bundled, .unknown: nil
        }
    }

    func updateCommand(
        executable: String,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> String? {
        func quote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        switch self {
        case .npm(let prefix, let package):
            let bin = "\(prefix)/bin"
            guard isExecutable("\(bin)/npm"), isExecutable("\(bin)/node") else { return nil }
            // Target the detected global prefix even when a terminal has a different NVM version.
            return "PATH=\(quote(bin)):\"$PATH\" \(quote(bin + "/npm")) install -g --prefix \(quote(prefix)) \(package)@latest"
        case .homebrew(let prefix, let package, let cask):
            let brew = "\(prefix)/bin/brew"
            guard isExecutable(brew) else { return nil }
            return "\(quote(brew)) upgrade \(cask ? "--cask" : "--formula") \(package)"
        case .claudeNative: return "\(quote(executable)) update"
        case .bundled, .unknown: return nil
        }
    }
}

struct CLIUpdateInfo: Equatable {
    let installedVersion: CLIVersion?
    let installation: CLIInstallation
    let executablePath: String
    let command: String?
    var latestVersion: CLIVersion?
    var checkedAt: Date?

    var updateAvailable: Bool {
        guard let installedVersion, installedVersion.isStable, let latestVersion else { return false }
        return installedVersion < latestVersion
    }

    var status: String {
        guard let installedVersion else { return L10n.text("Installed version unavailable") }
        guard installedVersion.isStable else { return L10n.text("Preview or custom version") }
        if installation == .bundled { return L10n.text("Update through the containing app") }
        if installation == .unknown { return L10n.text("Check the installation guide for updates") }
        guard checkedAt != nil else { return L10n.text("Checking published version…") }
        guard let latestVersion else { return L10n.text("Update check unavailable") }
        if updateAvailable { return String(format: L10n.text("Update available: %@"), latestVersion.text) }
        if latestVersion < installedVersion { return L10n.text("Ahead of published version") }
        return L10n.text("Up to date")
    }

    static func inspect(
        id: DiagnosticCheckID, executable: URL, environment: [String: String]
    ) -> Self {
        let installation = CLIInstallation.detect(
            id: id, resolvedPath: executable.resolvingSymlinksInPath().path,
            home: FileManager.default.homeDirectoryForCurrentUser.path)
        let output = try? BoundedProcessRunner.run(
            executableURL: executable, arguments: ["--version"],
            environment: CodexBinaryLocator.launchEnvironment(for: executable, environment: environment),
            timeout: 3, maximumOutputBytes: 4 * 1_024, diagnosticSource: .diagnostics)
        return Self(
            installedVersion: output.flatMap { CLIVersion.parseOutput($0, id: id) },
            installation: installation, executablePath: executable.path,
            command: installation.updateCommand(executable: executable.path))
    }
}

/// Public release metadata only; no CLI credentials, local paths, or versions are sent.
actor CLIReleaseChecker {
    struct Result {
        let version: CLIVersion?
        let checkedAt: Date
    }

    private var cache: [URL: Result] = [:]
    private let fetch: (URL) async throws -> Data
    private let now: () -> Date

    init(
        fetch: @escaping (URL) async throws -> Data = CLIReleaseChecker.fetchMetadata,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetch = fetch
        self.now = now
    }

    func check(_ info: CLIUpdateInfo) async -> CLIUpdateInfo {
        guard info.installedVersion?.isStable == true,
            let url = info.installation.metadataURL else { return info }
        let date = now()
        let result: Result
        if let cached = cache[url],
            date.timeIntervalSince(cached.checkedAt) < (cached.version == nil ? 300 : 21_600)
        {
            result = cached
        } else {
            let data = try? await fetch(url)
            result = Result(version: data.flatMap(Self.parseMetadata), checkedAt: date)
            cache[url] = result
        }
        var updated = info
        updated.latestVersion = result.version
        updated.checkedAt = result.checkedAt
        return updated
    }

    static func parseMetadata(_ data: Data) -> CLIVersion? {
        guard data.count <= 256 * 1_024,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = object["version"] as? String
                ?? (object["versions"] as? [String: Any])?["stable"] as? String,
            let version = CLIVersion(text), version.isStable else { return nil }
        return version
    }

    static func fetchMetadata(_ url: URL) async throws -> Data {
        let session = URLSession(configuration: .dockDeckEphemeral(requestTimeout: 5, resourceTimeout: 8))
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            http.url?.scheme == "https", response.expectedContentLength <= 256 * 1_024
        else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 256 * 1_024 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}
