// Views/SpeakerListView.swift — Sonos speaker ("Sonos") list + per-speaker toggle.
//
// Renders the speakers in the exact order returned by the Backend (Req 7.4).
// Each row is a `Toggle` labeled with the speaker's name whose position is on if
// and only if the speaker's displayed state is `playing` (Req 7.5/7.6). Flipping
// a toggle dispatches the on/off command to the view model, which resolves the
// concrete radio/play/pause command and performs optimistic update + revert.
//
// Offline speakers have their toggle disabled so no command can be issued
// (Req 7.7), and a speaker with an in-flight command disables only its own
// toggle (Req 8.4). An empty list shows the German empty-state message
// (Req 7.8), and a failed refresh/poll surfaces a small, non-blocking hint
// without discarding the retained list (Req 7.2/7.3/9.5).

import SwiftUI

/// The "Sonos" section: a list of speaker rows, each a play/pause toggle.
struct SpeakerListView: View {
    /// Observed speaker list + control view model.
    let viewModel: SpeakerViewModel

    var body: some View {
        Group {
            if viewModel.speakers.isEmpty {
                // Empty list → German empty-state message (Req 7.8).
                Text(Strings.speakersEmpty)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // Rows in the Backend's returned order (Req 7.4).
                ForEach(viewModel.speakers) { row in
                    Toggle(row.dto.name, isOn: binding(for: row))
                        // Offline speakers cannot be activated (Req 7.7); a
                        // pending speaker disables only its own toggle (Req 8.4).
                        .disabled(!row.dto.online || row.isPending)
                }
            }

            if viewModel.refreshFailed {
                // Non-blocking refresh-failed hint; the list is retained
                // (Req 7.2/7.3/9.5).
                Text(Strings.refreshFailed)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await viewModel.activate() }
    }

    /// Toggle binding for a speaker row.
    ///
    /// Reads on iff the row's displayed state is `playing` (Req 7.5/7.6). Writing
    /// a new value hands the intent to the view model, which maps it to the
    /// concrete command and performs the optimistic update; `speakers` is
    /// `private(set)`, so the set closure never mutates it directly.
    private func binding(for row: SpeakerRow) -> Binding<Bool> {
        Binding(
            get: { row.displayedState == .playing },
            set: { newValue in
                Task { await viewModel.toggle(id: row.id, on: newValue) }
            }
        )
    }
}
