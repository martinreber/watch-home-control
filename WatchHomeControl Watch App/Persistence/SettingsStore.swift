// Persistence/SettingsStore.swift — non-secret Base_URL persistence.
//
// The Base_URL is a non-secret setting persisted in `UserDefaults` (the API key
// lives only in the Keychain). It is stored in the Shared_Defaults_Suite (App
// Group) so the Watch_App and the widget extension — a separate process — read
// and write the same value (Req 7.4). The store returns the default value when
// no URL has been persisted or when the persisted string cannot be parsed back
// into a valid URL (Req 1.6/1.7, 7.7), via the shared, pure `BaseURLResolver`.

import Foundation

/// Persists and reads the configurable Base_URL the Watch_App targets.
protocol SettingsStore: Sendable {
    /// The configured Base_URL, defaulting to `https://192.168.1.122:8443` when
    /// absent or unparseable (Req 1.7).
    var baseURL: URL { get }

    /// Persists `url` as the Base_URL for use on subsequent launches (Req 1.6).
    func setBaseURL(_ url: URL)
}

/// `UserDefaults`-backed `SettingsStore`, reading/writing the Shared_Defaults_Suite.
final class LiveSettingsStore: SettingsStore, @unchecked Sendable {
    /// The default Base_URL used when none is configured (Req 1.7).
    static let defaultBaseURL = BaseURLResolver.defaultBaseURL

    /// The App Group identifier backing the Shared_Defaults_Suite (Req 7.4).
    static let appGroupID = "group.ch.reber.watchhomecontrol"

    static let baseURLKey = "base_url"

    /// The shared suite both the Watch_App and the widget extension read from.
    /// Falls back to `.standard` only if the App Group entitlement is somehow
    /// missing (e.g. a debug build without the capability), so the app still runs.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = LiveSettingsStore.sharedDefaults) {
        self.defaults = defaults
    }

    var baseURL: URL {
        switch BaseURLResolver.resolve(defaults.string(forKey: Self.baseURLKey)) {
        case .configured(let url):
            return url
        case .fallbackDefault(let url):
            return url
        case .invalid:
            // The app itself never persists an invalid Base_URL (Req 1.8), so an
            // invalid stored value can only be external tampering; behave exactly
            // as if nothing were stored rather than surfacing a broken URL.
            return Self.defaultBaseURL
        }
    }

    func setBaseURL(_ url: URL) {
        defaults.set(url.absoluteString, forKey: Self.baseURLKey)
    }
}
