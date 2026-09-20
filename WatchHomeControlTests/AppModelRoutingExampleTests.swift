// AppModelRoutingExampleTests.swift
//
// Feature: apple-watch-home-control — example (unit) tests for AppModel launch
// routing, connection-health mapping, and Auth_Error routing.
//
// These are deterministic example tests (not property tests): each case seeds
// fixed doubles and asserts an exact routing/health outcome.
//
// Validates Requirements:
//   - 1.1  launch AND no API_Key stored -> Setup_Screen.
//   - 1.9  launch AND API_Key present   -> proceed past Setup to the control screen.
//   - 3.2  GET /health == HTTP 200       -> Backend treated as reachable.
//   - 3.3  GET /health times out          -> German "not reachable" message.
//   - 3.4  GET /health non-200 / network error -> German "not reachable" message.
//   - 2.4  Auth_Error (HTTP 401) raised   -> present the Setup_Screen for re-pairing.
//
// AppModel API driven:
//   - onLaunch()        — launch routing (Req 1.1 / 1.9), which delegates to
//   - runHealthCheck()  — GET /health mapping onto healthState + route (Req 3.2–3.4)
//   - handleAuthError() — Auth_Error routing back to Setup (Req 2.4)
//
// Doubles (mirroring the sibling *PropertyTests convention): a configurable
// `MockAPIClient` whose `checkHealth` can return true, return false, or throw a
// specific `APIError`; the shared in-memory `InMemoryKeychainStore` (seeded or
// empty); and an in-memory `FakeSettingsStore`. No device, network, or
// UserDefaults involvement — outcomes are exact and reproducible.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct AppModelRoutingExampleTests {

    // MARK: - Test doubles

    /// In-memory `SettingsStore` — no UserDefaults, no shared state.
    private final class FakeSettingsStore: SettingsStore, @unchecked Sendable {
        private var url: URL
        init(_ url: URL) { self.url = url }
        var baseURL: URL { url }
        func setBaseURL(_ newValue: URL) { url = newValue }
    }

    /// An `APIClient` whose `checkHealth` behaviour is configurable per test.
    /// Only `checkHealth` is exercised by these tests; every other method traps
    /// (they are never on the launch/health/auth paths under test).
    private final class MockAPIClient: APIClient, @unchecked Sendable {
        /// How `checkHealth` should behave.
        enum HealthBehavior {
            case reachable          // HTTP 200 -> true (Req 3.2)
            case notReachable       // non-200 mapped to false by the client
            case throwing(APIError) // timeout / network / non-2xx thrown (Req 3.3/3.4)
        }

        let health: HealthBehavior
        init(health: HealthBehavior) { self.health = health }

        func checkHealth(timeout: Duration) async throws -> Bool {
            switch health {
            case .reachable:            return true
            case .notReachable:         return false
            case .throwing(let error):  throw error
            }
        }

        // Not part of launch/health/auth routing — never called here.
        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {
            Issue.record("moveBlind must not be called by routing/health tests")
        }
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            Issue.record("fetchLamps must not be called by routing/health tests"); return []
        }
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            Issue.record("setLampState must not be called by routing/health tests")
            throw APIError.decoding
        }
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] {
            Issue.record("fetchSpeakers must not be called by routing/health tests"); return []
        }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("playSpeaker must not be called by routing/health tests")
            throw APIError.decoding
        }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("pauseSpeaker must not be called by routing/health tests")
            throw APIError.decoding
        }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("playRadio must not be called by routing/health tests")
            throw APIError.decoding
        }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            Issue.record("redeemPairingCode must not be called by routing/health tests")
            throw APIError.unauthorized
        }
    }

    private static let baseURL = URL(string: "http://192.168.1.122:8080")!

    @MainActor
    private func makeModel(
        health: MockAPIClient.HealthBehavior,
        storedKey: String?
    ) -> (AppModel, MockAPIClient, InMemoryKeychainStore) {
        let api = MockAPIClient(health: health)
        let keychain = storedKey.map { InMemoryKeychainStore(initialKey: $0) } ?? InMemoryKeychainStore()
        let settings = FakeSettingsStore(AppModelRoutingExampleTests.baseURL)
        return (AppModel(api: api, keychain: keychain, settings: settings), api, keychain)
    }

    // MARK: - Launch routing (Req 1.1 / 1.9)

    @Test("Req 1.1: launch with no stored API_Key routes to the Setup_Screen")
    @MainActor
    func launchWithoutKeyRoutesToSetup() async {
        // Health would report reachable, but with no key the launch must stop at
        // Setup before ever consulting /health.
        let (model, _, _) = makeModel(health: .reachable, storedKey: nil)

        await model.onLaunch()

        #expect(model.route == .setup,
                "launch with no stored API_Key must display the Setup_Screen (Req 1.1)")
    }

    @Test("Req 1.9: launch with a stored API_Key and a reachable Backend proceeds to the control screen")
    @MainActor
    func launchWithKeyRoutesPastSetup() async {
        let (model, _, _) = makeModel(health: .reachable, storedKey: "stored-api-key-123")

        await model.onLaunch()

        #expect(model.route == .control,
                "launch with a stored API_Key must proceed past Setup to the control screen (Req 1.9)")
        #expect(model.healthState == .reachable)
    }

    // MARK: - Health mapping (Req 3.2 / 3.3 / 3.4)

    @Test("Req 3.2: GET /health 200 marks the Backend reachable and routes to control")
    @MainActor
    func healthOKMapsToReachable() async {
        let (model, _, _) = makeModel(health: .reachable, storedKey: "k")

        await model.runHealthCheck()

        #expect(model.healthState == .reachable,
                "HTTP 200 must map to a reachable HealthState (Req 3.2)")
        #expect(model.route == .control,
                "a reachable Backend must route to the control screen (Req 3.2)")
    }

    @Test("Req 3.3: a health-check timeout maps to an unreachable state with the German message")
    @MainActor
    func healthTimeoutMapsToUnreachable() async {
        let (model, _, _) = makeModel(health: .throwing(.timeout), storedKey: "k")
        model.route = .setup   // route must be left unchanged so the user can retry

        await model.runHealthCheck()

        #expect(model.healthState == .unreachable(Strings.backendUnreachable),
                "a health-check timeout must map to unreachable with the German message (Req 3.3)")
        #expect(model.route == .setup,
                "an unreachable result must leave the route unchanged so the user can retry (Req 3.3)")
    }

    @Test("Req 3.4: a non-200 health status maps to an unreachable state with the German message")
    @MainActor
    func healthNon200MapsToUnreachable() async {
        // The client reports non-2xx as `false` from checkHealth.
        let (model, _, _) = makeModel(health: .notReachable, storedKey: "k")

        await model.runHealthCheck()

        #expect(model.healthState == .unreachable(Strings.backendUnreachable),
                "a non-200 health status must map to unreachable with the German message (Req 3.4)")
    }

    @Test("Req 3.4: a network error during the health check maps to an unreachable state")
    @MainActor
    func healthNetworkErrorMapsToUnreachable() async {
        let (model, _, _) = makeModel(health: .throwing(.network("connection refused")), storedKey: "k")

        await model.runHealthCheck()

        #expect(model.healthState == .unreachable(Strings.backendUnreachable),
                "a network error must map to unreachable with the German message (Req 3.4)")
    }

    // MARK: - Auth routing (Req 2.4)

    @Test("Req 2.4: an Auth_Error (HTTP 401) routes back to the Setup_Screen for re-pairing without deleting the key")
    @MainActor
    func authErrorRoutesToSetup() async {
        let storedKey = "must-survive-a-401"
        let (model, _, keychain) = makeModel(health: .reachable, storedKey: storedKey)
        model.route = .control

        // handleAuthError() is the single entry point every authenticated call
        // funnels a 401 into (consistent with AuthError401PropertyTests).
        model.handleAuthError()

        #expect(model.route == .setup,
                "an Auth_Error must present the Setup_Screen for re-pairing (Req 2.4)")
        #expect(model.authErrorMessage == Strings.pairingInvalid,
                "an Auth_Error must surface the German invalid-credential message (Req 2.3/2.4)")
        #expect(keychain.readAPIKey() == storedKey,
                "an Auth_Error must not modify the stored API_Key (Req 2.3/2.4)")
    }
}
