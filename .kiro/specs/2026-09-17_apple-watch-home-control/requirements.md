# Requirements Document

## Introduction

This feature adds a standalone native Apple Watch app (targeting Apple Watch Ultra 2 on current watchOS) for the existing `home-control` Go application. The app replicates the interactive functionality of the "Home" tab (the `home-dashboard` web component) — controlling blinds (Storen), lamps (Lampen), and Sonos speakers — but excludes the Aare river data panel.

The Watch App is built with Apple-native tooling only (SwiftUI, URLSession, Keychain, Swift concurrency). It runs standalone with no iPhone companion app, and makes direct HTTP calls over the LAN to the Go backend. All configuration (server address, pairing) is performed on the watch. Rather than typing the Backend's 64-character API key on the watch, the user enters a short-lived 6-digit Pairing_Code — minted by the owner via the Backend's authenticated POST /pairing/codes endpoint — and the Watch_App redeems it against the public POST /pairing/redeem endpoint to obtain the real API_Key. From then on, authentication uses a static X-API-Key HTTP header, stored securely in the watchOS Keychain. The user interface is in German, and displayed times use the Europe/Zurich timezone.

This is a personal-use app for a sole developer and is not intended for App Store distribution. Complications, external/VPN access, and an iPhone relay are explicitly out of scope for v1.

## Glossary

- **Watch_App**: The standalone native watchOS application defined by this specification.
- **Backend**: The existing `home-control` Go application exposing the REST API.
- **Base_URL**: The configurable server address the Watch_App targets (default `http://192.168.1.122:8080`).
- **API_Key**: The static credential sent in the `X-API-Key` HTTP header on all authenticated requests.
- **Keychain**: The watchOS secure credential store used to persist the API_Key.
- **Blind**: A roller blind (German: "Storen") controlled via the `/blind` endpoint.
- **Lamp**: A controllable light (German: "Lampe") with fields `id`, `friendly_name`, `type` (ceiling/floor/strip/desk), and `state.power` (boolean).
- **Speaker**: A Sonos speaker with fields `id` (RINCON_...), `name`, `state` (`playing`/`paused`/`stopped`), `online` (boolean), and `model_name`.
- **Default_Radio**: The fallback radio station "Radio Bern 1" with URI `x-rincon-mp3radio://stream.streambase.ch/radiobern1/mp3-192/direct/`, played when a Speaker in the `stopped` state is turned on.
- **Pending_State**: A per-control UI state indicating that a command is in flight; the corresponding control is disabled during this state.
- **Poll_Cycle**: A periodic refresh of Lamp and Speaker state while a view is active.
- **Auth_Error**: The condition raised when the Backend returns HTTP 401 for an authenticated request, indicating an invalid or expired API_Key.
- **Setup_Screen**: The Watch_App screen where the user enters the Base_URL and a Pairing_Code to pair the Watch_App with the Backend.
- **Pairing_Code**: A short-lived credential of exactly 6 decimal digits, minted by the owner on the Backend, that the Watch_App exchanges once for the API_Key. It is valid for 5 minutes and single-use.
- **Redeem_Endpoint**: The Backend's public (unauthenticated) endpoint POST /pairing/redeem, which exchanges a valid Pairing_Code for the API_Key.
- **Pairing_Error**: The condition raised when a Pairing_Code redemption is rejected by the Backend (HTTP 400 malformed, HTTP 401 invalid/expired/consumed, or HTTP 429 too many attempts).

## Requirements

### Requirement 1: Initial Setup and Pairing

**User Story:** As the owner, I want to configure the server address and pair the watch with a short code, so that the Watch_App obtains its credential without typing the long API key.

#### Acceptance Criteria

1. WHEN the Watch_App launches AND no API_Key is stored in the Keychain, THE Watch_App SHALL display the Setup_Screen.
2. THE Setup_Screen SHALL provide a Base_URL input pre-filled with the default value `http://192.168.1.122:8080`.
3. THE Setup_Screen SHALL provide a Pairing_Code input that accepts exactly 6 decimal digits.
4. WHEN the user submits a Pairing_Code of exactly 6 decimal digits on the Setup_Screen, THE Watch_App SHALL attempt to redeem it via the Redeem_Endpoint (see Requirement 12).
5. IF the user submits a Pairing_Code that is not exactly 6 decimal digits, THEN THE Watch_App SHALL reject the submission, leave any stored API_Key unchanged, and display a German error message indicating the code must consist of 6 digits.
6. WHEN the user submits a non-empty Base_URL on the Setup_Screen, THE Watch_App SHALL persist the Base_URL for use on subsequent launches.
7. WHERE the user has not entered a Base_URL, THE Watch_App SHALL use the default value `http://192.168.1.122:8080`.
8. IF the user submits a Base_URL that is not a syntactically valid http URL, THEN THE Watch_App SHALL reject the submission and display a German error message indicating the address is invalid.
9. WHEN the Watch_App launches AND an API_Key is present in the Keychain, THE Watch_App SHALL proceed to the main control screen without displaying the Setup_Screen.
10. WHEN the user activates the configuration affordance on the main control screen, THE Watch_App SHALL present the Setup_Screen pre-filled with the current Base_URL so the user can change the Base_URL and pair again with a new Pairing_Code.

### Requirement 2: Authentication and Credential Handling

**User Story:** As the owner, I want the API key stored securely and authentication errors handled clearly, so that my credential is protected and I can recover from an invalid key.

#### Acceptance Criteria

1. WHEN the Watch_App issues an authenticated request to the Backend, THE Watch_App SHALL include the header `X-API-Key` set to the stored API_Key.
2. THE Watch_App SHALL store the API_Key in the Keychain and SHALL NOT persist the API_Key in any non-Keychain application storage.
3. IF the Backend returns HTTP 401 for an authenticated request, THEN THE Watch_App SHALL raise an Auth_Error, retain the current view state without modifying the stored API_Key, and display a German error message indicating the credential is invalid.
4. WHEN an Auth_Error is raised, THE Watch_App SHALL present the Setup_Screen so the user can pair again with a new Pairing_Code.
5. WHEN the user successfully redeems a new Pairing_Code after an Auth_Error, THE Watch_App SHALL replace the stored API_Key in the Keychain with the API_Key returned by the Redeem_Endpoint.

### Requirement 3: Connection Health Check

**User Story:** As the owner, I want the Watch_App to verify it can reach the Backend, so that I know whether the configured address is correct before controlling devices.

#### Acceptance Criteria

1. WHEN the Watch_App launches AND a Base_URL is configured, THE Watch_App SHALL send a request to `GET /health` without the `X-API-Key` header to verify Backend reachability.
2. WHEN a `GET /health` request returns HTTP 200, THE Watch_App SHALL treat the Backend as reachable.
3. IF a `GET /health` request does not complete within 5 seconds, THEN THE Watch_App SHALL abort the request and display a German message indicating the Backend is not reachable.
4. IF a `GET /health` request returns a non-200 status or fails due to a network error, THEN THE Watch_App SHALL display a German message indicating the Backend is not reachable.

### Requirement 4: Blind Control (Storen)

**User Story:** As the owner, I want to raise and lower the blinds from my watch, so that I can control them without opening the web app.

#### Acceptance Criteria

1. THE Watch_App SHALL display a "Storen" section containing a "Hoch" control and a "Runter" control.
2. WHEN the user activates the "Hoch" control, THE Watch_App SHALL send `POST /blind` with request body `{"action":"up"}` and `Content-Type: application/json`.
3. WHEN the user activates the "Runter" control, THE Watch_App SHALL send `POST /blind` with request body `{"action":"down"}` and `Content-Type: application/json`.
4. WHILE a blind command is in flight, THE Watch_App SHALL set the Pending_State for the blind controls and disable both the "Hoch" and "Runter" controls.
5. WHEN a blind command returns a success response, THE Watch_App SHALL clear the Pending_State, re-enable both controls, and display German success feedback.
6. IF a blind command returns an error response, THEN THE Watch_App SHALL clear the Pending_State, re-enable both controls, and display German error feedback.
7. IF a blind command does not complete within 10 seconds, THEN THE Watch_App SHALL abort the request, clear the Pending_State, re-enable both controls, and display German error feedback indicating the request timed out.

### Requirement 5: Lamp Listing (Lampen)

**User Story:** As the owner, I want to see my lamps and their on/off state on the watch, so that I know their current status.

#### Acceptance Criteria

1. WHEN the lamp view becomes active, THE Watch_App SHALL send `GET /lamps` to retrieve the Lamp list.
2. WHERE the `GET /lamps` response is an object with a `lamps` array, THE Watch_App SHALL use the `lamps` array as the Lamp list.
3. WHERE the `GET /lamps` response is a top-level array, THE Watch_App SHALL use that array as the Lamp list.
4. THE Watch_App SHALL display each Lamp with its `friendly_name` and an on/off toggle reflecting `state.power`.
5. IF a Lamp's `friendly_name` is absent, THEN THE Watch_App SHALL display that Lamp using its `id` as the label.
6. IF the Lamp list contains zero Lamps, THEN THE Watch_App SHALL display the German message "Keine Lampen gefunden".
7. IF the `GET /lamps` request does not complete within 10 seconds or returns an error response, THEN THE Watch_App SHALL retain the current displayed Lamp list and present a non-blocking indication that the refresh failed.

### Requirement 6: Lamp Control

**User Story:** As the owner, I want to toggle each lamp on or off from my watch, so that I can control my lighting.

#### Acceptance Criteria

1. WHEN the user toggles a Lamp on, THE Watch_App SHALL send `POST /lamps/{id}/state` with request body `{"power": true}` and `Content-Type: application/json`.
2. WHEN the user toggles a Lamp off, THE Watch_App SHALL send `POST /lamps/{id}/state` with request body `{"power": false}` and `Content-Type: application/json`.
3. WHILE a Lamp command is in flight, THE Watch_App SHALL set the Pending_State for that Lamp and disable that Lamp's toggle.
4. WHEN a Lamp command returns a response containing an updated `lamp` object within 5 seconds of dispatch, THE Watch_App SHALL update that Lamp's displayed state from the returned `lamp.state`, re-enable that Lamp's toggle, and clear the Pending_State.
5. IF a Lamp command returns an error response, THEN THE Watch_App SHALL revert that Lamp's toggle to its prior state, re-enable that Lamp's toggle, clear the Pending_State, and display a German error message indicating the toggle failed.
6. IF a Lamp command does not return a response within 5 seconds of dispatch, THEN THE Watch_App SHALL abort the request, revert that Lamp's toggle to its prior state, re-enable that Lamp's toggle, clear the Pending_State, and display a German error message indicating the request timed out.

### Requirement 7: Speaker Listing (Sonos)

**User Story:** As the owner, I want to see my Sonos speakers and their playback state on the watch, so that I know which speakers are playing and available.

#### Acceptance Criteria

1. WHEN the speaker view becomes active, THE Watch_App SHALL send `GET /sonos/speakers` to retrieve the Speaker list.
2. IF the `GET /sonos/speakers` request does not complete within 10 seconds, THEN THE Watch_App SHALL abort the request and retain the current displayed Speaker list.
3. IF the `GET /sonos/speakers` request returns an error response or fails due to a network error, THEN THE Watch_App SHALL retain the current displayed Speaker list and present a non-blocking indication that the refresh failed.
4. THE Watch_App SHALL display each Speaker in the order returned by the Backend, showing its `name` and a play/pause toggle.
5. THE Watch_App SHALL render a Speaker's toggle in the on position WHEN that Speaker's `state` equals `playing`.
6. THE Watch_App SHALL render a Speaker's toggle in the off position WHEN that Speaker's `state` does not equal `playing`.
7. WHILE a Speaker has `online` equal to `false`, THE Watch_App SHALL disable that Speaker's toggle and prevent its activation.
8. IF the Speaker list contains zero Speakers, THEN THE Watch_App SHALL display the German message "Keine Lautsprecher gefunden".

### Requirement 8: Speaker Control

**User Story:** As the owner, I want to start and stop playback on each Sonos speaker from my watch, replicating the web app's default-radio behavior, so that speakers behave consistently across clients.

#### Acceptance Criteria

1. WHEN the user toggles a Speaker on AND that Speaker's `state` equals `stopped`, THE Watch_App SHALL send `POST /sonos/speakers/{id}/radio` with request body `{"uri":"x-rincon-mp3radio://stream.streambase.ch/radiobern1/mp3-192/direct/","metadata":"","name":"Radio Bern 1"}` and `Content-Type: application/json`.
2. WHEN the user toggles a Speaker on AND that Speaker's `state` does not equal `stopped`, THE Watch_App SHALL send `POST /sonos/speakers/{id}/play`.
3. WHEN the user toggles a Speaker off, THE Watch_App SHALL send `POST /sonos/speakers/{id}/pause`.
4. WHILE a Speaker command is in flight, THE Watch_App SHALL set the Pending_State for that Speaker and disable that Speaker's toggle.
5. WHEN a Speaker command returns a response containing an updated Speaker state, THE Watch_App SHALL update that Speaker's displayed state from the returned value, re-enable that Speaker's toggle, and clear the Pending_State.
6. IF a Speaker command returns an error response, does not complete within 10 seconds, or returns a success response without an updated state, THEN THE Watch_App SHALL revert that Speaker's toggle to its prior state, re-enable that Speaker's toggle, clear the Pending_State, and display a German error message indicating the speaker command failed.

### Requirement 9: Periodic State Refresh

**User Story:** As the owner, I want lamp and speaker state to stay current while I'm looking at the app, so that the displayed state reflects reality.

#### Acceptance Criteria

1. WHILE the control view is active, THE Watch_App SHALL perform a Poll_Cycle that retrieves Lamp and Speaker state every 5 seconds.
2. WHILE a Lamp is in the Pending_State, THE Watch_App SHALL preserve that Lamp's current displayed state during a Poll_Cycle instead of overwriting it with polled data.
3. WHILE a Speaker is in the Pending_State, THE Watch_App SHALL preserve that Speaker's current displayed state during a Poll_Cycle instead of overwriting it with polled data.
4. IF a Poll_Cycle request does not complete within 10 seconds, THEN THE Watch_App SHALL abort that request, retain the current displayed state, and retry on the next Poll_Cycle.
5. IF a Poll_Cycle request returns an error response, THEN THE Watch_App SHALL retain the current displayed state, present a non-blocking indication that the refresh failed, and retry on the next Poll_Cycle.
6. WHEN the control view becomes inactive, THE Watch_App SHALL stop the Poll_Cycle such that no further Poll_Cycle is initiated.

### Requirement 10: Localization and Formatting

**User Story:** As the owner, I want the watch interface in German with local time, so that it matches the existing web app.

#### Acceptance Criteria

1. THE Watch_App SHALL display all user-facing labels in German, including at minimum the labels "Storen", "Lampen", "Sonos", "Hoch", and "Runter".
2. WHERE the Watch_App displays a time-of-day or date value, THE Watch_App SHALL convert and render that value in the Europe/Zurich timezone, applying Central European Time (UTC+1) or Central European Summer Time (UTC+2) according to the date.
3. WHERE the Watch_App displays a time-of-day value, THE Watch_App SHALL format that value using the 24-hour clock with two-digit hours and two-digit minutes (HH:MM).
4. IF a time or date value required for display is absent or cannot be parsed into a valid instant, THEN THE Watch_App SHALL display a fixed placeholder in place of the value.

### Requirement 11: Network and Transport Configuration

**User Story:** As the owner, I want the app to talk to my LAN Backend over plain HTTP, so that it works on my local network without TLS.

#### Acceptance Criteria

1. WHEN the Watch_App issues any Backend request, THE Watch_App SHALL send that request to the configured Base_URL over the LAN.
2. THE Watch_App SHALL permit cleartext HTTP requests to the configured Base_URL.
3. WHEN the Watch_App issues a request that includes a JSON request body, THE Watch_App SHALL set the request header `Content-Type` to `application/json`.
4. IF a Backend request does not complete within 10 seconds of being issued, THEN THE Watch_App SHALL abort that request and present an error indication identifying the request as failed.
5. IF a Backend request fails due to a network or connection error, THEN THE Watch_App SHALL present an error indication identifying the request as failed and leave locally displayed state unchanged.

### Requirement 12: Pairing-Code Redemption

**User Story:** As the owner, I want the watch to exchange a 6-digit code for the real API key, so that I never type the long key on the watch.

#### Acceptance Criteria

1. WHEN the Watch_App redeems a Pairing_Code, THE Watch_App SHALL send `POST /pairing/redeem` with request body `{"code":"<code>"}` and `Content-Type: application/json`, and SHALL NOT include an `X-API-Key` header on that request.
2. WHEN the Redeem_Endpoint returns HTTP 200 with a body containing an `api_key` field, THE Watch_App SHALL store that `api_key` value in the Keychain as the API_Key and proceed to the connection health check.
3. IF the Redeem_Endpoint returns HTTP 400, THEN THE Watch_App SHALL raise a Pairing_Error, leave any stored API_Key unchanged, and display a German error message indicating the code must consist of 6 digits.
4. IF the Redeem_Endpoint returns HTTP 401, THEN THE Watch_App SHALL raise a Pairing_Error, leave any stored API_Key unchanged, and display a German error message indicating the code is invalid or expired.
5. IF the Redeem_Endpoint returns HTTP 429, THEN THE Watch_App SHALL raise a Pairing_Error, leave any stored API_Key unchanged, and display a German error message indicating too many attempts were made.
6. IF a redeem request does not complete within 10 seconds, THEN THE Watch_App SHALL abort the request, leave any stored API_Key unchanged, and display a German error message indicating the request timed out.
7. THE Watch_App SHALL NOT persist a submitted Pairing_Code in any storage and SHALL NOT store the returned API_Key anywhere other than the Keychain.
