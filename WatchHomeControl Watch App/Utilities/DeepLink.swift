// Utilities/DeepLink.swift — the Setup_Deep_Link the Complication opens.
//
// While Unpaired, the Complication opens the Watch_App instead of invoking the
// Toggle_Intent (Req 6.2). `isSetup(_:)` is the pure predicate `RootView` uses
// to route an incoming URL to the Setup screen, matching scheme and host
// case-insensitively so `watchhomecontrol://setup` is the only accepted link.

import Foundation

enum DeepLink {
    static let scheme = "watchhomecontrol"
    static let setupHost = "setup"
    static let setupURL = URL(string: "watchhomecontrol://setup")!

    /// Whether `url` is the Setup_Deep_Link. Pure: no I/O.
    static func isSetup(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.caseInsensitiveCompare(scheme) == .orderedSame
            && components.host?.caseInsensitiveCompare(setupHost) == .orderedSame
    }
}
