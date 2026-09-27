// TVLampTimelineProvider.swift — the WidgetKit shell over `TVLampEntryLoader`.
//
// Holds no logic of its own: `placeholder`/`getSnapshot` return the loader's
// no-I/O representative entry (Req 3.2), and `getTimeline` returns exactly one
// entry dated now with a Background_Refresh reload policy `.after(now +
// refreshInterval)`, never pre-computing future entries (Req 3.10, 3.11, 3.12).
// `TimelineProviderContext` has no public initializer, so this type itself is
// not unit-tested — `TVLampEntryLoader` is (design › Testing Strategy).

import WidgetKit

struct TVLampTimelineProvider: TimelineProvider {
    private let loader = TVLampEntryLoader(env: .live)

    func placeholder(in context: Context) -> TVLampEntry {
        loader.placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (TVLampEntry) -> Void) {
        completion(loader.placeholder())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TVLampEntry>) -> Void) {
        // `completion` is not `Sendable`; opt out of the cross-isolation
        // "sending" check for this single-use bridge into the `Task` below —
        // it is called exactly once and never touched again afterward.
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await loader.load()
            let nextRequest = entry.date.addingTimeInterval(ComplicationTiming.refreshInterval.timeIntervalValue)
            completion(Timeline(entries: [entry], policy: .after(nextRequest)))
        }
    }
}
