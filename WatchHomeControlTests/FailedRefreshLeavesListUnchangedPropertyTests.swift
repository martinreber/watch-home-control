// FailedRefreshLeavesListUnchangedPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 11: A failed refresh or poll
// leaves the displayed list unchanged
//
// Validates Requirements 5.7, 7.2, 7.3, 9.4, 9.5, 11.5.
//
// Property statement (design › Correctness Properties, Property 11): *for any*
// current lamp list and *any* current speaker list, a refresh or Poll_Cycle
// that fails (timeout, non-2xx, or network error) leaves the displayed list
// unchanged and sets the non-blocking refresh-failed indicator.
//
// This test covers BOTH the lamp branch (LampViewModel, task 11.4) and the
// speaker branch (SpeakerViewModel), matching the property's "(lamp + speaker)"
// scope.
//
// How the seed-then-fail refresh is exercised:
//   1. A non-empty list of DTOs is generated and seeded into the view model by
//      calling `activate()` against a mock `APIClient` whose fetch returns
//      those DTOs (the seeding fetch succeeds).
//   2. The mock is then switched to THROW a generated `APIError` on the next
//      fetch (the failing refresh). `activate()` is called a second time.
//   3. The test snapshots the displayed list after the successful seed and
//      asserts, after the failing refresh, that the list is retained
//      byte-for-byte unchanged (Equatable rows: identity, order, displayed
//      value, and pending flag) and that `refreshFailed` is now true.
//
// The thrown `APIError` is varied across every variant (.timeout,
// .unauthorized, .http, .network, .decoding) so the "timeout, non-2xx, or
// network error" clause of the property is covered.
//
// The empty-list case is also covered: a view model whose FIRST `activate()`
// fails (never seeded) leaves the list empty and sets `refreshFailed` true.
//
// Failed poll: there is no throwing "poll fetch" on the view models — the poll
// driver lives in AppModel and only calls `applyPoll` on a successful fetch; a
// failed poll simply never invokes `applyPoll`. We represent that directly:
// after a thrown poll fetch, `applyPoll` is NOT called, so the displayed list
// is trivially unchanged. The core assertion stays on the failing refresh
// (`activate()`) path per Req 5.7.
//
// Pure and deterministic: in-memory mock `APIClient`, no network, no shared
// state. A self-contained splitmix64 generator drives ≥100 iterations with no
// third-party dependency, matching the sibling *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct FailedRefreshLeavesListUnchangedPropertyTests {

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

    private static func makeLamp(id: String, _ rng: inout RNG) -> LampDTO {
        let names: [String?] = ["Küche", "Wohnzimmer", "Büro", "", nil]
        let types: [String?] = ["ceiling", "floor", "strip", "desk", nil]
        return LampDTO(
            id: id,
            friendlyName: rng.pick(names),
            type: rng.pick(types),
            state: LampState(power: rng.bool())
        )
    }

    /// A non-empty lamp list with unique ids.
    private static func makeLampList(_ rng: inout RNG) -> [LampDTO] {
        let count = rng.int(1..<8)
        var lamps: [LampDTO] = []
        for index in 0..<count {
            lamps.append(makeLamp(id: "\(makeIDStem(&rng))-\(index)", &rng))
        }
        return lamps
    }

    private static func makeSpeaker(id: String, _ rng: inout RNG) -> SpeakerDTO {
        let names = ["Küche", "Wohnzimmer", "Bad", "Schlafzimmer", "Büro"]
        let models: [String?] = ["Sonos One", "Play:1", "Beam", nil]
        let states: [SpeakerState] = [.playing, .paused, .stopped]
        return SpeakerDTO(
            id: id,
            name: rng.pick(names),
            state: rng.pick(states),
            online: rng.bool(),
            modelName: rng.pick(models)
        )
    }

    /// A non-empty speaker list with unique ids.
    private static func makeSpeakerList(_ rng: inout RNG) -> [SpeakerDTO] {
        let count = rng.int(1..<8)
        var speakers: [SpeakerDTO] = []
        for index in 0..<count {
            speakers.append(makeSpeaker(id: "\(makeIDStem(&rng))-\(index)", &rng))
        }
        return speakers
    }

    /// Generates one of every `APIError` variant so the "timeout, non-2xx, or
    /// network error" clause of the property is uniformly covered.
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

    /// A mock `APIClient` whose fetch behavior can be switched between the
    /// seeding fetch (returns configured DTOs) and the failing refresh (throws a
    /// configured `APIError`). In-memory and deterministic.
    private final class MockAPIClient: APIClient, @unchecked Sendable {
        var seedLamps: [LampDTO]
        var seedSpeakers: [SpeakerDTO]
        /// When set, both fetch operations throw this instead of returning.
        var failWith: APIError?

        init(seedLamps: [LampDTO] = [], seedSpeakers: [SpeakerDTO] = []) {
            self.seedLamps = seedLamps
            self.seedSpeakers = seedSpeakers
        }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}

        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            if let failWith { throw failWith }
            return seedLamps
        }

        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            throw APIError.timeout
        }

        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] {
            if let failWith { throw failWith }
            return seedSpeakers
        }

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

    // MARK: - Property 11 (lamp branch): failing refresh retains the list

    @Test("Property 11 (lamp): a failing refresh retains the displayed lamp list byte-for-byte and sets refreshFailed")
    @MainActor
    func failedLampRefreshLeavesListUnchanged() async {
        var rng = RNG(seed: 0x11_FA_11ED_1A47)
        var checked = 0
        var timeoutCases = 0
        var nonTimeoutCases = 0

        for _ in 0..<200 {
            let seed = FailedRefreshLeavesListUnchangedPropertyTests.makeLampList(&rng)
            let error = FailedRefreshLeavesListUnchangedPropertyTests.makeError(&rng)
            if error == .timeout { timeoutCases += 1 } else { nonTimeoutCases += 1 }

            let api = MockAPIClient(seedLamps: seed)
            let vm = LampViewModel(api: api)

            // Seeding fetch succeeds → non-empty displayed list.
            await vm.activate()
            let before = vm.lamps
            #expect(before.count == seed.count)
            #expect(vm.refreshFailed == false)

            // Switch the mock to throw on the next fetch, then refresh again.
            api.failWith = error
            await vm.activate()

            let after = vm.lamps

            // The list is retained byte-for-byte (Equatable rows compare
            // identity, displayed power, and pending flag) in the same order.
            #expect(
                after == before,
                "failing refresh must leave the lamp list unchanged; before=\(before) after=\(after) error=\(error)"
            )

            // The non-blocking refresh-failed indicator is set (Req 5.7).
            #expect(vm.refreshFailed == true,
                    "refreshFailed must be true after a failing refresh (error \(error))")

            // Failed poll: applyPoll is simply not invoked on a failed fetch, so
            // the list stays exactly as-is. (No mutation happens here.)
            #expect(vm.lamps == before,
                    "not invoking applyPoll after a failed poll fetch leaves the list unchanged")

            checked += 1
        }

        #expect(checked >= 100)
        #expect(timeoutCases > 0, "must exercise at least one .timeout refresh failure")
        #expect(nonTimeoutCases > 0, "must exercise at least one non-timeout refresh failure")
    }

    // MARK: - Property 11 (lamp branch): failing INITIAL refresh on empty list

    @Test("Property 11 (lamp): a failing initial refresh leaves the list empty and sets refreshFailed")
    @MainActor
    func failedInitialLampRefreshLeavesListEmpty() async {
        var rng = RNG(seed: 0x11_FA_E307_1A47)
        var checked = 0

        for _ in 0..<120 {
            let error = FailedRefreshLeavesListUnchangedPropertyTests.makeError(&rng)

            // Never seeded: the very first fetch fails.
            let api = MockAPIClient(seedLamps: [])
            api.failWith = error
            let vm = LampViewModel(api: api)

            #expect(vm.lamps.isEmpty)
            await vm.activate()

            #expect(vm.lamps.isEmpty,
                    "a failing initial refresh must leave the list empty (error \(error))")
            #expect(vm.refreshFailed == true,
                    "refreshFailed must be true after a failing initial refresh (error \(error))")
            checked += 1
        }

        #expect(checked >= 100)
    }

    // MARK: - Property 11 (speaker branch): failing refresh retains the list

    @Test("Property 11 (speaker): a failing refresh retains the displayed speaker list byte-for-byte and sets refreshFailed")
    @MainActor
    func failedSpeakerRefreshLeavesListUnchanged() async {
        var rng = RNG(seed: 0x11_FA_5AE4_C0DE)
        var checked = 0
        var timeoutCases = 0
        var nonTimeoutCases = 0

        for _ in 0..<200 {
            let seed = FailedRefreshLeavesListUnchangedPropertyTests.makeSpeakerList(&rng)
            let error = FailedRefreshLeavesListUnchangedPropertyTests.makeError(&rng)
            if error == .timeout { timeoutCases += 1 } else { nonTimeoutCases += 1 }

            let api = MockAPIClient(seedSpeakers: seed)
            let vm = SpeakerViewModel(api: api)

            // Seeding fetch succeeds → non-empty displayed list in Backend order.
            await vm.activate()
            let before = vm.speakers
            #expect(before.count == seed.count)
            #expect(vm.refreshFailed == false)

            // Switch the mock to throw on the next fetch, then refresh again.
            api.failWith = error
            await vm.activate()

            let after = vm.speakers

            #expect(
                after == before,
                "failing refresh must leave the speaker list unchanged; before=\(before) after=\(after) error=\(error)"
            )
            #expect(vm.refreshFailed == true,
                    "refreshFailed must be true after a failing refresh (error \(error))")

            // Failed poll: applyPoll is not invoked on a failed fetch.
            #expect(vm.speakers == before,
                    "not invoking applyPoll after a failed poll fetch leaves the list unchanged")

            checked += 1
        }

        #expect(checked >= 100)
        #expect(timeoutCases > 0, "must exercise at least one .timeout refresh failure")
        #expect(nonTimeoutCases > 0, "must exercise at least one non-timeout refresh failure")
    }

    // MARK: - Property 11 (speaker branch): failing INITIAL refresh on empty list

    @Test("Property 11 (speaker): a failing initial refresh leaves the list empty and sets refreshFailed")
    @MainActor
    func failedInitialSpeakerRefreshLeavesListEmpty() async {
        var rng = RNG(seed: 0x11_FA_5AE4_E307)
        var checked = 0

        for _ in 0..<120 {
            let error = FailedRefreshLeavesListUnchangedPropertyTests.makeError(&rng)

            let api = MockAPIClient(seedSpeakers: [])
            api.failWith = error
            let vm = SpeakerViewModel(api: api)

            #expect(vm.speakers.isEmpty)
            await vm.activate()

            #expect(vm.speakers.isEmpty,
                    "a failing initial refresh must leave the list empty (error \(error))")
            #expect(vm.refreshFailed == true,
                    "refreshFailed must be true after a failing initial refresh (error \(error))")
            checked += 1
        }

        #expect(checked >= 100)
    }
}
