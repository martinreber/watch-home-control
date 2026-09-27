# Implementation Plan: TV-Lampe Complication

## Overview

This plan implements the **TV-Lampe complication**: an `accessoryCircular` watch-face
widget that renders the label "TV" in green/red/grey and toggles the lamp through an
App Intent. It follows the design document in this folder.

The order is bottom-up and test-driven, and it is deliberately front-loaded with the
**entitlements and credential plumbing**: the shared Keychain access group and App
Group suite must be in place before anything else works on device, and getting the
access group wrong fails silently in the simulator (`LiveKeychainIntegrationTests`
skips on -34018). After that come the pure core types and their property tests, the
app-side refresh hooks, and finally the new widget extension target, whose WidgetKit
and AppIntents types are thin shells over already-tested logic.

All 8 correctness properties from the design map to exactly one property-based test
each, tagged `Feature: tv-lamp-complication, Property {number}: {property_text}` and
running a minimum of 100 iterations, using the existing Swift Testing + seeded-LCG
convention. Every task ends with the project building and the full suite passing.

## Tasks

- [ ] 1. Enable the shared-container capabilities on the app target
  - [ ] 1.1 Add `WatchHomeControl Watch App.entitlements` and wire `CODE_SIGN_ENTITLEMENTS`
    - Declare `keychain-access-groups` with `$(AppIdentifierPrefix)ch.reber.watchhomecontrol.shared`
    - Declare `com.apple.security.application-groups` with `group.ch.reber.watchhomecontrol`
    - Enable Keychain Sharing and App Groups on the App ID so `release.sh` can sign
    - _Requirements: 11.2, 11.3_
  - [ ] 1.2 Register the deep-link URL scheme in the app `Info.plist`
    - Add `CFBundleURLTypes` with the scheme `watchhomecontrol`
    - _Requirements: 11.6_
  - [ ] 1.3 Verify the app still builds and installs on the watch with the new entitlements
    - `WATCH_UDID=00008310-0008F86A3699A01E ./release.sh deploy`
    - _Requirements: 11.3_

- [ ] 2. Move the credential and the Base_URL into the shared containers
  - [ ] 2.1 Extend `LiveKeychainStore` with the shared access group and accessibility
    - Add `static let accessGroup = "5V4FMXSU55.ch.reber.watchhomecontrol.shared"` — fully qualified, because an explicitly supplied group is NOT auto-prefixed (-34018)
    - Add an `accessGroup: String?` initializer parameter (defaulting to the shared group; `nil` reaches the legacy default-group item)
    - Put `kSecAttrAccessGroup` into `baseQuery` and `kSecAttrAccessibleAfterFirstUnlock` into both the `SecItemAdd` and `SecItemUpdate` paths
    - Expose the built query to the test target so its shape can be asserted without touching the Security framework
    - _Requirements: 7.1, 7.2, 7.3_
  - [ ] 2.2 Write property test: Keychain queries carry the qualified access group and accessibility
    - **Property 5: Keychain queries always carry the qualified access group and accessibility**
    - Tag: `Feature: tv-lamp-complication, Property 5: Keychain queries always carry the qualified access group and accessibility`; min 100 iterations
    - **Validates: Requirements 7.1, 7.2, 7.3**
  - [ ] 2.3 Implement `Persistence/BaseURLResolver.swift`
    - Add `BaseURLResolution` (`.configured(URL)`, `.fallbackDefault(URL)`, `.invalid`) and the pure `resolve(_ raw: String?)` built on `URLValidator`
    - `nil`/blank → `.fallbackDefault(defaultBaseURL)`; valid → `.configured`; anything else → `.invalid`
    - _Requirements: 3.9, 7.7, 8.2_
  - [ ] 2.4 Write property test: Base_URL resolution classifies absent, valid, and invalid values
    - **Property 3: Base_URL resolution classifies absent, valid, and invalid values**
    - Tag: `Feature: tv-lamp-complication, Property 3: Base_URL resolution classifies absent, valid, and invalid values`; min 100 iterations
    - **Validates: Requirements 3.9, 7.7, 8.2**
  - [ ] 2.5 Point `LiveSettingsStore` at the App Group suite and the resolver
    - Add `static let appGroupID = "group.ch.reber.watchhomecontrol"` and `static var sharedDefaults`
    - Default the initializer to the shared suite; read/write `base_url` there only, never in `UserDefaults.standard`
    - Implement `baseURL` through `BaseURLResolver`, mapping `.invalid` to the default so app behaviour is unchanged
    - _Requirements: 7.4, 7.6, 7.7_
  - [ ] 2.6 Implement `Persistence/LegacyStatePurge.swift` (no migration)
    - `runIfNeeded(sharedDefaults:standardDefaults:legacyKeychain:)` deletes the legacy default-group Keychain item, removes `base_url` from `UserDefaults.standard`, and sets `legacy_state_purged_shared_v1` in the shared suite
    - Idempotent, at most once per install; a credential paired afterwards is never touched
    - _Requirements: 7.9, 7.10_
  - [ ] 2.7 Write example tests for the legacy purge
    - Purges on first call, is a no-op on the second, and leaves a newly stored credential intact
    - **Validates: Requirements 7.9, 7.10**

- [ ] 3. Build the pure complication core in `Complication/`
  - [ ] 3.1 Add `Complication/ComplicationTiming.swift`
    - `providerTimeout = .seconds(5)`, `commandTimeout = .seconds(10)`, `refreshInterval = .seconds(10)`, and `ComplicationKind.tvLamp`
    - _Requirements: 3.10, 8.8_
  - [ ] 3.2 Add `Complication/TVLampSelector.swift`
    - `TVLampResolution` (`.resolved(LampDTO)` / `.unresolved`) and the pure `select(from:)` matching `displayName` containing "TV-Lampe" case-insensitively, first match wins
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 10.1_
  - [ ] 3.3 Write property test: TV-Lampe selection returns the first match or nothing
    - **Property 1: TV-Lampe selection returns the first case-insensitive "TV-Lampe" match or nothing**
    - Tag: `Feature: tv-lamp-complication, Property 1: TV-Lampe selection returns the first case-insensitive "TV-Lampe" match or nothing`; min 100 iterations
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5, 10.1**
  - [ ] 3.4 Add `Complication/ComplicationState.swift`
    - `PairingCondition`, `ComplicationState` (`.on`/`.off`/`.unknown`), the total `resolve(pairing:resolution:)`, and the pure `labelColor` (green/red/grey)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 10.2, 10.3_
  - [ ] 3.5 Write property test: complication state mapping is total and pure
    - **Property 2: Complication state mapping is total and pure**
    - Tag: `Feature: tv-lamp-complication, Property 2: Complication state mapping is total and pure`; min 100 iterations
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 10.2, 10.3**
  - [ ] 3.6 Write property test: complication requests are built by the shared builder
    - **Property 4: Complication requests are built by the shared builder with the key and body**
    - Asserts `GET /lamps` and `POST /lamps/{id}/state` produced via `RequestBuilder` carry the method, path, `X-API-Key`, `Content-Type: application/json`, and `{"power": …}` body
    - Tag: `Feature: tv-lamp-complication, Property 4: Complication requests are built by the shared builder with the key and body`; min 100 iterations
    - **Validates: Requirements 8.5, 8.6, 8.9, 10.4**
  - [ ] 3.7 Add the complication strings to `Strings.swift`
    - `complicationLabel = "TV"`, `complicationDisplayName = "TV-Lampe"`, `complicationDescription` (German)
    - _Requirements: 9.1, 9.2, 9.3_

- [ ] 4. Implement the reload seam and the throttled publisher
  - [ ] 4.1 Add `Complication/ComplicationRefreshing.swift`
    - Protocol `ComplicationRefreshing`, `LiveComplicationRefresher` wrapping `WidgetCenter.shared.reloadTimelines(ofKind:)`, and `SpyComplicationRefresher` counting calls for tests
    - _Requirements: 10.6_
  - [ ] 4.2 Add `Complication/ComplicationPublisher.swift`
    - `publish(tvLampPower:)` reloads only on a change and at most once per `refreshInterval`, holding a too-early change as pending until the interval elapses
    - `publishImmediately()` bypasses the change check and the throttle
    - Inject `now` so the throttle is testable without sleeping
    - _Requirements: 3.14, 7.11, 7.12, 7.13_
  - [ ] 4.3 Write property test: foreground refresh fires only on change and at most once per interval
    - **Property 7: Foreground refresh is emitted only on change and at most once per interval**
    - Tag: `Feature: tv-lamp-complication, Property 7: Foreground refresh is emitted only on change and at most once per interval`; min 100 iterations
    - **Validates: Requirements 3.14, 7.12, 7.13**

- [ ] 5. Implement the setup deep link and app-side routing
  - [ ] 5.1 Add `Utilities/DeepLink.swift`
    - `scheme`, `setupHost`, `setupURL`, and the pure `isSetup(_:)` comparing scheme and host case-insensitively
    - _Requirements: 6.2, 11.6_
  - [ ] 5.2 Write property test: only the setup deep link is accepted
    - **Property 8: Only the setup deep link is accepted**
    - Tag: `Feature: tv-lamp-complication, Property 8: Only the setup deep link is accepted`; min 100 iterations
    - **Validates: Requirements 6.2, 6.3, 11.6**
  - [ ] 5.3 Route the deep link into the Setup screen
    - Add `AppModel.openSetupFromComplication()`: stop polling, refresh `baseURLField`, set `route = .setup` unconditionally
    - Add `.onOpenURL` to `RootView` calling it when `DeepLink.isSetup(url)`
    - _Requirements: 6.3, 6.4_
  - [ ] 5.4 Write example tests for complication-initiated routing
    - Routes to `.setup` from `.control` and from `.setup`, stops polling, and ignores unrelated URLs
    - **Validates: Requirements 6.3, 6.4**

- [ ] 6. Implement the timeline entry and the entry loader
  - [ ] 6.1 Add `Complication/TVLampEntry.swift`
    - `TVLampEntry: TimelineEntry` with `date`, `state`, and `interaction` (`.toggle` / `.openSetup`)
    - _Requirements: 3.3, 5.1, 5.11_
  - [ ] 6.2 Add `Complication/ComplicationEnvironment.swift`
    - `readAPIKey`, `resolveBaseURL`, `api`, `refresher`, `now` closures/values plus the `.live` composition root built from `LiveKeychainStore`, `LiveSettingsStore`, `LiveAPIClient`, `LiveComplicationRefresher`
    - _Requirements: 7.1, 7.4, 10.6_
  - [ ] 6.3 Add `Complication/TVLampEntryLoader.swift`
    - `placeholder()` — no I/O, representative entry
    - `load()` — unpaired → `(.unknown, .openSetup)` with no request; `.invalid` Base_URL → `.unknown` with no request; otherwise `fetchLamps(timeout: providerTimeout)` mapped through `TVLampSelector` + `ComplicationState.resolve`; timeout, 401, transport, non-2xx, empty, and no-match all → `.unknown`
    - Never throws, never writes to the Keychain
    - _Requirements: 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.15, 6.1, 6.6, 7.8, 8.2, 8.7_
  - [ ] 6.4 Write example tests for every loader branch
    - Unpaired and invalid-URL branches assert **zero** API calls; on/off; timeout; 401 leaves the stored key untouched; non-2xx; network error; empty list; no match
    - **Validates: Requirements 3.3–3.9, 3.15, 6.1, 6.6, 8.2**

- [ ] 7. Implement the read-then-toggle service
  - [ ] 7.1 Add `Complication/TVLampToggleService.swift`
    - `run()` performs `GET /lamps` → `POST /lamps/{id}/state` with the inverted power → `GET /lamps` read-back, then exactly one `refresher.reload()`
    - Never derives the command from a timeline entry; `.unresolved` sends no `POST`; timeout/error/401 abort the remaining steps, reload, and leave the credential untouched
    - Return the `Outcome` enum (`.toggled`, `.readBackFailed`, `.unresolved`, `.unpaired`, `.failed`) for tests
    - _Requirements: 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 3.13_
  - [ ] 7.2 Write property test: the toggle service reads, inverts, and reads back
    - **Property 6: The toggle service reads, inverts, and reads back, never trusting the entry**
    - Tag: `Feature: tv-lamp-complication, Property 6: The toggle service reads, inverts, and reads back, never trusting the entry`; min 100 iterations
    - **Validates: Requirements 5.2, 5.3, 5.4, 5.5, 5.6, 10.7**
  - [ ] 7.3 Write example tests for every toggle outcome
    - `.toggled`, `.readBackFailed`, `.unresolved`, `.unpaired`, `.failed` — each asserting the ordered endpoint sequence and exactly one reload
    - **Validates: Requirements 5.5–5.9, 10.7**

- [ ] 8. Wire the app to keep the complication fresh
  - [ ] 8.1 Update the composition root in `WatchHomeControlApp.init()`
    - Run `LegacyStatePurge.runIfNeeded()` first, then build `LiveSettingsStore()` (shared suite), `LiveKeychainStore()` (shared group), the `ComplicationPublisher`, and `AppModel`
    - _Requirements: 7.4, 7.9, 7.10_
  - [ ] 8.2 Add the publisher hooks to `AppModel`
    - `publishImmediately()` after a successful pairing, after credential deletion, in `handleAuthError()`, and after `settings.setBaseURL`
    - In each Poll_Cycle, call `publish(tvLampPower:)` with the TV-Lampe power resolved from the fetched lamps (`nil` when unresolved)
    - _Requirements: 6.4, 6.5, 7.11, 7.12_
  - [ ] 8.3 Publish from `LampViewModel` after a successful lamp command
    - Forward the updated TV-Lampe power so an in-app toggle reaches the face without waiting for the next poll
    - _Requirements: 7.11, 7.12_
  - [ ] 8.4 Write example tests for the app-side refresh hooks
    - Pairing, auth error, and Base_URL change each publish immediately; an unchanged poll publishes nothing; a changed poll publishes once
    - **Validates: Requirements 6.4, 6.5, 7.11, 7.12, 7.13**

- [ ] 9. Create the widget extension target
  - [ ] 9.1 Add the `WatchHomeControlComplication` widget extension target
    - watchOS Widget Extension embedded in the watch app; bundle id `ch.reber.watchhomecontrol.watchkitapp.complication`; watchOS 11.0; Swift 6; team `5V4FMXSU55`
    - _Requirements: 11.1_
  - [ ] 9.2 Add the extension entitlements and `Info.plist`
    - Same `keychain-access-groups` and `com.apple.security.application-groups` values as the app; `NSAppTransportSecurity` / `NSAllowsLocalNetworking`; `NSExtensionPointIdentifier = com.apple.widgetkit-extension`
    - _Requirements: 8.3, 8.4, 11.2, 11.3_
  - [ ] 9.3 Add the shared sources to the extension target by membership
    - `Models/`, `Networking/`, `Persistence/`, `Utilities/URLValidator.swift`, `Utilities/DeepLink.swift`, `Strings.swift`, and all of `Complication/` — one copy of each file, no forks
    - Do NOT add `State/`, `Views/`, or `WatchHomeControlApp.swift`
    - Confirm the existing test suite still builds and passes afterwards
    - _Requirements: 11.4, 11.5_

- [ ] 10. Implement the WidgetKit and AppIntents shells
  - [ ] 10.1 Add `TVLampComplicationView`
    - Always renders `Strings.complicationLabel`; applies `ComplicationState.labelColor` only when `widgetRenderingMode == .fullColor`, and still renders the label in other modes
    - Applies `.containerBackground(.clear, for: .widget)`
    - `.toggle` wraps the label in `Button(intent: ToggleTVLampIntent())`; `.openSetup` applies `.widgetURL(DeepLink.setupURL)`
    - _Requirements: 1.3, 1.4, 1.5, 2.6, 5.1, 5.11, 6.2, 9.3_
  - [ ] 10.2 Add `ToggleTVLampIntent`
    - One-line `perform()` delegating to `TVLampToggleService(env: .live).run()`; `openAppWhenRun = false`; not discoverable in Shortcuts
    - _Requirements: 5.1, 5.10_
  - [ ] 10.3 Add `TVLampTimelineProvider`
    - `placeholder`/`getSnapshot` return `loader.placeholder()` with no network; `getTimeline` returns exactly one entry dated now with `.after(now + refreshInterval)` and no pre-computed future entries
    - _Requirements: 3.1, 3.2, 3.10, 3.11, 3.12, 3.15_
  - [ ] 10.4 Add `TVLampWidget` and the `@main` widget bundle
    - `StaticConfiguration` with `ComplicationKind.tvLamp`; `supportedFamilies([.accessoryCircular])`; German display name and description from `Strings`
    - _Requirements: 1.1, 1.2, 1.7, 9.2_
  - [ ] 10.5 Write smoke tests for the complication view and strings
    - The view builds for `.on`, `.off`, `.unknown` in both interaction modes; `labelColor` is pairwise distinct; the complication strings are non-empty and German
    - **Validates: Requirements 1.3, 2.5, 2.6, 9.1, 9.2, 9.3**

- [ ] 11. Verify on device
  - [ ] 11.1 Deploy the app plus the embedded extension and add the complication to the watch face
    - `WATCH_UDID=00008310-0008F86A3699A01E ./release.sh deploy`; confirm "TV-Lampe" appears in the gallery and occupies the bottom-middle slot
    - _Requirements: 1.1, 1.2, 11.1_
  - [ ] 11.2 Confirm pairing, colour, and toggling end to end
    - Re-pair after the legacy purge; the label turns green/red within one poll cycle; tapping with the app closed switches the lamp and the colour follows the read-back
    - _Requirements: 2.1, 2.2, 5.1, 5.3, 5.4, 7.9_
  - [ ] 11.3 Confirm the locked-watch and unpaired paths
    - With the watch locked, a background refresh must not fall back to grey (proves `kSecAttrAccessibleAfterFirstUnlock`); after deleting the credential, the label is grey and a tap opens the Einrichtung screen
    - _Requirements: 6.1, 6.2, 6.3, 7.3_
  - [ ] 11.4 Watch for `errSecMissingEntitlement` (-34018)
    - If the complication is grey while the app is paired, the access group or entitlement is wrong — the simulator cannot catch this because `LiveKeychainIntegrationTests` skips on -34018
    - _Requirements: 7.1, 7.2, 11.2, 11.3_
