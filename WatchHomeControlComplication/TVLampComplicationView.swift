// TVLampComplicationView.swift — renders one `TVLampEntry`.
//
// Always shows the label "TV" (Req 1.3, 2.6, 9.3); colour is the only signal of
// Complication_State, applied only in the `fullColor` rendering mode so other
// modes still render without failing (Req 1.4, 1.5, 2.5). `.toggle` wraps the
// label in a `Button(intent:)` that runs the Toggle_Intent in the background;
// `.openSetup` instead applies the Setup_Deep_Link via `widgetURL` (Req 5.1,
// 5.11, 6.2).

import SwiftUI
import WidgetKit

struct TVLampComplicationView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: TVLampEntry

    var body: some View {
        Group {
            switch entry.interaction {
            case .toggle:
                Button(intent: ToggleTVLampIntent()) { label }
                    .buttonStyle(.plain)
            case .openSetup:
                label
                    .widgetURL(DeepLink.setupURL)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var label: some View {
        Text(Strings.complicationLabel)
            .foregroundStyle(renderingMode == .fullColor ? entry.state.labelColor : .primary)
    }
}
