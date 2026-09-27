// KeychainAccessGroupPropertyTests.swift
//
// Feature: tv-lamp-complication, Property 5: Keychain queries always carry the
// qualified access group and accessibility
//
// Validates Requirements 7.1, 7.2, 7.3.
//
// Property statement (design › Correctness Properties, Property 5): every query
// `LiveKeychainStore` builds contains `kSecAttrAccessGroup` equal to
// `5V4FMXSU55.ch.reber.watchhomecontrol.shared` (team-prefixed), and every write
// carries `kSecAttrAccessibleAfterFirstUnlock`.
//
// This is a pure, no-I/O test: it inspects `LiveKeychainStore.baseQuery` (a
// computed dictionary) and the `LiveKeychainStore.writeAccessible` constant
// rather than calling `saveAPIKey`/`readAPIKey`, so it never touches the
// Security framework and cannot be masked by the -34018 skip that
// `LiveKeychainIntegrationTests` uses for on-device-only behaviour.
//
// A self-contained deterministic RNG drives ≥100 generated (service, account,
// key) triples through the default-configured store.

import Testing
import Foundation
import Security
@testable import WatchHomeControl_Watch_App

struct KeychainAccessGroupPropertyTests {

    /// Small deterministic LCG so failures reproduce (Numerical Recipes constants).
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static func randomIdentifier(_ rng: inout SeededRNG, prefix: String) -> String {
        "\(prefix)-\(UInt32.random(in: 0...UInt32.max, using: &rng))"
    }

    @Test("Property 5: Keychain queries always carry the qualified access group and accessibility")
    func queriesCarryQualifiedAccessGroupAndAccessibility() {
        var rng = SeededRNG(seed: 0x5EED_C0DE_AC65_5001)

        for _ in 0..<150 {
            let service = KeychainAccessGroupPropertyTests.randomIdentifier(&rng, prefix: "service")
            let account = KeychainAccessGroupPropertyTests.randomIdentifier(&rng, prefix: "account")

            // The default-configured store (as used by both the Watch_App and
            // the Widget_Extension) always carries the fully qualified,
            // team-prefixed access group (Req 7.2), regardless of service/account.
            let store = LiveKeychainStore(service: service, account: account)
            let query = store.baseQuery

            #expect(query[kSecAttrAccessGroup as String] as? String
                    == "5V4FMXSU55.ch.reber.watchhomecontrol.shared")
            #expect(query[kSecAttrService as String] as? String == service)
            #expect(query[kSecAttrAccount as String] as? String == account)
        }

        // Every write asserts kSecAttrAccessibleAfterFirstUnlock so a locked
        // watch can still be read by a widget timeline refresh (Req 7.3).
        #expect(LiveKeychainStore.writeAccessible as String
                == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    @Test("Property 5: an explicitly nil access group is never silently qualified")
    func nilAccessGroupIsOmittedNotDefaulted() {
        // The legacy-purge reader passes `accessGroup: nil` deliberately to reach
        // the pre-shared-group item; the resulting query must omit the attribute
        // entirely rather than falling back to the shared group (Req 7.2).
        let store = LiveKeychainStore(accessGroup: nil)
        #expect(store.baseQuery[kSecAttrAccessGroup as String] == nil)
    }
}
