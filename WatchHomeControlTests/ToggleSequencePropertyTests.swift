// ToggleSequencePropertyTests.swift
//
// Feature: tv-lamp-complication, Property 6: The toggle service reads,
// inverts, and reads back, never trusting the entry
//
// Validates Requirements 5.2, 5.3, 5.4, 5.5, 5.6, 10.7.
//
// Property statement (design › Correctness Properties, Property 6): for any
// generated starting power and lamp list, `TVLampToggleService.run` against a
// stub `APIClient` issues exactly `GET /lamps` → `POST /lamps/{id}/state` with
// the inverted power → `GET /lamps`, in that order, and issues no `POST` when
// the lamp is unresolved. The command is independent of any state supplied by
// the displayed entry (the service never reads a `TVLampEntry` at all).
//
// Deterministic: a recording `APIClient` double (used sequentially within a
// single `await` chain per case, so no external synchronization is needed) and
// a self-contained RNG drive ≥100 generated (starting power, lamp id, list
// shape) combinations.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct ToggleSequencePropertyTests {

    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Records the sequence of calls made against it. Used sequentially within
    /// a single `await`-chained test case; no internal synchronization needed.
    private final class RecordingAPIClient: APIClient, @unchecked Sendable {
        enum Call: Equatable {
            case fetchLamps
            case setLampState(id: String, power: Bool)
        }

        private(set) var calls: [Call] = []
        /// Lamp lists returned by successive `fetchLamps` calls: [0] is the
        /// initial read, [1] is the read-back.
        let lampsSequence: [[LampDTO]]

        init(lampsSequence: [[LampDTO]]) { self.lampsSequence = lampsSequence }

        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            let index = calls.filter { if case .fetchLamps = $0 { return true }; return false }.count
            calls.append(.fetchLamps)
            return lampsSequence[min(index, lampsSequence.count - 1)]
        }

        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            calls.append(.setLampState(id: id, power: power))
            return LampDTO(id: id, friendlyName: "TV-Lampe", type: nil, state: LampState(power: power))
        }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { [] }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.decoding
        }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.decoding
        }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
            throw APIError.decoding
        }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            throw APIError.unauthorized
        }
    }

    private static func makeEnvironment(api: RecordingAPIClient) -> ComplicationEnvironment {
        ComplicationEnvironment(
            readAPIKey: { "some-key" },
            resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api,
            refresher: SpyComplicationRefresher(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    @Test("Property 6: resolved lamp -> GET, POST(inverted), GET, never trusting a prior entry")
    func resolvedLampFollowsReadInvertReadSequence() async {
        var rng = SeededRNG(seed: 0x706C_E5EE_D9E6_0006)

        for _ in 0..<150 {
            let startPower = Bool.random(using: &rng)
            let id = "tv-\(UInt32.random(in: 0...UInt32.max, using: &rng))"
            let lamp = LampDTO(id: id, friendlyName: "TV-Lampe", type: nil, state: LampState(power: startPower))

            let api = ToggleSequencePropertyTests.RecordingAPIClient(lampsSequence: [
                [lamp],
                [LampDTO(id: id, friendlyName: "TV-Lampe", type: nil, state: LampState(power: !startPower))],
            ])
            let service = TVLampToggleService(env: ToggleSequencePropertyTests.makeEnvironment(api: api))

            let outcome = await service.run()

            #expect(api.calls == [.fetchLamps, .setLampState(id: id, power: !startPower), .fetchLamps])
            #expect(outcome == .toggled(startPower ? .off : .on))
        }
    }

    @Test("Property 6: an unresolved initial read sends no POST")
    func unresolvedInitialReadSendsNoPOST() async {
        var rng = SeededRNG(seed: 0x706C_E5EE_D9E6_0007)

        for _ in 0..<150 {
            let count = Int.random(in: 0..<4, using: &rng)
            let nonMatching = (0..<count).map { i in
                LampDTO(id: "other-\(i)", friendlyName: "Deckenlampe", type: nil, state: LampState(power: false))
            }
            let api = ToggleSequencePropertyTests.RecordingAPIClient(lampsSequence: [nonMatching])
            let service = TVLampToggleService(env: ToggleSequencePropertyTests.makeEnvironment(api: api))

            let outcome = await service.run()

            #expect(api.calls == [.fetchLamps])
            #expect(outcome == .unresolved)
        }
    }
}
