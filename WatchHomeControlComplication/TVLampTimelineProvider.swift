// TVLampTimelineProvider.swift — a static timeline for the TV-Lampe launcher.
//
// The launcher has no dynamic data, so every provider callback returns the
// same no-network entry and the timeline never requests background reloads.
// `TimelineProviderContext` has no public initializer, so this type itself is
// verified by the extension target's build.

import WidgetKit

struct TVLampTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TVLampEntry {
        entry()
    }

    func getSnapshot(in context: Context, completion: @escaping (TVLampEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TVLampEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> TVLampEntry {
        TVLampEntry(date: .now)
    }
}
