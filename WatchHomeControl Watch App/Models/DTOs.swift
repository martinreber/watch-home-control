// Models/DTOs.swift — Codable DTOs and enums mirroring the Backend contract.
//
// Decoding is lenient where the requirements demand it: the lamp list decodes
// from both response shapes (Req 5.2/5.3), and `friendly_name` is optional with
// an id fallback (Req 5.4/5.5).

import Foundation

/// Blind movement direction sent in `POST /blind` (Req 4.2/4.3).
enum BlindAction: String, Codable {
    case up
    case down
}

/// A lamp's on/off state. Additional fields are tolerated and ignored via
/// default decoding.
struct LampState: Codable, Equatable {
    let power: Bool
}

/// A controllable lamp (Req 5.4/5.5).
struct LampDTO: Codable, Equatable, Identifiable {
    let id: String
    /// Maps the Backend's `friendly_name`; optional (Req 5.5).
    let friendlyName: String?
    /// "ceiling" | "floor" | "strip" | "desk".
    let type: String?
    let state: LampState

    enum CodingKeys: String, CodingKey {
        case id
        case friendlyName = "friendly_name"
        case type
        case state
    }

    /// Display label: `friendly_name` when present and non-empty, else `id`
    /// (Req 5.4/5.5).
    var displayName: String {
        if let friendlyName, !friendlyName.isEmpty {
            return friendlyName
        }
        return id
    }
}

/// Decodes BOTH the wrapped object `{ "lamps": [...] }` and a bare top-level
/// array `[...]` into a single lamp list (Req 5.2/5.3).
enum LampsResponse: Decodable {
    case wrapped(lamps: [LampDTO])
    case bare([LampDTO])

    private enum CodingKeys: String, CodingKey {
        case lamps
    }

    init(from decoder: Decoder) throws {
        // Prefer the bare array shape; fall back to the wrapped object.
        if let array = try? [LampDTO](from: decoder) {
            self = .bare(array)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lamps = try container.decode([LampDTO].self, forKey: .lamps)
        self = .wrapped(lamps: lamps)
    }

    var lamps: [LampDTO] {
        switch self {
        case .wrapped(let lamps), .bare(let lamps):
            return lamps
        }
    }
}

/// Response body of `POST /lamps/{id}/state` (Req 6.4).
struct LampCommandResponse: Codable, Equatable {
    let lamp: LampDTO
}

/// A Sonos speaker's playback state.
enum SpeakerState: String, Codable {
    case playing
    case paused
    case stopped
}

/// A Sonos speaker (Req 7.4/7.5/7.6/7.7).
struct SpeakerDTO: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let state: SpeakerState
    let online: Bool
    /// Maps the Backend's `model_name`.
    let modelName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case state
        case online
        case modelName = "model_name"
    }

    /// Toggle position: on if and only if the speaker is playing (Req 7.5/7.6).
    var isOn: Bool { state == .playing }
}

/// Body of `POST /sonos/speakers/{id}/radio` (Req 8.1).
struct RadioRequest: Codable, Equatable {
    let uri: String
    let metadata: String
    let name: String

    /// Default station "Radio Bern 1" used when turning on a stopped speaker
    /// (Req 8.1).
    static let radioBern1 = RadioRequest(
        uri: "x-rincon-mp3radio://stream.streambase.ch/radiobern1/mp3-192/direct/",
        metadata: "",
        name: "Radio Bern 1"
    )
}

/// Response body of `POST /pairing/redeem` on success (Req 12.2).
///
/// Maps the Backend's `api_key` to `apiKey`, matching the explicit-`CodingKeys`
/// convention used by the other DTOs in this file (e.g. `friendly_name`,
/// `model_name`).
struct PairingCodeResponse: Codable, Equatable {
    /// The long-lived API key returned when a pairing code is redeemed.
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
    }
}
