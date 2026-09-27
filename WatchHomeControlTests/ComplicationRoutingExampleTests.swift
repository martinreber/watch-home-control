// ComplicationRoutingExampleTests.swift
//
// Feature: tv-lamp-complication — example (unit) tests for
// `AppModel.openSetupFromComplication()`.
//
// Validates Requirements 6.3, 6.4.
//
// Deterministic example tests: `openSetupFromComplication()` routes to
// `.setup` unconditionally (from `.control` and from `.setup` itself), clears
// any pending Auth_Error banner, and refreshes the Base_URL field — matching
// what the Complication's Setup_Deep_Link requires (Req 6.3). `DeepLink`
// filtering itself (ignoring unrelated URLs) is covered by
// `DeepLinkPropertyTests`; this file covers the `AppModel` routing behaviour
// the deep link triggers.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct ComplicationRoutingExampleTests {

    private final class FakeSettingsStore: SettingsStore, @unchecked Sendable {
        private var url: URL
        init(_ url: URL) { self.url = url }
        var baseURL: URL { url }
        func setBaseURL(_ newValue: URL) { url = newValue }
    }

    /// `checkHealth` is the only method these routing tests could reach, and
    /// only if a bug caused a health check to be (wrongly) triggered.
    private final class UnreachableAPIClient: APIClient, @unchecked Sendable {
        func checkHealth(timeout: Duration) async throws -> Bool {
            Issue.record("checkHealth must not be called by complication-routing tests"); return false
        }
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] { [] }
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

    private static let baseURL = URL(string: "https://192.168.1.122:8443")!

    @MainActor
    private func makeModel(storedKey: String? = "some-key") -> AppModel {
        let keychain = storedKey.map { InMemoryKeychainStore(initialKey: $0) } ?? InMemoryKeychainStore()
        return AppModel(
            api: UnreachableAPIClient(),
            keychain: keychain,
            settings: FakeSettingsStore(ComplicationRoutingExampleTests.baseURL)
        )
    }

    @Test("Req 6.3: routes to Setup from Control")
    @MainActor
    func routesToSetupFromControl() {
        let model = makeModel()
        model.route = .control

        model.openSetupFromComplication()

        #expect(model.route == .setup)
    }

    @Test("Req 6.3: routes to Setup even when already on Setup")
    @MainActor
    func routesToSetupFromSetupItself() {
        let model = makeModel()
        model.route = .setup

        model.openSetupFromComplication()

        #expect(model.route == .setup)
    }

    @Test("Req 6.4: clears a pending Auth_Error banner and refreshes the Base_URL field")
    @MainActor
    func clearsAuthErrorAndRefreshesBaseURLField() {
        let model = makeModel()
        model.authErrorMessage = Strings.pairingInvalid
        model.baseURLField = "stale"

        model.openSetupFromComplication()

        #expect(model.authErrorMessage == nil)
        #expect(model.baseURLField == ComplicationRoutingExampleTests.baseURL.absoluteString)
    }
}
