// Complication/TVLampEntryLoader.swift — the TimelineProvider's logic, without
// any WidgetKit context.
//
// One path per Requirement 3 criterion. Never throws and never writes to the
// Keychain — every failure (unpaired, invalid Base_URL, timeout, network error,
// HTTP 401, non-2xx, empty/no-match) maps to the Unknown_State (Req 3.2–3.9,
// 3.15, 6.1, 6.6, 7.8, 8.2).

import Foundation

struct TVLampEntryLoader: Sendable {
    let env: ComplicationEnvironment

    /// A no-I/O representative entry for `placeholder`/`getSnapshot` (Req 3.2).
    func placeholder() -> TVLampEntry {
        TVLampEntry(date: env.now(), state: .on, interaction: .toggle)
    }

    /// Resolves the current Complication_State, subject to the Provider_Timeout,
    /// never throwing (Req 3.15).
    func load() async -> TVLampEntry {
        let pairing = env.pairingCondition

        // Unpaired: no network request, tap opens the Watch_App (Req 3.7, 6.1).
        guard pairing == .paired else {
            return TVLampEntry(date: env.now(), state: .unknown, interaction: .openSetup)
        }

        // An invalid stored Base_URL: no network request (Req 3.9, 8.2).
        switch env.resolveBaseURL() {
        case .invalid:
            return TVLampEntry(date: env.now(), state: .unknown, interaction: .toggle)
        case .configured, .fallbackDefault:
            return await fetchAndResolve(pairing: pairing)
        }
    }

    private func fetchAndResolve(pairing: PairingCondition) async -> TVLampEntry {
        do {
            let lamps = try await env.api.fetchLamps(timeout: ComplicationTiming.providerTimeout)
            let resolution = TVLampSelector.select(from: lamps)
            let state = ComplicationState.resolve(pairing: pairing, resolution: resolution)
            return TVLampEntry(date: env.now(), state: state, interaction: .toggle)
        } catch {
            // Timeout, network error, non-2xx, and HTTP 401 (Auth_Error) all map
            // to Unknown_State; a 401 leaves the credential untouched — only the
            // Watch_App handles re-pairing (Req 3.4, 3.5, 3.6).
            return TVLampEntry(date: env.now(), state: .unknown, interaction: .toggle)
        }
    }
}
