// ComplicationStateMappingPropertyTests.swift
//
// Feature: tv-lamp-complication, Property 2: Complication state mapping is
// total and pure
//
// Validates Requirements 2.1, 2.2, 2.3, 2.4, 10.2, 10.3.
//
// Property statement (design › Correctness Properties, Property 2): for every
// (PairingCondition, TVLampResolution) pair, `ComplicationState.resolve` returns
// exactly one of `.on`, `.off`, `.unknown`, follows the mapping table, and is
// `.unknown` for every unpaired input.
//
// Pure and deterministic: no I/O, no stores. A self-contained RNG drives ≥100
// generated (pairing, resolution) pairs covering resolved-on, resolved-off,
// unresolved, and both pairing conditions.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct ComplicationStateMappingPropertyTests {

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

    private static func randomResolution(_ rng: inout SeededRNG) -> TVLampResolution {
        guard Bool.random(using: &rng) else { return .unresolved }
        let lamp = LampDTO(
            id: "lamp-\(UInt32.random(in: 0...UInt32.max, using: &rng))",
            friendlyName: Bool.random(using: &rng) ? "TV-Lampe" : nil,
            type: nil,
            state: LampState(power: Bool.random(using: &rng))
        )
        return .resolved(lamp)
    }

    @Test("Property 2: complication state mapping is total, pure, and matches the mapping table")
    func mappingIsTotalPureAndCorrect() {
        var rng = SeededRNG(seed: 0x57A7_E2C0_DE00_0002)

        for _ in 0..<150 {
            let pairing: PairingCondition = Bool.random(using: &rng) ? .paired : .unpaired
            let resolution = ComplicationStateMappingPropertyTests.randomResolution(&rng)

            let state = ComplicationState.resolve(pairing: pairing, resolution: resolution)

            // Totality: always exactly one of the three cases (trivially true for
            // a Swift enum, but assert the specific expected case per the table).
            switch (pairing, resolution) {
            case (.unpaired, _):
                #expect(state == .unknown)
            case (.paired, .unresolved):
                #expect(state == .unknown)
            case (.paired, .resolved(let lamp)):
                #expect(state == (lamp.state.power ? .on : .off))
            }

            // Purity: identical input yields identical output.
            #expect(ComplicationState.resolve(pairing: pairing, resolution: resolution) == state)
        }

        // The three label colours are pairwise distinct (Req 2.5).
        #expect(ComplicationState.on.labelColor != ComplicationState.off.labelColor)
        #expect(ComplicationState.on.labelColor != ComplicationState.unknown.labelColor)
        #expect(ComplicationState.off.labelColor != ComplicationState.unknown.labelColor)
    }
}
