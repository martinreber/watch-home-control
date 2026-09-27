// DeepLinkPropertyTests.swift
//
// Feature: tv-lamp-complication, Property 8: Only the setup deep link is
// accepted
//
// Validates Requirements 6.2, 6.3, 11.6.
//
// Property statement (design › Correctness Properties, Property 8): for
// generated URLs, `DeepLink.isSetup` is true exactly for
// `watchhomecontrol://setup` (scheme and host compared case-insensitively) and
// false for every other scheme, host, or path.
//
// Pure and deterministic: no I/O. A self-contained RNG drives ≥100 generated
// URLs spanning matching (varied casing) and non-matching scheme/host/path
// combinations.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct DeepLinkPropertyTests {

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

    private static func randomCasing(_ s: String, _ rng: inout SeededRNG) -> String {
        String(s.map { Bool.random(using: &rng) ? Character($0.uppercased()) : Character($0.lowercased()) })
    }

    private static let otherSchemes = ["https", "http", "wss", "otherapp", "file"]
    private static let otherHosts = ["config", "control", "home", "pairing", ""]
    private static let paths = ["", "/", "/setup", "/extra"]

    @Test("Property 8: only watchhomecontrol://setup is accepted, matched case-insensitively")
    func onlySetupDeepLinkIsAccepted() {
        var rng = SeededRNG(seed: 0xDEE9_1114_0008_0008)

        for _ in 0..<150 {
            if Bool.random(using: &rng) {
                // A matching URL with randomly varied scheme/host casing must
                // be accepted regardless of a trailing slash.
                let scheme = DeepLinkPropertyTests.randomCasing(DeepLink.scheme, &rng)
                let host = DeepLinkPropertyTests.randomCasing(DeepLink.setupHost, &rng)
                let path = Bool.random(using: &rng) ? "" : "/"
                let url = URL(string: "\(scheme)://\(host)\(path)")!

                #expect(DeepLink.isSetup(url), "expected \(url) to be accepted")
            } else {
                // A non-matching scheme, host, or both must be rejected.
                let scheme = DeepLinkPropertyTests.otherSchemes[
                    Int.random(in: 0..<DeepLinkPropertyTests.otherSchemes.count, using: &rng)]
                let host = DeepLinkPropertyTests.otherHosts[
                    Int.random(in: 0..<DeepLinkPropertyTests.otherHosts.count, using: &rng)]
                let path = DeepLinkPropertyTests.paths[
                    Int.random(in: 0..<DeepLinkPropertyTests.paths.count, using: &rng)]

                // Skip the astronomically unlikely case both happen to match.
                guard scheme.caseInsensitiveCompare(DeepLink.scheme) != .orderedSame
                        || host.caseInsensitiveCompare(DeepLink.setupHost) != .orderedSame else {
                    continue
                }

                let url = URL(string: "\(scheme)://\(host)\(path)")!
                #expect(!DeepLink.isSetup(url), "expected \(url) to be rejected")
            }
        }

        // Explicit reference cases.
        #expect(DeepLink.isSetup(DeepLink.setupURL))
        #expect(DeepLink.isSetup(URL(string: "WATCHHOMECONTROL://SETUP")!))
        #expect(!DeepLink.isSetup(URL(string: "https://setup")!))
        #expect(!DeepLink.isSetup(URL(string: "watchhomecontrol://config")!))
    }
}
