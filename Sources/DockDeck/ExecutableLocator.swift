import Foundation

/// Finds a CLI the way its module launches it: an explicit override, well-known install
/// locations, then the inherited PATH. Diagnostics must resolve the same binary a module runs.
enum ExecutableLocator {
    static func locate(
        name: String,
        overrideKey: String? = nil,
        preferredPaths: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates = [overrideKey.flatMap { environment[$0] }].compactMap { $0 }
        candidates.append(contentsOf: preferredPaths)
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/\(name)" })
        }
        var seen: Set<String> = []
        return candidates.first {
            var isDirectory: ObjCBool = false
            return seen.insert($0).inserted
                && FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory)
                && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }
}
