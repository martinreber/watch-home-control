// Networking/LiveAPIClient.swift — the URLSession-backed APIClient implementation.
//
// `LiveAPIClient` is the single place all Backend I/O happens. It composes the
// pure `RequestBuilder` (endpoint -> URLRequest) with a `URLSession` and funnels
// every failure into the normalized `APIError` enum (Req 3.3/3.4/4.7/5.7/6.6/7.2/
// 8.6/11.4/11.5). Views and view models depend on the `APIClient` protocol, never
// on this type directly.
//
// Credentials are read fresh per request via an injected credential provider
// closure (backed by the Keychain), so a re-entered API_Key takes effect on the
// next call without reconstructing the client (Req 2.1). The Base_URL is likewise
// read fresh from the injected `SettingsStore` so a config change applies to the
// next request.
//
// Timeouts (Req 11.4): the caller-supplied `timeout: Duration` is applied both as
// `URLRequest.timeoutIntervalForRequest` AND enforced by a structured
// `Task`-cancellation guard, so a hung request is cancelled at the deadline.
// `URLError.timedOut` and cancellation both map to `APIError.timeout`.

import Foundation

/// `URLSession`-backed implementation of `APIClient`.
///
/// Immutable and `Sendable`: it holds a `URLSession`, a `SettingsStore` (read for
/// the current Base_URL per request), and a `@Sendable` credential provider that
/// returns the current API_Key from the Keychain.
final class LiveAPIClient: APIClient, Sendable {
    private let session: URLSession
    private let settings: SettingsStore
    private let apiKeyProvider: @Sendable () -> String?

    /// - Parameters:
    ///   - session: The `URLSession` used for all requests. Defaults to `.shared`.
    ///   - settings: Source of the current Base_URL, read fresh per request.
    ///   - apiKeyProvider: Returns the current API_Key (typically reading the
    ///     Keychain). Called fresh per request so a re-entered key takes effect
    ///     immediately; not called for `checkHealth`.
    init(
        session: URLSession = .shared,
        settings: SettingsStore,
        apiKeyProvider: @escaping @Sendable () -> String?
    ) {
        self.session = session
        self.settings = settings
        self.apiKeyProvider = apiKeyProvider
    }

    /// Convenience initializer wiring the credential provider to a `KeychainStore`.
    convenience init(
        session: URLSession = .shared,
        settings: SettingsStore,
        keychain: KeychainStore
    ) {
        self.init(session: session, settings: settings, apiKeyProvider: { keychain.readAPIKey() })
    }

    // MARK: - APIClient

    func checkHealth(timeout: Duration) async throws -> Bool {
        // The only unauthenticated endpoint: no API_Key attached (Req 3.1). A
        // non-200, timeout, or transport failure means "unreachable" — surfaced
        // here as a thrown error / false rather than a crash (Req 3.3/3.4).
        let (_, response) = try await perform(.health, timeout: timeout, authenticated: false)
        return response.statusCode == 200
    }

    func moveBlind(_ action: BlindAction, timeout: Duration) async throws {
        _ = try await performExpectingSuccess(.blind(action), timeout: timeout)
    }

    func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
        let data = try await performExpectingSuccess(.lamps, timeout: timeout)
        return try decode(LampsResponse.self, from: data).lamps
    }

    func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
        let data = try await performExpectingSuccess(.lampState(id: id, power: power), timeout: timeout)
        return try decode(LampCommandResponse.self, from: data).lamp
    }

    func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] {
        let data = try await performExpectingSuccess(.speakers, timeout: timeout)
        return try decode([SpeakerDTO].self, from: data)
    }

    func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
        let data = try await performExpectingSuccess(.speakerPlay(id: id), timeout: timeout)
        return try decode(SpeakerDTO.self, from: data)
    }

    func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
        let data = try await performExpectingSuccess(.speakerPause(id: id), timeout: timeout)
        return try decode(SpeakerDTO.self, from: data)
    }

    func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
        let data = try await performExpectingSuccess(.speakerRadio(id: id, request), timeout: timeout)
        return try decode(SpeakerDTO.self, from: data)
    }

    func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
        // Unauthenticated like `checkHealth`: no API_Key attached (Req 12.1). We
        // enforce the status code ourselves so 400/401/429 stay distinguishable
        // in the `APIError` the caller inspects — `AppModel.submitSetup` maps
        // .http(status: 400) -> malformedCode, .unauthorized -> codeInvalid,
        // .http(status: 429) -> tooManyAttempts, .timeout -> redeemTimeout, else
        // redeemFailed (Req 12.3–12.6).
        let (data, response) = try await perform(.redeem(code: code), timeout: timeout, authenticated: false)
        switch response.statusCode {
        case 200...299:
            return try decode(PairingCodeResponse.self, from: data).apiKey
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.http(status: response.statusCode)
        }
    }

    // MARK: - Request execution

    /// Builds and sends the request for `endpoint`, returning the raw body and the
    /// HTTP response without inspecting the status code (used by `checkHealth`,
    /// which maps status itself).
    ///
    /// - Parameter authenticated: When `false`, no API_Key is attached (health).
    private func perform(
        _ endpoint: Endpoint,
        timeout: Duration,
        authenticated: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try makeRequest(endpoint, timeout: timeout, authenticated: authenticated)

        do {
            // Structured cancellation guard: race the network call against a
            // sleep of `timeout`. Whichever finishes first wins; the group is
            // cancelled on scope exit so the loser is torn down. This backs up
            // `timeoutIntervalForRequest` so even a stalled session is bounded.
            let (data, response) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask { [session] in
                    try await session.data(for: request)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw APIError.timeout
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw APIError.timeout
                }
                return result
            }

            guard let http = response as? HTTPURLResponse else {
                // A non-HTTP response is not something the Backend contract
                // produces; treat it as a transport failure.
                throw APIError.network("Ungültige Antwort ohne HTTP-Status")
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw APIError.timeout
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    /// Sends the request and enforces a 2xx status, mapping 401 and other non-2xx
    /// codes to `APIError`. Returns the body for the caller to decode.
    private func performExpectingSuccess(_ endpoint: Endpoint, timeout: Duration) async throws -> Data {
        let (data, response) = try await perform(endpoint, timeout: timeout, authenticated: true)
        switch response.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.http(status: response.statusCode)
        }
    }

    /// Builds the `URLRequest` for `endpoint`, attaching the freshly read API_Key
    /// (unless `authenticated == false`) and applying the per-call timeout to
    /// `timeoutIntervalForRequest`.
    private func makeRequest(
        _ endpoint: Endpoint,
        timeout: Duration,
        authenticated: Bool
    ) throws -> URLRequest {
        let builder = RequestBuilder(baseURL: settings.baseURL)
        let apiKey = authenticated ? apiKeyProvider() : nil
        var request = try builder.build(endpoint, apiKey: apiKey)
        request.timeoutInterval = timeout.timeoutInterval
        return request
    }

    /// Decodes `type` from `data`, mapping any `DecodingError` to
    /// `APIError.decoding` (Req 5.7/6.5/8.6).
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch is DecodingError {
            throw APIError.decoding
        }
    }

    /// Maps a `URLError` to the normalized `APIError`: `.timedOut`/`.cancelled` to
    /// `.timeout`, all other transport cases to `.network` (Req 11.4/11.5).
    private func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .timedOut, .cancelled:
            return .timeout
        default:
            return .network(error.localizedDescription)
        }
    }
}

private extension Duration {
    /// This `Duration` expressed as seconds for `URLRequest.timeoutInterval`.
    var timeoutInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
