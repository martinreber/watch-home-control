// Models/Rows.swift — UI-only row wrappers around the Codable DTOs.
//
// These add view-facing state (optimistic displayed value + a per-row pending
// flag) without polluting the wire DTOs. Both are `Identifiable` (keyed by the
// underlying device id) and `Equatable` so SwiftUI lists can diff efficiently
// (Req 6.3, 6.4, 8.4, 9.2, 9.3).

import Foundation

/// A lamp as shown in the UI: the decoded DTO plus the optimistically displayed
/// power state and a pending flag while a command is in flight.
struct LampRow: Identifiable, Equatable {
    let dto: LampDTO
    /// Optimistic value shown in the toggle; updated on command success or
    /// reverted on failure.
    var displayedPower: Bool
    /// True while a toggle command for this row is in flight (Req 6.3).
    var isPending: Bool
    var id: String { dto.id }
}

/// A speaker as shown in the UI: the decoded DTO plus the optimistically
/// displayed playback state and a pending flag while a command is in flight.
struct SpeakerRow: Identifiable, Equatable {
    let dto: SpeakerDTO
    /// Optimistic playback state shown in the toggle; updated on command
    /// success or reverted on failure.
    var displayedState: SpeakerState
    /// True while a toggle command for this row is in flight (Req 8.4).
    var isPending: Bool
    var id: String { dto.id }
}
