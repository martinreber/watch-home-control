// Views/BlindSection.swift — the "Storen" (blind) control section.
//
// Renders the "Storen" section header (Req 4.1, 10.1) with two controls: "Hoch"
// (raise) and "Runter" (lower), bound to a `BlindViewModel`. Activating a control
// dispatches the corresponding `move(_:)` command. While a command is in flight
// the view model's `isPending` flag is set, and both controls are disabled
// (Req 4.4). Any command feedback surfaced by the view model is shown inline.

import SwiftUI

/// The "Storen" section: raise/lower controls bound to a `BlindViewModel`.
struct BlindSection: View {
    /// The blind view model driving command dispatch and pending/feedback state.
    /// Held by reference and observed via `@Bindable` so pending-state and
    /// feedback changes re-render the section.
    @Bindable var viewModel: BlindViewModel

    var body: some View {
        Section(Strings.sectionBlinds) {
            Button {
                Task { await viewModel.move(.up) }
            } label: {
                Label(Strings.blindUp, systemImage: "arrow.up")
            }
            .disabled(viewModel.isPending)

            Button {
                Task { await viewModel.move(.down) }
            } label: {
                Label(Strings.blindDown, systemImage: "arrow.down")
            }
            .disabled(viewModel.isPending)

            if let feedback = viewModel.feedback {
                Text(feedback.message)
                    .font(.footnote)
                    .foregroundStyle(feedback.kind == .error ? .red : .secondary)
            }
        }
    }
}

#Preview {
    // A lightweight preview client that satisfies APIClient without any network.
    List {
        BlindSection(viewModel: BlindViewModel(api: PreviewAPIClient()))
    }
}

/// No-op `APIClient` used only by the SwiftUI preview above.
private struct PreviewAPIClient: APIClient {
    func checkHealth(timeout: Duration) async throws -> Bool { true }
    func moveBlind(_ action: BlindAction, timeout: Duration) async throws {}
    func fetchLamps(timeout: Duration) async throws -> [LampDTO] { [] }
    func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
        LampDTO(id: id, friendlyName: nil, type: nil, state: LampState(power: power))
    }
    func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] { [] }
    func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
        SpeakerDTO(id: id, name: "", state: .playing, online: true, modelName: nil)
    }
    func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
        SpeakerDTO(id: id, name: "", state: .paused, online: true, modelName: nil)
    }
    func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
        SpeakerDTO(id: id, name: "", state: .playing, online: true, modelName: nil)
    }
    func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String { "" }
}
