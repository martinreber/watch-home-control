// ToggleTVLampIntent.swift — the App Intent the Complication's tap invokes.
//
// A one-line shell over `TVLampToggleService`, which carries the actual
// read-then-toggle-then-read logic and is fully tested without WidgetKit or
// AppIntents involvement (Req 10.6). `openAppWhenRun = false` lets the toggle
// run in the background without foregrounding the Watch_App (Req 5.10);
// `isDiscoverable = false` keeps it a complication-only affordance rather than
// a Shortcuts action.

import AppIntents

struct ToggleTVLampIntent: AppIntent {
    static var title: LocalizedStringResource { "TV-Lampe schalten" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        _ = await TVLampToggleService(env: .live).run()
        return .result()
    }
}
