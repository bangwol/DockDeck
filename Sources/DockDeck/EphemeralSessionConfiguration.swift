import Foundation

extension URLSessionConfiguration {
    /// Disables caches, cookies, and credential storage so module requests leave no local trace.
    func applyDockDeckPrivacyDefaults(requestTimeout: TimeInterval, resourceTimeout: TimeInterval) {
        requestCachePolicy = .reloadIgnoringLocalCacheData
        urlCache = nil
        httpCookieStorage = nil
        httpShouldSetCookies = false
        urlCredentialStorage = nil
        timeoutIntervalForRequest = requestTimeout
        timeoutIntervalForResource = resourceTimeout
    }

    static func dockDeckEphemeral(
        requestTimeout: TimeInterval, resourceTimeout: TimeInterval
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.applyDockDeckPrivacyDefaults(
            requestTimeout: requestTimeout, resourceTimeout: resourceTimeout)
        return configuration
    }
}
