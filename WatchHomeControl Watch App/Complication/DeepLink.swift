import Foundation

enum DeepLink {
    static let scheme = "watchhomecontrol"
    static let setupHost = "setup"
    static let lampsHost = "lamps"
    static let setupURL = URL(string: "watchhomecontrol://setup")!
    static let lampsURL = URL(string: "watchhomecontrol://lamps")!
    static let lampsTargetID = "tv-lamp-control-section"

    static func isSetup(_ url: URL) -> Bool {
        isRoute(url, host: setupHost)
    }

    static func isLamps(_ url: URL) -> Bool {
        isRoute(url, host: lampsHost)
    }

    private static func isRoute(_ url: URL, host: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.caseInsensitiveCompare(scheme) == .orderedSame
            && components.host?.caseInsensitiveCompare(host) == .orderedSame
    }
}