// PollingPreservesPendingRowsPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 12: Polling preserves pending rows
// and updates the rest
//
// Validates Requirements 9.2, 9.3.
//
// Property statement (design › Correctness Properties, Property 12): *for any*
// current set of rows (lamps or speakers) and *any* freshly polled data, after
// `applyPoll` every row currently in the Pending_State retains its prior
// displayed value, and every non-pending row that appears in the polled data
// adopts the polled value.
//
// This test covers BOTH the lamp branch (LampViewModel.applyPoll) and the
// speaker branch (SpeakerViewModel.applyPoll), matching the property's
// "(lamp + speaker)" scope. Beyond the two headline clauses it also pins the
// full merge contract exercised by `applyPoll`:
//   - a pending row keeps its EXACT displayed value AND its pending flag;
//   - a non-pending row present in `fresh` becomes non-pending with
//     displayedPower / displayedState == the polled value;
//   - rows absent from `fresh` are dropped;
//   - ids new in `fresh` are appended as non-pending rows seeded from the DTO;
//   - final order equals `fresh` order keyed by id.
//
// How pending rows are produced DETERMINISTICALLY (no injecting LampRow/
// SpeakerRow directly — the lists are `private(set)`, so everything goes
// through the public API):
//   1. Seed the displayed list by calling `activate()` against a mock whose
//      fetch returns generated DTOs (this leaves every row non-pending).
//   2. For each id chosen to be pending, start `toggle(id:on:)` on a detached
//      Task. The mock's command method (`setLampState` / play/pause/radio)
//      SUSPENDS on a per-id gate that is never signalled, so the in-flight
//      command never returns and the row stays in the Pending_State. A short
//      poll loop waits until the view model reports the row as pending before
//      the test proceeds — this makes "the toggle has marked the row pending"
//      observable and deterministic rather than timing-dependent.
//   3. With exactly the chosen rows pending, call `applyPoll(fresh)` and assert
//      the merge contract above.
//   4. Finally the gates are released and the in-flight toggles are cancelled so
//      no task leaks between iterations.
//
// The optimistic pending value the toggle writes is `on ? .playing/.true :
// .paused/.false`; `fresh` is generated to carry a DIFFERENT value for pending
// ids wherever possible, so "pending retains its prior value" is proven to be
// distinct from "adopted the polled value".
//
// Pure and deterministic apart from the awaited pending gate: an in-memory mock
// `APIClient`, no network, no shared global state. A self-contained splitmix64
// generator drives ≥100 iterations with no third-party dependency, matching the
// sibling *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct PollingPreservesPendingRowsPropertyTests {

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

    private static func makeIDStem(_ rng: inout RNG) -> String {
        let length = rng.int(1..<8)
        var chars: [Character] = []
        for _ in 0..<length { chars.append(rng.pick(idAlphabet)) }
        return String(chars)
    }

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

    private static func makeSpeaker(id: String, state: SpeakerState, _ rng: inout RNG) -> SpeakerDTO {
        let names = ["Küche", "Wohnzimmer", "Bad", "Schlafzimmer", "Büro"]
        let models: [String?] = ["Sonos One", "Play:1", "Beam", nil]
        return SpeakerDTO(
            id: id,
            name: rng.pick(names),
            state: state,
            online: true, // must be online so `toggle` issues a command and marks pending (Req 7.7)
            modelName: rng.pick(models)
        )
    }

    // MARK: - Test doubles

    /// A mock `APIClient` for the lamp branch. `fetchLamps` seeds the displayed
    /// list. `setLampState` SUSPENDS forever (until the task is cancelled) so
    /// the toggled row stays pending — this is the deterministic pending gate.
    private final class GatedLampAPIClient: APIClient, @unchecked Sendable {
        let seedLamps: [LampDTO]
        init(seedLamps: [LampDTO]) { self.seedLamps = seedLamps }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { seedLamps }

        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            // Suspend indefinitely; only cancellation ends this. The row remains
            // in the Pending_State for the duration of the test.
            try await Task.sleep(nanoseconds: .max)
            throw APIError.timeout // unreachable
        }

        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { [] }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO { throw APIError.timeout }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO { throw APIError.timeout }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO { throw APIError.timeout }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String { throw APIError.timeout }
    }

    /// A mock `APIClient` for the speaker branch. `fetchSpeakers` seeds the
    /// list; the play/pause/radio commands SUSPEND forever so the toggled row
    /// stays pending.
    private final class GatedSpeakerAPIClient: APIClient, @unchecked Sendable {
        let seedSpeakers: [SpeakerDTO]
        init(seedSpeakers: [SpeakerDTO]) { self.seedSpeakers = seedSpeakers }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { [] }
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO { throw APIError.timeout }
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { seedSpeakers }

        private func suspendForever() async throws -> SpeakerDTO {
            try await Task.sleep(nanoseconds: .max)
            throw APIError.timeout // unreachable
        }

        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO { try await suspendForever() }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO { try await suspendForever() }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO { try await suspendForever() }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String { throw APIError.timeout }
    }

    // MARK: - Helpers

    /// Yields the main actor until `predicate` holds or the attempt budget is
    /// exhausted. Used to wait deterministically for a toggle to mark a row
    /// pending. Returns whether the predicate became true.
    @MainActor
    private static func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if predicate() { return true }
            await Task.yield()
        }
        return predicate()
    }

    // MARK: - Property 12 (lamp branch)

    @Test("Property 12 (lamp): applyPoll keeps pending rows untouched and adopts polled state for the rest")
    @MainActor
    func lampPollPreservesPendingUpdatesRest() async {
        var rng = RNG(seed: 0x12_B0_11ED_1A47)
        var checked = 0
        var pendingObserved = 0        // total pending rows exercised
        var divergingPending = 0       // pending rows whose fresh value differed from displayed
        var adoptedDiffered = 0        // non-pending rows whose polled value differed from prior

        for _ in 0..<130 {
            // 1. Seed a non-empty displayed lamp list with unique ids.
            let count = rng.int(2..<7)
            var seedLamps: [LampDTO] = []
            for index in 0..<count {
                let id = "\(Self.makeIDStem(&rng))-\(index)"
                seedLamps.append(Self.makeLamp(id: id, power: rng.bool(), &rng))
            }

            let api = GatedLampAPIClient(seedLamps: seedLamps)
            let vm = LampViewModel(api: api)
            await vm.activate()
            #expect(vm.lamps.count == count)

            // 2. Choose which ids become pending (0..<count of them). For each,
            //    start a toggle whose command suspends forever, then wait until
            //    the row is observably pending.
            var pendingTasks: [Task<Void, Never>] = []
            var pendingExpected: [String: LampRow] = [:] // id -> exact pending row snapshot

            for row in vm.lamps where rng.bool() {
                let id = row.id
                let on = rng.bool()
                let task = Task { @MainActor in await vm.toggle(id: id, on: on) }
                pendingTasks.append(task)
                _ = await Self.waitUntil { vm.lamps.first(where: { $0.id == id })?.isPending == true }
            }
            // Snapshot the exact pending rows AFTER all pending toggles are in
            // flight (their displayedPower is the optimistic value the toggle set).
            for row in vm.lamps where row.isPending {
                pendingExpected[row.id] = row
                pendingObserved += 1
            }

            // 3. Build `fresh`: a reordered mix that (a) keeps some pending ids
            //    with a DIFFERENT power, (b) keeps some non-pending ids with a
            //    possibly different power, (c) drops some ids, (d) adds new ids.
            var fresh: [LampDTO] = []
            var shuffledCurrent = vm.lamps
            // Fisher-Yates shuffle with the deterministic RNG for reordering.
            for i in stride(from: shuffledCurrent.count - 1, to: 0, by: -1) {
                let j = rng.int(0..<(i + 1))
                shuffledCurrent.swapAt(i, j)
            }
            for row in shuffledCurrent {
                if rng.bool() && !row.isPending {
                    // Drop this non-pending id from fresh (must be removed).
                    continue
                }
                // For pending ids, force the polled power to differ from the
                // displayed optimistic value where possible, proving the pending
                // row is NOT overwritten.
                let polledPower: Bool
                if row.isPending {
                    polledPower = !row.displayedPower
                    if polledPower != row.displayedPower { divergingPending += 1 }
                } else {
                    polledPower = rng.bool()
                    if polledPower != row.displayedPower { adoptedDiffered += 1 }
                }
                fresh.append(Self.makeLamp(id: row.id, power: polledPower, &rng))
            }
            // Add up to two brand-new ids not currently displayed.
            let newCount = rng.int(0..<3)
            var newIDs: [String] = []
            for n in 0..<newCount {
                let id = "new-\(Self.makeIDStem(&rng))-\(n)"
                newIDs.append(id)
                fresh.append(Self.makeLamp(id: id, power: rng.bool(), &rng))
            }

            // 4. Apply the poll.
            vm.applyPoll(fresh)

            // --- Assertions -------------------------------------------------
            let after = vm.lamps

            // Final order equals `fresh` order keyed by id.
            #expect(after.map(\.id) == fresh.map(\.id),
                    "applyPoll result order must equal fresh order")

            let afterByID = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            for dto in fresh {
                guard let resultRow = afterByID[dto.id] else {
                    Issue.record("row \(dto.id) present in fresh missing after applyPoll")
                    continue
                }
                if let expectedPending = pendingExpected[dto.id] {
                    // Pending rows retain their EXACT displayed value AND flag.
                    #expect(resultRow == expectedPending,
                            "pending row \(dto.id) must be untouched by applyPoll; expected \(expectedPending) got \(resultRow)")
                    #expect(resultRow.isPending == true)
                } else {
                    // Non-pending rows adopt the polled state, non-pending.
                    #expect(resultRow.displayedPower == dto.state.power,
                            "non-pending row \(dto.id) must adopt polled power \(dto.state.power)")
                    #expect(resultRow.isPending == false,
                            "non-pending row \(dto.id) must be non-pending after applyPoll")
                }
            }

            // Rows absent from fresh are dropped.
            let freshIDs = Set(fresh.map(\.id))
            for row in after {
                #expect(freshIDs.contains(row.id),
                        "row \(row.id) not in fresh must have been dropped")
            }

            // 5. Release the in-flight toggles.
            for task in pendingTasks { task.cancel() }
            for task in pendingTasks { await task.value }

            checked += 1
        }

        #expect(checked >= 100)
        #expect(pendingObserved > 0, "must exercise at least one pending lamp row")
        #expect(divergingPending > 0, "pending rows must be tested against a differing polled value")
        #expect(adoptedDiffered > 0, "non-pending rows must be tested where the polled value differs from prior")
    }

    // MARK: - Property 12 (speaker branch)

    @Test("Property 12 (speaker): applyPoll keeps pending rows untouched and adopts polled state for the rest")
    @MainActor
    func speakerPollPreservesPendingUpdatesRest() async {
        var rng = RNG(seed: 0x12_B0_5AE4_C0DE)
        let allStates: [SpeakerState] = [.playing, .paused, .stopped]
        var checked = 0
        var pendingObserved = 0
        var divergingPending = 0
        var adoptedDiffered = 0

        for _ in 0..<130 {
            // 1. Seed a non-empty displayed speaker list (all online) with unique ids.
            let count = rng.int(2..<7)
            var seedSpeakers: [SpeakerDTO] = []
            for index in 0..<count {
                let id = "\(Self.makeIDStem(&rng))-\(index)"
                seedSpeakers.append(Self.makeSpeaker(id: id, state: rng.pick(allStates), &rng))
            }

            let api = GatedSpeakerAPIClient(seedSpeakers: seedSpeakers)
            let vm = SpeakerViewModel(api: api)
            await vm.activate()
            #expect(vm.speakers.count == count)

            // 2. Make some rows pending via a suspended toggle.
            var pendingTasks: [Task<Void, Never>] = []
            var pendingExpected: [String: SpeakerRow] = [:]

            for row in vm.speakers where rng.bool() {
                let id = row.id
                let on = rng.bool()
                let task = Task { @MainActor in await vm.toggle(id: id, on: on) }
                pendingTasks.append(task)
                _ = await Self.waitUntil { vm.speakers.first(where: { $0.id == id })?.isPending == true }
            }
            for row in vm.speakers where row.isPending {
                pendingExpected[row.id] = row
                pendingObserved += 1
            }

            // 3. Build `fresh`: reorder, force pending ids to a DIFFERENT state,
            //    vary non-pending ids, drop some, add new ids.
            var fresh: [SpeakerDTO] = []
            var shuffledCurrent = vm.speakers
            for i in stride(from: shuffledCurrent.count - 1, to: 0, by: -1) {
                let j = rng.int(0..<(i + 1))
                shuffledCurrent.swapAt(i, j)
            }
            for row in shuffledCurrent {
                if rng.bool() && !row.isPending {
                    continue // drop this non-pending id
                }
                let polledState: SpeakerState
                if row.isPending {
                    // Choose any state that differs from the optimistic displayed one.
                    let others = allStates.filter { $0 != row.displayedState }
                    polledState = rng.pick(others)
                    if polledState != row.displayedState { divergingPending += 1 }
                } else {
                    polledState = rng.pick(allStates)
                    if polledState != row.displayedState { adoptedDiffered += 1 }
                }
                fresh.append(Self.makeSpeaker(id: row.id, state: polledState, &rng))
            }
            let newCount = rng.int(0..<3)
            for n in 0..<newCount {
                let id = "new-\(Self.makeIDStem(&rng))-\(n)"
                fresh.append(Self.makeSpeaker(id: id, state: rng.pick(allStates), &rng))
            }

            // 4. Apply the poll.
            vm.applyPoll(fresh)

            // --- Assertions -------------------------------------------------
            let after = vm.speakers

            #expect(after.map(\.id) == fresh.map(\.id),
                    "applyPoll result order must equal fresh order")

            let afterByID = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            for dto in fresh {
                guard let resultRow = afterByID[dto.id] else {
                    Issue.record("row \(dto.id) present in fresh missing after applyPoll")
                    continue
                }
                if let expectedPending = pendingExpected[dto.id] {
                    #expect(resultRow == expectedPending,
                            "pending speaker \(dto.id) must be untouched by applyPoll; expected \(expectedPending) got \(resultRow)")
                    #expect(resultRow.isPending == true)
                } else {
                    #expect(resultRow.displayedState == dto.state,
                            "non-pending speaker \(dto.id) must adopt polled state \(dto.state)")
                    #expect(resultRow.isPending == false,
                            "non-pending speaker \(dto.id) must be non-pending after applyPoll")
                }
            }

            let freshIDs = Set(fresh.map(\.id))
            for row in after {
                #expect(freshIDs.contains(row.id),
                        "speaker \(row.id) not in fresh must have been dropped")
            }

            // 5. Release the in-flight toggles.
            for task in pendingTasks { task.cancel() }
            for task in pendingTasks { await task.value }

            checked += 1
        }

        #expect(checked >= 100)
        #expect(pendingObserved > 0, "must exercise at least one pending speaker row")
        #expect(divergingPending > 0, "pending rows must be tested against a differing polled value")
        #expect(adoptedDiffered > 0, "non-pending rows must be tested where the polled value differs from prior")
    }
}
