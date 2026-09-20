// KeychainRoundTripPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 15: API key save round-trips
// through the Keychain.
//
// Validates Requirements 1.4, 2.5.
//
// Uses Swift Testing (Apple's first-party framework) with a generator-driven
// approach. A tiny, self-contained splitmix64 generator produces a large,
// reproducible sample of varied API-key strings (ASCII, unicode, long strings,
// empty, whitespace, symbols). Each property runs a minimum of 100 generated
// iterations.
//
// The unit under test is `InMemoryKeychainStore`, the in-memory `KeychainStore`
// double that mirrors `LiveKeychainStore`'s create/replace/read/delete
// semantics without the Security framework, so the round-trip runs
// deterministically off-device. (Task 7.5 covers the concrete SecItem-based
// `LiveKeychainStore` on-device.)

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct KeychainRoundTripPropertyTests {

    // MARK: - Deterministic pseudo-random generator

    /// A tiny, self-contained splitmix64-style generator so cases are
    /// reproducible and require no third-party dependency.
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

    // MARK: - API-key generator

    /// Character palettes spanning the input space an API_Key string can occupy:
    /// plain ASCII, symbols/punctuation, whitespace, and multi-byte unicode.
    private static let asciiChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let symbolChars = Array("!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~")
    private static let whitespaceChars = Array(" \t\n\r")
    private static let unicodeChars = Array("äöüéèàçßÄÖÜñ日本語한글emoji😀🔑🏠🎵→∑√πµ")

    /// Produces a varied API-key string. Roughly one in eight is a fixed edge
    /// case (empty, pure whitespace, or a long padded string) so those corners
    /// are always exercised alongside the random mixes.
    private static func makeAPIKey(_ rng: inout RNG) -> String {
        switch rng.int(0..<8) {
        case 0:
            return "" // empty
        case 1:
            return String(repeating: " ", count: rng.int(1..<8)) // pure whitespace
        case 2:
            // A long string (up to a few hundred chars) of mixed characters.
            let length = rng.int(200..<400)
            return randomMixed(length: length, &rng)
        default:
            let length = rng.int(1..<64)
            return randomMixed(length: length, &rng)
        }
    }

    /// Builds a string of the given length by drawing from a random blend of the
    /// ASCII, symbol, whitespace, and unicode palettes.
    private static func randomMixed(length: Int, _ rng: inout RNG) -> String {
        var chars: [Character] = []
        chars.reserveCapacity(length)
        for _ in 0..<length {
            switch rng.int(0..<10) {
            case 0...5: chars.append(rng.pick(asciiChars))
            case 6...7: chars.append(rng.pick(symbolChars))
            case 8:     chars.append(rng.pick(whitespaceChars))
            default:    chars.append(rng.pick(unicodeChars))
            }
        }
        return String(chars)
    }

    // MARK: - Property 15

    @Test("Property 15: saving an API key round-trips through the in-memory Keychain")
    func saveRoundTrips() {
        var rng = RNG(seed: 0x15_0DEF_A17E_C0DE)
        var checked = 0
        for _ in 0..<150 {
            let key = KeychainRoundTripPropertyTests.makeAPIKey(&rng)
            // Fresh store per iteration for full isolation.
            let store = InMemoryKeychainStore()

            #expect(throws: Never.self) {
                try store.saveAPIKey(key)
            }
            #expect(store.readAPIKey() == key,
                    "expected readAPIKey() to return exactly the saved key")
            checked += 1
        }
        #expect(checked >= 100)
    }

    @Test("Property 15: saving a second key replaces the first (last write wins)")
    func saveReplacesPriorKey() {
        var rng = RNG(seed: 0x15_5EC0_7C15_ABCD)
        var checked = 0
        for _ in 0..<150 {
            let first = KeychainRoundTripPropertyTests.makeAPIKey(&rng)
            let second = KeychainRoundTripPropertyTests.makeAPIKey(&rng)
            let store = InMemoryKeychainStore()

            #expect(throws: Never.self) {
                try store.saveAPIKey(first)
            }
            #expect(store.readAPIKey() == first)

            #expect(throws: Never.self) {
                try store.saveAPIKey(second)
            }
            // Replace semantics: the second save fully supersedes the first.
            #expect(store.readAPIKey() == second,
                    "expected the second saved key to replace the first")
            checked += 1
        }
        #expect(checked >= 100)
    }
}
