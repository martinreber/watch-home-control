# Implementation Plan: Apple Watch Home Control

## Overview

This plan implements **WatchHomeControl**, a standalone native watchOS app (Apple
Watch Ultra 2) built with SwiftUI, `@Observable`, Swift Concurrency, URLSession,
Keychain, and UserDefaults. No third-party runtime dependencies; property tests
use an established Swift property-testing library (SwiftCheck OR Swift Testing
parameterized/generator-driven tests).

The plan is test-driven and bottom-up: the pure, mockable core is built and
property-tested first (request building, DTO decoding, command mapping, URL
validation, time formatting), then persistence, then the `URLSession` client,
then the `@Observable` view models, then the SwiftUI views, and finally the app
entry point, routing, poll driver, and ATS configuration. Each step builds on the
previous ones and ends by wiring the new code into the app so nothing is orphaned.

All 19 correctness properties from the design map to exactly one property-based
test each, tagged `Feature: apple-watch-home-control, Property {number}: {property_text}`
and running a minimum of 100 iterations. Example, lifecycle, and smoke tests cover
routing, timing, and UI presence per the design's Testing Strategy.

## Tasks

- [x] 1. Scaffold the Xcode watchOS app project and folder structure
  - Create the `WatchHomeControl.xcodeproj` and `WatchHomeControl Watch App/` target for a standalone watchOS app (no iPhone companion)
  - Create the empty source-group folders per the design's Project Structure: `Models/`, `Networking/`, `Persistence/`, `State/`, `Views/`, `Utilities/`, plus `Strings.swift`
  - Create the `WatchHomeControlTests/` test target and select/link the chosen property-testing library (SwiftCheck OR Swift Testing generators); MUST use an existing library, MUST NOT implement property testing from scratch
  - Add a placeholder `WatchHomeControlApp.swift` `@main` App with a minimal `RootView` so the project builds
  - Verify the project builds for the watchOS Simulator
  - _Requirements: 11.1, 11.2_

- [x] 2. Define core data models and error types
  - [x] 2.1 Implement DTOs and enums in `Models/DTOs.swift`
    - Add `BlindAction` (`up`/`down`), `LampState`, `LampDTO` (with `friendly_name` mapping, optional `friendlyName`, and `displayName` fallback), `LampsResponse` (decodes both `{"lamps":[...]}` and bare `[...]`), `LampCommandResponse`, `SpeakerState`, `SpeakerDTO` (with `model_name` mapping and `isOn`), and `RadioRequest` (with the `radioBern1` default)
    - _Requirements: 4.2, 4.3, 5.2, 5.3, 5.4, 5.5, 6.1, 6.2, 7.5, 7.6, 8.1_
  - [x] 2.2 Implement UI row wrappers in `Models/Rows.swift`
    - Add `LampRow` (dto + `displayedPower` + `isPending`) and `SpeakerRow` (dto + `displayedState` + `isPending`), both `Identifiable`/`Equatable`
    - _Requirements: 6.3, 6.4, 8.4, 9.2, 9.3_
  - [x] 2.3 Implement error and feedback types in `Models/Errors.swift`
    - Add `APIError` (timeout/unauthorized/http/network/decoding), `SetupError` (emptyKey/keyTooLong/invalidURL), `Feedback`, and `HealthState`
    - _Requirements: 2.3, 3.3, 3.4, 4.6, 5.7, 6.5, 8.6_
  - [x] 2.4 Write property test: lamp list decodes identically from both shapes
    - **Property 3: The lamp list decodes identically from both response shapes**
    - Tag: `Feature: apple-watch-home-control, Property 3: The lamp list decodes identically from both response shapes`; min 100 iterations
    - **Validates: Requirements 5.2, 5.3**
  - [x] 2.5 Write property test: lamp display label falls back to id
    - **Property 4: Lamp display label falls back to id**
    - Tag: `Feature: apple-watch-home-control, Property 4: Lamp display label falls back to id`; min 100 iterations
    - **Validates: Requirements 5.4, 5.5**
  - [x] 2.6 Write property test: speaker toggle position is a pure function of playback state
    - **Property 5: Speaker toggle position is a pure function of playback state**
    - Tag: `Feature: apple-watch-home-control, Property 5: Speaker toggle position is a pure function of playback state`; min 100 iterations
    - **Validates: Requirements 7.5, 7.6**

- [x] 3. Implement request building (pure core)
  - [x] 3.1 Implement `Endpoint` enum in `Networking/Endpoint.swift`
    - Add cases: `health`, `blind(BlindAction)`, `lamps`, `lampState(id, power)`, `speakers`, `speakerPlay(id)`, `speakerPause(id)`, `speakerRadio(id, RadioRequest)`
    - _Requirements: 3.1, 4.2, 4.3, 6.1, 6.2, 8.1, 8.2, 8.3_
  - [x] 3.2 Implement `RequestBuilder` in `Networking/RequestBuilder.swift`
    - Pure `build(_:apiKey:) throws -> URLRequest` mapping each endpoint to URL/method/path/body; set `Content-Type: application/json` on body-bearing endpoints; attach `X-API-Key` on all endpoints except `.health`
    - _Requirements: 2.1, 3.1, 4.2, 4.3, 6.1, 6.2, 8.1, 8.2, 8.3, 11.1, 11.3_
  - [x] 3.3 Write property test: request building maps every endpoint correctly
    - **Property 1: Request building maps every endpoint to the correct URL, method, path, body, and Content-Type**
    - Tag: `Feature: apple-watch-home-control, Property 1: Request building maps every endpoint to the correct URL, method, path, body, and Content-Type`; min 100 iterations
    - **Validates: Requirements 4.2, 4.3, 6.1, 6.2, 11.1, 11.3**
  - [x] 3.4 Write property test: API key attached to exactly the authenticated endpoints
    - **Property 2: The API key is attached to exactly the authenticated endpoints**
    - Tag: `Feature: apple-watch-home-control, Property 2: The API key is attached to exactly the authenticated endpoints`; min 100 iterations
    - **Validates: Requirements 2.1, 3.1**

- [x] 4. Implement the speaker command mapper (pure core)
  - [x] 4.1 Implement `SpeakerToggleMapper` in `Models/DTOs.swift` (or a dedicated file)
    - Total function `command(toggleOn:current:) -> SpeakerCommand` returning `.radio(.radioBern1)` for on+stopped, `.play` for on+non-stopped, `.pause` for off
    - _Requirements: 8.1, 8.2, 8.3_
  - [x] 4.2 Write property test: speaker command mapping is a total function of (toggle, state)
    - **Property 8: Speaker command mapping is a total function of (toggle, state)**
    - Tag: `Feature: apple-watch-home-control, Property 8: Speaker command mapping is a total function of (toggle, state)`; min 100 iterations
    - **Validates: Requirements 8.1, 8.2, 8.3**

- [x] 5. Implement URL validation and time formatting utilities (pure core)
  - [x] 5.1 Implement `URLValidator` in `Utilities/URLValidator.swift`
    - `validate(_:) -> Result<URL, SetupError>` accepting only absolute http/https URLs with a host, else `.invalidURL`
    - _Requirements: 1.8_
  - [x] 5.2 Implement `ZurichTime` in `Utilities/ZurichTime.swift`
    - `hhmm(_:) -> String` formatting instants as 24-hour `HH:MM` in Europe/Zurich (CET/CEST per date); returns `"--:--"` for nil
    - _Requirements: 10.2, 10.3, 10.4_
  - [x] 5.3 Write property test: URL validation accepts valid http(s) URLs and rejects the rest
    - **Property 14: URL validation accepts valid http(s) URLs and rejects the rest**
    - Tag: `Feature: apple-watch-home-control, Property 14: URL validation accepts valid http(s) URLs and rejects the rest`; min 100 iterations
    - **Validates: Requirements 1.8**
  - [x] 5.4 Write property test: time formatting is Europe/Zurich, 24-hour HH:MM, placeholder for absent
    - **Property 19: Time formatting is Europe/Zurich, 24-hour HH:MM, with a placeholder for absent values**
    - Include the two Europe/Zurich DST boundary weekends in the generator range
    - Tag: `Feature: apple-watch-home-control, Property 19: Time formatting is Europe/Zurich, 24-hour HH:MM, with a placeholder for absent values`; min 100 iterations
    - **Validates: Requirements 10.2, 10.3, 10.4**

- [x] 6. Checkpoint - Ensure all core tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement persistence layer
  - [x] 7.1 Implement `SettingsStore` protocol + `LiveSettingsStore` in `Persistence/SettingsStore.swift`
    - Persist Base_URL string in UserDefaults; return default `http://192.168.1.122:8080` when absent or unparseable
    - _Requirements: 1.6, 1.7_
  - [x] 7.2 Implement `KeychainStore` protocol + `LiveKeychainStore` in `Persistence/KeychainStore.swift`
    - Wrap `SecItemAdd`/`SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete` for a single generic-password item (service `ch.reber.watchhomecontrol`, account `api_key`)
    - Provide an in-memory `KeychainStore` double for tests
    - _Requirements: 1.4, 2.2, 2.5_
  - [x] 7.3 Write property test: Base_URL persistence round-trips
    - **Property 13: Base_URL persistence round-trips**
    - Tag: `Feature: apple-watch-home-control, Property 13: Base_URL persistence round-trips`; min 100 iterations
    - **Validates: Requirements 1.6**
  - [x] 7.4 Write property test: API key save round-trips through the Keychain
    - **Property 15: API key save round-trips through the Keychain** (uses the in-memory store double)
    - Tag: `Feature: apple-watch-home-control, Property 15: API key save round-trips through the Keychain`; min 100 iterations
    - **Validates: Requirements 1.4, 2.5**
  - [x] 7.5 Write on-device/simulator Keychain integration test (optional)
    - Exercise the concrete `SecItem`-based `LiveKeychainStore` save/read/delete on the watchOS Simulator
    - _Requirements: 2.2_

- [x] 8. Implement the networking client
  - [x] 8.1 Define `APIClient` protocol in `Networking/APIClient.swift`
    - Declare `checkHealth`, `moveBlind`, `fetchLamps`, `setLampState`, `fetchSpeakers`, `playSpeaker`, `pauseSpeaker`, `playRadio`, each taking a `timeout: Duration`
    - _Requirements: 3.1, 4.1, 5.1, 6.1, 7.1, 8.1_
  - [x] 8.2 Implement `LiveAPIClient` in `Networking/LiveAPIClient.swift`
    - Build requests via `RequestBuilder` + a credential provider closure reading the Keychain; omit `X-API-Key` only on `checkHealth`
    - Enforce per-call timeout via `timeoutIntervalForRequest` + Task cancellation; map 401 → `.unauthorized`, other non-2xx → `.http`, transport → `.network`, decode failures → `.decoding`, timeout/cancel → `.timeout`
    - Decode `fetchLamps` via `LampsResponse`; decode command responses via `LampCommandResponse`/`SpeakerDTO`
    - _Requirements: 2.1, 3.1, 3.3, 3.4, 4.7, 5.7, 6.4, 6.6, 7.2, 8.5, 8.6, 11.3, 11.4, 11.5_
  - [x] 8.3 Write `URLProtocol`-stub integration test for `LiveAPIClient` (optional)
    - Verify header attachment, timeout mapping, and 401/non-2xx/decode error mapping via a stubbed `URLProtocol`
    - _Requirements: 2.1, 3.3, 3.4, 11.4_

- [x] 9. Implement the AppModel (routing, health, auth, poll driver)
  - [x] 9.1 Implement `AppModel` in `State/AppModel.swift`
    - `@MainActor @Observable`; hold `route`, `healthState`, `authErrorMessage`; inject `APIClient`, `KeychainStore`, `SettingsStore`
    - `onLaunch()` routes to Setup when no key, else runs health check; `submitSetup` validates key (1–256, reject empty/whitespace) and Base_URL, saving both; `openConfig` pre-fills current Base_URL; `handleAuthError` routes to Setup without mutating the stored key; `runHealthCheck` sends `GET /health` (5s, no key)
    - _Requirements: 1.1, 1.4, 1.5, 1.9, 1.10, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4_
  - [x] 9.2 Implement the poll driver in `AppModel`
    - Cancellable Task started when control view is active, cancelled when inactive/background; each 5s cycle fetches lamps + speakers (10s timeout) and hands results to the view models' `applyPoll`
    - _Requirements: 9.1, 9.4, 9.5, 9.6_
  - [x] 9.3 Write property test: an empty or whitespace key is rejected without disturbing the stored key
    - **Property 17: An empty or whitespace key is rejected without disturbing the stored key**
    - Tag: `Feature: apple-watch-home-control, Property 17: An empty or whitespace key is rejected without disturbing the stored key`; min 100 iterations
    - **Validates: Requirements 1.5**
  - [x] 9.4 Write property test: the API key is never persisted outside the Keychain
    - **Property 16: The API key is never persisted outside the Keychain**
    - Tag: `Feature: apple-watch-home-control, Property 16: The API key is never persisted outside the Keychain`; min 100 iterations
    - **Validates: Requirements 2.2**
  - [x] 9.5 Write property test: a 401 response never mutates the stored credential
    - **Property 18: A 401 response never mutates the stored credential**
    - Tag: `Feature: apple-watch-home-control, Property 18: A 401 response never mutates the stored credential`; min 100 iterations
    - **Validates: Requirements 2.3**
  - [x] 9.6 Write example tests for launch routing, health mapping, and auth routing
    - No key → Setup; key present → past Setup (Req 1.1, 1.9); 200 → reachable, 500/timeout/network → unreachable (Req 3.2–3.4); Auth_Error routes to Setup (Req 2.4)
    - _Requirements: 1.1, 1.9, 2.4, 3.2, 3.3, 3.4_

- [x] 10. Implement the BlindViewModel
  - [x] 10.1 Implement `BlindViewModel` in `State/BlindViewModel.swift`
    - `@MainActor @Observable`; `isPending`, `feedback`; `move(_:)` sets pending, sends `POST /blind` (10s), clears pending on completion, sets German success/error/timeout feedback
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_
  - [x] 10.2 Write example tests for the blind flow
    - Success → German success + cleared pending; error/timeout → German error + cleared pending + both controls re-enabled
    - _Requirements: 4.4, 4.5, 4.6, 4.7_

- [x] 11. Implement the LampViewModel
  - [x] 11.1 Implement `LampViewModel` in `State/LampViewModel.swift`
    - `@MainActor @Observable`; `lamps: [LampRow]`, `refreshFailed`; `activate()` loads via `GET /lamps` (10s); `toggle(id:on:)` optimistically sets, marks pending, sends `POST /lamps/{id}/state` (5s), applies returned `lamp.state` on success or reverts on failure/timeout; `applyPoll(_:)` merges preserving pending rows
    - _Requirements: 5.1, 5.6, 5.7, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 9.2_
  - [x] 11.2 Write property test: a successful command applies exactly the returned device state
    - **Property 9: A successful command applies exactly the returned device state** (lamp + speaker branches)
    - Tag: `Feature: apple-watch-home-control, Property 9: A successful command applies exactly the returned device state`; min 100 iterations
    - **Validates: Requirements 6.4, 8.5**
  - [x] 11.3 Write property test: a failed command restores the exact prior device state
    - **Property 10: A failed command restores the exact prior device state** (lamp + speaker branches)
    - Tag: `Feature: apple-watch-home-control, Property 10: A failed command restores the exact prior device state`; min 100 iterations
    - **Validates: Requirements 6.5, 6.6, 8.6**
  - [x] 11.4 Write property test: a failed refresh or poll leaves the displayed list unchanged
    - **Property 11: A failed refresh or poll leaves the displayed list unchanged** (lamp + speaker)
    - Tag: `Feature: apple-watch-home-control, Property 11: A failed refresh or poll leaves the displayed list unchanged`; min 100 iterations
    - **Validates: Requirements 5.7, 7.2, 7.3, 9.4, 9.5, 11.5**
  - [x] 11.5 Write property test: polling preserves pending rows and updates the rest
    - **Property 12: Polling preserves pending rows and updates the rest** (lamp + speaker)
    - Tag: `Feature: apple-watch-home-control, Property 12: Polling preserves pending rows and updates the rest`; min 100 iterations
    - **Validates: Requirements 9.2, 9.3**
  - [x] 11.6 Write example test for lamp empty-state and per-toggle pending
    - "Keine Lampen gefunden" on empty list (Req 5.6); toggling one lamp disables only that toggle (Req 6.3)
    - _Requirements: 5.6, 6.3_

- [x] 12. Implement the SpeakerViewModel
  - [x] 12.1 Implement `SpeakerViewModel` in `State/SpeakerViewModel.swift`
    - `@MainActor @Observable`; `speakers: [SpeakerRow]`, `refreshFailed`; `activate()` loads via `GET /sonos/speakers` (10s) preserving order; `toggle(id:on:)` uses `SpeakerToggleMapper` to pick radio/play/pause, marks pending, applies returned state on success or reverts on failure/timeout/no-state; disable offline speakers; `applyPoll(_:)` merges preserving pending rows
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 9.3_
  - [x] 12.2 Write property test: speaker order is preserved
    - **Property 6: Speaker order is preserved**
    - Tag: `Feature: apple-watch-home-control, Property 6: Speaker order is preserved`; min 100 iterations
    - **Validates: Requirements 7.4**
  - [x] 12.3 Write property test: offline speakers cannot issue commands
    - **Property 7: Offline speakers cannot issue commands**
    - Tag: `Feature: apple-watch-home-control, Property 7: Offline speakers cannot issue commands`; min 100 iterations
    - **Validates: Requirements 7.7**
  - [x] 12.4 Write example test for speaker empty-state and per-toggle pending
    - "Keine Lautsprecher gefunden" on empty list (Req 7.8); toggling one speaker disables only that toggle (Req 8.4)
    - _Requirements: 7.8, 8.4_

- [x] 13. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. Implement SwiftUI views
  - [x] 14.1 Implement `SetupView` in `Views/SetupView.swift`
    - Base_URL input pre-filled with default, API_Key input, validation + save; reused for config change and auth re-entry; German error messages for empty key and invalid URL
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.10, 2.4, 2.5_
  - [x] 14.2 Implement `BlindSection` in `Views/BlindSection.swift`
    - "Storen" section with "Hoch" and "Runter" controls, both disabled while pending, bound to `BlindViewModel`
    - _Requirements: 4.1, 4.4, 10.1_
  - [x] 14.3 Implement `LampListView` in `Views/LampListView.swift`
    - Lamp rows with `Toggle` reflecting `displayedPower`, `displayName` label, empty-state message, refresh-failed hint
    - _Requirements: 5.4, 5.6, 5.7, 6.3_
  - [x] 14.4 Implement `SpeakerListView` in `Views/SpeakerListView.swift`
    - Speaker rows in returned order with `Toggle` (on iff playing), offline speakers disabled, empty-state message, refresh-failed hint
    - _Requirements: 7.4, 7.5, 7.6, 7.7, 7.8, 8.4_
  - [x] 14.5 Implement `MessageBanner` in `Views/MessageBanner.swift`
    - Reusable non-blocking German feedback/error presentation
    - _Requirements: 2.3, 4.5, 4.6, 5.7, 6.5, 8.6, 9.5_
  - [x] 14.6 Implement `ControlView` in `Views/ControlView.swift`
    - `TabView`/scrolling `List` hosting the three sections plus a config affordance; wire German labels via `Strings.swift`
    - _Requirements: 1.10, 10.1_
  - [x] 14.7 Add German label constants in `Strings.swift`
    - Include at minimum "Storen", "Lampen", "Sonos", "Hoch", "Runter"
    - _Requirements: 10.1_

- [x] 15. Wire the app entry point, routing, and poll lifecycle
  - [x] 15.1 Implement `RootView` and app entry in `Views/RootView.swift` and `WatchHomeControlApp.swift`
    - `RootView` switches on `AppModel.route` (Setup vs Control), runs `onLaunch`, and drives poll start/stop from `@Environment(\.scenePhase)` (`.active` starts, `.inactive`/`.background` stops)
    - Construct `AppModel` with `LiveAPIClient`, `LiveKeychainStore`, `LiveSettingsStore` in `@main` App
    - _Requirements: 1.1, 1.9, 1.10, 3.1, 9.1, 9.6, 11.1_
  - [x] 15.2 Write poll/lifecycle tests with a controllable clock and mock client
    - Verify fetches issue on a 5s cadence while active (Req 9.1) and stop once inactive (Req 9.6)
    - _Requirements: 9.1, 9.6_

- [x] 16. Configure App Transport Security for cleartext LAN HTTP
  - [x] 16.1 Add ATS local-networking exception to `Info.plist`
    - Set `NSAppTransportSecurity` → `NSAllowsLocalNetworking` to permit cleartext HTTP to the LAN Base_URL
    - _Requirements: 11.2_
  - [x] 16.2 Write smoke tests for German labels and ATS/Setup presence
    - Assert the three sections render "Storen", "Lampen", "Sonos", "Hoch", "Runter" (Req 10.1); assert `Info.plist` contains the ATS local-networking exception (Req 11.2); assert Setup_Screen shows Base_URL and API_Key fields (Req 1.3)
    - _Requirements: 1.3, 10.1, 11.2_

- [x] 17. Final checkpoint - Ensure all tests pass and the app builds
  - Ensure all unit, property, and example/smoke tests pass and the app builds for the watchOS Simulator; ask the user if questions arise.
  - [x] 17.1 Run the app on the watchOS Simulator to sanity-check navigation (optional)
    - Manual simulator build/run verification of setup → control flow

- [x] 18. Adopt pairing-code onboarding (replaces manual API-key entry)
  - [x] 18.1 Add the redeem endpoint to request building
    - Add `Endpoint.redeem(code:)`; in `RequestBuilder` map it to `POST /pairing/redeem` with body `{"code": <code>}`, `Content-Type: application/json`, and NO `X-API-Key` header
    - _Requirements: 12.1_
  - [x] 18.2 Add the `PairingCodeResponse` DTO
    - `PairingCodeResponse { apiKey }` mapping `api_key`, in `Models/DTOs.swift`
    - _Requirements: 12.2_
  - [x] 18.3 Extend `APIClient`/`LiveAPIClient` with `redeemPairingCode`
    - Declare `redeemPairingCode(_:timeout:) async throws -> String`; implement in `LiveAPIClient` (10s timeout, no key header), decoding `PairingCodeResponse`; map 400→`malformedCode`, 401→`codeInvalid`, 429→`tooManyAttempts`, timeout→`redeemTimeout`, other→`redeemFailed`
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_
  - [x] 18.4 Update `SetupError` and rework `AppModel.submitSetup`
    - Replace `SetupError` cases per design; change `submitSetup(baseURL:code:)` to validate the 6-digit code, persist Base_URL, redeem, store the returned key in the Keychain on success, and map failures without mutating the stored key
    - _Requirements: 1.4, 1.5, 2.5, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7_
  - [x] 18.5 Convert `SetupView` to a Pairing_Code field
    - Replace the API_Key input with a 6-digit Pairing_Code input (numeric); keep Base_URL input; show German errors for malformed code / invalid URL / redeem failures; reuse for config change and re-pair after Auth_Error
    - _Requirements: 1.2, 1.3, 1.5, 1.8, 1.10, 2.4, 12.3, 12.4, 12.5_
  - [x] 18.6 Write property test: the redeem request carries the code body and no API key header
    - **Property 20: The redeem request carries the code body and no API key header**
    - Tag: `Feature: apple-watch-home-control, Property 20: The redeem request carries the code body and no API key header`; min 100 iterations
    - **Validates: Requirements 12.1**
  - [x] 18.7 Write property test: redeem failure statuses map to the correct Pairing_Error without mutating the stored key
    - **Property 21: Redeem failure statuses map to the correct Pairing_Error without mutating the stored key**
    - Tag: `Feature: apple-watch-home-control, Property 21: Redeem failure statuses map to the correct Pairing_Error without mutating the stored key`; min 100 iterations
    - **Validates: Requirements 12.3, 12.4, 12.5, 12.6**
  - [x] 18.8 Update rescoped property tests 15/16/17 to the pairing flow
    - Property 15 (successful redemption stores exactly the returned key), Property 16 (credential never outside Keychain + code not persisted), Property 17 (malformed code rejected, no redeem issued, stored key unchanged)
    - **Validates: Requirements 12.2, 12.7, 2.2, 1.5, 12.3**

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP; core
  implementation tasks and the 19 property tests are required by the design.
- Each task references specific requirement clauses and/or design properties for
  traceability.
- The pure/mockable core (RequestBuilder, DTO decoding, SpeakerToggleMapper,
  URLValidator, ZurichTime, view-model apply/revert/poll-merge) is built first so
  property tests can run without a device or Backend.
- Networking property tests use a `MockAPIClient`/stubbed `URLProtocol`; the
  Keychain round-trip property uses an in-memory `KeychainStore` double, while the
  concrete `SecItem` store is exercised by the optional on-device integration test.
- All 19 properties are implemented as exactly one property-based test each, tagged
  `Feature: apple-watch-home-control, Property {number}: ...` with a minimum of 100
  iterations.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "2.3", "5.1", "5.2", "7.1", "7.2"] },
    { "id": 2, "tasks": ["2.2", "3.1", "4.1", "5.3", "5.4", "7.3", "7.4", "7.5"] },
    { "id": 3, "tasks": ["2.4", "2.5", "2.6", "3.2", "4.2", "8.1"] },
    { "id": 4, "tasks": ["3.3", "3.4", "8.2"] },
    { "id": 5, "tasks": ["8.3", "9.1"] },
    { "id": 6, "tasks": ["9.2", "9.3", "9.4", "9.5", "9.6", "10.1", "11.1", "12.1"] },
    { "id": 7, "tasks": ["10.2", "11.2", "11.3", "11.4", "11.5", "11.6", "12.2", "12.3", "12.4"] },
    { "id": 8, "tasks": ["14.1", "14.2", "14.3", "14.4", "14.5", "14.7"] },
    { "id": 9, "tasks": ["14.6", "15.1"] },
    { "id": 10, "tasks": ["15.2", "16.1"] },
    { "id": 11, "tasks": ["16.2", "17.1"] },
    { "id": 12, "tasks": ["18.1", "18.2", "18.3", "18.4", "18.5", "18.6", "18.7", "18.8"] }
  ]
}
```
