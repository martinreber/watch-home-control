// Views/LampListView.swift — the "Lampen" section.
//
// Renders the lamp list from `LampViewModel`: one `Toggle` per lamp whose label
// is the lamp's `displayName` and whose position reflects `displayedPower`
// (Req 5.4). Flipping a toggle dispatches `toggle(id:on:)`; while a row is
// pending only that row's toggle is disabled (Req 6.3). An empty list shows the
// German "Keine Lampen gefunden" message (Req 5.6), and a failed refresh shows a
// small non-blocking hint without clearing the list (Req 5.7).

import SwiftUI

/// The lamp (Lampen) control section.
struct LampListView: View {
    /// Observed lamp view model. `@Bindable` is not needed because `lamps` is
    /// `private(set)`; per-row bindings are constructed manually below.
    let viewModel: LampViewModel

    var body: some View {
        Section(Strings.sectionLamps) {
            if viewModel.lamps.isEmpty {
                // Empty state — no lamps returned (Req 5.6).
                Text(Strings.lampsEmpty)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.lamps) { row in
                    Toggle(row.dto.displayName, isOn: binding(for: row))
                        // Only the in-flight row's toggle is disabled (Req 6.3).
                        .disabled(row.isPending)
                }
            }

            if viewModel.refreshFailed {
                // Non-blocking hint; the list above is retained unchanged (Req 5.7).
                Text(Strings.refreshFailed)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await viewModel.activate()
        }
    }

    /// Builds a per-row `Binding<Bool>` over `displayedPower`. Reads reflect the
    /// row's optimistic power; a flip dispatches the toggle command for exactly
    /// that lamp (Req 5.4, 6.3). `lamps` is `private(set)`, so the setter routes
    /// through `toggle(id:on:)` rather than mutating the array directly.
    private func binding(for row: LampRow) -> Binding<Bool> {
        Binding(
            get: {
                // Re-read from the current model so the toggle reflects reverts
                // and returned device state; fall back to the captured row.
                viewModel.lamps.first(where: { $0.id == row.id })?.displayedPower
                    ?? row.displayedPower
            },
            set: { newValue in
                Task { await viewModel.toggle(id: row.id, on: newValue) }
            }
        )
    }
}

#Preview {
    // Preview relies on a lightweight in-memory client; construction is deferred
    // to the app target where LiveAPIClient is available.
    EmptyView()
}
