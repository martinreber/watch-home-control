# Project Structure

```
watch-home-control/
├── WatchHomeControl.xcodeproj/         # Xcode project (single scheme)
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/         # Shared scheme "WatchHomeControl Watch App"
│
├── WatchHomeControl Watch App/         # App target (standalone watchOS, no iPhone companion)
│   ├── WatchHomeControlApp.swift       # @main App; constructs AppModel with Live* deps
│   ├── Strings.swift                   # All German user-facing strings (single source)
│   ├── Info.plist                      # Includes ATS NSAllowsLocalNetworking exception
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/         # 1024x1024 watchOS icon (AppIcon.png, no alpha)
│   │   └── AccentColor.colorset/
│   │
│   ├── Models/                         # Pure data types (no I/O)
│   │   ├── DTOs.swift                  # BlindAction, LampDTO, SpeakerDTO, RadioRequest, ...
│   │   ├── Rows.swift                  # LampRow / SpeakerRow (UI row wrappers)
│   │   ├── Errors.swift                # APIError, SetupError, Feedback, HealthState
│   │   └── SpeakerCommand.swift        # SpeakerToggleMapper (total toggle→command fn)
│   │
│   ├── Networking/                     # Request building + URLSession client
│   │   ├── Endpoint.swift              # Enum of every backend operation
│   │   ├── RequestBuilder.swift        # Pure Endpoint → URLRequest mapping
│   │   ├── APIClient.swift             # APIClient protocol
│   │   └── LiveAPIClient.swift         # URLSession impl (timeouts, 401/error mapping)
│   │
│   ├── Persistence/
│   │   ├── SettingsStore.swift         # Base_URL in UserDefaults (default 192.168.1.122:8080)
│   │   └── KeychainStore.swift         # API key in Keychain (service ch.reber.watchhomecontrol)
│   │
│   ├── State/                          # @MainActor @Observable view models
│   │   ├── AppModel.swift              # Routing, health, auth, pairing, poll driver
│   │   ├── BlindViewModel.swift        # Storen commands + feedback
│   │   ├── LampViewModel.swift         # Lamp list, optimistic toggle, poll merge
│   │   └── SpeakerViewModel.swift      # Speaker list, toggle mapper, poll merge
│   │
│   ├── Utilities/
│   │   ├── URLValidator.swift          # Absolute http(s) URL validation
│   │   └── ZurichTime.swift            # Europe/Zurich HH:MM formatting
│   │
│   └── Views/                          # SwiftUI views
│       ├── RootView.swift              # Routes Setup↔Control; scenePhase poll lifecycle
│       ├── SetupView.swift             # Einrichtung: Base_URL + Kopplungscode (CodePad) + cancel
│       ├── ControlView.swift           # TabView/List hosting the three sections + config
│       ├── BlindSection.swift          # Storen: Hoch / Runter
│       ├── LampListView.swift          # Lampen rows with toggles
│       ├── SpeakerListView.swift       # Sonos rows with toggles
│       ├── MessageBanner.swift         # Non-blocking German feedback/errors
│       └── ConnectionStatus / etc.
│
├── WatchHomeControlTests/              # Unit / property / example tests
│   └── WatchHomeControlTests.swift
│
├── build/                             # Local build output (git-ignored); e.g. build/cli-device
└── .kiro/
    ├── steering/                       # This directory
    └── specs/2026-09-17_apple-watch-home-control/   # requirements → design → tasks
```

## Key Patterns

| Pattern | Convention |
|---------|-----------|
| New backend call | Add case to `Endpoint`, map it in `RequestBuilder`, add a method to `APIClient`/`LiveAPIClient` |
| New view model | `@MainActor @Observable` class in `State/`, injected an `APIClient` |
| New Web/Screen view | Add SwiftUI view in `Views/`, route/host it from `RootView`/`ControlView` |
| User-facing text | Add a constant to `Strings.swift` (German); never hardcode strings in views |
| Optimistic command | set pending → send → apply returned state on success / revert on failure |
| Poll merge | `applyPoll(_:)` updates non-pending rows, preserves pending ones |
| Pure core first | Models/Networking(request)/Utilities are I/O-free and property-tested |

## Layering Rules

- **Pure core** (`Models`, `Networking/RequestBuilder`, `Utilities`) has no I/O
  and is exhaustively property-testable.
- **I/O edges** (`LiveAPIClient`, `KeychainStore`, `SettingsStore`) sit behind
  protocols so view models can be tested against doubles.
- **View models** (`State/`) are `@MainActor @Observable` and hold no
  networking logic beyond orchestration.
- **Views** (`Views/`) are declarative and delegate all logic to view models.

## Housekeeping

- Stray scratch files may appear during edits (e.g. `*.swift.new`,
  `UtilitiesPlaceholder.swift`, `StatePlaceholder.swift`). Placeholders exist to
  keep empty groups compiling; real scratch files (`.new`/`.tmp`) should not be
  committed and are safe to delete.
