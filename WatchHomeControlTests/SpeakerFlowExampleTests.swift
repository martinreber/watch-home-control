// SpeakerFlowExampleTests.swift
//
// Feature: apple-watch-home-control — example (unit) tests for the speaker
// (Sonos) listing + control flow driven by SpeakerViewModel.
//
// These are deterministic example tests (not property tests): each case seeds a
// configurable MockAPIClient and asserts an exact SpeakerViewModel outcome
// (empty list state + per-speaker Pending_State isolation).
//
// Validates Requirements:
//   - 7.8  IF the Speaker list contains zero Speakers, THEN THE Watch_App SHALL
//          display the German message "Keine Lautsprecher gefunden". The empty
//          list is a VALID state, not a refresh failure — so
//          `speakers.isEmpty == true` and `refreshFailed == false`. The German
//          copy lives in `Strings.speakersEmpty` ("Keine Lautsprecher gefunden"),
//          which the SpeakerListView renders for the empty case.
//   - 8.4  WHILE a Speaker command is in flight, THE Watch_App SHALL set the
//          Pending_State for THAT Speaker and disable ONLY that Speaker's toggle
//          — every other row stays non-pending (and therefore enabled). After
//          the command completes, that row's Pending_State clears and it adopts
//          the returned state (Req 8.5).
//
// SpeakerViewModel API driven:
//   - activate()        — loads the list via GET /sonos/speakers (10s); an empty
//                          list is a success (speakers empty, refreshFailed
//                          false) (Req 7.8).
//   - toggle(id:on:)     — optimistically flips a single row, marks ONLY that
//                          row pending, sends the mapped command (radio/play/
//                          pause via SpeakerToggleMapper), and on success applies
//                          the returned state and clears pending (Req 8.4/8.5).
//   - speakers / refreshFailed — the state the SpeakerListView binds to.
//
// The target speaker starts in the `.paused` state, so toggling it ON maps to
// `.play` (on + non-stopped -> play, per SpeakerToggleMapper / Req 8.2) — a
// clear, single command path.
//
// Doubles (mirroring the sibling *ExampleTests / *PropertyTests convention): a
// configurable MockAPIClient whose `fetchSpeakers` returns a seeded list and
// whose `playSpeaker` can either return immediately or BLOCK on an AsyncStream
// gate so the in-flight per-row Pending_State can be observed deterministically
// (no sleeps). No device, network, or Backend involvement; outcomes are exact
// and reproducible.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct SpeakerFlowExampleTests {

    // MARK: - Test double

    /// An `APIClient` whose `fetchSpeakers` returns a configured list and whose
    /// `playSpeaker` behaviour is configurable per test. Only these two methods
    /// are exercised by these speaker cases (the target starts `.paused`, so a
    /// toggle-on maps to `.play`); every other method traps to prove it is never
    /// reached.
    private final class MockAPIClient: APIClient, @unchecked Sendable {
        /// The list returned by `fetchSpeakers`.
        let seedSpeakers: [SpeakerDTO]

        /// Optional gate: when set, `playSpeaker` signals it is in flight and
        /// then suspends until the test releases the gate. Lets a test observe
        /// the in-flight per-row Pending_State (Req 8.4) deterministically.
        private let gate: AsyncStream<Void>?
        private let gateReady: (@Sendable () -> Void)?

        init(
            seedSpeakers: [SpeakerDTO],
            gate: AsyncStream<Void>? = nil,
            gateReady: (@Sendable () -> Void)? = nil
        ) {
            self.seedSpeakers = seedSpeakers
            self.gate = gate
            self.gateReady = gateReady
        }

        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { seedSpeakers }

        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            // If a gate is configured, announce that the command is now in
            // flight and wait for the test to release it before completing.
            if let gate {
                gateReady?()
                var iterator = gate.makeAsyncIterator()
                _ = await iterator.next()
            }
            // On completion return a benign updated DTO carrying the `.playing`
            // state so a successful toggle-on applies exactly `.playing`
            // (Req 8.5). Other fields mirror a plausible online speaker.
            return SpeakerDTO(
                id: id,
                name: id,
                state: .playing,
                online: true,
                modelName: nil
            )
        }

        // Not part of these speaker toggle-on cases — never called here.
        func checkHealth(timeout: Duration) async throws -> Bool {
            Issue.record("checkHealth must not be called by the speaker flow"); return true
        }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {
            Issue.record("moveBlind must not be called by the speaker flow")
        }
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            Issue.record("fetchLamps must not be called by the speaker flow"); return []
        }
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            Issue.record("setLampState must not be called by the speaker flow")
            throw APIError.decoding
        }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("pauseSpeaker must not be called by this toggle-on flow")
            throw APIError.decoding
        }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("playRadio must not be called by this toggle-on flow")
            throw APIError.decoding
        }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            Issue.record("redeemPairingCode must not be called by the speaker flow")
            throw APIError.unauthorized
        }
    }

    // MARK: - Helpers

    private static func speaker(
        _ id: String,
        state: SpeakerState = .paused,
        online: Bool = true
    ) -> SpeakerDTO {
        SpeakerDTO(id: id, name: id, state: state, online: online, modelName: nil)
    }

    // MARK: - Empty state (Req 7.8)

    @Test("Req 7.8: an empty GET /sonos/speakers list is a valid state — speakers is empty and refreshFailed is false (UI shows Strings.speakersEmpty)")
    @MainActor
    func emptySpeakerListIsValidStateNotAFailure() async {
        // GET /sonos/speakers returns an empty array.
        let api = MockAPIClient(seedSpeakers: [])
        let vm = SpeakerViewModel(api: api)

        await vm.activate()

        // The empty list is a valid, successful state — NOT a refresh failure.
        #expect(vm.speakers.isEmpty == true,
                "an empty GET /sonos/speakers response must leave the speaker list empty (Req 7.8)")
        #expect(vm.refreshFailed == false,
                "an empty list is a valid state, not a failure — refreshFailed must be false (Req 7.8)")

        // The German empty-state copy the SpeakerListView renders for this state.
        #expect(Strings.speakersEmpty == "Keine Lautsprecher gefunden",
                "the empty-state message must be the German 'Keine Lautsprecher gefunden' (Req 7.8)")
    }

    // MARK: - Per-toggle Pending_State isolation (Req 8.4)

    @Test("Req 8.4: toggling one speaker marks ONLY that row pending while in flight; all other rows stay non-pending; the row clears pending and adopts the returned state after completion")
    @MainActor
    func togglingOneSpeakerMarksOnlyThatRowPending() async {
        // A multi-speaker list, all online, so we can prove isolation across
        // rows. Every speaker starts `.paused`, so a toggle-on maps to `.play`.
        let seed = [
            SpeakerFlowExampleTests.speaker("kitchen"),
            SpeakerFlowExampleTests.speaker("living"),
            SpeakerFlowExampleTests.speaker("office"),
        ]
        let targetID = "living"

        // Gate `playSpeaker` so it blocks in flight until the test releases it,
        // letting us observe the in-flight pending state deterministically.
        var continuation: AsyncStream<Void>.Continuation!
        let gate = AsyncStream<Void> { continuation = $0 }

        await confirmation("playSpeaker reaches the in-flight gate") { inFlight in
            let api = MockAPIClient(seedSpeakers: seed, gate: gate, gateReady: { inFlight() })
            let vm = SpeakerViewModel(api: api)

            // Seed the displayed list; no row pending to start.
            await vm.activate()
            #expect(vm.speakers.count == 3)
            #expect(vm.speakers.allSatisfy { !$0.isPending },
                    "no row should be pending before any toggle")

            // Toggle the target speaker ON (it starts paused). The command
            // suspends inside `playSpeaker` on the gate.
            let task = Task { @MainActor in await vm.toggle(id: targetID, on: true) }

            // Yield until the target row has entered its in-flight pending state.
            // `toggle` sets `isPending = true` synchronously before awaiting the
            // client, so once the task has run this holds.
            while vm.speakers.first(where: { $0.id == targetID })?.isPending == false {
                await Task.yield()
            }

            // In flight: EXACTLY one row pending, and it is the target (Req 8.4).
            let pendingIDs: [String] = vm.speakers.compactMap { $0.isPending ? $0.id : nil }
            #expect(pendingIDs == [targetID],
                    "only the toggled speaker may be pending while its command is in flight (Req 8.4)")

            // Every OTHER row stays non-pending (and therefore enabled) (Req 8.4).
            for row in vm.speakers where row.id != targetID {
                #expect(row.isPending == false,
                        "non-target row \(row.id) must stay non-pending while another speaker toggles (Req 8.4)")
            }

            // The optimistic flip (on -> .playing) is visible on the target row
            // while in flight.
            #expect(vm.speakers.first(where: { $0.id == targetID })?.displayedState == .playing,
                    "the toggled row shows its optimistic .playing value while in flight (Req 8.4)")

            // Release the gate so the command can complete, then wait for it.
            continuation.yield()
            continuation.finish()
            await task.value

            // After completion the target row clears its Pending_State (Req 8.4),
            // and NO row is left pending.
            #expect(vm.speakers.allSatisfy { !$0.isPending },
                    "the target row must clear its Pending_State after completion (Req 8.4)")
            // The row adopts exactly the returned device state (.playing) (Req 8.5).
            #expect(vm.speakers.first(where: { $0.id == targetID })?.displayedState == .playing,
                    "the toggled row adopts the returned .playing state after success (Req 8.4/8.5)")
        }
    }
}
