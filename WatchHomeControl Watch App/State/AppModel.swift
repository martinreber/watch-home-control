// State/AppModel.swift — root @Observable view model: routing, health, auth.
//
// `AppModel` owns the top-level navigation state (Setup vs Control), the launch/
// retry health check, and Auth_Error handling. It is the composition root's
// mediator between the SwiftUI views and the core layer (`APIClient`,
// `KeychainStore`, `SettingsStore`).
//
// Routing state machine (design › Routing / App State Machine):
//   launch ─▶ Setup            (no API_Key in Keychain, Req 1.1)
//   launch ─▶ health check     (API_Key present, Req 1.9 / Req 3)
//   Setup  ─▶ Control          (valid key + Base_URL saved, Req 1.4–1.8)
//   health ─▶ Control          (GET /health == 200, Req 3.2)
//   health ─▶ Unreachable      (timeout / non-200 / network, Req 3.3/3.4)
//   Control ─▶ Setup           (config affordance, Req 1.10; or Auth_Error, Req 2.3/2.4)
//
// `AppModel` also owns the poll driver (Req 9): a cancellable `Task` started when
// the control view becomes active (`startPolling`) and cancelled when it goes
// inactive/background (`stopPolling`). Each 5s Poll_Cycle fetches lamps and
// speakers (10s timeout) and hands the results to the view models' `applyPoll`,
// retaining displayed state on any per-cycle failure.

import Foundation

/// Root view model driving top-level routing, the connection health check, and
/// Auth_Error recovery.
@MainActor
@Observable
final class AppModel {
    /// Top-level navigation destinations.
    enum Route: Equatable {
        /// The Setup_Screen (initial config, config change, or Auth_Error re-entry).
        case setup
        /// The main control screen (blinds, lamps, speakers).
        case control
    }

    /// The outcome of a Setup_Screen submission.
    ///
    /// `.success` means the Pairing_Code was redeemed and the returned API_Key
    /// stored; `.failure` carries the specific `SetupError` and guarantees the
    /// stored key was left unchanged (Req 12.3, Property 17/21).
    enum SetupResult: Equatable {
        case success
        case failure(SetupError)
    }

    // MARK: - Observable state

    /// Current top-level route. Starts at `.setup`; `onLaunch()` decides the real
    /// destination.
    var route: Route = .setup

    /// Backend reachability, driven by `runHealthCheck()` (Req 3).
    var healthState: HealthState = .checking

    /// German Auth_Error banner shown after an HTTP 401 (Req 2.3). `nil` when no
    /// auth error is active.
    var authErrorMessage: String?

    /// Base_URL pre-fill value for the Setup_Screen. Mirrors the persisted
    /// Base_URL and is refreshed by `openConfig()` (Req 1.10). Exposed for the
    /// view to bind its Base_URL input.
    var baseURLField: String

    // MARK: - Dependencies

    let api: APIClient
    let keychain: KeychainStore
    let settings: SettingsStore
    /// Drives the Complication's Foreground_Refresh and immediate reloads
    /// (Req 6.4, 6.5, 7.11, 7.12). `nil` in tests that do not exercise the
    /// Complication.
    private let publisher: ComplicationPublisher?

    init(
        api: APIClient,
        keychain: KeychainStore,
        settings: SettingsStore,
        publisher: ComplicationPublisher? = nil
    ) {
        self.api = api
        self.keychain = keychain
        self.settings = settings
        self.publisher = publisher
        self.baseURLField = settings.baseURL.absoluteString
    }

    // MARK: - Complication refresh (Req 7.11, 7.12)

    /// Reports the TV_Lampe's current power from a Poll_Cycle fetch, driving a
    /// throttled Foreground_Refresh (Req 7.12, 7.13).
    private func notifyComplication(ofFetchedLamps lamps: [LampDTO]) {
        publisher?.publish(tvLampPower: TVLampSelector.select(from: lamps).power)
    }

    /// Reports a lamp command's returned state so an in-app TV-Lampe toggle
    /// reaches the Complication without waiting for the next Poll_Cycle
    /// (Req 7.11, 7.12).
    func notifyLampUpdated(_ lamp: LampDTO) {
        guard lamp.displayName.range(of: TVLampSelector.nameNeedle, options: .caseInsensitive) != nil else {
            return
        }
        publisher?.publish(tvLampPower: lamp.state.power)
    }

    // MARK: - Launch (Req 1.1 / 1.9 / 3)

    /// Decides the initial route on launch: with no stored API_Key, show the
    /// Setup_Screen (Req 1.1); otherwise verify Backend reachability and, when
    /// reachable, enter the control screen (Req 1.9 / Req 3).
    func onLaunch() async {
        baseURLField = settings.baseURL.absoluteString

        guard keychain.readAPIKey() != nil else {
            route = .setup
            return
        }

        await runHealthCheck()
    }

    // MARK: - Setup submission (Req 1.5–1.8, 2.5, 12)

    /// Validates the submitted Base_URL + Pairing_Code, redeems the code for a
    /// long-lived API_Key, and stores that key in the Keychain.
    ///
    /// Order and rules (design › Pairing setup):
    /// - The Pairing_Code is trimmed of surrounding whitespace and must be
    ///   exactly 6 decimal digits (0–9). Anything else is rejected with
    ///   `.malformedCode` WITHOUT issuing a redeem request and WITHOUT mutating
    ///   the stored key (Req 1.5/12.3, Property 17).
    /// - The Base_URL is validated via `URLValidator`; a non-http(s) or malformed
    ///   address is rejected with `.invalidURL` (Req 1.8) before anything is
    ///   persisted or redeemed.
    /// - The Base_URL is then persisted (Req 1.6) — the redeem request is built
    ///   from `settings.baseURL`, which `LiveAPIClient` reads fresh per request.
    /// - The code is redeemed with a 10s deadline (Req 12.1). On success the
    ///   returned key is stored ONLY in the Keychain (Req 12.2/2.5/12.7), the auth
    ///   banner is cleared, and the app routes to the control screen while a fresh
    ///   health check runs.
    ///
    /// Redeem failures map to `SetupError` WITHOUT touching the stored key
    /// (Req 12.3–12.6, Property 21): HTTP 400 -> `.malformedCode`, 401 ->
    /// `.codeInvalid`, 429 -> `.tooManyAttempts`, timeout -> `.redeemTimeout`,
    /// anything else -> `.redeemFailed`. The submitted code is never persisted
    /// (Req 12.7).
    ///
    /// - Returns: `.success`, or `.failure` carrying the specific `SetupError`.
    @discardableResult
    func submitSetup(baseURL: String, code: String) async -> SetupResult {
        // 1. Pairing_Code: must be exactly 6 decimal digits. Reject without any
        //    redeem request and without mutating stored state (Req 1.5/12.3,
        //    Property 17).
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6,
              trimmedCode.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return .failure(.malformedCode)
        }

        // 2. Base_URL: must be a syntactically valid absolute http(s) URL (Req 1.8).
        //    Validated before persisting or redeeming anything.
        let url: URL
        switch URLValidator.validate(baseURL) {
        case .success(let validated):
            url = validated
        case .failure:
            return .failure(.invalidURL)
        }

        // 3. Persist Base_URL (Req 1.6) so the redeem request can be built from it.
        settings.setBaseURL(url)
        baseURLField = url.absoluteString

        // 4. Redeem the Pairing_Code for a long-lived API_Key (Req 12.1). On any
        //    failure the stored key is left untouched (Property 21).
        let returnedKey: String
        do {
            returnedKey = try await api.redeemPairingCode(trimmedCode, timeout: .seconds(10))
        } catch {
            return .failure(mapRedeemError(error))
        }

        // 5. Success: store the returned key ONLY in the Keychain (Req 12.2/2.5/12.7).
        do {
            try keychain.saveAPIKey(returnedKey)
        } catch {
            // A backing-store failure leaves the previous key in place; surface it
            // as a generic redeem failure so the user retries.
            return .failure(.redeemFailed)
        }

        authErrorMessage = nil
        route = .control
        publisher?.publishImmediately()

        // Verify reachability now that a Base_URL + key are configured (Req 3).
        await runHealthCheck()

        return .success
    }

    /// Maps a redeem error thrown by `api.redeemPairingCode` to the matching
    /// `SetupError` (Req 12.3–12.6). Callers must not mutate the stored key.
    private func mapRedeemError(_ error: Error) -> SetupError {
        switch error {
        case APIError.http(status: 400):
            return .malformedCode
        case APIError.unauthorized:
            return .codeInvalid
        case APIError.http(status: 429):
            return .tooManyAttempts
        case APIError.timeout:
            return .redeemTimeout
        default:
            return .redeemFailed
        }
    }

    // MARK: - Config affordance (Req 1.10)

    /// Presents the Setup_Screen for a Base_URL/API_Key change, pre-filling the
    /// current Base_URL (Req 1.10).
    func openConfig() {
        baseURLField = settings.baseURL.absoluteString
        route = .setup
    }

    // MARK: - Complication deep link (Req 6.2, 6.3)

    /// Routes to the Setup_Screen when the Complication opens the Watch_App via
    /// the Setup_Deep_Link — while Unpaired or after an Auth_Error. Unconditional:
    /// it presents Setup regardless of the current route, including from Setup
    /// itself, so the user always lands on the Pairing_Code input (Req 6.3).
    func openSetupFromComplication() {
        authErrorMessage = nil
        baseURLField = settings.baseURL.absoluteString
        route = .setup
    }

    /// Whether the Setup_Screen can be dismissed back to the control screen.
    ///
    /// Cancelling only makes sense once a credential has been paired: on the
    /// very first launch (no stored API_Key) there is no configured control
    /// screen to return to, so the Setup_Screen must stay put. When a key is
    /// present the screen is a config change / re-pair surface (Req 1.10, 2.4)
    /// and the user may back out without changing anything.
    var canCancelSetup: Bool {
        keychain.readAPIKey() != nil
    }

    /// Dismisses the Setup_Screen without changing any stored state and returns
    /// to the control screen. Clears a pending Auth_Error banner so it does not
    /// linger after the user backs out. A no-op when no credential is stored
    /// (there is nothing to return to); callers gate on `canCancelSetup`.
    func cancelSetup() {
        guard canCancelSetup else { return }
        authErrorMessage = nil
        route = .control
    }

    // MARK: - Auth error (Req 2.3 / 2.4)

    /// Handles an Auth_Error (HTTP 401): shows the German "API-Key ungültig"
    /// banner and routes to the Setup_Screen for re-entry, WITHOUT deleting or
    /// otherwise mutating the stored API_Key (Req 2.3/2.4, Property 18).
    func handleAuthError() {
        authErrorMessage = Strings.pairingInvalid
        baseURLField = settings.baseURL.absoluteString
        route = .setup
        publisher?.publishImmediately()
    }

    // MARK: - Health check (Req 3)

    /// Sends `GET /health` (5s deadline, no `X-API-Key`) and maps the outcome to
    /// `healthState` (Req 3.1). HTTP 200 marks the Backend reachable and routes to
    /// the control screen (Req 3.2); a non-200, timeout, or network error marks it
    /// unreachable with a German message and leaves the route unchanged so the user
    /// can retry (Req 3.3/3.4).
    func runHealthCheck() async {
        healthState = .checking
        do {
            let ok = try await api.checkHealth(timeout: .seconds(5))
            if ok {
                healthState = .reachable
                route = .control
            } else {
                healthState = .unreachable(Strings.backendUnreachable)
            }
        } catch {
            healthState = .unreachable(Strings.backendUnreachable)
        }
    }

    // MARK: - Poll driver (Req 9)

    /// The in-flight poll loop, or `nil` when polling is stopped. Retained so
    /// `stopPolling()` can cancel it and guarantee no further Poll_Cycle starts
    /// (Req 9.6). A `Task<Void, Never>` because the loop itself never throws —
    /// per-cycle failures are absorbed so a single bad fetch never tears down
    /// the loop (Req 9.4/9.5).
    private var pollTask: Task<Void, Never>?

    /// Starts the periodic Lamp/Speaker refresh while the control view is active
    /// (Req 9.1). Idempotent: if a loop is already running this is a no-op, so a
    /// repeated `.active` scenePhase transition never spawns a second loop.
    ///
    /// Each Poll_Cycle concurrently fetches lamps and speakers with a 10s
    /// deadline and hands each result to the matching view model's `applyPoll`,
    /// which preserves pending rows (Req 9.2/9.3). Lamp and speaker fetches are
    /// handled independently: a failure of one (timeout, non-2xx, or network
    /// error) neither blocks nor discards the other, the displayed state is
    /// retained, and the loop proceeds to the next cycle (Req 9.4/9.5). An HTTP
    /// 401 surfacing during a poll routes to the Setup_Screen via
    /// `handleAuthError()` and stops polling.
    ///
    /// The loop sleeps 5s between cycles and checks `Task.isCancelled` at the
    /// cycle boundaries so `stopPolling()` takes effect promptly (Req 9.6).
    func startPolling(lamps: LampViewModel, speakers: SpeakerViewModel) {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // Fetch lamps and speakers concurrently, each with its own 10s
                // deadline. Handled independently so one failure can't block or
                // cancel the other (Req 9.4/9.5).
                async let lampResult = self.pollFetchLamps()
                async let speakerResult = self.pollFetchSpeakers()
                let (lampOutcome, speakerOutcome) = await (lampResult, speakerResult)

                if Task.isCancelled { return }

                // A 401 on either fetch means the credential is no longer valid:
                // route to Setup and stop polling (do not keep hammering).
                if case .failure(APIError.unauthorized) = lampOutcome {
                    self.handleAuthError()
                    self.stopPolling()
                    return
                }
                if case .failure(APIError.unauthorized) = speakerOutcome {
                    self.handleAuthError()
                    self.stopPolling()
                    return
                }

                // Apply successful results on the main actor; retain state on
                // failure (Req 9.4/9.5). `AppModel` is @MainActor, so these calls
                // are already main-actor isolated.
                if case .success(let fetchedLamps) = lampOutcome {
                    lamps.applyPoll(fetchedLamps)
                    self.notifyComplication(ofFetchedLamps: fetchedLamps)
                }
                if case .success(let fetchedSpeakers) = speakerOutcome {
                    speakers.applyPoll(fetchedSpeakers)
                }

                // Cadence: wait 5s before the next Poll_Cycle (Req 9.1). A
                // cancellation during the sleep throws, ending the loop cleanly.
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }
    }

    /// Stops the poll driver: cancels the in-flight loop and clears the handle so
    /// no further Poll_Cycle is initiated (Req 9.6). Idempotent.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One lamp Poll_Cycle fetch (10s deadline), captured as a `Result` so the
    /// caller can apply or discard it without letting a throw abort the sibling
    /// speaker fetch (Req 9.4/9.5).
    private func pollFetchLamps() async -> Result<[LampDTO], Error> {
        do {
            return .success(try await api.fetchLamps(timeout: .seconds(10)))
        } catch {
            return .failure(error)
        }
    }

    /// One speaker Poll_Cycle fetch (10s deadline), captured as a `Result` for the
    /// same reason as `pollFetchLamps()`.
    private func pollFetchSpeakers() async -> Result<[SpeakerDTO], Error> {
        do {
            return .success(try await api.fetchSpeakers(timeout: .seconds(10)))
        } catch {
            return .failure(error)
        }
    }
}
