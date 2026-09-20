# Code Review — WatchHomeControl (Apple Watch Ultra 2)

**Scope:** the standalone watchOS app under `WatchHomeControl Watch App/`, its
tests, project configuration, and `release.sh`. Reviewed against maintainability,
documentation, security, enhanceability, and Swift/Apple-platform best practices.

**Overall:** this is a well-architected, cleanly layered SwiftUI app. The design
is genuinely testable (pure core behind protocols), the networking layer is
robust, and the code is unusually well documented. The test suite — previously
the single biggest gap — is now **fully implemented**: all of the design's
property-based tests plus example, integration, and smoke tests are present and
green. The remaining gaps are (1) a few security hardening opportunities, (2) UI
accessibility labels, and (3) minor repo/build hygiene (leftover placeholder
files and committed per-user Xcode state).

_Last updated after completing the spec's implementation plan (all 80 tasks in
`2026-09-17_apple-watch-home-control/tasks.md` done; full test suite added and
passing on the watchOS Simulator)._

---

## Summary Scorecard

| Area | Rating | Headline |
|------|--------|----------|
| Architecture & maintainability | Strong | Clean layering, protocol seams, small focused types |
| Documentation | Strong | Thorough file/type/method docs; requirement traceability |
| Testing | Strong | Full property + example + integration + smoke suite, all passing |
| Security | Good, with gaps | Keychain-only key; missing `kSecAttrAccessible`, cleartext LAN HTTP |
| Enhanceability | Good | Easy to add endpoints/screens; a few coupling points to watch |
| Apple/Swift best practices | Strong | Modern concurrency, `@Observable`, Swift 6 `Sendable` discipline |

---

## Strengths

- **Layering is disciplined.** Pure core (`Models`, `Networking/RequestBuilder`,
  `Utilities`) has no I/O; I/O edges (`LiveAPIClient`, `KeychainStore`,
  `SettingsStore`) sit behind `protocol`s; view models orchestrate; views are
  declarative. This is the right shape for a testable app — and it paid off:
  the whole suite runs offline against in-memory doubles and a `URLProtocol`
  stub, no device required.
- **Networking is robust.** `LiveAPIClient` funnels every failure into a single
  normalized `APIError`, applies a per-call `Duration` timeout both via
  `timeoutIntervalForRequest` and a structured `withThrowingTaskGroup`
  cancellation guard, and maps 401 distinctly so re-pairing can trigger. Reading
  the API key and Base_URL fresh per request (via closures/stores) is a clean way
  to make config/credential changes take effect immediately.
- **Optimistic UI with correct revert.** `LampViewModel` / `SpeakerViewModel`
  capture the exact prior row, apply the server-returned state on success, and
  revert verbatim on failure, re-resolving the row by id in case a poll reordered
  the list mid-flight. The poll-merge preserves pending rows. This is subtle
  concurrency handled correctly — and now locked down by property tests
  (Properties 9–12).
- **Concurrency hygiene is modern and correct.** View models are
  `@MainActor @Observable`; the client is `Sendable` with a `@Sendable`
  credential provider; `InMemoryKeychainStore` locks its state. This is
  idiomatic Swift 6.
- **Documentation is a standout.** Nearly every file, type, and method has a
  doc comment explaining intent and (usefully) tracing to requirement numbers.
  The tests carry the same discipline: each property test's header names the
  design property and the requirement IDs it validates.
- **Composition root is explicit.** `WatchHomeControlApp` builds the whole
  dependency graph in one place (`LiveSettingsStore`, `LiveKeychainStore`,
  `LiveAPIClient`, `AppModel`) and injects it into `RootView`, with no
  environment-based seeding — the simulator and device both go through the
  normal Einrichtung pairing flow.

---

## Findings by Area

### 1. Testing — Strong (resolved)

The suite is now comprehensive. `WatchHomeControlTests/` contains ~26 test
files: the design's property-based tests, plus example (unit), integration, and
smoke tests. All run offline (no device, no live backend) using
`InMemoryKeychainStore`, in-memory `SettingsStore`, mock `APIClient` doubles, and
a stub `URLProtocol`. They are executed via `./release.sh test` against a warm
watchOS Simulator with a pinned derived-data path so incremental builds are
reused. Every property test runs >=100 deterministic (seeded) iterations, using
Swift Testing's generator-driven approach — no third-party dependency and no
hand-rolled property engine.

Coverage highlights (design property -> test file):

- **Request building** — `RequestBuilderPropertyTests` (P1),
  `APIKeyAttachmentPropertyTests` (P2), `RedeemRequestShapePropertyTests` (P20:
  redeem carries the code body and no `X-API-Key`).
- **DTO decoding / display** — `LampsResponsePropertyTests` (P3: both response
  shapes), `LampDisplayNamePropertyTests` (P4: id fallback).
- **Speaker logic** — `SpeakerTogglePositionPropertyTests` (P5),
  `SpeakerOrderPreservedPropertyTests` (P6),
  `OfflineSpeakerNoCommandPropertyTests` (P7),
  `SpeakerCommandMapperPropertyTests` (P8: mapper totality).
- **Optimistic UI + poll merge** —
  `SuccessfulCommandAppliesReturnedStatePropertyTests` (P9),
  `FailedCommandRestoresPriorStatePropertyTests` (P10),
  `FailedRefreshLeavesListUnchangedPropertyTests` (P11),
  `PollingPreservesPendingRowsPropertyTests` (P12).
- **Persistence** — `SettingsStorePropertyTests`,
  `KeychainRoundTripPropertyTests`, and an on-simulator
  `LiveKeychainIntegrationTests`.
- **Utilities** — `URLValidatorPropertyTests`, `ZurichTimePropertyTests`.
- **Pairing / credentials** — `EmptyKeyRejectedPropertyTests` (P17: malformed/
  empty code rejected without disturbing the stored key),
  `CredentialNotPersistedPropertyTests` (P16: key lives only in the Keychain),
  `AuthError401PropertyTests` (P18: a 401 never mutates the stored credential),
  `RedeemFailureMappingPropertyTests` (P21: redeem status -> `SetupError`).
- **Example / integration** — `AppModelRoutingExampleTests` (launch/health/auth
  routing), `BlindFlowExampleTests`, `LampFlowExampleTests`,
  `SpeakerFlowExampleTests` (empty-state + per-toggle pending isolation),
  `PollLifecycleExampleTests` (poll driver start/stop/idempotence/401),
  `LiveAPIClientStubTests` (timeout/status/decode mapping via `URLProtocol`),
  and `SmokeTests` (German label presence + ATS `NSAllowsLocalNetworking`).

**Follow-ups (minor):**
- The poll cadence is verified behaviorally (the first cycle runs immediately;
  "no further cycle" is asserted within a bounded yield window) because the loop
  sleeps with `Task.sleep(for:)` and has no injectable clock. If cadence-exact
  assertions ever matter, introduce a `Clock`/sleep seam in `AppModel` so the
  5s interval can be tested deterministically without wall-clock waits.
- Some `LiveAPIClient` body-bearing POST assertions are made at the
  `RequestBuilder` boundary rather than through the stub, because a custom
  `URLProtocol` on watchOS does not reliably intercept requests carrying an
  `httpBodyStream`. This is documented in `LiveAPIClientStubTests` and is a
  platform limitation, not a coverage gap.

### 2. Security — Good, with concrete gaps

- **Good:** the API key lives only in the Keychain (never UserDefaults, never
  logged) — now enforced by `CredentialNotPersistedPropertyTests`, which scans
  everything the settings store persists and asserts neither the key nor the
  code leaks. A 401 routes to re-pairing without deleting the stored key
  (`AuthError401PropertyTests`); the Base_URL/key are read fresh per request; the
  pairing code is single-use and short-lived on the backend, and the redeem path
  returns a uniform 401 so callers cannot distinguish failure reasons.
- **Gap — Keychain accessibility not set (still open).** `LiveKeychainStore`
  does not set `kSecAttrAccessible`, so the item defaults to
  `kSecAttrAccessibleWhenUnlocked`. Recommend setting it explicitly to
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (or
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` if background access is ever
  needed). `ThisDeviceOnly` prevents the credential from migrating via backups.
- **Gap — cleartext HTTP (accepted, document it).** The default Base_URL is
  `http://…:8080` and `Info.plist` sets `NSAllowsLocalNetworking`, permitting
  cleartext on the LAN (a smoke test now asserts this exception is present). This
  is a reasonable pragmatic choice for a home LAN backend, but it means the API
  key is sent in plaintext over the local network. Document this explicitly as an
  accepted risk, and consider a path to TLS (self-signed cert pinned, or a
  reverse proxy) if the threat model ever includes an untrusted LAN. A related
  `tls-https-encryption` spec exists in the `home-control` backend repo.
- **Note — `network(String)` carries `error.localizedDescription`.** Low risk,
  but be mindful this can surface system-level detail into UI/feedback; it is
  currently only used for a generic German banner, so acceptable.

### 3. Maintainability — Strong, minor cleanups

- **Repo/build hygiene (partly fixed).**
  - `WatchHomeControl Watch App/State/AppModel.swift.new` — the stray scratch
    file (which the build was copying into the `.app`) has been **removed from
    the working tree**. It is still tracked in git, so the deletion needs to be
    committed and the reference removed from the target to keep it out of future
    builds.
  - `WatchHomeControl Watch App/State/StatePlaceholder.swift` and
    `Utilities/UtilitiesPlaceholder.swift` — empty-group placeholders that are no
    longer needed now that the groups have real files; **still present**, safe to
    delete.
  - `…/project.xcworkspace/xcuserdata/…/UserInterfaceState.xcuserstate` — per-user
    Xcode UI state; **still tracked**. Should be git-ignored, not committed.
- **No linter/formatter config.** Style is consistent by hand, but adding a
  `.swiftlint.yml` or `swift-format` config would keep it that way as the app
  grows and make CI enforcement possible later.
- **`Strings.apiKeyLabel` is dead (still present).** The setup screen moved to a
  pairing code (`pairingCodeLabel`); the `API-Key` label constant appears unused.
  Trim to avoid confusion.
- **Duplication across the two list view models.** `LampViewModel` and
  `SpeakerViewModel` share near-identical activate/toggle/applyPoll/revert
  shapes. Acceptable today (each has small domain differences), but if a third
  list appears, extract a generic "optimistic list" helper.

### 4. Enhanceability — Good

- **Adding an endpoint is a well-worn path:** add an `Endpoint` case, map it in
  `RequestBuilder`, add a method to `APIClient`/`LiveAPIClient`. The steering docs
  capture this, and the request-mapping property test will immediately cover a
  new case's URL/method/body/header shape.
- **`JSONDecoder` is constructed per decode call** in `LiveAPIClient.decode`.
  Negligible cost here, but a single shared decoder is marginally cleaner and a
  natural place to centralize date/key strategies if the contract grows.
- **`RadioRequest.radioBern1` hardcodes a station.** Fine for now; if stations
  become user-selectable this should move to configuration.
- **Poll cadence (5s) and timeouts are literals** in view models / `AppModel`.
  Consider centralizing these as named constants (or a small `Timeouts` type) so
  tuning is one edit — and, paired with a clock seam, cadence-exact tests become
  possible.

### 5. Apple / Swift Best Practices — Strong

- Modern stack used correctly: SwiftUI, `@Observable`, `@State`-owned root model,
  `scenePhase`-driven poll lifecycle in `RootView`, Swift Concurrency with
  structured cancellation, and Swift 6 `Sendable` conformances.
- **Accessibility is missing (should add).** No `accessibilityLabel` /
  `accessibilityValue` / `accessibilityHint` anywhere in `Views/`. On watchOS,
  VoiceOver users benefit from explicit labels on the blind buttons, the lamp/
  speaker toggles (state + pending), and the number-pad keys. This is the clearest
  best-practice gap in the UI layer.
- **Number-pad entry (`CodePad`)** correctly works around the watchOS limitation
  that `TextField` cannot be forced numeric. Good, pragmatic. Consider a
  Digital Crown affordance as an alternative input for accessibility.
- **Localization is centralized in `Strings.swift`** (good), and a smoke test now
  guards the key German strings against accidental regressions. Strings are Swift
  constants, not a `.strings`/String Catalog. Since the app is German-only by
  design this is acceptable; if localization is ever wanted, migrating to a String
  Catalog (`.xcstrings`) is the Apple-recommended path.
- **Previews are stubbed to `EmptyView()`.** Wiring an in-memory `APIClient`
  double into previews would restore SwiftUI preview value for the list views —
  the same doubles the tests already use.

---

## Prioritized Recommendations

**High**
1. Commit the `AppModel.swift.new` removal and drop it from the target;
   untrack `UserInterfaceState.xcuserstate` and add it to `.gitignore`.
2. Set an explicit `kSecAttrAccessible…ThisDeviceOnly` on the Keychain item.

**Medium**
3. Add accessibility labels/values to the interactive controls and pad keys.
4. Document the cleartext-HTTP decision as an accepted risk; plan a TLS path
   (coordinated with the backend `tls-https-encryption` spec).
5. Delete unused placeholders and the dead `apiKeyLabel`; add a SwiftLint/
   swift-format config.

**Low**
6. Centralize timeouts/poll cadence as named constants; add a clock seam to
   `AppModel` so poll cadence can be tested deterministically.
7. Share a single `JSONDecoder`; wire in-memory previews for the list views.
8. If a third device list appears, extract a shared optimistic-list helper.

---

## Notable Files Reviewed

- `Networking/LiveAPIClient.swift` — timeout/cancellation + error mapping (strong)
- `Networking/RequestBuilder.swift`, `Endpoint.swift` — pure request mapping (strong)
- `Persistence/KeychainStore.swift` — Keychain wrapper (good; add accessibility attr)
- `State/AppModel.swift` — routing, health, pairing, poll driver (strong)
- `State/LampViewModel.swift`, `SpeakerViewModel.swift` — optimistic UI (strong)
- `Views/SetupView.swift` — pairing + `CodePad` numeric entry (good)
- `Models/DTOs.swift`, `Errors.swift` — lenient decoding, normalized errors (strong)
- `WatchHomeControlTests/` — full property + example + integration + smoke suite,
  all passing (strong); see the Testing section for the property->file map

_Review is code-and-config level; it does not include runtime/on-device
verification (e.g. VoiceOver behavior, live network failure injection) or a
formal threat model. The automated suite runs on the watchOS Simulator; the
final interactive navigation sanity-check (tapping through Storen/Lampen/Sonos
and the Einrichtung flow) remains a manual step._
