// Complication/ComplicationPublisher.swift — throttled Foreground_Refresh.
//
// Drives Timeline_Reload from the running Watch_App: `publish(tvLampPower:)` is
// called from the Poll_Cycle (and after a successful lamp command) with the
// TV-Lampe's current power. It reloads only when that power differs from what
// was last published, and at most once per `refreshInterval`, so the poll loop
// never spends more of the system's background-refresh budget than necessary
// (Req 3.14, 7.12, 7.13). `publishImmediately()` bypasses both checks for
// pairing/credential/Base_URL changes, which must reach the face at once
// (Req 7.11, 6.4, 6.5).

import Foundation

@MainActor
final class ComplicationPublisher {
    private let refresher: ComplicationRefreshing
    private let minimumInterval: Duration
    private let now: () -> Date

    /// `false` until the first `publish`/`publishImmediately` call: the very
    /// first observation always reaches the face.
    private var hasPublishedBefore = false
    /// The TV-Lampe power the Complication currently reflects, or `nil` when it
    /// was last published as unresolved/unknown. Not `private` so
    /// `@testable import` can assert the throttle's settled state (Property 7).
    private(set) var lastPublishedPower: Bool?
    private var lastReloadDate: Date?

    init(
        refresher: ComplicationRefreshing,
        minimumInterval: Duration = ComplicationTiming.refreshInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.refresher = refresher
        self.minimumInterval = minimumInterval
        self.now = now
    }

    /// Reports the TV-Lampe's current power from a Poll_Cycle or a lamp
    /// command. Reloads only on a change from the last published value, and at
    /// most once per `minimumInterval`; a change observed too soon after the
    /// last reload is re-evaluated (and flushed) on a later call once the
    /// interval has elapsed (Req 7.12, 7.13).
    func publish(tvLampPower: Bool?) {
        guard hasPublishedBefore else {
            reload(with: tvLampPower)
            return
        }

        guard tvLampPower != lastPublishedPower else {
            return
        }

        if let lastReloadDate, now().timeIntervalSince(lastReloadDate) < minimumInterval.timeIntervalValue {
            return
        }

        reload(with: tvLampPower)
    }

    /// Bypasses the change check and the throttle: pairing, credential
    /// deletion, and Base_URL changes must reach the face immediately.
    func publishImmediately() {
        reload(with: nil)
    }

    private func reload(with power: Bool?) {
        hasPublishedBefore = true
        lastPublishedPower = power
        lastReloadDate = now()
        refresher.reload()
    }
}
