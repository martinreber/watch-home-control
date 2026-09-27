// Complication/TVLampToggleService.swift — the read-then-toggle-then-read
// sequence run by the Toggle_Intent.
//
// Never derives the command from a displayed timeline entry: it always reads
// the TV_Lampe's current power first, sends the inverted value, and reads the
// result back before reporting a state, so a stale complication can never
// invert the wrong command (Req 5.2). Every path ends in exactly one
// `refresher.reload()` (Req 5.4–5.9, 3.13).

import Foundation

struct TVLampToggleService: Sendable {
    let env: ComplicationEnvironment

    /// The outcome of a run, primarily for tests to assert the exact path taken.
    enum Outcome: Equatable {
        /// The command and its read-back both succeeded.
        case toggled(ComplicationState)
        /// The command succeeded but the read-back failed or no longer
        /// resolves the TV_Lampe (Req 5.5).
        case readBackFailed
        /// The initial read resolved no TV_Lampe; no command was sent (Req 5.6).
        case unresolved
        /// No API_Key was available; defensive — the view does not offer the
        /// toggle affordance while Unpaired.
        case unpaired
        /// Any request (initial read or command) failed, timed out, or
        /// returned HTTP 401 (Req 5.7, 5.8, 5.9).
        case failed
    }

    func run() async -> Outcome {
        guard env.readAPIKey() != nil else {
            env.refresher.reload()
            return .unpaired
        }

        let initialLamps: [LampDTO]
        do {
            initialLamps = try await env.api.fetchLamps(timeout: ComplicationTiming.commandTimeout)
        } catch {
            env.refresher.reload()
            return .failed
        }

        guard case .resolved(let lamp) = TVLampSelector.select(from: initialLamps) else {
            env.refresher.reload()
            return .unresolved
        }

        do {
            _ = try await env.api.setLampState(
                id: lamp.id, power: !lamp.state.power, timeout: ComplicationTiming.commandTimeout)
        } catch {
            env.refresher.reload()
            return .failed
        }

        let readBackLamps: [LampDTO]
        do {
            readBackLamps = try await env.api.fetchLamps(timeout: ComplicationTiming.commandTimeout)
        } catch {
            env.refresher.reload()
            return .readBackFailed
        }

        guard case .resolved(let readBackLamp) = TVLampSelector.select(from: readBackLamps) else {
            env.refresher.reload()
            return .readBackFailed
        }

        env.refresher.reload()
        return .toggled(ComplicationState.resolve(pairing: .paired, resolution: .resolved(readBackLamp)))
    }
}
