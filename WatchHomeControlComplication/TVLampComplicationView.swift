// TVLampComplicationView.swift — renders the static launcher affordance.
//
// Always shows a neutral TV-Lampe shortcut; it does not fetch or display lamp
// state, and a tap opens the app at the lamp controls.

import SwiftUI
import WidgetKit

struct TVLampComplicationView: View {
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "lightbulb.fill")
                .font(.caption2)
            Text(Strings.complicationLabel)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .widgetURL(DeepLink.lampsURL)
        .containerBackground(.clear, for: .widget)
    }
}
