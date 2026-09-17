// Views/RootView.swift — top-level routing + scenePhase-driven poll lifecycle.
//
// `RootView` is the app's root screen (design › Views table). It owns three
// concerns:
//
//   1. Routing — switches on `AppModel.route` between the Setup_Screen and the
//      Control screen (Req 1.1/1.9/1.10). The switch lives inside a
//      `NavigationStack` so both destinations get a navigation chrome and the
//      config affordance in `ControlView`'s toolbar works.
//   2. Launch — runs `AppModel.onLaunch()` exactly once when the view appears,
//      which decides the initial route and (when a key exists) runs the health
//      check (Req 1.1/1.9/3.1).
//   3. Poll lifecycle — drives the Req 9 poll driver from
//      `@Environment(\.scenePhase)`: it starts polling on `.active` while the
//      Control screen is showing, and stops on `.inactive`/`.background`
//      (Req 9.1/9.6). Polling is never started on the Setup_Screen.
//
// The lamp and speaker view models are owned HERE (not in `ControlView`) so the
// scenePhase authority and the poll driver operate on the same instances that
// `ControlView` renders. They are constructed from `AppModel`'s shared
// `APIClient` and injected into `ControlView`.

import SwiftUI

/// Root view: routes between Setup and Control, runs launch, and drives the
/// scenePhase-aware poll lifecycle.
struct RootView: View {
    /// The root view model. Bindable so `route`/health/auth changes stay observed.
    @Bindable var model: AppModel

    /// Watch lifecycle phase. `.active` (while on Control) starts polling;
    /// `.inactive`/`.background` stop it (Req 9.1/9.6).
    @Environment(\.scenePhase) private var scenePhase

    /// Lamp (Lampen) view model, owned at the root so the poll driver and
    /// `ControlView` share one instance.
    @State private var lampVM: LampViewModel

    /// Speaker (Sonos) view model, owned at the root for the same reason.
    @State private var speakerVM: SpeakerViewModel

    init(model: AppModel) {
        self.model = model
        _lampVM = State(initialValue: LampViewModel(api: model.api))
        _speakerVM = State(initialValue: SpeakerViewModel(api: model.api))
    }

    var body: some View {
        NavigationStack {
            switch model.route {
            case .setup:
                SetupView(model: model)
            case .control:
                ControlView(model: model, lampVM: lampVM, speakerVM: speakerVM)
            }
        }
        // Decide the initial route and run the health check once on launch
        // (Req 1.1/1.9/3.1).
        .task {
            await model.onLaunch()
        }
        // Start/stop polling as the watch lifecycle changes (Req 9.1/9.6).
        .onChange(of: scenePhase) { _, newPhase in
            updatePolling(for: newPhase, route: model.route)
        }
        // Also react when routing into/out of Control while already active: e.g.
        // a successful setup submission switches to Control while `.active`, and
        // opening config switches back to Setup where polling must stop.
        .onChange(of: model.route) { _, newRoute in
            updatePolling(for: scenePhase, route: newRoute)
        }
    }

    /// Starts polling only while the app is `.active` AND showing the Control
    /// screen; stops polling otherwise (Setup screen or inactive/background).
    /// `startPolling` is idempotent and `stopPolling` is a no-op when already
    /// stopped, so this is safe to call on every transition (Req 9.1/9.6).
    private func updatePolling(for phase: ScenePhase, route: AppModel.Route) {
        if phase == .active && route == .control {
            model.startPolling(lamps: lampVM, speakers: speakerVM)
        } else {
            model.stopPolling()
        }
    }
}
