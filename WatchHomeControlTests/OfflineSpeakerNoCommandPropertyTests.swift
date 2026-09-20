// OfflineSpeakerNoCommandPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 7: Offline speakers cannot issue commands
//
// Validates Requirements 7.7.
//
// Property statement (design › Correctness Properties, Property 7): *for any*
// speaker whose `online` is `false`, its toggle is disabled and invoking its
// toggle action issues NO Backend command. Requirement 7.7 phrases this as
// "WHILE a Speaker has `online` equal to `false`, THE Watch_App SHALL disable
// that Speaker's toggle and prevent its activation".
//
// How this is exercised: a varied list mixing online and offline speakers is
// seeded into a SpeakerViewModel via `activate()` against a mock APIClient. A
// target row is picked per iteration.
//
//   • OFFLINE target — calling `toggle(id:on:)` must:
//       - issue NO command (playSpeaker/pauseSpeaker/playRadio never called),
//       - leave the target row byte-for-byte unchanged (== the prior SpeakerRow,
//         so displayed state is unchanged AND the row is not marked pending),
//       - set no error feedback (feedback stays nil).
//
//   • ONLINE target (the counter-case) — calling `toggle(id:on:)` must issue
//     EXACTLY ONE command. This proves the guard is specifically about
//     `online == false`, not a blanket no-op, so a `toggle` that did nothing at
//     all would fail this half.
//
// Both halves are counted and the test asserts at the end that each was
// actually exercised across the run.
//
// Pure and deterministic: an in-memory mock `APIClient` that RECORDS which
// command (if any) was issued and for which id, no network, no shared global
// state. A self-contained splitmix64 generator drives ≥100 iterations with no
// third-party dependency, matching the sibling *PropertyTests convention.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct OfflineSpeakerNoCommandPropertyTests {

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

    private static func makeIDStem(_ rng: inout RNG) -> String {
        let length = rng.int(1..<8)
        var chars: [Character] = []
        for _ in 0..<length { chars.append(rng.pick(idAlphabet)) }
        return String(chars)
    }

    /// Makes a speaker with an explicit `online` flag so the test controls the
    /// online/offline mix precisely.
    private static func makeSpeaker(id: String, online: Bool, _ rng: inout RNG) -> SpeakerDTO {
        let names = ["Küche", "Wohnzimmer", "Bad", "Schlafzimmer", "Büro"]
        let models: [String?] = ["Sonos One", "Play:1", "Beam", nil]
        return SpeakerDTO(
            id: id,
            name: rng.pick(names),
            state: rng.pick(allStates),
            online: online,
            modelName: rng.pick(models)
        )
    }

    /// Builds a speaker list with unique ids, guaranteeing at least one offline
    /// and at least one online speaker so both target kinds are always pickable.
    private static func makeMixedList(count: Int, _ rng: inout RNG) -> [SpeakerDTO] {
        var speakers: [SpeakerDTO] = []
        for index in 0..<count {
            let id = "\(makeIDStem(&rng))-\(index)"
            speakers.append(makeSpeaker(id: id, online: rng.bool(), &rng))
        }
        // Force the mix: index 0 offline, index 1 online (count >= 2 always).
        speakers[0] = makeSpeaker(id: speakers[0].id, online: false, &rng)
        speakers[1] = makeSpeaker(id: speakers[1].id, online: true, &rng)
        rng.shuffle(&speakers)
        return speakers
    }

    // MARK: - Test double

    /// A mock `APIClient` that RECORDS every speaker command it receives. The
    /// online counter-case returns a benign `SpeakerDTO` so the online toggle
    /// completes successfully (exactly one command issued). `fetchSpeakers`
    /// returns the seeded list verbatim. All lamp/blind/pairing methods are
    /// unused by this property.
    private final class RecordingSpeakerAPIClient: APIClient, @unchecked Sendable {
        let seedSpeakers: [SpeakerDTO]
        /// Total number of play/pause/radio commands issued.
        private(set) var commandCount = 0
        /// The id most recently commanded (for cross-checking the target).
        private(set) var lastCommandedID: String?

        init(seedSpeakers: [SpeakerDTO]) { self.seedSpeakers = seedSpeakers }

        private func record(id: String) -> SpeakerDTO {
            commandCount += 1
            lastCommandedID = id
            // Return a benign, playing speaker so the online case succeeds.
            return SpeakerDTO(id: id, name: "ok", state: .playing, online: true, modelName: nil)
        }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { [] }
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO { throw APIError.timeout }
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { seedSpeakers }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO { record(id: id) }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO { record(id: id) }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO { record(id: id) }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String { throw APIError.timeout }
    }

    // MARK: - Property 7

    @Test("Property 7: offline speakers issue no command and stay unchanged; online speakers issue exactly one")
    @MainActor
    func offlineSpeakersCannotIssueCommands() async {
        var rng = RNG(seed: 0x07_0FF1_11E5_0FFF)
        var checked = 0
        var offlineCasesExercised = 0
        var onlineCasesExercised = 0

        for _ in 0..<130 {
            let count = rng.int(2..<8)
            let seed = Self.makeMixedList(count: count, &rng)

            let api = RecordingSpeakerAPIClient(seedSpeakers: seed)
            let vm = SpeakerViewModel(api: api)
            await vm.activate()

            // Sanity: activation issues no command and no feedback.
            #expect(api.commandCount == 0)
            #expect(vm.feedback == nil)

            let offlineIDs = seed.filter { !$0.online }.map(\.id)
            let onlineIDs = seed.filter { $0.online }.map(\.id)
            // makeMixedList guarantees at least one of each.
            #expect(!offlineIDs.isEmpty)
            #expect(!onlineIDs.isEmpty)

            // Alternate between the offline (guard) case and the online
            // (counter) case so both branches are exercised every couple of
            // iterations.
            let doOffline = rng.bool()

            if doOffline {
                let targetID = rng.pick(offlineIDs)
                let priorRow = vm.speakers.first(where: { $0.id == targetID })!
                let requestedOn = rng.bool()

                await vm.toggle(id: targetID, on: requestedOn)

                // No command was issued at all.
                #expect(api.commandCount == 0,
                        "offline toggle must issue NO command (id=\(targetID))")
                // The target row is byte-for-byte unchanged: displayed state
                // preserved AND not marked pending.
                let afterRow = vm.speakers.first(where: { $0.id == targetID })!
                #expect(afterRow == priorRow,
                        "offline toggle must leave the row unchanged (id=\(targetID))")
                #expect(afterRow.isPending == false)
                #expect(afterRow.displayedState == priorRow.displayedState)
                // The whole displayed list is unchanged too.
                #expect(vm.speakers.map(\.id) == seed.map(\.id))
                // No error feedback surfaced.
                #expect(vm.feedback == nil,
                        "offline toggle must set no feedback (id=\(targetID))")

                offlineCasesExercised += 1
            } else {
                // Counter-case: an ONLINE target issues EXACTLY ONE command.
                let targetID = rng.pick(onlineIDs)
                let requestedOn = rng.bool()

                await vm.toggle(id: targetID, on: requestedOn)

                #expect(api.commandCount == 1,
                        "online toggle must issue exactly one command (id=\(targetID))")
                #expect(api.lastCommandedID == targetID,
                        "online toggle must command the target speaker (id=\(targetID))")

                onlineCasesExercised += 1
            }

            checked += 1
        }

        #expect(checked >= 100)
        // Prove BOTH halves of the property were actually exercised.
        #expect(offlineCasesExercised > 0, "must exercise the offline (no command) case")
        #expect(onlineCasesExercised > 0, "must exercise the online (one command) counter-case")
    }
}
