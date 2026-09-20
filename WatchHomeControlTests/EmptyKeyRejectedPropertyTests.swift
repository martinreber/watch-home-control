// EmptyKeyRejectedPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 17: An empty or whitespace key is
// rejected without disturbing the stored key.
//
// Validates Requirements 1.5, 12.3.
//
// Property statement (design › Correctness Properties, rescoped to the
// pairing-code flow by task 18.8): for ANY already-stored API_Key `K` and ANY
// candidate Pairing_Code that is empty or consists solely of whitespace, the
// Setup submit path rejects it as malformed WITHOUT issuing a redeem request and
// WITHOUT mutating the Keychain — afterwards the Keychain still holds exactly
// `K` (no delete, no overwrite).
//
// `AppModel.submitSetup` trims the code and requires exactly six ASCII decimal
// digits before doing anything else; an empty or whitespace-only code can never
// satisfy that, so it must short-circuit to `.failure(.malformedCode)` before
// the Base_URL is persisted or `api.redeemPairingCode` is called (Req 1.5/12.3,
// Property 17).
//
// The test is pure and deterministic: an in-memory `InMemoryKeychainStore`
// pre-seeded with `K`, a spy `SpyAPIClient` that records whether redeem was
// invoked (and would fail loudly if it were), and an in-memory `SettingsStore`.
// A tiny self-contained splitmix64 generator drives ≥100 iterations without a
// third-party dependency, matching the sibling *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct EmptyKeyRejectedPropertyTests {

    // MARK: - Deterministic pseudo-random generator

    /// Self-contained splitmix64 generator: reproducible cases, no dependency.
    private struct RNG {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func int(_ range: Range<Int>) -> Int {
            let span = UInt64(range.count)
            return range.lowerBound + Int(next() % span)
        }

        mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }
    }

    // MARK: - Generators

    /// The whitespace/newline palette an "empty or whitespace-only" candidate can
    /// be built from. `.whitespacesAndNewlines` (what `submitSetup` trims with)
    /// covers exactly these code points, so any string of them trims to "".
    private static let whitespaceChars: [Character] =
        [" ", "\t", "\n", "\r", "\u{000B}" /* VT */, "\u{000C}" /* FF */,
         "\u{00A0}" /* NBSP */, "\u{2007}" /* figure space */, "\u{202F}" /* narrow NBSP */]

    /// Produces a candidate Pairing_Code that is empty or whitespace-only. Roughly
    /// one in six is the empty string; the rest are 1–10 whitespace characters
    /// drawn from the palette above.
    private static func makeBlankCode(_ rng: inout RNG) -> String {
        if rng.int(0..<6) == 0 { return "" }
        let length = rng.int(1..<11)
        var chars: [Character] = []
        chars.reserveCapacity(length)
        for _ in 0..<length { chars.append(rng.pick(whitespaceChars)) }
        return String(chars)
    }

    /// Character palettes for the pre-stored API_Key `K` so the "unchanged"
    /// assertion is exercised across varied secrets.
    private static let asciiChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let symbolChars = Array("!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~")
    private static let unicodeChars = Array("äöüéèàçßÄÖÜñ日本語한글😀🔑🏠🎵→∑√πµ")

    /// A varied, non-empty stored API_Key.
    private static func makeStoredKey(_ rng: inout RNG) -> String {
        let length = rng.int(8..<48)
        var chars: [Character] = []
        chars.reserveCapacity(length)
        for _ in 0..<length {
            switch rng.int(0..<10) {
            case 0...6: chars.append(rng.pick(asciiChars))
            case 7...8: chars.append(rng.pick(symbolChars))
            default:    chars.append(rng.pick(unicodeChars))
            }
        }
        return String(chars)
    }

    /// A varied Base_URL string. Includes valid and invalid forms — the property
    /// must hold regardless, because the malformed-code check precedes URL
    /// validation, so no candidate here ever advances past the code guard.
    private static func makeBaseURL(_ rng: inout RNG) -> String {
        rng.pick([
            "http://192.168.1.122:8080",
            "https://home.example.ch",
            "http://10.0.0.5:8080",
            "not a url",
            "",
            "ftp://example.com",
        ])
    }

    // MARK: - Test doubles

    /// Records whether `redeemPairingCode` was ever called. The property requires
    /// that a blank code is rejected BEFORE any redeem is issued, so any
    /// invocation is a violation; the client fails loudly if called.
    ///
    /// No lock is used: redeem is never actually invoked for a blank code, and
    /// the whole test runs single-threaded on the main actor, so plain mutable
    /// state under `@unchecked Sendable` is safe (and `NSLock` is unavailable
    /// from async contexts).
    private final class SpyAPIClient: APIClient, @unchecked Sendable {
        private(set) var redeemCalled = false

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { [] }
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            throw APIError.decoding
        }
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { [] }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.decoding
        }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.decoding
        }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.decoding
        }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            // Should never be reached for a blank code. Record the call and return
            // a sentinel that would obviously overwrite `K`, so a spurious call is
            // caught by both the `redeemCalled` and "stored key unchanged" checks.
            redeemCalled = true
            return "REDEEM-SHOULD-NOT-HAVE-BEEN-CALLED"
        }
    }

    /// In-memory `SettingsStore` so nothing touches `UserDefaults`.
    private final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
        private var url: URL
        init(_ url: URL) { self.url = url }
        var baseURL: URL { url }
        func setBaseURL(_ newValue: URL) { url = newValue }
    }

    // MARK: - Property 17

    @Test("Property 17: a blank Pairing_Code is rejected without issuing a redeem or disturbing the stored key")
    @MainActor
    func blankCodeRejectedLeavesStoredKeyIntact() async {
        var rng = RNG(seed: 0x17_B1A4_C0DE_5EED)
        var checked = 0

        for _ in 0..<150 {
            let storedKey = EmptyKeyRejectedPropertyTests.makeStoredKey(&rng)
            let blankCode = EmptyKeyRejectedPropertyTests.makeBlankCode(&rng)
            let baseURL = EmptyKeyRejectedPropertyTests.makeBaseURL(&rng)

            // Pre-seed the Keychain with K (the "already-stored key").
            let keychain = InMemoryKeychainStore(initialKey: storedKey)
            let api = SpyAPIClient()
            let settings = InMemorySettingsStore(LiveSettingsStore.defaultBaseURL)
            let model = AppModel(api: api, keychain: keychain, settings: settings)

            let result = await model.submitSetup(baseURL: baseURL, code: blankCode)

            // 1. Rejected as malformed (empty/whitespace can never be 6 digits).
            #expect(result == .failure(.malformedCode),
                    "blank code \(blankCode.debugDescription) must be rejected as .malformedCode")

            // 2. No redeem request was issued (rejection precedes any network call).
            #expect(api.redeemCalled == false,
                    "a blank code must be rejected before any redeem request is issued")

            // 3. The Keychain still holds exactly K — no delete, no overwrite.
            #expect(keychain.readAPIKey() == storedKey,
                    "stored key must be left exactly unchanged after a rejected blank code")

            // 4. Route was not advanced to control (still setup).
            #expect(model.route == .setup,
                    "a rejected submission must not advance to the control screen")

            checked += 1
        }

        #expect(checked >= 100)
    }
}
