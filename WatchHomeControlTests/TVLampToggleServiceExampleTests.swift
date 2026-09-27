// TVLampToggleServiceExampleTests.swift
//
// Feature: tv-lamp-complication — example (unit) tests for every
// `TVLampToggleService.Outcome`.
//
// Validates Requirements 5.5, 5.6, 5.7, 5.8, 5.9, 10.7.
//
// Deterministic example tests: a configurable stub `APIClient` drives each
// outcome exactly, and every case asserts the `SpyComplicationRefresher`
// recorded exactly one reload.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct TVLampToggleServiceExampleTests {

    private final class StubAPIClient: APIClient, @unchecked Sendable {
        enum FetchBehavior {
            case success([LampDTO])
            case throwing(Error)
        }

        /// Successive `fetchLamps` results/failures: [0] initial read, [1] read-back.
        var fetchBehaviors: [FetchBehavior]
        var setStateBehavior: Result<LampDTO, Error> = .failure(APIError.decoding)
        private var fetchIndex = 0
        private(set) var fetchLampsCallCount = 0

        init(fetchBehaviors: [FetchBehavior]) { self.fetchBehaviors = fetchBehaviors }

        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            fetchLampsCallCount += 1
            let behavior = fetchBehaviors[min(fetchIndex, fetchBehaviors.count - 1)]
            fetchIndex += 1
            switch behavior {
            case .success(let lamps): return lamps
            case .throwing(let error): throw error
            }
        }

        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            switch setStateBehavior {
            case .success(let lamp): return lamp
            case .failure(let error): throw error
            }
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

    private static let lampID = "tv-1"

    private static func lamp(power: Bool) -> LampDTO {
        LampDTO(id: lampID, friendlyName: "TV-Lampe", type: nil, state: LampState(power: power))
    }

    @Test("Req 5.6: unresolved initial read -> .unresolved, no POST, exactly one reload")
    func unresolvedInitialReadOutcome() async {
        let api = StubAPIClient(fetchBehaviors: [.success([])])
        let refresher = SpyComplicationRefresher()
        let env = ComplicationEnvironment(
            readAPIKey: { "key" }, resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api, refresher: refresher, now: { Date(timeIntervalSince1970: 0) })

        let outcome = await TVLampToggleService(env: env).run()

        #expect(outcome == .unresolved)
        #expect(refresher.reloadCount == 1)
    }

    @Test("Req 5.7: the initial read failing -> .failed, exactly one reload")
    func initialReadFailureOutcome() async {
        let api = StubAPIClient(fetchBehaviors: [.throwing(APIError.timeout)])
        let refresher = SpyComplicationRefresher()
        let env = ComplicationEnvironment(
            readAPIKey: { "key" }, resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api, refresher: refresher, now: { Date(timeIntervalSince1970: 0) })

        let outcome = await TVLampToggleService(env: env).run()

        #expect(outcome == .failed)
        #expect(refresher.reloadCount == 1)
    }

    @Test("Req 5.8: the command failing -> .failed, exactly one reload")
    func commandFailureOutcome() async {
        let api = StubAPIClient(fetchBehaviors: [.success([TVLampToggleServiceExampleTests.lamp(power: true)])])
        api.setStateBehavior = .failure(APIError.http(status: 500))
        let refresher = SpyComplicationRefresher()
        let env = ComplicationEnvironment(
            readAPIKey: { "key" }, resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api, refresher: refresher, now: { Date(timeIntervalSince1970: 0) })

        let outcome = await TVLampToggleService(env: env).run()

        #expect(outcome == .failed)
        #expect(refresher.reloadCount == 1)
    }

    @Test("Req 5.9: HTTP 401 on the command -> .failed, exactly one reload")
    func commandUnauthorizedOutcome() async {
        let api = StubAPIClient(fetchBehaviors: [.success([TVLampToggleServiceExampleTests.lamp(power: true)])])
        api.setStateBehavior = .failure(APIError.unauthorized)
        let refresher = SpyComplicationRefresher()
        let env = ComplicationEnvironment(
            readAPIKey: { "key" }, resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api, refresher: refresher, now: { Date(timeIntervalSince1970: 0) })

        let outcome = await TVLampToggleService(env: env).run()

        #expect(outcome == .failed)
        #expect(refresher.reloadCount == 1)
    }

    @Test("Req 5.5: the read-back failing -> .readBackFailed, exactly one reload")
    func readBackFailureOutcome() async {
        let api = StubAPIClient(fetchBehaviors: [
            .success([TVLampToggleServiceExampleTests.lamp(power: true)]),
            .throwing(APIError.timeout),
        ])
        api.setStateBehavior = .success(TVLampToggleServiceExampleTests.lamp(power: false))
        let refresher = SpyComplicationRefresher()
        let env = ComplicationEnvironment(
            readAPIKey: { "key" }, resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api, refresher: refresher, now: { Date(timeIntervalSince1970: 0) })

        let outcome = await TVLampToggleService(env: env).run()

        #expect(outcome == .readBackFailed)
        #expect(refresher.reloadCount == 1)
    }

    @Test("Req 5.5: a read-back that no longer resolves the TV-Lampe -> .readBackFailed")
    func readBackNoLongerResolvesOutcome() async {
        let api = StubAPIClient(fetchBehaviors: [
            .success([TVLampToggleServiceExampleTests.lamp(power: true)]),
            .success([]),
        ])
        api.setStateBehavior = .success(TVLampToggleServiceExampleTests.lamp(power: false))
        let refresher = SpyComplicationRefresher()
        let env = ComplicationEnvironment(
            readAPIKey: { "key" }, resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api, refresher: refresher, now: { Date(timeIntervalSince1970: 0) })

        let outcome = await TVLampToggleService(env: env).run()

        #expect(outcome == .readBackFailed)
        #expect(refresher.reloadCount == 1)
    }

    @Test("The full success path -> .toggled(state), exactly one reload")
    func fullSuccessOutcome() async {
        let api = StubAPIClient(fetchBehaviors: [
            .success([TVLampToggleServiceExampleTests.lamp(power: true)]),
            .success([TVLampToggleServiceExampleTests.lamp(power: false)]),
        ])
        api.setStateBehavior = .success(TVLampToggleServiceExampleTests.lamp(power: false))
        let refresher = SpyComplicationRefresher()
        let env = ComplicationEnvironment(
            readAPIKey: { "key" }, resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api, refresher: refresher, now: { Date(timeIntervalSince1970: 0) })

        let outcome = await TVLampToggleService(env: env).run()

        #expect(outcome == .toggled(.off))
        #expect(refresher.reloadCount == 1)
    }

    @Test("Defensive: no API_Key -> .unpaired, exactly one reload, no API calls")
    func unpairedOutcome() async {
        let api = StubAPIClient(fetchBehaviors: [.success([TVLampToggleServiceExampleTests.lamp(power: true)])])
        let refresher = SpyComplicationRefresher()
        let env = ComplicationEnvironment(
            readAPIKey: { nil }, resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api, refresher: refresher, now: { Date(timeIntervalSince1970: 0) })

        let outcome = await TVLampToggleService(env: env).run()

        #expect(outcome == .unpaired)
        #expect(refresher.reloadCount == 1)
        #expect(api.fetchLampsCallCount == 0)
    }
}
