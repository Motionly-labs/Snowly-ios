# Local Development

Run Snowly locally, pick the right target, and avoid the common backend and device-specific gotchas.

---

## Targets And Schemes

| Target | Scheme | Notes |
|---|---|---|
| `Snowly` | `Snowly` | Main iOS app plus widget extension embedding |
| `Snowly Watch App` | `Snowly Watch App` | watchOS app for companion and independent sessions |
| `SnowlyTests` | `Snowly` | Swift Testing unit and integration coverage |
| `SnowlyUITests` | `Snowly` | XCTest UI smoke tests |

---

## Requirements

- Xcode 26+
- iOS 26.2+ simulator or device
- watchOS 26.2+ device or supported simulator if you are touching watch features
- No external package install step

To inspect installed destinations:

```bash
xcodebuild -project Snowly.xcodeproj -scheme Snowly -showdestinations
```

---

## First Run

1. Open `Snowly.xcodeproj` in Xcode.
2. Select the `Snowly` scheme.
3. Choose an installed iOS simulator such as `iPhone 17 Pro`.
4. Build and run.

If you only need UI, history, or design-system work, the simulator is enough.

---

## Simulator vs Device

| Area | Simulator | Real device |
|---|---|---|
| Onboarding, settings, history, gear, design work | Good | Good |
| Fixture replay (`-replay_recap`) | Good | Good |
| GPX replay (`-replay_gpx`) | Good | Good |
| CloudKit sync | Disabled | Supported |
| HealthKit authorization and workout persistence | Not available | Supported |
| Apple Music playback controls | Not available | Supported |
| Background location behavior | Partial | Required for real validation |
| Local notifications | Limited confidence | Required for real validation |
| Watch connectivity and independent workout import | Not available | Required |

CloudKit is intentionally turned off on simulators and during tests. `SnowlyApp` falls back to local-only persistence in those cases.

---

## Backend Defaults And Server Management

Snowly has two server-backed flows in the iOS app:

- Crew state and pin sync via `CrewAPIClient`
- Session upload via `SkiDataAPIClient`

Default base URLs:

- `DEBUG`: `http://localhost:4000/api/v1`
- `RELEASE`: `https://api.snowly.app/api/v1`

Server profiles:

- Stored locally in `ServerProfile`
- Managed from `Settings -> Server Management`
- The first visit to that screen seeds a default production profile if one does not exist yet
- The active persisted server is restored on app launch and applied to both network clients

If you switch the active server and want to validate ski-data upload against that new backend, relaunch before testing upload so the persisted active profile is re-applied everywhere.

For self-hosted servers, Snowly expects a health endpoint at:

```text
<server-base-url>/api/v1/health
```

If you are working on offline-only features, no backend is required.

---

## Replay Tools

### Fixture Replay

Replay a known JSON fixture through the production pipeline at launch:

```text
-replay_recap zermatt_loop
```

This path exercises Kalman filtering, activity detection, dwell time, segmentation, validation, and persistence.

### GPX Replay

Replay a GPX file as a synthetic live tracking session:

```text
-replay_gpx ZermattLoop
-replay_speed 4
```

Notes:

- GPX filenames come from `Snowly/Debug/Locations/`
- The name is case-sensitive
- `-replay_speed` is optional and scales playback speed

---

## Useful Commands

```bash
# Build
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Unit + integration tests
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# UI tests only
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SnowlyUITests test
```

Replace the simulator name if needed.

---

## Common Gotchas

- No backend profile exists on a fresh install until `Server Management` has been opened at least once.
- `DEBUG` builds pointing at `localhost` are expected behavior, not a misconfiguration.
- `Snowly/Shared/` is compiled by iOS, watchOS, and widget targets; do not add platform-specific imports there.
- HealthKit, CloudKit, Apple Music, notifications, and watch import need real-device validation before merge.
- GPX replay names are case-sensitive because they map directly to bundled filenames.
