// SuccessfulCommandAppliesReturnedStatePropertyTests.swift
//
// Feature: apple-watch-home-control, Property 9: A successful command applies
// exactly the returned device state
//
// Validates Requirements 6.4.
//
// Property statement (design › Correctness Properties, Property 9): *for any*
// lamp command that returns a `lamp` object, the lamp row's displayed power
// equals the returned `lamp.state.power` and its pending flag is cleared.
//
// This test covers the LAMP branch of Property 9 (task 11.2, targeting the
// LampViewModel). The speaker branch is exercised by the SpeakerViewModel tests.
//
// How this is exercised: an initial lamp list is generated and seeded into a
// `LampViewModel` by calling `activate()` against a mock `APIClient` whose
// `fetchLamps` returns those DTOs. A target lamp id and a requested on/off value
// are generated. The mock's `setLampState` returns a `LampDTO` whose
// `state.power` is chosen INDEPENDENTLY of the requested `on` (it may agree or
// disagree). After `toggle(id:on:)` completes successfully the test asserts:
//   1. the target row's `displayedPower` equals EXACTLY the returned
//      `lamp.state.power` — not merely the requested `on` (this is the crux of
//      the "exactly returned state" distinction);
//   2. the target row's `isPending` is cleared;
//   3. no other row changed (identity, displayed power, and pending flag are all
//      byte-for-byte identical to before the toggle).
// The returned-vs-requested distinction is exercised explicitly: whenever the
// returned power differs from the requested `on`, the assertion would fail for
// any implementation that applied the request instead of the response.
//
// Pure and deterministic: an in-memory mock `APIClient`, no network, no shared
// state. A self-contained splitmix64 generator drives ≥100 iterations with no
// third-party dependency, matching the sibling *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct SuccessfulCommandAppliesReturnedStatePropertyTests {

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
    }

    // MARK: - Generators

    private static let idAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// A random lamp id fragment; uniqueness across a list is enforced by the
    /// caller appending the row index.
    private static func makeIDStem(_ rng: inout RNG) -> String {
        let length = rng.int(1..<8)
        var chars: [Character] = []
        for _ in 0..<length { chars.append(rng.pick(idAlphabet)) }
        return String(chars)
    }

    /// Builds a lamp DTO with the given id and power.
    private static func makeLamp(id: String, power: Bool, _ rng: inout RNG) -> LampDTO {
        let names: [String?] = ["Küche", "Wohnzimmer", "Büro", "", nil]
        let types: [String?] = ["ceiling", "floor", "strip", "desk", nil]
        return LampDTO(
            id: id,
            friendlyName: rng.pick(names),
            type: rng.pick(types),
            state: LampState(power: power)
        )
    }

    /// Generates a non-empty lamp list with unique ids.
    private static func makeLampList(_ rng: inout RNG) -> [LampDTO] {
        let count = rng.int(1..<8)
        var lamps: [LampDTO] = []
        for index in 0..<count {
            let id = "\(makeIDStem(&rng))-\(index)"
            lamps.append(makeLamp(id: id, power: rng.bool(), &rng))
        }
        return lamps
    }

    // MARK: - Test double

    /// A mock `APIClient` that seeds a lamp list and returns a configured
    /// `LampDTO` from `setLampState`. In-memory and deterministic.
    private final class MockAPIClient: APIClient, @unchecked Sendable {
        let seedLamps: [LampDTO]
        /// The exact lamp returned by `setLampState`, keyed by the id under
        /// test. Its `state.power` is chosen independently of the request.
        let returnedLamp: LampDTO

        init(seedLamps: [LampDTO], returnedLamp: LampDTO) {
            self.seedLamps = seedLamps
            self.returnedLamp = returnedLamp
        }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { seedLamps }

        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            // Return the pre-configured lamp verbatim, ignoring the requested
            // `power`. This is what proves "exactly returned state".
            returnedLamp
        }

        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { [] }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.timeout
        }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.timeout
        }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.timeout
        }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            throw APIError.timeout
        }
    }

    // MARK: - Property 9 (lamp branch)

    @Test("Property 9: a successful lamp toggle applies EXACTLY the returned lamp.state.power, clears pending, and leaves other rows unchanged")
    @MainActor
    func successfulCommandAppliesReturnedState() async {
        var rng = RNG(seed: 0x09_A9_C0DE_57A7E)
        var checked = 0
        var divergedCases = 0   // cases where returned power != requested `on`

        for _ in 0..<200 {
            let seed = SuccessfulCommandAppliesReturnedStatePropertyTests.makeLampList(&rng)

            // Choose a target lamp in the list and a requested on/off value.
            let targetIndex = rng.int(0..<seed.count)
            let targetID = seed[targetIndex].id
            let requestedOn = rng.bool()

            // The device state the API returns: chosen INDEPENDENTLY of the
            // request so it may agree or disagree with `requestedOn`.
            let returnedPower = rng.bool()
            if returnedPower != requestedOn { divergedCases += 1 }
            let returnedLamp = SuccessfulCommandAppliesReturnedStatePropertyTests.makeLamp(
                id: targetID, power: returnedPower, &rng
            )

            let api = MockAPIClient(seedLamps: seed, returnedLamp: returnedLamp)
            let vm = LampViewModel(api: api)

            // Seed the displayed list from the generated DTOs.
            await vm.activate()

            // Snapshot the pre-toggle rows to assert non-target rows are intact.
            let before = vm.lamps
            #expect(before.count == seed.count)

            // Perform the toggle; the mock returns success with `returnedLamp`.
            await vm.toggle(id: targetID, on: requestedOn)

            let after = vm.lamps

            // The list identity/order is unchanged by a successful toggle.
            #expect(after.count == before.count)
            #expect(after.map(\.id) == before.map(\.id))

            guard let targetRow = after.first(where: { $0.id == targetID }) else {
                Issue.record("target row \(targetID) missing after toggle")
                continue
            }

            // 1. displayedPower equals EXACTLY the returned lamp.state.power —
            //    NOT the requested `on`.
            #expect(
                targetRow.displayedPower == returnedPower,
                "target row must display the returned state.power (\(returnedPower)), got \(targetRow.displayedPower)"
            )

            // 2. Pending is cleared on the target row.
            #expect(targetRow.isPending == false,
                    "target row pending flag must be cleared after success")

            // 3. No other row changed (id, displayed power, pending flag).
            for beforeRow in before where beforeRow.id != targetID {
                guard let afterRow = after.first(where: { $0.id == beforeRow.id }) else {
                    Issue.record("non-target row \(beforeRow.id) disappeared")
                    continue
                }
                #expect(afterRow == beforeRow,
                        "non-target row \(beforeRow.id) must be byte-for-byte unchanged")
            }

            checked += 1
        }

        #expect(checked >= 100)
        // Confirm the returned-vs-requested distinction was actually exercised:
        // at least some cases had the returned power differ from the request.
        #expect(divergedCases > 0,
                "the test must exercise cases where the returned state differs from the requested value")
    }
}
