// Complication/ComplicationTiming.swift — shared timing and identity constants.
//
// One place for every deadline and identifier the Complication uses, so the
// Provider_Timeout, Command_Timeout, and Refresh_Interval values from the
// requirements are never duplicated as inline literals (Req 3.10, 8.8).

import Foundation

enum ComplicationTiming {
    /// Deadline for a Backend request issued from the `TimelineProvider` (Req 8.8).
    static let providerTimeout: Duration = .seconds(5)
    /// Deadline for each Backend request issued from the Toggle_Intent (Req 8.8).
    static let commandTimeout: Duration = .seconds(10)
    /// Target interval between Timeline_Reloads (Req 3.10, 3.14).
    static let refreshInterval: Duration = .seconds(10)
}

enum ComplicationKind {
    /// The WidgetKit `kind` identifier for the TV-Lampe complication.
    static let tvLamp = "TVLampComplication"
}

extension Duration {
    /// This `Duration` expressed as seconds, for comparisons against `Date`
    /// intervals (e.g. the publisher's throttle window).
    var timeIntervalValue: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
