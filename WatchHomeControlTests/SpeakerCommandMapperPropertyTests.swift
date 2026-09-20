import Foundation
import Testing
@testable import WatchHomeControl_Watch_App

/// Property tests for `SpeakerToggleMapper.command(toggleOn:current:)`.
///
/// Feature: apple-watch-home-control, Property 8: Speaker command mapping is a
/// total function of (toggle, state)
///
/// Validates Requirements 8.1, 8.2, 8.3.
///
/// The mapper is a pure total function over the finite domain
/// `(toggleOn: Bool) × (state: SpeakerState)` — 6 combinations. This test uses
/// a deterministic, seedable RNG to sample that domain ≥100 times and asserts
/// that every returned `SpeakerCommand` exactly equals the command produced by
/// an independent oracle:
///   - on + stopped        → `.radio(.radioBern1)`   (Req 8.1)
///   - on + playing|paused → `.play`                 (Req 8.2)
///   - off + any state     → `.pause`                (Req 8.3)
struct SpeakerCommandMapperPropertyTests {
    /// Small, deterministic splitmix64 RNG so failures are reproducible.
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// All speaker states — enumerated explicitly since `SpeakerState` is not
    /// `CaseIterable`.
    private static let allStates: [SpeakerState] = [.playing, .paused, .stopped]

    /// Independent oracle for the expected command mapping (Req 8.1–8.3).
    private static func expectedCommand(on: Bool, state: SpeakerState) -> SpeakerCommand {
        guard on else { return .pause }
        return state == .stopped ? .radio(.radioBern1) : .play
    }

    @Test("Property 8: speaker command mapping is a total function of (toggle, state)")
    func mappingIsTotalFunction() {
        var rng = SeededRNG(seed: 0xC0FF_EE12_3456_789A)
        let iterations = 200

        for _ in 0..<iterations {
            let on = Bool.random(using: &rng)
            let state = Self.allStates.randomElement(using: &rng)!

            let actual = SpeakerToggleMapper.command(toggleOn: on, current: state)
            let expected = Self.expectedCommand(on: on, state: state)

            #expect(
                actual == expected,
                "command(toggleOn: \(on), current: .\(state)) == \(actual), expected \(expected)"
            )
        }
    }

    @Test("Property 8: exhaustive coverage of all (toggle, state) combinations")
    func exhaustiveCombinations() {
        for on in [true, false] {
            for state in Self.allStates {
                let actual = SpeakerToggleMapper.command(toggleOn: on, current: state)
                let expected = Self.expectedCommand(on: on, state: state)
                #expect(
                    actual == expected,
                    "command(toggleOn: \(on), current: .\(state)) == \(actual), expected \(expected)"
                )
            }
        }

        // Spot-check the exact station used for the on + stopped case (Req 8.1).
        #expect(
            SpeakerToggleMapper.command(toggleOn: true, current: .stopped) == .radio(.radioBern1)
        )
    }
}
