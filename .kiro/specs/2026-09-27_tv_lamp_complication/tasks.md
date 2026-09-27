# Tasks: TV-Lampe App Shortcut

## Overview

Change the existing `accessoryCircular` complication from a status/toggle widget into
a static app launcher. A tap opens the full WatchHomeControl app at the existing
Lampen controls. No widget-side network, state, App Intent, or refresh scheduling is
needed.

## Tasks

- [x] 1. Make the complication a static launcher
  - [x] Show a neutral lamp glyph and the shared "TV" label in the circular family
  - [x] Add `widgetURL(DeepLink.lampsURL)`; remove the Toggle App Intent from the widget
  - [x] Return a static timeline with no network request and no periodic reload
  - _Requirements: 1.1–1.6, 5.1–5.3_

- [x] 2. Route the lamps deep link into the app
  - [x] Add `watchhomecontrol://lamps` recognition to `DeepLink`
  - [x] Route paired launches to Control; route unpaired launches to Einrichtung
  - [x] Keep the existing Setup deep link working
  - _Requirements: 2.1–2.4, 4.1–4.4_

- [x] 3. Focus the existing Lampen section
  - [x] Add an observable focus-request counter to `AppModel` so repeated taps are handled even when Control is already visible
  - [x] Wrap the Control list in `ScrollViewReader`, identify the Lampen section, and scroll to it on appearance or a new focus request
  - [x] Continue using the existing `LampViewModel` and row Toggle for lamp control
  - _Requirements: 2.2, 2.4, 3.1–3.4_

- [x] 4. Remove obsolete status/toggle/refresh integration
  - [x] Remove the complication Toggle intent, read-then-toggle service, entry loader, state mapping, polling publisher, and WatchKit app-refresh scheduler
  - [x] Remove AppModel/LampViewModel hooks that only reloaded the former status widget
  - [x] Exclude app-only networking, persistence, models, state, and views from the extension target's synchronized source membership
  - _Requirements: 1.4–1.6, 3.4, 6.3, 7.3_

- [x] 5. Update tests and specifications
  - [x] Test case-insensitive lamps/setup deep-link recognition
  - [x] Test paired routing, repeated Lampen focus requests, and unpaired Setup routing
  - [x] Update the requirements and design documents to specify launcher-only behavior
  - _Requirements: 4.1–4.4, 6.1–6.4_

- [ ] 6. Verify the new launch flow on the paired watch
  - Progress: launcher build deployed successfully. `watchhomecontrol://lamps` was delivered to the newly installed app with `devicectl`; the captured watch screen showed the TV-Lampe row at the top of Control. The simulator suite passed with 86 tests in 36 suites, and the extension built.
  - [x] Rebuild/install the app and embedded extension on the watch
  - [ ] Confirm the widget shows no power/status color
  - [x] Open the paired app with the complication's lamps URL and confirm the Lampen section is in view
  - [x] Verify that repeated lamps URLs issue a new focus request while Control is already open (routing unit test)
  - [ ] Confirm a tap while unpaired opens Einrichtung

## Validation

- WatchOS Simulator test suite: 86 tests in 36 suites passed after the launcher
  conversion.
- Widget extension target builds for the watchOS Simulator.
- Physical-watch steps in Task 6 remain pending.
