// Networking/APIClient.swift — the seam between view models and the Backend.
//
// The `APIClient` protocol declares every Backend operation the app performs.
// Views and view models depend on this protocol; `LiveAPIClient` (Task 8.2)
// implements it over `URLSession`, and tests inject a mock. Each call takes a
// per-request `timeout` so callers pass the requirement-mandated deadline
// (`.seconds(5)` for `/health` and lamp-state commands; `.seconds(10)` for
// blind, speaker, list, and poll requests).

import Foundation

protocol APIClient: Sendable {
    /// GET /health — no `X-API-Key`. Returns true iff HTTP 200 within `timeout`
    /// (Req 3.1).
    func checkHealth(timeout: Duration) async throws -> Bool

    /// POST /blind {"action": ...} (Req 4.1).
    func moveBlind(_ action: BlindAction, timeout: Duration) async throws

    /// GET /lamps — decodes both response shapes into `[LampDTO]` (Req 5.1).
    func fetchLamps(timeout: Duration) async throws -> [LampDTO]

    /// POST /lamps/{id}/state {"power": ...} -> { "lamp": {...} } (Req 6.1).
    func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO

    /// GET /sonos/speakers -> [SpeakerDTO] (Req 7.1).
    func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO]

    /// POST /sonos/speakers/{id}/play -> updated speaker (Req 8.1).
    func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO

    /// POST /sonos/speakers/{id}/pause -> updated speaker (Req 8.1).
    func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO

    /// POST /sonos/speakers/{id}/radio {uri,metadata,name} -> updated speaker
    /// (Req 8.1).
    func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO

    /// POST /pairing/redeem {"code": ...} — no `X-API-Key`. Returns the decoded
    /// long-lived `api_key` on success (Req 12.1/12.2). Non-2xx status and
    /// transport failures map to the normalized `APIError` (e.g. 401 ->
    /// `.unauthorized`, other non-2xx -> `.http(status:)`, timeout -> `.timeout`);
    /// `AppModel.submitSetup` translates those into `SetupError` (Req 12.3–12.6).
    func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String
}
