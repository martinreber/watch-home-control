// LegacyStatePurgeExampleTests.swift
//
// Feature: tv-lamp-complication — example (unit) tests for `LegacyStatePurge`.
//
// Validates Requirements 7.9, 7.10.
//
// These are deterministic example tests (not property tests): each case seeds
// fixed doubles and asserts an exact outcome.
//
//   - First call: deletes the legacy Keychain item, clears the legacy
//     `base_url` from `UserDefaults.standard` (isolated suite here), and marks
//     the shared-suite flag (Req 7.9).
//   - Second call: a no-op — does not touch a subsequently paired credential
//     (Req 7.10).
//
// Doubles: two isolated `UserDefaults(suiteName:)` instances (standing in for
// the Shared_Defaults_Suite and `UserDefaults.standard`) and the shared
// `InMemoryKeychainStore` double, so no real Keychain or shared container is
// touched.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct LegacyStatePurgeExampleTests {

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "LegacyStatePurgeExampleTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Req 7.9: first launch deletes the legacy key and Base_URL, and marks the flag")
    func firstRunPurgesLegacyState() {
        let shared = isolatedDefaults("shared")
        let standard = isolatedDefaults("standard")
        standard.set("http://legacy.example.com:8080", forKey: LiveSettingsStore.baseURLKey)
        let legacyKeychain = InMemoryKeychainStore(initialKey: "legacy-key-123")

        let ran = LegacyStatePurge.runIfNeeded(
            sharedDefaults: shared,
            standardDefaults: standard,
            legacyKeychain: legacyKeychain
        )

        #expect(ran)
        #expect(legacyKeychain.readAPIKey() == nil)
        #expect(standard.string(forKey: LiveSettingsStore.baseURLKey) == nil)
        #expect(shared.bool(forKey: LegacyStatePurge.didRunKey))
    }

    @Test("Req 7.10: a second call is a no-op and does not touch a newly paired credential")
    func secondRunIsNoOp() {
        let shared = isolatedDefaults("shared")
        let standard = isolatedDefaults("standard")
        let legacyKeychain = InMemoryKeychainStore(initialKey: "legacy-key-456")

        // First run purges the legacy state and marks the flag.
        #expect(LegacyStatePurge.runIfNeeded(
            sharedDefaults: shared, standardDefaults: standard, legacyKeychain: legacyKeychain
        ))

        // The user re-pairs; a NEW credential now sits under the (simulated)
        // legacy store's location — representing whatever store a later launch
        // would pass in. A second `runIfNeeded` call must leave it untouched.
        try? legacyKeychain.saveAPIKey("freshly-paired-key")

        let ranAgain = LegacyStatePurge.runIfNeeded(
            sharedDefaults: shared, standardDefaults: standard, legacyKeychain: legacyKeychain
        )

        #expect(!ranAgain)
        #expect(legacyKeychain.readAPIKey() == "freshly-paired-key")
    }
}
