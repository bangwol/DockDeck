import Foundation

enum AppResources {
    static let bundle = resolve(in: .main)

    static func resolve(in main: Bundle) -> Bundle {
        if let url = main.url(forResource: "DockDeck_DockDeck", withExtension: "bundle"),
            let resources = Bundle(url: url) { return resources }
        // SwiftPM's generated accessor searches the build tree. Installed apps
        // must use Contents/Resources and remain usable if their bundle is missing.
        return main.bundleURL.pathExtension == "app" ? main : .module
    }
}

enum L10n {
    static func text(_ key: String, bundle: Bundle = AppResources.bundle) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
