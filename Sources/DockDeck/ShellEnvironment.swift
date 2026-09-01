import Foundation
import SwiftTerm

enum ShellEnvironment {
    static let executable = "/bin/zsh"

    private static let compactPromptHook = """
        ZDOTDIR="${DOCKDECK_USER_ZDOTDIR:-$HOME}"
        if [[ -r "$ZDOTDIR/.zshenv" ]]; then
            source "$ZDOTDIR/.zshenv"
        fi
        autoload -Uz add-zsh-hook
        function _dockdeck_compact_prompt {
            PROMPT='%% '
            RPROMPT=''
        }
        add-zsh-hook precmd _dockdeck_compact_prompt
        unset DOCKDECK_USER_ZDOTDIR
        """

    static func variables() -> [String] {
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        if !environment.contains(where: { $0.hasPrefix("SHELL=") }) {
            environment.append("SHELL=\(executable)")
        }
        if let hookDirectory = try? installCompactPromptHook() {
            let userZDOTDIR = value(named: "ZDOTDIR", in: environment) ?? NSHomeDirectory()
            environment.removeAll {
                $0.hasPrefix("ZDOTDIR=") || $0.hasPrefix("DOCKDECK_USER_ZDOTDIR=")
            }
            environment.append("DOCKDECK_USER_ZDOTDIR=\(userZDOTDIR)")
            environment.append("ZDOTDIR=\(hookDirectory.path)")
        }
        return environment
    }

    @discardableResult
    static func installCompactPromptHook(at directory: URL? = nil) throws -> URL {
        let fileManager = FileManager.default
        let hookDirectory: URL
        if let directory {
            hookDirectory = directory
        } else {
            let caches = try fileManager.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            hookDirectory = caches
                .appendingPathComponent("DockDeck", isDirectory: true)
                .appendingPathComponent("Shell", isDirectory: true)
        }

        try fileManager.createDirectory(
            at: hookDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hookDirectory.path)

        let hookURL = hookDirectory.appendingPathComponent(".zshenv")
        if (try? String(contentsOf: hookURL, encoding: .utf8)) != compactPromptHook {
            try compactPromptHook.write(to: hookURL, atomically: true, encoding: .utf8)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hookURL.path)
        return hookDirectory
    }

    private static func value(named name: String, in environment: [String]) -> String? {
        let prefix = "\(name)="
        return environment.first(where: { $0.hasPrefix(prefix) }).map {
            String($0.dropFirst(prefix.count))
        }
    }
}
