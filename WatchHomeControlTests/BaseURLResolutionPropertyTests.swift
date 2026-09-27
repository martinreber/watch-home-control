// BaseURLResolutionPropertyTests.swift
//
// Feature: tv-lamp-complication, Property 3: Base_URL resolution classifies
// absent, valid, and invalid values
//
// Validates Requirements 3.9, 7.7, 8.2.
//
// Property statement (design › Correctness Properties, Property 3): for
// generated raw strings, `BaseURLResolver.resolve` returns `.fallbackDefault`
// exactly for `nil`/blank, `.configured` exactly for strings `URLValidator`
// accepts, and `.invalid` otherwise; `.configured` round-trips the parsed URL.
//
// Pure and deterministic: no I/O, no stores. A self-contained RNG drives ≥100
// generated raw strings spanning nil, blank/whitespace, valid http(s) URLs, and
// a range of invalid strings (matching `URLValidatorPropertyTests`' generators
// for consistency with the existing validator's accepted/rejected space).

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct BaseURLResolutionPropertyTests {

    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private enum Case {
        case absent
        case blank(String)
        case valid(String)
        case invalid(String)
    }

    private static let validSamples = [
        "http://192.168.1.122:8080",
        "https://192.168.1.122:8443",
        "https://home.example.ch",
        "http://10.0.0.5:8080/",
        "https://pi.local:8443",
    ]

    private static let invalidSamples = [
        "not a url",
        "ftp://example.com",
        "example.com",
        "http://",
        "https://",
        "://missing-scheme",
        "http:// spaced host.com",
    ]

    private static func nextCase(_ rng: inout SeededRNG) -> Case {
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: return .absent
        case 1: return .blank(Bool.random(using: &rng) ? "" : "   \t  ")
        case 2: return .valid(validSamples[Int.random(in: 0..<validSamples.count, using: &rng)])
        default: return .invalid(invalidSamples[Int.random(in: 0..<invalidSamples.count, using: &rng)])
        }
    }

    @Test("Property 3: Base_URL resolution classifies absent, valid, and invalid values")
    func resolvesEveryClassCorrectly() {
        var rng = SeededRNG(seed: 0xBA5E_0121_DEFA_0071)

        for _ in 0..<150 {
            switch BaseURLResolutionPropertyTests.nextCase(&rng) {
            case .absent:
                #expect(BaseURLResolver.resolve(nil) == .fallbackDefault(BaseURLResolver.defaultBaseURL))

            case .blank(let raw):
                #expect(BaseURLResolver.resolve(raw) == .fallbackDefault(BaseURLResolver.defaultBaseURL))

            case .valid(let raw):
                guard case .configured(let url) = BaseURLResolver.resolve(raw) else {
                    Issue.record("expected .configured for valid input \(raw)")
                    continue
                }
                // Round-trips whatever URLValidator itself would have parsed.
                if case .success(let expected) = URLValidator.validate(raw) {
                    #expect(url == expected)
                } else {
                    Issue.record("URLValidator disagreed with the generator for \(raw)")
                }

            case .invalid(let raw):
                #expect(BaseURLResolver.resolve(raw) == .invalid)
            }
        }
    }
}
