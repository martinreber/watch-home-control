// SpeakerOrderPreservedPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 6: Speaker order is preserved
//
// Validates Requirements 7.4.
//
// Property statement (design › Correctness Properties, Property 6): *for any*
// speaker list returned by the Backend, the displayed speaker rows appear in the
// SAME order (by `id`) as the returned list. Requirement 7.4 phrases this as
// "THE Watch_App SHALL display each Speaker in the order returned by the
// Backend".
//
// The order is established at two points in SpeakerViewModel and both are
// covered here:
//   1. activate() — maps `fetchSpeakers()` result to rows preserving the
//      Backend's returned order. Assertion: speakers.map(\.id) == fresh.map(\.id).
//   2. applyPoll(fresh) — rebuilds the list by iterating `fresh` in order.
//      Assertion: after applyPoll of a DIFFERENTLY ordered list, the displayed
//      order equals the new fresh order keyed by id.
//
// To prove the order is preserved VERBATIM (not coincidentally sorted), the
// generator deliberately produces input lists that are NOT in sorted id order.
// Each iteration counts how often the generated / reordered list was non-sorted
// and the test asserts at the end that non-sorted orderings were actually
// exercised. It also asserts that the displayed order is not merely the sorted
// order (so a hidden `.sorted()` would be caught).
//
// Pure and deterministic: an in-memory mock `APIClient` returns the seeded
// speaker list, no network, no shared global state. A self-contained splitmix64
// generator drives ≥100 iterations with no third-party dependency, matching the
// sibling *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct SpeakerOrderPreservedPropertyTests {

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

        mutating func bool() -> Bool { next() & 1 == 0 }

        mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }

        /// In-place Fisher-Yates shuffle driven by this deterministic RNG.
        mutating func shuffle<T>(_ items: inout [T]) {
            guard items.count > 1 else { return }
            for i in stride(from: items.count - 1, to: 0, by: -1) {
                let j = int(0..<(i + 1))
                items.swapAt(i, j)
            }
        }
    }

    // MARK: - Generators

    private static let idAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let allStates: [SpeakerState] = [.playing, .paused, .stopped]

    /// A random id stem; a monotonically increasing index suffix guarantees
    /// per-list uniqueness while the stem varies the natural sort order.
    private static func makeIDStem(_ rng: inout RNG) -> String {
        let length = rng.int(1..<8)
        var chars: [Character] = []
        for _ in 0..<length { chars.append(rng.pick(idAlphabet)) }
        return String(chars)
    }

    private static func makeSpeaker(id: String, _ rng: inout RNG) -> SpeakerDTO {
        let names = ["Küche", "Wohnzimmer", "Bad", "Schlafzimmer", "Büro"]
        let models: [String?] = ["Sonos One", "Play:1", "Beam", nil]
        return SpeakerDTO(
            id: id,
            name: rng.pick(names),
            state: rng.pick(allStates),
            online: rng.bool(),
            modelName: rng.pick(models)
        )
    }

    /// Builds a speaker list with unique ids in a deliberately varied (often
    /// NOT sorted) order. Uniqueness comes from an index suffix; the leading
    /// stem is random so `id` sort order rarely matches insertion order.
    private static func makeSpeakerList(count: Int, _ rng: inout RNG) -> [SpeakerDTO] {
        var speakers: [SpeakerDTO] = []
        for index in 0..<count {
            let id = "\(makeIDStem(&rng))-\(index)"
            speakers.append(makeSpeaker(id: id, &rng))
        }
        // Shuffle so the emitted order is not tied to the increasing index.
        rng.shuffle(&speakers)
        return speakers
    }

    private static func isSortedByID(_ speakers: [SpeakerDTO]) -> Bool {
        speakers.map(\.id) == speakers.map(\.id).sorted()
    }

    private static func isSortedByID(_ rows: [SpeakerRow]) -> Bool {
        rows.map(\.id) == rows.map(\.id).sorted()
    }

    // MARK: - Test double

    /// In-memory `APIClient` that returns the seeded speaker list verbatim from
    /// `fetchSpeakers`. All other methods are unused by this property.
    private final class OrderedSpeakerAPIClient: APIClient, @unchecked Sendable {
        let seedSpeakers: [SpeakerDTO]
        init(seedSpeakers: [SpeakerDTO]) { self.seedSpeakers = seedSpeakers }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { [] }
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO { throw APIError.timeout }
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { seedSpeakers }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO { throw APIError.timeout }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO { throw APIError.timeout }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO { throw APIError.timeout }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String { throw APIError.timeout }
    }

    // MARK: - Property 6

    @Test("Property 6: activate() and applyPoll preserve the Backend's speaker order verbatim")
    @MainActor
    func speakerOrderIsPreserved() async {
        var rng = RNG(seed: 0x06_5EED_0FDE_C6D6)
        var checked = 0
        var nonSortedActivateInputs = 0   // seeded lists that were NOT already id-sorted
        var nonSortedPollInputs = 0       // poll lists that were NOT already id-sorted
        var activateDifferedFromSorted = 0 // displayed order != sorted order (proves no re-sort)

        for _ in 0..<130 {
            // 1. activate() ordering — seed a varied list and load it.
            let count = rng.int(1..<8)
            let seed = Self.makeSpeakerList(count: count, &rng)
            if !Self.isSortedByID(seed) { nonSortedActivateInputs += 1 }

            let api = OrderedSpeakerAPIClient(seedSpeakers: seed)
            let vm = SpeakerViewModel(api: api)
            await vm.activate()

            // Displayed rows appear in EXACTLY the Backend's returned order.
            #expect(vm.speakers.map(\.id) == seed.map(\.id),
                    "activate() must preserve Backend order; expected \(seed.map(\.id)) got \(vm.speakers.map(\.id))")

            // If the seed was not id-sorted, the displayed order must NOT equal
            // the sorted order — this would catch a hidden `.sorted()`.
            if !Self.isSortedByID(seed) {
                #expect(vm.speakers.map(\.id) != seed.map(\.id).sorted(),
                        "activate() must not re-sort the list")
                activateDifferedFromSorted += 1
            }
            _ = Self.isSortedByID(vm.speakers) // touch the row overload for coverage

            // 2. applyPoll ordering — feed a DIFFERENTLY ordered list built from
            //    the same ids (a reorder proves order tracks `fresh`, not the
            //    previously displayed order).
            var polled = seed
            // Reorder until different from the current displayed order when
            // possible (lists of size >= 2), so the reorder is meaningful.
            if polled.count >= 2 {
                var attempts = 0
                repeat {
                    rng.shuffle(&polled)
                    attempts += 1
                } while polled.map(\.id) == vm.speakers.map(\.id) && attempts < 8
            }
            if !Self.isSortedByID(polled) { nonSortedPollInputs += 1 }

            vm.applyPoll(polled)

            // After applyPoll the displayed order equals the polled order by id.
            #expect(vm.speakers.map(\.id) == polled.map(\.id),
                    "applyPoll must yield fresh order; expected \(polled.map(\.id)) got \(vm.speakers.map(\.id))")

            if !Self.isSortedByID(polled) {
                #expect(vm.speakers.map(\.id) != polled.map(\.id).sorted(),
                        "applyPoll must not re-sort the list")
            }

            checked += 1
        }

        #expect(checked >= 100)
        // Prove the "verbatim, not sorted" claim was actually exercised.
        #expect(nonSortedActivateInputs > 0, "must exercise non-sorted activate() input orders")
        #expect(nonSortedPollInputs > 0, "must exercise non-sorted applyPoll input orders")
        #expect(activateDifferedFromSorted > 0,
                "must exercise cases where the preserved order differs from the sorted order")
    }
}
