// Persistence/LegacyStatePurge.swift — one-time deletion of pre-sharing state.
//
// This version moves the API_Key into a shared Keychain access group and the
// Base_URL into a shared App Group UserDefaults suite. There is no migration:
// a credential or Base_URL stored under the OLD, non-shared locations is
// deleted (never copied) on first launch, and the user re-pairs from the Setup
// screen (Req 7.9). The deletion is idempotent and runs at most once per
// install, so a credential paired afterwards — stored under the new shared
// locations — is never touched by a later launch (Req 7.10).

import Foundation

enum LegacyStatePurge {
    /// Flag key, stored in the Shared_Defaults_Suite, recording that the purge
    /// already ran for this install.
    static let didRunKey = "legacy_state_purged_shared_v1"

    /// Runs the one-time legacy purge if it has not already run.
    ///
    /// - Parameters:
    ///   - sharedDefaults: The Shared_Defaults_Suite holding the didRun flag.
    ///   - standardDefaults: Where the pre-sharing Base_URL was stored.
    ///   - legacyKeychain: A `KeychainStore` reaching the pre-sharing (default
    ///     access group) API_Key item — i.e. `LiveKeychainStore(accessGroup: nil)`.
    /// - Returns: `true` if the purge ran (first launch after upgrade), `false`
    ///   if it was already done on a prior launch (no-op).
    @discardableResult
    static func runIfNeeded(
        sharedDefaults: UserDefaults = LiveSettingsStore.sharedDefaults,
        standardDefaults: UserDefaults = .standard,
        legacyKeychain: KeychainStore = LiveKeychainStore(accessGroup: nil)
    ) -> Bool {
        guard !sharedDefaults.bool(forKey: didRunKey) else {
            return false
        }

        // Best-effort: a failure to delete the legacy Keychain item must not
        // block marking the purge as done, or every future launch would retry
        // and keep re-presenting Setup even after a successful re-pair.
        try? legacyKeychain.deleteAPIKey()
        standardDefaults.removeObject(forKey: LiveSettingsStore.baseURLKey)

        sharedDefaults.set(true, forKey: didRunKey)
        return true
    }
}
