// Views/ControlView.swift — the main control screen (blinds, lamps, speakers).
//
// `ControlView` is the app's primary screen once a Base_URL + API_Key are
// configured and the Backend is reachable (design › Views table). It composes
// the three control sections in a single watchOS-friendly scrolling `List`:
//
//   • `BlindSection`   — "Storen" raise/lower controls
//   • `LampListView`   — "Lampen" per-lamp toggles
//   • `SpeakerListView`— "Sonos" per-speaker toggles
//
// It owns the blind view model as `@State` (constructed from the `AppModel`'s
// shared `APIClient`), while the lamp and speaker view models are injected by
// `RootView` so their lifetime spans the whole session and the scenePhase-driven
// poll lifecycle at the `RootView` level (Task 15.1) can start/stop polling
// against the same instances the sections render.
// A config affordance in the navigation toolbar (labeled "Einstellungen") calls
// `AppModel.openConfig()` to re-present the Setup_Screen pre-filled with the
// current Base_URL (Req 1.10). All labels come from `Strings` (German — Req 10.1).
//
// The periodic Lamp/Speaker refresh (Req 9) is driven entirely by `RootView`'s
// scenePhase logic via `AppModel`'s poll driver, not by this view. `ControlView`
// no longer starts/stops polling itself; it only renders the injected view models.

import SwiftUI

/// The main control screen hosting the blind, lamp, and speaker sections plus a
/// configuration affordance.
struct ControlView: View {
    /// The root view model. Bindable so `openConfig()` routing stays observed and
    /// so the shared `APIClient` is available for the child view models.
    @Bindable var model: AppModel

    /// Blind (Storen) control view model, backed by the shared API client. Owned
    /// here because it plays no part in the poll lifecycle.
    @State private var blindVM: BlindViewModel

    /// Lamp (Lampen) list + control view model. Injected by `RootView` so the
    /// scenePhase-driven poll driver refreshes the same instance rendered here.
    let lampVM: LampViewModel

    /// Speaker (Sonos) list + control view model. Injected by `RootView` for the
    /// same reason as `lampVM`.
    let speakerVM: SpeakerViewModel

    init(model: AppModel, lampVM: LampViewModel, speakerVM: SpeakerViewModel) {
        self.model = model
        self.lampVM = lampVM
        self.speakerVM = speakerVM
        _blindVM = State(initialValue: BlindViewModel(api: model.api))
    }

    var body: some View {
        // A single scrolling List is the watchOS-friendly host: each child view
        // renders its own Section, except SpeakerListView which is wrapped here.
        List {
            BlindSection(viewModel: blindVM)

            LampListView(viewModel: lampVM)

            Section(Strings.sectionSpeakers) {
                SpeakerListView(viewModel: speakerVM)
            }
        }
        .navigationTitle(Strings.appTitle)
        .toolbar {
            // Config affordance: re-present the Setup_Screen pre-filled with the
            // current Base_URL for a Base_URL/API_Key change (Req 1.10).
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.openConfig()
                } label: {
                    Label(Strings.openConfig, systemImage: "gearshape")
                }
            }
        }
        // Poll start/stop is owned by RootView's scenePhase logic (Req 9.1/9.6);
        // ControlView intentionally does not drive the poll lifecycle.
    }
}
