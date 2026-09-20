import Foundation
import Testing
@testable import WatchHomeControl_Watch_App

/// Property tests for `SpeakerDTO.isOn`.
///
/// Feature: apple-watch-home-control, Property 5: Speaker toggle position is a
/// pure function of playback state
///
/// Validates Requirements 7.5, 7.6.
///
/// The toggle position (`isOn`) must be a pure function of `state` alone:
/// `isOn == true` iff `state == .playing`, and `isOn == false` for both
/// `.paused` and `.stopped`. The other fields (`id`, `name`, `online`,
/// `modelName`) must not influence the result. This is verified by generating
/// speakers (≥100 iterations, deterministic RNG) that vary every field across
/// all three states and asserting the equivalence holds regardless.
struct SpeakerTogglePositionPropertyTests {
    /// Deterministic RNG so any failure is reproducible.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed != 0 ? seed : 0x9E3779B97F4A7C15 }
        // SplitMix64.
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private static let allStates: [SpeakerState] = [.playing, .paused, .stopped]

    /// Generates a wide set of speakers varying every field. At least 100
    /// cases, and every playback state is represented (round-robin over the
    /// three states so each is exercised many times).
    private static func speakers() -> [SpeakerDTO] {
        var rng = SeededGenerator(seed: 0xC0FFEE)
        var result: [SpeakerDTO] = []
        for i in 0..<180 {
            let state = allStates[i % allStates.count]
            let online = Bool.random(using: &rng)
            let id = "speaker-\(UInt16.random(in: 0...UInt16.max, using: &rng))"
            let name = "Sonos \(UInt8.random(in: 0...UInt8.max, using: &rng))"
            let modelName: String? = Bool.random(using: &rng)
                ? "Model-\(UInt8.random(in: 0...UInt8.max, using: &rng))"
                : nil
            result.append(SpeakerDTO(
                id: id,
                name: name,
                state: state,
                online: online,
                modelName: modelName
            ))
        }
        return result
    }

    @Test("Property 5: isOn is a pure function of playback state (true iff .playing)")
    func isOnDependsOnlyOnState() {
        let speakers = Self.speakers()
        // Guarantee the minimum iteration count.
        #expect(speakers.count >= 100)

        // Confirm all three states are actually exercised.
        #expect(speakers.contains { $0.state == .playing })
        #expect(speakers.contains { $0.state == .paused })
        #expect(speakers.contains { $0.state == .stopped })

        for speaker in speakers {
            let expected = (speaker.state == .playing)
            #expect(
                speaker.isOn == expected,
                "isOn=\(speaker.isOn) but expected \(expected) for state=\(speaker.state) (online=\(speaker.online), id=\(speaker.id), modelName=\(String(describing: speaker.modelName)))"
            )
            // Explicit per-state checks (Req 7.5/7.6).
            switch speaker.state {
            case .playing:
                #expect(speaker.isOn == true)
            case .paused, .stopped:
                #expect(speaker.isOn == false)
            }
        }
    }

    @Test("Property 5: non-state fields never affect isOn")
    func nonStateFieldsDoNotAffectIsOn() {
        // For a fixed state, isOn is identical no matter how the other fields
        // vary. Build many speakers per state and assert a single value.
        for state in Self.allStates {
            var rng = SeededGenerator(seed: 0xABCD ^ UInt64(state.rawValue.hashValue & 0xFFFF))
            let expected = (state == .playing)
            for _ in 0..<40 {
                let speaker = SpeakerDTO(
                    id: "id-\(UInt32.random(in: 0...UInt32.max, using: &rng))",
                    name: "name-\(UInt16.random(in: 0...UInt16.max, using: &rng))",
                    state: state,
                    online: Bool.random(using: &rng),
                    modelName: Bool.random(using: &rng) ? "m" : nil
                )
                #expect(speaker.isOn == expected)
            }
        }
    }
}
