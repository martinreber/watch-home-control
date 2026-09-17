# Technology Stack

## Platform & Toolchain

- **App type**: standalone native watchOS app (no iPhone companion target)
- **Target device**: Apple Watch Ultra 2 (physical), watchOS deployment target **11.0**
- **Language**: Swift **6.0**, SwiftUI, `@Observable`, Swift Concurrency (async/await)
- **IDE / build**: **Xcode 27** (`xcodebuild`, `devicectl`)
- **Networking**: `URLSession` (no third-party runtime dependencies)
- **Persistence**: Keychain (API key) + UserDefaults (Base_URL)
- **Testing**: unit + example + property-based tests in `WatchHomeControlTests`

## Project Identity

| Item | Value |
|------|-------|
| Xcode project | `WatchHomeControl.xcodeproj` |
| Scheme / target | `WatchHomeControl Watch App` |
| Bundle ID | `ch.reber.watchhomecontrol.watchkitapp` |
| Development team | `5V4FMXSU55` (Automatic signing) |
| Keychain service | `ch.reber.watchhomecontrol` (account `api_key`) |
| Default Base_URL | `http://192.168.1.122:8080` |

## Backend Contract (home-control)

`X-API-Key` on every request except `GET /health` and `POST /pairing/redeem`.

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /health` | none | reachability check |
| `POST /pairing/codes` | API key | mint a 6-digit code (run on your Mac) |
| `POST /pairing/redeem` | none | exchange a code for the API key |
| `POST /blind` | API key | `{ "action": "up"｜"down" }` |
| `GET /lamps` | API key | list lamps |
| `POST /lamps/{id}/state` | API key | `{ "power": true｜false }` |
| `GET /sonos/speakers` | API key | list speakers |
| `POST /sonos/speakers/{id}/{play｜pause｜radio}` | API key | speaker control |

## Constraints

- watchOS `TextField` ignores `.keyboardType`/`.textContentType` — a numeric-only
  keyboard cannot be requested. The Pairing_Code uses an in-app number pad
  (`CodePad` in `SetupView.swift`).
- watchOS app icons must be a flat PNG with **no alpha**; the system applies the
  circular mask. The icon is `Assets.xcassets/AppIcon.appiconset/AppIcon.png`
  (1024x1024, opaque).
- Cleartext LAN HTTP requires the ATS `NSAllowsLocalNetworking` exception in
  `Info.plist`.

---

## Terminal Workflow: build / deploy / delete / re-deploy

There is no `release.sh` here — deployment is done directly with Xcode's CLI
tools (`xcodebuild` + `devicectl`). Everything below runs from the repo root
(`watch-home-control/`) on the Mac. The Watch must be **paired to the Mac in
Device Hub** and reachable (unlocked, on wrist, same network / Bluetooth on).

### 0. Find the paired Watch (get its UDID)

```bash
xcrun devicectl list devices
```

Look for the physical Apple Watch Ultra 2 with state `connected`. Copy its
UDID. As of this writing the device is:

- **Name**: `mr-wa-u225`
- **UDID**: `00008310-0008F86A3699A01E`

Re-check the UDID if the Watch is re-paired or replaced — it can change.

### 1. Build for the physical Watch

Builds and code-signs the `.app` into a dedicated derived-data folder so the
artifact path is predictable. `clean` guarantees a fresh asset catalog (needed
after an icon change).

```bash
xcodebuild \
  -project "WatchHomeControl.xcodeproj" \
  -scheme "WatchHomeControl Watch App" \
  -destination "id=00008310-0008F86A3699A01E" \
  -derivedDataPath build/cli-device \
  clean build
```

Expect `** BUILD SUCCEEDED **`. The signed app lands at:

```
build/cli-device/Build/Products/Debug-watchos/WatchHomeControl Watch App.app
```

### 2. Install (deploy) to the Watch

```bash
xcrun devicectl device install app \
  --device 00008310-0008F86A3699A01E \
  "build/cli-device/Build/Products/Debug-watchos/WatchHomeControl Watch App.app"
```

Expect `App installed:` with `bundleID: ch.reber.watchhomecontrol.watchkitapp`.
Installing over an existing app is fine for code changes.

### 3. Launch (optional)

```bash
xcrun devicectl device process launch \
  --device 00008310-0008F86A3699A01E \
  ch.reber.watchhomecontrol.watchkitapp
```

### 4. Delete (uninstall) from the Watch

Use this when the gesture-based delete on the Watch is impractical, or to force
a clean icon/state refresh. **Uninstalling also clears the Keychain**, so the
next launch starts at the Einrichtung (pairing) screen.

```bash
xcrun devicectl device uninstall app \
  --device 00008310-0008F86A3699A01E \
  ch.reber.watchhomecontrol.watchkitapp
```

Expect `App uninstalled.`

### 5. Re-deploy (clean reinstall)

Required after an **app-icon change**, because watchOS caches the old icon on an
install-over. Full sequence:

```bash
# a) remove the stale app (and its cached icon + Keychain key)
xcrun devicectl device uninstall app \
  --device 00008310-0008F86A3699A01E \
  ch.reber.watchhomecontrol.watchkitapp

# b) clean build
xcodebuild \
  -project "WatchHomeControl.xcodeproj" \
  -scheme "WatchHomeControl Watch App" \
  -destination "id=00008310-0008F86A3699A01E" \
  -derivedDataPath build/cli-device \
  clean build

# c) install fresh
xcrun devicectl device install app \
  --device 00008310-0008F86A3699A01E \
  "build/cli-device/Build/Products/Debug-watchos/WatchHomeControl Watch App.app"
```

If the icon still looks stale after a clean reinstall, **restart the Watch
once** — the icon cache sometimes only flushes on reboot.

### After a fresh install: re-pair

Because uninstall wiped the Keychain, mint a new pairing code on the backend
(run on the Mac; replace `YOUR_API_KEY` with the backend key from
`home-control/secrets.yml`):

```bash
curl -sS -X POST http://192.168.1.122:8080/pairing/codes \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" | jq
```

Enter the returned 6-digit `code` on the Watch's Einrichtung screen (number
pad). Codes are short-lived and single-use.

---

## App Icon: regenerate from the home-control UI icon

The app icon is derived from `home-control/web/icon-512.png` (the canonical PWA
icon). watchOS icons must be opaque (no alpha) and 1024x1024. Regenerate with
Python + Pillow, flattening onto opaque white and upscaling:

```bash
python3 - <<'PY'
from PIL import Image
src = "/Users/martin/git/raspberry/home-control/web/icon-512.png"
dst = "/Users/martin/git/raspberry/watch-home-control/WatchHomeControl Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img = Image.open(src).convert("RGBA")
bg = Image.new("RGBA", img.size, (255, 255, 255, 255))   # web background_color is #ffffff
flat = Image.alpha_composite(bg, img).convert("RGB")     # drop alpha (watchOS requirement)
flat.resize((1024, 1024), Image.LANCZOS).save(dst, "PNG")
print("wrote", dst)
PY
```

The appiconset `Contents.json` references this single universal watchOS entry:

```json
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "watchos", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Then do a **clean re-deploy** (section 5) so the new icon is picked up.

### Verify the icon compiled into the bundle

```bash
APP="build/cli-device/Build/Products/Debug-watchos/WatchHomeControl Watch App.app"
xcrun --sdk watchos assetutil --info "$APP/Assets.car" | grep -iE "AssetType|RenditionName|PixelWidth"
/usr/libexec/PlistBuddy -c "Print :CFBundleIcons" "$APP/Info.plist"
```

Expect an `Icon Image` rendition named `AppIcon.png` at 1024 px and
`CFBundleIconName = AppIcon`.

---

## Testing

Run from the repo root against a watchOS Simulator (unit/property tests need no
device). Pick an available simulator name from `xcrun devicectl list devices`
or Xcode's destination list.

```bash
# All tests on a simulator
xcodebuild test \
  -project "WatchHomeControl.xcodeproj" \
  -scheme "WatchHomeControl Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)"

# Compile-only sanity check (generic simulator, no device signing)
xcodebuild \
  -project "WatchHomeControl.xcodeproj" \
  -scheme "WatchHomeControl Watch App" \
  -destination "generic/platform=watchOS Simulator" \
  build
```

Property tests run a minimum of 100 iterations each and cover request building,
DTO decoding, the speaker command mapper, URL validation, time formatting,
Keychain round-trip, optimistic apply/revert, poll merge, and the pairing-code
redeem flow (see the spec's design/tasks).

## Notes

- `build/` is local output only — keep it out of version control.
- Xcode `Run` (Cmd+R) does build + install + launch + debugger attach in one
  step; the CLI flow above is the equivalent for scripted/terminal use and for
  when the on-Watch delete gesture is impractical.
