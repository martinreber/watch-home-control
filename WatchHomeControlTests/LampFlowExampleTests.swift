// LampFlowExampleTests.swift
//
// Feature: apple-watch-home-control — example (unit) tests for the lamp
// (Lampen) listing + control flow driven by LampViewModel.
//
// These are deterministic example tests (not property tests): each case seeds a
// configurable MockAPIClient and asserts an exact LampViewModel outcome (empty
// list state + per-lamp Pending_State isolation).
//
// Validates Requirements:
//   - 5.6  IF the Lamp list contains zero Lamps, THEN THE Watch_App SHALL
//          display the German message "Keine Lampen gefunden". The empty list
//          is a VALID state, not a refresh failure — so `lamps.isEmpty == true`
//          and `refreshFailed == false`. The German copy lives in
//          `Strings.lampsEmpty` ("Keine Lampen gefunden"), which the
//          LampListView renders for the empty case.
//   - 6.3  WHILE a Lamp command is in flight, THE Watch_App SHALL set the
//          Pending_State for THAT Lamp and disable ONLY that Lamp's toggle —
//          every other row stays non-pending (and therefore enabled). After the
//          command completes, that row's Pending_State clears.
//
// LampViewModel API driven:
//   - activate()        — loads the list via GET /lamps (10s); an empty list is
//                         a success (lamps empty, refreshFailed false) (Req 5.6).
//   - toggle(id:on:)     — optimistically flips a single row, marks ONLY that
//                         row pending, sends POST /lamps/{id}/state (5s), and on
//                         success applies the returned state and clears pending
//                         (Req 6.3/6.4).
//   - lamps / refreshFailed — the state the LampListView binds to.
//
// Doubles (mirroring the sibling *ExampleTests / *PropertyTests convention): a
// configurable MockAPIClient whose `fetchLamps` returns a seeded list and whose
// `setLampState` can either return immediately or BLOCK on an AsyncStream gate
// so the in-flight per-row Pending_State can be observed deterministically
// (no sleeps). No device, network, or Backend involvement; outcomes are exact
// and reproducible.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct LampFlowExampleTests {

    // MARK: - Test double

    /// An `APIClient` whose `fetchLamps` returns a configured list and whose
    /// `setLampState` behaviour is configurable per test. Only these two methods
    /// are exercised by these lamp cases; every other method traps to prove it
    /// is never reached.
    private final class MockAPIClient: APIClient, @unchecked Sendable {
        /// The list returned by `fetchLamps`.
        let seedLamps: [LampDTO]

        /// Optional gate: when set, `setLampState` signals it is in flight and
        /// then suspends until the test releases the gate. Lets a test observe
        /// the in-flight per-row Pending_State (Req 6.3) deterministically.
        private let gate: AsyncStream<Void>?
        private let gateReady: (@Sendable () -> Void)?

        init(
            seedLamps: [LampDTO],
            gate: AsyncStream<Void>? = nil,
            gateReady: (@Sendable () -> Void)? = nil
        ) {
            self.seedLamps = seedLamps
            self.gate = gate
            self.gateReady = gateReady
        }

        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { seedLamps }

        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            // If a gate is configured, announce that the command is now in
            // flight and wait for the test to release it before completing.
            if let gate {
                gateReady?()
                var iterator = gate.makeAsyncIterator()
                _ = await iterator.next()
            }
            // On completion return the requested state as the device state so a
            // successful toggle applies exactly `power` (Req 6.4).
            return LampDTO(
                id: id,
                friendlyName: nil,
                type: nil,
                state: LampState(power: power)
            )
        }

        // Not part of these lamp cases — never called here.
        func checkHealth(timeout: Duration) async throws -> Bool {
            Issue.record("checkHealth must not be called by the lamp flow"); return true
        }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {
            Issue.record("moveBlind must not be called by the lamp flow")
        }
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] {
            Issue.record("fetchSpeakers must not be called by the lamp flow"); return []
        }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("playSpeaker must not be called by the lamp flow")
            throw APIError.decoding
        }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("pauseSpeaker must not be called by the lamp flow")
            throw APIError.decoding
        }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("playRadio must not be called by the lamp flow")
            throw APIError.decoding
        }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            Issue.record("redeemPairingCode must not be called by the lamp flow")
            throw APIError.unauthorized
        }
    }

    // MARK: - Helpers

    private static func lamp(_ id: String, power: Bool) -> LampDTO {
        LampDTO(id: id, friendlyName: nil, type: nil, state: LampState(power: power))
    }

    // MARK: - Empty state (Req 5.6)

    @Test("Req 5.6: an empty GET /lamps list is a valid state — lamps is empty and refreshFailed is false (UI shows Strings.lampsEmpty)")
    @MainActor
    func emptyLampListIsValidStateNotAFailure() async {
        // GET /lamps returns an empty array.
        let api = MockAPIClient(seedLamps: [])
        let vm = LampViewModel(api: api)

        await vm.activate()

        // The empty list is a valid, successful state — NOT a refresh failure.
        #expect(vm.lamps.isEmpty == true,
                "an empty GET /lamps response must leave the lamp list empty (Req 5.6)")
        #expect(vm.refreshFailed == false,
                "an empty list is a valid state, not a failure — refreshFailed must be false (Req 5.6)")

        // The German empty-state copy the LampListView renders for this state.
        #expect(Strings.lampsEmpty == "Keine Lampen gefunden",
                "the empty-state message must be the German 'Keine Lampen gefunden' (Req 5.6)")
    }

    // MARK: - Per-toggle Pending_State isolation (Req 6.3)

    @Test("Req 6.3: toggling one lamp marks ONLY that row pending while in flight; all other rows stay non-pending; the row clears pending after completion")
    @MainActor
    func togglingOneLampMarksOnlyThatRowPending() async {
        // A multi-lamp list so we can prove isolation across rows.
        let seed = [
            LampFlowExampleTests.lamp("kitchen", power: false),
            LampFlowExampleTests.lamp("living",  power: true),
            LampFlowExampleTests.lamp("office",  power: false),
        ]
        let targetID = "living"

        // Gate `setLampState` so it blocks in flight until the test releases it,
        // letting us observe the in-flight pending state deterministically.
        var continuation: AsyncStream<Void>.Continuation!
        let gate = AsyncStream<Void> { continuation = $0 }

        await confirmation("setLampState reaches the in-flight gate") { inFlight in
            let api = MockAPIClient(seedLamps: seed, gate: gate, gateReady: { inFlight() })
            let vm = LampViewModel(api: api)

            // Seed the displayed list; no row pending to start.
            await vm.activate()
            #expect(vm.lamps.count == 3)
            #expect(vm.lamps.allSatisfy { !$0.isPending },
                    "no row should be pending before any toggle")

            // Toggle the target lamp OFF (it starts on). The command suspends
            // inside `setLampState` on the gate.
            let task = Task { @MainActor in await vm.toggle(id: targetID, on: false) }

            // Yield until the target row has entered its in-flight pending state.
            // `toggle` sets `isPending = true` synchronously before awaiting the
            // client, so once the task has run this holds.
            while vm.lamps.first(where: { $0.id == targetID })?.isPending == false {
                await Task.yield()
            }

            // In flight: EXACTLY one row pending, and it is the target (Req 6.3).
            let pendingIDs: [String] = vm.lamps.compactMap { $0.isPending ? $0.id : nil }
            #expect(pendingIDs == [targetID],
                    "only the toggled lamp may be pending while its command is in flight (Req 6.3)")

            // Every OTHER row stays non-pending (and therefore enabled) (Req 6.3).
            for row in vm.lamps where row.id != targetID {
                #expect(row.isPending == false,
                        "non-target row \(row.id) must stay non-pending while another lamp toggles (Req 6.3)")
            }

            // The optimistic flip is visible on the target row while in flight.
            #expect(vm.lamps.first(where: { $0.id == targetID })?.displayedPower == false,
                    "the toggled row shows its optimistic value while in flight (Req 6.3)")

            // Release the gate so the command can complete, then wait for it.
            continuation.yield()
            continuation.finish()
            await task.value

            // After completion the target row clears its Pending_State (Req 6.3),
            // and NO row is left pending.
            #expect(vm.lamps.allSatisfy { !$0.isPending },
                    "the target row must clear its Pending_State after completion (Req 6.3)")
            #expect(vm.lamps.first(where: { $0.id == targetID })?.displayedPower == false,
                    "the toggled row adopts the returned OFF state after success (Req 6.3/6.4)")
        }
    }
}
