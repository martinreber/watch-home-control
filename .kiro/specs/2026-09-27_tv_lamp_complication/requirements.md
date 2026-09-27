# Requirements Document

## Introduction

This feature adds a watchOS watch-face **complication** to the existing standalone
**WatchHomeControl** app (Apple Watch Ultra 2, watchOS 11.0, Swift 6, SwiftUI). The
complication surfaces the on/off state of the "TV-Lampe" lamp directly on the watch
face and lets the user toggle that lamp without opening the app. It occupies the
bottom-row middle slot of the user's watch face, i.e. the round `accessoryCircular`
slot, which is the **only** supported widget family.

The complication is a new **WidgetKit** widget delivered by a watchOS **widget
extension** target, not an in-app control. Its content is an interactive
`Button(intent:)` that runs an **App Intent** (AppIntents framework) in the
background where the platform permits. The intent performs a **read-then-toggle**:
it reads the current TV-Lampe state from the Backend, sends the inverted power
value, reads the resulting state back, and then reloads the complication's timeline.
It never infers the command from a possibly stale timeline entry.

The Complication always renders the label "TV" and expresses state through font
colour only: green when on, red when off, grey when unknown. It requests the
`fullColor` widget rendering mode. Because the unpaired case routes the user into
the Watch_App instead of toggling, the Complication needs exactly three display
states: On, Off, Unknown.

Refreshing follows what watchOS actually permits. WidgetKit does **not** run a
timer: a timeline reload policy is only a *request*, and background reloads are
capped by a daily system budget, so a watch face cannot be polled every 10 seconds.
The 10-second cadence is therefore specified as a **target interval that applies
while the Watch_App is running** — the app already polls the Backend and requests a
Timeline_Reload at most every 10 seconds when the TV-Lampe's power actually changed.
While the Watch_App is not running, the Complication relies on two other paths: the
reload the Toggle_Intent requests right after the user taps it (user-initiated, so
not subject to the background budget), and the background reload policy the
Widget_Extension requests, which the system may defer for many minutes. Between
reloads the Complication keeps showing its last known state; it never downgrades to
Unknown merely because the entry is old, and a tap stays correct regardless of
displayed age because the Toggle_Intent re-reads the lamp before commanding it.

Because a widget extension runs in a separate process from the main app, the
complication and its App Intent must read the same credentials the main app uses.
The API_Key is therefore stored in a **shared Keychain access group** (fully
qualified with the team prefix, and accessible after first unlock so refreshes work
while the watch is locked), and the Base_URL is stored in a **shared App Group
UserDefaults suite**. The API_Key continues to live only in the Keychain and is
never logged or persisted elsewhere. There is **no migration** of existing local
state: the first launch of this version deletes the legacy credential and Base_URL,
and the user re-pairs from the Setup screen.

The TV-Lampe is not identified by a hardcoded id. It is selected at runtime by
matching the lamp from `GET /lamps` whose name (`friendly_name`, falling back to
`id`) contains the case-insensitive substring "TV-Lampe". User-facing text is German
and comes from the app's existing shared `Strings.swift`. When no API_Key is present
(or the Backend rejects it with HTTP 401), the Complication renders the Unknown_State
and tapping it opens the Watch_App on its Setup (Einrichtung) screen so the user can
enter a new pairing code.

## Glossary

- **Watch_App**: The existing standalone watchOS application ("WatchHomeControl").
- **Complication**: The WidgetKit widget rendered on the watch face by the Widget_Extension, showing TV-Lampe state and acting as the toggle affordance.
- **Widget_Extension**: The new watchOS widget extension target (separate process) that hosts the Complication, its `TimelineProvider`, and its App Intent.
- **Backend**: The existing `home-control` Go application exposing the REST API.
- **Base_URL**: The configured server address the Watch_App and Widget_Extension target (default `https://192.168.1.122:8443`).
- **API_Key**: The static credential sent in the `X-API-Key` HTTP header on authenticated requests.
- **Shared_Keychain_Group**: The Keychain access group `5V4FMXSU55.ch.reber.watchhomecontrol.shared` (team prefix `5V4FMXSU55`), holding the generic-password item with service `ch.reber.watchhomecontrol` and account `api_key`, shared by the Watch_App and the Widget_Extension.
- **Shared_Defaults_Suite**: The App Group UserDefaults suite `group.ch.reber.watchhomecontrol`, shared by the Watch_App and the Widget_Extension, holding the Base_URL under the key `base_url`.
- **Shared_Sources**: The existing Swift source files (`Endpoint`, `RequestBuilder`, `APIClient`/`LiveAPIClient`, `DTOs`, `KeychainStore`, `SettingsStore`, `URLValidator`, `Strings`) plus the new pure complication logic, compiled into the Watch_App, the Widget_Extension, and the test target from a single copy.
- **Lamp**: A controllable light with fields `id`, `friendly_name` (optional), `type`, and `state.power` (boolean), as returned by `GET /lamps`.
- **Lamp_Name**: A lamp's display name: its `friendly_name` when present and non-empty, otherwise its `id` (the existing `LampDTO.displayName`).
- **TV_Lampe**: The Lamp selected for the Complication: the lamp whose Lamp_Name contains the case-insensitive substring "TV-Lampe".
- **Toggle_Intent**: The App Intent invoked when the user taps the Complication while Paired; it performs the read-then-toggle-then-read sequence and requests a Timeline_Reload.
- **Timeline_Reload**: A request to WidgetKit (`WidgetCenter.reloadTimelines`) to refresh the Complication's timeline so displayed state reflects the current TV_Lampe state.
- **Refresh_Interval**: The 10-second target interval between Timeline_Reloads requested by the Watch_App while it is running, and the interval requested by the Widget_Extension's background reload policy.
- **Foreground_Refresh**: A Timeline_Reload requested by the running Watch_App from its existing lamp poll cycle. This is the only path that meets the Refresh_Interval in practice.
- **Interaction_Refresh**: The Timeline_Reload the Toggle_Intent requests after a user tap. User-initiated, therefore not deferred by the background refresh budget.
- **Background_Refresh**: A timeline request WidgetKit issues on its own schedule from the reload policy. Best-effort only: watchOS caps these by a daily budget and may defer them for many minutes.
- **Complication_State**: The display state of the Complication, exactly one of On_State, Off_State, Unknown_State.
- **On_State**: Complication_State shown WHEN the TV_Lampe's `state.power` is `true`; label "TV" in green.
- **Off_State**: Complication_State shown WHEN the TV_Lampe's `state.power` is `false`; label "TV" in red.
- **Unknown_State**: Complication_State shown WHEN the TV_Lampe's power cannot currently be determined — request failed, timed out, no matching lamp, invalid Base_URL, Auth_Error, or Unpaired; label "TV" in grey.
- **Paired**: The condition in which an API_Key is readable from the Shared_Keychain_Group.
- **Unpaired**: The condition in which no API_Key is readable from the Shared_Keychain_Group, including the case where the Keychain read fails for any other reason.
- **Setup_Deep_Link**: The URL `watchhomecontrol://setup`, opened by the Complication while Unpaired, which routes the Watch_App to its Setup (Einrichtung) screen.
- **Provider_Timeout**: The 5-second deadline applied to any Backend request issued from the Complication's `TimelineProvider`.
- **Command_Timeout**: The 10-second deadline applied to each Backend request issued from the Toggle_Intent.
- **Auth_Error**: The condition in which the Backend returns HTTP 401 for an authenticated request.

## Requirements

### Requirement 1: Complication Target and Supported Family

**User Story:** As the owner, I want a watch-face complication for the TV-Lampe, so that I can see and control it from the bottom-middle slot of my watch face.

#### Acceptance Criteria

1. THE Widget_Extension SHALL provide a Complication that the user can add to a watch face.
2. THE Complication SHALL declare support for exactly one widget family, `accessoryCircular`.
3. THE Complication SHALL render the label "TV" and SHALL convey the current Complication_State solely through the label's font colour.
4. THE Complication SHALL request the `fullColor` widget rendering mode.
5. WHERE the watch face renders the Complication in a rendering mode other than `fullColor`, THE Complication SHALL still render the label "TV" and SHALL NOT fail to render.
6. IF the Complication_State cannot be determined at render time, THEN THE Complication SHALL render the Unknown_State.
7. THE Complication SHALL expose a German display name and description in the watch-face gallery, sourced from the shared string definitions.

### Requirement 2: State Display

**User Story:** As the owner, I want the complication to show whether the TV-Lampe is on or off, so that I can read its status at a glance.

#### Acceptance Criteria

1. WHEN the resolved TV_Lampe has `state.power` equal to `true`, THE Complication SHALL render the On_State: the label "TV" in green.
2. WHEN the resolved TV_Lampe has `state.power` equal to `false`, THE Complication SHALL render the Off_State: the label "TV" in red.
3. IF the TV_Lampe's power cannot be determined within the Provider_Timeout, THEN THE Complication SHALL render the Unknown_State: the label "TV" in grey.
4. WHILE Unpaired, THE Complication SHALL render the Unknown_State.
5. THE green, red, and grey label colours SHALL be pairwise distinct.
6. THE Complication SHALL render the same label text "TV" in every Complication_State, sourced from the shared string definitions.

### Requirement 3: Timeline Provisioning

**User Story:** As the owner, I want the complication to reflect the current lamp state, so that what I see on the watch face matches reality.

#### Acceptance Criteria

1. WHEN WidgetKit requests a timeline for the Complication AND the Watch_App is Paired AND the Base_URL resolves to a valid absolute http(s) URL, THE Widget_Extension SHALL send `GET /lamps` to the Base_URL with the `X-API-Key` header set to the API_Key, subject to the Provider_Timeout.
2. WHEN WidgetKit requests a placeholder or a snapshot for the Complication, THE Widget_Extension SHALL return a single representative entry rendering a defined Complication_State without sending any network request.
3. WHEN a timeline request resolves the TV_Lampe, THE Widget_Extension SHALL produce a timeline entry rendering the On_State when the lamp's `state.power` is `true` and the Off_State when it is `false`.
4. IF a timeline `GET /lamps` request does not complete within the Provider_Timeout, THEN THE Widget_Extension SHALL cancel the request and produce a timeline entry rendering the Unknown_State.
5. IF a timeline `GET /lamps` request returns an error response or fails due to a network error, THEN THE Widget_Extension SHALL produce a timeline entry rendering the Unknown_State.
6. IF a timeline `GET /lamps` request returns HTTP 401, THEN THE Widget_Extension SHALL produce a timeline entry rendering the Unknown_State and SHALL leave the API_Key in the Shared_Keychain_Group unchanged, so that the Watch_App can handle re-pairing (Requirement 6).
7. WHILE Unpaired, THE Widget_Extension SHALL produce a timeline entry rendering the Unknown_State without sending any network request.
8. IF a timeline `GET /lamps` request succeeds but no lamp in the response matches the TV_Lampe, THEN THE Widget_Extension SHALL produce a timeline entry rendering the Unknown_State.
9. IF the Base_URL stored in the Shared_Defaults_Suite is present but is not a valid absolute http(s) URL with a host, THEN THE Widget_Extension SHALL produce a timeline entry rendering the Unknown_State without sending any network request.
10. WHEN the Widget_Extension returns a timeline, THE Widget_Extension SHALL return exactly one entry dated now, with the reload policy `.after(now + Refresh_Interval)`, and SHALL NOT pre-compute future entries.
11. THE Refresh_Interval requested in criterion 10 SHALL be treated as a Background_Refresh request only: the Widget_Extension SHALL NOT assume WidgetKit honours it, SHALL tolerate the system deferring it for an arbitrary duration, and SHALL request it again on every subsequent timeline request.
12. WHILE no new timeline entry has been produced, THE Complication SHALL keep rendering its most recent entry and SHALL NOT change the rendered Complication_State based on the entry's age.
13. WHEN the Toggle_Intent completes, THE Widget_Extension SHALL request an Interaction_Refresh so the tap result is reflected without waiting for a Background_Refresh (Requirement 5).
14. WHILE the Watch_App is running, THE Watch_App SHALL drive the Refresh_Interval through Foreground_Refresh as defined in Requirement 7.
15. THE Widget_Extension SHALL complete every timeline request without terminating abnormally, in every state defined by this requirement.

### Requirement 4: TV-Lampe Selection by Name

**User Story:** As the owner, I want the complication to find the TV-Lampe by name, so that it keeps working even if the lamp's id changes.

#### Acceptance Criteria

1. WHEN resolving the TV_Lampe from a lamp list, THE Widget_Extension SHALL select the lamp whose Lamp_Name contains the substring "TV-Lampe", compared case-insensitively.
2. IF more than one lamp's Lamp_Name contains "TV-Lampe", THEN THE Widget_Extension SHALL select the first such lamp in the order returned by the Backend.
3. IF no lamp's Lamp_Name contains "TV-Lampe", THEN THE Widget_Extension SHALL treat the TV_Lampe as unresolved.
4. WHERE a lamp has no `friendly_name` or an empty `friendly_name`, THE Widget_Extension SHALL use that lamp's `id` as its Lamp_Name for the match, reusing the existing `LampDTO.displayName` rule.
5. IF the lamp list is empty or absent, THEN THE Widget_Extension SHALL treat the TV_Lampe as unresolved.
6. WHEN the TV_Lampe is unresolved, THE Complication SHALL render the Unknown_State.

### Requirement 5: Toggle via App Intent

**User Story:** As the owner, I want to tap the complication to turn the TV-Lampe on or off, so that I can control it without opening the app.

#### Acceptance Criteria

1. WHILE Paired, THE Complication SHALL present its content as an interactive control that invokes the Toggle_Intent when tapped.
2. WHEN the Toggle_Intent runs, THE Toggle_Intent SHALL first send `GET /lamps` to read the current TV_Lampe state, and SHALL NOT derive the command from the Complication's displayed timeline entry.
3. WHEN the Toggle_Intent has read the TV_Lampe with `state.power` equal to `P`, THE Toggle_Intent SHALL send `POST /lamps/{id}/state` for that lamp's id with request body `{"power": !P}` and header `Content-Type: application/json`.
4. WHEN the `POST /lamps/{id}/state` request succeeds, THE Toggle_Intent SHALL send a further `GET /lamps` to read the resulting TV_Lampe state and SHALL request a Timeline_Reload so the Complication renders that read-back state.
5. IF the read-back `GET /lamps` in criterion 4 fails, times out, or no longer resolves the TV_Lampe, THEN THE Toggle_Intent SHALL request a Timeline_Reload and complete without reporting a TV_Lampe state.
6. IF the initial `GET /lamps` resolves no TV_Lampe, THEN THE Toggle_Intent SHALL complete without sending any `POST /lamps/{id}/state` request and SHALL request a Timeline_Reload.
7. IF any Toggle_Intent request does not complete within the Command_Timeout, THEN THE Toggle_Intent SHALL cancel that request, send no further requests, request a Timeline_Reload, and complete.
8. IF any Toggle_Intent request returns an error response or fails due to a network error, THEN THE Toggle_Intent SHALL send no further requests, request a Timeline_Reload, and complete.
9. IF any Toggle_Intent request returns HTTP 401, THEN THE Toggle_Intent SHALL leave the API_Key in the Shared_Keychain_Group unchanged, request a Timeline_Reload, and complete, so that the Complication renders the Unknown_State.
10. WHERE the platform permits an App Intent to run without bringing the Watch_App to the foreground, THE Toggle_Intent SHALL perform the toggle without launching the Watch_App into the foreground.
11. WHILE Unpaired, THE Complication SHALL NOT invoke the Toggle_Intent and SHALL instead behave as defined in Requirement 6.

### Requirement 6: Unpaired and Auth-Failure Handling

**User Story:** As the owner, I want the complication to behave sensibly before pairing and after a rejected credential, so that it never crashes and guides me back to pairing.

#### Acceptance Criteria

1. WHILE Unpaired, THE Widget_Extension SHALL render the Unknown_State and SHALL NOT send any authenticated Backend request.
2. WHEN the user taps the Complication WHILE Unpaired, THE Complication SHALL open the Watch_App via the Setup_Deep_Link instead of invoking the Toggle_Intent.
3. WHEN the Watch_App is opened with the Setup_Deep_Link, THE Watch_App SHALL present its Setup (Einrichtung) screen with the Pairing_Code input, regardless of its current routing state.
4. WHEN an authenticated Backend request from the Watch_App returns HTTP 401, THE Watch_App SHALL present its Setup (Einrichtung) screen so the user can enter a new pairing code, and SHALL request a Timeline_Reload.
5. WHEN the API_Key is removed from the Shared_Keychain_Group, THE Watch_App SHALL request a Timeline_Reload, and THE Widget_Extension SHALL render the Unknown_State on the next timeline request after the removal.
6. IF a read of the Shared_Keychain_Group fails for any reason other than absence of the API_Key, THEN THE Widget_Extension SHALL treat the condition as Unpaired.
7. WHILE Unpaired, THE Widget_Extension SHALL complete each timeline request without issuing a network request and without terminating abnormally.

### Requirement 7: Credential and Setting Sharing Across App and Extension

**User Story:** As the owner, I want the app and the complication to share one credential, so that pairing once makes the complication work.

#### Acceptance Criteria

1. THE Watch_App and the Widget_Extension SHALL read and write the API_Key as a single generic-password item in the Shared_Keychain_Group, with service `ch.reber.watchhomecontrol` and account `api_key`.
2. THE Watch_App and the Widget_Extension SHALL set `kSecAttrAccessGroup` to the fully qualified value `5V4FMXSU55.ch.reber.watchhomecontrol.shared` on every Keychain query, because an explicitly supplied access group is NOT automatically prefixed with the team identifier and an unprefixed value fails with `errSecMissingEntitlement` (-34018).
3. THE Watch_App SHALL store the API_Key with `kSecAttrAccessible` set to `kSecAttrAccessibleAfterFirstUnlock`, so the Widget_Extension can read it during a timeline refresh while the watch is locked.
4. THE Watch_App and the Widget_Extension SHALL read the Base_URL from the Shared_Defaults_Suite `group.ch.reber.watchhomecontrol` under the key `base_url`, and SHALL NOT read it from `UserDefaults.standard`.
5. WHEN the Watch_App stores or replaces the API_Key after a successful pairing, THE Watch_App SHALL write it to the Shared_Keychain_Group such that any Widget_Extension request issued after the write completes reads the same API_Key value.
6. WHEN the Watch_App persists the Base_URL, THE Watch_App SHALL write it to the Shared_Defaults_Suite such that any Widget_Extension request issued after the write completes targets the same Base_URL value.
7. WHERE no `base_url` value exists in the Shared_Defaults_Suite, THE Watch_App and the Widget_Extension SHALL use the default value `https://192.168.1.122:8443`.
8. THE Widget_Extension SHALL NOT write the API_Key to the Shared_Defaults_Suite, to any file, or to any log output, and SHALL NOT write to the Shared_Keychain_Group at all.
9. WHEN this version of the Watch_App launches for the first time after an upgrade, THE Watch_App SHALL delete any legacy API_Key item stored without the Shared_Keychain_Group and any legacy `base_url` value stored in `UserDefaults.standard`, SHALL NOT migrate either value, and SHALL present its Setup (Einrichtung) screen so the user re-enters a pairing code.
10. THE legacy-state deletion in criterion 9 SHALL be idempotent and SHALL run at most once per install, leaving a subsequently paired credential untouched on later launches.
11. WHEN the Watch_App completes a pairing, deletes the API_Key, or changes the Base_URL, THE Watch_App SHALL request a Timeline_Reload for the Complication.
12. WHILE the Watch_App is running and polling the Backend, THE Watch_App SHALL perform a Foreground_Refresh whenever the TV_Lampe's power read from its existing 5-second Poll_Cycle or returned by a lamp command differs from the power it last published to the Complication.
13. THE Watch_App SHALL NOT issue more than one Foreground_Refresh per Refresh_Interval, and SHALL NOT issue a Foreground_Refresh when the TV_Lampe's power is unchanged, so the system refresh budget is not consumed needlessly.
14. WHILE the Watch_App is not running, THE Watch_App SHALL NOT be required to refresh the Complication, and the Complication's freshness SHALL depend solely on Interaction_Refresh and Background_Refresh.

### Requirement 8: Network and Transport Configuration

**User Story:** As the owner, I want the complication to reach my LAN Backend over its local endpoint, so that it works on my home network.

#### Acceptance Criteria

1. WHEN the Widget_Extension issues any Backend request, THE Widget_Extension SHALL send that request to the Base_URL read from the Shared_Defaults_Suite.
2. IF the stored Base_URL is empty or is not a syntactically valid absolute http or https URL with a host, as decided by the existing `URLValidator`, THEN THE Widget_Extension SHALL NOT issue the request and SHALL render the Unknown_State.
3. THE Widget_Extension's own `Info.plist` SHALL declare the App Transport Security local-networking exception (`NSAppTransportSecurity` / `NSAllowsLocalNetworking`), matching the Watch_App's `Info.plist`.
4. THE Widget_Extension SHALL rely on the device-installed trust profile for the Backend's self-signed TLS certificate and SHALL NOT implement a server-trust override.
5. WHEN the Widget_Extension issues a request that includes a JSON request body, THE Widget_Extension SHALL set the request header `Content-Type` to `application/json`.
6. WHEN the Widget_Extension issues an authenticated request, THE Widget_Extension SHALL include the header `X-API-Key` set to the API_Key read from the Shared_Keychain_Group.
7. IF no API_Key is available, THEN THE Widget_Extension SHALL NOT issue an authenticated request.
8. THE Widget_Extension SHALL apply the Provider_Timeout of 5 seconds to requests issued from the `TimelineProvider` and the Command_Timeout of 10 seconds to requests issued from the Toggle_Intent, cancelling any request that exceeds its deadline.
9. THE Widget_Extension SHALL construct every Backend request through the shared `Endpoint` and `RequestBuilder` types and SHALL NOT build URLs, headers, or bodies inline.

### Requirement 9: German Localization

**User Story:** As the owner, I want the complication text in German, so that it matches the rest of the app.

#### Acceptance Criteria

1. THE Complication SHALL source all user-facing text from the shared `Strings` definitions used by the Watch_App and SHALL NOT define any user-facing string literal locally in the Widget_Extension.
2. THE shared `Strings` definitions SHALL provide the Complication label "TV", the German watch-face gallery display name "TV-Lampe", and a German gallery description.
3. WHEN the Complication renders any Complication_State, THE Complication SHALL display the label from criterion 2 and SHALL NOT render empty text.

### Requirement 10: Testability of Pure Logic

**User Story:** As the developer, I want the selection, mapping, and request logic to be pure and property-tested, so that the complication's core behavior is verifiable without a device.

#### Acceptance Criteria

1. THE TV_Lampe selection logic SHALL be a pure function that takes a lamp list and returns either the selected lamp or an unresolved result, performing no I/O and producing identical output for identical input.
2. THE mapping from a selection result plus the pairing condition to a Complication_State SHALL be a pure function that performs no I/O and produces identical output for identical input.
3. THE mapping in criterion 2 SHALL be total: every combination of selection result and pairing condition SHALL yield exactly one of On_State, Off_State, Unknown_State.
4. THE construction of the `GET /lamps` request and the `POST /lamps/{id}/state` request SHALL reuse the existing `RequestBuilder`, producing method, path, headers, and body deterministically without I/O.
5. THE TV_Lampe selection, Complication_State mapping, and request-building logic SHALL each be covered by property-based tests running a minimum of 100 iterations per property.
6. THE `TimelineProvider` and the Toggle_Intent SHALL depend on the existing `APIClient`, `KeychainStore`, and `SettingsStore` protocol seams rather than concrete live implementations, so their behaviour can be exercised with in-memory doubles and no network.
7. THE Toggle_Intent's read-then-toggle-then-read sequence SHALL be covered by tests asserting the ordered sequence of endpoints issued against a stub `APIClient`, including the success, unresolved, timeout, error, and HTTP 401 paths.

### Requirement 11: Target, Entitlements, and Build Configuration

**User Story:** As the developer, I want the extension target wired up correctly, so that the shared Keychain and App Group actually resolve on device.

#### Acceptance Criteria

1. THE project SHALL contain a new watchOS widget extension target embedded in the Watch_App, with bundle identifier `ch.reber.watchhomecontrol.watchkitapp.tvlampcomplication`, deployment target watchOS 11.0, Swift 6, and development team `5V4FMXSU55`.
2. THE Watch_App target and the Widget_Extension target SHALL each have a code-signing entitlements file declaring the Keychain access group `$(AppIdentifierPrefix)ch.reber.watchhomecontrol.shared` and the App Group `group.ch.reber.watchhomecontrol`.
3. THE App ID used for both targets SHALL have the Keychain Sharing and App Groups capabilities enabled, and the provisioning profiles used by `release.sh` SHALL include them.
4. THE Shared_Sources SHALL be compiled into the Watch_App target, the Widget_Extension target, and the test target from a single copy of each file, with no duplicated or forked source files.
5. THE existing test target SHALL continue to build and run the full test suite after the Shared_Sources are added to the Widget_Extension target.
6. THE Watch_App SHALL declare the URL scheme `watchhomecontrol` so the Setup_Deep_Link resolves to the Watch_App.
