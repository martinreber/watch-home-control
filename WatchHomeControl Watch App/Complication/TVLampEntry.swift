// Complication/TVLampEntry.swift — the Complication's WidgetKit timeline entry.
//
// Static timeline entry for the TV-Lampe launcher; it intentionally carries no
// lamp state because the complication is a shortcut, not a status display.

import WidgetKit
import Foundation

struct TVLampEntry: TimelineEntry, Equatable {
    let date: Date
}
