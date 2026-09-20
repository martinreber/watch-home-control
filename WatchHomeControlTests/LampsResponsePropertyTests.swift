import Foundation
import Testing
@testable import WatchHomeControl_Watch_App

/// Property tests for `LampsResponse` decoding.
///
/// Feature: apple-watch-home-control, Property 3: The lamp list decodes
/// identically from both response shapes
///
/// Validates Requirements 5.2, 5.3.
///
/// For any generated list of lamps the property encodes it two ways — as the
/// wrapped object `{"lamps":[...]}` and as a bare top-level array `[...]` — then
/// decodes BOTH through `JSONDecoder().decode(LampsResponse.self, from:)` and
/// asserts the two `.lamps` arrays equal each other AND equal the original list.
///
/// Iterations: a self-contained deterministic RNG drives ≥100 generated lists,
/// plus explicit edge cases (empty, single, many) with varied id, friendly_name
/// (present / nil / empty), type (present / nil) and power (true / false).
struct LampsResponsePropertyTests {

    /// Small deterministic linear-congruential RNG so failures reproduce.
    /// (Numerical Recipes constants.)
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Wrapper used to build the `{"lamps":[...]}` JSON encoding from a list.
    private struct WrappedLamps: Encodable {
        let lamps: [LampDTO]
    }

    // MARK: - Generators

    private static func randomLamp(_ rng: inout SeededRNG, index: Int) -> LampDTO {
        let id = "lamp-\(index)-\(UInt16.random(in: 0...UInt16.max, using: &rng))"

        // friendly_name: present / nil / empty
        let friendlyName: String?
        switch Int.random(in: 0...2, using: &rng) {
        case 0: friendlyName = "Name \(Int.random(in: 0...9999, using: &rng))"
        case 1: friendlyName = ""
        default: friendlyName = nil
        }

        // type: present / nil
        let type: String?
        if Bool.random(using: &rng) {
            let types = ["ceiling", "floor", "strip", "desk"]
            type = types[Int.random(in: 0..<types.count, using: &rng)]
        } else {
            type = nil
        }

        let power = Bool.random(using: &rng)
        return LampDTO(id: id, friendlyName: friendlyName, type: type, state: LampState(power: power))
    }

    /// Produces the generated list of lamp lists to check.
    private static func lampLists() -> [[LampDTO]] {
        var lists: [[LampDTO]] = []
        var rng = SeededRNG(seed: 0xC0FF_EE00_1234_5678)

        // Explicit edge cases.
        lists.append([]) // empty
        lists.append([LampDTO(id: "solo", friendlyName: "Solo", type: "desk", state: LampState(power: true))]) // single
        lists.append([
            LampDTO(id: "a", friendlyName: nil, type: nil, state: LampState(power: false)),
            LampDTO(id: "b", friendlyName: "", type: "strip", state: LampState(power: true)),
            LampDTO(id: "c", friendlyName: "Kitchen", type: "ceiling", state: LampState(power: false)),
        ]) // many, varied fields

        // ≥100 random lists of varying length (0...8).
        for _ in 0..<150 {
            let count = Int.random(in: 0...8, using: &rng)
            var lamps: [LampDTO] = []
            lamps.reserveCapacity(count)
            for i in 0..<count {
                lamps.append(randomLamp(&rng, index: i))
            }
            lists.append(lamps)
        }
        return lists
    }

    @Test("Property 3: lamp list decodes identically from wrapped and bare shapes")
    func decodesIdenticallyFromBothShapes() throws {
        let lists = Self.lampLists()
        #expect(lists.count >= 100)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in lists {
            // Bare array encoding: [...]
            let bareData = try encoder.encode(original)
            // Wrapped object encoding: {"lamps":[...]}
            let wrappedData = try encoder.encode(WrappedLamps(lamps: original))

            let bareDecoded = try decoder.decode(LampsResponse.self, from: bareData)
            let wrappedDecoded = try decoder.decode(LampsResponse.self, from: wrappedData)

            #expect(
                bareDecoded.lamps == wrappedDecoded.lamps,
                "Bare and wrapped decodings differ for \(original)"
            )
            #expect(
                bareDecoded.lamps == original,
                "Bare decoding does not equal original for \(original)"
            )
            #expect(
                wrappedDecoded.lamps == original,
                "Wrapped decoding does not equal original for \(original)"
            )
        }
    }
}
