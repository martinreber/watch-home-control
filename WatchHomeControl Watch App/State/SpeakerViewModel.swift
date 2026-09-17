// State/SpeakerViewModel.swift — Sonos speaker (Sonos) list + control view model.
//
// Drives the "Sonos" section: it loads the speaker list on activation (Req 7.1),
// preserves the Backend's returned order (Req 7.4), toggles playback per speaker
// with optimistic UI + revert-on-failure (Req 8), disables offline speakers
// (Req 7.7), and merges background poll results without clobbering in-flight rows
// (Req 9.3).
//
// The toggle decision (radio / play / pause) is delegated to the pure
// `SpeakerToggleMapper` (Req 8.1–8.3). All state mutation happens on the main
// actor.

import Foundation

@MainActor
@Observable
final class SpeakerViewModel {
    /// The speakers shown in the UI, in the order returned by the Backend
    /// (Req 7.4). Each row carries an optimistic displayed state and a pending
    /// flag while a command for that row is in flight.
    private(set) var speakers: [SpeakerRow] = []

    /// Non-blocking indicator that the most recent list refresh or Poll_Cycle
    /// failed. The view surfaces this as a small inline hint; the list itself is
    /// retained (Req 7.2/7.3/9.5).
    var refreshFailed: Bool = false

    /// German feedback shown after a toggle command completes with an error
    /// (Req 8.6). `nil` when no feedback is currently presented.
    var feedback: Feedback?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// Loads the speaker list via `GET /sonos/speakers` with a 10s deadline
    /// (Req 7.1).
    ///
    /// On success it rebuilds the rows preserving the Backend's order (Req 7.4),
    /// seeding each row's displayed state from the DTO and clearing pending, and
    /// clears `refreshFailed`. On timeout or any error it retains the current
    /// list and sets `refreshFailed` (Req 7.2/7.3).
    func activate() async {
        do {
            let fresh = try await api.fetchSpeakers(timeout: .seconds(10))
            speakers = fresh.map { dto in
                SpeakerRow(dto: dto, displayedState: dto.state, isPending: false)
            }
            refreshFailed = false
        } catch {
            // Retain the current list; surface a non-blocking refresh hint.
            refreshFailed = true
        }
    }

    /// Toggles the speaker with `id` on or off.
    ///
    /// Offline speakers issue no command (Req 7.7). Otherwise the command is
    /// resolved by `SpeakerToggleMapper` (radio for on+stopped, play for
    /// on+non-stopped, pause for off — Req 8.1–8.3). The row is marked pending
    /// and optimistically reflects the intended state for the duration of the
    /// call. On a success carrying an updated state the returned state is applied
    /// and pending cleared (Req 8.5). On an error, a timeout, or a success
    /// without a usable state, the row is reverted to its exact prior value with
    /// pending cleared and a German error message is shown (Req 8.6).
    func toggle(id: String, on: Bool) async {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }

        // Offline speakers cannot issue commands (Req 7.7).
        guard speakers[index].dto.online else { return }

        // Capture the exact prior row so we can restore it on any failure.
        let priorRow = speakers[index]

        let command = SpeakerToggleMapper.command(toggleOn: on, current: priorRow.displayedState)

        // Mark pending and optimistically reflect the intended state.
        var pendingRow = priorRow
        pendingRow.isPending = true
        pendingRow.displayedState = on ? .playing : .paused
        speakers[index] = pendingRow

        do {
            let updated: SpeakerDTO
            switch command {
            case .radio(let request):
                updated = try await api.playRadio(id: id, request: request, timeout: .seconds(10))
            case .play:
                updated = try await api.playSpeaker(id: id, timeout: .seconds(10))
            case .pause:
                updated = try await api.pauseSpeaker(id: id, timeout: .seconds(10))
            }

            // Apply the returned device state (Req 8.5). The row may have moved
            // (or vanished) while the command was in flight, so re-resolve it.
            guard let current = speakers.firstIndex(where: { $0.id == id }) else { return }
            var row = speakers[current]
            row.displayedState = updated.state
            row.isPending = false
            speakers[current] = row
        } catch {
            revert(id: id, to: priorRow)
            feedback = Feedback(kind: .error, message: Strings.commandError)
        }
    }

    /// Merges freshly polled speaker data into the displayed list (Req 9.3).
    ///
    /// Pure merge: rows currently in the Pending_State retain their prior
    /// displayed value (their in-flight command owns them), while non-pending
    /// rows present in `fresh` adopt the polled value. Backend order and row
    /// identity are preserved by iterating `fresh` in order and carrying the
    /// pending flag from the existing row.
    func applyPoll(_ fresh: [SpeakerDTO]) {
        let existing = Dictionary(speakers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        speakers = fresh.map { dto in
            if let prior = existing[dto.id], prior.isPending {
                // Pending row: keep the in-flight optimistic value untouched.
                return prior
            }
            return SpeakerRow(dto: dto, displayedState: dto.state, isPending: false)
        }
    }

    /// Restores the row for `id` to its exact prior value with pending cleared
    /// (Req 8.6). No-op if the row is no longer present.
    private func revert(id: String, to priorRow: SpeakerRow) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        var row = priorRow
        row.isPending = false
        speakers[index] = row
    }
}
