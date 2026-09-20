import Foundation
import Testing
@testable import WatchHomeControl_Watch_App

/// Property tests for `LampDTO.displayName`.
///
/// Feature: apple-watch-home-control, Property 4: Lamp display label falls back
/// to id
///
/// Validates Requirements 5.4, 5.5.
///
/// Property: for any lamp, `displayName` equals `friendly_name` if and only if
/// `friendly_name` is present AND non-empty; otherwise it equals `id`. Note
/// that a whitespace-only name is non-empty, so it must be returned verbatim.
///
/// Uses Swift Testing's generator-driven approach: a self-contained
/// deterministic RNG produces varied lamps (≥100 iterations) covering
/// `friendlyName` = nil, empty string, whitespace-only, and normal names, with
/// a non-empty `id` that itself varies (including values that collide with the
/// friendly name and values containing whitespace/unicode). Each generated
/// lamp is asserted against the exact expected branch.
struct LampDisplayNamePropertyTests {
    /// A small, deterministic linear-congruential RNG so failures reproduce.
    private struct DeterministicRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            // splitmix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// The kinds of friendly-name values the property must cover.
    private enum FriendlyNameKind: CaseIterable {
        case nilValue
        case empty
        case whitespaceOnly
        case normal
    }

    /// Candidate non-empty id fragments (id is never empty per the contract).
    private static let idSamples = [
        "lamp-1", "living_room", "0", "ütösed", "id with spaces",
        "🛋️-couch", "AABBCC", "z", "kitchen.ceiling.03",
    ]

    /// Candidate normal (non-empty, non-whitespace) friendly names.
    private static let normalNameSamples = [
        "Wohnzimmer", "Küche", "Stehlampe", "Desk Light", "字幕", "n",
        "Ceiling 💡",
    ]

    /// Whitespace-only strings (non-empty; must be returned as-is).
    private static let whitespaceSamples = [
        " ", "  ", "\t", "\n", " \t \n ",
    ]

    /// Builds a lamp for the given friendly-name kind using the RNG to vary
    /// the concrete id/name and power.
    private static func makeLamp(kind: FriendlyNameKind, rng: inout DeterministicRNG) -> LampDTO {
        let id = idSamples[Int(rng.next() % UInt64(idSamples.count))]
        let power = (rng.next() & 1) == 0
        let type: String? = (rng.next() & 1) == 0 ? "ceiling" : nil

        let friendlyName: String?
        switch kind {
        case .nilValue:
            friendlyName = nil
        case .empty:
            friendlyName = ""
        case .whitespaceOnly:
            friendlyName = whitespaceSamples[Int(rng.next() % UInt64(whitespaceSamples.count))]
        case .normal:
            // Sometimes make the name collide with an id value to ensure the
            // branch (not equality-by-accident) is what we assert.
            if (rng.next() & 1) == 0 {
                friendlyName = normalNameSamples[Int(rng.next() % UInt64(normalNameSamples.count))]
            } else {
                friendlyName = id
            }
        }

        return LampDTO(
            id: id,
            friendlyName: friendlyName,
            type: type,
            state: LampState(power: power)
        )
    }

    @Test("Property 4: displayName is friendly_name iff present and non-empty, else id")
    func displayNameFallsBackToId() {
        var rng = DeterministicRNG(seed: 0x5EED_C0FE_1234_ABCD)

        // Round-robin over the kinds so every branch is exercised many times,
        // well past the 100-iteration minimum.
        let iterations = 240
        var count = 0
        let kinds = FriendlyNameKind.allCases

        for i in 0..<iterations {
            let kind = kinds[i % kinds.count]
            let lamp = Self.makeLamp(kind: kind, rng: &rng)
            count += 1

            let hasNonEmptyName = (lamp.friendlyName != nil) && !(lamp.friendlyName!.isEmpty)

            if hasNonEmptyName {
                #expect(
                    lamp.displayName == lamp.friendlyName!,
                    "Expected displayName == friendlyName \"\(lamp.friendlyName!)\" but got \"\(lamp.displayName)\" (id=\(lamp.id))"
                )
            } else {
                #expect(
                    lamp.displayName == lamp.id,
                    "Expected displayName == id \"\(lamp.id)\" but got \"\(lamp.displayName)\" (friendlyName=\(String(describing: lamp.friendlyName)))"
                )
            }
        }

        #expect(count >= 100)
    }

    @Test("Property 4: explicit branch examples (nil, empty, whitespace, normal)")
    func explicitBranchExamples() {
        // nil -> id
        #expect(LampDTO(id: "a", friendlyName: nil, type: nil, state: LampState(power: true)).displayName == "a")
        // empty -> id
        #expect(LampDTO(id: "b", friendlyName: "", type: nil, state: LampState(power: false)).displayName == "b")
        // whitespace-only -> returned as-is (non-empty)
        #expect(LampDTO(id: "c", friendlyName: " ", type: nil, state: LampState(power: true)).displayName == " ")
        // normal -> friendly name
        #expect(LampDTO(id: "d", friendlyName: "Küche", type: nil, state: LampState(power: true)).displayName == "Küche")
    }
}
