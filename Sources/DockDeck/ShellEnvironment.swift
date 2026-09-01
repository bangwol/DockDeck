import SwiftTerm

enum ShellEnvironment {
    static let executable = "/bin/zsh"

    static func variables() -> [String] {
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        if !environment.contains(where: { $0.hasPrefix("SHELL=") }) {
            environment.append("SHELL=\(executable)")
        }
        return environment
    }
}
