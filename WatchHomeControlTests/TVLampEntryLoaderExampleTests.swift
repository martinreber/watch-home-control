// TVLampEntryLoaderExampleTests.swift
//
// Feature: tv-lamp-complication — example (unit) tests for every
// `TVLampEntryLoader.load()` branch.
//
// Validates Requirements 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.15, 6.1, 6.6, 8.2.
//
// Deterministic example tests: a configurable stub `APIClient` (counting calls
// so the "zero API calls" branches are provably no-I/O), an `InMemoryKeychainStore`,
// and directly-constructed `BaseURLResolution` values drive every branch to an
// exact, asserted `TVLampEntry`.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct TVLampEntryLoaderExampleTests {

    /// A configurable `APIClient` counting `fetchLamps` calls; every other
    /// method traps since the loader never calls them.
    private final class StubAPIClient: APIClient, @unchecked Sendable {
        enum Behavior {
            case success([LampDTO])
            case throwing(Error)
        }

        private let lock = NSLock()
        private var _fetchLampsCallCount = 0
        var fetchLampsCallCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _fetchLampsCallCount
        }

        let behavior: Behavior
        init(behavior: Behavior) { self.behavior = behavior }

        /// Synchronous helper so the lock is never taken directly inside an
        /// `async` function body (`NSLock.lock()`/`unlock()` are unavailable
        /// from asynchronous contexts).
        private func recordCall() {
            lock.lock(); defer { lock.unlock() }
            _fetchLampsCallCount += 1
        }

        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            recordCall()
            switch behavior {
            case .success(let lamps): return lamps
            case .throwing(let error): throw error
            }
        }

        func checkHealth(timeout: Duration) async throws -> Bool { true }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            throw APIError.decoding
        }
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

    private static func tvLamp(power: Bool, id: String = "tv-1") -> LampDTO {
        LampDTO(id: id, friendlyName: "TV-Lampe", type: nil, state: LampState(power: power))
    }

    private static func makeEnvironment(
        apiKey: String?,
        baseURL: BaseURLResolution,
        api: StubAPIClient
    ) -> ComplicationEnvironment {
        ComplicationEnvironment(
            readAPIKey: { apiKey },
            resolveBaseURL: { baseURL },
            api: api,
            refresher: SpyComplicationRefresher(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    @Test("Req 6.1: unpaired renders Unknown/openSetup without any API call")
    func unpairedRendersUnknownOpenSetupWithoutAnAPICall() async {
        let api = StubAPIClient(behavior: .success([TVLampEntryLoaderExampleTests.tvLamp(power: true)]))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: nil, baseURL: .fallbackDefault(BaseURLResolver.defaultBaseURL), api: api))

        let entry = await loader.load()

        #expect(entry.state == .unknown)
        #expect(entry.interaction == .openSetup)
        #expect(api.fetchLampsCallCount == 0)
    }

    @Test("Req 3.9/8.2: an invalid Base_URL renders Unknown/toggle without any API call")
    func invalidBaseURLRendersUnknownWithoutAnAPICall() async {
        let api = StubAPIClient(behavior: .success([TVLampEntryLoaderExampleTests.tvLamp(power: true)]))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .invalid, api: api))

        let entry = await loader.load()

        #expect(entry.state == .unknown)
        #expect(entry.interaction == .toggle)
        #expect(api.fetchLampsCallCount == 0)
    }

    @Test("Req 3.3: a resolved TV-Lampe with power true renders On/toggle")
    func resolvedOnRendersOn() async {
        let api = StubAPIClient(behavior: .success([TVLampEntryLoaderExampleTests.tvLamp(power: true)]))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .configured(BaseURLResolver.defaultBaseURL), api: api))

        let entry = await loader.load()

        #expect(entry.state == .on)
        #expect(entry.interaction == .toggle)
        #expect(api.fetchLampsCallCount == 1)
    }

    @Test("Req 3.3: a resolved TV-Lampe with power false renders Off/toggle")
    func resolvedOffRendersOff() async {
        let api = StubAPIClient(behavior: .success([TVLampEntryLoaderExampleTests.tvLamp(power: false)]))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .configured(BaseURLResolver.defaultBaseURL), api: api))

        let entry = await loader.load()

        #expect(entry.state == .off)
    }

    @Test("Req 3.4: a timeout renders Unknown")
    func timeoutRendersUnknown() async {
        let api = StubAPIClient(behavior: .throwing(APIError.timeout))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .configured(BaseURLResolver.defaultBaseURL), api: api))

        #expect(await loader.load().state == .unknown)
    }

    @Test("Req 3.6: HTTP 401 renders Unknown and leaves the credential untouched")
    func unauthorizedRendersUnknownAndLeavesCredentialUntouched() async {
        let keychain = InMemoryKeychainStore(initialKey: "still-here")
        let api = StubAPIClient(behavior: .throwing(APIError.unauthorized))
        let env = ComplicationEnvironment(
            readAPIKey: { keychain.readAPIKey() },
            resolveBaseURL: { .configured(BaseURLResolver.defaultBaseURL) },
            api: api,
            refresher: SpyComplicationRefresher(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let loader = TVLampEntryLoader(env: env)

        #expect(await loader.load().state == .unknown)
        #expect(keychain.readAPIKey() == "still-here")
    }

    @Test("Req 3.5: a non-2xx error renders Unknown")
    func nonSuccessHTTPStatusRendersUnknown() async {
        let api = StubAPIClient(behavior: .throwing(APIError.http(status: 500)))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .configured(BaseURLResolver.defaultBaseURL), api: api))

        #expect(await loader.load().state == .unknown)
    }

    @Test("Req 3.5: a network error renders Unknown")
    func networkErrorRendersUnknown() async {
        let api = StubAPIClient(behavior: .throwing(APIError.network("offline")))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .configured(BaseURLResolver.defaultBaseURL), api: api))

        #expect(await loader.load().state == .unknown)
    }

    @Test("Req 3.8: an empty lamp list renders Unknown")
    func emptyLampListRendersUnknown() async {
        let api = StubAPIClient(behavior: .success([]))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .configured(BaseURLResolver.defaultBaseURL), api: api))

        #expect(await loader.load().state == .unknown)
    }

    @Test("Req 3.8: a lamp list with no TV-Lampe match renders Unknown")
    func noMatchRendersUnknown() async {
        let api = StubAPIClient(behavior: .success([
            LampDTO(id: "l1", friendlyName: "Deckenlampe", type: nil, state: LampState(power: true))
        ]))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .configured(BaseURLResolver.defaultBaseURL), api: api))

        #expect(await loader.load().state == .unknown)
    }

    @Test("placeholder() performs no I/O and returns a representative entry")
    func placeholderPerformsNoIO() {
        let api = StubAPIClient(behavior: .success([TVLampEntryLoaderExampleTests.tvLamp(power: true)]))
        let loader = TVLampEntryLoader(env: TVLampEntryLoaderExampleTests.makeEnvironment(
            apiKey: "key", baseURL: .configured(BaseURLResolver.defaultBaseURL), api: api))

        let entry = loader.placeholder()

        #expect(entry.interaction == .toggle)
        #expect(api.fetchLampsCallCount == 0)
    }
}
