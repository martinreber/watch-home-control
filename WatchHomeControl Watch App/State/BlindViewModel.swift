// State/BlindViewModel.swift — blind (Storen) control view model.
//
// Drives the "Storen" section: a "Hoch" and a "Runter" control that raise and
// lower the blinds via `POST /blind`. While a command is in flight the view
// model is in the Pending_State (Req 4.4), which the view binds to in order to
// disable both controls. On completion it clears the pending flag and surfaces
// German success/error/timeout feedback (Req 4.5–4.7).

import Foundation

@MainActor
@Observable
final class BlindViewModel {
    /// True while a blind command is in flight. The view disables both the
    /// "Hoch" and "Runter" controls while this is set (Req 4.4).
    var isPending: Bool = false

    /// Non-blocking German feedback shown after the most recent command
    /// completes (success, error, or timeout). `nil` when no feedback is
    /// currently presented.
    var feedback: Feedback?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// Sends `POST /blind` for the given action with a 10s deadline (Req 4.2/4.3).
    ///
    /// Sets the Pending_State for the duration of the request (Req 4.4) and
    /// always clears it on completion (Req 4.5–4.7). On success it presents
    /// German success feedback; on a timeout it presents German timeout
    /// feedback; on any other failure it presents German error feedback.
    func move(_ action: BlindAction) async {
        isPending = true
        feedback = nil
        defer { isPending = false }

        do {
            try await api.moveBlind(action, timeout: .seconds(10))
            feedback = Feedback(kind: .success, message: Strings.commandSuccess)
        } catch APIError.timeout {
            feedback = Feedback(kind: .error, message: Strings.commandTimeout)
        } catch {
            feedback = Feedback(kind: .error, message: Strings.commandError)
        }
    }
}
