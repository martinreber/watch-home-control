// Complication/TVLampSelector.swift — pure TV_Lampe selection.
//
// Selects the TV_Lampe from a lamp list by name, matching the case-insensitive
// substring "TV-Lampe" against each lamp's `displayName` (`friendly_name`
// falling back to `id`). Pure: no I/O, deterministic (Req 4.1–4.5, 10.1).

import Foundation

/// The outcome of resolving the TV_Lampe from a lamp list.
enum TVLampResolution: Equatable {
    case resolved(LampDTO)
    case unresolved

    /// The resolved lamp's power, or `nil` when unresolved. Convenience for
    /// callers that only need the power value (e.g. the publisher).
    var power: Bool? {
        if case .resolved(let lamp) = self { return lamp.state.power }
        return nil
    }
}

enum TVLampSelector {
    /// The substring a lamp's `displayName` must contain, case-insensitively,
    /// to be selected as the TV_Lampe (Req 4.1).
    static let nameNeedle = "TV-Lampe"

    /// Selects the first lamp in `lamps` whose `displayName` contains
    /// `nameNeedle` case-insensitively (Req 4.1–4.5). Returns `.unresolved` for
    /// an empty list or when no lamp matches.
    static func select(from lamps: [LampDTO]) -> TVLampResolution {
        for lamp in lamps where lamp.displayName.range(of: nameNeedle, options: .caseInsensitive) != nil {
            return .resolved(lamp)
        }
        return .unresolved
    }
}
