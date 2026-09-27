// Complication/ComplicationRefreshing.swift — the Timeline_Reload seam.
//
// Abstracts `WidgetCenter.shared.reloadTimelines(ofKind:)` behind a protocol so
// `ComplicationPublisher`, `TVLampToggleService`, and their tests never touch
// WidgetKit directly (Req 10.6).

import WidgetKit

protocol ComplicationRefreshing: Sendable {
    /// Requests a Timeline_Reload for the TV-Lampe complication.
    func reload()
}

/// Live `ComplicationRefreshing` backed by `WidgetCenter`.
struct LiveComplicationRefresher: ComplicationRefreshing {
    func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: ComplicationKind.tvLamp)
    }
}

/// Test double counting `reload()` calls without touching WidgetKit.
final class SpyComplicationRefresher: ComplicationRefreshing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var reloadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func reload() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }
}
