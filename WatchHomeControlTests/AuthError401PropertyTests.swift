// AuthError401PropertyTests.swift
//
// Feature: apple-watch-home-control, Property 18: A 401 response never mutates
// the stored credential.
//
// Validates Requirements 2.3.
//
// Property statement (design › Correctness Properties, Property 18): *for any*
// authenticated command, when the Backend responds with HTTP 401 the command is
// mapped to an Auth_Error and the stored API key is left unchanged.
//
// How this is exercised: an `AppModel` is seeded with an arbitrary stored API_Key
// K in an `InMemoryKeychainStore`. A `Stub401APIClient` throws
// `APIError.unauthorized` from the authenticated fetch(es) that the poll driver
// issues. Driving `startPolling(lamps:speakers:)` produces a Poll_Cycle whose
// fetch fails with 401; `AppModel` handles it by calling `handleAuthError()`,
// which routes back to the Setup_Screen for re-pairing and stops polling. The
// test then asserts:
//   1. route == .setup   (the 401 was mapped to an Auth_Error / re-pair routing)
//   2. keychain.readAPIKey() == K  (the stored credential is byte-for-byte intact)
// The direct `handleAuthError()` entry point (used by other authenticated
// commands) is asserted the same way, covering the mapping regardless of which
// authenticated call surfaced the 401.
//
// Pure and deterministic: an `InMemoryKeychainStore` pre-seeded with K, a
// `Stub401APIClient` that throws `APIError.unauthorized`, and an in-memory
// `FakeSettingsStore`. A self-contained splitmix64 generator drives ≥100
// iterations with no third-party dependency, matching the sibling
// *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct AuthError401PropertyTests {

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

    /// Character palettes spanning the input space a stored API_Key can occupy.
    private static let asciiChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let symbolChars = Array("!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~")
    private static let unicodeChars = Array("äöüéèàçßÄÖÜñ日本語한글😀🔑🏠🎵→∑√πµ")

    /// A varied, non-empty API_Key already stored in the Keychain (the K whose
    /// integrity the property protects).
    private static func makeStoredKey(_ rng: inout RNG) -> String {
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

    /// A valid absolute http(s) Base_URL for the in-memory settings store.
    private static func makeBaseURL(_ rng: inout RNG) -> URL {
        URL(string: rng.pick([
            "http://192.168.1.122:8080",
            "https://home.example.ch",
            "http://10.0.0.5:8080",
            "https://pi.local:8443",
            "http://watch-home.internal",
        ]))!
    }

    // MARK: - Test doubles

    /// In-memory, mutable `SettingsStore` — no UserDefaults, no shared state.
    private final class FakeSettingsStore: SettingsStore, @unchecked Sendable {
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

    /// An `APIClient` whose authenticated fetches always fail with HTTP 401
    /// (`APIError.unauthorized`), emulating the Backend rejecting the credential.
    private final class Stub401APIClient: APIClient, @unchecked Sendable {
        // Health has no key and is not the path under test; report reachable so
        // it never interferes.
        func checkHealth(timeout: Duration) async throws -> Bool { true }

        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {
            throw APIError.unauthorized
        }
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            throw APIError.unauthorized
        }
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            throw APIError.unauthorized
        }
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] {
            throw APIError.unauthorized
        }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.unauthorized
        }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.unauthorized
        }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.unauthorized
        }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            throw APIError.unauthorized
        }
    }

    // MARK: - Property 18

    @Test("Property 18: a 401 during an authenticated command routes to Setup and leaves the stored API key unchanged")
    @MainActor
    func authError401NeverMutatesStoredCredential() async {
        var rng = RNG(seed: 0x18_C0DE_A117_5EED)
        var checked = 0

        for _ in 0..<150 {
            let storedKey = AuthError401PropertyTests.makeStoredKey(&rng)
            let baseURL = AuthError401PropertyTests.makeBaseURL(&rng)

            // --- Path A: 401 surfacing through the poll driver's authenticated
            // fetch. This exercises the real code path where an authenticated
            // command hits HTTP 401 and AppModel maps it to an Auth_Error.
            do {
                let keychain = InMemoryKeychainStore(initialKey: storedKey)
                let settings = FakeSettingsStore(baseURL)
                let api = Stub401APIClient()
                let model = AppModel(api: api, keychain: keychain, settings: settings)
                model.route = .control

                let lamps = LampViewModel(api: api)
                let speakers = SpeakerViewModel(api: api)

                // A single Poll_Cycle: the lamp/speaker fetch throws 401, so the
                // poll driver invokes handleAuthError() and stops polling.
                model.startPolling(lamps: lamps, speakers: speakers)

                // Wait for the first cycle to run and route back to Setup.
                var spins = 0
                while model.route != .setup && spins < 2000 {
                    await Task.yield()
                    spins += 1
                }
                model.stopPolling()

                // 1. The 401 was mapped to an Auth_Error → routed to Setup.
                #expect(model.route == .setup,
                        "a 401 during a poll must route back to the Setup_Screen")
                // 2. The stored credential is byte-for-byte unchanged.
                #expect(keychain.readAPIKey() == storedKey,
                        "the 401 handling must never delete or overwrite the stored API key")
            }

            // --- Path B: the direct Auth_Error entry point used by other
            // authenticated commands. Same guarantee: route to Setup, key intact.
            do {
                let keychain = InMemoryKeychainStore(initialKey: storedKey)
                let settings = FakeSettingsStore(baseURL)
                let api = Stub401APIClient()
                let model = AppModel(api: api, keychain: keychain, settings: settings)
                model.route = .control

                model.handleAuthError()

                #expect(model.route == .setup,
                        "handleAuthError must route back to the Setup_Screen")
                #expect(keychain.readAPIKey() == storedKey,
                        "handleAuthError must leave the stored API key unchanged")
            }

            checked += 1
        }

        #expect(checked >= 100)
    }
}
