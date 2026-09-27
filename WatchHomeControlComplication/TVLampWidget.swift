// TVLampWidget.swift + widget bundle — the Complication's WidgetKit declaration.
//
// `accessoryCircular` is the only supported family (Req 1.2); the display name
// and description come from the shared `Strings` (Req 1.7, 9.2).

import WidgetKit
import SwiftUI

struct TVLampWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationKind.tvLamp, provider: TVLampTimelineProvider()) { _ in
            TVLampComplicationView()
        }
        .configurationDisplayName(Strings.complicationDisplayName)
        .description(Strings.complicationDescription)
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct WatchHomeControlComplicationBundle: WidgetBundle {
    var body: some Widget {
        TVLampWidget()
    }
}
