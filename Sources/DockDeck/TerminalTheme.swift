import Cocoa

enum TerminalTheme {
    static let fontSize: CGFloat = 11
    static let padding: CGFloat = 8
    static let defaultCornerRadius: CGFloat = 12

    static let systemFontName = "__system__"

    static let availableFontNames = [
        "MesloLGS NF",
        "MesloLGS Nerd Font",
        "Hack Nerd Font",
        "FiraCode Nerd Font",
        "JetBrainsMono Nerd Font",
        "Menlo",
        systemFontName,
    ]

    static var installedFontNames: [String] {
        availableFontNames.filter { $0 == systemFontName || NSFont(name: $0, size: fontSize) != nil }
    }

    static let defaultFontName: String =
        availableFontNames.first { $0 != systemFontName && NSFont(name: $0, size: fontSize) != nil }
        ?? systemFontName

    static func displayName(forFontName name: String) -> String {
        name == systemFontName ? "SF Mono (System)" : name
    }

    static func font(named name: String?) -> NSFont {
        let resolvedName = name ?? defaultFontName
        if resolvedName == systemFontName {
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        return NSFont(name: resolvedName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}
