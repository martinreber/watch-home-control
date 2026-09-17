// Models/SpeakerCommand.swift — Pure speaker toggle-to-endpoint mapping.
//
// Centralizes the speaker command decision (Req 8.1–8.3) in a total function so
// it can be tested exhaustively without a device or Backend. `RadioRequest` and
// `SpeakerState` are defined in Models/DTOs.swift.

import Foundation

/// The command a speaker toggle resolves to.
enum SpeakerCommand: Equatable {
    case play
    case pause
    case radio(RadioRequest)
}

enum SpeakerToggleMapper {
    /// on == desired toggle position; current == speaker's current state.
    static func command(toggleOn on: Bool, current state: SpeakerState) -> SpeakerCommand {
        if on {
            return state == .stopped ? .radio(.radioBern1) : .play   // Req 8.1 / 8.2
        } else {
            return .pause                                            // Req 8.3
        }
    }
}
