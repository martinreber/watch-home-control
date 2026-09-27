// TVLampSelectionPropertyTests.swift
//
// Feature: tv-lamp-complication, Property 1: TV-Lampe selection returns the
// first case-insensitive "TV-Lampe" match or nothing
//
// Validates Requirements 4.1, 4.2, 4.3, 4.4, 4.5, 10.1.
//
// Property statement (design › Correctness Properties, Property 1): for any
// generated lamp list (empty, no match, one match, several matches, mixed
// `friendly_name` present/empty/absent), `TVLampSelector.select` returns
// `.resolved` with the first lamp whose `displayName` contains "TV-Lampe"
// ignoring case, and `.unresolved` when none does. Pure: identical input yields
// identical output, no I/O.
//
// A self-contained deterministic RNG drives ≥100 generated lists, plus explicit
// edge cases (empty, single, many, and a list containing several matches so the
// "first match wins" rule is exercised).

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct TVLampSelectionPropertyTests {

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

    private static func makeLamp(
        id: String,
        friendlyName: String?,
        power: Bool,
        rng: inout SeededRNG
    ) -> LampDTO {
        LampDTO(
            id: id,
            friendlyName: friendlyName,
            type: Bool.random(using: &rng) ? "ceiling" : nil,
            state: LampState(power: power)
        )
    }

    /// Casing variants of the needle so the match is proven case-insensitive.
    private static let needleCasings = ["TV-Lampe", "tv-lampe", "Tv-Lampe", "TV-LAMPE", "tV-lAmPe"]

    /// Non-matching display names, including near-misses (bare "TV", no dash).
    private static let nonMatchingNames = [
        "Deckenlampe", "Stehlampe Wohnzimmer", "Kueche", "TV", "TVLampe",
        "Lampe TV Ecke", "Schreibtischlampe",
    ]

    private static func matchingName(_ rng: inout SeededRNG) -> String {
        let needle = needleCasings[Int.random(in: 0..<needleCasings.count, using: &rng)]
        // Sometimes embed the needle inside a larger string to prove substring
        // (not exact-equality) matching.
        return Bool.random(using: &rng) ? needle : "Wohnzimmer \(needle) rechts"
    }

    @Test("Property 1: TV-Lampe selection returns the first case-insensitive match or nothing")
    func selectsFirstMatchOrUnresolved() {
        var rng = SeededRNG(seed: 0x7157_0001_1A47_5EED)

        // Explicit edge cases first.
        #expect(TVLampSelector.select(from: []) == .unresolved)

        let onlyMiss = TVLampSelectionPropertyTests.makeLamp(
            id: "l1", friendlyName: "Deckenlampe", power: true, rng: &rng)
        #expect(TVLampSelector.select(from: [onlyMiss]) == .unresolved)

        // Randomized cases.
        for _ in 0..<150 {
            let count = Int.random(in: 0..<8, using: &rng)
            var lamps: [LampDTO] = []
            var expectedFirstMatchIndex: Int?

            for i in 0..<count {
                let isMatch = Bool.random(using: &rng)
                let power = Bool.random(using: &rng)

                // friendly_name present / empty / absent (Req 4.4).
                let friendlyName: String?
                let effectiveDisplayName: String
                switch Int.random(in: 0..<3, using: &rng) {
                case 0:
                    let name = isMatch
                        ? TVLampSelectionPropertyTests.matchingName(&rng)
                        : TVLampSelectionPropertyTests.nonMatchingNames[
                            Int.random(in: 0..<TVLampSelectionPropertyTests.nonMatchingNames.count, using: &rng)]
                    friendlyName = name
                    effectiveDisplayName = name
                case 1:
                    friendlyName = ""
                    // Empty friendly_name falls back to id (Req 4.4); force the
                    // id itself to carry the match/non-match.
                    effectiveDisplayName = "lamp-\(i)"
                default:
                    friendlyName = nil
                    effectiveDisplayName = "lamp-\(i)"
                }

                let id = (friendlyName == "" || friendlyName == nil)
                    ? (isMatch ? TVLampSelectionPropertyTests.matchingName(&rng) : effectiveDisplayName)
                    : "id-\(i)"

                let lamp = TVLampSelectionPropertyTests.makeLamp(
                    id: id, friendlyName: friendlyName, power: power, rng: &rng)

                let actuallyMatches = lamp.displayName.range(
                    of: TVLampSelector.nameNeedle, options: .caseInsensitive) != nil
                if actuallyMatches && expectedFirstMatchIndex == nil {
                    expectedFirstMatchIndex = lamps.count
                }
                lamps.append(lamp)
            }

            let result = TVLampSelector.select(from: lamps)

            if let expectedFirstMatchIndex {
                #expect(result == .resolved(lamps[expectedFirstMatchIndex]))
            } else {
                #expect(result == .unresolved)
            }

            // Purity: identical input yields identical output.
            #expect(TVLampSelector.select(from: lamps) == result)
        }
    }
}
