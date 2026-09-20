// FailedCommandRestoresPriorStatePropertyTests.swift
//
// Feature: apple-watch-home-control, Property 10: A failed command restores the
// exact prior device state
//
// Validates Requirements 6.5, 6.6.
//
// Property statement (design › Correctness Properties, Property 10): *for any*
// prior lamp row and *any* failing outcome (error response, or timeout), the row
// after the command equals the prior row with its pending flag cleared.
//
// This test covers the LAMP branch of Property 10 (task 11.3, targeting the
// LampViewModel). The speaker branch is exercised by the SpeakerViewModel tests.
//
// How this is exercised: an initial lamp list is generated and seeded into a
// `LampViewModel` by calling `activate()` against a mock `APIClient` whose
// `fetchLamps` returns those DTOs. A target lamp id and a requested on/off value
// are generated, together with a generated `APIError` that the mock's
// `setLampState` THROWS. The thrown error is varied across every variant —
// `.timeout`, `.unauthorized`, `.http(status:)`, `.network(_)`, `.decoding` —
// so both feedback branches of `feedbackForToggleFailure` are covered:
//   * `.timeout`      -> Strings.commandTimeout ("Zeitüberschreitung")
//   * everything else -> Strings.commandError   ("Fehler")
//
// After `toggle(id:on:)` completes the test asserts:
//   1. the target row equals EXACTLY the snapshot's prior LampRow value (dto
//      identity + displayedPower) with `isPending` cleared — i.e. the optimistic
//      flip was fully reverted, regardless of the requested `on`;
//   2. `isPending` is false on the target row;
//   3. no other row changed (identity, displayed power, and pending flag are all
//      byte-for-byte identical to before the toggle);
//   4. `feedback` is a `.error` Feedback whose message is the German timeout
//      message when the thrown error is `APIError.timeout`, and the German
//      generic error message otherwise.
//
// Note on `.unauthorized`: AppModel treats a 401 as an Auth_Error that routes
// back to Setup, but the LampViewModel — the unit under test here — has no such
// routing; its `feedbackForToggleFailure` maps every non-timeout error
// (including `.unauthorized`) to `Strings.commandError`. This test asserts the
// LampViewModel behavior only.
//
// Pure and deterministic: an in-memory mock `APIClient`, no network, no shared
// state. A self-contained splitmix64 generator drives ≥100 iterations with no
// third-party dependency, matching the sibling *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct FailedCommandRestoresPriorStatePropertyTests {

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

    /// Generates one of every `APIError` variant so both feedback branches are
    /// exercised. `.timeout` maps to the German timeout message; every other
    /// variant maps to the German generic error message.
    private static func makeError(_ rng: inout RNG) -> APIError {
        switch rng.int(0..<5) {
        case 0: return .timeout
        case 1: return .unauthorized
        case 2: return .http(status: rng.pick([400, 403, 404, 409, 500, 502, 503]))
        case 3: return .network(rng.pick(["connection lost", "cannot connect", "dns", ""]))
        default: return .decoding
        }
    }

    // MARK: - Test double

    /// A mock `APIClient` that seeds a lamp list and THROWS a configured
    /// `APIError` from `setLampState`. In-memory and deterministic.
    private final class MockAPIClient: APIClient, @unchecked Sendable {
        let seedLamps: [LampDTO]
        /// The exact error thrown by `setLampState` for any request.
        let thrownError: APIError

        init(seedLamps: [LampDTO], thrownError: APIError) {
            self.seedLamps = seedLamps
            self.thrownError = thrownError
        }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { seedLamps }

        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            // Always fail with the configured error; this drives the revert path.
            throw thrownError
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

    // MARK: - Property 10 (lamp branch)

    @Test("Property 10: a failed lamp toggle restores the EXACT prior row with pending cleared, leaves other rows unchanged, and shows the correct German feedback")
    @MainActor
    func failedCommandRestoresPriorState() async {
        var rng = RNG(seed: 0x10_FA_11ED_C0DE)
        var checked = 0
        var timeoutCases = 0     // cases whose error was .timeout
        var nonTimeoutCases = 0  // cases whose error was any other variant

        for _ in 0..<200 {
            let seed = FailedCommandRestoresPriorStatePropertyTests.makeLampList(&rng)

            // Choose a target lamp in the list and a requested on/off value.
            let targetIndex = rng.int(0..<seed.count)
            let targetID = seed[targetIndex].id
            let requestedOn = rng.bool()

            // The failing outcome: every APIError variant, uniformly sampled.
            let error = FailedCommandRestoresPriorStatePropertyTests.makeError(&rng)
            let isTimeout = (error == .timeout)
            if isTimeout { timeoutCases += 1 } else { nonTimeoutCases += 1 }

            let api = MockAPIClient(seedLamps: seed, thrownError: error)
            let vm = LampViewModel(api: api)

            // Seed the displayed list from the generated DTOs.
            await vm.activate()

            // Snapshot the pre-toggle rows so we can assert an exact restore.
            let before = vm.lamps
            #expect(before.count == seed.count)
            guard let priorTarget = before.first(where: { $0.id == targetID }) else {
                Issue.record("target row \(targetID) missing before toggle")
                continue
            }

            // Perform the toggle; the mock throws, driving the revert path.
            await vm.toggle(id: targetID, on: requestedOn)

            let after = vm.lamps

            // The list identity/order is unchanged by a failed toggle.
            #expect(after.count == before.count)
            #expect(after.map(\.id) == before.map(\.id))

            guard let targetRow = after.first(where: { $0.id == targetID }) else {
                Issue.record("target row \(targetID) missing after toggle")
                continue
            }

            // 1. The target row equals EXACTLY the prior row (dto identity +
            //    displayedPower), with pending cleared — the optimistic flip to
            //    `requestedOn` was fully reverted.
            #expect(
                targetRow == priorTarget,
                "target row must be restored to its exact prior value \(priorTarget), got \(targetRow)"
            )

            // 2. Pending is cleared on the target row (redundant with the exact
            //    equality above since priorTarget.isPending is false, but stated
            //    explicitly to match the property text).
            #expect(targetRow.isPending == false,
                    "target row pending flag must be cleared after failure")

            // 3. No other row changed (id, displayed power, pending flag).
            for beforeRow in before where beforeRow.id != targetID {
                guard let afterRow = after.first(where: { $0.id == beforeRow.id }) else {
                    Issue.record("non-target row \(beforeRow.id) disappeared")
                    continue
                }
                #expect(afterRow == beforeRow,
                        "non-target row \(beforeRow.id) must be byte-for-byte unchanged")
            }

            // 4. Feedback is a German error message: the timeout message for
            //    .timeout, the generic error message for every other variant.
            let expectedMessage = isTimeout ? Strings.commandTimeout : Strings.commandError
            #expect(
                vm.feedback == Feedback(kind: .error, message: expectedMessage),
                "feedback for \(error) must be .error/\(expectedMessage), got \(String(describing: vm.feedback))"
            )

            checked += 1
        }

        #expect(checked >= 100)
        // Confirm BOTH feedback branches were actually exercised.
        #expect(timeoutCases > 0,
                "the test must exercise at least one .timeout case (German timeout feedback)")
        #expect(nonTimeoutCases > 0,
                "the test must exercise at least one non-timeout case (German generic error feedback)")
    }
}
