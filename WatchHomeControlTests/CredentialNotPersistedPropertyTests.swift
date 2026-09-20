// CredentialNotPersistedPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 16: The credential is never
// persisted outside the Keychain.
//
// Validates Requirements 12.7, 2.2.
//
// (Note: the invoking task referred to this as "Property 7", but design.md ›
// Correctness Properties assigns this statement Property 16. This test matches
// the design's numbering/title, as instructed.)
//
// Property statement (design › Correctness Properties): for ANY successful
// redemption — i.e. any 6-digit Pairing_Code and any API_Key the Backend returns
// on a 200 redeem — after `AppModel.submitSetup` the returned API_Key is present
// in the Keychain store AND does not appear anywhere in the non-secret settings
// storage, and the submitted Pairing_Code is not persisted anywhere.
//
// How the leak is detected: `submitSetup`'s only write to non-secret storage is
// `settings.setBaseURL(_:)`. The test injects a `RecordingSettingsStore` that
// captures EVERY string ever handed to it (the running persisted representation
// of the settings store) into an append-only log. After a successful setup the
// test scans that entire log — every value the settings store was ever asked to
// persist — and asserts that no recorded value equals OR contains the returned
// API_Key, and none equals or contains the submitted Pairing_Code. Substring
// (`.contains`) checks, not just equality, so even partial embedding of the
// secret (e.g. a key smuggled into a URL query) is caught. The secret is then
// confirmed to live only in the in-memory Keychain.
//
// Pure and deterministic: an `InMemoryKeychainStore`, a `RecordingSettingsStore`,
// and a `StubAPIClient` whose `redeemPairingCode` returns a generated key. A
// self-contained splitmix64 generator drives ≥100 iterations with no third-party
// dependency, matching the sibling *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct CredentialNotPersistedPropertyTests {

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

    /// A valid 6-decimal-digit Pairing_Code (what `submitSetup` requires before
    /// it will redeem).
    private static func makeCode(_ rng: inout RNG) -> String {
        var digits = ""
        for _ in 0..<6 { digits.append(Character("\(rng.int(0..<10))")) }
        return digits
    }

    /// Character palettes spanning the input space a returned API_Key can occupy.
    private static let asciiChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let symbolChars = Array("!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~")
    private static let unicodeChars = Array("äöüéèàçßÄÖÜñ日本語한글😀🔑🏠🎵→∑√πµ")

    /// A varied, non-empty API_Key the Backend "returns" on a successful redeem.
    private static func makeReturnedKey(_ rng: inout RNG) -> String {
        let length = rng.int(16..<64)
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

    /// A valid absolute http(s) Base_URL. Must pass `URLValidator` so `submitSetup`
    /// proceeds to redeem and store the key.
    private static func makeValidBaseURL(_ rng: inout RNG) -> String {
        rng.pick([
            "http://192.168.1.122:8080",
            "https://home.example.ch",
            "http://10.0.0.5:8080",
            "https://pi.local:8443",
            "http://watch-home.internal",
        ])
    }

    // MARK: - Test doubles

    /// A `SettingsStore` that records EVERY string ever persisted to it (its
    /// running persisted representation) into an append-only log, so the test can
    /// scan all persisted values for the secret. `baseURL` still round-trips so
    /// `submitSetup` behaves exactly like production.
    private final class RecordingSettingsStore: SettingsStore, @unchecked Sendable {
        private let lock = NSLock()
        private var url: URL
        /// Every value the store was ever asked to persist, in order.
        private var persisted: [String] = []

        init(_ url: URL) { self.url = url }

        var baseURL: URL {
            lock.lock(); defer { lock.unlock() }
            return url
        }

        func setBaseURL(_ newValue: URL) {
            lock.lock(); defer { lock.unlock() }
            url = newValue
            // Record the full persisted representation — both the URL object's
            // absolute string and the raw value — so the scan sees everything the
            // store now holds.
            persisted.append(newValue.absoluteString)
        }

        /// Snapshot of every persisted value plus the current live representation,
        /// for the leak scan.
        func persistedValues() -> [String] {
            lock.lock(); defer { lock.unlock() }
            return persisted + [url.absoluteString]
        }
    }

    /// Returns a generated key from `redeemPairingCode`, emulating a 200 redeem.
    /// Also records the code it was asked to redeem so the test can confirm the
    /// code is passed through transiently and never lands in settings storage.
    private final class StubAPIClient: APIClient, @unchecked Sendable {
        let keyToReturn: String
        private(set) var redeemedCode: String?

        init(keyToReturn: String) { self.keyToReturn = keyToReturn }

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
            redeemedCode = code
            return keyToReturn
        }
    }

    // MARK: - Property 16

    @Test("Property 16: after a successful redemption the returned key lives only in the Keychain and neither the key nor the code is persisted in settings")
    @MainActor
    func credentialNeverPersistedOutsideKeychain() async {
        var rng = RNG(seed: 0x16_C0DE_5EC7_5EED)
        var checked = 0

        for _ in 0..<150 {
            let code = CredentialNotPersistedPropertyTests.makeCode(&rng)
            let returnedKey = CredentialNotPersistedPropertyTests.makeReturnedKey(&rng)
            let baseURL = CredentialNotPersistedPropertyTests.makeValidBaseURL(&rng)

            // Fresh, empty backing stores each iteration.
            let keychain = InMemoryKeychainStore()
            let settings = RecordingSettingsStore(LiveSettingsStore.defaultBaseURL)
            let api = StubAPIClient(keyToReturn: returnedKey)
            let model = AppModel(api: api, keychain: keychain, settings: settings)

            let result = await model.submitSetup(baseURL: baseURL, code: code)

            // Precondition: this is the successful-redemption path.
            #expect(result == .success,
                    "generated inputs must drive a successful redemption")

            // 1. The returned key is present ONLY in the Keychain.
            #expect(keychain.readAPIKey() == returnedKey,
                    "the returned API key must be stored in the Keychain")

            // 2. Scan the entire persisted settings representation: no recorded
            //    value may equal or contain the returned key. `.contains` (not just
            //    ==) catches partial embedding of the secret.
            let persisted = settings.persistedValues()
            for value in persisted {
                #expect(!value.contains(returnedKey),
                        "the API key must never appear in persisted settings; found in \(value.debugDescription)")
            }

            // 3. The submitted Pairing_Code must not be persisted anywhere in
            //    settings either.
            for value in persisted {
                #expect(!value.contains(code),
                        "the Pairing_Code must never be persisted; found in \(value.debugDescription)")
            }

            // 4. Sanity: the code did reach the redeem call transiently (it is
            //    used, just not persisted) and the persisted Base_URL is the
            //    non-secret setting we expect.
            #expect(api.redeemedCode == code)
            #expect(persisted.contains(URL(string: baseURL)!.absoluteString),
                    "the non-secret Base_URL should be the value persisted in settings")

            checked += 1
        }

        #expect(checked >= 100)
    }
}
