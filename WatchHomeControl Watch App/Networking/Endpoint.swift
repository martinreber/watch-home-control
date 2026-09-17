// Networking/Endpoint.swift — enumerates every Backend operation the app performs.
//
// `Endpoint` is a pure description of a Backend call (path, method, body). It
// carries no I/O; `RequestBuilder` (Task 3.2) turns an endpoint plus the
// configured Base_URL and API key into a concrete `URLRequest`. Keeping the
// endpoint set as a single enum makes request building total and exhaustively
// testable (Property 1/2).

import Foundation

/// A Backend operation the app can invoke.
///
/// - `health`: `GET /health` — the only unauthenticated endpoint (Req 3.1).
/// - `blind`: `POST /blind` with a `{ "action": ... }` body (Req 4.2/4.3).
/// - `lamps`: `GET /lamps` (Req 6.1).
/// - `lampState`: `POST /lamps/{id}/state` with a `{ "power": ... }` body (Req 6.2).
/// - `speakers`: `GET /sonos/speakers` (Req 8.1).
/// - `speakerPlay`: `POST /sonos/speakers/{id}/play` (Req 8.2).
/// - `speakerPause`: `POST /sonos/speakers/{id}/pause` (Req 8.3).
/// - `speakerRadio`: `POST /sonos/speakers/{id}/radio` with a `RadioRequest` body (Req 8.1).
/// - `redeem`: `POST /pairing/redeem` with a `{ "code": ... }` body — unauthenticated,
///   like `.health`, it carries no `X-API-Key` header (Req 12.1).
enum Endpoint {
    case health
    case blind(BlindAction)
    case lamps
    case lampState(id: String, power: Bool)
    case speakers
    case speakerPlay(id: String)
    case speakerPause(id: String)
    case speakerRadio(id: String, RadioRequest)
    case redeem(code: String)
}
