// Views/MessageBanner.swift — reusable non-blocking feedback/error presentation.
//
// A small, non-modal SwiftUI view that renders German command feedback and
// refresh/error hints inline (as a row/label suitable for a watchOS List or
// VStack). It never blocks interaction: success feedback shows subtle green
// styling, error feedback subtle red. When there is nothing to show (a nil
// `Feedback`) the view renders `EmptyView` and occupies no space.
//
// Used by the command/list views to surface `Feedback?` from the view models
// (Req 4.5/4.6, 5.7, 6.5, 8.6), the auth error message (Req 2.3), and the
// non-blocking refresh/poll-failed hint (Req 9.5).

import SwiftUI

/// A reusable, non-blocking inline banner for optional German feedback.
///
/// Renders nothing when there is no message, a subtle green row for success,
/// and a subtle red row for errors. It is deliberately non-modal — just an
/// inline label/row that composes inside a `List`, `Section`, or `VStack`.
struct MessageBanner: View {
    /// The optional feedback to present. `nil` renders `EmptyView`.
    let feedback: Feedback?

    /// Present an optional `Feedback` (from a view model).
    init(feedback: Feedback?) {
        self.feedback = feedback
    }

    /// Convenience initializer for a plain message string and an error flag.
    /// Passing an empty message renders nothing.
    init(text: String, isError: Bool) {
        if text.isEmpty {
            self.feedback = nil
        } else {
            self.feedback = Feedback(kind: isError ? .error : .success, message: text)
        }
    }

    var body: some View {
        if let feedback {
            Label {
                Text(feedback.message)
                    .font(.footnote)
            } icon: {
                Image(systemName: iconName(for: feedback.kind))
            }
            .foregroundStyle(tint(for: feedback.kind))
            .accessibilityElement(children: .combine)
        } else {
            EmptyView()
        }
    }

    /// Subtle, kind-appropriate tint: green for success, red for error.
    private func tint(for kind: Feedback.Kind) -> Color {
        switch kind {
        case .success: return .green
        case .error: return .red
        }
    }

    /// SF Symbol matching the feedback kind.
    private func iconName(for kind: Feedback.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
}

#Preview {
    List {
        MessageBanner(feedback: Feedback(kind: .success, message: "Befehl gesendet"))
        MessageBanner(feedback: Feedback(kind: .error, message: "Backend nicht erreichbar"))
        MessageBanner(text: "API-Key ungültig", isError: true)
        // Renders nothing:
        MessageBanner(feedback: nil)
    }
}
