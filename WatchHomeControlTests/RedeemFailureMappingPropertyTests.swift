// RedeemFailureMappingPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 21: Redeem failure statuses map to
// the correct Pairing_Error without mutating the stored key.
//
// Validates Requirements 12.3, 12.4, 12.5, 12.6.
//
// Property statement (design › Correctness Properties, Property 21): *for any*
// prior stored key K (present or absent) and *any* failing redeem outcome,
// `AppModel.submitSetup(baseURL:code:)` yields the matching `SetupError` and
// leaves the stored API_Key unchanged (still K, or still empty). The mapping,
// per `AppModel.mapRedeemError`, is:
//   - APIError.http(status: 400) -> .malformedCode   (Req 12.3)
//   - APIError.unauthorized      -> .codeInvalid      (Req 12.4)
//   - APIError.http(status: 429) -> .tooManyAttempts  (Req 12.5)
//   - APIError.timeout           -> .redeemTimeout     (Req 12.6)
//   - any other error            -> .redeemFailed
//
// How this is exercised: `submitSetup` is fed a VALID 6-digit Pairing_Code and a
// VALID absolute http(s) Base_URL so the pre-checks (code shape, URL validity)
// pass and control actually reaches `api.redeemPairingCode(...)`. That call is
// wired to throw a chosen `APIError` bucket. The test then asserts:
//   1. result == .failure(expectedMappedError) — the thrown error mapped to the
//      exact SetupError; and
//   2. keychain.readAPIKey() == priorK — the stored credential is byte-for-byte
//      unchanged (still K, or still nil), since the Keychain is written ONLY on
//      a successful redeem.
// Note: the Base_URL IS persisted before redeem (expected, Req 1.6); this
// property is specifically about the KEYCHAIN key being untouched on failure.
//
// Buckets exercised across iterations: http(400), unauthorized (401), http(429),
// timeout, and the "any other error" bucket — assorted other HTTP statuses
// (403/404/409/418/500/502/503) plus network(...) and decoding — all of which
// must map to .redeemFailed.
//
// Pure and deterministic: an `InMemoryKeychainStore` (seeded with K or empty), a
// throwing mock `APIClient`, and an in-memory `SettingsStore`. A self-contained
// splitmix64 generator drives ≥100 iterations with no third-party dependency,
// matching the sibling *PropertyTests convention. @MainActor because AppModel is
// main-actor isolated.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct RedeemFailureMappingPropertyTests {

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

        mutating func bool() -> Bool { next() & 1 == 0 }

        mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }
    }

    // MARK: - Generators

    /// A valid 6-decimal-digit Pairing_Code (Req 1.5) so submitSetup's code
    /// pre-check passes and control reaches redeem.
    private static func makeCode(_ rng: inout RNG) -> String {
        String(format: "%06d", rng.int(0..<1_000_000))
    }

    /// A valid absolute http(s) Base_URL so submitSetup's URL pre-check passes
    /// and control reaches redeem.
    private static func makeBaseURL(_ rng: inout RNG) -> String {
        rng.pick([
            "http://192.168.1.122:8080",
            "https://home.example.ch",
            "http://10.0.0.5:8080",
            "https://pi.local:8443",
            "http://watch-home.internal",
            "https://sub.example.org:65535",
            "http://127.0.0.1:8080",
        ])
    }

    /// Character palettes for a varied, non-empty stored API_Key K.
    private static let asciiChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let symbolChars = Array("!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~")
    private static let unicodeChars = Array("äöüéèàçßÄÖÜñ日本語한글😀🔑🏠🎵→∑√πµ")

    /// A varied, non-empty API_Key already stored in the Keychain (the K whose
    /// integrity the property protects). Returns `nil` sometimes so the
    /// "absent key" case is covered too.
    private static func makePriorKey(_ rng: inout RNG) -> String? {
        // ~1 in 4 iterations: no stored key (fresh pairing).
        if rng.int(0..<4) == 0 { return nil }
        let length = rng.int(1..<64)
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

    /// A redeem failure and its expected `SetupError` mapping, per
    /// `AppModel.mapRedeemError`.
    private struct FailureCase {
        let label: String
        let error: APIError
        let expected: SetupError
    }

    /// Every bucket the mapping must cover. The four named buckets plus an
    /// assortment of "other" errors that all fold into `.redeemFailed`.
    private static let failureCases: [FailureCase] = [
        // Named buckets.
        FailureCase(label: "http(400)",   error: .http(status: 400), expected: .malformedCode),
        FailureCase(label: "unauthorized(401)", error: .unauthorized, expected: .codeInvalid),
        FailureCase(label: "http(429)",   error: .http(status: 429), expected: .tooManyAttempts),
        FailureCase(label: "timeout",     error: .timeout,            expected: .redeemTimeout),
        // "Any other error" bucket -> .redeemFailed.
        FailureCase(label: "http(403)",   error: .http(status: 403), expected: .redeemFailed),
        FailureCase(label: "http(404)",   error: .http(status: 404), expected: .redeemFailed),
        FailureCase(label: "http(409)",   error: .http(status: 409), expected: .redeemFailed),
        FailureCase(label: "http(418)",   error: .http(status: 418), expected: .redeemFailed),
        FailureCase(label: "http(500)",   error: .http(status: 500), expected: .redeemFailed),
        FailureCase(label: "http(502)",   error: .http(status: 502), expected: .redeemFailed),
        FailureCase(label: "http(503)",   error: .http(status: 503), expected: .redeemFailed),
        FailureCase(label: "network",     error: .network("connection refused"), expected: .redeemFailed),
        FailureCase(label: "decoding",    error: .decoding,           expected: .redeemFailed),
    ]

    // MARK: - Test doubles

    /// In-memory, mutable `SettingsStore` — no UserDefaults, no shared state.
    private final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
        private let lock = NSLock()
        private var url: URL
        init(_ url: URL) { self.url = url }
        var baseURL: URL {
            lock.lock(); defer { lock.unlock() }
            return url
        }
        func setBaseURL(_ newValue: URL) {
            lock.lock(); defer { lock.unlock() }
            url = newValue
        }
    }

    /// An `APIClient` whose `redeemPairingCode` always throws the configured
    /// `APIError`. No other endpoint is exercised by `submitSetup` before the
    /// failing redeem, so the rest either report benign values or trap if called.
    private final class RedeemFailingAPIClient: APIClient, @unchecked Sendable {
        let redeemError: APIError
        init(redeemError: APIError) { self.redeemError = redeemError }

        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            throw redeemError
        }

        // Health is only reached on the SUCCESS path (after the key is stored),
        // which this test never takes. Report reachable defensively.
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
    }

    // MARK: - Property 21

    @Test("Property 21: redeem failure statuses map to the correct Pairing_Error without mutating the stored key")
    @MainActor
    func redeemFailureMapsAndLeavesKeyUnchanged() async {
        var rng = RNG(seed: 0x21_C0DE_5EED_0021)
        var checked = 0

        for _ in 0..<200 {
            let priorKey = RedeemFailureMappingPropertyTests.makePriorKey(&rng)
            let baseURL = RedeemFailureMappingPropertyTests.makeBaseURL(&rng)
            let code = RedeemFailureMappingPropertyTests.makeCode(&rng)
            let failure = RedeemFailureMappingPropertyTests.failureCases[
                rng.int(0..<RedeemFailureMappingPropertyTests.failureCases.count)
            ]

            // Seed the Keychain with K (present) or empty (absent).
            let keychain = InMemoryKeychainStore(initialKey: priorKey)
            let settings = InMemorySettingsStore(LiveSettingsStore.defaultBaseURL)
            let api = RedeemFailingAPIClient(redeemError: failure.error)
            let model = AppModel(api: api, keychain: keychain, settings: settings)

            let result = await model.submitSetup(baseURL: baseURL, code: code)

            // 1. The thrown redeem error mapped to exactly the expected SetupError.
            #expect(result == .failure(failure.expected),
                    "redeem failure \(failure.label) must map to \(failure.expected), got \(result)")

            // 2. The stored credential is byte-for-byte unchanged (still K, or still nil).
            #expect(keychain.readAPIKey() == priorKey,
                    "redeem failure \(failure.label) must leave the stored API key unchanged (expected \(String(describing: priorKey)), got \(String(describing: keychain.readAPIKey())))")

            checked += 1
        }

        #expect(checked >= 100, "expected at least 100 property iterations, ran \(checked)")
    }
}
