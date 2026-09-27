// State/LampViewModel.swift — lamp (Lampen) listing + control view model.
//
// Drives the "Lampen" section: an initial load of the lamp list, optimistic
// per-lamp toggles, and merge-on-poll that never clobbers a pending row.
//
// - `activate()` loads the list via `GET /lamps` (10s). On failure it retains
//   the current list and raises a non-blocking refresh-failed indicator
//   (Req 5.1/5.7).
// - `toggle(id:on:)` optimistically flips a single row, marks it pending, and
//   sends `POST /lamps/{id}/state` (5s). On success it applies exactly the
//   returned `lamp.state`; on error/timeout it reverts that row to its exact
//   prior value and shows German feedback (Req 6.1–6.6). Only the targeted
//   row's toggle is affected (Req 6.3).
// - `applyPoll(_:)` merges freshly polled lamps into the displayed list,
//   preserving any pending row's displayed value while adopting polled values
//   for non-pending rows (Req 9.2).

import Foundation

@MainActor
@Observable
final class LampViewModel {
    /// The lamps currently shown in the UI. Each row carries the optimistic
    /// displayed power plus a per-row pending flag.
    private(set) var lamps: [LampRow] = []

    /// Non-blocking indicator that the most recent load/poll failed. The list
    /// is retained unchanged when this is set (Req 5.7).
    var refreshFailed: Bool = false

    /// Non-blocking German feedback shown after a toggle command completes with
    /// an error or timeout. `nil` when no feedback is currently presented.
    var feedback: Feedback?

    private let api: APIClient
    init(api: APIClient) {
        self.api = api
    }

    /// Loads the lamp list via `GET /lamps` with a 10s deadline (Req 5.1).
    ///
    /// On success, rebuilds the displayed rows from the fetched DTOs
    /// (displayed power mirrors `state.power`, no row pending) and clears the
    /// refresh-failed indicator. On any failure the current list is retained
    /// unchanged and the refresh-failed indicator is set (Req 5.7).
    func activate() async {
        do {
            let fetched = try await api.fetchLamps(timeout: .seconds(10))
            lamps = fetched.map { dto in
                LampRow(dto: dto, displayedPower: dto.state.power, isPending: false)
            }
            refreshFailed = false
        } catch {
            // Retain the current list; surface a non-blocking hint (Req 5.7).
            refreshFailed = true
        }
    }

    /// Toggles a single lamp on or off via `POST /lamps/{id}/state` with a 5s
    /// deadline (Req 6.1/6.2).
    ///
    /// The targeted row is optimistically set to `on` and marked pending
    /// (Req 6.3). On success the row adopts exactly the returned `lamp.state`
    /// and clears pending (Req 6.4). On an error or timeout the row is reverted
    /// to the exact value it held before dispatch, pending is cleared, and
    /// German error/timeout feedback is shown (Req 6.5/6.6). Rows other than
    /// the targeted one are never touched (Req 6.3).
    func toggle(id: String, on: Bool) async {
        guard let index = lamps.firstIndex(where: { $0.id == id }) else { return }

        // Capture the exact prior row so a failure can restore it verbatim.
        let prior = lamps[index]

        // Optimistic update + pending (Req 6.3).
        lamps[index].displayedPower = on
        lamps[index].isPending = true
        feedback = nil

        do {
            let updated = try await api.setLampState(id: id, power: on, timeout: .seconds(5))
            // Apply exactly the returned device state (Req 6.4). Re-find the row
            // in case the list changed (e.g. a poll) while the command was in
            // flight; if it's gone, there is nothing to update.
            if let current = lamps.firstIndex(where: { $0.id == id }) {
                lamps[current].displayedPower = updated.state.power
                lamps[current].isPending = false
            }
        } catch {
            // Revert the row to its exact prior value with pending cleared
            // (Req 6.5/6.6). Re-find by id in case ordering shifted.
            if let current = lamps.firstIndex(where: { $0.id == id }) {
                lamps[current] = prior
                lamps[current].isPending = false
            }
            feedback = feedbackForToggleFailure(error)
        }
    }

    /// Merges freshly polled lamp data into the displayed list (Req 9.2).
    ///
    /// This is a pure synchronous merge (no I/O, no throwing). Every row that is
    /// currently pending retains its prior displayed value and pending flag;
    /// every non-pending row that appears in `fresh` adopts the polled value.
    /// Rows are keyed by id so identity is preserved across the merge; rows
    /// absent from `fresh` are dropped and new rows in `fresh` are appended.
    func applyPoll(_ fresh: [LampDTO]) {
        // Index current rows by id for pending/identity lookup.
        var currentByID: [String: LampRow] = [:]
        for row in lamps {
            currentByID[row.id] = row
        }

        lamps = fresh.map { dto in
            if let existing = currentByID[dto.id], existing.isPending {
                // Preserve the pending row's displayed value untouched (Req 9.2).
                return existing
            }
            return LampRow(dto: dto, displayedPower: dto.state.power, isPending: false)
        }
    }

    /// Maps a toggle-command failure to the appropriate German feedback: a
    /// timeout gets the timeout message, everything else the generic error
    /// message (Req 6.5/6.6).
    private func feedbackForToggleFailure(_ error: Error) -> Feedback {
        if case APIError.timeout = error {
            return Feedback(kind: .error, message: Strings.commandTimeout)
        }
        return Feedback(kind: .error, message: Strings.commandError)
    }
}
