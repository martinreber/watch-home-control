# Product Overview

**WatchHomeControl** is a standalone native watchOS app (Apple Watch Ultra 2)
that controls the home-control backend directly from the wrist: roller blinds
(Storen), Hue/Zigbee2MQTT lamps, and Sonos speakers. It is the companion client
to the `home-control` Go backend running on the Raspberry Pi.

## What It Does

- **Storen (blinds)**: raise ("Hoch") / lower ("Runter") via `POST /blind`.
- **Lampen (lamps)**: list lamps and toggle power via `GET /lamps` and
  `POST /lamps/{id}/state`, with optimistic UI and revert-on-failure.
- **Sonos (speakers)**: list speakers and play/pause/radio via
  `GET /sonos/speakers` and the `POST /sonos/speakers/{id}/{play|pause|radio}`
  endpoints; offline speakers are disabled.
- **Live status**: polls lamps + speakers every 5s while the control screen is
  active, preserving in-flight (pending) rows.

## Pairing & Auth

- The app authenticates with the backend via an `X-API-Key` header on every
  request except `GET /health` and `POST /pairing/redeem`.
- First-run onboarding uses a short-lived **6-digit pairing code**, not manual
  API-key entry. The owner mints a code on the backend
  (`POST /pairing/codes`, authenticated); the watch redeems it
  (`POST /pairing/redeem`, public) to receive the long-lived API key, which is
  stored only in the Keychain.
- On HTTP 401 the app routes back to the Einrichtung (Setup) screen for
  re-pairing without deleting the stored key.

## Key Conventions

- **UI language is German** (e.g. "Storen", "Lampen", "Sonos", "Hoch",
  "Runter", "Einrichtung", "Kopplungscode").
- **Times are shown in Europe/Zurich**, 24-hour `HH:MM`, with `--:--` for
  absent values.
- **The API key never leaves the Keychain** — never persisted to UserDefaults
  and never logged.
- The default Base_URL is `http://192.168.1.122:8080` (the Pi on the LAN);
  cleartext LAN HTTP is allowed via an ATS local-networking exception.
- The Pairing_Code is entered through an in-app **number pad**, not the system
  keyboard (watchOS cannot force a `TextField` to numeric-only input).

## Relationship to home-control

- The backend contract (endpoints, auth, pairing) lives in the `home-control`
  repo. This app is a pure client: it adds no server behavior.
- The app icon is derived from the home-control web UI icon
  (`home-control/web/icon-512.png`).
