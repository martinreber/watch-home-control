// WatchHomeControlApp.swift — @main entry point and composition root.
//
// This is the app's composition root: it constructs the single live dependency
// graph and hands it to `RootView`. Concretely it wires:
//
//   • `LiveSettingsStore`  — persists/reads the Base_URL (UserDefaults), so all
//     requests go to the configured Base_URL (Req 11.1).
//   • `LiveKeychainStore`  — stores/reads the API_Key in the Keychain (Req 2.2).
//   • `LiveAPIClient`       — URLSession-backed client reading Base_URL from the
//     settings store and the API_Key from the Keychain, fresh per request.
//   • `AppModel`            — the root @Observable view model, holding routing,
//     health, auth, and the poll driver.
//
// `AppModel` is held as `@State` so its identity is stable across body
// re-evaluations and its `@Observable` mutations drive the UI.

import SwiftUI

/// Application entry point for the standalone WatchHomeControl watchOS app.
@main
struct WatchHomeControlApp: App {
    /// The root view model, constructed once from the live dependency graph and
    /// retained for the lifetime of the app.
    @State private var model: AppModel

    init() {
        // One-time deletion of pre-sharing credential/Base_URL state (Req 7.9,
        // 7.10) — must run before the live stores below are constructed.
        LegacyStatePurge.runIfNeeded()

        // Build the live dependency graph (Req 11.1: requests target the
        // configured Base_URL via LiveSettingsStore; Req 2.2: the API_Key lives
        // only in the Keychain via LiveKeychainStore). Both now read/write the
        // Shared_Keychain_Group / Shared_Defaults_Suite the widget extension
        // also reads (Req 7.1, 7.4).
        let settings = LiveSettingsStore()
        let keychain = LiveKeychainStore()
        let api = LiveAPIClient(settings: settings, keychain: keychain)

        _model = State(initialValue: AppModel(api: api, keychain: keychain, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
