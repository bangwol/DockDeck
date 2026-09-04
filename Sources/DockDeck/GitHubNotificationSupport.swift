import Foundation

enum GitHubNotificationURLResolver {
    static func resolve(apiURL: String?, repository: String) -> URL? {
        guard let repository = ProjectPulseConfiguration.normalizedGitHubRepository(
            repository)
        else { return nil }
        let repositoryURL = URL(string: "https://github.com/\(repository)")
        guard let apiURL, apiURL.count <= 2_048,
            let url = URL(string: apiURL),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.host?.lowercased() == "api.github.com",
            components.user == nil, components.password == nil
        else { return repositoryURL }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 5, parts[0] == "repos",
            "\(parts[1])/\(parts[2])".caseInsensitiveCompare(repository) == .orderedSame
        else { return repositoryURL }
        let kind = parts[3]
        let identifier = parts[4]
        guard isSafePathComponent(identifier) else { return repositoryURL }
        let path: String
        switch kind {
        case "pulls":
            path = "\(repository)/pull/\(identifier)"
        case "issues":
            path = "\(repository)/issues/\(identifier)"
        case "commits":
            path = "\(repository)/commit/\(identifier)"
        case "discussions":
            path = "\(repository)/discussions/\(identifier)"
        case "actions" where parts.count >= 6 && parts[4] == "runs":
            guard isSafePathComponent(parts[5]) else { return repositoryURL }
            path = "\(repository)/actions/runs/\(parts[5])"
        case "releases":
            path = "\(repository)/releases"
        default:
            return repositoryURL
        }
        return URL(string: "https://github.com/\(path)")
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_."))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

struct GitHubIncludedResponse: Equatable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

enum GitHubIncludedResponseParser {
    static func parse(_ data: Data) throws -> GitHubIncludedResponse {
        let separators = [Data("\r\n\r\n".utf8), Data("\n\n".utf8)]
        guard let match = separators.compactMap({ separator -> (Range<Data.Index>, Int)? in
            data.range(of: separator).map { ($0, separator.count) }
        }).min(by: { $0.0.lowerBound < $1.0.lowerBound }),
            let headerText = String(
                data: data[..<match.0.lowerBound], encoding: .utf8)
        else { throw GitHubInboxError.invalidOutput }
        let lines = headerText.split(whereSeparator: \.isNewline)
        guard let statusLine = lines.first else { throw GitHubInboxError.invalidOutput }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/"),
            let statusCode = Int(statusParts[1])
        else { throw GitHubInboxError.invalidOutput }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { continue }
            headers[name] = String(value.prefix(1_024))
        }
        let bodyStart = match.0.lowerBound + match.1
        return GitHubIncludedResponse(
            statusCode: statusCode, headers: headers, body: data[bodyStart...])
    }
}
