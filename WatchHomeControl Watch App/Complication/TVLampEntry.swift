// Complication/TVLampEntry.swift — the Complication's WidgetKit timeline entry.
//
// Carries the resolved Complication_State plus which tap behaviour the view
// should offer: `.toggle` (invoke the Toggle_Intent) while Paired, or
// `.openSetup` (open the Setup_Deep_Link) while Unpaired (Req 3.3, 5.1, 5.11).

import WidgetKit
import Foundation

struct TVLampEntry: TimelineEntry, Equatable {
    let date: Date
    let state: ComplicationState
    let interaction: Interaction

    enum Interaction: Equatable {
        case toggle
        case openSetup
    }
}
