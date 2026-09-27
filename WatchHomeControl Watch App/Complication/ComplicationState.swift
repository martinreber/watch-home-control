// Complication/ComplicationState.swift — pure Complication_State mapping.
//
// Maps a TV_Lampe selection result plus the pairing condition to exactly one
// display state. Total and pure: no I/O, deterministic for identical input
// (Req 2.1–2.4, 10.2, 10.3).

import SwiftUI

/// Whether an API_Key is currently readable from the Shared_Keychain_Group.
enum PairingCondition: Equatable {
    case paired
    case unpaired
}

/// The Complication's display state — exactly one of on, off, unknown.
enum ComplicationState: String, Equatable, Codable {
    case on
    case off
    case unknown

    /// Total function: every (pairing, resolution) pair yields exactly one of
    /// `.on`, `.off`, `.unknown` (Req 2.1–2.4, 10.2, 10.3).
    ///
    /// - Unpaired always yields `.unknown`, regardless of `resolution`.
    /// - Paired + resolved maps the lamp's power straight through.
    /// - Paired + unresolved yields `.unknown`.
    static func resolve(pairing: PairingCondition, resolution: TVLampResolution) -> ComplicationState {
        guard pairing == .paired else { return .unknown }

        switch resolution {
        case .resolved(let lamp):
            return lamp.state.power ? .on : .off
        case .unresolved:
            return .unknown
        }
    }

    /// The label colour for this state (Req 2.1, 2.2, 2.3, 2.5): green when on,
    /// red when off, grey when unknown. Pairwise distinct.
    var labelColor: Color {
        switch self {
        case .on: return .green
        case .off: return .red
        case .unknown: return .gray
        }
    }
}
