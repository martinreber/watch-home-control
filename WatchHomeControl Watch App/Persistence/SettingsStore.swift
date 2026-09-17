// Persistence/SettingsStore.swift — non-secret Base_URL persistence.
//
// The Base_URL is a non-secret setting persisted in UserDefaults (the API key
// lives only in the Keychain). The store returns the default value when no URL
// has been persisted or when the persisted string cannot be parsed back into a
// valid URL (Req 1.6/1.7).

import Foundation

/// Persists and reads the configurable Base_URL the Watch_App targets.
protocol SettingsStore: Sendable {
    /// The configured Base_URL, defaulting to `http://192.168.1.122:8080` when
    /// absent or unparseable (Req 1.7).
    var baseURL: URL { get }

    /// Persists `url` as the Base_URL for use on subsequent launches (Req 1.6).
    func setBaseURL(_ url: URL)
}

/// `UserDefaults`-backed `SettingsStore`.
///
/// The Base_URL is stored as its string representation and parsed back on read;
/// any absent or unparseable value falls back to the default (Req 1.6/1.7).
final class LiveSettingsStore: SettingsStore, @unchecked Sendable {
    /// The default Base_URL used when none is configured (Req 1.7).
    static let defaultBaseURL = URL(string: "http://192.168.1.122:8080")!

    private static let baseURLKey = "base_url"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var baseURL: URL {
        guard let raw = defaults.string(forKey: Self.baseURLKey),
              let url = URL(string: raw)
        else {
            return Self.defaultBaseURL
        }
        return url
    }

    func setBaseURL(_ url: URL) {
        defaults.set(url.absoluteString, forKey: Self.baseURLKey)
    }
}
