// Persistence/BaseURLResolver.swift — pure classification of a stored Base_URL.
//
// The Watch_App and the Widget_Extension must agree on what a stored `base_url`
// string means: absent/blank falls back to the default, a syntactically valid
// absolute http(s) URL is used as configured, and anything else is invalid. This
// is a pure function built on the existing `URLValidator` so both processes
// resolve identically without I/O (Req 3.9, 7.7, 8.2).

import Foundation

/// The outcome of classifying a raw, possibly-stored Base_URL string.
enum BaseURLResolution: Equatable {
    /// A syntactically valid absolute http(s) URL was stored and is used as is.
    case configured(URL)
    /// No value was stored (`nil` or blank); the default Base_URL applies.
    case fallbackDefault(URL)
    /// A value was stored but is not a valid absolute http(s) URL with a host.
    case invalid
}

enum BaseURLResolver {
    /// The default Base_URL used when none is configured (Req 7.7).
    ///
    /// Cleartext HTTP on `:8080` is used as the default because the app performs
    /// no TLS trust handling (`URLSession.shared`, no challenge delegate), so the
    /// backend's self-signed cert on `:8443` cannot be validated on-device
    /// without a trust profile that watchOS does not expose. HTTP on the LAN is
    /// permitted by the ATS `NSAllowsLocalNetworking` exception in Info.plist. A
    /// user can still configure an HTTPS Base_URL manually on the Setup screen.
    static let defaultBaseURL = URL(string: "http://192.168.1.122:8080")!

    /// Classifies `raw` without performing any I/O (Req 10.2 style purity).
    ///
    /// - `nil` or a whitespace-only string resolves to `.fallbackDefault`.
    /// - A string `URLValidator` accepts resolves to `.configured` with the
    ///   parsed URL.
    /// - Anything else resolves to `.invalid`.
    static func resolve(_ raw: String?) -> BaseURLResolution {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .fallbackDefault(defaultBaseURL)
        }

        switch URLValidator.validate(raw) {
        case .success(let url):
            return .configured(url)
        case .failure:
            return .invalid
        }
    }
}
