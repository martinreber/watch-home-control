// AppModelComplicationRefreshExampleTests.swift
//
// Feature: tv-lamp-complication — example (unit) tests for the AppModel-side
// Complication refresh hooks.
//
// Validates Requirements 6.4, 6.5, 7.11, 7.12, 7.13.
//
// Deterministic example tests: an `AppModel` is constructed with a
// `ComplicationPublisher` backed by a `SpyComplicationRefresher`, so every hook
// (successful pairing, Auth_Error, a Poll_Cycle) can assert the exact reload
// count it produces without touching WidgetKit.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct AppModelComplicationRefreshExampleTests {

    private final class FakeSettingsStore: SettingsStore, @unchecked Sendable {
        private var url: URL
        init(_ url: URL) { self.url = url }
        var baseURL: URL { url }
        func setBaseURL(_ newValue: URL) { url = newValue }
    }

    /// A configurable `APIClient`: `redeemPairingCode` for the pairing test,
    /// `fetchLamps` for the poll test. Every other method traps.
    private final class StubAPIClient: APIClient, @unchecked Sendable {
        var redeemResult: Result<String, Error> = .failure(APIError.unauthorized)
        var lampsSequence: [[LampDTO]] = [[]]
        private var lampsCallIndex = 0

        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            switch redeemResult {
            case .success(let key): return key
            case .failure(let error): throw error
            }
        }

        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            let lamps = lampsSequence[min(lampsCallIndex, lampsSequence.count - 1)]
            lampsCallIndex += 1
            return lamps
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
    }

    private static let baseURL = URL(string: "https://192.168.1.122:8443")!

    private static func tvLamp(power: Bool) -> LampDTO {
        LampDTO(id: "tv-1", friendlyName: "TV-Lampe", type: nil, state: LampState(power: power))
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if predicate() { return true }
            await Task.yield()
        }
        return predicate()
    }

    @Test("Req 7.11: a successful pairing publishes immediately")
    @MainActor
    func successfulPairingPublishesImmediately() async {
        let api = StubAPIClient()
        api.redeemResult = .success("fresh-key")
        let refresher = SpyComplicationRefresher()
        let publisher = ComplicationPublisher(refresher: refresher)
        let model = AppModel(
            api: api, keychain: InMemoryKeychainStore(), settings: FakeSettingsStore(Self.baseURL),
            publisher: publisher
        )

        let result = await model.submitSetup(baseURL: Self.baseURL.absoluteString, code: "123456")

        #expect(result == .success)
        #expect(refresher.reloadCount == 1)
    }

    @Test("Req 6.4/6.5: an Auth_Error publishes immediately")
    @MainActor
    func authErrorPublishesImmediately() {
        let refresher = SpyComplicationRefresher()
        let publisher = ComplicationPublisher(refresher: refresher)
        let model = AppModel(
            api: StubAPIClient(), keychain: InMemoryKeychainStore(initialKey: "k"),
            settings: FakeSettingsStore(Self.baseURL), publisher: publisher
        )

        model.handleAuthError()

        #expect(refresher.reloadCount == 1)
    }

    @Test("Req 7.12: a Poll_Cycle with an unchanged TV-Lampe power publishes only once")
    @MainActor
    func pollCycleWithUnchangedPowerPublishesOnce() async {
        let api = StubAPIClient()
        api.lampsSequence = [[Self.tvLamp(power: true)]]
        let refresher = SpyComplicationRefresher()
        let publisher = ComplicationPublisher(refresher: refresher)
        let model = AppModel(
            api: api, keychain: InMemoryKeychainStore(initialKey: "k"),
            settings: FakeSettingsStore(Self.baseURL), publisher: publisher
        )
        let lampVM = LampViewModel(api: api)
        let speakerVM = SpeakerViewModel(api: api)

        model.startPolling(lamps: lampVM, speakers: speakerVM)
        _ = await waitUntil { lampVM.lamps.count == 1 }
        model.stopPolling()

        // The first observation always reaches the face (Property 7), and no
        // further reload is needed since the power never changed.
        #expect(refresher.reloadCount == 1)
    }

    @Test("Req 7.11: forwarding a lamp command's TV-Lampe result publishes")
    @MainActor
    func notifyLampUpdatedPublishesForTheTVLampe() {
        let refresher = SpyComplicationRefresher()
        let publisher = ComplicationPublisher(refresher: refresher)
        let model = AppModel(
            api: StubAPIClient(), keychain: InMemoryKeychainStore(initialKey: "k"),
            settings: FakeSettingsStore(Self.baseURL), publisher: publisher
        )

        model.notifyLampUpdated(Self.tvLamp(power: false))
        #expect(refresher.reloadCount == 1)

        // A non-TV-Lampe lamp must not trigger a reload.
        model.notifyLampUpdated(LampDTO(id: "other", friendlyName: "Deckenlampe", type: nil, state: LampState(power: true)))
        #expect(refresher.reloadCount == 1)
    }
}
