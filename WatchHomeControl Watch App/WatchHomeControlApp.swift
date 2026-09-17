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
        // Build the live dependency graph (Req 11.1: requests target the
        // configured Base_URL via LiveSettingsStore; Req 2.2: the API_Key lives
        // only in the Keychain via LiveKeychainStore).
        let settings = LiveSettingsStore()
        let keychain = LiveKeychainStore()
        let api = LiveAPIClient(settings: settings, keychain: keychain)

        #if DEBUG
        // Debug-only convenience for the watchOS Simulator, where entering an
        // API_Key by hand (or via paste) is unreliable. When the app is launched
        // with `WHC_DEBUG_API_KEY` set, seed the Keychain once so Setup is
        // skipped; `WHC_DEBUG_BASE_URL` optionally overrides the Base_URL. This
        // block is compiled out of Release builds entirely.
        let env = ProcessInfo.processInfo.environment
        if let debugBaseURL = env["WHC_DEBUG_BASE_URL"],
           case .success(let url) = URLValidator.validate(debugBaseURL) {
            settings.setBaseURL(url)
        }
        if let debugKey = env["WHC_DEBUG_API_KEY"] {
            let trimmed = debugKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try? keychain.saveAPIKey(trimmed)
            }
        }
        #endif

        _model = State(initialValue: AppModel(api: api, keychain: keychain, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
