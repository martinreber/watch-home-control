// Complication/ComplicationEnvironment.swift — composition root for the loader
// and the toggle service.
//
// Bundles every dependency `TVLampEntryLoader` and `TVLampToggleService` need
// behind protocol/closure seams, so both can run against in-memory doubles in
// tests (Req 10.6) while `.live` wires the real Keychain/UserDefaults/URLSession
// implementations for the Widget_Extension process.

import Foundation

struct ComplicationEnvironment: Sendable {
    /// Reads the API_Key from the Shared_Keychain_Group, or `nil` when absent
    /// or the read fails for any reason (Req 6.1, 6.6).
    var readAPIKey: @Sendable () -> String?
    /// Resolves the Base_URL from the Shared_Defaults_Suite.
    var resolveBaseURL: @Sendable () -> BaseURLResolution
    var api: APIClient
    var refresher: ComplicationRefreshing
    var now: @Sendable () -> Date

    /// Whether an API_Key is currently readable (Req 6.1).
    var pairingCondition: PairingCondition {
        readAPIKey() != nil ? .paired : .unpaired
    }

    static let live: ComplicationEnvironment = {
        let keychain = LiveKeychainStore()
        let settings = LiveSettingsStore()
        return ComplicationEnvironment(
            readAPIKey: { keychain.readAPIKey() },
            resolveBaseURL: {
                BaseURLResolver.resolve(LiveSettingsStore.sharedDefaults.string(forKey: LiveSettingsStore.baseURLKey))
            },
            api: LiveAPIClient(settings: settings, keychain: keychain),
            refresher: LiveComplicationRefresher(),
            now: Date.init
        )
    }()
}
