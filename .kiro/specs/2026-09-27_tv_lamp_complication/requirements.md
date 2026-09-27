# Requirements: TV-Lampe App Shortcut

## Introduction

This feature provides a watchOS `accessoryCircular` complication as a shortcut into
the existing standalone WatchHomeControl app. The complication is intentionally
**not a status display and not a toggle**: it always shows a neutral TV-Lampe icon
and label, and tapping it opens the app at the lamp controls. The user sees the
current state in the app and uses the existing lamp toggle there.

The widget is static and performs no network request, Keychain read, background
refresh, or App Intent. Its tap target is `watchhomecontrol://lamps`. The app routes
that URL to the Control screen and scrolls the existing lamp section into view. If
no API key is stored, the app routes to Einrichtung instead so the user can pair.

The prior status-colour, complication-side toggle, timeline polling, and background
refresh requirements are superseded by this launcher-only behavior.

## Glossary

- **Watch_App**: The standalone watchOS WatchHomeControl app.
- **Widget_Extension**: The watchOS WidgetKit extension containing the launcher widget.
- **Complication**: A static `accessoryCircular` widget that opens the Watch_App at its lamp controls.
- **Lamps_Deep_Link**: `watchhomecontrol://lamps`, routed to the app's Control screen with the Lampen section focused.
- **Setup_Deep_Link**: `watchhomecontrol://setup`, routed to the app's Einrichtung screen.

## Requirements

### Requirement 1: Static Launcher Widget

**User Story:** As the owner, I want a complication shortcut to the TV-Lampe controls, so I can open the app directly at the lamp list.

#### Acceptance Criteria

1. THE Widget_Extension SHALL provide a complication supporting exactly the `accessoryCircular` family.
2. THE Complication SHALL render a fixed, neutral TV-Lampe symbol and the shared label "TV"; its content SHALL NOT vary with lamp power or pairing state.
3. THE Complication SHALL use the shared German gallery display name and description.
4. THE Complication SHALL NOT render On_State, Off_State, Unknown_State, or any other representation of lamp power.
5. THE Widget_Extension SHALL NOT issue a Backend request, read the API_Key, or execute an App Intent to render or activate the Complication.
6. THE Widget_Extension SHALL provide a static timeline and SHALL NOT request periodic timeline reloads.

### Requirement 2: Tap Opens the Lamp Controls

**User Story:** As the owner, I want one tap on the complication to open the full app at the lamps, so I can see and control the current state there.

#### Acceptance Criteria

1. WHEN the user taps the Complication, THE Complication SHALL open the Watch_App through the Lamps_Deep_Link.
2. WHEN the Watch_App receives the Lamps_Deep_Link AND an API key is stored, THE Watch_App SHALL show the Control screen and scroll the Lampen section to the top of the visible content.
3. WHEN the Watch_App receives the Lamps_Deep_Link AND no API key is stored, THE Watch_App SHALL show Einrichtung so the user can pair.
4. WHEN the Watch_App is already showing Control and receives the Lamps_Deep_Link again, THE Watch_App SHALL scroll the Lampen section into view again.
5. THE Watch_App SHALL use the existing lamp list and toggle controls; it SHALL NOT add a second lamp-control implementation for the complication.

### Requirement 3: App Routing and Lamp Interaction

**User Story:** As the owner, I want to use the familiar in-app lamp controls after opening the complication, so the displayed state and toggle action remain consistent with the full app.

#### Acceptance Criteria

1. THE Watch_App SHALL continue to fetch lamp data using its existing `APIClient` and `LampViewModel` behavior after navigating to Control.
2. THE Lampen section SHALL preserve its existing pending-row, error, and refresh behavior.
3. WHEN the user changes the TV-Lampe from its in-app toggle, THE Watch_App SHALL send the existing `POST /lamps/{id}/state` command and render the response returned by the Backend.
4. THE Complication SHALL NOT attempt to keep its own lamp state synchronized; current state is read in the Watch_App.

### Requirement 4: Deep-Link Validation and Safety

**User Story:** As the owner, I want only recognized app links to change the app's route, so unrelated URLs cannot unexpectedly navigate the app.

#### Acceptance Criteria

1. THE Watch_App SHALL recognize the Lamps_Deep_Link by its `watchhomecontrol` scheme and `lamps` host, case-insensitively.
2. THE Watch_App SHALL continue to recognize the Setup_Deep_Link by its `watchhomecontrol` scheme and `setup` host, case-insensitively.
3. IF an incoming URL matches neither recognized link, THEN THE Watch_App SHALL leave its current route unchanged.
4. WHEN the user opens Einrichtung through the Setup_Deep_Link, THE Watch_App SHALL show the pairing-code input as defined by the existing setup flow.

### Requirement 5: Localization and Widget Configuration

**User Story:** As the owner, I want the complication launcher to match the app's German UI and be easy to identify in the watch-face gallery.

#### Acceptance Criteria

1. THE Complication SHALL source its label, gallery name, and gallery description from the shared `Strings` definitions.
2. THE Complication SHALL use the label "TV" and a fixed lamp glyph in every render.
3. THE Widget_Extension SHALL declare only `accessoryCircular` support.

### Requirement 6: Build and Testability

**User Story:** As the developer, I want the launcher routing to be testable without a watch, so the app opens on the correct section reliably.

#### Acceptance Criteria

1. THE recognition of the Lamps_Deep_Link and Setup_Deep_Link SHALL be pure and testable without I/O.
2. THE app-routing logic for paired and unpaired Lamps_Deep_Link handling SHALL be testable with in-memory dependencies.
3. THE Widget_Extension and Watch_App SHALL build for watchOS 11.0 with Swift 6.
4. THE Widget_Extension SHALL contain no duplicate app sources and SHALL not include Watch_App-only state or views.

### Requirement 7: Existing Credential Storage

**User Story:** As the owner, I want the app to retain its existing credential behavior, so the launcher does not disrupt pairing.

#### Acceptance Criteria

1. THE Watch_App SHALL continue to store and read the API_Key using its existing shared Keychain access group and `kSecAttrAccessibleAfterFirstUnlock` setting.
2. THE Watch_App SHALL continue to store and read Base_URL from the existing App Group UserDefaults suite.
3. THE Widget_Extension SHALL NOT read or write either shared store.
4. THE one-time legacy-state purge SHALL remain idempotent and SHALL NOT delete the current shared credential after it has run.

## Build Configuration

The Widget_Extension bundle identifier is `ch.reber.watchhomecontrol.watchkitapp.tvlampcomplication`; its deployment target is watchOS 11.0. The app registers the `watchhomecontrol` URL scheme. The complication uses `watchhomecontrol://lamps` to open the app at the Lampen section.
